-- 模块：团队标记（Raid Targets）与世界标记（World Markers）工具
-- 提供快捷的团队目标图标标记和世界标记功能，支持水平/垂直排列、淡出效果、拖拽定位
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs
local A = Cell.animations

-- 局部变量：marks 为团队目标标记按钮组，worldMarks 为世界标记按钮组
local marks, worldMarks

-- 创建主框架 CellRaidMarksFrame，继承 SecureFrameTemplate 和 BackdropTemplate
-- 作为团队标记和世界标记的父容器，支持拖拽移动
local marksFrame = CreateFrame("Frame", "CellRaidMarksFrame", Cell.frames.mainFrame, "SecureFrameTemplate,BackdropTemplate")
Cell.frames.raidMarksFrame = marksFrame
marksFrame:SetSize(196, 40)
PixelUtil.SetPoint(marksFrame, "BOTTOMRIGHT", CellParent, "CENTER", -1, 1)
marksFrame:SetClampedToScreen(true)
marksFrame:SetMovable(true)
marksFrame:RegisterForDrag("LeftButton")
-- 拖拽开始：允许移动框架，标记为非用户放置（由插件控制位置保存）
marksFrame:SetScript("OnDragStart", function()
    marksFrame:StartMoving()
    marksFrame:SetUserPlaced(false)
end)
-- 拖拽停止：保存最终位置到 CellDB 数据库
marksFrame:SetScript("OnDragStop", function()
    marksFrame:StopMovingOrSizing()
    -- 保存拖拽后的位置到数据库
    P.SavePosition(marksFrame, CellDB["tools"]["marks"][4])
end)

-------------------------------------------------
-- mover
-------------------------------------------------
-- 移动提示文字：显示在标记框架顶部的"Mover"文本，仅在编辑模式下可见
marksFrame.moverText = marksFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
marksFrame.moverText:SetPoint("TOP", 0, -3)
marksFrame.moverText:SetText(L["Mover"])
marksFrame.moverText:Hide()

-- ShowMover: 切换标记框架的显示模式（编辑/使用模式）
-- show=true: 进入编辑模式，显示移动提示文字，高亮框架边框，启用鼠标拖拽
-- show=false: 进入使用模式，隐藏移动提示文字，根据设置控制按钮可见性
local function ShowMover(show)
    if show then
		-- 如果工具未启用则直接返回
		if not CellDB["tools"]["marks"][1] then return end
		marksFrame:EnableMouse(true)
        marksFrame.moverText:Show()
        Cell.StylizeFrame(marksFrame, {0, 1, 0, 0.4}, {0, 0, 0, 0})
-- 编辑模式下：即使没有权限也显示所有按钮（方便预览布局）
        if not F.HasPermission(true) then -- button not shown
            if strfind(CellDB["tools"]["marks"][3], "^target") then
                marks:Show()
            elseif strfind(CellDB["tools"]["marks"][3], "^world") then
                worldMarks:Show()
            else
                marks:Show()
                worldMarks:Show()
            end
        end
        marksFrame:SetAlpha(1)
    else
        marksFrame:EnableMouse(false)
        marksFrame.moverText:Hide()
        Cell.StylizeFrame(marksFrame, {0, 0, 0, 0}, {0, 0, 0, 0})
-- 非编辑模式下的权限检查：如果当前是 solo 且启用了 solo 标记则保留团队标记显示
        if not F.HasPermission(true) then -- button should not shown
            if not (Cell.vars.groupType == "solo" and CellDB["tools"]["marks"][2]) then
                marks:Hide()
            end
            worldMarks:Hide()
        end
        marksFrame:SetAlpha(CellDB["tools"]["fadeOut"] and 0 or 1)
    end
end
Cell.RegisterCallback("ShowMover", "RaidMarks_ShowMover", ShowMover)

-------------------------------------------------
-- colors
-------------------------------------------------
-- 团队标记颜色表：索引 1-8 对应星星/圆圈/菱形/三角/月亮/方块/十字/骷髅，索引 9 为清除按钮颜色
local markColors = {
    {1, 1, 0}, -- star
    {1, 0.5, 0}, -- circle
    {0.5, 0, 1}, -- diamond
    {0, 1, 0.2}, -- triangle
    {0.5, 0.5, 0.5}, -- moon
    {0, 0.5, 1}, -- square
    {1, 0, 0}, -- cross
    {1, 1, 1}, -- skull
    {1, 0.19, 0.19}, -- clear
}

-------------------------------------------------
-- marks
-------------------------------------------------
-- 团队目标标记按钮容器：嵌套在 marksFrame 内，大小为 196x20
marks = Cell.CreateFrame("CellRaidMarksFrame_Marks", marksFrame, 196, 20, true)
marks:SetPoint("BOTTOMLEFT")
-- 初始隐藏，等待权限检查后决定是否显示
marks:Hide()

-- ticker: 用于锁定标记的周期性刷新定时器（仅索引 1-8 的按钮使用）
local ticker
-- markButtons: 团队目标图标按钮数组（索引 1-8 为标记类型，索引 9 为清除全部）
local markButtons = {}
-- 创建 9 个团队标记按钮（按钮 1-8 为标记类型图标，按钮 9 为清除全部）
for i = 1, 9 do
    markButtons[i] = Cell.CreateButton(marks, "", "accent-hover", {20, 20})
    markButtons[i].texture = markButtons[i]:CreateTexture(nil, "ARTWORK")
    P.Point(markButtons[i].texture, "TOPLEFT", markButtons[i], "TOPLEFT", 2, -2)
-- 按钮 1-8: 团队目标图标标记按钮 / 按钮 9: 清除全部标记按钮
    P.Point(markButtons[i].texture, "BOTTOMRIGHT", markButtons[i], "BOTTOMRIGHT", -2, 2)

    if i == 9 then
        -- clear all marks
        markButtons[i].texture:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        markButtons[i]:SetScript("OnClick", function()
            RemoveRaidTargets()
            -- markButtons[i]:SetEnabled(false)
-- 第9个按钮为"清除所有标记"按钮，调用 RemoveRaidTargets() 一次移除所有团队标记
            -- markButtons[i].texture:SetDesaturated(true)
            -- for j = 1, 8 do
            --     SetRaidTarget("player", j)
            -- end
            -- C_Timer.After(0.5, function()
            --     SetRaidTarget("player", 0)
            --     markButtons[i]:SetEnabled(true)
            --     markButtons[i].texture:SetDesaturated(false)
            -- end)
        end)
    else
        markButtons[i].texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
-- 为按钮设置对应标记类型的图标纹理（从 UI-RaidTargetingIcons 图集采样）
        SetRaidTargetIconTexture(markButtons[i].texture, i)
        markButtons[i]:RegisterForClicks("LeftButtonDown", "RightButtonDown")
        markButtons[i]:SetScript("OnClick", function(self, button)
-- 左键点击：切换当前目标的团队标记图标（如果已设置相同图标则清除）
            if button == "LeftButton" then
                -- set raid target icon
                if GetRaidTargetIndex("target") == i then
                    SetRaidTarget("target", 0)
                else
-- 获取当前目标的 unit, name, class 信息
                    SetRaidTarget("target", i)
                end
            elseif button == "RightButton" then
                -- lock raid target icon
                local unit, name, class = F.GetTargetUnitInfo()
-- 右击解锁：清除锁定标记，恢复边框颜色
                if unit and name then
                    if markButtons[i].locked then
                        F.NotifyMarkUnlock(i, name, class)
                        SetRaidTarget(markButtons[i].locked, 0)
                        markButtons[i]:SetBackdropBorderColor(0, 0, 0, 1)
                        markButtons[i].locked = nil
                        if markButtons[i].ticker then
                            markButtons[i].ticker:Cancel()
                            markButtons[i].ticker = nil
-- 右击锁定：将当前目标锁定到该标记图标，边框高亮为标记颜色
                        end
                    else
                        F.NotifyMarkLock(i, name, class)
                        SetRaidTarget(unit, i)
-- 锁定标记：启动 1.5 秒定时器，如果目标单位仍然存在且标记被覆盖则重新设置
                        markButtons[i]:SetBackdropBorderColor(markColors[i][1], markColors[i][2], markColors[i][3], 1)
                        markButtons[i].locked = unit
                        markButtons[i].ticker = C_Timer.NewTicker(1.5, function()
                            if UnitName(unit) == name then
                                if GetRaidTargetIndex(unit) ~= i then
                                    SetRaidTarget(unit, i)
                                end
                            else
                                markButtons[i].locked = nil
                                markButtons[i].ticker:Cancel()
                                markButtons[i].ticker = nil
                                markButtons[i]:SetBackdropBorderColor(0, 0, 0, 1)
                            end
                        end)
                    end
                end
            end
        end)
    end

-- 按钮背景：深灰色 10% 亮度 + 70% 不透明度
    markButtons[i].bg:SetColorTexture(0.1, 0.1, 0.1, 0.7)
-- 按钮默认背景完全透明，实际颜色由 bg 纹理提供
    markButtons[i]:SetBackdropColor(0, 0, 0, 0)
    markButtons[i].color = {0, 0, 0, 0}
-- 鼠标悬停颜色：使用对应标记颜色 + 35% 透明度
    markButtons[i].hoverColor = {markColors[i][1], markColors[i][2], markColors[i][3], 0.35}

    -- if i == 1 then
    --     P.Point(markButtons[i], "TOPLEFT")
    -- else
    --     P.Point(markButtons[i], "LEFT", markButtons[i-1], "RIGHT", 2, 0)
    -- end
end

-- 团队标记框架隐藏时：清除所有锁定状态并取消定时器
marks:SetScript("OnHide", function()
    for i = 1, 8 do
        markButtons[i].locked = nil
        if markButtons[i].ticker then
            markButtons[i].ticker:Cancel()
            markButtons[i].ticker = nil
        end
        markButtons[i]:SetBackdropBorderColor(0, 0, 0, 1)
    end
end)

-------------------------------------------------
-- world marks
-------------------------------------------------
-- 世界标记按钮框架，使用 SecureActionButtonTemplate 以支持在战斗中通过属性设置发送世界标记指令
worldMarks = Cell.CreateFrame("CellRaidMarksFrame_WorldMarks", marksFrame, 196, 20, true)
worldMarks:SetPoint("BOTTOMLEFT")
worldMarks:Hide()

-- 世界标记索引映射：按钮顺序(1-8)对应的世界标记 ID (5=月亮, 6=方块, 3=菱形, 2=圆圈, 7=十字, 1=星星, 4=三角, 8=骷髅)
local worldMarkIndices = {5, 6, 3, 2, 7, 1, 4, 8}
local worldMarkButtons = {}
-- 创建世界标记按钮（1-8 为世界标记类型，9 为清除全部）
for i = 1, 9 do
    worldMarkButtons[i] = Cell.CreateButton(worldMarks, "", "accent-hover", {20, 20}, false, false, nil, nil, "SecureActionButtonTemplate")
    worldMarkButtons[i]:RegisterForClicks("LeftButtonUp", "LeftButtonDown") -- NOTE: ActionButtonUseKeyDown will affect this
    worldMarkButtons[i].texture = worldMarkButtons[i]:CreateTexture(nil, "ARTWORK")

    if i == 9 then
        -- clear all marks
        P.Point(worldMarkButtons[i].texture, "TOPLEFT", worldMarkButtons[i], "TOPLEFT", 2, -2)
        P.Point(worldMarkButtons[i].texture, "BOTTOMRIGHT", worldMarkButtons[i], "BOTTOMRIGHT", -2, 2)
        worldMarkButtons[i].texture:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
-- 清除按钮：设置世界标记类型为 "clear" 清除所有世界标记
        worldMarkButtons[i]:SetAttribute("type", "worldmarker")
        worldMarkButtons[i]:SetAttribute("action", "clear")
    else
        P.Point(worldMarkButtons[i].texture, "TOPLEFT", worldMarkButtons[i], "TOPLEFT", 1, -1)
        P.Point(worldMarkButtons[i].texture, "BOTTOMRIGHT", worldMarkButtons[i], "BOTTOMRIGHT", -1, 1)
-- 世界标记按钮使用纯色填充纹理（无图标），40% 不透明度
        worldMarkButtons[i].texture:SetColorTexture(markColors[i][1], markColors[i][2], markColors[i][3], 0.4)
        worldMarkButtons[i]:SetAttribute("type", "worldmarker")
-- 设置世界标记 ID（使用 worldMarkIndices 映射表）
        worldMarkButtons[i]:SetAttribute("marker", worldMarkIndices[i])
        -- worldMarkButtons[i]:SetAttribute("type", "macro")
        -- worldMarkButtons[i]:SetAttribute("macrotext", "/wm "..worldMarkIndices[i])
    end

-- 按钮背景：深灰色 10% 亮度 + 70% 不透明度
    worldMarkButtons[i].bg:SetColorTexture(0.1, 0.1, 0.1, 0.7)
-- 按钮默认背景完全透明，实际颜色由 bg 纹理提供
    worldMarkButtons[i]:SetBackdropColor(0, 0, 0, 0)
    worldMarkButtons[i].color = {0, 0, 0, 0}
-- 鼠标悬停颜色：使用对应标记颜色 + 35% 透明度
    worldMarkButtons[i].hoverColor = {markColors[i][1], markColors[i][2], markColors[i][3], 0.35}

    -- if i == 1 then
    --     P.Point(worldMarkButtons[i], "TOPLEFT")
    -- else
    --     P.Point(worldMarkButtons[i], "LEFT", worldMarkButtons[i-1], "RIGHT", 2, 0)
    -- end
end

local worldMarksTimer
-- 世界标记显示时启动 0.5 秒定时器，周期性检查各世界标记是否激活并更新按钮边框颜色
worldMarks:SetScript("OnShow", function()
-- 周期性检查世界标记激活状态的定时器（0.5 秒间隔）
    worldMarksTimer = C_Timer.NewTicker(0.5, function()
        for i = 1, 8 do
            if IsRaidMarkerActive(worldMarkIndices[i]) then
                worldMarkButtons[i]:SetBackdropBorderColor(markColors[i][1], markColors[i][2], markColors[i][3], 1)
            else
                worldMarkButtons[i]:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
    end)
end)
-- 世界标记隐藏时取消更新定时器
worldMarks:SetScript("OnHide", function()
    if worldMarksTimer then
        worldMarksTimer:Cancel()
        worldMarksTimer = nil
    end
end)

-------------------------------------------------
-- fade out
-------------------------------------------------
local buttons = {}
for _, b in pairs(markButtons) do
    tinsert(buttons, b)
end
for _, b in pairs(worldMarkButtons) do
    tinsert(buttons, b)
end
-- 将淡入淡出动画应用到所有标记按钮（团队标记 + 世界标记共 18 个按钮）
A.ApplyFadeInOutToParent(marksFrame, function()
    return CellDB["tools"]["fadeOut"] and not marksFrame.moverText:IsShown()
end, unpack(buttons))

-------------------------------------------------
-- functions
-------------------------------------------------
-- Rearrange: 根据布局配置重新排列标记按钮
-- marksConfig 格式示例: "target_h" = 仅团队标记水平排列, "world_v" = 仅世界标记垂直排列, "both_h" = 两者水平排列
-- 水平模式 (_h): 按钮从左到右排列，整体框架宽度 = 9 * 20 + 8 * 2
-- 垂直模式 (_v): 按钮从上到下排列，整体框架高度 = 9 * 20 + 8 * 2
-- 同时显示两者时，团队标记位于世界标记上方（_h）或右侧（_v）
local function Rearrange(marksConfig)
    local scaled20 = P.Scale(20)

    if strfind(marksConfig, "_h$") then
        local width = scaled20 * 9 + P.Scale(2) * 8

        marks:SetSize(width, scaled20)
        worldMarks:SetSize(width, scaled20)

        if strfind(marksConfig, "^target") then
            marksFrame:SetSize(width, P.Scale(40))
            worldMarks:Hide()
            P.ClearPoints(marks)
            P.Point(marks, "BOTTOMLEFT")
        elseif strfind(marksConfig, "^world") then
            marksFrame:SetSize(width, P.Scale(40))
            marks:Hide()
            P.ClearPoints(worldMarks)
            P.Point(worldMarks, "BOTTOMLEFT")
        else -- both
            marksFrame:SetSize(width, P.Scale(60))
            P.ClearPoints(worldMarks)
            P.Point(worldMarks, "BOTTOMLEFT")
            P.ClearPoints(marks)
            P.Point(marks, "BOTTOMLEFT", worldMarks, "TOPLEFT", 0, 2)
        end

        -- repoint each button
        for i = 1, 9 do
            P.ClearPoints(markButtons[i])
            P.ClearPoints(worldMarkButtons[i])
            if i == 1 then
                P.Point(markButtons[i], "TOPLEFT")
                P.Point(worldMarkButtons[i], "TOPLEFT")
            else
                P.Point(markButtons[i], "TOPLEFT", markButtons[i-1], "TOPRIGHT", 2, 0)
                P.Point(worldMarkButtons[i], "TOPLEFT", worldMarkButtons[i-1], "TOPRIGHT", 2, 0)
            end
        end
    elseif strfind(marksConfig, "_v$") then
        local height = scaled20 * 9 + P.Scale(2) * 8

        marks:SetSize(scaled20, height)
        worldMarks:SetSize(scaled20, height)

        if strfind(marksConfig, "^target") then
            marksFrame:SetSize(scaled20, height + scaled20)
            worldMarks:Hide()
            P.ClearPoints(marks)
            P.Point(marks, "BOTTOMLEFT")
        elseif strfind(marksConfig, "^world") then
            marksFrame:SetSize(scaled20, height + scaled20)
            marks:Hide()
            P.ClearPoints(worldMarks)
            P.Point(worldMarks, "BOTTOMLEFT")
        else -- both
            marksFrame:SetSize(P.Scale(40) + P.Scale(2), height + scaled20)
            P.ClearPoints(worldMarks)
            P.Point(worldMarks, "BOTTOMLEFT")
            P.ClearPoints(marks)
            P.Point(marks, "BOTTOMLEFT", worldMarks, "BOTTOMRIGHT", 2, 0)
        end

        -- repoint each button
        for i = 1, 9 do
            P.ClearPoints(markButtons[i])
            P.ClearPoints(worldMarkButtons[i])
            if i == 1 then
                P.Point(markButtons[i], "TOPLEFT")
                P.Point(worldMarkButtons[i], "TOPLEFT")
            else
                P.Point(markButtons[i], "TOPLEFT", markButtons[i-1], "BOTTOMLEFT", 0, -2)
                P.Point(worldMarkButtons[i], "TOPLEFT", worldMarkButtons[i-1], "BOTTOMLEFT", 0, -2)
            end
        end
    end
end

-- CheckPermission: 根据战斗状态和权限设置控制标记按钮的显示/隐藏
-- 战斗中注册 PLAYER_REGEN_ENABLED 事件等待脱战再检查，避免战斗中修改受保护框架
-- 非战斗中直接检查：工具启用标记、显示模式（target/world/both）、权限与 solo 模式覆盖
local function CheckPermission()
-- 战斗保护检查：战斗中无法修改受保护框架的显示状态
    if InCombatLockdown() then
-- 战斗中：注册 PLAYER_REGEN_ENABLED 事件，等待脱战后再检查
        marksFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
-- 非战斗中：取消事件注册，直接执行权限检查
        marksFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
-- 工具已启用，根据显示模式决定显示哪些按钮（target/world/both）
        if CellDB["tools"]["marks"][1] then
            if strfind(CellDB["tools"]["marks"][3], "^target") then
                if marksFrame.moverText:IsShown() or Cell.vars.hasPartyMarkPermission then
                    marks:Show()
                else
                    marks:Hide()
                end

            elseif strfind(CellDB["tools"]["marks"][3], "^world") then
                if marksFrame.moverText:IsShown() or Cell.vars.hasPartyMarkPermission then
                    worldMarks:Show()
                else
                    worldMarks:Hide()
                end

            else -- both
                if marksFrame.moverText:IsShown() or Cell.vars.hasPartyMarkPermission then
                    marks:Show()
                    worldMarks:Show()
                else
                    marks:Hide()
                    worldMarks:Hide()
                end
            end

            -- override
-- solo 模式覆盖：如果当前是单人模式且启用了 solo 标记，强制显示团队标记
            if Cell.vars.groupType == "solo" and CellDB["tools"]["marks"][2] then
                marks:Show()
            end

-- 根据新的配置重新排列按钮布局
            Rearrange(CellDB["tools"]["marks"][3])
        else
            marks:Hide()
            worldMarks:Hide()
        end
    end
end

-- 事件处理: 当 PLAYER_REGEN_ENABLED 事件触发时（脱离战斗），重新检查权限并刷新按钮显示
marksFrame:SetScript("OnEvent", function()
    CheckPermission()
end)

Cell.RegisterCallback("PermissionChanged", "RaidMarks_PermissionChanged", CheckPermission)

local function UpdateTools(which)
    F.Debug("|cffBBFFFFUpdateTools:|r", which)
-- UpdateTools: 响应工具配置变更回调，处理标记启用、淡出和位置三项更新
-- which 参数可指定只更新某一方面："marks" | "fadeOut" | nil（全部更新含位置）
    if not which or which == "marks" then
        CheckPermission()
        ShowMover(Cell.vars.showMover and CellDB["tools"]["marks"][1])
    end

    if not which or which == "fadeOut" then
        if CellDB["tools"]["fadeOut"] and not marksFrame.moverText:IsShown() then
            marksFrame:SetAlpha(0)
        else
            marksFrame:SetAlpha(1)
        end
    end

    if not which then -- position
        P.LoadPosition(marksFrame, CellDB["tools"]["marks"][4])
    end
end
Cell.RegisterCallback("UpdateTools", "RaidMarks_UpdateTools", UpdateTools)

-- UpdatePixelPerfect: 响应像素完美缩放更新，重新调整所有标记按钮及其纹理的位置
local function UpdatePixelPerfect()
    -- P.Resize(marksFrame)
    -- P.Resize(marks)
    -- P.Resize(worldMarks)
    P.Repoint(marks) -- only marks needs to repoint

-- 遍历所有按钮（团队标记 9 个 + 世界标记 8 个），更新像素完美缩放
    for i = 1, 9 do
        markButtons[i]:UpdatePixelPerfect()
        worldMarkButtons[i]:UpdatePixelPerfect()
        P.Repoint(markButtons[i].texture)
        P.Repoint(worldMarkButtons[i].texture)
    end
end
Cell.RegisterCallback("UpdatePixelPerfect", "Marks_UpdatePixelPerfect", UpdatePixelPerfect)