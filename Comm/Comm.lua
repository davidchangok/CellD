local _, Cell = ...
local L = Cell.L
local F = Cell.funcs

-- 加载通信所需的第三方库
-- LibDeflate: 数据压缩/解压，压缩等级9（最高）
-- LibSerialize: 将Lua表序列化为字符串，支持循环引用
-- AceComm-3.0: WoW插件间通信框架
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local deflateConfig = {level = 9}
local Serializer = LibStub:GetLibrary("LibSerialize")
local Comm = LibStub:GetLibrary("AceComm-3.0")

-- 序列化并压缩数据，用于Addon频道传输
-- 流程：Lua表 → 字符串 → Deflate压缩 → WoW频道编码
local function Serialize(data)
    local serialized = Serializer:Serialize(data) -- 序列化Lua表为字符串
    local compressed = LibDeflate:CompressDeflate(serialized, deflateConfig) -- Deflate压缩
    return LibDeflate:EncodeForWoWAddonChannel(compressed) -- 编码为WoW频道可传输格式
end

-- 解码并反序列化从Addon频道接收的数据
-- 流程：WoW频道编码 → 解码 → Deflate解压 → 字符串 → Lua表
local function Deserialize(encoded)
    local decoded = LibDeflate:DecodeForWoWAddonChannel(encoded) -- 解码WoW频道数据
    local decompressed = LibDeflate:DecompressDeflate(decoded) -- Deflate解压
    if not decompressed then
        F.Debug("Error decompressing: " .. errorMsg)
        return
    end
    local success, data = Serializer:Deserialize(decompressed) -- 反序列化字符串为Lua表
    if not success then
        F.Debug("Error deserializing: " .. data)
        return
    end
    return data
end

-----------------------------------------
-- 通信限制检测（Midnight 12.0.0+）
-- 在战斗中、大秘境进行中、PvP战场中，暴雪会屏蔽插件间的Addon频道通信
-- 该函数判断当前是否处于受限制的上下文，若受限则不应发送任何Addon消息
-----------------------------------------
local function IsCommRestricted()
    if not Cell.isMidnight then return false end
    -- 检查是否在BOSS战中
    if IsEncounterInProgress and IsEncounterInProgress() then return true end
    -- 检查是否在大秘境进行中
    if C_MythicPlus and C_MythicPlus.IsRunActive and C_MythicPlus.IsRunActive() then return true end
    -- 检查是否在PvP竞技场/战场中
    if C_PvP and C_PvP.IsActiveBattlefield and C_PvP.IsActiveBattlefield() then return true end
    return false
end

-- 导出供其他Comm文件使用（如 Nicknames.lua）
function F.IsCommRestricted()
    return IsCommRestricted()
end

-- 待发送消息队列：当通信受限时，消息不直接发送而是暂存于此
-- 队列元素结构: {prefix=前缀, message=消息体, channel=频道, target=目标, priority=优先级}
local pendingComms = {}

-- 将消息加入待发送队列（通信受限时使用）
local function QueueComm(prefix, message, channel, target, priority)
    tinsert(pendingComms, {prefix=prefix, message=message, channel=channel, target=target, priority=priority})
end

-- 清空待发送队列：将队列中的消息逐条发送出去
-- 调用前需确保通信不再受限，否则直接返回
local function FlushPendingComms()
    if IsCommRestricted() then return end
    if #pendingComms == 0 then return end
    local toSend = pendingComms
    pendingComms = {}
    for _, msg in ipairs(toSend) do
        Comm:SendCommMessage(msg.prefix, msg.message, msg.channel, msg.target, msg.priority or "NORMAL")
    end
end

-- 通信恢复监听Frame：监听战斗结束和离开世界事件
-- 当战斗结束后延迟1秒清空待发送队列，避免通信刚恢复就立即大量发送
local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("ENCOUNTER_END")
commFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
commFrame:SetScript("OnEvent", function()
    C_Timer.After(1, FlushPendingComms)
end)

-----------------------------------------
-- WeakAuras 通知接口
-- 向 WeakAuras 发送 CELL_NOTIFY 事件，使WA可以基于Cell的内部事件触发自定义特效
-- 参数: type 为事件类型字符串，... 为附加参数
-----------------------------------------
function F.Notify(type, ...)
    if WeakAuras then
        WeakAuras.ScanEvents("CELL_NOTIFY", type, ...)
    end
end

-----------------------------------------
-- 通信频道选择
-- 根据玩家当前所在队伍类型，自动选择最合适的聊天频道作为Addon通信频道
-- 副本队伍→INSTANCE_CHAT, 团队→RAID, 小队→PARTY
-----------------------------------------
local sendChannel
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
-- 版本检查系统
-- 在进入队伍/团队和登录时向队友/公会广播自身版本号
-- 若收到比自身更新的版本号，提示用户前往CurseForge更新
-----------------------------------------
-- 事件处理Frame：通过 method-call 风格分发事件（self[event](self, ...)）
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end)

-- 队伍/团队更新事件：加入队伍时广播自身版本号给队友
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
function eventFrame:GROUP_ROSTER_UPDATE()
    if IsInGroup() then
        eventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
        UpdateSendChannel()
        -- 在限制环境下（战斗/大秘境/PvP）不发送Addon消息
        if IsCommRestricted() then
            F.Debug("Cell: Comm suppressed - restricted context (CELL_VERSION group)")
            return
        end
        Comm:SendCommMessage("CELL_VERSION", Cell.version, sendChannel, nil, "NORMAL")
    end
end

-- 登录事件：登录时向公会广播自身版本号
eventFrame:RegisterEvent("PLAYER_LOGIN")
function eventFrame:PLAYER_LOGIN()
    if IsInGuild() then
        -- 在限制环境下（战斗/大秘境/PvP）不发送Addon消息
        if IsCommRestricted() then
            F.Debug("Cell: Comm suppressed - restricted context (CELL_VERSION guild)")
            return
        end
        Comm:SendCommMessage("CELL_VERSION", Cell.version, "GUILD", nil, "NORMAL")
    end
end

-- 接收他人版本号：比较版本，若对方更新则提示用户
-- 每25200秒（7小时）最多提示一次，避免频繁骚扰
Comm:RegisterComm("CELL_VERSION", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    local version = tonumber(string.match(message, "%d+"))
    local myVersion = tonumber(string.match(Cell.version, "%d+"))
    if (not CellDB["lastVersionCheck"] or time()-CellDB["lastVersionCheck"]>=25200) and version and myVersion and myVersion < version then
        CellDB["lastVersionCheck"] = time()
        F.Print(L["New version found (%s). Please visit %s to get the latest version."]:format(message, "|cFF00CCFFhttps://www.curseforge.com/wow/addons/cell|r"))
    end
end)

-----------------------------------------
-- 标记锁定/解锁通知系统
-- 当队伍成员锁定或解锁世界标记（星星、大饼等）时，通过Addon频道广播此操作
-- 接收方根据权限设置决定是否在聊天框打印提示信息
-----------------------------------------

-- 接收标记通知：解析他人发送的标记锁定/解锁消息
-- data[1]: true=锁定, false=解锁; data[2]: 标记索引; data[3]: 目标名称
-- 仅在玩家拥有标记权限且开启了标记提示功能时才打印消息
Comm:RegisterComm("CELL_MARKS", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    local data = Deserialize(message)
    if Cell.vars.hasPartyMarkPermission and CellDB["tools"]["marks"][1] and (strfind(CellDB["tools"]["marks"][3], "^target") or strfind(CellDB["tools"]["marks"][3], "^both")) and data then
        sender = F.GetClassColorStr(select(2, UnitClass(sender)))..sender.."|r"

        if data[1] then -- 锁定标记
            F.Print(L["%s lock %s on %s."]:format(sender, F.GetMarkEscapeSequence(data[2]), data[3]))
        else
            F.Print(L["%s unlock %s from %s."]:format(sender, F.GetMarkEscapeSequence(data[2]), data[3]))
        end
    end
end)

-- 广播标记锁定操作：将目标标记和名称序列化后发送给全队
function F.NotifyMarkLock(mark, name, class)
    name = F.GetClassColorStr(class)..name.."|r"
    F.Print(L["%s lock %s on %s."]:format(L["You"], F.GetMarkEscapeSequence(mark), name))

    UpdateSendChannel()
    -- 在限制环境下（战斗/大秘境/PvP）不发送Addon消息
    if IsCommRestricted() then
        F.Debug("Cell: Comm suppressed - restricted context (CELL_MARKS lock)")
        return
    end
    Comm:SendCommMessage("CELL_MARKS", Serialize({true, mark, name}), sendChannel, nil, "ALERT")
end

-- 广播标记解锁操作：将目标标记和名称序列化后发送给全队
function F.NotifyMarkUnlock(mark, name, class)
    name = F.GetClassColorStr(class)..name.."|r"
    F.Print(L["%s unlock %s from %s."]:format(L["You"], F.GetMarkEscapeSequence(mark), name))

    UpdateSendChannel()
    -- 在限制环境下（战斗/大秘境/PvP）不发送Addon消息
    if IsCommRestricted() then
        F.Debug("Cell: Comm suppressed - restricted context (CELL_MARKS unlock)")
        return
    end
    Comm:SendCommMessage("CELL_MARKS", Serialize({false, mark, name}), sendChannel, nil, "ALERT")
end

-----------------------------------------
-- 优先级协商系统
-- 当队伍中有多个Cell用户时，通过优先级协商选出一个"主控"来执行特定操作（如自动标记）
-- 优先级规则：队长=0（最高），团队成员按队伍索引排序，小队按名字字母排序
-- 数值越小优先级越高，highestPriority记录全队中看到的最小值
-----------------------------------------
local myPriority                   -- 自己的优先级值
local highestPriority = 99         -- 全队最高优先级（默认99最低）
Cell.hasHighestPriority = false    -- 导出标志：自己是否拥有最高优先级

-- 更新自身优先级
-- 队长优先级=0，团队成员按队伍索引，小队成员按名字字母排序
local function UpdatePriority()
    myPriority = 99
    if UnitIsGroupLeader("player") then
        myPriority = 0
    else
        if IsInRaid() then
            -- 团队中：按团队编号（raid1, raid2...）确定优先级
            for i = 1, GetNumGroupMembers() do
                if UnitIsUnit("player", "raid"..i) then
                    myPriority = i
                    break
                end
            end
        elseif IsInGroup() then -- 小队中：按全名（名字-服务器）字母排序确定优先级
            local players = {}
            local pName, pRealm = UnitFullName("player")
            pRealm = pRealm or GetRealmName()
            pName = pName.."-"..pRealm
            tinsert(players, pName)

            for i = 1, GetNumGroupMembers()-1 do
                local name, realm = UnitFullName("party"..i)
                tinsert(players, name.."-"..(realm or pRealm))
            end
            table.sort(players)

            for i, p in pairs(players) do
                if p == pName then
                    myPriority = i
                    break
                end
            end
        end
    end

end

-- 定时器句柄：t_check（检查请求）、t_send（发送自身优先级）、t_update（更新最终结果）
local t_check, t_send, t_update

-- 发起优先级协商：计算自身优先级，1秒后广播CELL_CPRIO检查请求
-- 延迟1秒是为了确保myPriority已正确计算
function F.CheckPriority()
    UpdatePriority()
    -- NOTE: needs time to calc myPriority
    C_Timer.After(1, function()
        UpdateSendChannel()
        -- 在限制环境下（战斗/大秘境/PvP）不发送Addon消息
        if IsCommRestricted() then
            F.Debug("Cell: Comm suppressed - restricted context (CELL_CPRIO chk)")
            return
        end
        Comm:SendCommMessage("CELL_CPRIO", "chk", sendChannel, nil, "ALERT")
    end)
    -- NOTE: 以下为备用重试逻辑，已注释
    -- if t_check then t_check:Cancel() end
    -- t_check = C_Timer.NewTimer(2, function()
    --     UpdateSendChannel()
    --     Comm:SendCommMessage("CELL_CPRIO", "chk", sendChannel, nil, "BULK")
    -- end)
end

-- 接收优先级协商请求：重置highestPriority，2秒后广播自身优先级（等待所有请求收敛）
-- 仅当myPriority已计算（即GROUP_JOINED之后）才响应
Comm:RegisterComm("CELL_CPRIO", function(prefix, message, channel, sender)
    if not myPriority then return end -- 刚加入队伍时myPriority尚未计算，忽略
    highestPriority = 99

    -- 等待所有check请求收敛后，延迟2秒发送自身优先级
    if t_send then t_send:Cancel() end
    t_send = C_Timer.NewTimer(2, function()
        UpdateSendChannel()
        -- 在限制环境下（战斗/大秘境/PvP）不发送Addon消息
        if IsCommRestricted() then
            F.Debug("Cell: Comm suppressed - restricted context (CELL_PRIO)")
            return
        end
        Comm:SendCommMessage("CELL_PRIO", tostring(myPriority), sendChannel, nil, "ALERT")
    end)
end)

-- 接收他人优先级：更新highestPriority，2秒后判定最终结果
-- 通过反复取消/重置t_update定时器来等待所有CELL_PRIO消息收齐
Comm:RegisterComm("CELL_PRIO", function(prefix, message, channel, sender)
    if not myPriority then return end -- 刚加入队伍时myPriority尚未计算，忽略

    local p = tonumber(message)
    if p then
        highestPriority = highestPriority < p and highestPriority or p  -- 保留最小值（最高优先级）

        if t_update then t_update:Cancel() end
        t_update = C_Timer.NewTimer(2, function()
            Cell.hasHighestPriority = myPriority <= highestPriority
            Cell.Fire("UpdatePriority", Cell.hasHighestPriority)  -- 触发全局事件通知其他模块
            F.Debug("|cff00ff00UpdatePriority:|r", Cell.hasHighestPriority)
        end)
    end
end)

-----------------------------------------
-- 跨服通信发送函数
-- WoW的WHISPER频道仅限同服务器，跨服时必须通过小队/团队频道中继
-- 消息格式：跨服时在消息前附加 "目标全名:" 前缀，接收方解析时剥离
-----------------------------------------
local function CrossRealmSendCommMessage(prefix, message, playerName, priority, callbackFn)
    -- 在限制环境下（战斗/大秘境/PvP）不发送Addon消息
    if IsCommRestricted() then
        F.Debug("Cell: Comm suppressed - restricted context (CrossRealm:", prefix, ")")
        return
    end
    -- NOTE: UnitIsSameServer要求目标必须在队伍中，否则始终返回true
    if UnitIsSameServer(playerName) then
        Comm:SendCommMessage(prefix, message, "WHISPER", playerName, priority, callbackFn)
    else
        -- 跨服场景：在小队或团队频道中广播，消息前加目标全名供接收方路由
        if UnitInParty(playerName) then
            Comm:SendCommMessage(prefix, playerName..":"..message, "PARTY", nil, priority, callbackFn)
        elseif UnitInRaid(playerName) then
            Comm:SendCommMessage(prefix, playerName..":"..message, "RAID", nil, priority, callbackFn)
        end
    end
end

-----------------------------------------
-- 团队Debuff与布局方案的发送/接收
-- 通过聊天超链接实现Debuff配置和Cell布局的分享
-- 发送方在聊天中生成可点击的超链接，接收方点击后触发SetItemRef导入
-----------------------------------------

-- 聊天消息过滤器：将原始Cell消息转换为可点击的超链接格式
-- 匹配格式: "[Cell:Debuffs: ...]" 和 "[Cell:Layout: ...]"
-- 转换后生成 garrmission 协议的聊天超链接，点击可触发接收流程
local function filterFunc(self, event, msg, player, arg1, arg2, arg3, flag, channelId, ...)
    local newMsg = ""

    local type = msg:match("%[Cell:(.+): .+]")
    if type == "Debuffs" then
        -- 尝试匹配带Boss名的Debuff消息
        local bossName, instanceName, playerName = msg:match("%[Cell:Debuffs: (.+) %((.+)%) %- ([^%s]+%-[^%s]+)%]")
        if bossName and instanceName and playerName then
            newMsg = "|Hgarrmission:cell-debuffs|h|cFFFF0066["..L[type]..": "..bossName.." ("..instanceName..") - "..playerName.."]|h|r"
        else
            -- 无Boss名时仅匹配副本名
            instanceName, playerName = msg:match("%[Cell:Debuffs: (.+) %- ([^%s]+%-[^%s]+)%]")
            if instanceName and playerName then
                newMsg = "|Hgarrmission:cell-debuffs|h|cFFFF0066["..L[type]..": "..instanceName.." - "..playerName.."]|h|r"
            end
        end
    elseif type == "Layout" then
        -- 匹配布局分享消息
        local layoutName, playerName = msg:match("%[Cell:Layout: (.+) %- ([^%s]+%-[^%s]+)%]")
        if layoutName and playerName then
            if layoutName == "default" then
                -- 将内部 "default" 转换为显示用的本地化默认值
                layoutName = _G.DEFAULT
            end
            newMsg = "|Hgarrmission:cell-layout|h|cFFFF0066["..L[type]..": "..layoutName.." - "..playerName.."]|h|r"
        end
    end

    if newMsg ~= "" then
        return false, newMsg, player, arg1, arg2, arg3, flag, channelId, ...
    end
end

-- 在所有聊天频道注册过滤器，拦截Cell格式的原始消息并转为可点击超链接
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT", filterFunc)
ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT_LEADER", filterFunc)

-- 是否正在请求接收数据（防止重复请求/导出冲突）
local isRequesting

-- 接收CELL_SEND消息：收到发送方返回的Debuff或Layout数据
-- 仅在isRequesting状态下处理（即用户已点击请求按钮）
-- 跨服消息需从 "目标全名:数据" 格式中剥离目标前缀
Comm:RegisterComm("CELL_SEND", function(prefix, message, channel, sender)
    if not isRequesting then return end
    if channel ~= "WHISPER" then
        -- 跨服场景：消息格式为 "目标全名:实际数据"，剥离目标前缀
        local target
        target, message = strsplit(":", message, 2)
        if target ~= Cell.vars.playerNameFull then
            return
        end
    end

    local receivedData = Deserialize(message)

    if Cell.frames.receivingFrame then
        if receivedData then
            -- 数据接收成功，显示导入界面（含确认按钮）
            Cell.frames.receivingFrame:ShowImport(true, receivedData, function()
                isRequesting = false
            end)
        else
            -- 数据解析失败，显示错误提示UI
            Cell.frames.receivingFrame:ShowImport(false, nil, function()
                isRequesting = false
            end)
        end
    end
end)

-- 接收CELL_SEND_PROG消息：显示数据传输进度
-- 消息格式: "已完成|总量"，如 "5|20" 表示已传输5/20个数据块
Comm:RegisterComm("CELL_SEND_PROG", function(prefix, message, channel, sender)
    if not isRequesting then return end
    if channel ~= "WHISPER" then
        -- 跨服场景：消息格式为 "目标全名:已完成|总量"，剥离目标前缀
        local target
        target, message = strsplit(":", message, 2)
        if target ~= Cell.vars.playerNameFull then
            return
        end
    end

    local done, total = strsplit("|", message)
    done, total = tonumber(done), tonumber(total)

    if Cell.frames.receivingFrame then
        Cell.frames.receivingFrame:ShowProgress(done, total)
    end
end)

-- 接收CELL_REQ消息：收到他人的数据请求，从本地数据库中查找对应数据并返回
-- 消息格式: "类型:参数1:参数2"（如 "Debuffs:副本名:Boss名" 或 "Layout:布局名"）
-- 找到数据后通过CrossRealmSendCommMessage返回，并附带回调报告传输进度
Comm:RegisterComm("CELL_REQ", function(prefix, message, channel, requester)
    if channel ~= "WHISPER" then
        -- 跨服场景：剥离目标前缀
        local target
        target, message = strsplit(":", message, 2)
        if target ~= Cell.vars.playerNameFull then
            return
        end
    end

    -- 解析请求类型和参数
    local type, name1, name2 = strsplit(":", message)
    local requestData

    -- print(type, name1, name2)
    if type == "Debuffs" then
        -- name1=副本名, name2=Boss名
        local instanceId, bossId = F.GetInstanceAndBossId(name1, name2)
        if not instanceId then return end -- 无效的副本名称

        requestData = {
            ["type"] = "Debuffs",
            ["instanceId"] = instanceId,
            ["bossId"] = bossId,
            ["version"] = Cell.versionNum
        }

        -- 从本地数据库查找对应Debuff数据
        if not bossId then -- 请求所有Boss的Debuff数据
            if CellDB["raidDebuffs"][instanceId] then
                requestData["data"] = CellDB["raidDebuffs"][instanceId]
            end
        else
            if CellDB["raidDebuffs"][instanceId] and CellDB["raidDebuffs"][instanceId][bossId] then
                requestData["data"] = CellDB["raidDebuffs"][instanceId][bossId]
            end
        end
    elseif type == "Layout" then
        -- name1=布局名称
        if name1 == _G.DEFAULT then
            -- 将显示用的本地化默认值转回内部key "default"
            name1 = "default"
        end
        if name1 and CellDB["layouts"][name1] then
            requestData = {
                ["type"] = "Layout",
                ["name"] = name1,
                ["version"] = Cell.versionNum,
                ["data"] = CellDB["layouts"][name1]
            }
        end
    end

    -- texplore(requestData)

    if not requestData then return end
    -- 通过跨服通信返回数据，BULK优先级传输大量数据
    -- 回调函数在每完成一个数据块时发送进度通知（done|total）
    CrossRealmSendCommMessage("CELL_SEND", Serialize(requestData), requester, "BULK", function(arg, done, total)
        -- 发送传输进度：当前完成数 | 总块数
        CrossRealmSendCommMessage("CELL_SEND_PROG", done.."|"..total, requester, "ALERT")
    end)
end)

-- 显示接收Frame UI控件
-- type: "Debuffs" 或 "Layout"
-- playerName: 发送方全名
-- name1: 副本名(Buffs) 或 布局名(Layout)
-- name2: Boss名(Buffs) 或 nil(Layout)
local function ShowReceivingFrame(type, playerName, name1, name2)
    if not Cell.frames.receivingFrame then
        -- 首次使用时创建接收Frame，挂载到主Frame上
        Cell.frames.receivingFrame = Cell.CreateReceivingFrame(Cell.frames.mainFrame)
        Cell.frames.receivingFrame:SetOnCancel(function(b)
            isRequesting = false
        end)
    end

    -- 设置请求回调：用户点击确认后发送CELL_REQ请求
    Cell.frames.receivingFrame:SetOnRequest(function(b)
        isRequesting = true
        --! 发送数据请求
        CrossRealmSendCommMessage("CELL_REQ", type..":"..name1..":"..(name2 or ""), playerName, "ALERT")
    end)

    Cell.frames.receivingFrame:ShowFrame(type, playerName, name1, name2)
end

-- Hook SetItemRef：拦截聊天超链接点击事件
-- 当玩家点击[Cell:Debuffs:...]或[Cell:Layout:...]链接时，弹出接收Frame
-- 链接协议为 garrmission:cell-debuffs 和 garrmission:cell-layout
hooksecurefunc("SetItemRef", function(link, text)
    if isRequesting then return end
    if link == "garrmission:cell-debuffs" then
        -- 解析Debuff链接：提取Boss名、副本名、发送方全名
        local bossName, instanceName, playerName = text:match("|Hgarrmission:cell%-debuffs|h|cFFFF0066%[.+: (.+) %((.+)%) %- ([^%s]+%-[^%s]+)%]|h|r")
        if bossName and instanceName and playerName then
            ShowReceivingFrame("Debuffs", playerName, instanceName, bossName)
        else
            -- 无Boss名的Debuff链接（整个副本的所有Boss）
            instanceName, playerName = text:match("|Hgarrmission:cell%-debuffs|h|cFFFF0066%[.+: (.+) %- ([^%s]+%-[^%s]+)%]|h|r")
            ShowReceivingFrame("Debuffs", playerName, instanceName)
        end
    elseif link == "garrmission:cell-layout" then
        -- 解析Layout链接：提取布局名、发送方全名
        local layoutName, playerName = text:match("|Hgarrmission:cell%-layout|h|cFFFF0066%[.+: (.+) %- ([^%s]+%-[^%s]+)%]|h|r")
        ShowReceivingFrame("Layout", playerName, layoutName)
    end
end)