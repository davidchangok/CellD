local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local U = Cell.uFuncs
local P = Cell.pixelPerfectFuncs
local LCG = LibStub("LibCustomGlow-1.0")

-------------------------------------------------
-- 技能请求（Spell Request）设置面板
-- 允许队伍/团队成员请求特定法术（如Buff），响应者在单位按钮上看到发光/图标提示
-------------------------------------------------
-- 面板主框架与类型选项按钮
local srPane, srTypeOptionsBtn
-- 技能编辑帧的显示函数引用（在 CreateSpellEditFrame 之后定义）
local ShowSpellEditFrame
-- UI 控件：WeakAuras提示按钮、启用、检查已存在、仅已知法术、仅空闲冷却、回复冷却、回复施法后输入框、响应类型下拉、响应类型标签、超时下拉、超时标签
local waTips, srEnabledCB, srExistsCB, srKnownOnlyCB, srFreeCDOnlyCB, srReplyCDCB, srReplyCastEB, srResponseDD, srResponseText, srTimeoutDD, srTimeoutText
-- UI 控件：技能下拉列表、技能标签、添加按钮、删除按钮、宏标签、宏编辑框、类型下拉、类型标签
local srSpellsDD, srSpellsText, srAddBtn, srDeleteBtn, srMacroText, srMacroEB, srTypeDD, srTypeText
-- 当前状态：选中的技能索引、是否可编辑（非内置技能）、当前技能类型（"icon" 或 "glow"）
local srSelectedSpell, canEdit, srType

-- ================================================================
-- ShowSpellOptions(index)
-- 显示指定技能的详细选项（宏内容/关键词、类型下拉、类型选项按钮）
-- 根据响应类型（all / me / whisper）构建不同的宏文本或显示关键词编辑框
-- ================================================================
local function ShowSpellOptions(index)
    -- 隐藏发光/图标选项面板，停止彩色文字动画
    U.HideGlowOptions()
    U.HideIconOptions()
    Cell.StopRainbowText(srTypeOptionsBtn:GetFontString())

    srSelectedSpell = index

    local responseType = CellDB["spellRequest"]["responseType"]
    local spellId = CellDB["spellRequest"]["spells"][index]["spellId"]
    local macroText, keywords

    -- 根据响应类型构建宏文本或关键词
    if responseType == "all" then
        -- 响应所有：宏发送技能请求给全团
        srMacroText:SetText(L["Macro"])
        macroText = "/run C_ChatInfo.SendAddonMessage(\"CELL_REQ_S\",\""..spellId.."\",\"RAID\")"
    elseif responseType == "me" then
        -- 仅响应"密我"的：宏发送技能请求给全团，附带请求者名称
        srMacroText:SetText(L["Macro"])
        macroText = "/run C_ChatInfo.SendAddonMessage(\"CELL_REQ_S\",\""..spellId..":"..GetUnitName("player").."\",\"RAID\")"
    else -- whisper
        -- 响应私聊：显示关键词编辑框，用户可修改触发私聊的关键词
        srMacroText:SetText(L["Contains"])
        keywords = CellDB["spellRequest"]["spells"][index]["keywords"]
    end

    if macroText then
        -- 宏模式：设置编辑框为只读，用户只能复制宏文本
        srMacroEB:SetText(macroText)
        srMacroEB.gauge:SetText(macroText)
        srMacroEB:SetScript("OnTextChanged", function(self, userChanged)
            if userChanged then
                srMacroEB:SetText(macroText)
                srMacroEB:HighlightText()
            end
        end)
    else
        -- 关键词模式：用户可编辑关键词，修改后同步到数据库并触发刷新
        srMacroEB:SetText(keywords)
        srMacroEB.gauge:SetText(keywords)
        srMacroEB:SetScript("OnTextChanged", function(self, userChanged)
            if userChanged then
                CellDB["spellRequest"]["spells"][index]["keywords"] = strtrim(self:GetText())
                Cell.Fire("UpdateRequests", "spellRequest_spells")
            end
        end)
    end

    -- 内置技能不可删除、不可编辑
    canEdit = not CellDB["spellRequest"]["spells"][index]["isBuiltIn"] -- not built-in
    srDeleteBtn:SetEnabled(canEdit)

    srMacroText:Show()
    srMacroEB:SetCursorPosition(0)
    srMacroEB:Show()

    -- 技能类型："icon"（图标显示）或 "glow"（发光显示）
    srType = CellDB["spellRequest"]["spells"][index]["type"]

    srTypeText:Show()
    srTypeDD:Show()
    srTypeDD:SetSelectedValue(srType)

    srTypeOptionsBtn:Show()
    if srType == "icon" then
        srTypeOptionsBtn:SetText(L["Icon Options"])
    else
        srTypeOptionsBtn:SetText(L["Glow Options"])
    end
end

-- ================================================================
-- HideSpellOptions()
-- 隐藏技能详细选项面板，重置所有相关状态和控件
-- ================================================================
local function HideSpellOptions()
    U.HideGlowOptions()
    U.HideIconOptions()
    Cell.StopRainbowText(srTypeOptionsBtn:GetFontString())

    srSelectedSpell = nil
    canEdit = nil
    srType = nil
    srSpellsDD:ClearSelected()
    srDeleteBtn:SetEnabled(false)
    srTypeOptionsBtn:Hide()
    CellDropdownList:Hide()
    srMacroText:Hide()
    srMacroEB:Hide()
    srTypeDD:Hide()
    srTypeText:Hide()
end

-- ================================================================
-- LoadSpellsDropdown()
-- 从数据库加载所有技能，填充到技能下拉列表中
-- 每个条目显示技能图标 + 名称，点击时调用 ShowSpellOptions
-- ================================================================
local function LoadSpellsDropdown()
    local items = {}
    for i, t in pairs(CellDB["spellRequest"]["spells"]) do
        local name, icon = F.GetSpellInfo(t["spellId"])
        tinsert(items, {
            ["text"] = "|T"..icon..":0::0:0:16:16:1:15:1:15|t "..name,
            ["value"] = t["spellId"],
            ["onClick"] = function()
                ShowSpellOptions(i)
            end
        })
    end
    srSpellsDD:SetItems(items)
end

-- ================================================================
-- UpdateSRWidgets()
-- 根据当前启用状态和各项设置，更新所有控件的启用/禁用状态
-- 级联关系：
--   enabled 为 false 时，大部分控件禁用
--   knownSpellsOnly 为 false 时，freeCDOnly、replyCD、replyCast 禁用
--   responseType 为 "all" 时，replyCD 禁用（全团响应不需要回复冷却）
-- ================================================================
local function UpdateSRWidgets()
    Cell.SetEnabled(CellDB["spellRequest"]["enabled"], waTips, srExistsCB, srKnownOnlyCB, srResponseDD, srResponseText, srTimeoutDD, srTimeoutText, srSpellsDD, srSpellsText, srAddBtn, srDeleteBtn)
    Cell.SetEnabled(CellDB["spellRequest"]["enabled"] and CellDB["spellRequest"]["knownSpellsOnly"], srFreeCDOnlyCB)
    Cell.SetEnabled(CellDB["spellRequest"]["enabled"] and CellDB["spellRequest"]["knownSpellsOnly"] and CellDB["spellRequest"]["responseType"] ~= "all", srReplyCDCB)
    Cell.SetEnabled(CellDB["spellRequest"]["enabled"] and CellDB["spellRequest"]["knownSpellsOnly"], srReplyCastEB)
end

-- ================================================================
-- CreateSRPane()
-- 创建技能请求设置面板的主框架及所有子控件
-- 包含：WA提示按钮、启用/检查/已知/空闲CD/回复CD复选框、
--        回复施法后输入框、响应类型下拉、超时下拉、技能下拉、
--        添加/删除按钮、宏编辑框、类型下拉、类型选项按钮
-- ================================================================
local function CreateSRPane()
    -- 确保 utilitiesTab 有遮罩层
    if not Cell.frames.utilitiesTab.mask then
        Cell.CreateMask(Cell.frames.utilitiesTab, nil, {1, -1, -1, 1})
        Cell.frames.utilitiesTab.mask:Hide()
    end

    -- 创建带标题的面板，面板隐藏时自动收起技能选项
    srPane = Cell.CreateTitledPane(Cell.frames.utilitiesTab, L["Spell Request"], 422, 250)
    srPane:SetPoint("TOPLEFT", 5, -5)
    srPane:SetPoint("BOTTOMRIGHT", -5, 5)
    srPane:SetScript("OnHide", function()
        HideSpellOptions()
    end)

    -- ============ WA 提示按钮 ============
    -- 悬停时显示 WeakAuras 自定义事件的使用说明
    waTips = Cell.CreateButton(srPane, "WA", "accent", {50, 17})
    waTips:SetPoint("TOPRIGHT")
    waTips:HookScript("OnEnter", function()
        CellTooltip:SetOwner(waTips, "ANCHOR_NONE")
        CellTooltip:SetPoint("TOPLEFT", waTips, "TOPRIGHT", 6, 0)
        CellTooltip:AddLine("WeakAuras Custom Events")
        CellTooltip:AddLine("|cffffffff"..[[eventName: "CELL_NOTIFY"]])
        CellTooltip:AddLine("|cffffffff".."arg1:\n    \"SPELL_REQ_RECEIVED\"\n    \"SPELL_REQ_APPLIED\"")
        CellTooltip:AddLine("|cffffffff".."arg2: unitId")
        CellTooltip:AddLine("|cffffffff".."arg3: buffId")
        CellTooltip:AddLine("|cffffffff".."arg4: timeout")
        CellTooltip:AddLine("|cffffffff".."arg5: caster")
        CellTooltip:Show()
    end)
    waTips:HookScript("OnLeave", function()
        CellTooltip:Hide()
    end)

    -- ============ 说明文本 ============
    local srTips = srPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    srTips:SetPoint("TOPLEFT", 5, -25)
    srTips:SetJustifyH("LEFT")
    srTips:SetSpacing(5)
    srTips:SetText(L["Glow unit button when a group member sends a %s request"]:format(Cell.GetAccentColorString()..L["SPELL"].."|r").."\n"..
        L["Shows only one spell request on a unit button at a time"]
    )

    -- ============ 启用复选框 ============
    -- 控制整个技能请求功能的开关
    -- enabled ----------------------------------------------------------------------
    srEnabledCB = Cell.CreateCheckButton(srPane, L["Enabled"], function(checked, self)
        CellDB["spellRequest"]["enabled"] = checked
        UpdateSRWidgets()
        HideSpellOptions()
        Cell.Fire("UpdateRequests", "spellRequest")
    end)
    srEnabledCB:SetPoint("TOPLEFT", srPane, "TOPLEFT", 5, -100)
    ---------------------------------------------------------------------------------

    -- ============ 检查已存在复选框 ============
    -- 如果请求者身上已有该Buff/技能，则不响应（不发光）
    -- check exists -----------------------------------------------------------------
    srExistsCB = Cell.CreateCheckButton(srPane, L["Check If Exists"], function(checked, self)
        CellDB["spellRequest"]["checkIfExists"] = checked
        Cell.Fire("UpdateRequests", "spellRequest")
    end, L["Do nothing if requested spell/buff already exists on requester"])
    srExistsCB:SetPoint("TOPLEFT", srEnabledCB, "TOPLEFT", 200, 0)
    ---------------------------------------------------------------------------------

    -- ============ 仅已知法术复选框 ============
    -- 开启后只响应自己会施放的法术；关闭则不检查，直接发光不回复
    -- known only -------------------------------------------------------------------
    srKnownOnlyCB = Cell.CreateCheckButton(srPane, L["Known Spells Only"], function(checked, self)
        CellDB["spellRequest"]["knownSpellsOnly"] = checked
        UpdateSRWidgets()
        HideSpellOptions()
        Cell.Fire("UpdateRequests", "spellRequest")
    end, L["If disabled, no check, no reply, just glow"])
    srKnownOnlyCB:SetPoint("TOPLEFT", srEnabledCB, "BOTTOMLEFT", 0, -15)
    ---------------------------------------------------------------------------------

    -- ============ 仅空闲冷却复选框 ============
    -- 开启后只在技能冷却完毕时才响应
    -- free cooldown ----------------------------------------------------------------
    srFreeCDOnlyCB = Cell.CreateCheckButton(srPane, L["Free Cooldown Only"], function(checked, self)
        CellDB["spellRequest"]["freeCooldownOnly"] = checked
        Cell.Fire("UpdateRequests", "spellRequest")
    end)
    srFreeCDOnlyCB:SetPoint("TOPLEFT", srKnownOnlyCB, "TOPLEFT", 200, 0)
    ---------------------------------------------------------------------------------

    -- ============ 回复冷却复选框 ============
    -- 开启后在响应请求时附带自己的技能冷却信息
    -- reply cd ---------------------------------------------------------------------
    srReplyCDCB = Cell.CreateCheckButton(srPane, L["Reply With Cooldown"], function(checked, self)
        CellDB["spellRequest"]["replyCooldown"] = checked
        Cell.Fire("UpdateRequests", "spellRequest")
    end)
    srReplyCDCB:SetPoint("TOPLEFT", srKnownOnlyCB, "BOTTOMLEFT", 0, -15)
    ---------------------------------------------------------------------------------

    -- ============ 回复施法后输入框 ============
    -- 用户在输入框中输入法术名称，施放该法术后自动回复请求者
    -- reply after cast -------------------------------------------------------------
    srReplyCastEB = Cell.CreateEditBox(srPane, 20, 20)
    srReplyCastEB:SetPoint("TOPLEFT", srFreeCDOnlyCB, "BOTTOMLEFT", 0, -12)
    srReplyCastEB:SetPoint("RIGHT", -5, 0)
    srReplyCastEB:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            local text = strtrim(self:GetText())
            if text ~= "" then
                CellDB["spellRequest"]["replyAfterCast"] = text
                srReplyCastEB.tip:Hide()
            else
                CellDB["spellRequest"]["replyAfterCast"] = nil
                srReplyCastEB.tip:Show()
            end
            Cell.Fire("UpdateRequests", "spellRequest")
        end
    end)

    -- 输入框占位提示文字
    srReplyCastEB.tip = srReplyCastEB:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    srReplyCastEB.tip:SetPoint("LEFT", 5, 0)
    srReplyCastEB.tip:SetTextColor(0.4, 0.4, 0.4, 1)
    srReplyCastEB.tip:SetText(L["Reply After Cast"])
    srReplyCastEB.tip:Hide()
    ---------------------------------------------------------------------------------

    -- ============ 响应类型下拉 ============
    -- all:    响应所有团队成员的请求
    -- me:     仅响应明确发给自己的请求
    -- whisper:响应私聊请求（通过关键词匹配）
    -- response ----------------------------------------------------------------------
    srResponseDD = Cell.CreateDropdown(srPane, 345)
    srResponseDD:SetPoint("TOPLEFT", srReplyCDCB, "BOTTOMLEFT", 0, -37)
    srResponseDD:SetItems({
        {
            ["text"] = L["Respond to all requests from group members"],
            ["value"] = "all",
            ["onClick"] = function()
                HideSpellOptions()
                CellDB["spellRequest"]["responseType"] = "all"
                Cell.Fire("UpdateRequests", "spellRequest")
                UpdateSRWidgets()
            end
        },
        {
            ["text"] = L["Respond to requests that are only sent to me"],
            ["value"] = "me",
            ["onClick"] = function()
                HideSpellOptions()
                CellDB["spellRequest"]["responseType"] = "me"
                Cell.Fire("UpdateRequests", "spellRequest")
                UpdateSRWidgets()
            end
        },
        {
            ["text"] = L["Respond to whispers"],
            ["value"] = "whisper",
            ["onClick"] = function()
                HideSpellOptions()
                CellDB["spellRequest"]["responseType"] = "whisper"
                Cell.Fire("UpdateRequests", "spellRequest")
                UpdateSRWidgets()
            end
        },
    })

    srResponseText = srPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    srResponseText:SetPoint("BOTTOMLEFT", srResponseDD, "TOPLEFT", 0, 1)
    srResponseText:SetText(L["Response Type"])
    ---------------------------------------------------------------------------------

    -- ============ 超时下拉 ============
    -- 技能请求的超时时间（秒），超时后发光/图标消失
    -- timeout ----------------------------------------------------------------------
    srTimeoutDD = Cell.CreateDropdown(srPane, 60)
    srTimeoutDD:SetPoint("TOPLEFT", srResponseDD, "TOPRIGHT", 7, 0)

    local items = {}
    local secs = {1, 2, 3, 4, 5, 10, 15, 20, 25, 30}
    for _, s in ipairs(secs) do
        tinsert(items, {
            ["text"] = s,
            ["value"] = s,
            ["onClick"] = function()
                CellDB["spellRequest"]["timeout"] = s
                Cell.Fire("UpdateRequests", "spellRequest")
            end
        })
    end
    srTimeoutDD:SetItems(items)

    srTimeoutText = srPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    srTimeoutText:SetPoint("BOTTOMLEFT", srTimeoutDD, "TOPLEFT", 0, 1)
    srTimeoutText:SetText(L["Timeout"])
    ---------------------------------------------------------------------------------

    -- ============ 技能下拉列表 ============
    -- 列出所有已配置的技能请求项目，选择后显示详细选项
    -- spells -----------------------------------------------------------------------
    srSpellsDD = Cell.CreateDropdown(srPane, 268)
    srSpellsDD:SetPoint("TOPLEFT", srResponseDD, "BOTTOMLEFT", 0, -37)

    srSpellsText = srPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    srSpellsText:SetPoint("BOTTOMLEFT", srSpellsDD, "TOPLEFT", 0, 1)
    srSpellsText:SetText(L["Spells"])
    ---------------------------------------------------------------------------------

    -- ============ 添加/编辑按钮 ============
    -- 单击：添加新技能；Alt+左键单击：编辑当前选中的技能
    -- OnUpdate 脚本每 0.25 秒检测 Alt 键状态来切换按钮文字（Add / Edit）
    -- create -----------------------------------------------------------------------
    srAddBtn = Cell.CreateButton(srPane, L["Add"], "green-hover", {65, 20}, nil, nil, nil, nil, nil,
        L["Add new spell"], L["[Alt+LeftClick] to edit"], L["The spell is required to apply a buff on the target"], L["SpellId and BuffId are the same in most cases"])
    srAddBtn:SetPoint("TOPLEFT", srSpellsDD, "TOPRIGHT", 7, 0)
    srAddBtn:SetScript("OnUpdate", function(self, elapsed)
        srAddBtn.elapsed = (srAddBtn.elapsed or 0) + elapsed
        if srAddBtn.elapsed >= 0.25 then
            if IsAltKeyDown() and canEdit then
                srAddBtn:SetText(L["Edit"])
            else
                srAddBtn:SetText(L["Add"])
            end
        end
    end)
    srAddBtn:SetScript("OnClick", function()
        if IsAltKeyDown() and canEdit then
            -- Alt+单击：编辑当前选中技能
            ShowSpellEditFrame(srSelectedSpell)
        else
            -- 普通单击：添加新技能
            ShowSpellEditFrame()
        end
    end)
    Cell.RegisterForCloseDropdown(srAddBtn)
    ---------------------------------------------------------------------------------

    -- ============ 删除按钮 ============
    -- 删除当前选中的技能，弹出确认对话框
    -- delete -----------------------------------------------------------------------
    srDeleteBtn = Cell.CreateButton(srPane, L["Delete"], "red-hover", {65, 20})
    srDeleteBtn:SetPoint("TOPLEFT", srAddBtn, "TOPRIGHT", 7, 0)
    srDeleteBtn:SetScript("OnClick", function()
        local name, icon = F.GetSpellInfo(CellDB["spellRequest"]["spells"][srSelectedSpell]["spellId"])
        local spellEditFrame = Cell.CreateConfirmPopup(Cell.frames.utilitiesTab, 200, L["Delete spell?"].."\n".."|T"..icon..":0::0:0:16:16:1:15:1:15|t "..name, function(self)
            tremove(CellDB["spellRequest"]["spells"], srSelectedSpell)
            srSpellsDD:RemoveCurrentItem()
            HideSpellOptions()
            Cell.Fire("UpdateRequests", "spellRequest_spells")
        end, nil, true)
        spellEditFrame:SetPoint("LEFT", 117, 0)
        spellEditFrame:SetPoint("BOTTOM", srDeleteBtn, 0, 0)
    end)
    Cell.RegisterForCloseDropdown(srDeleteBtn)
    ---------------------------------------------------------------------------------

    -- ============ 宏/关键词编辑框 ============
    -- 根据响应类型显示为只读宏文本或可编辑的关键词文本
    -- macro ------------------------------------------------------------------------
    srMacroEB = Cell.CreateEditBox(srPane, 412, 20)
    srMacroEB:SetPoint("TOPLEFT", srSpellsDD, "BOTTOMLEFT", 0, -27)

    srMacroText = srPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    srMacroText:SetPoint("BOTTOMLEFT", srMacroEB, "TOPLEFT", 0, 1)
    srMacroText:SetText(L["Macro"])

    -- gauge 用于测量文本实际宽度，超出时自动扩展编辑框宽度
    srMacroEB.gauge = srMacroEB:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    srMacroEB:SetScript("OnEditFocusGained", function()
        local requiredWidth = srMacroEB.gauge:GetStringWidth()
        if requiredWidth > srMacroEB:GetWidth() then
            P.Width(srMacroEB, requiredWidth + 20)
        end
        srMacroEB:HighlightText()
    end)
    srMacroEB:SetScript("OnEditFocusLost", function()
        P.Width(srMacroEB, 412)
        srMacroEB:SetCursorPosition(0)
        srMacroEB:HighlightText(0, 0)
    end)
    ---------------------------------------------------------------------------------

    -- ============ 类型下拉 ============
    -- "icon": 在单位按钮上显示技能图标
    -- "glow": 在单位按钮上显示发光效果
    -- type -------------------------------------------------------------------------
    srTypeDD = Cell.CreateDropdown(srPane, 131)
    srTypeDD:SetPoint("TOPLEFT", srMacroEB, "BOTTOMLEFT", 0, -27)
    srTypeDD:SetItems({
        {
            ["text"] = L["Icon"],
            ["value"] = "icon",
            ["onClick"] = function()
                U.HideGlowOptions()
                U.HideIconOptions()
                Cell.StopRainbowText(srTypeOptionsBtn:GetFontString())
                srTypeOptionsBtn:SetText(L["Icon Options"])
                CellDB["spellRequest"]["spells"][srSelectedSpell]["type"] = "icon"
                srType = "icon"
                Cell.Fire("UpdateRequests", "spellRequest")
                Cell.Fire("UpdateRequests", "spellRequest_spells")
            end
        },
        {
            ["text"] = L["Glow"],
            ["value"] = "glow",
            ["onClick"] = function()
                U.HideGlowOptions()
                U.HideIconOptions()
                Cell.StopRainbowText(srTypeOptionsBtn:GetFontString())
                srTypeOptionsBtn:SetText(L["Glow Options"])
                CellDB["spellRequest"]["spells"][srSelectedSpell]["type"] = "glow"
                srType = "glow"
                Cell.Fire("UpdateRequests", "spellRequest")
                Cell.Fire("UpdateRequests", "spellRequest_spells")
            end
        },
    })

    srTypeText = srPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    srTypeText:SetPoint("BOTTOMLEFT", srTypeDD, "TOPLEFT", 0, 1)
    srTypeText:SetText(L["Type"])

    ---------------------------------------------------------------------------------

    -- ============ 类型选项按钮 ============
    -- 点击展开图标选项面板或发光选项面板（根据当前 srType 决定）
    -- 点击时切换彩色文字动画，隐藏时停止动画
    -- type option ------------------------------------------------------------------
    srTypeOptionsBtn = Cell.CreateButton(srPane, L["Glow Options"], "accent", {130, 20})
    srTypeOptionsBtn:SetPoint("TOPLEFT", srTypeDD, "TOPRIGHT", 7, 0)
    srTypeOptionsBtn:SetScript("OnClick", function()
        local fs = srTypeOptionsBtn:GetFontString()
        if fs.rainbow then
            Cell.StopRainbowText(fs)
        else
            Cell.StartRainbowText(fs)
        end

        if srType == "icon" then
            U.ShowIconOptions(Cell.frames.utilitiesTab, CellDB["spellRequest"]["spells"][srSelectedSpell]["icon"], CellDB["spellRequest"]["spells"][srSelectedSpell]["iconColor"])
        else
            U.ShowGlowOptions(Cell.frames.utilitiesTab, CellDB["spellRequest"]["spells"][srSelectedSpell]["glowOptions"])
        end
    end)
    srTypeOptionsBtn:SetScript("OnHide", function()
        Cell.StopRainbowText(srTypeOptionsBtn:GetFontString())
    end)
    Cell.RegisterForCloseDropdown(srTypeOptionsBtn)
    ---------------------------------------------------------------------------------
end

-------------------------------------------------
-- 技能编辑帧（Spell Edit Frame）
-- 用于添加新技能或编辑已有技能的 SpellID / BuffID
-------------------------------------------------
local spellId, buffId, spellName, spellIcon
local spellEditFrame, title, spellIdEB, buffIdEB, addBtn, cancelBtn

-- ================================================================
-- CreateSpellEditFrame()
-- 创建技能编辑弹窗：
--   title:      标题文字（"添加新技能" 或 "编辑技能"）
--   spellIdEB:  Spell ID 输入框（数字输入），输入后实时查询法术名称并显示tooltip
--   buffIdEB:   Buff ID 输入框（数字输入），按Tab可在两个输入框间切换
--   addBtn:     添加/保存按钮
--   cancelBtn:  取消按钮
-- 隐藏时清理所有状态
-- ================================================================
local function CreateSpellEditFrame()
    spellEditFrame = CreateFrame("Frame", nil, Cell.frames.utilitiesTab, "BackdropTemplate")
    spellEditFrame:Hide()
    Cell.StylizeFrame(spellEditFrame, {0.1, 0.1, 0.1, 0.95}, Cell.GetAccentColorTable())
    spellEditFrame:SetFrameLevel(Cell.frames.utilitiesTab:GetFrameLevel() + 50)
    spellEditFrame:SetSize(200, 100)
    spellEditFrame:SetPoint("LEFT", 117, 0)
    spellEditFrame:SetPoint("BOTTOM", srAddBtn, 0, 0)
    -- 隐藏时清理 tooltip、遮罩、输入框内容及临时变量
    spellEditFrame:SetScript("OnHide", function()
        CellSpellTooltip:Hide()
        Cell.frames.utilitiesTab.mask:Hide()
        spellEditFrame:Hide()
        spellIdEB:SetText("")
        buffIdEB:SetText("")
        spellId, buffId, spellName, spellIcon = nil, nil, nil, nil
    end)

    -- ============ 标题 ============
    title = spellEditFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_TITLE")
    title:SetWordWrap(true)
    title:SetJustifyH("CENTER")
    title:SetPoint("TOPLEFT", 5, -8)
    title:SetPoint("TOPRIGHT", -5, -8)
    title:SetText(L["Add new spell"])

    -- ============ Spell ID 输入框 ============
    -- 输入数字 ID 后自动查询法术信息，有效则显示绿色提示并启用添加按钮，
    -- 同时在编辑框下方显示法术 tooltip；无效则显示红色提示
    -- spllId editbox
    spellIdEB = Cell.CreateEditBox(spellEditFrame, 20, 20)
    spellIdEB:SetPoint("TOPLEFT", spellEditFrame, 10, -30)
    spellIdEB:SetPoint("TOPRIGHT", spellEditFrame, -10, -30)
    spellIdEB:SetNumeric(true)
    -- Tab 键跳转到 Buff ID 输入框
    spellIdEB:SetScript("OnTabPressed", function()
        buffIdEB:SetFocus()
    end)
    spellIdEB:SetScript("OnTextChanged", function()
        local id = tonumber(spellIdEB:GetText())
        if not id then
            -- 非法输入：隐藏 tooltip，禁用添加按钮，红色提示
            CellSpellTooltip:Hide()
            spellId = nil
            addBtn:SetEnabled(false)
            spellIdEB.tip:SetTextColor(1, 0, 0, 0.777)
            return
        end

        local name, icon = F.GetSpellInfo(id)
        if not name then
            -- 无效 ID：隐藏 tooltip，禁用添加按钮，红色提示
            CellSpellTooltip:Hide()
            spellId = nil
            addBtn:SetEnabled(false)
            spellIdEB.tip:SetTextColor(1, 0, 0, 0.777)
            return
        end

        -- 有效法术：延时显示 tooltip，保存数据，绿色提示，启用按钮
        C_Timer.After(0.1, function()
            CellSpellTooltip:SetOwner(spellEditFrame, "ANCHOR_NONE")
            CellSpellTooltip:SetPoint("TOPLEFT", spellEditFrame, "BOTTOMLEFT", 0, -1)
            CellSpellTooltip:SetSpellByID(id)
            CellSpellTooltip:Show()
        end)

        spellId = id
        spellName = name
        spellIcon = icon
        addBtn:SetEnabled(spellId and buffId)
        spellIdEB.tip:SetTextColor(0, 1, 0, 0.777)
    end)

    -- 输入框占位提示文字
    spellIdEB.tip = spellIdEB:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    spellIdEB.tip:SetTextColor(0.4, 0.4, 0.4, 1)
    spellIdEB.tip:SetText(L["Spell"].." ID")
    spellIdEB.tip:SetPoint("RIGHT", -5, 0)

    -- ============ Buff ID 输入框 ============
    -- 大部分情况下 Buff ID 与 Spell ID 相同，但也允许手动输入不同 ID
    -- buffId editbox
    buffIdEB = Cell.CreateEditBox(spellEditFrame, 20, 20)
    buffIdEB:SetPoint("TOPLEFT", spellIdEB, "BOTTOMLEFT", 0, -5)
    buffIdEB:SetPoint("TOPRIGHT", spellIdEB, "BOTTOMRIGHT", 0, -5)
    buffIdEB:SetNumeric(true)
    -- Tab 键跳转回 Spell ID 输入框（仅在可编辑时）
    buffIdEB:SetScript("OnTabPressed", function()
        if spellIdEB:IsEnabled() then
            spellIdEB:SetFocus()
        end
    end)
    buffIdEB:SetScript("OnTextChanged", function()
        local id = tonumber(buffIdEB:GetText())
        if not id then
            -- 非法输入：禁用添加按钮，红色提示
            buffId = nil
            addBtn:SetEnabled(false)
            buffIdEB.tip:SetTextColor(1, 0, 0, 0.777)
            return
        end

        local name = F.GetSpellInfo(id)
        if not name then
            -- 无效 ID：禁用添加按钮，红色提示
            buffId = nil
            addBtn:SetEnabled(false)
            buffIdEB.tip:SetTextColor(1, 0, 0, 0.777)
            return
        end

        buffId = id
        addBtn:SetEnabled(spellId and buffId)
        buffIdEB.tip:SetTextColor(0, 1, 0, 0.777)
    end)

    -- 输入框占位提示文字
    buffIdEB.tip = buffIdEB:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    buffIdEB.tip:SetTextColor(0.4, 0.4, 0.4, 1)
    buffIdEB.tip:SetText(L["Buff"].." ID")
    buffIdEB.tip:SetPoint("RIGHT", -5, 0)

    -- ============ 取消按钮 ============
    -- cancel
    cancelBtn = Cell.CreateButton(spellEditFrame, L["Cancel"], "red", {50, 15})
    cancelBtn:SetPoint("BOTTOMRIGHT")
    cancelBtn:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))
    cancelBtn:SetScript("OnClick", function()
        spellEditFrame:Hide()
    end)

    -- ============ 添加/保存按钮 ============
    -- 默认显示 "Add"，编辑模式下显示 "Save"
    -- add
    addBtn = Cell.CreateButton(spellEditFrame, L["Add"], "green", {50, 15})
    addBtn:SetPoint("BOTTOMRIGHT", cancelBtn, "BOTTOMLEFT", P.Scale(1), 0)
    addBtn:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))
    addBtn:SetScript("OnClick", function()
        spellEditFrame:Hide()
    end)
end

-- ================================================================
-- ShowSpellEditFrame([index])
-- 显示技能编辑帧，支持两种模式：
--   无 index（添加模式）：SpellID 可编辑，按钮为 "Add"
--   有 index（编辑模式）：SpellID 不可编辑（只读），按钮为 "Save"
-- 添加模式下会检查技能是否已存在，新增后自动选中
-- ================================================================
ShowSpellEditFrame = function(index)
    Cell.frames.utilitiesTab.mask:Show()
    spellEditFrame:Show()

    if not index then -- 添加模式
        spellIdEB:SetEnabled(true)
        spellIdEB:SetFocus()

        title:SetText(L["Add new spell"])
        addBtn:SetText(L["Add"])

        addBtn:SetScript("OnClick", function()
            if spellId and buffId then
                -- 检查技能是否已存在于列表中
                -- check if exists
                for _, t in pairs(CellDB["spellRequest"]["spells"]) do
                    if t["spellId"] == spellId then
                        F.Print(L["Spell already exists."])
                        return
                    end
                end

                -- 写入数据库：创建新技能条目（默认类型为 icon，默认颜色为黄色）
                -- update db
                tinsert(CellDB["spellRequest"]["spells"], {
                    ["spellId"] = spellId,
                    ["buffId"] = buffId,
                    ["keywords"] = spellName,
                    ["icon"] = spellIcon,
                    ["type"] = "icon",
                    ["iconColor"] = {1, 1, 0, 1},
                    ["glowOptions"] = {
                        "pixel", -- [1] 发光类型
                        {
                            {0,1,0.5,1}, -- [1] 颜色
                            0, -- [2] x 偏移
                            0, -- [3] y 偏移
                            9, -- [4] 粒子数
                            0.25, -- [5] 频率
                            8, -- [6] 长度
                            2 -- [7] 厚度
                        } -- [2] 发光选项
                    }
                })
                Cell.Fire("UpdateRequests", "spellRequest_spells")

                local index = #CellDB["spellRequest"]["spells"]

                -- 更新下拉列表：添加新条目并自动选中
                -- update dropdown
                srSpellsDD:AddItem({
                    ["text"] = "|T"..spellIcon..":0::0:0:16:16:1:15:1:15|t "..spellName,
                    ["value"] = spellId,
                    ["onClick"] = function()
                        ShowSpellOptions(index)
                    end
                })
                srSpellsDD:SetSelectedValue(spellId)
                ShowSpellOptions(index)
            else
                F.Print(L["Invalid spell id."])
            end
            spellEditFrame:Hide()
        end)
    else -- 编辑模式
        spellIdEB:SetEnabled(false) -- Spell ID 不可修改
        buffIdEB:SetFocus()

        spellIdEB:SetText(CellDB["spellRequest"]["spells"][index]["spellId"])
        buffIdEB:SetText(CellDB["spellRequest"]["spells"][index]["buffId"])

        title:SetText(L["Edit spell"])
        addBtn:SetText(L["Save"])

        addBtn:SetScript("OnClick", function()
            if spellId and buffId then
                -- 更新数据库中的 Buff ID
                -- update db
                CellDB["spellRequest"]["spells"][index]["buffId"] = buffId
                Cell.Fire("UpdateRequests", "spellRequest_spells")

                -- 更新下拉列表中的当前条目
                -- update dropdown
                srSpellsDD:SetCurrentItem({
                    ["text"] = "|T"..spellIcon..":0::0:0:16:16:1:15:1:15|t "..spellName,
                    ["value"] = spellId,
                    ["onClick"] = function()
                        ShowSpellOptions(index)
                    end
                })
                srSpellsDD:SetSelectedValue(spellId)
                ShowSpellOptions(index)
            else
                F.Print(L["Invalid spell id."])
            end
            spellEditFrame:Hide()
        end)
    end
end

-------------------------------------------------
-- 创建技能请求图标（在单位按钮上显示）
-------------------------------------------------

-- ================================================================
-- GetValue(progress, start, delta)
-- 正弦波辅助函数：将 [0,1] 区间的 progress 映射为一个在 start
-- 到 start+delta 之间正弦波动的值，用于动画效果
-- ================================================================
local function GetValue(progress, start, delta)
    local angle = (progress * 2 * math.pi) - (math.pi / 2)
    return start + ((math.sin(angle) + 1) / 2) * delta
end

-- 正弦波辅助函数（备用，当前未使用）
-- local function GetSineValue(progress, scale)
--     return math.sin(progress * 2 * math.pi) * scale
-- end

-- ================================================================
-- U.CreateSpellRequestIcon(parent)
-- 在指定单位按钮的指示器区域创建技能请求图标帧
-- 支持四种动画类型：
--   "beat"   - 缩放脉冲动画
--   "bounce" - 位置弹跳动画
--   "blink"  - 透明度闪烁动画
--   其他/nil  - 无动画，静态显示
-- 显示时同时启用自定义发光效果（LibCustomGlow）
-- ================================================================
function U.CreateSpellRequestIcon(parent)
    local srIcon = CreateFrame("Frame", parent:GetName().."SpellRequestIcon", parent.widgets.indicatorFrame)
    parent.widgets.srIcon = srIcon
    srIcon:SetIgnoreParentAlpha(true)
    srIcon:SetFrameLevel(parent.widgets.indicatorFrame:GetFrameLevel()+110)
    srIcon:Hide()

    -- 背景纹理（当前注释掉，使用透明背景）
    -- srIcon:SetBackdrop({bgFile = Cell.vars.whiteTexture})
    -- srIcon:SetBackdropColor(0, 0, 0, 1)

    -- 图标纹理：显示技能图标，裁切边角以去除边框
    srIcon.icon = srIcon:CreateTexture(nil, "ARTWORK")
    srIcon.icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    P.Point(srIcon.icon, "TOPLEFT", srIcon, "TOPLEFT", 2, -2)
    P.Point(srIcon.icon, "BOTTOMRIGHT", srIcon, "BOTTOMRIGHT", -2, 2)

    -- ================================================================
    -- srIcon:Display(tex, color)
    -- 显示技能请求图标：设置纹理、重置缩放/透明度/位置/动画计时器，
    -- 并用指定颜色启动自定义发光效果
    -- ================================================================
    function srIcon:Display(tex, color)
        -- srIcon:SetBackdropColor(unpack(color))
        srIcon.icon:SetTexture(tex)

        -- 重置动画状态
        -- reset
        srIcon:SetScale(1)
        srIcon:SetAlpha(1)
        P.Repoint(srIcon)
        srIcon.elapsed = 0

        LCG.ButtonGlow_Start(srIcon, color)

        srIcon:Show()
    end

    -- 隐藏时停止发光效果
    srIcon:SetScript("OnHide", function()
        LCG.ButtonGlow_Stop(srIcon)
    end)

    -- ================================================================
    -- srIcon:SetAnimationType(type)
    -- 设置图标动画类型，通过 OnUpdate 脚本驱动
    -- ================================================================
    function srIcon:SetAnimationType(type)
        if type == "beat" then
            -- 缩放脉冲：在 0.9x ~ 1.0x 之间正弦波动
            srIcon:SetScript("OnUpdate", function(self, elapsed)
                srIcon.elapsed = (srIcon.elapsed or 0) + elapsed * 2
                srIcon:SetScale(GetValue(srIcon.elapsed, 0.9, 0.1))
                if srIcon.elapsed >= 1 then
                    srIcon.elapsed = 0
                end
            end)
        elseif type == "bounce" then
            -- 位置弹跳：沿预设方向正弦位移 0~7 像素
            srIcon:SetScript("OnUpdate", function(self, elapsed)
                srIcon.elapsed = (srIcon.elapsed or 0) + elapsed * 2
                srIcon:SetPoint(
                    CellDB["spellRequest"]["sharedIconOptions"][3],
                    parent.widgets.srGlowFrame,
                    CellDB["spellRequest"]["sharedIconOptions"][4],
                    CellDB["spellRequest"]["sharedIconOptions"][5],
                    CellDB["spellRequest"]["sharedIconOptions"][6] + GetValue(srIcon.elapsed / 1, 0, 7)
                )
            end)
        elseif type == "blink" then
            -- 闪烁：透明度在 0.75 ~ 1.0 之间正弦波动
            srIcon:SetScript("OnUpdate", function(self, elapsed)
                srIcon.elapsed = (srIcon.elapsed or 0) + elapsed * 2
                srIcon:SetAlpha(GetValue(srIcon.elapsed, 0.75, 0.25))
                if srIcon.elapsed >= 1 then
                    srIcon.elapsed = 0
                end
            end)
        else
            -- 无动画：清除 OnUpdate 脚本
            srIcon:SetScript("OnUpdate", nil)
        end
    end

    -- ================================================================
    -- srIcon:UpdatePixelPerfect()
    -- 像素完美更新：重新计算尺寸、锚点和图标位置，确保 UI 清晰
    -- ================================================================
    function srIcon:UpdatePixelPerfect()
        P.Resize(srIcon)
        P.Repoint(srIcon)
        P.Repoint(srIcon.icon)
    end
end

-------------------------------------------------
-- 面板显示入口
-------------------------------------------------
local init

-- ================================================================
-- ShowUtilitySettings(which)
-- 工具页面选项卡切换回调
--   which == "spellRequest": 首次调用时创建面板和编辑帧，后续只显示
--   which ~= "spellRequest": 隐藏面板
-- 首次初始化时从数据库加载所有设置值到 UI 控件
-- ================================================================
local function ShowUtilitySettings(which)
    if which == "spellRequest" then
        -- 延迟创建：首次访问时才创建 UI（节省资源）
        if not init then
            CreateSRPane()
            CreateSpellEditFrame()
        end

        srPane:Show()

        if init then return end
        init = true

        -- 从数据库加载所有设置到 UI 控件
        -- spell request
        srEnabledCB:SetChecked(CellDB["spellRequest"]["enabled"])
        srExistsCB:SetChecked(CellDB["spellRequest"]["checkIfExists"])
        srKnownOnlyCB:SetChecked(CellDB["spellRequest"]["knownSpellsOnly"])
        srFreeCDOnlyCB:SetChecked(CellDB["spellRequest"]["freeCooldownOnly"])
        srReplyCDCB:SetChecked(CellDB["spellRequest"]["replyCooldown"])
        srReplyCastEB:SetText(CellDB["spellRequest"]["replyAfterCast"] or "")
        if not CellDB["spellRequest"]["replyAfterCast"] then
            srReplyCastEB.tip:Show()
        end
        srResponseDD:SetSelectedValue(CellDB["spellRequest"]["responseType"])
        srTimeoutDD:SetSelected(CellDB["spellRequest"]["timeout"])
        UpdateSRWidgets()
        HideSpellOptions()
        LoadSpellsDropdown()

    elseif init then
        srPane:Hide()
    end
end
Cell.RegisterCallback("ShowUtilitySettings", "SpellRequest_ShowUtilitySettings", ShowUtilitySettings)
