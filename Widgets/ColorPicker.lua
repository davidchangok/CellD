local addonName, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 顶层控件引用：主窗口、颜色预览、色相饱和度区域、亮度/透明度滑块、取色指示器
local colorPicker
local current, original, hueSaturationBG, hueSaturation, brightness, alpha, picker
-- 输入框引用：R/G/B/A/H/S/B/Hex 八个编辑框
local rEB, gEB, bEB, aEB, h_EB, s_EB, b_EB, hexEB
-- 确认 / 取消按钮
local confirmBtn, cancelBtn

-- 实时颜色变更回调（每次拖动或输入都会触发，用于即时预览）
local Callback

-- 打开取色器时的原始颜色备份（用于取消时恢复）
local oR, oG, oB, oA
-- 当前颜色在 HSB 色彩空间的值（0-360 / 0-1 / 0-1）及透明度 A（0-1）
local H, S, B, A

-------------------------------------------------
-- 更新函数：负责将颜色变更同步到所有控件（预览、滑块、输入框）
-------------------------------------------------

-- 用 RGBA 值更新"当前颜色"预览块以及所有 RGB/Alpha/Hex 输入框
-- @param r,g,b 0-1 范围的浮点值
-- @param a 0-1 范围的透明度
local function UpdateColor_RGBA(r, g, b, a)
    -- 更新"当前颜色"预览块（左半实色 + 右半含透明度的对比预览）
    current:SetColor(r, g, b, a)

    -- 转为 0-255 整数供输入框显示
    r, g, b = math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)

    -- 同步所有 RGB/Alpha/Hex 输入框文本
    rEB:SetText(r)
    gEB:SetText(g)
    bEB:SetText(b)
    aEB:SetText(math.floor(a * 100))
    hexEB:SetText(F.ConvertRGBToHEX(r, g, b))
end

-- 用 HSBA 值更新 HSB 输入框、亮度条渐变、以及取色指示器和滑块位置
-- @param h 0-360 色相
-- @param s,b 0-1 饱和度/亮度
-- @param a 0-1 透明度
-- @param updateBrightness 是否刷新亮度条的渐变颜色（色相/饱和度变化时需要）
-- @param updatePickers 是否移动取色指示器和滑块位置（颜色来源变化时需要）
local function UpdateColor_HSBA(h, s, b, a, updateBrightness, updatePickers)
    h_EB:SetText(math.floor(h))
    s_EB:SetText(math.floor(s * 100))
    b_EB:SetText(math.floor(b * 100))

    if updateBrightness then
        -- 亮度条需要从纯黑渐变到当前色相+饱和度的纯色（亮度=1时的颜色）
        local _r, _g, _b = F.ConvertHSBToRGB(h, s, 1)
        brightness.tex:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(_r, _g, _b, 1))
    end

    if updatePickers then
        -- 移动色相-饱和度平面上的取色指示器
        picker:SetPoint("CENTER", hueSaturation, "BOTTOMLEFT", H/360*hueSaturation:GetWidth(), S*hueSaturation:GetHeight())
        -- 同步亮度滑块（注意：亮度滑块值越高越暗，取反）
        brightness:SetValue(1-B)
        -- 同步透明度滑块（同样取反：值越高越透明）
        alpha:SetValue(1-a)
    end
end

-- 核心更新调度函数：统一入口，根据颜色空间来源（RGB 或 HSB）驱动双向同步
-- @param use "rgb" 或 "hsb"，标识本次变更的来源色彩空间
-- @param v1,v2,v3 颜色分量（RGB 0-1 或 HSB 分别按各自范围）
-- @param a 透明度 0-1
-- @param updateBrightness 同 UpdateColor_HSBA
-- @param updatePickers 同 UpdateColor_HSBA
local function UpdateAll(use, v1, v2, v3, a, updateBrightness, updatePickers)
    if use == "rgb" then
        -- 来源是 RGB：先更新 RGB 相关控件，再转为 HSB 更新 HSB 控件
        UpdateColor_RGBA(v1, v2, v3, a)
        local h, s, b = F.ConvertRGBToHSB(v1, v2, v3)
        UpdateColor_HSBA(h, s, b, a, updateBrightness, updatePickers)
        if Callback then Callback(v1, v2, v3, a) end
    elseif use == "hsb" then
        -- 来源是 HSB：先更新 HSB 相关控件，再转为 RGB 更新 RGB 控件
        UpdateColor_HSBA(v1, v2, v3, a, updateBrightness, updatePickers)
        local r, g, b = F.ConvertHSBToRGB(v1, v2, v3)
        UpdateColor_RGBA(r, g, b, a)
        if Callback then Callback(r, g, b, a) end
    end
end

-------------------------------------------------
-- 创建取色器主窗口及所有子控件
-------------------------------------------------

-- 创建一个带标签的颜色值编辑框，绑定焦点/回车事件
-- @param label 编辑框上方显示的标签文本（如 "R", "G", "B", "A", "H", "S", "Hex"）
-- @param width,height 编辑框尺寸
-- @param isNumeric 是否仅允许数字输入
-- @param group 编辑框所属分组："rgb" / "hsb" / nil（Alpha） / 非数字时预期为 hex
-- @return 创建好的编辑框 Frame
local function CreateEB(label, width, height, isNumeric, group)
    local eb = Cell.CreateEditBox(colorPicker, width, height, false, false, isNumeric)
    -- 在编辑框上方创建标签文本
    eb.label = eb:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    eb.label:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 1)
    eb.label:SetText(label)

    -- 获得焦点时：全选文本以便快速输入，同时保存旧文本以在清空时恢复
    eb:SetScript("OnEditFocusGained", function()
        eb:HighlightText()
        eb.oldText = eb:GetText()
    end)

    -- 失去焦点时：取消选中，如果用户清空了内容则恢复旧文本
    eb:SetScript("OnEditFocusLost", function()
        eb:HighlightText(0, 0)
        if eb:GetText() == "" then
            eb:SetText(eb.oldText)
        end
    end)

    -- 按回车确认输入：校验范围、转换颜色空间、触发全局更新
    eb:SetScript("OnEnterPressed", function()
        if isNumeric then
            if group == "rgb" then
                -- RGB 组：钳制上限到 255，转为 0-1 浮点，反推 HSB，全量刷新
                if rEB:GetNumber() > 255 then
                    rEB:SetText(255)
                end
                if gEB:GetNumber() > 255 then
                    gEB:SetText(255)
                end
                if bEB:GetNumber() > 255 then
                    bEB:SetText(255)
                end

                local r, g, b = F.ConvertRGB(rEB:GetNumber(), gEB:GetNumber(), bEB:GetNumber())
                H, S, B = F.ConvertRGBToHSB(r, g, b)
                UpdateAll("rgb", r, g, b, A, true, true)

            elseif group == "hsb" then
                -- HSB 组：H 钳制到 360，S/B 钳制到 100，全量刷新
                if h_EB:GetNumber() > 360 then
                    h_EB:SetText(360)
                end
                if s_EB:GetNumber() > 100 then
                    s_EB:SetText(100)
                end
                if b_EB:GetNumber() > 100 then
                    b_EB:SetText(100)
                end

                H, S, B = h_EB:GetNumber(), s_EB:GetNumber()/100, b_EB:GetNumber()/100
                UpdateAll("hsb", H, S, B, A, true, true)

            else -- alpha 透明度：钳制到 100，只刷透明度滑块和回调
                if aEB:GetNumber() > 100 then
                    aEB:SetText(100)
                end
                A = aEB:GetNumber()/100

                alpha:SetValue(1-A)
                UpdateAll("hsb", H, S, B, A)
            end

        else -- hex：校验是否为 6 位十六进制字符串，无效则恢复旧值
            local text = strtrim(hexEB:GetText())
            -- print(text, hexEB.oldText)
            if strlen(text) ~= 6 or not strmatch(text, "^[0-9a-fA-F]+$") then
                hexEB:SetText(hexEB.oldText)
            end

            local r, g, b = F.ConvertRGB(F.ConvertHEXToRGB(hexEB:GetText()))
            H, S, B = F.ConvertRGBToHSB(r, g, b)
            UpdateAll("rgb", r, g, b, A, true, true)
        end

        eb:ClearFocus()
    end)

    return eb
end

-- 创建取色器主窗口及所有子控件（仅首次调用时执行）
local function CreateColorPicker()
    local name = addonName.."ColorPicker"

    -- 主窗口：可拖拽的 Dialog 风格 Frame，尺寸 216x295，隐藏关闭按钮
    colorPicker = Cell.CreateMovableFrame(_G.COLOR_PICKER, name, 216, 295, "DIALOG", 1, true)
    colorPicker:SetToplevel(true)
    colorPicker:SetPoint("CENTER")
    colorPicker.header.closeBtn:Hide()

    --------------------------------------------------
    -- "当前"颜色预览块（左上角，97x27）
    -- 左半部分显示实色填充，右半部分显示含透明度的颜色（与棋盘格背景对比）
    --------------------------------------------------
    current = CreateFrame("Frame", name.."Current", colorPicker, "BackdropTemplate")
    Cell.StylizeFrame(current)
    P.Size(current, 97, 27)
    current:SetPoint("TOPLEFT", 7, -7)

    current.solid = current:CreateTexture(nil, "ARTWORK")
    current.solid:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
    current.solid:SetPoint("BOTTOMRIGHT", current, "BOTTOMLEFT", current:GetWidth()/2, P.Scale(1))

    current.alpha = current:CreateTexture(nil, "ARTWORK")
    current.alpha:SetPoint("TOPLEFT", current.solid, "TOPRIGHT")
    current.alpha:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))

    -- 设置当前颜色预览：左半实色 + 右半带透明度
    function current:SetColor(r, g, b, a)
        current.solid:SetColorTexture(r, g, b)
        current.alpha:SetColorTexture(r, g, b, a)
    end

    --------------------------------------------------
    -- "原始"颜色预览块（右上角，97x27，与当前预览对称）
    -- 用于对比显示打开取色器时的初始颜色，点击取消时恢复到此颜色
    --------------------------------------------------
    original = CreateFrame("Frame", name.."Original", colorPicker, "BackdropTemplate")
    Cell.StylizeFrame(original)
    P.Size(original, 97, 27)
    original:SetPoint("TOPRIGHT", -7, -7)

    original.solid = original:CreateTexture(nil, "ARTWORK")
    original.solid:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
    original.solid:SetPoint("BOTTOMRIGHT", original, "BOTTOMLEFT", original:GetWidth()/2, P.Scale(1))

    original.alpha = original:CreateTexture(nil, "ARTWORK")
    original.alpha:SetPoint("TOPLEFT", original.solid, "TOPRIGHT")
    original.alpha:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))

    -- 设置原始颜色预览
    function original:SetColor(r, g, b, a)
        original.solid:SetColorTexture(r, g, b)
        original.alpha:SetColorTexture(r, g, b, a)
    end

    --------------------------------------------------
    -- 色相-饱和度选择平面（130x130）
    -- 水平方向：6 段渐变覆盖完整色相环（红->黄->绿->青->蓝->紫->红）
    -- 垂直方向：白色到透明渐变叠加，实现饱和度从 100% 到 0%
    --------------------------------------------------
    hueSaturationBG = CreateFrame("Frame", name.."HueSaturation", colorPicker, "BackdropTemplate")
    Cell.StylizeFrame(hueSaturationBG)
    P.Size(hueSaturationBG, 130, 130)
    hueSaturationBG:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, -7)

    hueSaturation = CreateFrame("Frame", nil, hueSaturationBG)
    hueSaturation:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
    hueSaturation:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))

    -- 用 6 段水平渐变纹理拼出完整色相环（每段宽度 = 总宽 / 6）
    local sectionSize = hueSaturation:GetWidth() / 6
    local color = {
        { r=1, g=0, b=0 },    -- Red    红
        { r=1, g=1, b=0 },    -- Yellow 黄
        { r=0, g=1, b=0 },    -- Green  绿
        { r=0, g=1, b=1 },    -- Cyan   青
        { r=0, g=0, b=1 },    -- Blue   蓝
        { r=1, g=0, b=1 },    -- Purple 紫
        { r=1, g=0, b=0 },    -- back to Red  回到红（闭合色相环）
    }
    for i = 1, 6 do
        hueSaturation[i] = hueSaturation:CreateTexture(name.."HS_Gradient"..i, "ARTWORK", nil, 0)
        hueSaturation[i]:SetTexture(Cell.vars.whiteTexture)
        -- hueSaturation[i]:SetColorTexture(1, 1, 1, 1)
        -- hueSaturation[i]:SetVertexColor(1, 1, 1, 1)
        hueSaturation[i]:SetGradient("HORIZONTAL", CreateColor(color[i].r, color[i].g, color[i].b, 1), CreateColor(color[i+1].r, color[i+1].g, color[i+1].b, 1))

        -- 每段宽度
        hueSaturation[i]:SetWidth(sectionSize)

        -- 首段锚定左上角，后续段紧接前一段右侧
        if i == 1 then
            hueSaturation[i]:SetPoint("TOPLEFT")
        else
            hueSaturation[i]:SetPoint("TOPLEFT", hueSaturation[i-1], "TOPRIGHT")
        end
        hueSaturation[i]:SetPoint("BOTTOM")
    end

    -- 叠加垂直饱和度渐变：顶部白色（饱和度0% = 纯白），底部透明（饱和度100% = 纯色）
    local saturation = hueSaturation:CreateTexture(name.."HS_Saturation", "ARTWORK", nil, 1)
    saturation:SetBlendMode("BLEND")
    saturation:SetTexture(Cell.vars.whiteTexture)
    saturation:SetGradient("VERTICAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))
    saturation:SetAllPoints(hueSaturation)

    --------------------------------------------------
    -- 亮度滑块（垂直方向，17x130，位于色相平面右侧）
    -- 渐变从纯黑（亮度0%）到当前色相+饱和度的纯色（亮度100%）
    --------------------------------------------------
    brightness = CreateFrame("Slider", nil, colorPicker, "BackdropTemplate")
    Cell.StylizeFrame(brightness)
    brightness:SetValueStep(0.01)
    brightness:SetMinMaxValues(0, 1)
    brightness:SetObeyStepOnDrag(true)
    brightness:SetOrientation("VERTICAL")
    P.Size(brightness, 17, 130)
    brightness:SetPoint("TOPLEFT", hueSaturation, "TOPRIGHT", 15, 0)

    -- 亮度滑块值变更事件：value 越大越暗，因此 B = 1 - value
    -- 仅响应用户操作（userChanged=true），并通过 prev 去重避免循环更新
    brightness:SetScript("OnValueChanged", function(self, value, userChanged)
        if not userChanged then return end
        B = 1 - value

        if brightness.prev == B then return end
        brightness.prev = B

        -- 通过 HSB 路径触发全局更新
        UpdateAll("hsb", H, S, B, A)
    end)

    -- 亮度滑块背景纹理（渐变由 UpdateColor_HSBA 动态刷新）
    brightness.tex = brightness:CreateTexture(nil, "ARTWORK")
    brightness.tex:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
    brightness.tex:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))
    brightness.tex:SetTexture(Cell.vars.whiteTexture)

    -- 亮度滑块的滑块指示器：由一条细线(thumb1) + 一个圆点图标(thumb2) 组成
    brightness.thumb1 = brightness:CreateTexture(nil, "ARTWORK")
    -- brightness.thumb1:SetColorTexture(0, 1, 0, 1)
    P.Size(brightness.thumb1, 17, 1)
    brightness:SetThumbTexture(brightness.thumb1)

    brightness.thumb2 = brightness:CreateTexture(nil, "ARTWORK")
    brightness.thumb2:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\thumb.tga")
    P.Size(brightness.thumb2, 16, 16)
    brightness.thumb2:SetPoint("LEFT", brightness.thumb1, "RIGHT", -5, 0)

    --------------------------------------------------
    -- 透明度滑块（垂直方向，17x130，位于亮度滑块右侧）
    -- 渐变从纯黑（不透明）到纯白（完全透明），支持启用/禁用状态
    --------------------------------------------------
    alpha = CreateFrame("Slider", nil, colorPicker, "BackdropTemplate")
    Cell.StylizeFrame(alpha)
    alpha:SetValueStep(0.01)
    alpha:SetMinMaxValues(0, 1)
    alpha:SetObeyStepOnDrag(true)
    alpha:SetOrientation("VERTICAL")
    P.Size(alpha, 17, 130)
    alpha:SetPoint("TOPLEFT", brightness, "TOPRIGHT", 15, 0)

    -- 启用时恢复正常外观
    alpha:SetScript("OnEnable", function()
        alpha:SetAlpha(1)
        alpha.thumb2:SetVertexColor(1, 1, 1, 1)
    end)
    -- 禁用时半透明显示，表示不可操作
    alpha:SetScript("OnDisable", function()
        alpha:SetAlpha(0.2)
        alpha.thumb2:SetVertexColor(0.2, 0.2, 0.2, 1)
    end)
    -- 同亮度滑块：仅响应用户操作，去重，通过 HSB 路径更新
    alpha:SetScript("OnValueChanged", function(self, value, userChanged)
        if not userChanged then return end
        A = 1 - value

        if alpha.prev == A then return end
        alpha.prev = A

        -- 通过 HSB 路径触发全局更新
        UpdateAll("hsb", H, S, B, A)
    end)

    -- 透明度滑块背景：从纯黑（底部，不透明）到纯白（顶部，完全透明）
    alpha.tex = alpha:CreateTexture(nil, "ARTWORK")
    alpha.tex:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
    alpha.tex:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))
    alpha.tex:SetTexture(Cell.vars.whiteTexture)
    alpha.tex:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(1, 1, 1, 1))

    alpha.thumb1 = alpha:CreateTexture(nil, "ARTWORK")
    P.Size(alpha.thumb1, 17, 1)
    alpha:SetThumbTexture(alpha.thumb1)

    alpha.thumb2 = brightness:CreateTexture(nil, "ARTWORK")
    alpha.thumb2:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\thumb.tga")
    P.Size(alpha.thumb2, 16, 16)
    alpha.thumb2:SetPoint("LEFT", alpha.thumb1, "RIGHT", -5, 0)

    --------------------------------------------------
    -- 色相-饱和度取色指示器（10x10 小圆点，可在 HS 平面上拖拽）
    -- X 轴 = 色相 H（0-360），Y 轴 = 饱和度 S（0-1）
    --------------------------------------------------
    picker = CreateFrame("Frame", name.."HSPicker", hueSaturation, "BackdropTemplate")
    P.Size(picker, 10, 10)
    picker:SetPoint("CENTER", hueSaturation, "BOTTOMLEFT")

    -- 使用暴雪原生取色器按钮贴图作为指示器外观
    picker.tex = picker:CreateTexture(nil, "ARTWORK")
    picker.tex:SetAllPoints(picker)
    picker.tex:SetTexture("Interface\\Buttons\\UI-ColorPicker-Buttons")
    picker.tex:SetTexCoord(0, 0.15625, 0, 0.625)

    picker:EnableMouse(true)
    picker:SetMovable(true)

    -- 开始拖拽取色指示器：注册 OnUpdate 每帧跟踪鼠标并更新位置和颜色
    -- @param x,y 取色器在 hueSaturation 中的初始偏移
    -- @param mouseX,mouseY 鼠标按下时的屏幕坐标（含缩放）
    function picker:StartMoving(x, y, mouseX, mouseY)
        local scale = picker:GetEffectiveScale()

        local lastX, lastY
        self:SetScript("OnUpdate", function(self)
            local newMouseX, newMouseY = GetCursorPosition()
            -- 鼠标未移动则跳过，避免无谓的更新
            if newMouseX == lastX and newMouseY == lastY then return end
            lastX, lastY = newMouseX, newMouseY

            -- 根据鼠标位移计算取色器新位置
            local newX = x + (newMouseX - mouseX) / scale
            local newY = y + (newMouseY - mouseY) / scale

            -- 钳制在 hueSaturation 边界内（左/右边界）
            if newX < 0 then
                newX = 0
            elseif newX > hueSaturation:GetWidth() then
                newX = hueSaturation:GetWidth()
            end

            -- 钳制在 hueSaturation 边界内（下/上边界）
            if newY < 0 then
                newY = 0
            elseif newY > hueSaturation:GetHeight() then
                newY = hueSaturation:GetHeight()
            end

            picker:SetPoint("CENTER", hueSaturation, "BOTTOMLEFT", newX, newY)

            -- 从位置推导 HS 值：水平位置 -> 色相，垂直位置 -> 饱和度
            H = (newX / hueSaturation:GetWidth()) * 360
            S = newY / hueSaturation:GetHeight()

            -- 通过 HSB 路径触发全局更新（需刷新亮度条渐变，因为色相/饱和度变了）
            UpdateAll("hsb", H, S, B, A, true)
        end)
    end

    -- 鼠标按下取色指示器本身：记录起始位置并开始拖拽
    picker:SetScript("OnMouseDown", function(self, button)
        if button ~= 'LeftButton' then return end
        local x, y = select(4, picker:GetPoint(1))
        local mouseX, mouseY = GetCursorPosition()

        picker:StartMoving(x, y, mouseX, mouseY)
    end)

    -- 鼠标释放：移除 OnUpdate 脚本停止拖拽
    picker:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- 在色相-饱和度平面上任意位置点击也能开始拖拽取色器
    hueSaturation:SetScript("OnMouseDown", function(self, button)
        if button ~= 'LeftButton' then return end
        local hueSaturationX, hueSaturationY = hueSaturation:GetLeft(), hueSaturation:GetBottom()
        local mouseX, mouseY = GetCursorPosition()

        local scale = picker:GetEffectiveScale()
        mouseX, mouseY = mouseX/scale, mouseY/scale

        -- 将点击位置（相对于 hueSaturation 左下角）作为取色器的起始位置
        local x, y = select(4, picker:GetPoint(1))
        picker:StartMoving(mouseX/scale-hueSaturationX, mouseY/scale-hueSaturationY, mouseX, mouseY)
    end)

    -- 在色相-饱和度平面上释放鼠标也停止拖拽
    hueSaturation:SetScript("OnMouseUp", function(self, button)
        picker:SetScript("OnUpdate", nil)
    end)

    --------------------------------------------------
    -- 颜色值编辑框（两行排列）
    -- 第一行：R / G / B / A（RGB 组 + 透明度）
    -- 第二行：H / S / B / Hex（HSB 组 + 十六进制）
    --------------------------------------------------
    -- 红色编辑框（R, 0-255）
    rEB = CreateEB("R", 40, 20, true, "rgb")
    rEB:SetPoint("TOPLEFT", hueSaturationBG, "BOTTOMLEFT", 0, -25)

    -- 绿色编辑框（G, 0-255）
    gEB = CreateEB("G", 40, 20, true, "rgb")
    gEB:SetPoint("TOPLEFT", rEB, "TOPRIGHT", 7, 0)

    -- 蓝色编辑框（B, 0-255）
    bEB = CreateEB("B", 40, 20, true, "rgb")
    bEB:SetPoint("TOPLEFT", gEB, "TOPRIGHT", 7, 0)

    -- 透明度编辑框（A, 0-100，稍宽 61px）
    aEB = CreateEB("A", 61, 20, true)
    aEB:SetPoint("TOPLEFT", bEB, "TOPRIGHT", 7, 0)

    -- 色相编辑框（H, 0-360）
    h_EB = CreateEB("H", 40, 20, true, "hsb")
    h_EB:SetPoint("TOPLEFT", rEB, "BOTTOMLEFT", 0, -25)

    -- 饱和度编辑框（S, 0-100）
    s_EB = CreateEB("S", 40, 20, true, "hsb")
    s_EB:SetPoint("TOPLEFT", h_EB, "TOPRIGHT", 7, 0)

    -- 亮度编辑框（B, 0-100）
    b_EB = CreateEB("B", 40, 20, true, "hsb")
    b_EB:SetPoint("TOPLEFT", s_EB, "TOPRIGHT", 7, 0)

    -- 十六进制颜色编辑框（Hex, 宽 61px，非纯数字）
    hexEB = CreateEB("Hex", 61, 20, false, "rgb")
    hexEB:SetPoint("TOPLEFT", b_EB, "TOPRIGHT", 7, 0)

    --------------------------------------------------
    -- 底部按钮：确认（绿色）/ 取消（红色）
    --------------------------------------------------
    confirmBtn = Cell.CreateButton(colorPicker, L["Confirm"], "green", {97, 20})
    confirmBtn:SetPoint("BOTTOMLEFT", 7, 7)

    cancelBtn = Cell.CreateButton(colorPicker, L["Cancel"], "red", {97, 20})
    cancelBtn:SetPoint("BOTTOMRIGHT", -7, 7)
end

-------------------------------------------------
-- 显示取色器（外部调用入口）
-------------------------------------------------

-- 打开取色器窗口
-- @param callback   实时预览回调：每次颜色变更时调用 callback(r, g, b, a)，用于即时预览效果
-- @param onConfirm  确认回调：用户点击"确认"按钮时调用，传入最终选择的颜色
-- @param hasAlpha   是否启用透明度编辑（false 时 alpha 滑块和输入框变灰禁用）
-- @param r,g,b,a    初始颜色值（0-1 范围），未传则默认白色不透明
function Cell.ShowColorPicker(callback, onConfirm, hasAlpha, r, g, b, a)
    -- 延迟创建：首次打开时才构建整个取色器 UI
    if not colorPicker then
        CreateColorPicker()
    end

    -- 清除上一次会话的滑块去重标记，避免新颜色值被误判为重复而不触发更新
    brightness.prev = nil
    alpha.prev = nil

    -- 如果取色器已经显示，先将当前颜色恢复到原始值（相当于关闭上一次未完成的编辑）
    if colorPicker:IsShown() then
        if Callback then
            Callback(oR, oG, oB, oA)
        end
    end

    -- 保存原始颜色备份，取默认值白色（取消时恢复用）
    oR, oG, oB, oA = r or 1, g or 1, b or 1, a or 1

    -- 初始化当前 HSBA 值并保存回调引用
    H, S, B = F.ConvertRGBToHSB(oR, oG, oB)
    A = oA
    Callback = callback

    -- 确认按钮：隐藏窗口，将当前 HSBA 转为 RGB 后调用 onConfirm
    confirmBtn:SetScript("OnClick", function()
        colorPicker:Hide()
        if onConfirm then
            local r, g, b = F.ConvertHSBToRGB(H, S, B)
            onConfirm(r, g, b, A)
        end
    end)

    -- 取消按钮：隐藏窗口，通过实时回调恢复到打开时的原始颜色
    cancelBtn:SetScript("OnClick", function()
        colorPicker:Hide()
        if callback then callback(oR, oG, oB, oA) end
    end)

    -- 更新"原始"颜色预览块
    original:SetColor(oR, oG, oB, oA)

    -- 用初始颜色全量刷新所有控件（预览、滑块、输入框、取色器位置）
    UpdateAll("rgb", oR, oG, oB, oA, true, true)
    -- 根据 hasAlpha 参数启用或禁用透明度相关控件
    Cell.SetEnabled(hasAlpha, alpha, aEB, aEB.label)

    -- 像素完美居中并显示
    P.PixelPerfectPoint(colorPicker)
    colorPicker:Show()
end

-- 隐藏取色器窗口（外部调用入口，例如在 ESC 或点击外部区域时关闭）
function Cell.HideColorPicker()
    if colorPicker then
        colorPicker:Hide()
    end
end