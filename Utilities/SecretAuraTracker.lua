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
--   2. 目标识别: 有目标技能用施放瞬间 UnitTarget("player") 快照(unit token 非 secret);
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
-- 状态
-------------------------------------------------
local eventFrame = CreateFrame("Frame")
local tracked = {} -- [spellId] = { duration = number|nil }
local trackedReady = false
local iconCache = {} -- [spellId] = fileID
local active = {} -- [unit] = { [spellId] = { slot = n, timer = 句柄 } }
local knownIDs = {} -- 美德道标 diff 基线 [unit] = {[auraInstanceID] = true}
local baselineTicker, matchTicker
local pending -- 美德道标专用 { spellId, duration, start, windowUntil, targets, count }

-------------------------------------------------
-- 追踪列表构建
-------------------------------------------------
local function AddTracked(id)
    if type(id) == "number" and not tracked[id] then
        tracked[id] = { duration = defaultDurations[id] }
    end
end

local function BuildTrackedList()
    -- 用户自定义指示器(Healers 等)的光环列表
    local customs = Cell.snippetVars and Cell.snippetVars.customIndicators
    if customs and customs["buff"] then
        for _, indicatorTable in pairs(customs["buff"]) do
            local auras = indicatorTable and indicatorTable["_auras"]
            if auras then
                for k, v in pairs(auras) do
                    if type(k) == "number" then AddTracked(k) end
                    if type(v) == "number" then AddTracked(v) end
                end
            end
        end
    end
    -- 内置 externals(施加于他人的增益)
    if I and I.GetExternals then
        local externals = I.GetExternals()
        if externals then
            for _, spells in pairs(externals) do
                for id, v in pairs(spells) do
                    if type(id) == "number" then AddTracked(id) end
                    if type(v) == "table" then
                        for subId in pairs(v) do
                            AddTracked(subId)
                        end
                    end
                end
            end
        end
    end
    trackedReady = true
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
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            callback("raid"..i)
        end
    else
        for i = 1, 4 do
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

-------------------------------------------------
-- 施放事件(主入口)
-------------------------------------------------
local function OnSpellCastSucceeded(unit, spellId)
    if unit ~= "player" then return end
    if not trackedReady then BuildTrackedList() end
    if not tracked[spellId] then return end
    -- 12.1 若连施放事件 spellId 都 secret, 静默放弃
    if F.IsSecretValue and F.IsSecretValue(spellId) then return end

    local restricted = F.IsAuraRestricted and F.IsAuraRestricted()
    local spellSecret = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret and C_Secrets.ShouldSpellAuraBeSecret(spellId)

    local target = UnitTarget("player") -- 施放瞬间目标快照(unit token 非 secret)
    local duration = tracked[spellId].duration

    if not restricted and not spellSecret then
        -- 非受限环境: 现有指示器正常显示, 不干预; 仅自学习缓存真实时长
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
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- 脱战: 清理追踪, 交还正常指示器
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD") -- 进出场景: 刷新追踪列表与图标缓存

eventFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellId)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellCastSucceeded(unit, spellId)
    elseif event == "PLAYER_REGEN_ENABLED" then
        ClearAllIcons()
        FinishPending()
        RefreshAllIcons()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not trackedReady then BuildTrackedList() end
        RefreshAllIcons()
    end
end)

-- 模块加载: 预构建追踪列表 + 预缓存图标 + 常驻基线
if not trackedReady then BuildTrackedList() end
RefreshAllIcons()
EnsureBaselineLoop()
