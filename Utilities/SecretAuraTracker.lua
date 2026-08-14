-------------------------------------------------
-- SecretAuraTracker
-- 12.1 (Curse of Ula'tek) 受限环境友方光环近似追踪
--
-- 背景:
--   12.1 起, 副本战斗(受限环境)中友方单位光环对插件不可读:
--   - GetUnitAuraBySpellID / GetUnitAuras 返回 nil
--   - spellId/duration/expirationTime 全部 secret
--   导致美德道标(200025)等自己施放的增益无法在团队框架显示。
--   (暴雪设计: 防 MDI 竞技作弊, 见蓝贴 "Addons and Auras in Curse of Ula'tek")
--
-- 方案(双保险, 纯本地, 不依赖 12.1 新 API):
--   1. 施放事件: UNIT_SPELLCAST_SUCCEEDED(player) 确认施放(spellId 非 secret)
--   2. 目标匹配: 施放后 2 秒窗口内, 对收到 UNIT_AURA 的单位做
--      GetUnitAuraInstanceIDs 前后 diff, 新出现且 spellId 为 secret 的
--      光环判定为疑似目标(最多 3 个, 符合美德道标机制)
--   3. 显示: 疑似目标框架上显示图标 + 倒计时; 匹配失败时降级为
--      玩家自己框架显示"激活中"(此时正常指示器同样无法工作)
--   4. 脱战(PLAYER_REGEN_ENABLED)立即清理, 交还正常光环读取
-------------------------------------------------

local _, Cell = ...
local F = Cell.funcs

-------------------------------------------------
-- 配置
-------------------------------------------------
-- spellId → 持续时间(秒)
-- 战斗中无法读取光环剩余时间, 使用固定时长近似
-- (美德道标 12 秒; 若 12.1 数值有变, 修改此表)
local tracked = {
    [200025] = 12, -- 美德道标 - Beacon of Virtue
}

local MATCH_WINDOW = 2 -- 目标匹配窗口(秒)
local MAX_TARGETS = 3  -- 美德道标最多点 3 人
local ICON_SIZE = 18
local ICON_POINT = "TOPRIGHT" -- 图标锚点(贴近原 Healers 指示器位置)

-------------------------------------------------
-- 状态
-------------------------------------------------
local eventFrame = CreateFrame("Frame")
local listening = false -- 是否监听 UNIT_AURA
local pending -- { spellId, duration, start, windowUntil, targets, count }
local knownIDs = {} -- [unit] = {[auraInstanceID] = true} 匹配基线

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
        f:Hide()
        button._SecretAuraTrackerIcon = f
    end
    return f
end

local function ShowOnButton(button, spellId, start, duration)
    local f = GetIcon(button)
    local icon
    if C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(spellId)
    end
    if not icon then
        icon = select(2, GetSpellInfo(spellId))
    end
    if icon then
        f.tex:SetTexture(icon)
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
    knownIDs = {}

    if listening then
        eventFrame:UnregisterEvent("UNIT_AURA")
        listening = false
    end
end

-------------------------------------------------
-- 目标匹配
-------------------------------------------------
local function OnUnitAura(unit)
    if not pending then return end
    if GetTime() > pending.windowUntil then return end
    if pending.targets[unit] then return end
    if pending.count >= MAX_TARGETS then return end

    local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, "HELPFUL")
    if not ok or not ids then return end

    local base = knownIDs[unit]
    if not base then
        -- 首次看到该单位: 记录基线, 排除已有光环
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
            -- 新光环且 spellId 为 secret → 疑似受限目标(无法识别身份, 只能靠时间窗)
            if ok2 and d and F.IsSecretValue and F.IsSecretValue(d.spellId) then
                matched = true
            end
        end
    end

    if matched then
        pending.targets[unit] = true
        pending.count = pending.count + 1
        F.HandleUnitButton("unit", unit, ShowOnButton, pending.spellId, pending.start, pending.duration)
    end
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
    knownIDs = {}

    if not listening then
        eventFrame:RegisterEvent("UNIT_AURA")
        listening = true
    end

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

eventFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellId)
    if event == "UNIT_AURA" then
        OnUnitAura(unit)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellCastSucceeded(unit, spellId)
    elseif event == "PLAYER_REGEN_ENABLED" then
        FinishPending()
    end
end)
