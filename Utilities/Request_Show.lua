-- /script SetAllowDangerousScripts(true)
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local I = Cell.iFuncs
local P = Cell.pixelPerfectFuncs

local LCG = LibStub("LibCustomGlow-1.0")
local Comm = LibStub:GetLibrary("AceComm-3.0")

-------------------------------------------------
-- 发光效果控制 —— 为团队框体按钮提供多种发光高亮动画，用于提示玩家施法请求
-------------------------------------------------
-- 隐藏发光效果：停止所有类型的发光动画并取消关联的计时器
local function HideGlow(glowFrame)
    LCG.ButtonGlow_Stop(glowFrame)
    LCG.PixelGlow_Stop(glowFrame)
    LCG.AutoCastGlow_Stop(glowFrame)
    LCG.ProcGlow_Stop(glowFrame)

    if glowFrame.timer then
        glowFrame.timer:Cancel()
        glowFrame.timer = nil
    end
end

-- 显示发光效果：根据 glowType 启动对应的发光动画（normal/pixel/shine/proc），并在超时后自动隐藏
-- glowFrame:  目标按钮的发光子框架
-- glowType:   发光类型 —— "normal"(按钮发光) / "pixel"(像素发光) / "shine"(闪烁发光) / "proc"(触发发光)
-- glowOptions: 各类型对应的参数表（颜色、频率、尺寸、偏移等）
-- timeout:    发光持续秒数，到期后自动隐藏
-- callback:   隐藏后的回调函数
local function ShowGlow(glowFrame, glowType, glowOptions, timeout, callback)
    F.Debug("|cffa2d2ffSHOW_GLOW:|r", glowFrame:GetName())

    if glowType == "normal" then
        LCG.PixelGlow_Stop(glowFrame)
        LCG.AutoCastGlow_Stop(glowFrame)
        LCG.ProcGlow_Stop(glowFrame)
        LCG.ButtonGlow_Start(glowFrame, glowOptions[1])
    elseif glowType == "pixel" then
        LCG.ButtonGlow_Stop(glowFrame)
        LCG.AutoCastGlow_Stop(glowFrame)
        LCG.ProcGlow_Stop(glowFrame)
        -- color, N, frequency, length, thickness, x, y
        LCG.PixelGlow_Start(glowFrame, glowOptions[1], glowOptions[4], glowOptions[5], glowOptions[6], glowOptions[7], glowOptions[2], glowOptions[3])
    elseif glowType == "shine" then
        LCG.ButtonGlow_Stop(glowFrame)
        LCG.PixelGlow_Stop(glowFrame)
        LCG.ProcGlow_Stop(glowFrame)
        -- color, N, frequency, scale, x, y
        LCG.AutoCastGlow_Start(glowFrame, glowOptions[1], glowOptions[4], glowOptions[5], glowOptions[6], glowOptions[2], glowOptions[3])
    elseif glowType == "proc" then
        LCG.ButtonGlow_Stop(glowFrame)
        LCG.PixelGlow_Stop(glowFrame)
        LCG.AutoCastGlow_Stop(glowFrame)
        -- color, duration
        LCG.ProcGlow_Start(glowFrame, {color=glowOptions[1], xOffset=glowOptions[2], yOffset=glowOptions[3], duration=glowOptions[4], startAnim=false})
    end

    if glowFrame.timer then
        glowFrame.timer:Cancel()
    end
    glowFrame.timer = C_Timer.NewTimer(timeout, function()
        glowFrame.timer = nil
        HideGlow(glowFrame)
        if callback then
            callback()
        end
    end)
end

-------------------------------------------------
-- 图标显示控制 —— 在团队框体按钮上显示技能图标，用于提示施法请求类型
-------------------------------------------------
-- 隐藏图标并取消关联的计时器
local function HideIcon(icon)
    icon:Hide()

    if icon.timer then
        icon.timer:Cancel()
        icon.timer = nil
    end
end

-- 显示图标：设置材质和颜色并显示，超时后自动隐藏
-- icon:      图标UI控件
-- tex:       图标材质路径
-- iconColor: 图标颜色（r, g, b, a）
-- timeout:   显示持续秒数
-- callback:  隐藏后的回调函数
local function ShowIcon(icon, tex, iconColor, timeout, callback)
    F.Debug("|cffa2d2ffSHOW_ICON:|r", icon:GetName())

    icon:Display(tex, iconColor)

    if icon.timer then
        icon.timer:Cancel()
    end
    icon.timer = C_Timer.NewTimer(timeout, function()
        icon.timer = nil
        HideIcon(icon)
        if callback then
            callback()
        end
    end)
end

-------------------------------------------------
-- 文字提示控制 —— 在团队框体按钮上显示文本提示（如驱散请求文字）
-------------------------------------------------
-- 隐藏文字提示并取消关联的计时器
local function HideText(text)
    text:Hide()

    if text.timer then
        text.timer:Cancel()
        text.timer = nil
    end
end

-- 显示文字提示：调用控件自身的 Display 方法显示文本，超时后自动隐藏
-- text:     文字UI控件
-- timeout:  显示持续秒数
-- callback: 隐藏后的回调函数
local function ShowText(text, timeout, callback)
    F.Debug("|cffa2d2ffSHOW_TEXT:|r", text:GetName())

    text:Display()

    if text.timer then
        text.timer:Cancel()
    end
    text.timer = C_Timer.NewTimer(timeout, function()
        text.timer = nil
        HideText(text)
        if callback then
            callback()
        end
    end)
end

-------------------------------------------------
-- 施法请求系统 —— 接收其他玩家发来的施法请求（通过插件通讯或密语），在目标单位框体上显示发光/图标提示
-- 两个入口：
--   1. 插件通讯 "CELL_REQ_S"（由 Cell 队友发送）
--   2. 密语 CHAT_MSG_WHISPER（匹配关键字触发）
-- 收到请求后检查条件（技能是否已知/冷却/目标已有Buff），满足则在对应单位按钮上显示视觉提示
-------------------------------------------------
-- 施法请求的全局配置变量（从 CellDB["spellRequest"] 中读取，由 SR_UpdateRequests 初始化）
-- srEnabled:      是否启用施法请求功能
-- srExists:       是否检查目标已有Buff（避免重复施法）
-- srKnown:        是否只响应已学会的技能
-- srFreeCD:       是否要求技能冷却完毕
-- srReplyCD:      是否在技能冷却中时回复冷却时间
-- srResponseType: 响应模式 —— "all"(响应所有) / "me"(仅响应发给自己的) / "whisper"(仅密语模式)
-- srTimeout:      发光提示的持续秒数
-- srCastMsg:      施法成功后自动发送的密语消息（可选）
local srEnabled, srExists, srKnown, srFreeCD, srReplyCD, srResponseType, srTimeout, srCastMsg
-- 施法请求的技能配置表 —— [spellId] = {显示类型, BuffId, 关键字, 发光参数} 或 {显示类型, BuffId, 关键字, 图标材质, 图标颜色}
-- 显示类型为 "icon"(图标模式) 或 glowType 字符串(发光模式)
local srSpells = {
    -- [spellId] = {type, buffId, keywords, glowOptions} / {type, buffId, keywords, icon, iconColor}
}
-- 施法请求的活跃追踪表 —— [unit] = buffId，记录当前正在显示提示的单位及其等待的Buff
-- 当 COMBAT_LOG_EVENT_UNFILTERED 检测到对应 Buff 成功施放后，自动隐藏提示
local srUnits = {
    -- [unit] = buffId
}

-- 核心帧 —— 用于注册事件监听，并非显示控件
local SR = CreateFrame("Frame")
local COOLDOWN_TIME = _G.ITEM_COOLDOWN_TIME
local IsSpellReady = F.IsSpellReady

local GetSpellLink = C_Spell.GetSpellLink or GetSpellLink

-- 检查施法请求的条件是否满足
-- spellId: 请求的技能ID
-- unit:    目标单位标识（如 "raid1"）
-- sender:  请求发送者的角色名
-- 返回 true 表示应该显示施法提示，false 则不显示
local function CheckSRConditions(spellId, unit, sender)
    F.Debug("|cffcdb4dbCheckSRConditions:|r", spellId, unit, sender)

    if not srSpells[spellId] then return end

    -- can't find unit
    if not unit or not UnitIsVisible(unit) then return end

    -- already has this buff
    if srExists and F.FindAuraById(unit, "BUFF", srSpells[spellId][2]) then return end

    if srKnown then
        if IsSpellKnown(spellId) then
            -- if srDeadMsg and UnitIsDeadOrGhost("player") then
            --     SendChatMessage(srDeadMsg, "WHISPER", nil, sender)
            -- end

            local isReady, cdLeft = IsSpellReady(spellId)

            if srFreeCD then -- NOTE: require free cd
                if isReady then
                    return true
                else
                    if srReplyCD then -- reply cooldown
                        SendChatMessage(GetSpellLink(spellId).." "..format(COOLDOWN_TIME, F.SecondsToTime(cdLeft)), "WHISPER", nil, sender)
                    end
                    return false
                end
            else -- NOTE: no require free cd
                if srReplyCD and not isReady then -- reply cd if cd
                    SendChatMessage(GetSpellLink(spellId).." "..format(COOLDOWN_TIME, F.SecondsToTime(cdLeft)), "WHISPER", nil, sender)
                end
                return true
            end
        else
            return false
        end
    else
        return true
    end
end

-- 在指定单位按钮上显示施法请求提示
-- button:  单位按钮对象（widget 容器）
-- spellId: 请求的技能ID，决定用图标还是发光来提示
local function ShowSpellRequest(button, spellId)
    if button then
        local unit = button.states.unit

        --! save requesterUnit and buffId
        srUnits[unit] = srSpells[spellId][2]

        if srSpells[spellId][1] == "icon" then
            ShowIcon(button.widgets.srIcon, srSpells[spellId][4], srSpells[spellId][5], srTimeout, function()
                srUnits[unit] = nil
            end)
        else
            ShowGlow(button.widgets.srGlowFrame, srSpells[spellId][4][1], srSpells[spellId][4][2], srTimeout, function()
                srUnits[unit] = nil
            end)
        end
    end
end

-- 隐藏单位按钮上的施法请求提示（同时停止发光和图标）
local function HideSpellRequest(button)
    HideGlow(button.widgets.srGlowFrame)
    HideIcon(button.widgets.srIcon)
end

-- 注册插件通讯通道 "CELL_REQ_S"：接收其他 Cell 用户发来的施法请求
-- message 格式: "spellId:target"（target 可选，为请求目标玩家的名称或昵称）
-- 仅在 srResponseType ~= "whisper" 时生效（密语模式下走 CHAT_MSG_WHISPER 事件）
Comm:RegisterComm("CELL_REQ_S", function(prefix, message, channel, sender)
    if srEnabled and srResponseType ~= "whisper" then
        local spellId, target = strsplit(":", message)
        spellId = tonumber(spellId)

        if spellId and CheckSRConditions(spellId, Cell.vars.names[sender], sender) then
            local me = GetUnitName("player")
            -- NOTE: to all provider / to me
            -- if (srResponseType == "all" and (not target or target == me)) or (srResponseType == "me" and target == me) then
            if srResponseType == "all" or (srResponseType == "me" and (target == me or target == Cell.vars.playerNickname)) then
                F.HandleUnitButton("name", sender, ShowSpellRequest, spellId)
                -- notify WA
                F.Notify("SPELL_REQ_RECEIVED", Cell.vars.names[sender], srSpells[spellId][2], srTimeout)
            end
        end
    end
end)

-- 密语监听 —— 当收到玩家密语时，将密语内容与所有已配置技能的关键字匹配
-- 匹配成功则触发施法请求提示
-- 冷却时间回复密语（格式为技能链接+"冷却剩余..."）会被过滤跳过，避免循环触发
-- NOTE: playerName always contains SERVER name!
local COOLDOWN_TIME_TEXT = string.gsub(ITEM_COOLDOWN_TIME, "%%s", "")
function SR:CHAT_MSG_WHISPER(text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)
    -- NOTE: filter cd reply
    if strfind(text, "^|c.+|H.+|h%[.+%]|h|r "..COOLDOWN_TIME_TEXT..".+") then return end

    for spellId, t in pairs(srSpells) do
        if strfind(strlower(text), strlower(t[3])) then
            if CheckSRConditions(spellId, Cell.vars.guids[guid], playerName) then
                F.HandleUnitButton("guid", guid, ShowSpellRequest, spellId)
                -- notify WA
                F.Notify("SPELL_REQ_RECEIVED", Cell.vars.guids[guid], t[2], srTimeout)
            end
            break
        end
    end
end

--! hide on applied
-- 战斗记录监听 —— 检测施法请求的技能Buff是否已施放成功
-- 当检测到目标单位获得了对应的Buff(Aura)，自动隐藏施法请求提示
-- 如果施法者是玩家自己且配置了 srCastMsg，则自动发送密语告知请求者
function SR:COMBAT_LOG_EVENT_UNFILTERED(_, event, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, buffId)
    if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
        local unit = Cell.vars.guids[destGUID]
        if unit and srUnits[unit] == buffId then
            -- hide
            F.HandleUnitButton("unit", unit, HideSpellRequest)
            -- notify APPLIED
            F.Notify("SPELL_REQ_APPLIED", unit, buffId, 0, Cell.vars.guids[sourceGUID])
            F.Debug("|cffdda15eSR_HIDE [|cffbc6c25CLEU:"..event.."|r]:|r", unit, buffId, Cell.vars.guids[sourceGUID])
            -- cast msg (if castByMe)
            if sourceGUID == Cell.vars.playerGUID and srCastMsg then
                SendChatMessage(srCastMsg, "WHISPER", nil, GetUnitName(unit, true))
            end
            -- clear
            srUnits[unit] = nil
        end
    end
end

-- 事件分发器 —— 通过 OnEvent 脚本统一处理 SR 帧注册的所有事件
-- COMBAT_LOG_EVENT_UNFILTERED 取回完整事件参数后转发到对应方法
-- 其他事件（如 CHAT_MSG_WHISPER）直接按方法名调用
SR:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:COMBAT_LOG_EVENT_UNFILTERED(CombatLogGetCurrentEventInfo())
    else
        self[event](self, ...)
    end
end)

-- 更新施法请求配置 —— 从 CellDB 读取最新的设置并应用
-- 在插件初始化或设置变更时由 Cell.RegisterCallback("UpdateRequests") 触发
-- which: 指定更新范围，nil 表示全量更新
--   "spellRequest"       - 仅更新开关/条件/事件注册/超时等基础设置
--   "spellRequest_icon"  - 仅更新图标组件的位置/大小/动画
--   "spellRequest_spells"- 仅更新技能配置表 srSpells
local function SR_UpdateRequests(which)
    F.Debug("|cffBBFFFFUpdateRequests:|r", which)

    if not which or which == "spellRequest" then
        -- NOTE: hide all
        for unit in pairs(srUnits) do
            F.HandleUnitButton("unit", unit, HideSpellRequest)
        end
        wipe(srUnits)
        -- texplore(srUnits)

        srEnabled = CellDB["spellRequest"]["enabled"]

        if srEnabled then
            srExists = CellDB["spellRequest"]["checkIfExists"]
            srKnown = CellDB["spellRequest"]["knownSpellsOnly"]
            srFreeCD = CellDB["spellRequest"]["freeCooldownOnly"]
            srResponseType = CellDB["spellRequest"]["responseType"]
            srReplyCD = CellDB["spellRequest"]["replyCooldown"] and srResponseType ~= "all"
            srTimeout = CellDB["spellRequest"]["timeout"]
            srCastMsg = CellDB["spellRequest"]["replyAfterCast"]

            if srResponseType == "whisper" then
                SR:RegisterEvent("CHAT_MSG_WHISPER")
            else
                SR:UnregisterEvent("CHAT_MSG_WHISPER")
            end

            SR:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        else
            SR:UnregisterAllEvents()
        end
    end

    if not which or which == "spellRequest_icon" then
        F.IterateAllUnitButtons(function(b)
            local setting = CellDB["spellRequest"]["sharedIconOptions"]
            b.widgets.srIcon:SetAnimationType(setting[1])
            P.Size(b.widgets.srIcon, setting[2], setting[2])
            P.ClearPoints(b.widgets.srIcon)
            P.Point(b.widgets.srIcon, setting[3], b.widgets.srGlowFrame, setting[4], setting[5], setting[6])
        end)
    end

    if not which or which == "spellRequest_spells" then
        wipe(srSpells)
        if srEnabled then
            for _, t in pairs(CellDB["spellRequest"]["spells"]) do
                if t["type"] == "icon" then
                    srSpells[t["spellId"]] = {t["type"], t["buffId"], t["keywords"], t["icon"], t["iconColor"]} -- [spellId] = {buffId, keywords, icon, iconColor}
                else
                    srSpells[t["spellId"]] = {t["type"], t["buffId"], t["keywords"], t["glowOptions"]} -- [spellId] = {buffId, keywords, glowOptions}
                end
            end
        end
    end
end
Cell.RegisterCallback("UpdateRequests", "SR_UpdateRequests", SR_UpdateRequests)

-------------------------------------------------
-- 驱散请求系统 —— 接收其他玩家发来的驱散请求，在需要驱散的单位框体上显示发光/文字提示
-- 两个入口：
--   1. 插件通讯 "CELL_REQ_D"（由 Cell 队友发送）
--   2. 战斗记录 COMBAT_LOG_EVENT_UNFILTERED（检测DEBUFF移除后自动隐藏）
--   3. 遭遇开始/结束 ENCOUNTER_START / ENCOUNTER_END（重置所有提示）
-- 响应逻辑：根据 responseType 获取目标单位上所有可驱散DEBUFF或指定DEBUFF，过滤后显示提示
-------------------------------------------------
-- 驱散请求的全局配置变量（从 CellDB["dispelRequest"] 中读取）
-- drEnabled:      是否启用驱散请求功能
-- drDispellable:  是否仅显示自己可以驱散的DEBUFF
-- drResponseType: 响应模式 —— "all"(获取所有可驱散DEBUFF) / "specific"(仅获取指定DEBUFF列表)
-- drTimeout:      发光/文字提示的持续秒数
-- drDebuffs:      指定关注的DEBUFF ID表（由配置的字符串转换而来）
-- drDisplayType:  显示类型 —— "text"(文字提示) 或 glow 类型(发光效果)
local drEnabled, drDispellable, drResponseType, drTimeout, drDebuffs, drDisplayType
-- 驱散请求的活跃追踪表 —— [unit] = { [debuffSpellId] = debuffType }
-- 记录正在显示驱散提示的单位及其DEBUFF列表
-- 当检测到DEBUFF被移除后自动隐藏对应提示
local drUnits = {}
-- 核心帧 —— 用于注册战斗记录/遭遇事件监听，并非显示控件
local DR = CreateFrame("Frame")

-- 隐藏所有单位的驱散请求提示 —— 遍历 drUnits 中所有单位并清除对应的发光/文字提示
local function HideAllDRGlows()
    -- NOTE: hide all
    for unit in pairs(drUnits) do
        F.HandleUnitButton("guid", destGUID, function(b)
            HideGlow(b.widgets.drGlowFrame)
            HideText(b.widgets.drText)
        end)
    end
    wipe(drUnits)
end

-- hide glow if removed
-- 事件分发器 —— 通过 OnEvent 脚本统一处理 DR 帧注册的所有事件
-- COMBAT_LOG_EVENT_UNFILTERED：检测DEBUFF移除，若对应单位有活跃的驱散提示则自动隐藏
-- ENCOUNTER_START / ENCOUNTER_END：遭遇开始时重置所有驱散提示
DR:SetScript("OnEvent", function(self, event)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subEvent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID = CombatLogGetCurrentEventInfo()
        if subEvent == "SPELL_AURA_REMOVED" then
            local unit = Cell.vars.guids[destGUID]
            if unit and drUnits[unit] and drUnits[unit][spellID] then
                -- NOTE: one of debuffs removed, hide glow
                drUnits[unit] = nil
                F.HandleUnitButton("guid", destGUID, function(b)
                    HideGlow(b.widgets.drGlowFrame)
                    HideText(b.widgets.drText)
                end)
            end
        end
    else
        HideAllDRGlows()
    end
end)

-- 注册插件通讯通道 "CELL_REQ_D"：接收其他 Cell 用户发来的驱散请求
-- 根据 drResponseType 获取目标单位上所有可驱散DEBUFF或指定DEBUFF列表
-- 根据 drDispellable 过滤出自身职业可驱散的DEBUFF后，在对应单位按钮上显示提示
Comm:RegisterComm("CELL_REQ_D", function(prefix, message, channel, sender)
    if drEnabled then
        local unit = Cell.vars.names[sender]
        if not unit or not UnitIsVisible(unit) then return end

        if drResponseType == "all" then
            -- NOTE: get all dispellable debuffs on unit
            drUnits[unit] = F.FindAuraByDebuffTypes(unit, "all")
        else -- specific debuff
            -- NOTE: get specific dispellable debuffs on unit
            drUnits[unit] = F.FindDebuffByIds(unit, drDebuffs)
        end

        -- NOTE: filter dispellable by me
        if drDispellable then
            for spellId, debuffType in pairs(drUnits[unit]) do
                if not I.CanDispel(debuffType) then
                    drUnits[unit][spellId] = nil
                end
            end
        end

        if F.Getn(drUnits[unit]) ~= 0 then -- found
            F.HandleUnitButton("name", sender, function(b)
                if drDisplayType == "text" then
                    ShowText(b.widgets.drText, drTimeout, function()
                        drUnits[unit] = nil
                    end)
                else
                    ShowGlow(b.widgets.drGlowFrame, CellDB["dispelRequest"]["glowOptions"][1], CellDB["dispelRequest"]["glowOptions"][2], drTimeout, function()
                        drUnits[unit] = nil
                    end)
                end
            end)
        else
            drUnits[unit] = nil
        end
    end
end)

-- 更新驱散请求配置 —— 从 CellDB 读取最新的设置并应用
-- 在插件初始化或设置变更时由 Cell.RegisterCallback("UpdateRequests") 触发
-- which: 指定更新范围，nil 表示全量更新
--   "dispelRequest"       - 仅更新开关/条件/事件注册/超时等基础设置
--   "dispelRequest_text"  - 仅更新文字提示控件的位置/大小/颜色
local function DR_UpdateRequests(which)
    if not which or which == "dispelRequest" then
        HideAllDRGlows()

        drEnabled = CellDB["dispelRequest"]["enabled"]

        if drEnabled then
            drDispellable = CellDB["dispelRequest"]["dispellableByMe"]
            drResponseType = CellDB["dispelRequest"]["responseType"]
            drTimeout = CellDB["dispelRequest"]["timeout"]
            drDebuffs = F.ConvertTable(CellDB["dispelRequest"]["debuffs"])
            drDisplayType = CellDB["dispelRequest"]["type"]

            DR:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            DR:RegisterEvent("ENCOUNTER_START")
            DR:RegisterEvent("ENCOUNTER_END")
        else
            DR:UnregisterAllEvents()
        end
        -- texplore(drUnits)
        -- texplore(drDebuffs)

    end

    if not which or which == "dispelRequest_text" then
        F.IterateAllUnitButtons(function(b)
            local setting = CellDB["dispelRequest"]["textOptions"]
            b.widgets.drText:SetType(setting[1])
            b.widgets.drText:SetColor(setting[2])
            P.Size(b.widgets.drText, setting[3] * 2, setting[3])
            P.ClearPoints(b.widgets.drText)
            P.Point(b.widgets.drText, setting[4], b.widgets.srGlowFrame, setting[5], setting[6], setting[7])
        end)
    end
end
Cell.RegisterCallback("UpdateRequests", "DR_UpdateRequests", DR_UpdateRequests)