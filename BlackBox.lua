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

-- 从 CellD 主模块获取核心引用
-- Cell: 主模块表，包含所有核心数据和回调系统
-- F (Cell.funcs): 全局函数工具集，包括 SafeNumber、SafeCompareGE 等安全包装函数
-- L (Cell.L): 本地化字符串表
local _, Cell = ...
local F = Cell.funcs
local L = Cell.L

--------------------------------------------------
-- Secret Value 检测工具
-- Midnight 12.0.0+ 引入了 Secret Value（不透明类型）机制，
-- 在战斗中对敏感游戏数据进行包装，禁止直接读取/比较/运算。
-- 以下工具函数提供了安全的包装层，通过 pcall 捕获错误并返回安全的回退值。
--------------------------------------------------

-- 判断一个值是否为 Secret Value（opaque type）
-- Secret Value 的特征：对任何操作都会抛出 "secret" 相关错误
-- 原理：暴雪在 Midnight 版本中提供了 issecretvalue 全局函数，
--       可以识别所有被包装的类型（number、string、fileID 等）。
--       如果 issecretvalue 函数不存在（旧版本客户端），则始终返回 false。
-- 参数 v: 待检测的任意 Lua 值
-- 返回值: boolean —— true 表示该值是 Secret Value
function F.IsSecretValue(v)
    -- 使用 Blizzard issecretvalue 全局函数（Midnight 12.0.0+）
    -- 支持所有 secret 类型：number、string、fileID 等
    -- 参考 Grid2 实现：GridUtils.lua
    if issecretvalue then
        return issecretvalue(v)
    end
    return false
end

-- 安全数值转换：将任意值安全地转换为 number 类型
-- 适用场景：UnitHealth、UnitPower、GetDamageAbsorbs 等 API 在战斗中
--           可能返回 Secret Value，直接使用会导致 Lua 错误。
-- 参数 v: 待转换的值（可能是 number、Secret Value 或 nil）
-- 参数 fallback: v 无法安全转换时使用的回退值（默认 0）
-- 返回值: number —— 安全的数值
-- 防护原理：通过 pcall 包装算术运算，如果 v 是 Secret Value，
--           运算会抛出错误，pcall 捕获后返回 fallback。
function F.SafeNumber(v, fallback)
    if v == nil then return fallback or 0 end
    if type(v) == "number" then return v end
    local ok, result = pcall(function()
        return v + 0
    end)
    if ok then return result end
    return fallback or 0
end

-- 安全大于等于比较：返回 a >= b 的结果
-- 适用场景：判断生命值是否低于阈值、比较吸收量等需要不等式的场合
-- 参数 a, b: 待比较的两个值（任意类型）
-- 返回值: boolean —— 比较结果，无法比较时返回 false（保守策略）
-- 防护原理：通过 pcall 包装比较操作，Secret Value 参与 >= 比较会抛出错误。
function F.SafeCompareGE(a, b)
    if a == nil or b == nil then return false end
    local ok, result = pcall(function()
        return a >= b
    end)
    if ok then return result end
    return false
end

-- 安全乘法：返回 a * b 的结果
-- 适用场景：计算吸收量百分比等需要乘法的场合
-- 参数 a, b: 待乘的两个值
-- 返回值: number —— 乘积，无法计算时返回 0
-- 防护原理：通过 pcall 包装乘法操作。
function F.SafeMultiply(a, b)
    if a == nil or b == nil then return 0 end
    local ok, result = pcall(function()
        return a * b
    end)
    if ok then return result end
    return 0
end

-- 安全除法：返回 a / b 的结果
-- 适用场景：计算生命值百分比（health / maxHealth）等需要除法的场合
-- 参数 a: 被除数
-- 参数 b: 除数（额外检查 b == 0 防止除零错误）
-- 返回值: number —— 商，无法计算或除数为零时返回 0
-- 防护原理：通过 pcall 包装除法操作，同时防御除零和 Secret Value 两种崩溃路径。
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
-- 功能：模拟 Secret Value 限制环境下的完整测试流程
-- 测试覆盖范围：
--   1. 基础 API（生命/能量）
--   2. 吸收量 API
--   3. 光环数据 API
--   4. 移动速度 API
--   5. 保护函数自测（SafeNumber/SafeCompareGE/SafeDivide/SafeMultiply）
--   6. 内建指示器代码路径（ShieldBar/HealthText）
--   7. UnitButton 健康计算器模块
--   8. 配置数据完整性（CellDB/version/vars）
--   9. CVar 状态报告
-- 返回值: testsPassed, testsFailed, testsSkipped（三个数字）
--------------------------------------------------
local function RunBlackBox()
    print("|cFF00FFFF[CellD-BlackBox]|r ======== Secret Value 黑箱自检开始 ========")

    -- 测试计数器：分别记录通过、失败、跳过的测试数量
    local testsPassed, testsFailed, testsSkipped = 0, 0, 0
    -- 结果收集表：按执行顺序存储每条测试结果的格式化字符串
    local results = {}

    -- 测试辅助函数：运行单个测试用例并自动判断通过/失败/Secret Value 触发
    -- 参数 name: 测试名称（用于输出报告）
    -- 参数 fn: 测试函数（无参数，通过 pcall 安全执行）
    -- 逻辑：
    --   - pcall 成功 → PASS（通过）
    --   - pcall 失败且错误信息包含 "secret"/"opaque"/"taint" → FAIL（Secret Value 保护触发）
    --   - pcall 失败且错误信息是其他内容 → FAIL（其他错误）
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

    -- 跳过测试辅助函数：当测试前提不满足时（如不在队伍中）跳过测试
    -- 参数 name: 测试名称
    -- 参数 reason: 跳过原因
    local function skipTest(name, reason)
        testsSkipped = testsSkipped + 1
        tinsert(results, "|cFFFFFF00[SKIP]|r " .. name .. " - " .. reason)
    end

    --------------------------------------------------
    -- 1. 基础 API 检测
    -- 目的：验证 UnitHealth/UnitHealthMax/UnitPower/UnitPowerMax
    --       在 Secret Value 环境下能否通过安全函数正常访问。
    -- 原理：这些 API 在战斗中返回 Secret Value，直接运算会崩溃。
    --       使用 F.SafeCompareGE 包装比较操作来绕过限制。
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
    -- 目的：验证吸收量 API 在 Secret Value 环境下的安全性。
    -- 原理：UnitGetTotalAbsorbs 返回的吸收总量在战斗中可能是 Secret Value，
    --       使用 F.SafeNumber 进行安全包装。
    -- 注意：此 API 的后备名是 GetDamageAbsorbs，测试名称中保留了两者以方便排查。
    print("|cFF00FFFF[CellD-BlackBox]|r --- 吸收量检测 ---")

    runTest("GetDamageAbsorbs (UnitGetTotalAbsorbs)", function()
        local absorbs = UnitGetTotalAbsorbs("player")
        if absorbs then
            F.SafeNumber(absorbs, -1)
        end
    end)

    -- 3. 光环数据检测
    -- 目的：验证光环持续时间/过期时间在 Secret Value 环境下的安全性。
    -- 原理：C_UnitAuras.GetAuraDataByIndex 返回的 aura 表中，
    --       duration 和 expirationTime 字段在战斗中可能是 Secret Value。
    --       使用 F.SafeNumber 进行安全包装。
    -- 注意：需要 WoW 11.0.7+ 或 Midnight 版本才支持此 API。
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
    -- 目的：验证 GetUnitSpeed 在 Secret Value 环境下的安全性。
    -- 原理：GetUnitSpeed 返回的移动速度在战斗中可能是 Secret Value，
    --       使用 F.SafeNumber 进行安全包装。
    -- 注意：GetUnitSpeed 函数在极旧客户端不存在，需先检查存在性。
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
    -- 目的：验证所有 F.Safe* 安全包装函数在正常输入下的行为正确性。
    -- 原理：用已知的非 Secret 值（nil、纯数字）测试每个安全函数，
    --       确保它们在正常环境中返回预期结果，不会误报或产生错误。
    -- 这是自检模块的"自检"——如果这部分失败，其他所有测试结果都不可信。
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
    -- 目的：模拟插件内建指示器（ShieldBar、HealthText）中对 Secret Value 的典型操作路径。
    -- 原理：ShieldBar 需要读取吸收量并计算百分比，HealthText 需要计算生命值比例。
    --       这些操作在战斗中如果直接使用原始 Secret Value 会崩溃。
    --       测试通过 F.SafeCompareGE、F.SafeMultiply、F.SafeDivide 包装后是否安全。
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
    -- 目的：验证 UnitButton 的 healthCalculator 模块
    --       在 Secret Value 环境下的运行时安全性。
    -- 原理：healthCalculator:GetDamageAbsorbs() 可能返回 Secret Value，
    --       需通过 F.SafeNumber 安全处理。
    -- 注意：此测试依赖于单位按钮是否存在（需要玩家在队伍/团队中）。
    --       如果不在队伍中则跳过（SKIP）。
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
    -- 目的：验证 CellD 核心数据结构在运行时的完整性。
    -- 检测项：
    --   - CellDB 全局数据库是否存在且为 table（存储所有插件设置）
    --   - Cell.version 是否存在且为字符串（版本号，用于兼容性判断）
    --   - Cell.vars.playerClass/playerSpecID 是否已设置（职业和专精标识）
    -- 注意：这些不涉及 Secret Value，但补充验证可以排除非 Secret Value 相关的崩溃。
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
    -- 目的：报告所有与 Secret Value 相关的 CVar 当前状态。
    -- CVar 列表及含义：
    --   - secretCombatRestrictionsForced:     普通战斗中的 Secret Value 限制
    --   - secretEncounterRestrictionsForced:   首领战（Raid Boss）中的限制
    --   - secretChallengeModeRestrictionsForced: 大秘境中的限制
    --   - secretPvPMatchRestrictionsForced:     PvP 比赛中的限制
    -- 输出格式：已开启（红色）/ 已关闭（绿色）
    -- 注意：CVar 值通过 pcall 安全读取，避免 C_CVar API 不可用时崩溃。
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

    -- 总结：遍历所有测试结果并汇总输出
    -- 输出顺序：先输出自检完成的标题行，然后逐条输出每个测试的 PASS/FAIL/SKIP 结果，
    --          最后输出汇总统计（通过/失败/跳过数量）。
    -- 异常情况：如果存在 FAIL 的测试，额外输出警告提示用户在非战斗环境复查。
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
-- 注册斜杠命令与事件回调
-- CellD 使用两种机制暴露 BlackBox 入口：
--   1. 全局函数 _G.CellD_BlackBox: Core.lua 的斜杠命令处理函数通过此全局引用
--      来调用 RunBlackBox，实现 /celld blackbox 命令。
--   2. Cell 回调系统: 注册 "BlackBox_Run" 事件，其他模块可以通过
--      Cell.FireCallback("BlackBox_Run", "RunBlackBox") 触发自检。
-- 双入口设计使得自检既可以手动触发（斜杠命令），也可以被自动化流程调用（回调系统）。
--------------------------------------------------
Cell.RegisterCallback("BlackBox_Run", "RunBlackBox", RunBlackBox)

-- 在 Core.lua 的斜杠命令处理中添加 /celld blackbox
-- 此处定义函数，实际命令注册在 Core.lua 中
_G.CellD_BlackBox = RunBlackBox

-- 打印加载信息（仅 Debug 模式下可见）
F.Debug("|cFF00FF00[BlackBox]|r 黑箱自检模块已加载。使用 /celld blackbox 运行自检。")
