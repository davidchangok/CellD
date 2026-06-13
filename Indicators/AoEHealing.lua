-- 引入 Cell 核心模块
-- Cell: 主表，包含核心数据、内部状态和配置
-- L: 本地化字符串表，用于多语言支持
-- F: 通用辅助函数集合（CellFuncs 类型），如 HandleUnitButton 等
-- I: 指示器专用函数集合（CellIndicatorFuncs 类型），如 IsAoEHealing、GetSummonDuration 等
local _, Cell = ...
local L = Cell.L
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs

-------------------------------------------------
-- CreateAoEHealing -- not support for npc
-------------------------------------------------
-- NOTE: This indicator relied on COMBAT_LOG_EVENT_UNFILTERED (SPELL_HEAL /
-- SPELL_PERIODIC_HEAL / SPELL_SUMMON) to detect AoE healing events.
-- COMBAT_LOG_EVENT_UNFILTERED is removed in Midnight (WoW 12.0.0).
-- When Cell.isMidnight is true the eventFrame is never registered, so no
-- flash animation will trigger. The indicator frame still exists and can be
-- re-enabled if a suitable non-CLEU API becomes available in a future build.

-- 内部辅助函数：触发指定单位按钮上的 AoE 治疗闪烁动画
-- @param b: 单位按钮对象（即 Cell 单元框架），通过 b.indicators.aoeHealing 访问指示器
-- 此函数作为回调传递给 F.HandleUnitButton，用于对受治疗单位所在的按钮执行动画
local function Display(b)
    b.indicators.aoeHealing:Display()
end

-- 创建独立的事件监听框架，用于监听战斗日志事件
-- 此框架与指示器框架分离，独立管理事件注册/注销生命周期
local eventFrame = CreateFrame("Frame")

-- Midnight 守卫：COMBAT_LOG_EVENT_UNFILTERED 事件在 WoW 12.0.0 中被移除
-- 当 Cell.isMidnight 为 true 时，跳过整个事件脚本设置，避免注册不存在的 API
if not Cell.isMidnight then
    -- 存储玩家召唤物的过期时间，键为召唤物 GUID，值为过期时间戳
    -- 用于追踪由玩家 AoE 法术召唤的临时单位（如宁静化身），其治疗效果也属于 AoE 治疗
    -- 数据结构：{ [destGUID] = expirationTime (GetTime() + duration) }
    local playerSummoned = {}
    eventFrame:SetScript("OnEvent", function()
        -- COMBAT_LOG_EVENT_UNFILTERED 事件参数（按 CombatLogGetCurrentEventInfo 返回顺序）：
        -- timestamp: 事件时间戳
        -- subevent: 子事件类型（SPELL_HEAL / SPELL_PERIODIC_HEAL / SPELL_SUMMON 等）
        -- sourceGUID: 施法者 GUID
        -- sourceName: 施法者名称
        -- sourceFlags: 施法者标识位
        -- sourceRaidFlags: 施法者团队标记
        -- destGUID: 目标 GUID
        -- destName: 目标名称
        -- destFlags: 目标标识位
        -- destRaidFlags: 目标团队标记
        -- spellId: 法术 ID
        -- spellName: 法术名称
        local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName = CombatLogGetCurrentEventInfo()
        -- if subevent == "SPELL_SUMMON" then print(subevent, sourceName, sourceGUID, destName, destGUID, spellName) end

        -- 处理法术召唤事件：当玩家施放的 AoE 治疗法术召唤出临时单位（如图腾、化身）时，
        -- 记录该召唤物 GUID 及其过期时间，后续该召唤物发出的治疗也将视为玩家的 AoE 治疗
        if subevent == "SPELL_SUMMON" then
            if sourceGUID == Cell.vars.playerGUID and destGUID and I.IsAoEHealing(spellName, spellId) then
                local duration = I.GetSummonDuration(spellName)
                if duration then
                    -- 记录召唤物过期时间并设置自动清理定时器
                    playerSummoned[destGUID] = GetTime() + duration -- expirationTime
                    C_Timer.After(duration, function()
                        playerSummoned[destGUID] = nil
                    end)
                end
            end
        end

        -- 处理治疗效果事件：判断治疗来源是否为玩家本人或玩家召唤物
        -- 若是，则通过 F.HandleUnitButton 找到目标单位所在的按钮并播放闪烁动画
        -- 安全说明：sourceGUID 和 destGUID 均来自游戏内置战斗日志系统，非用户输入，
        -- 此处仅用于 GUID 相等性比较和表键查找，无注入风险
        if subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
            if destGUID then
                -- 条件一：施法者是玩家本人且法术是 AoE 治疗法术
                -- 条件二：施法者是玩家的临时召唤物（已在 playerSummoned 表中注册）
                -- 注意：此处使用 playerSummoned[sourceGUID] 而非 Safe 安全函数，
                -- 因为 playerSummoned 表是模块内部私有表，仅由本函数写入 GUID 键，
                -- sourceGUID 来自系统 API，无用户可控性，不构成 secret value 风险
                if (sourceGUID == Cell.vars.playerGUID and I.IsAoEHealing(spellName, spellId)) or playerSummoned[sourceGUID] then
                    F.HandleUnitButton("guid", destGUID, Display)
                end
            end
        end
    end)
end

-- 创建 AoE 治疗指示器，为指定的单位按钮添加闪烁动画效果
-- 该指示器覆盖在血量条上方，当单位受到 AoE 治疗时会播放一次透明闪烁
-- @param parent: 单位按钮框架（Cell 单元框架实例），指示器将挂载到该按钮上
function I.CreateAoEHealing(parent)
    -- 创建指示器 Frame，命名规则为 "<按钮名>AoEHealing"，挂载到按钮的 indicatorFrame 容器中
    local aoeHealing = CreateFrame("Frame", parent:GetName().."AoEHealing", parent.widgets.indicatorFrame)
    -- 将指示器引用存入按钮的 indicators 表，供 Display 回调等访问
    parent.indicators.aoeHealing = aoeHealing
    -- 覆盖血量条区域：左上到右上，高度自适应
    aoeHealing:SetPoint("TOPLEFT", parent.widgets.healthBar)
    aoeHealing:SetPoint("TOPRIGHT", parent.widgets.healthBar)
    aoeHealing:Hide()

    -- 创建纹理对象，用于渲染渐变色彩
    aoeHealing.tex = aoeHealing:CreateTexture(nil, "ARTWORK")
    aoeHealing.tex:SetAllPoints(aoeHealing)
    aoeHealing.tex:SetTexture(Cell.vars.whiteTexture)

    -- 创建动画组：包含两段 Alpha 动画，模拟"闪入→闪出"效果
    local ag = aoeHealing:CreateAnimationGroup()
    -- 动画阶段一：淡入（0→1 alpha），持续 0.5 秒，OUT 缓出
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0)
    a1:SetToAlpha(1)
    a1:SetDuration(0.5)
    a1:SetOrder(1)
    a1:SetSmoothing("OUT")
    -- 动画阶段二：淡出（1→0 alpha），持续 0.5 秒，IN 缓入
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(1)
    a2:SetToAlpha(0)
    a2:SetDuration(0.5)
    a2:SetOrder(2)
    a2:SetSmoothing("IN")

    -- 动画开始播放时显示指示器框架
    ag:SetScript("OnPlay", function()
        aoeHealing:Show()
    end)
    -- 动画播放完毕后隐藏指示器框架，避免不透明帧阻挡鼠标事件
    ag:SetScript("OnFinished", function()
        aoeHealing:Hide()
    end)

    -- 设置指示器闪烁颜色
    -- @param r, g, b: RGB 颜色分量（0-1），用于生成渐变纹理
    -- 渐变从透明（alpha=0）到半透明（alpha=0.77），VERTICAL 方向
    function aoeHealing:SetColor(r, g, b)
        aoeHealing.tex:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.77))
    end

    -- 触发指示器闪烁动画
    -- 从外部调用（如事件处理中的 Display 回调），播放一次淡入淡出循环
    function aoeHealing:Display()
        -- if ag:IsPlaying() then
        --     ag:Restart()
        -- else
            ag:Play()
        -- end
    end
end

-- 启用或禁用 AoE 治疗指示器的事件监听
-- @param enabled: true 注册事件，false 注销事件
-- Midnight 防护：在 WoW 12.0.0+ 版本中 COMBAT_LOG_EVENT_UNFILTERED 不可用，
-- 此时直接返回，不进行任何注册/注销操作（eventFrame 的 OnEvent 脚本也无注册）
function I.EnableAoEHealing(enabled)
    -- On Midnight (12.0.0+) COMBAT_LOG_EVENT_UNFILTERED is unavailable;
    -- the eventFrame has no OnEvent script in that case, so registration
    -- is intentionally skipped.
    if Cell.isMidnight then return end
    if enabled then
        eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        eventFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end