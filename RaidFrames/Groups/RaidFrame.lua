-- 模块导入：Cell 主表、函数表 F、布局函数表 B、像素完美缩放函数表 P
local _, Cell = ...
---@class CellFuncs
local F = Cell.funcs
local B = Cell.bFuncs
local P = Cell.pixelPerfectFuncs

-- 创建主团队框架，挂载到 Cell 主窗口上，使用 SecureHandlerAttributeTemplate 模板以支持安全属性驱动
local raidFrame = CreateFrame("Frame", "CellRaidFrame", Cell.frames.mainFrame, "SecureHandlerAttributeTemplate")
Cell.frames.raidFrame = raidFrame
raidFrame:SetAllPoints(Cell.frames.mainFrame)

-- NPC 框架锚点：用于在团队框架末尾定位 NPC/宠物按钮的虚拟锚点框架
-- 此框架的位置由 _onattributechanged 事件处理程序根据 combineGroups、orientation、anchor 等属性动态计算
local npcFrameAnchor = CreateFrame("Frame", "CellNPCFrameAnchor", raidFrame, "SecureFrameTemplate,BackDropTemplate")
raidFrame:SetFrameRef("npcAnchor", npcFrameAnchor)
-- npcFrameAnchor:Hide() -- 注释掉的隐藏逻辑，锚点框架需要始终可见以提供定位参考
-- Cell.StylizeFrame(npcFrameAnchor) -- 注释掉的样式应用

--[[ _onattributechanged 安全属性变更事件处理程序
-- 当 combineGroups 或 visibility 属性变更时，重新计算并设置 npcFrameAnchor 的位置。
-- npcFrameAnchor 是 NPC/宠物按钮的锚点参考，必须跟随团队框架的最后一个可见 header 来定位。
--
-- 工作原理：
-- 1. 合并模式 (combineGroups=true)：锚点对接到 combinedHeader（所有小队合并显示）
-- 2. 分离模式 (combineGroups=false)：查找最高编号的可见 visibilityHelper，其对应当前布局中最后一个小队 header
--    如果所有子组都为空（maxGroup == nil），则直接返回不更新锚点位置
-- 3. 根据 orientation（垂直/水平）和 anchor（四个角落）计算锚点方向和 spacing
--    - 垂直布局：锚点在 header 的横向（LEFT/RIGHT），间距作用于 x 轴
--    - 水平布局：锚点在 header 的纵向（TOP/BOTTOM），间距作用于 y 轴
--]]
raidFrame:SetAttribute("_onattributechanged", [[
    -- 仅响应 combinegroups 和 visibility 属性变更，忽略其他属性变更以提升性能
    if not (name == "combinegroups" or name == "visibility") then
        return
    end

    local header
    local combineGroups = self:GetAttribute("combineGroups")

    if combineGroups then
        -- 合并模式：使用 combinedHeader 作为 NPC 锚点的参考
        header = self:GetFrameRef("combinedHeader")
    else
        -- 分离模式：找到最高编号的可见小队，将其 header 作为锚点参考
        local maxGroup
        for i = 1, 8 do
            if self:GetFrameRef("visibilityHelper"..i):IsVisible() then
                maxGroup = i
            end
        end
        if not maxGroup then return end -- NOTE: empty subgroup will cause maxGroup == nil -- 所有子组为空，无法确定锚点位置
        header = self:GetFrameRef("subgroup"..maxGroup)
    end

    local npcFrameAnchor = self:GetFrameRef("npcAnchor")
    local spacing = self:GetAttribute("spacing") or 0
    local orientation = self:GetAttribute("orientation") or "vertical"
    local anchor = self:GetAttribute("anchor") or "TOPLEFT"

    -- 清除旧锚点，根据布局方向和起始角落重新计算 NPC 锚点的位置
    npcFrameAnchor:ClearAllPoints()
    local point, anchorPoint
    if orientation == "vertical" then
        -- 垂直布局：NPC 锚点接在 header 的水平（左右）方向上
        -- spacing 作用于 x 轴（header 的横向偏移）
        if anchor == "BOTTOMLEFT" then
            point, anchorPoint = "BOTTOMLEFT", "BOTTOMRIGHT"
        elseif anchor == "BOTTOMRIGHT" then
            point, anchorPoint = "BOTTOMRIGHT", "BOTTOMLEFT"
        elseif anchor == "TOPLEFT" then
            point, anchorPoint = "TOPLEFT", "TOPRIGHT"
        elseif anchor == "TOPRIGHT" then
            point, anchorPoint = "TOPRIGHT", "TOPLEFT"
        end

        npcFrameAnchor:SetPoint(point, header, anchorPoint, spacing, 0)
    else
        -- 水平布局：NPC 锚点接在 header 的垂直（上下）方向上
        -- spacing 作用于 y 轴（header 的纵向偏移）
        if anchor == "BOTTOMLEFT" then
            point, anchorPoint = "BOTTOMLEFT", "TOPLEFT"
        elseif anchor == "BOTTOMRIGHT" then
            point, anchorPoint = "BOTTOMRIGHT", "TOPRIGHT"
        elseif anchor == "TOPLEFT" then
            point, anchorPoint = "TOPLEFT", "BOTTOMLEFT"
        elseif anchor == "TOPRIGHT" then
            point, anchorPoint = "TOPRIGHT", "BOTTOMRIGHT"
        end

        npcFrameAnchor:SetPoint(point, header, anchorPoint, 0, spacing)
    end
]])

--[[ Interface\FrameXML\SecureGroupHeaders.lua
-- 安全团队头部模板 (SecureGroupHeaderTemplate) 支持的配置属性列表
-- CellD 使用这些属性来控制团队框架的显示方式、排序、分组和布局
List of the various configuration attributes
======================================================
showRaid = [BOOLEAN] -- true if the header should be shown while in a raid
showParty = [BOOLEAN] -- true if the header should be shown while in a party and not in a raid
showPlayer = [BOOLEAN] -- true if the header should show the player when not in a raid
showSolo = [BOOLEAN] -- true if the header should be shown while not in a group (implies showPlayer)
nameList = [STRING] -- a comma separated list of player names (not used if 'groupFilter' is set)
groupFilter = [1-8, STRING] -- a comma seperated list of raid group numbers and/or uppercase class names and/or uppercase roles
roleFilter = [STRING] -- a comma seperated list of MT/MA/Tank/Healer/DPS role strings
strictFiltering = [BOOLEAN]
-- if true, then
---- if only groupFilter is specified then characters must match both a group and a class from the groupFilter list
---- if only roleFilter is specified then characters must match at least one of the specified roles
---- if both groupFilter and roleFilters are specified then characters must match a group and a class from the groupFilter list and a role from the roleFilter list
point = [STRING] -- a valid XML anchoring point (Default: "TOP")
xOffset = [NUMBER] -- the x-Offset to use when anchoring the unit buttons (Default: 0)
yOffset = [NUMBER] -- the y-Offset to use when anchoring the unit buttons (Default: 0)
sortMethod = ["INDEX", "NAME", "NAMELIST"] -- defines how the group is sorted (Default: "INDEX")
sortDir = ["ASC", "DESC"] -- defines the sort order (Default: "ASC")
template = [STRING] -- the XML template to use for the unit buttons
templateType = [STRING] - specifies the frame type of the managed subframes (Default: "Button")
groupBy = [nil, "GROUP", "CLASS", "ROLE", "ASSIGNEDROLE"] - specifies a "grouping" type to apply before regular sorting (Default: nil)
groupingOrder = [STRING] - specifies the order of the groupings (ie. "1,2,3,4,5,6,7,8")
maxColumns = [NUMBER] - maximum number of columns the header will create (Default: 1)
unitsPerColumn = [NUMBER or nil] - maximum units that will be displayed in a singe column, nil is infinite (Default: nil)
startingIndex = [NUMBER] - the index in the final sorted unit list at which to start displaying units (Default: 1)
columnSpacing = [NUMBER] - the amount of space between the rows/columns (Default: 0)
columnAnchorPoint = [STRING] - the anchor point of each new column (ie. use LEFT for the columns to grow to the right)
--]]

-------------------------------------------------
-- combinedHeader（合并模式团队头部，将所有 1-8 小组合并显示在一个 header 中）
-------------------------------------------------
-- 使用 startingIndex 技巧在初始化时强制预创建充足的按钮槽位（needButtons=5），详见下方注释
local combinedHeader
do
    local headerName = "CellRaidFrameHeader0"
    combinedHeader = CreateFrame("Frame", headerName, raidFrame, "SecureGroupHeaderTemplate")
    Cell.unitButtons.raid[headerName] = combinedHeader

    combinedHeader:SetAttribute("template", "CellUnitButtonTemplate")
    combinedHeader:SetAttribute("columnAnchorPoint", "LEFT")
    combinedHeader:SetAttribute("point", "TOP")
    combinedHeader:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
    -- combinedHeader:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    -- combinedHeader:SetAttribute("groupBy", "ASSIGNEDROLE")
    combinedHeader:SetAttribute("xOffset", 0)
    combinedHeader:SetAttribute("yOffset", -1)
    combinedHeader:SetAttribute("unitsPerColumn", 5)
    combinedHeader:SetAttribute("maxColumns", 8)
    -- combinedHeader:SetAttribute("showRaid", true)

    -- startingIndex 技巧：先设为 -39 再 Show() 然后恢复为 1，欺骗 SecureGroupHeaders 的
    -- configureChildren 逻辑：起始索引 -39 经过 unitsPerColumn*maxColumns 计算后迫使 needButtons 至少为 5
    -- 这比默认的 1 个按钮更充足，确保团队框架有足够的预分配按钮
    combinedHeader:SetAttribute("startingIndex", -39)
    combinedHeader:Show()
    combinedHeader:SetAttribute("startingIndex", 1)

    -- for npcFrame's point（注册 combinedHeader 为 frameRef，供 _onattributechanged 在合并模式下获取 NPC 锚点参考）
    raidFrame:SetFrameRef("combinedHeader", combinedHeader)
end

-------------------------------------------------
-- separatedHeaders（分离模式团队头部，每个小队独立一个 header）
-- 每个 header 只显示 groupFilter 指定的单个小队，各小队 header 独立排列
-------------------------------------------------
local separatedHeaders = {} -- 存放 1-8 小队各自的 header 引用
-- 创建单个小队的独立 header，使用 SecureGroupHeaderTemplate 模板，groupFilter 锁定为指定 group
local function CreateGroupHeader(group)
    local headerName = "CellRaidFrameHeader"..group
    local header = CreateFrame("Frame", headerName, raidFrame, "SecureGroupHeaderTemplate")
    separatedHeaders[group] = header
    Cell.unitButtons.raid[headerName] = header

    -- header:SetAttribute("initialConfigFunction", [[
    --     RegisterUnitWatch(self)

    --     local header = self:GetParent()
    --     self:SetWidth(header:GetAttribute("buttonWidth") or 66)
    --     self:SetHeight(header:GetAttribute("buttonHeight") or 46)
    -- ]])

    -- header:SetAttribute("_initialAttributeNames", "refreshUnitChange")

    header:SetAttribute("template", "CellUnitButtonTemplate")
    header:SetAttribute("columnAnchorPoint", "LEFT")
    header:SetAttribute("point", "TOP")
    header:SetAttribute("groupFilter", group)
    header:SetAttribute("xOffset", 0)
    header:SetAttribute("yOffset", -1)
    header:SetAttribute("unitsPerColumn", 5)
    header:SetAttribute("columnSpacing", 1)
    header:SetAttribute("maxColumns", 1)
    -- header:SetAttribute("startingIndex", 1)
    header:SetAttribute("showRaid", true)

    --[[ Interface\FrameXML\SecureGroupHeaders.lua line 150
        local loopStart = startingIndex;
        local loopFinish = min((startingIndex - 1) + unitsPerColumn * numColumns, unitCount)
        -- ensure there are enough buttons
        numDisplayed = loopFinish - (loopStart - 1)
        local needButtons = max(1, numDisplayed); --! to make needButtons == 5
    ]]

    --! to make needButtons == 5 cheat configureChildren in SecureGroupHeaders.lua
    -- startingIndex 技巧（小队版本）：设为 -4 再 Show() 然后恢复为 1，使 needButtons=5，原理与 combinedHeader 相同
    header:SetAttribute("startingIndex", -4)
    header:Show()
    header:SetAttribute("startingIndex", 1)

    -- for i, b in ipairs(header) do
    --     b.type = "main" -- layout setup
    -- end

    -- for npcFrame's point（注册子组 header 为 frameRef，供 _onattributechanged 在分离模式下查找最后可见小队位置）
    raidFrame:SetFrameRef("subgroup"..group, header)

    -- visibilityHelper：监控小队第一个单位按钮的显示/隐藏，当小队可见时设置 raidFrame.visibility=1
    local helper = CreateFrame("Frame", nil, header[1], "SecureHandlerShowHideTemplate")
    helper:SetFrameRef("raidframe", raidFrame)
    raidFrame:SetFrameRef("visibilityHelper"..group, helper)
    helper:SetAttribute("_onshow", [[ self:GetFrameRef("raidframe"):SetAttribute("visibility", 1) ]])
    helper:SetAttribute("_onhide", [[ self:GetFrameRef("raidframe"):SetAttribute("visibility", 0) ]])
end

for i = 1, 8 do
    CreateGroupHeader(i)
end

-- arena pet（竞技场宠物按钮，正式服 3 个 / 怀旧服 5 个，作为独立按钮而非 header 管理）
local arenaPetButtons = {}
for i = 1, (Cell.isRetail and 3 or 5) do
    arenaPetButtons[i] = CreateFrame("Button", "CellArenaPet"..i, raidFrame, "CellUnitButtonTemplate")
    arenaPetButtons[i]:SetAttribute("unit", "raidpet"..i)

    Cell.unitButtons.arena["raidpet"..i] = arenaPetButtons[i]
end

-------------------------------------------------
-- update（团队框架布局更新逻辑区域）
-------------------------------------------------
-- 核心布局计算函数：根据布局方向、锚点、间距、尺寸计算所有必要的布局参数（锚点、间距、行列间距等）
function F.GetRaidFramePoints(layout)
    local orientation = layout["orientation"]
    local anchor = layout["anchor"]
    local spacingX = layout["spacingX"]
    local spacingY = layout["spacingY"]
    local width, height = unpack(layout["size"])

    local point, anchorPoint, groupAnchorPoint, unitSpacing, groupSpacing, unitSpacingX, unitSpacingY, verticalSpacing, horizontalSpacing, headerPoint, headerColumnAnchorPoint

    if orientation == "vertical" then
        if anchor == "BOTTOMLEFT" then
            point, anchorPoint, groupAnchorPoint = "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT"
            headerPoint, headerColumnAnchorPoint = "BOTTOM", "LEFT"
            unitSpacing = spacingY
            groupSpacing = spacingX
            unitSpacingX, unitSpacingY = spacingX, spacingY
            verticalSpacing = P.Scale(spacingY) + P.Scale(layout["groupSpacing"]) + P.Scale(height) * 5 + P.Scale(spacingY) * 4
        elseif anchor == "BOTTOMRIGHT" then
            point, anchorPoint, groupAnchorPoint = "BOTTOMRIGHT", "TOPRIGHT", "BOTTOMLEFT"
            headerPoint, headerColumnAnchorPoint = "BOTTOM", "RIGHT"
            unitSpacing = spacingY
            groupSpacing = -spacingX
            unitSpacingX, unitSpacingY = spacingX, spacingY
            verticalSpacing = P.Scale(spacingY) + P.Scale(layout["groupSpacing"]) + P.Scale(height) * 5 + P.Scale(spacingY) * 4
        elseif anchor == "TOPLEFT" then
            point, anchorPoint, groupAnchorPoint = "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT"
            headerPoint, headerColumnAnchorPoint = "TOP", "LEFT"
            unitSpacing = -spacingY
            groupSpacing = spacingX
            unitSpacingX, unitSpacingY = spacingX, -spacingY
            verticalSpacing = P.Scale(-layout["groupSpacing"]) + P.Scale(-height) * 5 + P.Scale(-spacingY) * 5
        elseif anchor == "TOPRIGHT" then
            point, anchorPoint, groupAnchorPoint = "TOPRIGHT", "BOTTOMRIGHT", "TOPLEFT"
            headerPoint, headerColumnAnchorPoint = "TOP", "RIGHT"
            unitSpacing = -spacingY
            groupSpacing = -spacingX
            unitSpacingX, unitSpacingY = spacingX, -spacingY
            verticalSpacing = P.Scale(-spacingY) + P.Scale(-layout["groupSpacing"]) + P.Scale(-height) * 5 + P.Scale(-spacingY) * 4
        end
    else
        if anchor == "BOTTOMLEFT" then
            point, anchorPoint, groupAnchorPoint = "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT"
            headerPoint, headerColumnAnchorPoint = "LEFT", "BOTTOM"
            unitSpacing = spacingX
            groupSpacing = spacingY
            unitSpacingX, unitSpacingY = spacingX, spacingY
            horizontalSpacing = P.Scale(spacingX) + P.Scale(layout["groupSpacing"]) + P.Scale(width) * 5 + P.Scale(spacingX) * 4
        elseif anchor == "BOTTOMRIGHT" then
            point, anchorPoint, groupAnchorPoint = "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT"
            headerPoint, headerColumnAnchorPoint = "RIGHT", "BOTTOM"
            unitSpacing = -spacingX
            groupSpacing = spacingY
            unitSpacingX, unitSpacingY = -spacingX, spacingY
            horizontalSpacing = P.Scale(-spacingX) + P.Scale(-layout["groupSpacing"]) + P.Scale(-width) * 5 + P.Scale(-spacingX) * 4
        elseif anchor == "TOPLEFT" then
            point, anchorPoint, groupAnchorPoint = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT"
            headerPoint, headerColumnAnchorPoint = "LEFT", "TOP"
            unitSpacing = spacingX
            groupSpacing = -spacingY
            unitSpacingX, unitSpacingY = spacingX, spacingY
            horizontalSpacing = P.Scale(spacingX) + P.Scale(layout["groupSpacing"]) + P.Scale(width) * 5 + P.Scale(spacingX) * 4
        elseif anchor == "TOPRIGHT" then
            point, anchorPoint, groupAnchorPoint = "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT"
            headerPoint, headerColumnAnchorPoint = "RIGHT", "TOP"
            unitSpacing = -spacingX
            groupSpacing = -spacingY
            unitSpacingX, unitSpacingY = -spacingX, spacingY
            horizontalSpacing = P.Scale(-spacingX) + P.Scale(-layout["groupSpacing"]) + P.Scale(-width) * 5 + P.Scale(-spacingX) * 4
        end
    end

    return point, anchorPoint, groupAnchorPoint, P.Scale(unitSpacing), P.Scale(groupSpacing), P.Scale(unitSpacingX), P.Scale(unitSpacingY), verticalSpacing, horizontalSpacing, headerPoint, headerColumnAnchorPoint
end

-- 根据当前是否为合并模式，动态切换 combinedHeader 和 separatedHeaders 的 showRaid 属性
-- 合并模式：只让 combinedHeader 显示团队成员；分离模式：只让 separatedHeaders 显示团队成员
local function UpdateHeadersShowRaidAttribute()
    if Cell.vars.currentLayoutTable["main"]["combineGroups"] then
        combinedHeader:SetAttribute("showRaid", true)
        for _, header in ipairs(separatedHeaders) do
            header:SetAttribute("showRaid", nil)
        end
    else
        combinedHeader:SetAttribute("showRaid", nil)
        for _, header in ipairs(separatedHeaders) do
            header:SetAttribute("showRaid", true)
        end
    end
end

-- 更新指定 header 中所有按钮的尺寸、方向、能量条大小
-- which 参数用于增量更新：nil=全部更新，否则只更新对应分类（header/main-size/main-power/groupFilter/barOrientation/powerFilter）
local function UpdateHeader(header, layout, which)
    if not which or which == "header" or which == "main-size" or which == "main-power" or which == "groupFilter" or which == "barOrientation" or which == "powerFilter" then
        local width, height = unpack(layout["main"]["size"])

        for _, b in ipairs(header) do
            if not which or which == "header" or which == "main-size" or which == "groupFilter" then
                P.Size(b, width, height)
                b:ClearAllPoints()
            end
            -- NOTE: SetOrientation BEFORE SetPowerSize
            if not which or which == "header" or which == "barOrientation" then
                B.SetOrientation(b, layout["barOrientation"][1], layout["barOrientation"][2])
            end
            if not which or which == "header" or which == "main-power" or which == "groupFilter" or which == "barOrientation" or which == "powerFilter" then
                B.SetPowerSize(b, layout["main"]["powerSize"])
            end
        end

        if not which or which == "header" or which == "main-size" or which == "groupFilter" then
            -- 确保按钮在“一定程度上”对齐
            header:SetAttribute("minWidth", P.Scale(width))
            header:SetAttribute("minHeight", P.Scale(height))

            P.Size(npcFrameAnchor, width, height) -- REVIEW: check same as main（确保 NPC 锚点尺寸与主按钮一致，待验证）
        end
    end

    -- REVIEW: fix name width（当 header 或 groupFilter 变更时，手动触发 healthBar 的 OnSizeChanged 以修正名字文本宽度）
    if which == "header" or which == "groupFilter" then
        for j, b in ipairs(header) do
            b.widgets.healthBar:GetScript("OnSizeChanged")(b.widgets.healthBar)
        end
        for k, arenaPet in ipairs(arenaPetButtons) do
            arenaPet.widgets.healthBar:GetScript("OnSizeChanged")(arenaPet.widgets.healthBar)
        end
    end
end

-- local function RemoveInitialAttribute(header)
--     header:SetAttribute("_initialAttribute-refreshUnitChange", nil)
-- end

-- local function SetInitialAttribute(header, relativeTo)
--     header:SetAttribute("_initialAttribute-refreshUnitChange", [[

--     ]])
-- end

-- 团队框架布局更新的核心入口函数，协调所有 header、宠物按钮、排序、可见性的更新
-- layout 参数：布局名称（字符串），which 参数：增量更新标识（nil=完全重建），按模块分类更新以优化性能
local function RaidFrame_UpdateLayout(layout, which)
    -- 可见性检查：非团队状态(party/solo)或用户主动隐藏(Cell.vars.isHidden)时，注销驱动并隐藏框架后直接返回
    -- visibility
    if Cell.vars.groupType ~= "raid" or Cell.vars.isHidden then
        UnregisterAttributeDriver(raidFrame, "state-visibility")
        raidFrame:Hide()
        return
    else
        RegisterAttributeDriver(raidFrame, "state-visibility", "show")
    end

    -- update
    layout = CellDB["layouts"][layout]

    -- 竞技场宠物可见性：仅在评级战场(inBattleground==5)且布局中启用宠物且宠物未分离时，注册状态驱动显示；否则隐藏
    -- arena pets
    if Cell.vars.inBattleground == 5 and layout["pet"]["partyEnabled"] and not layout["pet"]["partyDetached"] then
        for i, arenaPet in ipairs(arenaPetButtons) do
            RegisterAttributeDriver(arenaPet, "state-visibility", "[@raidpet"..i..", exists] show;hide")
        end
    else
        for i, arenaPet in ipairs(arenaPetButtons) do
            UnregisterAttributeDriver(arenaPet, "state-visibility")
            arenaPet:Hide()
        end
    end

    local point, anchorPoint, groupAnchorPoint, unitSpacing, groupSpacing, unitSpacingX, unitSpacingY, verticalSpacing, horizontalSpacing, headerPoint, headerColumnAnchorPoint = F.GetRaidFramePoints(layout["main"])

    -- 宠物按钮排列：当 which 为 nil（全量更新）或属于布局相关分类时才执行
    -- not which 模式：nil 表示全量重建，非 nil 时仅更新 which 指定的分类以减少不必要的重排
    if not which or which == "main-arrangement" or which == "pet-arrangement" or which == "rows_columns" or which == "groupSpacing" or which == "groupFilter" then
        local petSpacingX = layout["pet"]["sameArrangementAsMain"] and unitSpacingX or P.Scale(layout["pet"]["spacingX"])
        local petSpacingY = layout["pet"]["sameArrangementAsMain"] and unitSpacingY or P.Scale(layout["pet"]["spacingY"])

        -- arena pets（排列竞技场宠物按钮：从 npcFrameAnchor 开始，按方向依次附加）
        for k in ipairs(arenaPetButtons) do
            arenaPetButtons[k]:ClearAllPoints()
            if k == 1 then
                arenaPetButtons[k]:SetPoint(point, npcFrameAnchor)
            else
                if layout["main"]["orientation"] == "vertical" then
                    arenaPetButtons[k]:SetPoint(point, arenaPetButtons[k-1], anchorPoint, 0, petSpacingY)
                else
                    arenaPetButtons[k]:SetPoint(point, arenaPetButtons[k-1], anchorPoint, petSpacingX, 0)
                end
            end
        end
    end

    -- 收集当前布局中可见的小队编号（groupFilter[i]=true），同时预先更新所有可见小队的 header 样式
    local shownGroups = {}
    for i, isShown in ipairs(layout["groupFilter"]) do
        if isShown then
            UpdateHeader(separatedHeaders[i], layout, which)
            tinsert(shownGroups, i)
        end
    end

    if not which or which == "header" then
        UpdateHeadersShowRaidAttribute()
    end

    if layout["main"]["combineGroups"] then
        UpdateHeader(combinedHeader, layout, which)

        if not which or which == "header" or which == "main-arrangement" or which == "rows_columns" or which == "groupSpacing" or which == "unitsPerColumn" then
            combinedHeader:ClearAllPoints()

            if layout["main"]["orientation"] == "vertical" then
                combinedHeader:SetAttribute("columnAnchorPoint", headerColumnAnchorPoint)
                combinedHeader:SetAttribute("point", headerPoint)
                combinedHeader:SetAttribute("xOffset", 0)
                combinedHeader:SetAttribute("yOffset", unitSpacingY)
                combinedHeader:SetAttribute("columnSpacing", unitSpacingX)
                combinedHeader:SetAttribute("maxColumns", layout["main"]["maxColumns"])
            else
                combinedHeader:SetAttribute("columnAnchorPoint", headerColumnAnchorPoint)
                combinedHeader:SetAttribute("point", headerPoint)
                combinedHeader:SetAttribute("xOffset", unitSpacingX)
                combinedHeader:SetAttribute("yOffset", 0)
                combinedHeader:SetAttribute("columnSpacing", unitSpacingY)
                combinedHeader:SetAttribute("maxColumns", layout["main"]["maxColumns"])
            end

            --! force update unitbutton's point（强制清除所有按钮锚点，迫使 SecureGroupHeaders 重新计算位置）
            for _, b in ipairs(combinedHeader) do
                b:ClearAllPoints()
            end

            combinedHeader:SetAttribute("unitsPerColumn", layout["main"]["unitsPerColumn"])
            combinedHeader:SetPoint(point)

            raidFrame:SetAttribute("spacing", groupSpacing)
            raidFrame:SetAttribute("orientation", layout["main"]["orientation"])
            raidFrame:SetAttribute("anchor", layout["main"]["anchor"])
            raidFrame:SetAttribute("combineGroups", true) -- NOTE: 触发 _onattributechanged 事件，重新计算 npcFrameAnchor 位置
        end

        if not which or which == "header" or which == "sort" then
        -- 排序模式：按职责排序(sortByRole) -> NAME+ASSIGNEDROLE；否则 -> INDEX 默认排序
            if layout["main"]["sortByRole"] then
                combinedHeader:SetAttribute("sortMethod", "NAME")
                local order = table.concat(layout["main"]["roleOrder"], ",")..",NONE"
                combinedHeader:SetAttribute("groupingOrder", order)
                combinedHeader:SetAttribute("groupBy", "ASSIGNEDROLE")
            else
                combinedHeader:SetAttribute("sortMethod", "INDEX")
                combinedHeader:SetAttribute("groupingOrder", "")
                combinedHeader:SetAttribute("groupBy", nil)
            end
        end

        if not which or which == "header" or which == "groupFilter" then
            combinedHeader:SetAttribute("groupFilter", F.TableToString(shownGroups, ","))
        end

    else
        if not which or which == "header" or which == "main-arrangement" or which == "rows_columns" or which == "groupSpacing" or which == "groupFilter" then
            for i, group in ipairs(shownGroups) do
                local header = separatedHeaders[group]
                header:ClearAllPoints()

                if layout["main"]["orientation"] == "vertical" then
                    header:SetAttribute("columnAnchorPoint", headerColumnAnchorPoint)
                    header:SetAttribute("point", headerPoint)
                    header:SetAttribute("xOffset", 0)
                    header:SetAttribute("yOffset", unitSpacing)

                    --! force update unitbutton's point
                    for j = 1, 5 do
                        header[j]:ClearAllPoints()
                    end
                    header:SetAttribute("unitsPerColumn", 5)

                    if i == 1 then
                        header:SetPoint(point)
                    else
                        -- 按 maxColumns 计算当前 header 所在列：每行放 headersPerRow 个小队
                        local headersPerRow = layout["main"]["maxColumns"]
                        local headerCol = i % headersPerRow
                        headerCol = headerCol == 0 and headersPerRow or headerCol

                        if headerCol == 1 then -- first column on each row
                            header:SetPoint(point, separatedHeaders[shownGroups[i-headersPerRow]], 0, verticalSpacing)
                        else
                            header:SetPoint(point, separatedHeaders[shownGroups[i-1]], groupAnchorPoint, groupSpacing, 0)
                        end
                    end
                else
                    header:SetAttribute("columnAnchorPoint", headerColumnAnchorPoint)
                    header:SetAttribute("point", headerPoint)
                    header:SetAttribute("xOffset", unitSpacing)
                    header:SetAttribute("yOffset", 0)

                    --! force update unitbutton's point
                    for j = 1, 5 do
                        header[j]:ClearAllPoints()
                    end
                    header:SetAttribute("unitsPerColumn", 5)

                    if i == 1 then
                        header:SetPoint(point)
                    else
                        -- 按 maxColumns 计算当前 header 所在行：每列放 headersPerCol 个小队
                        local headersPerCol = layout["main"]["maxColumns"]
                        local headerRow = i % headersPerCol
                        headerRow = headerRow == 0 and headersPerCol or headerRow

                        if headerRow == 1 then -- first row on each column
                            header:SetPoint(point, separatedHeaders[shownGroups[i-headersPerCol]], point, horizontalSpacing, 0)
                        else
                            header:SetPoint(point, separatedHeaders[shownGroups[i-1]], groupAnchorPoint, 0, groupSpacing)
                        end
                    end
                end
            end

            raidFrame:SetAttribute("spacing", groupSpacing)
            raidFrame:SetAttribute("orientation", layout["main"]["orientation"])
            raidFrame:SetAttribute("anchor", layout["main"]["anchor"])
            raidFrame:SetAttribute("combineGroups", false) -- NOTE: 触发 _onattributechanged 事件，重新计算 npcFrameAnchor 位置
        end

        if not which or which == "header" or which == "sort" then
            if layout["main"]["sortByRole"] then
                for i = 1, 8 do
                    separatedHeaders[i]:SetAttribute("sortMethod", "NAME")
                    local order = table.concat(layout["main"]["roleOrder"], ",")..",NONE"
                    separatedHeaders[i]:SetAttribute("groupingOrder", order)
                    separatedHeaders[i]:SetAttribute("groupBy", "ASSIGNEDROLE")
                end
            else
                for i = 1, 8 do
                    separatedHeaders[i]:SetAttribute("sortMethod", "INDEX")
                    separatedHeaders[i]:SetAttribute("groupingOrder", "")
                    separatedHeaders[i]:SetAttribute("groupBy", nil)
                end
            end
        end

        -- show/hide groups（根据 layout.groupFilter 配置显示/隐藏各个小队 header）
        if not which or which == "header" or which == "groupFilter" then
            for i = 1, 8 do
                if layout["groupFilter"][i] then
                    separatedHeaders[i]:Show()
                else
                    separatedHeaders[i]:Hide()
                end
            end
        end
    end

    -- 竞技场宠物按钮尺寸更新：当 which 匹配 size/power 后缀、或 barOrientation、或 powerFilter 时才更新
    -- strfind 匹配模式：如 "main-size" 或 "pet-power" 等以 size/power 结尾的 which 值会触发宠物尺寸更新
    -- raid pets
    if not which or strfind(which, "size$") or strfind(which, "power$") or which == "barOrientation" or which == "powerFilter" then
        local width, height = unpack(layout["main"]["size"])

        for i, arenaPet in ipairs(arenaPetButtons) do
            -- NOTE: SetOrientation BEFORE SetPowerSize（必须先设置方向再设置能量条大小，顺序不可颠倒）
            B.SetOrientation(arenaPet, layout["barOrientation"][1], layout["barOrientation"][2])

            if layout["pet"]["sameSizeAsMain"] then
                P.Size(arenaPet, width, height)
                B.SetPowerSize(arenaPet, layout["main"]["powerSize"])
            else
                P.Size(arenaPet, layout["pet"]["size"][1], layout["pet"]["size"][2])
                B.SetPowerSize(arenaPet, layout["pet"]["powerSize"])
            end
        end
    end
end
Cell.RegisterCallback("UpdateLayout", "RaidFrame_UpdateLayout", RaidFrame_UpdateLayout) -- 注册 UpdateLayout 回调，当布局变更时 Cell 核心触发此函数

-- 以下为已弃用的独立可见性更新逻辑，已被 RaidFrame_UpdateLayout 中的内联可见性检查取代
-- local function RaidFrame_UpdateVisibility(which)
--     if not which or which == "raid" then
--         UpdateHeadersShowRaidAttribute()

--         if CellDB["general"]["showRaid"] then
--             RegisterAttributeDriver(raidFrame, "state-visibility", "show")
--         else
--             UnregisterAttributeDriver(raidFrame, "state-visibility")
--             raidFrame:Hide()
--         end
--     end
-- end
-- Cell.RegisterCallback("UpdateVisibility", "RaidFrame_UpdateVisibility", RaidFrame_UpdateVisibility)
