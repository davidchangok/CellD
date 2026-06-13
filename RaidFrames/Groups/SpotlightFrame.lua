-- 模块导入：Cell 是主对象，L 是本地化表，F 是安全函数集合（Midnight/SecretValue 防护），B 是条状布局函数，A 是动画函数，P 是像素完美函数
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs  -- 安全函数封装，所有敏感运算必须通过 F.Safe* 进行，防止 Midnight/SecretValue 泄漏
local B = Cell.bFuncs
local A = Cell.animations
local P = Cell.pixelPerfectFuncs

local LCG = LibStub("LibCustomGlow-1.0")

-- 数据结构：placeholders 存储占位符框架，assignmentButtons 存储分配按钮
local placeholders, assignmentButtons = {}, {}
-- 菜单项引用：menu（分配菜单）、target（目标）、targettarget（目标的目标）、focus（焦点）、focustarget（焦点目标）、unit（单位）、unitname（单位名称）、unitpet（单位宠物）、unittarget（单位目标）、tank（坦克）、boss1target（Boss1目标）、clear（清除）
local menu, target, targettarget, focus, focustarget, unit, unitname, unitpet, unittarget, tank, boss1target, clear
-- 索引表：tanks 记录哪些槽位被分配为坦克，healers 记录治疗分配，names 记录按名称匹配的分配（key=名称, value=槽位索引）
local tanks, healers, names = {}, {}, {}
-- 更新函数引用：用于延迟/条件更新坦克、治疗、名称分配
local UpdateTanks, UpdateHealers, UpdateNames
-- 延迟更新标志：当战斗锁定中无法立即更新时，设为 true 以在解锁后重试
local tankUpdateRequired, nameUpdateRequired
-- 提示框定位参数：根据锚点方向动态计算
local tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY
local NONE = strlower(_G.NONE)  -- 全局 NONE 常量的小写形式，用于显示空单位
-------------------------------------------------
-- spotlightFrame
-- 聚光灯框架：主要的独立监控框架，跟踪指定目标
-------------------------------------------------
-- 使用 SecureFrameTemplate 创建安全框架，防止在战斗中被篡改点击行为
local spotlightFrame = CreateFrame("Frame", "CellSpotlightFrame", Cell.frames.mainFrame, "SecureFrameTemplate")
Cell.frames.spotlightFrame = spotlightFrame

-- 锚点框架：用于拖拽定位聚光灯框架的整个模块，独立于主框架锚点
local anchorFrame = CreateFrame("Frame", "CellSpotlightAnchorFrame", spotlightFrame)
Cell.frames.spotlightFrameAnchor = anchorFrame
PixelUtil.SetPoint(anchorFrame, "TOPLEFT", CellParent, "CENTER", 1, -1)
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)

-- 悬停高亮框架：鼠标悬停在锚点上时触发渐入动画
local hoverFrame = CreateFrame("Frame", nil, spotlightFrame, "BackdropTemplate")
hoverFrame:SetPoint("TOP", anchorFrame, 0, 1)
hoverFrame:SetPoint("BOTTOM", anchorFrame, 0, -1)
hoverFrame:SetPoint("LEFT", anchorFrame, -1, 0)
hoverFrame:SetPoint("RIGHT", anchorFrame, 1, 0)
-- Cell.StylizeFrame(hoverFrame, {1,0,0,0.3}, {0,0,0,0})

-- 应用渐入渐出动画到锚点和悬停框架
A.ApplyFadeInOutToMenu(anchorFrame, hoverFrame)

-- 配置按钮：覆盖在锚点框架上，处理左键点击（展开菜单）、右键点击、拖拽事件
-- 使用 SecureHandlerAttributeTemplate 和 SecureHandlerClickTemplate 确保安全代码执行
local config = Cell.CreateButton(anchorFrame, nil, "accent", {20, 10}, false, true, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
config:SetFrameStrata("MEDIUM")
config:SetAllPoints(anchorFrame)
config:RegisterForDrag("LeftButton")
-- OnDragStart：开始拖拽锚点框架，重置用户放置标记
config:SetScript("OnDragStart", function()
    anchorFrame:StartMoving()
    anchorFrame:SetUserPlaced(false)
end)
-- OnDragStop：停止拖拽，保存新位置到布局配置
config:SetScript("OnDragStop", function()
    anchorFrame:StopMovingOrSizing()
    P.SavePosition(anchorFrame, Cell.vars.currentLayoutTable["spotlight"]["position"])
end)
-- _onclick 安全属性：点击配置按钮时，切换 15 个分配按钮的显示/隐藏状态，并隐藏菜单
config:SetAttribute("_onclick", [[
    for i = 1, 15 do
        local b = self:GetFrameRef("assignment"..i)
        if b:IsShown() then
            b:Hide()
        else
            b:Show()
        end
    end

    self:GetFrameRef("menu"):Hide()
]])
-- OnEnter 钩子：鼠标进入时显示操作提示
config:HookScript("OnEnter", function()
    hoverFrame:GetScript("OnEnter")(hoverFrame)
    CellTooltip:SetOwner(config, "ANCHOR_NONE")
    CellTooltip:SetPoint(tooltipPoint, config, tooltipRelativePoint, tooltipX, tooltipY)
    CellTooltip:AddLine(L["Spotlight Frame"])

    local tips = {
        {L["Left-Click"]..":", L["menu"]},
        {L["Right-Click"]..":", L["clear"]},
        {L["Left-Drag"]..":", L["set unit"].." ("..L["not in combat"]..")"},
        {"Shift+"..L["Left-Drag"]..":", L["set unit's name"].." ("..L["not in combat"]..")"},
        {L["Right-Drag"]..":", L["set unit's pet"].." ("..L["not in combat"]..")"},
    }
    for i = 1, 5 do
        CellTooltip:AddDoubleLine("|cffffb5c5"..tips[i][1], "|cffffffff"..tips[i][2])
    end
    CellTooltip:Show()
end)
-- OnLeave 钩子：鼠标离开时隐藏提示
config:HookScript("OnLeave", function()
    hoverFrame:GetScript("OnLeave")(hoverFrame)
    CellTooltip:Hide()
end)

-------------------------------------------------
-- target frame: drag and set
-- 拖拽目标指示框架：拖拽分配按钮时显示的浮动指示器
-------------------------------------------------
local targetFrame = Cell.CreateFrame(nil, spotlightFrame, 50, 20)
targetFrame.label = targetFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
targetFrame.label:SetPoint("CENTER")
targetFrame:EnableMouse(false)

-- StartMoving：开始拖拽时，显示指示框架并跟随鼠标位置更新
function targetFrame:StartMoving()
    targetFrame:Show()
    local scale = targetFrame:GetEffectiveScale()
    -- OnUpdate 回调：每帧更新指示器位置以跟随鼠标
    targetFrame:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        targetFrame:SetPoint("BOTTOMLEFT", CellParent, x/scale, y/scale)
        targetFrame:SetWidth(targetFrame.label:GetWidth() + 10)
    end)
end

-- StopMoving：停止拖拽时，隐藏指示框架并清除锚点
function targetFrame:StopMoving()
    targetFrame:Hide()
    targetFrame:ClearAllPoints()
end

-------------------------------------------------
-- assignment buttons
-- 分配按钮：15 个槽位的分配按钮，用于拖拽单位到聚光灯槽位
-------------------------------------------------
-- CreateAssignmentButton：创建一个分配按钮（index=1..15）
-- 每个按钮支持左键点击（显示菜单）、右键点击（清除）、左键拖拽（设置单位）、右键拖拽（设置宠物）
local function CreateAssignmentButton(index)
    local b = Cell.CreateButton(spotlightFrame, "|cffababab"..NONE, "accent-hover", {20, 20}, false, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
    b:GetFontString():SetNonSpaceWrap(true)
    b:GetFontString():SetWordWrap(true)
    b:SetToplevel(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetAttribute("index", index)
    b:Hide()

    -- _onclick 安全属性：处理左键和右键点击
    -- 左键：显示/隐藏分配菜单（定位到当前按钮旁边）
    -- 右键：清除当前槽位的单位分配
    b:SetAttribute("_onclick", [[
        local menu = self:GetFrameRef("menu")

        if button == "LeftButton" then --! show menu -- 左键：显示菜单
            if menu:IsShown() and menu:GetAttribute("index") == self:GetAttribute("index") then
                menu:Hide()
            else
                menu:ClearAllPoints()
                menu:SetPoint(menu:GetAttribute("point"), self, menu:GetAttribute("anchorPoint"), menu:GetAttribute("xOffset"), menu:GetAttribute("yOffset"))
                menu:Show()
            end
        end

        local index = self:GetAttribute("index")
        -- print(index)
        menu:SetAttribute("index", index)

        if button == "RightButton" then --! clear -- 右键：清除分配
            local spotlight = menu:GetFrameRef("spotlight"..index)
            -- 清除所有单位相关属性
            spotlight:SetAttribute("unit", nil)
            spotlight:SetAttribute("refreshOnUpdate", nil)
            spotlight:SetAttribute("updateOnTargetChanged", nil)
            menu:GetFrameRef("assignment"..index):SetAttribute("text", nil)
            menu:Hide()

            menu:CallMethod("Save", index, nil)
        end
    ]])

    -- OnAttributeChanged：当 "text" 属性变化时更新按钮显示文本和占位符文本
    -- 如果值为 nil（清空），则隐藏占位符；否则显示单位名称
    b:SetScript("OnAttributeChanged", function(self, name, value)
        if name ~= "text" then return end
        b:SetText(value and value or "|cffababab" .. NONE)
        placeholders[index].text:SetText(value and "|cffababab" .. value or "|cffababab" .. NONE)
        if not value then
            placeholders[index]:Hide()
        end
    end)

    --! drag and set -- 拖拽设置单位
    b:RegisterForDrag("LeftButton", "RightButton")
    -- OnDragStart：开始拖拽，战斗锁定中禁止操作（Midnight 防护点）
    b:SetScript("OnDragStart", function(self, button)
        -- Midnight/战斗锁定检查：战斗中禁止拖拽分配，防止安全框架冲突
        if InCombatLockdown() then return end

        menu:Hide()
        targetFrame:StartMoving()
        -- 拖拽时添加像素发光效果作为视觉反馈
        -- color, N, frequency, length, thickness
        LCG.PixelGlow_Start(b, Cell.GetAccentColorTable(), 9, 0.25, 8, 2)

        if button == "LeftButton" then
            if IsShiftKeyDown() then
                -- Shift+左键拖拽：按名称分配（用于跟踪特定玩家名）
                targetFrame.label:SetText(L["Unit's Name"])
                targetFrame.type = "name"
            else
                -- 左键拖拽：按 unitID 分配
                targetFrame.label:SetText(L["Unit"])
                targetFrame.type = "unit"
            end
        else
            -- 右键拖拽：分配单位的宠物
            targetFrame.label:SetText(L["Unit's Pet"])
            targetFrame.type = "pet"
        end
    end)

    -- OnDragStop：结束拖拽，确定目标单位并分配
    b:SetScript("OnDragStop", function()
        targetFrame:StopMoving()
        LCG.PixelGlow_Stop(b)

        -- Midnight/战斗锁定检查：战斗中禁止分配操作
        if InCombatLockdown() then return end

        -- 使用安全函数 F.GetMouseFocus() 获取鼠标下方的框架（SecretValue 防护）
        local f = F.GetMouseFocus()

        if f == WorldFrame then
            -- 如果鼠标在世界框架上，尝试通过 GUID 获取单位按钮（支持第三方框架）
            f = F.GetUnitButtonByGUID(UnitGUID("mouseover") or "")
        end

        if not f then return end -- cursor outside wow window -- 鼠标在 Wow 窗口外，取消操作

        local unitId
        -- 从 Cell 或其他框架获取单位 ID
        if f.states and f.states.displayedUnit then -- Cell -- Cell 框架：从 states.displayedUnit 获取
            unitId = f.states.displayedUnit
        elseif f.unit then -- 其他框架：直接读 unit 属性
            unitId = f.unit
        end

        if unitId then
            -- 根据拖拽类型调用对应的设置函数
            if targetFrame.type == "unit" then
                unit:SetUnit(b:GetAttribute("index"), unitId)
            elseif targetFrame.type == "name" then
                unitname:SetUnit(b:GetAttribute("index"), unitId)
            elseif targetFrame.type == "pet" then
                unitpet:SetUnit(b:GetAttribute("index"), unitId)
            end
        end
    end)

    return b
end

-------------------------------------------------
-- placeholders
-- 占位符：当单位按钮隐藏时显示的半透明占位符，提示槽位存在
-------------------------------------------------
local function CreatePlaceHolder(index)
    local placeholder = CreateFrame("Frame", "CellSpotlightFramePlaceholder"..index, spotlightFrame, "BackdropTemplate")
    placeholder:Hide()
    Cell.StylizeFrame(placeholder, {0, 0, 0, 0.27})

    -- 占位符上显示单位名称，方便识别已分配的槽位
    placeholder.text = placeholder:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    placeholder.text:SetPoint("LEFT")
    placeholder.text:SetPoint("RIGHT")
    placeholder.text:SetWordWrap(true)
    placeholder.text:SetNonSpaceWrap(true)

    return placeholder
end

-------------------------------------------------
-- unitbuttons
-- 单位按钮：15 个实际的单位框架，用于显示血条、施法、Buff 等信息
-------------------------------------------------
-- wrapFrame：用于包装安全脚本（WrapScript），确保在战斗中可以安全执行代码
local wrapFrame = CreateFrame("Frame", "CellSpotlightWrapFrame", nil, "SecureHandlerBaseTemplate")

for i = 1, 15 do
    -- placeholder -- 创建占位符
    placeholders[i] = CreatePlaceHolder(i)

    -- assignment button -- 创建分配按钮，覆盖在占位符上
    assignmentButtons[i] = CreateAssignmentButton(i)
    assignmentButtons[i]:SetAllPoints(placeholders[i])
    -- 使用安全引用将分配按钮注册到配置按钮中，供安全片段使用
    SecureHandlerSetFrameRef(config, "assignment"..i, assignmentButtons[i])

    -- unit button -- 创建实际的单位按钮框架
    local b = CreateFrame("Button", "CellSpotlightFrameUnitButton"..i, spotlightFrame, "CellUnitButtonTemplate")
    Cell.unitButtons.spotlight[i] = b
    -- b.type = "spotlight" -- layout setup
    -- b:SetAttribute("unit", "player")
    -- RegisterUnitWatch(b)
    b:SetAllPoints(placeholders[i])
    b.isSpotlight = true --! NOTE: prevent overwrite Cell.vars.guids and Cell.vars.names -- 标记为聚光灯单位按钮，防止覆盖全局 GUID 和名称映射表

    --! 天杀的 Secure Codes -- 安全代码（WoW 的安全模板限制）
    -- 将占位符注册为安全引用，供 WrapScript 片段使用
    SecureHandlerSetFrameRef(b, "placeholder", placeholders[i])
    -- WrapScript OnShow：单位按钮显示时隐藏占位符
    wrapFrame:WrapScript(b, "OnShow", [[
        self:GetFrameRef("placeholder"):Hide()
    ]])
    -- WrapScript OnHide：单位按钮隐藏时，如果有分配的单位则显示占位符（除非设置了 hidePlaceholder）
    wrapFrame:WrapScript(b, "OnHide", [[
        if (self:GetAttribute("unit") or self:GetAttribute("specialUnit")) and not self:GetAttribute("hidePlaceholder") then
            self:GetFrameRef("placeholder"):Show()
        end
    ]])
    -- WrapScript OnAttributeChanged：当 "unit" 属性变化时，根据是否有单位决定占位符的显示/隐藏
    wrapFrame:WrapScript(b, "OnAttributeChanged", [[
        if name ~= "unit" then return end
        if (self:GetAttribute("unit") or self:GetAttribute("specialUnit")) and not self:IsShown() and not self:GetAttribute("hidePlaceholder") then
            self:GetFrameRef("placeholder"):Show()
        else
            self:GetFrameRef("placeholder"):Hide()
        end
    ]])

    -- HookScript OnAttributeChanged：单位变化时更新 OmniCD 位置
    b:HookScript("OnAttributeChanged", function(self, name, value)
        if name ~= "unit" then return end

        self.unit = value
        F.UpdateOmniCDPosition("Cell-Spotlight")  -- 安全更新 OmniCD 冷却插件的位置
    end)
end

-------------------------------------------------
-- menu
-- 分配菜单：点击分配按钮时弹出的下拉菜单，提供目标、焦点、单位、坦克等分配选项
-------------------------------------------------
menu = CreateFrame("Frame", "CellSpotlightAssignmentMenu", spotlightFrame, "BackdropTemplate,SecureHandlerAttributeTemplate,SecureHandlerShowHideTemplate")
menu:SetFrameStrata("FULLSCREEN_DIALOG")
menu:SetToplevel(true)
menu:SetClampedToScreen(true)
menu:Hide()

--! assignmentBtn -> spotlightButton -- 建立安全引用关系：分配按钮引用菜单，菜单引用聚光灯单位按钮和分配按钮
for i = 1, 15 do
    -- assignmentBtn -> menu -- 每个分配按钮引用菜单
    SecureHandlerSetFrameRef(assignmentButtons[i], "menu", menu)
    -- menu -> spotlightButton -- 菜单引用聚光灯单位按钮（用于设置单位属性）
    SecureHandlerSetFrameRef(menu, "spotlight"..i, Cell.unitButtons.spotlight[i])
    -- menu -> assignmentBtn -- 菜单引用分配按钮（用于更新显示文本）
    SecureHandlerSetFrameRef(menu, "assignment"..i, assignmentButtons[i])
end

-- hide -- 配置按钮和菜单之间的相互引用
SecureHandlerSetFrameRef(menu, "config", config)
SecureHandlerSetFrameRef(config, "menu", menu)
-- menu:SetAttribute("_onhide", [[
--     for i = 1, 15 do
--         self:GetFrameRef("assignment"..i):Hide()
--     end
-- ]])

-- menu items -- 菜单项创建

-- target: "目标" -- 分配当前目标，使用 PLAYER_TARGET_CHANGED 事件自动更新（updateOnTargetChanged = true）
-- 这是性能最优的跟踪方式，因为有专门的事件通知
target = Cell.CreateButton(menu, L["Target"], "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(target, "TOPLEFT", menu, "TOPLEFT", 1, -1)
P.Point(target, "RIGHT", menu, "RIGHT", -1, 0)
target:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    spotlight:SetAttribute("unit", "target")
    spotlight:SetAttribute("specialUnit", nil)
    spotlight:SetAttribute("refreshOnUpdate", nil)
    spotlight:SetAttribute("updateOnTargetChanged", true)  -- 使用事件驱动更新，无需 OnUpdate 轮询
    menu:GetFrameRef("assignment"..index):SetAttribute("text", "target")
    menu:Hide()

    menu:CallMethod("Save", index, "target")
]])

-- NOTE: no EVENT for this kind of targets， use OnUpdate
-- 目标的目标：WoW 没有专门的事件通知 "targettarget" 变化，因此使用 OnUpdate 轮询（refreshOnUpdate = true）
targettarget = Cell.CreateButton(menu, L["Target of Target"], "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(targettarget, "TOPLEFT", target, "BOTTOMLEFT")
P.Point(targettarget, "TOPRIGHT", target, "BOTTOMRIGHT")
targettarget:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    spotlight:SetAttribute("unit", "targettarget")
    spotlight:SetAttribute("specialUnit", nil)
    spotlight:SetAttribute("refreshOnUpdate", true)  -- 无事件通知，必须用 OnUpdate 轮询
    spotlight:SetAttribute("updateOnTargetChanged", nil)
    menu:GetFrameRef("assignment"..index):SetAttribute("text", "targettarget")
    menu:Hide()

    menu:CallMethod("Save", index, "targettarget")
]])

-- focus: "焦点" -- 分配当前焦点，WoW 有 PLAYER_FOCUS_CHANGED 事件，但这里使用单位自身的机制跟踪
focus = Cell.CreateButton(menu, L["Focus"], "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(focus, "TOPLEFT", targettarget, "BOTTOMLEFT")
P.Point(focus, "TOPRIGHT", targettarget, "BOTTOMRIGHT")
focus:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    spotlight:SetAttribute("unit", "focus")
    spotlight:SetAttribute("specialUnit", nil)
    spotlight:SetAttribute("refreshOnUpdate", nil)
    spotlight:SetAttribute("updateOnTargetChanged", nil)
    menu:GetFrameRef("assignment"..index):SetAttribute("text", "focus")
    menu:Hide()

    menu:CallMethod("Save", index, "focus")
]])

-- focustarget: "焦点目标" -- 分配焦点目标，无事件通知，使用 OnUpdate 轮询
focustarget = Cell.CreateButton(menu, L["Focus Target"], "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(focustarget, "TOPLEFT", focus, "BOTTOMLEFT")
P.Point(focustarget, "TOPRIGHT", focus, "BOTTOMRIGHT")
focustarget:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    spotlight:SetAttribute("unit", "focustarget")
    spotlight:SetAttribute("specialUnit", nil)
    spotlight:SetAttribute("refreshOnUpdate", true)
    spotlight:SetAttribute("updateOnTargetChanged", nil)
    menu:GetFrameRef("assignment"..index):SetAttribute("text", "focustarget")
    menu:Hide()

    menu:CallMethod("Save", index, "focustarget")
]])

-- unit: "单位" -- 通过输入框指定任意 unitID 进行跟踪
unit = Cell.CreateButton(menu, L["Unit"], "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(unit, "TOPLEFT", focustarget, "BOTTOMLEFT")
P.Point(unit, "TOPRIGHT", focustarget, "BOTTOMRIGHT")
unit:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    spotlight:SetAttribute("specialUnit", nil)
    spotlight:SetAttribute("refreshOnUpdate", nil)
    spotlight:SetAttribute("updateOnTargetChanged", nil)
    self:CallMethod("SetUnit", index, "target")  -- 调用外部 Lua 函数（非安全代码），弹出输入框
    menu:Hide()
]])
-- SetUnit：外部 Lua 函数，弹出目标选择界面让用户输入 unitID
function unit:SetUnit(index, target)
    local unitId = F.GetTargetUnitID(target)  -- 安全函数：获取目标单位 ID
    if unitId then
        Cell.unitButtons.spotlight[index]:SetAttribute("unit", unitId)
        assignmentButtons[index]:SetText(unitId)
        menu:Save(index, unitId)
    else
        F.Print(L["Invalid unit."])  -- 安全打印
    end
end

-- unitname: "单位名称" -- 按玩家名称跟踪，会在队伍中查找匹配名称的单位
unitname = Cell.CreateButton(menu, L["Unit's Name"], "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(unitname, "TOPLEFT", unit, "BOTTOMLEFT")
P.Point(unitname, "TOPRIGHT", unit, "BOTTOMRIGHT")
unitname:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    spotlight:SetAttribute("specialUnit", nil)
    spotlight:SetAttribute("refreshOnUpdate", nil)
    spotlight:SetAttribute("updateOnTargetChanged", nil)
    self:CallMethod("SetUnit", index, "target")
    menu:Hide()
]])
-- SetUnit：按名称分配，使用安全函数获取单位名称，防止 SecretValue 泄漏
function unitname:SetUnit(index, target)
    local unitId = F.GetTargetUnitID(target)  -- 安全函数
    if unitId and (UnitIsPlayer(unitId) or UnitInPartyIsAI(unitId)) then
        local name = GetUnitName(unitId, true)  -- 获取带 realm 的完整名称，防止同名冲突
        Cell.unitButtons.spotlight[index]:SetAttribute("unit", unitId)
        assignmentButtons[index]:SetText(name)
        menu:Save(index, ":"..name)  -- 以 ":" 前缀保存，表示名称模式

        local previous = names[name]
        names[name] = index

        -- 如果该名称之前已分配给其他槽位，清除旧槽位（名称唯一性保证）
        if previous and previous ~= index then -- exists, remove previous
            Cell.unitButtons.spotlight[previous]:SetAttribute("unit", nil)
            assignmentButtons[previous]:SetText("|cffababab"..NONE)
            menu:Save(previous, nil)
        end
    else
        F.Print(L["Invalid unit."])
    end
end

-- unitpet: "单位宠物" -- 跟踪指定单位的宠物
unitpet = Cell.CreateButton(menu, L["Unit's Pet"], "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(unitpet, "TOPLEFT", unitname, "BOTTOMLEFT")
P.Point(unitpet, "TOPRIGHT", unitname, "BOTTOMRIGHT")
unitpet:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    spotlight:SetAttribute("specialUnit", nil)
    spotlight:SetAttribute("refreshOnUpdate", nil)
    spotlight:SetAttribute("updateOnTargetChanged", nil)
    self:CallMethod("SetUnit", index, "target")
    menu:Hide()
]])
-- SetUnit：使用安全函数获取目标宠物的 unitID
function unitpet:SetUnit(index, target)
    local unitId = F.GetTargetPetID(target)  -- 安全函数：获取目标宠物的单位 ID
    if unitId then
        Cell.unitButtons.spotlight[index]:SetAttribute("unit", unitId)
        assignmentButtons[index]:SetText(unitId)
        menu:Save(index, unitId)
    else
        F.Print(L["Invalid unit."])
    end
end

-- unittarget: "单位目标" -- 跟踪指定单位的目标，对玩家则是 "target"，其他单位则为 "unitIDtarget"
unittarget = Cell.CreateButton(menu, L["Unit's Target"], "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(unittarget, "TOPLEFT", unitpet, "BOTTOMLEFT")
P.Point(unittarget, "TOPRIGHT", unitpet, "BOTTOMRIGHT")
unittarget:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    self:CallMethod("SetUnit", index, "target")
    menu:Hide()
]])
-- SetUnit：根据目标类型选择不同的跟踪策略
function unittarget:SetUnit(index, target)
    local unitId = F.GetTargetUnitID(target)  -- 安全函数
    if unitId then
        if unitId == "player" then
            -- 玩家自身的目标：直接使用 "target"，有事件通知
            unitId = "target"
            Cell.unitButtons.spotlight[index]:SetAttribute("refreshOnUpdate", nil)
            Cell.unitButtons.spotlight[index]:SetAttribute("updateOnTargetChanged", true)
        else
            -- 其他单位的目标：拼接 "unitIDtarget"，无事件通知，使用 OnUpdate 轮询
            unitId = unitId.."target"
            -- NOTE: no EVENT for this kind of targets， use OnUpdate
            Cell.unitButtons.spotlight[index]:SetAttribute("refreshOnUpdate", true)
            Cell.unitButtons.spotlight[index]:SetAttribute("updateOnTargetChanged", nil)
        end
        Cell.unitButtons.spotlight[index]:SetAttribute("unit", unitId)
        Cell.unitButtons.spotlight[index]:SetAttribute("specialUnit", nil)
        assignmentButtons[index]:SetText(unitId)
        menu:Save(index, unitId)
    else
        F.Print(L["Invalid unit."])
    end
end

-- tank: "坦克" -- 按职责分配，自动在队伍中查找所有坦克并按槽位分配
tank = Cell.CreateButton(menu, _G.TANK, "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(tank, "TOPLEFT", unittarget, "BOTTOMLEFT")
P.Point(tank, "TOPRIGHT", unittarget, "BOTTOMRIGHT")
tank:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    spotlight:SetAttribute("specialUnit", "tank")  -- 使用 specialUnit 而非 unit，标识为动态坦克查找
    spotlight:SetAttribute("refreshOnUpdate", nil)
    spotlight:SetAttribute("updateOnTargetChanged", nil)
    menu:GetFrameRef("assignment"..index):SetAttribute("text", "tank")
    self:CallMethod("SetUnit", index)
    menu:Hide()
]])
-- SetUnit：标记槽位为坦克，触发 UpdateTanks 进行实际的单位分配
function tank:SetUnit(index)
    tanks[index] = true
    tankUpdateRequired = true
    UpdateTanks()
    menu:Save(index, "tank")
end

-- healer: "治疗" -- 按职责分配，自动在队伍中查找所有治疗者并按槽位分配
healer = Cell.CreateButton(menu, _G.HEALER, "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(healer, "TOPLEFT", tank, "BOTTOMLEFT")
P.Point(healer, "TOPRIGHT", tank, "BOTTOMRIGHT")
healer:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    spotlight:SetAttribute("specialUnit", "healer")  -- 使用 specialUnit 标识为动态治疗查找
    spotlight:SetAttribute("refreshOnUpdate", nil)
    spotlight:SetAttribute("updateOnTargetChanged", nil)
    menu:GetFrameRef("assignment"..index):SetAttribute("text", "healer")
    self:CallMethod("SetUnit", index)
    menu:Hide()
]])
-- SetUnit：标记槽位为治疗，触发 UpdateHealers 进行实际的单位分配
function healer:SetUnit(index)
    healers[index] = true
    healerUpdateRequired = true
    UpdateHealers()
    menu:Save(index, "healer")
end

-- boss1target: "Boss1 目标" -- 跟踪一号首领的目标（在 TBC/Vanilla 版本中不可用）
boss1target = Cell.CreateButton(menu, L["Boss1 Target"], "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(boss1target, "TOPLEFT", healer, "BOTTOMLEFT")
P.Point(boss1target, "TOPRIGHT", healer, "BOTTOMRIGHT")
boss1target:SetEnabled(not (Cell.isTBC or Cell.isVanilla))  -- TBC/Vanilla 版本不支持 boss1target
boss1target:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    spotlight:SetAttribute("unit", "boss1target")
    spotlight:SetAttribute("specialUnit", nil)
    spotlight:SetAttribute("refreshOnUpdate", true)  -- boss1target 无事件通知，使用 OnUpdate 轮询
    spotlight:SetAttribute("updateOnTargetChanged", nil)
    menu:GetFrameRef("assignment"..index):SetAttribute("text", "boss1target")
    menu:Hide()

    menu:CallMethod("Save", index, "boss1target")
]])

-- clear: "清除" -- 清除当前槽位的所有分配
clear = Cell.CreateButton(menu, L["Clear"], "transparent-accent", {20, 20}, true, false, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
P.Point(clear, "TOPLEFT", boss1target, "BOTTOMLEFT")
P.Point(clear, "TOPRIGHT", boss1target, "BOTTOMRIGHT")
clear:SetAttribute("_onclick", [[
    local menu = self:GetParent()
    local index = menu:GetAttribute("index")
    local spotlight = menu:GetFrameRef("spotlight"..index)
    -- 清除所有单位相关属性，彻底重置槽位
    spotlight:SetAttribute("unit", nil)
    spotlight:SetAttribute("specialUnit", nil)
    spotlight:SetAttribute("refreshOnUpdate", nil)
    spotlight:SetAttribute("updateOnTargetChanged", nil)
    menu:GetFrameRef("assignment"..index):SetAttribute("text", nil)
    menu:Hide()

    menu:CallMethod("Save", index, nil)
]])

-------------------------------------------------
-- functions
-- 核心更新函数：处理坦克、治疗、名称分配的动态更新逻辑
-------------------------------------------------
-- UpdateTanks：查找队伍中所有坦克职责的单位并分配到标记为坦克的槽位
-- 战斗锁定中无法分配时，设置 tankUpdateRequired 标志延迟重试
UpdateTanks = function()
    if not tankUpdateRequired then return end

    -- search for tanks -- 遍历队伍成员查找坦克职责
    local units = {}
    for unit in F.IterateGroupMembers() do  -- 安全迭代队伍成员（SecretValue 防护）
        if UnitGroupRolesAssigned(unit) == "TANK" then
            tinsert(units, unit)
        end
    end

    -- assign -- 按顺序分配到已标记为坦克的槽位
    local n = 1
    for index = 1, 15 do
        -- Midnight/战斗锁定检查：如果进入战斗，推迟更新到战斗结束
        if InCombatLockdown() then
            tankUpdateRequired = true
            return
        end

        if tanks[index] then
            if units[n] then
                Cell.unitButtons.spotlight[index]:SetAttribute("unit", units[n])
            else
                -- 没有更多坦克可分配，清空该槽位
                Cell.unitButtons.spotlight[index]:SetAttribute("unit", nil)
            end
            n = n + 1
        end
    end

    tankUpdateRequired = nil
end

-- UpdateHealers：查找队伍中所有治疗职责的单位并分配到标记为治疗的槽位
-- 逻辑与 UpdateTanks 对称，同样支持战斗锁定延迟重试
UpdateHealers = function()
    if not healerUpdateRequired then return end

    -- search for healers -- 遍历队伍成员查找治疗职责
    local units = {}
    for unit in F.IterateGroupMembers() do  -- 安全迭代（SecretValue 防护）
        if UnitGroupRolesAssigned(unit) == "HEALER" then
            tinsert(units, unit)
        end
    end

    -- assign -- 按顺序分配到已标记为治疗的槽位
    local n = 1
    for index = 1, 15 do
        -- Midnight/战斗锁定检查
        if InCombatLockdown() then
            healerUpdateRequired = true
            return
        end

        if healers[index] then
            if units[n] then
                Cell.unitButtons.spotlight[index]:SetAttribute("unit", units[n])
            else
                Cell.unitButtons.spotlight[index]:SetAttribute("unit", nil)
            end
            n = n + 1
        end
    end

    healerUpdateRequired = nil
end

-- UpdateNames：按名称匹配队伍成员，更新名称分配的槽位
-- 当队伍中有同名玩家或有玩家离开/加入时重新匹配
UpdateNames = function()
    if not nameUpdateRequired then return end

    -- search for names -- 在队伍中查找匹配的名称
    local found = {}
    for unit in F.IterateGroupMembers() do  -- 安全迭代（SecretValue 防护）
        -- Midnight/战斗锁定检查
        if InCombatLockdown() then
            nameUpdateRequired = true
            return
        end
        local name = GetUnitName(unit, true)  -- 获取带 realm 的完整名称
        if names[name] then
            -- 找到匹配名称的单位，分配到对应槽位
            Cell.unitButtons.spotlight[names[name]]:SetAttribute("unit", unit)
            found[name] = true
        end
    end

    -- hide not found -- 未找到的队伍成员：清空对应槽位（玩家可能离线或离开了队伍）
    for name, index in pairs(names) do
        -- Midnight/战斗锁定检查
        if InCombatLockdown() then
            nameUpdateRequired = true
            return
        end
        if not found[name] then
            Cell.unitButtons.spotlight[index]:SetAttribute("unit", nil)
        end
    end

    nameUpdateRequired = nil
end

-- 防抖定时器：避免队伍变化时频繁更新
local timer
-- UpdateAll：聚合更新所有动态分配（坦克、治疗、名称），使用 1 秒防抖延迟
local function UpdateAll()
    timer = nil
    tankUpdateRequired = true
    UpdateTanks()
    healerUpdateRequired = true
    UpdateHealers()
    nameUpdateRequired = true
    UpdateNames()
end

-- 事件处理逻辑
menu:RegisterEvent("GROUP_ROSTER_UPDATE")  -- 队伍成员变化
menu:RegisterEvent("PLAYER_REGEN_ENABLED")  -- 战斗结束
menu:RegisterEvent("PLAYER_REGEN_DISABLED") -- 战斗开始
menu:SetScript("OnEvent", function(self, event)
    if event == "GROUP_ROSTER_UPDATE" then
        -- 队伍成员变化：使用 1 秒防抖延迟更新，避免频繁的成员变动导致性能问题
        if timer then
            timer:Cancel()
        end
        timer = C_Timer.NewTimer(1, UpdateAll)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- 战斗开始：禁用需要玩家交互的菜单项（unit/unitname/unittarget/unitpet/tank/healer），因为这些会弹出输入框或影响性能
        -- 这是 Midnight 防护的一部分：战斗中禁止非安全的 UI 交互
        unit:SetEnabled(false)
        unitname:SetEnabled(false)
        unittarget:SetEnabled(false)
        unitpet:SetEnabled(false)
        tank:SetEnabled(false)
        healer:SetEnabled(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- 战斗结束：重新启用所有菜单项，并立即执行所有延迟的更新
        unit:SetEnabled(true)
        unitname:SetEnabled(true)
        unittarget:SetEnabled(true)
        unitpet:SetEnabled(true)
        tank:SetEnabled(true)
        healer:SetEnabled(true)
        UpdateTanks()
        UpdateHealers()
        UpdateNames()
    end
end)

-- Save：保存当前槽位的单位分配到布局配置中，同时清理其他分配表（坦克/治疗/名称）中该槽位的记录
function menu:Save(index, unit)
    Cell.vars.currentLayoutTable["spotlight"]["units"][index] = unit

    -- clear -- 清除该槽位在其他分配表中的记录（一个槽位只能有一种分配类型）
    if unit ~= "tank" then
        tanks[index] = nil
    end
    if unit ~= "healer" then
        healers[index] = nil
    end
    for n, i in pairs(names) do
        if i == index then
            names[n] = nil
        end
    end
end

-- update width to show full text -- 使用虚拟字体串计算菜单所需的最大宽度
local dumbFS1 = menu:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
dumbFS1:SetText(L["Target of Target"])
local dumbFS2 = menu:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
dumbFS2:SetText(L["Unit's Target"])

-- UpdatePixelPerfect：菜单的像素完美更新，根据最长文本计算菜单尺寸
function menu:UpdatePixelPerfect()
    menu:SetSize(ceil(max(dumbFS1:GetStringWidth(), dumbFS2:GetStringWidth())) + P.Scale(13), P.Scale(20) * 11 + P.Scale(2))

    Cell.StylizeFrame(menu, nil, Cell.GetAccentColorTable())
    target:UpdatePixelPerfect()
    focus:UpdatePixelPerfect()
    targettarget:UpdatePixelPerfect()
    unit:UpdatePixelPerfect()
    unitpet:UpdatePixelPerfect()
    clear:UpdatePixelPerfect()
end

-------------------------------------------------
-- callbacks
-- 回调函数：响应布局、外观、像素完美等全局更新事件
-------------------------------------------------
-- UpdatePosition：根据布局配置计算聚光灯框架和提示框的相对位置
-- 处理 top_bottom（上/下排列）和 left_right（左/右排列）两种方向模式
local function UpdatePosition()
    local layout = Cell.vars.currentLayoutTable

    local anchor
    if layout["spotlight"]["sameArrangementAsMain"] then
        anchor = layout["main"]["anchor"]
    else
        anchor = layout["spotlight"]["anchor"]
    end

    spotlightFrame:ClearAllPoints()
    -- NOTE: detach from spotlightPreviewAnchor -- 从预览锚点分离，使用实际存储的位置
    P.LoadPosition(anchorFrame, layout["spotlight"]["position"])

    if CellDB["general"]["menuPosition"] == "top_bottom" then
        -- 上/下排列模式：锚点框架为 20x10 的横向条
        P.Size(anchorFrame, 20, 10)

        if anchor == "BOTTOMLEFT" then
            spotlightFrame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPLEFT", "BOTTOMLEFT", 0, -3
        elseif anchor == "BOTTOMRIGHT" then
            spotlightFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPRIGHT", "BOTTOMRIGHT", 0, -3
        elseif anchor == "TOPLEFT" then
            spotlightFrame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMLEFT", "TOPLEFT", 0, 3
        elseif anchor == "TOPRIGHT" then
            spotlightFrame:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMRIGHT", "TOPRIGHT", 0, 3
        end
    else -- left_right -- 左/右排列模式：锚点框架为 10x20 的纵向条
        P.Size(anchorFrame, 10, 20)

        if anchor == "BOTTOMLEFT" then
            spotlightFrame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMRIGHT", 4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMRIGHT", "BOTTOMLEFT", -3, 0
        elseif anchor == "BOTTOMRIGHT" then
            spotlightFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMLEFT", -4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMLEFT", "BOTTOMRIGHT", 3, 0
        elseif anchor == "TOPLEFT" then
            spotlightFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPRIGHT", "TOPLEFT", -3, 0
        elseif anchor == "TOPRIGHT" then
            spotlightFrame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPLEFT", "TOPRIGHT", 3, 0
        end
    end
end

-- UpdateMenu：响应锁定状态和渐隐设置的变化
-- which = "lock": 锁定/解锁时更新拖拽注册
-- which = "fadeOut": 渐隐开关时播放/停止渐隐动画
-- which = "position": 位置变化时重新计算布局
local function UpdateMenu(which)
    if not which or which == "lock" then
        if CellDB["general"]["locked"] then
            config:RegisterForDrag()  -- 锁定时取消拖拽
        else
            config:RegisterForDrag("LeftButton")  -- 解锁时允许左键拖拽
        end
    end

    if not which or which == "fadeOut" then
        if CellDB["general"]["fadeOut"] then
            anchorFrame.fadeOut:Play()
        else
            anchorFrame.fadeIn:Play()
        end
    end

    if which == "position" then
        UpdatePosition()
    end
end
Cell.RegisterCallback("UpdateMenu", "SpotlightFrame_UpdateMenu", UpdateMenu)

-- UpdateLayout：核心布局更新函数，处理所有布局属性变化
-- which 参数支持增量更新（nil = 全量更新，或指定具体属性）
local function UpdateLayout(layout, which)
    -- visibility -- 如果 Cell 整体隐藏，聚光灯也隐藏
    if Cell.vars.isHidden then
        spotlightFrame:Hide()
        menu:Hide()
        return
    end

    -- update -- 刷新当前布局引用
    layout = Cell.vars.currentLayoutTable

    -- size 更新：聚光灯框架和占位符的尺寸
    if not which or strfind(which, "size$") then
        local width, height
        if layout["spotlight"]["sameSizeAsMain"] then
            width, height = unpack(layout["main"]["size"])  -- 与主框架相同尺寸
        else
            width, height = unpack(layout["spotlight"]["size"])  -- 独立尺寸
        end

        P.Size(spotlightFrame, width, height)

        for _, f in pairs(placeholders) do
            P.Size(f, width, height)
        end
    end

    -- arrangement 更新：排列方向、间距、锚点计算
    if not which or strfind(which, "arrangement$") then
        local orientation, anchor, spacingX, spacingY
        if layout["spotlight"]["sameArrangementAsMain"] then
            -- 与主框架相同的排列方式
            orientation = layout["main"]["orientation"]
            anchor = layout["main"]["anchor"]
            spacingX = layout["main"]["spacingX"]
            spacingY = layout["main"]["spacingY"]
        else
            -- 独立排列方式
            orientation = layout["spotlight"]["orientation"]
            anchor = layout["spotlight"]["anchor"]
            spacingX = layout["spotlight"]["spacingX"]
            spacingY = layout["spotlight"]["spacingY"]
        end

        -- anchors -- 根据方向和锚点计算框架锚点、组锚点、菜单锚点
        local point, anchorPoint, groupPoint, unitSpacingX, unitSpacingY
        local menuAnchorPoint, menuX, menuY

        if strfind(orientation, "^vertical") then
            -- 垂直排列：单位从锚点开始向上/向下排列，每 5 个单位换列
            if anchor == "BOTTOMLEFT" then
                point, anchorPoint = "BOTTOMLEFT", "TOPLEFT"
                groupPoint = "BOTTOMRIGHT"
                unitSpacingX = spacingX
                unitSpacingY = spacingY
                menuAnchorPoint = "BOTTOMRIGHT"
                menuX, menuY = 4, 0
            elseif anchor == "BOTTOMRIGHT" then
                point, anchorPoint = "BOTTOMRIGHT", "TOPRIGHT"
                groupPoint = "BOTTOMLEFT"
                unitSpacingX = -spacingX
                unitSpacingY = spacingY
                menuAnchorPoint = "BOTTOMLEFT"
                menuX, menuY = -4, 0
            elseif anchor == "TOPLEFT" then
                point, anchorPoint = "TOPLEFT", "BOTTOMLEFT"
                groupPoint = "TOPRIGHT"
                unitSpacingX = spacingX
                unitSpacingY = -spacingY
                menuAnchorPoint = "TOPRIGHT"
                menuX, menuY = 4, 0
            elseif anchor == "TOPRIGHT" then
                point, anchorPoint = "TOPRIGHT", "BOTTOMRIGHT"
                groupPoint = "TOPLEFT"
                unitSpacingX = -spacingX
                unitSpacingY = -spacingY
                menuAnchorPoint = "TOPLEFT"
                menuX, menuY = -4, 0
            end
        else
            -- 水平排列：单位从锚点开始向左/向右排列，每 5 个单位换行
            if anchor == "BOTTOMLEFT" then
                point, anchorPoint = "BOTTOMLEFT", "BOTTOMRIGHT"
                groupPoint = "TOPLEFT"
                unitSpacingX = spacingX
                unitSpacingY = spacingY
                menuAnchorPoint = "TOPLEFT"
                menuX, menuY = 0, 4
            elseif anchor == "BOTTOMRIGHT" then
                point, anchorPoint = "BOTTOMRIGHT", "BOTTOMLEFT"
                groupPoint = "TOPRIGHT"
                unitSpacingX = -spacingX
                unitSpacingY = spacingY
                menuAnchorPoint = "TOPRIGHT"
                menuX, menuY = 0, 4
            elseif anchor == "TOPLEFT" then
                point, anchorPoint = "TOPLEFT", "TOPRIGHT"
                groupPoint = "BOTTOMLEFT"
                unitSpacingX = spacingX
                unitSpacingY = -spacingY
                menuAnchorPoint = "BOTTOMLEFT"
                menuX, menuY = 0, -4
            elseif anchor == "TOPRIGHT" then
                point, anchorPoint = "TOPRIGHT", "TOPLEFT"
                groupPoint = "BOTTOMRIGHT"
                unitSpacingX = -spacingX
                unitSpacingY = -spacingY
                menuAnchorPoint = "BOTTOMRIGHT"
                menuX, menuY = 0, -4
            end
        end

        -- 存储菜单锚点到安全属性中，供 _onclick 片段使用
        menu:SetAttribute("point", point)
        menu:SetAttribute("anchorPoint", menuAnchorPoint)
        menu:SetAttribute("xOffset", P.Scale(menuX))
        menu:SetAttribute("yOffset", P.Scale(menuY))
        menu:Hide()

        -- 排列所有占位符（以及通过 SetAllPoints 关联的分配按钮和单位按钮）
        local last
        for i, f in pairs(placeholders) do
            f:ClearAllPoints()
            if last then
                if strfind(orientation, "^vertical") then
                    -- 垂直排列：每 5 个一组换列
                    if i % 5 == 1 and orientation == "vertical" then
                        f:SetPoint(point, placeholders[i-5], groupPoint, P.Scale(unitSpacingX), 0)
                    else
                        f:SetPoint(point, last, anchorPoint, 0, P.Scale(unitSpacingY))
                    end
                else
                    -- 水平排列：每 5 个一组换行
                    if i % 5 == 1 and orientation == "horizontal" then
                        f:SetPoint(point, placeholders[i-5], groupPoint, 0, P.Scale(unitSpacingY))
                    else
                        f:SetPoint(point, last, anchorPoint, P.Scale(unitSpacingX), 0)
                    end
                end
            else
                -- 第一个单位直接在聚光灯框架的左上角
                f:SetPoint("TOPLEFT", spotlightFrame)
            end
            last = f
        end

        UpdatePosition()
    end

    -- NOTE: SetOrientation BEFORE SetPowerSize -- 必须先设置方向再设置能量条尺寸
    -- barOrientation 更新：设置每个聚光灯单位按钮的条状方向
    if not which or which == "barOrientation" then
        for _, b in pairs(Cell.unitButtons.spotlight) do
            B.SetOrientation(b, layout["barOrientation"][1], layout["barOrientation"][2])
        end
    end

    -- power 更新：能量条尺寸
    if not which or strfind(which, "power$") or which == "barOrientation" or which == "powerFilter" then
        for _, b in pairs(Cell.unitButtons.spotlight) do
            if layout["spotlight"]["sameSizeAsMain"] then
                B.SetPowerSize(b, layout["main"]["powerSize"])
            else
                B.SetPowerSize(b, layout["spotlight"]["powerSize"])
            end
        end
    end

    -- spotlight 更新：聚光灯启用的核心逻辑，初始化/刷新所有槽位的单位分配
    if not which or which == "spotlight" then
        -- 清除所有动态分配表，准备重新初始化
        wipe(tanks)
        wipe(healers)
        wipe(names)

        if layout["spotlight"]["enabled"] then
            for i = 1, 15 do
                local unit = layout["spotlight"]["units"][i]
                -- 设置占位符隐藏选项（hidePlaceholder：不显示占位符，即使该槽位有分配）
                Cell.unitButtons.spotlight[i]:SetAttribute("hidePlaceholder", layout["spotlight"]["hidePlaceholder"])

                -- 重置所有刷新属性（将在下面的分支中根据类型重新设置）
                Cell.unitButtons.spotlight[i]:SetAttribute("refreshOnUpdate", nil)
                Cell.unitButtons.spotlight[i]:SetAttribute("updateOnTargetChanged", nil)
                Cell.unitButtons.spotlight[i]:SetAttribute("specialUnit", nil)

                if unit == "tank" then -- tank -- 坦克类型：使用动态查找
                    tanks[i] = true
                    Cell.unitButtons.spotlight[i]:SetAttribute("specialUnit", "tank")
                elseif unit == "healer" then -- healer -- 治疗类型：使用动态查找
                    healers[i] = true
                    Cell.unitButtons.spotlight[i]:SetAttribute("specialUnit", "healer")
                elseif unit and strfind(unit, "^:") then -- name -- 名称类型（以 ":" 开头）：按名称匹配
                    unit = strsub(unit, 2)
                    names[unit] = i
                else -- unitid -- 直接 unitID：如 "target", "focus", "party1" 等
                    Cell.unitButtons.spotlight[i]:SetAttribute("unit", unit)
                    -- 对于 "XXtarget" 形式的 unitID，需要 OnUpdate 轮询（无事件通知）
                    if unit and strfind(unit, "^.+target$") then
                        Cell.unitButtons.spotlight[i]:SetAttribute("refreshOnUpdate", true)
                    elseif unit == "target" then
                        -- "target" 有 PLAYER_TARGET_CHANGED 事件，使用事件驱动
                        Cell.unitButtons.spotlight[i]:SetAttribute("updateOnTargetChanged", true)
                    end
                end
                RegisterUnitWatch(Cell.unitButtons.spotlight[i])  -- 注册单位观察，开始接收事件
                assignmentButtons[i]:SetAttribute("text", unit)
            end
            -- 触发动态分配更新
            tankUpdateRequired = true
            UpdateTanks()
            healerUpdateRequired = true
            UpdateHealers()
            nameUpdateRequired = true
            UpdateNames()
            spotlightFrame:Show()
        else
            -- 聚光灯未启用：清除所有槽位并注销单位观察
            for i = 1, 15 do
                Cell.unitButtons.spotlight[i]:SetAttribute("unit", nil)
                Cell.unitButtons.spotlight[i]:SetAttribute("refreshOnUpdate", nil)
                Cell.unitButtons.spotlight[i]:SetAttribute("updateOnTargetChanged", nil)
                UnregisterUnitWatch(Cell.unitButtons.spotlight[i])
                assignmentButtons[i]:SetText("|cffababab"..NONE)
                Cell.unitButtons.spotlight[i]:Hide()
            end
            spotlightFrame:Hide()
            menu:Hide()
        end
    end

    -- load position -- 加载或重置锚点位置
    if not P.LoadPosition(anchorFrame, layout["spotlight"]["position"]) then
        P.ClearPoints(anchorFrame)
        -- no position, use default -- 无保存位置时，使用默认位置（屏幕居中偏上）
        anchorFrame:SetPoint("TOPLEFT", CellParent, "CENTER")
    end
end
Cell.RegisterCallback("UpdateLayout", "SpotlightFrame_UpdateLayout", UpdateLayout)

-- UpdatePixelPerfect：像素完美更新回调，调整所有子框架的尺寸和样式
local function UpdatePixelPerfect()
    P.Resize(spotlightFrame)
    P.Resize(anchorFrame)
    targetFrame:UpdatePixelPerfect()
    config:UpdatePixelPerfect()
    menu:UpdatePixelPerfect()
    menu:SetSize(ceil(max(dumbFS1:GetStringWidth(), dumbFS2:GetStringWidth())) + P.Scale(13), P.Scale(20) * 11 + P.Scale(2))

    for _, p in pairs(placeholders) do
        Cell.StylizeFrame(p, {0, 0, 0, 0.27})
    end

    for _, b in pairs(assignmentButtons) do
        b:UpdatePixelPerfect()
    end
end
Cell.RegisterCallback("UpdatePixelPerfect", "SpotlightFrame_UpdatePixelPerfect", UpdatePixelPerfect)

-- UpdateAppearance：外观更新回调，处理框架层级变化
-- strata 更新后需要延迟 0.5 秒重新设置，因为 WoW 可能在内部重置某些框架的层级（Midnight 相关行为）
local function UpdateAppearance(which)
    if not which or which == "strata" then
        C_Timer.After(0.5, function()
            targetFrame:SetFrameStrata("TOOLTIP")
            -- 战斗锁定检查：安全限制下不能修改某些框架属性，延迟到解锁后再设置
            if not InCombatLockdown() then
                menu:SetFrameStrata("FULLSCREEN_DIALOG")
                menu:SetToplevel(true)
            end
        end)
    end
end
Cell.RegisterCallback("UpdateAppearance", "SpotlightFrame_UpdateAppearance", UpdateAppearance)