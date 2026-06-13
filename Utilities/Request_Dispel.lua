-- Request_Dispel.lua
-- 驱散请求模块：处理团队/小队成员发送的驱散请求
-- 功能包括：接收驱散请求、在单位按钮上显示请求指示器（文字动画或发光效果）、
--           配置面板（启用/禁用、仅可驱散、响应类型、超时、宏、Debuff列表、显示类型等）

local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local U = Cell.uFuncs
local P = Cell.pixelPerfectFuncs

-- debuffItems 缓存已创建的 debuff 列表项按钮，按索引复用，避免重复创建
local debuffItems = {}
-- LoadList 前向声明，在 CreateDRPane 之后定义：刷新 debuff 列表显示
local LoadList

-------------------------------------------------
-- dispel request
-- 驱散请求配置面板：在 Cell 工具页签中创建设置界面
-------------------------------------------------
-- 配置面板主容器
local drPane
-- UI 控件引用：复选框、下拉菜单、文本标签、编辑框、列表、按钮等
local drEnabledCB, drDispellableCB, drResponseDD, drResponseText, drTimeoutDD, drTimeoutText, drMacroText, drMacroEB, drDebuffsText, drDebuffsList, drTypeDD, drTypeText, drTypeOptionsBtn
-- 当前选择的显示类型（"text" 文字 或 "glow" 发光）
local drType

-- UpdateDRWidgets: 根据启用状态和响应类型，更新各控件的启用/禁用状态
-- 当驱散请求未启用时，禁用大部分控件；当响应类型非 "specific" 时，遮罩 debuff 列表
local function UpdateDRWidgets()
    Cell.SetEnabled(CellDB["dispelRequest"]["enabled"], drDispellableCB, drResponseDD, drResponseText, drTimeoutDD, drTimeoutText, drMacroText, drMacroEB, drTypeDD, drTypeText, drTypeOptionsBtn)
    Cell.SetEnabled(CellDB["dispelRequest"]["enabled"] and CellDB["dispelRequest"]["responseType"] == "specific", drDebuffsText)
    if CellDB["dispelRequest"]["enabled"] and CellDB["dispelRequest"]["responseType"] == "specific" then
        drDebuffsList.mask:Hide()
    else
        drDebuffsList.mask:Show()
    end
end

-- CreateDRPane: 创建驱散请求的完整配置面板
-- 包含：启用开关、仅可驱散、响应类型、超时、宏编辑框、Debuff 列表、显示类型及其选项按钮
local function CreateDRPane()
    -- 创建带标题的面板容器，尺寸 422x183
    drPane = Cell.CreateTitledPane(Cell.frames.utilitiesTab, L["Dispel Request"], 422, 183)
    drPane:SetPoint("TOPLEFT", 5, -5)
    drPane:SetPoint("BOTTOMRIGHT", -5, 5)
    -- 面板隐藏时关闭所有弹出选项
    drPane:SetScript("OnHide", function()
        U.HideGlowOptions()
        U.HideTextOptions()
    end)

    -- 顶部提示文字：说明该功能的用途
    local drTips = drPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    drTips:SetPoint("TOPLEFT", 5, -25)
    drTips:SetJustifyH("LEFT")
    drTips:SetSpacing(5)
    drTips:SetText(L["Glow unit button when a group member sends a %s request"]:format(Cell.GetAccentColorString()..L["DISPEL"].."|r"))

    -- enabled ----------------------------------------------------------------------
    -- 启用/禁用驱散请求功能的复选框
    -- 切换时会更新所有子控件状态、触发 UpdateRequests 事件刷新请求处理
    drEnabledCB = Cell.CreateCheckButton(drPane, L["Enabled"], function(checked, self)
        CellDB["dispelRequest"]["enabled"] = checked
        UpdateDRWidgets()
        Cell.Fire("UpdateRequests", "dispelRequest")
        CellDropdownList:Hide()

        U.HideGlowOptions()
        U.HideTextOptions()
        Cell.StopRainbowText(drTypeOptionsBtn:GetFontString())
    end)
    drEnabledCB:SetPoint("TOPLEFT", drPane, "TOPLEFT", 5, -80)
    ---------------------------------------------------------------------------------

    -- dispellable ------------------------------------------------------------------
    -- "仅我可驱散"复选框：勾选后只响应自己能够驱散的 debuff 类型
    drDispellableCB = Cell.CreateCheckButton(drPane, L["Dispellable By Me"], function(checked, self)
        CellDB["dispelRequest"]["dispellableByMe"] = checked
        Cell.Fire("UpdateRequests", "dispelRequest")
    end)
    drDispellableCB:SetPoint("TOPLEFT", drEnabledCB, "TOPLEFT", 200, 0)
    ---------------------------------------------------------------------------------

    -- response ---------------------------------------------------------------------
    -- 响应类型下拉菜单：选择"响应所有可驱散 debuff"或"仅响应指定 debuff"
    -- "specific" 模式会启用下方的 debuff 列表，允许手动管理要响应的法术 ID
    drResponseDD = Cell.CreateDropdown(drPane, 345)
    drResponseDD:SetPoint("TOPLEFT", drEnabledCB, "BOTTOMLEFT", 0, -37)
    drResponseDD:SetItems({
        {
            ["text"] = L["Respond to all dispellable debuffs"],
            ["value"] = "all",
            ["onClick"] = function()
                CellDB["dispelRequest"]["responseType"] = "all"
                UpdateDRWidgets()
                Cell.Fire("UpdateRequests", "dispelRequest")
            end
        },
        {
            ["text"] = L["Respond to specific dispellable debuffs"],
            ["value"] = "specific",
            ["onClick"] = function()
                CellDB["dispelRequest"]["responseType"] = "specific"
                UpdateDRWidgets()
                Cell.Fire("UpdateRequests", "dispelRequest")
            end
        },
    })

    -- 响应类型标签文字
    drResponseText = drPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    drResponseText:SetPoint("BOTTOMLEFT", drResponseDD, "TOPLEFT", 0, 1)
    drResponseText:SetText(L["Response Type"])
    ---------------------------------------------------------------------------------

    -- timeout ----------------------------------------------------------------------
    -- 超时下拉菜单：驱散请求的显示持续时间（秒）
    -- 可选值：1, 2, 3, 4, 5, 10, 15, 20, 25, 30 秒
    drTimeoutDD = Cell.CreateDropdown(drPane, 60)
    drTimeoutDD:SetPoint("TOPLEFT", drResponseDD, "TOPRIGHT", 7, 0)

    local items = {}
    local secs = {1, 2, 3, 4, 5, 10, 15, 20, 25, 30}
    for _, s in ipairs(secs) do
        tinsert(items, {
            ["text"] = s,
            ["value"] = s,
            ["onClick"] = function()
                CellDB["dispelRequest"]["timeout"] = s
                Cell.Fire("UpdateRequests", "dispelRequest")
            end
        })
    end
    drTimeoutDD:SetItems(items)

    -- 超时标签文字
    drTimeoutText = drPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    drTimeoutText:SetPoint("BOTTOMLEFT", drTimeoutDD, "TOPLEFT", 0, 1)
    drTimeoutText:SetText(L["Timeout"])
    ---------------------------------------------------------------------------------

    -- macro ------------------------------------------------------------------------
    -- 宏编辑框：显示发送驱散请求的宏命令，用户可复制到游戏内宏使用
    -- 编辑框内容被锁定——任何用户修改都会被重置为默认宏文本
    drMacroEB = Cell.CreateEditBox(drPane, 412, 20)
    drMacroEB:SetPoint("TOPLEFT", drResponseDD, "BOTTOMLEFT", 0, -27)

    -- 预填发送驱散请求的插件通信宏
    drMacroEB:SetText("/run C_ChatInfo.SendAddonMessage(\"CELL_REQ_D\",\"D\",\"RAID\")")
    drMacroEB:SetCursorPosition(0)

    -- OnTextChanged: 阻止用户修改宏文本——任何改动都会被重置
    drMacroEB:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            drMacroEB:SetText("/run C_ChatInfo.SendAddonMessage(\"CELL_REQ_D\",\"D\",\"RAID\")")
            drMacroEB:SetCursorPosition(0)
            drMacroEB:HighlightText()
        end
    end)

    -- gauge 用于测量宏文本实际所需宽度，以便获得焦点时自动扩展编辑框
    drMacroEB.gauge = drMacroEB:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    drMacroEB.gauge:SetText(drMacroEB:GetText())

    -- OnEditFocusGained: 获得焦点时，如果文本宽度超出编辑框则自动扩展，并全选文本便于复制
    drMacroEB:SetScript("OnEditFocusGained", function()
        local requiredWidth = drMacroEB.gauge:GetStringWidth()
        if requiredWidth > drMacroEB:GetWidth() then
            P.Width(drMacroEB, requiredWidth + 20)
        end
        drMacroEB:HighlightText()
    end)

    -- OnEditFocusLost: 失去焦点时恢复编辑框原始宽度
    drMacroEB:SetScript("OnEditFocusLost", function()
        P.Width(drMacroEB, 412)
        drMacroEB:SetCursorPosition(0)
        drMacroEB:HighlightText(0, 0)
    end)

    -- 宏标签文字
    drMacroText = drPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    drMacroText:SetPoint("BOTTOMLEFT", drMacroEB, "TOPLEFT", 0, 1)
    drMacroText:SetText(L["Macro"])

    ---------------------------------------------------------------------------------

    -- debuffs ----------------------------------------------------------------------
    -- Debuff 列表容器：显示用户手动添加的特定 debuff 法术 ID 列表
    -- 仅当响应类型为 "specific" 时可用，包含滚动视图和遮罩
    drDebuffsList = CreateFrame("Frame", nil, drPane)
    drDebuffsList:SetPoint("TOPLEFT", drMacroEB, "BOTTOMLEFT", 0, -35)
    drDebuffsList:SetSize(270, 172)
    -- 创建滚动框架，支持滚轮浏览
    Cell.CreateScrollFrame(drDebuffsList)
    Cell.StylizeFrame(drDebuffsList.scrollFrame)
    drDebuffsList.scrollFrame:SetScrollStep(19)

    -- 遮罩层：当响应类型非 "specific" 时覆盖列表，阻止交互
    Cell.CreateMask(drDebuffsList)
    drDebuffsList.mask:Hide()

    -- 弹出编辑框：用于输入法术 ID 查询法术信息
    local popup = Cell.CreatePopupEditBox(drDebuffsList)
    popup:SetNumeric(true)
    -- OnTextChanged: 输入数字时实时显示对应法术的提示信息
    popup:SetScript("OnTextChanged", function()
        local spellId = tonumber(popup:GetText())
        if not spellId then
            CellSpellTooltip:Hide()
            return
        end

        local name, tex = F.GetSpellInfo(spellId)
        if not name then
            CellSpellTooltip:Hide()
            return
        end

        CellSpellTooltip:SetOwner(popup, "ANCHOR_NONE")
        CellSpellTooltip:SetPoint("TOPLEFT", popup, "BOTTOMLEFT", 0, -1)
        CellSpellTooltip:SetSpellByID(spellId, tex)
        CellSpellTooltip:Show()
    end)

    -- 弹出框隐藏时关闭法术提示
    popup:HookScript("OnHide", function()
        CellSpellTooltip:Hide()
    end)

    -- debuffItems[0] 是列表顶部的"添加"按钮，用于新增 debuff 法术 ID
    debuffItems[0] = Cell.CreateButton(drDebuffsList.scrollFrame.content, "", "transparent-accent", {20, 20})
    debuffItems[0]:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\new", {16, 16}, {"RIGHT", -1, 0})
    -- OnClick: 弹出输入框让用户输入法术 ID，验证通过后加入数据库并刷新列表
    debuffItems[0]:SetScript("OnClick", function(self)
        local popup = Cell.CreatePopupEditBox(drDebuffsList, function(text)
            local spellId = tonumber(text)
            local spellName = F.GetSpellInfo(spellId)
            if spellId and spellName then
                -- update db
                tinsert(CellDB["dispelRequest"]["debuffs"], spellId)
                LoadList(true)
            else
                F.Print(L["Invalid spell id."])
            end
        end)
        popup:SetPoint("TOPLEFT", self)
        popup:SetPoint("BOTTOMRIGHT", self)
        popup:ShowEditBox("")
        popup:SetFrameStrata("DIALOG")
        popup:SetTips("|cffababab"..L["Input spell id"])
    end)

    -- Debuff 列表标签文字
    drDebuffsText = drPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    drDebuffsText:SetPoint("BOTTOMLEFT", drDebuffsList, "TOPLEFT", 0, 1)
    drDebuffsText:SetText(L["Debuffs"])
    ---------------------------------------------------------------------------------

    -- type -------------------------------------------------------------------------
    -- 显示类型下拉菜单：选择驱散请求在单位按钮上的显示方式
    -- "Text" = 翻页动画图标；"Glow" = 按钮发光效果
    drTypeDD = Cell.CreateDropdown(drPane, 135)
    drTypeDD:SetPoint("TOPLEFT", drDebuffsList, "TOPRIGHT", 7, 0)
    drTypeDD:SetItems({
        {
            ["text"] = L["Text"],
            ["value"] = "text",
            ["onClick"] = function()
                U.HideGlowOptions()
                U.HideTextOptions()
                Cell.StopRainbowText(drTypeOptionsBtn:GetFontString())
                drTypeOptionsBtn:SetText(L["Text Options"])
                CellDB["dispelRequest"]["type"] = "text"
                drType = "text"
                Cell.Fire("UpdateRequests", "dispelRequest")
            end
        },
        {
            ["text"] = L["Glow"],
            ["value"] = "glow",
            ["onClick"] = function()
                U.HideGlowOptions()
                U.HideTextOptions()
                Cell.StopRainbowText(drTypeOptionsBtn:GetFontString())
                drTypeOptionsBtn:SetText(L["Glow Options"])
                CellDB["dispelRequest"]["type"] = "glow"
                drType = "glow"
                Cell.Fire("UpdateRequests", "dispelRequest")
            end
        },
    })

    -- 显示类型标签文字
    drTypeText = drPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    drTypeText:SetPoint("BOTTOMLEFT", drTypeDD, "TOPLEFT", 0, 1)
    drTypeText:SetText(L["Type"])

    ---------------------------------------------------------------------------------

    -- type option ------------------------------------------------------------------
    -- 类型选项按钮：根据当前选择的显示类型，打开对应的选项面板（文字选项或发光选项）
    -- 点击时切换彩虹文字效果作为视觉反馈
    drTypeOptionsBtn = Cell.CreateButton(drPane, L["Glow Options"], "accent", {135, 20})
    drTypeOptionsBtn:SetPoint("TOPLEFT", drTypeDD, "BOTTOMLEFT", 0, -15)
    -- OnClick: 切换彩虹文字效果，并根据 drType 弹出对应的选项面板
    drTypeOptionsBtn:SetScript("OnClick", function()
        local fs = drTypeOptionsBtn:GetFontString()
        if fs.rainbow then
            Cell.StopRainbowText(fs)
        else
            Cell.StartRainbowText(fs)
        end

        if drType == "text" then
            U.ShowTextOptions(Cell.frames.utilitiesTab)
        else
            U.ShowGlowOptions(Cell.frames.utilitiesTab, CellDB["dispelRequest"]["glowOptions"])
        end
    end)
    -- OnHide: 按钮隐藏时停止彩虹文字效果
    drTypeOptionsBtn:SetScript("OnHide", function()
        Cell.StopRainbowText(drTypeOptionsBtn:GetFontString())
    end)
    -- 注册为下拉菜单关闭触发器：点击此按钮时关闭所有打开的下拉菜单
    Cell.RegisterForCloseDropdown(drTypeOptionsBtn)
    ---------------------------------------------------------------------------------
end

-- LoadList: 刷新 debuff 列表显示
-- 遍历 CellDB["dispelRequest"]["debuffs"] 中的所有法术 ID，
-- 复用已创建的列表项按钮（debuffItems），按需创建新项，并填充法术图标、ID 和名称
-- @param scrollToBottom: 是否在加载后滚动到列表底部（新增 debuff 时使用）
LoadList = function(scrollToBottom)
    -- 重置滚动框架，清空内容高度
    drDebuffsList.scrollFrame:Reset()

    -- 添加按钮始终置于列表底部
    debuffItems[0]:SetParent(drDebuffsList.scrollFrame.content)
    debuffItems[0]:Show()
    debuffItems[0]:SetPoint("BOTTOMLEFT")
    debuffItems[0]:SetPoint("RIGHT")

    -- 遍历数据库中的所有 debuff 法术 ID
    for i, id in ipairs(CellDB["dispelRequest"]["debuffs"]) do
        -- 如果该索引的列表项尚未创建，则动态创建
        if not debuffItems[i] then
            debuffItems[i] = Cell.CreateButton(drDebuffsList.scrollFrame.content, "", "transparent-accent", {20, 20})

            -- icon 背景：黑色底衬
            debuffItems[i].spellIconBg = debuffItems[i]:CreateTexture(nil, "BORDER")
            debuffItems[i].spellIconBg:SetSize(16, 16)
            debuffItems[i].spellIconBg:SetPoint("TOPLEFT", 2, -2)
            debuffItems[i].spellIconBg:SetColorTexture(0, 0, 0, 1)
            debuffItems[i].spellIconBg:Hide()

            -- spellIcon: 法术图标纹理，裁剪边缘去除边框
            debuffItems[i].spellIcon = debuffItems[i]:CreateTexture(nil, "OVERLAY")
            debuffItems[i].spellIcon:SetPoint("TOPLEFT", debuffItems[i].spellIconBg, 1, -1)
            debuffItems[i].spellIcon:SetPoint("BOTTOMRIGHT", debuffItems[i].spellIconBg, -1, 1)
            debuffItems[i].spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            debuffItems[i].spellIcon:Hide()

            -- spellId text: 显示法术 ID 数字
            debuffItems[i].spellIdText = debuffItems[i]:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
            debuffItems[i].spellIdText:SetPoint("LEFT", debuffItems[i].spellIconBg, "RIGHT", 5, 0)
            debuffItems[i].spellIdText:SetPoint("RIGHT", debuffItems[i], "LEFT", 80, 0)
            debuffItems[i].spellIdText:SetWordWrap(false)
            debuffItems[i].spellIdText:SetJustifyH("LEFT")

            -- spellName text: 显示法术名称
            debuffItems[i].spellNameText = debuffItems[i]:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
            debuffItems[i].spellNameText:SetPoint("LEFT", debuffItems[i].spellIdText, "RIGHT", 5, 0)
            debuffItems[i].spellNameText:SetPoint("RIGHT", -20, 0)
            debuffItems[i].spellNameText:SetWordWrap(false)
            debuffItems[i].spellNameText:SetJustifyH("LEFT")

            -- del: 删除按钮，右对齐，hover 时高亮
            debuffItems[i].del = Cell.CreateButton(debuffItems[i], "", "none", {18, 20}, true, true)
            debuffItems[i].del:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\delete", {16, 16}, {"CENTER", 0, 0})
            debuffItems[i].del:SetPoint("RIGHT")
            debuffItems[i].del.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
            -- OnEnter: 鼠标进入时高亮删除图标，并触发父项的整体 hover 效果
            debuffItems[i].del:SetScript("OnEnter", function()
                debuffItems[i]:GetScript("OnEnter")(debuffItems[i])
                debuffItems[i].del.tex:SetVertexColor(1, 1, 1, 1)
            end)
            -- OnLeave: 鼠标离开时恢复删除图标颜色，并触发父项的离开效果
            debuffItems[i].del:SetScript("OnLeave",  function()
                debuffItems[i]:GetScript("OnLeave")(debuffItems[i])
                debuffItems[i].del.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
            end)

            -- tooltip: OnEnter 时在列表项左侧显示法术提示信息
            debuffItems[i]:HookScript("OnEnter", function(self)
                if not drDebuffsList.popupEditBox:IsShown() then
                    local name, icon = F.GetSpellInfo(self.spellId)
                    if not name then
                        CellSpellTooltip:Hide()
                        return
                    end

                    CellSpellTooltip:SetOwner(debuffItems[i], "ANCHOR_NONE")
                    CellSpellTooltip:SetPoint("TOPRIGHT", debuffItems[i], "TOPLEFT", -1, 0)
                    CellSpellTooltip:SetSpellByID(self.spellId, icon)
                    CellSpellTooltip:Show()
                end
            end)
            -- OnLeave: 鼠标离开时隐藏法术提示
            debuffItems[i]:HookScript("OnLeave", function()
                if not drDebuffsList.popupEditBox:IsShown() then
                    CellSpellTooltip:Hide()
                end
            end)
        end

        -- 获取法术信息
        local name, icon = F.GetSpellInfo(id)

        -- 更新列表项数据
        debuffItems[i].spellId = id
        debuffItems[i].spellIdText:SetText(id)
        debuffItems[i].spellNameText:SetText(name or "|cffff2222"..L["Invalid"])

        -- 根据是否有图标来显示或隐藏图标区域
        if icon then
            debuffItems[i].spellIcon:SetTexture(icon)
            debuffItems[i].spellIcon:Show()
            debuffItems[i].spellIconBg:Show()
        else
            debuffItems[i].spellIcon:Hide()
            debuffItems[i].spellIconBg:Hide()
        end


        -- 删除按钮点击：从数据库中移除该法术 ID，触发更新并刷新列表
        debuffItems[i].del:SetScript("OnClick", function()
            tremove(CellDB["dispelRequest"]["debuffs"], i)
            Cell.Fire("UpdateRequests", "dispelRequest")
            LoadList()
        end)

        -- 将列表项挂载到滚动内容区域并显示
        debuffItems[i]:SetParent(drDebuffsList.scrollFrame.content)
        debuffItems[i]:Show()

        -- 布局：首项锚定左上角，后续项依次向下排列
        debuffItems[i]:SetPoint("RIGHT")
        if i == 1 then
            debuffItems[i]:SetPoint("TOPLEFT")
        else
            debuffItems[i]:SetPoint("TOPLEFT", debuffItems[i-1], "BOTTOMLEFT", 0, 1)
        end
    end

    -- 根据列表项数量设置滚动内容高度（每项 20px，+1 为添加按钮留空间）
    drDebuffsList.scrollFrame:SetContentHeight(20, #CellDB["dispelRequest"]["debuffs"]+1, -1)

    -- 新增 debuff 后自动滚动到底部
    if scrollToBottom then
        drDebuffsList.scrollFrame:ScrollToBottom()
    end
end

-------------------------------------------------
-- create text
-- 创建驱散请求文字指示器（翻页动画）
-- 在单位按钮的 indicatorFrame 上创建一个翻页动画帧，
-- 用于显示驱散请求图标（A/B/C 三种样式）
-------------------------------------------------
-- flipBookFrames: 各翻页动画类型的总帧数
-- A/B/C 对应不同的美术资源，帧数不同
local flipBookFrames = {
    ["A"] = 31,
    ["B"] = 30,
    ["C"] = 25,
}

-- U.CreateDispelRequestText: 在指定 parent 的指示器帧上创建驱散请求文字/动画显示
-- @param parent: Cell 单位按钮对象，包含 widgets.indicatorFrame 子帧
function U.CreateDispelRequestText(parent)
    -- 创建命名子帧，挂载在 indicatorFrame 上
    local drText = CreateFrame("Frame", parent:GetName().."DispelRequestText", parent.widgets.indicatorFrame)
    parent.widgets.drText = drText
    drText:SetIgnoreParentAlpha(true)
    -- 设置较高的帧层级，确保显示在其他指示器之上
    drText:SetFrameLevel(parent.widgets.indicatorFrame:GetFrameLevel()+110)
    drText:Hide()

    -- 翻页动画纹理：使用 FlipBook 动画系统逐帧播放
    local tex = drText:CreateTexture(nil, "ARTWORK")
    -- tex:SetTexture("Interface/AddOns/Cell/Media/FlipBooks/dispel.png")
    --tex:SetAtlas("UI-HUD-ActionBar-GCD-Flipbook")
    --tex:SetTexture("interface/hud/uiactionbarfx")
    --tex:SetTexCoord(0.412598, 0.458496, 0.393555, 0.898438) -- NOTE: SetTexCoord will NOT work
    tex:SetAllPoints(drText)
    tex:SetParentKey("Flipbook")  -- 设置父键，让 FlipBook 动画通过此键引用纹理

    -- 创建循环动画组
    local ag = drText:CreateAnimationGroup()
    ag:SetLooping("REPEAT")

    -- FlipBook 动画：8 行 x 4 列 = 32 格 spritesheet，播放时长 1 秒
    local flip = ag:CreateAnimation("FlipBook")
    flip:SetDuration(1)
    flip:SetFlipBookRows(8)
    flip:SetFlipBookColumns(4)
    flip:SetFlipBookFrames(31)  -- 默认 31 帧（对应 A 类型）
    --flip:SetFlipBookFrameWidth(0)
    --flip:SetFlipBookFrameHeight(0)
    flip:SetChildKey("Flipbook")  -- 关联到上方纹理的 ParentKey

    -- drText:Display: 显示驱散请求指示器并开始播放动画
    function drText:Display()
        drText:Show()
        ag:Play()
    end

    -- drText:SetType: 根据类型切换纹理资源和帧数
    -- @param type: "A" / "B" / "C"，对应不同的翻页动画资源文件
    function drText:SetType(type)
        tex:SetTexture("Interface/AddOns/Cell/Media/FlipBooks/dispel_"..type..".png")
        flip:SetFlipBookFrames(flipBookFrames[type])
    end

    -- drText:SetColor: 设置动画纹理的颜色（RGBA）
    -- @param color: {r, g, b, a} 表
    function drText:SetColor(color)
        tex:SetVertexColor(unpack(color))
    end
end

-------------------------------------------------
-- show
-- 工具页签切换回调：根据选中的设置项显示或隐藏驱散请求面板
-------------------------------------------------
-- init 标志：确保面板控件只初始化一次，后续切换时仅显示/隐藏
local init
-- ShowUtilitySettings: 响应 "ShowUtilitySettings" 事件的回调
-- @param which: 当前选中的设置项标识，如 "dispelRequest"
local function ShowUtilitySettings(which)
    if which == "dispelRequest" then
        -- 首次调用时创建面板（懒加载）
        if not init then
            CreateDRPane()
        end

        drPane:Show()

        -- 面板已初始化过，无需重复设置控件值
        if init then return end
        init = true

        -- dispel request: 首次显示时从数据库同步所有控件状态
        drEnabledCB:SetChecked(CellDB["dispelRequest"]["enabled"])
        drDispellableCB:SetChecked(CellDB["dispelRequest"]["dispellableByMe"])
        drResponseDD:SetSelectedValue(CellDB["dispelRequest"]["responseType"])
        drTimeoutDD:SetSelected(CellDB["dispelRequest"]["timeout"])
        drTypeDD:SetSelectedValue(CellDB["dispelRequest"]["type"])
        -- 根据当前设置更新控件启用/禁用状态
        UpdateDRWidgets()
        -- 加载 debuff 列表
        LoadList()

        -- 同步 drType 变量并设置选项按钮文字
        drType = CellDB["dispelRequest"]["type"]
        if drType == "text" then
            drTypeOptionsBtn:SetText(L["Text Options"])
        else
            drTypeOptionsBtn:SetText(L["Glow Options"])
        end

    elseif init then
        -- 切换到其他设置项时隐藏面板
        drPane:Hide()
    end
end
-- 注册 ShowUtilitySettings 回调：当用户切换工具页签中的设置项时触发
Cell.RegisterCallback("ShowUtilitySettings", "DispelRequest_ShowUtilitySettings", ShowUtilitySettings)