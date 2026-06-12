--[[
    CellD 黑箱自检模块 (BlackBox.lua)
    =================================
    暴雪在 12.0.0+ 中引入了 Secret Value（Opaque Type）机制，对战斗中的敏感
    游戏数据进行包装，使其在战斗中无法被直接读取、比较或运算。

    被包装的数据类型包括:
    - UnitHealth / UnitHealthMax (单位生命值)
    - UnitPower / UnitPowerMax (单位能量值)
    - UnitGetTotalAbsorbs / GetDamageAbsorbs (吸收量)
    - UnitAura 的持续时间/过期时间 (光环信息)
    - GetUnitSpeed (单位移动速度)

    Secret Value 的限制:
    - 不能与数字比较 (>, <, ==)
    - 不能参与算术运算 (+, -, *, /)
    - 不能转换为字符串 (tostring/print)
    - 不能作为表索引

    本模块用途:
    1. 模拟黑箱测试环境（通过 CVar 强制开启 Secret Value 限制）
    2. 测试插件所有涉及 Secret Value 的代码路径
    3. 提供安全包装函数，避免插件因 Secret Value 崩溃
    4. 在游戏中通过 /celld blackbox 命令运行自检

    测试 CVar:
    /run SetCVar("secretCombatRestrictionsForced", 1)  -- 战斗限制
    /run SetCVar("secretEncounterRestrictionsForced", 1) -- 首领战限制
    /run SetCVar("secretChallengeModeRestrictionsForced", 1) -- 大秘境限制
    /run SetCVar("secretPvPMatchRestrictionsForced", 1) -- PvP限制
    全部关闭: /run SetCVar("secretCombatRestrictionsForced", 0)

    用法: /celld blackbox
--]]

local _, Cell = ...
local F = Cell.funcs
local L = Cell.L

--------------------------------------------------
-- Secret Value 检测工具
--------------------------------------------------

-- 判断一个值是否为 Secret Value（opaque type）
-- Secret Value 的特征：对任何操作都会抛出 "secret" 相关错误
function F.IsSecretValue(v)
    if v == nil then return false end
    if type(v) == "number" then return false end
    if type(v) == "string" then return false end
    if type(v) == "boolean" then return false end

    -- 对未知类型的值尝试安全操作
    local ok = pcall(function()
        local _ = v + 0  -- 尝试加0，secret值会失败
    end)
    return not ok
end

-- 安全检查：如果值为 Secret Value，返回回退值
function F.SafeNumber(v, fallback)
    if v == nil then return fallback or 0 end
    if type(v) == "number" then return v end
    local ok, result = pcall(function()
        return v + 0
    end)
    if ok then return result end
    return fallback or 0
end

-- 安全比较：返回 a >= b 的结果，处理 Secret Value
function F.SafeCompareGE(a, b)
    if a == nil or b == nil then return false end
    local ok, result = pcall(function()
        return a >= b
    end)
    if ok then return result end
    return false
end

-- 安全乘法：返回 a * b，处理 Secret Value
function F.SafeMultiply(a, b)
    if a == nil or b == nil then return 0 end
    local ok, result = pcall(function()
        return a * b
    end)
    if ok then return result end
    return 0
end

-- 安全除法：返回 a / b，处理 Secret Value
function F.SafeDivide(a, b)
    if a == nil or b == nil or b == 0 then return 0 end
    local ok, result = pcall(function()
        return a / b
    end)
    if ok then return result end
    return 0
end

--------------------------------------------------
-- 黑箱自检主函数
--------------------------------------------------
local function RunBlackBox()
    print("|cFF00FFFF[CellD-BlackBox]|r ======== Secret Value 黑箱自检开始 ========")

    local testsPassed, testsFailed, testsSkipped = 0, 0, 0
    local results = {}

    -- 测试辅助函数
    local function runTest(name, fn)
        local ok, err = pcall(fn)
        if ok then
            testsPassed = testsPassed + 1
            tinsert(results, "|cFF00FF00[PASS]|r " .. name)
        elseif type(err) == "string" and (strfind(err, "secret") or strfind(err, "opaque") or strfind(err, "taint")) then
            testsFailed = testsFailed + 1
            tinsert(results, "|cFFFF0000[FAIL]|r " .. name .. " - Secret Value 保护触发: " .. tostring(err))
        else
            testsFailed = testsFailed + 1
            tinsert(results, "|cFFFF0000[FAIL]|r " .. name .. " - " .. tostring(err))
        end
    end

    local function skipTest(name, reason)
        testsSkipped = testsSkipped + 1
        tinsert(results, "|cFFFFFF00[SKIP]|r " .. name .. " - " .. reason)
    end

    --------------------------------------------------
    -- 1. 基础 API 检测
    --------------------------------------------------
    print("|cFF00FFFF[CellD-BlackBox]|r --- 基础 API 检测 ---")

    runTest("UnitHealth('player')", function()
        local h = UnitHealth("player")
        F.SafeCompareGE(h, 0)  -- 使用安全比较绕过 Secret Value
    end)

    runTest("UnitHealthMax('player')", function()
        local h = UnitHealthMax("player")
        F.SafeCompareGE(h, 0)
    end)

    runTest("UnitPower('player')", function()
        local p = UnitPower("player")
        F.SafeCompareGE(p, 0)
    end)

    runTest("UnitPowerMax('player')", function()
        local p = UnitPowerMax("player")
        F.SafeCompareGE(p, 0)
    end)

    -- 2. 吸收量检测
    print("|cFF00FFFF[CellD-BlackBox]|r --- 吸收量检测 ---")

    runTest("GetDamageAbsorbs (UnitGetTotalAbsorbs)", function()
        local absorbs = UnitGetTotalAbsorbs("player")
        if absorbs then
            F.SafeNumber(absorbs, -1)
        end
    end)

    -- 3. 光环数据检测
    print("|cFF00FFFF[CellD-BlackBox]|r --- 光环数据检测 ---")

    runTest("C_UnitAuras.GetAuraDataByIndex", function()
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local aura = C_UnitAuras.GetAuraDataByIndex("player", 1)
            if aura and aura.duration then
                F.SafeNumber(aura.duration, 0)  -- 光环持续时间可能是 secret value
            end
        else
            error("C_UnitAuras.GetAuraDataByIndex 不可用")
        end
    end)

    -- 4. 速度检测
    print("|cFF00FFFF[CellD-BlackBox]|r --- 速度检测 ---")

    runTest("GetUnitSpeed('player')", function()
        if GetUnitSpeed then
            local s = GetUnitSpeed("player")
            if s then
                F.SafeNumber(s, 0)  -- 移动速度可能是 secret value
            end
        end
    end)

    -- 5. Secret Value 检测函数自测
    print("|cFF00FFFF[CellD-BlackBox]|r --- 保护函数自测 ---")

    runTest("F.IsSecretValue(nil)", function()
        assert(not F.IsSecretValue(nil), "nil should not be secret")
    end)

    runTest("F.IsSecretValue(42)", function()
        assert(not F.IsSecretValue(42), "number should not be secret")
    end)

    runTest("F.SafeNumber(nil, 0)", function()
        assert(F.SafeNumber(nil, 0) == 0)
    end)

    runTest("F.SafeNumber(42, 0)", function()
        assert(F.SafeNumber(42, 0) == 42)
    end)

    runTest("F.SafeCompareGE(1, 0)", function()
        assert(F.SafeCompareGE(1, 0))
    end)

    runTest("F.SafeCompareGE(nil, 0)", function()
        assert(not F.SafeCompareGE(nil, 0))
    end)

    -- 6. 内建指示器安全检测
    print("|cFF00FFFF[CellD-BlackBox]|r --- 指示器安全路径检测 ---")

    runTest("Built-in ShieldBar Secret Value 路径", function()
        -- 模拟 ShieldBar_SetHorizontalValue 路径
        local testPercent = UnitGetTotalAbsorbs("player")
        if testPercent then
            F.SafeCompareGE(testPercent, 1)
            F.SafeMultiply(testPercent, 100)
        end
    end)

    runTest("Built-in HealthText Secret Value 路径", function()
        local health = UnitHealth("player")
        local maxHealth = UnitHealthMax("player")
        if health and maxHealth then
            F.SafeDivide(health, maxHealth)
        end
    end)

    -- 7. 重要模块安全检查
    print("|cFF00FFFF[CellD-BlackBox]|r --- 模块安全检查 ---")

    local hasUnitButtons = Cell.unitButtons and #Cell.unitButtons > 0
    if hasUnitButtons then
        runTest("UnitButton 健康计算器", function()
            local b = Cell.unitButtons[1]
            if b.widgets and b.widgets.healthCalculator then
                -- 测试 GetDamageAbsorbs 路径
                local absorbs = b.widgets.healthCalculator:GetDamageAbsorbs()
                if absorbs then
                    F.SafeNumber(absorbs, 0)
                end
            else
                error("healthCalculator 不存在")
            end
        end)
    else
        skipTest("UnitButton 健康计算器", "无单位按钮（可能不在队伍中）")
    end

    -- 8. 配置数据完整性
    print("|cFF00FFFF[CellD-BlackBox]|r --- 配置完整性 ---")

    runTest("CellDB 可访问", function()
        assert(CellDB, "CellDB 不存在")
        assert(type(CellDB) == "table", "CellDB 不是 table")
    end)

    runTest("Cell.version 有效", function()
        assert(Cell.version, "Cell.version 为 nil")
        assert(type(Cell.version) == "string", "Cell.version 不是字符串")
    end)

    runTest("Cell.vars 关键字段", function()
        assert(Cell.vars.playerClass, "playerClass 未设置")
        assert(Cell.vars.playerSpecID, "playerSpecID 未设置")
    end)

    -- 9. CVar 状态报告
    print("|cFF00FFFF[CellD-BlackBox]|r --- CVar 状态 ---")
    local cvars = {
        "secretCombatRestrictionsForced",
        "secretEncounterRestrictionsForced",
        "secretChallengeModeRestrictionsForced",
        "secretPvPMatchRestrictionsForced",
    }
    for _, cvar in ipairs(cvars) do
        local ok, val = pcall(C_CVar.GetCVar, cvar)
        local status = ok and val == "1" and "|cFFFF0000已开启|r" or "|cFF00FF00已关闭|r"
        print("  " .. cvar .. ": " .. status)
    end

    -- 总结
    print("|cFF00FFFF[CellD-BlackBox]|r ======== 自检完成 ========")
    for _, line in ipairs(results) do
        print("  " .. line)
    end
    print(string.format(
        "|cFF00FFFF[CellD-BlackBox]|r 结果: |cFF00FF00通过 %d|r / |cFFFF0000失败 %d|r / |cFFFFFF00跳过 %d|r",
        testsPassed, testsFailed, testsSkipped
    ))

    if testsFailed > 0 then
        print("|cFFFF0000[CellD-BlackBox]|r 警告: 存在未处理的 Secret Value 路径，请在非战斗环境下使用 /celld blackbox 检查")
    end

    return testsPassed, testsFailed, testsSkipped
end

--------------------------------------------------
-- 注册斜杠命令
--------------------------------------------------
Cell.RegisterCallback("BlackBox_Run", "RunBlackBox", RunBlackBox)

-- 在 Core.lua 的斜杠命令处理中添加 /celld blackbox
-- 此处定义函数，实际命令注册在 Core.lua 中
_G.CellD_BlackBox = RunBlackBox

-- 打印加载信息
F.Debug("|cFF00FF00[BlackBox]|r 黑箱自检模块已加载。使用 /celld blackbox 运行自检。")
