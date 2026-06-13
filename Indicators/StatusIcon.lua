-- ================================================================
-- StatusIcon.lua - 状态图标指示器
-- ================================================================
-- 负责在单位按钮上显示各种特殊状态图标，包括：
--   - 跨队伍玩家（LFG 眼睛图标）
--   - 即将到来的复活 / 战复 debuff / 灵魂石（复活图标）
--   - 相位状态（Chromie 时光 / 战争模式 / 分片等）
--   - 战场旗帜 / 宝珠
--   - 召唤图标（零售版，需启用 CELL_SUMMON_ICONS_ENABLED）
-- 同时管理复活计时器条（resurrectionIcon）的显示与动画。
-- Midnight (12.0.0+) 兼容：移除了对 COMBAT_LOG_EVENT_UNFILTERED 的依赖，
-- 改用 UNIT_AURA + UNIT_HEALTH 追踪灵魂石死亡，UNIT_AURA 处理复活 debuff 移除，
-- INCOMING_RESURRECT_CHANGED + UnitHasIncomingResurrection() 处理即将到来的复活。
-- ================================================================

local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs
---@type PixelPerfectFuncs
local P = Cell.pixelPerfectFuncs

-- 控制是否显示召唤图标（零售版 Incoming Summon 功能）
-- 默认关闭，因为该功能在大多数场景下不需要
CELL_SUMMON_ICONS_ENABLED = false

-------------------------------------------------
-- event
-- 事件处理：监听单位状态变化并更新对应按钮的状态图标
-- eventFrame 处理常规事件（INCOMING_RESURRECT_CHANGED, UNIT_PHASE 等）
-- cleuFrame 处理战斗日志事件（Pre-Midnight）或 UNIT_AURA/UNIT_HEALTH（Midnight）
-------------------------------------------------
-- 通用事件帧：将事件统一分发给对应单位的按钮进行图标刷新
-- 使用 F.HandleUnitButton 根据 unit token 找到对应的 UnitButton 实例
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, unit)
    F.HandleUnitButton("unit", unit, I.UpdateStatusIcon)
end)

-- 标记单位按钮为"携带灵魂石死亡"状态
-- 当检测到单位在持有灵魂石 buff 后死亡时调用，设置 hasSoulstone 状态并刷新图标
local function DiedWithSoulstone(b)
    b.states.hasSoulstone = true
    I.UpdateStatusIcon(b)
end

-- rez 表：记录正在等待接受复活的单位
-- 结构：rez[guid] = {startTime, duration}
-- 用于在单位按钮发生变化（如队伍更新）后仍能恢复复活计时器状态
local rez = {}
-- soulstones 表：记录当前持有灵魂石 buff 的单位及时间戳
-- 结构：soulstones[guid] = timestamp
-- 用于追踪灵魂石 buff 的获得与移除，配合死亡检测判断"带灵魂石死亡"
local soulstones = {}
-- 预解析法术名称，避免每次事件触发时重复调用 GetSpellInfo
local SOULSTONE = F.GetSpellInfo(20707)
local RESURRECTING = F.GetSpellInfo(160029)

-- NOTE: The cleuFrame previously relied on COMBAT_LOG_EVENT_UNFILTERED for:
--   1. SPELL_AURA_REMOVED (soulstone / Resurrecting debuff removal)
--   2. UNIT_DIED sub-event (to detect soulstone deaths)
--   3. SPELL_RESURRECT (to detect incoming resurrections)
-- COMBAT_LOG_EVENT_UNFILTERED is removed in Midnight (WoW 12.0.0).
--
-- Midnight replacements:
--   - Incoming resurrection: already handled via INCOMING_RESURRECT_CHANGED
--     in eventFrame + UnitHasIncomingResurrection() in I.UpdateStatusIcon.
--   - Resurrecting debuff removal: handled by UNIT_AURA → UpdateStatusIcon_Resurrection
--     which re-checks F.FindAuraById for the Resurrecting debuff.
--   - Soulstone death detection: tracked via UNIT_AURA (soulstone buff removal)
--     combined with UNIT_HEALTH + UnitIsDeadOrGhost() for the death signal.
local cleuFrame = CreateFrame("Frame")

if not Cell.isMidnight then
    -- Pre-Midnight 路径：使用 COMBAT_LOG_EVENT_UNFILTERED 追踪灵魂石和复活事件
    cleuFrame:SetScript("OnEvent", function()
        local timestamp, subEvent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName = CombatLogGetCurrentEventInfo()

        if subEvent == "SPELL_AURA_REMOVED" then
            if spellName == SOULSTONE then
                -- 灵魂石 buff 被移除，记录时间戳
                -- 短暂保留（0.1秒）以便 UNIT_DIED 事件能检测到"携带灵魂石死亡"
                soulstones[destGUID] = timestamp
                C_Timer.After(0.1, function()
                    soulstones[destGUID] = nil
                end)
            elseif spellName == RESURRECTING then
                -- 战复 debuff（Resurrecting）移除，清除复活记录并刷新图标
                rez[destGUID] = nil
                F.HandleUnitButton("guid", destGUID, I.UpdateStatusIcon_Resurrection)
            end
        elseif subEvent == "UNIT_DIED" then
            -- 单位死亡：如果在灵魂石 buff 被移除后短时间内死亡，判定为"携带灵魂石死亡"
            if soulstones[destGUID] then
                F.HandleUnitButton("guid", destGUID, DiedWithSoulstone)
            end
            soulstones[destGUID] = nil
        elseif subEvent == "SPELL_RESURRECT" then
            -- 检测到复活法术开始施放，记录复活信息并显示复活计时器图标
            local start, duration = GetTime(), 60
            rez[destGUID] = {start, duration}

            F.HandleUnitButton("guid", destGUID, I.UpdateStatusIcon_Resurrection, start, duration)
        end
    end)
else
    -- Midnight 路径（WoW 12.0.0+）：COMBAT_LOG_EVENT_UNFILTERED 已被移除
    -- 使用 UNIT_AURA + UNIT_HEALTH 两个事件的组合来替代原有的 CLEU 事件逻辑。
    --
    -- 设计原理：
    --   UNIT_AURA 在追踪单位的任何光环增减时触发 → 替代 SPELL_AURA_REMOVED
    --   UNIT_HEALTH 在追踪单位血量变化时触发 → 替代 UNIT_DIED（用 UnitIsDeadOrGhost 判断）
    --   SPELL_RESURRECT 不再有直接替代，改为依赖 INCOMING_RESURRECT_CHANGED + UnitHasIncomingResurrection()
    --
    -- SecretValue 防护（Midnight 12.0.0+）：
    --   非队友/非团队成员调用 UnitGUID 可能返回 secret value（加密字符串）
    --   issecretvalue() 可检测此类值，必须跳过以避免后续操作出错
    cleuFrame:SetScript("OnEvent", function(self, event, unit)
        if event == "UNIT_AURA" then
            local guid = UnitGUID(unit)
            if not guid then return end
            -- Midnight 12.0.0+: UnitGUID may return secret strings for non-group units
            -- 安全防护：Guid 为 secret value 时不可用，直接返回
            if issecretvalue and issecretvalue(guid) then return end
            -- Check if soulstone buff is now absent but was present
            -- (simple: after UNIT_AURA fires, see if unit still has it)
            -- 检查灵魂石 buff 是否存在：用 FindAuraByName 查找单位上的灵魂石 buff
            -- hasSoulstone == false 且 soulstones[guid] 有记录 → buff 刚被移除，延迟清除以便死亡检测
            -- hasSoulstone == true → buff 仍在，更新时间戳
            local hasSoulstone = F.FindAuraByName and F.FindAuraByName(unit, "BUFF", SOULSTONE)
            if not hasSoulstone and soulstones[guid] then
                -- aura gone; keep window open for death
                C_Timer.After(0.1, function()
                    soulstones[guid] = nil
                end)
            elseif hasSoulstone then
                soulstones[guid] = GetTime()
            end
            -- Also refresh rez icon in case Resurrecting debuff changed
            -- 同时刷新复活图标（Resurrecting debuff 可能已变化）
            F.HandleUnitButton("unit", unit, I.UpdateStatusIcon_Resurrection)
        elseif event == "UNIT_HEALTH" then
            local guid = UnitGUID(unit)
            if not guid then return end
            -- Midnight 12.0.0+: UnitGUID may return secret strings for non-group units
            -- 安全防护：Guid 为 secret value 时不可用，直接返回
            if issecretvalue and issecretvalue(guid) then return end
            if UnitIsDeadOrGhost(unit) then
                -- 单位死亡：检查是否在灵魂石 buff 移除后短时间内死亡
                if soulstones[guid] then
                    F.HandleUnitButton("unit", unit, DiedWithSoulstone)
                end
                soulstones[guid] = nil
            else
                -- unit came back alive; clear soulstone state
                -- 单位复活（或非死亡状态），清除灵魂石追踪状态
                soulstones[guid] = nil
            end
        end
    end)
end

-------------------------------------------------
-- create
-- 创建状态图标控件，包括主状态图标 (statusIcon) 和复活计时器图标 (resurrectionIcon)
-- statusIcon：显示静态状态图标（LFG眼睛、复活图标、相位图标、战场旗帜等）
-- resurrectionIcon：显示复活计时器覆盖层，带遮罩动画的进度条效果
-------------------------------------------------
function I.CreateStatusIcon(parent)
    -- 主状态图标帧 —— 用于显示静态状态图标
    local statusIcon = CreateFrame("Frame", parent:GetName().."StatusIcon", parent.widgets.indicatorFrame)
    parent.indicators.statusIcon = statusIcon
    statusIcon:Hide()

    statusIcon:SetIgnoreParentAlpha(true)

    -- 状态图标纹理（OVERLAY 层，位于其他 indicator 之上）
    statusIcon.tex = statusIcon:CreateTexture(nil, "OVERLAY")
    statusIcon.tex:SetAllPoints(statusIcon)

    -- 便捷方法：直接委托给内部纹理对象
    function statusIcon:SetTexture(tex)
        statusIcon.tex:SetTexture(tex)
    end

    function statusIcon:SetTexCoord(...)
        statusIcon.tex:SetTexCoord(...)
    end

    function statusIcon:SetAtlas(...)
        statusIcon.tex:SetAtlas(...)
    end

    function statusIcon:SetVertexColor(...)
        statusIcon.tex:SetVertexColor(...)
    end

    -- resurrection icon ----------------------------------
    -- 复活计时器图标：覆盖在主状态图标上，通过遮罩实现自下而上的填充动画
    -- 结构：resurrectionIcon 帧 → 去饱和底图(tex) + 进度条(bar) + 遮罩纹理(mask) + 彩色前景(maskIcon)
    -- 原理：mask 锚定在 bar 的填充纹理底部，随着 bar 数值增加，mask 向下移动，
    --       maskIcon 通过 AddMaskTexture 显示被 mask 覆盖的部分，形成自下而上填充的视觉效果
    local resurrectionIcon = CreateFrame("Frame", parent:GetName().."ResurrectionIcon", parent.widgets.indicatorFrame)
    parent.indicators.resurrectionIcon = resurrectionIcon
    resurrectionIcon:SetAllPoints(statusIcon)
    resurrectionIcon:Hide()

    -- 底图：去饱和的灰色复活图标，作为背景
    resurrectionIcon.tex = resurrectionIcon:CreateTexture(nil, "ARTWORK")
    resurrectionIcon.tex:SetAllPoints(resurrectionIcon)
    resurrectionIcon.tex:SetDesaturated(true)
    resurrectionIcon.tex:SetVertexColor(0.4, 0.4, 0.4, 0.5)
    resurrectionIcon.tex:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")

    -- 进度条：用于驱动遮罩动画
    -- 垂直方向、反向填充（从底部向上）
    -- 状态条纹理本身透明（Alpha=0），其作用仅为提供锚点给 mask
    local bar = CreateFrame("StatusBar", nil, resurrectionIcon)
    bar:SetAllPoints(resurrectionIcon)
    bar:SetOrientation("VERTICAL")
    bar:SetReverseFill(true)
    bar:SetStatusBarTexture(Cell.vars.whiteTexture)
    bar:GetStatusBarTexture():SetAlpha(0)
    bar.elapsedTime = 0
    -- OnUpdate：每 0.25 秒刷新一次进度条值（节流更新，减少 CPU 开销）
    bar:SetScript("OnUpdate", function(self, elapsed)
        if bar.elapsedTime >= 0.25 then
            bar:SetValue(bar:GetValue() + bar.elapsedTime)
            bar.elapsedTime = 0
        end
        bar.elapsedTime = bar.elapsedTime + elapsed
    end)

    -- 遮罩纹理：锚定在进度条的填充纹理底部
    -- "CLAMPTOBLACKADDITIVE" 模式：遮罩白色区域显示前景，黑色区域显示底图
    local mask = resurrectionIcon:CreateMaskTexture()
    mask:SetTexture(Cell.vars.whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "BOTTOMLEFT")
    mask:SetPoint("BOTTOMRIGHT")

    -- 彩色前景图标：被 mask 裁剪，仅显示已"填充"部分
    local maskIcon = bar:CreateTexture(nil, "ARTWORK")
    maskIcon:SetAllPoints(resurrectionIcon)
    maskIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    maskIcon:AddMaskTexture(mask)

    -- 设置复活计时器：根据起始时间和持续时间初始化进度条
    -- duration + 13 的原因：复活图标纹理在 (0,1,0,1) texcoord 下有空白间隙，
    -- 需要额外 13 秒来使遮罩完全覆盖图标区域
    function resurrectionIcon:SetTimer(start, duration)
        resurrectionIcon:Hide() -- pause OnUpdate
        bar:SetMinMaxValues(0, duration + 13) -- NOTE: texture gap (texcoord 0,1,0,1)
        bar:SetValue(GetTime()-start)
        resurrectionIcon:Show()
    end

    -- 复活图标隐藏时取消相关计时器
    resurrectionIcon:SetScript("OnHide", function()
        if resurrectionIcon.timer then
            resurrectionIcon.timer:Cancel()
            resurrectionIcon.timer = nil
        end
    end)
    -------------------------------------------------------

    -- 重写 SetFrameLevel：使 resurrectionIcon 与 statusIcon 保持同一层级
    statusIcon._SetFrameLevel = statusIcon.SetFrameLevel
    function statusIcon:SetFrameLevel(level)
        statusIcon:_SetFrameLevel(level)
        resurrectionIcon:SetFrameLevel(level)
    end
end

-------------------------------------------------
-- resurrection
-- 更新复活计时器图标：处理战复 debuff 计时器显示逻辑
-- 三种数据来源（按优先级）：
--   1. 直接传入的 start/duration（来自 SPELL_RESURRECT CLEU 事件，Pre-Midnight）
--   2. 从单位身上查找 Resurrecting debuff（光环 ID 160029）
--   3. 从 rez 缓存表恢复（单位按钮发生变化后仍能保持状态）
-- Midnight 注意：AuraUtil.FindAura/UnpackAuraData 对 secret aura 数据会失败，
-- F.IsAuraRestricted() 不可靠，因此在 Midnight 上完全跳过 debuff 查找。
-------------------------------------------------
function I.UpdateStatusIcon_Resurrection(button, start, duration)
    local guid = button.states.guid
    local unit = button.states.unit
    local resurrectionIcon = button.indicators.resurrectionIcon

    -- 无有效 guid 或 unit 时隐藏图标
    if not (guid and unit) then
        resurrectionIcon:Hide()
        return
    end

    if not start then
        -- Midnight 12.0.0+: AuraUtil.FindAura/UnpackAuraData fails on secret aura data
        -- F.IsAuraRestricted() is unreliable; skip entirely on Midnight
        -- Midnight 安全防护：跳过有风险的 FindAuraById 调用
        if Cell.isMidnight then
            resurrectionIcon:Hide()
            return
        end
        -- 尝试从单位身上查找战复 debuff（Resurrecting，ID 160029）
        local dur, expir = select(5, F.FindAuraById(unit, "DEBUFF", 160029)) -- battle res
        if dur then --! check Resurrecting debuff
            -- 找到 debuff：反算 start = 过期时间 - 持续时间
            start = expir - dur
            duration = dur
        elseif rez[guid] then --! check saved data (unit button changed)
            -- 从缓存恢复（单位按钮对象可能已重建，但 guid 未变）
            start = rez[guid][1]
            duration = rez[guid][2]
        else
            -- 无任何复活数据：隐藏图标
            resurrectionIcon:Hide()
            return
        end
    end

    --! alive or expired：单位已复活或计时器已到期，清除状态并隐藏
    if not UnitIsDeadOrGhost(unit) or start + duration <= GetTime() then
        rez[guid] = nil
        resurrectionIcon:Hide()
        return
    end

    -- 启动复活计时器动画（遮罩进度条）
    resurrectionIcon:SetTimer(start, duration)
    -- timer：倒计时结束后自动隐藏图标并清理缓存
    if resurrectionIcon.timer then resurrectionIcon.timer:Cancel() end
    resurrectionIcon.timer = C_Timer.NewTimer(start + duration - GetTime(), function()
        rez[guid] = nil
        resurrectionIcon:Hide()
    end)
end

-------------------------------------------------
-- update (UnitButton_UpdateAuras)
-- 主更新函数：根据单位当前状态按优先级选择并显示对应的状态图标
-- 参考暴雪原生代码：Interface\FrameXML\CompactUnitFrame.lua → CompactUnitFrame_UpdateCenterStatusIcon
--
-- 优先级链（零售版）：
--   1. 跨队伍玩家 → LFG 眼睛图标
--   2. 即将到来的复活 → 白色复活图标
--   3. 战复 debuff（Resurrecting）→ 绿色复活图标
--   4. 携带灵魂石死亡 → 紫色复活图标
--   5. 召唤图标（需启用 CELL_SUMMON_ICONS_ENABLED）→ 待定/接受/拒绝
--   6. 相位原因 → 相位图标（黄色=Chromie/红色=战争模式/绿色=分片/白色=其他）
--   7. 战场旗帜 → 旗帜 atlas 图标
--   8. 战场宝珠 → 宝珠 atlas 图标
--   9. 无匹配 → 隐藏图标
-------------------------------------------------
if Cell.isRetail then
    function I.UpdateStatusIcon(button)
        local unit = button.states.unit
        if not unit then return end

        -- https://wow.gamepedia.com/API_UnitPhaseReason
        -- 获取单位的相位原因：0=相位/1=分片/2=战争模式/3=Chromie时光
        local phaseReason = UnitPhaseReason(unit)

        local icon = button.indicators.statusIcon

        -- Interface\FrameXML\CompactUnitFrame.lua, CompactUnitFrame_UpdateCenterStatusIcon
        -- 优先级 1：跨队伍玩家（其他队伍成员）
        if UnitInOtherParty(unit) then
            icon:SetVertexColor(1, 1, 1, 1)
            icon:SetTexture("Interface\\LFGFrame\\LFG-Eye")
            -- icon:SetTexCoord(0.125, 0.25, 0.25, 0.5)
            -- icon:SetTexCoord(0.145, 0.23, 0.29, 0.46)
            icon:SetTexCoord(0.14, 0.235, 0.28, 0.47)
            icon:Show()
        -- 优先级 2：即将到来的复活（Incoming Resurrection）
        elseif UnitHasIncomingResurrection(unit) then
            icon:SetVertexColor(1, 1, 1, 1)
            icon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
            icon:SetTexCoord(0, 1, 0, 1)
            icon:Show()
        -- 优先级 3：战复 debuff（绿色复活图标，表示已被战复正在等待接受）
        elseif button.states.hasRezDebuff then
            icon:SetVertexColor(0.6, 1, 0.6, 1)
            icon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
            icon:SetTexCoord(0, 1, 0, 1)
            icon:Show()
        -- 优先级 4：携带灵魂石死亡（紫色复活图标，表示死亡时有灵魂石 buff）
        elseif button.states.hasSoulstone then
            icon:SetVertexColor(1, 0.4, 1, 1)
            icon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
            icon:SetTexCoord(0, 1, 0, 1)
            icon:Show()
        -- 优先级 5：召唤图标（需全局开关启用）
        elseif CELL_SUMMON_ICONS_ENABLED and C_IncomingSummon.HasIncomingSummon(unit) then
            local status = C_IncomingSummon.IncomingSummonStatus(unit)
            if status == Enum.SummonStatus.Pending then
                -- 召唤待确认
                icon:SetAtlas("Raid-Icon-SummonPending")
                icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
            elseif status == Enum.SummonStatus.Accepted then
                -- 召唤已接受：6 秒后自动刷新（状态可能变为完成）
                icon:SetAtlas("Raid-Icon-SummonAccepted")
                icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
                C_Timer.After(6, function() I.UpdateStatusIcon(button) end)
            elseif status == Enum.SummonStatus.Declined then
                -- 召唤已拒绝：6 秒后自动刷新清除图标
                icon:SetAtlas("Raid-Icon-SummonDeclined")
                icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
                C_Timer.After(6, function() I.UpdateStatusIcon(button) end)
            end
            icon:Show()
        -- 优先级 6：相位状态（非载具中的玩家单位）
        elseif UnitIsPlayer(unit) and phaseReason and not button.states.inVehicle then
            if phaseReason == 3 then -- chromie, yellow（Chromie 时光漫游相位）
                icon:SetVertexColor(1, 1, 0)
            elseif phaseReason == 2 then -- warmode, red（战争模式相位）
                icon:SetVertexColor(1, 0.6, 0.6)
            elseif phaseReason == 1 then -- sharding, green（跨服分片）
                icon:SetVertexColor(0.5, 1, 0.5)
            else -- 0, phasing（普通相位/其他）
                icon:SetVertexColor(1, 1, 1)
            end
            icon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
            icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            icon:Show()
        -- 死亡图标（已注释，Cell 使用单独的死亡指示器）
        -- elseif UnitIsDeadOrGhost(unit) then
        --     icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        --     icon:SetTexCoord(0, 1, 0, 1)
        --     icon:Show()
        -- 优先级 7：战场旗帜
        elseif button.states.BGFlag then
            icon:SetVertexColor(1, 1, 1, 1)
            icon:SetAtlas("nameplates-icon-flag-"..button.states.BGFlag)
            icon:SetTexCoord(0, 1, 0, 1)
            icon:Show()
        -- 优先级 8：战场宝珠
        elseif button.states.BGOrb then
            icon:SetVertexColor(1, 1, 1, 1)
            icon:SetAtlas("nameplates-icon-orb-"..button.states.BGOrb)
            icon:SetTexCoord(0, 1, 0, 1)
            icon:Show()
        -- 无匹配状态：隐藏图标
        else
            icon:Hide()
        end
    end
else
    -- 经典版路径：精简的优先级链，无相位原因细分、无召唤图标、无战场宝珠
    --
    -- 优先级链（经典版）：
    --   1. 跨队伍玩家 → LFG 眼睛图标
    --   2. 即将到来的复活 → 白色复活图标
    --   3. 战复 debuff 或灵魂石 → 绿色复活图标（合并显示）
    --   4. 相位不同步 → 相位图标（经典版仅检查 UnitInPhase 是否为 false）
    --   5. 战场旗帜 → 旗帜 atlas 图标
    --   6. 无匹配 → 隐藏图标
    function I.UpdateStatusIcon(button)
        local unit = button.states.unit
        if not unit then return end

        local icon = button.indicators.statusIcon

        -- Interface\FrameXML\CompactUnitFrame.lua, CompactUnitFrame_UpdateCenterStatusIcon
        -- 优先级 1：跨队伍玩家
        if UnitInOtherParty(unit) then
            icon:SetVertexColor(1, 1, 1, 1)
            icon:SetTexture("Interface\\LFGFrame\\LFG-Eye")
            icon:SetTexCoord(0.14, 0.235, 0.28, 0.47)
            icon:Show()
        -- 优先级 2：即将到来的复活
        elseif UnitHasIncomingResurrection(unit) then
            icon:SetVertexColor(1, 1, 1, 1)
            icon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
            icon:SetTexCoord(0, 1, 0, 1)
            icon:Show()
        -- 优先级 3：战复 debuff 或携带灵魂石死亡（经典版合并为同一显示）
        elseif button.states.hasRezDebuff or button.states.hasSoulstone then
            icon:SetVertexColor(0.6, 1, 0.6, 1)
            icon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
            icon:SetTexCoord(0, 1, 0, 1)
            icon:Show()
        -- 优先级 4：相位状态（经典版简化判断：玩家 + 已连接 + 不在同一相位 + 非载具）
        elseif UnitIsPlayer(unit) and UnitIsConnected(unit) and not UnitInPhase(unit) and not button.states.inVehicle then
            icon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
            icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            icon:Show()
        -- 死亡图标（已注释，Cell 使用单独的死亡指示器）
        -- elseif UnitIsDeadOrGhost(unit) then
        --     icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        --     icon:SetTexCoord(0, 1, 0, 1)
        --     icon:Show()
        -- 优先级 5：战场旗帜
        elseif button.states.BGFlag then
            icon:SetVertexColor(1, 1, 1, 1)
            icon:SetAtlas(button.states.BGFlag.."_icon_and_flag-dynamicIcon")
            icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            icon:Show()
        -- 无匹配状态：隐藏图标
        else
            icon:Hide()
        end
    end
end

-------------------------------------------------
-- enable
-- 启用/禁用状态图标指示器：注册或注销所需事件，并清理所有单位按钮的图标
--
-- 注册的事件（eventFrame）：
--   INCOMING_RESURRECT_CHANGED — 即将到来的复活状态变化
--   UNIT_PHASE — 单位相位变化
--   PARTY_MEMBER_DISABLE / PARTY_MEMBER_ENABLE — 队伍成员禁用/启用（影响跨队伍状态）
--   INCOMING_SUMMON_CHANGED — 召唤状态变化（仅零售版且启用召唤图标时）
--
-- 注册的事件（cleuFrame）：
--   Pre-Midnight：COMBAT_LOG_EVENT_UNFILTERED — 战斗日志全事件，追踪灵魂石/复活/死亡
--   Midnight (12.0.0+)：UNIT_AURA + UNIT_HEALTH — 替代 CLEU 的事件组合
--
-- 禁用时：注销所有事件并遍历所有单位按钮隐藏图标
-------------------------------------------------
function I.EnableStatusIcon(enabled)
    if enabled then
        -- 注册常规事件到 eventFrame，触发时调用 I.UpdateStatusIcon 刷新图标
        eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
        eventFrame:RegisterEvent("UNIT_PHASE")
        eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
        eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
        if Cell.isRetail and CELL_SUMMON_ICONS_ENABLED then
            eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")
        end
        -- resurrection / soulstone tracking
        -- 复活和灵魂石追踪事件注册（版本分化）
        if not Cell.isMidnight then
            -- Pre-Midnight: use CLEU for soulstone removal, UNIT_DIED, SPELL_RESURRECT
            cleuFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        else
            -- Midnight (12.0.0+): COMBAT_LOG_EVENT_UNFILTERED unavailable.
            -- Use UNIT_AURA for soulstone buff tracking and UNIT_HEALTH for
            -- death detection. INCOMING_RESURRECT_CHANGED (above) handles
            -- incoming rez detection via UnitHasIncomingResurrection().
            cleuFrame:RegisterEvent("UNIT_AURA")
            cleuFrame:RegisterEvent("UNIT_HEALTH")
        end
    else
        -- 禁用：注销所有事件监听
        eventFrame:UnregisterAllEvents()
        cleuFrame:UnregisterAllEvents()
        -- 遍历所有单位按钮，隐藏状态图标和复活图标
        F.IterateAllUnitButtons(function(b)
            b.indicators.statusIcon:Hide()
            b.indicators.resurrectionIcon:Hide()
        end)
    end
end