-- ===========================================================================
-- 模块：QuickAssist（快速协助）
-- 功能：在 Cell 主界面上显示可点击的单元按钮，用于快速选中队伍/团队成员，
--       同时显示玩家的增益光环（buffs）和团队成员的进攻性增益/施法计时。
--       支持按职责、职业、专精、名称排序过滤，支持自动切换过滤规则。
-- ===========================================================================

local _, Cell = ...
local L = Cell.L          -- 本地化字符串
local F = Cell.funcs       -- 通用函数库
local I = Cell.iFuncs      -- 指示器函数库
local U = Cell.uFuncs      -- 工具函数库
local A = Cell.animations  -- 动画函数库
local P = Cell.pixelPerfectFuncs  -- 像素完美对齐函数库

-- 缓存常用 API，减少全局查找开销
local UnitIsConnected = UnitIsConnected
local InCombatLockdown = InCombatLockdown
local GetUnitName = GetUnitName
local UnitGUID = UnitGUID
local GetAuraSlots = C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras.GetAuraDataBySlot

--! AI followers, wrong value returned by UnitClassBase
-- 获取单位职业英文名（UnitClassBase 对 AI 追随者返回值有误，故自行封装）
local UnitClassBase = function(unit)
    return select(2, UnitClass(unit))
end

-- 第三方库引用
local LGI = LibStub:GetLibrary("LibGroupInfo")       -- 队伍信息库（获取专精等）
local LCG = LibStub("LibCustomGlow-1.0")             -- 自定义发光效果库
local LibTranslit = LibStub("LibTranslit-1.0")       -- 音译库（西里尔字母转拉丁）

-- 模块级配置缓存（由 UpdateQuickAssist 填充）
local quickAssistTable, layoutTable, styleTable, spellTable, quickAssistReady
-- 玩家自身光环映射表：{法术名 = 颜色}（图标类型 / 进度条类型）
local myBuffs_icon, myBuffs_bar = {}, {}
-- 进攻性增益光环映射表 & 进攻性施法持续时间映射表
local offensiveBuffs, offensiveCasts = {}, {}
-- 指示器配置缓存
local offensivesEnabled, offensiveIconGlowType, offensiveIconGlowColor, buffsGlowType
-- 配置按钮提示框定位参数
local tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY

-- ----------------------------------------------------------------------- --
--                     快速协助主框架 (quick assist frame)                     --
-- ----------------------------------------------------------------------- --
-- 创建安全框架，承载所有快速协助按钮
local quickAssistFrame = CreateFrame("Frame", "CellQuickAssistFrame", Cell.frames.mainFrame, "SecureFrameTemplate")
Cell.frames.quickAssistFrame = quickAssistFrame

-- 锚点框架：作为配置按钮和整体位置的锚点，可拖动
local anchorFrame = CreateFrame("Frame", "CellQuickAssistAnchorFrame", quickAssistFrame)
PixelUtil.SetPoint(anchorFrame, "TOPLEFT", CellParent, "CENTER", 1, -1)
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)

-- 悬停检测框架：包裹锚点，用于鼠标进入/离开时触发渐入渐出动画
local hoverFrame = CreateFrame("Frame", nil, quickAssistFrame, "BackdropTemplate")
hoverFrame:SetPoint("TOP", anchorFrame, 0, 1)
hoverFrame:SetPoint("BOTTOM", anchorFrame, 0, -1)
hoverFrame:SetPoint("LEFT", anchorFrame, -1, 0)
hoverFrame:SetPoint("RIGHT", anchorFrame, 1, 0)
-- Cell.StylizeFrame(hoverFrame, {1,0,0,0.3}, {0,0,0,0})

-- 为锚点/悬停框架注入渐入渐出动画
A.ApplyFadeInOutToMenu(anchorFrame, hoverFrame)

-- 配置按钮：左键打开设置面板，右键刷新队伍信息
local config = Cell.CreateButton(anchorFrame, nil, "accent", {20, 10}, false, true)
config:SetFrameStrata("MEDIUM")
config:SetAllPoints(anchorFrame)
config:RegisterForDrag("LeftButton")
config:RegisterForClicks("LeftButtonUp", "RightButtonUp")
config:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        -- 左键：打开 Cell 设置 -> 快速协助标签页
        F.ShowUtilitiesTab()
        F.ShowQuickAssistTab()
    elseif button == "RightButton" then
        -- 右键：非战斗中强制刷新队伍信息
        if not InCombatLockdown() then
            F.Print(L["Refreshing unit buttons (%s)..."]:format(L["Quick Assist"]))
            LGI:ForceUpdate()
        end
    end
end)

-- 拖动开始：允许移动锚点框架
config:SetScript("OnDragStart", function()
    anchorFrame:StartMoving()
    anchorFrame:SetUserPlaced(false)
end)

-- 拖动结束：停止移动并保存位置
config:SetScript("OnDragStop", function()
    anchorFrame:StopMovingOrSizing()
    P.SavePosition(anchorFrame, layoutTable["position"])
end)

-- 鼠标进入：显示提示框，说明快速协助功能及右键刷新操作
config:HookScript("OnEnter", function()
    hoverFrame:GetScript("OnEnter")(hoverFrame)
    CellTooltip:SetOwner(config, "ANCHOR_NONE")
    CellTooltip:SetPoint(tooltipPoint, config, tooltipRelativePoint, tooltipX, tooltipY)
    CellTooltip:AddLine(L["Quick Assist"])
    CellTooltip:AddLine("|cffffb5c5"..L["Right-Click"]..": |cffffffff"..L["refresh unit buttons"])
    CellTooltip:AddLine("|cffababab("..L["not in combat"]..")")
    CellTooltip:Show()
end)

-- 鼠标离开：隐藏提示框
config:HookScript("OnLeave", function()
    hoverFrame:GetScript("OnLeave")(hoverFrame)
    CellTooltip:Hide()
end)

-- 更新锚点/配置按钮可见性
-- 当快速协助至少有一个按钮可见时显示配置按钮，否则隐藏
local function UpdateAnchor()
    local show
    if layoutTable then
        show = Cell.unitButtons.quickAssist[1]:IsShown()
    end

    hoverFrame:EnableMouse(show)
    if show then
        config:Show()
        -- 根据渐隐设置决定渐入还是渐出
        if CellDB["general"]["fadeOut"] then
            if hoverFrame:IsMouseOver() then
                anchorFrame.fadeIn:Play()
            else
                anchorFrame.fadeOut:GetScript("OnFinished")(anchorFrame.fadeOut)
            end
        end
    else
        config:Hide()
    end
end

-- ----------------------------------------------------------------------- --
--                    点击施法 (click-castings) [已弃用]                       --
-- ----------------------------------------------------------------------- --
-- 以下为已弃用的点击施法功能代码
-- 原用于将配置中的法术绑定到按钮的鼠标点击事件 (SecureActionButton)
-- 现已被 Cell 统一的点击施法系统替代
-- local function ClearClickCastings(b)
--     for i = 1, 5 do
--         b:SetAttribute("type"..i, nil)
--     end
-- end

-- local function ApplyClickCastings(b)
--     for i, t in pairs(spellTable["mine"]["clickCastings"]) do
--         if t[1] == 0 then
--             b:SetAttribute("type"..i, "target")
--         elseif t[1] ~= -1 then
--             local spellName = F.GetSpellInfo(t[1])

--             b:SetAttribute("type"..i, "macro")
--             b:SetAttribute("macrotext"..i, "/cast [@mouseover] "..spellName)
--         end
--     end
-- end

-- ---------------------------------------------------------------
-- 光环数据表 (aura tables)
-- ---------------------------------------------------------------
-- 初始化按钮的光环缓存表
-- self._casts:  记录进攻性施法开始时间 {spellId = startTime}
-- self._timers: 记录进攻性施法到期计时器 {spellId = timerHandle}
-- self._buffs_cache:       光环实例ID -> 到期时间（用于动画判断）
-- self._buffs_count_cache: 光环实例ID -> 层数（用于动画判断）
local function InitAuraTables(self)
    -- vars
    self._casts = {}
    self._timers = {}

    -- for icon animation only
    self._buffs_cache = {}
    self._buffs_count_cache = {}
end

-- 清空按钮的光环缓存表（按钮隐藏或 unit 改变时调用）
local function ResetAuraTables(self)
    wipe(self._casts)
    wipe(self._timers)
    wipe(self._buffs_cache)
    wipe(self._buffs_count_cache)
end

-- ---------------------------------------------------------------
-- 遍历光环 (ForEachAura)
-- ---------------------------------------------------------------
-- 光环遍历辅助函数：逐个处理 UnitAuraSlots 返回的光环槽位
-- continuationToken 是 GetAuraSlots 的第一个返回值（延续标记，此处未使用）
-- func(button, auraInfo, slotIndex) 返回 true 则提前终止遍历
local function ForEachAuraHelper(button, func, continuationToken, ...)
    -- continuationToken is the first return value of UnitAuraSlots()
    local n = select('#', ...)
    for i = 1, n do
        local slot = select(i, ...)
        local auraInfo = GetAuraDataBySlot(button.unit, slot)
        local done = func(button, auraInfo, i)
        if done then
            -- if func returns true then no further slots are needed, so don't return continuationToken
            return nil
        end
    end
end

-- 遍历指定单位上符合 filter 条件的所有光环，对每个光环调用 func
-- filter 取值："HELPFUL" | "HARMFUL"
local function ForEachAura(button, filter, func)
    ForEachAuraHelper(button, func, GetAuraSlots(button.unit, filter))
end

-- ----------------------------------------------------------------------- --
--                             光环处理函数                                  --
-- ----------------------------------------------------------------------- --
-- 处理单个增益光环 (HandleBuff)
-- 在 ForEachAura 遍历中为每个光环调用，负责：
--   1. 判断光环是否"刷新"（用于图标动画）
--   2. 将玩家施放的 Buff 推入 buffIcons / buffBars 指示器
--   3. 将队友的进攻性 Buff 推入 offensiveIcons 指示器
local function HandleBuff(self, auraInfo)
    -- Midnight 12.0.0+: 跳过字段为 secret 的光环；非 secret 光环（如团队 Buff）可安全读取
    if not F.IsAuraNonSecret(auraInfo) then return end
    local auraInstanceID = auraInfo.auraInstanceID
    local name = auraInfo.name
    local icon = auraInfo.icon
    local count = auraInfo.applications
    -- local debuffType = auraInfo.isHarmful and auraInfo.dispelName
    local expirationTime = auraInfo.expirationTime or 0
    local start = expirationTime - auraInfo.duration
    local duration = auraInfo.duration
    local source = auraInfo.sourceUnit
    local spellId = auraInfo.spellId
    -- local attribute = auraInfo.points[1] -- UnitAura:arg16

    local refreshing = false

    if duration then
        -- 根据图标动画模式判断光环是否正在"刷新"
        if Cell.vars.iconAnimation == "duration" then
            -- 持续时间模式：到期时间顺延 >= 0.5s 或层数增加视为刷新
            local timeIncreased = self._buffs_cache[auraInstanceID] and (expirationTime - self._buffs_cache[auraInstanceID] >= 0.5) or false
            local countIncreased = self._buffs_count_cache[auraInstanceID] and (count > self._buffs_count_cache[auraInstanceID]) or false
            refreshing = timeIncreased or countIncreased
        elseif Cell.vars.iconAnimation == "stack" then
            -- 层数模式：仅层数增加视为刷新
            refreshing = self._buffs_count_cache[auraInstanceID] and (count > self._buffs_count_cache[auraInstanceID]) or false
        else
            refreshing = false
        end

        -- 缓存光环数据（仅跟踪我们关心的光环：玩家自身 Buff 或进攻性 Buff）
        if (source == "player" and (myBuffs_icon[name] or myBuffs_bar[name])) or offensiveBuffs[spellId] then
            self._buffs_cache[auraInstanceID] = expirationTime
            self._buffs_count_cache[auraInstanceID] = count
        end

        -- 玩家自身 Buff（图标型）：推入 buffIcons 指示器（最多 5 个）
        if myBuffs_icon[name] and source == "player" and self._buffIconsFound < 5 then
            self._buffIconsFound = self._buffIconsFound + 1
            self.buffIcons[self._buffIconsFound]:SetCooldown(start, duration, nil, icon, count, refreshing, myBuffs_icon[name], buffsGlowType)
        end

        -- 玩家自身 Buff（进度条型）：推入 buffBars 指示器（最多 5 个）
        if myBuffs_bar[name] and source == "player" and self._buffBarsFound < 5 then
            self._buffBarsFound = self._buffBarsFound + 1
            self.buffBars[self._buffBarsFound]:SetCooldown(start, duration, myBuffs_bar[name])
        end

        -- 队友进攻性 Buff：推入 offensiveIcons 指示器（最多 5 个）
        if offensiveBuffs[spellId] and self._offensivesFound < 5 then
            self._offensivesFound = self._offensivesFound + 1
            self.offensiveIcons[self._offensivesFound]:SetCooldown(start, duration, nil, icon, count, refreshing, offensiveIconGlowColor, offensiveIconGlowType)
            self.offensiveGlow:SetCooldown(start, duration)
        end
    end
end

-- 更新按钮上所有光环指示器
-- updateInfo: UNIT_AURA 事件携带的光环变更信息（完整更新或增量更新）
-- 流程：
--   1. 判断 buffs 是否发生变化
--   2. 若变化，清空指示器计数器并重新遍历所有增益光环
--   3. 将找到的光环推入 buffIcons / buffBars / offensiveIcons（各最多 5 个）
--   4. 若有进攻性施法计时 (_casts)，一并推入 offensiveIcons
local function QuickAssist_UpdateAuras(self, updateInfo)
    local unit = self.unit
    if not unit then return end

    local buffsChanged

    if not updateInfo or updateInfo.isFullUpdate then
        -- 完整更新：清空缓存并重新扫描
        wipe(self._buffs_cache)
        wipe(self._buffs_count_cache)
        buffsChanged = true
    else
        -- 增量更新：检查是否有我们需要跟踪的光环被添加/更新/移除
        if updateInfo.addedAuras then
            for _, aura in pairs(updateInfo.addedAuras) do
                if aura.isHelpful then buffsChanged = true end
            end
        end

        if updateInfo.updatedAuraInstanceIDs then
            for _, auraInstanceID in pairs(updateInfo.updatedAuraInstanceIDs) do
                if self._buffs_cache[auraInstanceID] then buffsChanged = true end
            end
        end

        if updateInfo.removedAuraInstanceIDs then
            for _, auraInstanceID in pairs(updateInfo.removedAuraInstanceIDs) do
                if self._buffs_cache[auraInstanceID] then
                    self._buffs_cache[auraInstanceID] = nil
                    self._buffs_count_cache[auraInstanceID] = nil
                    buffsChanged = true
                end
            end
        end

        -- 全局设置"始终更新光环"打开时强制刷新
        if Cell.loaded then
            if CellDB["general"]["alwaysUpdateAuras"] then buffsChanged = true end
        end
    end

    if buffsChanged then
        -- 重置各指示器的已找到计数
        self._buffIconsFound = 0
        self._buffBarsFound = 0
        self._offensivesFound = 0

        self.offensiveGlow:Hide()

        -- 遍历所有增益光环，推入对应指示器
        ForEachAura(self, "HELPFUL", HandleBuff)
        self.buffIcons:UpdateSize(self._buffIconsFound)
        self.buffBars:UpdateSize(self._buffBarsFound)

        -- 处理进攻性施法计时（非光环，来自 UNIT_SPELLCAST_SUCCEEDED）
        if offensivesEnabled then
            for spellId, start in pairs(self._casts) do
                local duration = offensiveCasts[spellId][1]
                -- if start + duration <= GetTime() then
                --     self._casts[spellId] = nil
                -- else
                    if self._offensivesFound < 5 then
                        self._offensivesFound = self._offensivesFound + 1
                        self.offensiveIcons[self._offensivesFound]:SetCooldown(start, duration, nil, offensiveCasts[spellId][2], 0, false, offensiveIconGlowColor, offensiveIconGlowType)
                        self.offensiveGlow:SetCooldown(start, duration)
                    end
                -- end
            end
        end
        self.offensiveIcons:UpdateSize(self._offensivesFound)
    end
end

-- 更新进攻性施法计时
-- 在收到 UNIT_SPELLCAST_SUCCEEDED 事件时调用
-- 记录施法开始时间，并为该法术设置一个计时器，到期后自动清除
local function QuickAssist_UpdateCasts(self, spellId)
    if not self.unit then return end
    -- Midnight 12.0.0+: 受限场景中 UNIT_SPELLCAST_SUCCEEDED 的 spellId 为 secret，跳过
    if Cell.isMidnight and issecretvalue and issecretvalue(spellId) then return end
    if not offensiveCasts[spellId] then return end

    self._casts[spellId] = GetTime()
    QuickAssist_UpdateAuras(self)

    -- 若已有该法术的计时器则取消重建，避免重复
    if self._timers[spellId] then self._timers[spellId]:Cancel() end
    self._timers[spellId] = C_Timer.NewTimer(offensiveCasts[spellId][1], function()
        -- print("TIMER:QuickAssist_UpdateAuras", spellId)
        self._timers[spellId] = nil
        self._casts[spellId] = nil
        QuickAssist_UpdateAuras(self)
    end)
end

-- 更新按钮上显示的单位名称
-- 同时缓存 short name 和 full name（用于昵称系统）
local function QuickAssist_UpdateName(self)
    if not self.unit then return end

    self.name = UnitName(self.unit)
    self.fullName = F.UnitFullName(self.unit)

    self.nameText:UpdateName()
end

-- 更新名称文字颜色
-- 根据样式设置（职业颜色 / 自定义颜色）设置 nameText 的文字颜色
-- 离线单位使用职业颜色
local function QuickAssist_UpdateNameColor(self)
    if not self.unit then return end

    self.class = UnitClassBase(self.unit) --! update class or it may be nil

    if not styleTable then
        self.nameText:SetTextColor(1, 1, 1)
        return
    end

    if not UnitIsConnected(self.unit) then
        self.nameText:SetTextColor(F.GetClassColor(self.class))
    else
        if styleTable["name"]["color"][1] == "class_color" then
            self.nameText:SetTextColor(F.GetClassColor(self.class))
        else
            self.nameText:SetTextColor(unpack(styleTable["name"]["color"][2]))
        end
    end
end

-- 根据职业颜色和样式设置计算血条颜色
-- 输入：职业颜色的 r, g, b
-- 输出：血条前景色 + 血量损失背景色（各含 RGBA）
local function GetHealthColor(r, g, b)
    if not styleTable then
        return r, g, b, 1, r*0.2, g*0.2, b*0.2, 1
    end

    local hpR, hpG, hpB, lossR, lossG, lossB

    -- 血量前景色
    if styleTable["hpColor"][1] == "class_color" then
        hpR, hpG, hpB = r, g, b
    elseif styleTable["hpColor"][1] == "class_color_dark" then
        hpR, hpG, hpB = r*0.2, g*0.2, b*0.2
    else
        hpR = styleTable["hpColor"][2][1]
        hpG = styleTable["hpColor"][2][2]
        hpB = styleTable["hpColor"][2][3]
    end

    -- 血量损失背景色
    if styleTable["lossColor"][1] == "class_color" then
        lossR, lossG, lossB = r, g, b
    elseif styleTable["lossColor"][1] == "class_color_dark" then
        lossR, lossG, lossB = r*0.2, g*0.2, b*0.2
    else
        lossR = styleTable["lossColor"][2][1]
        lossG = styleTable["lossColor"][2][2]
        lossB = styleTable["lossColor"][2][3]
    end

    -- 透明度（自定义颜色可指定透明度，否则默认为 1）
    hpA =  styleTable["hpColor"][1] == "custom" and styleTable["hpColor"][2][4] or 1
    lossA =  styleTable["lossColor"][1] == "custom" and styleTable["lossColor"][2][4] or 1

    return hpR, hpG, hpB, hpA, lossR, lossG, lossB, lossA
end

-- 更新血条和掉血背景的颜色
-- 离线单位显示为灰色
local function QuickAssist_UpdateHealthColor(self)
    if not self.unit then return end

    self.class = UnitClassBase(self.unit) --! update class or it may be nil

    local hpR, hpG, hpB
    local lossR, lossG, lossB
    local hpA, lossA = 1, 1

    if not UnitIsConnected(self.unit) then
        hpR, hpG, hpB = 0.4, 0.4, 0.4
        lossR, lossG, lossB = 0.4, 0.4, 0.4
    else
        hpR, hpG, hpB, hpA, lossR, lossG, lossB, lossA = GetHealthColor(F.GetClassColor(self.class))
    end

    self.healthBar:SetStatusBarColor(hpR, hpG, hpB, hpA)
    self.healthLoss:SetVertexColor(lossR, lossG, lossB, lossA)
end

-- 更新血条最大值（用于 StatusBar:SetMinMaxValues）
-- Midnight: SetMinMaxValues 接受 secret-wrapped 值
local function QuickAssist_UpdateHealthMax(self)
    if not self.unit then return end
    -- StatusBar:SetMinMaxValues accepts secret-wrapped values on Midnight (see UnitButton.lua:2398).
    self.healthBar:SetMinMaxValues(0, UnitHealthMax(self.unit))
end

-- 更新血条当前值，并控制死亡贴图 (deadTex) 的显示/隐藏
local function QuickAssist_UpdateHealth(self)
    if not self.unit then return end

    -- StatusBar:SetValue accepts secret-wrapped values on Midnight.
    self.healthBar:SetValue(UnitHealth(self.unit))

    if UnitIsDeadOrGhost(self.unit) then
        self.deadTex:Show()
    else
        self.deadTex:Hide()
    end
end

-- 更新目标高亮边框
-- 若该单位是当前玩家的目标，则显示 targetHighlight 边框
local function QuickAssist_UpdateTarget(self)
    if not self.unit then return end

    if UnitIsUnit(self.unit, "target") then
        if styleTable["highlightSize"] ~= 0 then self.targetHighlight:Show() end
    else
        self.targetHighlight:Hide()
    end
end

-- 根据 UNIT_IN_RANGE_UPDATE 事件更新按钮透明度
-- 在范围内 -> 渐入到 1，超出范围 -> 渐出到 oorAlpha
-- FIXME: BLIZZARD, IT'S BUGGY! — 暴雪的 UNIT_IN_RANGE_UPDATE 事件有时行为异常
-- UNIT_IN_RANGE_UPDATE: unit, inRange
local function QuickAssist_UpdateInRange(self, ir)
    if not self.unit then return end

    if ir then
        A.FrameFadeIn(self, 0.25, self:GetAlpha(), 1)
    else
        A.FrameFadeOut(self, 0.25, self:GetAlpha(), styleTable["oorAlpha"] or 0.25)
    end
end

-- 定时检查范围内/外状态（每 0.25s 触发一次）
-- 与 QuickAssist_UpdateInRange 不同，此函数使用 IsInRange() API 主动查询
-- 仅在状态改变时触发动画，避免不必要的渐入渐出
local IsInRange = F.IsInRange
local function QuickAssist_UpdateInRange_OnTick(self)
    if not self.unit then return end

    local inRange = IsInRange(self.unit)

    self.inRange = inRange
    if Cell.loaded then
        if self.inRange ~= self.wasInRange then
            if inRange then
                A.FrameFadeIn(self, 0.25, self:GetAlpha(), 1)
            else
                A.FrameFadeOut(self, 0.25, self:GetAlpha(), styleTable["oorAlpha"] or 0.25)
            end
        end
        self.wasInRange = inRange
    end
end

-- 完整刷新按钮所有显示内容
-- 仅在按钮可见时执行，避免不必要的更新
local function QuickAssist_UpdateAll(self)
    if not self:IsVisible() then return end

    QuickAssist_UpdateName(self)
    QuickAssist_UpdateNameColor(self)
    QuickAssist_UpdateHealthMax(self)
    QuickAssist_UpdateHealth(self)
    QuickAssist_UpdateHealthColor(self)
    QuickAssist_UpdateTarget(self)
    -- QuickAssist_UpdateInRange(self, IsInRange(self.unit))
    QuickAssist_UpdateInRange_OnTick(self)
    QuickAssist_UpdateAuras(self)
end

-- 注册按钮需要监听的所有事件
-- 在按钮显示时（OnShow）调用
local function QuickAssist_RegisterEvents(self)
    self:RegisterEvent("GROUP_ROSTER_UPDATE")

    self:RegisterEvent("UNIT_HEALTH")
    self:RegisterEvent("UNIT_MAXHEALTH")

    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

    self:RegisterEvent("UNIT_CONNECTION") -- 离线/上线检测
    self:RegisterEvent("UNIT_NAME_UPDATE") -- 未知目标名称更新

    self:RegisterEvent("PLAYER_TARGET_CHANGED")

    if quickAssistReady then
        QuickAssist_UpdateAll(self)
    end
end

-- 取消所有事件注册（按钮隐藏时调用）
local function QuickAssist_UnregisterEvents(self)
    self:UnregisterAllEvents()
end

-- 事件处理入口
-- 分类处理两类事件：
--   1. 单位特定事件（unit 匹配 self.unit 时直接更新对应内容）
--   2. 全局事件（如队伍更新、目标变更）
local function QuickAssist_OnEvent(self, event, unit, arg, arg2)
    if unit and self.unit == unit then
        if event == "UNIT_AURA" then
            QuickAssist_UpdateAuras(self, arg)

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            QuickAssist_UpdateCasts(self, arg2)

        elseif event == "UNIT_HEALTH" then
            QuickAssist_UpdateHealth(self)

        elseif event == "UNIT_MAXHEALTH" then
            QuickAssist_UpdateHealthMax(self)
            QuickAssist_UpdateHealth(self)

        elseif event == "UNIT_CONNECTION" then
            -- 连接状态变化，标记需要完整更新
            self._updateRequired = 1

        elseif event == "UNIT_NAME_UPDATE" then
            QuickAssist_UpdateName(self)
            QuickAssist_UpdateNameColor(self)
            QuickAssist_UpdateHealthColor(self)

        elseif event == "UNIT_IN_RANGE_UPDATE" then
            QuickAssist_UpdateInRange(self, arg)
        end

    else
        if event == "GROUP_ROSTER_UPDATE" then
            -- 队伍变更，标记需要完整更新
            self._updateRequired = 1

        elseif event == "PLAYER_TARGET_CHANGED" then
            QuickAssist_UpdateTarget(self)
        end
    end
end

-- 按钮显示时的处理
-- 清空 _updateRequired 防止重复刷新（队伍 <-> 团队转换时 GROUP_ROSTER_UPDATE 也会触发）
local function QuickAssist_OnShow(self)
    -- print(GetTime(), "OnShow", self:GetName())
    self._updateRequired = nil -- prevent QuickAssist_UpdateAll twice. when convert party <-> raid, GROUP_ROSTER_UPDATE fired.
    QuickAssist_RegisterEvents(self)
end

-- 按钮隐藏时的处理
-- 取消所有事件监听并清空光环缓存
local function QuickAssist_OnHide(self)
    -- print(GetTime(), "OnHide", self:GetName())
    QuickAssist_UnregisterEvents(self)
    ResetAuraTables(self)
end

-- 鼠标进入按钮时显示高亮边框
local function QuickAssist_OnEnter(self)
    if styleTable["highlightSize"] ~= 0 then
        self.mouseoverHighlight:Show()
    end
end

-- 鼠标离开按钮时隐藏高亮边框
local function QuickAssist_OnLeave(self)
    self.mouseoverHighlight:Hide()
end

-- 定时逻辑（由 OnUpdate 驱动，每 ~0.25s 执行一次）
-- 功能：
--   1. 每 0.5s 检查单位 GUID 是否变化（若变化则标记需要完整更新）
--   2. 检查范围内/外状态变化
--   3. 若 _updateRequired 被标记，执行完整更新
local function QuickAssist_OnTick(self)
    -- print(GetTime(), "OnTick", self._updateRequired, self:GetAttribute("refreshOnUpdate"), self:GetName())
    local e = (self.__tickCount or 0) + 1
    if e >= 2 then -- every 0.5 second
        e = 0

        if self.unit then
            local guid = UnitGUID(self.unit)
            -- Midnight 12.0.0+: 副本内 GUID 可能为 secret，此时跳过比较
            if F.IsSecretValue and F.IsSecretValue(guid) then
                guid = nil
            end
            if guid and guid ~= self.__guid then
                self.__guid = guid
                self._updateRequired = 1
            end
        end
    end

    self.__tickCount = e

    QuickAssist_UpdateInRange_OnTick(self)

    if self._updateRequired then
        self._updateRequired = nil
        QuickAssist_UpdateAll(self)
    end
end

-- OnUpdate 处理器：累积 elapsed，每超过 0.25s 触发一次 OnTick
local function QuickAssist_OnUpdate(self, elapsed)
    local e = (self.__updateElapsed or 0) + elapsed
    if e > 0.25 then
        QuickAssist_OnTick(self)
        e = 0
    end
    self.__updateElapsed = e
end

-- 按钮尺寸变化时更新名称文字（重新计算截断宽度）
local function QuickAssist_OnSizeChanged(self)
    if not self.unit then return end
    self.nameText:UpdateName()
end

-- 属性变更处理（由 SecureGroupHeader 设置 unit 属性时触发）
-- 若 unit 变化：更新 self.unit，清空光环缓存，注册 units 映射表
local function QuickAssist_OnAttributeChanged(self, name, value)
    if name == "unit" then
        if self.unit ~= value then
            self.unit = value
            -- self:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", value)
            ResetAuraTables(self)
        end

        if value then
            Cell.unitButtons.quickAssist.units[value] = self
        end
    end
end

-- ----------------------------------------------------------------------- --
--                   按钮模板加载回调 (OnLoad)                               --
-- ----------------------------------------------------------------------- --
-- 在 XML 模板实例化时调用，负责创建按钮的所有子控件并挂载脚本
function CellQuickAssist_OnLoad(button)
    -- 初始化光环缓存表
    InitAuraTables(button)

    -- 信号系统（Ping）集成：使按钮可作为 Ping 目标
    Mixin(button, PingableType_UnitFrameMixin)
    button:SetAttribute("ping-receiver", true)

    function button:GetTargetPingGUID()
        return button.__unitGuid
    end

    -- 血条 (healthBar)：显示当前生命值
    local healthBar = CreateFrame("StatusBar", nil, button)
    button.healthBar = healthBar

    healthBar:SetStatusBarTexture(Cell.vars.texture)
    healthBar:SetFrameLevel(button:GetFrameLevel()+1)

    -- 掉血背景 (healthLoss)：从血条纹理右边缘延伸，显示血量损失部分
    local healthLoss = healthBar:CreateTexture(nil, "ARTWORK", nil , -7)
    button.healthLoss = healthLoss
    healthLoss:SetPoint("TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
    healthLoss:SetPoint("BOTTOMRIGHT")

    -- 死亡贴图 (deadTex)：单位死亡/鬼魂时覆盖在血条上的红色渐变
    local deadTex = healthBar:CreateTexture(nil, "OVERLAY")
    button.deadTex = deadTex
    deadTex:SetAllPoints(healthBar)
    deadTex:SetTexture(Cell.vars.whiteTexture)
    deadTex:SetGradient("VERTICAL", CreateColor(0.545, 0, 0, 1), CreateColor(0, 0, 0, 1))
    deadTex:Hide()

    -- 名称文字 (nameText)：显示单位名称，支持昵称系统和音译
    local nameText = healthBar:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    button.nameText = nameText
    nameText.width = {"percentage", 0.75}

    -- nameText 更新方法：应用昵称、音译、截断
    function nameText:UpdateName()
        local name

        if CELL_NICKTAG_ENABLED and Cell.NickTag then
            name = Cell.NickTag:GetNickname(button.name, nil, true)
        end
        name = name or F.GetNickname(button.name, button.fullName)

        if Cell.loaded and CellDB["general"]["translit"] then
            name = LibTranslit:Transliterate(name)
        end

        F.UpdateTextWidth(nameText, name, nameText.width, button)

        -- nameText:SetSize(nameText:GetWidth(), nameText:GetHeight())
    end

    -- 目标高亮边框 (targetHighlight)：当该单位是当前目标时显示
    local targetHighlight = CreateFrame("Frame", nil, button, "BackdropTemplate")
    button.targetHighlight = targetHighlight
    targetHighlight:SetIgnoreParentAlpha(true)
    targetHighlight:SetFrameLevel(button:GetFrameLevel()+2)
    targetHighlight:Hide()

    -- 鼠标悬停高亮边框 (mouseoverHighlight)：鼠标划过时显示
    local mouseoverHighlight = CreateFrame("Frame", nil, button, "BackdropTemplate")
    button.mouseoverHighlight = mouseoverHighlight
    mouseoverHighlight:SetIgnoreParentAlpha(true)
    mouseoverHighlight:SetFrameLevel(button:GetFrameLevel()+3)
    mouseoverHighlight:Hide()

    -- overlayFrame（已弃用）
    -- local overlayFrame = CreateFrame("Frame", button:GetName().."OverlayFrame", button)
    -- button.overlayFrame = overlayFrame
    -- overlayFrame:SetFrameLevel(button:GetFrameLevel()+10)
    -- overlayFrame:SetAllPoints(button)

    -- 指示器父框架 (indicatorFrame)：承载所有光环指示器（Buff 图标/Buff 进度条/进攻图标/发光）
    local indicatorFrame = CreateFrame("Frame", button:GetName().."IndicatorFrame", button)
    button.indicatorFrame = indicatorFrame
    indicatorFrame:SetFrameLevel(button:GetFrameLevel()+10)
    indicatorFrame:SetAllPoints(button)

    -- 挂载所有脚本处理器
    button:SetScript("OnAttributeChanged", QuickAssist_OnAttributeChanged) -- SecureGroupHeader 设置 unit 属性时触发
    button:HookScript("OnShow", QuickAssist_OnShow)
    button:HookScript("OnHide", QuickAssist_OnHide)
    button:HookScript("OnEnter", QuickAssist_OnEnter)
    button:HookScript("OnLeave", QuickAssist_OnLeave)
    button:SetScript("OnUpdate", QuickAssist_OnUpdate)
    button:SetScript("OnSizeChanged", QuickAssist_OnSizeChanged)
    button:SetScript("OnEvent", QuickAssist_OnEvent)
    button:RegisterForClicks("AnyDown")
end

-- ----------------------------------------------------------------------- --
--                  创建 SecureGroupHeader（单元按钮容器）                    --
-- ----------------------------------------------------------------------- --
-- SecureGroupHeader 是暴雪安全框架的核心，负责自动管理一组安全按钮的显示/隐藏
-- 它根据队伍的成员列表和过滤规则自动创建/回收按钮实例
local header = CreateFrame("Frame", "CellQuickAssistHeader", quickAssistFrame, "SecureGroupHeaderTemplate")

-- （已弃用）按钮 unit 更新回调
-- function header:UpdateButtonUnit(bName, unit)
--     local b = _G[bName]
--     b.unit = unit
--     b:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit)
--     ResetAuraTables(b)
--     if not unit then return end
--     Cell.unitButtons.quickAssist.units[unit] = b
-- end

-- （已弃用）初始属性
-- header:SetAttribute("_initialAttributeNames", "refreshUnitChange")
-- header:SetAttribute("_initialAttribute-refreshUnitChange", [[
--     self:GetParent():CallMethod("UpdateButtonUnit", self:GetName(), self:GetAttribute("unit"))
-- ]])

-- header:SetAttribute("initialConfigFunction", [[
--     local header = self:GetParent()
--     self:SetWidth(header:GetAttribute("minWidth") or 70)
--     self:SetHeight(header:GetAttribute("minHeight") or 25)
-- ]])

-- 设置按钮模板
header:SetAttribute("template", "CellQuickAssistButtonTemplate")

-- header:SetAttribute("showRaid", true)
-- header:SetAttribute("showParty", true)

--! 技巧：先设置 startingIndex = -39 使 Blizzard 的 configureChildren 认为 needButtons == 40
--! 从而预分配 40 个按钮实例（这是 SecureGroupHeaders.lua 的限制规避手段）
header:SetAttribute("startingIndex", -39)
header:Show()
header:SetAttribute("startingIndex", 1)

-- 将按钮按索引存入全局表，方便外部访问
for i, b in ipairs(header) do
    Cell.unitButtons.quickAssist[i] = b
end

-- 监听第一个按钮的显示/隐藏以更新配置按钮锚点可见性
header[1]:HookScript("OnShow", function()
    UpdateAnchor()
end)
header[1]:HookScript("OnHide", function()
    UpdateAnchor()
end)

-- ----------------------------------------------------------------------- --
--                         发光效果 (glow)                                   --
-- ----------------------------------------------------------------------- --
-- 根据发光类型 (glowType) 为指示器应用对应的 LibCustomGlow 效果
-- 支持四种发光类型：
--   "Normal" - 按钮发光（仿系统动作条闪光）
--   "Pixel"  - 像素发光（边框像素点闪烁）
--   "Shine"  - 闪光（自动施法高亮效果）
--   "Proc"   - 触发闪光（短暂的爆发效果）
-- 其他值则停止所有发光
local function ShowGlow(indicator, glowType, glowColor)
    if glowType == "Normal" then
        LCG.PixelGlow_Stop(indicator)
        LCG.AutoCastGlow_Stop(indicator)
        LCG.ProcGlow_Stop(indicator)
        LCG.ButtonGlow_Start(indicator, glowColor)
    elseif glowType == "Pixel" then
        LCG.ButtonGlow_Stop(indicator)
        LCG.AutoCastGlow_Stop(indicator)
        LCG.ProcGlow_Stop(indicator)
        -- color, N, frequency, length, thickness
        LCG.PixelGlow_Start(indicator, glowColor, 7, 0.5, 4, 1)
    elseif glowType == "Shine" then
        LCG.ButtonGlow_Stop(indicator)
        LCG.PixelGlow_Stop(indicator)
        LCG.ProcGlow_Stop(indicator)
        -- color, N, frequency, scale
        LCG.AutoCastGlow_Start(indicator, glowColor, 7, 0.5, 0.7)
    elseif glowType == "Proc" then
        LCG.ButtonGlow_Stop(indicator)
        LCG.PixelGlow_Stop(indicator)
        LCG.AutoCastGlow_Stop(indicator)
        -- color, duration
        LCG.ProcGlow_Start(indicator, {color=glowColor, duration=0.6, startAnim=false})
    else
        LCG.ButtonGlow_Stop(indicator)
        LCG.PixelGlow_Stop(indicator)
        LCG.AutoCastGlow_Stop(indicator)
        LCG.ProcGlow_Stop(indicator)
    end
end

-- ----------------------------------------------------------------------- --
--                   专精过滤 (spec filter)                                  --
-- ----------------------------------------------------------------------- --
-- 用于实现"按专精排序"的过滤模式
-- 通过 LibGroupInfo 获取队伍成员专精信息，按职业/专精优先级排序
-- 排序后生成 nameList 传给 SecureGroupHeader
local specFrame = CreateFrame("Frame")

local specFilter       -- specFilter = {类型, 职业/专精配置表, hideSelf}
local nameList = {}     -- 排好序的玩家名称列表
local nameToPriority = {}  -- 玩家名称 -> 排序优先级

-- 计算某职业+专精的排序优先级
-- 优先级 = 职业索引*10 + 专精索引（值越小越靠前）
-- 若该专精在过滤中未启用则返回 nil（不包含在列表中）
local function GetPriority(class, specId)
    if not specFilter then return end
    if not class then return end
    if not specId or specId == 0 then return end

    local priority
    for ci, ct in pairs(specFilter[2]) do
        if class == ct[1] then  -- 匹配职业
            priority = ci*10
            for si, st in pairs(ct[2]) do
                if specId == st[1] then  -- 匹配专精
                    if st[2] then -- 该专精已启用
                        priority = priority + si
                    else
                        priority = nil  -- 该专精未启用，不包含
                    end
                    break
                end
            end
            break
        end
    end

    return priority
end

-- 重建排序后的单位列表并应用到 SecureGroupHeader
-- 战斗中延迟到 PLAYER_REGEN_ENABLED 后执行
local function UpdateAllUnits()
    if InCombatLockdown() then
        specFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    wipe(nameList)
    wipe(nameToPriority)

    -- 遍历所有队伍成员，计算优先级
    for unit in F.IterateGroupMembers() do
        if UnitIsConnected(unit) then
            local name = GetUnitName(unit, true)
            -- Midnight 12.0.0+: UnitName 可能为 secret，不能用作表键
            if F.IsSecretValue and F.IsSecretValue(name) then
                name = unit -- 降级：使用 unit token 作为键
            end
            local guid = UnitGUID(unit)
            local info = LGI:GetCachedInfo(guid)
            if info then
                nameToPriority[name] = GetPriority(info.class, info.specId)
                -- print(name, nameToPriority[name], info.class, info.specId)
            end
            if nameToPriority[name] then
                tinsert(nameList, name)
            end
        end
    end

    -- 检查是否隐藏自己
    if specFilter[3] then
        F.TRemove(nameList, Cell.vars.playerNameShort)
        nameToPriority[Cell.vars.playerNameShort] = nil
    end

    -- 按职业、专精、名称排序
    sort(nameList, function(a, b)
        if nameToPriority[a] ~= nameToPriority[b] then
            return nameToPriority[a] < nameToPriority[b]
        else
            return a < b
        end
    end)

    -- texplore(nameList)
    -- texplore(nameToPriority)

    -- 清除分组逻辑，改用 NAMELIST 排序
    header:SetAttribute("groupingOrder", "")
    header:SetAttribute("groupFilter", nil)
    header:SetAttribute("groupBy", nil)
    header:SetAttribute("nameList", F.TableToString(nameList, ","))
    header:SetAttribute("sortMethod", "NAMELIST")
end

-- 延迟 1 秒准备更新（防抖，避免频繁触发）
local timer
function specFrame:PrepareUpdate(self, ...)
    specFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")

    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(1, UpdateAllUnits)
end
specFrame:SetScript("OnEvent", specFrame.PrepareUpdate)

-- 启用/禁用专精过滤器
-- 启用时注册 GROUP_ROSTER_UPDATE 和 LibGroupInfo 更新回调
local function EnableSpecFilter(enable)
    if enable then
        specFrame:PrepareUpdate()
        specFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        LGI.RegisterCallback(specFrame, "GroupInfo_Update", "PrepareUpdate")
    else
        specFrame:UnregisterAllEvents()
        LGI.UnregisterCallback(specFrame, "GroupInfo_Update")
    end
end

-- ----------------------------------------------------------------------- --
--                         回调函数 (callbacks)                              --
-- ----------------------------------------------------------------------- --
-- 更新快速协助框架的位置和配置按钮提示框定位
-- 根据 layoutTable["anchor"] 和菜单位置模式 (top_bottom / left_right) 计算
local function UpdatePosition()
    if not layoutTable then return end

    local anchor = layoutTable["anchor"]

    quickAssistFrame:ClearAllPoints()
    P.LoadPosition(anchorFrame, layoutTable["position"])

    if CellDB["general"]["menuPosition"] == "top_bottom" then
        P.Size(anchorFrame, 20, 10)

        if anchor == "BOTTOMLEFT" then
            quickAssistFrame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPLEFT", "BOTTOMLEFT", 0, -3
        elseif anchor == "BOTTOMRIGHT" then
            quickAssistFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPRIGHT", "BOTTOMRIGHT", 0, -3
        elseif anchor == "TOPLEFT" then
            quickAssistFrame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMLEFT", "TOPLEFT", 0, 3
        elseif anchor == "TOPRIGHT" then
            quickAssistFrame:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -4)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMRIGHT", "TOPRIGHT", 0, 3
        end
    else -- left_right
        P.Size(anchorFrame, 10, 20)

        if anchor == "BOTTOMLEFT" then
            quickAssistFrame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMRIGHT", 4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMRIGHT", "BOTTOMLEFT", -3, 0
        elseif anchor == "BOTTOMRIGHT" then
            quickAssistFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMLEFT", -4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMLEFT", "BOTTOMRIGHT", 3, 0
        elseif anchor == "TOPLEFT" then
            quickAssistFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPRIGHT", "TOPLEFT", -3, 0
        elseif anchor == "TOPRIGHT" then
            quickAssistFrame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -4, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPLEFT", "TOPRIGHT", 3, 0
        end
    end
end

-- 更新菜单状态（锁定、渐隐、位置）
-- which: "lock" | "fadeOut" | "position"
local function UpdateMenu(which)
    if not which or which == "lock" then
        if CellDB["general"]["locked"] then
            config:RegisterForDrag()
        else
            config:RegisterForDrag("LeftButton")
        end
    end

    if not which or which == "fadeOut" then
        if CellDB["general"]["fadeOut"] then
            anchorFrame.fadeOut:Play()
        else
            anchorFrame.fadeIn:Play()
        end
        UpdateAnchor()
    end

    if which == "position" then
        UpdatePosition()
    end
end
Cell.RegisterCallback("UpdateMenu", "QuickAssist_UpdateMenu", UpdateMenu)

-- ===========================================================================
-- UpdateQuickAssist (核心更新函数)
-- 根据 which 参数选择性更新快速协助的某一方面：
--   "layout"    - 布局（位置、大小、方向、列数、间距）
--   "filter"    - 过滤（按职责/职业/专精/名称筛选和排序）
--   "style"     - 样式（血条纹理、颜色、字体、高亮等）
--   "mine"      - 玩家自身 Buff 法术列表
--   "mine-indicator"    - 玩家自身 Buff 指示器配置
--   "offensives"        - 进攻性 Buff/施法法术列表
--   "offensives-indicator" - 进攻性指示器配置
-- 若 which 为 nil 则全部更新
-- ===========================================================================
local function UpdateQuickAssist(which)
    F.Debug("|cff33937FUpdateQuickAssist:|r", which)

    -- 根据当前专精加载配置
    quickAssistTable = CellDB["quickAssist"][Cell.vars.playerSpecID]
    local groupType = Cell.vars.quickAssistGroupType

    -- 若未启用则隐藏框架并清空缓存
    if not (quickAssistTable and quickAssistTable["enabled"]) then
        quickAssistFrame:Hide()
        layoutTable = nil
        styleTable = nil
        spellTable = nil
        quickAssistReady = nil
        F.UpdateOmniCDPosition("Cell-QuickAssist")
        return
    end

    -- 启用：显示框架并缓存配置
    quickAssistFrame:Show()
    layoutTable = quickAssistTable["layout"]
    styleTable = quickAssistTable["style"]
    spellTable = quickAssistTable["spells"]
    quickAssistReady = true

    -- ===== 布局更新 =====
    if not which or which == "layout" then
        UpdatePosition()
        header:ClearAllPoints()
        header:SetPoint(layoutTable["anchor"])

        local width, height = layoutTable["size"][1], layoutTable["size"][2]
        P.Size(quickAssistFrame, width, height)

        -- 临时忽略属性变更，防止多次触发 SecureGroupHeader_OnAttributeChanged
        header:SetAttribute("_ignore", true) --! NOTE: prevent multi-invoke SecureGroupHeader_OnAttributeChanged

        header:SetAttribute("minWidth", P.Scale(width))
        header:SetAttribute("minHeight", P.Scale(height))

        -- 根据方向和锚点计算 unitSpacing 和 groupSpacing（含方向符号）
        local point, groupRelativePoint, unitSpacing, groupSpacing
        local spacing, x, y = layoutTable["spacingX"], layoutTable["spacingY"]

        if layoutTable["orientation"] == "horizontal" then
            -- 水平布局：unitSpacing = X 间距，groupSpacing = Y 间距
            if layoutTable["anchor"] == "BOTTOMLEFT" then
                point, groupRelativePoint = "LEFT", "BOTTOM"
                unitSpacing = layoutTable["spacingX"]
                groupSpacing = layoutTable["spacingY"]
            elseif layoutTable["anchor"] == "BOTTOMRIGHT" then
                point, groupRelativePoint = "RIGHT", "BOTTOM"
                unitSpacing = -layoutTable["spacingX"]
                groupSpacing = layoutTable["spacingY"]
            elseif layoutTable["anchor"] == "TOPLEFT" then
                point, groupRelativePoint = "LEFT", "TOP"
                unitSpacing = layoutTable["spacingX"]
                groupSpacing = layoutTable["spacingY"]
            elseif layoutTable["anchor"] == "TOPRIGHT" then
                point, groupRelativePoint = "RIGHT", "TOP"
                unitSpacing = -layoutTable["spacingX"]
                groupSpacing = layoutTable["spacingY"]
            end

            header:SetAttribute("xOffset", P.Scale(unitSpacing))
            header:SetAttribute("yOffset", 0)
        else
            -- 垂直布局：unitSpacing = Y 间距，groupSpacing = X 间距
            if layoutTable["anchor"] == "BOTTOMLEFT" then
                point, groupRelativePoint = "BOTTOM", "LEFT"
                unitSpacing = layoutTable["spacingY"]
                groupSpacing = layoutTable["spacingX"]
            elseif layoutTable["anchor"] == "BOTTOMRIGHT" then
                point, groupRelativePoint = "BOTTOM", "RIGHT"
                unitSpacing = layoutTable["spacingY"]
                groupSpacing = -layoutTable["spacingX"]
            elseif layoutTable["anchor"] == "TOPLEFT" then
                point, groupRelativePoint = "TOP", "LEFT"
                unitSpacing = -layoutTable["spacingY"]
                groupSpacing = layoutTable["spacingX"]
            elseif layoutTable["anchor"] == "TOPRIGHT" then
                point, groupRelativePoint = "TOP", "RIGHT"
                unitSpacing = -layoutTable["spacingY"]
                groupSpacing = layoutTable["spacingX"]
            end

            header:SetAttribute("xOffset", 0)
            header:SetAttribute("yOffset", P.Scale(unitSpacing))
        end

        -- 预设置所有 40 个按钮的初始尺寸并隐藏
        for i = 1, 40 do
            P.Size(header[i], width, height)
            header[i]:ClearAllPoints()
            header[i]:Hide()
        end

        header:SetAttribute("point", point)
        header:SetAttribute("columnAnchorPoint", groupRelativePoint)
        header:SetAttribute("columnSpacing", P.Scale(groupSpacing))
        header:SetAttribute("maxColumns", layoutTable["maxColumns"])

        -- 恢复属性变更监听，应用 unitsPerColumn 触发重新布局
        header:SetAttribute("_ignore", false) --! NOTE: restore SecureGroupHeader_OnAttributeChanged
        header:SetAttribute("unitsPerColumn", layoutTable["unitsPerColumn"])
    end

    -- ===== 过滤更新 =====
    if not which or which == "filter" then
        -- 根据当前队伍类型自动选择过滤规则
        local selectedFilter = groupType and quickAssistTable["filterAutoSwitch"][groupType] or 0

        EnableSpecFilter(false)
        specFilter = nil

        if selectedFilter == 0 then -- 全部隐藏
            header:SetAttribute("showRaid", false)
            header:SetAttribute("showParty", false)
            header:SetAttribute("showPlayer", false)
        else
            header:SetAttribute("showRaid", true)
            header:SetAttribute("showParty", true)
            header:SetAttribute("showPlayer", not quickAssistTable["filters"][selectedFilter][3])

            if quickAssistTable["filters"][selectedFilter][1] == "role" then
                -- 按职责过滤：TANK / HEALER / DAMAGER
                local groupFilter = {}
                for k, v in pairs(quickAssistTable["filters"][selectedFilter][2]) do
                    if v then
                        tinsert(groupFilter, k)
                    end
                end
                groupFilter = table.concat(groupFilter, ",")

                header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER")
                header:SetAttribute("groupBy", "ASSIGNEDROLE")
                header:SetAttribute("sortMethod", "NAME")
                header:SetAttribute("groupFilter", groupFilter)

            elseif quickAssistTable["filters"][selectedFilter][1] == "class" then
                -- 按职业过滤
                local groupFilter = {}
                for k, v in pairs(quickAssistTable["filters"][selectedFilter][2]) do
                    if v[2] then
                        tinsert(groupFilter, v[1])
                    end
                end
                groupFilter = table.concat(groupFilter, ",")

                header:SetAttribute("groupingOrder", groupFilter)
                header:SetAttribute("groupBy", "CLASS")
                header:SetAttribute("sortMethod", "NAME")
                header:SetAttribute("groupFilter", groupFilter)

            elseif quickAssistTable["filters"][selectedFilter][1] == "spec" then
                -- 按专精过滤（使用自定义排序逻辑）
                specFilter = quickAssistTable["filters"][selectedFilter]
                EnableSpecFilter(true)

            elseif quickAssistTable["filters"][selectedFilter][1] == "name" then
                -- 按名称列表过滤（固定顺序）
                header:SetAttribute("sortMethod", "NAMELIST")
                header:SetAttribute("nameList", table.concat(quickAssistTable["filters"][selectedFilter][2], ","))
                header:SetAttribute("groupingOrder", "")
                header:SetAttribute("groupFilter", nil)
                header:SetAttribute("groupBy", nil)
            end
        end

        F.UpdateOmniCDPosition("Cell-QuickAssist")
    end

    -- ===== 样式更新 =====
    if not which or which == "style" then
        for i = 1, 40 do
            -- 血条纹理和颜色
            local tex = F.GetBarTextureByName(styleTable["texture"])
            header[i].healthBar:SetStatusBarTexture(tex)
            header[i].healthLoss:SetTexture(tex)
            QuickAssist_UpdateHealthColor(header[i])
            QuickAssist_UpdateNameColor(header[i])

            -- 名称文字位置
            header[i].nameText:ClearAllPoints()
            header[i].nameText:SetPoint(unpack(styleTable["name"]["position"]))

            -- 名称字体和轮廓
            local font, fontSize, fontOutline, fontShadow = unpack(styleTable["name"]["font"])
            font = F.GetFont(font)

            local fontFlags
            if fontOutline == "None" then
                fontFlags = ""
            elseif fontOutline == "Outline" then
                fontFlags = "OUTLINE"
            else
                fontFlags = "OUTLINE,MONOCHROME"
            end

            header[i].nameText:SetFont(font, fontSize, fontFlags)

            -- 名称阴影
            if fontShadow then
                header[i].nameText:SetShadowOffset(1, -1)
                header[i].nameText:SetShadowColor(0, 0, 0, 1)
            else
                header[i].nameText:SetShadowOffset(0, 0)
                header[i].nameText:SetShadowColor(0, 0, 0, 0)
            end

            header[i].nameText.width = styleTable["name"]["width"]
            header[i].nameText:UpdateName()

            -- 高亮边框
            local targetHighlight = header[i].targetHighlight
            local mouseoverHighlight = header[i].mouseoverHighlight
            local size = styleTable["highlightSize"]

            -- 更新高亮边框锚点（size < 0 表示内嵌，>= 0 表示外扩）
            if size == 0 then
                targetHighlight:Hide()
                mouseoverHighlight:Hide()
            else
                P.ClearPoints(targetHighlight)
                P.ClearPoints(mouseoverHighlight)

                if size < 0 then
                    size = abs(size)
                    P.Point(targetHighlight, "TOPLEFT", header[i], "TOPLEFT")
                    P.Point(targetHighlight, "BOTTOMRIGHT", header[i], "BOTTOMRIGHT")
                    P.Point(mouseoverHighlight, "TOPLEFT", header[i], "TOPLEFT")
                    P.Point(mouseoverHighlight, "BOTTOMRIGHT", header[i], "BOTTOMRIGHT")
                else
                    P.Point(targetHighlight, "TOPLEFT", header[i], "TOPLEFT", -size, size)
                    P.Point(targetHighlight, "BOTTOMRIGHT", header[i], "BOTTOMRIGHT", size, -size)
                    P.Point(mouseoverHighlight, "TOPLEFT", header[i], "TOPLEFT", -size, size)
                    P.Point(mouseoverHighlight, "BOTTOMRIGHT", header[i], "BOTTOMRIGHT", size, -size)
                end

                QuickAssist_UpdateTarget(header[i])
            end

            -- 更新高亮边框粗细
            targetHighlight:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(size)})
            mouseoverHighlight:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(size)})

            -- 更新高亮边框颜色
            targetHighlight:SetBackdropBorderColor(unpack(styleTable["targetColor"]))
            mouseoverHighlight:SetBackdropBorderColor(unpack(styleTable["mouseoverColor"]))
        end
    end

    -- ===== 玩家自身 Buff 法术列表 =====
    if not which or which == "mine" then
        wipe(myBuffs_icon)
        wipe(myBuffs_bar)

        -- 将配置中的法术 ID 转换为法术名称，并按类型存入对应表
        for _, t in pairs(spellTable["mine"]["buffs"]) do
            if t[1] > 0 then
                local spellName = F.GetSpellInfo(t[1])
                if spellName then
                    if t[2] == "icon" then
                        myBuffs_icon[spellName] = t[3]  -- 图标类型：法术名 -> 颜色
                    else -- bar
                        myBuffs_bar[spellName] = t[3]   -- 进度条类型：法术名 -> 颜色
                    end
                end
            end
        end
    end

    -- ===== 玩家自身 Buff 指示器配置 =====
    if not which or which == "mine-indicator" then
        local bit = spellTable["mine"]["icon"]   -- buff 图标指示器设置
        buffsGlowType = bit["glow"]

        local bbt = spellTable["mine"]["bar"]    -- buff 进度条指示器设置

        for i = 1, 40 do
            -- Buff 图标指示器配置
            local indicator = header[i].buffIcons
            P.ClearPoints(indicator)
            P.Point(indicator, bit["position"][1], header[i], bit["position"][2], bit["position"][3], bit["position"][4])
            P.Size(indicator, bit["size"][1], bit["size"][2])
            indicator:SetOrientation(bit["orientation"])
            indicator:SetFont(unpack(bit["font"]))
            indicator:ShowDuration(bit["showDuration"])
            indicator:ShowAnimation(bit["showAnimation"])
            indicator:ShowStack(bit["showStack"])

            -- Buff 进度条指示器配置
            indicator = header[i].buffBars
            P.ClearPoints(indicator)
            P.Point(indicator, bbt["position"][1], header[i], bbt["position"][2], bbt["position"][3], bbt["position"][4])
            P.Size(indicator, bbt["size"][1], bbt["size"][2])
            indicator:SetOrientation(bbt["orientation"])
        end
    end

    -- ===== 进攻性 Buff/施法法术列表 =====
    if not which or which == "offensives" then
        wipe(offensiveBuffs)
        wipe(offensiveCasts)

        if spellTable["offensives"]["enabled"] then
            -- 将职业相关的法术表转换为全局查找表
            offensiveBuffs = F.ConvertSpellTable_WithClass(spellTable["offensives"]["buffs"], true)
            offensiveCasts = F.ConvertSpellDurationTable_WithClass(spellTable["offensives"]["casts"])
        end

        offensivesEnabled = spellTable["offensives"]["enabled"]
    end

    -- ===== 进攻性指示器配置 =====
    if not which or which == "offensives-indicator" then
        local oit = spellTable["offensives"]["icon"]
        offensiveIconGlowType = oit["glow"]
        offensiveIconGlowColor = oit["glowColor"]

        local ogt = spellTable["offensives"]["glow"]

        for i = 1, 40 do
            -- 进攻性图标指示器配置
            local indicator = header[i].offensiveIcons
            P.ClearPoints(indicator)
            P.Point(indicator, oit["position"][1], header[i], oit["position"][2], oit["position"][3], oit["position"][4])
            P.Size(indicator, oit["size"][1], oit["size"][2])
            indicator:SetOrientation(oit["orientation"])
            indicator:SetFont(unpack(oit["font"]))
            indicator:ShowDuration(oit["showDuration"])
            indicator:ShowAnimation(oit["showAnimation"])
            indicator:ShowStack(oit["showStack"])

            -- 进攻性发光指示器配置
            indicator = header[i].offensiveGlow
            indicator:SetFadeOut(ogt["fadeOut"])
            indicator:SetupGlow(ogt["options"])
        end
    end

    -- 若更新了法术列表或指示器配置，刷新所有按钮的光环显示
    if which == "mine" or which == "offensives" or which == "mine-indicator" or which == "offensives-indicator" then
        for i = 1, 40 do
            QuickAssist_UpdateAuras(header[i])
        end
    end
end
Cell.RegisterCallback("UpdateQuickAssist", "UpdateQuickAssist", UpdateQuickAssist)

-- 为单个按钮创建所有光环指示器（Buff 图标/Buff 进度条/进攻图标/进攻发光）
-- 在 AddonLoaded 时对所有 40 个按钮调用
local function QuickAssist_CreateIndicators(button)
    -- 玩家自身 Buff 图标指示器（最多 5 个图标）
    local buffIcons = I.CreateAura_Icons(button:GetName().."BuffIcons", button.indicatorFrame, 5)
    button.buffIcons = buffIcons
    buffIcons:Show()

    -- 为每个 buff 图标挂载 hook：在 SetCooldown 时同步更新图标颜色贴图并触发发光
    for i = 1, 5 do
        if buffIcons[i].cooldown:IsObjectType("StatusBar") then
            buffIcons[i].cooldown:GetStatusBarTexture():SetAlpha(1)
            buffIcons[i].tex = buffIcons[i]:CreateTexture(nil, "OVERLAY")
            buffIcons[i].tex:SetAllPoints(buffIcons[i].icon)

            hooksecurefunc(buffIcons[i], "SetCooldown", function(self, _, _, _, _, _, _, color, glow)
                self.tex:SetColorTexture(unpack(color))
                -- self.spark:SetColorTexture(color[1], color[2], color[3], 1) -- ignore alpha
                -- elseif self.cooldown:IsObjectType("Cooldown") then
                --     self.cooldown:SetSwipeTexture(0)
                --     self.cooldown:SetSwipeColor(unpack(color))
                ShowGlow(self, glow, color)
            end)
        end
    end

    -- 玩家自身 Buff 进度条指示器（最多 5 个进度条）
    local buffBars = I.CreateAura_QuickAssistBars(button:GetName().."BuffBars", button.indicatorFrame, 5)
    button.buffBars = buffBars
    buffBars:Show()

    -- 进攻性图标指示器（最多 5 个图标）
    local offensiveIcons = I.CreateAura_Icons(button:GetName().."OffensiveIcons", button.indicatorFrame, 5)
    button.offensiveIcons = offensiveIcons
    offensiveIcons:Show()
    for i = 1, 5 do
        hooksecurefunc(offensiveIcons[i], "SetCooldown", function(self, _, _, _, _, _, _, color, glow)
            ShowGlow(self, glow, color)
        end)
    end

    -- 进攻性发光指示器（全按钮发光）
    local offensiveGlow = I.CreateAura_Glow(button:GetName().."OffensiveGlow", button)
    button.offensiveGlow = offensiveGlow
end
U.QuickAssist_CreateIndicators = QuickAssist_CreateIndicators

-- AddonLoaded 回调：为所有 40 个按钮创建光环指示器
local function AddonLoaded()
    for i = 1, 40 do
        QuickAssist_CreateIndicators(header[i])
    end
end
Cell.RegisterCallback("AddonLoaded", "QuickAssist_AddonLoaded", AddonLoaded)

-- 像素完美更新回调：根据当前边框设置和像素缩放调整按钮边框与血条边距
local function UpdatePixelPerfect()
    for i = 1, 40 do
        if CELL_BORDER_SIZE ~= 0 then
            header[i]:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(CELL_BORDER_SIZE)})
            header[i]:SetBackdropBorderColor(unpack(CELL_BORDER_COLOR))
        end

        -- 血条内边距：保证 1 像素边距
        header[i].healthBar:SetPoint("TOPLEFT", header[i], "TOPLEFT", P.Scale(1), P.Scale(-1))
        header[i].healthBar:SetPoint("BOTTOMRIGHT", header[i], "BOTTOMRIGHT", P.Scale(-1), P.Scale(1))
    end
end
Cell.RegisterCallback("UpdatePixelPerfect", "QuickAssist_UpdatePixelPerfect", UpdatePixelPerfect)

-- ----------------------------------------------------------------------- --
--                   过滤自动切换 (filter auto switch)                        --
-- ----------------------------------------------------------------------- --
-- 根据当前实例类型和队伍类型自动设置 quickAssistGroupType
-- 战斗中延迟到 PLAYER_REGEN_ENABLED 再触发 UpdateQuickAssist
local delayedFrame = CreateFrame("Frame")
delayedFrame:SetScript("OnEvent", function()
    delayedFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    Cell.Fire("UpdateQuickAssist")
end)

-- 在进入/离开实例、队伍类型变化、专精变化时调用
-- 根据 instanceType 和 groupType 推导 quickAssistGroupType
local function PreUpdateQuickAssist()
    if Cell.vars.instanceType == "pvp" then
        Cell.vars.quickAssistGroupType = "battleground"
    elseif Cell.vars.instanceType == "arena" then
        Cell.vars.quickAssistGroupType = "arena"
    else
        if Cell.vars.groupType == "party" then
            Cell.vars.quickAssistGroupType = "party"
        elseif Cell.vars.groupType == "raid" then
            if Cell.vars.inMythic then
                Cell.vars.quickAssistGroupType = "mythic"
            else
                Cell.vars.quickAssistGroupType = "raid"
            end
        else
            Cell.vars.quickAssistGroupType = nil
        end
    end

    -- 战斗中延迟更新（避免安全限制），否则立即触发
    if InCombatLockdown() then
        delayedFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        Cell.Fire("UpdateQuickAssist")
    end
end
Cell.RegisterCallback("EnterInstance", "QuickAssist_EnterInstance", PreUpdateQuickAssist)
Cell.RegisterCallback("LeaveInstance", "QuickAssist_LeaveInstance", PreUpdateQuickAssist)
Cell.RegisterCallback("GroupTypeChanged", "QuickAssist_GroupTypeChanged", PreUpdateQuickAssist)
Cell.RegisterCallback("SpecChanged", "QuickAssist_SpecChanged", PreUpdateQuickAssist)
