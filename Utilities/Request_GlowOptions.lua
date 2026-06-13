-- 从 Cell 全局对象获取本地引用
local _, Cell = ...
local L = Cell.L          -- 本地化字符串表
local F = Cell.funcs       -- 通用函数库
local B = Cell.bFuncs      -- 按钮相关函数库
local U = Cell.uFuncs      -- UI 工具函数库
local P = Cell.pixelPerfectFuncs  -- 像素完美函数库

-- LibCustomGlow-1.0: 自定义发光效果库，提供 ButtonGlow / PixelGlow / AutoCastGlow / ProcGlow 四种发光类型
local LCG = LibStub("LibCustomGlow-1.0")

-- 当前正在编辑的发光选项表引用，格式: {glowType, {color, x, y, ...参数因类型而异}}
local glowOptionsTable
-- 发光选项面板及其预览按钮
local glowOptionsFrame, previewButton

--------------------------------------------------
-- glow preview
--------------------------------------------------

-- 创建用于预览发光效果的按钮控件
-- 该按钮复用 CellPreviewButtonTemplate 模板，模拟一个满血满能量的单位框体
-- 并在其上方添加半透明背景和"预览"文字标签
local function CreatePreviewButton()
    previewButton = CreateFrame("Button", "CellGlowsPreviewButton", glowOptionsFrame, "CellPreviewButtonTemplate")
    B.UpdateBackdrop(previewButton)
    -- previewButton.type = "main" -- layout setup
    previewButton:SetPoint("BOTTOMLEFT", glowOptionsFrame, "TOPLEFT", 0, 5)
    -- 清除模板自带的所有事件和脚本，因为预览按钮不需要交互行为
    previewButton:UnregisterAllEvents()
    previewButton:SetScript("OnEnter", nil)
    previewButton:SetScript("OnLeave", nil)
    previewButton:SetScript("OnShow", nil)
    previewButton:SetScript("OnHide", nil)
    previewButton:SetScript("OnUpdate", nil)

    -- 将血条和能量条设置为满值，用于预览外观
    previewButton.widgets.healthBar:SetMinMaxValues(0, 1)
    previewButton.widgets.healthBar:SetValue(1)
    previewButton.widgets.powerBar:SetMinMaxValues(0, 1)
    previewButton.widgets.powerBar:SetValue(1)

    -- 创建预览按钮下方的半透明深色背景，使预览按钮在亮色界面上也能看清
    local previewButtonBG = Cell.CreateFrame("CellGlowsPreviewButtonBG", previewButton)
    previewButtonBG:SetPoint("TOPLEFT", previewButton, 0, 20)
    previewButtonBG:SetPoint("BOTTOMRIGHT", previewButton, "TOPRIGHT")
    Cell.StylizeFrame(previewButtonBG, {0.1, 0.1, 0.1, 0.77}, {0, 0, 0, 0})
    previewButtonBG:Show()

    -- 背景上的"预览"文字标签，使用强调色
    local previewText = previewButtonBG:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_TITLE")
    previewText:SetPoint("TOP", 0, -3)
    previewText:SetText(Cell.GetAccentColorString()..L["Preview"])

    -- 触发 CreatePreview 事件，允许其他模块在预览按钮创建时进行扩展
    Cell.Fire("CreatePreview", previewButton)
end

-- 更新预览按钮的外观，使其反映当前布局和外观设置
-- 包括指示器（名称文字）、尺寸、血条/能量条方向、颜色、透明度等
-- 首次调用时若预览按钮不存在则自动创建
local function UpdatePreviewButton()
    if not previewButton then
        CreatePreviewButton()
    end

    -- 设置指示器（名称文字）的显示状态和外观
    local iTable = Cell.vars.currentLayoutTable["indicators"][1]
    if iTable["enabled"] then
        previewButton.indicators.nameText:Show()
        previewButton.states.name = UnitName("player")
        previewButton.indicators.nameText:UpdateName()
        previewButton.indicators.nameText:UpdatePreviewColor(iTable["color"])
        previewButton.indicators.nameText:UpdateTextWidth(iTable["textWidth"])
        previewButton.indicators.nameText:SetFont(unpack(iTable["font"]))
        previewButton.indicators.nameText:ClearAllPoints()
        local relativeTo = iTable["position"][2] == "healthBar" and previewButton.widgets.healthBar or previewButton
        previewButton.indicators.nameText:SetPoint(iTable["position"][1], relativeTo, iTable["position"][3], iTable["position"][4], iTable["position"][5])
    else
        previewButton.indicators.nameText:Hide()
    end

    -- 应用当前布局设置：尺寸、方向、能量条大小
    P.Size(previewButton, Cell.vars.currentLayoutTable["main"]["size"][1], Cell.vars.currentLayoutTable["main"]["size"][2])
    B.SetOrientation(previewButton, Cell.vars.currentLayoutTable["barOrientation"][1], Cell.vars.currentLayoutTable["barOrientation"][2])
    B.SetPowerSize(previewButton, Cell.vars.currentLayoutTable["main"]["powerSize"])

    -- 应用当前纹理
    previewButton.widgets.healthBar:SetStatusBarTexture(Cell.vars.texture)
    previewButton.widgets.powerBar:SetStatusBarTexture(Cell.vars.texture)

    -- 根据当前玩家职业和血量百分比计算血条颜色
    local r, g, b = F.GetHealthBarColor(1, false, F.GetClassColor(Cell.vars.playerClass))
    previewButton.widgets.healthBar:SetStatusBarColor(r, g, b, CellDB["appearance"]["barAlpha"])

    -- 根据当前玩家职业计算能量条颜色
    r, g, b = F.GetPowerBarColor("player", Cell.vars.playerClass)
    previewButton.widgets.powerBar:SetStatusBarColor(r, g, b)

    -- 应用背景透明度
    previewButton:SetBackdropColor(0, 0, 0, CellDB["appearance"]["bgAlpha"])

    previewButton:Show()

    -- 触发 UpdatePreview 事件，允许其他模块同步更新预览按钮的扩展元素
    Cell.Fire("UpdatePreview", previewButton)
end

-------------------------------------------------
-- glow options
-------------------------------------------------

-- 发光选项面板的 UI 控件，在 CreateGlowOptionsFrame() 中初始化
-- glowTypeDropdown: 发光类型下拉菜单（Normal/Pixel/Shine/Proc）
-- glowColor:       发光颜色选择器
-- glowLines:       线条数量滑块（Normal/Pixel 类型使用）
-- glowParticles:   粒子数量滑块（Shine 类型使用）
-- glowDuration:    动画持续时间滑块（Proc 类型使用）
-- glowFrequency:   频率滑块（Normal/Pixel/Shine 类型使用）
-- glowLength:      长度滑块（Normal/Pixel 类型使用）
-- glowThickness:   厚度滑块（Normal/Pixel 类型使用）
-- glowScale:       缩放滑块（Shine 类型使用）
-- glowOffsetX/Y:   X/Y 偏移滑块（Pixel/Shine/Proc 类型使用）
local glowTypeDropdown, glowColor, glowLines, glowParticles, glowDuration, glowFrequency, glowLength, glowThickness, glowScale, glowOffsetX, glowOffsetY

-- 根据当前 glowOptionsTable 中的发光类型和参数，在预览按钮上启停对应的发光效果
-- refresh 参数为 true 时，Shine 类型会先停止再重新开始（用于粒子数量等参数变化时需要完全刷新动画的场景）
local function UpdateGlowPreview(refresh)
    local glowType, glowOptions = unpack(glowOptionsTable)

    if glowType == "normal" then
        -- Normal: 使用 Blizzard 原生按钮发光边框，只需颜色参数
        LCG.PixelGlow_Stop(previewButton)
        LCG.AutoCastGlow_Stop(previewButton)
        LCG.ProcGlow_Stop(previewButton)
        LCG.ButtonGlow_Start(previewButton, glowOptions[1])
    elseif glowType == "pixel" then
        -- Pixel: 像素化旋转发光边框
        -- 参数: color, x, y, N(线条数), frequency(频率), length(长度), thickness(厚度)
        LCG.ButtonGlow_Stop(previewButton)
        LCG.AutoCastGlow_Stop(previewButton)
        LCG.ProcGlow_Stop(previewButton)
        LCG.PixelGlow_Start(previewButton, glowOptions[1], glowOptions[4], glowOptions[5], glowOptions[6], glowOptions[7], glowOptions[2], glowOptions[3])
    elseif glowType == "shine" then
        -- Shine: 从左到右的闪光扫过效果
        -- 参数: color, x, y, N(粒子数), frequency(频率), scale(缩放)
        LCG.ButtonGlow_Stop(previewButton)
        LCG.PixelGlow_Stop(previewButton)
        LCG.ProcGlow_Stop(previewButton)
        if refresh then LCG.AutoCastGlow_Stop(previewButton) end
        LCG.AutoCastGlow_Start(previewButton, glowOptions[1], glowOptions[4], glowOptions[5], glowOptions[6], glowOptions[2], glowOptions[3])
    elseif glowType == "proc" then
        -- Proc: 触发时的光圈扩散效果
        -- 参数: color, xOffset, yOffset, duration(持续时间)
        LCG.ButtonGlow_Stop(previewButton)
        LCG.PixelGlow_Stop(previewButton)
        LCG.AutoCastGlow_Stop(previewButton)
        LCG.ProcGlow_Start(previewButton, {color=glowOptions[1], xOffset=glowOptions[2], yOffset=glowOptions[3], duration=glowOptions[4], startAnim=false})
    end
end

-- 将 glowOptionsTable 中的参数加载到 UI 控件中，并刷新预览
-- 根据发光类型显示/隐藏对应的参数滑块，不同类型的可用参数不同：
--   Normal: Lines, Frequency, Length, Thickness
--   Pixel:  Lines, Frequency, Length, Thickness + X/Y Offset
--   Shine:  Particles, Frequency, Scale + X/Y Offset
--   Proc:   Duration + X/Y Offset
local function LoadGlowOptions()
    UpdateGlowPreview()

    local glowType, glowOptions = unpack(glowOptionsTable)
    glowTypeDropdown:SetSelectedValue(glowType)
    glowColor:SetColor(glowOptions[1])

    -- Normal 类型没有偏移、线条、频率、长度、厚度参数，禁用这些滑块
    glowOffsetX:SetEnabled(glowType ~= "normal")
    glowOffsetY:SetEnabled(glowType ~= "normal")
    glowLines:SetEnabled(glowType ~= "normal")
    glowFrequency:SetEnabled(glowType ~= "normal")
    glowLength:SetEnabled(glowType ~= "normal")
    glowThickness:SetEnabled(glowType ~= "normal")

    if glowType == "normal" then
        -- Normal: 显示线条相关滑块，隐藏粒子/持续时间/缩放
        glowLines:Show()
        glowFrequency:Show()
        glowLength:Show()
        glowThickness:Show()

        glowParticles:Hide()
        glowDuration:Hide()
        glowScale:Hide()

    elseif glowType == "pixel" then
        -- Pixel: 显示线条相关滑块 + X/Y 偏移，隐藏粒子/持续时间/缩放
        glowLines:Show()
        glowFrequency:Show()
        glowLength:Show()
        glowThickness:Show()

        glowParticles:Hide()
        glowDuration:Hide()
        glowScale:Hide()

        glowOffsetX:SetValue(glowOptions[2])
        glowOffsetY:SetValue(glowOptions[3])
        glowLines:SetValue(glowOptions[4])
        glowFrequency:SetValue(glowOptions[5])
        glowLength:SetValue(glowOptions[6])
        glowThickness:SetValue(glowOptions[7])

    elseif glowType == "shine" then
        -- Shine: 显示粒子/频率/缩放 + X/Y 偏移，隐藏线条/持续时间/长度/厚度
        glowParticles:Show()
        glowFrequency:Show()
        glowScale:Show()

        glowLines:Hide()
        glowDuration:Hide()
        glowLength:Hide()
        glowThickness:Hide()

        glowOffsetX:SetValue(glowOptions[2])
        glowOffsetY:SetValue(glowOptions[3])
        glowParticles:SetValue(glowOptions[4])
        glowFrequency:SetValue(glowOptions[5])
        glowScale:SetValue(glowOptions[6]*100)  -- Scale 在 UI 中以百分比显示（50-500），存储时除以 100

    elseif glowType == "proc" then
        -- Proc: 仅显示持续时间和 X/Y 偏移
        glowDuration:Show()

        glowLines:Hide()
        glowParticles:Hide()
        glowFrequency:Hide()
        glowLength:Hide()
        glowThickness:Hide()
        glowScale:Hide()

        glowOffsetX:SetValue(glowOptions[2])
        glowOffsetY:SetValue(glowOptions[3])
        glowDuration:SetValue(glowOptions[4])
    end
end

-- 切换发光类型时调用
-- 更新 glowOptionsTable[1] 为新的发光类型字符串
-- 保留原有颜色 glowOptionsTable[2][1]，其余参数重置为该类型的默认值
local function UpdateGlowType(glowType)
    glowOptionsTable[1] = glowType

    if glowType == "normal" then
        -- Normal: 仅需颜色 {r, g, b, a}
        glowOptionsTable[2] = {glowOptionsTable[2][1]}
    elseif glowType == "pixel" then
        -- Pixel: {color, xOffset, yOffset, lines(N), frequency, length, thickness}
        glowOptionsTable[2] = {glowOptionsTable[2][1], 0, 0, 9, 0.25, 8, 2}
    elseif glowType == "shine" then
        -- Shine: {color, xOffset, yOffset, particles(N), frequency, scale}
        glowOptionsTable[2] = {glowOptionsTable[2][1], 0, 0, 9, 0.5, 1}
    elseif glowType == "proc" then
        -- Proc: {color, xOffset, yOffset, duration}
        glowOptionsTable[2] = {glowOptionsTable[2][1], 0, 0, 1}
    end

    LoadGlowOptions()
end

-- 滑块数值变化时的统一回调
-- index:   glowOptionsTable[2] 中的参数索引（2=X偏移, 3=Y偏移, 4=线条/粒子/持续时间, 5=频率, 6=长度/缩放, 7=厚度）
-- value:   新的数值
-- refresh: 是否强制刷新发光动画（用于粒子数量等需要完全重启动画的参数）
local function SliderValueChanged(index, value, refresh)
    -- 将新值写入当前发光选项表
    glowOptionsTable[2][index] = value
    -- 刷新发光预览
    UpdateGlowPreview(refresh)
end

-- 创建发光选项编辑面板
-- 包含发光类型下拉菜单、颜色选择器以及各类型的参数滑块
-- 面板位于主选项框体右侧，宽度 127，高度 371
-- 控件按垂直方向依次排列：类型 -> 颜色 -> X偏移 -> Y偏移 -> 线条/粒子/持续时间 -> 频率 -> 长度/缩放 -> 厚度
-- 注意：多个滑块通过 Show/Hide 在同一位置切换显示，避免重新布局
local function CreateGlowOptionsFrame()
    glowOptionsFrame = Cell.CreateFrame("CellOptionsFrame_GlowOptions", Cell.frames.optionsFrame, 127, 371)
    glowOptionsFrame:SetPoint("BOTTOMLEFT", Cell.frames.optionsFrame, "BOTTOMRIGHT", 5, 0)

    -- 发光类型标签
    local glowTypeText = glowOptionsFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    glowTypeText:SetText(L["Glow Type"])
    glowTypeText:SetPoint("TOPLEFT", 5, -5)

    -- 发光类型下拉菜单：Normal / Pixel / Shine / Proc 四种类型
    glowTypeDropdown = Cell.CreateDropdown(glowOptionsFrame, 117)
    glowTypeDropdown:SetPoint("TOPLEFT", 5, -22)
    glowTypeDropdown:SetItems({
        {
            ["text"] = L["Normal"],
            ["value"] = "normal",
            ["onClick"] = function()
                UpdateGlowType("normal")
            end,
        },
        {
            ["text"] = L["Pixel"],
            ["value"] = "pixel",
            ["onClick"] = function()
                UpdateGlowType("pixel")
            end,
        },
        {
            ["text"] = L["Shine"],
            ["value"] = "shine",
            ["onClick"] = function()
                UpdateGlowType("shine")
            end,
        },
        {
            ["text"] = L["Proc"],
            ["value"] = "proc",
            ["onClick"] = function()
                UpdateGlowType("proc")
            end,
        },
    })

    -- 发光颜色选择器：不透明度始终为 1，仅编辑 RGB
    glowColor = Cell.CreateColorPicker(glowOptionsFrame, L["Glow Color"], false, function(r, g, b)
        -- 将颜色写入 glowOptionsTable[2][1] = {r, g, b, 1}
        glowOptionsTable[2][1][1] = r
        glowOptionsTable[2][1][2] = g
        glowOptionsTable[2][1][3] = b
        glowOptionsTable[2][1][4] = 1
        -- 实时刷新预览
        UpdateGlowPreview()
    end)
    -- glowColor:SetPoint("TOPLEFT", glowOptionsFrame, 5, 0)
    glowColor:SetPoint("TOPLEFT", glowTypeDropdown, "BOTTOMLEFT", 0, -10)

    -- X 偏移滑块：范围 -100 到 100，步长 1，更新 glowOptionsTable[2][2]
    glowOffsetX = Cell.CreateSlider(L["X Offset"], glowOptionsFrame, -100, 100, 117, 1, function(value)
        SliderValueChanged(2, value)
    end)
    glowOffsetX:SetPoint("TOPLEFT", glowColor, "BOTTOMLEFT", 0, -25)

    -- Y 偏移滑块：范围 -100 到 100，步长 1，更新 glowOptionsTable[2][3]
    glowOffsetY = Cell.CreateSlider(L["Y Offset"], glowOptionsFrame, -100, 100, 117, 1, function(value)
        SliderValueChanged(3, value)
    end)
    glowOffsetY:SetPoint("TOPLEFT", glowOffsetX, "BOTTOMLEFT", 0, -40)

    -- 线条数量滑块：范围 1-30，步长 1，用于 Normal/Pixel 类型，更新 glowOptionsTable[2][4]
    glowLines = Cell.CreateSlider(L["Lines"], glowOptionsFrame, 1, 30, 117, 1, function(value)
        SliderValueChanged(4, value)
    end)
    glowLines:SetPoint("TOPLEFT", glowOffsetY, "BOTTOMLEFT", 0, -40)

    -- 粒子数量滑块：范围 1-30，步长 1，用于 Shine 类型，变化时需要强制刷新动画（refresh=true）
    glowParticles = Cell.CreateSlider(L["Particles"], glowOptionsFrame, 1, 30, 117, 1, function(value)
        SliderValueChanged(4, value, true)
    end)
    glowParticles:SetPoint("TOPLEFT", glowOffsetY, "BOTTOMLEFT", 0, -40)

    -- 持续时间滑块：范围 0.1-3 秒，步长 0.1，用于 Proc 类型，变化时需要强制刷新动画
    glowDuration = Cell.CreateSlider(L["Duration"], glowOptionsFrame, 0.1, 3, 117, 0.1, function(value)
        SliderValueChanged(4, value, true)
    end)
    glowDuration:SetPoint("TOPLEFT", glowOffsetY, "BOTTOMLEFT", 0, -40)

    -- 频率滑块：范围 -2 到 2，步长 0.01，用于 Normal/Pixel/Shine 类型，更新 glowOptionsTable[2][5]
    glowFrequency = Cell.CreateSlider(L["Frequency"], glowOptionsFrame, -2, 2, 117, 0.01, function(value)
        SliderValueChanged(5, value)
    end)
    glowFrequency:SetPoint("TOPLEFT", glowLines, "BOTTOMLEFT", 0, -40)

    -- 长度滑块：范围 1-20，步长 1，用于 Normal/Pixel 类型，更新 glowOptionsTable[2][6]
    glowLength = Cell.CreateSlider(L["Length"], glowOptionsFrame, 1, 20, 117, 1, function(value)
        SliderValueChanged(6, value)
    end)
    glowLength:SetPoint("TOPLEFT", glowFrequency, "BOTTOMLEFT", 0, -40)

    -- 厚度滑块：范围 1-20，步长 1，用于 Normal/Pixel 类型，更新 glowOptionsTable[2][7]
    glowThickness = Cell.CreateSlider(L["Thickness"], glowOptionsFrame, 1, 20, 117, 1, function(value)
        SliderValueChanged(7, value)
    end)
    glowThickness:SetPoint("TOPLEFT", glowLength, "BOTTOMLEFT", 0, -40)

    -- 缩放滑块：范围 50%-500%，步长 1%，用于 Shine 类型
    -- UI 显示百分比值，存储时除以 100，更新 glowOptionsTable[2][6]
    -- 第 4 个参数为 true 表示值以百分比格式显示
    glowScale = Cell.CreateSlider(L["Scale"], glowOptionsFrame, 50, 500, 117, 1, function(value)
        SliderValueChanged(6, value/100)
    end, nil, true)
    glowScale:SetPoint("TOPLEFT", glowFrequency, "BOTTOMLEFT", 0, -40)

    -- OnHide 脚本：面板隐藏时保持隐藏状态（阻止默认的显示行为）
    glowOptionsFrame:SetScript("OnHide", function()
        glowOptionsFrame:Hide()
    end)
end

-------------------------------------------------
-- functions (公开接口，挂载到 U = Cell.uFuncs)
-------------------------------------------------

-- 显示发光选项编辑面板
-- parent: 父框体，面板将附着于该框体
-- t:     发光选项表，格式 {glowType, {color{r,g,b,a}, param2, param3, ...}}
--         面板在显示/隐藏之间切换：若已显示则隐藏，若隐藏则显示
function U.ShowGlowOptions(parent, t)
    if not glowOptionsFrame then
        CreateGlowOptionsFrame()
    end

    if glowOptionsFrame:IsShown() then
        -- 已显示则关闭
        glowOptionsFrame:Hide()
    else
        -- 未显示则初始化并打开
        glowOptionsFrame:SetParent(parent)
        glowOptionsTable = t
        UpdatePreviewButton()
        LoadGlowOptions()
        glowOptionsFrame:Show()
    end
end

-- 隐藏发光选项编辑面板
function U.HideGlowOptions()
    if glowOptionsFrame then glowOptionsFrame:Hide() end
end

-------------------------------------------------
-- callbacks (Cell 事件回调注册)
-------------------------------------------------

-- 布局更新回调：当用户调整框体布局（尺寸、方向等）时，同步更新预览按钮
local function UpdateLayout()
    if previewButton then
        UpdatePreviewButton()
    end
end
Cell.RegisterCallback("UpdateLayout", "GlowOptions_UpdateLayout", UpdateLayout)

-- 外观更新回调：当用户调整外观设置（纹理、颜色、透明度等）时，同步更新预览按钮
local function UpdateAppearance()
    if previewButton then
        UpdatePreviewButton()
    end
end
Cell.RegisterCallback("UpdateAppearance", "GlowOptions_UpdateAppearance", UpdateAppearance)