-- =========================================================================== --
-- QuickCast.lua                                                               --
-- 快速施法模块：在团队/小队中创建可点击的快捷施法按钮，支持 Buff 监控、        --
-- 施法光效、内外圈冷却显示、单位拖拽绑定等功能。设置按专精独立保存。           --
-- =========================================================================== --

local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local U = Cell.uFuncs
local A = Cell.animations
local P = Cell.pixelPerfectFuncs

-- 第三方库：自定义光效 LibCustomGlow-1.0 和音译库 LibTranslit-1.0
local LCG = LibStub("LibCustomGlow-1.0")
local LibTranslit = LibStub("LibTranslit-1.0")

-- ----------------------------------------------------------------------- --
--                                quick cast                               --
-- ----------------------------------------------------------------------- --
-- quickCastTable: 当前专精的快捷施法配置表（指向 CellDB 或默认表）
-- previewButtons: 设置界面中的预览按钮框架列表（灰色半透明覆盖层）
-- UpdatePreview / CreateQuickCastButton: 前向声明，供各 UI 控件回调使用
local quickCastTable
local previewButtons = {}
local UpdatePreview, CreateQuickCastButton

-- 默认配置：所有字段的初始值，新建专精配置时从此拷贝
local defaultQuickCastTable = {
    ["enabled"] = false,              -- 是否启用快捷施法
    ["namePosition"] = "RIGHT",       -- 名字文本相对按钮的位置：LEFT/RIGHT/TOP/BOTTOM/none
    ["num"] = 4,                      -- 最大按钮数量（1-6）
    ["orientation"] = "top-to-bottom",-- 排列方向：left-to-right / right-to-left / top-to-bottom / bottom-to-top
    ["size"] = 25,                    -- 按钮尺寸（像素，16-64）
    ["lines"] = 6,                    -- 每行/列的按钮数（1-6）
    ["spacingX"] = 3,                 -- 按钮水平间距
    ["spacingY"] = 3,                 -- 按钮垂直间距
    ["glowBuffsColor"] = {1, 1, 0, 1},    -- Buff 光效颜色 {R, G, B, A}
    ["glowBuffs"] = {},               -- 触发光效的 Buff 法术 ID 列表
    ["glowCastsColor"] = {1, 0, 1, 1},    -- 施法光效颜色 {R, G, B, A}
    ["glowCasts"] = {},               -- 触发光效的施法法术 ID:持续时间 列表
    ["outerColor"] = {0.11, 0.74, 0.9},   -- 外圈冷却颜色（左键施法）
    ["outerBuff"] = 0,                -- 外圈冷却对应的 Buff 法术 ID
    ["innerColor"] = {0.95, 0.32, 0.37},  -- 内圈冷却颜色（右键施法）
    ["innerBuff"] = 0,                -- 内圈冷却对应的 Buff 法术 ID
    ["units"] = {},                   -- 每个按钮绑定的单位 token（如 "raid1"）
    ["position"] = {},                -- quickCastFrame 的位置保存数据
}

-- ----------------------------------------------------------------------- --
--                              option widgets                             --
-- ----------------------------------------------------------------------- --
-- 设置面板及弹窗输入框
local qcPane, qcAddEB
-- 基础设置控件：启用复选框、名字下拉、名字文本标签、按钮数量滑块、尺寸滑块
-- 排列方向下拉、排列方向文本标签、水平间距滑块、垂直间距滑块、行列数滑块
local qcEnabledCB, qcNameDD, qcNameText, qcButtonsSlider, qcSizeSlider, qcOrientationDD, qcOrientationText, qcSpacingXSlider, qcSpacingYSlider, qcLinesSlider
-- 外圈 Buff：颜色选择器、法术选择按钮
local qcOuterCP, qcOuterBtn
-- 内圈 Buff：颜色选择器、法术选择按钮
local qcInnerCP, qcInnerBtn

-- Buff 光效按钮列表、面板、颜色选择器、添加按钮
local qcGlowBuffsButtons = {}
local qcGlowBuffsPane, qcGlowBuffsCP, qcGlowBuffsAddBtn

-- 施法光效按钮列表、面板、颜色选择器、添加按钮
local qcGlowCastsButtons = {}
local qcGlowCastsPane, qcGlowCastsCP, qcGlowCastsAddBtn

-- 根据 quickCastTable["enabled"] 统一启用/禁用所有设置控件
local function UpdateWidgets()
    Cell.SetEnabled(quickCastTable["enabled"], qcNameDD, qcNameText, qcButtonsSlider, qcSizeSlider, qcOrientationDD, qcOrientationText, qcSpacingXSlider, qcSpacingYSlider, qcLinesSlider)
    Cell.SetEnabled(quickCastTable["enabled"], qcOuterCP, qcOuterBtn, qcInnerCP, qcInnerBtn, qcGlowBuffsCP, qcGlowBuffsAddBtn, qcGlowCastsCP, qcGlowCastsAddBtn)

    for _, b in pairs(qcGlowBuffsButtons) do
        b:SetEnabled(quickCastTable["enabled"])
    end

    for _, b in pairs(qcGlowCastsButtons) do
        b:SetEnabled(quickCastTable["enabled"])
    end
end

-- ----------------------------------------------------------------------- --
--                                main pane                                --
-- ----------------------------------------------------------------------- --
-- 创建主设置面板：包含启用、名字、按钮数量、排列方向、行列数、尺寸、间距等控件
local function CreateQCPane()
    -- 创建带标题的面板，提示仅在小队中可用
    qcPane = Cell.CreateTitledPane(Cell.frames.utilitiesTab, L["Quick Cast"].." |cFF777777"..L["only in group"], 422, 250)
    qcPane:SetPoint("TOPLEFT", 5, -5)
    qcPane:SetPoint("BOTTOMRIGHT", -5, 5)
    qcPane:Hide()

    -- 顶部功能说明文本（跨两行）
    local qcTips = qcPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    qcTips:SetPoint("TOPLEFT", 5, -25)
    qcTips:SetJustifyH("LEFT")
    qcTips:SetSpacing(5)
    qcTips:SetText(L["Create several buttons for quick casting and buff monitoring"].."\n"..L["These settings are spec-specific"])

    -- enabled ----------------------------------------------------------------------
    -- 启用复选框：勾选时初始化当前专精配置（如果不存在则从默认表拷贝），触发全局更新
    qcEnabledCB = Cell.CreateCheckButton(qcPane, L["Enabled"], function(checked, self)
        if not CellDB["quickCast"][Cell.vars.playerClass] then
            CellDB["quickCast"][Cell.vars.playerClass] = {}
        end

        if not CellDB["quickCast"][Cell.vars.playerClass][Cell.vars.playerSpecID] then
            CellDB["quickCast"][Cell.vars.playerClass][Cell.vars.playerSpecID] = F.Copy(defaultQuickCastTable)
        end

        CellDB["quickCast"][Cell.vars.playerClass][Cell.vars.playerSpecID]["enabled"] = checked

        Cell.Fire("UpdateQuickCast")
        UpdateWidgets()
        UpdatePreview()
    end)
    qcEnabledCB:SetPoint("TOPLEFT", qcPane, 5, -75)

    -- name -------------------------------------------------------------------------
    -- 名字文本位置下拉框：None / LEFT / RIGHT / TOP / BOTTOM
    qcNameDD = Cell.CreateDropdown(qcPane, 120)
    qcNameDD:SetPoint("TOPLEFT", qcPane, 297, -75)

    local anchorPoints = {"LEFT", "RIGHT", "TOP", "BOTTOM"}
    local items = {}
    tinsert(items, {
        ["text"] = L["None"],
        ["value"] = "none",
        ["onClick"] = function()
            quickCastTable["namePosition"] = "none"
            UpdatePreview()
            Cell.Fire("UpdateQuickCast")
        end
    })
    for _, point in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[point],
            ["value"] = point,
            ["onClick"] = function()
                quickCastTable["namePosition"] = point
                UpdatePreview()
                Cell.Fire("UpdateQuickCast")
            end
        })
    end
    qcNameDD:SetItems(items)

    -- 名字文本标签（显示在下拉框上方）
    qcNameText = qcPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    qcNameText:SetText(L["Name Text"])
    qcNameText:SetPoint("BOTTOMLEFT", qcNameDD, "TOPLEFT", 0, 1)

    -- buttons ----------------------------------------------------------------------
    -- 最大按钮数量滑块：1-6，步长 1
    qcButtonsSlider = Cell.CreateSlider(L["Max Buttons"], qcPane, 1, 6, 120, 1, function(value)
        quickCastTable["num"] = value
        UpdatePreview()
        Cell.Fire("UpdateQuickCast")
    end)
    qcButtonsSlider:SetPoint("TOPLEFT", qcEnabledCB, 0, -55)

    -- orientation ------------------------------------------------------------------
    -- 排列方向下拉框：四种方向，选择 top/bottom 时行列标签显示"Rows"，left/right 时显示"Columns"
    qcOrientationDD = Cell.CreateDropdown(qcPane, 120)
    qcOrientationDD:SetPoint("TOPLEFT", qcButtonsSlider, 146, 0)
    qcOrientationDD:SetItems({
        {
            ["text"] = L["left-to-right"],
            ["value"] = "left-to-right",
            ["onClick"] = function()
                qcLinesSlider:SetLabel(L["Columns"])
                quickCastTable["orientation"] = "left-to-right"
                Cell.Fire("UpdateQuickCast")
            end
        },
        {
            ["text"] = L["right-to-left"],
            ["value"] = "right-to-left",
            ["onClick"] = function()
                qcLinesSlider:SetLabel(L["Columns"])
                quickCastTable["orientation"] = "right-to-left"
                Cell.Fire("UpdateQuickCast")
            end
        },
        {
            ["text"] = L["top-to-bottom"],
            ["value"] = "top-to-bottom",
            ["onClick"] = function()
                qcLinesSlider:SetLabel(L["Rows"])
                quickCastTable["orientation"] = "top-to-bottom"
                Cell.Fire("UpdateQuickCast")
            end
        },
        {
            ["text"] = L["bottom-to-top"],
            ["value"] = "bottom-to-top",
            ["onClick"] = function()
                qcLinesSlider:SetLabel(L["Rows"])
                quickCastTable["orientation"] = "bottom-to-top"
                Cell.Fire("UpdateQuickCast")
            end
        },
    })

    -- 排列方向文本标签（显示在下拉框上方）
    qcOrientationText = qcPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    qcOrientationText:SetText(L["Orientation"])
    qcOrientationText:SetPoint("BOTTOMLEFT", qcOrientationDD, "TOPLEFT", 0, 1)

    -- row/column -------------------------------------------------------------------
    -- 行/列数滑块：根据排列方向动态切换标签为"Columns"或"Rows"
    qcLinesSlider = Cell.CreateSlider(L["Columns"], qcPane, 1, 6, 120, 1, function(value)
        quickCastTable["lines"] = value
        Cell.Fire("UpdateQuickCast")
    end)
    qcLinesSlider:SetPoint("TOPLEFT", qcOrientationDD, 146, 0)

    -- size -------------------------------------------------------------------------
    -- 按钮尺寸滑块：16-64 像素
    qcSizeSlider = Cell.CreateSlider(L["Size"], qcPane, 16, 64, 120, 1, function(value)
        quickCastTable["size"] = value
        UpdatePreview()
        Cell.Fire("UpdateQuickCast")
    end)
    qcSizeSlider:SetPoint("TOPLEFT", qcButtonsSlider, 0, -55)

    -- spacingX ---------------------------------------------------------------------
    -- 水平间距滑块：0-64 像素
    qcSpacingXSlider = Cell.CreateSlider(L["Spacing"].." X", qcPane, 0, 64, 120, 1, function(value)
        quickCastTable["spacingX"] = value
        Cell.Fire("UpdateQuickCast")
    end)
    qcSpacingXSlider:SetPoint("TOPLEFT", qcSizeSlider, 146, 0)

    -- spacingY ---------------------------------------------------------------------
    -- 垂直间距滑块：0-64 像素
    qcSpacingYSlider = Cell.CreateSlider(L["Spacing"].." Y", qcPane, 0, 64, 120, 1, function(value)
        quickCastTable["spacingY"] = value
        Cell.Fire("UpdateQuickCast")
    end)
    qcSpacingYSlider:SetPoint("TOPLEFT", qcSpacingXSlider, 146, 0)

    -- input ------------------------------------------------------------------------
    -- 法术 ID 输入框：输入数字后自动显示对应法术的提示信息
    qcAddEB = Cell.CreatePopupEditBox(qcPane)
    qcAddEB:SetNumeric(true)
    qcAddEB:SetFrameStrata("DIALOG")

    -- 输入文本变化时：解析法术 ID 并在输入框下方显示法术提示
    qcAddEB:SetScript("OnTextChanged", function()
        local spellId = tonumber(qcAddEB:GetText())
        if not spellId then
            CellSpellTooltip:Hide()
            return
        end

        local name, icon = F.GetSpellInfo(spellId)
        if not name then
            CellSpellTooltip:Hide()
            return
        end

        CellSpellTooltip:SetOwner(qcAddEB, "ANCHOR_NONE")
        CellSpellTooltip:SetPoint("TOPLEFT", qcAddEB, "BOTTOMLEFT", 0, -1)
        CellSpellTooltip:SetSpellByID(spellId, icon)
        CellSpellTooltip:Show()
    end)

    -- 输入框显示时设置提示文字
    qcAddEB:HookScript("OnShow", function()
        qcAddEB:SetTips("|cffababab"..L["Input spell id"])
    end)

    -- 输入框隐藏时隐藏法术提示
    qcAddEB:HookScript("OnHide", function()
        CellSpellTooltip:Hide()
    end)

    -- tips -------------------------------------------------------------------------
    -- 底部操作提示：右键可以删除已有的光效条目
    local tips = qcPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    tips:SetText("|cffababab"..L["Tip: right-click to delete"])
    tips:SetPoint("BOTTOMLEFT")
end

-- ----------------------------------------------------------------------- --
--                                 preview                                 --
-- ----------------------------------------------------------------------- --
-- 设置面板右侧的预览区和预览按钮，实时反映当前配置的外观效果
local previewFrame, previewPane, previewButton

-- 更新预览按钮：根据 quickCastTable 的各项设置刷新预览按钮的尺寸、名字位置、颜色
UpdatePreview = function()
    -- 首次调用时创建预览按钮并配置模拟动画（Buff 光效、施法光效、外圈、内圈循环演示）
    if not previewButton then
        previewButton = CreateQuickCastButton(previewPane, "CellQuickCastPreviewButton", true)
        previewButton:SetPoint("TOP", previewPane, 0, -55)

        local _r, _g, _b = F.GetClassColor(Cell.vars.playerClass)
        previewButton._r, previewButton._g, previewButton._b = _r, _g, _b
        previewButton.nameText:SetTextColor(_r, _g, _b)

        -- 截取玩家名字用于预览显示：英文取前 3 字符，中文取前 1 字符
        local name = Cell.vars.playerNameShort
        name = Cell.vars.nicknameCustoms[name] or Cell.vars.nicknames[name] or name
        if string.len(name) == string.utf8len(name) then -- en
            previewButton.nameText:SetText(string.utf8sub(name, 1, 3))
        else
            previewButton.nameText:SetText(string.utf8sub(name, 1, 1))
        end

        -- 预览按钮的 OnUpdate：循环模拟光效和冷却动画，让用户直观看到效果
        local timer
        previewButton:SetScript("OnUpdate", function(self, elapsed)
            self.glowBuffElapsed = (self.glowBuffElapsed or 0) + elapsed
            self.outerElapsed = (self.outerElapsed or 0) + elapsed
            self.innerElapsed = (self.innerElapsed or 0) + elapsed

            -- 每 20 秒触发一次 Buff 光效（5 秒冷却），10 秒后触发施法光效
            if self.glowBuffElapsed >= 20 then
                self.glowBuffElapsed = 0
                self:SetGlowBuffCooldown(GetTime(), 5)
                timer = C_Timer.NewTimer(10, function()
                    self:SetGlowCastCooldown(GetTime(), 5)
                end)
            end

            -- 每 10 秒触发一次外圈冷却动画（7 秒冷却）
            if self.outerElapsed >= 10 then
                self.outerElapsed = 0
                self:SetOuterCooldown(GetTime(), 7)
            end

            -- 每 10 秒触发一次内圈冷却动画（10 秒冷却）
            if self.innerElapsed >= 10 then
                self.innerElapsed = 0
                self:SetInnerCooldown(GetTime(), 10)
            end
        end)

        -- 预览按钮隐藏时取消定时器，防止内存泄漏
        previewButton:SetScript("OnHide", function(self)
            if timer then
                timer:Cancel()
                timer = nil
            end
        end)

        -- 预览按钮显示时重置所有动画计时器并立即展示效果
        previewButton:SetScript("OnShow", function(self)
            self.glowBuffElapsed = 0
            self.outerElapsed = 0
            self.innerElapsed = 0
            self:SetGlowBuffCooldown(GetTime(), 5)
            self:SetGlowCastCooldown()
            timer = C_Timer.NewTimer(10, function()
                self:SetGlowCastCooldown(GetTime(), 5)
            end)
            self:SetOuterCooldown(GetTime(), 7)
            self:SetInnerCooldown(GetTime(), 10)
        end)
    end

    -- 应用当前配置到预览按钮
    previewButton:SetSize(quickCastTable["size"])
    previewButton:SetNamePosition(quickCastTable["namePosition"])
    previewButton:SetColor(quickCastTable["glowBuffsColor"],  quickCastTable["glowCastsColor"], quickCastTable["outerColor"], quickCastTable["innerColor"])
    previewButton:Show()

    -- 根据按钮尺寸调整预览框架大小
    P.Size(previewFrame, 100+quickCastTable["size"], 100+quickCastTable["size"])

    -- 根据启用状态和按钮数量显示/隐藏覆盖层标记
    for i, p in pairs(previewButtons) do
        if quickCastTable["enabled"] and i <= quickCastTable["num"] then
            p:Show()
        else
            p:Hide()
        end
    end
end

-- 创建预览框架：位于 CellOptionsFrame 右侧，包含标题面板和操作提示
local function CreatePreviewFrame()
    previewFrame = Cell.CreateFrame(nil, qcPane, 130, 130)
    previewFrame:SetPoint("TOPLEFT", CellOptionsFrame, "TOPRIGHT", 5, -80)
    previewFrame:Show()

    previewPane = Cell.CreateTitledPane(previewFrame, L["Preview"], 130, 130)
    previewPane:SetPoint("TOPLEFT", 5, -5)
    previewPane:SetPoint("BOTTOMRIGHT", -5, 5)

    -- 操作提示按钮：说明左键施放外圈法术、右键施放内圈法术、Shift+左键拖拽设置单位等
    local tips = Cell.CreateTipsButton(previewPane, 17, {"TOPLEFT", previewPane, "TOPRIGHT", 10, 0},
        L["Quick Cast"],
        {"|cffffb5c5"..L["Left-Click"]..":", L["cast Outer spell"]},
        {"|cffffb5c5"..L["Right-Click"]..":", L["cast Inner spell"]},
        {"|cffffb5c5Shift+"..L["Left-Drag"]..":", L["set unit"]},
        {"|cffffb5c5Shift+"..L["Right-Click"]..":", L["clear unit"]},
        {"|cffffb5c5Alt+"..L["Left-Drag"]..":", L["move"]}
    )
end

-- ----------------------------------------------------------------------- --
--                        outer / inner spell button                       --
-- ----------------------------------------------------------------------- --
-- 创建法术选择按钮（外圈/内圈共用）：左键点击弹出法术 ID 输入框，右键点击清除法术
-- parent: 父框架
-- func: 选择/清除法术后的回调函数，参数为法术 ID（0 表示清除）
local function CreateSpellButton(parent, func)
    local b = Cell.CreateButton(parent, " ", "accent-hover", {195, 20})
    b:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create", {16, 16}, {"LEFT", 2, 0})
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:GetFontString():SetJustifyH("LEFT")

    -- 点击事件：左键弹出输入框设置法术，右键清除法术
    b:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            -- 左键：弹出法术 ID 输入弹窗，确认后设置法术名称和图标
            local popup = Cell.CreatePopupEditBox(qcPane, function(text)
                local spellId = tonumber(text)
                local spellName, spellIcon = F.GetSpellInfo(spellId)
                if spellId and spellName then
                    b.id = spellId
                    b.icon = spellIcon
                    b:SetText(spellName)
                    b.tex:SetTexture(spellIcon)
                    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    func(spellId)
                    Cell.Fire("UpdateQuickCast")
                else
                    F.Print(L["Invalid spell id."])
                end
            end)
            popup:ClearAllPoints()
            popup:SetAllPoints(b)
            popup:ShowEditBox("")
        else
            -- 右键：清除法术，恢复默认图标
            b.id = nil
            b.icon = nil
            b:SetText("")
            b.tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create")
            b.tex:SetTexCoord(0, 1, 0, 1)
            func(0)
            Cell.Fire("UpdateQuickCast")
        end
    end)

    -- 鼠标悬停时显示法术提示
    b:HookScript("OnEnter", function(self)
        if self.id and self.icon then
            CellSpellTooltip:SetOwner(self, "ANCHOR_NONE")
            CellSpellTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
            CellSpellTooltip:SetSpellByID(self.id, self.icon)
            CellSpellTooltip:Show()
        end
    end)

    -- 鼠标离开时隐藏法术提示
    b:HookScript("OnLeave", function(self)
        CellSpellTooltip:Hide()
    end)

    return b
end

-- ----------------------------------------------------------------------- --
--                                  outer                                  --
-- ----------------------------------------------------------------------- --
-- 创建外圈 Buff 设置面板：包含颜色选择器和外圈法术选择按钮（对应左键施法）
local function CreateOuterPane()
    local qcOuterPane = Cell.CreateTitledPane(qcPane, L["Outer Buff"], 205, 80)
    qcOuterPane:SetPoint("TOPLEFT", 0, -250)

    -- 左键图标提示（表示外圈法术通过左键施放）
    local tip = qcOuterPane:CreateTexture(nil, "ARTWORK")
    tip:SetPoint("BOTTOMRIGHT", qcOuterPane.line, "TOPRIGHT", 0, P.Scale(2))
    tip:SetSize(16, 16)
    tip:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\left-click")

    -- 外圈颜色选择器
    qcOuterCP = Cell.CreateColorPicker(qcOuterPane, L["Color"], false, nil, function(r, g, b)
        quickCastTable["outerColor"][1] = r
        quickCastTable["outerColor"][2] = g
        quickCastTable["outerColor"][3] = b
        UpdatePreview()
        Cell.Fire("UpdateQuickCast")
    end)
    qcOuterCP:SetPoint("TOPLEFT", 5, -27)

    -- spell ------------------------------------------------------------------------
    -- 外圈法术选择按钮
    qcOuterBtn = CreateSpellButton(qcOuterPane, function(spellId)
        quickCastTable["outerBuff"] = spellId
    end)
    qcOuterBtn:SetPoint("TOPLEFT", qcOuterCP, "BOTTOMLEFT", 0, -10)
end

-- ----------------------------------------------------------------------- --
--                                  inner                                  --
-- ----------------------------------------------------------------------- --
-- 创建内圈 Buff 设置面板：包含颜色选择器和内圈法术选择按钮（对应右键施法）
local function CreateInnerPane()
    local qcInnerPane = Cell.CreateTitledPane(qcPane, L["Inner Buff"], 205, 80)
    qcInnerPane:SetPoint("TOPLEFT", 217, -250)

    -- 右键图标提示（表示内圈法术通过右键施放）
    local tip = qcInnerPane:CreateTexture(nil, "ARTWORK")
    tip:SetPoint("BOTTOMRIGHT", qcInnerPane.line, "TOPRIGHT", 0, P.Scale(2))
    tip:SetSize(16, 16)
    tip:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\right-click")

    -- 内圈颜色选择器
    qcInnerCP = Cell.CreateColorPicker(qcInnerPane, L["Color"], false, nil, function(r, g, b)
        quickCastTable["innerColor"][1] = r
        quickCastTable["innerColor"][2] = g
        quickCastTable["innerColor"][3] = b
        UpdatePreview()
        Cell.Fire("UpdateQuickCast")
    end)
    qcInnerCP:SetPoint("TOPLEFT", 5, -27)

    -- spell ------------------------------------------------------------------------
    -- 内圈法术选择按钮
    qcInnerBtn = CreateSpellButton(qcInnerPane, function(spellId)
        quickCastTable["innerBuff"] = spellId
    end)
    qcInnerBtn:SetPoint("TOPLEFT", qcInnerCP, "BOTTOMLEFT", 0, -10)
end

-- ----------------------------------------------------------------------- --
--                             glow list shared                            --
-- ----------------------------------------------------------------------- --
-- 光效列表布局常量
-- BUTTONS_PER_ROW: 每行最多显示的按钮数
-- BUTTONS_SPACING: 按钮之间的间距（像素）
-- BUTTONS_MAX: 最多允许添加的法术条目数
local BUTTONS_PER_ROW = 9
local BUTTONS_SPACING = 2
local BUTTONS_MAX = 27

-- 加载光效列表的通用函数（Buff 光效和施法光效共用）
-- parent: 父面板
-- buttons: 按钮缓存表（复用已创建的按钮）
-- addBtn: 添加按钮
-- anchorTo: 锚点控件（按钮列表定位在其下方）
-- t: 法术 ID 列表（施法光效时格式为 "id:duration"）
-- separator: 分隔符（nil 用于 Buff 光效，":" 用于施法光效）
local function LoadGlowList(parent, buttons, addBtn, anchorTo, t, separator)
    for i, id in pairs(t) do
        -- 如果按钮不存在则创建新的法术条目按钮
        if not buttons[i] then
            buttons[i] = Cell.CreateButton(parent, nil, "accent-hover", {20, 20})
            buttons[i]:RegisterForClicks("RightButtonUp")

            -- 默认图标（问号）
            buttons[i]:SetTexture(134400, {16, 16}, {"CENTER", 0, 0})
            buttons[i].tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- 施法光效需要显示持续时间标签
            if separator then
                buttons[i].duration = buttons[i]:CreateFontString(nil, "OVERLAY")
                buttons[i].duration:SetFont(GameFontNormal:GetFont(), 12, "OUTLINE")
                buttons[i].duration:SetTextColor(1, 1, 1, 1)
                buttons[i].duration:SetShadowColor(0, 0, 0, 0)
                buttons[i].duration:SetShadowOffset(0, 0)
                buttons[i].duration:SetJustifyH("CENTER")
                buttons[i].duration:SetPoint("BOTTOMRIGHT")
            end

            -- 鼠标悬停显示法术提示
            buttons[i]:HookScript("OnEnter", function(self)
                if self.id and self.icon then
                    CellSpellTooltip:SetOwner(self, "ANCHOR_NONE")
                    CellSpellTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
                    CellSpellTooltip:SetSpellByID(self.id, self.icon)
                    CellSpellTooltip:Show()
                end
            end)

            buttons[i]:HookScript("OnLeave", function(self)
                CellSpellTooltip:Hide()
            end)

            -- 右键点击从列表中移除该条目
            buttons[i]:SetScript("OnClick", function()
                tremove(t, i)
                LoadGlowList(parent, buttons, addBtn, anchorTo, t, separator)
                Cell.Fire("UpdateQuickCast")
            end)
        end

        -- 施法光效：解析 "id:duration" 格式并设置持续时间显示
        if separator then
            id, duration = strsplit(separator, id)
            buttons[i].duration:SetText(duration)
        end

        -- 获取法术名称和图标，找不到则使用默认问号图标
        local name, icon = F.GetSpellInfo(id)
        if not name then icon = 134400 end
        buttons[i].id = id
        buttons[i].icon = icon

        buttons[i].tex:SetTexture(icon)

        -- 按网格布局排列按钮
        buttons[i]:ClearAllPoints()
        if i == 1 then
            buttons[i]:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -10)
        elseif (i - 1) % BUTTONS_PER_ROW == 0 then
            buttons[i]:SetPoint("TOPLEFT", buttons[i-BUTTONS_PER_ROW], "BOTTOMLEFT", 0, -BUTTONS_SPACING)
        else
            buttons[i]:SetPoint("TOPLEFT", buttons[i-1], "TOPRIGHT", BUTTONS_SPACING, 0)
        end

        buttons[i]:Show()
    end

    local n = #t

    -- 隐藏多余的按钮（超出列表长度）
    for i = n+1, #buttons do
        buttons[i]:Hide()
    end

    -- 更新添加按钮的位置：如果已达上限则隐藏，否则放在列表末尾
    if n == BUTTONS_MAX then --max
        addBtn:Hide()
    else
        addBtn:ClearAllPoints()
        if n == 0 then
            addBtn:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -10)
        elseif n % BUTTONS_PER_ROW == 0 then
            addBtn:SetPoint("TOPLEFT", buttons[n-BUTTONS_PER_ROW+1], "BOTTOMLEFT", 0, -BUTTONS_SPACING)
        else
            addBtn:SetPoint("TOPLEFT", buttons[n], "TOPRIGHT", BUTTONS_SPACING, 0)
        end
        addBtn:Show()
    end
end

-- ----------------------------------------------------------------------- --
--                                glow buffs                               --
-- ----------------------------------------------------------------------- --
-- 创建 Buff 光效设置面板：颜色选择器 + Buff 法术列表（按钮网格）+ 添加按钮
local function CreateGlowBuffsPane()
    qcGlowBuffsPane = Cell.CreateTitledPane(qcPane, L["Glow Buffs"], 205, 130)
    qcGlowBuffsPane:SetPoint("TOPLEFT", 0, -355)

    -- 提示按钮：说明此功能基于 UNIT_AURA 事件
    Cell.CreateTipsButton(qcGlowBuffsPane, 17, "BOTTOMRIGHT", "UNIT_AURA")

    -- color ------------------------------------------------------------------------
    -- Buff 光效颜色选择器
    qcGlowBuffsCP = Cell.CreateColorPicker(qcGlowBuffsPane, L["Color"], false, nil, function(r, g, b)
        quickCastTable["glowBuffsColor"][1] = r
        quickCastTable["glowBuffsColor"][2] = g
        quickCastTable["glowBuffsColor"][3] = b
        UpdatePreview()
        Cell.Fire("UpdateQuickCast")
    end)
    qcGlowBuffsCP:SetPoint("TOPLEFT", 5, -27)

    -- buffs ------------------------------------------------------------------------
    -- 添加 Buff 按钮：点击弹出法术 ID 输入框，确认后加入列表
    qcGlowBuffsAddBtn = Cell.CreateButton(qcGlowBuffsPane, nil, "accent-hover", {20, 20})
    qcGlowBuffsAddBtn:SetPoint("TOPLEFT", qcGlowBuffsCP, "BOTTOMLEFT", 0, -10)
    qcGlowBuffsAddBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create", {16, 16}, {"CENTER", 0, 0})
    qcGlowBuffsAddBtn:SetScript("OnClick", function()
        local popup = Cell.CreatePopupEditBox(qcPane, function(text)
            local spellId = tonumber(text)
            local spellName = F.GetSpellInfo(spellId)
            if spellId and spellName then
                tinsert(quickCastTable["glowBuffs"], spellId)
                LoadGlowList(qcGlowBuffsPane, qcGlowBuffsButtons, qcGlowBuffsAddBtn, qcGlowBuffsCP, quickCastTable["glowBuffs"])
                Cell.Fire("UpdateQuickCast")
            else
                F.Print(L["Invalid spell id."])
            end
        end)
        popup:ClearAllPoints()
        popup:SetPoint("LEFT", qcGlowBuffsPane, 5, 0)
        popup:SetPoint("RIGHT", qcGlowBuffsPane, -4, 0)
        popup:SetPoint("TOP", qcGlowBuffsAddBtn)
        popup:ShowEditBox("")
    end)
end

-- ----------------------------------------------------------------------- --
--                                glow casts                               --
-- ----------------------------------------------------------------------- --
-- 创建施法光效设置面板：颜色选择器 + 施法法术列表（带持续时间）+ 双输入框添加按钮
local function CreateGlowCastsPane()
    qcGlowCastsPane = Cell.CreateTitledPane(qcPane, L["Glow Casts"], 205, 130)
    qcGlowCastsPane:SetPoint("TOPLEFT", 217, -355)

    -- 提示按钮：说明此功能基于 UNIT_SPELLCAST_SUCCEEDED 事件
    Cell.CreateTipsButton(qcGlowCastsPane, 17, "BOTTOMRIGHT", "UNIT_SPELLCAST_SUCCEEDED")

    -- color ------------------------------------------------------------------------
    -- 施法光效颜色选择器
    qcGlowCastsCP = Cell.CreateColorPicker(qcGlowCastsPane, L["Color"], false, nil, function(r, g, b)
        quickCastTable["glowCastsColor"][1] = r
        quickCastTable["glowCastsColor"][2] = g
        quickCastTable["glowCastsColor"][3] = b
        UpdatePreview()
        Cell.Fire("UpdateQuickCast")
    end)
    qcGlowCastsCP:SetPoint("TOPLEFT", 5, -27)

    -- 双输入框弹窗：左框输入法术 ID，右框输入持续时间（秒）
    local popup = Cell.CreateDualPopupEditBox(qcGlowCastsPane, "ID", L["Duration"], true)
    -- 左框输入法术 ID 时实时显示法术提示
    popup.left:HookScript("OnTextChanged", function(self)
        local spellId = tonumber(self:GetText())
        if not spellId then
            CellSpellTooltip:Hide()
            return
        end

        local name, icon = F.GetSpellInfo(spellId)
        if not name then
            CellSpellTooltip:Hide()
            return
        end

        CellSpellTooltip:SetOwner(self, "ANCHOR_NONE")
        CellSpellTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -1)
        CellSpellTooltip:SetSpellByID(spellId, icon)
        CellSpellTooltip:Show()
    end)
    -- 弹窗隐藏时隐藏法术提示
    popup:HookScript("OnHide", function()
        CellSpellTooltip:Hide()
    end)

    -- casts ------------------------------------------------------------------------
    -- 添加施法光效按钮：弹出双输入框（法术 ID + 持续时间），确认后以 "id:duration" 格式存储
    qcGlowCastsAddBtn = Cell.CreateButton(qcGlowCastsPane, nil, "accent-hover", {20, 20})
    qcGlowCastsAddBtn:SetPoint("TOPLEFT", qcGlowCastsCP, "BOTTOMLEFT", 0, -10)
    qcGlowCastsAddBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create", {16, 16}, {"CENTER", 0, 0})
    qcGlowCastsAddBtn:SetScript("OnClick", function()
        local popup = Cell.CreateDualPopupEditBox(qcGlowCastsPane, "ID", L["Duration"], true, function(spellId, duration)
            local spellName = F.GetSpellInfo(spellId)
            if spellId and spellName and duration then
                tinsert(quickCastTable["glowCasts"], spellId..":"..duration)
                LoadGlowList(qcGlowCastsPane, qcGlowCastsButtons, qcGlowCastsAddBtn, qcGlowCastsCP, quickCastTable["glowCasts"], ":")
                Cell.Fire("UpdateQuickCast")
            else
                F.Print(L["Invalid"])
            end
        end)
        popup.left:SetWidth(P.Scale(90))
        popup:SetPoint("LEFT", qcGlowCastsPane, 5, 0)
        popup:SetPoint("RIGHT", qcGlowCastsPane, -4, 0)
        popup:SetPoint("TOP", qcGlowCastsAddBtn)
        popup:ShowEditBox()
    end)
end

-- ----------------------------------------------------------------------- --
--                                   load                                  --
-- ----------------------------------------------------------------------- --
-- 根据配置值加载法术按钮的外观（名称 + 图标）
-- value: 法术 ID，0 表示无法术（显示默认图标）
local function LoadSpellButton(b, value)
    b.id = nil
    b.icon = nil
    if value == 0 then
        -- 无法术：显示创建图标，文本为空
        b:SetText("")
        b.tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create")
        b.tex:SetTexCoord(0, 1, 0, 1)
    else
        -- 有法术：显示法术名称和图标，找不到则显示红色"无效"标记
        local name, icon = F.GetSpellInfo(value)
        if name and icon then
            b:SetText(name)
            b.tex:SetTexture(icon)
            b.id = value
            b.icon = icon
        else
            b:SetText("|cffff2222"..L["Invalid"])
            b.tex:SetTexture(134400)
        end
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- 从 quickCastTable 加载所有设置控件的值，并刷新预览和光效列表
local function LoadDB()
    -- 基础设置
    qcEnabledCB:SetChecked(quickCastTable["enabled"])
    qcNameDD:SetSelectedValue(quickCastTable["namePosition"])
    qcButtonsSlider:SetValue(quickCastTable["num"])
    qcOrientationDD:SetSelectedValue(quickCastTable["orientation"])
    if strfind(quickCastTable["orientation"], "top") then
        qcLinesSlider:SetLabel(L["Rows"])
    else
        qcLinesSlider:SetLabel(L["Columns"])
    end
    qcLinesSlider:SetValue(quickCastTable["lines"])
    qcSizeSlider:SetValue(quickCastTable["size"])
    qcSpacingXSlider:SetValue(quickCastTable["spacingX"])
    qcSpacingYSlider:SetValue(quickCastTable["spacingY"])

    -- 刷新预览
    UpdatePreview()

    -- 加载光效设置：颜色选择器 + 法术列表
    qcGlowBuffsCP:SetColor(unpack(quickCastTable["glowBuffsColor"]))
    LoadGlowList(qcGlowBuffsPane, qcGlowBuffsButtons, qcGlowBuffsAddBtn, qcGlowBuffsCP, quickCastTable["glowBuffs"])
    qcGlowCastsCP:SetColor(unpack(quickCastTable["glowCastsColor"]))
    LoadGlowList(qcGlowCastsPane, qcGlowCastsButtons, qcGlowCastsAddBtn, qcGlowCastsCP, quickCastTable["glowCasts"], ":")

    -- 加载外圈设置
    qcOuterCP:SetColor(unpack(quickCastTable["outerColor"]))
    LoadSpellButton(qcOuterBtn, quickCastTable["outerBuff"])

    -- 加载内圈设置
    qcInnerCP:SetColor(unpack(quickCastTable["innerColor"]))
    LoadSpellButton(qcInnerBtn, quickCastTable["innerBuff"])

    -- 更新控件启用状态
    UpdateWidgets()
end

-- ----------------------------------------------------------------------- --
--                                   show                                  --
-- ----------------------------------------------------------------------- --
-- 延迟初始化标志：第一次切换到 quickCast 标签页时才创建所有 UI
local init

-- Cell 设置面板的标签页切换回调
-- which: 当前激活的标签页名称（如 "quickCast"）
local function ShowUtilitySettings(which)
    if which == "quickCast" then
        -- 延迟初始化：仅在首次显示时创建所有设置面板
        if not init then
            init = true
            CreateQCPane()
            CreatePreviewFrame()
            CreateOuterPane()
            CreateInnerPane()
            CreateGlowBuffsPane()
            CreateGlowCastsPane()

            -- 为设置面板添加战斗保护（进出战斗时自动隐藏/显示以防止受保护操作）
            F.ApplyCombatProtectionToFrame(qcPane, -4, 4, 4, -4)

            -- 面板显示时：让预览覆盖层淡入（仅限已启用的按钮）
            qcPane:SetScript("OnShow", function()
                if quickCastTable["enabled"] then
                    for i, p in pairs(previewButtons) do
                        if quickCastTable and i <= quickCastTable["num"] then
                            p.fadeOut:Stop()
                            p:FadeIn()
                        end
                    end
                end
            end)

            -- 面板隐藏时：让预览覆盖层淡出
            qcPane:SetScript("OnHide", function()
                for i, p in pairs(previewButtons) do
                    if quickCastTable and i <= quickCastTable["num"] then
                        p.fadeIn:Stop()
                        p:FadeOut()
                    end
                end
            end)
        end

        -- 每次切换到该标签页都重新加载数据库（以反映可能的外部变更）
        LoadDB()
        qcPane:Show()

    elseif init then
        qcPane:Hide()
    end
end
-- 注册到 Cell 的标签页切换回调
Cell.RegisterCallback("ShowUtilitySettings", "QuickCast_ShowUtilitySettings", ShowUtilitySettings)












-- ----------------------------------------------------------------------- --
--                             quick cast frame                            --
-- ----------------------------------------------------------------------- --
-- 实际游戏中的快捷施法按钮列表（最多 6 个）
local quickCastButtons
-- Buff/施法光效查找表：key 为法术名称（字符串），用于快速 O(1) 匹配
-- outerBuff/innerBuff: 外圈/内圈法术名称（字符串，从法术 ID 转换而来）
-- borderSize: 按钮边框宽度（根据 size/8 计算）
-- glowBuffsColor/glowCastsColor: 光效颜色缓存
local glowBuffs, glowCasts = {}, {}
local outerBuff, innerBuff
local borderSize, glowBuffsColor, glowCastsColor

-- 快捷施法主框架：所有按钮的父框架，使用 SecureHandlerAttributeTemplate 实现安全施法
-- 通过 RegisterAttributeDriver 控制可见性（队伍存在时显示）
local quickCastFrame = CreateFrame("Frame", "CellQuickCastFrame", Cell.frames.mainFrame, "SecureHandlerAttributeTemplate")
PixelUtil.SetPoint(quickCastFrame, "TOPLEFT", CellParent, "CENTER", -1, -1)
quickCastFrame:SetSize(16, 16)
quickCastFrame:SetClampedToScreen(true)
quickCastFrame:SetMovable(true)
quickCastFrame:Hide()

-- quickCastFrame:SetScript("OnEvent", function(self, event, ...)
--     self[event](self, ...)
-- end)

-- function quickCastFrame:PLAYER_ENTERING_WORLD()
--     quickCastFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
--     quickCastFrame:GROUP_ROSTER_UPDATE()
-- end

-- function quickCastFrame:GROUP_ROSTER_UPDATE()
--     if IsInGroup() then
--         quickCastFrame:Show()
--     else
--         quickCastFrame:Hide()
--     end
-- end

-- ----------------------------------------------------------------------- --
--                        target frame: drag and set                       --
-- ----------------------------------------------------------------------- --
-- 拖拽目标指示框架：Shift+左键拖拽快捷施法按钮时显示，用于将按钮绑定到目标单位
-- 跟随鼠标移动并显示"Unit"标签，松开时检测鼠标下方是否为有效的团队/小队单位框架
local targetFrame = Cell.CreateFrame(nil, quickCastFrame, 50, 20)
targetFrame.label = targetFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
targetFrame.label:SetPoint("CENTER")
targetFrame:EnableMouse(false)
targetFrame:SetFrameStrata("TOOLTIP")

-- 开始拖拽定位：显示目标框架并跟随鼠标移动
function targetFrame:StartMoving()
    targetFrame:Show()
    local scale = targetFrame:GetEffectiveScale()
    targetFrame:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        targetFrame:SetPoint("BOTTOMLEFT", CellParent, x/scale, y/scale)
        targetFrame:SetWidth(targetFrame.label:GetWidth() + 10)
    end)
end

-- 停止拖拽定位：隐藏目标框架并清除锚点
function targetFrame:StopMoving()
    targetFrame:Hide()
    targetFrame:ClearAllPoints()
end

-- 为快捷施法按钮注册拖拽行为
-- Shift+左键拖拽：设置按钮绑定的单位（将按钮拖到目标单位框架上）
-- Alt+左键拖拽：移动整个 quickCastFrame 的位置
local function RegisterDrag(frame)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function()
        if IsShiftKeyDown() then --! set unit
            -- Shift+拖拽：进入单位设置模式，显示目标指示框架并添加光效
            targetFrame.isMoving = true
            targetFrame:StartMoving()
            LCG.PixelGlow_Start(b, Cell.GetAccentColorTable(), 9, 0.25, 8, 2) -- color, N, frequency, length, thickness

            targetFrame.label:SetText(L["Unit"])

        elseif IsAltKeyDown() then --! move
            -- Alt+拖拽：移动整个快捷施法框架
            quickCastFrame:StartMoving()
            quickCastFrame:SetUserPlaced(false)
        end
    end)

    frame:SetScript("OnDragStop", function()
        quickCastFrame:StopMovingOrSizing()
        if not InCombatLockdown() then P.PixelPerfectPoint(quickCastFrame) end
        P.SavePosition(quickCastFrame, quickCastTable["position"])

        -- 处理单位设置拖拽结果
        if targetFrame.isMoving then
            targetFrame.isMoving = false
            targetFrame:StopMoving()

            if InCombatLockdown() then
                F.Print(L["You can't do that while in combat."])
                return
            end

            -- 获取鼠标下方的框架，检查是否为有效的 Cell 单位框架
            local f = F.GetMouseFocus()
            if f and f.states and f.states.displayedUnit and F.UnitInGroup(f.states.displayedUnit) then
                -- 绑定单位：存储到配置并设置按钮属性
                quickCastTable["units"][frame.index] = f.states.displayedUnit
                frame:SetUnit(f.states.displayedUnit, outerBuff, innerBuff)
            end
        end
    end)
end

-- ----------------------------------------------------------------------- --
--                            quick cast events                            --
-- ----------------------------------------------------------------------- --
-- 更新按钮的 Buff 光效和内外圈冷却状态
-- 遍历目标单位的所有有益光环，匹配 Buff 光效列表和外圈/内圈法术
local function QuickCast_UpdateAuras(self)
    if not self.unit then return end

    local glowBuffFound, outerBuffFound, innerBuffFound

    AuraUtil.ForEachAura(self.unit, "HELPFUL", nil, function(name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
        -- Midnight 12.0.0+: skip auras whose fields are secret; non-secret auras (e.g. raid buffs) are safe to read
        if Cell.isMidnight and issecretvalue and issecretvalue(spellId) then return end

        -- 检查是否匹配 Buff 光效列表（按法术名称匹配）
        if glowBuffs[name] then
            glowBuffFound = true
            self:SetGlowBuffCooldown(expirationTime - duration, duration)
        end

        -- 检查是否为自己施放的外圈/内圈 Buff（需要 source == "player"）
        if source == "player" then
            if name == outerBuff then
                outerBuffFound = true
                self:SetOuterCooldown(expirationTime - duration, duration)
            end

            if name == innerBuff then
                innerBuffFound = true
                self:SetInnerCooldown(expirationTime - duration, duration)
            end
        end
    end)

    -- 未找到对应 Buff 时清除冷却显示
    if not glowBuffFound then self:SetGlowBuffCooldown() end
    if not outerBuffFound then self:SetOuterCooldown() end
    if not innerBuffFound then self:SetInnerCooldown() end
end

-- 更新施法光效：单位成功施放指定法术后触发光效
-- spellId: UNIT_SPELLCAST_SUCCEEDED 事件传来的法术 ID
local function QuickCast_UpdateCasts(self, spellId)
    -- Midnight 12.0.0+: spellId from UNIT_SPELLCAST_SUCCEEDED is secret during restricted contexts
    if Cell.isMidnight and issecretvalue and issecretvalue(spellId) then return end
    if glowCasts[spellId] then
        self:SetGlowCastCooldown(GetTime(), glowCasts[spellId])
    end
end

-- 更新距离透明度：单位在范围内时按钮完全不透明，超出范围时半透明
local function QuickCast_UpdateInRange(self, ir)
    if not self.unit then return end

    if ir then
        A.FrameFadeIn(self, 0.25, self:GetAlpha(), 1)
    else
        A.FrameFadeOut(self, 0.25, self:GetAlpha(), 0.25)
    end
end

-- 更新单位状态：死亡或离线时显示红色叉号覆盖层
local function QuickCast_UpdateStatus(self)
    if UnitIsDeadOrGhost(self.unit) or not UnitIsConnected(self.unit) then
        self.invalidTex:Show()
    else
        self.invalidTex:Hide()
    end
end

-- 更新按钮上显示的单位名字文本
-- 英文名截取前 3 字符，中文名截取前 1 字符；支持音译和昵称
local function QuickCast_UpdateName(self)
    if not self.unit then return end

    local name = F.GetNickname(UnitName(self.unit), F.UnitFullName(self.unit))

    -- Midnight 12.0.0+: UnitName may return secret string
    if F.IsSecretValue and F.IsSecretValue(name) then
        self.nameText:SetText(name) -- FontString natively accepts secrets
        return
    end

    -- 如果启用了音译，将名字转换为拉丁字母
    if CellDB["general"]["translit"] then
        name = LibTranslit:Transliterate(name)
    end

    -- 根据语言截取名字：纯 ASCII 英文取 3 字符，含多字节字符（中文等）取 1 字符
    if string.len(name) == string.utf8len(name) then -- en
        self.nameText:SetText(string.utf8sub(name, 1, 3))
    else
        self.nameText:SetText(string.utf8sub(name, 1, 1))
    end
end

-- 昵称更新回调：延迟 1 秒后刷新所有按钮的名字显示
-- FIXME: sync others name
Cell.RegisterCallback("UpdateNicknames", "QuickCast_UpdateNicknames", function()
    if quickCastButtons then
        C_Timer.After(1, function()
            for _, b in pairs(quickCastButtons) do
                QuickCast_UpdateName(b)
            end
        end)
    end
end)

-- 音译设置变更回调：立即刷新所有按钮的名字显示
Cell.RegisterCallback("TranslitNames", "QuickCast_TranslitNames", function()
    if quickCastButtons then
        for _, b in pairs(quickCastButtons) do
            QuickCast_UpdateName(b)
        end
    end
end)

-- 快捷施法按钮的统一事件处理器
-- 将单位事件派发到对应的更新函数；队伍变化时检查单位有效性
local function QuickCast_OnEvent(self, event, unit, arg1, arg2)
    -- 事件来自绑定的单位：按事件类型派发到对应的更新函数
    if unit and self.unit == unit then
        if event == "UNIT_AURA" then
            QuickCast_UpdateAuras(self)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            QuickCast_UpdateCasts(self, arg2)
        elseif event == "UNIT_IN_RANGE_UPDATE" then
            QuickCast_UpdateInRange(self, arg1)
        elseif event == "UNIT_FLAGS" then
            QuickCast_UpdateStatus(self)
        elseif event == "UNIT_NAME_UPDATE" then
            QuickCast_UpdateName(self)
        end
    else
        -- 全局事件：队伍变动或进入世界时重新检查单位有效性
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            self:CheckUnit()
        end
    end
end

-- 按钮显示时注册所需事件并立即检查单位状态
local function QuickCast_OnShow(self)
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    -- self:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- update all now
    self:CheckUnit()
end

-- 按钮隐藏时注销所有事件以节省资源
local function QuickCast_OnHide(self)
    self:UnregisterAllEvents()
end

-- ----------------------------------------------------------------------- --
--                            create quick cast                            --
-- ----------------------------------------------------------------------- --
-- 创建预览覆盖层：半透明灰色框架覆盖在实际按钮上，显示序号，仅用于设置面板中的位置预览
local function CreatePreviewButton(b)
    local p = CreateFrame("Frame", nil, CellMainFrame, "BackdropTemplate")
    p:SetBackdrop({bgFile = Cell.vars.whiteTexture})
    p:SetBackdropColor(0.5, 0.5, 0.5, 0.7)
    p:SetAllPoints(b)
    p:SetFrameStrata("LOW")
    p:Hide()
    tinsert(previewButtons, p)

    -- 覆盖层中央显示按钮序号
    p.s = p:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS_TITLE")
    p.s:SetPoint("CENTER")
    p.s:SetText(#previewButtons)

    -- 创建淡入淡出动画
    A.CreateFadeIn(p, 0, 1, 0.5)
    A.CreateFadeOut(p, 1, 0, 0.5)

    -- 预览覆盖层也支持拖拽以移动整体位置
    p:RegisterForDrag("LeftButton")
    p:EnableMouse(true)

    p:SetScript("OnDragStart", function()
        quickCastFrame:StartMoving()
        quickCastFrame:SetUserPlaced(false)
    end)

    p:SetScript("OnDragStop", function()
        quickCastFrame:StopMovingOrSizing()
        if not InCombatLockdown() then P.PixelPerfectPoint(quickCastFrame) end
        P.SavePosition(quickCastFrame, quickCastTable["position"])
    end)
end

-- 创建快捷施法按钮的核心工厂函数
-- parent: 父框架（实际使用时为 quickCastFrame，预览时为 previewPane）
-- name: 按钮全局名称
-- isPreview: true 表示创建预览按钮（无 SecureUnitButtonTemplate），false 表示创建实际按钮
-- 返回的按钮对象包含：光效冷却、外圈冷却、内圈冷却、名字显示、单位绑定等完整功能
CreateQuickCastButton = function(parent, name, isPreview)
    local b
    if isPreview then
        -- 预览按钮：无需安全模板
        b = CreateFrame("Button", name, parent, "BackdropTemplate")
    else
        -- 实际按钮：使用 SecureUnitButtonTemplate 实现安全施法
        b = CreateFrame("Button", name, parent, "BackdropTemplate,SecureUnitButtonTemplate")
        CreatePreviewButton(b)
    end
    b:RegisterForClicks("AnyDown")
    b:Hide()
    b._r, b._g, b._b = 0, 0, 0

    -- name -------------------------------------------------------------------------
    -- 单位名字文本：显示在按钮旁边（上/下/左/右，由 SetNamePosition 控制）
    local nameText = b:CreateFontString(nil, "OVERLAY")
    b.nameText = nameText
    nameText:Hide()
    nameText:SetFont(GameFontNormal:GetFont(), 13, "Outline")

    -- invalid ----------------------------------------------------------------------
    -- 无效状态纹理（红色叉号）：单位死亡或离线时显示
    local invalidTex = b:CreateTexture(nil, "ARTWORK")
    b.invalidTex = invalidTex
    invalidTex:Hide()
    invalidTex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\close")
    invalidTex:SetVertexColor(0.7, 0.7, 0.7, 1)

    -- glow buff --------------------------------------------------------------------
    -- Buff 光效冷却框架：使用 LibCustomGlow 库显示按钮周围的发光效果
    -- 显示/隐藏时自动启动/停止光效动画；OnUpdate 中根据剩余时间动态调整透明度
    local glowBuffCD = CreateFrame("Frame", name.."GlowBuffCD", b)
    b.glowBuffCD = glowBuffCD
    glowBuffCD:Hide()
    glowBuffCD:SetScript("OnShow", function()
        LCG.ButtonGlow_Start(glowBuffCD, glowBuffsColor)
    end)
    glowBuffCD:SetScript("OnHide", function()
        LCG.ButtonGlow_Stop(glowBuffCD)
    end)

    -- glow cast --------------------------------------------------------------------
    -- 施法光效冷却框架：与 Buff 光效类似，但由施法成功事件触发
    local glowCastCD = CreateFrame("Frame", name.."GlowCastCD", b)
    b.glowCastCD = glowCastCD
    glowCastCD:Hide()
    glowCastCD:SetScript("OnShow", function()
        LCG.ButtonGlow_Start(glowCastCD, glowCastsColor)
    end)
    glowCastCD:SetScript("OnHide", function()
        LCG.ButtonGlow_Stop(glowCastCD)
    end)

    -- outer ------------------------------------------------------------------------
    -- 外圈冷却框架（Cooldown 类型）：显示在按钮边缘，表示左键法术的 Buff 剩余时间
    -- 使用标准的 CooldownFrameTemplate 实现扇形扫描冷却动画
    local outerCD = CreateFrame("Cooldown", name.."OuterCD", b, "BackdropTemplate,CooldownFrameTemplate")
    b.outerCD = outerCD
    outerCD:SetFrameLevel(b:GetFrameLevel() + 1)
    outerCD:SetSwipeTexture(Cell.vars.whiteTexture)
    outerCD:SetDrawEdge(true)
    -- outerCD:SetBackdrop({bgFile = Cell.vars.whiteTexture})
    -- outerCD:SetBackdropColor(0, 0, 0, 0.5)
    outerCD.noCooldownCount = true -- disable omnicc
    outerCD:SetHideCountdownNumbers(true)
    outerCD:Hide()
    -- 冷却结束时自动隐藏外圈
    outerCD:SetScript("OnCooldownDone", function()
        outerCD:Hide()
    end)
    -- 外圈显示/隐藏时更新内圈布局（内圈需要根据外圈是否可见调整大小和位置）
    outerCD:SetScript("OnShow", function()
        b:Update()
    end)
    outerCD:SetScript("OnHide", function()
        b:Update()
    end)

    -- inner ------------------------------------------------------------------------
    -- 内圈冷却框架（Cooldown 类型）：显示在按钮内部，表示右键法术的 Buff 剩余时间
    -- 半透明黑色背景 + 扇形扫描冷却动画
    local innerCD = CreateFrame("Cooldown", name.."InnerCD", b, "BackdropTemplate,CooldownFrameTemplate")
    b.innerCD = innerCD
    innerCD:SetFrameLevel(b:GetFrameLevel() + 2)
    innerCD:SetSwipeTexture(Cell.vars.whiteTexture)
    innerCD:SetDrawEdge(true)
    innerCD:SetBackdrop({bgFile = Cell.vars.whiteTexture})
    innerCD:SetBackdropColor(0, 0, 0, 0.4)
    innerCD.noCooldownCount = true -- disable omnicc
    innerCD:SetHideCountdownNumbers(true)
    innerCD:Hide()
    -- 冷却结束时自动隐藏内圈
    innerCD:SetScript("OnCooldownDone", function()
        innerCD:Hide()
    end)

    -- cooldowns --------------------------------------------------------------------
    -- 设置 Buff 光效冷却状态
    -- start: 冷却开始时间（GetTime() 返回值）
    -- duration: 冷却持续时长（秒）
    -- 无参数调用时清除光效
    function b:SetGlowBuffCooldown(start, duration)
        if start and duration then
            -- 通过 OnUpdate 每 0.1 秒更新光效透明度，实现渐变效果
            glowBuffCD:SetScript("OnUpdate", function(self, elapsed)
                self.elapsed = (self.elapsed or 0) + elapsed
                if self.elapsed >= 0.1 then
                    local remain = duration - (GetTime() - start)
                    if remain <= 0 then
                        -- 冷却结束：设置为最低透明度并隐藏
                        glowBuffCD:SetAlpha(0.1)
                        glowBuffCD:Hide()
                    elseif remain >= duration then
                        -- 冷却刚开始：完全不透明
                        glowBuffCD:SetAlpha(1)
                    else
                        -- 冷却中：透明度按剩余比例计算（0.1 ~ 1.0）
                        glowBuffCD:SetAlpha(remain / duration * 0.9 + 0.1)
                    end
                    self.elapsed = 0
                end
            end)
            glowBuffCD:Show()
        else
            -- 无参数：停止 OnUpdate 并隐藏光效
            glowBuffCD:SetScript("OnUpdate", nil)
            glowBuffCD:Hide()
        end
    end

    -- 设置施法光效冷却状态（逻辑与 Buff 光效相同）
    function b:SetGlowCastCooldown(start, duration)
        if start and duration then
            glowCastCD:SetScript("OnUpdate", function(self, elapsed)
                self.elapsed = (self.elapsed or 0) + elapsed
                if self.elapsed >= 0.1 then
                    local remain = duration - (GetTime() - start)
                    if remain <= 0 then
                        glowCastCD:SetAlpha(0.1)
                        glowCastCD:Hide()
                    elseif remain >= duration then
                        glowCastCD:SetAlpha(1)
                    else
                        glowCastCD:SetAlpha(remain / duration * 0.9 + 0.1)
                    end
                    self.elapsed = 0
                end
            end)
            glowCastCD:Show()
        else
            glowCastCD:SetScript("OnUpdate", nil)
            glowCastCD:Hide()
        end
    end

    -- 更新内圈冷却框架的位置和大小
    -- 如果外圈正在显示，内圈居中显示（较小）；如果外圈未显示，内圈撑满整个按钮
    function b:Update()
        P.ClearPoints(innerCD)
        if outerCD:IsShown() then
            P.Point(innerCD, "CENTER")
        else
            P.Point(innerCD, "TOPLEFT", borderSize+1, -borderSize-1)
            P.Point(innerCD, "BOTTOMRIGHT", -borderSize-1, borderSize+1)
        end
    end

    -- 设置外圈冷却（对应左键施法 Buff）
    function b:SetOuterCooldown(start, duration)
        if start and duration then
            outerCD:Show()
            outerCD:SetCooldown(start, duration)
        else
            outerCD:Hide()
        end
    end

    -- 设置内圈冷却（对应右键施法 Buff）
    function b:SetInnerCooldown(start, duration)
        if start and duration then
            b:Update()
            innerCD:Show()
            innerCD:SetCooldown(start, duration)
        else
            innerCD:Hide()
        end
    end

    -- setup ------------------------------------------------------------------------
    -- 设置按钮尺寸：同时更新边框、冷却框架、光效框架、名字字体的大小和位置
    b._SetSize = b.SetSize
    function b:SetSize(size)
        b:_SetSize(P.Scale(size), P.Scale(size))

        -- 边框宽度 = size/8（向下取整）
        borderSize = floor(size/8)
        b:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(borderSize)})
        b:SetBackdropColor(b._r*0.2, b._g*0.2, b._b*0.2, 0.7)
        b:SetBackdropBorderColor(b._r, b._g, b._b, 0.9)

        -- 无效状态图标撑满按钮内部
        P.ClearPoints(invalidTex)
        P.Point(invalidTex, "TOPLEFT", borderSize, -borderSize)
        P.Point(invalidTex, "BOTTOMRIGHT", -borderSize, borderSize)

        -- 外圈冷却框架位置：距离边框 1 像素
        P.ClearPoints(outerCD)
        outerCD:SetPoint("TOPLEFT", P.Scale(borderSize)+P.Scale(1), -P.Scale(borderSize)-P.Scale(1))
        outerCD:SetPoint("BOTTOMRIGHT", -P.Scale(borderSize)-P.Scale(1), P.Scale(borderSize)+P.Scale(1))
        -- 内圈冷却框架尺寸：比外圈小一圈
        P.Size(innerCD, floor(size-borderSize*4-2), floor(size-borderSize*4-2))

        -- 光效框架位置：略大于按钮
        P.ClearPoints(glowBuffCD)
        P.Point(glowBuffCD, "TOPLEFT", -borderSize, borderSize)
        P.Point(glowBuffCD, "BOTTOMRIGHT", borderSize, -borderSize)

        P.ClearPoints(glowCastCD)
        P.Point(glowCastCD, "TOPLEFT", -borderSize, borderSize)
        P.Point(glowCastCD, "BOTTOMRIGHT", borderSize, -borderSize)

        -- 名字字体大小随按钮尺寸缩放（最小 13，最大为 size/2）
        nameText:SetFont(GameFontNormal:GetFont(), max(13, floor(size/2)), "Outline")
        nameText:SetShadowColor(0, 0, 0)
        nameText:SetShadowOffset(0, 0)

        b:Update()
    end

    -- 设置名字文本相对于按钮的显示位置
    -- position: "LEFT"/"RIGHT"/"TOP"/"BOTTOM" 或 "none"（隐藏名字）
    function b:SetNamePosition(position)
        nameText:Show()
        nameText:ClearAllPoints()

        if position == "LEFT" then
            nameText:SetPoint("RIGHT", b, "LEFT", -3, 0)
        elseif position == "RIGHT" then
            nameText:SetPoint("LEFT", b, "RIGHT", 3, 0)
        elseif position == "TOP" then
            nameText:SetPoint("BOTTOM", b, "TOP", 0, 3)
        elseif position == "BOTTOM" then
            nameText:SetPoint("TOP", b, "BOTTOM", 0, -3)
        else
            nameText:Hide()
        end
    end

    -- 设置按钮各元素的颜色：光效颜色和冷却扫描颜色
    function b:SetColor(_glowBuffsColor, _glowCastsColor, _outerColor, _innerColor)
        -- 如果光效当前正在显示，需要重启以应用新颜色
        if glowBuffCD:IsShown() then
            LCG.ButtonGlow_Start(glowBuffCD, _glowBuffsColor)
        end
        if glowCastCD:IsShown() then
            LCG.ButtonGlow_Start(glowCastCD, _glowCastsColor)
        end
        outerCD:SetSwipeColor(unpack(_outerColor))
        innerCD:SetSwipeColor(unpack(_innerColor))
    end

    -- 检查并更新按钮绑定的单位状态
    -- 调用时机：GROUP_ROSTER_UPDATE / PLAYER_LOGIN / 手动调用
    -- 如果单位存在：更新职业颜色、注册事件、立即检查 Buff/距离/状态/名字
    -- 如果单位不存在：显示灰色占位状态（显示 unit 字符串作为名字）
    --! NOTE: GROUP_ROSTER_UPDATE or PLAYER_LOGIN or MANUALLY CALLED
    function b:CheckUnit()
        local unit = b.unit

        if unit and UnitExists(unit) then
            b:SetAlpha(1)

            -- local _r, _g, _b
            -- if UnitIsConnected(unit) then
            --     local class = UnitClassBase(unit)
            --     _r, _g, _b = F.GetClassColor(class)
            -- else
            --     _r, _g, _b = 0.4, 0.4, 0.4
            -- end

            -- 根据单位职业设置按钮颜色
            local class = UnitClassBase(unit)
            local _r, _g, _b = F.GetClassColor(class)
            b._r, b._g, b._b = _r, _g, _b
            b:SetBackdropColor(_r*0.2, _g*0.2, _b*0.2, 0.7)
            b:SetBackdropBorderColor(_r, _g, _b, 0.9)
            nameText:SetTextColor(_r, _g, _b)

            --! update name
            b:RegisterEvent("UNIT_NAME_UPDATE")
            QuickCast_UpdateName(b)

            --! check range now
            b:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit)
            QuickCast_UpdateInRange(b, UnitInRange(unit))

            --! check buffs now
            b:RegisterEvent("UNIT_AURA")
            QuickCast_UpdateAuras(b)

            --! casts glow
            b:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            b:SetGlowCastCooldown()

            --! check dead / offline
            b:RegisterEvent("UNIT_FLAGS")
            QuickCast_UpdateStatus(b)
        else
            -- 单位不存在：显示灰色未绑定状态
            b:SetAlpha(0.4)
            b:SetBackdropColor(0, 0, 0, 0.7)
            b:SetBackdropBorderColor(0, 0, 0, 0.9)
            nameText:SetTextColor(0.7, 0.7, 0.7)
            nameText:SetText(unit)

            invalidTex:Hide()
            glowBuffCD:Hide()
            glowCastCD:Hide()
            outerCD:Hide()
            innerCD:Hide()
        end

        F.UpdateOmniCDPosition("Cell-QuickCast")
    end

    -- 设置按钮绑定的单位和施法宏
    -- unit: 单位 token（如 "raid1"、"party2"）
    -- leftCast: 左键施放的法术名称（外圈 Buff 对应的法术）
    -- rightCast: 右键施放的法术名称（内圈 Buff 对应的法术）
    --! NOTE: PLAYER_LOGIN or MANUALLY CALLED
    function b:SetUnit(unit, leftCast, rightCast)
        F.Debug("[QuickCast] SetUnit:", unit, leftCast, rightCast)

        b.unit = unit

        if unit then
            -- 设置安全按钮属性：通过宏实现 [@unit,nodead] 条件施法
            b:SetAttribute("unit", unit)
            if leftCast then
                b:SetAttribute("type1", "macro")
                b:SetAttribute("macrotext1", "/cast [@"..unit..",nodead] "..leftCast)
            end
            if rightCast then
                b:SetAttribute("type2", "macro")
                b:SetAttribute("macrotext2", "/cast [@"..unit..",nodead] "..rightCast)
            end

            -- RegisterAttributeDriver(b, "state-visibility", "[@"..unit..",exists] show; hide")
        else
            -- 清除安全按钮属性
            b:SetAttribute("unit", nil)
            b:SetAttribute("type1", nil)
            b:SetAttribute("macrotext1", nil)
            b:SetAttribute("type2", nil)
            b:SetAttribute("macrotext2", nil)

            -- UnregisterAttributeDriver(b, "state-visibility")
            -- b:Hide()
        end

        b:CheckUnit()
    end

    -- Shift+右键点击清除按钮绑定的单位
    --! shift right-click to clear unit
    -- NOTE: if unit and unit ~= "none" and not UnitExists(unit) then THESE CODE WILL NOT RUN
    -- b:SetAttribute("shift-type2", "clearunit")
    -- b:SetAttribute("_clearunit", function()
    --     if InCombatLockdown() then
    --         F.Print(L["You can't do that while in combat."])
    --         return
    --     end

    --     b.unit = nil
    --     b:CheckUnit()

    --     b:SetAttribute("unit", nil)
    --     b:SetAttribute("type1", nil)
    --     b:SetAttribute("spell1", nil)
    --     b:SetAttribute("type2", nil)
    --     b:SetAttribute("spell2", nil)

    --     quickCastTable["units"][b.index] = nil
    -- end)

    b:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and IsShiftKeyDown() then
            if InCombatLockdown() then
                F.Print(L["You can't do that while in combat."])
                return
            end

            -- 清除单位绑定：重置所有属性和状态
            b.unit = nil
            b:CheckUnit()

            b:SetAttribute("unit", nil)
            b:SetAttribute("type1", nil)
            b:SetAttribute("spell1", nil)
            b:SetAttribute("type2", nil)
            b:SetAttribute("spell2", nil)

            quickCastTable["units"][b.index] = nil
        end
    end)

    -- 绑定按钮的生命周期事件
    b:SetScript("OnShow", QuickCast_OnShow)
    b:SetScript("OnHide", QuickCast_OnHide)
    b:SetScript("OnEvent", QuickCast_OnEvent)

    return b
end

-- ----------------------------------------------------------------------- --
--                                callbacks                                --
-- ----------------------------------------------------------------------- --
-- 全局更新快捷施法：读取当前专精的配置，创建/更新/隐藏按钮，设置布局和绑定
-- 触发时机：专精切换、设置变更、Cell.Fire("UpdateQuickCast")
local function UpdateQuickCast()
    -- 获取当前专精的配置表，不存在则使用默认配置
    if CellDB["quickCast"][Cell.vars.playerClass] and CellDB["quickCast"][Cell.vars.playerClass][Cell.vars.playerSpecID] then
        quickCastTable = CellDB["quickCast"][Cell.vars.playerClass][Cell.vars.playerSpecID]
    else
        quickCastTable = defaultQuickCastTable
    end

    -- 准备全局共享的配置缓存
    borderSize = floor(quickCastTable["size"]/8)
    glowBuffsColor = quickCastTable["glowBuffsColor"]
    glowCastsColor = quickCastTable["glowCastsColor"]

    if quickCastTable["enabled"] then
        -- 启用状态：注册属性驱动以在有队伍时自动显示 quickCastFrame
        RegisterAttributeDriver(quickCastFrame, "state-visibility", "[@raid1,exists] show;[@party1,exists] show;hide")
        targetFrame:UpdatePixelPerfect()
        -- quickCastFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- quickCastFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

        -- 更新父框架尺寸
        P.Size(quickCastFrame, quickCastTable["size"], quickCastTable["size"])
        -- if strfind(quickCastTable["orientation"], "top") then
        --     P.Size(quickCastFrame, quickCastTable["size"], quickCastTable["size"] * quickCastTable["num"] + quickCastTable["spacing"] * (quickCastTable["num"] - 1))
        -- else
        --     P.Size(quickCastFrame, quickCastTable["size"] * quickCastTable["num"] + quickCastTable["spacing"] * (quickCastTable["num"] - 1), quickCastTable["size"])
        -- end

        -- 恢复保存的位置
        P.LoadPosition(quickCastFrame, quickCastTable["position"])

        -- 将法术 ID 列表转换为法术名称查找表（用于光效和 Buff 匹配）
        glowBuffs = F.ConvertSpellTable(quickCastTable["glowBuffs"], true)
        glowCasts = F.ConvertSpellDurationTable(quickCastTable["glowCasts"])
        outerBuff = F.GetSpellInfo(quickCastTable["outerBuff"])
        innerBuff = F.GetSpellInfo(quickCastTable["innerBuff"])

        -- 首次创建 6 个按钮（最多 6 个），按需显示
        if not quickCastButtons then
            quickCastButtons = {}
            for i = 1, 6 do
                quickCastButtons[i] = CreateQuickCastButton(quickCastFrame, "CellQuickCastButton"..i)
                quickCastButtons[i].index = i -- for save
                RegisterDrag(quickCastButtons[i])
            end
        end

        -- 显示已配置数量的按钮并应用设置
        for i = 1, quickCastTable["num"] do
            quickCastButtons[i]:SetSize(quickCastTable["size"])
            quickCastButtons[i]:SetNamePosition(quickCastTable["namePosition"])
            quickCastButtons[i]:SetColor(quickCastTable["glowBuffsColor"], quickCastTable["glowCastsColor"], quickCastTable["outerColor"], quickCastTable["innerColor"])
            quickCastButtons[i]:SetUnit(quickCastTable["units"][i], outerBuff, innerBuff)
            quickCastButtons[i]:Show()

            -- 根据排列方向和行列数设置按钮位置
            P.ClearPoints(quickCastButtons[i])
            if quickCastTable["orientation"] == "left-to-right" then
                if i == 1 then
                    P.Point(quickCastButtons[i], "TOPLEFT")
                else
                    if quickCastTable["lines"] == 6 then
                        P.Point(quickCastButtons[i], "TOPLEFT", quickCastButtons[i-1], "TOPRIGHT", quickCastTable["spacingX"], 0)
                    else
                        if (i-1) % quickCastTable["lines"] == 0 then
                            P.Point(quickCastButtons[i], "TOPLEFT", quickCastButtons[i-quickCastTable["lines"]], "BOTTOMLEFT", 0, -quickCastTable["spacingY"])
                        else
                            P.Point(quickCastButtons[i], "TOPLEFT", quickCastButtons[i-1], "TOPRIGHT", quickCastTable["spacingX"], 0)
                        end
                    end
                end
            elseif quickCastTable["orientation"] == "right-to-left" then
                if i == 1 then
                    P.Point(quickCastButtons[i], "TOPRIGHT")
                else
                    if quickCastTable["lines"] == 6 then
                        P.Point(quickCastButtons[i], "TOPRIGHT", quickCastButtons[i-1], "TOPLEFT", -quickCastTable["spacingX"], 0)
                    else
                        if (i-1) % quickCastTable["lines"] == 0 then
                            P.Point(quickCastButtons[i], "TOPRIGHT", quickCastButtons[i-quickCastTable["lines"]], "BOTTOMRIGHT", 0, -quickCastTable["spacingY"])
                        else
                            P.Point(quickCastButtons[i], "TOPRIGHT", quickCastButtons[i-1], "TOPLEFT", -quickCastTable["spacingX"], 0)
                        end
                    end
                end
            elseif quickCastTable["orientation"] == "top-to-bottom" then
                if i == 1 then
                    P.Point(quickCastButtons[i], "TOPLEFT")
                else
                    if quickCastTable["lines"] == 6 then
                        P.Point(quickCastButtons[i], "TOPLEFT", quickCastButtons[i-1], "BOTTOMLEFT", 0, -quickCastTable["spacingY"])
                    else
                        if (i-1) % quickCastTable["lines"] == 0 then
                            P.Point(quickCastButtons[i], "TOPLEFT", quickCastButtons[i-quickCastTable["lines"]], "TOPRIGHT", quickCastTable["spacingX"], 0)
                        else
                            P.Point(quickCastButtons[i], "TOPLEFT", quickCastButtons[i-1], "BOTTOMLEFT", 0, -quickCastTable["spacingY"])
                        end
                    end
                end
            elseif quickCastTable["orientation"] == "bottom-to-top" then
                if i == 1 then
                    P.Point(quickCastButtons[i], "BOTTOMLEFT")
                else
                    if quickCastTable["lines"] == 6 then
                        P.Point(quickCastButtons[i], "BOTTOMLEFT", quickCastButtons[i-1], "TOPLEFT", 0, quickCastTable["spacingY"])
                    else
                        if (i-1) % quickCastTable["lines"] == 0 then
                            P.Point(quickCastButtons[i], "BOTTOMLEFT", quickCastButtons[i-quickCastTable["lines"]], "BOTTOMRIGHT", quickCastTable["spacingX"], 0)
                        else
                            P.Point(quickCastButtons[i], "BOTTOMLEFT", quickCastButtons[i-1], "TOPLEFT", 0, quickCastTable["spacingY"])
                        end
                    end
                end
            end
        end

        -- 隐藏超出配置数量的按钮
        for i = quickCastTable["num"] + 1, 6 do
            quickCastButtons[i]:Hide()
        end
    else
        -- 禁用状态：注销属性驱动、隐藏框架、清空查找表
        UnregisterAttributeDriver(quickCastFrame, "state-visibility")
        quickCastFrame:Hide()
        wipe(glowBuffs)
        wipe(glowCasts)
        outerBuff = nil
        innerBuff = nil
    end

    F.UpdateOmniCDPosition("Cell-QuickCast")
end
-- 注册 UpdateQuickCast 回调，供 Cell.Fire("UpdateQuickCast") 调用
Cell.RegisterCallback("UpdateQuickCast", "QuickCast_UpdateQuickCast", UpdateQuickCast)

-- 专精切换回调：重新加载配置，如果设置面板正在显示则刷新 UI
local function SpecChanged()
    UpdateQuickCast()
    if init and qcPane:IsShown() then
        LoadDB()
    end
end
Cell.RegisterCallback("SpecChanged", "QuickCast_SpecChanged", SpecChanged)
