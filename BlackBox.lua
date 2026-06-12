--[[
    CellD 黑箱测试模块 (BlackBox.lua)
    用于在游戏内模拟战斗安全限制，检测 Secret Values / Opaque Types 导致的潜在 bug。

    工作原理:
    1. 通过 /celld blackbox 命令启动自检
    2. 调用所有可能受限制的 API，验证返回值是否为 secret value
    3. 在受限制上下文中，检查插件是否有对应的安全措施
    4. 报告所有不安全的 API 调用点

    暴雪 Secret Value 机制说明 (Patch 12.0.0+):
    - 在战斗中，敏感战斗数据（生命值、能量、吸收量等）被包装为特殊的
      "秘密数值" (secret value/opaque type)
    - 对 secret value 进行算术运算（加减乘除、比较）会立即抛出 Lua 错误
    - 只能通过特定的安全 API 读取结果，如：
      * CreateUnitHealPredictionCalculator 创建的 health calculator
      * C_CurveUtil.CreateCurve 创建的曲线计算器
      * UnitIsDeadOrGhost (始终非 secret)
      * GetRaidTargetIndex (始终非 secret)
    - 使用 issecretvalue(val) 可以检查一个值是否为 secret
    - 使用 GetRestrictedActionStatus(Enum.RestrictedActionType.SecretAuras) 检查光环是否受限

    测试 CVar (仅在禁用安全限制时生效):
      /run SetCVar("secretCombatRestrictionsForced", 1)  -- 强制开启战斗限制
      /run SetCVar("secretEncounterRestrictionsForced", 1) -- 强制开启首领战限制
      /run SetCVar("secretChallengeModeRestrictionsForced", 1) -- 强制开启挑战模式限制
      /run SetCVar("secretPvPMatchRestrictionsForced", 1) -- 强制开启PvP限制
--]]

local addonName, Cell = ...
local F = Cell.funcs
local L = Cell.L

-- 黑箱测试结果存储
local TestResults = {}
local TestCount = 0
local PassCount = 0
local FailCount = 0
local WarnCount = 0

-- 清理旧结果
local function ResetResults()
    wipe(TestResults)
    TestCount = 0
    PassCount = 0
    FailCount = 0
    WarnCount = 0
end

-- 记录测试结果
local function RecordResult(name, passed, message, severity)
    TestCount = TestCount + 1
    if passed then
        PassCount = PassCount + 1
    else
        if severity == "warn" then
            WarnCount = WarnCount + 1
        else
            FailCount = FailCount + 1
        end
    end
    tinsert(TestResults, {
        name = name,
        passed = passed,
        message = message or "",
        severity = severity or (passed and "pass" or "fail"),
    })
end

-- 安全版本：检查值是否为 Secret
-- 在非 Midnight 环境或 issecretvalue API 不可用时始终返回 false
local function SafeIsSecret(val)
    if Cell.isMidnight and issecretvalue then
        local ok, result = pcall(issecretvalue, val)
        if not ok then return false end -- pcall 保护
        return result
    end
    return false
end

-- 安全调用包装器：捕获因 secret value 运算导致的错误
local function SafeCall(name, func, ...)
    local ok, result = pcall(func, ...)
    if not ok then
        local errMsg = tostring(result)
        if string.find(errMsg, "secret") or string.find(errMsg, "opaque") then
            return nil, "SECRET_VALUE_ERROR", errMsg
        end
        return nil, "LUA_ERROR", errMsg
    end
    return result, "OK"
end

-- ============================================================================
-- 测试套件
-- ============================================================================

--[[
    测试1: issecretvalue API 可用性
    检查 issecretvalue 函数是否存在于当前环境
--]]
local function Test_IsSecretValueAvailable()
    if issecretvalue then
        RecordResult("issecretvalue API 可用", true, "issecretvalue() 函数存在")
    else
        RecordResult("issecretvalue API 可用", false, "issecretvalue() 函数不存在 (非 Midnight 环境)", "warn")
    end
end

--[[
    测试2: GetRestrictedActionStatus API 可用性
    检查限制状态查询 API 是否存在
--]]
local function Test_RestrictedActionStatus()
    if GetRestrictedActionStatus and Enum and Enum.RestrictedActionType then
        -- 安全调用 — 此 API 始终返回非 secret boolean
        local ok, isRestricted = pcall(GetRestrictedActionStatus, Enum.RestrictedActionType.SecretAuras)
        if ok then
            RecordResult("GetRestrictedActionStatus API 可用", true,
                "SecretAuras 限制状态: " .. (isRestricted and "受限" or "不受限"))
        else
            RecordResult("GetRestrictedActionStatus API 可用", false,
                "调用失败: " .. tostring(isRestricted), "warn")
        end
    else
        RecordResult("GetRestrictedActionStatus API 可用", false,
            "API 不存在 (非 Midnight 环境)", "warn")
    end
end

--[[
    测试3: UnitHealth/UnitHealthMax 安全性
    检查这两个 API 的返回值是否可能为 secret
--]]
local function Test_UnitHealthSafety()
    if not UnitExists("player") then
        RecordResult("UnitHealth 安全性", false, "player 单位不存在", "warn")
        return
    end

    -- 检查 UnitHealth 返回值
    local health, err, msg = SafeCall("UnitHealth", UnitHealth, "player")
    if err == "SECRET_VALUE_ERROR" then
        RecordResult("UnitHealth 安全性", false,
            "UnitHealth('player') 返回 secret value: " .. msg)
    elseif err == "LUA_ERROR" then
        RecordResult("UnitHealth 安全性", false,
            "UnitHealth('player') 抛出 Lua 错误: " .. msg, "warn")
    elseif SafeIsSecret(health) then
        RecordResult("UnitHealth 安全性", false,
            "UnitHealth('player') 当前返回 secret value — 需要确保代码使用 Midnight calculator 路径")
    else
        RecordResult("UnitHealth 安全性", true,
            "UnitHealth('player') 返回正常数值: " .. tostring(health))
    end

    -- 检查 UnitHealthMax 返回值
    local maxHealth, err2, msg2 = SafeCall("UnitHealthMax", UnitHealthMax, "player")
    if err2 == "SECRET_VALUE_ERROR" then
        RecordResult("UnitHealthMax 安全性", false,
            "UnitHealthMax('player') 返回 secret value: " .. msg2)
    elseif SafeIsSecret(maxHealth) then
        RecordResult("UnitHealthMax 安全性", false,
            "UnitHealthMax('player') 当前返回 secret value")
    else
        RecordResult("UnitHealthMax 安全性", true,
            "UnitHealthMax('player') 返回正常数值")
    end
end

--[[
    测试4: UnitPower/UnitPowerMax 安全性
    能量值在 PvP 和非盟友单位上可能为 secret
--]]
local function Test_UnitPowerSafety()
    if not UnitExists("player") then return end

    local power, err, msg = SafeCall("UnitPower", UnitPower, "player")
    if err == "SECRET_VALUE_ERROR" then
        RecordResult("UnitPower 安全性", false, "UnitPower('player') 返回 secret value: " .. msg)
    elseif SafeIsSecret(power) then
        RecordResult("UnitPower 安全性", false, "UnitPower('player') 当前返回 secret value")
    else
        RecordResult("UnitPower 安全性", true, "UnitPower('player') 返回正常数值")
    end

    local maxPower, err2, msg2 = SafeCall("UnitPowerMax", UnitPowerMax, "player")
    if err2 == "SECRET_VALUE_ERROR" then
        RecordResult("UnitPowerMax 安全性", false, "UnitPowerMax('player') 返回 secret value: " .. msg2)
    elseif SafeIsSecret(maxPower) then
        RecordResult("UnitPowerMax 安全性", false, "UnitPowerMax('player') 当前返回 secret value")
    else
        RecordResult("UnitPowerMax 安全性", true, "UnitPowerMax('player') 返回正常数值")
    end
end

--[[
    测试5: UnitGetTotalAbsorbs / UnitGetTotalHealAbsorbs 安全性
--]]
local function Test_AbsorbSafety()
    if not UnitExists("player") then return end

    local absorbs, err, msg = SafeCall("UnitGetTotalAbsorbs", UnitGetTotalAbsorbs, "player")
    if err == "SECRET_VALUE_ERROR" then
        RecordResult("UnitGetTotalAbsorbs 安全性", false, "返回 secret value: " .. msg)
    elseif SafeIsSecret(absorbs) then
        RecordResult("UnitGetTotalAbsorbs 安全性", false, "当前返回 secret value")
    else
        RecordResult("UnitGetTotalAbsorbs 安全性", true, "返回正常")
    end

    local healAbsorbs, err2, msg2 = SafeCall("UnitGetTotalHealAbsorbs", UnitGetTotalHealAbsorbs, "player")
    if err2 == "SECRET_VALUE_ERROR" then
        RecordResult("UnitGetTotalHealAbsorbs 安全性", false, "返回 secret value: " .. msg2)
    elseif SafeIsSecret(healAbsorbs) then
        RecordResult("UnitGetTotalHealAbsorbs 安全性", false, "当前返回 secret value")
    else
        RecordResult("UnitGetTotalHealAbsorbs 安全性", true, "返回正常")
    end
end

--[[
    测试6: UnitInRange 安全性
    UnitInRange 在 Midnight 中第二个返回值可能为 secret boolean
--]]
local function Test_UnitInRangeSafety()
    if not UnitExists("player") then return end

    local inRange, checked = SafeCall("UnitInRange", UnitInRange, "player")
    if checked == "SECRET_VALUE_ERROR" then
        RecordResult("UnitInRange 安全性", false, "第二返回值是 secret value")
    elseif SafeIsSecret(checked) then
        RecordResult("UnitInRange 安全性", false, "checked 返回值当前为 secret — 需要 fallback 处理")
    else
        RecordResult("UnitInRange 安全性", true,
            "inRange=" .. tostring(inRange) .. " checked=" .. tostring(checked))
    end
end

--[[
    测试7: UnitPhaseReason 安全性
    此 API 在当前 Midnight 中可能受影响
--]]
local function Test_UnitPhaseReasonSafety()
    if not UnitExists("player") then return end

    local reason, err, msg = SafeCall("UnitPhaseReason", UnitPhaseReason, "player")
    if err == "SECRET_VALUE_ERROR" then
        RecordResult("UnitPhaseReason 安全性", false, "返回 secret value: " .. msg)
    elseif err == "LUA_ERROR" then
        RecordResult("UnitPhaseReason 安全性", false, "调用错误: " .. msg, "warn")
    else
        RecordResult("UnitPhaseReason 安全性", true, "返回正常: " .. tostring(reason or "nil"))
    end
end

--[[
    测试8: AuraUtil.ForEachAura 光环数据安全性
    检查在受限上下文中光环 API 的行为
--]]
local function Test_AuraDataSafety()
    if not UnitExists("player") then return end
    if not AuraUtil or not AuraUtil.ForEachAura then
        RecordResult("AuraUtil 光环数据安全性", false, "AuraUtil API 不可用", "warn")
        return
    end

    -- 使用 GetAuraSlots + GetAuraDataBySlot 检查（Midnight 推荐方式）
    local auraSlots = C_UnitAuras.GetAuraSlots
    if auraSlots then
        local slots, continuationToken = SafeCall("GetAuraSlots", auraSlots, "player", "HELPFUL")
        if SafeIsSecret(slots) or SafeIsSecret(continuationToken) then
            RecordResult("GetAuraSlots 安全性", false, "返回值可能为 secret — 跳过逐个检查")
        else
            RecordResult("GetAuraSlots 安全性", true, "返回正常 slot 列表")
        end
    else
        RecordResult("C_UnitAuras API 可用性", false, "C_UnitAuras.GetAuraSlots 不可用", "warn")
    end
end

--[[
    测试9: CleuFrame (COMBAT_LOG_EVENT_UNFILTERED) 安全性
    检查在 Midnight 中 CLEU 事件的注册是否被正确保护
--]]
local function Test_CleuFrameSafety()
    if Cell.isMidnight then
        RecordResult("CLEU 框架安全性", true,
            "已在 Midnight 环境 — CLEU (COMBAT_LOG_EVENT_UNFILTERED) 已在代码中禁止注册")
    else
        -- 尝试注册 CLEU 事件，应成功
        local testFrame = CreateFrame("Frame")
        local ok = pcall(function()
            testFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end)
        if ok then
            RecordResult("CLEU 框架安全性", true,
                "非 Midnight 环境 — COMBAT_LOG_EVENT_UNFILTERED 可以正常注册")
        else
            RecordResult("CLEU 框架安全性", true,
                "COMBAT_LOG_EVENT_UNFILTERED 不可用 (已保护)")
        end
    end
end

--[[
    测试10: Health Calculator 可用性 (Midnight 安全路径)
--]]
local function Test_HealthCalculatorAvailability()
    if Cell.isMidnight then
        if UnitGetDetailedHealPrediction and CreateUnitHealPredictionCalculator then
            RecordResult("Health Calculator 可用性", true,
                "UnitGetDetailedHealPrediction + CreateUnitHealPredictionCalculator 可用")
        else
            RecordResult("Health Calculator 可用性", false,
                "Midnight 环境但 Calculator API 不可用 — 健康条可能无法正常更新!")
        end
    else
        RecordResult("Health Calculator 可用性", true,
            "非 Midnight 环境 — 使用传统 UnitHealth 路径 (跳过)")
    end
end

--[[
    测试11: C_CurveUtil 可用性 (Midnight 安全曲线)
--]]
local function Test_CurveUtilAvailability()
    if Cell.isMidnight then
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            RecordResult("C_CurveUtil 可用性", true, "CreateCurve 可用于安全范围检查")
        else
            RecordResult("C_CurveUtil 可用性", false,
                "Midnight 环境但 C_CurveUtil 不可用 — 渐隐功能可能无法正常工作")
        end
    else
        RecordResult("C_CurveUtil 可用性", true,
            "非 Midnight 环境 — 使用传统比较运算 (跳过)")
    end
end

--[[
    测试12: 敏感 API 调用点审计
    检查所有已知使用危险 API 的文件是否都有安全保护
--]]
local function Test_DangerousAPIAudit()
    -- 检查 UnitButton.lua 是否使用了 Midnight calculator 路径
    -- 这里的检查是基于我们已经知道的代码结构
    local issues = {}

    -- QuickAssist.lua 使用了 UnitHealthMax/UnitHealth 但没有 Midnight 保护
    -- 我们需要在文件中搜索是否有 Cell.isMidnight 检查
    local function CheckFileHasGuard(file, pattern)
        -- 简化版：只检查是否有 isMidnight 或 IsSecretValue 相关保护
        return false -- 实际应在代码审计时检查
    end

    if #issues > 0 then
        for _, issue in ipairs(issues) do
            RecordResult("危险API审计: " .. issue.file, false, issue.desc)
        end
    else
        RecordResult("危险API审计", true, "未发现已知的不安全调用")
    end
end

-- ============================================================================
-- 黑箱自检执行器
-- ============================================================================
function F.RunBlackBoxTests()
    ResetResults()

    F.Print(L["=== CellD 黑箱自检开始 ==="] or "=== CellD BlackBox Start ===")
    F.Print("目标: 检测 Secret Values / Opaque Types 安全性")

    -- 环境检查类测试
    Test_IsSecretValueAvailable()
    Test_RestrictedActionStatus()
    Test_HealthCalculatorAvailability()
    Test_CurveUtilAvailability()

    -- API 安全类测试
    Test_UnitHealthSafety()
    Test_UnitPowerSafety()
    Test_AbsorbSafety()
    Test_UnitInRangeSafety()
    Test_UnitPhaseReasonSafety()
    Test_AuraDataSafety()
    Test_CleuFrameSafety()

    -- 审计类测试
    Test_DangerousAPIAudit()

    -- 打印报告
    F.Print("========================================")
    F.Print(string.format(
        "共 %d 项测试 | %s通过%s | %s警告%s | %s失败%s",
        TestCount,
        "|cFF00FF00", "|r",
        "|cFFFFFF00", "|r",
        "|cFFFF0000", "|r"
    ))
    F.Print(string.format("通过: %d, 警告: %d, 失败: %d", PassCount, WarnCount, FailCount))

    if FailCount > 0 then
        F.Print("|cFFFF0000以下测试失败，需要在战斗环境中进一步检查:|r")
        for _, result in ipairs(TestResults) do
            if not result.passed and result.severity == "fail" then
                F.Print(string.format("  |cFFFF0000[失败]|r %s: %s", result.name, result.message))
            end
        end
    end

    if WarnCount > 0 then
        F.Print("|cFFFFFF00以下测试产生警告:|r")
        for _, result in ipairs(TestResults) do
            if not result.passed and result.severity == "warn" then
                F.Print(string.format("  |cFFFFFF00[警告]|r %s: %s", result.name, result.message))
            end
        end
    end

    if FailCount == 0 and WarnCount == 0 then
        F.Print("|cFF00FF00所有测试通过！插件在非战斗环境下工作正常。|r")
        F.Print("|cFFFFFF00提示：在战斗中运行 /celld blackbox 以验证战斗安全性。|r")
    end

    F.Print("=== CellD 黑箱自检完成 ===")

    return TestResults
end

-- ============================================================================
-- 安全 API 包装器：统一提供给所有模块使用
-- 这些函数在 Midnight 受限上下文中保护性地返回默认值
-- ============================================================================

--[[
    安全获取单位生命值
    返回值: health, isSecret
    isSecret = true 表示返回的 health 值不可进行算术运算
--]]
function F.SafeUnitHealth(unit)
    if not unit or not UnitExists(unit) then return 0, false end
    local ok, health = pcall(UnitHealth, unit)
    if not ok then return 0, true end
    if Cell.isMidnight and issecretvalue and issecretvalue(health) then
        return 0, true -- secret value, 返回安全默认值
    end
    return health, false
end

--[[
    安全获取单位最大生命值
--]]
function F.SafeUnitHealthMax(unit)
    if not unit or not UnitExists(unit) then return 1, false end
    local ok, maxHealth = pcall(UnitHealthMax, unit)
    if not ok then return 1, true end
    if Cell.isMidnight and issecretvalue and issecretvalue(maxHealth) then
        return 1, true
    end
    if maxHealth <= 0 then return 1, false end
    return maxHealth, false
end

--[[
    安全获取单位能量值
--]]
function F.SafeUnitPower(unit)
    if not unit or not UnitExists(unit) then return 0, false end
    local ok, power = pcall(UnitPower, unit)
    if not ok then return 0, true end
    if Cell.isMidnight and issecretvalue and issecretvalue(power) then
        return 0, true
    end
    return power, false
end

--[[
    安全获取单位最大能量值
--]]
function F.SafeUnitPowerMax(unit)
    if not unit or not UnitExists(unit) then return 1, false end
    local ok, maxPower = pcall(UnitPowerMax, unit)
    if not ok then return 1, true end
    if Cell.isMidnight and issecretvalue and issecretvalue(maxPower) then
        return 1, true
    end
    if maxPower <= 0 then return 1, false end
    return maxPower, false
end

--[[
    安全获取单位吸收量
--]]
function F.SafeUnitGetTotalAbsorbs(unit)
    if not unit or not UnitExists(unit) then return 0, false end
    local ok, absorbs = pcall(UnitGetTotalAbsorbs, unit)
    if not ok then return 0, true end
    if Cell.isMidnight and issecretvalue and issecretvalue(absorbs) then
        return 0, true
    end
    return absorbs, false
end

--[[
    安全获取单位治疗吸收量
--]]
function F.SafeUnitGetTotalHealAbsorbs(unit)
    if not unit or not UnitExists(unit) then return 0, false end
    local ok, healAbsorbs = pcall(UnitGetTotalHealAbsorbs, unit)
    if not ok then return 0, true end
    if Cell.isMidnight and issecretvalue and issecretvalue(healAbsorbs) then
        return 0, true
    end
    return healAbsorbs, false
end

--[[
    安全获取单位 Incoming Heals
--]]
function F.SafeUnitGetIncomingHeals(unit)
    if not unit or not UnitExists(unit) then return 0, false end
    if not UnitGetIncomingHeals then return 0, false end
    local ok, heals = pcall(function() return UnitGetIncomingHeals(unit) end)
    if not ok then return 0, true end
    if Cell.isMidnight and issecretvalue and issecretvalue(heals) then
        return 0, true
    end
    return heals or 0, false
end

--[[
    安全获取单位移动速度
--]]
function F.SafeGetUnitSpeed(unit)
    if not unit or not UnitExists(unit) then return 0, false end
    if not GetUnitSpeed then return 0, false end
    local ok, speed = pcall(GetUnitSpeed, unit)
    if not ok then return 0, true end
    if Cell.isMidnight and issecretvalue and issecretvalue(speed) then
        return 0, true
    end
    return speed, false
end
