local addonName, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs
---@class CellAnimations
local A = Cell.animations

-----------------------------------------
-- forked from ElvUI
-----------------------------------------
-- FADEFRAMES: 存储所有需要执行渐变效果的 frame 及其渐变参数
-- FADEMANAGER: 全局渐变管理帧，通过 OnUpdate 驱动所有渐变 frame 的 alpha 更新
-- FADEMANAGER.interval: OnUpdate 更新间隔（秒），控制渐变刷新频率
local FADEFRAMES, FADEMANAGER = {}, CreateFrame('FRAME')
FADEMANAGER.interval = 0.025

-----------------------------------------
-- fade manager onupdate
-----------------------------------------
-- Fading: 渐变管理器的 OnUpdate 回调，每 FADEMANAGER.interval 秒执行一次
-- 遍历 FADEFRAMES 中所有注册的 frame，根据渐变模式（淡入/淡出）计算并设置当前 alpha 值
-- 当某个 frame 的渐变计时器到达 timeToFade 时，将其 alpha 设为最终值并从 FADEFRAMES 中移除
-- 当 FADEFRAMES 为空时，停止 OnUpdate 循环以节省性能
local function Fading(_, elapsed)
    FADEMANAGER.timer = (FADEMANAGER.timer or 0) + elapsed

    if FADEMANAGER.timer > FADEMANAGER.interval then
        FADEMANAGER.timer = 0

        for frame, info in next, FADEFRAMES do
            if frame:IsVisible() then
                info.fadeTimer = (info.fadeTimer or 0) + (elapsed + FADEMANAGER.interval)
            else -- 隐藏状态的 frame 加速完成渐变（跳过计时直接标记为完成）
                info.fadeTimer = info.timeToFade + 1
            end

            if info.fadeTimer < info.timeToFade then
                if info.mode == 'IN' then
                    -- 淡入：alpha 从 startAlpha 线性过渡到 endAlpha
                    frame:SetAlpha((info.fadeTimer / info.timeToFade) * info.diffAlpha + info.startAlpha)
                else
                    -- 淡出：alpha 从 startAlpha 线性过渡到 endAlpha
                    frame:SetAlpha(((info.timeToFade - info.fadeTimer) / info.timeToFade) * info.diffAlpha + info.endAlpha)
                end
            else
                -- 渐变完成：设置最终 alpha 值并从管理表中移除
                frame:SetAlpha(info.endAlpha)
                -- NOTE: remove from FADEFRAMES
                if frame and FADEFRAMES[frame] then
                    if frame.fade then
                        frame.fade.fadeTimer = nil
                    end
                    FADEFRAMES[frame] = nil
                end
            end
        end

        if not next(FADEFRAMES) then
            -- 所有渐变完成，停止 OnUpdate 循环
            -- print("FINISHED FADING!")
            FADEMANAGER:SetScript('OnUpdate', nil)
        end
    end
end

-----------------------------------------
-- fade
-----------------------------------------
-- FrameFade: 内部渐变启动函数，将 frame 和渐变信息注册到 FADEFRAMES 管理表
-- @param frame: 需要执行渐变的 UI frame
-- @param info: 渐变参数表，包含 mode、timeToFade、startAlpha、endAlpha、diffAlpha 等
-- 非保护状态的 frame 会自动调用 Show()，受保护 frame 需由外部自行处理显示
local function FrameFade(frame, info)
    frame:SetAlpha(info.startAlpha)

    if not frame:IsProtected() then
        frame:Show()
    end

    if not FADEFRAMES[frame] then
        -- 首次注册该 frame 时启动 OnUpdate 循环
        FADEFRAMES[frame] = info
        FADEMANAGER:SetScript('OnUpdate', Fading)
    else
        -- 已在管理表中则更新参数（会覆盖正在进行的渐变）
        FADEFRAMES[frame] = info
    end
end

-- A.FrameFadeIn: 对指定 frame 执行淡入动画（alpha 从 startAlpha 过渡到 endAlpha）
-- @param frame: 目标 frame
-- @param timeToFade: 渐变持续时间（秒）
-- @param startAlpha: 起始透明度（0=完全透明, 1=完全不透明）
-- @param endAlpha: 结束透明度
-- 在 frame 上创建或复用 frame.fade 表存储渐变参数
function A.FrameFadeIn(frame, timeToFade, startAlpha, endAlpha)
    if frame.fade then
        -- 如果已有进行中的渐变，先清空计时器以中断它
        frame.fade.fadeTimer = nil
    else
        frame.fade = {}
    end

    frame.fade.mode = 'IN'
    frame.fade.timeToFade = timeToFade
    frame.fade.startAlpha = startAlpha
    frame.fade.endAlpha = endAlpha
    frame.fade.diffAlpha = endAlpha - startAlpha

    FrameFade(frame, frame.fade)
end

-- A.FrameFadeOut: 对指定 frame 执行淡出动画（alpha 从 startAlpha 过渡到 endAlpha）
-- @param frame: 目标 frame
-- @param timeToFade: 渐变持续时间（秒）
-- @param startAlpha: 起始透明度
-- @param endAlpha: 结束透明度
-- 注：diffAlpha 使用 startAlpha - endAlpha，与淡入方向相反
function A.FrameFadeOut(frame, timeToFade, startAlpha, endAlpha)
    if frame.fade then
        -- 如果已有进行中的渐变，先清空计时器以中断它
        frame.fade.fadeTimer = nil
    else
        frame.fade = {}
    end

    frame.fade.mode = 'OUT'
    frame.fade.timeToFade = timeToFade
    frame.fade.startAlpha = startAlpha
    frame.fade.endAlpha = endAlpha
    frame.fade.diffAlpha = startAlpha - endAlpha

    FrameFade(frame, frame.fade)
end

-----------------------------------------
-- fade in/out on mouseover/mouseout
-----------------------------------------
-- A.ApplyFadeInOutToParent: 给一组子 frame 绑定鼠标悬停的淡入淡出效果
-- 当鼠标进入任一子 frame 时，父 frame 淡入到 alpha=1
-- 当鼠标离开任一子 frame 时，父 frame 淡出到 alpha=0
-- @param parent: 需要渐变效果的父 frame
-- @param condition: 条件函数，返回 true 时才执行渐变（用于根据设置开关此行为）
-- @param ...: 可变数量子 frame，它们的 OnEnter/OnLeave 事件会被 Hook
-- SetHitRectInsets(-2,-2,-2,-2) 将命中区域向外扩展 2 像素，使鼠标更容易触发事件
function A.ApplyFadeInOutToParent(parent, condition, ...)
    for _, f in pairs({...}) do
        f:SetHitRectInsets(-2, -2, -2, -2)

        f:HookScript("OnEnter", function()
            if condition() then
                A.FrameFadeIn(parent, 0.25, parent:GetAlpha(), 1)
            end
        end)

        f:HookScript("OnLeave", function()
            if condition() then
                A.FrameFadeOut(parent, 0.25, parent:GetAlpha(), 0)
            end
        end)
    end
end

-----------------------------------------
-- add fade in/out
-----------------------------------------
-- A.CreateFadeIn: 使用 AnimationGroup 为 frame 创建淡入动画
-- 生成的动画存储在 frame.fadeIn 中，并为 frame 添加 FadeIn() 方法
-- @param frame: 目标 frame
-- @param fromAlpha: 起始透明度
-- @param toAlpha: 结束透明度
-- @param duration: 动画持续时间（秒）
-- @param delay: （可选）动画开始前的延迟时间（秒）
-- @param onFinished: （可选）动画完成后的回调函数
-- OnPlay 回调会在淡入开始前自动停止正在进行的淡出动画，防止冲突
function A.CreateFadeIn(frame, fromAlpha, toAlpha, duration, delay, onFinished)
    local fadeIn = frame:CreateAnimationGroup()
    frame.fadeIn = fadeIn
    fadeIn.alpha = fadeIn:CreateAnimation("Alpha")
    fadeIn.alpha:SetFromAlpha(fromAlpha)
    fadeIn.alpha:SetToAlpha(toAlpha)
    fadeIn.alpha:SetDuration(duration)
    if delay then fadeIn.alpha:SetStartDelay(delay) end

    fadeIn:SetScript("OnPlay", function()
        -- 停止正在进行的淡出动画，避免同时淡入淡出
        if frame.fadeOut then
            frame.fadeOut:Stop()
        end
    end)

    if onFinished then
        fadeIn:SetScript("OnFinished", onFinished)
    end

    -- 为 frame 添加 FadeIn 方法，调用时先 Show() 再播放动画
    function frame:FadeIn()
        frame:Show()
        fadeIn:Play()
    end
end

-- A.CreateFadeOut: 使用 AnimationGroup 为 frame 创建淡出动画
-- 生成的动画存储在 frame.fadeOut 中，并为 frame 添加 FadeOut() 方法
-- @param frame: 目标 frame
-- @param fromAlpha: 起始透明度
-- @param toAlpha: 结束透明度
-- @param duration: 动画持续时间（秒）
-- @param delay: （可选）动画开始前的延迟时间（秒）
-- @param onFinished: （可选）动画完成后的回调函数（若不提供则默认调用 frame:Hide()）
-- OnPlay 回调会在淡出开始前自动停止正在进行的淡入动画，防止冲突
function A.CreateFadeOut(frame, fromAlpha, toAlpha, duration, delay, onFinished)
    local fadeOut = frame:CreateAnimationGroup()
    frame.fadeOut = fadeOut
    fadeOut.alpha = fadeOut:CreateAnimation("Alpha")
    fadeOut.alpha:SetFromAlpha(fromAlpha)
    fadeOut.alpha:SetToAlpha(toAlpha)
    fadeOut.alpha:SetDuration(duration)
    if delay then fadeOut.alpha:SetStartDelay(delay) end

    fadeOut:SetScript("OnPlay", function()
        -- 停止正在进行的淡入动画，避免同时淡入淡出
        if frame.fadeIn then
            frame.fadeIn:Stop()
        end
    end)

    if onFinished then
        fadeOut:SetScript("OnFinished", onFinished)
    else
        -- 默认行为：淡出完成后隐藏 frame
        fadeOut:SetScript("OnFinished", function()
            frame:Hide()
        end)
    end

    -- 为 frame 添加 FadeOut 方法，调用时直接播放动画
    function frame:FadeOut()
        fadeOut:Play()
    end
end

-----------------------------------------
-- apply fade in/out to menu
-----------------------------------------
-- A.ApplyFadeInOutToMenu: 为菜单类 frame 创建进出淡入淡出动画系统
-- 根据 CellDB["general"]["fadeOut"] 设置决定是否启用淡出行为
-- 使用四个状态变量跟踪动画状态：
--   fadingIn: 淡入动画进行中
--   fadedIn: 淡入已完成（anchorFrame 完全显示）
--   fadingOut: 淡出动画进行中
--   fadedOut: 淡出已完成（anchorFrame 完全隐藏）
-- @param anchorFrame: 需要淡入淡出效果的目标 frame（菜单本体）
-- @param hoverFrame: 用于判断鼠标悬停的检测 frame
-- 动画参数：duration=0.5秒，Smoothing="OUT"（缓出效果，动画开始时较快）
function A.ApplyFadeInOutToMenu(anchorFrame, hoverFrame)
    -- 四个布尔状态变量跟踪动画的当前所处阶段
    local fadingIn, fadedIn, fadingOut, fadedOut

    -- 创建淡入动画组
    anchorFrame.fadeIn = anchorFrame:CreateAnimationGroup()
    anchorFrame.fadeIn.alpha = anchorFrame.fadeIn:CreateAnimation("alpha")
    anchorFrame.fadeIn.alpha:SetFromAlpha(0)
    anchorFrame.fadeIn.alpha:SetToAlpha(1)
    anchorFrame.fadeIn.alpha:SetDuration(0.5)
    anchorFrame.fadeIn.alpha:SetSmoothing("OUT")
    anchorFrame.fadeIn:SetScript("OnPlay", function()
        -- 立即结束正在进行的淡出动画，标记为淡入中
        anchorFrame.fadeOut:Finish()
        fadingIn = true
    end)
    anchorFrame.fadeIn:SetScript("OnFinished", function()
        fadingIn = false
        fadingOut = false
        fadedIn = true
        fadedOut = false
        anchorFrame:SetAlpha(1)

        -- 淡入完成后，若开启了淡出设置且鼠标已离开 hoverFrame，立即开始淡出
        if CellDB["general"]["fadeOut"] and not hoverFrame:IsMouseOver() then
            anchorFrame.fadeOut:Play()
        end
    end)

    -- 创建淡出动画组
    anchorFrame.fadeOut = anchorFrame:CreateAnimationGroup()
    anchorFrame.fadeOut.alpha = anchorFrame.fadeOut:CreateAnimation("alpha")
    anchorFrame.fadeOut.alpha:SetFromAlpha(1)
    anchorFrame.fadeOut.alpha:SetToAlpha(0)
    anchorFrame.fadeOut.alpha:SetDuration(0.5)
    anchorFrame.fadeOut.alpha:SetSmoothing("OUT")
    anchorFrame.fadeOut:SetScript("OnPlay", function()
        -- 立即结束正在进行的淡入动画，标记为淡出中
        anchorFrame.fadeIn:Finish()
        fadingOut = true
    end)
    anchorFrame.fadeOut:SetScript("OnFinished", function()
        fadingIn = false
        fadingOut = false
        fadedIn = false
        fadedOut = true
        anchorFrame:SetAlpha(0)

        -- 淡出完成后，若鼠标重新进入 hoverFrame，立即开始淡入
        if hoverFrame:IsMouseOver() then
            anchorFrame.fadeIn:Play()
        end
    end)

    -- hoverFrame 鼠标进入事件：若未在淡入中且未完全显示，则触发淡入
    hoverFrame:SetScript("OnEnter", function()
        if not CellDB["general"]["fadeOut"] then return end
        if not (fadingIn or fadedIn) then
            anchorFrame.fadeIn:Play()
        end
    end)
    -- hoverFrame 鼠标离开事件：若未在淡出中且未完全隐藏，则触发淡出
    hoverFrame:SetScript("OnLeave", function()
        if not CellDB["general"]["fadeOut"] then return end
        if hoverFrame:IsMouseOver() then return end
        if not (fadingOut or fadedOut) then
            anchorFrame.fadeOut:Play()
        end
    end)
end

-----------------------------------------
-- blink
-----------------------------------------
-- A.CreateBlinkAnimation: 为 UI 区域（region）创建闪烁动画（alpha 在 0.25 和 1 之间往复）
-- @param region: 需要有闪烁效果的 UI 区域（通常是 Texture 或 Frame）
-- @param duration: （可选）单次闪烁周期时长（秒），默认 0.5
-- @param enableShowHideHook: 是否绑定 OnShow/OnHide 自动控制动画播放/停止
--   - true: 当 region 显示时自动播放闪烁，隐藏时自动停止
--   - false: 立即开始播放闪烁
-- SetLooping("BOUNCE") 使 alpha 在 0.25→1→0.25 之间来回循环，产生脉冲闪烁效果
function A.CreateBlinkAnimation(region, duration, enableShowHideHook)
    local blink = region:CreateAnimationGroup()
    region.blink = blink

    local alpha = blink:CreateAnimation("Alpha")
    blink.alpha = alpha
    alpha:SetFromAlpha(0.25)
    alpha:SetToAlpha(1)
    alpha:SetDuration(duration or 0.5)

    blink:SetLooping("BOUNCE")

    if enableShowHideHook then
        -- 绑定 OnShow/OnHide 事件：显示时自动播放，隐藏时自动停止
        region:HookScript("OnShow", function()
            blink:Play()
        end)
        region:HookScript("OnHide", function()
            blink:Stop()
        end)
    else
        blink:Play()
    end
end