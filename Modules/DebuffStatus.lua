--[[
    CellD Debuff DurationObject 回退模块 (DebuffStatus.lua)
    ==========================================================
    Grid2 风格：当 aura expiration/duration 在 combat 环境下是 Secret Value 时，
    通过 C_UnitAuras.GetAuraDuration 获取 DurationObject，
    让 cooldown frame 使用 SetCooldownFromDurationObject 渲染正常冷却动画。

    参考：Grid2 IndicatorIcons.lua → canaccessvalue → DurationObject fallback

    注意：时间值计算/debuffType提取/分类/刷新状态/排序/变量重置均保持
    在 UnitButton.lua 中内联，以确保 WoW restricted 环境下的可靠性。
--]]

local _, Cell = ...

local DebuffStatus = {}

function DebuffStatus.GetDurationObject(unit, auraInstanceID)
    if C_UnitAuras and C_UnitAuras.GetAuraDuration and unit and auraInstanceID then
        return C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
    end
    return nil
end

Cell.DebuffStatus = DebuffStatus
