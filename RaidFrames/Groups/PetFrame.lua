-- 从变长参数中解包获取 Cell 主模块（下划线为插件名占位符）
local _, Cell = ...
-- L: 本地化字符串表，用于多语言支持
local L = Cell.L
-- F: 通用工具函数库（Safe* 安全函数、表操作等）
local F = Cell.funcs
-- B: 按钮相关工具函数库（SetOrientation、SetPowerSize 等）
local B = Cell.bFuncs
-- A: 动画工具函数库（淡入淡出等）
local A = Cell.animations
-- P: 像素完美函数库（缩放、定位、尺寸计算，避免亚像素模糊）
local P = Cell.pixelPerfectFuncs

-- 模块级变量：存储锚点提示框的四个定位参数，由 UpdatePosition 动态计算
local tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY

-- 创建宠物框体主 Frame，挂载在 Cell 主框体下
-- SecureHandlerAttributeTemplate：安全模板，允许在受保护环境下执行 SetAttribute 操作
-- Midnight/SecretValue 防护：此 Frame 继承安全模板的属性驱动机制，通过 RegisterAttributeDriver 控制可见性，外部代码无法通过常规手段篡改其安全属性
local petFrame = CreateFrame("Frame", "CellPetFrame", Cell.frames.mainFrame, "SecureHandlerAttributeTemplate")
-- 将 petFrame 注册到 Cell 全局框体表中，供其他模块引用
Cell.frames.petFrame = petFrame

-------------------------------------------------
-- anchor — 可拖拽的锚点控件，用于控制宠物框体在屏幕上的位置
-- 同时也是菜单入口：鼠标悬停时显示提示信息和设置入口
-------------------------------------------------
-- 创建锚点 Frame，使用 BackdropTemplate 支持背景渲染
local anchorFrame = CreateFrame("Frame", "CellPetAnchorFrame", petFrame, "BackdropTemplate")
Cell.frames.petFrameAnchor = anchorFrame
-- 初始定位在屏幕中央，后续由 UpdatePosition 根据保存的布局数据重新定位
anchorFrame:SetPoint("TOPLEFT", CellParent, "CENTER")
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)
-- 调试用：红色半透明背景（已注释，正式环境不显示）
-- Cell.StylizeFrame(anchorFrame, {1, 0, 0, 0.4})

-- 悬停检测 Frame：比 anchorFrame 四周各扩大 1px，用于提升鼠标热区响应
local hoverFrame = CreateFrame("Frame", nil, petFrame)
hoverFrame:SetPoint("TOP", anchorFrame, 0, 1)
hoverFrame:SetPoint("BOTTOM", anchorFrame, 0, -1)
hoverFrame:SetPoint("LEFT", anchorFrame, -1, 0)
hoverFrame:SetPoint("RIGHT", anchorFrame, 1, 0)

-- 为锚点框体应用淡入淡出动画：鼠标进入时淡入显示，离开后淡出隐藏
A.ApplyFadeInOutToMenu(anchorFrame, hoverFrame)

-- dumb 按钮：覆盖在 anchorFrame 上的透明交互层，负责拖拽移动和悬停提示
-- 命名为 "dumb" 表示它不承载任何视觉元素，仅作为事件接收器
local dumb = Cell.CreateButton(anchorFrame, nil, "accent", {20, 10}, false, true)
dumb:Hide() -- 默认隐藏，由 UpdateAnchor 根据可见性状态决定是否显示
dumb:SetFrameStrata("MEDIUM")
dumb:SetAllPoints(anchorFrame)
-- 拖拽开始：通知锚点框体开始跟随鼠标移动
dumb:SetScript("OnDragStart", function()
    anchorFrame:StartMoving()
    anchorFrame:SetUserPlaced(false)
end)
-- 拖拽结束：停止移动，并将新位置通过 P.SavePosition 持久化到当前布局配置
dumb:SetScript("OnDragStop", function()
    anchorFrame:StopMovingOrSizing()
    P.SavePosition(anchorFrame, Cell.vars.currentLayoutTable["pet"]["position"])
end)
-- 鼠标进入：触发淡入动画，同时显示宠物框体位置提示
dumb:HookScript("OnEnter", function()
    hoverFrame:GetScript("OnEnter")(hoverFrame)
    CellTooltip:SetOwner(dumb, "ANCHOR_NONE")
    -- 提示框位置由 UpdatePosition 根据锚点方位动态计算
    CellTooltip:SetPoint(tooltipPoint, dumb, tooltipRelativePoint, tooltipX, tooltipY)
    CellTooltip:AddLine(L["Pets"])
    CellTooltip:Show()
end)
-- 鼠标离开：触发淡出动画，隐藏提示框
dumb:HookScript("OnLeave", function()
    hoverFrame:GetScript("OnLeave")(hoverFrame)
    CellTooltip:Hide()
end)

-- UpdateAnchor: 根据宠物框体的可见性状态，控制锚点控件的显示/隐藏和淡入淡出动画
-- 调用时机：第一个宠物按钮的 OnShow/OnHide 事件、UpdatePosition 中
local function UpdateAnchor()
    local show
    -- 判断是否应该显示锚点：团队启用宠物框体，或队伍启用且宠物框体为分离模式
    if Cell.vars.currentLayoutTable["pet"]["raidEnabled"]
    or (Cell.vars.currentLayoutTable["pet"]["partyEnabled"] and Cell.vars.currentLayoutTable["pet"]["partyDetached"]) then
        -- 以第一个宠物按钮的实际显示状态为准（该按钮可能因无宠物而隐藏）
        show = Cell.unitButtons.pet[1]:IsShown()
    end

    -- 根据 show 状态启用/禁用悬停框体的鼠标事件
    hoverFrame:EnableMouse(show)
    if show then
        dumb:Show()
        -- 处理淡出模式：如果用户开启了锚点淡出，根据鼠标是否悬停决定播放淡入还是保持淡出
        if CellDB["general"]["fadeOut"] then
            if hoverFrame:IsMouseOver() then
                anchorFrame.fadeIn:Play()
            else
                -- 直接调用淡出动画的 OnFinished 回调，使锚点立即进入完全淡出状态
                anchorFrame.fadeOut:GetScript("OnFinished")(anchorFrame.fadeOut)
            end
        end
    else
        dumb:Hide()
    end
end

-------------------------------------------------
-- header — 安全宠物组头部控件，使用 Blizzard 的 SecureGroupPetHeaderTemplate
-- 负责根据队伍/团队中的宠物数量自动创建和管理宠物按钮
-- Midnight/SecretValue 防护：此 header 使用 SecureGroupPetHeaderTemplate，
-- 其内部按钮的 unit 属性由安全模板自动分配，外部代码无法通过 SetAttribute 篡改 unit 映射
-------------------------------------------------
-- 创建安全宠物组头部，AllPoints 填充父框体 petFrame
local header = CreateFrame("Frame", "CellPetFrameHeader", petFrame, "SecureGroupPetHeaderTemplate")
header:SetAllPoints(petFrame)

-- initialConfigFunction: 每个由 header 创建的按钮初始化时执行的安全配置片段
-- 此属性在受保护环境下运行，防止外部插件篡改
header:SetAttribute("initialConfigFunction", [[
    --! button for pet/vehicle only, toggleForVehicle MUST be false
    -- 关键安全设置：宠物/载具按钮必须将 toggleForVehicle 设为 false
    -- 这确保按钮不会在宠物和载具之间切换，仅显示宠物
    self:SetAttribute("toggleForVehicle", false)

    -- RegisterUnitWatch(self)

    -- local header = self:GetParent()
    -- self:SetWidth(header:GetAttribute("buttonWidth") or 66)
    -- self:SetHeight(header:GetAttribute("buttonHeight") or 46)
]])

-- UpdateButtonUnit: 当 header 中某个按钮的 unit 属性发生变化时被调用（通过 refreshUnitChange 机制触发）
-- 将 unit -> buttonName 的映射关系存储到 Cell.unitButtons.pet.units 表中
-- 同时标记该按钮为宠物组成员（isGroupPet = true）
function header:UpdateButtonUnit(bName, unit)
    if not unit then return end
    -- 建立 unit 到按钮名的反向索引，供其他模块（如高亮、点击施法）查找按钮
    Cell.unitButtons.pet.units[unit] = _G[bName]
    _G[bName].isGroupPet = true
end

-- _initialAttributeNames: 声明需要在按钮初始化时设置的安全属性列表
-- refreshUnitChange: 订阅按钮 unit 变化事件，当 header 重新分配 unit 时自动回调 UpdateButtonUnit
header:SetAttribute("_initialAttributeNames", "refreshUnitChange")
header:SetAttribute("_initialAttribute-refreshUnitChange", [[
    self:GetParent():CallMethod("UpdateButtonUnit", self:GetName(), self:GetAttribute("unit"))
]])

-- 按钮模板：使用 Cell 自定义的 UnitButton 模板
header:SetAttribute("template", "CellUnitButtonTemplate")
-- 按钮在列内的排列方向：从 TOP 向 BOTTOM
header:SetAttribute("point", "TOP")
-- 列与列之间的锚点方向：列从左到右排列
header:SetAttribute("columnAnchorPoint", "LEFT")
-- 每列 5 个按钮（5 个宠物位）
header:SetAttribute("unitsPerColumn", 5)
header:SetAttribute("showPlayer", true) -- show player pet while not in a raid
-- 显示玩家宠物（不在团队中时也显示）

if Cell.isRetail then
    header:SetAttribute("maxColumns", 4)
    --! make needButtons == 20
    -- startingIndex = -19 配合 maxColumns=4，使按钮总数达到 20（(4-(-19)+1)*1 = 24? 实际由 Blizzard 安全模板内部计算）
    header:SetAttribute("startingIndex", -19)
else
    header:SetAttribute("maxColumns", 5)
    --! make needButtons == 25
    -- 经典版：5 列布局，共 25 个按钮位
    header:SetAttribute("startingIndex", -24)
end
header:Show()
header:SetAttribute("startingIndex", 1)

-- 遍历 header 的所有子按钮，将它们注册到 Cell.unitButtons.pet 索引表中
-- Cell.unitButtons.pet 是一个混合表：数字索引存按钮引用，units 子表存 unit->button 映射
for i, b in ipairs(header) do
    Cell.unitButtons.pet[i] = b
    -- b.type = "pet" -- layout setup
end

-- update mover: 监听第一个宠物按钮的显示/隐藏事件，联动更新锚点控件的可见性
-- Midnight/SecretValue 防护点：OnShow/OnHide 通过 HookScript 挂载，不覆盖原始脚本，保证安全模板的原始事件处理不被破坏
header[1]:HookScript("OnShow", function()
    UpdateAnchor()
end)
header[1]:HookScript("OnHide", function()
    UpdateAnchor()
end)

-------------------------------------------------
-- functions — 宠物框体的核心控制函数
-------------------------------------------------

-- UpdatePosition: 根据当前布局配置重新计算宠物框体相对于锚点的位置
-- 处理两种菜单布局模式（上下排列 / 左右排列）和四种锚点方位（BOTTOMLEFT/BOTTOMRIGHT/TOPLEFT/TOPRIGHT）
-- 同时计算对应方位的提示框显示位置，存入模块级变量供 OnEnter 使用
local function UpdatePosition()
    -- 清除所有现有锚点，准备重新设置
    petFrame:ClearAllPoints()
    -- NOTE: detach from spotlightPreviewAnchor
    -- 从保存的布局数据中加载锚点位置（像素完美）
    P.LoadPosition(anchorFrame, Cell.vars.currentLayoutTable["pet"]["position"])

    -- 确定锚点方位：如果宠物框体与主框体使用相同排列，则复用主框体的锚点设置
    local anchor
    if Cell.vars.currentLayoutTable["pet"]["sameArrangementAsMain"] then
        anchor = Cell.vars.currentLayoutTable["main"]["anchor"]
    else
        anchor = Cell.vars.currentLayoutTable["pet"]["anchor"]
    end

    -- 菜单位置模式一：上下排列（锚点框体为 20x10 的横条）
    if CellDB["general"]["menuPosition"] == "top_bottom" then
        P.Size(anchorFrame, 20, 10)
        if anchor == "BOTTOMLEFT" then
            -- 宠物框体在锚点上方
            petFrame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPLEFT", "BOTTOMLEFT", 0, -3
        elseif anchor == "BOTTOMRIGHT" then
            petFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPRIGHT", "BOTTOMRIGHT", 0, -3
        elseif anchor == "TOPLEFT" then
            -- 宠物框体在锚点下方
            petFrame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMLEFT", "TOPLEFT", 0, 3
        elseif anchor == "TOPRIGHT" then
            petFrame:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMRIGHT", "TOPRIGHT", 0, 3
        end
    else
        -- 菜单位置模式二：左右排列（锚点框体为 10x20 的竖条）
        P.Size(anchorFrame, 10, 20)
        if anchor == "BOTTOMLEFT" then
            -- 宠物框体在锚点右侧
            petFrame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMRIGHT", 4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMRIGHT", "BOTTOMLEFT", -3, 0
        elseif anchor == "BOTTOMRIGHT" then
            -- 宠物框体在锚点左侧
            petFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMLEFT", -4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMLEFT", "BOTTOMRIGHT", 3, 0
        elseif anchor == "TOPLEFT" then
            petFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPRIGHT", "TOPLEFT", -3, 0
        elseif anchor == "TOPRIGHT" then
            petFrame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPLEFT", "TOPRIGHT", 3, 0
        end
    end

    -- 位置更新后重新检查锚点可见性
    UpdateAnchor()
end

-- UpdateMenu: 响应全局菜单设置变化的回调函数
-- 由 Cell.RegisterCallback 注册到 "UpdateMenu" 事件，当用户修改通用设置时触发
-- @param which: 指示变化的设置项（"lock" 锁定状态 / "fadeOut" 淡出 / "position" 菜单位置 / nil 全部刷新）
local function UpdateMenu(which)
    -- 处理锁定状态变化：锁定时不可拖拽（RegisterForDrag 无参数），解锁时允许左键拖拽
    if not which or which == "lock" then
        if CellDB["general"]["locked"] then
            dumb:RegisterForDrag()
        else
            dumb:RegisterForDrag("LeftButton")
        end
    end

    -- 处理淡出设置变化：根据用户选择播放淡出或淡入动画
    if not which or which == "fadeOut" then
        if CellDB["general"]["fadeOut"] then
            anchorFrame.fadeOut:Play()
        else
            anchorFrame.fadeIn:Play()
        end
    end

    -- 处理菜单位置变化：重新计算宠物框体与锚点的相对位置
    if which == "position" then
        UpdatePosition()
    end
end
-- 将 UpdateMenu 注册为 "UpdateMenu" 事件的回调，标识符为 "PetFrame_UpdateMenu"
Cell.RegisterCallback("UpdateMenu", "PetFrame_UpdateMenu", UpdateMenu)

-- PetFrame_UpdateLayout: 响应布局设置变化的核心回调函数
-- 由 Cell.RegisterCallback 注册到 "UpdateLayout" 事件
-- 负责同步宠物框体的所有布局属性：可见性、尺寸、能量条、排列方向、宠物显示规则
-- @param layout: 当前布局名称（字符串）
-- @param which: 指示变化的布局子项（"size" 尺寸 / "power" 能量条 / "barOrientation" 条方向 / "arrangement" 排列 / "pet" 宠物可见性 / nil 全部刷新）
-- Midnight/SecretValue 防护：通过 RegisterAttributeDriver 控制可见性，header 的 SetAttribute 调用均在安全模板框架内执行
local function PetFrame_UpdateLayout(layout, which)
    -- visibility — 可见性控制
    -- 单人模式或全局隐藏时：注销属性驱动，直接隐藏宠物框体
    if Cell.vars.groupType == "solo" or Cell.vars.isHidden then
        UnregisterAttributeDriver(petFrame, "state-visibility")
        petFrame:Hide()
        return
    end
    -- 注册安全属性驱动：当 raid1 或 party1 存在时显示宠物框体，否则隐藏
    -- Midnight/SecretValue 防护点：属性驱动字符串在受保护环境下评估，防止外部代码伪造 raid1/party1 存在状态
    RegisterAttributeDriver(petFrame, "state-visibility", "[@raid1,exists] show;[@party1,exists] show;hide")

    -- update — 从 CellDB 中获取当前布局的完整配置表
    layout = CellDB["layouts"][layout]

    -- 处理尺寸、能量条、条方向相关变化
    if not which or strfind(which, "size$") or strfind(which, "power$") or which == "barOrientation" then
        local width, height, powerSize

        -- 尺寸来源：如果宠物框体与主框体使用相同尺寸，则复用主框体设置
        if layout["pet"]["sameSizeAsMain"] then
            width, height = unpack(layout["main"]["size"])
            powerSize = layout["main"]["powerSize"]
        else
            width, height = unpack(layout["pet"]["size"])
            powerSize = layout["pet"]["powerSize"]
        end

        -- 设置宠物框体本身尺寸（像素完美）
        P.Size(petFrame, width, height)

        -- header:SetAttribute("buttonWidth", P.Scale(width))
        -- header:SetAttribute("buttonHeight", P.Scale(height))

        -- 遍历所有宠物按钮，逐一应用尺寸和能量条设置
        for i, b in ipairs(header) do
            if not which or strfind(which, "size$") then
                P.Size(b, width, height)
            end

            -- NOTE: SetOrientation BEFORE SetPowerSize
            -- 重要：必须先设置条方向再设置能量条尺寸，因为 SetPowerSize 依赖于当前的 orientation
            if not which or which == "barOrientation" then
                B.SetOrientation(b, layout["barOrientation"][1], layout["barOrientation"][2])
            end

            if not which or strfind(which, "power$") or which == "barOrientation" or which == "powerFilter" then
                B.SetPowerSize(b, powerSize)
            end
        end
    end

    -- 处理排列相关变化（方向、锚点、间距）
    if not which or strfind(which, "arrangement$") then
        local orientation, anchor, spacingX, spacingY
        -- 排列来源：如果宠物框体与主框体使用相同排列，则复用主框体设置
        if layout["pet"]["sameArrangementAsMain"] then
            orientation = layout["main"]["orientation"]
            anchor = layout["main"]["anchor"]
            spacingX = layout["main"]["spacingX"]
            spacingY = layout["main"]["spacingY"]
        else
            orientation = layout["pet"]["orientation"]
            anchor = layout["pet"]["anchor"]
            spacingX = layout["pet"]["spacingX"]
            spacingY = layout["pet"]["spacingY"]
        end

        -- 根据排列方向和锚点方位计算 header 的各项安全属性
        local point, anchorPoint, unitSpacing, headerPoint, headerColumnAnchorPoint
        if orientation == "vertical" then
            -- 垂直排列：按钮从上到下（或从下到上）堆叠，列从左到右排列
            -- anchor
            if anchor == "BOTTOMLEFT" then
                point, anchorPoint = "BOTTOMLEFT", "TOPLEFT"
                headerPoint, headerColumnAnchorPoint = "BOTTOM", "LEFT"
                unitSpacing = spacingY
            elseif anchor == "BOTTOMRIGHT" then
                point, anchorPoint = "BOTTOMRIGHT", "TOPRIGHT"
                headerPoint, headerColumnAnchorPoint = "BOTTOM", "RIGHT"
                unitSpacing = spacingY
            elseif anchor == "TOPLEFT" then
                point, anchorPoint = "TOPLEFT", "BOTTOMLEFT"
                headerPoint, headerColumnAnchorPoint = "TOP", "LEFT"
                unitSpacing = -spacingY
            elseif anchor == "TOPRIGHT" then
                point, anchorPoint = "TOPRIGHT", "BOTTOMRIGHT"
                headerPoint, headerColumnAnchorPoint = "TOP", "RIGHT"
                unitSpacing = -spacingY
            end

            -- 垂直模式：列间距使用 spacingX，行偏移使用 spacingY
            header:SetAttribute("columnSpacing", P.Scale(spacingX))
            header:SetAttribute("xOffset", 0)
            header:SetAttribute("yOffset", P.Scale(unitSpacing))
        else
            -- 水平排列：按钮从左到右（或从右到左）排列，行从上到下堆叠
            -- anchor
            if anchor == "BOTTOMLEFT" then
                point, anchorPoint = "BOTTOMLEFT", "BOTTOMRIGHT"
                headerPoint, headerColumnAnchorPoint = "LEFT", "BOTTOM"
                unitSpacing = spacingX
            elseif anchor == "BOTTOMRIGHT" then
                point, anchorPoint = "BOTTOMRIGHT", "BOTTOMLEFT"
                headerPoint, headerColumnAnchorPoint = "RIGHT", "BOTTOM"
                unitSpacing = -spacingX
            elseif anchor == "TOPLEFT" then
                point, anchorPoint = "TOPLEFT", "TOPRIGHT"
                headerPoint, headerColumnAnchorPoint = "LEFT", "TOP"
                unitSpacing = spacingX
            elseif anchor == "TOPRIGHT" then
                point, anchorPoint = "TOPRIGHT", "TOPLEFT"
                headerPoint, headerColumnAnchorPoint = "RIGHT", "TOP"
                unitSpacing = -spacingX
            end

            -- 水平模式：行间距使用 spacingY，列偏移使用 spacingX
            header:SetAttribute("columnSpacing", P.Scale(spacingY))
            header:SetAttribute("xOffset", P.Scale(unitSpacing))
            header:SetAttribute("yOffset", 0)
        end

        -- header:ClearAllPoints()
        -- header:SetPoint(point)
        -- 将排列方向和列锚点写入 header 的安全属性
        header:SetAttribute("point", headerPoint)
        header:SetAttribute("columnAnchorPoint", headerColumnAnchorPoint)

        --! force update unitbutton's point
        -- 强制刷新所有按钮的锚点：清除后由安全模板根据新属性重新分配位置
        for i, b in ipairs(header) do
            b:ClearAllPoints()
        end
        header:SetAttribute("unitsPerColumn", 5)
        header:SetAttribute("maxColumns", 8)
    end

    -- 排列变化后需要更新锚点位置
    if not which or strfind(which, "arrangement$") then
        UpdatePosition()
    end

    -- 处理宠物可见性规则
    if not which or which == "pet" then
        -- 队伍模式（或竞技场）且启用了队伍宠物分离显示
        if (Cell.vars.groupType == "party" or Cell.vars.inBattleground == 5) and layout["pet"]["partyEnabled"] and layout["pet"]["partyDetached"] then
            if Cell.vars.inBattleground == 5 then -- arena
                -- 竞技场模式：使用 raid 通道显示（竞技场队伍在 Blizzard API 中被视为 raid）
                header:SetAttribute("showParty", false)
                header:SetAttribute("showRaid", true)
            else
                -- 普通队伍模式：使用 party 通道显示
                header:SetAttribute("showParty", true)
                header:SetAttribute("showRaid", false)
            end
            petFrame:Show()
        elseif Cell.vars.groupType == "raid" and layout["pet"]["raidEnabled"] and Cell.vars.inBattleground ~= 5 then
            -- 团队模式且启用了团队宠物显示（排除竞技场，因为竞技场已在上面处理）
            header:SetAttribute("showParty", false)
            header:SetAttribute("showRaid", true)
            petFrame:Show()
        else
            -- 其他情况（宠物未启用或不满足显示条件）：隐藏所有宠物
            header:SetAttribute("showParty", false)
            header:SetAttribute("showRaid", false)
            petFrame:Hide()
        end
    end
end
Cell.RegisterCallback("UpdateLayout", "PetFrame_UpdateLayout", PetFrame_UpdateLayout)