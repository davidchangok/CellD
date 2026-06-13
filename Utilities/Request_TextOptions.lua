-- ============================================================================
-- Request_TextOptions.lua - 驱散请求文字选项面板
-- 提供驱散请求（Dispel Request）文字的样式、颜色、大小、锚点与偏移设置，
-- 并包含一个实时预览按钮，用于在布局中预览驱散请求文字的效果。
-- ============================================================================

local _, Cell = ...
local L = Cell.L               -- 本地化字符串表
local F = Cell.funcs           -- 通用函数表
local B = Cell.bFuncs          -- 单位按钮相关函数表
local U = Cell.uFuncs          -- UI/工具函数表
local P = Cell.pixelPerfectFuncs -- 像素完美/精确像素函数表

-- 模块级变量：文字选项面板框架 & 预览按钮
local textOptionsFrame, previewButton

--------------------------------------------------
-- icon preview
-- 图标预览区域：创建一个模拟的单位按钮，用于在设置面板中实时预览
-- 驱散请求文字在单位框体上的实际显示效果（包含血条、能量条、指示器等）
--------------------------------------------------

--- 创建预览按钮（仅首次调用时执行）
--- 基于 CellPreviewButtonTemplate 模板构建一个模拟单位按钮，置于文字选项面板上方，
--- 并为其添加半透明背景和"Preview"标题文字。创建完毕后触发 CreatePreview 事件，
--- 供其他模块在预览按钮上注册额外的预览元素（如驱散请求文字）。
local function CreatePreviewButton()
    -- 基于 CellPreviewButtonTemplate 模板创建模拟按钮
    previewButton = CreateFrame("Button", "CellTextPreviewButton", textOptionsFrame, "CellPreviewButtonTemplate")
    B.UpdateBackdrop(previewButton)
    -- previewButton.type = "main" -- 布局设置（注释掉的备用逻辑）
    -- 将预览按钮放置在文字选项面板的左下方外侧
    previewButton:SetPoint("BOTTOMLEFT", textOptionsFrame, "TOPLEFT", 0, 5)
    -- 移除模板自带的所有事件和脚本，预览按钮不需要交互
    previewButton:UnregisterAllEvents()
    previewButton:SetScript("OnEnter", nil)
    previewButton:SetScript("OnLeave", nil)
    previewButton:SetScript("OnShow", nil)
    previewButton:SetScript("OnHide", nil)
    previewButton:SetScript("OnUpdate", nil)

    -- 设置血条和能量条为满值（模拟满血满蓝状态）
    previewButton.widgets.healthBar:SetMinMaxValues(0, 1)
    previewButton.widgets.healthBar:SetValue(1)
    previewButton.widgets.powerBar:SetMinMaxValues(0, 1)
    previewButton.widgets.powerBar:SetValue(1)

    -- 为预览按钮添加半透明深色背景框
    local previewButtonBG = Cell.CreateFrame("CellTextPreviewButton", previewButton)
    previewButtonBG:SetPoint("TOPLEFT", previewButton, 0, 20)
    previewButtonBG:SetPoint("BOTTOMRIGHT", previewButton, "TOPRIGHT")
    Cell.StylizeFrame(previewButtonBG, {0.1, 0.1, 0.1, 0.77}, {0, 0, 0, 0})
    previewButtonBG:Show()

    -- 在背景框顶部显示"Preview"标题文字（带强调色）
    local previewText = previewButtonBG:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_TITLE")
    previewText:SetPoint("TOP", 0, -3)
    previewText:SetText(Cell.GetAccentColorString()..L["Preview"])

    -- 触发 CreatePreview 事件，让其他模块（如驱散请求文字模块）在此按钮上注册预览元素
    Cell.Fire("CreatePreview", previewButton)
end

--- 更新预览按钮的显示状态
--- 根据当前布局表（currentLayoutTable）中的设置，实时更新预览按钮的：
--- - 姓名指示器（名称文字）的启用/颜色/字体/宽度/位置
--- - 按钮尺寸、血条方向、能量条高度
--- - 血条和能量条的纹理、颜色、透明度
--- - 背景透明度
--- 如果预览按钮尚未创建，则先调用 CreatePreviewButton 创建。
local function UpdatePreviewButton()
    if not previewButton then
        CreatePreviewButton()
    end

    -- 获取当前布局表中第一个指示器（姓名指示器）的配置
    local iTable = Cell.vars.currentLayoutTable["indicators"][1]
    if iTable["enabled"] then
        -- 姓名指示器启用：根据布局配置更新预览按钮上的玩家姓名文字显示
        previewButton.indicators.nameText:Show()
        previewButton.states.name = UnitName("player")       -- 使用当前玩家姓名
        previewButton.indicators.nameText:UpdateName()
        previewButton.indicators.nameText:UpdatePreviewColor(iTable["color"])
        previewButton.indicators.nameText:UpdateTextWidth(iTable["textWidth"])
        previewButton.indicators.nameText:SetFont(unpack(iTable["font"]))
        previewButton.indicators.nameText:ClearAllPoints()
        -- 根据配置决定姓名文字相对于血条还是按钮本身定位
        local relativeTo = iTable["position"][2] == "healthBar" and previewButton.widgets.healthBar or previewButton
        previewButton.indicators.nameText:SetPoint(iTable["position"][1], relativeTo, iTable["position"][3], iTable["position"][4], iTable["position"][5])
    else
        -- 姓名指示器未启用：隐藏姓名文字
        previewButton.indicators.nameText:Hide()
    end

    -- 根据当前布局设置更新预览按钮的尺寸、血条方向和能量条高度
    P.Size(previewButton, Cell.vars.currentLayoutTable["main"]["size"][1], Cell.vars.currentLayoutTable["main"]["size"][2])
    B.SetOrientation(previewButton, Cell.vars.currentLayoutTable["barOrientation"][1], Cell.vars.currentLayoutTable["barOrientation"][2])
    B.SetPowerSize(previewButton, Cell.vars.currentLayoutTable["main"]["powerSize"])

    -- 更新血条和能量条的纹理
    previewButton.widgets.healthBar:SetStatusBarTexture(Cell.vars.texture)
    previewButton.widgets.powerBar:SetStatusBarTexture(Cell.vars.texture)

    -- 根据玩家职业和当前生命值比例计算血量颜色
    local r, g, b = F.GetHealthBarColor(1, false, F.GetClassColor(Cell.vars.playerClass))
    previewButton.widgets.healthBar:SetStatusBarColor(r, g, b, CellDB["appearance"]["barAlpha"])

    -- 根据玩家职业计算能量条颜色
    r, g, b = F.GetPowerBarColor("player", Cell.vars.playerClass)
    previewButton.widgets.powerBar:SetStatusBarColor(r, g, b)

    -- 更新预览按钮背景透明度
    previewButton:SetBackdropColor(0, 0, 0, CellDB["appearance"]["bgAlpha"])

    previewButton:Show()

    -- 触发 UpdatePreview 事件，通知其他模块（如驱散请求文字）更新其预览显示
    Cell.Fire("UpdatePreview", previewButton)
end

-- 注册布局更新回调：当布局（尺寸、方向、指示器位置等）发生变化时，
-- 自动刷新预览按钮的显示，使预览与当前布局保持一致。
Cell.RegisterCallback("UpdateLayout", "TextOptions_UpdateLayout", function()
    if previewButton then
        UpdatePreviewButton()
    end
end)

-- 注册外观更新回调：当外观设置（纹理、颜色、透明度等）发生变化时，
-- 自动刷新预览按钮的显示，使预览与当前外观设置保持一致。
Cell.RegisterCallback("UpdateAppearance", "TextOptions_UpdateAppearance", function()
    if previewButton then
        UpdatePreviewButton()
    end
end)

-------------------------------------------------
-- text options
-- 驱散请求文字设置区域：创建并管理文字类型、颜色、大小、锚点、
-- 锚点目标及XY偏移等UI控件，所有设置实时写入 CellDB 并刷新预览。
-------------------------------------------------

-- 文字选项面板上的各UI控件引用（模块级变量，在 CreateTextOptionsFrame 中初始化）
local textType, textAnchor, textAnchorTo, textColor, size, xOffset, yOffset

--- 根据当前 CellDB 中的文字选项设置，更新预览按钮上驱散请求文字（drText）的显示。
--- 调用 drText 控件的方法来设置文字类型、颜色、大小和锚点位置，并触发重绘。
local function UpdateTextPreview()
    -- setting 数组索引说明：
    -- [1] 文字类型（"A"/"B"/"C"），[2] 文字颜色 RGBA，
    -- [3] 文字大小，[4] 文字自身锚点，[5] 锚定目标点，
    -- [6] X偏移，[7] Y偏移
    local setting = CellDB["dispelRequest"]["textOptions"]
    previewButton.widgets.drText:SetType(setting[1])          -- 设置驱散请求文字的类型样式
    previewButton.widgets.drText:SetColor(setting[2])         -- 设置文字颜色
    P.Size(previewButton.widgets.drText, setting[3] * 2, setting[3]) -- 设置文字尺寸（宽度为高度的2倍）
    P.ClearPoints(previewButton.widgets.drText)               -- 清除旧锚点
    -- 将文字锚定到 drGlowFrame（发光框架），偏移量由 setting[6]/[7] 控制
    P.Point(previewButton.widgets.drText, setting[4], previewButton.widgets.drGlowFrame, setting[5], setting[6], setting[7])
    previewButton.widgets.drText:Display()                    -- 触发文字重绘
end

--- 从 CellDB 中加载已保存的文字选项设置，并同步到面板上的各个UI控件。
--- 在面板显示时调用，确保控件状态与数据库中的设置一致。
local function LoadTextOptions()
    UpdateTextPreview()

    textType:SetSelected(CellDB["dispelRequest"]["textOptions"][1])
    textColor:SetColor(unpack(CellDB["dispelRequest"]["textOptions"][2]))
    size:SetValue(CellDB["dispelRequest"]["textOptions"][3])
    textAnchor:SetSelectedValue(CellDB["dispelRequest"]["textOptions"][4])
    textAnchorTo:SetSelectedValue(CellDB["dispelRequest"]["textOptions"][5])
    xOffset:SetValue(CellDB["dispelRequest"]["textOptions"][6])
    yOffset:SetValue(CellDB["dispelRequest"]["textOptions"][7])
end

--- 创建文字选项设置面板（仅首次调用时执行）
--- 依次构建以下UI控件，从上到下排列在选项面板中：
--- 1. textType 下拉框 - 文字类型（A/B/C三种样式）
--- 2. textColor 颜色选择器 - 文字颜色
--- 3. size 滑块 - 文字大小（8-64）
--- 4. textAnchor 下拉框 - 文字自身锚点
--- 5. textAnchorTo 下拉框 - 锚定目标点（相对于单位按钮或发光框架）
--- 6. xOffset 滑块 - X轴偏移（-100 ~ 100）
--- 7. yOffset 滑块 - Y轴偏移（-100 ~ 100）
--- 每个控件的值变更都会实时写入 CellDB、刷新预览文字并触发 UpdateRequests 事件。
local function CreateTextOptionsFrame()
    -- 创建文字选项面板框架，置于主选项框右侧
    textOptionsFrame = Cell.CreateFrame("CellOptionsFrame_TextOptions", textOptionsFrame, 127, 325)
    textOptionsFrame:SetPoint("BOTTOMLEFT", Cell.frames.optionsFrame, "BOTTOMRIGHT", 5, 0)

    -- ===== textType：文字类型下拉框（A/B/C三种预设样式）=====
    textType = Cell.CreateDropdown(textOptionsFrame, 117)
    textType:SetPoint("TOPLEFT", 5, -20)
    -- A/B/C 三种文字类型选项，每种类型对应不同的文字渲染样式
    textType:SetItems({
        {
            ["text"] = "A",
            ["onClick"] = function()
                CellDB["dispelRequest"]["textOptions"][1] = "A"
                UpdateTextPreview()
                Cell.Fire("UpdateRequests", "dispelRequest_text") -- 通知所有单位按钮刷新驱散请求文字
            end
        },
        {
            ["text"] = "B",
            ["onClick"] = function()
                CellDB["dispelRequest"]["textOptions"][1] = "B"
                UpdateTextPreview()
                Cell.Fire("UpdateRequests", "dispelRequest_text")
            end
        },
        {
            ["text"] = "C",
            ["onClick"] = function()
                CellDB["dispelRequest"]["textOptions"][1] = "C"
                UpdateTextPreview()
                Cell.Fire("UpdateRequests", "dispelRequest_text")
            end
        },
    })

    -- 文字类型标签
    local textTypeText = textOptionsFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    textTypeText:SetText(L["Type"])
    textTypeText:SetPoint("BOTTOMLEFT", textType, "TOPLEFT", 0, 1)

    -- ===== textColor：文字颜色选择器 =====
    -- 第三个参数 false 表示不使用透明度通道（alpha 固定为 1）
    textColor = Cell.CreateColorPicker(textOptionsFrame, L["Color"], false, function(r, g, b)
        -- 将选中的 RGBA 颜色写入数据库（alpha 始终为 1）
        CellDB["dispelRequest"]["textOptions"][2][1] = r
        CellDB["dispelRequest"]["textOptions"][2][2] = g
        CellDB["dispelRequest"]["textOptions"][2][3] = b
        CellDB["dispelRequest"]["textOptions"][2][4] = 1
        UpdateTextPreview()
        Cell.Fire("UpdateRequests", "dispelRequest_text")
    end)
    -- 颜色选择器定位在文字类型下方
    textColor:SetPoint("TOPLEFT", textType, "BOTTOMLEFT", 0, -10)

    -- ===== size：文字大小滑块（范围 8~64，步长 1）=====
    size = Cell.CreateSlider(L["Size"], textOptionsFrame, 8, 64, 117, 1, function(value)
        CellDB["dispelRequest"]["textOptions"][3] = value
        UpdateTextPreview()
        Cell.Fire("UpdateRequests", "dispelRequest_text")
    end)
    size:SetPoint("TOPLEFT", textColor, "BOTTOMLEFT", 0, -30)

    -- ===== textAnchor：文字自身锚点下拉框 =====
    -- 决定驱散请求文字自身以哪个角/边作为定位基准
    local anchorPoints = {"BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "LEFT", "RIGHT", "TOP", "TOPLEFT", "TOPRIGHT"}
    textAnchor = Cell.CreateDropdown(textOptionsFrame, 117)
    textAnchor:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -40)
    local items = {}
    for _, point in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[point],       -- 本地化的锚点名称
            ["value"] = point,         -- 内部锚点标识
            ["onClick"] = function()
                CellDB["dispelRequest"]["textOptions"][4] = point
                UpdateTextPreview()
                Cell.Fire("UpdateRequests", "dispelRequest_text")
            end,
        })
    end
    textAnchor:SetItems(items)

    -- 锚点标签
    local textAnchorText = textOptionsFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    textAnchorText:SetText(L["Anchor Point"])
    textAnchorText:SetPoint("BOTTOMLEFT", textAnchor, "TOPLEFT", 0, 1)

    -- ===== textAnchorTo：锚定目标点下拉框 =====
    -- 决定驱散请求文字附着到发光框架（drGlowFrame）的哪个位置
    textAnchorTo = Cell.CreateDropdown(textOptionsFrame, 117)
    textAnchorTo:SetPoint("TOPLEFT", textAnchor, "BOTTOMLEFT", 0, -30)
    local items = {}
    for _, point in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[point],
            ["value"] = point,
            ["onClick"] = function()
                CellDB["dispelRequest"]["textOptions"][5] = point
                UpdateTextPreview()
                Cell.Fire("UpdateRequests", "dispelRequest_text")
            end,
        })
    end
    textAnchorTo:SetItems(items)

    -- 锚定目标标签（"To UnitButton's" 表示锚定到单位按钮相关的框架）
    local textAnchorToText = textOptionsFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    textAnchorToText:SetText(L["To UnitButton's"])
    textAnchorToText:SetPoint("BOTTOMLEFT", textAnchorTo, "TOPLEFT", 0, 1)

    -- ===== xOffset：X轴偏移滑块（范围 -100~100，步长 1）=====
    xOffset = Cell.CreateSlider(L["X Offset"], textOptionsFrame, -100, 100, 117, 1, function(value)
        CellDB["dispelRequest"]["textOptions"][6] = value
        UpdateTextPreview()
        Cell.Fire("UpdateRequests", "dispelRequest_text")
    end)
    xOffset:SetPoint("TOPLEFT", textAnchorTo, "BOTTOMLEFT", 0, -30)

    -- ===== yOffset：Y轴偏移滑块（范围 -100~100，步长 1）=====
    yOffset = Cell.CreateSlider(L["Y Offset"], textOptionsFrame, -100, 100, 117, 1, function(value)
        CellDB["dispelRequest"]["textOptions"][7] = value
        UpdateTextPreview()
        Cell.Fire("UpdateRequests", "dispelRequest_text")
    end)
    yOffset:SetPoint("TOPLEFT", xOffset, "BOTTOMLEFT", 0, -40)
end

-------------------------------------------------
-- functions
-- 公开API函数：通过 Cell.uFuncs 表暴露给其他模块调用
-------------------------------------------------

--- 显示或切换文字选项面板
--- 首次调用时创建面板和预览按钮；再次调用时在显示/隐藏之间切换。
--- @param parent Frame - 面板的父框架（通常是驱散请求设置的主面板）
function U.ShowTextOptions(parent)
    if not textOptionsFrame then
        CreateTextOptionsFrame()
    end

    if textOptionsFrame:IsShown() then
        -- 面板已显示：点击切换为隐藏（切换按钮行为）
        textOptionsFrame:Hide()
    else
        -- 面板未显示：设置父框架、刷新预览按钮、加载已保存设置后显示
        textOptionsFrame:SetParent(parent)
        UpdatePreviewButton()
        LoadTextOptions()
        textOptionsFrame:Show()
    end
end

--- 隐藏文字选项面板
--- 安全调用，如果面板尚未创建则不做任何操作。
function U.HideTextOptions()
    if textOptionsFrame then textOptionsFrame:Hide() end
end