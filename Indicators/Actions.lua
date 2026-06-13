local _, Cell = ...
local L = Cell.L
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs

-- ============================================================================
-- 模块概述：Actions 指示器 (Actions Indicator)
-- 监听小队/团队成员的 UNIT_SPELLCAST_SUCCEEDED 事件，
-- 当施法 ID 匹配 Cell.vars.actions 中的预设技能列表时，
-- 在对应单位框体上播放指定的动画效果。
-- 支持 A~G 共七种动画类型，通过 CreateObjectPool 管理动画画布复用。
-- ============================================================================

local orientation, speed

-------------------------------------------------
-- events
-------------------------------------------------
-- Audited for Midnight 12.0.0+ compatibility: no changes required.
-- CLEU (COMBAT_LOG_EVENT_UNFILTERED) is not used — it is fully commented out below.
-- The active handler listens to UNIT_SPELLCAST_SUCCEEDED for group members only.
-- spellID from UNIT_SPELLCAST_SUCCEEDED for allied units is non-secret.
-- Cell.vars.actions[spellID] table key usage is safe because the spellID comes
-- from your own group's spellcasts, which are never restricted by GetRestrictedActionStatus.
--
-- [Midnight 12.0.0+ 兼容性审计说明]
-- 当前代码无需任何修改，原因如下：
-- 1. CLEU (COMBAT_LOG_EVENT_UNFILTERED) 已完全注释，未被使用。
-- 2. 活跃的事件处理仅监听小队/团队成员发出的 UNIT_SPELLCAST_SUCCEEDED。
-- 3. 友方单位 UNIT_SPELLCAST_SUCCEEDED 返回的 spellID 不受 RestrictedActions
--    影响，属于非密文 (non-secret)。
-- 4. Cell.vars.actions[spellID] 表键查询安全：spellID 来自己方队伍法术施放，
--    永远不会受到 GetRestrictedActionStatus 的限制。

-- 事件数据格式参考 (Event Data Format Reference):
-- CLEU: subevent, source, target, spellId, spellName
-- [15:10] SPELL_HEAL 秋静葉 秋静葉 6262 治疗石
-- [15:10] SPELL_CAST_SUCCESS 秋静葉 nil 6262 治疗石
-- [15:13] SPELL_HEAL 秋静葉 秋静葉 307192 灵魂治疗药水
-- [15:13] SPELL_CAST_SUCCESS 秋静葉 nil 307192 灵魂治疗药水

-- UNIT_SPELLCAST_SUCCEEDED 事件参数 (仅监听小队/团队成员):
-- unit, castGUID, spellID

-- Display 辅助函数：将动画参数从 HandleUnitButton 回调转发到对应按钮实例的
-- actions 指示器。b 为按钮对象，... 包含动画类型和颜色等参数。
local function Display(b, ...)
    b.indicators.actions:Display(...)
end

-- 事件监听框架：接收 UNIT_SPELLCAST_SUCCEEDED 事件，触发匹配的动画播放。
-- 注意：事件注册由 I.EnableActions(enabled) 控制，仅在用户启用 Actions
-- 指示器时才注册事件，避免不必要的 CPU 开销。
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    -- filter out players not in your group
    -- 过滤非小队/团队成员：仅处理小队、团队、自身玩家及宠物
    -- 避免处理陌生单位（如附近的非队伍玩家）的施法事件
    if not (UnitInRaid(unit) or UnitInParty(unit) or unit == "player" or unit == "pet") then return end

    -- 调试模式：输出法术施放成功事件的完整信息
    -- 格式：[Cell] 事件名: 单位名 spellID 法术名称
    -- 由 Cell.vars.actionsDebugModeEnabled 开关控制
    if Cell.vars.actionsDebugModeEnabled then
        local name = F.GetSpellInfo(spellID)
        print("|cFFFF3030[Cell]|r |cFFB2B2B2" .. event .. ":|r", unit, "|cFF00FF00" .. (spellID or "nil") .. "|r", name)
    end

    -- Midnight 12.0.0+ 密文防护 (SecretValue Protection):
    -- 在战斗受限上下文中，UNIT_SPELLCAST_SUCCEEDED 的 spellID 可能被 Blizzard
    -- 标记为密文 (secret value)。使用全局函数 issecretvalue() 检测密文事件
    -- 并直接丢弃，防止将密文值用作 Cell.vars.actions 表的键导致功能异常。
    -- Cell.isMidnight 标志在 Cell 核心初始化时设置，用于判断当前客户端版本。
    if Cell.isMidnight and issecretvalue and issecretvalue(spellID) then return end

    -- 在预设技能列表中查找匹配的 spellID，找到则在对应单位框体上播放动画
    -- Cell.vars.actions[spellID] 存储了 {animationType, r, g, b} 格式的配置
    if Cell.vars.actions[spellID] then
        F.HandleUnitButton("unit", unit, Display, unpack(Cell.vars.actions[spellID]))
    end
end)

-- [已废弃] CLEU (COMBAT_LOG_EVENT_UNFILTERED) 监听方案：
-- 被注释的原因是 Midnight 12.0.0+ 中 CLEU 的 spellID 在战斗受限上下文中
-- 必定为密文 (secret value)，无法安全地用作表键。且 UNIT_SPELLCAST_SUCCEEDED
-- 方案已完全满足 Actions 指示器的所有需求（仅监听己方队伍施法）。
-- local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
-- eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
-- eventFrame:SetScript("OnEvent", function()
--     local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName = CombatLogGetCurrentEventInfo()
--     print(subevent, sourceName, destName, spellId, spellName)
-- end)

-------------------------------------------------
-- pool
-------------------------------------------------

-- ============================================================================
-- 动画对象池 (Animation Object Pool)
-- 使用 Blizzard 的 CreateObjectPool API 管理动画画布 (Canvas Frame) 的创建
-- 与复用，避免频繁创建/销毁 Frame 对象带来的性能开销。每种动画类型 (A~G)
-- 拥有独立的对象池 animationPool[A] ~ animationPool[G]。
-- 工作流程：Acquire() 获取空闲画布 -> 配置并播放动画 -> OnFinished 时 Release() 归还。
-- ============================================================================

local animationPool = {}

-- 对象池重置回调 (Pool Resetter): 画布被 Release 回收时调用。
-- 仅执行 Hide()，等待下次 Acquire 时重新配置父框体、锚点和动画参数后再 Show。
local function ResetterFunc(_, canvas)
    canvas:Hide()
end

-------------------------------------------------
-- animation: A
-------------------------------------------------

-- ============================================================================
-- 动画类型 A：渐变光条扫过 (Gradient Sweep)
-- 效果：一条从透明到实色的渐变光条从框体起始端滑入，
-- 先 Alpha 淡入，再水平/垂直平移，最后 Alpha 淡出消失。
-- 支持水平和垂直两种方向，根据 parent.orientation 自动适配。
-- 动画序列：Alpha 淡入(0→1, OUT 缓出) + Translation(位移) + Alpha 淡出(1→0)
-- ============================================================================
local function CreateAnimationGroup_TypeA()
    -- 创建动画画布 (Canvas): 所有子元素的容器，也是遮罩 (Mask) 的附着目标
    local canvas = CreateFrame("Frame")

    -- frame
    local f = CreateFrame("Frame", nil, canvas)

    -- texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(f)
    tex:SetTexture(Cell.vars.whiteTexture)

    -- mask
    local mask = canvas:CreateMaskTexture()
    mask:SetTexture(Cell.vars.whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(canvas)
    -- mask:SetSnapToPixelGrid(true)
    tex:AddMaskTexture(mask)

    -- animation
    local ag = f:CreateAnimationGroup()
    canvas.ag = ag

    -- Alpha 淡入：透明度从 0 渐变到 1，Order=1 与 Translation 同时开始
    local a1 = ag:CreateAnimation("Alpha")
    a1.duration = 0.6
    a1:SetFromAlpha(0)
    a1:SetToAlpha(1)
    a1:SetOrder(1)
    a1:SetDuration(a1.duration)
    a1:SetSmoothing("OUT")

    -- 平移：光条从框体一端移动到另一端，Order=1 与 Alpha 淡入同时开始
    local t1 = ag:CreateAnimation("Translation")
    t1.duration = 0.6
    t1:SetOrder(1)
    t1:SetSmoothing("OUT")
    t1:SetDuration(t1.duration)

    -- Alpha 淡出：光条进入末尾阶段时淡出，Order=2 在 Order=1 动画结束后执行
    local a2 = ag:CreateAnimation("Alpha")
    a2.duration = 0.5
    a2:SetFromAlpha(1)
    a2:SetToAlpha(0)
    a2:SetDuration(a2.duration)
    a2:SetOrder(2)
    -- a2:SetSmoothing("IN")

    -- OnPlay: 动画开始播放时显示画布 (canvas 默认隐藏)
    ag:SetScript("OnPlay", function()
        canvas:Show()
    end)

    -- OnFinished: 动画播放完毕，将画布归还对象池供下次复用
    ag:SetScript("OnFinished", function()
        animationPool.A:Release(canvas)
    end)

    -- Display 方法：配置动画参数并开始/重启播放
    -- parent: 目标按钮/框体实例，需提供 orientation 和 speed 属性
    -- r, g, b: 光条颜色 (RGB 分量，0~1 范围)
    function ag:Display(parent, r, g, b)
        canvas:SetParent(parent)
        canvas:SetAllPoints(parent)

        if parent.orientation == "horizontal" then
            -- 水平布局：光条从左侧滑入，宽度 15px，使用水平渐变 (左透明→右实色)
            f:SetPoint("TOPRIGHT", canvas, "TOPLEFT")
            f:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMLEFT")
            f:SetWidth(15)

            t1:SetOffset(canvas:GetWidth(), 0)
            tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 1))
        else
            -- 垂直布局：光条从底部滑入，高度 15px，使用垂直渐变 (上透明→下实色)
            f:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT")
            f:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT")
            f:SetHeight(15)

            t1:SetOffset(0, canvas:GetHeight())
            tex:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 1))
        end

        -- 根据父框体的 speed 属性调整动画持续时间：duration / speed
        -- speed 越大动画越快（duration 越小）
        a1:SetDuration(a1.duration / parent.speed)
        t1:SetDuration(t1.duration / parent.speed)
        a2:SetDuration(a2.duration / parent.speed)

        -- Restart 机制：如果动画已在播放中则重新开始，否则从头播放
        -- 这确保了连续施法时每次都能看到完整的动画效果
        if ag:IsPlaying() then
            ag:Restart()
        else
            ag:Play()
        end
    end

    return canvas
end

animationPool.A = CreateObjectPool(CreateAnimationGroup_TypeA, ResetterFunc)

-------------------------------------------------
-- animation: B
-------------------------------------------------

-- ============================================================================
-- 动画类型 B：斜纹光条划过 (Diagonal Stripe Sweep)
-- 效果：一条 45 度倾斜的实色条纹从框体左侧扫入，
-- Alpha 从 0 渐变到 0.7，带 IN_OUT 缓动的平滑平移效果。
-- 条纹宽度由 WIDTH 常量控制 (20 像素)，平移距离含倾斜几何补偿。
-- 动画序列：Alpha 淡入(0→0.7) + Translation(水平平移，含 45° 倾斜补偿)
-- ============================================================================
local function CreateAnimationGroup_TypeB()
    local WIDTH = 20

    local canvas = CreateFrame("Frame")

    -- frame
    local f = CreateFrame("Frame", nil, canvas)
    f:SetPoint("TOPRIGHT", canvas, "TOPLEFT")
    f:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMLEFT")
    f:SetWidth(WIDTH)

    -- texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("BOTTOMRIGHT")
    tex:SetWidth(WIDTH)
    -- 纹理旋转 45 度形成斜纹效果，旋转轴为 (1,0) 即右侧边缘
    tex:SetRotation(45 * math.pi / 180, CreateVector2D(1, 0))

    -- mask
    local mask = canvas:CreateMaskTexture()
    mask:SetTexture(Cell.vars.whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(canvas)
    -- mask:SetSnapToPixelGrid(true)
    tex:AddMaskTexture(mask)

    -- animation
    local ag = f:CreateAnimationGroup()
    canvas.ag = ag

    -- Alpha 淡入到 0.7（非全不透明），Order=1
    local a1 = ag:CreateAnimation("Alpha")
    a1.duration = 0.35
    a1:SetFromAlpha(0)
    a1:SetToAlpha(0.7)
    a1:SetDuration(a1.duration)
    -- a1:SetSmoothing("IN")

    -- 平移：带 IN_OUT 缓动，总持续 0.7s，后半段自然减速
    local t1 = ag:CreateAnimation("Translation")
    t1.duration = 0.7
    t1:SetSmoothing("IN_OUT")
    t1:SetDuration(t1.duration)

    -- Alpha 淡出动画 (已注释): 原计划平移结束后淡出，目前仅依靠平移自然结束
    -- local a2 = ag:CreateAnimation("Alpha")
    -- a2.duration = 0.3
    -- a2:SetFromAlpha(0.7)
    -- a2:SetToAlpha(0)
    -- a2:SetDuration(a2.duration)
    -- a2:SetStartDelay(t1.duration - a2.duration)

    ag:SetScript("OnPlay", function()
        canvas:Show()
    end)

    ag:SetScript("OnFinished", function()
        animationPool.B:Release(canvas)
    end)

    function ag:Display(parent, r, g, b)
        canvas:SetParent(parent)
        canvas:SetAllPoints(parent)

        a1:SetDuration(a1.duration / parent.speed)
        t1:SetDuration(t1.duration / parent.speed)

        -- 平移距离计算：框体宽度 + 45° 倾斜的水平分量 + 条纹本身的宽度补偿
        -- tan(π/4)=1, cos(π/4)=√2/2，确保 45° 斜纹完全移出框体可见区域
        t1:SetOffset(canvas:GetWidth() + math.tan(math.pi / 4) * canvas:GetHeight() + WIDTH / math.cos(math.pi / 4), 0)
        -- 纹理高度：框体高度 + 45° 斜向延伸，确保斜纹覆盖整个框体高度
        tex:SetHeight(canvas:GetHeight() / math.sin(math.pi / 4) + WIDTH)
        tex:SetColorTexture(r, g, b)

        if ag:IsPlaying() then
            ag:Restart()
        else
            ag:Play()
        end
    end

    return canvas
end

animationPool.B = CreateObjectPool(CreateAnimationGroup_TypeB, ResetterFunc)

-------------------------------------------------
-- animation: C
-------------------------------------------------

-- ============================================================================
-- 动画类型 C：升级箭头图标 (Upgrade Arrow Icon)
-- 效果：使用 Cell 内置的 upgrade.tga 贴图，从框体底部垂直向上滑入，
-- 淡入后淡出消失。支持三个水平位置子类型 (subType)。
-- 动画序列：Alpha 淡入(0→1, OUT) + Translation(垂直平移, OUT) + Alpha 淡出(1→0, IN)
-- ============================================================================
local function CreateAnimationGroup_TypeC()
    local canvas = CreateFrame("Frame")

    -- frame
    local f = CreateFrame("Frame", nil, canvas)

    -- texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(f)
    tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\upgrade.tga")

    -- animation
    local ag = f:CreateAnimationGroup()
    canvas.ag = ag

    local a1 = ag:CreateAnimation("Alpha")
    a1.duration = 0.5
    a1:SetFromAlpha(0)
    a1:SetToAlpha(1)
    a1:SetOrder(1)
    a1:SetDuration(a1.duration)
    a1:SetSmoothing("OUT")

    local t1 = ag:CreateAnimation("Translation")
    t1.duration = 0.5
    t1:SetOrder(1)
    t1:SetSmoothing("OUT")
    t1:SetDuration(t1.duration)

    local a2 = ag:CreateAnimation("Alpha")
    a2.duration = 0.5
    a2:SetFromAlpha(1)
    a2:SetToAlpha(0)
    a2:SetDuration(a2.duration)
    a2:SetOrder(2)
    a2:SetSmoothing("IN")

    ag:SetScript("OnPlay", function()
        canvas:Show()
    end)

    ag:SetScript("OnFinished", function()
        animationPool.C:Release(canvas)
    end)

    function ag:Display(parent, subType, r, g, b)
        canvas:SetParent(parent)
        canvas:SetAllPoints(parent)

        f:ClearAllPoints()
        -- subType 决定图标在框体上的水平锚点位置：
        -- "1" = 左对齐 (BOTTOMLEFT/LEFT), "2" = 居中 (BOTTOM/CENTER), 其他 = 右对齐 (BOTTOMRIGHT/RIGHT)
        if subType == "1" then
            f:SetPoint("BOTTOMLEFT")
            f:SetPoint("TOPLEFT", canvas, "LEFT")
        elseif subType == "2" then
            f:SetPoint("BOTTOM")
            f:SetPoint("TOP", canvas, "CENTER")
        else
            f:SetPoint("BOTTOMRIGHT")
            f:SetPoint("TOPRIGHT", canvas, "RIGHT")
        end

        a1:SetDuration(a1.duration / parent.speed)
        t1:SetDuration(t1.duration / parent.speed)
        a2:SetDuration(a2.duration / parent.speed)

        -- 图标宽度为框体高度的一半，保持宽高比
        f:SetWidth(canvas:GetHeight() / 2)
        -- 平移量：向上移动框体高度的一半
        t1:SetOffset(0, canvas:GetHeight() / 2)
        tex:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 1))

        if ag:IsPlaying() then
            ag:Restart()
        else
            ag:Play()
        end
    end

    return canvas
end

animationPool.C = CreateObjectPool(CreateAnimationGroup_TypeC, ResetterFunc)

-------------------------------------------------
-- animation: D
-------------------------------------------------

-- ============================================================================
-- 动画类型 D：圆形扩散脉冲 (Circle Expansion Pulse)
-- 效果：一个圆形图案从框体中心向外缩放扩散，淡入后淡出消失。
-- 圆形尺寸根据父框体的对角线长度自动计算（取宽高平方和的平方根 × 2）。
-- 双遮罩设计：mask1 (circle_filled_256) 限定圆形形状，mask2 (白纹理) 限定在框体可视区域内。
-- 动画序列：Alpha 淡入(0→1, OUT) + Scale(0→1) + Alpha 淡出(1→0, IN)
-- ============================================================================
local function CreateAnimationGroup_TypeD()
    local canvas = CreateFrame("Frame")

    -- frame
    local f = CreateFrame("Frame", nil, canvas)
    f:SetAllPoints(canvas)

    -- texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("CENTER")

    -- mask1: 圆形形状遮罩，将纹理裁剪为圆形
    local mask1 = f:CreateMaskTexture()
    mask1:SetAllPoints(tex)
    mask1:SetTexture("Interface/AddOns/Cell/Media/Shapes/circle_filled_256", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(mask1)

    -- mask2: 框体区域遮罩，限制圆形不会渲染到框体外部
    local mask2 = canvas:CreateMaskTexture()
    mask2:SetTexture(Cell.vars.whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask2:SetAllPoints(canvas)
    tex:AddMaskTexture(mask2)

    -- animation
    local ag = f:CreateAnimationGroup()
    canvas.ag = ag

    local a1 = ag:CreateAnimation("Alpha")
    a1.duration = 0.3
    a1:SetFromAlpha(0)
    a1:SetToAlpha(1)
    a1:SetOrder(1)
    a1:SetDuration(a1.duration)
    a1:SetSmoothing("OUT")

    -- Scale 缩放：从 (0,0) 缩放到原始大小 (1,1)，实现扩散效果
    local s1 = ag:CreateAnimation("Scale")
    s1.duration = 0.5
    s1:SetScaleFrom(0, 0)
    s1:SetScaleTo(1, 1)
    s1:SetOrder(1)
    s1:SetDuration(s1.duration)

    local a2 = ag:CreateAnimation("Alpha")
    a2.duration = 0.5
    a2:SetFromAlpha(1)
    a2:SetToAlpha(0)
    a2:SetDuration(a2.duration)
    a2:SetOrder(2)
    a2:SetSmoothing("IN")

    ag:SetScript("OnPlay", function()
        canvas:Show()
    end)

    ag:SetScript("OnFinished", function()
        animationPool.D:Release(canvas)
    end)

    function ag:Display(parent, r, g, b)
        canvas:SetParent(parent)
        canvas:SetAllPoints(parent)

        a1:SetDuration(a1.duration / parent.speed)
        s1:SetDuration(s1.duration / parent.speed)
        a2:SetDuration(a2.duration / parent.speed)

        -- 圆的直径 = 父框体对角线长度 × 2，确保缩放扩散时圆形能覆盖整个框体
        -- 父框体的父框体才是实际的 unitButton
        local l = math.sqrt((parent:GetParent():GetHeight() / 2) ^ 2 + (parent:GetParent():GetWidth() / 2) ^ 2) * 2
        tex:SetSize(l, l)
        tex:SetColorTexture(r, g, b, 0.6)

        if ag:IsPlaying() then
            ag:Restart()
        else
            ag:Play()
        end
    end

    return canvas
end

animationPool.D = CreateObjectPool(CreateAnimationGroup_TypeD, ResetterFunc)

-------------------------------------------------
-- animation: E
-------------------------------------------------

-- ============================================================================
-- 动画类型 E：箭头扫过 (Arrow Sweep)
-- 效果：使用 Cell 内置的 arrow.tga 贴图，从框体左侧水平滑入至右侧消失，
-- 带 IN_OUT 缓动效果。纹理保持半透明 (alpha=0.6)，无淡入淡出，仅平移。
-- 平移距离 = 箭头纹理宽度 (框体高度 × 2) + 框体宽度。
-- 动画序列：Translation(水平平移, IN_OUT 缓动)
-- ============================================================================
local function CreateAnimationGroup_TypeE()
    local canvas = CreateFrame("Frame")

    -- frame
    local f = CreateFrame("Frame", nil, canvas)
    f:SetPoint("TOPRIGHT", canvas, "TOPLEFT")
    f:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMLEFT")

    -- texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(f)
    tex:SetTexture("Interface/AddOns/Cell/Media/Icons/arrow.tga")

    -- mask
    local mask = canvas:CreateMaskTexture()
    mask:SetTexture(Cell.vars.whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(canvas)
    -- frame:SetSnapToPixelGrid(false)
    -- frame:SetTexelSnappingBias(0)
    tex:AddMaskTexture(mask)

    -- animation
    local ag = f:CreateAnimationGroup()
    canvas.ag = ag

    -- Alpha 淡入动画 (已注释): 原计划带淡入效果，当前仅使用平移实现简洁的箭头飞过效果
    -- local a1 = ag:CreateAnimation("Alpha")
    -- a1:SetFromAlpha(0)
    -- a1:SetToAlpha(0.7)
    -- a1:SetDuration(0.3)
    -- a1:SetSmoothing("OUT")

    local t1 = ag:CreateAnimation("Translation")
    t1.duration = 0.8
    t1:SetSmoothing("IN_OUT")
    t1:SetDuration(t1.duration)

    -- Alpha 淡出动画 (已注释): 原计划平移结束后淡出，当前由平移自然消失替代
    -- local a2 = ag:CreateAnimation("Alpha")
    -- a2:SetFromAlpha(0.7)
    -- a2:SetToAlpha(0)
    -- a2:SetDuration(0.3)
    -- a2:SetStartDelay(0.5)
    -- a2:SetSmoothing("IN")

    ag:SetScript("OnPlay", function()
        canvas:Show()
    end)

    ag:SetScript("OnFinished", function()
        animationPool.E:Release(canvas)
    end)

    function ag:Display(parent, r, g, b)
        canvas:SetParent(parent)
        canvas:SetAllPoints(parent)

        t1:SetDuration(t1.duration / parent.speed)

        -- 箭头宽度 = 框体高度 × 2，保持宽高比
        local l = canvas:GetHeight() * 2
        f:SetWidth(l)
        -- 平移距离：箭头自身宽度 + 框体宽度，确保箭头完全移出视野
        t1:SetOffset(l + canvas:GetWidth(), 0)

        -- 使用 SetVertexColor 设置颜色（无渐变），alpha 固定 0.6
        tex:SetVertexColor(r, g, b, 0.6)

        if ag:IsPlaying() then
            ag:Restart()
        else
            ag:Play()
        end
    end

    return canvas
end

animationPool.E = CreateObjectPool(CreateAnimationGroup_TypeE, ResetterFunc)

-------------------------------------------------
-- animation: F
-------------------------------------------------

-- ============================================================================
-- 动画类型 F：心形扩散脉冲 (Heart Expansion Pulse)
-- 效果：与类型 D (圆形扩散) 类似，但使用 heart_filled_256 遮罩形成心形图案。
-- 从框体中心向外缩放扩散，淡入后淡出消失。
-- 尺寸取父框体宽高中的较大者 × 2。
-- 双遮罩设计：mask1 (heart_filled_256) 限定心形形状，mask2 (白纹理) 限定在框体可视区域内。
-- 动画序列：Alpha 淡入(0→1, OUT) + Scale(0→1) + Alpha 淡出(1→0, IN)
-- ============================================================================
local function CreateAnimationGroup_TypeF()
    local canvas = CreateFrame("Frame")

    -- frame
    local f = CreateFrame("Frame", nil, canvas)
    f:SetAllPoints(canvas)

    -- texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("CENTER")

    -- mask1: 心形形状遮罩，将纹理裁剪为心形
    local mask1 = f:CreateMaskTexture()
    mask1:SetAllPoints(tex)
    mask1:SetTexture("Interface/AddOns/Cell/Media/Shapes/heart_filled_256", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(mask1)

    -- mask2: 框体区域遮罩，限制心形不会渲染到框体外部
    local mask2 = canvas:CreateMaskTexture()
    mask2:SetTexture(Cell.vars.whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask2:SetAllPoints(canvas)
    tex:AddMaskTexture(mask2)

    -- animation
    local ag = f:CreateAnimationGroup()
    canvas.ag = ag

    local a1 = ag:CreateAnimation("Alpha")
    a1.duration = 0.3
    a1:SetFromAlpha(0)
    a1:SetToAlpha(1)
    a1:SetOrder(1)
    a1:SetDuration(a1.duration)
    a1:SetSmoothing("OUT")

    local s1 = ag:CreateAnimation("Scale")
    s1.duration = 0.5
    s1:SetScaleFrom(0, 0)
    s1:SetScaleTo(1, 1)
    s1:SetOrder(1)
    s1:SetDuration(s1.duration)

    local a2 = ag:CreateAnimation("Alpha")
    a2.duration = 0.5
    a2:SetFromAlpha(1)
    a2:SetToAlpha(0)
    a2:SetDuration(a2.duration)
    a2:SetOrder(2)
    a2:SetSmoothing("IN")

    ag:SetScript("OnPlay", function()
        canvas:Show()
    end)

    ag:SetScript("OnFinished", function()
        animationPool.F:Release(canvas)
    end)

    function ag:Display(parent, r, g, b)
        canvas:SetParent(parent)
        canvas:SetAllPoints(parent)

        a1:SetDuration(a1.duration / parent.speed)
        s1:SetDuration(s1.duration / parent.speed)
        a2:SetDuration(a2.duration / parent.speed)

        -- 心形尺寸取父框体宽高中的较大者 × 2，确保心形能覆盖整个框体
        local l = max(parent:GetParent():GetWidth(), parent:GetParent():GetHeight()) * 2
        tex:SetSize(l, l)
        tex:SetColorTexture(r, g, b, 0.6)

        if ag:IsPlaying() then
            ag:Restart()
        else
            ag:Play()
        end
    end

    return canvas
end

animationPool.F = CreateObjectPool(CreateAnimationGroup_TypeF, ResetterFunc)

-------------------------------------------------
-- animation: G
-------------------------------------------------

-- ============================================================================
-- 动画类型 G：顶部渐变条 (Top Gradient Bar)
-- 效果：框体上半部分显示一条从透明到实色的垂直渐变条（上透明→下实色），
-- 淡入后保持片刻再淡出。无平移效果，仅纯 Alpha 动画。
-- 渐变条高度为框体高度的一半，宽度充满框体全宽。
-- 动画序列：Alpha 淡入(0→1, OUT) + Alpha 淡出(1→0, IN)
-- ============================================================================
local function CreateAnimationGroup_TypeG()
    local canvas = CreateFrame("Frame")

    -- frame: 锚定在框体顶部，高度为框体的一半
    local f = CreateFrame("Frame", nil, canvas)
    f:SetPoint("TOPLEFT", canvas)
    f:SetPoint("TOPRIGHT", canvas)

    -- texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(f)
    tex:SetTexture(Cell.vars.whiteTexture)

    -- animation
    local ag = f:CreateAnimationGroup()
    canvas.ag = ag

    local a1 = ag:CreateAnimation("Alpha")
    a1.duration = 0.5
    a1:SetFromAlpha(0)
    a1:SetToAlpha(1)
    a1:SetOrder(1)
    a1:SetDuration(a1.duration)
    a1:SetSmoothing("OUT")

    local a2 = ag:CreateAnimation("Alpha")
    a2.duration = 0.5
    a2:SetFromAlpha(1)
    a2:SetToAlpha(0)
    a2:SetDuration(a2.duration)
    a2:SetOrder(2)
    a2:SetSmoothing("IN")

    ag:SetScript("OnPlay", function()
        canvas:Show()
    end)

    ag:SetScript("OnFinished", function()
        animationPool.G:Release(canvas)
    end)

    function ag:Display(parent, r, g, b)
        canvas:SetParent(parent)
        canvas:SetAllPoints(parent)

        -- 渐变条高度 = 框体高度 / 2，仅覆盖上半部分
        f:SetHeight(canvas:GetHeight() / 2)

        -- 垂直渐变：从顶部透明过渡到底部实色
        tex:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 1))

        a1:SetDuration(a1.duration / parent.speed)
        a2:SetDuration(a2.duration / parent.speed)

        if ag:IsPlaying() then
            ag:Restart()
        else
            ag:Play()
        end
    end

    return canvas
end

animationPool.G = CreateObjectPool(CreateAnimationGroup_TypeG, ResetterFunc)

-------------------------------------------------
-- indicator
-------------------------------------------------

-- ============================================================================
-- 指示器集成层 (Indicator Integration Layer)
-- 将七种动画对象池与 Cell 的指示器框架对接，提供 Display/SetSpeed 公共接口。
-- ============================================================================

-- 预览模式按钮引用表：存储所有选项界面预览中的按钮引用，用于同步 orientation 变更
local previews = {}
-- 预览模式下的当前 bar 朝向，用于判断是否需要更新所有预览按钮
local previewOrientation

-- 设置动画播放速度倍率
-- speed 越大动画越快：实际 duration = 基础 duration / speed
local function Actions_SetSpeed(self, speed)
    self.speed = speed
end

-- 触发动画播放 (Actions 指示器的核心接口)
-- animationType: 动画类型字符串，如 "A"、"B"、"C1"、"C2"、"C3"、"D"、"E"、"F"、"G"
-- color: {r, g, b} 颜色表 (0~1 范围的 RGB 分量)
local function Actions_Display(self, animationType, color)
    -- animations[animationType]:Display(unpack(color))
    -- 动画类型 C 特殊处理：从 animationType 字符串中提取子类型数字
    -- 正则 ^C 匹配以 "C" 开头，%d 提取紧跟的数字字符
    -- 例如 "C1" -> subType="1"（左对齐），"C2" -> subType="2"（居中），"C3" -> subType="3"（右对齐）
    if strfind(animationType, "^C") then
        local subType = strmatch(animationType, "%d")
        local canvas = animationPool.C:Acquire()
        canvas.ag:Display(self, subType, color[1], color[2], color[3])
    else
        local canvas = animationPool[animationType]:Acquire()
        canvas.ag:Display(self, color[1], color[2], color[3])
    end
end

-- 为指定父框体创建 Actions 指示器实例 (工厂方法)
-- parent: 按钮/框体对象
-- isPreview: 是否为选项界面预览模式
--   预览模式：actions 直接锚定到 parent，便于在选项面板中独立展示预览效果
--   正常模式：actions 锚定到 parent.widgets.healthBar，覆盖在血条上播放动画
function I.CreateActions(parent, isPreview)
    local actions = CreateFrame("Frame", parent:GetName() .. "ActionsParent", isPreview and parent or parent.widgets.indicatorFrame)

    if isPreview then
        parent.actions = actions
        -- 注册到 previews 表，便于 orientation 变更时批量同步
        tinsert(previews, parent)
        actions:SetPoint("TOPLEFT", 1, -1)
        actions:SetPoint("BOTTOMRIGHT", -1, 1)
        actions.orientation = previewOrientation
    else
        parent.indicators.actions = actions
        actions:SetAllPoints(parent.widgets.healthBar)
    end

    -- 初始化默认速度倍率为 1（正常速度）
    actions.speed = 1
    -- 绑定公共方法
    actions.SetSpeed = Actions_SetSpeed
    actions.Display = Actions_Display
end

-- 更新 Actions 指示器的朝向 (水平/垂直)
-- 当 Bar 朝向改变时（如玩家切换布局），同步更新所有按钮及预览中的 orientation
function I.UpdateActionsOrientation(button, barOrientation)
    button.indicators.actions.orientation = barOrientation

    -- 仅当预览朝向与新朝向不同时才遍历更新所有预览按钮，避免不必要的循环
    if previewOrientation ~= barOrientation then
        previewOrientation = barOrientation
        for _, p in pairs(previews) do
            p.actions.orientation = barOrientation
        end
    end
end

-- 启用/禁用 Actions 指示器的事件监听
-- 仅在用户启用 Actions 指示器时注册事件，禁用时注销以节省 CPU
function I.EnableActions(enabled)
    if enabled then
        eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    else
        eventFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end