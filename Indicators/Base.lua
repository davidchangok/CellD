local _, Cell = ...
local L = Cell.L
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs
---@type PixelPerfectFuncs
local P = Cell.pixelPerfectFuncs

-- ============================================================================
-- 模块概述：指示器基础控件工厂
-- ============================================================================
-- 本文件定义了 Cell 所有光环指示器类型的底层控件创建与更新逻辑。
-- 支持的指示器类型包括：
--   BorderIcon  - 带边框的图标（用于 debuff 等）
--   BarIcon     - 带状态条动画的图标
--   Icons       - 多图标容器（自动布局）
--   Text        - 纯文本指示器
--   Rect        - 矩形色块指示器
--   Bar         - 单个进度条指示器
--   Bars        - 多个进度条容器（自动布局）
--   Color       - 颜色覆盖层（支持纯色/渐变/随时间变色/职业色/debuff类型色）
--   Texture     - 自定义纹理指示器
--   Glow        - 发光效果指示器
--   Overlay     - 状态条覆盖层（支持平滑过渡）
--   Block       - 带冷却动画的块指示器
--   Blocks      - 多个块容器（自动布局）
--   Border      - 边框发光指示器
--   QuickAssistBars - 快速协助条
--
-- 每个指示器类型遵循统一模式：
--   1. 本地函数定义 OnUpdate 回调、SetCooldown、SetFont 等
--   2. 工厂函数 I.CreateAura_<Type> 创建控件并装配方法
--   3. OnUpdate 通过 elapsed 累加实现 0.1 秒节流
--
-- Midnight 12.0.0+ 防护要点：
--   - 光环堆叠数(count)可能为 secret value，通过 _SanitizeCount 清洗
--   - 冷却时间(duration)可能为 secret，通过 DurationObject 模式绕过直接读取
--   - SetText/SetFormattedText 原生接受 secret value，无需额外处理

-- NOTE (Midnight 12.0.0+): Health text formatting with arithmetic on health/maxHealth
-- is guarded for secret values in Indicators/Built-in.lua (HealthText_SetValue).
-- All other numeric display in this file uses SetText/SetFormattedText which accept secrets.

local LCG = LibStub("LibCustomGlow-1.0")

-- Midnight 12.0.0+: aura count (applications) may be secret; sanitize for safe comparisons/table-key use
-- 光环堆叠数可能在 Midnight 版本中被标记为 secret value，此函数将其清洗为普通的 0
-- 以避免在数值比较、表索引等场景中因 secret value 触发 UI 错误
local function _SanitizeCount(count)
    if issecretvalue and issecretvalue(count) then return 0 end
    return count or 0
end

-- Midnight 12.0.0+: helper for stack text display (most common pattern)
-- 生成堆叠数显示文本：0 或 1 层时不显示数字，2 层及以上显示层数
-- 所有堆叠数显示均通过此函数清洗，确保 secret value 不会意外泄漏
local function _StackText(count)
    count = _SanitizeCount(count)
    return (count == 0 or count == 1) and "" or count
end

-- 全局常量：单元格边框大小(像素)、边框颜色、默认冷却样式
CELL_BORDER_SIZE = 1
CELL_BORDER_COLOR = {0, 0, 0, 1}
CELL_COOLDOWN_STYLE = "VERTICAL"

-------------------------------------------------
-- SetFont / JustifyText — 字体配置与文本对齐
-------------------------------------------------
-- 根据锚点(anchor point)名称推断水平/垂直对齐方式
-- 例如 "TOPLEFT" -> 水平左对齐 + 垂直顶对齐
-- "CENTER" -> 水平居中 + 垂直居中
-- 锚点命名须遵循 WoW 标准：<VERTICAL><HORIZONTAL> 格式
function I.JustifyText(text, point)
    if strfind(point, "LEFT$") then
        text:SetJustifyH("LEFT")
    elseif strfind(point, "RIGHT$") then
        text:SetJustifyH("RIGHT")
    else
        text:SetJustifyH("CENTER")
    end

    if strfind(point, "^TOP") then
        text:SetJustifyV("TOP")
    elseif strfind(point, "^BOTTOM") then
        text:SetJustifyV("BOTTOM")
    else
        text:SetJustifyV("MIDDLE")
    end
end

-- 配置字体字符串的完整样式：字体文件、大小、描边、阴影、锚点位置、颜色
-- @param fs 字体字符串对象(FontString)
-- @param anchorTo 相对锚定目标
-- @param font 字体名称（通过 F.GetFont 解析为路径）
-- @param size 字号
-- @param outline "None" | "Outline" | "Outline+Monochrome"
-- @param shadow 是否启用阴影
-- @param anchor 锚点名称（同时用于定位和对齐推断）
-- @param xOffset, yOffset 锚点偏移
-- @param color {r, g, b} 或 nil（默认白色）
function I.SetFont(fs, anchorTo, font, size, outline, shadow, anchor, xOffset, yOffset, color)
    font = F.GetFont(font)

    local flags
    if outline == "None" then
        flags = ""
    elseif outline == "Outline" then
        flags = "OUTLINE"
    else
        flags = "OUTLINE,MONOCHROME"
    end

    fs:SetFont(font, size, flags)

    if shadow then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
        fs:SetShadowColor(0, 0, 0, 0)
    end

    P.ClearPoints(fs)
    P.Point(fs, anchor, anchorTo, anchor, xOffset, yOffset)
    I.JustifyText(fs, anchor)

    if color then
        fs.r = color[1]
        fs.g = color[2]
        fs.b = color[3]
        fs:SetTextColor(fs.r, fs.g, fs.b)
    else
        fs.r, fs.g, fs.b = 1, 1, 1
    end
end

-------------------------------------------------
-- Shared — 多个指示器类型共用的辅助函数
-- 这些函数通过 frame 上的方法表装配到不同指示器实例
-------------------------------------------------
-- 共用字体设置：font1 配置 stack（堆叠数），font2 配置 duration（持续时间）
local function Shared_SetFont(frame, font1, font2)
    I.SetFont(frame.stack, frame, unpack(font1))
    I.SetFont(frame.duration, frame, unpack(font2))
end

local function Shared_ShowStack(frame, show)
    frame.stack:SetShown(show)
end

local function Shared_ShowDuration(frame, show)
    frame.showDuration = show
    frame.duration:SetShown(show)
end

-------------------------------------------------
-- VerticalCooldown — 垂直填充冷却动画系统
-- 使用 StatusBar 模拟垂直方向填充的冷却效果（而非 WoW 原生 Cooldown 帧的径向扫描）
-- 组件结构：StatusBar + Spark(闪烁线) + Mask(遮罩) + Icon(褪色图标)
-- 与 ClockCooldown（时钟式）互为替代方案，通过 CELL_COOLDOWN_STYLE 切换
-------------------------------------------------
-- 当 frame 尺寸改变时重新计算图标 UV 裁剪坐标，确保图标按比例显示
local function ReCalcTexCoord(self, width, height)
    local texCoord = F.GetTexCoord(width, height)
    self.icon:SetTexCoord(unpack(texCoord))
    if self.cooldown.icon then
        self.cooldown.icon:SetTexCoord(unpack(texCoord))
    end
end

-- 垂直冷却条的 OnUpdate：每 0.1 秒累加一次已用时间，驱动 StatusBar 的 Value 从 0 增长到 duration
-- 注意：与大多数指示器的 OnUpdate 不同，这里累加的是 elapsed 而非直接计算剩余时间
local function VerticalCooldown_OnUpdate(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed >= 0.1 then
        self:SetValue(self:GetValue() + self.elapsed)
        self.elapsed = 0
    end
end

-- for LCG.ButtonGlow_Start
-- 返回 0 以跳过 LibCustomGlow 的 ButtonGlow 冷却逻辑（垂直冷却条自行管理显示）
local function VerticalCooldown_GetCooldownDuration()
    return 0
end

-- 显示垂直冷却动画
-- @param start 光环开始时间(GetTime() 时间戳)
-- @param duration 总持续时间(秒)
-- @param icon 褪色图标纹理
-- @param debuffType debuff 类型字符串（决定 spark 颜色），nil 时为灰色
local function VerticalCooldown_ShowCooldown(self, start, duration, _, icon, debuffType)
    if debuffType then
        self.spark:SetColorTexture(I.GetDebuffTypeColor(debuffType))
    else
        self.spark:SetColorTexture(0.5, 0.5, 0.5)
    end

    if self.icon then
        self.icon:SetTexture(icon)
    end

    self.elapsed = 0.1 -- update immediately
    self:SetMinMaxValues(0, duration)
    self:SetValue(GetTime() - start)
    self:Show()
end

local function Shared_CreateCooldown_Vertical(frame)
    local cooldown = CreateFrame("StatusBar", nil, frame)
    frame.cooldown = cooldown
    cooldown:Hide()

    cooldown.GetCooldownDuration = VerticalCooldown_GetCooldownDuration
    cooldown.ShowCooldown = VerticalCooldown_ShowCooldown
    cooldown:SetScript("OnUpdate", VerticalCooldown_OnUpdate)

    P.Point(cooldown, "TOPLEFT", frame.icon)
    P.Point(cooldown, "BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 0, CELL_BORDER_SIZE)
    cooldown:SetOrientation("VERTICAL")
    cooldown:SetReverseFill(true)
    cooldown:SetStatusBarTexture(Cell.vars.whiteTexture)

    local texture = cooldown:GetStatusBarTexture()
    texture:SetAlpha(0)

    local spark = cooldown:CreateTexture(nil, "BORDER")
    cooldown.spark = spark
    P.Height(spark, 1)
    spark:SetBlendMode("ADD")
    spark:SetPoint("TOPLEFT", texture, "BOTTOMLEFT")
    spark:SetPoint("TOPRIGHT", texture, "BOTTOMRIGHT")

    local mask = cooldown:CreateMaskTexture()
    mask:SetTexture(Cell.vars.whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT")
    mask:SetPoint("BOTTOMRIGHT", texture)

    local icon = cooldown:CreateTexture(nil, "ARTWORK")
    cooldown.icon = icon
    -- icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    icon:SetDesaturated(true)
    icon:SetAllPoints(frame.icon)
    icon:SetVertexColor(0.5, 0.5, 0.5, 1)
    icon:AddMaskTexture(mask)
end

local function Shared_CreateCooldown_Vertical_NoIcon(frame)
    local cooldown = CreateFrame("StatusBar", nil, frame)
    frame.cooldown = cooldown
    cooldown:Hide()

    cooldown.GetCooldownDuration = VerticalCooldown_GetCooldownDuration
    cooldown.ShowCooldown = VerticalCooldown_ShowCooldown
    cooldown:SetScript("OnUpdate", VerticalCooldown_OnUpdate)

    P.Point(cooldown, "TOPLEFT", frame, CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
    P.Point(cooldown, "BOTTOMRIGHT", frame, -CELL_BORDER_SIZE, CELL_BORDER_SIZE + CELL_BORDER_SIZE)
    cooldown:SetOrientation("VERTICAL")
    cooldown:SetReverseFill(true)
    cooldown:SetStatusBarTexture(Cell.vars.whiteTexture)

    local texture = cooldown:GetStatusBarTexture()
    texture:SetVertexColor(0, 0, 0, 0.8)

    local spark = cooldown:CreateTexture(nil, "BORDER")
    cooldown.spark = spark
    P.Height(spark, 1)
    spark:SetBlendMode("ADD")
    spark:SetPoint("TOPLEFT", texture, "BOTTOMLEFT")
    spark:SetPoint("TOPRIGHT", texture, "BOTTOMRIGHT")
end

-------------------------------------------------
-- ClockCooldown — WoW 原生径向扫描冷却动画
-- 使用 Blizzard Cooldown 帧实现时钟式冷却覆盖层
-- 防御性措施：禁用 OmniCC 等第三方冷却文字插件对 cooldown 帧的文字注入
-------------------------------------------------
local function Shared_CreateCooldown_Clock(frame)
    local cooldown = CreateFrame("Cooldown", nil, frame)
    frame.cooldown = cooldown
    cooldown:Hide()

    P.Point(cooldown, "TOPLEFT", frame, CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
    P.Point(cooldown, "BOTTOMRIGHT", frame, -CELL_BORDER_SIZE, CELL_BORDER_SIZE)
    cooldown:SetReverse(true)
    cooldown:SetDrawEdge(false)
    cooldown:SetSwipeTexture(Cell.vars.whiteTexture)
    cooldown:SetSwipeColor(0, 0, 0, 0.77)
    -- cooldown:SetEdgeTexture([[Interface\Cooldown\UI-HUD-ActionBar-SecondaryCooldown]])

    -- cooldown text
    -- 隐藏 Blizzard 原生冷却倒计时数字（由指示器自身的 duration 字体字符串接管）
    cooldown:SetHideCountdownNumbers(true)
    -- disable omnicc
    -- OmniCC 通过 noCooldownCount 标记跳过此帧
    cooldown.noCooldownCount = true
    -- prevent some dirty addons from adding cooldown text
    -- 保存原始 SetCooldown 到 ShowCooldown（供 Grid2 DurationObject 模式使用），
    -- 然后置空 SetCooldown 阻止其他插件向此帧注入冷却文字
    cooldown.ShowCooldown = cooldown.SetCooldown
    cooldown.SetCooldown = nil
end

-------------------------------------------------
-- SetCooldownStyle — 切换冷却显示风格
-- "CLOCK" -> 时钟式（原生 Cooldown 帧）
-- 其他 -> 垂直填充式（StatusBar 模拟），noIcon 决定是否带褪色图标层
-- 切换时会销毁旧冷却帧并重建新风格的冷却帧
-------------------------------------------------
local function Shared_SetCooldownStyle(frame, style, noIcon)
    if frame.style == style then return end

    if frame.cooldown then
        frame.cooldown:SetParent(nil)
        frame.cooldown:Hide()
    end

    frame.style = style

    if style == "CLOCK" then
        Shared_CreateCooldown_Clock(frame)
    else
        if noIcon then
            Shared_CreateCooldown_Vertical_NoIcon(frame)
        else
            Shared_CreateCooldown_Vertical(frame)
        end
    end
end

--------------------------------------------------
-- glow — LibCustomGlow 发光效果系统
-- 支持五种发光类型：None / Normal(按钮式) / Pixel(像素式) / Shine(自动施法式) / Proc(触发式)
-- 通过 StartGlow/StopGlow 分发表实现策略模式，在切换发光类型时自动切换实现
--------------------------------------------------
---@type function
local ButtonGlow_Start = LCG.ButtonGlow_Start
---@type function
local ButtonGlow_Stop = LCG.ButtonGlow_Stop
---@type function
local PixelGlow_Start = LCG.PixelGlow_Start
---@type function
local PixelGlow_Stop = LCG.PixelGlow_Stop
---@type function
local AutoCastGlow_Start = LCG.AutoCastGlow_Start
---@type function
local AutoCastGlow_Stop = LCG.AutoCastGlow_Stop
---@type function
local ProcGlow_Start = LCG.ProcGlow_Start
---@type function
local ProcGlow_Stop = LCG.ProcGlow_Stop

-- 发光启动分发表：根据 glowType 字符串路由到对应的 LCG 启动函数
-- "none" 为空操作，允许在无发光时仍可通过统一接口调用
local StartGlow = {
    ["none"] = function(frame)
    end,
    ["normal"] = function(frame)
        ButtonGlow_Start(frame, frame.glowOptions.color)
    end,
    ["pixel"] = function(frame)
        PixelGlow_Start(frame, frame.glowOptions.color, frame.glowOptions.N, frame.glowOptions.frequency, frame.glowOptions.length, frame.glowOptions.thickness)
    end,
    ["shine"] = function(frame)
        AutoCastGlow_Start(frame, frame.glowOptions.color, frame.glowOptions.N, frame.glowOptions.frequency, frame.glowOptions.scale)
    end,
    ["proc"] = function(frame)
        ProcGlow_Start(frame, frame.glowOptions)
    end,
}

-- 发光停止分发表：与 StartGlow 对称
local StopGlow = {
    ["none"] = function(frame)
    end,
    ["normal"] = ButtonGlow_Stop,
    ["pixel"] = PixelGlow_Stop,
    ["shine"] = AutoCastGlow_Stop,
    ["proc"] = ProcGlow_Stop,
}

-- 配置并启动发光效果
-- glowOptions 结构: {type, ...} 其中 type 为 "Normal"/"Pixel"/"Shine"/"Proc"/"None"
-- 后续参数根据类型不同携带颜色、频率、长度等配置
-- 重要：每次调用先停止所有旧发光效果，再启动新效果，防止叠加
-- Hook OnSizeChanged 确保缩放后发光效果自动重绘
local function Shared_SetupGlow(frame, glowOptions)
    frame.glowType = glowOptions[1]
    frame.glowOptions = {}

    ButtonGlow_Stop(frame)
    PixelGlow_Stop(frame)
    AutoCastGlow_Stop(frame)
    ProcGlow_Stop(frame)

    frame.StartGlow = StartGlow[strlower(frame.glowType)]
    frame.StopGlow = StopGlow[strlower(frame.glowType)]

    if frame.glowType == "Normal" then
        frame.glowOptions.color = glowOptions[2]
    elseif frame.glowType == "Pixel" then
        frame.glowOptions.color = glowOptions[2]
        frame.glowOptions.N = glowOptions[3]
        frame.glowOptions.frequency = glowOptions[4]
        frame.glowOptions.length = glowOptions[5]
        frame.glowOptions.thickness = glowOptions[6]
    elseif frame.glowType == "Shine" then
        frame.glowOptions.color = glowOptions[2]
        frame.glowOptions.N = glowOptions[3]
        frame.glowOptions.frequency = glowOptions[4]
        frame.glowOptions.scale = glowOptions[5]
    elseif frame.glowType == "Proc" then
        frame.glowOptions = {color = glowOptions[2], duration = glowOptions[3], startAnim = false}
    end

    if frame.glowType ~= "None" then
        frame:StartGlow()
        if not frame._sizeChangedHooked then
            frame._sizeChangedHooked = true
            frame:HookScript("OnSizeChanged", function()
                frame:StartGlow()
            end)
        end
    end
end

function I.Glow_SetupForChildren(parent, glowOptions)
    for _, child in ipairs(parent) do
        child:SetupGlow(glowOptions)
    end
end

-------------------------------------------------
-- Icon_OnUpdate — 图标持续时间显示更新逻辑（倒计时模式）
-- 每 0.1 秒节流更新一次：先检查颜色切换阈值，再格式化剩余时间文本
-- 颜色分三档：从 durationColors[3]（紧急）-> [2]（警告）-> [1]（正常）按剩余时间回退
-- 格式化策略：>60秒显示"Xm"，否则根据 iconDurationRoundUp / iconDurationDecimal 决定取整或小数
-- 注意：_remain 通过 GetTime() - _start 实时计算，而非 delta 累加，避免累积误差
-------------------------------------------------
-- 倒计时模式 OnUpdate：显示剩余时间（duration - elapsed）
local function Icon_OnUpdate(frame, elapsed)
    frame._remain = frame._duration - (GetTime() - frame._start)
    if frame._remain < 0 then frame._remain = 0 end

    if frame._remain > frame._threshold then
        frame.duration:SetText("")
        return
    end

    frame._elapsed = frame._elapsed + elapsed
    if frame._elapsed >= 0.1 then
        frame._elapsed = 0
        -- color
        if Cell.vars.iconDurationColors then
            if frame._remain < Cell.vars.iconDurationColors[3][4] then
                frame.duration:SetTextColor(Cell.vars.iconDurationColors[3][1], Cell.vars.iconDurationColors[3][2], Cell.vars.iconDurationColors[3][3])
            elseif frame._remain < (Cell.vars.iconDurationColors[2][4] * frame._duration) then
                frame.duration:SetTextColor(Cell.vars.iconDurationColors[2][1], Cell.vars.iconDurationColors[2][2], Cell.vars.iconDurationColors[2][3])
            else
                frame.duration:SetTextColor(Cell.vars.iconDurationColors[1][1], Cell.vars.iconDurationColors[1][2], Cell.vars.iconDurationColors[1][3])
            end
        else
            frame.duration:SetTextColor(frame.duration.r, frame.duration.g, frame.duration.b)
        end
    end

    -- format
    if frame._remain > 60 then
        frame.duration:SetFormattedText("%dm", frame._remain / 60)
    else
        if Cell.vars.iconDurationRoundUp then
            frame.duration:SetFormattedText("%d", ceil(frame._remain))
        else
            if Cell.vars.iconDurationDecimal and frame._remain < Cell.vars.iconDurationDecimal then
                frame.duration:SetFormattedText("%.1f", frame._remain)
            else
                frame.duration:SetFormattedText("%d", frame._remain)
            end
        end
    end
end

-- 已用时间模式 OnUpdate：显示已过时间（elapsed since start），而非剩余时间
-- 用于需要展示"已持续多久"的场景（如 HoT 的已用时间）
local function Icon_OnUpdate_ElapsedTime(frame, elapsed)
    frame._remain = frame._duration - (GetTime() - frame._start)
    if frame._remain < 0 then frame._remain = 0 end

    if frame._remain > frame._threshold then
        frame.duration:SetText("")
        return
    end

    frame._elapsed = frame._elapsed + elapsed
    if frame._elapsed >= 0.1 then
        frame._elapsed = 0
        -- color
        if Cell.vars.iconDurationColors then
            if frame._remain < Cell.vars.iconDurationColors[3][4] then
                frame.duration:SetTextColor(Cell.vars.iconDurationColors[3][1], Cell.vars.iconDurationColors[3][2], Cell.vars.iconDurationColors[3][3])
            elseif frame._remain < (Cell.vars.iconDurationColors[2][4] * frame._duration) then
                frame.duration:SetTextColor(Cell.vars.iconDurationColors[2][1], Cell.vars.iconDurationColors[2][2], Cell.vars.iconDurationColors[2][3])
            else
                frame.duration:SetTextColor(Cell.vars.iconDurationColors[1][1], Cell.vars.iconDurationColors[1][2], Cell.vars.iconDurationColors[1][3])
            end
        else
            frame.duration:SetTextColor(frame.duration.r, frame.duration.g, frame.duration.b)
        end
    end

    -- format
    frame._elapsedTime = GetTime() - frame._start
    if frame._elapsedTime > frame._duration then frame._elapsedTime = frame._duration end

    if frame._elapsedTime > 60 then
        frame.duration:SetFormattedText("%dm", frame._elapsedTime / 60)
    else
        frame.duration:SetFormattedText("%d", frame._elapsedTime)
    end
end

-------------------------------------------------
-- CreateAura_BorderIcon — 带边框的图标指示器
-- 结构: 背景底板 + 边框纹理 + 冷却动画 + 图标 + 堆叠数/持续时间文字
-- 边框在有 debuffType 时显示对应颜色，有持续时间时切换为冷却动画
-------------------------------------------------
-- BorderIcon 的冷却/状态设置核心函数
-- Midnight 12.0.0+ 关键防护点：
--   当 duration 为 secret value 时，Blizzard API 可能提供 DurationObject 作为替代，
--   此时无法读取具体的数值用于倒计时文本，因此：
--     - 使用 cooldown:SetCooldownFromDurationObject(durationObject) 渲染冷却动画
--     - 隐藏 duration 文本（因为无法读取 secret number 来格式化显示）
--   这是 Grid2 风格的兼容方案，确保 secret value 下指示器仍能正常显示冷却动画
local function BorderIcon_SetCooldown(frame, start, duration, debuffType, texture, count, refreshing, useElapsedTime, durationObject)
    -- Grid2-style DurationObject fallback (Midnight 12.0.0+):
    -- when time values are secret, C_UnitAuras.GetAuraDuration provides
    -- a DurationObject that cooldown:SetCooldownFromDurationObject can render.
    local r, g, b
    if debuffType then
        r, g, b = I.GetDebuffTypeColor(debuffType)
    else
        r, g, b = 0, 0, 0
    end

    -- 分支1: 无持续时间(静态光环，如被动buff) -> 显示纯色边框，隐藏冷却和倒计时
    if duration == 0 and not durationObject then
        frame.border:Show()
        frame.border:SetColorTexture(r, g, b)
        frame.cooldown:Hide()
        frame.duration:Hide()
        frame:SetScript("OnUpdate", nil)
        frame._start = nil
        frame._duration = nil
        frame._remain = nil
        frame._elapsed = nil
        frame._threshold = nil
        frame._elapsedTime = nil
    -- 分支2: 有持续时间(有时限光环) -> 显示冷却动画
    else
        frame.border:Hide()
        frame.cooldown:Show()
        frame.cooldown:SetSwipeColor(r, g, b)
        -- Midnight 防护：有 DurationObject 时使用 SetCooldownFromDurationObject（安全路径）
        -- 无 DurationObject 时使用保存的原始 _SetCooldown（兼容旧版本/普通光环）
        if durationObject then
            -- Grid2 pattern: SetCooldownFromDurationObject for secret auras
            frame.cooldown:SetCooldownFromDurationObject(durationObject)
        else
            frame.cooldown:_SetCooldown(start, duration)
        end

        -- Duration text not available for DurationObject auras (can't read secret numbers),
        -- so hide duration text when using fallback
        if not frame.showDuration or durationObject then
            frame.duration:Hide()
        else
            if frame.showDuration == true then
                frame._threshold = duration
            elseif frame.showDuration >= 1 then
                frame._threshold = frame.showDuration
            else -- < 1
                frame._threshold = frame.showDuration * duration
            end
            frame.duration:Show()
        end

        if frame.showDuration and not durationObject then
            frame._start = start
            frame._duration = duration
            frame._elapsed = 0.1 -- update immediately
            frame:SetScript("OnUpdate", useElapsedTime and Icon_OnUpdate_ElapsedTime or Icon_OnUpdate)
        end
    end

    frame.icon:SetTexture(texture)
    frame.stack:SetText(_StackText(count))
    frame:Show()

    if refreshing then
        frame.ag:Play()
    end
end

local function BorderIcon_SetBorder(frame, thickness)
    P.ClearPoints(frame.iconFrame)
    P.Point(frame.iconFrame, "TOPLEFT", frame, "TOPLEFT", thickness, -thickness)
    P.Point(frame.iconFrame, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -thickness, thickness)
end

-- showDuration 支持三种模式：
--   false/nil -> 不显示倒计时
--   true      -> 从开始就显示
--   数字 >=1  -> 剩余秒数 <= 该值时显示（绝对阈值）
--   数字 <1   -> 剩余时间 <= duration * 该值时显示（比例阈值）
local function BorderIcon_ShowDuration(frame, show)
    frame.showDuration = show
    if show then
        frame.duration:Show()
    else
        frame.duration:Hide()
    end
end

-- 像素完美模式下的重新布局：重定位 frame 自身 + 子控件
local function BorderIcon_UpdatePixelPerfect(frame)
    P.Resize(frame)
    P.Repoint(frame)
    P.Repoint(frame.iconFrame)
    P.Repoint(frame.stack)
    P.Repoint(frame.duration)
end

-- BorderIcon 工厂：创建带边框的图标指示器
-- 组件层级：Frame(背景) -> Border(边框纹理) -> Cooldown(冷却) -> IconFrame -> Icon + Stack + Duration
-- iconFrame 抬高一级 frameLevel 使图标绘制在冷却覆盖层之上
-- 包含一个上下弹跳 AnimationGroup(ag)，用于光环刷新时的视觉反馈
function I.CreateAura_BorderIcon(name, parent, borderSize)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:Hide()
    -- frame:SetSize(11, 11)
    frame:SetBackdrop({bgFile = Cell.vars.whiteTexture})
    frame:SetBackdropColor(0, 0, 0, 0.85)

    local border = frame:CreateTexture(name.."Border", "BORDER")
    frame.border = border
    border:SetAllPoints(frame)
    border:Hide()

    local cooldown = CreateFrame("Cooldown", name.."Cooldown", frame)
    frame.cooldown = cooldown
    cooldown:SetAllPoints(frame)
    cooldown:SetSwipeTexture(Cell.vars.whiteTexture)
    cooldown:SetSwipeColor(1, 1, 1)
    cooldown:SetHideCountdownNumbers(true)
    -- disable omnicc
    cooldown.noCooldownCount = true
    -- prevent some addons from adding cooldown text
    cooldown._SetCooldown = cooldown.SetCooldown
    cooldown.SetCooldown = nil

    local iconFrame = CreateFrame("Frame", name.."IconFrame", frame)
    frame.iconFrame = iconFrame
    P.Point(iconFrame, "TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    P.Point(iconFrame, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
    iconFrame:SetFrameLevel(cooldown:GetFrameLevel()+1)

    local icon = iconFrame:CreateTexture(name.."Icon", "ARTWORK")
    frame.icon = icon
    icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    icon:SetAllPoints(iconFrame)

    frame.stack = iconFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    frame.duration = iconFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")

    local ag = frame:CreateAnimationGroup()
    frame.ag = ag
    local t1 = ag:CreateAnimation("Translation")
    t1:SetOffset(0, 5)
    t1:SetDuration(0.1)
    t1:SetOrder(1)
    t1:SetSmoothing("OUT")
    local t2 = ag:CreateAnimation("Translation")
    t2:SetOffset(0, -5)
    t2:SetDuration(0.1)
    t2:SetOrder(2)
    t2:SetSmoothing("IN")

    frame.SetFont = Shared_SetFont
    frame.SetBorder = BorderIcon_SetBorder
    frame.SetCooldown = BorderIcon_SetCooldown
    frame.ShowDuration = BorderIcon_ShowDuration
    frame.UpdatePixelPerfect = BorderIcon_UpdatePixelPerfect

    return frame
end

-------------------------------------------------
-- CreateAura_BarIcon — 带垂直冷却动画的状态条图标
-- 与 BorderIcon 的区别：冷却使用垂直 StatusBar 模式（可选关闭动画），
-- 背景颜色由 debuffType 决定而非固定
-------------------------------------------------
-- BarIcon 的冷却设置：无冷却时隐藏冷却条和倒计时，有冷却时配置 StatusBar 冷却动画
-- showAnimation 控制是否使用 StatusBar 冷却（开启时 stack/duration 挂载到 cooldown 上）
local function BarIcon_SetCooldown(frame, start, duration, debuffType, texture, count, refreshing)
    if duration == 0 then
        frame.cooldown:Hide()
        frame.duration:Hide()
        frame.stack:SetParent(frame)
        frame:SetScript("OnUpdate", nil)
        frame._start = nil
        frame._duration = nil
        frame._threshold = nil
        frame._remain = nil
        frame._elapsed = nil
    else
        if frame.showAnimation then
            frame.cooldown:ShowCooldown(start, duration, nil, texture, debuffType)
            frame.duration:SetParent(frame.cooldown)
            frame.stack:SetParent(frame.cooldown)
        else
            frame.cooldown:Hide()
            frame.duration:SetParent(frame)
            frame.stack:SetParent(frame)
        end

        if not frame.showDuration then
            frame.duration:Hide()
        else
            if frame.showDuration == true then
                frame._threshold = duration
            elseif frame.showDuration >= 1 then
                frame._threshold = frame.showDuration
            else -- < 1
                frame._threshold = frame.showDuration * duration
            end
            frame.duration:Show()
        end

        if frame.showDuration then
            frame._start = start
            frame._duration = duration
            frame._elapsed = 0.1 -- update immediately
            frame:SetScript("OnUpdate", Icon_OnUpdate)
        end
    end

    if debuffType then
        frame:SetBackdropColor(I.GetDebuffTypeColor(debuffType))
    else
        frame:SetBackdropColor(0, 0, 0)
    end

    frame.icon:SetTexture(texture)
    frame.stack:SetText(_StackText(count))
    frame:Show()

    if refreshing then
        frame.ag:Play()
    end
end

local function BarIcon_ShowAnimation(frame, show)
    frame.showAnimation = show
    if show then
        frame.cooldown:Show()
    else
        frame.cooldown:Hide()
    end
end

local function BarIcon_UpdatePixelPerfect(frame)
    P.Resize(frame)
    P.Repoint(frame)
    P.Repoint(frame.icon)
    P.Repoint(frame.stack)
    P.Repoint(frame.duration)
    P.Repoint(frame.cooldown)
    if frame.cooldown.spark then
        P.Resize(frame.cooldown.spark)
    end
end

-- BarIcon 工厂：创建带垂直冷却条动画的图标指示器
-- 默认冷却风格由 CELL_COOLDOWN_STYLE 全局常量决定（当前为 "VERTICAL"）
-- 通过 OnSizeChanged 自动重算图标 UV 裁剪坐标
-- 与 BorderIcon 共享 animation group 的弹跳动画逻辑
function I.CreateAura_BarIcon(name, parent)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:Hide()
    -- frame:SetSize(11, 11)
    frame:SetBackdrop({bgFile = Cell.vars.whiteTexture})
    frame:SetBackdropColor(0, 0, 0, 1)

    local icon = frame:CreateTexture(name and name.."Icon", "ARTWORK")
    frame.icon = icon
    -- icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    P.Point(icon, "TOPLEFT", frame, "TOPLEFT", CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
    P.Point(icon, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -CELL_BORDER_SIZE, CELL_BORDER_SIZE)
    -- icon:SetDrawLayer("ARTWORK", 1)

    frame.stack = frame:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    frame.duration = frame:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")

    local ag = frame:CreateAnimationGroup()
    frame.ag = ag
    local t1 = ag:CreateAnimation("Translation")
    t1:SetOffset(0, 5)
    t1:SetDuration(0.1)
    t1:SetOrder(1)
    t1:SetSmoothing("OUT")
    local t2 = ag:CreateAnimation("Translation")
    t2:SetOffset(0, -5)
    t2:SetDuration(0.1)
    t2:SetOrder(2)
    t2:SetSmoothing("IN")

    frame.SetFont = Shared_SetFont
    frame.SetCooldown = BarIcon_SetCooldown
    frame.ShowDuration = Shared_ShowDuration
    frame.ShowStack = Shared_ShowStack
    frame.ShowAnimation = BarIcon_ShowAnimation
    frame.SetupGlow = Shared_SetupGlow
    frame.UpdatePixelPerfect = BarIcon_UpdatePixelPerfect

    Shared_SetCooldownStyle(frame, CELL_COOLDOWN_STYLE)

    frame:SetScript("OnSizeChanged", ReCalcTexCoord)

    -- frame:SetScript("OnEnter", function()
        -- local f = frame
        -- repeat
        --     f = f:GetParent()
        -- until f:IsObjectType("button")
        -- f:GetScript("OnEnter")(f)
    -- end)

    return frame
end

-------------------------------------------------
-- CreateAura_Icons — 多图标容器（自动网格布局）
-- 核心设计：icons 本身是一个 Frame，包含 maxNum 个子 BarIcon
-- 布局引擎通过 orientation + numPerLine + spacing 自动计算每个子图标的位置
-- 容器尺寸随可见子图标的数量和行数动态调整
-------------------------------------------------
-- 更新容器尺寸：根据可见光环数量计算所需行数，并通过 P.SetGridSize 调整网格
-- @param numAuras nil 时自动统计可见子图标数；传入数字时用于预览/外部强制设置
local function Icons_UpdateSize(icons, numAuras)
    if not (icons.width and icons.orientation) then return end -- not init

    if numAuras then -- call from I.CheckCustomIndicators or preview
        for i = numAuras + 1, icons.maxNum do
            icons[i]:Hide()
        end
    else
        numAuras = 0
        for i = 1, icons.maxNum do
            if icons[i]:IsShown() then
                numAuras = i
            else
                break
            end
        end
    end

    -- set size
    local lines = ceil(numAuras / icons.numPerLine)
    numAuras = min(numAuras, icons.numPerLine)

    if icons.isHorizontal then
        P.SetGridSize(icons, icons.width, icons.height, icons.spacingX, icons.spacingY, numAuras, lines)
    else
        P.SetGridSize(icons, icons.width, icons.height, icons.spacingX, icons.spacingY, lines, numAuras)
    end
end

local function Icons_SetNumPerLine(icons, numPerLine)
    icons.numPerLine = min(numPerLine, icons.maxNum)


    if icons.orientation then
        icons:SetOrientation(icons.orientation)
    -- else
    --     icons:UpdateSize()
    end
end

-- 设置排列方向：支持 "left-to-right" / "right-to-left" / "top-to-bottom" / "bottom-to-top"
-- 根据锚点位置（BOTTOM/TOP/RIGHT/LEFT）自动选择换行方向和偏移量
-- 布局算法：
--   第1个图标放在 point1 锚点
--   每行内相邻图标间距 spacingX/spacingY
--   每行第1个图标相对于上一行首个图标偏移 newLineX/newLineY
-- 换行判断：i % numPerLine == 1 表示新行开始
local function Icons_SetOrientation(icons, orientation)
    icons.orientation = orientation

    local anchor = icons:GetPoint()
    assert(anchor, "[indicator] SetPoint must be called before SetOrientation")

    icons.isHorizontal = not strfind(orientation, "top")

    local point1, point2, x, y
    local newLinePoint2, newLineX, newLineY

    if orientation == "left-to-right" then
        if strfind(anchor, "^BOTTOM") then
            point1 = "BOTTOMLEFT"
            point2 = "BOTTOMRIGHT"
            newLinePoint2 = "TOPLEFT"
            y = 0
            newLineY = icons.spacingY
        else
            point1 = "TOPLEFT"
            point2 = "TOPRIGHT"
            newLinePoint2 = "BOTTOMLEFT"
            y = 0
            newLineY = -icons.spacingY
        end
        x = icons.spacingX
        newLineX = 0

    elseif orientation == "right-to-left" then
        if strfind(anchor, "^BOTTOM") then
            point1 = "BOTTOMRIGHT"
            point2 = "BOTTOMLEFT"
            newLinePoint2 = "TOPRIGHT"
            y = 0
            newLineY = icons.spacingY
        else
            point1 = "TOPRIGHT"
            point2 = "TOPLEFT"
            newLinePoint2 = "BOTTOMRIGHT"
            y = 0
            newLineY = -icons.spacingY
        end
        x = -icons.spacingX
        newLineX = 0

    elseif orientation == "top-to-bottom" then
        if strfind(anchor, "RIGHT$") then
            point1 = "TOPRIGHT"
            point2 = "BOTTOMRIGHT"
            newLinePoint2 = "TOPLEFT"
            x = 0
            newLineX = -icons.spacingX
        else
            point1 = "TOPLEFT"
            point2 = "BOTTOMLEFT"
            newLinePoint2 = "TOPRIGHT"
            x = 0
            newLineX = icons.spacingX
        end
        y = -icons.spacingY
        newLineY = 0

    elseif orientation == "bottom-to-top" then
        if strfind(anchor, "RIGHT$") then
            point1 = "BOTTOMRIGHT"
            point2 = "TOPRIGHT"
            newLinePoint2 = "BOTTOMLEFT"
            x = 0
            newLineX = -icons.spacingX
        else
            point1 = "BOTTOMLEFT"
            point2 = "TOPLEFT"
            newLinePoint2 = "BOTTOMRIGHT"
            x = 0
            newLineX = icons.spacingX
        end
        y = icons.spacingY
        newLineY = 0
    end

    for i = 1, icons.maxNum do
        P.ClearPoints(icons[i])
        if i == 1 then
            P.Point(icons[i], point1)
        elseif i % icons.numPerLine == 1 then
            P.Point(icons[i], point1, icons[i-icons.numPerLine], newLinePoint2, newLineX, newLineY)
        else
            P.Point(icons[i], point1, icons[i-1], point2, x, y)
        end
    end

    icons:UpdateSize()
end

local function Icons_SetSize(icons, width, height)
    icons.width = width
    icons.height = height

    for i = 1, icons.maxNum do
        icons[i]:SetSize(width, height)
        --! width & height P.Scaled
        icons[i].width = nil
        icons[i].height = nil
    end

    icons:UpdateSize()
end

-- 设置图标间距：spacing[1]=水平间距, spacing[2]=垂直间距，设置后自动重新布局
local function Icons_SetSpacing(icons, spacing)
    icons.spacingX = spacing[1]
    icons.spacingY = spacing[2]

    if icons.orientation then
        icons:SetOrientation(icons.orientation)
    end
end

local function Icons_Hide(icons, hideAll)
    icons:_Hide()
    if hideAll then
        for i = 1, icons.maxNum do
            icons[i]:Hide()
        end
    end
end

local function Icons_SetFont(icons, ...)
    for i = 1, icons.maxNum do
        icons[i]:SetFont(...)
    end
end

local function Icons_ShowDuration(icons, show)
    for i = 1, icons.maxNum do
        icons[i]:ShowDuration(show)
    end
end

local function Icons_ShowStack(icons, show)
    for i = 1, icons.maxNum do
        icons[i]:ShowStack(show)
    end
end

local function Icons_ShowAnimation(icons, show)
    for i = 1, icons.maxNum do
        icons[i]:ShowAnimation(show)
    end
end

local function Icons_UpdatePixelPerfect(icons)
    P.Repoint(icons)
    P.Resize(icons)
    for i = 1, icons.maxNum do
        icons[i]:UpdatePixelPerfect()
    end
end

-- Icons 工厂：创建多图标容器
-- 保存原始 SetSize/Hide 方法为 _SetSize/_Hide，然后替换为自定义布局感知版本
-- 每个子图标通过 I.CreateAura_BarIcon 创建，存储在 icons[1..num] 中
-- 通过 SetupGlow = I.Glow_SetupForChildren 实现遍历所有子图标应用发光效果
function I.CreateAura_Icons(name, parent, num)
    local icons = CreateFrame("Frame", name, parent)
    icons:Hide()

    icons.indicatorType = "icons"
    icons.maxNum = num
    icons.numPerLine = num
    icons.spacingX = 0
    icons.spacingY = 0

    icons._SetSize = icons.SetSize
    icons.SetSize = Icons_SetSize
    icons._Hide = icons.Hide
    icons.Hide = Icons_Hide
    icons.SetFont = Icons_SetFont
    icons.UpdateSize = Icons_UpdateSize
    icons.SetOrientation = Icons_SetOrientation
    icons.SetSpacing = Icons_SetSpacing
    icons.SetNumPerLine = Icons_SetNumPerLine
    icons.ShowDuration = Icons_ShowDuration
    icons.ShowStack = Icons_ShowStack
    icons.ShowAnimation = Icons_ShowAnimation
    icons.SetupGlow = I.Glow_SetupForChildren
    icons.UpdatePixelPerfect = Icons_UpdatePixelPerfect

    for i = 1, num do
        local name = name and name.."Icon"..i
        local frame = I.CreateAura_BarIcon(name, icons)
        icons[i] = frame
    end

    return icons
end

-------------------------------------------------
-- CreateAura_Text — 纯文本指示器
-- 支持显示堆叠数（普通数字或带圈数字 ①②③...㊿）和/或持续时间
-- 颜色随时间分三档变化（动态颜色模式），由 colors 表驱动
-- 当 durationTbl[1] 为 true 时显示倒计时，否则只显示堆叠数+动态颜色
-------------------------------------------------
local function Text_SetFont(frame, font, size, outline, shadow)
    font = F.GetFont(font)

    local flags
    if outline == "None" then
        flags = ""
    elseif outline == "Outline" then
        flags = "OUTLINE"
    else
        flags = "OUTLINE,MONOCHROME"
    end

    frame.text:SetFont(font, size, flags)

    if shadow then
        frame.text:SetShadowOffset(1, -1)
        frame.text:SetShadowColor(0, 0, 0, 1)
    else
        frame.text:SetShadowOffset(0, 0)
        frame.text:SetShadowColor(0, 0, 0, 0)
    end

    frame:SetSize(size, size)
end

local function Text_SetPoint(frame, point, relativeTo, relativePoint, x, y)
    frame.text:ClearAllPoints()
    frame.text:SetPoint(point)
    frame:_SetPoint(point, relativeTo, relativePoint, x, y)
    I.JustifyText(frame.text, point)
end

-- 设置持续时间显示配置
-- durationTbl = {showDuration, roundUp, decimalThreshold}
--   [1]: true/false 是否显示倒计时
--   [2]: true=向上取整, false=根据阈值显示小数
--   [3]: 低于此秒数时显示一位小数
local function Text_SetDuration(frame, durationTbl)
    frame.durationTbl = durationTbl
end

-- 设置堆叠数显示配置: stack[1]=是否显示, stack[2]=是否使用带圈数字
local function Text_SetStack(frame, stack)
    frame.showStack = stack[1]
    frame.circledStackNums = stack[2]
end

-- 设置颜色表
-- colors 结构: {[1]={r,g,b,a}, [2]={enabled, ratio, {r,g,b,a}}, [3]={enabled, threshold, {r,g,b,a}}}
--   [1] 正常状态颜色
--   [2] 阶段2颜色: enabled 开关, ratio 占 duration 的比例阈值, 颜色
--   [3] 阶段3颜色: enabled 开关, threshold 绝对秒数阈值, 颜色
local function Text_SetColors(frame, colors)
    frame.state = nil
    frame.colors = colors
end

-- 根据剩余时间更新文本颜色（三档优先级从高到低）
-- [3] 紧急色: colors[3][1] 启用且 _remain <= colors[3][2] 绝对阈值
-- [2] 警告色: colors[2][1] 启用且 _remain <= _duration * colors[2][2] 比例阈值
-- [1] 正常色: 其他情况（默认）
-- 通过 frame.state 缓存当前状态避免重复调用 SetTextColor
local function Text_OnUpdateColor(frame)
    if frame.colors[3][1] and frame._remain <= frame.colors[3][2] then
        if frame.state ~= 3 then
            frame.state = 3
            frame.text:SetTextColor(frame.colors[3][3][1], frame.colors[3][3][2], frame.colors[3][3][3], frame.colors[3][3][4])
        end
    elseif frame.colors[2][1] and frame._remain <= frame._duration * frame.colors[2][2] then
        if frame.state ~= 2 then
            frame.state = 2
            frame.text:SetTextColor(frame.colors[2][3][1], frame.colors[2][3][2], frame.colors[2][3][3], frame.colors[2][3][4])
        end
    elseif frame.state ~= 1 then
        frame.state = 1
        frame.text:SetTextColor(frame.colors[1][1], frame.colors[1][2], frame.colors[1][3], frame.colors[1][4])
    end
end

-- 带倒计时文本的 OnUpdate：颜色更新 + 时间格式化（_count.. 前缀拼接堆叠数）
-- 格式化逻辑与 Icon_OnUpdate 一致，但在文本前拼接 _count（堆叠数 + 空格）
local function Text_OnUpdateDuration(frame, elapsed)
    frame._remain = frame._duration - (GetTime() - frame._start)
    if frame._remain < 0 then frame._remain = 0 end

    frame._elapsed = frame._elapsed + elapsed
    if frame._elapsed >= 0.1 then
        frame._elapsed = 0
        -- color
        Text_OnUpdateColor(frame)
    end

    -- format
    if frame._remain > 60 then
        frame.text:SetFormattedText(frame._count.."%dm", frame._remain/60)
    else
        if frame.durationTbl[2] then
            frame.text:SetFormattedText(frame._count.."%d", ceil(frame._remain))
        else
            if frame._remain < frame.durationTbl[3] then
                frame.text:SetFormattedText(frame._count.."%.1f", frame._remain)
            else
                frame.text:SetFormattedText(frame._count.."%d", frame._remain)
            end
        end
    end
end

-- 纯堆叠数+动态颜色模式的 OnUpdate：只更新颜色，不更新文本内容（文本在 SetCooldown 时已设定）
-- 适用于不显示倒计时、仅根据剩余时间变色的场景
local function Text_OnUpdate(frame, elapsed)
    frame._elapsed = frame._elapsed + elapsed
    if frame._elapsed >= 0.1 then
        frame._elapsed = 0

        frame._remain = frame._duration - (GetTime() - frame._start)
        -- update color
        Text_OnUpdateColor(frame)
    end
end

-- 带圈数字字符表：索引1-50 对应 ①-㊿，用于 circledStackNums 模式
local circled = {"①","②","③","④","⑤","⑥","⑦","⑧","⑨","⑩","⑪","⑫","⑬","⑭","⑮","⑯","⑰","⑱","⑲","⑳","㉑","㉒","㉓","㉔","㉕","㉖","㉗","㉘","㉙","㉚","㉛","㉜","㉝","㉞","㉟","㊱","㊲","㊳","㊴","㊵","㊶","㊷","㊸","㊹","㊺","㊻","㊼","㊽","㊾","㊿"}
-- Text 指示器的冷却设置：根据是否显示倒计时选择不同的 OnUpdate 处理
-- Midnight 防护：所有 count 通过 _SanitizeCount 清洗后再使用
local function Text_SetCooldown(frame, start, duration, debuffType, texture, count)
    if duration == 0 then
        -- always show stack
        count = _SanitizeCount(count)
        count = count == 0 and 1 or count
        count = frame.circledStackNums and circled[count] or count
        frame.text:SetText(count)
        frame.text:SetTextColor(frame.colors[1][1], frame.colors[1][2], frame.colors[1][3], frame.colors[1][4])
        frame:SetScript("OnUpdate", nil)
        frame._count = nil
        frame._start = nil
        frame._duration = nil
        frame._remain = nil
        frame._elapsed = nil
    else
        frame._start = start
        frame._duration = duration

        if frame.durationTbl[1] then
            count = _SanitizeCount(count)
            if frame.showStack and count ~= 0 then
                if frame.circledStackNums then
                    frame._count = circled[count].." "
                else
                    frame._count = count.." "
                end
            else
                frame._count = ""
            end

            frame._elapsed = 0.1 -- update immediately
            frame:SetScript("OnUpdate", Text_OnUpdateDuration)
        else
            -- always show stack
            count = _SanitizeCount(count)
            count = count == 0 and 1 or count
            if frame.circledStackNums then
                frame.text:SetText(circled[count])
            else
                frame.text:SetText(count)
            end

            frame._elapsed = 0.1 -- update immediately
            frame:SetScript("OnUpdate", Text_OnUpdate)
        end
    end

    frame:Show()
end

-- Text 工厂：创建纯文本指示器
-- 保存原始 SetPoint 为 _SetPoint，替换为同时设置 frame 和 text 锚点的包装版本
-- text 字体字符串默认定位在 frame 的 CENTER (1, 0) 偏移
function I.CreateAura_Text(name, parent)
    local frame = CreateFrame("Frame", name, parent)
    frame:Hide()
    frame.indicatorType = "text"

    local text = frame:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    frame.text = text
    text:SetPoint("CENTER", 1, 0)

    frame.SetFont = Text_SetFont
    frame._SetPoint = frame.SetPoint
    frame.SetPoint = Text_SetPoint
    frame.SetCooldown = Text_SetCooldown
    frame.SetDuration = Text_SetDuration
    frame.SetStack = Text_SetStack
    frame.SetColors = Text_SetColors

    return frame
end

-------------------------------------------------
-- CreateAura_Rect — 矩形色块指示器
-- 一个带边框的矩形 Frame，内部填充纯色纹理(tex)，颜色随时间三档变化
-- 与 Bar 不同，Rect 不使用 StatusBar 而是一个普通的带纹理 Frame
-- colors 结构: {[1]正常色, [2]{enabled,ratio,color}, [3]{enabled,threshold,color}, [4]边框色}
-------------------------------------------------
local function Rect_SetFont(frame, font1, font2)
    I.SetFont(frame.stack, frame, unpack(font1))
    I.SetFont(frame.duration, frame, unpack(font2))
end

local function Rect_OnUpdateColor(frame)
    if frame.colors[3][1] and frame._remain <= frame.colors[3][2] then
        if frame.state ~= 3 then
            frame.state = 3
            frame.tex:SetColorTexture(frame.colors[3][3][1], frame.colors[3][3][2], frame.colors[3][3][3], frame.colors[3][3][4])
        end
    elseif frame.colors[2][1] and frame._remain <= frame._duration * frame.colors[2][2] then
        if frame.state ~= 2 then
            frame.state = 2
            frame.tex:SetColorTexture(frame.colors[2][3][1], frame.colors[2][3][2], frame.colors[2][3][3], frame.colors[2][3][4])
        end
    elseif frame.state ~= 1 then
        frame.state = 1
        frame.tex:SetColorTexture(frame.colors[1][1], frame.colors[1][2], frame.colors[1][3], frame.colors[1][4])
    end
end

local function Rect_OnUpdate(frame, elapsed)
    frame._remain = frame._duration - (GetTime() - frame._start)
    if frame._remain < 0 then frame._remain = 0 end

    frame._elapsed = frame._elapsed + elapsed
    if frame._elapsed >= 0.1 then
        frame._elapsed = 0
        -- update color
        Rect_OnUpdateColor(frame)
    end

    if frame._remain > frame._threshold then
        frame.duration:SetText("")
        return
    end

    -- format
    if frame._remain > 60 then
        frame.duration:SetFormattedText("%dm", frame._remain / 60)
    else
        if Cell.vars.iconDurationRoundUp then
            frame.duration:SetFormattedText("%d", ceil(frame._remain))
        else
            if Cell.vars.iconDurationDecimal and frame._remain < Cell.vars.iconDurationDecimal then
                frame.duration:SetFormattedText("%.1f", frame._remain)
            else
                frame.duration:SetFormattedText("%d", frame._remain)
            end
        end
    end
end

local function Rect_SetCooldown(frame, start, duration, debuffType, texture, count)
    if duration == 0 then
        frame.tex:SetColorTexture(unpack(frame.colors[1]))
        frame:SetScript("OnUpdate", nil)
        frame.duration:Hide()
        frame._start = nil
        frame._duration = nil
        frame._remain = nil
        frame._elapsed = nil
        frame._threshold = nil
    else
        if not frame.showDuration then
            frame._threshold = -1
            frame.duration:Hide()
        else
            if frame.showDuration == true then
                frame._threshold = duration
            elseif frame.showDuration >= 1 then
                frame._threshold = frame.showDuration
            else -- < 1
                frame._threshold = frame.showDuration * duration
            end
            frame.duration:Show()
        end

        frame._start = start
        frame._duration = duration
        frame._elapsed = 0.1 -- update immediately
        frame:SetScript("OnUpdate", Rect_OnUpdate)
    end

    frame.stack:SetText(_StackText(count))
    frame:Show()
end

local function Rect_SetColors(frame, colors)
    frame.state = nil
    frame.colors = colors
    frame:SetBackdropBorderColor(colors[4][1], colors[4][2], colors[4][3], colors[4][4])
end

local function Rect_UpdatePixelPerfect(frame)
    P.Resize(frame)
    P.Reborder(frame)
    P.Repoint(frame)
end

-- Rect 工厂：创建矩形色块指示器
-- tex 纹理层级为 BORDER（绘制在背景之上），drawLayer 为 -7 使其在所有指示器下层
-- 使用 Backdrop 边框而非独立的 border 纹理
function I.CreateAura_Rect(name, parent)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:Hide()
    frame.indicatorType = "rect"
    frame:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(CELL_BORDER_SIZE)})
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    local tex = frame:CreateTexture(nil, "BORDER", nil, -7)
    frame.tex = tex
    tex:SetAllPoints()

    frame.stack = frame:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    frame.duration = frame:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")

    frame.SetFont = Rect_SetFont
    frame.SetCooldown = Rect_SetCooldown
    frame.SetColors = Rect_SetColors
    frame.ShowStack = Shared_ShowStack
    frame.ShowDuration = Shared_ShowDuration
    frame.SetupGlow = Shared_SetupGlow
    frame.UpdatePixelPerfect = Rect_UpdatePixelPerfect

    return frame
end

-------------------------------------------------
-- CreateAura_Bar — 单个进度条指示器
-- StatusBar 控件，颜色随时间三档变化，支持 maxValue 上限配置
-- colors 结构: {[1]正常色, [2]{enabled,ratio,color}, [3]{enabled,threshold,color}, [4]边框色, [5]背景色}
-- maxValue 配置: {enabled, value, allowSmaller}
--   allowSmaller=true 时，如果光环持续时间 < maxValue，则按实际 duration 设上限
-------------------------------------------------
local function Bar_SetFont(bar, font1, font2)
    I.SetFont(bar.stack, bar, unpack(font1))
    I.SetFont(bar.duration, bar, unpack(font2))
end

local function Bar_OnUpdate(bar, elapsed)
    bar._remain = bar._duration - (GetTime() - bar._start)
    if bar._remain < 0 then bar._remain = 0 end
    bar:SetValue(bar._remain)

    bar._elapsed = bar._elapsed + elapsed
    if bar._elapsed >= 0.1 then
        bar._elapsed = 0
        -- update color
        if bar.colors[3][1] and bar._remain <= bar.colors[3][2] then
            if bar.state ~= 3 then
                bar.state = 3
                bar:SetStatusBarColor(bar.colors[3][3][1], bar.colors[3][3][2], bar.colors[3][3][3], bar.colors[3][3][4])
            end
        elseif bar.colors[2][1] and bar._remain <= bar._duration * bar.colors[2][2] then
            if bar.state ~= 2 then
                bar.state = 2
                bar:SetStatusBarColor(bar.colors[2][3][1], bar.colors[2][3][2], bar.colors[2][3][3], bar.colors[2][3][4])
            end
        elseif bar.state ~= 1 then
            bar.state = 1
            bar:SetStatusBarColor(bar.colors[1][1], bar.colors[1][2], bar.colors[1][3], bar.colors[1][4])
        end
    end

    if bar._remain > bar._threshold then
        bar.duration:SetText("")
        return
    end

    -- format
    if bar._remain > 60 then
        bar.duration:SetFormattedText("%dm", bar._remain / 60)
    else
        if Cell.vars.iconDurationRoundUp then
            bar.duration:SetFormattedText("%d", ceil(bar._remain))
        else
            if Cell.vars.iconDurationDecimal and bar._remain < Cell.vars.iconDurationDecimal then
                bar.duration:SetFormattedText("%.1f", bar._remain)
            else
                bar.duration:SetFormattedText("%d", bar._remain)
            end
        end
    end
end

local function Bar_SetCooldown(bar, start, duration, debuffType, texture, count)
    if duration == 0 then
        bar:SetScript("OnUpdate", nil)
        bar.duration:Hide()
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar._start = nil
        bar._duration = nil
        bar._threshold = nil
        bar._remain = nil
        bar._elapsed = nil
    else
        if not bar.showDuration then
            bar._threshold = -1
            bar.duration:Hide()
        else
            if bar.showDuration == true then
                bar._threshold = duration
            elseif bar.showDuration >= 1 then
                bar._threshold = bar.showDuration
            else -- < 1
                bar._threshold = bar.showDuration * duration
            end
            bar.duration:Show()
        end

        if bar.maxValue then
            bar:SetMinMaxValues(0, bar.allowSmaller and min(bar.maxValue, duration) or bar.maxValue)
        else
            bar:SetMinMaxValues(0, duration)
        end
        bar._start = start
        bar._duration = duration
        bar._elapsed = 0.1 -- update immediately
        bar:SetScript("OnUpdate", Bar_OnUpdate)
    end

    bar.stack:SetText(_StackText(count))
    bar:Show()
end

local function Bar_SetMaxValue(bar, maxValue)
    if maxValue[1]then
        bar.maxValue = maxValue[2]
        bar.allowSmaller = maxValue[3]
    else
        bar.maxValue = nil
        bar.allowSmaller = nil
    end
end

local function Bar_SetColors(bar, colors)
    bar:SetBackdropBorderColor(colors[4][1], colors[4][2], colors[4][3], colors[4][4])
    bar:SetBackdropColor(colors[5][1], colors[5][2], colors[5][3], colors[5][4])
    bar.state = nil
    bar.colors = colors
end

-- Bar 工厂：通过 Cell.CreateStatusBar 创建带背景/边框的 StatusBar
-- 参数: 18=宽度, 4=高度, 100=最大缩放值
function I.CreateAura_Bar(name, parent)
    local bar = Cell.CreateStatusBar(name, parent, 18, 4, 100)
    bar:Hide()
    bar.indicatorType = "bar"

    bar.stack = bar:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    bar.duration = bar:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")

    bar.SetFont = Bar_SetFont
    bar.SetCooldown = Bar_SetCooldown
    bar.ShowStack = Shared_ShowStack
    bar.ShowDuration = Shared_ShowDuration
    bar.SetMaxValue = Bar_SetMaxValue
    bar.SetupGlow = Shared_SetupGlow
    bar.SetColors = Bar_SetColors

    return bar
end

-------------------------------------------------
-- CreateAura_Bars — 多个进度条容器（复用 Icons 的布局引擎）
-- 与 CreateAura_Icons 共享 SetSize/Hide/SetFont/UpdateSize/SetOrientation 等布局方法
-- 区别：每个子元素是 Bar 而非 BarIcon，且 Bars_SetCooldown 额外接收 color 参数用于染色
-------------------------------------------------
-- Bars 容器的子 Bar OnUpdate：仅更新 StatusBar 值和持续时间文本（不做颜色切换）
-- 颜色切换由外部 Bars_SetCooldown 一次性设定
local function Bars_OnUpdate(bar, elapsed)
    bar._remain = bar._duration - (GetTime() - bar._start)
    if bar._remain < 0 then bar._remain = 0 end
    bar:SetValue(bar._remain)

    if bar._remain > bar._threshold then
        bar.duration:SetText("")
        return
    end

    -- format
    if bar._remain > 60 then
        bar.duration:SetFormattedText("%dm", bar._remain / 60)
    else
        if Cell.vars.iconDurationRoundUp then
            bar.duration:SetFormattedText("%d", ceil(bar._remain))
        else
            if Cell.vars.iconDurationDecimal and bar._remain < Cell.vars.iconDurationDecimal then
                bar.duration:SetFormattedText("%.1f", bar._remain)
            else
                bar.duration:SetFormattedText("%d", bar._remain)
            end
        end
    end
end

local function Bars_SetCooldown(bar, start, duration, debuffType, texture, count, refreshing, color)
    if duration == 0 then
        bar:SetScript("OnUpdate", nil)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar.duration:Hide()
        bar._start = nil
        bar._duration = nil
        bar._remain = nil
        bar._threshold = nil
    else
        if not bar.showDuration then
            bar._threshold = -1
            bar.duration:Hide()
        else
            if bar.showDuration == true then
                bar._threshold = duration
            elseif bar.showDuration >= 1 then
                bar._threshold = bar.showDuration
            else -- < 1
                bar._threshold = bar.showDuration * duration
            end
            bar.duration:Show()
        end

        if bar.maxValue then
            bar:SetMinMaxValues(0, bar.allowSmaller and min(bar.maxValue, duration) or bar.maxValue)
        else
            bar:SetMinMaxValues(0, duration)
        end
        bar._start = start
        bar._duration = duration
        bar:SetScript("OnUpdate", Bars_OnUpdate)
    end

    bar:SetStatusBarColor(color[1], color[2], color[3], color[4])
    bar:SetBackdropColor(color[1] * 0.2, color[2] * 0.2, color[3] * 0.2, color[4])
    bar.stack:SetText(_StackText(count))
    bar:Show()
end

local function Bars_SetMaxValue(bars, maxValue)
    for _, bar in ipairs(bars) do
        bar:SetMaxValue(maxValue)
    end
end

-- Bars 工厂：创建多个进度条容器（复用 Icons 的布局引擎）
-- 每个子元素通过 I.CreateAura_Bar 创建，然后替换其 SetCooldown 为 Bars_SetCooldown
-- 子 Bar 的边框色统一设为黑色，背景色由 Bars_SetCooldown 中的 color 参数派生（主色的 20% 亮度）
function I.CreateAura_Bars(name, parent, num)
    local bars = CreateFrame("Frame", name, parent)
    bars:Hide()

    bars.indicatorType = "bars"
    bars.maxNum = num
    bars.numPerLine = num

    bars._SetSize = bars.SetSize
    bars.SetSize = Icons_SetSize
    bars._Hide = bars.Hide
    bars.Hide = Icons_Hide
    bars.SetFont = Icons_SetFont
    bars.UpdateSize = Icons_UpdateSize
    bars.SetOrientation = Icons_SetOrientation
    bars.SetSpacing = Icons_SetSpacing
    bars.SetNumPerLine = Icons_SetNumPerLine
    bars.ShowDuration = Icons_ShowDuration
    bars.ShowStack = Icons_ShowStack
    bars.SetMaxValue = Bars_SetMaxValue
    bars.SetupGlow = I.Glow_SetupForChildren
    bars.UpdatePixelPerfect = Icons_UpdatePixelPerfect

    for i = 1, num do
        local name = name and name.."Icons"..i
        local frame = I.CreateAura_Bar(name, bars)
        bars[i] = frame
        frame.parent = bars
        frame.SetCooldown = Bars_SetCooldown
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    return bars
end

-------------------------------------------------
-- CreateAura_Color — 颜色覆盖层指示器
-- 支持六种颜色模式：
--   "solid"             纯色填充
--   "gradient-vertical"  垂直渐变
--   "gradient-horizontal" 水平渐变
--   "debuff-type"        debuff类型色（需配合 debuffType 参数动态获取）
--   "change-over-time"   随时间变色（三档颜色随时间变化）
--   "class-color"        职业色（从 parent.states.class 获取）
-- 锚点支持：healthbar-current / healthbar-loss / healthbar-entire / unitbutton
-- 帧层级偏移：baseFrameLevel + 5，防止与其他指示器重叠
-------------------------------------------------
-- change-over-time 模式的 OnUpdate：根据剩余时间切换三档颜色
-- [6][2] 紧急色, [5][2] 警告色, [4] 正常色
local function Color_OnUpdate(color, elapsed)
    color._elapsed = color._elapsed + elapsed
    if color._elapsed >= 0.1 then
        color._elapsed = 0

        color._remain = color._duration - (GetTime() - color._start)
        -- update color
        if color._remain <= color.colors[6][1] then
            if color.state ~= 3 then
                color.state = 3
                color.solidTex:SetVertexColor(color.colors[6][2][1], color.colors[6][2][2], color.colors[6][2][3], color.colors[6][2][4])
            end
        elseif color._remain <= color._duration * color.colors[5][1] then
            if color.state ~= 2 then
                color.state = 2
                color.solidTex:SetVertexColor(color.colors[5][2][1], color.colors[5][2][2], color.colors[5][2][3], color.colors[5][2][4])
            end
        elseif color.state ~= 1 then
            color.state = 1
            color.solidTex:SetVertexColor(color.colors[4][1], color.colors[4][2], color.colors[4][3], color.colors[4][4])
        end
    end
end

local function Color_SetCooldown(color, start, duration, debuffType)
    if color.type == "change-over-time" then
        if duration == 0 then
            color.solidTex:SetVertexColor(unpack(color.colors[4]))
            color:SetScript("OnUpdate", nil)
            color._start = nil
            color._duration = nil
            color._remain = nil
            color._elapsed = nil
        else
            color._start = start
            color._duration = duration
            color._elapsed = 0.1 -- update immediately
            color:SetScript("OnUpdate", Color_OnUpdate)
        end
    elseif color.type == "class-color" then
        color.solidTex:SetVertexColor(F.GetClassColor(color.parent.states.class))
    elseif color.type == "debuff-type" and debuffType then
        color.solidTex:SetVertexColor(CellDB["debuffTypeColor"][debuffType]["r"], CellDB["debuffTypeColor"][debuffType]["g"], CellDB["debuffTypeColor"][debuffType]["b"], 1)
    end
    color:Show()
end

-- +6 ~ +55
-- 帧层级偏移：在原始 frameLevel 基础上 +5，确保颜色层在不低于原控件的层级绘制
-- 但不超过其他更高优先级的指示器
local function Color_SetFrameLevel(color, frameLevel)
    color:_SetFrameLevel(frameLevel + 5)
end

-- 设置锚点：决定颜色层覆盖的范围
--   "healthbar-current"  -> 仅覆盖当前血量纹理
--   "healthbar-loss"     -> 仅覆盖损失血量纹理
--   "healthbar-entire"   -> 覆盖整个血条
--   其他                  -> 覆盖整个 unitbutton（内缩 CELL_BORDER_SIZE）
local function Color_SetAnchor(color, anchorTo)
    color:ClearAllPoints()
    if anchorTo == "healthbar-current" then
        -- current hp texture
        color:SetAllPoints(color.parent.widgets.healthBar:GetStatusBarTexture())
    elseif anchorTo == "healthbar-loss" then
        -- lost texture
        color:SetAllPoints(color.parent.widgets.healthBarLoss)
    elseif anchorTo == "healthbar-entire" then
        -- entire hp bar
        color:SetAllPoints(color.parent.widgets.healthBar)
    else -- unitbutton
        P.Point(color, "TOPLEFT", color.parent, "TOPLEFT", CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
        P.Point(color, "BOTTOMRIGHT", color.parent, "BOTTOMRIGHT", -CELL_BORDER_SIZE, CELL_BORDER_SIZE)
    end

    -- color:SetFrameLevel(color:GetParent():GetFrameLevel() + color.configs.frameLevel)
end

-- 设置颜色模式并立即更新纹理
-- 状态清零后根据 type 选择显示 solidTex 或 gradientTex（两者互斥）
-- "debuff-type" 和 "class-color" 模式不在此处设置最终颜色，
-- 而是在 Color_SetCooldown 中根据实际 debuffType / class 动态获取
local function Color_SetColors(self, colors)
    self.state = nil
    self.type = colors[1]
    self.colors = colors

    if colors[1] == "solid" then
        self:SetScript("OnUpdate", nil)
        self.solidTex:SetVertexColor(colors[2][1], colors[2][2], colors[2][3], colors[2][4])
        self.solidTex:Show()
        self.gradientTex:Hide()
    elseif colors[1] == "gradient-vertical" then
        self:SetScript("OnUpdate", nil)
        self.gradientTex:SetGradient("VERTICAL", CreateColor(colors[2][1], colors[2][2], colors[2][3], colors[2][4]), CreateColor(colors[3][1], colors[3][2], colors[3][3], colors[3][4]))
        self.gradientTex:Show()
        self.solidTex:Hide()
    elseif colors[1] == "gradient-horizontal" then
        self:SetScript("OnUpdate", nil)
        self.gradientTex:SetGradient("HORIZONTAL", CreateColor(colors[2][1], colors[2][2], colors[2][3], colors[2][4]), CreateColor(colors[3][1], colors[3][2], colors[3][3], colors[3][4]))
        self.gradientTex:Show()
        self.solidTex:Hide()
    elseif colors[1] == "debuff-type" then
        self:SetScript("OnUpdate", nil)
        self.solidTex:SetVertexColor(colors[2][1], colors[2][2], colors[2][3], colors[2][4])
        self.solidTex:Show()
        self.gradientTex:Hide()
    elseif colors[1] == "change-over-time" then
        self.solidTex:SetVertexColor(colors[4][1], colors[4][2], colors[4][3], colors[4][4])
        self.solidTex:Show()
        self.gradientTex:Hide()
    elseif colors[1] == "class-color" then
        self:SetScript("OnUpdate", nil)
        self.solidTex:Show()
        self.gradientTex:Hide()
    end
end

function I.CreateAura_Color(name, parent)
    local color = CreateFrame("Frame", name, parent)
    color:Hide()
    color.indicatorType = "color"
    color.parent = parent

    local solidTex = color:CreateTexture(nil, "ARTWORK")
    color.solidTex = solidTex
    solidTex:SetTexture(Cell.vars.texture)
    solidTex:SetAllPoints(color)
    solidTex:Hide()

    solidTex:SetScript("OnShow", function()
        -- update texture
        solidTex:SetTexture(Cell.vars.texture)
    end)

    local gradientTex = color:CreateTexture(nil, "ARTWORK")
    color.gradientTex = gradientTex
    gradientTex:SetTexture(Cell.vars.whiteTexture)
    gradientTex:SetAllPoints(color)
    gradientTex:Hide()

    color.SetCooldown = Color_SetCooldown
    color._SetFrameLevel = color.SetFrameLevel
    color.SetFrameLevel = Color_SetFrameLevel
    color.SetAnchor = Color_SetAnchor
    color.SetColors = Color_SetColors

    return color
end

-------------------------------------------------
-- CreateAura_Texture — 自定义纹理指示器
-- 支持通过 SetTexture 设置任意纹理路径或 Atlas，可旋转，可配置颜色
-- 可选 fadeOut 模式：持续时间流逝时 alpha 从 colorAlpha 渐变到 colorAlpha*0.1
--   公式: alpha = _remain / _duration * 0.9 + 0.1 （保证最小 0.1 可见度）
-------------------------------------------------
-- 淡出模式的 OnUpdate：剩余时间越少，透明度越低
local function Texture_OnUpdate(texture, elapsed)
    texture._elapsed = texture._elapsed + elapsed
    if texture._elapsed >= 0.1 then
        texture._elapsed = 0

        texture._remain = texture._duration - (GetTime() - texture._start)
        if texture._remain < 0 then texture._remain = 0 end
        texture.tex:SetAlpha(texture._remain / texture._duration * 0.9 + 0.1)
    end
end

local function Texture_SetCooldown(texture, start, duration)
    if duration ~= 0 and texture.fadeOut then
        texture._start = start
        texture._duration = duration
        texture._elapsed = 0.1 -- update immediately
        texture:SetScript("OnUpdate", Texture_OnUpdate)
    else
        texture:SetScript("OnUpdate", nil)
        texture.tex:SetAlpha(texture.colorAlpha)
        texture._start = nil
        texture._duration = nil
        texture._remain = nil
        texture._elapsed = nil
    end
    texture:Show()
end

local function Texture_SetFadeOut(texture, fadeOut)
    texture.fadeOut = fadeOut
end

-- 设置纹理：texTbl = {path/atlas, rotation(度), {r,g,b,a}}
-- 以 "interface" 开头的路径视为文件路径（SetTexture），否则视为 Atlas（SetAtlas）
-- rotation 以度为单位，内部转换为弧度
-- colorAlpha 缓存用于 fadeOut 模式的起始 alpha 值
local function Texture_SetTexture(texture, texTbl) -- texture, rotation, color
    if strfind(strlower(texTbl[1]), "^interface") then
        texture.tex:SetTexture(texTbl[1])
    else
        texture.tex:SetAtlas(texTbl[1])
    end
    texture.tex:SetRotation(texTbl[2] * math.pi / 180)
    texture.tex:SetVertexColor(unpack(texTbl[3]))
    texture.colorAlpha = texTbl[3][4]
end

-- Texture 工厂：简单的纹理承载 Frame，默认隐藏
function I.CreateAura_Texture(name, parent)
    local texture = CreateFrame("Frame", name, parent)
    texture:Hide()
    texture.indicatorType = "texture"

    local tex = texture:CreateTexture(name, "OVERLAY")
    texture.tex = tex
    tex:SetAllPoints(texture)

    texture.SetCooldown = Texture_SetCooldown
    texture.SetFadeOut = Texture_SetFadeOut
    texture.SetTexture = Texture_SetTexture

    return texture
end

-------------------------------------------------
-- CreateAura_Glow — 发光效果指示器
-- 基于 LibCustomGlow，覆盖整个 parent 区域，配合 Shared_SetupGlow 选择发光类型
-- 支持 fadeOut 淡出模式：与 Texture 相同的 alpha 渐变公式
-- 重要：此 Frame 必须 SetAllPoints(parent) 以完全覆盖目标区域
-------------------------------------------------
-- 发光淡出的 OnUpdate：与 Texture_OnUpdate 相同的 alpha 衰减逻辑
local function Glow_OnUpdate(glow, elapsed)
    glow._elapsed = glow._elapsed + elapsed
    if glow._elapsed >= 0.1 then
        glow._elapsed = 0

        glow._remain = glow._duration - (GetTime() - glow._start)
        if glow._remain < 0 then glow._remain = 0 end
        glow:SetAlpha(glow._remain / glow._duration * 0.9 + 0.1)
    end
end

local function Glow_SetCooldown(glow, start, duration)
    if duration ~= 0 and glow.fadeOut then
        glow._start = start
        glow._duration = duration
        glow._elapsed = 0.1 -- update immediately
        glow:SetScript("OnUpdate", Glow_OnUpdate)
    else
        glow:SetScript("OnUpdate", nil)
        glow:SetAlpha(1)
        glow._start = nil
        glow._duration = nil
        glow._remain = nil
        glow._elapsed = nil
    end

    glow:Show()
end

-- Glow 工厂：创建发光效果覆盖层
-- 通过 SetAllPoints(parent) 完全覆盖目标区域
-- 发光类型通过 Shared_SetupGlow 配置，支持 None/Normal/Pixel/Shine/Proc 五种模式
-- SetFadeOut 以闭包方式附加（非外部函数引用），控制淡出行为
function I.CreateAura_Glow(name, parent)
    local glow = CreateFrame("Frame", name, parent)
    glow:SetAllPoints(parent)
    glow:Hide()
    glow.indicatorType = "glow"

    glow.SetCooldown = Glow_SetCooldown

    function glow:SetFadeOut(fadeOut)
        glow.fadeOut = fadeOut
    end

    glow.SetupGlow = Shared_SetupGlow

    -- glow:SetScript("OnHide", function()
    --     LCG.ButtonGlow_Stop(glow)
    --     LCG.PixelGlow_Stop(glow)
    --     LCG.AutoCastGlow_Stop(glow)
    --     LCG.ProcGlow_Stop(glow)
    -- end)

    return glow
end

-------------------------------------------------
-- CreateAura_QuickAssistBars — 快速协助进度条容器
-- 专为快速协助（QuickAssist）功能设计的多 Bar 容器
-- 与 Bars 的区别：
--   1. 使用自定义 UpdateSize：根据可见条数动态计算容器总高度
--   2. 没有图标/堆叠数/倒计时文本，纯进度条
--   3. 排列方向仅支持 top-to-bottom / bottom-to-top
--   4. 子 Bar 的 SetCooldown 接收 color 参数直接染色
-------------------------------------------------
-- 快速协助条 OnUpdate：仅更新 StatusBar 值（不做颜色和文本更新）
local function QuickAssistBars_OnUpdate(bar, elapsed)
    bar._remain = bar._duration - (GetTime() - bar._start)
    if bar._remain < 0 then bar._remain = 0 end
    bar:SetValue(bar._remain)
end

local function QuickAssistBars_SetCooldown(bar, start, duration, color)
    if duration == 0 then
        bar:SetScript("OnUpdate", nil)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar._start = nil
        bar._duration = nil
        bar._remain = nil
    else
        bar._start = start
        bar._duration = duration
        bar:SetMinMaxValues(0, duration)
        bar:SetScript("OnUpdate", QuickAssistBars_OnUpdate)
    end

    bar:SetStatusBarColor(color[1], color[2], color[3], 1)
    bar:Show()
end

local function QuickAssistBars_UpdateSize(bars, barsShown)
    if not (bars.width and bars.height) then return end -- not init
    if barsShown then -- call from I.CheckCustomIndicators or preview
        for i = barsShown + 1, bars.num do
            bars[i]:Hide()
        end
        if barsShown ~= 0 then
            bars:_SetSize(bars.width, bars.height*barsShown-P.Scale(1)*(barsShown-1))
        end
    else
        for i = 1, bars.num do
            if bars[i]:IsShown() then
                bars:_SetSize(bars.width, bars.height*i-P.Scale(1)*(i-1))
            else
                break
            end
        end
    end
end

local function QuickAssistBars_SetSize(bars, width, height)
    bars.width = width
    bars.height = height

    for i = 1, bars.num do
        bars[i]:SetSize(width, height)
    end

    bars:UpdateSize()
end

local function QuickAssistBars_SetOrientation(bars, orientation)
    local point1, point2, offset
    if orientation == "top-to-bottom" then
        point1 = "TOPLEFT"
        point2 = "BOTTOMLEFT"
        offset = 1
    elseif orientation == "bottom-to-top" then
        point1 = "BOTTOMLEFT"
        point2 = "TOPLEFT"
        offset = -1
    end

    for i = 1, bars.num do
        P.ClearPoints(bars[i])
        if i == 1 then
            P.Point(bars[i], point1)
        else
            P.Point(bars[i], point1, bars[i-1], point2, 0, offset)
        end
    end

    bars:UpdateSize()
end

local function QuickAssistBars_Hide(bars, hideAll)
    bars:_Hide()
    if hideAll then
        for i = 1, bars.num do
            bars[i]:Hide()
        end
    end
end

local function QuickAssistBars_UpdatePixelPerfect(bars)
    -- P.Resize(bars)
    P.Repoint(bars)
    for i = 1, bars.num do
        bars[i]:UpdatePixelPerfect()
    end
end

-- QuickAssistBars 工厂：快速协助专用进度条容器
-- 与 Bars 不同，堆叠数和持续时间文字默认隐藏，子 Bar 的 SetCooldown 被替换为简化版本
-- 容器高度动态计算：barsShown * height - (barsShown-1) * 1px（留出间隔）
function I.CreateAura_QuickAssistBars(name, parent, num)
    local bars = CreateFrame("Frame", name, parent)
    bars:Hide()
    bars.indicatorType = "bars"
    bars.num = num

    bars._SetSize = bars.SetSize
    bars.SetSize = QuickAssistBars_SetSize
    bars.UpdateSize = QuickAssistBars_UpdateSize
    bars.SetOrientation = QuickAssistBars_SetOrientation
    bars._Hide = bars.Hide
    bars.Hide = QuickAssistBars_Hide
    bars.UpdatePixelPerfect = QuickAssistBars_UpdatePixelPerfect

    for i = 1, num do
        local name = name and name.."Bar"..i
        local bar = I.CreateAura_Bar(name, bars)
        bars[i] = bar

        bar.stack:Hide()
        bar.duration:Hide()
        bar.SetCooldown = QuickAssistBars_SetCooldown
    end

    return bars
end

-------------------------------------------------
-- CreateAura_Overlay — 血量条覆盖层指示器
-- 直接创建在 healthBar 上的 StatusBar 覆盖层，可平滑过渡（SmoothStatusBarMixin）
-- 帧层级偏移 +55，确保在所有指示器中处于较高层级
-- 支持 EnableSmooth 动态切换平滑/瞬时更新模式
-------------------------------------------------
-- Overlay 的 OnUpdate：同时更新 StatusBar 值和三档颜色
local function Overlay_OnUpdate(overlay, elapsed)
    overlay._remain = overlay._duration - (GetTime() - overlay._start)
    if overlay._remain < 0 then overlay._remain = 0 end
    overlay:_SetValue(overlay._remain)

    overlay._elapsed = overlay._elapsed + elapsed
    if overlay._elapsed >= 0.1 then
        overlay._elapsed = 0
        -- update color
        if overlay.colors[3][1] and overlay._remain <= overlay.colors[3][2] then
            if overlay.state ~= 3 then
                overlay.state = 3
                overlay:SetStatusBarColor(overlay.colors[3][3][1], overlay.colors[3][3][2], overlay.colors[3][3][3], overlay.colors[3][3][4])
            end
        elseif overlay.colors[2][1] and overlay._remain <= overlay._duration * overlay.colors[2][2] then
            if overlay.state ~= 2 then
                overlay.state = 2
                overlay:SetStatusBarColor(overlay.colors[2][3][1], overlay.colors[2][3][2], overlay.colors[2][3][3], overlay.colors[2][3][4])
            end
        elseif overlay.state ~= 1 then
            overlay.state = 1
            overlay:SetStatusBarColor(overlay.colors[1][1], overlay.colors[1][2], overlay.colors[1][3], overlay.colors[1][4])
        end
    end
end

local function Overlay_SetCooldown(overlay, start, duration, debuffType, texture, count)
    if duration == 0 then
        overlay:SetScript("OnUpdate", nil)
        overlay:_SetMinMaxValues(0, 1)
        overlay:_SetValue(1)
        overlay:SetStatusBarColor(unpack(overlay.colors[1]))
        overlay._start = nil
        overlay._duration = nil
        overlay._remain = nil
        overlay._elapsed = nil
    else
        overlay:_SetMinMaxValues(0, duration)
        overlay._start = start
        overlay._duration = duration
        overlay._elapsed = 0.1 -- update immediately
        overlay:SetScript("OnUpdate", Overlay_OnUpdate)
    end

    overlay:Show()
end

-- 启用/禁用平滑过渡：通过替换内部方法实现
-- 平滑模式：使用 SmoothStatusBarMixin 提供的 SetMinMaxSmoothedValue / SetSmoothedValue
-- 普通模式：使用原生 SetMinMaxValues / SetValue
local function Overlay_EnableSmooth(overlay, smooth)
    if smooth then
        overlay._SetMinMaxValues = overlay.SetMinMaxSmoothedValue
        overlay._SetValue = overlay.SetSmoothedValue
    else
        overlay._SetMinMaxValues = overlay.SetMinMaxValues
        overlay._SetValue = overlay.SetValue
    end
end

-- 设置颜色表：与 Bar/Rect 的三档颜色结构相同
local function Overlay_SetColors(overlay, colors)
    overlay.state = nil
    overlay.colors = colors
end

-- +56 ~ +110
-- Overlay 的帧层级偏移：+55，是所有指示器中层级最高的
-- 这样覆盖层在血条上可见但不会阻挡更高优先级的 UI 元素
local function Overlay_SetFrameLevel(overlay, frameLevel)
    overlay:_SetFrameLevel(frameLevel + 55)
end

-- Overlay 工厂：基于 StatusBar + SmoothStatusBarMixin，直接挂载到 healthBar 上
-- 通过替换 _SetMinMaxValues/_SetValue 方法实现平滑/瞬时切换
function I.CreateAura_Overlay(name, parent)
    local overlay = CreateFrame("StatusBar", name, parent.widgets.healthBar)
    overlay:SetStatusBarTexture(Cell.vars.whiteTexture)
    overlay:Hide()
    overlay.indicatorType = "overlay"

    Mixin(overlay, SmoothStatusBarMixin)
    overlay:SetAllPoints()
    -- overlay:SetBackdropColor(0, 0, 0, 0)

    overlay.SetCooldown = Overlay_SetCooldown
    overlay._SetMinMaxValues = overlay.SetMinMaxValues
    overlay._SetValue = overlay.SetValue
    overlay._SetFrameLevel = overlay.SetFrameLevel
    overlay.SetFrameLevel = Overlay_SetFrameLevel
    overlay.EnableSmooth = Overlay_EnableSmooth
    overlay.SetColors = Overlay_SetColors

    return overlay
end

-------------------------------------------------
-- CreateAura_Block — 块状指示器（带冷却动画和背景色切换）
-- 独特的双模式颜色切换系统：
--   "duration" 模式 (Block_SetCooldown_Duration)：
--     颜色根据剩余时间三档变化，与 Bar/Rect 逻辑一致
--   "stack" 模式 (Block_SetCooldown_Stack)：
--     颜色根据堆叠层数三档变化（count >= 阈值），仅在 SetCooldown 时切换
-- 两种模式的 OnUpdate 逻辑不同，通过 SetColors 动态切换 SetCooldown 函数引用
-------------------------------------------------
-- duration 模式 OnUpdate：颜色随剩余时间变化 + 倒计时文本
local function Block_OnUpdate_Duration(frame, elapsed)
    frame._remain = frame._duration - (GetTime() - frame._start)
    if frame._remain < 0 then frame._remain = 0 end

    frame._elapsed = frame._elapsed + elapsed
    if frame._elapsed >= 0.1 then
        frame._elapsed = 0
        -- update color
        if frame.colors[4][1] and frame._remain <= frame.colors[4][2] then
            if frame.state ~= 3 then
                frame.state = 3
                frame:SetBackdropColor(frame.colors[4][3][1], frame.colors[4][3][2], frame.colors[4][3][3], frame.colors[4][3][4])
            end
        elseif frame.colors[3][1] and frame._remain <= frame._duration * frame.colors[3][2] then
            if frame.state ~= 2 then
                frame.state = 2
                frame:SetBackdropColor(frame.colors[3][3][1], frame.colors[3][3][2], frame.colors[3][3][3], frame.colors[3][3][4])
            end
        elseif frame.state ~= 1 then
            frame.state = 1
            frame:SetBackdropColor(frame.colors[2][1], frame.colors[2][2], frame.colors[2][3], frame.colors[2][4])
        end
    end

    if frame._remain > frame._threshold then
        frame.duration:SetText("")
        return
    end

    -- format
    if frame._remain > 60 then
        frame.duration:SetFormattedText("%dm", frame._remain / 60)
    else
        if Cell.vars.iconDurationRoundUp then
            frame.duration:SetFormattedText("%d", ceil(frame._remain))
        else
            if Cell.vars.iconDurationDecimal and frame._remain < Cell.vars.iconDurationDecimal then
                frame.duration:SetFormattedText("%.1f", frame._remain)
            else
                frame.duration:SetFormattedText("%d", frame._remain)
            end
        end
    end
end

-- duration 模式冷却设置：颜色在 OnUpdate 中动态切换，此处仅配置冷却动画和阈值
local function Block_SetCooldown_Duration(frame, start, duration, debuffType, texture, count, refreshing)
    -- local r, g, b
    -- if debuffType then
    --     r, g, b = I.GetDebuffTypeColor(debuffType)
    -- else
    --     r, g, b = 0, 0, 0
    -- end

    if duration == 0 then
        frame.cooldown:Hide()
        frame.duration:Hide()
        frame:SetScript("OnUpdate", nil)
        frame._start = nil
        frame._duration = nil
        frame._remain = nil
        frame._elapsed = nil
        frame._threshold = nil
    else
        -- frame.cooldown:SetSwipeColor(r, g, b)
        frame.cooldown:ShowCooldown(start, duration)

        if not frame.showDuration then
            frame._threshold = -1
            frame.duration:Hide()
        else
            if frame.showDuration == true then
                frame._threshold = duration
            elseif frame.showDuration >= 1 then
                frame._threshold = frame.showDuration
            else -- < 1
                frame._threshold = frame.showDuration * duration
            end
            frame.duration:Show()
        end

        frame._start = start
        frame._duration = duration
        frame._elapsed = 0.1 -- update immediately
        frame:SetScript("OnUpdate", Block_OnUpdate_Duration)
    end

    frame.stack:SetText(_StackText(count))
    frame:Show()

    if refreshing then
        frame.ag:Play()
    end
end

-- stack 模式 OnUpdate：仅更新倒计时文本（颜色在 SetCooldown 时根据 count 一次性设定）
local function Block_OnUpdate_Stack(frame, elapsed)
    frame._remain = frame._duration - (GetTime() - frame._start)
    if frame._remain < 0 then frame._remain = 0 end

    if frame._remain > frame._threshold then
        frame.duration:SetText("")
        return
    end

    -- format
    if frame._remain > 60 then
        frame.duration:SetFormattedText("%dm", frame._remain / 60)
    else
        if Cell.vars.iconDurationRoundUp then
            frame.duration:SetFormattedText("%d", ceil(frame._remain))
        else
            if Cell.vars.iconDurationDecimal and frame._remain < Cell.vars.iconDurationDecimal then
                frame.duration:SetFormattedText("%.1f", frame._remain)
            else
                frame.duration:SetFormattedText("%d", frame._remain)
            end
        end
    end
end

-- stack 模式冷却设置：颜色在此时根据 count 一次性切换（colors[4]=紧急/colors[3]=警告/colors[2]=正常）
-- 注意：count 参数在调用方已通过 _SanitizeCount 清洗，但此处颜色比较使用的是原始数值逻辑
local function Block_SetCooldown_Stack(frame, start, duration, debuffType, texture, count, refreshing)
    if duration == 0 then
        frame.cooldown:Hide()
        frame.duration:Hide()
        frame:SetScript("OnUpdate", nil)
        frame._start = nil
        frame._duration = nil
        frame._remain = nil
        frame._threshold = nil
    else
        -- frame.cooldown:SetSwipeColor(r, g, b)
        frame.cooldown:ShowCooldown(start, duration)

        if not frame.showDuration then
            frame._threshold = -1
            frame.duration:Hide()
        else
            if frame.showDuration == true then
                frame._threshold = duration
            elseif frame.showDuration >= 1 then
                frame._threshold = frame.showDuration
            else -- < 1
                frame._threshold = frame.showDuration * duration
            end
            frame.duration:Show()
        end

        frame._start = start
        frame._duration = duration
        frame:SetScript("OnUpdate", Block_OnUpdate_Stack)
    end

    -- update color
    if frame.colors[4][1] and count >= frame.colors[4][2] then
        frame:SetBackdropColor(frame.colors[4][3][1], frame.colors[4][3][2], frame.colors[4][3][3], frame.colors[4][3][4])
    elseif frame.colors[3][1] and count >= frame.colors[3][2] then
        frame:SetBackdropColor(frame.colors[3][3][1], frame.colors[3][3][2], frame.colors[3][3][3], frame.colors[3][3][4])
    else
        frame:SetBackdropColor(frame.colors[2][1], frame.colors[2][2], frame.colors[2][3], frame.colors[2][4])
    end

    frame.stack:SetText(_StackText(count))
    frame:Show()

    if refreshing then
        frame.ag:Play()
    end
end

-- 通过替换 SetCooldown 函数引用来切换 duration/stack 模式（策略模式）
-- colors[1] 为 "duration" 时使用持续时间变色，否则使用堆叠数变色
-- colors 结构: {type, [2]=正常色, [3]={enabled, threshold, color}, [4]={enabled, threshold, color}, [5]=边框色}
local function Block_SetColors(frame, colors)
    if colors[1] == "duration" then
        frame.SetCooldown = Block_SetCooldown_Duration
    else
        frame.SetCooldown = Block_SetCooldown_Stack
    end
    frame:SetBackdropBorderColor(colors[5][1], colors[5][2], colors[5][3], colors[5][4])
    frame.state = nil
    frame.colors = colors
end

-- Block 的像素完美重布局：除自身外还需重定位子控件和冷却动画的 spark
local function Block_UpdatePixelPerfect(frame)
    P.Resize(frame)
    P.Repoint(frame)
    P.Repoint(frame.stack)
    P.Repoint(frame.duration)
    P.Repoint(frame.cooldown)
    P.Reborder(frame)
    if frame.cooldown.spark then
        P.Resize(frame.cooldown.spark)
    end
end

-- Block 工厂：带背景和边框的块状指示器，内置冷却动画
-- 默认冷却风格由 CELL_COOLDOWN_STYLE 决定，noIcon=true（无褪色图标层）
-- stack/duration 字体字符串直接挂载在 cooldown 帧上
-- 包含弹跳 AnimationGroup 用于刷新视觉反馈
function I.CreateAura_Block(name, parent)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:Hide()
    frame.indicatorType = "block"

    frame:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(CELL_BORDER_SIZE)})

    Shared_SetCooldownStyle(frame, CELL_COOLDOWN_STYLE, true)

    frame.stack = frame.cooldown:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    frame.duration = frame.cooldown:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")

    frame.SetFont = Shared_SetFont
    frame.SetColors = Block_SetColors
    frame.ShowStack = Shared_ShowStack
    frame.ShowDuration = Shared_ShowDuration
    frame.SetCooldown = Block_SetCooldown_Duration
    frame.SetupGlow = Shared_SetupGlow
    frame.UpdatePixelPerfect = Block_UpdatePixelPerfect

    local ag = frame:CreateAnimationGroup()
    frame.ag = ag
    local t1 = ag:CreateAnimation("Translation")
    t1:SetOffset(0, 5)
    t1:SetDuration(0.1)
    t1:SetOrder(1)
    t1:SetSmoothing("OUT")
    local t2 = ag:CreateAnimation("Translation")
    t2:SetOffset(0, -5)
    t2:SetDuration(0.1)
    t2:SetOrder(2)
    t2:SetSmoothing("IN")

    return frame
end

-------------------------------------------------
-- CreateAura_Blocks — 多个块容器（复用 Icons 的布局引擎）
-- 与 Bars 类似，使用 Blocks_SetCooldown 替代子 Block 的默认 SetCooldown
-- 区别：子元素是 Block（非 Bar），且 Blocks_SetCooldown 额外接收 color 参数
-- color 用于直接染色背景，而非依赖 Block 自身的 colors 配置
-------------------------------------------------
-- Blocks 容器的子 Block OnUpdate：仅更新倒计时文本（不做颜色切换）
local function Blocks_OnUpdate(frame, elapsed)
    frame._remain = frame._duration - (GetTime() - frame._start)
    if frame._remain < 0 then frame._remain = 0 end

    if frame._remain > frame._threshold then
        frame.duration:SetText("")
        return
    end

    -- format
    if frame._remain > 60 then
        frame.duration:SetFormattedText("%dm", frame._remain / 60)
    else
        if Cell.vars.iconDurationRoundUp then
            frame.duration:SetFormattedText("%d", ceil(frame._remain))
        else
            if Cell.vars.iconDurationDecimal and frame._remain < Cell.vars.iconDurationDecimal then
                frame.duration:SetFormattedText("%.1f", frame._remain)
            else
                frame.duration:SetFormattedText("%d", frame._remain)
            end
        end
    end
end

local function Blocks_SetCooldown(frame, start, duration, debuffType, texture, count, refreshing, color)
    if duration == 0 then
        frame.cooldown:Hide()
        frame.duration:Hide()
        frame:SetScript("OnUpdate", nil)
        frame._start = nil
        frame._duration = nil
        frame._remain = nil
        frame._threshold = nil
    else
        frame.cooldown:ShowCooldown(start, duration)

        if not frame.showDuration then
            frame._threshold = -1
            frame.duration:Hide()
        else
            if frame.showDuration == true then
                frame._threshold = duration
            elseif frame.showDuration >= 1 then
                frame._threshold = frame.showDuration
            else -- < 1
                frame._threshold = frame.showDuration * duration
            end
            frame.duration:Show()
        end

        frame._start = start
        frame._duration = duration
        frame:SetScript("OnUpdate", Blocks_OnUpdate)
    end

    frame:SetBackdropColor(color[1], color[2], color[3], color[4])
    frame.stack:SetText(_StackText(count))
    frame:Show()

    if refreshing then
        frame.ag:Play()
    end
end

-- Blocks 工厂：创建多个块容器（复用 Icons 布局引擎）
-- 每个子 Block 通过 I.CreateAura_Block 创建，替换 SetCooldown 为 Blocks_SetCooldown
-- 子 Block 的边框色统一设为黑色，背景色由 Blocks_SetCooldown 中的 color 参数直接染色
function I.CreateAura_Blocks(name, parent, num)
    local blocks = CreateFrame("Frame", name, parent)
    blocks:Hide()

    blocks.indicatorType = "blocks"
    blocks.maxNum = num
    blocks.numPerLine = num

    blocks._SetSize = blocks.SetSize
    blocks.SetSize = Icons_SetSize
    blocks._Hide = blocks.Hide
    blocks.Hide = Icons_Hide
    blocks.SetFont = Icons_SetFont
    blocks.UpdateSize = Icons_UpdateSize
    blocks.SetOrientation = Icons_SetOrientation
    blocks.SetSpacing = Icons_SetSpacing
    blocks.SetNumPerLine = Icons_SetNumPerLine
    blocks.ShowDuration = Icons_ShowDuration
    blocks.ShowStack = Icons_ShowStack
    blocks.SetupGlow = I.Glow_SetupForChildren
    blocks.UpdatePixelPerfect = Icons_UpdatePixelPerfect

    for i = 1, num do
        local name = name and name.."Icons"..i
        local frame = I.CreateAura_Block(name, blocks)
        blocks[i] = frame
        frame.SetCooldown = Blocks_SetCooldown
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    return blocks
end

-------------------------------------------------
-- CreateAura_Border — 边框发光指示器
-- 通过双层 Mask 纹理实现镂空边框效果：
--   mask 层：留出 thickness 宽度的边框区域（白色=可见）
--   mask2 层：比 mask 多 CELL_BORDER_SIZE 的额外区域（用于绘制黑色外边框）
--   tex 层：白色纹理 + mask 遮罩 -> 显示彩色边框
--   tex2 层：黑色纹理 + mask2 遮罩 -> 显示黑色外边框（层级-1在下方）
-- 支持 fadeOut 淡出模式
-------------------------------------------------
-- 边框淡出的 OnUpdate：与 Texture 相同的 alpha 衰减公式
local function Border_OnUpdate(border, elapsed)
    border._elapsed = border._elapsed + elapsed
    if border._elapsed >= 0.1 then
        border._elapsed = 0

        border._remain = border._duration - (GetTime() - border._start)
        if border._remain < 0 then border._remain = 0 end
        border:SetAlpha(border._remain / border._duration * 0.9 + 0.1)
    end
end

local function Border_SetFadeOut(border, fadeOut)
    border.fadeOut = fadeOut
end

local function Border_SetCooldown(border, start, duration, _, _, _, _, color)
    if duration ~= 0 and border.fadeOut then
        border._start = start
        border._duration = duration
        border._elapsed = 0.1 -- update immediately
        border:SetScript("OnUpdate", Border_OnUpdate)
    else
        border:SetScript("OnUpdate", nil)
        border._start = nil
        border._duration = nil
        border._remain = nil
        border._elapsed = nil
        border:SetAlpha(1)
    end
    border.tex:SetVertexColor(color[1], color[2], color[3], color[4])
    border:Show()
end

local function Border_UpdatePixelPerfect(border)
    P.Repoint(border)
    P.Repoint(border.mask)
    P.Repoint(border.mask2)
end

local function Border_SetThickness(border, thickness)
    P.ClearPoints(border.mask)
    P.Point(border.mask, "TOPLEFT", thickness, -thickness)
    P.Point(border.mask, "BOTTOMRIGHT", -thickness, thickness)
    P.ClearPoints(border.mask2)
    P.Point(border.mask2, "TOPLEFT", thickness+CELL_BORDER_SIZE, -thickness-CELL_BORDER_SIZE)
    P.Point(border.mask2, "BOTTOMRIGHT", -thickness-CELL_BORDER_SIZE, thickness+CELL_BORDER_SIZE)
end

-- Border 工厂：创建双层 Mask 镂空边框效果
-- mask 使用 emptyTexture（中间透明四周白色），通过 CLAMPTOWHITE 模式在边框区域显示纹理
-- 双层设计：tex 显示彩色边框，tex2 在底层显示黑色外边框增强对比
function I.CreateAura_Border(name, parent)
    local border = CreateFrame("Frame", name, parent)
    border:Hide()
    border.indicatorType = "border"

    P.Point(border, "TOPLEFT", CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
    P.Point(border, "BOTTOMRIGHT", -CELL_BORDER_SIZE, CELL_BORDER_SIZE)

    -- mask: 用于彩色边框的镂空遮罩
    local mask = border:CreateMaskTexture()
    border.mask = mask
    mask:SetTexture(Cell.vars.emptyTexture, "CLAMPTOWHITE","CLAMPTOWHITE")

    local tex = border:CreateTexture(nil, "ARTWORK")
    border.tex = tex
    tex:SetAllPoints()
    tex:SetTexture(Cell.vars.whiteTexture)
    tex:AddMaskTexture(mask)

    local mask2 = border:CreateMaskTexture()
    border.mask2 = mask2
    mask2:SetTexture(Cell.vars.emptyTexture, "CLAMPTOWHITE","CLAMPTOWHITE")

    local tex2 = border:CreateTexture(nil, "ARTWORK", nil, -1)
    tex2:SetAllPoints()
    tex2:SetColorTexture(0, 0, 0)
    tex2:AddMaskTexture(mask2)

    border.SetCooldown = Border_SetCooldown
    border.SetFadeOut = Border_SetFadeOut
    border.SetThickness = Border_SetThickness
    border.UpdatePixelPerfect = Border_UpdatePixelPerfect

    return border
end