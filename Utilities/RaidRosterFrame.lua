local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs
local A = Cell.animations
local LibTranslit = LibStub("LibTranslit-1.0")
local LCG = LibStub("LibCustomGlow-1.0")

local GetRaidRosterInfo = GetRaidRosterInfo
local SwapRaidSubgroup = SwapRaidSubgroup
local SetRaidSubgroup = SetRaidSubgroup

local LoadRoster, UpdateRoster
local UpdateMode
local PremadeSwap, PremadeSet, PremadeApply, ProcessNext

-- groups: 队伍编号 → 小队Frame的映射表，共8个小队，每个小队包含5个成员槽位
local groups = {} -- contains girds
-- changes: 存储预排模式下被修改了子组/位置的成员信息
-- key=成员全名(含服务器), value={目标子组编号, 目标子组内索引, 与之交换的目标玩家名}
local changes = {} -- store subgroup changed member indices
-- queue: 预排模式应用时的处理队列，按顺序存放需要移动的成员全名
local queue
-- local premadeGroups = {} -- contains member nums of each sub group

-- isInstantMode: true=即时模式(拖拽即生效), false=预排模式(先规划再一键应用)
local isInstantMode = true
-- isProcessing: 是否正在执行预排应用流程
local isProcessing = false
-- 预排模式的UI控件引用
local modeBtn, assistantCB, processingFrame, progressBar, combatTips

-- 重置预排状态：清空队列和变更记录，恢复即时模式
-- @param reload: 是否同时重新加载队伍列表
local function Reset(reload)
    -- print("RESET", reload)
    queue = nil
    isInstantMode = true
    isProcessing = false
    wipe(changes)
    UpdateMode()

    if reload then
        LoadRoster()
    end
end

-------------------------------------------------
-- 创建队伍面板的主框架
-- 尺寸405x230, 可变位置, 层级DIALOG, 层级编号5
-------------------------------------------------
local raidRosterFrame = Cell.CreateFrame("CellRaidRosterFrame", Cell.frames.mainFrame, 405, 230)
Cell.frames.raidRosterFrame = raidRosterFrame
raidRosterFrame:SetFrameStrata("DIALOG")
raidRosterFrame:SetFrameLevel(5)

-- 创建队伍面板上的交互控件：模式按钮、全设为助理勾选框、滚动提示文本
local function CreateWidgets()
    -- 模式切换按钮 (左键切换/应用，右键放弃)
    modeBtn = Cell.CreateButton(raidRosterFrame, L["Instant Mode"], "accent", {127, 17})
    modeBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\instant", {13, 13}, {"LEFT", 4, 0})
    modeBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    modeBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then -- 左键：切换模式 / 应用变更
            if isInstantMode then
                isInstantMode = false
                UpdateMode()
            else
                if not isProcessing then
                    isProcessing = true
                    PremadeApply()
                end
            end

        else -- 右键：放弃所有变更
            if isProcessing then
                processingFrame:Hide()
            else
                Reset(true)
            end
        end
    end)

    -- 模式按钮的工具提示
    Cell.SetTooltips(modeBtn, "ANCHOR_TOPRIGHT", 0, 2,
        "|cffff2727EXPERIMENTAL|r",
        L["No support for rearrangement of members within a same subgroup"],
        L["No guarantee of the order of members in each subgroup"],
        "|cffffb5c5"..L["Left-Click"]..":|r "..L["change mode / apply changes"],
        "|cffffb5c5"..L["Right-Click"]..":|r "..L["discard changes"]
    )

    -- 勾选框：将所有成员设为团队助理
    assistantCB = Cell.CreateCheckButton(raidRosterFrame, "|TInterface\\GroupFrame\\UI-Group-AssistantIcon:16:16|t", function(checked)
        SetEveryoneIsAssistant(checked)
    end)
    assistantCB:SetPoint("BOTTOMRIGHT", -25, 5)

    -- 滚动提示文本（显示队伍面板使用说明）
    local tips = Cell.CreateScrollTextFrame(raidRosterFrame, "|cffb7b7b7"..L["raidRosterTips"], 0.02, nil, 2)
    tips:SetPoint("BOTTOMLEFT", raidRosterFrame, 5, 2)
    tips:SetPoint("RIGHT", assistantCB, "LEFT", -5, 0)
end

-- 根据主面板锚点方向调整模式按钮位置，使其始终附在面板外侧
local function UpdateModeBtnPosition()
    local anchor = Cell.vars.currentLayoutTable.main.anchor
    modeBtn:ClearAllPoints()
    if anchor == "TOPLEFT" then
        modeBtn:SetPoint("BOTTOMRIGHT", raidRosterFrame, "TOPRIGHT", 0, 4)
    elseif anchor == "TOPRIGHT" then
        modeBtn:SetPoint("BOTTOMLEFT", raidRosterFrame, "TOPLEFT", 0, 4)
    elseif anchor == "BOTTOMLEFT" then
        modeBtn:SetPoint("TOPRIGHT", raidRosterFrame, "BOTTOMRIGHT", 0, -4)
    elseif anchor == "BOTTOMRIGHT" then
        modeBtn:SetPoint("TOPLEFT", raidRosterFrame, "BOTTOMLEFT", 0, -4)
    end
end

-- 更新模式按钮的文本、图标和光效，同时控制 GROUP_ROSTER_UPDATE 事件的注册/注销
-- 即时模式：注册事件以实时同步队伍变化，按钮无光效
-- 预排模式：注销事件以冻结面板状态，按钮带流光特效提示用户处于预排中
UpdateMode = function()
    -- update button
    if isInstantMode then
        raidRosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        modeBtn:SetText(L["Instant Mode"])
        modeBtn.tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\instant")
        LCG.PixelGlow_Stop(modeBtn)
    else
        raidRosterFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
        modeBtn:SetText(L["Premade Mode"])
        modeBtn.tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\premade")
        LCG.PixelGlow_Start(modeBtn, Cell.GetAccentColorTable(1), 12, 0.25, 10, 1)
    end
end

-- 创建预排模式的处理覆盖层：半透明遮罩 + 进度条 + 战斗等待提示
-- OnShow: 注册 GROUP_ROSTER_UPDATE 事件并开始逐条处理变更队列
-- OnHide: 注销所有事件并重置状态
-- OnEvent: 响应队伍更新事件，若注册了 PLAYER_REGEN_ENABLED 则战斗结束后继续处理
local function CreateProcessingFrame()
    -- 处理中的遮罩层（覆盖整个面板，阻止用户操作）
    processingFrame = CreateFrame("Frame", nil, raidRosterFrame, "BackdropTemplate")
    processingFrame:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
    processingFrame:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))
    Cell.StylizeFrame(processingFrame, {0.15, 0.15, 0.15, 0.7}, {0, 0, 0, 0})
    processingFrame:SetFrameLevel(raidRosterFrame:GetFrameLevel()+30)
    processingFrame:EnableMouse(true)
    processingFrame:Hide()

    -- 显示时自动注册队伍更新事件并开始处理队列
    processingFrame:SetScript("OnShow", function()
        processingFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        ProcessNext()
    end)

    -- 隐藏时清理事件监听并重置所有状态
    processingFrame:SetScript("OnHide", function()
        processingFrame:Hide()
        processingFrame:UnregisterAllEvents()
        Reset(true)
    end)

    -- 响应事件：PLAYER_REGEN_ENABLED(脱离战斗)时隐藏战斗提示并继续处理；GROUP_ROSTER_UPDATE时继续处理
    processingFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            processingFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            combatTips:Hide()
        end
        ProcessNext()
    end)

    -- 处理完毕后的淡出动画
    A.CreateFadeOut(processingFrame, 1, 0, 0.5, 0.5)

    -- 进度条：显示预排变更的执行进度 (当前处理数/总变更数)
    progressBar = Cell.CreateStatusBar(nil, processingFrame, 1, 1, 100, true, nil, true, "Interface\\AddOns\\Cell\\Media\\statusbar", Cell.GetAccentColorTable())
    progressBar:SetPoint("TOPLEFT", 10, -103)
    progressBar:SetPoint("BOTTOMRIGHT", -10, 102)

    -- 战斗等待提示文本（战斗中无法调整队伍时显示）
    combatTips = processingFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    combatTips:SetPoint("TOP", progressBar, "BOTTOM", 0, -5)
    combatTips:SetTextColor(1, 0.2, 0.2)
    combatTips:SetText(L["Waiting for combat to end..."])
    combatTips:Hide()
end

-------------------------------------------------
-- 预排模式核心逻辑：拖拽交换、设置、逐条应用
-------------------------------------------------
-- 预排模式下交换两个成员格子的位置（仅UI层面+changes记录，不真正调用API）
-- 同一子组内不交换（无意义），跨子组时交换锚点、点位、子组编号和索引
-- 交换后在changes表中记录实际子组发生变化的成员
PremadeSwap = function(grid1, grid2)
    -- 若两个格子的实际子组相同（原始子组和预排子组均一致），无需交换
    if grid1.subgroup == grid2.subgroup and grid1._subgroup == grid2._subgroup then
        -- NOTE: in same group, don't swap
        return
    end

    -- 保存grid1的位置信息作为临时变量
    local tempPoint1 = grid1._point1 or grid1.point1
    local tempPoint2 = grid1._point2 or grid1.point2

    -- 交换两个格子的锚点位置
    grid1._point1 = grid2._point1 or grid2.point1
    grid1._point2 = grid2._point2 or grid2.point2
    grid2._point1 = tempPoint1
    grid2._point2 = tempPoint2

    -- 确定各自所属的小队Frame（优先使用预排子组_anchor，其次使用原始子组的group）
    local anchor1 = grid1._subgroup and groups[grid1._subgroup] or groups[grid1.subgroup]
    local anchor2 = grid2._subgroup and groups[grid2._subgroup] or groups[grid2.subgroup]

    grid1._anchor = anchor2
    grid2._anchor = anchor1

    -- 重新设置grid1到grid2的锚点位置
    grid1:ClearAllPoints()
    grid1:SetPoint(grid1._point1[1], anchor2, grid1._point1[2], grid1._point1[3])
    grid1:SetPoint(grid1._point2[1], anchor2, grid1._point2[2], grid1._point2[3])

    -- 重新设置grid2到grid1的锚点位置
    grid2:ClearAllPoints()
    grid2:SetPoint(grid2._point1[1], anchor1, grid2._point1[2], grid2._point1[3])
    grid2:SetPoint(grid2._point2[1], anchor1, grid2._point2[2], grid2._point2[3])

    -- 交换预排子组编号
    local subgroup = grid1._subgroup or grid1.subgroup
    grid1._subgroup = grid2._subgroup or grid2.subgroup
    grid2._subgroup = subgroup

    -- 交换预排子组内索引
    local index = grid1._index or grid1.index
    grid1._index = grid2._index or grid2.index
    grid2._index = index

    -- 记录grid1的变更：如果预排子组与原始子组不同，写入changes表
    if grid1.hasUnit then
        if grid1._subgroup ~= grid1.subgroup then
            changes[grid1.fullName] = {grid1._subgroup, grid1._index, grid2.fullName}
        else
            changes[grid1.fullName] = nil
        end
    end

    -- 记录grid2的变更：同样比较预排子组与原始子组
    if grid2.hasUnit then
        if grid2._subgroup ~= grid2.subgroup then
            changes[grid2.fullName] = {grid2._subgroup, grid2._index, grid1.fullName}
        else
            changes[grid2.fullName] = nil
        end
    end
end

-- 预排模式下将成员格子移动到空位（本质是调用PremadeSwap交换两个格子的全部信息）
PremadeSet = function(grid, emptyGrid)
    -- premadeGroups[grid._subgroup or grid.subgroup] = premadeGroups[grid._subgroup or grid.subgroup] - 1
    -- premadeGroups[emptyGrid._subgroup or emptyGrid.subgroup] = premadeGroups[emptyGrid._subgroup or emptyGrid.subgroup] + 1

    PremadeSwap(grid, emptyGrid)
end

-- 逐条处理预排变更队列的核心函数
-- 从队列首取出一个成员，根据changes表中记录的目标子组和位置，执行SwapRaidSubgroup或SetRaidSubgroup
-- 若在战斗中则暂停处理，注册PLAYER_REGEN_ENABLED事件等待脱战后继续
-- 处理完当前条目后若无需API调用(noAction=true)则立即递归处理下一条，否则等待事件触发
ProcessNext = function()
    -- print("ProcessNext", queue and queue[1] or nil)
    if queue and queue[1] then
        local noAction = true

        -- 取队列第一个成员的信息
        local next = queue[1]
        local fromIndex, fromSubgroup = F.GetRaidInfoByName(next)

        -- 从changes表读取该成员的目标子组、目标子组内索引和交换对象
        local targetSubgroup = changes[next][1]
        local targetIndex = changes[next][2] -- index in subgroup, not raidIndex
        local targetPlayer = changes[next][3]

        if fromIndex then -- 该成员仍在团队中
            local targetPlayerTarget = changes[targetPlayer] and changes[targetPlayer][3] or nil
            local toIndex, toName = F.GetRaidInfoBySubgroupIndex(targetSubgroup, targetIndex)

            -- print(next, "raidIndex:", fromIndex, "subgroup:", fromSubgroup.."->"..targetSubgroup, "targetIndex:", targetIndex, "targetPlayer:", targetPlayer, targetPlayerTarget)

            -- 情况1：目标位置有人且对方也正好要与"next"交换 → 执行Swap
            if toIndex and targetPlayerTarget == next then -- NOTE: unit to be swapped with exists, and requires a swap with "next"
                if fromIndex ~= toIndex then
                    if not InCombatLockdown() then
                        noAction = false
                        SwapRaidSubgroup(fromIndex, toIndex)
                    else
                        -- 战斗中无法调整队伍，注册脱离战斗事件并显示等待提示
                        processingFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                        combatTips:Show()
                        return
                    end
                end
            else  -- 情况2：目标位置为空或对方不需要与"next"交换 → 直接Set到目标子组
                if fromSubgroup ~= targetSubgroup and F.GetNumSubgroupMembers(targetSubgroup) < 5 then
                    if not InCombatLockdown() then
                        noAction = false
                        SetRaidSubgroup(fromIndex, targetSubgroup)
                    else
                        processingFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                        combatTips:Show()
                        return
                    end
                end
            end
        end

        -- 移除已处理的队首元素并更新进度条
        tremove(queue, 1)
        progressBar.value = progressBar.value + 1
        progressBar:SetSmoothedValue(progressBar.value)

        -- 如果当前条目无需调用API（目标位置已是正确子组），立即递归处理下一条
        if noAction then
            ProcessNext()
        end
    else
        -- 队列为空，全部处理完毕，淡出遮罩
        processingFrame:FadeOut()
    end
end

-- 开始应用预排变更：从changes表提取所有变更成员的名单作为处理队列
-- 若有待处理的变更，初始化进度条并显示处理遮罩层；否则直接重置
PremadeApply = function()
    queue = F.GetKeys(changes)
    local n = #queue
    if n ~= 0 then
        progressBar:SetMaxValue(n)
        progressBar:SetValue(0)
        progressBar.value = 0
        -- texplore(queue)
        processingFrame:Show()
    else
        Reset(true)
    end
end

-------------------------------------------------
-- 创建队伍成员格子及相关UI
-------------------------------------------------
-- 当前正在被拖拽移动的成员格子
local movingGrid

-- 创建一个队伍成员格子（Button类型，可点击、可拖拽）
-- 包含：职业角色图标+背景、成员名字文本
-- 支持三种交互：右键点击升降助理、左键拖拽移动、鼠标悬停高亮
local function CreateRaidRosterGrid(parent, index)
    local grid = CreateFrame("Button", parent:GetName().."Unit"..index, parent, "BackdropTemplate")
    P.Size(grid, 100, 17)
    Cell.StylizeFrame(grid, {0.1, 0.1, 0.1, 0.5})
    grid.color = {0.5, 0.5, 0.5}

    grid:SetFrameLevel(7)

    -- 角色图标背景（根据权限显示不同颜色：队长金色、助理灰色、普通黑色）
    local roleIconBg = grid:CreateTexture(nil, "BORDER")
    roleIconBg:SetPoint("TOPLEFT", 2, -2)
    roleIconBg:SetSize(13, 13)
    roleIconBg:SetColorTexture(0, 0, 0, 1)

    -- 角色职责图标（坦克/治疗/伤害/无）
    local roleIcon = grid:CreateTexture(nil, "ARTWORK")
    roleIcon:SetPoint("TOPLEFT", roleIconBg, P.Scale(1), P.Scale(-1))
    roleIcon:SetPoint("BOTTOMRIGHT", roleIconBg, P.Scale(-1), P.Scale(1))
    roleIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    -- 成员名字文本（左对齐，不换行）
    local nameText = grid:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    nameText:SetPoint("LEFT", roleIcon, "RIGHT", 2, 0)
    nameText:SetPoint("RIGHT", -2, 0)
    nameText:SetWordWrap(false)
    nameText:SetJustifyH("LEFT")

    -- 右键点击事件：Alt+右键踢出队伍，普通右键升降团队助理
    grid:RegisterForClicks("RightButtonDown")
    grid:SetScript("OnClick", function()
        if IsAltKeyDown() then
            UninviteUnit(grid.name)
        else
            if not UnitIsGroupLeader("player") then return end

            if UnitIsGroupLeader(grid.unit) then return end

            if UnitIsGroupAssistant(grid.unit) then
                DemoteAssistant(grid.unit)
            else
                PromoteToAssistant(grid.unit)
            end
        end
    end)

    -- 左键拖拽：提升层级、记录移动状态、设置高亮外观
    grid:SetMovable(true)
    grid:RegisterForDrag("LeftButton")
    grid:SetScript("OnDragStart", function()
        grid:SetFrameLevel(9)
        grid:StartMoving()
        grid:SetUserPlaced(false)
        grid:SetBackdropBorderColor(unpack(grid.color))
        grid:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        grid.isMoving = true
        movingGrid = grid
    end)
    -- 拖拽结束：恢复层级到7，清除手动位置，若有预排锚点则用预排位置否则用原始位置，恢复外观
    grid:SetScript("OnDragStop", function()
        grid:SetFrameLevel(7)
        grid:StopMovingOrSizing()
        grid:ClearAllPoints()
        if grid._anchor then
            grid:SetPoint(grid._point1[1], grid._anchor, grid._point1[2], grid._point1[3])
            grid:SetPoint(grid._point2[1], grid._anchor, grid._point2[2], grid._point2[3])
        else
            grid:SetPoint(unpack(grid.point1))
            grid:SetPoint(unpack(grid.point2))
        end
        grid:SetBackdropBorderColor(0, 0, 0, 1)
        grid:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        grid.isMoving = nil
    end)

    -- 显示时注册全局鼠标释放事件，隐藏时注销（仅在显示期间检测拖拽释放的目标）
    grid:SetScript("OnShow", function()
        grid:RegisterEvent("GLOBAL_MOUSE_UP")
    end)
    grid:SetScript("OnHide", function()
        grid:UnregisterEvent("GLOBAL_MOUSE_UP")
    end)
    -- GLOBAL_MOUSE_UP事件：检测鼠标释放时是否悬停在另一个格子（或空位）上
    -- 即时模式直接调用SwapRaidSubgroup/SetRaidSubgroup；预排模式调用PremadeSwap/PremadeSet
    grid:SetScript("OnEvent", function(self, event)
        if movingGrid and movingGrid ~= self and self:IsMouseOver() then
            if isInstantMode then
                if not InCombatLockdown() then
                    if self.hasUnit then
                        -- print("SWAP "..self:GetName().." WITH "..movingGrid:GetName())
                        SwapRaidSubgroup(movingGrid.raidIndex, self.raidIndex)
                    else
                        SetRaidSubgroup(movingGrid.raidIndex, self.subgroup)
                    end
                end
            else
                if self.hasUnit then
                    PremadeSwap(movingGrid, self)
                else
                    PremadeSet(movingGrid, self)
                end
            end
            movingGrid = nil
        end
    end)

    -- OnUpdate：每帧检测鼠标悬停，悬停时显示职业颜色半透明背景，否则恢复默认暗色背景
    grid:SetScript("OnUpdate", function()
        if not grid.isMoving then
            if grid:IsMouseOver() then
                grid:SetBackdropColor(grid.color[1], grid.color[2], grid.color[3], 0.2)
            else
                grid:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            end
        end
    end)

    -- 更新格子的显示内容：名字(职业颜色)、职责图标、权限背景色
    function grid:Update()
        nameText:SetText(grid.name)
        nameText:SetTextColor(unpack(grid.color))

        roleIcon:Show()
        roleIconBg:Show()
        -- 无职责时使用特殊纹理
        if role == "NONE" then
            roleIcon:SetTexture(134400)
        else
            roleIcon:SetTexture(F.GetDefaultRoleIcon(grid.role))
        end

        -- 根据权限设置角色图标背景色：队长金色、助理灰色、普通黑色
        if grid.isLeader then
            roleIconBg:SetColorTexture(1, 0.84, 0, 1)
        elseif grid.isAssistant then
            roleIconBg:SetColorTexture(0.7, 0.7, 0.7, 1)
        else
            roleIconBg:SetColorTexture(0, 0, 0, 1)
        end
    end

    -- 重置格子到空状态：清除所有成员数据、预排临时字段，恢复默认外观和位置
    function grid:Reset()
        F.RemoveElementsByKeys(grid,
            "hasUnit", "raidIndex", "unit", "fullName", "name", "role", "isLeader", "isAssistant",
            "_subgroup", "_index", "_point1", "_point2", "_anchor" -- premade temps
        )
        grid.color[1], grid.color[2], grid.color[3] = 0.5, 0.5, 0.5

        nameText:SetText("")
        nameText:SetTextColor(1, 1, 1)
        roleIconBg:SetColorTexture(0, 0, 0, 1)
        roleIconBg:Hide()
        roleIcon:Hide()

        grid:ClearAllPoints()
        grid:SetPoint(unpack(grid.point1))
        grid:SetPoint(unpack(grid.point2))

        -- 空位不可点击交互
        grid:EnableMouse(false)
    end

    -- 将一个raidIndex对应的团队成员数据填充到格子中
    -- 包含跨服名称处理(去掉服务器后缀)、音译转换、职业颜色、权限检测
    -- 若GetRaidRosterInfo返回nil则延迟0.5秒重试（处理跨服数据未就绪）
    function grid:Set(raidIndex)
        local name, _, subgroup, _, _, classFileName, _, _, _, _, _, combatRole = GetRaidRosterInfo(raidIndex)

        if not name then
            -- 跨服成员数据可能未就绪，0.5秒后重试
            C_Timer.After(0.5, function()
                grid:Set(raidIndex)
            end)
            return
        end



        -- 保存原始全名（含服务器名，用于跨服成员识别）
        grid.fullName = name -- contains server name for cross-realm players

        -- 去掉跨服后缀（-服务器名），只保留角色名
        if string.find(name, "-") then
            name = strsplit("-", name)
        end

        -- 如果开启了音译选项，将名字音译
        if CellDB["general"]["translit"] then
            name = LibTranslit:Transliterate(name)
        end

        -- 设置格子的成员数据
        grid.hasUnit = true
        grid.raidIndex = raidIndex
        grid.unit = "raid"..raidIndex
        grid.name = name
        grid.role = combatRole
        grid.color[1], grid.color[2], grid.color[3] = F.GetClassColor(classFileName)
        grid.isLeader = UnitIsGroupLeader(grid.unit)
        grid.isAssistant = UnitIsGroupAssistant(grid.unit)

        -- 更新显示并启用鼠标交互
        grid:Update()
        grid:EnableMouse(true)
    end

    return grid
end

-- 创建一个小队的容器Frame，包含5个成员格子（从上到下排列）
-- @param parent: 父容器Frame
-- @param groupIndex: 小队编号 1-8
local function CreateRaidRosterGroup(parent, groupIndex)
    local group = CreateFrame("Frame", parent:GetName().."Subgroup"..groupIndex, parent, "BackdropTemplate")
    P.Size(group, 95, 81)
    Cell.StylizeFrame(group, {0.1, 0.1, 0.1, 0.5})

    -- 小队标题（显示"小队 N"）
    local headerText = group:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    headerText:SetPoint("BOTTOM", group, "TOP", 0, 1)
    headerText:SetText("|cFFEEC900"..GROUP.." "..groupIndex)

    -- 创建5个成员格子，纵向排列，每个高度17px（含1px间距即16px步进）
    for i = 1, 5 do
        group[i] = CreateRaidRosterGrid(group, i)
        group[i].point1 = {"TOPLEFT", 0, -(i-1)*16}
        group[i]:SetPoint(unpack(group[i].point1))
        group[i].point2 = {"TOPRIGHT", 0, -(i-1)*16}
        group[i]:SetPoint(unpack(group[i].point2))
        group[i].subgroup = groupIndex
        group[i].index = i
    end

    group.numMembers = 0

    -- 重置小队：清空成员计数，重置所有格子
    function group:Reset()
        group.numMembers = 0
        for i = 1, 5 do
            group[i]:Reset()
        end
    end

    -- 向小队中插入一个成员（按顺序填充到下一个可用格子）
    function group:Insert(raidIndex)
        group.numMembers = group.numMembers + 1
        group[group.numMembers]:Set(raidIndex)
    end

    return group
end

-- 创建队伍列表容器：8个小队分两行排列（每行4个小队）
-- 第1行：小队1-4，纵坐标偏移 -20
-- 第2行：小队5-8，纵坐标偏移 -20-(1*(小队高度+20))
local function CreateRosterContainer()
    local rosterContainer = CreateFrame("Frame", "CellRaidRosterFrameContainer", raidRosterFrame)
    rosterContainer:SetPoint("TOPLEFT", 5, -5)
    rosterContainer:SetPoint("BOTTOMRIGHT", raidRosterFrame, "TOPRIGHT", -5, -207)

    for i = 1, 8 do
        groups[i] = CreateRaidRosterGroup(rosterContainer, i)

        -- 每行第一个小队靠左，其余向右依次排列，间距5px
        if i % 4 == 1 then
            groups[i]:SetPoint("TOPLEFT", 0, -20-(math.modf(i/4)*(groups[i]:GetHeight()+20)))
        else
            groups[i]:SetPoint("TOPLEFT", groups[i-1], "TOPRIGHT", 5, 0)
        end
    end
end

-------------------------------------------------
-- 队伍数据加载与更新函数
-------------------------------------------------
-- 加载团队列表：先强制结束任何进行中的拖拽，然后重置所有小队并重新填充成员
LoadRoster = function()
    -- 如果有正在拖拽的格子，先强制触发OnDragStop结束拖拽
    if movingGrid then
        movingGrid:GetScript("OnDragStop")()
    end

    -- 重置所有8个小队
    for i = 1, 8 do
        groups[i]:Reset()
        -- premadeGroups[i] = 0
    end

    -- 遍历所有团队成员，按子组归类插入对应小队
    for i = 1, GetNumGroupMembers() do
        local subgroup = select(3, GetRaidRosterInfo(i))
        groups[subgroup]:Insert(i)
        -- premadeGroups[subgroup] = premadeGroups[subgroup] + 1
    end
end

-- 增量更新队伍列表（当前为空实现，预留扩展）
UpdateRoster = function()

end

-------------------------------------------------
-- 主框架的事件脚本
-------------------------------------------------
-- 检查玩家权限：队长或助理可操作，否则显示无权限遮罩
local function CheckPermission()
    if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
        if raidRosterFrame.mask then raidRosterFrame.mask:Hide() end
    else
        Cell.CreateMask(raidRosterFrame, L["You don't have permission to do this"], {1, -1, -1, 1})
    end
end

-- GROUP_ROSTER_UPDATE 事件（仅在即时模式下注册）：队伍变化时重新加载列表、检查权限、同步助理勾选状态
raidRosterFrame:SetScript("OnEvent", function()
    LoadRoster()
    CheckPermission()
    assistantCB:SetChecked(IsEveryoneAssistant())
end)

-- 面板显示时：注册队伍更新事件、加载列表、检查权限、同步助理状态
raidRosterFrame:SetScript("OnShow", function()
    raidRosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    LoadRoster()
    CheckPermission()
    assistantCB:SetChecked(IsEveryoneAssistant())
end)

-- 面板隐藏时：注销队伍更新事件并重置预排状态
raidRosterFrame:SetScript("OnHide", function()
    raidRosterFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    Reset()
end)

-------------------------------------------------
-- 回调注册：响应外部事件
-------------------------------------------------
-- 队伍类型变化时（如从团队切为小队），隐藏队伍面板
local function GroupTypeChanged(groupType)
    raidRosterFrame:Hide()
end
Cell.RegisterCallback("GroupTypeChanged", "RaidRosterFrame_GroupTypeChanged", GroupTypeChanged)

-- 布局更新时：若Cell整体隐藏则同步隐藏面板；否则根据主面板锚点重新定位并调整模式按钮位置
local function UpdateLayout(layout, which)
    if Cell.vars.isHidden then
        raidRosterFrame:Hide()
        return
    end

    layout = Cell.vars.currentLayoutTable
    if not which or which == "main-arrangement" then
        raidRosterFrame:ClearAllPoints()
        raidRosterFrame:SetPoint(layout["main"]["anchor"], Cell.frames.mainFrame)

        if modeBtn then UpdateModeBtnPosition() end
    end
end
Cell.RegisterCallback("UpdateLayout", "RaidRosterFrame_UpdateLayout", UpdateLayout)

-------------------------------------------------
-- 对外暴露的显示/隐藏切换入口
-- 首次调用时完成所有子控件的懒初始化
-------------------------------------------------
local init
function F.ShowRaidRosterFrame()
    -- 懒初始化：首次调用时创建所有子控件
    if not init then
        init = true
        raidRosterFrame:UpdatePixelPerfect()
        CreateWidgets()
        CreateProcessingFrame()
        UpdateModeBtnPosition()
        CreateRosterContainer()
    end

    -- 切换显示/隐藏
    if raidRosterFrame:IsShown() then
        raidRosterFrame:Hide()
    else
        raidRosterFrame:Show()
        -- texplore(changes)
    end
end