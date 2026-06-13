--[[
    CellD 集中化 Debuff/Buff 状态模块 (DebuffStatus.lua)
    =====================================================
    借鉴 Grid2 StatusAuras.lua 设计模式，将 UnitButton.lua 中分散在
    HandleDebuff/HandleBuff/UpdateDebuffs/UpdateBuffs 中的以下逻辑
    集中到单一模块：

    1. 时间值计算（start/duration/hasSecretTime）
    2. DurationObject 回退（C_UnitAuras.GetAuraDuration）
    3. 光环刷新状态（UpdateAuraRefreshState）
    4. 分类查询（isBig/isBlacklisted/isDispelBlacklisted）
    5. 排序和变量重置

    Grid2 参考：
    - StatusAuras.lua: Shared.GetIcons() → GetUnitAuras 批量获取
    - IndicatorIcons.lua: canaccessvalue → DurationObject fallback
    - GridUtils.lua: issecretvalue/canaccessvalue 全局原语

    本模块不改变 CellD 的 HandleDebuff/HandleBuff 整体架构，
    但消除了其中 4 处重复的时间值计算代码，并提供
    DurationObject 作为 secret aura 冷却动画的 fallback。
--]]

local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs

local DebuffStatus = {}

--------------------------------------------------
-- 时间值计算
--------------------------------------------------

-- 从 auraInfo 提取 start/duration/hasSecret 三元组
-- 参考 Grid2 IndicatorIcons: canaccessvalue → SetCooldownFromExpirationTime
--                        else → GetAuraDuration → DurationObject
function DebuffStatus.GetTemporal(auraInfo)
    local start, duration, hasSecret
    if F.IsValueNonSecret(auraInfo.expirationTime) and F.IsValueNonSecret(auraInfo.duration) then
        start = (auraInfo.expirationTime or 0) - auraInfo.duration
        duration = auraInfo.duration
        hasSecret = false
    else
        start = 0
        duration = 0
        hasSecret = true  -- 标记原始值是 secret，不跳过分类
    end
    return start, duration, hasSecret
end

-- DurationObject 回退：当时间值是 secret 时获取可渲染对象
-- Grid2 模式：C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
function DebuffStatus.GetDurationObject(unit, auraInstanceID)
    if C_UnitAuras and C_UnitAuras.GetAuraDuration and unit and auraInstanceID then
        return C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
    end
    return nil
end

-- 安全的 debuffType 提取
-- Grid2 模式：issecretvalue guard 在字符串操作前
function DebuffStatus.GetDebuffType(auraInfo)
    return (auraInfo.dispelName and (not issecretvalue or not issecretvalue(auraInfo.dispelName))) and auraInfo.dispelName or ""
end

--------------------------------------------------
-- 分类查询
--------------------------------------------------

function DebuffStatus.ClassifyDebuff(auraInfo)
    local isBig, isBlacklisted, isDispelBlacklisted
    if F.IsAuraNonSecret(auraInfo) then
        local spellId = auraInfo.spellId
        isBig = spellId and Cell.vars.bigDebuffs[spellId] or false
        isBlacklisted = spellId and Cell.vars.debuffBlacklist[spellId] or false
        isDispelBlacklisted = spellId and Cell.vars.dispelBlacklist[spellId] or false
    end
    return isBig or false, isBlacklisted or false, isDispelBlacklisted or false
end

--------------------------------------------------
-- 刷新状态
--------------------------------------------------

function DebuffStatus.UpdateRefreshState(auraInfo)
    if Cell.vars.iconAnimation == "duration" then
        local timeIncreased, countIncreased
        if Cell.isMidnight and (
            not F.IsValueNonSecret(auraInfo.expirationTime)
            or not F.IsValueNonSecret(auraInfo.oldExpirationTime)
            or not F.IsValueNonSecret(auraInfo.applications)
            or not F.IsValueNonSecret(auraInfo.oldApplications)
        ) then
            timeIncreased = false
            countIncreased = false
        else
            timeIncreased = auraInfo.oldExpirationTime and ((auraInfo.expirationTime or 0) - auraInfo.oldExpirationTime >= 0.5) or false
            countIncreased = auraInfo.oldApplications and (auraInfo.applications > auraInfo.oldApplications) or false
        end
        auraInfo.refreshing = timeIncreased or countIncreased
    elseif Cell.vars.iconAnimation == "stack" then
        if Cell.isMidnight and (
            not F.IsValueNonSecret(auraInfo.applications)
            or not F.IsValueNonSecret(auraInfo.oldApplications)
        ) then
            auraInfo.refreshing = false
        else
            auraInfo.refreshing = auraInfo.oldApplications and (auraInfo.applications > auraInfo.oldApplications) or false
        end
    else
        auraInfo.refreshing = false
    end

    auraInfo.oldExpirationTime = nil
    auraInfo.oldApplications = nil
end

--------------------------------------------------
-- 排序
--------------------------------------------------

function DebuffStatus.SortRaidDebuffs(button)
    sort(button._debuffs_raid, function(a, b)
        local ca = button._debuffs_cache[a]
        local cb = button._debuffs_cache[b]
        if not ca then return false end -- cache miss: push to end
        if not cb then return true end  -- cache miss: push to end
        return ca.raidDebuffOrder < cb.raidDebuffOrder
    end)
end

--------------------------------------------------
-- 变量重置
--------------------------------------------------

function DebuffStatus.ResetDebuffVars(button)
    button._debuffs.resurrectionFound = false
    button._debuffs.crowdControlsFound = 0
    button.states.BGOrb = nil
end

function DebuffStatus.ResetBuffVars(button)
    button._buffs.defensiveFound = 0
    button._buffs.externalFound = 0
    button._buffs.allFound = 0
    button._buffs.tankActiveMitigationFound = false
    button._buffs.drinkingFound = false
    button.states.BGFlag = nil
end

--------------------------------------------------
-- 暴露到 Cell 命名空间
--------------------------------------------------

Cell.DebuffStatus = DebuffStatus
