-- 模块导入：Cell 核心对象、本地化、通用函数、像素完美缩放、动画系统
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs
local A = Cell.animations

-- 就位确认按钮和倒数拉怪按钮的引用
local readyBtn, pullBtn

-- 创建主按钮容器框架，使用 SecureFrameTemplate 以支持战斗中保护模式
-- BackdropTemplate 用于支持背景样式
local buttonsFrame = CreateFrame("Frame", "CellReadyAndPullFrame", Cell.frames.mainFrame, "SecureFrameTemplate,BackdropTemplate")
Cell.frames.readyAndPullFrame = buttonsFrame
-- 设置容器大小（默认 60x55）
P.Size(buttonsFrame, 60, 55)
-- 将容器定位到屏幕中央的右上侧（偏移 -1,-1）
PixelUtil.SetPoint(buttonsFrame, "TOPRIGHT", CellParent, "CENTER", -1, -1)
-- 确保容器不会被拖出屏幕边界
buttonsFrame:SetClampedToScreen(true)
-- 允许左键拖拽移动
buttonsFrame:SetMovable(true)
buttonsFrame:RegisterForDrag("LeftButton")
-- 拖拽开始时允许移动，清除用户手动放置标记
buttonsFrame:SetScript("OnDragStart", function()
    buttonsFrame:StartMoving()
    buttonsFrame:SetUserPlaced(false)
end)
-- 拖拽结束时保存位置到数据库
buttonsFrame:SetScript("OnDragStop", function()
    buttonsFrame:StopMovingOrSizing()
    P.SavePosition(buttonsFrame, CellDB["tools"]["readyAndPull"][4])
end)

-------------------------------------------------
-- 拖拽移动指示器（mover）
-- 当玩家进入 UI 编辑模式时，显示绿色的半透明方框及"Mover"文字标记
-- 方便玩家识别并拖拽此按钮组到想要的位置
-------------------------------------------------
-- 创建"Myover"提示文字，位于容器顶部
buttonsFrame.moverText = buttonsFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
buttonsFrame.moverText:SetPoint("TOP", 0, -3)
buttonsFrame.moverText:SetText(L["Mover"])
buttonsFrame.moverText:Hide()

-- ShowMover：控制移动指示器的显示/隐藏
-- show=true 时开启鼠标交互并以绿色半透明边框包裹框架
-- show=false 时关闭鼠标交互并清除边框样式，恢复淡出或完全透明
local function ShowMover(show)
    if show then
        -- 如果玩家未启用此工具，不显示 mover
        if not CellDB["tools"]["readyAndPull"][1] then return end
        buttonsFrame:EnableMouse(true)
        buttonsFrame.moverText:Show()
        -- 绿色半透明边框，方便识别可拖拽区域
        Cell.StylizeFrame(buttonsFrame, {0, 1, 0, 0.4}, {0, 0, 0, 0})
        -- 无权限时（非队长/非助理），临时显示按钮以便玩家了解尺寸位置
        if not F.HasPermission() then -- button not shown
            readyBtn:Show()
            pullBtn:Show()
        end
        buttonsFrame:SetAlpha(1)
    else
        buttonsFrame:EnableMouse(false)
        buttonsFrame.moverText:Hide()
        -- 移除边框样式
        Cell.StylizeFrame(buttonsFrame, {0, 0, 0, 0}, {0, 0, 0, 0})
        -- 无权限时恢复隐藏，按钮不应对非队长可见
        if not F.HasPermission() then -- button should not shown
            readyBtn:Hide()
            pullBtn:Hide()
        end
        -- 根据用户淡出设置调整透明度
        buttonsFrame:SetAlpha(CellDB["tools"]["fadeOut"] and 0 or 1)
    end
end
-- 注册 ShowMover 回调，与 UI 编辑模式的开关联动
Cell.RegisterCallback("ShowMover", "RaidButtons_ShowMover", ShowMover)

-------------------------------------------------
-- 倒数拉怪按钮（pull）
-- 队长/助理点击后发起倒数计时器，到时间后在团队/小队频道发送"Go!"消息
-- 支持 DBM、BigWigs（MRT）、BigWigs 等多种首领模块的倒数协议
-------------------------------------------------
pullBtn = Cell.CreateStatusBarButton(buttonsFrame, L["Pull"], {60, 17}, 7, "SecureActionButtonTemplate")
-- 注册四种点击方式，同时支持按住施法和松开施法模式
pullBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "LeftButtonDown", "RightButtonDown") -- NOTE: ActionButtonUseKeyDown will affect this
pullBtn:Hide()

-------------------------------------------------
-- 倒数进度条事件分发（pull bar）
-- OnEvent 将事件名转发为同名方法调用，简洁的事件分发机制
-------------------------------------------------
pullBtn:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end)

-- pullTicker：每秒触发的计时器句柄；isPullTickerRunning：倒数是否进行中
local pullTicker, isPullTickerRunning

-- Start：启动倒数计时器
-- sec - 倒数的总秒数
-- sendToChat - 是否向团队/小队频道发送倒数消息（仅在无内置倒数协议的经典服使用）
local function Start(sec, sendToChat)
    isPullTickerRunning = true
    pullBtn:SetMaxValue(sec)
    pullBtn:Start()

    -- 更新按钮文字为剩余秒数
    pullBtn:SetText(sec)
    -- 取消已有的计时器（避免重复）
    if pullTicker then
        pullTicker:Cancel()
        pullTicker = nil
    end
    pullBtn.sec = sec
    -- 每秒触发一次，更新按钮文字和发送频道消息
    pullTicker = C_Timer.NewTicker(1, function()
        pullBtn.sec = pullBtn.sec - 1
        if pullBtn.sec == 0 then
            -- 倒数结束，显示"Go!"
            isPullTickerRunning = false
            pullBtn:SetText(L["Go!"])
            if sendToChat then
                SendChatMessage(L["Go!"], IsInRaid() and "RAID_WARNING" or "PARTY")
            end
        elseif pullBtn.sec == -1 then
            -- 倒数结束后一秒恢复到"Pull"文字
            pullBtn:SetText(L["Pull"])
        else
            -- 倒数进行中，更新秒数
            pullBtn:SetText(pullBtn.sec)
            if sendToChat then
                -- 大于3秒时发普通频道消息，最后3秒发 RAID_WARNING 醒目提醒
                if pullBtn.sec > 3 then
                    SendChatMessage(pullBtn.sec, IsInRaid() and "RAID" or "PARTY")
                else
                    SendChatMessage(pullBtn.sec, IsInRaid() and "RAID_WARNING" or "PARTY")
                end
            end
        end
    end, sec+1)
end

-- Stop：停止并取消倒数计时器
local function Stop()
    isPullTickerRunning = false
    pullBtn:Stop()

    -- 恢复按钮文字为"Pull"
    pullBtn:SetText(L["Pull"])
    if pullTicker then
        pullTicker:Cancel()
        pullTicker = nil
    end
end

-- CHAT_MSG_ADDON 事件处理：监听来自 DBM 的倒数 pull 消息
-- prefix="D4" 为 DBM 的插件通信频道，text 格式为 "PT\t<秒数>"
function pullBtn:CHAT_MSG_ADDON(prefix, text)
    if prefix == "D4" then -- DBM
        local pre, sec = strsplit("\t", text)
        sec = tonumber(sec)
        if pre == "PT" and sec > 0 then -- 收到开始倒数指令
            Start(sec)
        elseif pre == "PT" and sec  == 0 then -- 收到取消倒数指令
            Stop()
        end

    -- 预留的 BigWigs 倒数监听（当前未启用）
    -- elseif prefix == "BigWigs" then
    --     local _, pre, sec = strsplit("^", text)
    --     sec = tonumber(sec)
    --     if pre == "Pull" and sec > 0 then -- start
    --     elseif pre == "Pull" and sec  == 0 then -- cancel
    --     end
    end
end

-- START_TIMER 事件处理：监听正式服内置倒计时事件（/cd 命令触发）
-- totalTime > 0 表示倒数开始，== 0 表示倒数取消
function pullBtn:START_TIMER(timerType, timeRemaining, totalTime)
    if totalTime > 0 then
        Start(totalTime)
    else
        Stop()
    end
end

-------------------------------------------------
-- 就位确认按钮（ready）
-- 左键点击发送就位确认，右键点击发起职责确认
-- 在就位确认进行中实时显示已确认人数
-------------------------------------------------
readyBtn = Cell.CreateStatusBarButton(buttonsFrame, L["Ready"], {60, 17}, 35)
-- P.Point(readyBtn, "BOTTOMLEFT", pullBtn, "TOPLEFT", 0, 3)
readyBtn:Hide()

-- 左键就位确认，右键职责确认
readyBtn:RegisterForClicks("LeftButtonDown", "RightButtonDown")
readyBtn:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        DoReadyCheck()
    else
        InitiateRolePoll()
    end
end)

-- ready 表：记录所有已确认就位的玩家名称
local ready = {}

-- 就位确认相关事件处理
-- READY_CHECK：就位确认开始，初始化进度条和已确认名单
-- READY_CHECK_FINISHED：就位确认结束，停止进度条
-- READY_CHECK_CONFIRM：某个玩家确认就位，更新计数
readyBtn:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "READY_CHECK" then
        -- arg2 为超时秒数，用于设置进度条最大值
        readyBtn:SetMaxValue(arg2)
        readyBtn:Start()
        -- 清空并初始化确认名单（玩家自己默认已确认）
        wipe(ready)
        tinsert(ready, "player")
        readyBtn:SetText("1 / "..GetNumGroupMembers())
    elseif event == "READY_CHECK_FINISHED" then
        readyBtn:Stop()
        readyBtn:SetText(L["Ready"])
    else
        -- READY_CHECK_CONFIRM：arg2 为 true 表示该玩家已确认
        if arg2 then -- isReady
            if IsInRaid() then
                -- 团队中只统计 raid 分组内的玩家（排除坦克/治疗等独立分组）
                if string.find(arg1, "raid") then tinsert(ready, arg1) end
            else
                tinsert(ready, arg1)
            end
            -- 更新按钮文字为"已确认数 / 总人数"
            readyBtn:SetText(#ready.." / "..GetNumGroupMembers())
        end
    end
end)

-------------------------------------------------
-- 图标样式（style）
-- 为图标按钮模式创建纹理图标，支持按下的视觉反馈和禁用状态灰化
-------------------------------------------------

-- CreateTexture：为按钮创建图标纹理
-- b - 目标按钮
-- tex - 图标纹理路径
local function CreateTexture(b, tex)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("CENTER")
    P.Size(b.tex, 16, 16)
    b.tex:SetTexture(tex)

    -- 按下效果：图标向下偏移 1px 模拟按压
    b.onMouseDown = function()
        b.tex:ClearAllPoints()
        b.tex:SetPoint("CENTER", 0, -1)
    end
    -- 松开时恢复图标居中位置
    b.onMouseUp = function()
        b.tex:ClearAllPoints()
        b.tex:SetPoint("CENTER")
    end
    b:SetScript("OnMouseDown", b.onMouseDown)
    b:SetScript("OnMouseUp", b.onMouseUp)

    -- 启用/禁用状态切换
    -- 启用：白色图标 + 正常按压反馈
    b:HookScript("OnEnable", function()
        b.tex:SetVertexColor(1, 1, 1)
        b:SetScript("OnMouseDown", b.onMouseDown)
        b:SetScript("OnMouseUp", b.onMouseUp)
    end)
    -- 禁用：灰化图标 + 移除按压反馈
    b:HookScript("OnDisable", function()
        b.tex:SetVertexColor(0.4, 0.4, 0.4)
        b:SetScript("OnMouseDown", nil)
        b:SetScript("OnMouseUp", nil)
    end)
end

-- UpdateStyle：根据配置切换文字按钮模式与图标按钮模式
-- 文字按钮模式：显示文字标签，注册就位确认事件
-- 图标按钮模式：显示图标，隐藏文字，注销就位确认事件（纯手动使用）
local function UpdateStyle()
    P.ClearPoints(pullBtn)
    P.ClearPoints(readyBtn)

    if CellDB["tools"]["readyAndPull"][2] == "text_button" then
        -- 文字按钮模式：注册就位确认的三个事件
        readyBtn:RegisterEvent("READY_CHECK")
        readyBtn:RegisterEvent("READY_CHECK_FINISHED")
        readyBtn:RegisterEvent("READY_CHECK_CONFIRM")

        -- 容器 60x55，按钮 60x17，上下排列
        P.Size(buttonsFrame, 60, 55)
        P.Size(pullBtn, 60, 17)
        P.Size(readyBtn, 60, 17)

        P.Point(pullBtn, "BOTTOMLEFT")
        P.Point(readyBtn, "BOTTOMLEFT", pullBtn, "TOPLEFT", 0, 3)

        -- 隐藏图标，显示文字
        pullBtn.tex:Hide()
        pullBtn:SetText(L["Pull"])
        readyBtn.tex:Hide()
        readyBtn:SetText(L["Ready"])
    else
        -- 图标按钮模式：停止当前进行的倒数/就位确认
        Stop()
        readyBtn:Stop()

        -- 注销所有事件，图标模式下手动使用不自动响应
        pullBtn:UnregisterAllEvents()
        readyBtn:UnregisterAllEvents()

        if CellDB["tools"]["readyAndPull"][2] == "icon_button_h" then -- 水平排列
            buttonsFrame:SetSize(P.Scale(40)+P.Scale(2), P.Scale(40))
            P.Size(pullBtn, 20, 20)
            P.Size(readyBtn, 20, 20)

            P.Point(readyBtn, "BOTTOMLEFT")
            P.Point(pullBtn, "BOTTOMLEFT", readyBtn, "BOTTOMRIGHT", 2, 0)
        else -- 垂直排列
            P.Size(buttonsFrame, 20, 62)
            P.Size(pullBtn, 20, 20)
            P.Size(readyBtn, 20, 20)

            P.Point(pullBtn, "BOTTOMLEFT")
            P.Point(readyBtn, "BOTTOMLEFT", pullBtn, "TOPLEFT", 0, 2)
        end

        -- 显示图标，隐藏文字
        pullBtn.tex:Show()
        pullBtn:SetText("")
        readyBtn.tex:Show()
        readyBtn:SetText("")
    end
end

-------------------------------------------------
-- 淡出效果（fade out）
-- 鼠标离开一段时间后按钮组自动淡出，鼠标移入时恢复不透明
-- mover 显示时（编辑模式）不淡出，始终可见
-------------------------------------------------
A.ApplyFadeInOutToParent(buttonsFrame, function()
    return CellDB["tools"]["fadeOut"] and not buttonsFrame.moverText:IsShown()
end, readyBtn, pullBtn)

-------------------------------------------------
-- 权限检查与工具配置更新（functions）
-------------------------------------------------

-- CheckPermission：检查玩家是否有权限使用拉怪/就位确认功能
-- 有权限（队长/助理）且功能已启用时显示按钮
-- 无权限时隐藏按钮
-- 战斗中进入保护模式，等待战斗结束后通过 PLAYER_REGEN_ENABLED 事件重新检查
local function CheckPermission()
    if InCombatLockdown() then
        -- 战斗中无法操作按钮状态，注册事件等脱战后再检查
        buttonsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        -- 脱战后不再需要监听
        buttonsFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if F.HasPermission() and CellDB["tools"]["readyAndPull"][1] then
            readyBtn:Show()
            readyBtn:SetEnabled(true)
            pullBtn:Show()
            pullBtn:SetEnabled(true)
        else
            readyBtn:Hide()
            readyBtn:SetEnabled(false)
            pullBtn:Hide()
            pullBtn:SetEnabled(false)
        end
    end
end

-- 容器框架的 OnEvent：脱战时触发重新检查权限
buttonsFrame:SetScript("OnEvent", function()
    CheckPermission()
end)

-- 当权限发生变化时（如队长变更），重新检查按钮可见性
Cell.RegisterCallback("PermissionChanged", "RaidButtons_PermissionChanged", CheckPermission)

-- UpdateTools：根据配置更新工具按钮的所有设置
-- which 参数可选：nil 全部更新、"buttons" 仅权限可见性、"readyAndPull" 倒数协议与样式、"fadeOut" 淡出状态
local function UpdateTools(which)
    -- 检查权限与 mover 显示状态
    if not which or which == "buttons" then
        CheckPermission()
        ShowMover(Cell.vars.showMover and CellDB["tools"]["readyAndPull"][1])
    end

    if not which or which == "readyAndPull" then
        -- 确保图标纹理已创建（延迟创建，避免初始化顺序问题）
        if not pullBtn.tex then CreateTexture(pullBtn, "Interface\\AddOns\\Cell\\Media\\Icons\\pull") end
        if not readyBtn.tex then CreateTexture(readyBtn, "Interface\\AddOns\\Cell\\Media\\Icons\\ready") end

        -- 重置 pull 按钮事件和属性
        pullBtn:UnregisterAllEvents()
        pullBtn:SetScript("OnMouseUp", pullBtn.onMouseUp)
        pullBtn:SetAttribute("type1", "macro")
        pullBtn:SetAttribute("type2", "macro")

        -- 根据所选倒数协议配置 pull 按钮的行为
        if CellDB["tools"]["readyAndPull"][3][1] == "mrt" then
            -- MRT/Exorsus Raid Tools：通过插件通信启动倒数
            pullBtn:RegisterEvent("CHAT_MSG_ADDON")
            pullBtn:SetAttribute("macrotext1", "/ert pull "..CellDB["tools"]["readyAndPull"][3][2])
            pullBtn:SetAttribute("macrotext2", "/ert pull 0")
        elseif CellDB["tools"]["readyAndPull"][3][1] == "dbm" then
            -- Deadly Boss Mods：通过 /dbm pull 命令启动倒数
            pullBtn:RegisterEvent("CHAT_MSG_ADDON")
            pullBtn:SetAttribute("macrotext1", "/dbm pull "..CellDB["tools"]["readyAndPull"][3][2])
            pullBtn:SetAttribute("macrotext2", "/dbm pull 0")
        elseif CellDB["tools"]["readyAndPull"][3][1] == "bw" then
            -- BigWigs：通过 /pull 命令启动倒数
            pullBtn:RegisterEvent("CHAT_MSG_ADDON")
            pullBtn:SetAttribute("macrotext1", "/pull "..CellDB["tools"]["readyAndPull"][3][2])
            pullBtn:SetAttribute("macrotext2", "/pull 0")
        else -- default：正式服内置倒数或经典服手动倒数
            if Cell.isRetail then
                -- 正式服使用 /cd 内置倒计时，通过 START_TIMER 事件监听
                -- C_PartyInfo.DoCountdown(CellDB["tools"]["readyAndPull"][3][2])
                pullBtn:RegisterEvent("START_TIMER")
                pullBtn:SetAttribute("macrotext1", "/cd "..CellDB["tools"]["readyAndPull"][3][2])
                pullBtn:SetAttribute("macrotext2", "/cd 0")
            else
                -- 经典服无内置倒数，通过手动发送频道消息模拟倒数
                pullBtn:SetAttribute("type1", nil)
                pullBtn:SetAttribute("type2", nil)
                pullBtn:SetScript("OnMouseUp", function(self, button)
                    if button == "LeftButton" then
                        -- 左键：发送倒数开始消息并启动本地计时器
                        SendChatMessage(L["Pull in %d sec"]:format(CellDB["tools"]["readyAndPull"][3][2]), IsInRaid() and "RAID_WARNING" or "PARTY")
                        Start(CellDB["tools"]["readyAndPull"][3][2], true)
                    else
                        -- 右键：如果正在倒数则取消
                        if isPullTickerRunning then
                            SendChatMessage(L["Pull timer cancelled"], IsInRaid() and "RAID_WARNING" or "PARTY")
                            Stop()
                        end
                    end
                    pullBtn.onMouseUp()
                end)
            end
        end

        -- 应用样式更新（文字/图标、水平/垂直）
        UpdateStyle()
    end

    -- 淡出设置更新
    if not which or which == "fadeOut" then
        if CellDB["tools"]["fadeOut"] and not buttonsFrame.moverText:IsShown() then
            buttonsFrame:SetAlpha(0)
        else
            buttonsFrame:SetAlpha(1)
        end
    end

    -- 全部更新时加载保存的位置
    if not which then -- position
        P.LoadPosition(buttonsFrame, CellDB["tools"]["readyAndPull"][4])
    end
end
-- 注册 UpdateTools 回调，响应用户配置变更
Cell.RegisterCallback("UpdateTools", "RaidButtons_UpdateTools", UpdateTools)

-- UpdatePixelPerfect：像素完美缩放更新，确保按钮在不同 UI 缩放下清晰
local function UpdatePixelPerfect()
    -- P.Resize(buttonsFrame)
    readyBtn:UpdatePixelPerfect()
    pullBtn:UpdatePixelPerfect()
end
Cell.RegisterCallback("UpdatePixelPerfect", "RaidButtons_UpdatePixelPerfect", UpdatePixelPerfect)
