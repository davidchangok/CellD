-- 从 Cell 表中解构出核心模块引用
-- _: 插件名 "CellD", Cell: 插件共享表, L: 本地化字符串表, F: 通用函数, B: 按钮函数, P: 像素级位置/尺寸函数
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local B = Cell.bFuncs
local P = Cell.pixelPerfectFuncs

-- Cell.unitButtons: 单元按键注册表数据结构
-- 按队伍类型(solo/party/raid/pet/npc/arena/spotlight/quickAssist)分类存储单元按键引用
-- 每种类型包含 units 表，用于快速遍历和更新该类型下的所有按键
Cell.unitButtons = {
    ["solo"] = {},
    ["party"] = {
        ["units"] = {}, -- NOTE: update in PartyFrame _initialAttribute-refreshUnitChange -- 在 PartyFrame 的 _initialAttribute-refreshUnitChange 中更新
    },
    ["raid"] = {
        ["units"] = {}, -- NOTE: update in UnitButton_OnAttributeChanged -- 在 UnitButton_OnAttributeChanged 中更新
    },
    ["pet"] = {
        ["units"] = {}, -- NOTE: update in _initialAttribute-refreshUnitChange -- 在 _initialAttribute-refreshUnitChange 中更新
    },
    ["npc"] = {
        ["units"] = {}, -- NOTE: update on creation -- 创建时更新
    },
    ["arena"] = {},
    ["spotlight"] = {},
    ["quickAssist"] = {
        ["units"] = {},
    },
}

-- hoverTop, hoverBottom, hoverLeft, hoverRight: 悬停检测区域边界偏移量(已弃用，改用固定1px扩展)
-- local hoverTop, hoverBottom, hoverLeft, hoverRight
-- tooltip 定位参数：锚点、相对锚点、x偏移、y偏移，根据菜单方向动态计算
local tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY
-------------------------------------------------
-- CellMainFrame -- 主框架容器，承载所有团队框体
-- 使用 SecureFrameTemplate 确保在战斗中仍可安全操作(如移动、显示/隐藏)
-------------------------------------------------
local cellMainFrame = CreateFrame("Frame", "CellMainFrame", CellParent, "SecureFrameTemplate")
Cell.frames.mainFrame = cellMainFrame

-- hoverFrame: 菜单悬停检测区域，用于淡入淡出逻辑
-- 包裹所有菜单按钮，当鼠标进入/离开此区域时触发菜单的显示/隐藏动画
local hoverFrame = CreateFrame("Frame", "CellMenuHoverDetector", cellMainFrame, "BackdropTemplate")
-- Cell.StylizeFrame(hoverFrame, {1,0,0,0.3}, {0,0,0,0})

-- anchorFrame: 锚点框架，用户可通过拖拽移动整个 Cell 界面的位置
-- 初始位置为屏幕中央，可被用户自由拖拽并保存位置
local anchorFrame = CreateFrame("Frame", "CellAnchorFrame", cellMainFrame)
Cell.frames.anchorFrame = anchorFrame
PixelUtil.SetPoint(anchorFrame, "TOPLEFT", CellParent, "CENTER", 1, -1)
P.Size(anchorFrame, 20, 10)
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)

-- RegisterButtonEvents: 为菜单按钮注册拖拽移动和悬停检测事件
-- 参数 frame: 需要注册事件的按钮框架
-- Midnight 防护: OnDragStart/OnDragStop 中检查 InCombatLockdown()，战斗中禁止拖拽移动位置
-- 悬停事件委托给 hoverFrame 的统一处理逻辑，实现全局菜单淡入淡出
local function RegisterButtonEvents(frame)
    -- frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end -- Midnight 防护: 战斗中禁止开始拖拽
        anchorFrame:StartMoving()
        anchorFrame:SetUserPlaced(false)
    end)
    frame:SetScript("OnDragStop", function()
        if InCombatLockdown() then return end -- Midnight 防护: 战斗中禁止停止拖拽(保存位置)
        anchorFrame:StopMovingOrSizing()
        -- 拖拽结束后将新位置保存到当前布局配置中
        P.SavePosition(anchorFrame, Cell.vars.currentLayoutTable["main"]["position"])
    end)

    frame:HookScript("OnEnter", function()
        hoverFrame:GetScript("OnEnter")(hoverFrame) -- 委托给 hoverFrame 的 OnEnter 处理
        -- Cell.frames.menuFrame:SetFrameStrata("HIGH")
        -- Cell.frames.menuFrame:SetToplevel(true)
    end)
    frame:HookScript("OnLeave", function()
        hoverFrame:GetScript("OnLeave")(hoverFrame) -- 委托给 hoverFrame 的 OnLeave 处理
        -- Cell.frames.menuFrame:SetFrameStrata(CellDB["appearance"]["strata"])
        -- Cell.frames.menuFrame:SetToplevel(false)
    end)
end

-------------------------------------------------
-- buttons -- 菜单栏按钮区域
-------------------------------------------------
-- menuFrame: 菜单框架，包裹所有菜单按钮，支持淡入淡出动画
-- 通过 SetAllPoints 与 anchorFrame 绑定，跟随拖拽移动
local menuFrame = CreateFrame("Frame", "CellMenuFrame", cellMainFrame)
Cell.frames.menuFrame = menuFrame
menuFrame:SetAllPoints(anchorFrame)
menuFrame:SetFrameLevel(27)

-- options: 红色选项按钮(齿轮图标)，左键打开设置面板，右键刷新所有单元按键
-- CreateButton 参数: 父框架, 文本, 颜色, 尺寸, 是否隐藏, 是否启用鼠标
local options = Cell.CreateButton(menuFrame, "", "red", {20, 10}, false, true)
P.Point(options, "TOPLEFT", menuFrame)
RegisterButtonEvents(options)
options:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- 支持左键和右键点击
options:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        F.ShowOptionsFrame() -- 打开 Cell 设置面板
    elseif button == "RightButton" then
        -- 右键刷新: 遍历所有单元按键并强制更新布局/指示器
        F.IterateAllUnitButtons(B.UpdateAll, true)
        F.Print(L["Unit buttons refreshed (%s)."]:format(F.UpperFirst(L["all"])))
    end
end)
-- 选项按钮悬停提示: 显示"选项"和"右键刷新单元按键"说明
options:HookScript("OnEnter", function()
    CellTooltip:SetOwner(options, "ANCHOR_NONE")
    if tooltipPoint then
        CellTooltip:SetPoint(tooltipPoint, options, tooltipRelativePoint, tooltipX, tooltipY)
    else
        CellTooltip:SetPoint("TOPLEFT", options, "BOTTOMLEFT", 0, -3)
    end
    CellTooltip:AddLine(L["Options"])
    CellTooltip:AddLine("|cffffb5c5"..L["Right-Click"]..": |cffffffff"..L["refresh unit buttons"])
    CellTooltip:Show()
end)
options:HookScript("OnLeave", function()
    CellTooltip:Hide()
end)

-- raid: 蓝色团队按钮，点击打开团队阵容面板(RaidRosterFrame)
-- 仅在团队模式下显示，小队/单人模式下隐藏
local raid = Cell.CreateButton(menuFrame, "", "blue", {20, 10}, false, true)
P.Point(raid, "LEFT", options, "RIGHT", 1, 0)
RegisterButtonEvents(raid)
raid:SetScript("OnClick", function()
    F.ShowRaidRosterFrame()
end)

-- 已废弃: 团队工具按钮(世界标记), 使用 SecureHandlerClickTemplate 用于战斗安全点击
-- local tools = Cell.CreateButton(menuFrame, "", "chartreuse", {20, 10}, false, true, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
-- tools:SetSize(20, 10)
-- tools:EnableMouse(true)
-- P.Point(tools, "LEFT", raid, "RIGHT", 1, 0)
-- RegisterButtonEvents(tools)
-- tools:SetAttribute("_onclick", [[
--     print(self:GetFrameRef("main"))
--     print(self:GetAttribute("main"))
-- ]])
-- SecureHandlerSetFrameRef(tools, "main", cellMainFrame)

-- REVIEW: raid tool button
--[===[
local frame = CreateFrame("Frame", nil, cellMainFrame, "BackdropTemplate")
Cell.StylizeFrame(frame)
frame:SetSize(100, 100)
frame:SetPoint("BOTTOMLEFT", cellMainFrame, "TOPLEFT", 0, 30)
frame:Hide()

local mark = Cell.CreateButton(frame, "", "accent-hover", {20, 20}, false, false, nil, nil, "SecureActionButtonTemplate")
mark:SetPoint("CENTER")
mark:SetSize(20, 20)
mark.texture = mark:CreateTexture(nil, "ARTWORK")
mark.texture:SetColorTexture(1, 0, 0, 0.4)
mark.texture:SetAllPoints(mark)
mark:SetAttribute("type", "worldmarker")
mark:SetAttribute("marker", 1)

-- local tools = Cell.CreateButton(menuFrame, "", "chartreuse", {20, 10}, false, true, nil, nil, "SecureHandlerAttributeTemplate,SecureHandlerClickTemplate")
local tools = CreateFrame("Frame", nil, menuFrame, "BackdropTemplate,SecureHandlerMouseUpDownTemplate")
Cell.StylizeFrame(tools)
tools:SetSize(20, 10)
tools:EnableMouse(true)
P.Point(tools, "LEFT", raid, "RIGHT", 1, 0)
tools:SetFrameStrata("MEDIUM")
RegisterButtonEvents(tools)
-- tools:SetScript("_onclick", function()
--     print(frame:IsShown())
-- end)
tools:SetFrameRef("frame", frame)

tools:SetAttribute("_onmousedown", [=[
    -- self, button
    local frame = self:GetFrameRef("frame")
    local raidMarksFrame = self:GetFrameRef("raidMarksFrame")
    if frame:IsShown() then
        frame:Hide()
        raidMarksFrame:Hide()
    else
        frame:Show()
        raidMarksFrame:Show()
    end
]=])
]===]

-------------------------------------------------
-- LoadingBar -- 加载进度条，位于选项按钮底部
-- 在单元按键批量创建/更新时显示，用绿色状态条指示加载进度
-------------------------------------------------
local loadingBar = CreateFrame("StatusBar", "CellLoadingBar", options)
loadingBar:Hide()
loadingBar:SetStatusBarTexture(Cell.vars.whiteTexture)
loadingBar:SetStatusBarColor(0.5, 1, 0) -- 亮绿色
P.Height(loadingBar, 1)
P.Point(loadingBar, "BOTTOMLEFT", options, 1, 1)
P.Point(loadingBar, "BOTTOMRIGHT", options, -1, 1)

-------------------------------------------------
-- MemoryUsage
-------------------------------------------------
--[==[@debug@
-- local memUsage = CreateFrame("Frame", nil, cellMainFrame)
-- memUsage:SetSize(10, 10)
-- memUsage:SetPoint("LEFT", raid, "RIGHT", 5, 0)
-- memUsage.text = memUsage:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
-- memUsage.text:SetPoint("LEFT")
-- memUsage:SetScript("OnUpdate", function(self, elapsed)
--     self.elapsed = (self.elapsed or 0) + elapsed
--     if self.elapsed > 1 then
--         UpdateAddOnMemoryUsage()
--         memUsage.text:SetFormattedText("%.2fMB", GetAddOnMemoryUsage("Cell")/1024)
--         self.elapsed = 0
--     end
-- end)
--@end-debug@]==]

-------------------------------------------------
-- fadeIn & fadeOut -- 菜单淡入淡出动画系统
-- 通过 AnimationGroup 实现菜单的平滑显示/隐藏过渡
-- 四种状态互斥: fadingIn(正在淡入), fadedIn(已淡入), fadingOut(正在淡出), fadedOut(已淡出)
-- 当鼠标悬停在菜单区域时淡入，离开后延迟淡出(如启用)
-- 关联战斗复活框架(OnMenuShow/OnMenuHide)，在菜单显示/隐藏时联动
-------------------------------------------------
-- 动画状态标志: 用于防止重复触发动画和在合适时机切换动画方向
local fadingIn, fadedIn, fadingOut, fadedOut
-- fadeIn: 淡入动画组，alpha 从 0 -> 1，持续0.5秒，OUT平滑曲线
menuFrame.fadeIn = menuFrame:CreateAnimationGroup()
menuFrame.fadeIn.alpha = menuFrame.fadeIn:CreateAnimation("alpha")
menuFrame.fadeIn.alpha:SetFromAlpha(0)
menuFrame.fadeIn.alpha:SetToAlpha(1)
menuFrame.fadeIn.alpha:SetDuration(0.5)
menuFrame.fadeIn.alpha:SetSmoothing("OUT")
menuFrame.fadeIn:SetScript("OnPlay", function()
    menuFrame.fadeOut:Finish() -- 停止正在进行的淡出动画
    fadingIn = true

    -- 如果战斗复活框架存在且为独立显示模式(top_bottom)，则通知其菜单显示
    if Cell.frames.battleResFrame and not CellDB["tools"]["battleResTimer"][2] and CellDB["general"]["menuPosition"] == "top_bottom" then
        Cell.frames.battleResFrame:OnMenuShow()
    end
end)
menuFrame.fadeIn:SetScript("OnFinished", function()
    fadingIn = false
    fadingOut = false
    fadedIn = true
    fadedOut = false
    menuFrame:SetAlpha(1)

    -- 淡入完成后，如果启用了 fadeOut 且鼠标已离开，则自动开始淡出
    if CellDB["general"]["fadeOut"] and not hoverFrame:IsMouseOver() then
        menuFrame.fadeOut:Play()
    end
end)

-- fadeOut: 淡出动画组，alpha 从 1 -> 0，持续0.5秒，OUT平滑曲线
menuFrame.fadeOut = menuFrame:CreateAnimationGroup()
menuFrame.fadeOut.alpha = menuFrame.fadeOut:CreateAnimation("alpha")
menuFrame.fadeOut.alpha:SetFromAlpha(1)
menuFrame.fadeOut.alpha:SetToAlpha(0)
menuFrame.fadeOut.alpha:SetDuration(0.5)
menuFrame.fadeOut.alpha:SetSmoothing("OUT")
menuFrame.fadeOut:SetScript("OnPlay", function()
    menuFrame.fadeIn:Finish() -- 停止正在进行的淡入动画
    fadingOut = true

    -- 淡出时通知战斗复活框架隐藏
    if Cell.frames.battleResFrame and not CellDB["tools"]["battleResTimer"][2] and CellDB["general"]["menuPosition"] == "top_bottom" then
        Cell.frames.battleResFrame:OnMenuHide()
    end
end)
menuFrame.fadeOut:SetScript("OnFinished", function()
    fadingIn = false
    fadingOut = false
    fadedIn = false
    fadedOut = true
    menuFrame:SetAlpha(0)

    -- 淡出完成后如果鼠标重新进入区域，立即重新淡入
    if hoverFrame:IsMouseOver() then
        menuFrame.fadeIn:Play()
    end
end)

-- hoverFrame OnEnter: 鼠标进入菜单区域 -> 触发淡入
-- 仅在 fadeOut 功能启用且当前未处于淡入/已淡入状态时触发
hoverFrame:SetScript("OnEnter", function()
    if not CellDB["general"]["fadeOut"] then return end
    if not (fadingIn or fadedIn) then
        menuFrame.fadeIn:Play()
    end
end)
-- hoverFrame OnLeave: 鼠标离开菜单区域 -> 触发淡出
-- 仅在 fadeOut 功能启用、确认鼠标已离开所有按钮、且当前未处于淡出/已淡出状态时触发
hoverFrame:SetScript("OnLeave", function()
    if not CellDB["general"]["fadeOut"] then return end
    if hoverFrame:IsMouseOver() then return end -- 二次确认鼠标确实离开了(防止快速移动时的误触发)
    if not (fadingOut or fadedOut) then
        menuFrame.fadeOut:Play()
    end
end)

-- UpdateHoverFrame: 根据菜单布局方向(top_bottom 或 left_right)和锚点位置
-- 动态计算 hoverFrame 的四边边界，确保悬停检测区域精确覆盖所有可见菜单按钮
-- 菜单方向:
--   top_bottom: 按钮水平排列，hoverFrame 在垂直方向包裹 options 和 raid
--   left_right: 按钮垂直排列，hoverFrame 在水平方向包裹 options 和 raid
local function UpdateHoverFrame()
    if not Cell.vars.currentLayoutTable then return end
    local anchor = Cell.vars.currentLayoutTable["main"]["anchor"]
    local top, bottom, left, right

    if CellDB["general"]["menuPosition"] == "top_bottom" then
        top, bottom = anchorFrame, anchorFrame
        if strfind(anchor, "LEFT$") then
            left = anchorFrame
            right = raid:IsShown() and raid or anchorFrame -- raid 可见时右边界扩展到 raid，否则仅 anchorFrame
        else -- RIGHT$ -- 右对齐时左边界向左扩展到 raid
            left = raid:IsShown() and raid or anchorFrame
            right = anchorFrame
        end
    else -- left_right -- 按钮垂直堆叠
        left, right = anchorFrame, anchorFrame
        if strfind(anchor, "^TOP") then
            top = anchorFrame
            bottom = raid:IsShown() and raid or anchorFrame -- raid 可见时下边界扩展到 raid
        else -- ^BOTTOM -- 底部对齐时上边界向上扩展到 raid
            top = raid:IsShown() and raid or anchorFrame
            bottom = anchorFrame
        end
    end

    hoverFrame:ClearAllPoints()
    -- 在按钮边界外扩展 1px 作为检测区域，避免边界情况下的悬停抖动
    hoverFrame:SetPoint("TOP", top, 0, 1)
    hoverFrame:SetPoint("BOTTOM", bottom, 0, -1)
    hoverFrame:SetPoint("LEFT", left, -1, 0)
    hoverFrame:SetPoint("RIGHT", right, 1, 0)
end

-------------------------------------------------
-- raid setup -- 团队阵容工具提示系统
-- 在悬停 raid 按钮时显示当前团队的职责/职业分布
-- raidSetup 数据结构: Cell.vars.raidSetup[role][class] = count
--   其中 role 为 TANK/HEALER/DAMAGER, class 为职业英文大写
--   每个 role 还有 .ALL 字段表示该职责总人数
-------------------------------------------------
-- 职责图标转义序列（用于 tooltip 中显示内联图标）
local tankIcon = F.GetDefaultRoleIconEscapeSequence("TANK")
local healerIcon = F.GetDefaultRoleIconEscapeSequence("HEALER")
local damagerIcon = F.GetDefaultRoleIconEscapeSequence("DAMAGER")

-- 已废弃: 旧版 GetGroupMemberCounts 兼容代码，用于不支持 GetGroupMemberCountsForDisplay 的版本
-- local GetGroupMemberCountsForDisplay = GetGroupMemberCountsForDisplay
-- if not GetGroupMemberCountsForDisplay then
--     GetGroupMemberCountsForDispla = function()
--         local data = GetGroupMemberCounts()
--         data.DAMAGER = data.DAMAGER + data.NOROLE --无职责的视为伤害输出
--         data.NOROLE = 0
--         return data
--     end
-- end

-- GetRaidSetupDetail: 为指定职责生成职业分布的可视化字符串
-- 返回由彩色方块组成的行，每个方块代表一个该职责下的队员，颜色对应该队员的职业色
-- white texture 通过 SetTexCoord 切片染色，实现职业色方块
local function GetRaidSetupDetail(role)
    local line = "  "

    for class in F.IterateClasses() do
        if Cell.vars.raidSetup[role][class] then
            local r, g, b = F.ConvertRGB_256(F.GetClassColor(class)) -- 获取职业颜色(0-255)

            for i = 1, Cell.vars.raidSetup[role][class] do
                if line ~= "  " then
                    -- 方块间的分隔线(1px宽白色竖线)
                    line = line .. "|TInterface\\AddOns\\Cell\\Media\\white:10:1:0:0:1:10:1:1:1:10:0:0:0|t"
                end

                -- 职业色方块(2px宽)，颜色通过纹理的 r/g/b 通道着色
                line = line .. "|TInterface\\AddOns\\Cell\\Media\\white:10:2:0:0:2:10:1:2:1:10:"..r..":"..g..":"..b.."|t"
            end
        end
    end

    return line
end

-- UpdateRaidSetupTooltip: 刷新团队按钮的工具提示，显示各职责人数和职业分布
-- CELL_TOOLTIP_REMOVE_RAID_SETUP_DETAILS 为 true 时仅显示总数，不显示职业方块详情
local function UpdateRaidSetupTooltip()
    CellTooltip:ClearLines()
    CellTooltip:AddLine(L["Raid"])

    if CELL_TOOLTIP_REMOVE_RAID_SETUP_DETAILS then
        CellTooltip:AddLine(tankIcon.." |cffffffff"..Cell.vars.raidSetup.TANK.ALL)
        CellTooltip:AddLine(healerIcon.." |cffffffff"..Cell.vars.raidSetup.HEALER.ALL)
        CellTooltip:AddLine(damagerIcon.." |cffffffff"..Cell.vars.raidSetup.DAMAGER.ALL)
    else
        CellTooltip:AddLine(tankIcon.." |cffffffff"..Cell.vars.raidSetup.TANK.ALL.."|r"..GetRaidSetupDetail("TANK"))
        CellTooltip:AddLine(healerIcon.." |cffffffff"..Cell.vars.raidSetup.HEALER.ALL.."|r"..GetRaidSetupDetail("HEALER"))
        CellTooltip:AddLine(damagerIcon.." |cffffffff"..Cell.vars.raidSetup.DAMAGER.ALL.."|r"..GetRaidSetupDetail("DAMAGER"))
    end

    CellTooltip:Show()
end

-- raid 按钮悬停事件: 显示团队阵容 tooltip
raid:HookScript("OnEnter", function()
    CellTooltip:SetOwner(raid, "ANCHOR_NONE")
    if tooltipPoint then
        CellTooltip:SetPoint(tooltipPoint, raid, tooltipRelativePoint, tooltipX, tooltipY)
    else
        CellTooltip:SetPoint("TOPLEFT", raid, "BOTTOMLEFT", 0, -3)
    end
    UpdateRaidSetupTooltip()
end)

raid:HookScript("OnLeave", function()
    CellTooltip:Hide()
end)

-- F.UpdateRaidSetup: 外部可调用接口，当团队阵容变化时刷新 tooltip(如果 tooltip 正在显示)
-- 通常在 Cell.vars.raidSetup 数据更新后由其他模块调用
function F.UpdateRaidSetup()
    if CellTooltip:GetOwner() == raid then
        UpdateRaidSetupTooltip()
    end
end

-------------------------------------------------
-- group type changed -- 队伍类型变化事件处理
-- 当玩家从单人->小队->团队切换时触发，控制 raid 按钮的显示/隐藏
-- 同时更新 hoverFrame 边界以适应按钮数量的变化
-------------------------------------------------
local function MainFrame_GroupTypeChanged(groupType)
    if groupType == "raid" then
        raid:Show() -- 团队模式下显示 raid 按钮
    else
        raid:Hide() -- 单人/小队模式下隐藏 raid 按钮
    end
    UpdateHoverFrame() -- 按钮可见性变化后重新计算悬停检测区域
end
-- 注册回调: 当 Cell 检测到队伍类型变化时，触发 MainFrame_GroupTypeChanged
Cell.RegisterCallback("GroupTypeChanged", "MainFrame_GroupTypeChanged", MainFrame_GroupTypeChanged)

-------------------------------------------------
-- event -- 游戏事件处理(已废弃，改用 RegisterStateDriver)
-- 旧版使用 RegisterEvent 监听宠物对战事件来隐藏/显示主框架
-- 现在通过 RegisterStateDriver + [petbattle] hide; show 宏条件实现，更可靠
-------------------------------------------------
-- cellMainFrame:RegisterEvent("PET_BATTLE_OPENING_START")
-- cellMainFrame:RegisterEvent("PET_BATTLE_OVER")
-- cellMainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- cellMainFrame:SetScript("OnEvent", function(self, event, ...)
--     if event == "PET_BATTLE_OPENING_START" then
--         cellMainFrame:Hide()
--     elseif event == "PET_BATTLE_OVER" then
--         cellMainFrame:Show()
--     -- elseif event == "PLAYER_ENTERING_WORLD" then
--     --     tools:SetFrameRef("raidMarksFrame", Cell.frames.raidMarksFrame)
--     end
-- end)

-------------------------------------------------
-- load & update -- 布局加载和菜单更新系统
-------------------------------------------------

-- UpdatePosition: 根据 menuPosition 配置(top_bottom/left_right)和 anchor 锚点
-- 排列 anchorFrame、options、raid 按钮的位置关系
-- 同时设置 tooltip 的弹出方向和像素级尺寸
-- 支持 8 种组合: 4个锚点(BOTTOMLEFT/BOTTOMRIGHT/TOPLEFT/TOPRIGHT) x 2个方向(top_bottom/left_right)
local function UpdatePosition()
    if not Cell.vars.currentLayoutTable then return end
    local anchor = Cell.vars.currentLayoutTable["main"]["anchor"]

    cellMainFrame:ClearAllPoints()
    P.ClearPoints(raid)

    if CellDB["general"]["menuPosition"] == "top_bottom" then
        -- 水平布局: 按钮横向排列，尺寸为 宽20 x 高10
        P.Size(anchorFrame, 20, 10)
        P.Size(options, 20, 10)
        P.Size(raid, 20, 10)


        if anchor == "BOTTOMLEFT" then
            cellMainFrame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 4) -- 团队框体在锚点上方
            P.Point(raid, "BOTTOMLEFT", options, "BOTTOMRIGHT", 1, 0) -- raid在options右侧
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPLEFT", "BOTTOMLEFT", 0, -3 -- tooltip在按钮下方
            -- hoverTop, hoverBottom, hoverLeft, hoverRight = 5, -20, -20, 20

        elseif anchor == "BOTTOMRIGHT" then
            cellMainFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 4)
            P.Point(raid, "BOTTOMRIGHT", options, "BOTTOMLEFT", -1, 0) -- raid在options左侧
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPRIGHT", "BOTTOMRIGHT", 0, -3
            -- hoverTop, hoverBottom, hoverLeft, hoverRight = 5, -20, -20, 20

        elseif anchor == "TOPLEFT" then
            cellMainFrame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4) -- 团队框体在锚点下方
            P.Point(raid, "TOPLEFT", options, "TOPRIGHT", 1, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMLEFT", "TOPLEFT", 0, 3 -- tooltip在按钮上方
            -- hoverTop, hoverBottom, hoverLeft, hoverRight = 20, -5, -20, 20

        elseif anchor == "TOPRIGHT" then
            cellMainFrame:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -4)
            P.Point(raid, "TOPRIGHT", options, "TOPLEFT", -1, 0)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMRIGHT", "TOPRIGHT", 0, 3
            -- hoverTop, hoverBottom, hoverLeft, hoverRight = 20, -5, -20, 20
        end
    else -- left_right -- 垂直布局: 按钮纵向排列，尺寸为 宽10 x 高20
        P.Size(anchorFrame, 10, 20)
        P.Size(options, 10, 20)
        P.Size(raid, 10, 20)

        if anchor == "BOTTOMLEFT" then
            cellMainFrame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMRIGHT", 4, 0) -- 团队框体在锚点右侧
            P.Point(raid, "BOTTOMLEFT", options, "TOPLEFT", 0, 1) -- raid在options上方
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMRIGHT", "BOTTOMLEFT", -3, 0 -- tooltip在按钮左侧
            -- hoverTop, hoverBottom, hoverLeft, hoverRight = 20, -20, -20, 5

        elseif anchor == "BOTTOMRIGHT" then
            cellMainFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMLEFT", -4, 0) -- 团队框体在锚点左侧
            P.Point(raid, "BOTTOMRIGHT", options, "TOPRIGHT", 0, 1)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMLEFT", "BOTTOMRIGHT", 3, 0 -- tooltip在按钮右侧
            -- hoverTop, hoverBottom, hoverLeft, hoverRight = 20, -20, -5, 20

        elseif anchor == "TOPLEFT" then
            cellMainFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 4, 0)
            P.Point(raid, "TOPLEFT", options, "BOTTOMLEFT", 0, -1) -- raid在options下方
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPRIGHT", "TOPLEFT", -3, 0
            -- hoverTop, hoverBottom, hoverLeft, hoverRight = 20, -20, -20, 5

        elseif anchor == "TOPRIGHT" then
            cellMainFrame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -4, 0)
            P.Point(raid, "TOPRIGHT", options, "BOTTOMRIGHT", 0, -1)
            tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPLEFT", "TOPRIGHT", 3, 0
            -- hoverTop, hoverBottom, hoverLeft, hoverRight = 20, -20, -5, 20
        end
    end

    UpdateHoverFrame()
end

-- UpdateMenu: 根据配置变更类型(which)更新菜单状态
-- which 参数可选值:
--   nil (全部更新): 同时更新 lock 和 fadeOut
--   "lock": 切换拖拽锁定状态 - 锁定时禁用拖拽，解锁后允许左键拖拽移动位置
--   "fadeOut": 切换淡出功能 - 启用时播放淡出动画，关闭时播放淡入(始终可见)
--   "position": 仅更新位置和方向
-- Midnight 防护: locked 状态下 RegisterForDrag() 无参数 => 禁止拖拽(战斗中安全)
--                unlocked 状态下 RegisterForDrag("LeftButton") => 允许左键拖拽(非战斗操作)
local function UpdateMenu(which)
    F.Debug("|cff00bfffUpdateMenu:|r", which)

    if not which or which == "lock" then
        if CellDB["general"]["locked"] then
            options:RegisterForDrag() -- 锁定: 不注册任何拖拽按钮(禁止拖拽)
            raid:RegisterForDrag()
            -- tools:RegisterForDrag()
        else
            options:RegisterForDrag("LeftButton") -- 解锁: 注册左键拖拽
            raid:RegisterForDrag("LeftButton")
            -- tools:RegisterForDrag("LeftButton")
        end
    end

    if not which or which == "fadeOut" then
        if CellDB["general"]["fadeOut"] then
            menuFrame.fadeOut:Play() -- 启用淡出: 立即开始淡出动画
            -- 旧版 OnUpdate 轮询方案(已废弃): 每0.25秒检查鼠标位置决定淡入/淡出
            -- 现改用 hoverFrame 的事件驱动方式，更高效且无轮询开销
        else
            menuFrame.fadeIn:Play() -- 禁用淡出: 保持菜单始终可见
        end
    end

    if which == "position" then
        UpdatePosition()
    end
end
-- 注册回调: 当用户修改菜单设置(锁定/淡出/位置)时触发
Cell.RegisterCallback("UpdateMenu", "MainFrame_UpdateMenu", UpdateMenu)

-- init: 首次加载标志，确保 RegisterStateDriver 只注册一次
-- 之所以需要此标志是因为 /reload 时布局可能被多次触发
local init
-- MainFrame_UpdateLayout: 布局更新主入口函数
-- 参数:
--   layout: 布局名称字符串(如 "default")
--   which: 更新范围 - nil(全量), "main-size"(仅尺寸), "main-arrangement"(仅排列)
-- 处理逻辑:
--   1. 检查 isHidden 状态 -> 控制整个主框架的显示/隐藏
--   2. 首次加载时注册 StateDriver 处理宠物对战时的自动隐藏
--   3. 根据 which 参数选择性更新尺寸、位置、排列
--   4. 全量更新时加载保存的位置，无保存位置则使用默认居中位置
-- Midnight 防护: RegisterStateDriver 使用宏条件 [petbattle] hide; show
--   在宠物对战时自动隐藏主框架，避免安全框架在宠物对战中的兼容问题
--   这是 WoW API 级别的安全机制，比手动监听事件更可靠
local function MainFrame_UpdateLayout(layout, which)
    F.Debug("|cffff0066UpdateLayout:|r layout:", layout, " which:", which)

    -- visibility -- 可见性控制
    if Cell.vars.isHidden then
        anchorFrame:Hide()
        menuFrame:Hide()
        hoverFrame:Hide()
        return -- 隐藏状态下跳过所有布局更新
    else
        anchorFrame:Show()
        menuFrame:Show()
        hoverFrame:Show()
    end

    if not init then
        --! NOTE: a reload during pet battle prevents HEADER from CREATING CHILDs (unit buttons), this hide delay is a MUST
        --! 重要: 宠物对战中 /reload 会导致 HEADER 无法创建子元素(单元按键)，此延迟隐藏是必须的
        -- Midnight 防护: RegisterStateDriver 通过宏条件在宠物对战时自动隐藏，对战结束后恢复
        RegisterStateDriver(cellMainFrame, "visibility", "[petbattle] hide; show")
        init = true
    end

    layout = Cell.vars.currentLayoutTable

    -- 尺寸更新: 应用布局中保存的 mainFrame 尺寸(width, height)
    if not which or which == "main-size" then
        P.Size(cellMainFrame, unpack(layout["main"]["size"]))
    end

    -- 排列更新: 重新计算按钮位置和 tooltip 方向
    if not which or which == "main-arrangement" then
        UpdatePosition()
    end

    -- load position -- 加载保存的锚点位置
    if not which then
        if not P.LoadPosition(anchorFrame, layout["main"]["position"]) then
            P.ClearPoints(anchorFrame)
            -- no position, use default -- 无保存位置时使用默认居中位置
            PixelUtil.SetPoint(anchorFrame, "TOPLEFT", CellParent, "CENTER", 1, -1)
        end
    end
end
-- 注册回调: 当布局配置变更(加载/切换/修改布局)时触发
Cell.RegisterCallback("UpdateLayout", "MainFrame_UpdateLayout", MainFrame_UpdateLayout)

-- UpdatePixelPerfect: 像素完美更新，在 UI 缩放变化后重新计算所有子元素的像素精确尺寸和位置
-- 遍历流程:
--   1. 重新计算 mainFrame 和 anchorFrame 的像素精确尺寸
--   2. options 和 raid 按钮调用各自的 UpdatePixelPerfect 方法
--   3. loadingBar 重新锚点和调整尺寸
--   4. 遍历所有单元按键，逐个调用 B.UpdatePixelPerfect 进行像素级修正
local function UpdatePixelPerfect()
    F.Debug("|cffffff7fUpdatePixelPerfect")
    P.Resize(cellMainFrame)
    -- P.Repoint(cellMainFrame)
    P.Resize(anchorFrame)
    options:UpdatePixelPerfect()
    raid:UpdatePixelPerfect()
    P.Repoint(loadingBar)
    P.Resize(loadingBar)

    -- 遍历所有单元按键进行像素完美更新，第二个参数 true 表示强制更新
    F.IterateAllUnitButtons(function(b)
        B.UpdatePixelPerfect(b, true)
    end, true)
end
-- 注册回调: 当 UI 缩放变化或需要像素级重绘时触发
Cell.RegisterCallback("UpdatePixelPerfect", "MainFrame_UpdatePixelPerfect", UpdatePixelPerfect)