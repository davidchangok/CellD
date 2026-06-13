--[[
    CellD 集中化 Debuff/Buff 状态模块 (DebuffStatus.lua)
    =====================================================
    借鉴 Grid2 StatusAuras.lua 设计模式，将 UnitButton.lua 中原先分散的
    纯函数集中管理。HandleDebuff/HandleBuff 的热路径（时间值计算、debuffType
    提取、分类查询）保持内联以保证 combat 环境下的可靠性。

    本模块提供：
    1. DurationObject 回退（C_UnitAuras.GetAuraDuration）
    2. 光环刷新状态（UpdateRefreshState）
    3. raidDebuffs 排序（含 cache miss nil guard）
    4. 变量重置（ResetDebuffVars / ResetBuffVars）

    Grid2 参考：
    - StatusAuras.lua: Shared.GetIcons() → GetUnitAuras 批量获取
    - IndicatorIcons.lua: canaccessvalue → DurationObject fallback
    - GridUtils.lua: issecretvalue/canaccessvalue 全局原语
--]]

local _, Cell = ...
local F = Cell.funcs

local DebuffStatus = {}

--------------------------------------------------
-- DurationObject 回退（Grid2 模式）
--------------------------------------------------

function DebuffStatus.GetDurationObject(unit, auraInstanceID)
    if C_UnitAuras and C_UnitAuras.GetAuraDuration and unit and auraInstanceID then
        return C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
    end
    return nil
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
-- 排序（含 cache miss nil guard）
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
