-------------------------------------------------
-- CastAuraTracker (v1.0.8)
-- 12.1 (Curse of Ula'tek) 受限环境自己施放增益的近似显示
--
-- 背景:
--   12.1 起, 副本战斗(受限环境)中友方单位光环对插件完全不可读
--   (GetUnitAuraBySpellID 返回 nil, GetUnitAuraInstanceIDs/
--   GetAuraDataByIndex 直接抛 "Auras cannot be accessed when secret"),
--   导致自己施放的增益(回春术/美德道标/保护祝福等)无法在团队框架显示。
--   (暴雪设计: 防 MDI 竞技作弊, 见蓝贴 "Addons and Auras in Curse of Ula'tek")
--
-- 方案(纯本地, 不依赖 12.1 新 API):
--   1. 施放事件: UNIT_SPELLCAST_SUCCEEDED(player) — spellId 非 secret(已验证)
--   2. 目标识别: 有目标技能用施放瞬间目标名字匹配队伍成员
--      (12.1 已移除 UnitTarget; UnitName 不再返回 secret, 名字可读)
--      无目标技能(美德道标)用光环实例 diff 轮询(受限环境不可用则仅自己框架兜底)
--   3. 时长: 脱战施放时从目标光环自学习缓存; 战斗中直接用缓存
--   4. 显示: 目标框架右上角最多 3 个图标槽(图标 + Cooldown 扫光, 无数字)
--   5. 脱战(PLAYER_REGEN_ENABLED)清理全部, 交还正常指示器
-------------------------------------------------

local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs

-------------------------------------------------
-- 配置
-------------------------------------------------
local ICON_SIZE = 18
local ICON_SLOTS = 3 -- 每个按钮的图标槽数(同一目标最多同时显示 3 个增益)
local ICON_POINT = "TOPRIGHT"
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
local active = {} -- [unit] = { [spellId] = { slot = n, timer = 句柄 } }
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
    for _, id in ipairs(officialSecretSpells) do
        ids[id] = true
    end

    -- 2. 硬编码兜底(关键法术永远追踪, 不受布局/时序影响)
    for id in pairs(defaultDurations) do
        ids[id] = true
    end

    -- 2. 当前布局中自定义指示器(Healers 等)的 buff 列表
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

    -- 3. 内置 externals(施加于他人的增益)
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

-- 每个按钮 3 个图标槽(懒创建, 横向排列)
local function GetIconSlots(button)
    local slots = button._CastAuraTrackerIcons
    if not slots then
        slots = {}
        for i = 1, ICON_SLOTS do
            local f = CreateFrame("Frame", nil, button)
            f:SetSize(ICON_SIZE, ICON_SIZE)
            f:SetPoint(ICON_POINT, button, ICON_POINT, -(i - 1) * (ICON_SIZE + 2), 2)
            f.tex = f:CreateTexture(nil, "ARTWORK")
            f.tex:SetAllPoints(f)
            f.cd = CreateFrame("Cooldown", nil, f)
            f.cd:SetAllPoints(f)
            f.cd:SetDrawEdge(false)
            f.cd:SetHideCountdownNumbers(true) -- 小图标上数字过大挡图标, 隐藏数字
            f:Hide()
            slots[i] = f
        end
        button._CastAuraTrackerIcons = slots
    end
    return slots
end

-------------------------------------------------
-- 显示(有目标技能)
-------------------------------------------------
local function HandleCast(spellId, target, start, duration)
    F.HandleUnitButton("unit", target, function(button)
        local slots = GetIconSlots(button)
        local entry = active[target] and active[target][spellId]
        local used
        if entry and entry.slot then
            used = entry.slot -- 同法术复用槽位(重置计时)
            if entry.timer then entry.timer:Cancel() end
        else
            for i = 1, ICON_SLOTS do
                if not slots[i]:IsShown() then
                    used = i
                    break
                end
            end
            used = used or ICON_SLOTS -- 全满时覆盖最后一个槽
        end

        local f = slots[used]
        local icon = GetIconFileID(spellId)
        if icon then
            f.tex:SetTexture(icon)
        else
            f.tex:SetTexture([[Interface\Icons\INV_Misc_QuestionMark]])
        end
        f.cd:SetCooldown(start, duration or 0)
        f:Show()

        if not active[target] then active[target] = {} end
        if active[target][spellId] and active[target][spellId].timer then
            active[target][spellId].timer:Cancel()
        end
        local timer
        if duration and duration > 0 then
            timer = C_Timer.After(duration + 0.5, function()
                local e = active[target] and active[target][spellId]
                if e and e.slot == used then
                    slots[used]:Hide()
                    active[target][spellId] = nil
                end
            end)
        end
        active[target][spellId] = { slot = used, timer = timer }
    end)
end

-------------------------------------------------
-- 清理
-------------------------------------------------
local function ClearAllIcons()
    for unit, spells in pairs(active) do
        F.HandleUnitButton("unit", unit, function(button)
            local slots = button._CastAuraTrackerIcons
            if slots then
                for i = 1, ICON_SLOTS do
                    slots[i]:Hide()
                end
            end
            -- 兼容旧版单图标字段
            if button._SecretAuraTrackerIcon then
                button._SecretAuraTrackerIcon:Hide()
            end
        end)
        for _, e in pairs(spells) do
            if e.timer then e.timer:Cancel() end
        end
    end
    wipe(active)
end

-------------------------------------------------
-- 美德道标(无目标技能)特殊处理
-------------------------------------------------
local function FinishPending()
    if not pending then return end
    for unit in pairs(pending.targets) do
        F.HandleUnitButton("unit", unit, function(button)
            if button._SecretAuraTrackerIcon then
                button._SecretAuraTrackerIcon:Hide()
            end
        end)
    end
    F.HandleUnitButton("unit", "player", function(button)
        if button._SecretAuraTrackerIcon then
            button._SecretAuraTrackerIcon:Hide()
        end
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
            local f = GetIcon(button)
            local icon = GetIconFileID(pending.spellId)
            f.tex:SetTexture(icon or [[Interface\Icons\INV_Misc_QuestionMark]])
            f.cd:SetCooldown(pending.start, pending.duration or 0)
            f:Show()
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
            local f = GetIcon(button)
            local icon = GetIconFileID(pending.spellId)
            f.tex:SetTexture(icon or [[Interface\Icons\INV_Misc_QuestionMark]])
            f.cd:SetCooldown(pending.start, pending.duration or 0)
            f:Show()
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

local function GetIcon(button)
    -- 美德道标兜底用单图标(与多槽图标并存)
    local f = button._SecretAuraTrackerIcon
    if not f then
        f = CreateFrame("Frame", nil, button)
        f:SetSize(ICON_SIZE, ICON_SIZE)
        f:SetPoint(ICON_POINT, button, ICON_POINT, 0, 2)
        f.tex = f:CreateTexture(nil, "ARTWORK")
        f.tex:SetAllPoints(f)
        f.cd = CreateFrame("Cooldown", nil, f)
        f.cd:SetAllPoints(f)
        f.cd:SetDrawEdge(false)
        f.cd:SetHideCountdownNumbers(true)
        f:Hide()
        button._SecretAuraTrackerIcon = f
    end
    return f
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
        local f = GetIcon(button)
        local icon = GetIconFileID(spellId)
        f.tex:SetTexture(icon or [[Interface\Icons\INV_Misc_QuestionMark]])
        f.cd:SetCooldown(start, duration or 0)
        f:Show()
    end)

    C_Timer.After((duration or 9) + 1, function()
        if pending and pending.spellId == spellId then
            FinishPending()
        end
    end)
end

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

-- 脱战扫描学习: 遍历队伍成员身上的 tracked 光环, 缓存真实时长
-- (天赋不同导致同技能时长不同, 真实光环数据最准确, 无需手工维护)
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
