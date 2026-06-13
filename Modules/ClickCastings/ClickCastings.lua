local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-------------------------------------------------
-- 点击施法模块 (Click-Castings Module)
-- 负责管理 Cell 的点击施法功能，包括按键绑定、技能/宏/物品映射、
-- 配置文件切换、智能复活、总是选目标等特性。
-- 采用 SecureActionButtonTemplate 安全模板实现，支持战斗中安全施法。
-- 数据库格式参考: https://wow.gamepedia.com/SecureActionButtonTemplate
-- {"shift-type1", "macro", "shift-macrotext1", "/cast [@mouseover] 回春术"}
-------------------------------------------------

-- 创建点击施法设置标签页，挂载到 Cell 选项面板上
local clickCastingsTab = Cell.CreateFrame("CellOptionsFrame_ClickCastingsTab", Cell.frames.optionsFrame, nil, nil, true)
Cell.frames.clickCastingsTab = clickCastingsTab
clickCastingsTab:SetAllPoints(Cell.frames.optionsFrame)
clickCastingsTab:Hide()

local listPane
local bindingsFrame
local listButtons = {}
local clickCastingTable
local loaded
local LoadProfile
local alwaysTargeting, smartResurrection
-------------------------------------------------
-- changes
-------------------------------------------------
local saveBtn, cancelBtn
local deleted, changed = {}, {}
-- 检查是否有未保存的修改，如果有则启用保存/取消按钮，并锁定列表按钮的拖拽排序
local function CheckChanges()
    if F.Getn(deleted) == 0 and F.Getn(changed) == 0 then
        saveBtn:SetEnabled(false)
        cancelBtn:SetEnabled(false)
        for _, b in pairs(listButtons) do
            b.unmovable = nil
        end
    else
        saveBtn:SetEnabled(true)
        cancelBtn:SetEnabled(true)
        for _, b in pairs(listButtons) do
            b.unmovable = true
        end
    end
end

-------------------------------------------------
-- db
-------------------------------------------------
-- https://wow.gamepedia.com/SecureActionButtonTemplate
-- {"shift-type1", "macro", "shift-macrotext1", "/cast [@mouseover] 回春术"}

-- 装备栏位名称映射表，用于 Item 类型的点击施法动作，将栏位编号映射为本地化名称
local slotNames = {
    [1] = _G.INVTYPE_HEAD,
    [2] = _G.INVTYPE_NECK,
    [3] = _G.INVTYPE_SHOULDER,
    [4] = _G.INVTYPE_BODY,
    [5] = _G.INVTYPE_CHEST,
    [6] = _G.INVTYPE_WAIST,
    [7] = _G.INVTYPE_LEGS,
    [8] = _G.INVTYPE_FEET,
    [9] = _G.INVTYPE_WRIST,
    [10] = _G.INVTYPE_HAND,
    [11] = _G.INVTYPE_FINGER .. " 1",
    [12] = _G.INVTYPE_FINGER .. " 2",
    [13] = _G.INVTYPE_TRINKET .. " 1",
    [14] = _G.INVTYPE_TRINKET .. " 2",
    [15] = _G.INVTYPE_CLOAK,
    [16] = _G.INVTYPE_WEAPONMAINHAND,
    [17] = _G.INVTYPE_WEAPONOFFHAND,
}

-- local modifiers = {"", "shift-", "ctrl-", "alt-", "ctrl-shift-", "alt-shift-", "alt-ctrl-", "alt-ctrl-shift-"}
-- local modifiersDisplay = {"", "Shift|cff777777+|r", "Ctrl|cff777777+|r", "Alt|cff777777+|r", "Ctrl|cff777777+|rShift|cff777777+|r", "Alt|cff777777+|rShift|cff777777+|r", "Alt|cff777777+|rCtrl|cff777777+|r", "Alt|cff777777+|rCtrl|cff777777+|rShift|cff777777+|r"}
-- local keys = {"Left", "Right", "Middle", "Button4", "Button5", "ScrollUp", "ScrollDown"}
-- 鼠标按键名称到编号的映射表，用于安全模板的属性键生成（如 "Left" -> 1, "Right" -> 2）
local mouseKeyIDs = {
    ["Left"] = 1,
    ["Right"] = 2,
    ["Middle"] = 3,
    ["Button4"] = 4,
    ["Button5"] = 5,
    ["Button6"] = 6,
    ["Button7"] = 7,
    ["Button8"] = 8,
    ["Button9"] = 9,
    ["Button10"] = 10,
    ["Button11"] = 11,
    ["Button12"] = 12,
    ["Button13"] = 13,
    ["Button14"] = 14,
    ["Button15"] = 15,
    ["Button16"] = 16,
    ["Button17"] = 17,
    ["Button18"] = 18,
    ["Button19"] = 19,
    ["Button20"] = 20,
    ["Button21"] = 21,
    ["Button22"] = 22,
    ["Button23"] = 23,
    ["Button24"] = 24,
    ["Button25"] = 25,
    ["Button26"] = 26,
    ["Button27"] = 27,
    ["Button28"] = 28,
    ["Button29"] = 29,
    ["Button30"] = 30,
    ["Button31"] = 31,
}

-- 将修饰键和按键转换为用户可读的显示文本（如 "shift-Left" -> "Shift+Left"）
-- 处理键盘按键、鼠标按键、小键盘等不同类型的按键名称本地化
local function GetBindingDisplay(modifier, key)
    modifier = modifier:gsub("%-", "|cff777777+|r")
    modifier = modifier:gsub("alt", "Alt")
    modifier = modifier:gsub("ctrl", "Ctrl")
    modifier = modifier:gsub("shift", "Shift")
    modifier = modifier:gsub("meta", "Command")

    if strfind(key, "^NUM") then
        key = _G["KEY_"..key]
    elseif strfind(key, "^Button") then
        key = gsub(key, "^Button", L["Button"])
    elseif strlen(key) ~= 1 then
        key = L[key]
    end

    return modifier..key
end

-- 将修饰键+按键组合转换为 SecureActionButtonTemplate 的属性键格式
-- 鼠标按键: shift-Left -> shift-type1
-- 滚轮: shift-ScrollUp -> shift-type-SCROLLUP
-- 键盘: shift-B -> type-shiftB
-- 此函数是 EncodeDB 的核心辅助，生成的键名对应安全模板的 SetAttribute 键
local function GetAttributeKey(modifier, bindKey)
    if mouseKeyIDs[bindKey] then -- normal mouse button
        return modifier.."type"..mouseKeyIDs[bindKey]
    elseif bindKey == "ScrollUp" or bindKey == "ScrollDown" then -- mouse wheel
        return modifier.."type-"..strupper(bindKey)
    else -- keyboard
        modifier = string.gsub(modifier, "alt%-", "alt")
        modifier = string.gsub(modifier, "ctrl%-", "ctrl")
        modifier = string.gsub(modifier, "shift%-", "shift")
        return "type-"..modifier..bindKey
    end
end

-- 将 UI 层的绑定数据编码为数据库存储格式
-- 输入: 修饰键、按键、绑定类型(spell/macro/custom/item/general)、绑定动作
-- 输出: {属性键, 类型, 动作} 三元组，用于持久化存储
-- 特殊: notBound 表示未绑定按键（新建的空绑定条目）
local function EncodeDB(modifier, bindKey, bindType, bindAction)
    local attrType, attrAction
    if bindType == "spell" then
        attrType = "spell"
        attrAction = bindAction
    elseif bindType == "macro" then
        attrType = "macro"
        attrAction = bindAction
    elseif bindType == "custom" then
        attrType = "custom"
        attrAction = bindAction
    elseif bindType == "item" then
        attrType = "item"
        attrAction = bindAction
    else -- general
        attrType = bindAction
        -- attrAction = nil
    end

    if bindKey == "notBound" then
        return {"notBound", attrType, attrAction}
    else
        return {GetAttributeKey(modifier, bindKey), attrType, attrAction}
    end
end

-- 解码键盘属性键中的修饰键和按键部分
-- 将紧凑格式（如 "altctrlB"）还原为修饰键（"alt-ctrl-"）和按键（"B"）
-- 用于 DecodeDB 中处理非鼠标按键的属性键解析
local function DecodeKeyboard(fullKey)
    fullKey = string.gsub(fullKey, "alt", "alt-")
    fullKey = string.gsub(fullKey, "ctrl", "ctrl-")
    fullKey = string.gsub(fullKey, "shift", "shift-")
    local modifier, key = strmatch(fullKey, "^(.*-)(.+)$")
    if not modifier then -- no modifier
        modifier = ""
        key = fullKey
    end
    return modifier, key
end

-- 将数据库存储的三元组解码为 UI 层可用的四个字段
-- 输入: {属性键, 类型, 动作} 三元组（来自 clickCastingTable）
-- 输出: modifier, bindKey, bindType, bindAction 四个独立值
-- 能够处理鼠标按键、滚轮、键盘按键三种不同的属性键格式
local function DecodeDB(t)
    local modifier, bindKey, bindType, bindAction

    if t[1] ~= "notBound" then
        local dash, key
        modifier, dash, key = strmatch(t[1], "^(.*)type(-*)(.+)$")

        if dash == "-" then
            if key == "SCROLLUP" then
                bindKey = "ScrollUp"
            elseif key == "SCROLLDOWN" then
                bindKey = "ScrollDown"
            else
                modifier, bindKey = DecodeKeyboard(key)
            end
        else -- normal mouse button
            bindKey = F.GetIndex(mouseKeyIDs, tonumber(key))
        end
    else
        modifier, bindKey = "", "notBound"
    end

    if not t[3] then
        bindType = "general"
        bindAction = t[2]
    else
        bindType = t[2]
        bindAction = t[3]
    end

    return modifier, bindKey, bindType, bindAction
end

-------------------------------------------------
-- 鼠标滚轮与键盘绑定处理
-- 利用 SecureHandlerStateTemplate 状态驱动框架管理鼠标悬停和战斗状态
-- wrapFrame 是整个点击施法按键绑定系统的核心调度器
-------------------------------------------------

-- 全局状态驱动框架，用于跟踪鼠标悬停状态和战斗状态变化
-- 当鼠标移出目标或进入/离开战斗时，自动清除或更新按键绑定
local wrapFrame = CreateFrame("Frame", "CellWrapFrame", nil, "SecureHandlerStateTemplate")
-- 鼠标悬停状态变化处理：当鼠标移出目标时自动清除绑定，防止残留的按键映射
wrapFrame:SetAttribute("_onstate-mouseoverstate", [[
    -- print("mouseoverstate", newstate)
    if newstate == "false" and mouseoverbutton then
        if not mouseoverbutton:IsUnderMouse() then
            mouseoverbutton:ClearBindings()
            mouseoverbutton = nil
        end
    end
]])
--! NOTE: not available for unit far away (different map)
-- 注册鼠标悬停状态驱动：鼠标悬停在有效单位上为 "true"，否则为 "false"
RegisterStateDriver(wrapFrame, "mouseoverstate", "[@mouseover, exists] true; false")

-- 战斗状态变化处理：进入战斗时禁用 togglemenu，离开战斗时恢复 togglemenu
-- 确保在战斗中不会弹出菜单干扰操作
wrapFrame:SetAttribute("_onstate-combatstate", [[
    -- print("combatstate", newstate)
    if mouseoverbutton then
        local menuKey = mouseoverbutton:GetAttribute("menu")
        if menuKey then
            if newstate == "true" then
                mouseoverbutton:SetAttribute(menuKey, nil)
            else
                mouseoverbutton:SetAttribute(menuKey, "togglemenu")
            end
        end
    end
]])
-- 注册战斗状态驱动：进入战斗为 "true"，脱离战斗为 "false"
RegisterStateDriver(wrapFrame, "combatstate", "[combat] true; false")

-- 设置目标按钮的按键绑定行为（_onenter/_onleave/_onhide 属性）
-- 分离正式服和经典旧世两条路径：
--   正式服: 使用 @mouseover 直接定位，无需处理载具
--   经典旧世: 使用 @cell 占位符，需要处理载具UI（载具宠物按钮映射）
-- 核心机制: 鼠标进入时注入按键绑定snippet，离开或隐藏时清除所有绑定
local SetBindingClicks
if Cell.isRetail then
    SetBindingClicks = function (b)
        -- 正式服版本的 _onenter: 鼠标进入时清除旧绑定、注入按键绑定snippet、更新 togglemenu 状态
        b:SetAttribute("_onenter", [[
            -- print("_onenter")
            self:ClearBindings()
            self:Run(self:GetAttribute("snippet"))

            -- self:SetBindingClick(true, "SHIFT-MOUSEWHEELUP", self, "shiftSCROLLUP")
            -- FIXME: --! 如果游戏按键设置（比如“视角”“载具控制”）中绑定了滚轮，那么 self:SetBindingClick(true, "MOUSEWHEELUP", self, "SCROLLUP") 会失效
            -- self:SetBindingClick(true, "MOUSEWHEELUP", self, "SCROLLUP")
            -- self:SetBindingClick(true, "MOUSEWHEELDOWN", self, "SCROLLDOWN")

            -- self:SetBindingClick(true, "SHIFT-B", self, "shiftB")
            -- self:SetBindingClick(true, "SHIFT-C", self, "shiftC")

            --! update click-casting unit
            -- local attrs = self:GetAttribute("cell")
            -- -- print(attrs)
            -- if attrs then
            --     for _, k in pairs(table.new(strsplit("|", attrs))) do
            --         self:SetAttribute(k, string.gsub(self:GetAttribute(k), "@%w+", "@"..self:GetAttribute("unit")))
            --     end
            -- end

            --! update togglemenu
            local menuKey = self:GetAttribute("menu")
            if menuKey then
                if PlayerInCombat() then
                    self:SetAttribute(menuKey, nil)
                else
                    self:SetAttribute(menuKey, "togglemenu")
                end
            end
        ]])

        -- 使用 WrapScript 包装 OnEnter：当鼠标从一个单位按钮移到另一个时，清理前一个按钮的绑定
        -- 这解决了 _onleave 被遮挡时不触发的问题
        wrapFrame:WrapScript(b, “OnEnter”, [[
            -- print(“OnEnter”)
            if mouseoverbutton then mouseoverbutton:ClearBindings() end --! NOTE: 鼠标放在过远单位上->被挡住->移走->移至可用单位再移出，会发现之前的不可用单位的按键绑定仍未取消
            mouseoverbutton = self
        ]])

        --! NOTE: if another frame shows in front of b, _onleave will NOT trigger. Use WrapScript to solve this issue.
        -- _onleave 属性：鼠标离开按钮时清除所有绑定（但若有遮挡不会触发，由 WrapScript 的 OnEnter 补足）
        b:SetAttribute(“_onleave”, [[
            -- print(“_onleave”)
            self:ClearBindings()
        ]])

        -- wrapFrame:WrapScript(b, “OnLeave”, [[
        --     -- print(“OnLeave”)
        --     mouseoverbutton = nil
        -- ]])

        -- _onhide 属性：按钮隐藏时清除所有绑定，确保安全模板干净
        b:SetAttribute(“_onhide”, [[
            self:ClearBindings()
        ]])
    end
else
    -- 经典旧世版本的 _onenter: 除基本绑定注入外，还需处理载具UI切换和 @cell 占位符更新
    SetBindingClicks = function(b)
        b:SetAttribute(“_onenter”, [[
            -- print(“_onenter”)
            self:ClearBindings()
            self:Run(self:GetAttribute(“snippet”))

            -- self:SetBindingClick(true, “SHIFT-MOUSEWHEELUP”, self, “shiftSCROLLUP”)
            -- FIXME: --! 如果游戏按键设置（比如”视角””载具控制”）中绑定了滚轮，那么 self:SetBindingClick(true, “MOUSEWHEELUP”, self, “SCROLLUP”) 会失效
            -- self:SetBindingClick(true, “MOUSEWHEELUP”, self, “SCROLLUP”)
            -- self:SetBindingClick(true, “MOUSEWHEELDOWN”, self, “SCROLLDOWN”)

            -- self:SetBindingClick(true, “SHIFT-B”, self, “shiftB”)
            -- self:SetBindingClick(true, “SHIFT-C”, self, “shiftC”)

            --! vehicle
            local unit = self:GetAttribute(“unit”)
            local vehicle
            if UnitHasVehicleUI(unit) then
                if unit == “player” then
                    vehicle = “pet”
                elseif strfind(unit, “^party%d+$”) then
                    vehicle = string.gsub(unit, “party”, “partypet”)
                elseif strfind(unit, “^raid%d+$”) then
                    vehicle = string.gsub(unit, “raid”, “raidpet”)
                end
            end

            --! update click-casting unit
            local clickCastingUnit = vehicle or unit
            local attrs = self:GetAttribute(“cell”)
            -- print(attrs)
            if attrs then
                for _, k in pairs(table.new(strsplit(“|”, attrs))) do
                    self:SetAttribute(k, string.gsub(self:GetAttribute(k), “@%w+”, “@”..clickCastingUnit))
                    -- print(self:GetAttribute(k))
                end
            end

            --! update togglemenu
            local menuKey = self:GetAttribute(“menu”)
            if menuKey then
                if PlayerInCombat() then
                    self:SetAttribute(menuKey, nil)
                else
                    self:SetAttribute(menuKey, “togglemenu”)
                end
            end
        ]])

        -- 使用 WrapScript 包装 OnEnter（经典旧世版本）：清理前一个按钮的绑定，并恢复其载具单位属性
        -- 经典旧世需要额外处理 oldUnit 属性来在按钮间切换时正确恢复载具状态
        wrapFrame:WrapScript(b, “OnEnter”, [[
            -- print(“OnEnter”)
            if mouseoverbutton then
                --! NOTE: 鼠标放在过远单位上->被挡住->移走->移至可用单位再移出，会发现之前的不可用单位的按键绑定仍未取消
                mouseoverbutton:ClearBindings()

                --! vehicle (previous button)
                local oldUnit = mouseoverbutton:GetAttribute(“oldUnit”)
                if oldUnit then
                    -- print(“wrap restore unit”)
                    mouseoverbutton:SetAttribute(“unit”, oldUnit)
                    mouseoverbutton:SetAttribute(“oldUnit”, nil)
                end
            end
            mouseoverbutton = self
        ]])

        --! NOTE: if another frame shows in front of b, _onleave will NOT trigger. Use WrapScript to solve this issue.
        -- _onleave 属性（经典旧世）：鼠标离开按钮时清除绑定
        b:SetAttribute("_onleave", [[
            -- print("_onleave")
            self:ClearBindings()
        ]])

        -- wrapFrame:WrapScript(b, "OnLeave", [[
        --     -- print("OnLeave")
        --     mouseoverbutton = nil
        -- ]])

        -- _onhide 属性（经典旧世）：按钮隐藏时清除绑定并恢复载具单位属性
        -- 经典旧世需要在此处处理 oldUnit 恢复，因为进入载具时会临时修改 unit
        b:SetAttribute("_onhide", [[
            self:ClearBindings()

            --! vehicle
            local oldUnit = self:GetAttribute("oldUnit")
            if oldUnit then
                -- print("restore unit")
                self:SetAttribute("oldUnit", nil)
                self:SetAttribute("unit", oldUnit)
            end
        ]])
    end
end

-- 从完整属性键中提取滚轮绑定键名
-- FIXME: 暴雪的滚轮绑定在游戏中可能存在优先级问题，此处为临时方案，希望暴雪修复此 Bug
-- 输入如 "alt-type-ctrlSCROLLUP"，输出 "type-ctrlSCROLLUP"（或 "ctrlSCROLLUP" 如果 noTypePrefix=true）
local function GetMouseWheelBindKey(fullKey, noTypePrefix)
    local modifier, key = strmatch(fullKey, "^(.*)type%-(.+)$")
    modifier = string.gsub(modifier, "-", "")

    if noTypePrefix then
        return modifier..key
    else
        return "type-"..modifier..key -- type-ctrlSCROLLUP
    end
end

-- 根据当前 clickCastingTable 生成按键绑定注入代码片段（snippet）
-- 遍历所有绑定条目，为每个唯一的按键组合生成一句 SetBindingClick 宏代码
-- 这段 snippet 会在 _onenter 时通过 self:Run(snippet) 注入到安全按钮上
-- 注意：滚轮绑定的 FIXME -- 如果游戏设置中已绑定滚轮（视角缩放、载具控制），SetBindingClick 会失效
function F.GetBindingSnippet()
    local bindingClicks = {}
    for _, t in pairs(clickCastingTable) do
        if t[1] ~= "notBound" then
            local modifier, key = strmatch(t[1], "^(.*)type%-(.+)$")
            if key then
                -- if key == "SCROLLUP" then
                --     bindingClicks[key] = [[self:SetBindingClick(true, "MOUSEWHEELUP", self, "SCROLLUP")]]
                -- elseif key == "SCROLLDOWN" then
                --     bindingClicks[key] = [[self:SetBindingClick(true, "MOUSEWHEELDOWN", self, "SCROLLDOWN")]]
                if key == "SCROLLUP" or key == "SCROLLDOWN" then
                    key = GetMouseWheelBindKey(t[1], true) -- ctrlSCROLLUP
                    if not bindingClicks[key] then
                        local m, k = DecodeKeyboard(key)
                        k = k == "SCROLLUP" and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
                        bindingClicks[key] = [[self:SetBindingClick(true, "]]..strupper(m..k)..[[", self, "]]..key..[[")]]
                    end
                elseif not bindingClicks[key] then
                    local m, k = DecodeKeyboard(key)
                    -- override keyboard to click
                    if k == [[\]] then
                        key = key:gsub([[\]], [[\\]])
                        bindingClicks[key] = [[self:SetBindingClick(true, "]]..strupper(m)..[[\\", self, "]]..key..[[")]]
                    elseif k == [["]] then
                        key = key:gsub([["]], [[\"]])
                        bindingClicks[key] = [[self:SetBindingClick(true, "]]..strupper(m)..[[\"", self, "]]..key..[[")]]
                    else
                        bindingClicks[key] = [[self:SetBindingClick(true, "]]..strupper(m..k)..[[", self, "]]..key..[[")]]
                    end
                end
            end
        end
    end

    local snippet = ""
    for _, bindingClick in pairs(bindingClicks) do
        snippet = snippet..bindingClick.."\n"
    end
    return snippet
end

-------------------------------------------------
-- update click-castings
-------------------------------------------------
-- 缓存上一次的点击施法配置，用于清除时比对
local previousClickCastings

-- 清除指定按钮上所有已设置的点击施法属性
-- 遍历上次绑定的所有属性键，将 type/spell/macro/macrotext/item 相关属性全部置 nil
-- 这确保在重新应用配置前按钮处于干净状态
local function ClearClickCastings(b)
    if not previousClickCastings then return end
    b:SetAttribute("cell", nil)
    b:SetAttribute("menu", nil)
    for _, t in pairs(previousClickCastings) do
        local bindKey = t[1]
        if strfind(bindKey, "SCROLL") then
            bindKey = GetMouseWheelBindKey(t[1])
        end

        b:SetAttribute(bindKey, nil)
        local attr = string.gsub(bindKey, "type", "spell")
        b:SetAttribute(attr, nil)
        attr = string.gsub(bindKey, "type", "macro")
        b:SetAttribute(attr, nil)
        attr = string.gsub(bindKey, "type", "macrotext")
        b:SetAttribute(attr, nil)
        attr = string.gsub(bindKey, "type", "item")
        b:SetAttribute(attr, nil)
        -- attr = string.gsub(bindKey, "type", "click")
        -- b:SetAttribute(attr, nil)
        -- if t[2] == "spell" then
        --     local attr = string.gsub(bindKey, "type", "spell")
        --     b:SetAttribute(attr, nil)
        -- elseif t[2] == "macro" then
        --     local attr = string.gsub(bindKey, "type", "macrotext")
        --     b:SetAttribute(attr, nil)
        -- end
    end
end

-- 存储需要动态更新 @cell 占位符的属性键列表
-- 这些键会在 _onenter 中被遍历并更新其中的 @unit 引用
-- NOTE: 尝试用于修复距离过远目标的点击施法问题，但没有卵用，确认是游戏问题。
-- NOTE: 当目标为敌对时，@范围内/距离稍微超出一点儿的 > 自动自我施法的优先级 > @距离过远的
-- 使用 "|" 分隔符将多个属性键串联存储在 "cell" 属性中
local function UpdatePlaceholder(b, attr)
    if not b:GetAttribute("cell") then
        b:SetAttribute("cell", attr)
    else
        b:SetAttribute("cell", b:GetAttribute("cell").."|"..attr)
    end
end

-- do
--     print(C_SpellBook.GetSpellBookItemName(FindSpellBookSlotBySpellID(428332), Enum.SpellBookSpellBank.Player))
--     local f = CreateFrame("Frame")
--     f:RegisterEvent("SPELLS_CHANGED")
--     f:SetScript("OnEvent", function()
--         f:UnregisterAllEvents()
--         local pw = Spell:CreateFromSpellID(428332)
--         pw:ContinueOnSpellLoad(function()
--               local name = pw:GetSpellName()
--               local sub = pw:GetSpellSubtext()
--               print(name, sub)
--         end)
--     end)
-- end

-- 将 clickCastingTable 中的所有绑定应用到指定按钮上
-- 处理五种绑定类型: spell(技能), macro(宏), custom(自定义), item(装备), general(通用)
-- 特殊处理:
--   - togglemenu_nocombat: 设置 menu 属性而非直接绑定
--   - spell: 构建宏文本实现技能施法，支持智能复活(sMaRt)和总是选目标(alwaysTargeting)
--   - 灵魂石: 自动 /targetlasttarget 避免切换目标
--   - 原始之波(Primordial Wave): 修复 Necrolord 萨满的技能名称显示
local function ApplyClickCastings(b)
    for i, t in pairs(clickCastingTable) do
        local bindKey = t[1]
        if strfind(bindKey, "SCROLL") then
            bindKey = GetMouseWheelBindKey(t[1])
        end

        if t[2] == "togglemenu_nocombat" then
            b:SetAttribute("menu", bindKey)
        ------------------------------------------------------------------
        --* 已修复：实际上载具（宠物按钮）无法选中的原因是没有 SetAttribute("toggleForVehicle", false)
        -- elseif Cell.isCata and t[2] == "target" then
        --     b:SetAttribute(bindKey, "macro")
        --     local attr = string.gsub(bindKey, "type", "macrotext")
        --     b:SetAttribute(attr, "/tar [@cell]")
        --     UpdatePlaceholder(b, attr)
        ------------------------------------------------------------------
        else
            b:SetAttribute(bindKey, t[2])
        end

        if t[2] == "spell" then
            local spellName, _, rank = F.GetSpellInfo(t[3])
            spellName = spellName or ""

            if rank then
                spellName = spellName .. F.GetRankSuffix(rank)
            end

            --! NOTE: fix Primordial Wave
            -- NOTE: only Necrolord shamans have this issue
            -- https://www.wowhead.com/spell=375982/primordial-wave#comments:id=5484251
            if t[3] == 428332 then
                local subtext = C_Spell.GetSpellSubtext(428332)
                spellName = spellName .. "(" .. (subtext or EXPANSION_NAME8) .. ")"
            end

            local condition = ""
            if not F.IsSoulstone(spellName) then
                condition = F.IsResurrectionForDead(spellName) and ",dead" or ",nodead"
            end

            local unit = Cell.isRetail and "@mouseover" or "@cell"

            -- "sMaRt" resurrection
            local sMaRt = ""
            if smartResurrection ~= "disabled" and not (F.IsResurrectionForDead(spellName) or F.IsSoulstone(spellName)) then
                if strfind(smartResurrection, "^normal") then
                    local normalResurrection = F.GetNormalResurrection(Cell.vars.playerClass)
                    if normalResurrection then
                        if Cell.isRetail then -- mass resurrections
                            for cond, spell in pairs(normalResurrection) do
                                sMaRt = sMaRt .. ";["..unit..",dead,nocombat,"..cond.."] "..spell
                            end
                        else
                            sMaRt = sMaRt .. ";["..unit..",dead,nocombat] "..normalResurrection
                        end
                    end
                end
                if strfind(smartResurrection, "combat$") then
                    if F.GetCombatResurrection(Cell.vars.playerClass) then
                        sMaRt = sMaRt .. ";["..unit..",dead,combat] "..F.GetCombatResurrection(Cell.vars.playerClass)
                    end
                end
            end

            --! NOTE: cancels the "blue glowing hand" cursor (cancel the target selection)
            local fix = t[3] == 370665 and "" or "\n/stopspelltarget"

            if (alwaysTargeting == "left" and bindKey == "type1") or alwaysTargeting == "any" then
                b:SetAttribute(bindKey, "macro")
                local attr = string.gsub(bindKey, "type", "macrotext")
                b:SetAttribute(attr, "/tar ["..unit.."]\n/cast ["..unit..condition.."] "..spellName..sMaRt..fix)
                if not Cell.isRetail then UpdatePlaceholder(b, attr) end
            else
                -- NOTE: "spell" is not ideal, 在无效/过远的目标上会处于“等待选中目标”的状态，即鼠标指针有一圈灰/蓝色材质
                -- local attr = string.gsub(bindKey, "type", "spell")
                -- b:SetAttribute(attr, spellName)
                b:SetAttribute(bindKey, "macro")
                local attr = string.gsub(bindKey, "type", "macrotext")
                if F.IsSoulstone(spellName) then
                    b:SetAttribute(attr, "/tar ["..unit.."]\n/cast ["..unit.."] "..spellName.."\n/targetlasttarget")
                else
                    b:SetAttribute(attr, "/cast ["..unit..condition.."] "..spellName..sMaRt..fix)
                end
                if not Cell.isRetail then UpdatePlaceholder(b, attr) end
            end
        elseif t[2] == "macro" then
            local attr = string.gsub(bindKey, "type", "macro")
            -- b:SetAttribute(attr, GetMacroIndexByName(t[3]))
            b:SetAttribute(attr, t[3])
        elseif t[2] == "custom" then
            b:SetAttribute(bindKey, "macro")
            local attr = string.gsub(bindKey, "type", "macrotext")
            b:SetAttribute(attr, t[3])
        else
            local attr = string.gsub(bindKey, "type", t[2])
            b:SetAttribute(attr, t[3])
        end
    end
end

-- 更新单个单位按钮的点击施法绑定
-- 执行三步操作: 清除旧绑定 -> 更新按键绑定snippet -> 重新应用数据库配置
-- 由 F.UpdateClickCastings 遍历所有单位按钮时调用
function F.UpdateClickCastOnFrame(frame, snippet)
    if frame then
        ClearClickCastings(frame)
        -- update bindingClicks
        frame:SetAttribute("snippet", snippet)
        SetBindingClicks(frame)
        -- load db and set attribute
        ApplyClickCastings(frame)
    end
end

-- 全局更新所有单位按钮的点击施法配置
-- 根据 useCommon 标志选择通用配置或专精配置
-- 同步更新 alwaysTargeting 和 smartResurrection 全局变量
-- 遍历所有单位按钮并逐个调用 UpdateClickCastOnFrame 刷新绑定
-- 参数: noReload=true 时不重新加载UI列表; onlyqueued=true 时仅更新队列中的按钮
function F.UpdateClickCastings(noReload, onlyqueued)
    F.Debug("|cff77ff77UpdateClickCastings:|r useCommon:", Cell.vars.clickCastings["useCommon"])
    clickCastingTable = Cell.vars.clickCastings["useCommon"] and Cell.vars.clickCastings["common"] or Cell.vars.clickCastings[Cell.vars.playerSpecID]

    -- FIXME: remove this determine statement
    if Cell.vars.clickCastings["alwaysTargeting"] then
        alwaysTargeting = Cell.vars.clickCastings["alwaysTargeting"][Cell.vars.clickCastings["useCommon"] and "common" or Cell.vars.playerSpecID]
    else
        alwaysTargeting = "disabled"
    end

    smartResurrection = Cell.vars.clickCastings["smartResurrection"]

    if not noReload then
        if clickCastingsTab:IsVisible() then
            LoadProfile(Cell.vars.clickCastings["useCommon"])
        else
            loaded = false
        end
    end

    local snippet = F.GetBindingSnippet()
    F.Debug(snippet)

    -- REVIEW:
    -- local clickFrames = Cell.clickCastFrames
    -- if onlyqueued then
    --     clickFrames = Cell.clickCastFrameQueue
    -- end
    -- for b, val in pairs(clickFrames) do
    --     Cell.clickCastFrameQueue[b] = nil
    --     -- clear if attribute already set
    --     ClearClickCastings(b)
    --     if val then
    --         -- update bindingClicks
    --         b:SetAttribute("snippet", snippet)
    --         SetBindingClicks(b)

    --         -- load db and set attribute
    --         ApplyClickCastings(b)
    --     end
    -- end

    F.IterateAllUnitButtons(function(b)
        F.UpdateClickCastOnFrame(b, snippet)
    end, false, true)

    previousClickCastings = F.Copy(clickCastingTable)
end
-- 注册全局点击施法更新回调，供其他模块通过 Cell.Fire("UpdateClickCastings") 触发
Cell.RegisterCallback("UpdateClickCastings", "UpdateClickCastings", F.UpdateClickCastings)

-- 队列式更新：仅更新已排队的按钮，不重新加载UI列表
local function UpdateQueuedClickCastings()
    UpdateClickCastings(true, true)
end
-- 注册队列式点击施法更新回调，供 Cell.Fire("UpdateQueuedClickCastings") 触发
Cell.RegisterCallback("UpdateQueuedClickCastings", "UpdateQueuedClickCastings", UpdateQueuedClickCastings)

-------------------------------------------------
-- 配置文件下拉面板
-- 提供"使用通用配置"和"各专精独立配置"两种模式切换
-- 切换配置模式后会触发 UpdateClickCastings 全局刷新
-------------------------------------------------
local profileDropdown

-- 创建配置文件选择面板 UI
-- 包含一个下拉菜单，支持"使用通用配置"和"各专精独立配置"两个选项
local function CreateProfilePane()
    local profilePane = Cell.CreateTitledPane(clickCastingsTab, L["Profiles"], 422, 50)
    profilePane:SetPoint("TOPLEFT", 5, -5)

    profileDropdown = Cell.CreateDropdown(profilePane, 412)
    profileDropdown:SetPoint("TOPLEFT", profilePane, "TOPLEFT", 5, -27)

    profileDropdown:SetItems({
        {
            ["text"] = L["Use common profile"],
            ["onClick"] = function()
                Cell.vars.clickCastings["useCommon"] = true
                Cell.Fire("UpdateClickCastings")
                LoadProfile(true)
            end,
        },
        {
            ["text"] = L["Use separate profile for each spec"],
            ["onClick"] = function()
                Cell.vars.clickCastings["useCommon"] = false
                Cell.Fire("UpdateClickCastings")
                LoadProfile(false)
            end,
        }
    })
end


-------------------------------------------------
-- "总是选目标"功能面板
-- 控制技能类型的点击施法是否自动先选中目标再施法
-- 三种模式: 禁用 / 仅左键技能 / 所有技能
-- 仅对 Spell 类型的绑定生效
-------------------------------------------------
local targetingDropdown

-- 创建"总是选目标"设置面板 UI
-- 下拉菜单包含: 禁用 / 仅左键技能 / 所有技能 三个选项
-- 仅对 Spell 类型绑定有效，切换时仅重载配置不刷新UI (noReload=true)
local function CreateTargetingPane()
    local targetingPane = Cell.CreateTitledPane(clickCastingsTab, L["Always Targeting"], 205, 50)
    targetingPane:SetPoint("TOPLEFT", clickCastingsTab, "TOPLEFT", 5, -70)

    targetingDropdown = Cell.CreateDropdown(targetingPane, 195)
    targetingDropdown:SetPoint("TOPLEFT", targetingPane, "TOPLEFT", 5, -27)

    local items = {
        {
            ["text"] = L["Disabled"],
            ["value"] = "disabled",
            ["onClick"] = function()
                local spec = Cell.vars.clickCastings["useCommon"] and "common" or Cell.vars.playerSpecID
                Cell.vars.clickCastings["alwaysTargeting"][spec] = "disabled"
                alwaysTargeting = "disabled"
                Cell.Fire("UpdateClickCastings", true)
            end,
        },
        {
            ["text"] = L["Left Spell"],
            ["value"] = "left",
            ["onClick"] = function()
                local spec = Cell.vars.clickCastings["useCommon"] and "common" or Cell.vars.playerSpecID
                Cell.vars.clickCastings["alwaysTargeting"][spec] = "left"
                alwaysTargeting = "left"
                Cell.Fire("UpdateClickCastings", true)
            end,
        },
        {
            ["text"] = L["Any Spells"],
            ["value"] = "any",
            ["onClick"] = function()
                local spec = Cell.vars.clickCastings["useCommon"] and "common" or Cell.vars.playerSpecID
                Cell.vars.clickCastings["alwaysTargeting"][spec] = "any"
                alwaysTargeting = "any"
                Cell.Fire("UpdateClickCastings", true)
            end,
        }
    }

    targetingDropdown:SetItems(items)
    Cell.SetTooltips(targetingDropdown, "ANCHOR_TOPLEFT", 0, 2, L["Always Targeting"], L["Only available for Spells"])
end

-------------------------------------------------
-- 智能复活功能面板 (sMaRt Resurrection)
-- 在目标死亡时自动将技能类型的点击施法替换为对应的复活技能
-- 三种模式: 禁用 / 常规复活 / 常规+战斗中复活
-- 会智能判断目标状态(dead/nodead)和战斗状态(combat/nocombat)来选择合适的复活法术
-------------------------------------------------
local smartResDropdown

-- 创建智能复活设置面板 UI
-- 下拉菜单包含: 禁用 / 常规复活 / 常规+战斗中复活 三个选项
local function CreateSmartResPane()
    local smartResPane = Cell.CreateTitledPane(clickCastingsTab, L["Smart Resurrection"], 205, 50)
    smartResPane:SetPoint("TOPLEFT", clickCastingsTab, "TOPLEFT", 222, -70)

    smartResDropdown = Cell.CreateDropdown(smartResPane, 195)
    smartResDropdown:SetPoint("TOPLEFT", smartResPane, "TOPLEFT", 5, -27)

    local items = {
        {
            ["text"] = L["Disabled"],
            ["value"] = "disabled",
            ["onClick"] = function()
                Cell.vars.clickCastings["smartResurrection"] = "disabled"
                Cell.Fire("UpdateClickCastings", true)
            end,
        },
        {
            ["text"] = L["Normal"],
            ["value"] = "normal",
            ["onClick"] = function()
                Cell.vars.clickCastings["smartResurrection"] = "normal"
                Cell.Fire("UpdateClickCastings", true)
            end,
        } ,
        {
            ["text"] = L["Normal + Combat Res"],
            ["value"] = "normal+combat",
            ["onClick"] = function()
                Cell.vars.clickCastings["smartResurrection"] = "normal+combat"
                Cell.Fire("UpdateClickCastings", true)
            end,
        }
    }

    smartResDropdown:SetItems(items)
    Cell.SetTooltips(smartResDropdown, "ANCHOR_TOPLEFT", 0, 2, L["Smart Resurrection"], L["Replace click-castings of Spell type with resurrection spells on dead units"])
end

-------------------------------------------------
-- menu
-------------------------------------------------
local menu = Cell.menu
local bindingButton

-- 检查指定索引的绑定条目是否有实际修改
-- 如果 changed[index] 中只有按钮引用（长度为1），说明没有实质改动，清除修改标记
-- 如果还有其他字段（modifier/bindKey/bindType/bindAction），保留修改标记
local function CheckChanged(index, b)
    if F.Getn(changed[index]) == 1 then -- nothing changed
        changed[index] = nil
        b:SetChanged(false)
    else
        b:SetChanged(true)
    end
end

-- 显示按键绑定选择菜单（弹出按键捕获按钮）
-- 允许用户按下任意修饰键+按键组合来重新绑定该条目的触发键
-- 已标记为删除的条目不响应此操作
-- 通过 Cell.CreateBindingButton 创建的 bindingButton 来捕获按键输入
local function ShowBindingMenu(index, b)
    -- if already in deleted, do nothing
    if deleted[index] then return end

    P.ClearPoints(bindingButton)
    P.Point(bindingButton, "TOPLEFT", b.keyGrid)
    bindingButton:Show()
    menu:Hide()

    bindingButton:SetFunc(function(modifier, key)
        F.Debug(modifier, key)
        b.keyGrid:SetText(GetBindingDisplay(modifier, key))

        changed[index] = changed[index] or {b}
        -- check modifier
        if modifier ~= b.modifier then
            changed[index]["modifier"] = modifier
        else
            changed[index]["modifier"] = nil
        end
        -- check bindKey
        if key ~= b.bindKey then
            changed[index]["bindKey"] = key
        else
            changed[index]["bindKey"] = nil
        end

        CheckChanged(index, b)
        CheckChanges()
    end)
end

-- 显示绑定类型选择菜单
-- 提供五种类型: General(通用), Spell(技能), Macro(宏), Custom(自定义), Item(装备)
-- 切换类型时会自动重置 action 字段为该类型的默认值
-- 如果菜单已定位到当前按钮则切换显示/隐藏
local function ShowTypesMenu(index, b)
    local parent = select(2, menu:GetPoint(1))
    if parent == b.typeGrid and menu:IsShown() then
        menu:Hide()
        return
    end

    -- if already in deleted, do nothing
    if deleted[index] then return end

    local items = {
        {
            ["text"] = L["General"],
            ["onClick"] = function()
                b.typeGrid:SetText(L["General"])
                if clickCastingsTab.popupEditBox then clickCastingsTab.popupEditBox:Hide() end

                changed[index] = changed[index] or {b}
                -- check type
                if b.bindType ~= "general" then
                    changed[index]["bindType"] = "general"
                    changed[index]["bindAction"] = "target"
                    b.actionGrid:SetText(L["target"])
                else
                    changed[index]["bindType"] = nil
                    changed[index]["bindAction"] = nil
                    b.actionGrid:SetText(L[b.bindAction])
                end
                CheckChanged(index, b)
                CheckChanges()
                b:HideIcon()
            end,
        }, {
            ["text"] = L["Spell"],
            ["onClick"] = function()
                b.typeGrid:SetText(L["Spell"])
                if clickCastingsTab.popupEditBox then clickCastingsTab.popupEditBox:Hide() end

                changed[index] = changed[index] or {b}
                -- check type
                if b.bindType ~= "spell" then
                    changed[index]["bindType"] = "spell"
                    changed[index]["bindAction"] = ""
                    b.actionGrid:SetText("")
                    b:HideIcon()
                else
                    changed[index]["bindType"] = nil
                    changed[index]["bindAction"] = nil
                    b.actionGrid:SetText(b.bindActionDisplay)
                    b:ShowSpellIcon(b.bindAction)
                end
                CheckChanged(index, b)
                CheckChanges()
            end,
        }, {
            ["text"] = L["Macro"],
            ["onClick"] = function()
                b.typeGrid:SetText(L["Macro"])
                if clickCastingsTab.popupEditBox then clickCastingsTab.popupEditBox:Hide() end

                changed[index] = changed[index] or {b}
                -- check type
                if b.bindType ~= "macro" then
                    changed[index]["bindType"] = "macro"
                    changed[index]["bindAction"] = ""
                    b.actionGrid:SetText("")
                    b:HideIcon()
                else
                    changed[index]["bindType"] = nil
                    changed[index]["bindAction"] = nil
                    if b.bindAction == "" then
                        b.actionGrid:SetText("")
                        b:HideIcon()
                    else
                        b.actionGrid:SetText(b.bindActionDisplay)
                        b:ShowMacroIcon(b.bindAction)
                    end
                end
                CheckChanged(index, b)
                CheckChanges()
            end,
        }, {
            ["text"] = L["Custom"],
            ["onClick"] = function()
                b.typeGrid:SetText(L["Custom"])
                if clickCastingsTab.popupEditBox then clickCastingsTab.popupEditBox:Hide() end

                changed[index] = changed[index] or {b}
                -- check type
                if b.bindType ~= "custom" then
                    changed[index]["bindType"] = "custom"
                    changed[index]["bindAction"] = ""
                    b.actionGrid:SetText("")
                    b:HideIcon()
                else
                    changed[index]["bindType"] = nil
                    changed[index]["bindAction"] = nil
                    b.actionGrid:SetText(b.bindAction)
                    b:HideIcon()
                end
                CheckChanged(index, b)
                CheckChanges()
            end,
        }, {
            ["text"] = L["Item"],
            ["onClick"] = function()
                b.typeGrid:SetText(L["Item"])
                if clickCastingsTab.popupEditBox then clickCastingsTab.popupEditBox:Hide() end

                changed[index] = changed[index] or {b}
                -- check type
                if b.bindType ~= "item" then
                    changed[index]["bindType"] = "item"
                    changed[index]["bindAction"] = ""
                    b.actionGrid:SetText("")
                    b:HideIcon()
                else
                    changed[index]["bindType"] = nil
                    changed[index]["bindAction"] = nil
                    b.actionGrid:SetText(b.bindActionDisplay)
                    b:ShowItemIcon(b.bindAction)
                end
                CheckChanged(index, b)
                CheckChanges()
            end,
        },
        -- {
        --     ["text"] = L["Click"],
        --     ["onClick"] = function()
        --         b.typeGrid:SetText(L["Click"])
        --         if clickCastingsTab.popupEditBox then clickCastingsTab.popupEditBox:Hide() end

        --         changed[index] = changed[index] or {b}
        --         -- check type
        --         if b.bindType ~= "click" then
        --             changed[index]["bindType"] = "click"
        --             changed[index]["bindAction"] = ""
        --             b.actionGrid:SetText("")
        --             b:HideIcon()
        --         else
        --             changed[index]["bindType"] = nil
        --             changed[index]["bindAction"] = nil
        --             b.actionGrid:SetText(b.bindActionDisplay)
        --             b:ShowSpellIcon(b.bindAction)
        --         end
        --         CheckChanged(index, b)
        --         CheckChanges()
        --     end,
        -- }
    }

    menu:SetItems(items)
    P.ClearPoints(menu)
    P.Point(menu, "TOPLEFT", b.typeGrid, "BOTTOMLEFT", 0, -1)
    menu:SetWidths(70)
    menu:ShowMenu()
    bindingButton:Hide()
end

-- 显示绑定动作选择菜单（根据当前绑定类型动态生成菜单项）
-- General:  目标/焦点/协助/菜单/非战斗菜单
-- Spell:    输入技能ID + 预设技能列表
-- Macro:    所有角色宏列表
-- Custom:   自定义宏文本编辑 + 特殊动作按钮 + 灵魂石(术士)
-- Item:     装备栏位 + 可用物品列表
-- 如果菜单已定位到当前按钮则切换显示/隐藏
local function ShowActionsMenu(index, b)
    local parent = select(2, menu:GetPoint(1))
    if parent == b.actionGrid and menu:IsShown() then
        menu:Hide()
        return
    end

    -- if already in deleted, do nothing
    if deleted[index] then return end

    local items

    local bindType
    if changed[index] and changed[index]["bindType"] then -- changed
        bindType = changed[index]["bindType"]
    else -- use original
        bindType = b.bindType
    end

    if bindType == "general" then
        items = {
            {
                ["text"] = L["Target"],
                ["onClick"] = function()
                    changed[index] = changed[index] or {b}
                    if b.bindAction ~= "target" then
                        changed[index]["bindAction"] = "target"
                        b.actionGrid:SetText(L["Target"])
                    else
                        changed[index]["bindAction"] = nil
                        b.actionGrid:SetText(L[b.bindAction])
                    end
                    CheckChanged(index, b)
                    CheckChanges()
                end,
            },
            {
                ["text"] = L["Focus"],
                ["onClick"] = function()
                    changed[index] = changed[index] or {b}
                    if b.bindAction ~= "focus" then
                        changed[index]["bindAction"] = "focus"
                        b.actionGrid:SetText(L["Focus"])
                    else
                        changed[index]["bindAction"] = nil
                        b.actionGrid:SetText(L[b.bindAction])
                    end
                    CheckChanged(index, b)
                    CheckChanges()
                end,
            },
            {
                ["text"] = L["Assist"],
                ["onClick"] = function()
                    changed[index] = changed[index] or {b}
                    if b.bindAction ~= "assist" then
                        changed[index]["bindAction"] = "assist"
                        b.actionGrid:SetText(L["Assist"])
                    else
                        changed[index]["bindAction"] = nil
                        b.actionGrid:SetText(L[b.bindAction])
                    end
                    CheckChanged(index, b)
                    CheckChanges()
                end,
            },
            {
                ["text"] = L["Menu"],
                ["onClick"] = function()
                    changed[index] = changed[index] or {b}
                    if b.bindAction ~= "togglemenu" then
                        changed[index]["bindAction"] = "togglemenu"
                        b.actionGrid:SetText(L["Menu"])
                    else
                        changed[index]["bindAction"] = nil
                        b.actionGrid:SetText(L[b.bindAction])
                    end
                    CheckChanged(index, b)
                    CheckChanges()
                end,
            },
            {
                ["text"] = L["togglemenu_nocombat"],
                ["onClick"] = function()
                    changed[index] = changed[index] or {b}
                    if b.bindAction ~= "togglemenu_nocombat" then
                        changed[index]["bindAction"] = "togglemenu_nocombat"
                        b.actionGrid:SetText(L["togglemenu_nocombat"])
                    else
                        changed[index]["bindAction"] = nil
                        b.actionGrid:SetText(L[b.bindAction])
                    end
                    CheckChanged(index, b)
                    CheckChanges()
                end,
            },
        }

    elseif bindType == "custom" then
        items = {}
        tinsert(items, {
            ["text"] = L["Edit"],
            ["onClick"] = function()
                local peb = Cell.CreatePopupEditBox(clickCastingsTab, function(text)
                    changed[index] = changed[index] or {b}
                    if b.bindAction ~= text then
                        changed[index]["bindAction"] = text
                        b.actionGrid:SetText(text)
                    else
                        changed[index]["bindAction"] = nil
                        b.actionGrid:SetText(b.bindAction)
                    end
                    CheckChanged(index, b)
                    CheckChanges()
                end, true)
                peb:SetPoint("TOPLEFT", b.actionGrid)
                peb:SetPoint("TOPRIGHT", b.actionGrid)
                P.Height(peb, 20)
                -- peb:SetPoint("BOTTOMRIGHT", b.actionGrid)
                peb:SetTips("|cffababab"..L["Shift+Enter: add a new line"].."\n"..L["Enter: apply\nESC: discard"])
                if b.bindType == "custom" then
                    if changed[index] and changed[index]["bindAction"] then
                        peb:ShowEditBox(changed[index]["bindAction"])
                    else
                        peb:ShowEditBox(b.bindAction)
                    end
                elseif changed[index] and changed[index]["bindType"] == "custom" then
                    if changed[index]["bindAction"] then
                        peb:ShowEditBox(changed[index]["bindAction"])
                    else
                        peb:ShowEditBox("")
                    end
                else
                    peb:ShowEditBox("")
                end
                peb:SetNumeric(false)
            end,
        })
        tinsert(items, {
            ["text"] = L["Extra Action Button"],
            ["onClick"] = function()
                changed[index] = changed[index] or {b}
                local macrotext = "/stopcasting\n/target mouseover\n/click ExtraActionButton1\n/targetlasttarget"
                if b.bindAction ~= macrotext then
                    changed[index]["bindAction"] = macrotext
                    b.actionGrid:SetText(macrotext)
                else
                    changed[index]["bindAction"] = nil
                    b.actionGrid:SetText(b.bindAction)
                end
                CheckChanged(index, b)
                CheckChanges()
            end,
        })

        if (Cell.isVanilla or Cell.isTBC or Cell.isWrath or Cell.isCata) and Cell.vars.playerClass == "WARLOCK" then
            local soulstoneID
            if Cell.isVanilla then
                soulstoneID = 16896
            elseif Cell.isTBC then
                soulstoneID = 22116
            else -- wrath & cata
                soulstoneID = 36895
            end

            tinsert(items, {
                ["text"] = F.GetSpellInfo(20707),
                ["onClick"] = function()
                    changed[index] = changed[index] or {b}

                    local macrotext = "/stopcasting\n/target mouseover\n/use item:"..soulstoneID.."\n/targetlasttarget"
                    if b.bindAction ~= macrotext then
                        changed[index]["bindAction"] = macrotext
                        b.actionGrid:SetText(macrotext)
                    else
                        changed[index]["bindAction"] = nil
                        b.actionGrid:SetText(b.bindAction)
                    end
                    CheckChanged(index, b)
                    CheckChanges()
                end,
            })
        end
    elseif bindType == "macro" then
        items = {}
        for _, i in pairs(F.GetMacroIndices()) do
            local name, icon = GetMacroInfo(i)
            if name then
                tinsert(items, {
                    ["text"] = name,
                    ["icon"] = icon,
                    ["onClick"] = function()
                        changed[index] = changed[index] or {b}
                        if b.bindAction ~= name then
                            changed[index]["bindAction"] = name
                        else
                            changed[index]["bindAction"] = nil
                        end
                        b.actionGrid:SetText(name)
                        b:ShowIcon(icon)
                        CheckChanged(index, b)
                        CheckChanges()
                    end,
                })
            end
        end

    elseif bindType == "item" then
        items = {}

        for _, slot in ipairs({13, 14, 6, 9, 10}) do
            tinsert(items, {
                ["text"] = slotNames[slot],
                ["onClick"] = function()
                    changed[index] = changed[index] or {b}
                    if b.bindAction ~= slot then
                        changed[index]["bindAction"] = slot
                    else
                        changed[index]["bindAction"] = nil
                    end
                    b.actionGrid:SetText(slotNames[slot])
                    b:ShowItemIcon(slot)
                    CheckChanged(index, b)
                    CheckChanges()
                end,
            })
        end

        for slot = 1, 17 do
            local itemId = GetInventoryItemID("player", slot)
            if itemId and C_Item.IsUsableItem(itemId) then
                local text = GetInventoryItemLink("player", slot) or ""
                text = string.gsub(text, "[%[%]]", "")

                tinsert(items, {
                    ["text"] = text,
                    ["icon"] = GetInventoryItemTexture("player", slot),
                    ["onClick"] = function()
                        changed[index] = changed[index] or {b}
                        if b.bindAction ~= slot then
                            changed[index]["bindAction"] = slot
                        else
                            changed[index]["bindAction"] = nil
                        end
                        b.actionGrid:SetText(slotNames[slot])
                        b:ShowItemIcon(slot)
                        CheckChanged(index, b)
                        CheckChanges()
                    end,
                })
            end
        end

    -- elseif bindType == "click" then
    --     items = {{
    --             ["text"] = "ExtraActionButton1",
    --             ["onClick"] = function()
    --                 changed[index] = changed[index] or {b}
    --                 if b.bindAction ~= "ExtraActionButton1" then
    --                     changed[index]["bindAction"] = "ExtraActionButton1"
    --                     b.actionGrid:SetText("ExtraActionButton1")
    --                 else
    --                     changed[index]["bindAction"] = nil
    --                     b.actionGrid:SetText(b.bindAction)
    --                 end
    --                 CheckChanged(index, b)
    --                 CheckChanges()
    --             end,
    --     }}

    else -- spell
        items = {
            {
                ["text"] = L["Edit"],
                ["onClick"] = function()
                    local peb = Cell.CreatePopupEditBox(clickCastingsTab, function(text)
                        changed[index] = changed[index] or {b}
                        text = tonumber(text) or ""
                        if b.bindAction ~= text then
                            changed[index]["bindAction"] = text
                            if text == "" then
                                b.actionGrid:SetText("")
                                b:HideIcon()
                            else
                                b.actionGrid:SetText(F.GetSpellInfo(text) or "|cFFFF3030"..L["Invalid"])
                                b:ShowSpellIcon(text)
                            end
                        else
                            changed[index]["bindAction"] = nil
                            if text == "" then
                                b.actionGrid:SetText("")
                                b:HideIcon()
                            else
                                b.actionGrid:SetText(b.bindActionDisplay)
                                b:ShowSpellIcon(b.bindAction)
                            end
                        end
                        CheckChanged(index, b)
                        CheckChanges()
                    end)
                    P.Point(peb, "TOPLEFT", b.actionGrid)
                    P.Point(peb, "BOTTOMRIGHT", b.actionGrid)
                    peb:SetTips("|cffababab"..L["Input spell id"].."\n"..L["Enter: apply\nESC: discard"])
                    peb:ShowEditBox(b.bindAction or "")
                    peb:SetNumeric(true)
                    if not peb.tooltipAdded then
                        peb.tooltipAdded = true
                        peb:SetScript("OnTextChanged", function()
                            local spellId = tonumber(peb:GetText())
                            if not spellId then
                                CellSpellTooltip:Hide()
                                return
                            end

                            local name, icon = F.GetSpellInfo(spellId)
                            if not name then
                                CellSpellTooltip:Hide()
                                return
                            end

                            CellSpellTooltip:SetOwner(peb, "ANCHOR_NONE")
                            CellSpellTooltip:SetPoint("TOPLEFT", peb, "BOTTOMLEFT", 0, -1)
                            CellSpellTooltip:SetSpellByID(spellId, icon)
                            CellSpellTooltip:Show()
                        end)
                        peb:HookScript("OnHide", function()
                            CellSpellTooltip:Hide()
                        end)
                    end
                end,
            },
        }

        -- default spells
        local spells = F.GetClickCastingSpellList(Cell.vars.playerClass, Cell.vars.playerSpecID)
        -- texplore(spells)
        -- {icon, name, type(C/S/P), id}

        for _, t in ipairs(spells) do
            local spellItem = {
                --! CANNOT use "|T****|t", if too many items (over 10?), it will cause game stuck!! I don't know why!
                -- ["text"] = "|T"..t[1]..":12:12:0:0:12:12:1:11:1:11|t "..t[2]..(t[3] and (" |cff777777("..t[3]..")") or ""),
                ["text"] = t[2]..(t[3] and (" |cff777777("..t[3]..")") or ""),
                ["icon"] = t[1],
                ["onClick"] = function()
                    changed[index] = changed[index] or {b}
                    if b.bindAction ~= t[4] then
                        changed[index]["bindAction"] = t[4]
                        b.actionGrid:SetText(t[2])
                        b:ShowSpellIcon(t[4])
                    else
                        changed[index]["bindAction"] = nil
                        b.actionGrid:SetText(b.bindActionDisplay)
                        b:ShowSpellIcon(b.bindAction)
                    end
                    CheckChanged(index, b)
                    CheckChanges()
                end
            }

            if t[5] and t[5] >= 1 then
                spellItem.children = {}
                for i = 1, t[5] do
                    tinsert(spellItem.children, {
                        ["text"] = i,
                        ["onClick"] = function()
                            changed[index] = changed[index] or {b}
                            if b.bindAction ~= t[4]..":"..i then
                                changed[index]["bindAction"] = t[4]..":"..i
                                b.actionGrid:SetText(t[2].."|cff777777("..i..")|r")
                                b:ShowSpellIcon(t[4])
                            else
                                changed[index]["bindAction"] = nil
                                b.actionGrid:SetText(b.bindActionDisplay)
                                b:ShowSpellIcon(b.bindAction)
                            end
                            CheckChanged(index, b)
                            CheckChanges()
                        end
                    })
                end
            end

            tinsert(items, spellItem)
        end
    end

    menu:SetItems(items, 15)
    menu:SetWidths(b.actionGrid:GetWidth(), 35)
    P.ClearPoints(menu)
    P.Point(menu, "TOPLEFT", b.actionGrid, "BOTTOMLEFT", 0, -1)
    menu:ShowMenu()
    bindingButton:Hide()
end

-------------------------------------------------
-- 绑定列表主面板
-- 显示当前配置的所有点击施法绑定条目，支持新建/编辑/删除/排序操作
-- 每行条目包含: 按键列 / 类型列 / 动作列，点击可弹出对应菜单进行修改
-- 右键点击条目可标记删除（半透明显示）
-- 支持左键拖拽排序
-------------------------------------------------
local CreateBindingListButton
local last

local function UpdateCurrentText(isCommon)
    if isCommon then
        listPane:SetTitle(L["Current Profile"]..": "..L["Common"])
    else
        if Cell.isRetail or Cell.isMists then
            listPane:SetTitle(L["Current Profile"]..": ".."|T"..Cell.vars.playerSpecIcon..":12:12:0:1:12:12:1:11:1:11|t "..Cell.vars.playerSpecName)
        elseif Cell.isCata or Cell.isWrath or Cell.isTBC or Cell.isVanilla then
            local name, icon = F.GetActiveTalentInfo()
            listPane:SetTitle(L["Current Profile"]..": ".."|T"..icon..":12:12:0:1:12:12:1:11:1:11|t "..name)
        end
    end
end

-- 创建绑定列表主面板 UI
-- 包含: 标题栏（显示当前配置名称）+ 提示按钮 + 导入/导出按钮 + 绑定条目列表 + 新建/保存/取消按钮
-- 列表使用滚动框架，支持条目拖拽排序
local function CreateListPane()
    listPane = Cell.CreateTitledPane(clickCastingsTab, L["Current Profile"], 422, 451)
    listPane:SetPoint("BOTTOMLEFT", clickCastingsTab, 5, 5)

    -- 操作提示按钮（悬停显示帮助信息）
    local hint = Cell.CreateButton(listPane, nil, "accent-hover", {17, 17}, nil, nil, nil, nil, nil,
        L["Click-Castings"],
        "|cffffb5c5"..L["Left-Click"]..":|r "..strlower(L["Edit"]),
        "|cffffb5c5"..L["Right-Click"]..":|r "..strlower(L["Delete"]),
        "|cffffb5c5"..L["Left-Drag"]..":|r "..L["change the order"]
    )
    hint:SetPoint("TOPRIGHT")
    hint.tex = hint:CreateTexture(nil, "ARTWORK")
    hint.tex:SetAllPoints(hint)
    hint.tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\info2.tga")

    -- 导出按钮：将当前点击施法配置导出为可分享的字符串
    local export = Cell.CreateButton(listPane, nil, "accent-hover", {27, 17}, nil, nil, nil, nil, nil, L["Export"])
    export:SetPoint("TOPRIGHT", hint, "TOPLEFT", -1, 0)
    export:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\export", {15, 15}, {"CENTER", 0, 0})
    export:SetScript("OnClick", function()
        F.ShowClickCastingExportFrame(clickCastingTable)
    end)

    -- 导入按钮：从分享字符串导入点击施法配置
    local import = Cell.CreateButton(listPane, nil, "accent-hover", {27, 17}, nil, nil, nil, nil, nil, L["Import"])
    import:SetPoint("TOPRIGHT", export, "TOPLEFT", -1, 0)
    import:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\import", {15, 15}, {"CENTER", 0, 0})
    import:SetScript("OnClick", function()
        F.ShowClickCastingImportFrame()
    end)

    -- 按键绑定捕获按钮：用于捕获用户按下的修饰键+按键组合
    bindingButton = Cell.CreateBindingButton(listPane, 130)

    -- 绑定条目容器框架
    bindingsFrame = Cell.CreateFrame("ClickCastingsTab_BindingsFrame", listPane)
    bindingsFrame:SetPoint("TOPLEFT", 0, -27)
    bindingsFrame:SetPoint("BOTTOMRIGHT", 0, 19)
    bindingsFrame:Show()

    Cell.CreateScrollFrame(bindingsFrame, -5, 5)
    bindingsFrame.scrollFrame:SetScrollStep(25)

    -- 底部操作按钮区域: 新建 / 保存 / 取消
    -- 新建：在列表末尾添加一条未绑定的空白条目
    local newBtn = Cell.CreateButton(listPane, L["New"], "blue-hover", {141, 20})
    newBtn:SetPoint("TOPLEFT", bindingsFrame, "BOTTOMLEFT", 0, P.Scale(1))
    newBtn:SetScript("OnClick", function()
        local index = #clickCastingTable+1
        local b = CreateBindingListButton("", "notBound", "general", "target", index)
        tinsert(clickCastingTable, EncodeDB("", "notBound", "general", "target"))

        b:SetPoint("TOP", 0, P.Scale(-20)*(index-1)+P.Scale(-5)*(index-1))

        menu:Hide()
        bindingButton:Hide()

        -- scroll
        bindingsFrame.scrollFrame:SetContentHeight(P.Scale(20), #clickCastingTable, P.Scale(5))
        bindingsFrame.scrollFrame:ScrollToBottom()
    end)

    -- 保存按钮：将 deleted（删除）和 changed（修改）合并写入数据库，然后触发全局刷新
    saveBtn = Cell.CreateButton(listPane, L["Save"], "green-hover", {142, 20})
    saveBtn:SetPoint("TOPLEFT", newBtn, "TOPRIGHT", P.Scale(-1), 0)
    saveBtn:SetEnabled(false)
    saveBtn:SetScript("OnClick", function()
        -- deleted
        local deletedIndices = {}
        for index, b in pairs(deleted) do
            if changed[index] then changed[index] = nil end -- if duplicated in changed, remove it
            -- clickCastingTable[index] = nil -- update db
            tinsert(deletedIndices, index)
        end

        -- changed
        for index, t in pairs(changed) do
            local b = t[1]
            local modifier = t["modifier"] or b.modifier
            local bindKey = t["bindKey"] or b.bindKey
            local bindType = t["bindType"] or b.bindType
            local bindAction = t["bindAction"] or b.bindAction
            clickCastingTable[index] = EncodeDB(modifier, bindKey, bindType, bindAction)
            -- texplore(clickCastingTable[index])
        end

        -- delete!
        table.sort(deletedIndices)
        for i, index in pairs(deletedIndices) do
            tremove(clickCastingTable, index-i+1) -- continuous table index
        end

        -- reload
        Cell.Fire("UpdateClickCastings")
        wipe(deleted)
        wipe(changed)
        CheckChanges()
        menu:Hide()
        if clickCastingsTab.popupEditBox then clickCastingsTab.popupEditBox:Hide() end
    end)

    -- 取消按钮：放弃所有未保存的修改，恢复条目到初始状态
    cancelBtn = Cell.CreateButton(listPane, L["Cancel"], "red-hover", {141, 20})
    cancelBtn:SetPoint("TOPLEFT", saveBtn, "TOPRIGHT", P.Scale(-1), 0)
    cancelBtn:SetEnabled(false)
    cancelBtn:SetScript("OnClick", function()
        -- deleted
        for index, b in pairs(deleted) do
            b:SetAlpha(1)
            b:SetChanged(false)
        end
        -- changed
        for index, t in pairs(changed) do
            t[1]:SetChanged(false)

            t[1].keyGrid:SetText(GetBindingDisplay(t[1].modifier, t[1].bindKey))
            t[1].typeGrid:SetText(L[F.UpperFirst(t[1].bindType)])
            t[1].actionGrid:SetText(t[1].bindActionDisplay)
            -- restore icon
            if t[1].bindType == "spell" then
                t[1]:ShowSpellIcon(t[1].bindAction)
            elseif t[1].bindType == "item" then
                t[1]:ShowItemIcon(t[1].bindAction)
            elseif t[1].bindType == "macro" then
                t[1]:ShowMacroIcon(t[1].bindAction)
            else
                t[1]:HideIcon()
            end
        end
        wipe(deleted)
        wipe(changed)
        CheckChanges()
        menu:Hide()
        if clickCastingsTab.popupEditBox then clickCastingsTab.popupEditBox:Hide() end
    end)
end

-------------------------------------------------
-- 绑定条目列表工厂函数
-- 创建或复用列表按钮，设置其显示内容（按键、类型、动作文本和图标）
-- 为每个子区域（keyGrid/typeGrid/actionGrid）绑定点击事件以弹出对应编辑菜单
-- 右键点击整行可标记/取消删除
-------------------------------------------------
CreateBindingListButton = function(modifier, bindKey, bindType, bindAction, i)
    if not listButtons[i] then
        listButtons[i] = Cell.CreateBindingListButton(bindingsFrame.scrollFrame.content, "", "", "", "")
    end
    local b = listButtons[i]
    b:SetParent(bindingsFrame.scrollFrame.content)
    b:SetAlpha(1)
    b:SetChanged(false)
    b:Show()

    b.modifier, b.bindKey, b.bindType, b.bindAction = modifier, bindKey, bindType, bindAction
    b.clickCastingIndex = i

    b.typeGrid:SetText(L[F.UpperFirst(bindType)])

    if bindType == "general" then
        b.bindActionDisplay = L[bindAction]
        b:HideIcon()
    elseif bindType == "spell" then
        if bindAction ~= "" then
            if strfind(bindAction, ":") then
                local spellId, rank = strsplit(":", bindAction)
                b.bindActionDisplay = F.GetSpellInfo(spellId).."|cff777777("..rank..")|r"
                b:ShowSpellIcon(spellId)
            elseif type(bindAction) ~= "number" then
                b.bindActionDisplay = "|cFFFF3030"..L["Invalid"]
                b:ShowSpellIcon()
            else
                b.bindActionDisplay = F.GetSpellInfo(bindAction) or "|cFFFF3030"..L["Invalid"]
                b:ShowSpellIcon(bindAction)
            end
        else
            b.bindActionDisplay = ""
            b:HideIcon()
        end
    elseif bindType == "item" then
        if bindAction ~= "" then
            b.bindActionDisplay = slotNames[bindAction]
            b:ShowItemIcon(bindAction)
        else
            b.bindActionDisplay = ""
            b:HideIcon()
        end
    elseif bindType == "macro" then
        -- NOTE: GetMacroInfo("name") seems no returns
        local name, icon = GetMacroInfo(GetMacroIndexByName(bindAction))
        if name then
            b.bindActionDisplay = name
            b:ShowIcon(icon)
        elseif bindAction ~= "" then -- maybe deleted
            b.bindActionDisplay = bindAction
            b:ShowIcon()
        else -- not bound
            b.bindActionDisplay = ""
            b:HideIcon()
        end
    elseif bindType == "custom" then
        b.bindActionDisplay = bindAction
        b:HideIcon()
        b.typeGrid:SetText(L["Custom"])
    end

    b.keyGrid:SetText(GetBindingDisplay(modifier, bindKey))
    b.actionGrid:SetText(b.bindActionDisplay)

    b:SetPoint("LEFT", 5, 0)
    b:SetPoint("RIGHT", -5, 0)

    b:SetScript("OnClick", function(self, button, down)
        if button == "RightButton" then
            if deleted[i] then
                deleted[i] = nil
                if not changed[i] then
                    b:SetChanged(false)
                end
                b:SetAlpha(1)
            else
                deleted[i] = b
                b:SetChanged(true)
                b:SetAlpha(0.3)
            end
            CheckChanges()
        end
    end)

    b.keyGrid:SetScript("OnClick", function(self, button, down)
        if button == "RightButton" then
            b:GetScript("OnClick")(b, button, down)
        else
            ShowBindingMenu(i, b)
        end
    end)

    b.typeGrid:SetScript("OnClick", function(self, button, down)
        if button == "RightButton" then
            b:GetScript("OnClick")(b, button, down)
        else
            ShowTypesMenu(i, b)
        end
    end)

    b.actionGrid:SetScript("OnClick", function(self, button, down)
        if button == "RightButton" then
            b:GetScript("OnClick")(b, button, down)
        else
            ShowActionsMenu(i, b)
        end
    end)

    return b
end

-- 加载配置文件到 UI 列表
-- 清空当前列表，解码数据库条目并逐行创建列表按钮
-- 设置滚动区域内容高度，清理修改/删除缓存
-- isCommon: true=通用配置, false=当前专精配置
LoadProfile = function(isCommon)
    targetingDropdown:SetSelectedValue(alwaysTargeting)
    UpdateCurrentText(isCommon)

    last = nil
    bindingsFrame.scrollFrame:Reset()
    -- F.Debug("-- Load clickCastings start --------------")
    for i, t in pairs(clickCastingTable) do
        -- F.Debug(table.concat(t, ","))
        local modifier, bindKey, bindType, bindAction = DecodeDB(t)
        local b = CreateBindingListButton(modifier, bindKey, bindType, bindAction, i)

        b:SetPoint("TOP", 0, P.Scale(-20)*(i-1)+P.Scale(-5)*(i-1))
    end
    -- hide unused
    for i = #clickCastingTable+1, #listButtons do
        listButtons[i]:Hide()
    end
    -- F.Debug("-- Load clickCastings end ----------------")
    bindingsFrame.scrollFrame:SetContentHeight(P.Scale(20), #clickCastingTable, P.Scale(5))
    menu:Hide()
    wipe(deleted)
    wipe(changed)
end

-- 拖动排序处理：将点击施法条目从 from 位置移动到 to 位置
-- 修改数据库数组，然后重新加载列表 UI
function F.MoveClickCastings(from, to)
    F.Debug(from, "->", to)
    if from and to then
        local temp = clickCastingTable[from]
        tremove(clickCastingTable, from)
        tinsert(clickCastingTable, to, temp)
    end
    LoadProfile(Cell.vars.clickCastings["useCommon"])
end

-------------------------------------------------
-- check conflicts
-------------------------------------------------
-- 检查点击施法与游戏自带快捷施法（如自动自我施法）之间的按键冲突
-- 如果检测到冲突，弹出确认对话框询问用户是否移除冲突的快捷键设置
-- 正式服通过 Settings API 清除，经典旧世通过 SetModifiedClick + SaveBindings 清除
function CheckConflicts()
    local selfCast = GetModifiedClick("SELFCAST")
    -- local focusCast = GetModifiedClick("FOCUSCAST")

    local selfCastMsg, focusCastMsg
    if selfCast ~= "NONE" then
        selfCastMsg = AUTO_SELF_CAST_KEY_TEXT..": |cFFFFD100"..selfCast.."|r\n"
    end
    -- if focusCast ~= "NONE" then
    --     focusCastMsg = FOCUS_CAST_KEY_TEXT..": |cFFFFD100"..focusCast.."|r\n"
    -- end

    if selfCastMsg or focusCastMsg then
        local msg = "|cFFFF3030"..L["Conflicts Detected!"].."|r\n"..(selfCastMsg or "")..(focusCastMsg or "")..
            "\n|cFFFF3030"..L["Yes"].."|r - "..L["Remove"].."\n".."|cFFFF3030"..L["No"].."|r - "..L["Cancel"]

        local popup = Cell.CreateConfirmPopup(clickCastingsTab, 200, msg, function(self)
            if Cell.isRetail then
                --! NOTE: show-set-hide or commit
                -- ShowUIPanel(SettingsPanel)
                -- Settings.OpenToCategory(8)
                Settings.SetValue("SELFCAST", "NONE", true)
                -- HideUIPanel(SettingsPanel)
                SettingsPanel:Commit()
            else
                SetModifiedClick("SELFCAST", "NONE")
                -- SetModifiedClick("FOCUSCAST", "NONE")
                SaveBindings(GetCurrentBindingSet())
            end
        end, nil, true)
        popup:SetPoint("TOPLEFT", 117, -90)
    end
end

-------------------------------------------------
-- functions
-------------------------------------------------
local init
-- 选项标签页显示/隐藏切换回调
-- 首次显示时初始化所有UI面板（配置文件/总是选目标/智能复活/绑定列表）
-- 并对面板施加战斗保护（防止战斗中误操作）
local function ShowTab(tab)
    if tab == "clickCastings" then
        if not init then
            init = true
            CreateProfilePane()
            CreateTargetingPane()
            CreateSmartResPane()
            CreateListPane()
            F.ApplyCombatProtectionToFrame(clickCastingsTab) -- 对面板施加战斗保护，防止战斗中误操作
        end
        clickCastingsTab:Show()
    else
        clickCastingsTab:Hide()
    end
end
-- 注册选项标签页切换回调，当用户切换到点击施法标签页时触发显示
Cell.RegisterCallback("ShowOptionsTab", "ClickCastingsTab_ShowTab", ShowTab)

-- 标签页显示事件：检查按键冲突、首次加载配置、初始化下拉菜单状态
clickCastingsTab:SetScript("OnShow", function()
    CheckConflicts()

    if loaded then return end

    loaded = true

    local isCommon = Cell.vars.clickCastings["useCommon"]
    profileDropdown:SetSelectedItem(isCommon and 1 or 2)
    -- UpdateCurrentText(isCommon)
    LoadProfile(isCommon)

    smartResDropdown:SetSelectedValue(Cell.vars.clickCastings["smartResurrection"])

    menu:SetMenuParent(clickCastingsTab)
    -- texplore(changed)
end)

-- 外部接口：当专精切换时更新配置标签显示名称
-- 仅在标签页已加载时更新，避免不必要的UI操作
function F.UpdateClickCastingProfileLabel()
    if loaded then
        UpdateCurrentText(Cell.vars.clickCastings["useCommon"])
    end
end
