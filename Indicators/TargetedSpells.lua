-- ===========================================================================
-- TargetedSpells Indicator（目标法术指示器）
-- 监控敌对单位正在施放的技能，在团队框体上显示被锁定为目标的玩家
-- 正在遭受哪些技能（如 Boss 点名技能），以便治疗/驱散提前应对。
-- 支持自定义法术列表 (targetedSpellsList) 和显示所有法术 (showAllSpells)。
-- 在 Midnight 12.0.0+ 副本中，敌对施法信息可能被标记为 secret，
-- 本模块通过 issecretvalue 检测跳过这些受限数据。
-- ===========================================================================

local _, Cell = ...
local L = Cell.L
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs
local LCG = LibStub("LibCustomGlow-1.0")

-- 缓存常用 API 为局部变量，减少全局查找开销
local UnitIsVisible = UnitIsVisible
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitIsUnit = UnitIsUnit
local UnitIsEnemy = UnitIsEnemy
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo

-- ===========================================================================
-- 核心数据结构
-- ===========================================================================

-- casts: 以施法者 GUID 为键，记录该单位当前正在施放的法术信息
--     castInfo = { startTime, endTime, spellId, icon, isChanneling, targetGUID, targetUnit, nonNameplate, recheck }
--     nonNameplate: 标记施法来源是否不是 nameplate（即来自目标/焦点等非名条单位）
--     recheck: 重检查计数器，用于异步刷新目标绑定
local casts = {}

-- castsOnUnit: 以目标 GUID 为键，聚合所有对该目标的施法信息
--     castsOnUnit[guid][spellId] = { count, startTime, endTime, icon, inList }
-- sortedCastsOnUnit: 排序后的结果，用于决定显示哪些法术图标
local castsOnUnit, sortedCastsOnUnit = {}, {}

-- recheck: 需要定期重检的施法者集合，以施法者 GUID 为键
--     当施法开始时目标尚未绑定（如目标单位还未生成），需要通过重检来绑定目标
local recheck = {}

-- maxIcons: 框体上最多显示多少个法术图标（用户设置）
-- showAllSpells: 是否显示所有法术（而非仅显示 targetedSpellsList 中的法术）
local maxIcons, showAllSpells
-- eventFrame: 用于事件监听和 OnUpdate 重检的通用帧
local eventFrame = CreateFrame("Frame")

-- ===========================================================================
-- Reset: 清空所有法术追踪数据
-- 在 ENCOUNTER_END（战斗结束）或进出副本时调用
-- ===========================================================================
local function Reset()
    wipe(recheck)
    wipe(casts)
    wipe(castsOnUnit)
    wipe(sortedCastsOnUnit)
end

-------------------------------------------------
-- show / hide
-------------------------------------------------

-- HideCasts: 隐藏指定框体 b 的目标法术指示器
-- 将指示器大小设为 0（隐藏所有图标），并停止发光效果
local function HideCasts(b)
    b.indicators.targetedSpells:UpdateSize(0)
    b.indicators.targetedSpells:HideGlow()
end

-- ShowCasts: 在指定框体 b 上显示排序后的施法图标
-- showGlow: 是否高亮发光（有列表中的法术时为 true）
-- sortedCasts: 排序后的法术信息数组
-- num: 法术数量，受 maxIcons 限制
-- 引导法术 (isChanneling) 冷却条反向显示（从满到空），普通施法正常显示
local function ShowCasts(b, showGlow, sortedCasts, num)
    num = min(maxIcons, num)
    for i = 1, num do
        local cast = sortedCasts[i]
        b.indicators.targetedSpells[i].cooldown:SetReverse(not cast.isChanneling)
        b.indicators.targetedSpells[i]:SetCooldown(cast.startTime, cast.endTime-cast.startTime, cast.icon, cast.count)
    end
    b.indicators.targetedSpells:UpdateSize(num)

    if showGlow then
        b.indicators.targetedSpells:ShowGlow(unpack(Cell.vars.targetedSpellsGlow))
    else
        b.indicators.targetedSpells:HideGlow()
    end
end

-------------------------------------------------
-- update casts for guid
-------------------------------------------------

-- GetCastsOnUnit: 聚合所有对指定目标 GUID 的施法信息
-- 遍历 casts 表，将目标为该 GUID 的所有施法信息合并到 castsOnUnit[guid]
-- 按 spellId 去重：同一法术被多个施法者施放时，取最早结束的那个（最短剩余时间）
-- 同一法术被多次施放时，count 累加
-- 返回值：castsOnUnit[guid]（法术聚合表）, inListFound（是否有列表中的法术）
local function GetCastsOnUnit(guid)
    if castsOnUnit[guid] then
        wipe(castsOnUnit[guid])
        wipe(sortedCastsOnUnit[guid])
    else
        castsOnUnit[guid] = {}
        sortedCastsOnUnit[guid] = {}
    end

    local inListFound
    for sourceGUID, castInfo in pairs(casts) do
        if guid == castInfo["targetGUID"] then
            if castInfo["endTime"] > GetTime() then -- not expired: 法术尚未过期
                local spellId = castInfo["spellId"]
                if not castsOnUnit[guid][spellId] then
                    castsOnUnit[guid][spellId] = {["count"] = 0}
                end
                -- 如果是新法术或当前法术剩余时间更短 -> 更新为最短剩余时间
                -- 这样显示的是"最紧迫"的那次施法信息
                if not castsOnUnit[guid][spellId]["endTime"] or castsOnUnit[guid][spellId]["endTime"] > castInfo["endTime"] then --! shorter duration
                    castsOnUnit[guid][spellId]["startTime"] = castInfo["startTime"]
                    castsOnUnit[guid][spellId]["endTime"] = castInfo["endTime"]
                    castsOnUnit[guid][spellId]["icon"] = castInfo["icon"]
                end
                castsOnUnit[guid][spellId]["count"] = castsOnUnit[guid][spellId]["count"] + 1

                -- 检查法术是否在用户配置的追踪列表中
                if Cell.vars.targetedSpellsList[spellId] then
                    castsOnUnit[guid][spellId]["inList"] = true
                    inListFound = true
                end
            else
                -- 已过期的施法记录，从 casts 表中清除
                casts[sourceGUID] = nil
            end
        end
    end

    return castsOnUnit[guid], inListFound
end

-- Comparator: 法术排序比较器
-- 优先级：1) 列表中的法术 (inList) 优先于非列表法术
--          2) 较早开始的法术优先（先施放的排在前面）
local function Comparator(a, b)
    if a.inList ~= b.inList then
        return a.inList
    end
    return a.startTime < b.startTime
end

-- UpdateCastsOnUnit: 更新指定目标 GUID 的施法指示器显示
-- 1) 调用 GetCastsOnUnit 聚合施法数据
-- 2) 将聚合结果转为数组并排序
-- 3) 通过 HandleUnitButton 找到对应框体，显示或隐藏指示器
local function UpdateCastsOnUnit(guid)
    if not guid then return end

    -- local startTime, endTime, spellId, icon, isChanneling
    local t, showGlow = GetCastsOnUnit(guid)

    for spellId, castInfo in pairs(t) do
        tinsert(sortedCastsOnUnit[guid], castInfo)

        -- if not endTime then --! init
        --     startTime, endTime, spellId, icon, isChanneling = castInfo["startTime"], castInfo["endTime"], castInfo["spellId"], castInfo["icon"], castInfo["isChanneling"]
        -- else
        --     spellId = castInfo["spellId"]
        --     if Cell.vars.targetedSpellsList[spellId] then --! [IN LIST]
        --         if not inListFound or endTime > castInfo["endTime"] then --! NOT FOUND BEFORE or SHORTER DURATION
        --             startTime, endTime, icon, isChanneling = castInfo["startTime"], castInfo["endTime"], castInfo["icon"], castInfo["isChanneling"]
        --         end
        --     elseif not inListFound and endTime > castInfo["endTime"] then --! [NOT IN LIST] NOT FOUND BEFORE and SHORTER DURATION
        --         startTime, endTime, icon, isChanneling = castInfo["startTime"], castInfo["endTime"], castInfo["icon"], castInfo["isChanneling"]
        --     end
        -- end

        -- if Cell.vars.targetedSpellsList[spellId] then
        --     inListFound = true
        -- end
    end

    local n = #sortedCastsOnUnit[guid]

    if n == 0 then
        F.HandleUnitButton("guid", guid, HideCasts)
    else
        table.sort(sortedCastsOnUnit[guid], Comparator)
        F.HandleUnitButton("guid", guid, ShowCasts, showGlow, sortedCastsOnUnit[guid], n)
    end
end

-------------------------------------------------
-- check if sourceUnit is casting
-------------------------------------------------

-- CheckUnitCast: 检查指定单位 sourceUnit 是否在施法，并更新追踪数据
-- 核心流程：
-- 1) 仅追踪敌方单位 (UnitIsEnemy)
-- 2) Midnight 防护：检查 IsAuraRestricted 和 issecretvalue，跳过受限施法数据
-- 3) 清理已过期的施法记录，通知前目标更新显示
-- 4) 读取 UnitCastingInfo / UnitChannelInfo 获取施法信息
-- 5) Midnight 防护：法术信息的各字段也需 secret 检查
-- 6) 仅追踪列表中的法术或 showAllSpells 时追踪所有法术
-- 7) 绑定施法目标（通过 sourceUnit.."target" 查找）
-- 8) 非重检时注册到 recheck 表，启动 OnUpdate 轮询
-- 9) 处理目标切换（前目标需要更新显示）
-- isRecheck: true 表示这是重检调用，不再重新注册 recheck
local function CheckUnitCast(sourceUnit, isRecheck)
    if not UnitIsEnemy("player", sourceUnit) then return end

    -- On Midnight 12.0.0+, enemy spellcast info is secret in instances
    -- Player's own casts (and pets) are always non-secret
    if Cell.isMidnight then
        local isPlayerCast = (sourceUnit == "player" or sourceUnit == "pet" or sourceUnit == "vehicle")
        if not isPlayerCast and F.IsAuraRestricted and F.IsAuraRestricted() then
            return -- skip enemy spell tracking during restricted periods
        end
    end

    local sourceGUID = UnitGUID(sourceUnit)
    -- Midnight 12.0.0+: UnitGUID for nameplates may return secret strings
    if Cell.isMidnight and issecretvalue and issecretvalue(sourceGUID) then return end
    local targetGUID
    local previousTarget, isChanneling

    if casts[sourceGUID] then
        previousTarget = casts[sourceGUID]["targetGUID"]
        if casts[sourceGUID]["endTime"] <= GetTime() then
            --! expired
            casts[sourceGUID] = nil
            UpdateCastsOnUnit(previousTarget)
            previousTarget = nil
        end
    end

    -- name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellId
    local name, _, texture, startTimeMS, endTimeMS, _, _, notInterruptible, spellId = UnitCastingInfo(sourceUnit)
    if not name then
        -- name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, spellId
        name, _, texture, startTimeMS, endTimeMS, _, notInterruptible, spellId = UnitChannelInfo(sourceUnit)
        isChanneling = true
    end

    -- print(sourceUnit, name, spellId)

    -- Enemy UnitCastingInfo fields can be secret independently of IsAuraRestricted.
    -- Bail before we use any as a table key or in arithmetic.
    if Cell.isMidnight and issecretvalue then
        if issecretvalue(spellId) or issecretvalue(startTimeMS) or issecretvalue(endTimeMS) or issecretvalue(texture) then
            return
        end
    end

    if spellId and (Cell.vars.targetedSpellsList[spellId] or showAllSpells) then
        if casts[sourceGUID] then
            casts[sourceGUID]["startTime"] = startTimeMS/1000
            casts[sourceGUID]["endTime"] = endTimeMS/1000
            casts[sourceGUID]["spellId"] = spellId
            casts[sourceGUID]["icon"] = texture
        else
            casts[sourceGUID] = {
                ["startTime"] = startTimeMS/1000,
                ["endTime"] = endTimeMS/1000,
                ["spellId"] = spellId,
                ["icon"] = texture,
                ["isChanneling"] = isChanneling,
                -- ["targetGUID"] = targetGUID,
                -- ["sourceUnit"] = sourceUnit,
                -- ["targetUnit"] = targetUnit,
                ["recheck"] = 0,
            }
        end

        -- 通过 sourceUnit.."target" 拼接获得施法者的目标单位 ID
        -- GetTargetUnitID 只返回团队/小队中的玩家或宠物，过滤掉 NPC
        local targetUnit = sourceUnit.."target"
        targetUnit = F.GetTargetUnitID(targetUnit) -- units in group (players/pets), no npcs
        if targetUnit then targetGUID = UnitGUID(targetUnit) end

        -- update spell target
        casts[sourceGUID]["targetUnit"] = targetUnit
        casts[sourceGUID]["targetGUID"] = targetGUID
        casts[sourceGUID]["nonNameplate"] = not strfind(sourceUnit, "^nameplate")

        UpdateCastsOnUnit(targetGUID)

        if not isRecheck then
            if not recheck[sourceGUID] or not (strfind(sourceUnit, "target$") or strfind(sourceUnit, "^nameplate")) then
                recheck[sourceGUID] = sourceUnit
            end
            eventFrame:Show()
        end
    end

    if previousTarget and previousTarget ~= targetGUID then
        UpdateCastsOnUnit(previousTarget)
    end
end

-------------------------------------------------
-- recheck（重检机制）
-- 当施法开始时目标尚未绑定（如 nameplate 单位刚出现，其 targetUnit 还未生成），
-- 通过 OnUpdate 每 0.1 秒轮询重检（最多 6 次即 0.6 秒），直到目标绑定成功或放弃。
-- recheck 表会在 CheckUnitCast 注册，OnUpdate 中消费。
-------------------------------------------------
eventFrame:Hide()
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    -- 每 0.1 秒执行一次重检（降低 CPU 开销）
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed >= 0.1 then
        self.elapsed = 0

        local empty = true

        for guid, unit in pairs(recheck) do
            if casts[guid] then
                casts[guid]["recheck"] = casts[guid]["recheck"] + 1
                -- 最多重检 6 次（0.6 秒），超时则放弃
                if casts[guid]["recheck"] >= 6 then
                    recheck[guid] = nil
                else
                    empty = false
                    -- 两种情况需要重检：
                    -- 1) targetUnit 未绑定，但有新单位出现 (UnitExists(unit.."target"))
                    -- 2) targetUnit 已绑定，但目标已切换 (不再是同一单位)
                    local recheckRequired = (not casts[guid]["targetUnit"] and UnitExists(unit.."target")) or (casts[guid]["targetUnit"] and not UnitIsUnit(unit.."target", casts[guid]["targetUnit"]))
                    if recheckRequired then
                        -- print(unit, casts[guid]["recheck"], recheckRequired)
                        CheckUnitCast(unit, true)
                    end
                end
            else
                -- 施法记录已被清除，同步清理 recheck 条目
                recheck[guid] = nil
            end
        end

        -- 当 recheck 队列为空时隐藏事件帧，停止 OnUpdate 轮询以节省性能
        if empty then
            eventFrame:Hide()
        end
    end
end)

-------------------------------------------------
-- events（事件处理）
-- 统一事件处理入口，根据事件类型分发到不同逻辑
-------------------------------------------------
eventFrame:SetScript("OnEvent", function(_, event, sourceUnit)
    -- ENCOUNTER_END: 战斗结束，清空所有追踪数据并隐藏所有指示器
    if event == "ENCOUNTER_END" then
        Reset()
        F.IterateAllUnitButtons(HideCasts, true)
        return
    end

    -- 忽略以 "soft" 开头的单位（softtarget 等软目标交互事件）
    if sourceUnit and strfind(sourceUnit, "^soft") then return end

    if event == "PLAYER_TARGET_CHANGED" then
        -- 玩家的目标切换了，检查新目标是否在施法
        CheckUnitCast("target")

    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "NAME_PLATE_UNIT_ADDED" then
        -- 开始施法 / 开始引导 / 延迟 / 引导更新 / 名条单位出现 -> 检查施法
        CheckUnitCast(sourceUnit)

    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- 施法停止 / 被打断 / 失败 / 引导停止 -> 清除该施法记录
        local sourceGUID = UnitGUID(sourceUnit)
        -- Midnight 12.0.0+: UnitGUID may return secret strings — can't use as table key
        if issecretvalue and issecretvalue(sourceGUID) then return end
        if casts[sourceGUID] then
            previousTarget = casts[sourceGUID]["targetGUID"]
            casts[sourceGUID] = nil
            -- 通知前目标刷新显示（图标消失）
            UpdateCastsOnUnit(previousTarget)
        end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        -- 名条单位消失：仅清理来自 nameplate 的施法记录
        -- nonNameplate 为 true 的记录（来自 target/focus 等）保留，确保玩家目标仍在追踪中
        local sourceGUID = UnitGUID(sourceUnit)
        -- Midnight 12.0.0+: UnitGUID may return secret strings — can't use as table key
        if issecretvalue and issecretvalue(sourceGUID) then return end
        if casts[sourceGUID] and not casts[sourceGUID]["nonNameplate"] then
            previousTarget = casts[sourceGUID]["targetGUID"]
            casts[sourceGUID] = nil
            UpdateCastsOnUnit(previousTarget)
        end
    end
end)

-------------------------------------------------
-- create（UI 组件创建）
-------------------------------------------------

-- SetCooldown: 设置单个法术图标框体的冷却动画和堆叠计数
-- start: 施法开始时间（秒）
-- duration: 施法总时长（秒）
-- count: 施法者数量（>1 时显示堆叠数字）
local function SetCooldown(frame, start, duration, icon, count)
    frame.duration:Hide()

    if count ~= 1 then
        frame.stack:Show()
        frame.stack:SetText(count)
    else
        frame.stack:Hide()
    end

    frame.border:Show()
    frame.cooldown:Show()
    frame.cooldown:SetSwipeColor(unpack(Cell.vars.targetedSpellsGlow[2]))
    frame.cooldown:SetCooldown(start, duration)
    frame.icon:SetTexture(icon)
    frame:Show()
end

-- SetFont: 为指示器内所有图标的堆叠文字设置字体
local function SetFont(frame, ...)
    for i = 1, #frame do
        I.SetFont(frame[i].stack, frame[i], ...)
    end
end

-- ShowGlowPreview: 在选项面板中预览发光效果（使用当前发光设置）
local function ShowGlowPreview(frame)
    frame:ShowGlow(unpack(Cell.vars.targetedSpellsGlow))
end

-- ShowGlow: 根据 glowType 显示不同类型的发光效果
-- 支持四种发光类型：Normal（按钮发光）/ Pixel（像素发光）/ Shine（自动施法发光）/ Proc（触发发光）
-- 每种类型先停止其他类型的发光，再启动目标类型
local function ShowGlow(frame, glowType, color, arg1, arg2, arg3, arg4)
    if glowType == "Normal" then
        LCG.PixelGlow_Stop(frame.tsGlowFrame)
        LCG.AutoCastGlow_Stop(frame.tsGlowFrame)
        LCG.ProcGlow_Stop(frame.tsGlowFrame)
        LCG.ButtonGlow_Start(frame.tsGlowFrame, color)
    elseif glowType == "Pixel" then
        LCG.ButtonGlow_Stop(frame.tsGlowFrame)
        LCG.AutoCastGlow_Stop(frame.tsGlowFrame)
        LCG.ProcGlow_Stop(frame.tsGlowFrame)
        -- color, N, frequency, length, thickness
        LCG.PixelGlow_Start(frame.tsGlowFrame, color, arg1, arg2, arg3, arg4)
    elseif glowType == "Shine" then
        LCG.ButtonGlow_Stop(frame.tsGlowFrame)
        LCG.PixelGlow_Stop(frame.tsGlowFrame)
        LCG.ProcGlow_Stop(frame.tsGlowFrame)
        -- color, N, frequency, scale
        LCG.AutoCastGlow_Start(frame.tsGlowFrame, color, arg1, arg2, arg3)
    elseif glowType == "Proc" then
        LCG.ButtonGlow_Stop(frame.tsGlowFrame)
        LCG.PixelGlow_Stop(frame.tsGlowFrame)
        LCG.AutoCastGlow_Stop(frame.tsGlowFrame)
        -- color, duration
        LCG.ProcGlow_Start(frame.tsGlowFrame, {color=color, duration=arg1, startAnim=false})
    else
        -- 未知类型：停止所有发光
        LCG.ButtonGlow_Stop(frame.tsGlowFrame)
        LCG.PixelGlow_Stop(frame.tsGlowFrame)
        LCG.AutoCastGlow_Stop(frame.tsGlowFrame)
        LCG.ProcGlow_Stop(frame.tsGlowFrame)
    end
end

-- HideGlow: 停止指示器上所有类型的发光效果
local function HideGlow(frame)
    LCG.ButtonGlow_Stop(frame.tsGlowFrame)
    LCG.PixelGlow_Stop(frame.tsGlowFrame)
    LCG.AutoCastGlow_Stop(frame.tsGlowFrame)
    LCG.ProcGlow_Stop(frame.tsGlowFrame)
end

-- I.CreateTargetedSpells: 为目标法术指示器创建 UI 组件
-- 创建容纳 3 个法术图标的 Frame，并挂载到 parent 框体上
-- 复用 Cooldowns 指示器的布局逻辑（SetSize, UpdateSize, SetOrientation 等）
-- 每个图标框体在冷却完成时自动隐藏（OnCooldownDone）
function I.CreateTargetedSpells(parent)
    local targetedSpells = CreateFrame("Frame", parent:GetName().."TargetedSpellsParent", parent.widgets.indicatorFrame)
    parent.indicators.targetedSpells = targetedSpells
    targetedSpells:Hide()

    targetedSpells.tsGlowFrame = parent.widgets.tsGlowFrame
    targetedSpells._SetSize = targetedSpells.SetSize
    targetedSpells.SetSize = I.Cooldowns_SetSize
    targetedSpells.SetBorder = I.Cooldowns_SetBorder
    targetedSpells.UpdateSize = I.Cooldowns_UpdateSize_WithSpacing
    targetedSpells.SetOrientation = I.Cooldowns_SetOrientation_WithSpacing
    targetedSpells.ShowGlow = ShowGlow
    targetedSpells.HideGlow = HideGlow
    targetedSpells.SetFont = SetFont
    targetedSpells.ShowGlowPreview = ShowGlowPreview
    targetedSpells.HideGlowPreview = HideGlow

    for i = 1, 3 do
        local frame = I.CreateAura_BorderIcon(parent:GetName().."TargetedSpells"..i, targetedSpells, 2)
        tinsert(targetedSpells, frame)
        frame.SetCooldown = SetCooldown
        -- frame:SetScript("OnShow", targetedSpells.UpdateSize)
        -- frame:SetScript("OnHide", targetedSpells.UpdateSize)
        frame.cooldown:SetScript("OnCooldownDone", function()
            frame:Hide()
        end)
    end
end

-------------------------------------------------
-- functions（公共 API）
-------------------------------------------------

-- EnterLeaveInstance: 进出副本时清空所有施法追踪
-- 防止跨副本遗留的施法数据残留显示
-- NOTE: in case there's a casting spell, hide!
local function EnterLeaveInstance()
    Reset()
    F.IterateAllUnitButtons(HideCasts, true)
end

-- I.EnableTargetedSpells: 启用/禁用目标法术指示器
-- enabled=true: 注册所有法术相关事件和副本回调，显示指示器
-- enabled=false: 清空数据，注销所有事件和回调，隐藏指示器
function I.EnableTargetedSpells(enabled)
    if enabled then
        F.IterateAllUnitButtons(function(b)
            b.indicators.targetedSpells:Show()
        end, true)

        -- UNIT_SPELLCAST_DELAYED UNIT_SPELLCAST_FAILED UNIT_SPELLCAST_INTERRUPTED UNIT_SPELLCAST_START UNIT_SPELLCAST_STOP
        -- UNIT_SPELLCAST_CHANNEL_START UNIT_SPELLCAST_CHANNEL_STOP
        -- PLAYER_TARGET_CHANGED ENCOUNTER_END

        eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
        eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
        eventFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
        eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
        eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")

        eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

        eventFrame:RegisterEvent("ENCOUNTER_END")

        Cell.RegisterCallback("EnterInstance", "TargetedSpells_EnterInstance", EnterLeaveInstance)
        Cell.RegisterCallback("LeaveInstance", "TargetedSpells_LeaveInstance", EnterLeaveInstance)
    else
        Reset()
        eventFrame:Hide()
        eventFrame:UnregisterAllEvents()

        Cell.UnregisterCallback("EnterInstance", "TargetedSpells_EnterInstance")
        Cell.UnregisterCallback("LeaveInstance", "TargetedSpells_LeaveInstance")

        F.IterateAllUnitButtons(function(b)
            HideCasts(b)
            b.indicators.targetedSpells:Hide()
        end, true)
    end
end

-- I.ShowAllTargetedSpells: 设置是否显示所有法术（而非仅列表中的法术）
function I.ShowAllTargetedSpells(showAll)
    showAllSpells = showAll
end

-- I.UpdateTargetedSpellsNum: 更新最大显示图标数量（用户设置变更时调用）
function I.UpdateTargetedSpellsNum(num)
    maxIcons = num
end