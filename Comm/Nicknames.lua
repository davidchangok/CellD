local _, Cell = ...
local L = Cell.L
local F = Cell.funcs

local LBW = LibStub:GetLibrary("LibBadWords")
local Comm = LibStub:GetLibrary("AceComm-3.0")

-----------------------------------------
-- shared
-----------------------------------------
-- 当前使用的通信频道，由 UpdateSendChannel 根据队伍类型动态更新
local sendChannel
-- 根据当前队伍类型（副本/团队/小队）更新 sendChannel 变量，确保昵称同步消息发送到正确的频道
local function UpdateSendChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        sendChannel = "INSTANCE_CHAT"
    elseif IsInRaid() then
        sendChannel = "RAID"
    else
        sendChannel = "PARTY"
    end
end

-----------------------------------------
-- nickname
-----------------------------------------
-- 从其他玩家同步过来的昵称表，key 为完整玩家名或短名，value 为昵称
Cell.vars.nicknames = {}
-- 用户自定义的昵称表，key 为完整玩家名或短名，value 为昵称
Cell.vars.nicknameCustoms = {}
-- 昵称黑名单，key 为玩家名，value 为 true，黑名单中的玩家不会显示昵称
Cell.vars.nicknameBlacklist = {}

-- 获取指定玩家的显示昵称：优先级为 自定义昵称 > 同步昵称 > 原始短名
-- Midnight 12.0.0+ 中名字可能是 secret string，不能用作 table key，此时直接返回短名
function F.GetNickname(shortname, fullname)
    -- Midnight 12.0.0+: names may be secret strings, cannot use as table keys
    if F.IsSecretValue and (F.IsSecretValue(shortname) or F.IsSecretValue(fullname)) then
        return shortname or _G.UNKNOWNOBJECT
    end
    local name
    if Cell.vars.nicknameCustomEnabled then
        name = Cell.vars.nicknameCustoms[fullname] or
               Cell.vars.nicknameCustoms[shortname] or
               Cell.vars.nicknames[fullname] or
               Cell.vars.nicknames[shortname] or
               shortname
    else
        name = Cell.vars.nicknames[fullname] or
               Cell.vars.nicknames[shortname] or
               shortname
    end
    return name or _G.UNKNOWNOBJECT
end

-- 昵称检查定时器（用于延迟发送 CHK 消息），昵称发送定时器（用于延迟发送 NIC 消息）
local nic_check, nic_send

-- 更新单个单位按钮的名字文本显示，用在 F.HandleUnitButton 的回调中
local function Update(b)
    b.indicators.nameText:UpdateName()
end

-- 刷新指定玩家的名字显示：先尝试完整名匹配单位按钮，失败后尝试短名，同时更新快速协助按钮
local function UpdateName(who)
    F.Debug("|cFF69A000UpdateName:|r|cFF696969", who, Cell.vars.nicknames[who], Cell.vars.nicknameCustoms[who])
    -- update name
    local handled = F.HandleUnitButton("name", who, Update)
    if not handled then
        if strfind(who, "-") then
            who = F.ToShortName(who)
        else
            who = who.."-"..GetNormalizedRealmName()
        end
        F.HandleUnitButton("name", who, Update)
    end
    -- update quickAssist
    local unit = Cell.vars.names[who]
    if unit and Cell.unitButtons.quickAssist.units[unit] then
        Cell.unitButtons.quickAssist.units[unit].nameText:UpdateName()
    end
end

-- 向队伍/团队发送昵称检查请求（CELL_CNIC），触发其他玩家回复自己的昵称
-- 仅在启用同步且不在通讯受限环境（如遭遇战/M+/PvP）时发送
local function CheckNicknames()
    if IsInGroup() then
        if CellDB["nicknames"]["sync"] then
            if nic_check then nic_check:Cancel() end
            nic_check = C_Timer.NewTimer(random(3), function()
                UpdateSendChannel()
                -- Addon comms blocked during encounters/M+/PvP on Midnight 12.0.0+
                if Cell.isMidnight and F.IsCommRestricted and F.IsCommRestricted() then
                    F.Debug("Cell: Comm suppressed - restricted context (CELL_CNIC)")
                    return
                end
                Comm:SendCommMessage("CELL_CNIC", "chk", sendChannel, nil, "ALERT")
            end)
        end
    end
end

-- 将玩家自己的昵称写入昵称表，并更新所有预览按钮（布局、指示器、团队Debuff、发光效果）中的名字显示
local function CheckSelf()
    Cell.vars.nicknames[Cell.vars.playerNameShort] = Cell.vars.playerNickname
    UpdateName(Cell.vars.playerNameShort)

    -- update preview buttons
    if CellLayoutsPreviewButton then
        CellLayoutsPreviewButton.indicators.nameText:UpdateName()
    end
    if CellIndicatorsPreviewButton then
        CellIndicatorsPreviewButton.indicators.nameText:UpdateName()
    end
    if CellRaidDebuffsPreviewButton then
        CellRaidDebuffsPreviewButton.indicators.nameText:UpdateName()
    end
    if CellGlowsPreviewButton then
        CellGlowsPreviewButton.indicators.nameText:UpdateName()
    end
end

-- 事件处理框架：用于监听游戏事件，在进入世界时触发昵称初始化，在队伍成员变化时触发昵称检查
local nickname = CreateFrame("Frame")
nickname:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end)

-- 玩家进入世界：仅触发一次，用于初始化所有昵称数据，之后取消注册该事件
nickname:RegisterEvent("PLAYER_ENTERING_WORLD")
function nickname:PLAYER_ENTERING_WORLD()
    nickname:UnregisterEvent("PLAYER_ENTERING_WORLD")
    Cell.Fire("UpdateNicknames")
end

-- 队伍/团队成员发生变化：重新检查其他成员的昵称
function nickname:GROUP_ROSTER_UPDATE()
    CheckNicknames()
end
---------------------------------------

-- 昵称更新回调主函数，由 Cell.RegisterCallback 注册，所有昵称相关变更均通过此函数处理
-- which 参数区分操作类型：nil=初始化, "sync"=同步开关, "mine"=自己昵称变更, "custom"=自定义开关, "list-*"=自定义列表操作, "blacklist-*"=黑名单操作
local function UpdateNicknames(which, value1, value2)
    F.Debug("|cFF80FF00UpdateNicknames:|r", which, value1, value2)
    -- 初始化：加载个人昵称、自定义开关、自定义列表、黑名单，并设置同步
    if not which then
        Cell.vars.playerNickname = CellDB["nicknames"]["mine"] ~= "" and CellDB["nicknames"]["mine"] or nil
        Cell.vars.nicknameCustomEnabled = CellDB["nicknames"]["custom"]
        CheckSelf()

        if CellDB["nicknames"]["sync"] then
            CheckNicknames()
            nickname:RegisterEvent("GROUP_ROSTER_UPDATE")
        end

        -- 加载自定义昵称列表：从 CellDB 中解析 "playerName:nickname" 格式的条目
        wipe(Cell.vars.nicknameCustoms)
        for _, v in ipairs(CellDB["nicknames"]["list"]) do
            local playerName, nickname = strsplit(":", v, 2)
            if playerName and nickname then
                Cell.vars.nicknameCustoms[playerName] = nickname
                if CellDB["nicknames"]["custom"] then
                    UpdateName(playerName)
                end
            end
        end

        -- 加载黑名单
        wipe(Cell.vars.nicknameBlacklist)
        for _, name in ipairs(CellDB["nicknames"]["blacklist"]) do
            Cell.vars.nicknameBlacklist[name] = true
        end

    -- 同步开关变更：开启时发送检查请求并注册队伍更新事件；关闭时清除同步昵称（保留自己的），通知其他玩家并刷新所有单位按钮名字
    elseif which == "sync" then
        if CellDB["nicknames"]["sync"] then
            CheckNicknames()
            nickname:RegisterEvent("GROUP_ROSTER_UPDATE")
        else
            -- 关闭同步：清除所有同步昵称，仅保留自己的
            F.RemoveElementsExceptKeys(Cell.vars.nicknames, Cell.vars.playerNameShort)
            nickname:UnregisterEvent("GROUP_ROSTER_UPDATE")

            if nic_check then nic_check:Cancel() end
            -- 通知其他玩家自己已关闭同步
            UpdateSendChannel()
            -- Addon comms blocked during encounters/M+/PvP on Midnight 12.0.0+
            if Cell.isMidnight and F.IsCommRestricted and F.IsCommRestricted() then
                F.Debug("Cell: Comm suppressed - restricted context (CELL_NIC sync-off)")
            else
                Comm:SendCommMessage("CELL_NIC", "CELL_NONE", sendChannel)
            end

            -- 刷新所有单位按钮的名字显示
            F.IterateAllUnitButtons(function(b)
                b.indicators.nameText:UpdateName()
            end, true)
        end

    -- 玩家自己的昵称变更：更新本地缓存，刷新预览按钮，并通知队伍/团队中的其他玩家
    elseif which == "mine" then
        Cell.vars.playerNickname = CellDB["nicknames"]["mine"] ~= "" and CellDB["nicknames"]["mine"] or nil

        -- 更新自己的名字显示
        CheckSelf()

        -- 通知其他玩家自己的新昵称
        if IsInGroup() and CellDB["nicknames"]["sync"] then
            UpdateSendChannel()
            -- Addon comms blocked during encounters/M+/PvP on Midnight 12.0.0+
            if Cell.isMidnight and F.IsCommRestricted and F.IsCommRestricted() then
                F.Debug("Cell: Comm suppressed - restricted context (CELL_NIC mine)")
            else
                Comm:SendCommMessage("CELL_NIC", Cell.vars.playerNickname or "CELL_NONE", sendChannel)
            end
        end

    -- 自定义昵称开关变更：更新启用状态并立即刷新所有自定义昵称的显示
    elseif which == "custom" then
        Cell.vars.nicknameCustomEnabled = CellDB["nicknames"]["custom"]
        -- 立即刷新所有自定义昵称的显示
        for playerName in pairs(Cell.vars.nicknameCustoms) do
            UpdateName(playerName)
        end

    -- 自定义昵称列表操作：增/改/删
    elseif which == "list-add" or which == "list-update" then
        Cell.vars.nicknameCustoms[value1] = value2
        UpdateName(value1)
    elseif which == "list-delete" then
        Cell.vars.nicknameCustoms[value1] = nil
        UpdateName(value1)

    -- 黑名单操作：添加时清除该玩家已存在的同步昵称并刷新显示；移除时仅删除黑名单记录（不主动请求同步）
    elseif which == "blacklist-add" then
        Cell.vars.nicknameBlacklist[value1] = true
        Cell.vars.nicknames[value1] = nil
        Cell.vars.nicknames[F.ToShortName(value1)] = nil
        UpdateName(value1)
    elseif which == "blacklist-delete" then
        Cell.vars.nicknameBlacklist[value1] = nil
        -- 仅移除黑名单记录，不主动请求同步（玩家需要重新加入队伍或手动触发才能获得昵称）
    end
end
-- 注册回调：所有昵称相关变更（初始化、同步开关、自定义列表、黑名单等）均通过此回调统一处理
Cell.RegisterCallback("UpdateNicknames", "UpdateNicknames", UpdateNicknames)

-- CELL_CNIC: 收到其他玩家的昵称检查请求 → 取消自己的检查定时器 → 延迟3秒回复自己的昵称
-- 延迟回复是为了避免多个玩家同时回复造成消息风暴
Comm:RegisterComm("CELL_CNIC", function(prefix, message, channel, sender)
    -- 有其他玩家先发送了检查请求，取消自己的检查定时器
    if nic_check then nic_check:Cancel() end

    -- 延迟3秒后回复自己的昵称（取消之前的定时器重置倒计时）
    if nic_send then nic_send:Cancel() end
    nic_send = C_Timer.NewTimer(3, function()
        UpdateSendChannel()
        -- Addon comms blocked during encounters/M+/PvP on Midnight 12.0.0+
        if Cell.isMidnight and F.IsCommRestricted and F.IsCommRestricted() then
            F.Debug("Cell: Comm suppressed - restricted context (CELL_NIC nic_send)")
            return
        end
        if CellDB["nicknames"]["sync"] then
            Comm:SendCommMessage("CELL_NIC", Cell.vars.playerNickname or "CELL_NONE", sendChannel)
        else
            Comm:SendCommMessage("CELL_NIC", "CELL_NONE", sendChannel)
        end
    end)
end)

-- CELL_NIC: 收到其他玩家的昵称信息 → 过滤自己的消息 → 校验黑名单和敏感词 → 更新昵称表并刷新显示
Comm:RegisterComm("CELL_NIC", function(prefix, message, channel, sender)
    -- 忽略自己发出的消息
    if sender == Cell.vars.playerNameShort then return end

    if CellDB["nicknames"]["sync"] then
        -- 将短名补全为完整名（含服务器）
        if not string.find(sender, "-") then
            sender = sender .. "-" .. GetNormalizedRealmName()
        end

        -- 清除昵称的情况：CELL_NONE（关闭同步）、在黑名单中、或包含敏感词
        if message == "CELL_NONE" or Cell.vars.nicknameBlacklist[sender] or LBW.ContainsBadWords(message) then
            Cell.vars.nicknames[sender] = nil
        else
            Cell.vars.nicknames[sender] = message
        end
        UpdateName(sender)
    end
end)

-----------------------------------------
-- NickTag 第三方库集成
-- NickTag-1.0 是一个第三方昵称库，当它存在且启用时，Cell 会监听其更新回调，
-- 在昵称变更后延迟3秒批量刷新所有单位按钮的名字显示
-----------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    f:UnregisterAllEvents()

    -- 仅在 NickTag 功能启用时继续
    if not CELL_NICKTAG_ENABLED then return end

    local nickTag = LibStub:GetLibrary("NickTag-1.0", true)
    if nickTag then
        Cell.NickTag = nickTag

        -- 刷新所有单位按钮的名字显示
        local function UpdateAll()
            F.IterateAllUnitButtons(function(b)
                b.indicators.nameText:UpdateName()
            end, true)
        end

        -- 监听 NickTag 更新回调：防抖处理，连续更新时取消旧定时器，延迟3秒后统一刷新
        local timer
        nickTag:RegisterCallback("NickTag_Update", function()
            if timer then
                timer:Cancel()
                timer = nil
            end
            timer = C_Timer.NewTimer(3, UpdateAll)
        end)
    end
end)