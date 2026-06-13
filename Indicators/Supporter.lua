local _, Cell = ...
local F = Cell.funcs
local A = Cell.animations

-- ================================================================================
-- Supporter.lua - 支持者/赞助者指示器模块
-- 职责：根据 Cell.wowSupporters 注册表，在小队/团队成员的单元按钮上展示
--       感谢动画效果。支持三种等级：
--       - true:  普通赞助者（星星旋转缩放动画）
--       - "mvp": MVP 赞助者（逐帧动画翻页书）
--       - "goat": GOAT 顶级赞助者（逐帧动画翻页书）
-- 使用对象池 (ObjectPool) 复用动画帧，避免频繁创建/销毁
-- ================================================================================

-------------------------------------------------
-- pool -- 普通赞助者动画对象池（星星图标）
-------------------------------------------------
local pool

-- ------------------------------------------------------------------
-- creationFunc -- 普通赞助者动画帧的创建函数（供对象池回调）
-- 构建一个包含"进场→主体→退场"三阶段合成动画的 Frame
-- ------------------------------------------------------------------
local function creationFunc()
    local f = CreateFrame("Frame")
    f:Hide()

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface/AddOns/Cell/Media/star.png")
    tex:SetAllPoints(f)

    local ag = f:CreateAnimationGroup()
    -- 动画播放完毕回调：若帧仍在池中活跃，则回收（对象池复用）
    ag:SetScript("OnFinished", function()
        if pool:IsActive(f) then
            pool:Release(f)
        end
    end)

    -- in -------------------------------------------------------------------- --
    -- 阶段1: 进场动画 —— 星星从(0,0)缩放旋转淡入到正常大小
    local in_t = ag:CreateAnimation("Translation")
    in_t:SetOrder(1)
    in_t:SetDuration(0.3)
    in_t:SetSmoothing("IN_OUT")

    local in_s = ag:CreateAnimation("Scale")
    in_s:SetOrder(1)
    in_s:SetScaleFrom(0, 0)
    in_s:SetScaleTo(1, 1)
    in_s:SetDuration(0.3)

    local in_a = ag:CreateAnimation("Alpha")
    in_a:SetOrder(1)
    in_a:SetFromAlpha(0)
    in_a:SetToAlpha(1)
    in_a:SetDuration(0.3)

    local in_spinning = ag:CreateAnimation("Rotation")
    in_spinning:SetOrder(1)
    in_spinning:SetDegrees(-360)
    in_spinning:SetDuration(0.5)
    in_spinning:SetEndDelay(0.5)

    -- main ------------------------------------------------------------------ --
    -- 阶段2: 主体动画 —— 两次上下弹跳 + 放大，产生"欢快跳跃"的视觉效果
    local main_s1 = ag:CreateAnimation("Scale")
    main_s1:SetOrder(2)
    main_s1:SetScaleTo(1.25, 1.25)
    main_s1:SetDuration(0.2)

    local main_t1 = ag:CreateAnimation("Translation")
    main_t1:SetOffset(0, 5)
    main_t1:SetDuration(0.1)
    main_t1:SetOrder(2)
    main_t1:SetSmoothing("OUT")

    local main_t2 = ag:CreateAnimation("Translation")
    main_t2:SetOffset(0, -5)
    main_t2:SetDuration(0.1)
    main_t2:SetOrder(2)
    main_t2:SetSmoothing("IN")
    main_t2:SetStartDelay(0.1)
    main_t2:SetEndDelay(0.25)

    local main_s2 = ag:CreateAnimation("Scale")
    main_s2:SetOrder(3)
    main_s2:SetScaleTo(1.25, 1.25)
    main_s2:SetDuration(0.2)

    local main_t3 = ag:CreateAnimation("Translation")
    main_t3:SetOffset(0, 5)
    main_t3:SetDuration(0.1)
    main_t3:SetOrder(3)
    main_t3:SetSmoothing("OUT")

    local main_t4 = ag:CreateAnimation("Translation")
    main_t4:SetOffset(0, -5)
    main_t4:SetDuration(0.1)
    main_t4:SetOrder(3)
    main_t4:SetSmoothing("IN")
    main_t4:SetStartDelay(0.1)
    main_t4:SetEndDelay(0.5)

    -- out ------------------------------------------------------------------- --
    -- 阶段3: 退场动画 —— 星星旋转缩小淡出，动画结束后回收到对象池
    local out_s = ag:CreateAnimation("Scale")
    out_s:SetOrder(4)
    out_s:SetScaleTo(0, 0)
    out_s:SetDuration(0.5)
    out_s:SetSmoothing("IN")

    local out_spinning = ag:CreateAnimation("Rotation")
    out_spinning:SetOrder(4)
    out_spinning:SetDegrees(-360)
    out_spinning:SetDuration(0.5)

    local out_t = ag:CreateAnimation("Translation")
    out_t:SetOrder(4)
    out_t:SetStartDelay(0.2)
    out_t:SetDuration(0.3)
    out_t:SetSmoothing("IN_OUT")

    local out_a = ag:CreateAnimation("Alpha")
    out_a:SetOrder(4)
    out_a:SetFromAlpha(1)
    out_a:SetToAlpha(0)
    out_a:SetStartDelay(0.2)
    out_a:SetDuration(0.3)

    function f:Display(x, y)
        in_t:SetOffset(x, y)
        out_t:SetOffset(x, -y)
        f:Show()
        ag:Play()
    end

    return f
end

-- resetterFunc -- 对象池回收时的重置回调：隐藏帧
-- 注意：对象池回调签名为 (pool, frame)，此处忽略 pool
local function resetterFunc(_, f)
    f:Hide()
end

-- 创建普通赞助者对象池（creationFunc + resetterFunc）
pool = CreateObjectPool(creationFunc, resetterFunc)

-- ------------------------------------------------------------------
-- Display(b) -- 外部入口：在指定 unitButton 上展示普通赞助者动画
-- b: unitButton 对象，动画帧锚定在其 BOTTOMLEFT 角居中显示
-- 动画帧尺寸取按钮宽高中的较大值（最小 64）
-- ------------------------------------------------------------------
local function Display(b)
    local f = pool:Acquire()
    f:SetParent(b.widgets.indicatorFrame)
    -- f:SetFrameLevel(b:GetFrameLevel()+200)
    f:SetPoint("CENTER", b, "BOTTOMLEFT")

    local size = max(min(b:GetHeight(), b:GetWidth()), 64)
    f:SetSize(size, size)

    f:Display(ceil(b:GetWidth()/2), ceil(b:GetHeight()/2))
    -- f:FadeIn()
    -- C_Timer.After(3, f.FadeOut)
end

-------------------------------------------------
-- mvp pool -- MVP 赞助者动画对象池（逐帧翻页书动画）
-- 使用 FlipBook 动画 + 遮罩纹理，中心位置显示
-- 播放 3 秒后自动淡出回收
-------------------------------------------------
-- mvpPool 创建函数 —— 匿名内联，闭包捕获 pool 参数供淡出回调使用
local mvpPool = CreateObjectPool(function(pool)
    local f = CreateFrame("Frame")
    f:Hide()
    f:SetSize(128, 128)

    -- MVP 翻页书纹理（4 列 x 8 行，32 帧）
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface/AddOns/Cell/Media/FlipBooks/mvp.png")
    tex:SetAllPoints(f)
    tex:SetParentKey("Flipbook") -- 标记为 FlipBook 动画的子对象

    -- 遮罩纹理：用于控制翻页书显示区域（绑定到 indicatorFrame）
    local mask = f:CreateMaskTexture()
    f.mask = mask
    mask:SetTexture(Cell.vars.whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "TRILINEAR")
    tex:AddMaskTexture(mask)

    -- 翻页书动画组（循环播放）
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("REPEAT")

    local flip = ag:CreateAnimation("FlipBook")
    flip:SetDuration(2)          -- 2 秒播放全部 32 帧
    flip:SetFlipBookColumns(4)
    flip:SetFlipBookRows(8)
    flip:SetFlipBookFrames(32)
    flip:SetChildKey("Flipbook")

    -- OnShow: 启动动画 + 3 秒后触发淡出
    f:SetScript("OnShow", function()
        ag:Play()
        f.timer = C_Timer.NewTimer(3, f.FadeOut)
    end)

    -- 淡入/淡出动画（通过 Cell.animations 工厂创建）
    A.CreateFadeIn(f, 0, 1, 0.2)
    A.CreateFadeOut(f, 1, 0, 0.2, nil, function()
        f.timer = nil
        -- Midnight/SecretValue 防护：只在帧仍在池中时回收，避免重复释放
        if pool:IsActive(f) then
            pool:Release(f)
        end
    end)

    return f
end, function(_, f)
    -- 重置回调：取消定时器并隐藏帧
    if f.timer then
        f.timer:Cancel()
        f.timer = nil
    end
    f:Hide()
end)

-- ------------------------------------------------------------------
-- DisplayMVP(b) -- 外部入口：在指定 unitButton 上展示 MVP 赞助者动画
-- 帧居中定位，遮罩与 indicatorFrame 对齐
-- ------------------------------------------------------------------
local function DisplayMVP(b)
    local f = mvpPool:Acquire()
    f:SetParent(b.widgets.indicatorFrame)
    f:SetPoint("CENTER")
    f.mask:SetAllPoints(b.widgets.indicatorFrame)

    f:FadeIn()
end

-------------------------------------------------
-- goat pool -- GOAT 顶级赞助者动画对象池（逐帧翻页书动画）
-- 与 MVP 类似但使用不同的翻页书纹理和帧布局（8 列 x 8 行，52 帧）
-- 定位于 BOTTOMRIGHT，播放 3.8 秒后自动淡出回收
-------------------------------------------------
-- goatPool 创建函数 —— 匿名内联，闭包捕获 pool 参数供淡出回调使用
local goatPool = CreateObjectPool(function(pool)
    local f = CreateFrame("Frame")
    f:Hide()
    f:SetSize(128, 128)

    -- GOAT 翻页书纹理（8 列 x 8 行，52 帧）
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface/AddOns/Cell/Media/FlipBooks/goat.png")
    tex:SetAllPoints(f)
    tex:SetParentKey("Flipbook")

    -- 遮罩纹理（注意 GOAT 不使用 TRILINEAR 过滤，性能优先）
    local mask = f:CreateMaskTexture()
    f.mask = mask
    mask:SetTexture(Cell.vars.whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(mask)

    -- 翻页书动画组（循环播放）
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("REPEAT")

    local flip = ag:CreateAnimation("FlipBook")
    flip:SetDuration(2)          -- 2 秒播放全部 52 帧
    flip:SetFlipBookColumns(8)
    flip:SetFlipBookRows(8)
    flip:SetFlipBookFrames(52)
    flip:SetChildKey("Flipbook")

    -- OnShow: 启动动画 + 3.8 秒后触发淡出（比 MVP 多 0.8 秒）
    f:SetScript("OnShow", function()
        ag:Play()
        f.timer = C_Timer.NewTimer(3.8, f.FadeOut)
    end)

    A.CreateFadeIn(f, 0, 1, 0.2)
    A.CreateFadeOut(f, 1, 0, 0.2, nil, function()
        f.timer = nil
        -- Midnight/SecretValue 防护：只在帧仍在池中时回收，避免重复释放
        if pool:IsActive(f) then
            pool:Release(f)
        end
    end)

    return f
end, function(_, f)
    -- 重置回调：取消定时器并隐藏帧
    if f.timer then
        f.timer:Cancel()
        f.timer = nil
    end
    f:Hide()
end)

-- ------------------------------------------------------------------
-- DisplayGOAT(b) -- 外部入口：在指定 unitButton 上展示 GOAT 顶级赞助者动画
-- 帧定位于 BOTTOMRIGHT，遮罩与 indicatorFrame 对齐
-- ------------------------------------------------------------------
local function DisplayGOAT(b)
    local f = goatPool:Acquire()
    f:SetParent(b.widgets.indicatorFrame)
    f:SetPoint("BOTTOMRIGHT")
    f.mask:SetAllPoints(b.widgets.indicatorFrame)

    f:FadeIn()
end

-------------------------------------------------
-- events -- 事件处理：监听队伍变化，为赞助者展示动画
-------------------------------------------------
-- 事件帧：初始注册 FIRST_FRAME_RENDERED，之后切换为 GROUP_ROSTER_UPDATE
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("FIRST_FRAME_RENDERED")

-- 赞助者等级 -> 展示函数 映射表
-- Cell.wowSupporters[fullName] 的值为 true / "mvp" / "goat"
local displays = {
    [true] = Display,
    ["mvp"] = DisplayMVP,
    ["goat"] = DisplayGOAT,
}

-- ------------------------------------------------------------------
-- Check() -- 核心检查函数：遍历队伍成员，为赞助者展示对应动画
-- 流程：
--   1. 释放所有对象池中的活跃帧（清除旧动画）
--   2. 若在队伍中：遍历所有团队成员；若不在：仅检查自己
--   3. 对每个成员查询 Cell.wowSupporters 注册表
--   4. 命中则调用 F.HandleUnitButton 触发对应动画
-- ------------------------------------------------------------------
local function Check()
    -- 释放所有旧动画帧（避免重复显示）
    pool:ReleaseAll()
    mvpPool:ReleaseAll()
    goatPool:ReleaseAll()

    -- 调试用：强制将当前玩家标记为赞助者（已注释）
    -- Cell.wowSupporters[Cell.vars.playerNameFull] = true

    -- 在队伍中：遍历所有团队成员，检查赞助者注册表
    if IsInGroup() then
        for unit in F.IterateGroupMembers() do
            local fullName = F.UnitFullName(unit)
            -- Midnight 防护：Cell.wowSupporters[fullName] 可能为 nil（非赞助者）
            if Cell.wowSupporters[fullName] then
                F.HandleUnitButton("unit", unit, displays[Cell.wowSupporters[fullName]])
            end
        end
    else
        -- 不在队伍中：只检查玩家自身
        -- Midnight 防护：玩家名可能不在注册表中
        if Cell.wowSupporters[Cell.vars.playerNameFull] then
            F.HandleUnitButton("unit", "player", displays[Cell.wowSupporters[Cell.vars.playerNameFull]])
        end
    end
end

-- timer: 防抖定时器，5 秒延迟后执行 Check
-- members: 缓存的上次队伍人数，用于判断人数是否变化
local timer, members
eventFrame:SetScript("OnEvent", function(self, event)
    -- 首次加载：切换事件监听从 FIRST_FRAME_RENDERED 到 GROUP_ROSTER_UPDATE
    -- 确保 UI 完全加载后才开始监听队伍变化
    if event == "FIRST_FRAME_RENDERED" then
        eventFrame:UnregisterEvent("FIRST_FRAME_RENDERED")
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    end

    -- 取消之前的防抖定时器（队伍连续变化时重置等待）
    if timer then
        timer:Cancel()
        timer = nil
    end

    -- Midnight 防护：战斗中禁止执行 UI 操作（受暴雪安全限制）
    if InCombatLockdown() then return end

    -- 仅在队伍人数发生变化时才触发检查（避免无关事件重复触发）
    local newMembers = GetNumGroupMembers()
    if members ~= newMembers then
        members = newMembers
        timer = C_Timer.NewTimer(5, Check) -- 5 秒防抖延迟
    end
end)