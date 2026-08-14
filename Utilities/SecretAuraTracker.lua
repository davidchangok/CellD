-------------------------------------------------
-- SecretAuraTracker
-- 12.1 (Curse of Ula'tek) 受限环境友方光环近似追踪
--
-- 背景:
--   12.1 起, 副本战斗(受限环境)中友方单位光环对插件不可读:
--   - GetUnitAuraBySpellID / GetUnitAuras 返回 nil
--   - spellId/duration/expirationTime 全部 secret 或缺失
--   导致美德道标(200025)等自己施放的增益无法在团队框架显示。
--   (暴雪设计: 防 MDI 竞技作弊, 见蓝贴 "Addons and Auras in Curse of Ula'tek")
--
-- 方案(纯本地, 不依赖 12.1 新 API):
--   1. 施放事件: UNIT_SPELLCAST_SUCCEEDED(player) 确认施放(spellId 非 secret)
--   2. 目标匹配(四通道, 常驻基线 + 施放窗口轮询):
--      通道0: GetUnitAuraBySpellID 精确查询(若 12.1 未被屏蔽则直接命中)
--      通道1: GetUnitAuraInstanceIDs 前后 diff, 新增光环实例 = 候选
--      通道2: GetAuraDataByIndex 索引遍历(通道1 失败时的备选)
--      匹配条件: 新增实例的 spellId 为 nil 或 secret 均视为"不可识别"→ 候选
--      约束: 2 秒窗口 + 最多 3 个目标(符合美德道标机制)
--   3. 显示: 匹配目标框架上显示图标; 匹配失败时降级为
--      玩家自己框架显示"激活中"
--   4. 脱战(PLAYER_REGEN_ENABLED)立即清理, 交还正常光环读取
-------------------------------------------------

local _, Cell = ...
local F = Cell.funcs

-------------------------------------------------
-- 配置
-------------------------------------------------
-- spellId → 持续时间(秒)
-- 战斗中无法读取光环剩余时间, 使用固定时长近似
-- (美德道标 9 秒, 用户实测 12.1 实际数值)
local tracked = {
    [200025] = 9, -- 美德道标 - Beacon of Virtue
}

local MATCH_WINDOW = 2 -- 目标匹配窗口(秒)
local MAX_TARGETS = 3  -- 美德道标最多点 3 人
local ICON_SIZE = 18
local ICON_POINT = "TOPRIGHT" -- 图标锚点(贴近原 Healers 指示器位置)
local BASELINE_INTERVAL = 1  -- 常驻基线轮询间隔(秒)
local MATCH_INTERVAL = 0.2   -- 施放窗口匹配轮询间隔(秒)

-------------------------------------------------
-- 状态
-------------------------------------------------
local eventFrame = CreateFrame("Frame")
local pending -- { spellId, duration, start, windowUntil, targets, count }
local knownIDs = {} -- [unit] = {[auraInstanceID] = true} 匹配基线
local baselineTicker -- 常驻基线维护
local matchTicker -- 施放窗口匹配轮询

-------------------------------------------------
-- 图标缓存
-- 12.1 战斗中 C_Spell.GetSpellInfo/GetSpellTexture 可能返回
-- nil 或 secret 值, 无法用于 SetTexture。因此在脱战(加载/进出
-- 场景)时预查询并缓存 fileID, 战斗中直接使用缓存值。
-------------------------------------------------
local iconCache = {} -- [spellId] = fileID

local function RefreshIconCache()
    for spellId in pairs(tracked) do
        if not iconCache[spellId] then
            local _, icon = F.GetSpellInfo(spellId)
            if icon and not (F.IsSecretValue and F.IsSecretValue(icon)) then
                iconCache[spellId] = icon
            end
        end
    end
end

-------------------------------------------------
-- 图标(懒创建, 挂在单位按钮上)
-------------------------------------------------
local function GetIcon(button)
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
        f.cd:SetHideCountdownNumbers(true) -- 18x18 小图标上数字过大挡图标, 隐藏数字
        f:Hide()
        button._SecretAuraTrackerIcon = f
    end
    return f
end

local function ShowOnButton(button, spellId, start, duration)
    local f = GetIcon(button)
    -- 图标优先用脱战缓存(fileID), 其次运行时查询, 最后问号占位
    local icon = iconCache[spellId]
    if not icon then
        if C_Spell and C_Spell.GetSpellTexture then
            icon = C_Spell.GetSpellTexture(spellId)
        end
        if not icon then
            icon = select(2, GetSpellInfo(spellId))
        end
        if icon and not (F.IsSecretValue and F.IsSecretValue(icon)) then
            iconCache[spellId] = icon
        end
    end
    if icon then
        f.tex:SetTexture(icon)
    else
        f.tex:SetTexture([[Interface\Icons\INV_Misc_QuestionMark]])
    end
    f.cd:SetCooldown(start, duration)
    f:Show()
end

local function HideOnButton(button)
    local f = button._SecretAuraTrackerIcon
    if f then
        f:Hide()
    end
end

-------------------------------------------------
-- 生命周期
-------------------------------------------------
local function FinishPending()
    if not pending then return end

    for unit in pairs(pending.targets) do
        F.HandleUnitButton("unit", unit, HideOnButton)
    end
    F.HandleUnitButton("unit", "player", HideOnButton)

    pending = nil

    if matchTicker then
        matchTicker:Cancel()
        matchTicker = nil
    end
end

-------------------------------------------------
-- 单位遍历 & 光环实例获取
-------------------------------------------------
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

-- 多通道获取单位 HELPULF 光环实例 ID 列表
local function GetUnitAuraIDs(unit)
    -- 通道1: 批量实例 ID
    local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, "HELPFUL")
    if ok and ids and #ids > 0 then return ids end
    -- 通道2: 按索引单取(受限环境批量 API 可能失败/抛错)
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

-------------------------------------------------
-- 基线维护(常驻轮询, 施放前快照供 diff 使用)
-------------------------------------------------
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
        if pending then return end -- 追踪期间冻结基线, 保证 diff 有效
        IterateGroupUnits(UpdateBaseline)
    end)
end

-------------------------------------------------
-- 目标匹配
-------------------------------------------------
local function ShowTarget(unit)
    pending.targets[unit] = true
    pending.count = pending.count + 1
    F.HandleUnitButton("unit", unit, ShowOnButton, pending.spellId, pending.start, pending.duration)
end

local function MatchUnit(unit)
    if not pending then return end
    if GetTime() > pending.windowUntil then return end
    if pending.targets[unit] then return end
    if pending.count >= MAX_TARGETS then return end

    -- 通道0: 精确查询(若 12.1 未被屏蔽则直接命中, 最可靠)
    local ok0, d0 = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, pending.spellId, "HELPFUL")
    if ok0 and d0 and d0.auraInstanceID then
        ShowTarget(unit)
        return
    end

    -- 通道1/2: 光环实例 diff
    local ids = GetUnitAuraIDs(unit)
    if not ids then return end

    local base = knownIDs[unit]
    if not base then
        -- 无基线: 记录当前快照, 本次不匹配(下一轮起生效)
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
            base[id] = true -- 无论是否匹配都标记, 防止重复判定
            local ok2, d = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
            -- 新增且身份不可识别(nil 或 secret) → 疑似受限目标
            if ok2 and d then
                local sid = d.spellId
                if sid == nil or (F.IsSecretValue and F.IsSecretValue(sid)) then
                    matched = true
                end
            end
        end
    end

    if matched then
        ShowTarget(unit)
    end
end

-- 施放窗口内的主动轮询(不依赖 UNIT_AURA 事件是否触发)
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

-------------------------------------------------
-- 施放事件
-------------------------------------------------
local function OnSpellCastSucceeded(unit, spellId)
    if unit ~= "player" then return end
    local duration = tracked[spellId]
    if not duration then return end

    -- 12.1 若连施放事件 spellId 都 secret, 静默放弃(无法追踪)
    if F.IsSecretValue and F.IsSecretValue(spellId) then return end

    -- 非受限环境: 正常光环读取可用, 交给现有指示器, 不干预
    local restricted = F.IsAuraRestricted and F.IsAuraRestricted()
    local spellSecret = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret and C_Secrets.ShouldSpellAuraBeSecret(spellId)
    if not restricted and not spellSecret then return end

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

    -- 基线维护常驻(无追踪时每秒快照, 保证施放时 diff 基线有效)
    EnsureBaselineLoop()
    -- 启动窗口匹配轮询
    StartMatchPolling()

    -- 兜底: 玩家自己框架显示"激活中"
    F.HandleUnitButton("unit", "player", ShowOnButton, spellId, start, duration)

    -- 到期清理
    C_Timer.After(duration + 1, function()
        if pending and pending.spellId == spellId then
            FinishPending()
        end
    end)
end

-------------------------------------------------
-- 事件注册
-------------------------------------------------
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- 脱战: 光环恢复可读, 清理追踪
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD") -- 进出场景: 脱战环境, 刷新图标缓存

-- 模块加载时立即预缓存(此时处于 loading screen, 查询安全)
RefreshIconCache()
-- 常驻基线轮询(保证任意时刻施放都有可用的 diff 基线)
EnsureBaselineLoop()

eventFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellId)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellCastSucceeded(unit, spellId)
    elseif event == "PLAYER_REGEN_ENABLED" then
        RefreshIconCache()
        FinishPending()
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshIconCache()
    end
end)
