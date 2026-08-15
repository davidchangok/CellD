-------------------------------------------------
-- CastAuraTracker (SecretAuraTracker v1.2.0)
-- 12.1 (Curse of Ula'tek) 受限环境自己施放增益的近似显示
--
-- 背景:
--   12.1 起, 副本战斗(受限环境)中友方单位光环对插件完全不可读
--   (GetUnitAuraBySpellID 返回 nil, GetUnitAuraInstanceIDs/
--   GetAuraDataByIndex 直接抛 "Auras cannot be accessed when secret"),
--   官方 AuraContainer 数据源同样受限(已验证), 导致自己施放的增益
--   (回春术/道标/保护祝福等)无法在团队框架显示。
--   (暴雪设计: 防 MDI 竞技作弊, 见蓝贴 "Addons and Auras in Curse of Ula'tek")
--
-- 方案(纯本地, 唯一合法通道 = 第一方施放事件):
--   1. 施放事件: UNIT_SPELLCAST_SUCCEEDED(player) — spellId 非 secret(已验证)
--   2. 目标识别: OnEnter/OnLeave 悬停记录 + GetMouseFocus 兜底
--      (UnitTarget/UNIT_SPELLCAST_TARGETED 已移除, UnitName/UnitIsUnit secret)
--   3. 显示: 复用 CellD 的 icons 指示器渲染(I.CreateCombatBuffTracker),
--      视觉与脱战 Healers 指示器完全一致
--   4. 时长: 脱战扫描队友光环自学习(天赋差异自动适配) + 硬编码兜底
--   5. 追踪列表: 官方 secret 名单(never-secret 移除清单) + IsSpellKnown
--      过滤(自动读取当前角色技能表) + Healers 布局列表 + externals
--   6. 脱战(PLAYER_REGEN_ENABLED)清理全部, 交还正常指示器
-------------------------------------------------

local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs

-------------------------------------------------
-- 配置
-------------------------------------------------
local MAX_COMBAT_BUFFS = 5 -- 战斗追踪图标槽数(与 Healers 指示器 num 一致)
local MATCH_WINDOW = 2 -- 美德道标目标匹配窗口(秒)
local MAX_TARGETS = 3  -- 美德道标最多点 3 人
local BASELINE_INTERVAL = 1 -- 常驻基线轮询间隔(秒)
local MATCH_INTERVAL = 0.2  -- 美德道标匹配轮询间隔(秒)

-- 硬编码时长(秒) — 脱战自学习缓存优先, 此表为兜底默认值
local defaultDurations = {
    [200025] = 9, -- 美德道标(用户实测 12.1 数值)
}

-------------------------------------------------
-- 官方 secret 名单 (12.1 "never secret" 移除清单)
-- 来源: warcraft.wiki.gg Patch 12.1.0/API_changes "Aura Classifications"
-- 这些法术战斗中光环数据对插件完全不可读, 需施放追踪
-------------------------------------------------
local officialSecretSpells = {
    -- Preservation Evoker
    355941, 363502, 364343, 366155, 367364, 373267, 376788, 409895,
    -- Augmentation Evoker
    360827, 395152, 395296, 410089, 410263, 410686, 413984,
    -- Resto Druid
    774, 8936, 33763, 48438, 155777, 439530,
    -- Disc Priest
    17, 194384, 1253593, 1300008, 1300009,
    -- Holy Priest
    139, 41635, 77489,
    -- Mistweaver Monk
    115175, 119611, 124682, 450769, 1292922,
    -- Restoration Shaman
    974, 383648, 61295, 382024, 207400, 444490,
    -- Holy Paladin
    53563, 156322, 156910, 1244893, 200025, 431381,
}

-------------------------------------------------
-- 状态
-------------------------------------------------
local eventFrame = CreateFrame("Frame")
local tracked = {} -- [spellId] = { duration = number|nil }
local iconCache = {} -- [spellId] = fileID
local knownIDs = {} -- 美德道标 diff 基线 [unit] = {[auraInstanceID] = true}
local baselineTicker, matchTicker
local pending -- 美德道标专用 { spellId, duration, start, windowUntil, targets, count }

-------------------------------------------------
-- 追踪列表构建
-------------------------------------------------
-- 每次施放时重建(布局/指示器可能在模块加载后才初始化,
-- 缓存会导致 200025 等关键法术永久缺失)
local function BuildTrackedList()
    local ids = {}

    -- 1. 官方 secret 名单(12.1 战斗中不可读的治疗 HoT/buff, 全职业)
    --    用 IsSpellKnown 过滤: 只追踪当前角色已学会的技能
    --    (天赋不同 → 学会的技能不同 → 追踪列表自动适配)
    if IsSpellKnown then
        for _, id in ipairs(officialSecretSpells) do
            if IsSpellKnown(id) then
                ids[id] = true
            end
        end
    else
        for _, id in ipairs(officialSecretSpells) do
            ids[id] = true
        end
    end

    -- 2. 硬编码兜底(关键法术永远追踪, 不受布局/时序影响)
    for id in pairs(defaultDurations) do
        ids[id] = true
    end

    -- 3. 当前布局中自定义指示器(Healers 等)的 buff 列表
    local layoutTable = Cell.vars and Cell.vars.currentLayoutTable
    if layoutTable and layoutTable.indicators then
        for _, ind in ipairs(layoutTable.indicators) do
            local auras = ind and ind["auras"]
            if auras and ind["auraType"] == "buff" then
                for k, v in pairs(auras) do
                    -- 数组形式 {8936, 774, ...}: 值是法术 ID
                    if type(k) == "number" and type(v) == "number" then
                        ids[v] = true
                    end
                end
            end
        end
    end

    -- 4. 内置 externals(施加于他人的增益)
    if I and I.GetExternals then
        local externals = I.GetExternals()
        if externals then
            for _, spells in pairs(externals) do
                for id, v in pairs(spells) do
                    if type(id) == "number" then ids[id] = true end
                    if type(v) == "table" then
                        for subId in pairs(v) do
                            ids[subId] = true
                        end
                    end
                end
            end
        end
    end

    wipe(tracked)
    for id in pairs(ids) do
        tracked[id] = { duration = defaultDurations[id] }
    end
end

-------------------------------------------------
-- 图标
-------------------------------------------------
local function GetIconFileID(spellId)
    local icon = iconCache[spellId]
    if not icon then
        local _, i = F.GetSpellInfo(spellId)
        if i and not (F.IsSecretValue and F.IsSecretValue(i)) then
            icon = i
            iconCache[spellId] = i
        end
    end
    return icon
end

local function RefreshAllIcons()
    for spellId in pairs(tracked) do
        GetIconFileID(spellId)
    end
end

-------------------------------------------------
-- 战斗图标驱动(复用 CellD icons 指示器渲染)
-------------------------------------------------
local function CombatBuffs_Update(button)
    local icons = button.widgets and button.widgets.combatBuffs
    if not icons then return end
    local slots = button._combatBuffSlots
    local count = 0
    if slots then
        for i = 1, icons.maxNum do
            if slots[i] then
                count = count + 1
            end
        end
    end
    if count == 0 then
        icons:Hide(true)
    else
        icons:Show()
        icons:UpdateSize(count)
    end
end

local function CombatBuffs_Add(button, spellId, start, duration)
    local icons = button.widgets and button.widgets.combatBuffs
    if not icons then return end
    local slots = button._combatBuffSlots
    if not slots then
        slots = {}
        button._combatBuffSlots = slots
    end

    -- 复用同法术槽(重置计时)
    local slot
    for i = 1, icons.maxNum do
        local e = slots[i]
        if e and e.spellId == spellId then
            slot = i
            break
        end
    end
    if not slot then
        -- 空槽
        for i = 1, icons.maxNum do
            if not slots[i] then
                slot = i
                break
            end
        end
    end
    if not slot then
        -- 全满: 覆盖最早施放的槽
        local oldest, oldestStart = 1, math.huge
        for i = 1, icons.maxNum do
            local e = slots[i]
            if e and e.start < oldestStart then
                oldest, oldestStart = i, e.start
            end
        end
        slot = oldest
    end

    local old = slots[slot]
    if old and old.timer then
        old.timer:Cancel()
    end

    local icon = GetIconFileID(spellId)
    icons[slot]:SetCooldown(start, duration or 0, nil, icon, 1, false)

    local timer
    if duration and duration > 0 then
        timer = C_Timer.After(duration + 0.5, function()
            local e = button._combatBuffSlots and button._combatBuffSlots[slot]
            if e and e.spellId == spellId then
                button._combatBuffSlots[slot] = nil
                CombatBuffs_Update(button)
            end
        end)
    end
    slots[slot] = { spellId = spellId, start = start, timer = timer }
    CombatBuffs_Update(button)
end

local function CombatBuffs_Remove(button, spellId)
    local icons = button.widgets and button.widgets.combatBuffs
    local slots = button._combatBuffSlots
    if not slots then return end
    for i = 1, icons and icons.maxNum or MAX_COMBAT_BUFFS do
        local e = slots[i]
        if e and e.spellId == spellId then
            if e.timer then e.timer:Cancel() end
            slots[i] = nil
        end
    end
    CombatBuffs_Update(button)
end

local function CombatBuffs_Clear(button)
    local icons = button.widgets and button.widgets.combatBuffs
    if icons then
        icons:Hide(true)
    end
    local slots = button._combatBuffSlots
    if slots then
        for _, e in pairs(slots) do
            if e and e.timer then
                e.timer:Cancel()
            end
        end
        wipe(slots)
    end
    -- 旧版自绘图标兼容清理
    if button._SecretAuraTrackerIcon then
        button._SecretAuraTrackerIcon:Hide()
    end
    if button._CastAuraTrackerIcons then
        for i = 1, 3 do
            if button._CastAuraTrackerIcons[i] then
                button._CastAuraTrackerIcons[i]:Hide()
            end
        end
    end
end

-------------------------------------------------
-- 显示(有目标技能)
-------------------------------------------------
local function HandleCast(spellId, target, start, duration)
    F.HandleUnitButton("unit", target, function(button)
        CombatBuffs_Add(button, spellId, start, duration)
    end)
end

-------------------------------------------------
-- 清理
-------------------------------------------------
local function ClearAllIcons()
    F.IterateAllUnitButtons(CombatBuffs_Clear, true)
end

-------------------------------------------------
-- 美德道标(无目标技能)特殊处理
-------------------------------------------------
local function FinishPending()
    if not pending then return end
    local spellId = pending.spellId
    for unit in pairs(pending.targets) do
        F.HandleUnitButton("unit", unit, function(button)
            CombatBuffs_Remove(button, spellId)
        end)
    end
    F.HandleUnitButton("unit", "player", function(button)
        CombatBuffs_Remove(button, spellId)
    end)
    pending = nil
    if matchTicker then
        matchTicker:Cancel()
        matchTicker = nil
    end
end

local function IterateGroupUnits(callback)
    local n = GetNumGroupMembers() -- 总人数(含自己): 5 人小队 = 5
    if IsInRaid() then
        for i = 1, n do
            callback("raid"..i)
        end
    else
        -- 小队: 队友为 party1..party(n-1) (5 人队 = 自己 + party1-4)
        for i = 1, n - 1 do
            callback("party"..i)
        end
    end
end

local function GetUnitAuraIDs(unit)
    -- 通道1: 批量实例 ID(受限环境会抛错, pcall 兜底)
    local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, "HELPFUL")
    if ok and ids and #ids > 0 then return ids end
    -- 通道2: 按索引单取
    local result = {}
    for i = 1, 60 do
        local ok2, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok2 or not d then break end
        if d.auraInstanceID then
            result[#result + 1] = d.auraInstanceID
        end
    end
    if #result > 0 then return result end
end

local function UpdateBaseline(unit)
    local ids = GetUnitAuraIDs(unit)
    if not ids then return end
    local base = knownIDs[unit]
    if not base then
        base = {}
        knownIDs[unit] = base
    end
    for _, id in ipairs(ids) do
        base[id] = true
    end
end

local function EnsureBaselineLoop()
    if baselineTicker then return end
    baselineTicker = C_Timer.NewTicker(BASELINE_INTERVAL, function()
        if pending then return end
        IterateGroupUnits(UpdateBaseline)
    end)
end

local function MatchUnit(unit)
    if not pending then return end
    if GetTime() > pending.windowUntil then return end
    if pending.targets[unit] then return end
    if pending.count >= MAX_TARGETS then return end

    -- 通道0: 精确查询(12.1 已验证返回 nil, 保留以防版本变化)
    local ok0, d0 = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, pending.spellId, "HELPFUL")
    if ok0 and d0 and d0.auraInstanceID then
        pending.targets[unit] = true
        pending.count = pending.count + 1
        F.HandleUnitButton("unit", unit, function(button)
            CombatBuffs_Add(button, pending.spellId, pending.start, pending.duration)
        end)
        return
    end

    -- 通道1/2: 光环实例 diff
    local ids = GetUnitAuraIDs(unit)
    if not ids then return end

    local base = knownIDs[unit]
    if not base then
        base = {}
        for _, id in ipairs(ids) do
            base[id] = true
        end
        knownIDs[unit] = base
        return
    end

    local matched
    for _, id in ipairs(ids) do
        if not base[id] then
            base[id] = true
            local ok2, d = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
            if ok2 and d then
                local sid = d.spellId
                if sid == nil or (F.IsSecretValue and F.IsSecretValue(sid)) then
                    matched = true
                end
            end
        end
    end

    if matched then
        pending.targets[unit] = true
        pending.count = pending.count + 1
        F.HandleUnitButton("unit", unit, function(button)
            CombatBuffs_Add(button, pending.spellId, pending.start, pending.duration)
        end)
    end
end

local function StartMatchPolling()
    if matchTicker then matchTicker:Cancel() end
    matchTicker = C_Timer.NewTicker(MATCH_INTERVAL, function()
        if not pending then
            if matchTicker then matchTicker:Cancel() matchTicker = nil end
            return
        end
        if GetTime() > pending.windowUntil then
            if matchTicker then matchTicker:Cancel() matchTicker = nil end
            return
        end
        IterateGroupUnits(MatchUnit)
    end)
end

local function StartBeaconTracking(spellId, duration)
    FinishPending()
    local start = GetTime()
    pending = {
        spellId = spellId,
        duration = duration,
        start = start,
        windowUntil = start + MATCH_WINDOW,
        targets = {},
        count = 0,
    }
    EnsureBaselineLoop()
    StartMatchPolling()

    -- 兜底: 玩家自己框架显示"激活中"
    F.HandleUnitButton("unit", "player", function(button)
        CombatBuffs_Add(button, spellId, start, duration)
    end)

    C_Timer.After((duration or 9) + 1, function()
        if pending and pending.spellId == spellId then
            FinishPending()
        end
    end)
end

-------------------------------------------------
-- 获取施放目标(unit token)
-- 12.1 战斗中目标识别通道盘点:
--   ❌ UnitTarget / UNIT_SPELLCAST_TARGETED: 已移除
--   ❌ UnitName: 返回 secret string (身份保护)
--   ❌ UnitIsUnit: 返回 secret boolean (比较保护)
--   ✅ OnEnter/OnLeave hook 记录当前悬停的单位(点击/悬停施法场景)
--   ✅ GetMouseFocus: 兜底
-- 返回 nil 时由调用方决定兜底(无目标技能走 StartBeaconTracking)。
local function GetCastTargetToken()
    -- 优先: 当前悬停的 CellD 按钮(OnEnter/OnLeave 维护, 比 GetMouseFocus 可靠)
    local unit = Cell.vars.secretAuraHoveredUnit
    if type(unit) == "string" then
        return unit
    end
    -- 兜底: GetMouseFocus 向上找 CellD 按钮
    if GetMouseFocus then
        local f = GetMouseFocus()
        while f do
            if f.states and f.states.unit and type(f.states.unit) == "string" then
                return f.states.unit
            end
            f = f:GetParent()
        end
    end
    return nil
end

-------------------------------------------------
-- 脱战扫描学习: 遍历队伍成员身上的 tracked 光环, 缓存真实时长
-- (天赋不同导致同技能时长不同, 真实光环数据最准确, 无需手工维护)
-------------------------------------------------
local function LearnDurationsFromGroup()
    IterateGroupUnits(function(unit)
        local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, "HELPFUL")
        if ok and ids then
            for _, id in ipairs(ids) do
                local ok2, d = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
                if ok2 and d and d.spellId and not (F.IsSecretValue and F.IsSecretValue(d.spellId)) then
                    local entry = tracked[d.spellId]
                    if entry and d.duration and not (F.IsSecretValue and F.IsSecretValue(d.duration)) then
                        entry.duration = d.duration
                    end
                end
            end
        end
    end)
end

-------------------------------------------------
-- 施放事件(主入口)
-------------------------------------------------
local function OnSpellCastSucceeded(unit, spellId)
    if unit ~= "player" then return end
    BuildTrackedList() -- 每次施放重建(布局时序无关)
    if not tracked[spellId] then return end
    -- 12.1 若连施放事件 spellId 都 secret, 静默放弃
    if F.IsSecretValue and F.IsSecretValue(spellId) then return end

    -- 受限环境判定: 战斗中或法术被 secret 化 → 接管显示
    -- 12.1 中 GetRestrictedActionStatus 失效(恒 false), 改用 UnitAffectingCombat
    -- (战斗状态事件, 12.1 仍可用); ShouldSpellAuraBeSecret 名单可能不全, 仅作补充
    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    local spellSecret = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret and C_Secrets.ShouldSpellAuraBeSecret(spellId)
    local restricted = inCombat or spellSecret

    local target = GetCastTargetToken() -- 施放瞬间目标(悬停/鼠标)
    local duration = tracked[spellId].duration

    if not restricted then
        -- 非受限环境(脱战): 现有指示器正常显示, 不干预; 仅自学习缓存真实时长
        if target then
            local ok, d = pcall(C_UnitAuras.GetUnitAuraBySpellID, target, spellId, "HELPFUL")
            if ok and d and d.duration and not (F.IsSecretValue and F.IsSecretValue(d.duration)) then
                duration = d.duration
                tracked[spellId].duration = d.duration
            end
        end
        return
    end

    -- 受限环境(战斗中): 接管显示
    if target then
        HandleCast(spellId, target, GetTime(), duration)
    elseif spellId == 200025 then
        -- 美德道标(无目标技能): diff 匹配 + 自己框架兜底
        StartBeaconTracking(spellId, duration)
    end
    -- 其他无目标技能: 不显示(避免错误位置)
end

-------------------------------------------------
-- 事件注册
-------------------------------------------------
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- 脱战: 清理追踪 + 学习时长, 交还正常指示器
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD") -- 进出场景: 刷新追踪列表与图标缓存

eventFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellId)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellCastSucceeded(unit, spellId)
    elseif event == "PLAYER_REGEN_ENABLED" then
        ClearAllIcons()
        FinishPending()
        RefreshAllIcons()
        BuildTrackedList()
        LearnDurationsFromGroup()
    elseif event == "PLAYER_ENTERING_WORLD" then
        BuildTrackedList()
        RefreshAllIcons()
    end
end)

-- 模块加载: 预构建追踪列表 + 预缓存图标 + 常驻基线
BuildTrackedList()
RefreshAllIcons()
EnsureBaselineLoop()
