local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
---@type PixelPerfectFuncs
local P = Cell.pixelPerfectFuncs

-- 战复计时器位置调整器（拖动锚点），在锁定模式下用于移动整个计时器控件
local battleResMover

-------------------------------------------------
-- battle res
-------------------------------------------------
-- 战复计时器主框架，挂载在 Cell 主框体上，用于显示战斗复活充能信息
local battleResFrame = CreateFrame("Frame", "CellBattleResFrame", Cell.frames.mainFrame, "BackdropTemplate")
Cell.frames.battleResFrame = battleResFrame
battleResFrame:SetFrameLevel(5)
P.Size(battleResFrame, 80, 20)
battleResFrame:Hide()
-- 应用 Cell 背景样式：半透明黑色背景 + 黑色边框
Cell.StylizeFrame(battleResFrame, {0.1, 0.1, 0.1, 0.7}, {0, 0, 0, 0.5})

--------------------------------------------------
-- 平滑移动动画：菜单展开/收起时战复计时器跟随平滑位移
--------------------------------------------------
-- 锚点、相对锚点、展开时Y偏移、收起时Y偏移（由 UpdatePosition 根据布局设定）
local point, relativePoint, onShow, onHide
-- 布局位置是否已初始化（仅在 UpdatePosition 首次执行后置为 true，防止动画在未就绪时执行）
local loaded = false

-- 菜单展开时的上移动画组（向上平移至 onShow 位置）
battleResFrame.onMenuShow = battleResFrame:CreateAnimationGroup()
battleResFrame.onMenuShow.trans = battleResFrame.onMenuShow:CreateAnimation("translation")
battleResFrame.onMenuShow.trans:SetDuration(0.3)
battleResFrame.onMenuShow.trans:SetSmoothing("OUT")
battleResFrame.onMenuShow:SetScript("OnPlay", function()
    -- 播放上移动画时停止下移动画，避免冲突
    battleResFrame.onMenuHide:Stop()
end)
battleResFrame.onMenuShow:SetScript("OnFinished", function()
    -- 动画结束后精确定位到目标位置（onShow），消除浮点误差
    battleResFrame:ClearAllPoints()
    battleResFrame:SetPoint(point, CellAnchorFrame, relativePoint, 0, onShow)
end)

-- 触发菜单展开动画：将战复计时器从当前Y位置平滑移动到 onShow 位置
function battleResFrame:OnMenuShow()
    if not loaded then return end

    -- 如果框架未显示，直接跳转到最终位置（跳过动画）
    if not battleResFrame:IsShown() then
        battleResFrame.onMenuShow:GetScript("OnFinished")()
        return
    end

    -- 获取当前Y坐标（select(5, ...) 取第五个返回值即Y偏移）
    local currentY = select(5, battleResFrame:GetPoint(1))
    if type(currentY) ~= "number" then return end
    currentY = math.floor(currentY+.5)

    -- 仅当当前位置与目标位置不同时才播放动画
    if onShow ~= currentY then
        local offset = onShow-currentY
        battleResFrame.onMenuShow.trans:SetOffset(0, offset)
        battleResFrame.onMenuShow:Play()
    end
end

-- 菜单收起时的下移动画组（向下平移至 onHide 位置）
battleResFrame.onMenuHide = battleResFrame:CreateAnimationGroup()
battleResFrame.onMenuHide.trans = battleResFrame.onMenuHide:CreateAnimation("translation")
battleResFrame.onMenuHide.trans:SetDuration(0.3)
battleResFrame.onMenuHide.trans:SetSmoothing("OUT")
battleResFrame.onMenuHide:SetScript("OnPlay", function()
    -- 播放下移动画时停止上移动画，避免冲突
    battleResFrame.onMenuShow:Stop()
end)
battleResFrame.onMenuHide:SetScript("OnFinished", function()
    -- 动画结束后精确定位到目标位置（onHide），消除浮点误差
    battleResFrame:ClearAllPoints()
    battleResFrame:SetPoint(point, CellAnchorFrame, relativePoint, 0, onHide)
end)

-- 触发菜单收起动画：将战复计时器从当前Y位置平滑移动到 onHide 位置
function battleResFrame:OnMenuHide()
    if not loaded then return end

    -- 如果框架未显示，直接跳转到最终位置（跳过动画）
    if not battleResFrame:IsShown() then
        battleResFrame.onMenuHide:GetScript("OnFinished")()
        return
    end

    -- 获取当前Y坐标（select(5, ...) 取第五个返回值即Y偏移）
    local currentY = select(5, battleResFrame:GetPoint(1))
    if type(currentY) ~= "number" then return end
    currentY = math.floor(currentY+.5)

    -- 仅当当前位置与目标位置不同时才播放动画
    if onHide ~= currentY then
        local offset = onHide-currentY
        battleResFrame.onMenuHide.trans:SetOffset(0, offset)
        battleResFrame.onMenuHide:Play()
    end
end

--------------------------------------------------
-- 进度条：显示战复冷却进度（从0到完整冷却时间 duration）
--------------------------------------------------
local bar = Cell.CreateStatusBar("CellBattleResBar", battleResFrame, 10, 4, 100, false, nil, false, "Interface\\AddOns\\Cell\\Media\\statusbar", Cell.GetAccentColorTable())
bar:SetPoint("BOTTOMLEFT")
bar:SetPoint("BOTTOMRIGHT")
-- P.Point(bar, "BOTTOMLEFT", battleResFrame, "BOTTOMLEFT", 1, 1)
-- P.Point(bar, "BOTTOMRIGHT", battleResFrame, "BOTTOMRIGHT", -1, 1)
-- bar:SetMinMaxValues(0, 100)
-- bar:SetValue(50)

--------------------------------------------------
-- 文字控件：标题、充能数、剩余时间
--------------------------------------------------
-- 标题文字："战复: "
local title = battleResFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
-- 充能数量文字（如"0"或"1"，带颜色标记）
local stack = battleResFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
-- 剩余冷却时间文字（格式 M:SS）
local rTime = battleResFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
-- 隐藏的占位文字，包含最宽可能文本，用于在 OnShow 时动态计算框架宽度
local dummy = battleResFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
dummy:Hide()

-- 统一字号 13，不加描边/阴影
title:SetFont(title:GetFont(), 13, "")
stack:SetFont(stack:GetFont(), 13, "")
rTime:SetFont(rTime:GetFont(), 13, "")
dummy:SetFont(dummy:GetFont(), 13, "")

-- 水平对齐：标题和充能数左对齐，剩余时间右对齐
title:SetJustifyH("LEFT")
stack:SetJustifyH("LEFT")
rTime:SetJustifyH("RIGHT")

-- 文字定位：title 位于进度条左上方；stack 紧接 title 右侧；rTime 紧接 stack 右侧
P.Point(title, "BOTTOMLEFT", bar, "TOPLEFT", 2, 1)
stack:SetPoint("LEFT", title, "RIGHT")
rTime:SetPoint("LEFT", stack, "RIGHT")
P.Point(dummy, "BOTTOMLEFT", bar, "TOPLEFT", 2, 1)
-- dummy:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 22)

title:SetTextColor(0.66, 0.66, 0.66)
rTime:SetTextColor(0.66, 0.66, 0.66)

title:SetText(L["BR"]..": ")
stack:SetText("")
rTime:SetText("")
-- dummy 预设最宽文本用于宽度计算（包含红色"0"和"00:00"的完整显示）
dummy:SetText(L["BR"]..": |cffff00000|r  00:00 ")

-- OnShow 事件：根据 dummy 计算出的最大文字宽度动态设置框架和 mover 的宽度
battleResFrame:SetScript("OnShow", function()
    battleResFrame.elapsed = 0.25
    battleResFrame:SetWidth(math.ceil(dummy:GetWidth()))
    battleResMover:SetWidth(math.ceil(dummy:GetWidth()))
end)

-- OnHide 事件：清空充能和剩余时间文字
battleResFrame:SetScript("OnHide", function()
    stack:SetText("")
    rTime:SetText("")
end)

--------------------------------------------------
-- 每帧更新逻辑：刷新战复充能数量和剩余冷却时间
--------------------------------------------------
-- 缓存全局API引用以提高性能
local GetSpellCharges = C_Spell.GetSpellCharges

-- 获取战复技能（20484 = 复生/战斗复活）的充能信息
-- 返回：currentCharges（当前充能数）, cooldownStartTime（冷却开始时间）, cooldownDuration（冷却总时长）
local function GetBRInfo()
    local info = GetSpellCharges(20484)
    if info then
        return info.currentCharges, info.cooldownStartTime, info.cooldownDuration
    end
end

-- 每0.25秒更新一次（而非每帧），减少性能开销
battleResFrame.elapsed = 0.25
battleResFrame.onUpdate = function(self, elapsed)
    battleResFrame.elapsed = battleResFrame.elapsed + elapsed
    if battleResFrame.elapsed >= 0.25 then
        battleResFrame.elapsed = 0

        -- 进入Boss战后所有战复技能冷却重置，初始1层充能
        -- 充能以每(90/团队人数)分钟1层的速率恢复
        local charges, started, duration = GetBRInfo()
        if not charges then
            -- 不在Boss战内（charges为nil表示无可用充能信息），隐藏计时器并监听充能更新
            battleResFrame:Hide()
            battleResFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
            return
        end

        -- Midnight 12.0.0+：受限战斗中冷却数值可能为加密值，显示"?"代替
        if F.IsSecretValue and (F.IsSecretValue(charges) or F.IsSecretValue(duration) or F.IsSecretValue(started)) then
            stack:SetFormattedText("%s?|r  ", "|cff00ff00")
            rTime:SetText("?:??")
            if bar.maxVlue ~= 60 then bar:SetMinMaxValues(0, 60) end
            bar:SetValue(0)
            return
        end

        -- 充能数 > 0 显示绿色，= 0 显示红色
        local color = (charges > 0) and "|cff00ff00" or "|cffff0000"
        -- 计算剩余冷却时间：总时长 - 已过时间
        local remaining = duration - (GetTime() - started)
        local m = floor(remaining / 60)
        local s = mod(remaining, 60)

        -- 更新文字显示：充能数（带颜色）和剩余时间（M:SS格式）
        stack:SetFormattedText("%s%d|r  ", color, charges)
        rTime:SetFormattedText("%d:%02d", m, s)

        -- 仅在冷却总时长变化时更新进度条的最大值（避免每次都调用 SetMinMaxValues）
        if bar.maxVlue ~= duration then
            bar:SetMinMaxValues(0, duration)
            bar.maxVlue = duration
        end
        bar:SetValue(duration - remaining)
    end
end

battleResFrame:SetScript("OnUpdate", battleResFrame.onUpdate)

-- SPELL_UPDATE_CHARGES 事件处理：战复充能恢复时触发，重新显示计时器
function battleResFrame:SPELL_UPDATE_CHARGES()
    local charges = GetBRInfo()
    if charges then
        battleResFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
        battleResFrame:Show()
    end
end

-- PLAYER_ENTERING_WORLD 事件处理：进入游戏/重载界面时根据场景决定是否显示战复计时器
function battleResFrame:PLAYER_ENTERING_WORLD()
    battleResFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
    battleResFrame:Hide()

    local _, instanceType, difficulty = GetInstanceInfo()

    if instanceType == "raid" then -- 团队副本
        if IsEncounterInProgress() then -- 上线时/重载界面后已在Boss战中，直接显示
            battleResFrame:Show()
        else
            -- 未在战斗中则监听充能更新事件，等待Boss战触发后显示
            battleResFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        end

    elseif difficulty == 8 then -- 大秘境（史诗钥石地下城难度=8）
        battleResFrame:Show()
    end
end

-- CHALLENGE_MODE_START 事件处理：大秘境开始时显示战复计时器
function battleResFrame:CHALLENGE_MODE_START()
    battleResFrame:Show()
end

-- 统一事件分发：将事件名映射到对应的成员函数
battleResFrame:SetScript("OnEvent", function(self, event, ...)
    battleResFrame[event](self, ...)
end)

-------------------------------------------------
-- 拖动锚点控件：在锁定布局模式下用于自由调整战复计时器位置
-------------------------------------------------
-- 创建可拖动的半透明绿色锚点框架
battleResMover = CreateFrame("Frame", nil, Cell.frames.mainFrame, "BackdropTemplate")
P.Size(battleResMover, 80, 40)
Cell.StylizeFrame(battleResMover, {0, 1, 0, 0.4}, {0, 0, 0, 0})
battleResMover:SetClampedToScreen(true)
-- battleResMover:SetClampRectInsets(0, 0, -20, 0)
battleResMover:SetFrameLevel(1)
battleResMover:SetMovable(true)
battleResMover:EnableMouse(true)
battleResMover:RegisterForDrag("LeftButton")
battleResMover:Hide()

-- 左键拖动开始：开始移动并清除"用户放置"标记（避免系统自动保存位置）
battleResMover:SetScript("OnDragStart", function()
    battleResMover:StartMoving()
    battleResMover:SetUserPlaced(false)
end)

-- 左键拖动结束：停止移动并保存新位置到 CellDB
battleResMover:SetScript("OnDragStop", function()
    battleResMover:StopMovingOrSizing()
    P.SavePosition(battleResMover, CellDB["tools"]["battleResTimer"][3])
end)

-- 锚点上的文字标签，显示"Mover"提示
battleResMover.text = battleResMover:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
battleResMover.text:SetPoint("TOP", 0, -3)
battleResMover.text:SetText(L["Mover"])

-- 显示拖动锚点模式：显示mover，暂停OnUpdate更新，隐藏实际文字而显示dummy占位
local function MoverShow()
    battleResMover:Show()
    if not battleResFrame:IsShown() then
        battleResFrame:SetScript("OnUpdate", nil)
        battleResFrame:Show()
        dummy:Show()
        title:Hide()
        stack:Hide()
        rTime:Hide()
    end
end

-- 隐藏拖动锚点模式：隐藏mover，恢复OnUpdate更新和正常文字显示
local function MoverHide()
    battleResMover:Hide()
    dummy:Hide()
    title:Show()
    stack:Show()
    rTime:Show()
    battleResFrame:SetScript("OnUpdate", battleResFrame.onUpdate)
end

-- 切换锚点显示状态（由 Cell 全局"显示锚点"回调触发）
local function ShowMover(show)
    shouldShowMover = show

    if show then
        -- 仅当战复计时器功能已开启且处于锁定布局模式时才显示锚点
        if CellDB["tools"]["battleResTimer"][1] and CellDB["tools"]["battleResTimer"][2] then
            MoverShow()
        end
    else
        MoverHide()
    end
end
Cell.RegisterCallback("ShowMover", "BattleResTimer_ShowMover", ShowMover)

--------------------------------------------------
-- 位置计算：根据 Cell 主框架锚点和菜单位置决定战复计时器放置位置
--------------------------------------------------
local function UpdatePosition()
    -- 锁定布局模式下由 mover 控制位置，跳过自动定位
    if CellDB["tools"]["battleResTimer"][2] then return end
    loaded = true

    -- 读取当前布局的主框架锚点（BOTTOMLEFT/BOTTOMRIGHT/TOPLEFT/TOPRIGHT）
    local anchor = Cell.vars.currentLayoutTable["main"]["anchor"]
    battleResFrame:ClearAllPoints()

    -- 根据主框架锚点确定战复计时器的附着方向和展开/收起偏移量
    if anchor == "BOTTOMLEFT" then
        -- 主框架锚在左下 → 计时器放在其上方（左上对左下）
        point, relativePoint = "TOPLEFT", "BOTTOMLEFT"
        onShow, onHide = -4, 10

    elseif anchor == "BOTTOMRIGHT" then
        -- 主框架锚在右下 → 计时器放在其上方（右上对右下）
        point, relativePoint = "TOPRIGHT", "BOTTOMRIGHT"
        onShow, onHide = -4, 10

    elseif anchor == "TOPLEFT" then
        -- 主框架锚在左上 → 计时器放在其下方（左下对左上）
        point, relativePoint = "BOTTOMLEFT", "TOPLEFT"
        onShow, onHide = 4, -10

    elseif anchor == "TOPRIGHT" then
        -- 主框架锚在右上 → 计时器放在其下方（右下对右上）
        point, relativePoint = "BOTTOMRIGHT", "TOPRIGHT"
        onShow, onHide = 4, -10
    end

    -- 根据菜单方向（顶部/底部）和是否渐隐来决定初始Y位置
    if CellDB["general"]["menuPosition"] == "top_bottom" then
        if CellDB["general"]["fadeOut"] then
            -- 渐隐模式下初始放在收起位置
            battleResFrame:SetPoint(point, CellAnchorFrame, relativePoint, 0, onHide)
        else
            -- 非渐隐模式下初始放在展开位置
            battleResFrame:SetPoint(point, CellAnchorFrame, relativePoint, 0, onShow)
        end
    else
        -- 左右布局模式，参考 CellMainFrame 放置
        battleResFrame:SetPoint(point, CellMainFrame, relativePoint, 0, onShow)
    end
end

--------------------------------------------------
-- Cell 全局回调注册：响应设置变更、布局切换、像素完美更新
--------------------------------------------------
-- UpdateTools 回调：当工具设置变更时（启用/禁用战复计时器、切换锁定/解锁布局）
-- CellDB["tools"]["battleResTimer"] = { enabled, locked, positionTable }
local function UpdateTools(which)
    if not which or which == "battleResTimer" then
        if CellDB["tools"]["battleResTimer"][1] then
            -- 战复计时器已启用：注册相关事件
            battleResFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            battleResFrame:RegisterEvent("CHALLENGE_MODE_START")
            battleResFrame:RegisterEvent("SPELL_UPDATE_CHARGES")

            if CellDB["tools"]["battleResTimer"][2] then
                -- 锁定布局模式：显示 mover 锚点，将计时器附着到 mover 上
                if shouldShowMover then
                    MoverShow()
                end
                P.ClearPoints(battleResFrame)
                battleResFrame:SetPoint("BOTTOMLEFT", battleResMover)
                -- 尝试从保存数据加载 mover 位置，失败则使用默认位置
                if not P.LoadPosition(battleResMover, CellDB["tools"]["battleResTimer"][3]) then
                    PixelUtil.SetPoint(battleResMover, "TOPLEFT", CellParent, "CENTER", 1, -100)
                end
            else
                -- 非锁定模式：隐藏 mover，按布局自动定位
                MoverHide()
                UpdatePosition()
            end
        else
            -- 战复计时器已禁用：注销所有事件并隐藏
            battleResFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            battleResFrame:UnregisterEvent("CHALLENGE_MODE_START")
            battleResFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
            MoverHide()
        end
    end
end
Cell.RegisterCallback("UpdateTools", "BattleResTimer_UpdateTools", UpdateTools)

-- UpdateMenu 回调：菜单位置变更时重新计算计时器位置
local function UpdateMenu(which)
    if which == "position" then
        UpdatePosition()
    end
end
Cell.RegisterCallback("UpdateMenu", "BattleRes_UpdateMenu", UpdateMenu)

-- UpdateLayout 回调：布局切换或锚点变更时重新计算计时器位置
local function UpdateLayout(layout, which)
    if not which or which == "anchor" then
        UpdatePosition()
    end
end
Cell.RegisterCallback("UpdateLayout", "BattleRes_UpdateLayout", UpdateLayout)

-- UpdatePixelPerfect 回调：像素完美模式更新时重新缩放所有控件尺寸和位置
local function UpdatePixelPerfect()
    P.Resize(battleResFrame)
    P.Resize(battleResMover)
    Cell.StylizeFrame(battleResFrame, {0.1, 0.1, 0.1, 0.7}, {0, 0, 0, 0.5})
    bar:UpdatePixelPerfect()
    P.Repoint(title)
    P.Repoint(dummy)
end
Cell.RegisterCallback("UpdatePixelPerfect", "BattleRes_UpdatePixelPerfect", UpdatePixelPerfect)