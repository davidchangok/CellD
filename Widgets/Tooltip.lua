local _, Cell = ...
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-----------------------------------------
-- Tooltip 模块
-- 负责创建自定义 Tooltip 框架，并提供工具提示显示控制功能。
-- 包括两个 Tooltip 实例：CellTooltip（通用）和 CellSpellTooltip（带法术图标）。
-- 同时提供 F.ShowTooltips / F.ShowSpellTooltips 作为外部调用入口。
-----------------------------------------

-- 创建一个自定义 Tooltip 框架
-- @param name     string  框架的全局名称
-- @param hasIcon  boolean 是否在 Tooltip 左上角附带一个法术/物品图标
local function CreateTooltip(name, hasIcon)
    -- 基于 GameTooltip 类型创建框架，继承 CellTooltipTemplate 模板和 BackdropTemplate 以支持背景边框
    local tooltip = CreateFrame("GameTooltip", name, CellParent, "CellTooltipTemplate,BackdropTemplate")
    -- 设置背景图与边框：使用纯白纹理 + 1像素边框
    tooltip:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = 1})
    -- 背景色：深灰黑带 90% 不透明度
    tooltip:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    -- 边框色：使用 Cell 主题色（accent color）
    tooltip:SetBackdropBorderColor(Cell.GetAccentColorRGB())
    -- 设置 Owner 为 CellParent，但禁用自动锚点，由调用方自行定位
    tooltip:SetOwner(CellParent, "ANCHOR_NONE")

    -- 如果启用了图标，在 Tooltip 左上角创建图标背景和图标纹理
    if hasIcon then
        -- 图标背景：35x35 像素，位于 Tooltip 左上角外侧，用主题色填充
        local iconBG = tooltip:CreateTexture(nil, "BACKGROUND")
        tooltip.iconBG = iconBG
        iconBG:SetSize(35, 35)
        iconBG:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", -1, 0)
        iconBG:SetColorTexture(Cell.GetAccentColorRGB())
        iconBG:Hide()

        -- 图标纹理：置于图标背景之上，内缩 1 像素以露出边框
        local icon = tooltip:CreateTexture(nil, "ARTWORK")
        tooltip.icon = icon
        P.Point(icon, "TOPLEFT", iconBG, 1, -1)
        P.Point(icon, "BOTTOMRIGHT", iconBG, -1, 1)
        -- 裁剪纹理边缘 8%，去除图标自带的边框
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:Hide()

        -- 钩子：当通过 SetSpellByID 设置法术时，自动显示对应图标
        hooksecurefunc(tooltip, "SetSpellByID", function(self, id, tex)
            if tex then
                iconBG:Show()
                icon:SetTexture(tex)
                icon:Show()
            end
        end)
    end

    -- 正式服特有：注册 TOOLTIP_DATA_UPDATE 事件以支持 Tooltip 数据动态刷新
    -- 参考 Interface\FrameXML\GameTooltip.lua line924
    if Cell.isRetail then
        tooltip:RegisterEvent("TOOLTIP_DATA_UPDATE")
        tooltip:SetScript("OnEvent", function()
            tooltip:RefreshData()
        end)
    end

    -- OnTooltipCleared：当 Tooltip 内容被清空时，重置边框颜色为主题色
    tooltip:SetScript("OnTooltipCleared", function()
        -- reset border color
        tooltip:SetBackdropBorderColor(Cell.GetAccentColorRGB())
    end)

    -- （已注释）OnTooltipSetItem：当设置物品时，根据物品品质颜色来染色边框
    -- tooltip:SetScript("OnTooltipSetItem", function()
    --     -- color border with item quality color
    --     tooltip:SetBackdropBorderColor(_G[name.."TextLeft1"]:GetTextColor())
    -- end)

    -- OnHide：Tooltip 隐藏时清理所有行内容，并隐藏图标（避免残留显示）
    tooltip:SetScript("OnHide", function()
        -- SetX with invalid data may or may not clear the tooltip's contents.
        tooltip:ClearLines()

        if hasIcon then
            tooltip.iconBG:Hide()
            tooltip.icon:Hide()
        end
    end)

    -- UpdatePixelPerfect：当 UI 缩放变化时，重新计算像素完美边框宽度并刷新(通过 Closure 捕获 hasIcon)
    function tooltip:UpdatePixelPerfect()
        tooltip:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
        tooltip:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        tooltip:SetBackdropBorderColor(Cell.GetAccentColorRGB())
        if hasIcon then
            -- 重新锚定图标位置以适配新缩放
            P.Repoint(tooltip.icon)
            -- 刷新图标背景色（可能因主题色变化而更新）
            tooltip.iconBG:SetColorTexture(Cell.GetAccentColorRGB())
        end
    end
end

-- 实例化 Tooltip 框架
-- 通用 Tooltip（无图标）
CreateTooltip("CellTooltip")
-- 法术 Tooltip（带图标，通过 SetSpellByID 钩子自动显示法术图标）
CreateTooltip("CellSpellTooltip", true)
-- （已注释）扫描 Tooltip
-- CreateTooltip("CellScanningTooltip")

-- 显示法术提示信息（使用新版 Tooltip API）
-- @param tooltip  frame   目标 Tooltip 框架
-- @param spellID  number  法术 ID
function F.ShowSpellTooltips(tooltip, spellID)
    -- 构建 BaseTooltipInfo，通过 ProcessInfo 设置 Tooltip 内容
    local tooltipInfo = CreateBaseTooltipInfo("GetSpellByID", spellID)
    tooltip:ProcessInfo(tooltipInfo)
    tooltip:Show()
end

-- 核心工具提示显示函数
-- 根据配置决定锚点位置，并根据类型（unit / spell / aura）设置相应内容
-- @param anchor      frame   锚点框架（通常为 Cell 单位按钮）
-- @param tooltipType string  提示类型："unit"=单位 / "spell"=法术 / "aura"=光环
-- @param unit        string  单位 ID（如 "player", "target", "party1"）
-- @param aura        number  光环索引或 AuraInstanceID
-- @param filter      string  光环过滤："HARMFUL"=减益 / "HELPFUL"=增益
function F.ShowTooltips(anchor, tooltipType, unit, aura, filter)
    -- 检查提示功能是否启用；战斗中隐藏单位提示时跳过
    if not CellDB["general"]["enableTooltips"] or (tooltipType == "unit" and CellDB["general"]["hideTooltipsInCombat"] and InCombatLockdown()) then return end

    -- 根据用户配置的 tooltipsPosition 决定 GameTooltip 的锚点策略
    -- tooltipsPosition 格式: { 锚点, 目标, 相对锚点, x偏移, y偏移 }
    if CellDB["general"]["tooltipsPosition"][2] == "Default" then
        -- 默认：使用暴雪内置的默认锚点
        GameTooltip_SetDefaultAnchor(GameTooltip, anchor)
    elseif CellDB["general"]["tooltipsPosition"][2] == "Cell" then
        -- Cell：相对于 Cell 主框架定位
        GameTooltip:SetOwner(Cell.frames.mainFrame, "ANCHOR_NONE")
        GameTooltip:SetPoint(CellDB["general"]["tooltipsPosition"][1], Cell.frames.mainFrame, CellDB["general"]["tooltipsPosition"][3], CellDB["general"]["tooltipsPosition"][4], CellDB["general"]["tooltipsPosition"][5])
    elseif CellDB["general"]["tooltipsPosition"][2] == "Unit Button" then
        -- 单位按钮：相对于触发按钮定位
        GameTooltip:SetOwner(anchor, "ANCHOR_NONE")
        GameTooltip:SetPoint(CellDB["general"]["tooltipsPosition"][1], anchor, CellDB["general"]["tooltipsPosition"][3], CellDB["general"]["tooltipsPosition"][4], CellDB["general"]["tooltipsPosition"][5])
    elseif CellDB["general"]["tooltipsPosition"][2] == "Cursor" then
        -- 光标位置：跟随鼠标
        GameTooltip:SetOwner(anchor, "ANCHOR_CURSOR")
    elseif CellDB["general"]["tooltipsPosition"][2] == "Cursor Left" then
        -- 光标左侧：在鼠标左方偏移显示
        GameTooltip:SetOwner(anchor, "ANCHOR_CURSOR_LEFT", CellDB["general"]["tooltipsPosition"][4], CellDB["general"]["tooltipsPosition"][5])
    elseif CellDB["general"]["tooltipsPosition"][2] == "Cursor Right" then
        -- 光标右侧：在鼠标右方偏移显示
        GameTooltip:SetOwner(anchor, "ANCHOR_CURSOR_RIGHT", CellDB["general"]["tooltipsPosition"][4], CellDB["general"]["tooltipsPosition"][5])
    end

    -- 根据提示类型设置 Tooltip 内容
    if tooltipType == "unit" then
        -- 单位提示：显示单位信息（姓名、生命值等）
        GameTooltip:SetUnit(unit)
    elseif tooltipType == "spell" and unit and aura then
        -- 法术提示：通过单位光环索引显示法术详情
        -- GameTooltip:SetSpellByID(aura)
        GameTooltip:SetUnitAura(unit, aura, filter)
    elseif tooltipType == "aura" and unit and aura then
        -- 光环提示：通过 AuraInstanceID 精确显示光环信息
        if filter == "HARMFUL" then
            GameTooltip:SetUnitDebuffByAuraInstanceID(unit, aura)
        elseif filter == "HELPFUL" then
            GameTooltip:SetUnitBuffByAuraInstanceID(unit, aura)
        end
    end
end