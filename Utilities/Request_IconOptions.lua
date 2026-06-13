--------------------------------------------------
-- Request_IconOptions.lua
-- 请求图标的共享选项面板模块
-- 该模块负责创建和管理"法术请求"功能中图标的全局显示选项，
-- 包括预览按钮（展示当前指示器和布局效果）以及图标动画、尺寸、
-- 锚点、偏移和发光颜色等可配置项。
-- 当用户打开请求图标选项时，面板会叠加在选项主面板的右侧显示。
--------------------------------------------------

local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local B = Cell.bFuncs
local U = Cell.uFuncs
local P = Cell.pixelPerfectFuncs
local LCG = LibStub("LibCustomGlow-1.0")

-- 选项面板框架和预览按钮的引用（延迟创建，首次访问时初始化）
local iconOptionsFrame, previewButton
-- 当前正在编辑的图标纹理路径和颜色表（由外部调用 ShowIconOptions 传入）
local icon, iconColorTable

--------------------------------------------------
-- icon preview
-- 预览区域：在选项面板上方创建一个单元按钮预览，实时反映指示器、布局、
-- 生命条/能量条颜色等当前设置，方便用户调整图标选项时对照查看效果。
--------------------------------------------------

--------------------------------------------------
-- CreatePreviewButton()
-- 创建预览按钮，基于 CellPreviewButtonTemplate 模板。
-- 该按钮模拟一个完整的单元框，包含生命条、能量条和指示器，
-- 并清除所有交互事件脚本使其仅作为静态预览展示。
-- 按钮上方附有半透明背景和"预览"标题文字。
-- 触发 "CreatePreview" 事件，允许其他模块扩展预览内容。
--------------------------------------------------
local function CreatePreviewButton()
    previewButton = CreateFrame("Button", "CellIconPreviewButton", iconOptionsFrame, "CellPreviewButtonTemplate")
    B.UpdateBackdrop(previewButton)
    -- previewButton.type = "main" -- layout setup
    previewButton:SetPoint("BOTTOMLEFT", iconOptionsFrame, "TOPLEFT", 0, 5)
    -- 清除所有交互事件脚本，使预览按钮仅作为静态展示
    previewButton:UnregisterAllEvents()
    previewButton:SetScript("OnEnter", nil)
    previewButton:SetScript("OnLeave", nil)
    previewButton:SetScript("OnShow", nil)
    previewButton:SetScript("OnHide", nil)
    previewButton:SetScript("OnUpdate", nil)

    -- 初始化生命条和能量条为满值状态以便预览
    previewButton.widgets.healthBar:SetMinMaxValues(0, 1)
    previewButton.widgets.healthBar:SetValue(1)
    previewButton.widgets.powerBar:SetMinMaxValues(0, 1)
    previewButton.widgets.powerBar:SetValue(1)

    -- 创建预览按钮上方的标题背景框
    local previewButtonBG = Cell.CreateFrame("CellIconPreviewButtonBG", previewButton)
    previewButtonBG:SetPoint("TOPLEFT", previewButton, 0, 20)
    previewButtonBG:SetPoint("BOTTOMRIGHT", previewButton, "TOPRIGHT")
    Cell.StylizeFrame(previewButtonBG, {0.1, 0.1, 0.1, 0.77}, {0, 0, 0, 0})
    previewButtonBG:Show()

    -- 创建预览标题文字（使用强调色 + 本地化"预览"文本）
    local previewText = previewButtonBG:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_TITLE")
    previewText:SetPoint("TOP", 0, -3)
    previewText:SetText(Cell.GetAccentColorString()..L["Preview"])

    -- 触发创建预览事件，允许其他模块向 previewButton 添加自定义元素
    Cell.Fire("CreatePreview", previewButton)
end

--------------------------------------------------
-- UpdatePreviewButton()
-- 更新预览按钮的显示状态，使其反映当前布局表中的最新设置。
-- 如果预览按钮尚未创建则先创建。
-- 更新内容包括：指示器名称显示/隐藏、玩家名称、颜色、文字宽度、字体、
-- 位置锚点、单元框尺寸、条方向、能量条大小、纹理、生命条颜色（基于职业）、
-- 能量条颜色、背景透明度等。
-- 最后触发 "UpdatePreview" 事件供其他模块同步更新。
--------------------------------------------------
local function UpdatePreviewButton()
    if not previewButton then
        CreatePreviewButton()
    end

    -- 读取当前布局表的指示器设置
    local iTable = Cell.vars.currentLayoutTable["indicators"][1]
    if iTable["enabled"] then
        -- 指示器启用时：显示名称文字，应用各项配置
        previewButton.indicators.nameText:Show()
        previewButton.states.name = UnitName("player")
        previewButton.indicators.nameText:UpdateName()
        previewButton.indicators.nameText:UpdatePreviewColor(iTable["color"])
        previewButton.indicators.nameText:UpdateTextWidth(iTable["textWidth"])
        previewButton.indicators.nameText:SetFont(unpack(iTable["font"]))
        previewButton.indicators.nameText:ClearAllPoints()
        -- 根据配置决定锚点的相对对象（生命条或按钮自身）
        local relativeTo = iTable["position"][2] == "healthBar" and previewButton.widgets.healthBar or previewButton
        previewButton.indicators.nameText:SetPoint(iTable["position"][1], relativeTo, iTable["position"][3], iTable["position"][4], iTable["position"][5])
    else
        -- 指示器禁用时隐藏名称文字
        previewButton.indicators.nameText:Hide()
    end

    -- 应用布局尺寸、条方向和能量条大小
    P.Size(previewButton, Cell.vars.currentLayoutTable["main"]["size"][1], Cell.vars.currentLayoutTable["main"]["size"][2])
    B.SetOrientation(previewButton, Cell.vars.currentLayoutTable["barOrientation"][1], Cell.vars.currentLayoutTable["barOrientation"][2])
    B.SetPowerSize(previewButton, Cell.vars.currentLayoutTable["main"]["powerSize"])

    -- 应用当前选择的全局纹理
    previewButton.widgets.healthBar:SetStatusBarTexture(Cell.vars.texture)
    previewButton.widgets.powerBar:SetStatusBarTexture(Cell.vars.texture)

    -- health color：根据血量百分比和职业颜色计算生命条颜色
    local r, g, b = F.GetHealthBarColor(1, false, F.GetClassColor(Cell.vars.playerClass))
    previewButton.widgets.healthBar:SetStatusBarColor(r, g, b, CellDB["appearance"]["barAlpha"])

    -- power color：根据玩家职业获取能量条颜色
    r, g, b = F.GetPowerBarColor("player", Cell.vars.playerClass)
    previewButton.widgets.powerBar:SetStatusBarColor(r, g, b)

    -- alpha：设置预览按钮背景透明度
    previewButton:SetBackdropColor(0, 0, 0, CellDB["appearance"]["bgAlpha"])

    previewButton:Show()

    -- 触发更新预览事件，允许其他模块同步更新其添加到预览按钮上的元素
    Cell.Fire("UpdatePreview", previewButton)
end

--------------------------------------------------
-- 回调：当布局设置变化时，刷新预览按钮使之立即反映最新布局效果。
--------------------------------------------------
Cell.RegisterCallback("UpdateLayout", "IconOptions_UpdateLayout", function()
    if previewButton then
        UpdatePreviewButton()
    end
end)

--------------------------------------------------
-- 回调：当外观设置变化时（如纹理、颜色、透明度），刷新预览按钮。
--------------------------------------------------
Cell.RegisterCallback("UpdateAppearance", "IconOptions_UpdateAppearance", function()
    if previewButton then
        UpdatePreviewButton()
    end
end)

-------------------------------------------------
-- icon options
-- 图标选项面板区域：包含共享选项（动画、尺寸、锚点、偏移）和
-- 独立选项（发光颜色选择器）。用户在此面板中调整的设置将保存在
-- CellDB["spellRequest"]["sharedIconOptions"] 中，并实时反映到预览按钮上。
-------------------------------------------------

-- 图标选项控件引用
local iconAnimation, iconAnchor, iconAnchorTo, iconiconGlowColor, size, xOffset, yOffset

--------------------------------------------------
-- UpdateIconPreview()
-- 根据 CellDB 中的共享图标选项刷新预览按钮上的图标显示。
-- 设置动画类型、图标尺寸、锚点位置和偏移，然后调用图标的 Display 方法。
--------------------------------------------------
local function UpdateIconPreview()
    local setting = CellDB["spellRequest"]["sharedIconOptions"]
    previewButton.widgets.srIcon:SetAnimationType(setting[1])
    P.Size(previewButton.widgets.srIcon, setting[2], setting[2])
    P.ClearPoints(previewButton.widgets.srIcon)
    P.Point(previewButton.widgets.srIcon, setting[3], previewButton.widgets.srGlowFrame, setting[4], setting[5], setting[6])
    previewButton.widgets.srIcon:Display(icon, iconColorTable)
end

--------------------------------------------------
-- LoadIconOptions()
-- 将 CellDB 中保存的共享图标选项加载到各个 UI 控件中，
-- 使面板显示与已保存的设置保持同步。在面板每次显示时调用。
-- 包括：更新图标预览、设置发光颜色选择器、下拉菜单选中值和滑块数值。
--------------------------------------------------
local function LoadIconOptions()
    UpdateIconPreview()

    -- 设置发光颜色选择器为当前颜色表的值
    iconGlowColor:SetColor(unpack(iconColorTable))

    -- 将已保存的选项值同步到各 UI 控件
    iconAnimation:SetSelectedValue(CellDB["spellRequest"]["sharedIconOptions"][1])
    size:SetValue(CellDB["spellRequest"]["sharedIconOptions"][2])
    iconAnchor:SetSelectedValue(CellDB["spellRequest"]["sharedIconOptions"][3])
    iconAnchorTo:SetSelectedValue(CellDB["spellRequest"]["sharedIconOptions"][4])
    xOffset:SetValue(CellDB["spellRequest"]["sharedIconOptions"][5])
    yOffset:SetValue(CellDB["spellRequest"]["sharedIconOptions"][6])
end

--------------------------------------------------
-- CreateIconOptionsFrame()
-- 创建图标选项面板的主框架及其所有子控件。
-- 面板位于选项主框架右侧，包含两个区域：
--   1. 共享选项区（Shared）：动画类型下拉菜单、图标尺寸滑块、
--      锚点下拉菜单、锚点目标下拉菜单、X/Y 偏移滑块
--   2. 独立选项区（Individual）：发光颜色选择器
-- 每个控件在值改变时都会更新 CellDB、刷新预览并通过
-- "UpdateRequests" 事件通知请求模块更新。
--------------------------------------------------
local function CreateIconOptionsFrame()
    iconOptionsFrame = CreateFrame("Frame", "CellOptionsFrame_IconOptions", Cell.frames.optionsFrame)
    iconOptionsFrame:SetPoint("BOTTOMLEFT", Cell.frames.optionsFrame, "BOTTOMRIGHT", 5, 0)
    P.Size(iconOptionsFrame, 127, 335)
    iconOptionsFrame:Hide()

    -- ========== 共享选项区域 ==========
    local sharedOptionsFrame = Cell.CreateFrame("CellOptionsFrame_IconOptions_Shared", iconOptionsFrame, 127, 300)
    sharedOptionsFrame:SetPoint("BOTTOMLEFT")
    sharedOptionsFrame:Show()

    -- ---------- 动画类型下拉菜单 ----------
    -- 提供四种动画选项：无动画、跳动、弹跳、闪烁
    iconAnimation = Cell.CreateDropdown(sharedOptionsFrame, 117)
    iconAnimation:SetPoint("TOPLEFT", 5, -20)
    iconAnimation:SetItems({
        {
            ["text"] = L["None"],        -- 无动画
            ["value"] = "none",
            ["onClick"] = function()
                CellDB["spellRequest"]["sharedIconOptions"][1] = "none"
                UpdateIconPreview()
                Cell.Fire("UpdateRequests", "spellRequest_icon")
            end
        },
        {
            ["text"] = L["Beat"],        -- 跳动动画
            ["value"] = "beat",
            ["onClick"] = function()
                CellDB["spellRequest"]["sharedIconOptions"][1] = "beat"
                UpdateIconPreview()
                Cell.Fire("UpdateRequests", "spellRequest_icon")
            end
        },
        {
            ["text"] = L["Bounce"],      -- 弹跳动画
            ["value"] = "bounce",
            ["onClick"] = function()
                CellDB["spellRequest"]["sharedIconOptions"][1] = "bounce"
                UpdateIconPreview()
                Cell.Fire("UpdateRequests", "spellRequest_icon")
            end
        },
        {
            ["text"] = L["Blink"],       -- 闪烁动画
            ["value"] = "blink",
            ["onClick"] = function()
                CellDB["spellRequest"]["sharedIconOptions"][1] = "blink"
                UpdateIconPreview()
                Cell.Fire("UpdateRequests", "spellRequest_icon")
            end
        }
    })

    -- 动画下拉菜单的标签文字
    local iconAnimationText = sharedOptionsFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    iconAnimationText:SetText(L["Animation"])
    iconAnimationText:SetPoint("BOTTOMLEFT", iconAnimation, "TOPLEFT", 0, 1)

    -- ---------- 图标尺寸滑块 ----------
    -- 范围 8~64，步长 1
    size = Cell.CreateSlider(L["Size"], sharedOptionsFrame, 8, 64, 117, 1, function(value)
        CellDB["spellRequest"]["sharedIconOptions"][2] = value
        UpdateIconPreview()
        Cell.Fire("UpdateRequests", "spellRequest_icon")
    end)
    size:SetPoint("TOPLEFT", iconAnimation, "BOTTOMLEFT", 0, -30)

    -- ---------- 图标自身锚点下拉菜单 ----------
    -- 决定图标的哪个点作为锚点（如 BOTTOM、CENTER、TOPLEFT 等）
    local anchorPoints = {"BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "LEFT", "RIGHT", "TOP", "TOPLEFT", "TOPRIGHT"}
    iconAnchor = Cell.CreateDropdown(sharedOptionsFrame, 117)
    iconAnchor:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -40)
    local items = {}
    for _, point in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[point],
            ["value"] = point,
            ["onClick"] = function()
                CellDB["spellRequest"]["sharedIconOptions"][3] = point
                UpdateIconPreview()
                Cell.Fire("UpdateRequests", "spellRequest_icon")
            end,
        })
    end
    iconAnchor:SetItems(items)

    -- 锚点下拉菜单的标签文字
    local iconAnchorText = sharedOptionsFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    iconAnchorText:SetText(L["Anchor Point"])
    iconAnchorText:SetPoint("BOTTOMLEFT", iconAnchor, "TOPLEFT", 0, 1)

    -- ---------- 锚定目标点下拉菜单 ----------
    -- 决定图标锚定到目标框的哪个点（如 BOTTOM、CENTER、TOPLEFT 等）
    iconAnchorTo = Cell.CreateDropdown(sharedOptionsFrame, 117)
    iconAnchorTo:SetPoint("TOPLEFT", iconAnchor, "BOTTOMLEFT", 0, -30)
    local items = {}
    for _, point in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[point],
            ["value"] = point,
            ["onClick"] = function()
                CellDB["spellRequest"]["sharedIconOptions"][4] = point
                UpdateIconPreview()
                Cell.Fire("UpdateRequests", "spellRequest_icon")
            end,
        })
    end
    iconAnchorTo:SetItems(items)

    -- 锚定目标下拉菜单的标签文字
    local iconAnchorToText = sharedOptionsFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    iconAnchorToText:SetText(L["To UnitButton's"])
    iconAnchorToText:SetPoint("BOTTOMLEFT", iconAnchorTo, "TOPLEFT", 0, 1)

    -- ---------- X 轴偏移滑块 ----------
    -- 范围 -100~100，步长 1
    xOffset = Cell.CreateSlider(L["X Offset"], sharedOptionsFrame, -100, 100, 117, 1, function(value)
        CellDB["spellRequest"]["sharedIconOptions"][5] = value
        UpdateIconPreview()
        Cell.Fire("UpdateRequests", "spellRequest_icon")
    end)
    xOffset:SetPoint("TOPLEFT", iconAnchorTo, "BOTTOMLEFT", 0, -30)

    -- ---------- Y 轴偏移滑块 ----------
    -- 范围 -100~100，步长 1
    yOffset = Cell.CreateSlider(L["Y Offset"], sharedOptionsFrame, -100, 100, 117, 1, function(value)
        CellDB["spellRequest"]["sharedIconOptions"][6] = value
        UpdateIconPreview()
        Cell.Fire("UpdateRequests", "spellRequest_icon")
    end)
    yOffset:SetPoint("TOPLEFT", xOffset, "BOTTOMLEFT", 0, -40)

    -- ========== 独立选项区域 ==========
    local individualOptionsFrame = Cell.CreateFrame("CellOptionsFrame_IconOptions_Individual", iconOptionsFrame, 127, 30)
    individualOptionsFrame:SetPoint("BOTTOMLEFT", sharedOptionsFrame, "TOPLEFT", 0, 5)
    individualOptionsFrame:Show()

    -- ---------- 发光颜色选择器 ----------
    -- 点击后打开颜色拾取面板，选择图标发光/轮廓的颜色。
    -- 当选色变化时，直接更新 colorTable 并刷新预览。
    -- 注意：此控件不在点击时触发 UpdateRequests，因为颜色选择器自身管理确认逻辑。
    iconGlowColor = Cell.CreateColorPicker(individualOptionsFrame, L["Glow Color"], false, function(r, g, b)
        -- update db
        iconColorTable[1] = r
        iconColorTable[2] = g
        iconColorTable[3] = b
        iconColorTable[4] = 1
        -- update preview
        UpdateIconPreview()
    end)
    iconGlowColor:SetPoint("TOPLEFT", 5, -7)
end

-------------------------------------------------
-- functions
-- 对外公开的接口函数，供 Cell.uFuncs 命名空间下的其他模块调用。
-------------------------------------------------

--------------------------------------------------
-- U.ShowIconOptions(parent, tex, t)
-- 显示或切换图标选项面板。
-- 参数：
--   parent - 父框架，面板将以此框架作为定位参考
--   tex    - 当前编辑的图标纹理路径
--   t      - 当前图标的颜色表 {r, g, b, a}
-- 行为：如果面板尚未创建则先创建；如果面板已显示则隐藏（切换逻辑）；
--       否则设置父框架、图标数据，刷新预览和控件值，然后显示面板。
--------------------------------------------------
function U.ShowIconOptions(parent, tex, t)
    if not iconOptionsFrame then
        CreateIconOptionsFrame()
    end

    if iconOptionsFrame:IsShown() then
        -- 面板已显示时再次调用则隐藏（切换行为）
        iconOptionsFrame:Hide()
    else
        iconOptionsFrame:SetParent(parent)
        icon = tex
        iconColorTable = t
        UpdatePreviewButton()
        LoadIconOptions()
        iconOptionsFrame:Show()
    end
end

--------------------------------------------------
-- U.HideIconOptions()
-- 隐藏图标选项面板（如果已创建）。
-- 通常在关闭主选项窗口或切换到其他设置页面时调用。
--------------------------------------------------
function U.HideIconOptions()
    if iconOptionsFrame then iconOptionsFrame:Hide() end
end