local _, Cell = ...
local L = Cell.L
local F = Cell.funcs

-- 将频繁调用的全局/API 函数本地化，提升运行效率
local UnitIsFeignDeath = UnitIsFeignDeath
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitName = UnitName
local IsInGroup = IsInGroup
local IsEncounterInProgress = IsEncounterInProgress
local GetSpellLink = C_Spell.GetSpellLink or GetSpellLink

----------------------------------------------------
-- 模块级状态变量
----------------------------------------------------
-- init: 标记 GROUP_ROSTER_UPDATE 是否已至少执行过一次
-- instanceType: 当前副本类型（"raid" / "party" / "pvp" / "arena" / "none" 等）
-- inInstance: 是否处于副本内部
local init, instanceType, inInstance
-- limit: 战斗中死亡播报的条数上限；count: 当前战斗已播报的累计条数
local limit, count

----------------------------------------------------
-- 播报发送辅助函数（CLEU 路径与 Midnight 路径共用）
----------------------------------------------------
-- 将死亡播报消息发送到合适的聊天频道：
--   - 副本中有 INSTANCE_CHAT 时发送到实例频道
--   - 否则根据是否在团队中分别发送到 RAID / PARTY 频道
-- 仅当 Cell 拥有最高优先级（hasHighestPriority）时才真正发送，避免多款插件重复播报。
local function Send(msg)
    if Cell.hasHighestPriority then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            SendChatMessage(strupper(ACTION_UNIT_DIED)..": "..msg, "INSTANCE_CHAT")
        else
            SendChatMessage(strupper(ACTION_UNIT_DIED)..": "..msg, IsInRaid() and "RAID" or "PARTY")
        end
    end
end

-- 战斗中播报条数限制检查
-- 仅在团队副本（raid）且战斗进行中时生效；超过 limit 上限后停止播报，防止刷屏。
local function CheckSendLimit()
    if instanceType == "raid" and IsEncounterInProgress() then
        count = count + 1
        if count > limit then
            return false
        end
    end
    return true
end

----------------------------------------------------
-- CLEU 详细死亡分析路径（Midnight 12.0.0 之前的版本 + 怀旧服）
-- COMBAT_LOG_EVENT_UNFILTERED 在 12.0.0（Midnight）中被移除，
-- 因此当 Cell.isMidnight 为 true 时，整个 CLEU 代码块将被跳过。
----------------------------------------------------
local deathLogs -- 仅在 CLEU 路径分配使用；key=destGUID，value=死亡详情表
-- 创建隐藏 Frame 用于注册/监听所有事件
local frame = CreateFrame("Frame")

if not Cell.isMidnight then
    -- 黑名单：指定法术 ID 造成的伤害不计入死亡记录
    local blacklist = {
        [124255] = true
    }

    -- 从游戏全局字符串中提取本地化的战斗文本格式模板
    -- 亚洲客户端（中文/韩文等）使用不同的字符串格式（子串截取去除修饰标记）
    -- 西方客户端则去掉括号后转换为小写
    local overkillFormat, resistedFormat, blockedFormat, absorbedFormat, criticalText
    if Cell.isAsian then
        overkillFormat = string.sub(_G.TEXT_MODE_A_STRING_RESULT_OVERKILLING, 4, string.len(_G.TEXT_MODE_A_STRING_RESULT_OVERKILLING)-3)
        resistedFormat = string.sub(_G.TEXT_MODE_A_STRING_RESULT_RESIST, 4, string.len(_G.TEXT_MODE_A_STRING_RESULT_RESIST)-3)
        blockedFormat = string.sub(_G.TEXT_MODE_A_STRING_RESULT_BLOCK, 4, string.len(_G.TEXT_MODE_A_STRING_RESULT_BLOCK)-3)
        absorbedFormat = string.sub(_G.TEXT_MODE_A_STRING_RESULT_ABSORB, 4, string.len(_G.TEXT_MODE_A_STRING_RESULT_ABSORB)-3)
        criticalText = string.sub(_G.TEXT_MODE_A_STRING_RESULT_CRITICAL, 4, string.len(_G.TEXT_MODE_A_STRING_RESULT_CRITICAL)-3)
    else
        overkillFormat = strlower(string.gsub(_G.TEXT_MODE_A_STRING_RESULT_OVERKILLING, "[()]", ""))
        resistedFormat = strlower(string.gsub(_G.TEXT_MODE_A_STRING_RESULT_RESIST, "[()]", ""))
        blockedFormat = strlower(string.gsub(_G.TEXT_MODE_A_STRING_RESULT_BLOCK, "[()]", ""))
        absorbedFormat = strlower(string.gsub(_G.TEXT_MODE_A_STRING_RESULT_ABSORB, "[()]", ""))
        criticalText = strlower(string.gsub(_G.TEXT_MODE_A_STRING_RESULT_CRITICAL, "[()]", ""))
    end

    -- deathLogs 表结构：以目标单位的 GUID 为键，记录该单位被击中/死亡的相关信息
    -- 字段说明：time(时间戳), type(伤害类型), name(单位名), ability(技能名/链接),
    --          school(伤害学派), amount(伤害量), overkill(过量伤害), resisted(抵抗量),
    --          blocked(格挡量), absorbed(吸收量), critical(是否暴击), sourceName(伤害来源名)
    deathLogs = {
    }

    -- 更新/记录某个单位受到的伤害事件
    -- 每次有新的伤害事件时调用，覆盖旧数据；同时将 reported 标记重置为 false，
    -- 确保最终死亡时可以触发播报。
    local function UpdateDeathLog(guid, ...)
        if not deathLogs[guid] then
            deathLogs[guid] = {}
        end

        deathLogs[guid]["time"], deathLogs[guid]["type"], deathLogs[guid]["name"], deathLogs[guid]["ability"],
        deathLogs[guid]["school"], deathLogs[guid]["amount"], deathLogs[guid]["overkill"], deathLogs[guid]["resisted"],
        deathLogs[guid]["blocked"], deathLogs[guid]["absorbed"], deathLogs[guid]["critical"], deathLogs[guid]["sourceName"] = ...

        deathLogs[guid]["reported"] = false
    end

    -- 根据 deathLogs 中的死亡详情生成并发送死亡播报消息
    -- 根据伤害类型不同，输出格式不同：
    --   - 无类型/超时（>1秒）：仅输出玩家名
    --   - 秒杀（INSTAKILL）：输出 "玩家名 > 秒杀"
    --   - 环境伤害（ENVIRONMENTAL）：输出 "玩家名 > 伤害量（环境类型）"
    --   - 法术/远程/近战：输出 "玩家名 > 技能名 伤害量（过量伤害）[来源名]"
    local function Report(guid)
        if not deathLogs[guid] or deathLogs[guid]["reported"] then return end
        deathLogs[guid]["reported"] = true

        if not CheckSendLimit() then return end

        -- 无伤害类型记录，或距离上次伤害超过1秒（可能为未知原因死亡）
        if not deathLogs[guid]["type"] or time()-deathLogs[guid]["time"]>=1 then -- unknown
            Send(deathLogs[guid]["name"])

        elseif deathLogs[guid]["type"] == "INSTAKILL" then
            Send(deathLogs[guid]["name"].." > "..L["instakill"])

        elseif deathLogs[guid]["type"] == "ENVIRONMENTAL" then
            Send(deathLogs[guid]["name"].." > "..F.FormatNumber(deathLogs[guid]["amount"]).." ("..deathLogs[guid]["ability"]..")")

        else -- SPELL & RANGE & SWING：法术/远程/近战伤害导致的死亡
            local damageDetails = ""

            -- 如果有过量伤害，附加过量伤害信息
            if deathLogs[guid]["overkill"] > 0 then
                damageDetails = " ("..string.format(overkillFormat, F.FormatNumber(deathLogs[guid]["overkill"]))..") "
            end

            -- 如果伤害来源名与目标名不同，附加来源名（用方括号包裹）
            local sourceName = (deathLogs[guid]["sourceName"] and deathLogs[guid]["name"]~=deathLogs[guid]["sourceName"]) and (" ["..deathLogs[guid]["sourceName"].."]") or ""
            local ability

            if deathLogs[guid]["type"] == "SPELL" then -- 法术/远程伤害，使用记录的技能链接
                ability = deathLogs[guid]["ability"]
            else -- SWING：近战攻击，使用本地化的"近战"文字
                ability = strlower(_G.MELEE)
            end

            Send(deathLogs[guid]["name"].." > "..ability.." "..F.FormatNumber(deathLogs[guid]["amount"])..damageDetails..sourceName)
        end
    end

    -- COMBAT_LOG_EVENT_UNFILTERED 事件处理
    -- 解析战斗日志中的伤害事件，仅关注友方玩家单位（destGUID 以 "Player" 开头且阵营友好），
    -- 根据事件类型提取对应的伤害详情并更新死亡记录：
    --   - SPELL_INSTAKILL：秒杀技能
    --   - ENVIRONMENTAL_DAMAGE：环境伤害（摔落、熔岩等）
    --   - SWING_DAMAGE：近战攻击伤害
    --   - SPELL_DAMAGE / SPELL_PERIODIC_DAMAGE / RANGE_DAMAGE：法术/持续/远程伤害
    --   - SPELL_AURA_APPLIED：特定光环（救赎之魂、灵魂疲惫）触发提前播报
    --   - UNIT_DIED：单位死亡事件，延迟0.5秒后播报（等待最终伤害记录落定）
    function frame:COMBAT_LOG_EVENT_UNFILTERED(...)
        local timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, arg12, arg13, arg14 = ...
        local amount, overkill, school, resisted, blocked, absorbed, critical

        -- 仅处理友方玩家单位受到的伤害
        if string.find(destGUID, "^Player") and F.IsFriend(destFlags) then
            if event == "SPELL_INSTAKILL" then
                UpdateDeathLog(destGUID, timestamp, "INSTAKILL", destName)
            end

            if event == "ENVIRONMENTAL_DAMAGE" then
                amount, overkill, school, resisted, blocked, absorbed, critical = select(13, ...)
                -- 当伤害为0且有吸收值时，使用吸收量作为伤害量
                amount = amount == 0 and absorbed or amount
                UpdateDeathLog(destGUID, timestamp, "ENVIRONMENTAL", destName, strlower(_G["ACTION_ENVIRONMENTAL_DAMAGE_" .. strupper(arg12)]), nil, amount)
            end

            if event == "SWING_DAMAGE" then
                amount, overkill, school, resisted, blocked, absorbed, critical = select(12, ...)
                UpdateDeathLog(destGUID, timestamp, "SWING", destName, nil, school, amount, overkill or -1, resisted, blocked, absorbed, critical, sourceName)
            end

            if event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE" or event == "RANGE_DAMAGE" then
                -- 跳过黑名单中的法术
                if not blacklist[arg12] then
                    amount, overkill, school, resisted, blocked, absorbed, critical = select(15, ...)
                    local spellLink = GetSpellLink(arg12)
                    UpdateDeathLog(destGUID, timestamp, "SPELL", destName, spellLink, school, amount, overkill or -1, resisted, blocked, absorbed, critical, sourceName)
                end
            end

            if event == "SPELL_AURA_APPLIED" then
                -- 检测特定光环：27827（救赎之魂）或 358164（灵魂疲惫）
                -- 这表示单位即将死亡，提前0.25秒触发死亡播报
                if arg12 == 27827 or arg12 == 358164 then -- 救赎之魂 or 灵魂疲惫
                    C_Timer.After(0.25, function()
                        Report(destGUID)
                    end)
                end
            end

            if event == "UNIT_DIED" and not UnitIsFeignDeath(destName) then
                -- 单位死亡（排除假死），延迟0.5秒后播报以确保最后的伤害事件已记录
                C_Timer.After(0.5, function()
                    if not deathLogs[destGUID] then deathLogs[destGUID] = {["name"]=destName} end
                    Report(destGUID)
                end)
            end
        end
    end

    -- 设置 Frame 的通用事件分发脚本
    -- COMBAT_LOG_EVENT_UNFILTERED 使用 CombatLogGetCurrentEventInfo() 获取事件参数
    -- 其他事件则通过 self[event] 调用对应的 Frame 方法
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            self:COMBAT_LOG_EVENT_UNFILTERED(CombatLogGetCurrentEventInfo())
        else
            self[event](self, ...)
        end
    end)
else
    -- Midnight (12.0.0+) 路径：COMBAT_LOG_EVENT_UNFILTERED 不可用。
    -- 使用简化的死亡检测方案：通过 UNIT_HEALTH 事件追踪队伍/团队成员的血量变化，
    -- 当 UnitIsDeadOrGhost() 返回 true 时判定死亡并播报。
    -- 注意：此路径无法获取 "被XX的YY技能杀死，造成ZZ伤害" 的详细信息。
    local reportedDead = {} -- 已播报死亡的 GUID 集合，防止同一死亡多次播报

    -- UNIT_HEALTH 事件回调：检测指定单位是否死亡
    -- 如果单位死亡（且非假死），在未播报过的情况下发送死亡播报。
    -- 如果单位复活（血量恢复），清除 reportedDead 标记以便下次死亡时再次播报。
    local function OnUnitHealth(unit)
        if not unit then return end
        local guid = UnitGUID(unit)
        -- Midnight 版本中某些 GUID 为加密值（Secret Value），不能用作表键
        if Cell.isMidnight and F.IsSecretValue and F.IsSecretValue(guid) then return end
        if UnitIsDeadOrGhost(unit) and not UnitIsFeignDeath(unit) then
            if guid and not reportedDead[guid] then
                reportedDead[guid] = true
                if not CheckSendLimit() then return end
                local name = UnitName(unit) or unit
                Send(name)
            end
        else
            -- 单位存活（已复活），移除死亡标记，允许未来再次检测并播报
            if guid then
                reportedDead[guid] = nil
            end
        end
    end

    -- 设置 Midnight 路径的事件分发脚本
    -- UNIT_HEALTH 事件交由 OnUnitHealth 处理，其他事件通过 self[event] 分发
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "UNIT_HEALTH" then
            OnUnitHealth(...)
        elseif self[event] then
            self[event](self, ...)
        end
    end)
end

----------------------------------------------------
-- 共享事件处理器（CLEU 路径和 Midnight 路径共用）
----------------------------------------------------

-- PLAYER_ENTERING_WORLD 事件处理
-- 在进入世界时检测当前副本类型：
--   - PvP/竞技场：注销所有死亡播报相关事件（不需要死亡播报功能）
--   - 副本/团队副本：注册 GROUP_ROSTER_UPDATE 事件
--   - 团队副本额外注册 ENCOUNTER_START 事件（用于重置战斗中播报计数）
--   - 首次进入时触发 GROUP_ROSTER_UPDATE 初始化
--   - 离开副本时清理 deathLogs 缓存并注销事件
function frame:PLAYER_ENTERING_WORLD()
    local isIn, iType = IsInInstance()
    instanceType = iType

    if instanceType == "pvp" or instanceType == "arena" then
        frame:UnregisterEvent("ENCOUNTER_START")
        frame:UnregisterEvent("ENCOUNTER_END")
        if not Cell.isMidnight then
            frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end
        frame:UnregisterEvent("GROUP_ROSTER_UPDATE")
        return
    else
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    end

    if not init then frame:GROUP_ROSTER_UPDATE() end
    if isIn then
        inInstance = true
        if instanceType == "raid" then
            frame:RegisterEvent("ENCOUNTER_START")
            count = 0
        else
            frame:UnregisterEvent("ENCOUNTER_START")
        end
    elseif inInstance then -- 刚离开副本
        inInstance = false
        if deathLogs then wipe(deathLogs) end
        frame:UnregisterEvent("ENCOUNTER_START")
    end
end

-- GROUP_ROSTER_UPDATE 事件处理
-- 队伍/团队成员变化时触发：
--   - 有队伍且战斗中：注册 ENCOUNTER_END 事件（用于战斗结束后重新检查优先级）
--   - 有队伍但非战斗：延迟7秒后检查优先级（等队伍稳定后决定谁负责播报）
--   - 无队伍：注销 CLEU 事件监听
-- 首次执行时标记 init = true
local timer
function frame:GROUP_ROSTER_UPDATE()
    if IsInGroup() then
        if IsEncounterInProgress() then
            frame:RegisterEvent("ENCOUNTER_END")
        else
            if timer then timer:Cancel() end
            timer = C_Timer.NewTimer(7, function()
                F.CheckPriority()
            end)
        end
    else
        if not Cell.isMidnight then
            frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end
    end
    init = true
end

-- ENCOUNTER_END 事件处理
-- 战斗结束时注销自身事件，然后重新触发 GROUP_ROSTER_UPDATE 以重新检查优先级。
function frame:ENCOUNTER_END()
    frame:UnregisterEvent("ENCOUNTER_END")
    frame:GROUP_ROSTER_UPDATE()
end

-- ENCOUNTER_START 事件处理
-- 战斗开始时重置 count 计数，开始新一轮的战斗内播报条数限制。
function frame:ENCOUNTER_START()
    count = 0
end

----------------------------------------------------
-- 优先级回调：当 Cell 插件的聊天播报优先级发生变化时触发
-- CLEU 路径：根据 hasHighestPriority 决定是否注册/注销 COMBAT_LOG_EVENT_UNFILTERED
-- Midnight 路径：无需额外操作（UNIT_HEALTH 由 UpdateTools 统一管理）
----------------------------------------------------
local function UpdatePriority(hasHighestPriority)
    if Cell.isMidnight then
        -- Midnight：CLEU 不可用；UNIT_HEALTH 的注册/注销在 UpdateTools 中统一处理
        return
    end
    if hasHighestPriority and CellDB["tools"]["deathReport"][1] then
        frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end
Cell.RegisterCallback("UpdatePriority", "DeathReport_UpdatePriority", UpdatePriority)

----------------------------------------------------
-- 工具开关回调：当用户在设置中启用/禁用死亡播报功能时触发
-- 启用时：注册核心事件（PLAYER_ENTERING_WORLD / GROUP_ROSTER_UPDATE），
--          Midnight 路径额外注册 UNIT_HEALTH，读取播报条数上限；
--         如果已在世界中手动启用，立即触发 PLAYER_ENTERING_WORLD 初始化。
-- 禁用时：注销所有事件并清理 deathLogs 缓存。
----------------------------------------------------
local enabled
local function UpdateTools(which)
    if not which or which == "deathReport" then
        if CellDB["tools"]["deathReport"][1] then
            -- 启用死亡播报功能
            frame:RegisterEvent("PLAYER_ENTERING_WORLD")
            frame:RegisterEvent("GROUP_ROSTER_UPDATE")
            if Cell.isMidnight then
                -- Midnight：通过 UNIT_HEALTH 检测所有队伍/团队成员的血量变化来判定死亡
                -- UnitHealth() 返回值为加密值但 UnitIsDeadOrGhost() 不是，故可用于判定
                frame:RegisterEvent("UNIT_HEALTH")
            end

            limit = CellDB["tools"]["deathReport"][2]
            count = 0
            if not enabled and which == "deathReport" then -- 已在世界中，手动开启功能
                frame:PLAYER_ENTERING_WORLD()
            end
            enabled = true
        else
            -- 禁用死亡播报功能：注销所有事件，清理死亡记录缓存
            frame:UnregisterAllEvents()
            if deathLogs then wipe(deathLogs) end
            enabled = false
        end
    end
end
Cell.RegisterCallback("UpdateTools", "DeathReport_UpdateTools", UpdateTools)