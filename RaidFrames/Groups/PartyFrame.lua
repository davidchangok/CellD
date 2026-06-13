-- 模块初始化：从 Cell 全局表中获取核心函数库的别名
-- F: 通用辅助函数（如 Safe* 安全运算函数）
-- B: 条形/布局相关函数（SetOrientation, SetPowerSize 等）
-- P: 像素完美缩放函数（确保 UI 在不同分辨率下清晰无模糊）
local _, Cell = ...
local F = Cell.funcs
local B = Cell.bFuncs
local P = Cell.pixelPerfectFuncs

-- 创建小队框架主容器
-- CellPartyFrame 是所有小队成员按钮的父框架，铺满 Cell 主框架的全部区域
-- 使用 SecureFrameTemplate 模板以支持战斗中安全的属性驱动操作
local partyFrame = CreateFrame("Frame", "CellPartyFrame", Cell.frames.mainFrame, "SecureFrameTemplate")
Cell.frames.partyFrame = partyFrame
partyFrame:SetAllPoints(Cell.frames.mainFrame)

-- 创建小队单位按钮头部管理器
-- SecureGroupHeaderTemplate 会自动根据属性配置生成和管理一组单位按钮
-- 每个单位按钮使用 CellUnitButtonTemplate 模板，包含血条、能量条等子元素
local header = CreateFrame("Frame", "CellPartyFrameHeader", partyFrame, "SecureGroupHeaderTemplate")
header:SetAttribute("template", "CellUnitButtonTemplate")

-- UpdateButtonUnit: 安全头部在单位变化时的回调函数
-- 由 SecureGroupHeaderTemplate 通过 CallMethod 在安全环境中调用
-- 参数：bName - 按钮的全局名称字符串，unit - 按钮当前对应的单位ID（如 "player", "party1"）
-- 功能：
--   1. 为 OmniCD 等外部插件提供全局按钮引用
--   2. 推导宠物单位ID（party1 → partypet1, player → pet）
--   3. 维护 unit→button 的双向映射表，供 IterateAllUnitButtons 等遍历使用
function header:UpdateButtonUnit(bName, unit)
    if not unit then return end

    _G[bName].unit = unit -- OmniCD: 将单位ID写入按钮的全局表中，供 OmniCD 插件读取以显示队友技能冷却

    -- 推导对应的宠物单位ID
    -- 玩家本人 → "pet"，队友 → 将 "party" 替换为 "partypet"
    local petUnit
    if unit == "player" then
        petUnit = "pet"
    else
        petUnit = string.gsub(unit, "party", "partypet")
    end
    -- 维护 unit→button 的映射表，使其他模块能通过单位ID快速查找按钮
    Cell.unitButtons.party.units[unit] = _G[bName]
    Cell.unitButtons.party.units[petUnit] = _G[bName].petButton
end

-- 备用的 initialConfigFunction（已注释）：在按钮首次创建时执行
-- 如果启用，会在按钮构造阶段设置初始宽高并注册单位监视
-- header:SetAttribute("initialConfigFunction", [[
--     RegisterUnitWatch(self)

--     local header = self:GetParent()
--     self:SetWidth(header:GetAttribute("buttonWidth") or 66)
--     self:SetHeight(header:GetAttribute("buttonHeight") or 46)
-- ]])

-- 注册需要初始化的属性名列表，使得 refreshUnitChange 属性在按钮创建时被初始化触发
header:SetAttribute("_initialAttributeNames", "refreshUnitChange")
-- _initialAttribute-refreshUnitChange: 安全环境下的单位刷新代码片段
-- 此代码在 SecureGroupHeaderTemplate 的安全执行环境中运行（Midnight/SecretValue 防护点）
-- 触发时机：按钮的单位属性变化或按钮首次创建时
-- 执行流程：
--   1. 获取当前按钮对应的单位ID
--   2. 获取宠物按钮的安全引用（通过 SecureHandlerSetFrameRef 注册）
--   3. 在宠物显示开启且非分离模式下，推导并设置宠物单位ID，注册宠物按钮的单位监视
--   4. 通过 CallMethod 回调到 Lua 层更新 unit→button 映射表
-- 注意：RegisterUnitWatch 是安全模板提供的函数，只能在安全代码片段中调用
header:SetAttribute("_initialAttribute-refreshUnitChange", [[
    local unit = self:GetAttribute("unit")
    local header = self:GetParent()
    local petButton = self:GetFrameRef("petButton")  -- 通过安全帧引用获取宠物按钮

    -- print(self:GetName(), unit, petButton)

    -- 仅在宠物显示开启且非分离模式下为宠物按钮设置单位
    -- partyDetached: 宠物与玩家按钮分离为独立按钮时，不在此处处理宠物
    if petButton and header:GetAttribute("showPartyPets") and not header:GetAttribute("partyDetached") then
        local petUnit
        if unit == "player" then
            petUnit = "pet"
        else
            petUnit = string.gsub(unit, "party", "partypet")
        end
        petButton:SetAttribute("unit", petUnit)  -- 安全地设置宠物单位ID
        RegisterUnitWatch(petButton)  -- 安全地注册宠物按钮的单位监视
    end

    -- 回调到 Lua 层：更新 unit→button 映射表（供非安全环境的代码使用）
    header:CallMethod("UpdateButtonUnit", self:GetName(), unit)
]])

-- 头部布局属性配置
-- point: 按钮的起始锚点，按钮从此位置开始依次排列
-- xOffset/yOffset: 按钮之间的间距（像素），通过 PixelPerfect 缩放以保证清晰度
-- maxColumns: 最大列数（1 表示单列排列）
-- unitsPerColumn: 每列最大单位数（5 人小队）
-- showPlayer/showParty: 控制是否显示玩家自身和小队队友
header:SetAttribute("point", "TOP")
header:SetAttribute("xOffset", 0)
header:SetAttribute("yOffset", -1)
header:SetAttribute("maxColumns", 1)
header:SetAttribute("unitsPerColumn", 5)
header:SetAttribute("showPlayer", true)
header:SetAttribute("showParty", true)

-- 技巧：通过临时设置 startingIndex 为 -4 再恢复为 1，欺骗 SecureGroupHeaders.lua 的
-- configureChildren 逻辑，使其计算出 needButtons == 5（始终创建 5 个按钮）
-- 这样即使队伍不满 5 人，框架也会预留 5 个按钮位置，避免按钮数量动态变化导致布局抖动
--! to make needButtons == 5 cheat configureChildren in SecureGroupHeaders.lua
header:SetAttribute("startingIndex", -4)
header:Show()  -- Show() 会触发 configureChildren，此时 needButtons 被计算为 5
header:SetAttribute("startingIndex", 1)  -- 恢复正常的起始索引

-- 初始化宠物按钮
-- 为头部中每个已创建的玩家按钮创建一个对应的宠物按钮（最多 5 个）
-- 宠物按钮与玩家按钮使用相同的 CellUnitButtonTemplate 模板
-- 宠物按钮默认忽略父框架透明度，确保宠物血条独立显示
-- toggleForVehicle 必须为 false，因为这些按钮仅用于宠物/载具显示
-- 通过 SecureHandlerSetFrameRef 建立安全帧引用，使安全代码片段能访问宠物按钮
-- 同时注册到 Cell.unitButtons.party 表中，供 IterateAllUnitButtons 等遍历
-- 为 OmniCD 插件设置全局名称引用（CellPartyFrameMember1..5）
-- init pet buttons
for i, playerButton in ipairs(header) do
    -- playerButton.type = "main" -- layout setup

    -- 创建宠物按钮：命名规则为 玩家按钮名+"Pet"，如 "CellPartyFrameMember1Pet"
    local petButton = CreateFrame("Button", playerButton:GetName().."Pet", playerButton, "CellUnitButtonTemplate")
    -- petButton.type = "pet" -- layout setup
    petButton:SetIgnoreParentAlpha(true)

    -- 关键：toggleForVehicle 必须为 false
    -- 此按钮仅用于显示宠物/载具的单位框架，不参与载具切换逻辑
    --! button for pet/vehicle only, toggleForVehicle MUST be false
    petButton:SetAttribute("toggleForVehicle", false)

    -- 将宠物按钮关联到玩家按钮上，建立双向引用
    playerButton.petButton = petButton
    -- 安全帧引用注册：使得安全代码片段（如 _initialAttribute-refreshUnitChange）能通过 GetFrameRef 获取宠物按钮
    SecureHandlerSetFrameRef(playerButton, "petButton", petButton)

    -- 注册到 unitButtons 表，键名为 "player1".."player5" 和 "pet1".."pet5"
    -- 供 Cell 内部遍历所有单位按钮时使用（如 IterateAllUnitButtons）
    -- for IterateAllUnitButtons
    Cell.unitButtons.party["player"..i] = playerButton
    Cell.unitButtons.party["pet"..i] = petButton

    -- 为 OmniCD 插件提供全局名称引用
    -- OmniCD 通过这些全局名称查找按钮以显示队友技能冷却信息
    -- OmniCD
    _G["CellPartyFrameMember"..i] = playerButton
end

-- PartyFrame_UpdateLayout: 小队框架布局更新的核心函数
-- 参数：
--   layout - 布局名称字符串（如 "default"），用于从 CellDB["layouts"] 中查找配置
--   which  - 可选，指定需要更新的具体方面（nil 表示全部更新）
--           可能的值："main-arrangement", "pet-arrangement", "size", "powerSize",
--           "barOrientation", "powerFilter", "pet", "sort", "hideSelf" 及其组合
-- 此函数通过 Cell.RegisterCallback("UpdateLayout", ...) 注册，由设置面板或初始化流程触发
local function PartyFrame_UpdateLayout(layout, which)
    -- 可见性控制
    -- 当队伍类型不是 party（如 raid、solo）或用户手动隐藏框架时，取消属性驱动并隐藏
    -- 否则通过安全属性驱动（AttributeDriver）实现战斗安全的显示/隐藏切换
    -- visibility
    if Cell.vars.groupType ~= "party" or Cell.vars.isHidden then
        UnregisterAttributeDriver(partyFrame, "state-visibility")
        partyFrame:Hide()
        return
    else
        -- 安全属性驱动规则：
        -- [@raid1,exists] hide    : 存在 raid1 单位时隐藏（在团队中不显示小队框架）
        -- [@party1,exists] show   : 存在 party1 单位时显示（有队友时显示）
        -- [group:party] show      : 群体状态为 party 时显示（预组队中仅自己一组但 party1 不存在时也能显示）
        -- hide                    : 默认隐藏
        RegisterAttributeDriver(partyFrame, "state-visibility", "[@raid1,exists] hide;[@party1,exists] show;[group:party] show;hide")
    end

    -- 从配置数据库中加载指定布局的完整设置
    -- CellDB["layouts"][layout] 包含 main 和 pet 两个子表，分别存储玩家和宠物的布局参数
    -- update
    layout = CellDB["layouts"][layout]

    -- 布局锚点和排列方向更新
    -- 仅在 which 为 nil（全量更新）或明确要求更新主/宠物排列时执行
    -- 根据 orientation（vertical/horizontal）和 anchor（四个角点）组合确定按钮增长方向和锚点
    -- 同时计算宠物按钮相对于玩家按钮的锚点位置和间距
    -- anchor
    if not which or which == "main-arrangement" or which == "pet-arrangement" then
        local orientation = layout["main"]["orientation"]  -- 排列方向："vertical" 纵向 / 其它 横向
        local anchor = layout["main"]["anchor"]  -- 锚点角：BOTTOMLEFT/BOTTOMRIGHT/TOPLEFT/TOPRIGHT
        local spacingX = layout["main"]["spacingX"]  -- 玩家按钮之间的水平间距
        local spacingY = layout["main"]["spacingY"]  -- 玩家按钮之间的垂直间距
        -- 宠物按钮间距：若宠物与主按钮使用相同排列设置则共享，否则使用宠物独立设置
        local petSpacingX = layout["pet"]["sameArrangementAsMain"] and spacingX or layout["pet"]["spacingX"]
        local petSpacingY = layout["pet"]["sameArrangementAsMain"] and spacingY or layout["pet"]["spacingY"]

        -- point: 按钮自身的锚点位置
        -- playerAnchorPoint: 按钮之间的相对锚点（决定下一个按钮放在哪个方向）
        -- petAnchorPoint: 宠物按钮相对于玩家按钮的锚点
        -- playerSpacing: 玩家按钮间距（带符号，负数表示反向增长）
        -- petSpacing: 宠物按钮间距（带符号）
        -- headerPoint: 头部排列方向属性
        local point, playerAnchorPoint, petAnchorPoint, playerSpacing, petSpacing, headerPoint
        if orientation == "vertical" then
            -- 纵向排列：按钮沿 Y 轴增长，宠物按钮放在玩家按钮的侧边
            if anchor == "BOTTOMLEFT" then
                point, playerAnchorPoint, petAnchorPoint = "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT"
                headerPoint = "BOTTOM"
                playerSpacing = spacingY
                petSpacing = petSpacingX
            elseif anchor == "BOTTOMRIGHT" then
                point, playerAnchorPoint, petAnchorPoint = "BOTTOMRIGHT", "TOPRIGHT", "BOTTOMLEFT"
                headerPoint = "BOTTOM"
                playerSpacing = spacingY
                petSpacing = -petSpacingX
            elseif anchor == "TOPLEFT" then
                point, playerAnchorPoint, petAnchorPoint = "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT"
                headerPoint = "TOP"
                playerSpacing = -spacingY
                petSpacing = petSpacingX
            elseif anchor == "TOPRIGHT" then
                point, playerAnchorPoint, petAnchorPoint = "TOPRIGHT", "BOTTOMRIGHT", "TOPLEFT"
                headerPoint = "TOP"
                playerSpacing = -spacingY
                petSpacing = -petSpacingX
            end

            header:SetAttribute("xOffset", 0)
            header:SetAttribute("yOffset", P.Scale(playerSpacing))
        else
            -- 横向排列：按钮沿 X 轴增长，宠物按钮放在玩家按钮的上方或下方
            -- anchor
            if anchor == "BOTTOMLEFT" then
                point, playerAnchorPoint, petAnchorPoint = "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT"
                headerPoint = "LEFT"
                playerSpacing = spacingX
                petSpacing = petSpacingY
            elseif anchor == "BOTTOMRIGHT" then
                point, playerAnchorPoint, petAnchorPoint = "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT"
                headerPoint = "RIGHT"
                playerSpacing = -spacingX
                petSpacing = petSpacingY
            elseif anchor == "TOPLEFT" then
                point, playerAnchorPoint, petAnchorPoint = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT"
                headerPoint = "LEFT"
                playerSpacing = spacingX
                petSpacing = -petSpacingY
            elseif anchor == "TOPRIGHT" then
                point, playerAnchorPoint, petAnchorPoint = "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT"
                headerPoint = "RIGHT"
                playerSpacing = -spacingX
                petSpacing = -petSpacingY
            end

            header:SetAttribute("xOffset", P.Scale(playerSpacing))
            header:SetAttribute("yOffset", 0)
        end

        -- 应用头部锚点
        header:ClearAllPoints()
        header:SetPoint(point)
        header:SetAttribute("point", headerPoint)

        -- 强制更新所有单位按钮（最多 5 个）的锚点位置
        -- SecureGroupHeaderTemplate 在布局变化时不会自动重新锚定已有按钮，
        -- 因此需要手动 ClearAllPoints 后重新设置按钮及其宠物按钮的锚点
        --! force update unitbutton's point
        for j = 1, 5 do
            header[j]:ClearAllPoints()
            -- 更新宠物按钮的锚点：宠物按钮相对于其玩家按钮定位
            -- update petButton's point
            header[j].petButton:ClearAllPoints()
            if orientation == "vertical" then
                header[j].petButton:SetPoint(point, header[j], petAnchorPoint, P.Scale(petSpacing), 0)
            else
                header[j].petButton:SetPoint(point, header[j], petAnchorPoint, 0, P.Scale(petSpacing))
            end
        end
        header:SetAttribute("unitsPerColumn", 5)  -- 每列固定 5 个单位
    end

    -- 按钮尺寸、能量条尺寸和条形方向更新
    -- 匹配条件：which 为 nil、以 "size" 结尾、含 "power"、barOrientation 或 powerFilter
    if not which or strfind(which, "size$") or strfind(which, "power$") or which == "barOrientation" or which == "powerFilter" then
        for i, playerButton in ipairs(header) do
            local petButton = playerButton.petButton

            -- 尺寸更新：设置玩家和宠物按钮的像素完美尺寸
            -- 同时更新 header 的 buttonWidth/buttonHeight 属性，确保新创建的按钮也使用正确尺寸
            if not which or strfind(which, "size$") then
                local width, height = unpack(layout["main"]["size"])
                P.Size(playerButton, width, height)  -- 像素完美设置玩家按钮尺寸
                header:SetAttribute("buttonWidth", P.Scale(width))
                header:SetAttribute("buttonHeight", P.Scale(height))
                if layout["pet"]["sameSizeAsMain"] then
                    P.Size(petButton, width, height)  -- 宠物按钮与玩家按钮同尺寸
                else
                    P.Size(petButton, layout["pet"]["size"][1], layout["pet"]["size"][2])
                end
            end

            -- 条形方向设置必须在 SetPowerSize 之前调用
            -- 因为 SetPowerSize 的布局计算依赖当前的方向设置
            -- NOTE: SetOrientation BEFORE SetPowerSize
            if not which or which == "barOrientation" then
                B.SetOrientation(playerButton, layout["barOrientation"][1], layout["barOrientation"][2])
                B.SetOrientation(petButton, layout["barOrientation"][1], layout["barOrientation"][2])
            end

            -- 能量条尺寸设置：控制法力/能量/怒气等资源条的显示大小
            -- 宠物按钮可以独立设置能量条尺寸，也可与玩家按钮保持一致
            if not which or strfind(which, "power$") or which == "barOrientation" or which == "powerFilter" then
                B.SetPowerSize(playerButton, layout["main"]["powerSize"])
                if layout["pet"]["sameSizeAsMain"] then
                    B.SetPowerSize(petButton, layout["main"]["powerSize"])
                else
                    B.SetPowerSize(petButton, layout["pet"]["powerSize"])
                end
            end
        end
    end

    -- 宠物框架更新
    -- showPartyPets: 是否启用小队宠物显示
    -- partyDetached: 宠物是否与玩家按钮分离为独立按钮
    -- 当启用且非分离模式时，注册宠物按钮的单位监视（在安全代码片段中处理）
    -- 否则取消监视并隐藏所有宠物按钮
    if not which or which == "pet" then
        header:SetAttribute("showPartyPets", layout["pet"]["partyEnabled"])
        header:SetAttribute("partyDetached", layout["pet"]["partyDetached"])
        if layout["pet"]["partyEnabled"] and not layout["pet"]["partyDetached"] then
            for i, playerButton in ipairs(header) do
                RegisterUnitWatch(playerButton.petButton)  -- 安全地注册宠物单位监视
            end
        else
            for i, playerButton in ipairs(header) do
                UnregisterUnitWatch(playerButton.petButton)  -- 安全地取消宠物单位监视
                playerButton.petButton:Hide()
            end
        end
    end

    -- 排序方式更新
    -- sortByRole: 按职责排序（坦克→治疗→输出→无职责），使用 ASSIGNEDROLE 分组
    -- 排序顺序由 roleOrder 配置指定（如 "TANK,HEALER,DAMAGER"），末尾追加 ",NONE" 处理无职责玩家
    -- 不按职责排序时使用 INDEX 排序（按队伍索引 party1..party4 原始顺序）
    if not which or which == "sort" then
        if layout["main"]["sortByRole"] then
            header:SetAttribute("sortMethod", "NAME")  -- 按名称排序作为次级排序
            local order = table.concat(layout["main"]["roleOrder"], ",")..",NONE"  -- 构建职责分组顺序
            header:SetAttribute("groupingOrder", order)
            header:SetAttribute("groupBy", "ASSIGNEDROLE")  -- 按分配的职责分组
        else
            header:SetAttribute("sortMethod", "INDEX")  -- 按队伍索引排序，保持原始顺序
            header:SetAttribute("groupingOrder", "")
            header:SetAttribute("groupBy", nil)
        end
    end

    -- 隐藏自身按钮设置
    -- hideSelf: 是否在框架中不显示玩家自己的按钮
    if not which or which == "hideSelf" then
        header:SetAttribute("showPlayer", not layout["main"]["hideSelf"])
    end
end
-- 注册布局更新回调：当设置面板或初始化流程触发 "UpdateLayout" 事件时，
-- 调用 PartyFrame_UpdateLayout 更新小队框架的布局
Cell.RegisterCallback("UpdateLayout", "PartyFrame_UpdateLayout", PartyFrame_UpdateLayout)

-- 已废弃的可见性控制函数（已合并到 PartyFrame_UpdateLayout 中）
-- 原先单独处理 showParty 设置和框架显示/隐藏，现在统一在 UpdateLayout 中管理
-- local function PartyFrame_UpdateVisibility(which)
--     if not which or which == "party" then
--         header:SetAttribute("showParty", CellDB["general"]["showParty"])
--         if CellDB["general"]["showParty"] then
--             --! [group] won't fire during combat
--             --! 注意：[group] 条件在战斗中不会触发状态变化，因此使用 [@party1,exists] 和 [group:party] 作为替代
--             -- RegisterAttributeDriver(partyFrame, "state-visibility", "[group:raid] hide; [group:party] show; hide")
--             -- NOTE: [group:party] show: 修复预组队中仅自己一队但 party1 不存在时框架不显示的问题
--             -- NOTE: [group:party] show: fix for premade, only player in party, but party1 not exists
--             RegisterAttributeDriver(partyFrame, "state-visibility", "[@raid1,exists] hide;[@party1,exists] show;[group:party] show;hide")
--         else
--             UnregisterAttributeDriver(partyFrame, "state-visibility")
--             partyFrame:Hide()
--         end
--     end
-- end
-- Cell.RegisterCallback("UpdateVisibility", "PartyFrame_UpdateVisibility", PartyFrame_UpdateVisibility)

-- 测试/调试代码（已注释）：用于验证安全状态驱动的工作机制
-- 通过属性驱动和状态驱动两种方式检测队伍类型（raid/party/solo）的变化
-- local f = CreateFrame("Frame", nil, CellParent, "SecureFrameTemplate")
-- RegisterAttributeDriver(f, "state-group", "[@raid1,exists] raid;[@party1,exists] party; solo")
-- SecureHandlerWrapScript(f, "OnAttributeChanged", f, [[
--     print(name, value)
--     if name ~= "state-group" then return end
-- ]])

-- RegisterStateDriver(f, "groupstate", "[group:raid] raid; [group:party] party; solo")
-- f:SetAttribute("_onstate-groupstate", [[
--     print(stateid, newstate)
-- ]])
