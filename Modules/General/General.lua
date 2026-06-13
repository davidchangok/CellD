-- 模块入口：从全局 Cell 表中获取本地化、通用函数、像素精确函数和黑盒安全函数
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs
local B = Cell.bFuncs

-- 创建"常规"配置标签页，作为选项面板的子页面，初始隐藏
local generalTab = Cell.CreateFrame("CellOptionsFrame_GeneralTab", Cell.frames.optionsFrame, nil, nil, true)
Cell.frames.generalTab = generalTab
generalTab:SetAllPoints(Cell.frames.optionsFrame)
generalTab:Hide()

-------------------------------------------------
-- 可见性设置面板
-- 控制 Blizzard 原生队伍/团队框架及团队管理器的显示与隐藏
-------------------------------------------------
local hideBlizzardPartyCB, hideBlizzardRaidCB, hideRaidManagerCB

-- 创建可见性设置子面板，包含三个勾选框：隐藏暴雪队伍、隐藏暴雪团队、隐藏团队管理器
-- 每个选项在切换后都会弹出重载 UI 确认对话框，因为修改需要重载界面才能生效
local function CreateVisibilityPane()
    local visibilityPane = Cell.CreateTitledPane(generalTab, L["Visibility"], 205, 80)
    visibilityPane:SetPoint("TOPLEFT", generalTab, "TOPLEFT", 5, -5)

    -- showSoloCB = Cell.CreateCheckButton(visibilityPane, L["Show Solo"], function(checked, self)
    --     CellDB["general"]["showSolo"] = checked
    --     Cell.Fire("UpdateVisibility", "solo")
    -- end, L["Show Solo"], L["Show while not in a group"], L["To open options frame, use /cell options"])
    -- showSoloCB:SetPoint("TOPLEFT", visibilityPane, "TOPLEFT", 5, -27)

    -- showPartyCB = Cell.CreateCheckButton(visibilityPane, L["Show Party"], function(checked, self)
    --     CellDB["general"]["showParty"] = checked
    --     Cell.Fire("UpdateVisibility", "party")
    -- end, L["Show Party"], L["Show while in a party"], L["To open options frame, use /cell options"])
    -- showPartyCB:SetPoint("TOPLEFT", showSoloCB, "BOTTOMLEFT", 0, -7)

    -- showRaidCB = Cell.CreateCheckButton(visibilityPane, L["Show Raid"], function(checked, self)
    --     CellDB["general"]["showRaid"] = checked
    --     Cell.Fire("UpdateVisibility", "raid")
    -- end, L["Show Raid"], L["Show while in a raid"], L["To open options frame, use /cell options"])
    -- showRaidCB:SetPoint("TOPLEFT", showPartyCB, "BOTTOMLEFT", 0, -7)

    hideBlizzardPartyCB = Cell.CreateCheckButton(visibilityPane, L["Hide Blizzard Party"], function(checked, self)
        CellDB["general"]["hideBlizzardParty"] = checked

        local popup = Cell.CreateConfirmPopup(generalTab, 200, L["A UI reload is required.\nDo it now?"], function()
            ReloadUI()
        end, nil, true)
        popup:SetPoint("TOPLEFT", generalTab, 117, -77)
    end, L["Hide Blizzard Frames"], L["Require reload of the UI"])
    hideBlizzardPartyCB:SetPoint("TOPLEFT", visibilityPane, 5, -27)

    hideBlizzardRaidCB = Cell.CreateCheckButton(visibilityPane, L["Hide Blizzard Raid"], function(checked, self)
        CellDB["general"]["hideBlizzardRaid"] = checked

        local popup = Cell.CreateConfirmPopup(generalTab, 200, L["A UI reload is required.\nDo it now?"], function()
            ReloadUI()
        end, nil, true)
        popup:SetPoint("TOPLEFT", generalTab, 117, -77)
    end, L["Hide Blizzard Frames"], L["Require reload of the UI"])
    hideBlizzardRaidCB:SetPoint("TOPLEFT", hideBlizzardPartyCB, "BOTTOMLEFT", 0, -7)

    hideRaidManagerCB = Cell.CreateCheckButton(visibilityPane, L["Hide Raid Manager"], function(checked, self)
        CellDB["general"]["hideBlizzardRaidManager"] = checked

        local popup = Cell.CreateConfirmPopup(generalTab, 200, L["A UI reload is required.\nDo it now?"], function()
            ReloadUI()
        end, nil, true)
        popup:SetPoint("TOPLEFT", generalTab, 117, -77)
    end, L["Hide Blizzard Frames"], L["Require reload of the UI"])
    hideRaidManagerCB:SetPoint("TOPLEFT", hideBlizzardRaidCB, "BOTTOMLEFT", 0, -7)
end

-------------------------------------------------
-- 鼠标提示（Tooltip）设置面板
-- 控制单元框架鼠标悬停提示的启用、战斗中隐藏、锚点位置及偏移量
-------------------------------------------------
local enableTooltipsCB, hideTooltipsInCombatCB, tooltipsAnchor, tooltipsAnchorText, tooltipsAnchoredTo, tooltipsAnchoredToText, tooltipsX, tooltipsY

-- 根据当前锚定方式（默认/跟随光标 vs 自定义锚点）来启用或禁用相关控件
-- 当锚定目标为"Cursor"或"Default"时，禁用锚点方向下拉框和 X/Y 偏移滑块
local function UpdateTooltipsOptions()
    if strfind(CellDB["general"]["tooltipsPosition"][2], "Cursor") or CellDB["general"]["tooltipsPosition"][2] == "Default" then
        tooltipsAnchor:SetEnabled(false)
        tooltipsAnchorText:SetTextColor(0.4, 0.4, 0.4)
    else
        tooltipsAnchor:SetEnabled(true)
        tooltipsAnchorText:SetTextColor(1, 1, 1)
    end

    if CellDB["general"]["tooltipsPosition"][2] == "Cursor" or CellDB["general"]["tooltipsPosition"][2] == "Default" then
        tooltipsX:SetEnabled(false)
        tooltipsY:SetEnabled(false)
    else
        tooltipsX:SetEnabled(true)
        tooltipsY:SetEnabled(true)
    end
end

-- 创建鼠标提示设置子面板，包含启用开关、战斗中隐藏、锚点方向、锚定目标、X/Y 偏移
local function CreateTooltipsPane()
    local tooltipsPane = Cell.CreateTitledPane(generalTab, L["Tooltips"], 205, 270)
    tooltipsPane:SetPoint("TOPLEFT", generalTab, "TOPLEFT", 222, -5)

    -- 启用鼠标提示总开关：勾选后联动启用/禁用下方的所有子控件
    enableTooltipsCB = Cell.CreateCheckButton(tooltipsPane, L["Enabled"], function(checked, self)
        CellDB["general"]["enableTooltips"] = checked
        hideTooltipsInCombatCB:SetEnabled(checked)
        -- enableAuraTooltipsCB:SetEnabled(checked)
        tooltipsAnchor:SetEnabled(checked)
        tooltipsAnchoredTo:SetEnabled(checked)
        tooltipsX:SetEnabled(checked)
        tooltipsY:SetEnabled(checked)
        if checked then
            tooltipsAnchorText:SetTextColor(1, 1, 1)
            tooltipsAnchoredToText:SetTextColor(1, 1, 1)
            UpdateTooltipsOptions()
        else
            tooltipsAnchorText:SetTextColor(0.4, 0.4, 0.4)
            tooltipsAnchoredToText:SetTextColor(0.4, 0.4, 0.4)
        end
    end)
    enableTooltipsCB:SetPoint("TOPLEFT", tooltipsPane, "TOPLEFT", 5, -27)

    -- 战斗中隐藏鼠标提示（不影响光环提示）
    hideTooltipsInCombatCB = Cell.CreateCheckButton(tooltipsPane, L["Hide in Combat"], function(checked, self)
        CellDB["general"]["hideTooltipsInCombat"] = checked
    end, L["Hide in Combat"], L["Hide tooltips for units"], L["This will not affect aura tooltips"])
    hideTooltipsInCombatCB:SetPoint("TOPLEFT", enableTooltipsCB, "BOTTOMLEFT", 0, -7)

    -- auras tooltips
    -- enableAuraTooltipsCB = Cell.CreateCheckButton(tooltipsPane, L["Enable Auras Tooltips"].." (pending)", function(checked, self)
    -- end)
    -- enableAuraTooltipsCB:SetPoint("TOPLEFT", hideTooltipsInCombatCB, "BOTTOMLEFT", 0, -7)
    -- enableAuraTooltipsCB:SetEnabled(false)

    -- 鼠标提示锚点方向下拉框：BOTTOM/BOTTOMLEFT/BOTTOMRIGHT/LEFT/RIGHT/TOP/TOPLEFT/TOPRIGHT
    -- 选择锚点方向时，同时自动设置对应的相对锚点方向（如选 BOTTOM 则相对点为 TOP）
    tooltipsAnchor = Cell.CreateDropdown(tooltipsPane, 137)
    tooltipsAnchor:SetPoint("TOPLEFT", hideTooltipsInCombatCB, "BOTTOMLEFT", 0, -25)
    local points = {"BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT", "LEFT", "RIGHT", "TOP", "TOPLEFT", "TOPRIGHT"}
    local relativePoints = {"TOP", "TOPLEFT", "TOPRIGHT", "RIGHT", "LEFT", "BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT"}
    local anchorItems = {}
    for i, point in pairs(points) do
        tinsert(anchorItems, {
            ["text"] = L[point],
            ["value"] = point,
            ["onClick"] = function()
                CellDB["general"]["tooltipsPosition"][1] = point
                CellDB["general"]["tooltipsPosition"][3] = relativePoints[i]
            end,
        })
    end
    tooltipsAnchor:SetItems(anchorItems)

    tooltipsAnchorText = tooltipsPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    tooltipsAnchorText:SetText(L["Anchor Point"])
    tooltipsAnchorText:SetPoint("BOTTOMLEFT", tooltipsAnchor, "TOPLEFT", 0, 1)

    -- 鼠标提示锚定目标下拉框：Default/Cell/Unit Button/Cursor/Cursor Left/Cursor Right
    -- 选择 Default 或 Cursor 系列时，禁用锚点方向和偏移控件
    tooltipsAnchoredTo = Cell.CreateDropdown(tooltipsPane, 137)
    tooltipsAnchoredTo:SetPoint("TOPLEFT", tooltipsAnchor, "BOTTOMLEFT", 0, -25)
    local relatives = {"Default", "Cell", "Unit Button", "Cursor", "Cursor Left", "Cursor Right"}
    local relativeToItems = {}
    for _, relative in pairs(relatives) do
        tinsert(relativeToItems, {
            ["text"] = L[relative],
            ["value"] = relative,
            ["onClick"] = function()
                CellDB["general"]["tooltipsPosition"][2] = relative
                UpdateTooltipsOptions()
            end,
        })
    end
    tooltipsAnchoredTo:SetItems(relativeToItems)

    tooltipsAnchoredToText = tooltipsPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    tooltipsAnchoredToText:SetText(L["Anchored To"])
    tooltipsAnchoredToText:SetPoint("BOTTOMLEFT", tooltipsAnchoredTo, "TOPLEFT", 0, 1)

    -- 鼠标提示 X/Y 偏移滑块（范围 -100 到 100），仅在锚定目标为非 Default/Cursor 时可用
    tooltipsX = Cell.CreateSlider(L["X Offset"], tooltipsPane, -100, 100, 137, 1)
    tooltipsX:SetPoint("TOPLEFT", tooltipsAnchoredTo, "BOTTOMLEFT", 0, -25)
    tooltipsX.afterValueChangedFn = function(value)
        CellDB["general"]["tooltipsPosition"][4] = value
    end

    tooltipsY = Cell.CreateSlider(L["Y Offset"], tooltipsPane, -100, 100, 137, 1)
    tooltipsY:SetPoint("TOPLEFT", tooltipsX, "BOTTOMLEFT", 0, -40)
    tooltipsY.afterValueChangedFn = function(value)
        CellDB["general"]["tooltipsPosition"][5] = value
    end
end

-------------------------------------------------
-- 位置与锁定设置面板
-- 控制 Cell 框架的锁定状态、菜单淡出效果以及菜单按钮排列方向
-------------------------------------------------
local lockCB, fadeOutCB, menuPositionDD

-- 创建位置设置子面板，包含锁定框架、淡出菜单、菜单位置下拉框
local function CreatePositionPane()
    local positionPane = Cell.CreateTitledPane(generalTab, L["Position"], 205, 120)
    positionPane:SetPoint("TOPLEFT", generalTab, 5, -120)

    -- 锁定 Cell 框架位置：勾选后禁止拖动单元框体，通过 Fire("UpdateMenu", "lock") 通知各模块
    lockCB = Cell.CreateCheckButton(positionPane, L["Lock Cell Frames"], function(checked, self)
        CellDB["general"]["locked"] = checked
        Cell.Fire("UpdateMenu", "lock")
    end)
    lockCB:SetPoint("TOPLEFT", 5, -27)

    -- 鼠标离开后淡出菜单按钮：通过 Fire("UpdateMenu", "fadeOut") 触发各模块更新菜单淡出状态
    fadeOutCB = Cell.CreateCheckButton(positionPane, L["Fade Out Menu"], function(checked, self)
        CellDB["general"]["fadeOut"] = checked
        Cell.Fire("UpdateMenu", "fadeOut")
    end, L["Fade Out Menu"], L["Fade out menu buttons on mouseout"])
    fadeOutCB:SetPoint("TOPLEFT", lockCB, "BOTTOMLEFT", 0, -7)

    -- 菜单位置下拉框：选择菜单按钮的排列方向（上下排列 / 左右排列）
    menuPositionDD = Cell.CreateDropdown(positionPane, 137)
    menuPositionDD:SetPoint("TOPLEFT", fadeOutCB, "BOTTOMLEFT", 0, -25)
    menuPositionDD:SetItems({
        {
            ["text"] = L["TOP"].." / "..L["BOTTOM"],
            ["value"] = "top_bottom",
            ["onClick"] = function()
                CellDB["general"]["menuPosition"] = "top_bottom"
                Cell.Fire("UpdateMenu", "position")
            end,
        },
        {
            ["text"] = L["LEFT"].." / "..L["RIGHT"],
            ["value"] = "left_right",
            ["onClick"] = function()
                CellDB["general"]["menuPosition"] = "left_right"
                Cell.Fire("UpdateMenu", "position")
            end,
        },
    })

    local menuPositionText = positionPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    menuPositionText:SetText(L["Menu Position"])
    menuPositionText:SetPoint("BOTTOMLEFT", menuPositionDD, "TOPLEFT", 0, 1)
end

-------------------------------------------------
-- 昵称设置面板
-- 支持设置自己的昵称、与其他玩家同步昵称、管理自定义昵称和昵称黑名单
-------------------------------------------------
local nicknameEB, syncCB

-- 创建昵称设置子面板，包含昵称输入框、同步开关、自定义昵称/黑名单按钮
-- 昵称输入框有 OnTextChanged 检测：当用户修改文本后显示确认按钮，点击 OK 后触发 UpdateNicknames 事件
local function CreateNicknamePane()
    local nicknamePane = Cell.CreateTitledPane(generalTab, L["Nickname"], 205, 130)
    nicknamePane:SetPoint("TOPLEFT", generalTab, 5, -300)

    -- 我的昵称输入框：带占位提示文字，修改后显示确认按钮
    nicknameEB = Cell.CreateEditBox(nicknamePane, 195, 20)
    nicknameEB:SetPoint("TOPLEFT", 5, -27)
    -- OnTextChanged 事件处理：用户修改文本时判断是否需要显示确认按钮
    -- userChanged 参数由系统传入，为 true 时表示用户手动编辑（非代码赋值）
    nicknameEB:SetScript("OnTextChanged", function(self, userChanged)
        local text = strtrim(nicknameEB:GetText())
        nicknameEB.tip:SetShown(text == "")

        if userChanged then
            if CellDB["nicknames"]["mine"] ~= "" then -- already set a nickname
                if text ~= CellDB["nicknames"]["mine"] then -- not the same nickname
                    nicknameEB.confirmBtn:Show()
                else
                    nicknameEB.confirmBtn:Hide()
                end
            elseif text ~= "" then -- nickname not set, expect a non-empty string
                nicknameEB.confirmBtn:Show()
            else
                nicknameEB.confirmBtn:Hide()
            end
        end
    end)

    -- 昵称确认按钮：点击后将输入框文本保存到 CellDB，触发 UpdateNicknames 事件通知其他模块
    nicknameEB.confirmBtn = Cell.CreateButton(nicknameEB, "OK", "accent", {50, 20})
    nicknameEB.confirmBtn:SetPoint("TOPRIGHT", nicknameEB)
    nicknameEB.confirmBtn:Hide()
    nicknameEB.confirmBtn:SetScript("OnHide", function()
        nicknameEB.confirmBtn:Hide()
    end)
    nicknameEB.confirmBtn:SetScript("OnClick", function()
        local text = strtrim(nicknameEB:GetText())
        nicknameEB:SetText(text)
        CellDB["nicknames"]["mine"] = text
        Cell.Fire("UpdateNicknames", "mine", text)
        nicknameEB.confirmBtn:Hide()
        nicknameEB:ClearFocus()
    end)

    -- 昵称输入框内的占位提示文字（输入为空时显示"我的昵称"）
    nicknameEB.tip = nicknameEB:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    nicknameEB.tip:SetPoint("LEFT", 5, 0)
    nicknameEB.tip:SetTextColor(0.4, 0.4, 0.4, 1)
    nicknameEB.tip:SetText(L["My Nickname"])

    -- 昵称同步开关：勾选后与其他使用 Cell 的队友同步自定义昵称
    syncCB = Cell.CreateCheckButton(nicknamePane, L["Nickname Sync"], function(checked, self)
        CellDB["nicknames"]["sync"] = checked
        Cell.Fire("UpdateNicknames", "sync", checked)
    end)
    syncCB:SetPoint("TOPLEFT", nicknameEB, "BOTTOMLEFT", 0, -7)

    -- 自定义昵称管理按钮：打开自定义昵称编辑窗口
    local customNicknamesBtn = Cell.CreateButton(nicknamePane, L["Custom Nicknames"], "accent-hover", {137, 20})
    customNicknamesBtn:SetPoint("TOPLEFT", syncCB, "BOTTOMLEFT", 0, -7)
    Cell.frames.generalTab.customNicknamesBtn = customNicknamesBtn
    customNicknamesBtn:SetScript("OnClick", function()
        F.ShowCustomNicknames()
    end)

    -- 昵称黑名单按钮：打开黑名单管理窗口，被加入黑名单的玩家不会同步其昵称
    local blacklistBtn = Cell.CreateButton(nicknamePane, L["Nickname Blacklist"], "accent-hover", {137, 20})
    blacklistBtn:SetPoint("TOPLEFT", customNicknamesBtn, "BOTTOMLEFT", 0, -7)
    Cell.frames.generalTab.nicknameBlacklistBtn = blacklistBtn
    blacklistBtn:SetScript("OnClick", function()
        F.ShowNicknameBlacklist()
    end)
end

-------------------------------------------------
-- 杂项设置面板
-- 包含光环常刷新开关和西里尔字母音译为拉丁字母开关
-------------------------------------------------
local alwaysUpdateAurasCB, translitCB

-- 创建杂项设置子面板
-- alwaysUpdateAurasCB：仅在 Mists 版本可用，忽略 UNIT_AURA 事件载荷，每次无条件刷新光环，解决部分指示器更新异常
-- translitCB：将俄文/西里尔字母姓名音译为拉丁字母显示
local function CreateMiscPane()
    local miscPane = Cell.CreateTitledPane(generalTab, L["Misc"], 205, 105)
    miscPane:SetPoint("TOPLEFT", generalTab, 222, -300)

    alwaysUpdateAurasCB = Cell.CreateCheckButton(miscPane, L["Always Update Auras"], function(checked, self)
        CellDB["general"]["alwaysUpdateAuras"] = checked
        Cell.vars.alwaysUpdateAuras = checked
    end, L["Ignore UNIT_AURA payloads"], L["This may help solve issues of indicators not updating correctly"])
    alwaysUpdateAurasCB:SetPoint("TOPLEFT", 5, -27)
    alwaysUpdateAurasCB:SetEnabled(Cell.isMists)

    -- NOTE: useCleuHealthUpdater (Faster Health Updates) was removed in r275.
    -- CLEU-based health updates are not available in Midnight 12.0.0+.

    translitCB = Cell.CreateCheckButton(miscPane, L["Translit Cyrillic to Latin"], function(checked, self)
        CellDB["general"]["translit"] = checked
        Cell.Fire("TranslitNames")
    end)
    translitCB:SetPoint("TOPLEFT", alwaysUpdateAurasCB, "BOTTOMLEFT", 0, -9)
end

-------------------------------------------------
-- LibGetFrame 帧优先级设置面板
-- 用于配置 Main / Spotlight / Quick Assist 三种框架的显示优先级顺序
-- 支持拖拽排序：拖动一个框架按钮到另一个框架按钮上方即可交换优先级位置
-------------------------------------------------
local framePriorityWidget

-- TODO: 待移到 Widgets.lua 中作为通用组件
-- 创建帧优先级拖拽排序控件：返回一个包含三个可拖拽按钮的 Frame
-- 每个按钮有独立的勾选框来控制该帧是否启用
-- 内部使用 CellDB["general"]["framePriority"] 二维数组存储 [{name, enabled}, ...]
-- 排序通过 tremove + tinsert 交换位置实现
local function CreateFramePriorityWidget(parent)
    local f = CreateFrame("Frame", nil, parent)
    P.Size(f, 336, 20)

    -- 根据帧名称在优先级表中查找当前索引位置
    local function GetPriority(name)
        for i, t in pairs(CellDB["general"]["framePriority"]) do
            if t[1] == name then
                return i
            end
        end
    end

    local buttons = {}

    -- 排序比较器：先按 enabled 状态排序（启用的在前），再按原始优先级索引排序
    local function Comparator(a, b)
        if a[2] ~= b[2] then
            return a[2]
        end

        return buttons[a[1]]._priority < buttons[b[1]]._priority
    end

    for _, name in pairs({"Main", "Spotlight", "Quick Assist"}) do
        buttons[name] = Cell.CreateButton(f, L[name], "accent-hover", {110, 20})
        buttons[name]._priorityName = name

        -- 每个帧按钮左侧的启用勾选框：切换后重新排序并刷新布局
        buttons[name].cb = Cell.CreateCheckButton(buttons[name], "", function(checked, self)
            CellDB["general"]["framePriority"][GetPriority(name)][2] = checked
            buttons[name]:SetEnabled(checked)
            buttons[name]._enabled = checked
            sort(CellDB["general"]["framePriority"], Comparator)
            f:Load(CellDB["general"]["framePriority"])
            F.UpdateFramePriority()
        end)
        buttons[name].cb:SetPoint("LEFT", 3, 0)

        buttons[name].fs:SetPoint("LEFT", buttons[name].cb, "RIGHT", 3, 0)
        buttons[name].fs:SetJustifyH("LEFT")

        -- 注册鼠标左键拖拽以支持排序
        buttons[name]:SetMovable(true)
        buttons[name]:RegisterForDrag("LeftButton")

        -- OnDragStart：拖拽开始时将按钮提升到 TOOLTIP 层级，避免被其他控件遮挡
        buttons[name]:SetScript("OnDragStart", function(self)
            self:SetFrameStrata("TOOLTIP")
            self:StartMoving()
            self:SetUserPlaced(false)
        end)

        -- OnDragStop：拖拽结束时检测鼠标下方是否为目标框架按钮，若是则交换优先级位置
        -- 注意：此处不使用 Hide() 因为会导致 OnDragStop 被触发两次
        -- 使用 C_Timer.After(0.05) 延迟执行，确保鼠标焦点已更新到正确的目标控件
        buttons[name]:SetScript("OnDragStop", function(self)
            if not self._enabled then return end
            self:StopMovingOrSizing()
            self:SetFrameStrata("LOW")
            -- self:Hide() --! Hide() will cause OnDragStop trigger TWICE!!!
            C_Timer.After(0.05, function()
                local b = F.GetMouseFocus()
                if b ~= self and b and b._priority and b._enabled then
                    -- print(self._priorityName, "->", b._priorityName)

                    local temp = CellDB["general"]["framePriority"][self._priority]
                    tremove(CellDB["general"]["framePriority"], self._priority)
                    tinsert(CellDB["general"]["framePriority"], b._priority, temp)
                end
                f:Load(CellDB["general"]["framePriority"])
                F.UpdateFramePriority()
            end)
        end)
    end

    -- Load 方法：根据传入的优先级表重新布局所有帧按钮，更新其启用状态和位置
    function f:Load(t)
        for i, p in pairs(t) do
            buttons[p[1]]:SetFrameStrata(parent:GetFrameStrata())
            buttons[p[1]]:Show()
            buttons[p[1]]:ClearAllPoints()
            buttons[p[1]]:SetPoint("TOPLEFT", (i-1)*(P.Scale(110)+P.Scale(3)), 0)
            buttons[p[1]]._enabled = p[2]
            buttons[p[1]]:SetEnabled(p[2])
            buttons[p[1]].cb:SetChecked(p[2])
            buttons[p[1]]._priority = i
        end
    end

    return f
end

-- 创建 LibGetFrame 帧优先级设置面板，内嵌可拖拽排序的优先级控件
local function CreateLibGetFramePane()
    local miscPane = Cell.CreateTitledPane(generalTab, "LibGetFrame", 422, 80)
    miscPane:SetPoint("TOPLEFT", generalTab, 5, -450)

    framePriorityWidget = CreateFramePriorityWidget(miscPane)
    framePriorityWidget:SetPoint("TOPLEFT", 5, -45)

    -- framePriorityDD = Cell.CreateDropdown(miscPane, 250)
    -- framePriorityDD:SetPoint("TOPLEFT", alwaysUpdateAurasCB, "BOTTOMLEFT", 0, -29)
    -- framePriorityDD:SetItems({
    --     {
    --         ["text"] = L["Main"].." > "..L["Spotlight"].." > "..L["Quick Assist"],
    --         ["value"] = "normal_spotlight_quickassist",
    --         ["onClick"] = function()
    --             CellDB["general"]["framePriority"] = "normal_spotlight_quickassist"
    --         end,
    --     },
    --     {
    --         ["text"] = L["Spotlight"].." > "..L["Main"].." > "..L["Quick Assist"],
    --         ["value"] = "spotlight_normal_quickassist",
    --         ["onClick"] = function()
    --             CellDB["general"]["framePriority"] = "spotlight_normal_quickassist"
    --         end,
    --     },
    --     {
    --         ["text"] = L["Quick Assist"].." > "..L["Main"].." > "..L["Spotlight"],
    --         ["value"] = "quickassist_normal_spotlight",
    --         ["onClick"] = function()
    --             CellDB["general"]["framePriority"] = "quickassist_normal_spotlight"
    --         end,
    --     },
    -- })

    local framePriorityText = miscPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    framePriorityText:SetPoint("BOTTOMLEFT", framePriorityWidget, "TOPLEFT", 0, 7)
    framePriorityText:SetText(L["Frame priorities for LibGetFrame"])
end

-------------------------------------------------
-- 核心控制函数
-------------------------------------------------
-- init 标志：确保面板控件只创建一次，但每次切换到常规标签时都会刷新控件显示值
local init

-- 响应选项面板标签切换的回调函数
-- 当用户点击"常规"标签时，首次调用会创建所有子面板（可见性、提示、位置、昵称、杂项、LibGetFrame），
-- 并通过战斗保护遮罩防止战斗中误操作。后续切换只显示/隐藏并刷新所有控件值为当前 CellDB 中的配置。
-- 若切换到其他标签页则隐藏整个常规面板。
local function ShowTab(tab)
    if tab == "general" then
        if not init then
            -- 首次初始化：创建所有子面板
            CreateVisibilityPane()
            CreateTooltipsPane()
            CreatePositionPane()
            CreateNicknamePane()
            CreateMiscPane()
            CreateLibGetFramePane()

            -- 应用战斗保护遮罩：战斗中禁止修改配置
            F.ApplyCombatProtectionToFrame(generalTab)
            Cell.CreateMask(generalTab, nil, {1, -1, -1, 1})
            generalTab.mask:Hide()
        end

        generalTab:Show()

        -- 非首次切换只显示，不重复初始化控件值
        if init then return end
        init = true

        -- 从 CellDB 读取当前配置并设置所有提示相关控件的初始值
        -- tooltips
        enableTooltipsCB:SetChecked(CellDB["general"]["enableTooltips"])
        hideTooltipsInCombatCB:SetEnabled(CellDB["general"]["enableTooltips"])
        hideTooltipsInCombatCB:SetChecked(CellDB["general"]["hideTooltipsInCombat"])
        -- enableAuraTooltipsCB:SetEnabled(CellDB["general"]["enableTooltips"])
        -- enableAuraTooltipsCB:SetChecked(CellDB["general"]["enableAurasTooltips"])
        tooltipsAnchor:SetEnabled(CellDB["general"]["enableTooltips"])
        tooltipsAnchor:SetSelectedValue(CellDB["general"]["tooltipsPosition"][1])
        tooltipsAnchoredTo:SetEnabled(CellDB["general"]["enableTooltips"])
        tooltipsAnchoredTo:SetSelectedValue(CellDB["general"]["tooltipsPosition"][2])
        tooltipsX:SetEnabled(CellDB["general"]["enableTooltips"])
        tooltipsX:SetValue(CellDB["general"]["tooltipsPosition"][4])
        tooltipsY:SetEnabled(CellDB["general"]["enableTooltips"])
        tooltipsY:SetValue(CellDB["general"]["tooltipsPosition"][5])
        if CellDB["general"]["enableTooltips"] then
            tooltipsAnchorText:SetTextColor(1, 1, 1)
            tooltipsAnchoredToText:SetTextColor(1, 1, 1)
            UpdateTooltipsOptions()
        else
            tooltipsAnchorText:SetTextColor(0.4, 0.4, 0.4)
            tooltipsAnchoredToText:SetTextColor(0.4, 0.4, 0.4)
        end

        -- 从 CellDB 读取当前配置并设置可见性相关控件的初始值
        -- visibility
        hideBlizzardPartyCB:SetChecked(CellDB["general"]["hideBlizzardParty"])
        hideBlizzardRaidCB:SetChecked(CellDB["general"]["hideBlizzardRaid"])
        hideRaidManagerCB:SetChecked(CellDB["general"]["hideBlizzardRaidManager"])

        -- 从 CellDB 读取当前配置并设置位置相关控件的初始值
        -- position
        lockCB:SetChecked(CellDB["general"]["locked"])
        fadeOutCB:SetChecked(CellDB["general"]["fadeOut"])
        menuPositionDD:SetSelectedValue(CellDB["general"]["menuPosition"])

        -- 从 CellDB 读取当前配置并设置昵称相关控件的初始值
        -- nickname
        nicknameEB:SetText(CellDB["nicknames"]["mine"])
        syncCB:SetChecked(CellDB["nicknames"]["sync"])

        -- 从 CellDB 读取当前配置并设置杂项相关控件的初始值
        -- misc
        alwaysUpdateAurasCB:SetChecked(CellDB["general"]["alwaysUpdateAuras"])
        framePriorityWidget:Load(CellDB["general"]["framePriority"])
        translitCB:SetChecked(CellDB["general"]["translit"])

    else
        generalTab:Hide()
    end
end
-- 注册回调：当选项面板切换到不同标签时，Cell 框架通过 "ShowOptionsTab" 事件通知本模块
Cell.RegisterCallback("ShowOptionsTab", "GeneralTab_ShowTab", ShowTab)