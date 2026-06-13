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

-- ============================================================================
-- 模块初始化：从全局环境获取 Cell 主模块引用（VarArg 传参机制）
-- ============================================================================
local _, Cell = ...

-- ============================================================================
-- DebuffStatus 模块表
-- 职责：为 CellD 提供在 Secret Value 环境下的光环持续时间回退方案
-- 通过 WoW API C_UnitAuras.GetAuraDuration 获取 DurationObject，
-- 绕过 combat 期间对 aura expiration/duration 字段的加密保护
-- ============================================================================
local DebuffStatus = {}

-- ============================================================================
-- GetDurationObject(unit, auraInstanceID) -> DurationObject | nil
-- ============================================================================
-- Midnight / SecretValue 防护核心函数
-- ------------------------------------------------------------
-- 背景：在战斗状态（combat）下，Blizzard 的 Midnight 安全系统会对光环的
-- expirationTime 和 duration 等字段进行加密（Secret Value），此时直接读取
-- 这些字段会得到无效/空值，导致 UnitButton 上的冷却动画无法正常渲染。
--
-- 工作原理：C_UnitAuras.GetAuraDuration 返回的是一个 DurationObject，
-- 该对象可以被 SetCooldownFromDurationObject 安全消费，从而绕过
-- Secret Value 限制，正确显示冷却进度。这是 Grid2 风格的成熟方案。
--
-- 参数：
--   unit           - 单位 ID（如 "player", "target", "raid1" 等）
--   auraInstanceID - 光环实例 ID（由 UNIT_AURA 事件提供）
--
-- 返回值：
--   DurationObject - 可传给 SetCooldownFromDurationObject 的对象
--   nil            - 当 API 不可用、参数无效、或光环不存在时
-- ============================================================================
function DebuffStatus.GetDurationObject(unit, auraInstanceID)
    -- 防卫性检查：确保 API 命名空间存在、函数存在、且调用参数均非 nil/false
    -- C_UnitAuras 可能在极旧客户端中不存在，GetAuraDuration 可能被 Blizzard 移除
    if C_UnitAuras and C_UnitAuras.GetAuraDuration and unit and auraInstanceID then
        -- 调用 WoW API 获取 DurationObject，绕过 Secret Value 加密
        return C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
    end
    -- 安全回退：任何前置条件不满足时返回 nil，
    -- 调用方（UnitButton.lua）将跳过本帧的冷却更新，避免错误渲染
    return nil
end

-- ============================================================================
-- 将 DebuffStatus 模块挂载到 Cell 主模块上，供其他模块（如 UnitButton.lua）
-- 通过 Cell.DebuffStatus.GetDurationObject() 调用
-- ============================================================================
Cell.DebuffStatus = DebuffStatus
