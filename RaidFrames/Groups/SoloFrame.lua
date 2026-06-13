-- Cell 框架引用：获取全局 Cell 表及常用子表
local _, Cell = ...
-- F: 通用工具函数集合（如 Debug 输出等）
local F = Cell.funcs
-- B: 按键/条相关函数集合（如 SetOrientation, SetPowerSize 等）
local B = Cell.bFuncs
-- P: 像素完美缩放函数集合
local P = Cell.pixelPerfectFuncs

-- 创建 SoloFrame —— 单人模式下的主容器框架
-- 使用 SecureFrameTemplate 作为安全模板，允许在战斗中安全地操作属性驱动（Midnight 安全机制：SecureStateDriver）
-- 父框架为 Cell 的主框架，置于其上层
local soloFrame = CreateFrame("Frame", "CellSoloFrame", Cell.frames.mainFrame, "SecureFrameTemplate")
Cell.frames.soloFrame = soloFrame
soloFrame:SetAllPoints(Cell.frames.mainFrame)

-- 创建玩家按钮 —— 使用 CellUnitButtonTemplate 安全模板
-- CellUnitButtonTemplate 继承自 SecureUnitButtonTemplate，在战斗中安全地处理 unit 属性设置
local playerButton = CreateFrame("Button", soloFrame:GetName().."Player", soloFrame, "CellUnitButtonTemplate")
-- playerButton.type = "main" -- layout setup
-- 通过安全属性设置 unit 为 "player"，Midnight 确保此设置在战斗中仍可安全执行
playerButton:SetAttribute("unit", "player")
playerButton:SetPoint("TOPLEFT")
playerButton:Show()
-- 注册到全局 unitButtons 表中的 solo 子表，供其他模块通过安全路径引用
Cell.unitButtons.solo["player"] = playerButton

-- 创建宠物按钮 —— 同样使用 CellUnitButtonTemplate 安全模板
-- petButton.type = "pet" -- layout setup
-- 通过安全属性设置 unit 为 "pet"，Midnight 防护确保战斗中安全设置
local petButton = CreateFrame("Button", soloFrame:GetName().."Pet", soloFrame, "CellUnitButtonTemplate")
petButton:SetAttribute("unit", "pet")
-- 注册到全局 unitButtons 表中的 solo 子表，供其他模块通过安全路径引用
Cell.unitButtons.solo["pet"] = petButton

-- ============================================================================
-- SoloFrame_UpdateLayout(layout, which)
-- 单人模式布局更新的核心函数
-- 参数:
--   layout - 布局名称字符串
--   which  - 可选，指定更新范围（如 "size", "barOrientation", "power", "pet" 等），nil 表示全部更新
--
-- 功能:
--   1. 可见性控制：根据队伍/团队状态决定是否显示 SoloFrame
--   2. 尺寸更新：玩家和宠物按钮的宽高
--   3. 条方向更新：血条/能量条的方向
--   4. 能量条尺寸更新
--   5. 宠物按钮锚点计算：根据主体方向（垂直/水平）和锚点位置计算宠物按钮位置
--   6. 宠物按钮可见性：根据是否有宠物/是否载具决定是否显示
--
-- Midnight/SecretValue 防护点:
--   - RegisterAttributeDriver / UnregisterAttributeDriver 是安全的状态驱动注册/注销 API，
--     通过条件宏（macro conditionals）控制框架可见性，在战斗中由 C 代码安全求值，
--     避免了 Lua 直接操作 Show/Hide 导致的安全污染（taint）问题。
--   - SetAttribute("unit", ...) 在按钮创建时已完成，Midnight 保护该属性在战斗中不被篡改。
-- ============================================================================
local function SoloFrame_UpdateLayout(layout, which)
    -- visibility — 可见性控制
    -- 仅在 solo 模式且未被隐藏时显示；否则注销安全状态驱动并隐藏框架
    if Cell.vars.groupType ~= "solo" or Cell.vars.isHidden then
        -- 注销安全属性驱动，避免残留的状态驱动影响后续操作（Midnight 防护：清除安全状态）
        UnregisterAttributeDriver(soloFrame, "state-visibility")
        soloFrame:Hide()
        return
    else
        -- 注册安全状态驱动：当存在 team1/party1/任意队伍时隐藏，否则显示
        -- 条件宏在战斗中由 C 代码安全求值，不会污染 Lua 环境（SecretValue 防护）
        RegisterAttributeDriver(soloFrame, "state-visibility", "[@raid1,exists] hide;[@party1,exists] hide;[group] hide;show")
    end

    -- update — 从配置数据库获取当前布局表
    -- CellDB["layouts"][layout] 是 SecretValue 保护的配置数据，读取安全但不可在战斗中篡改
    layout = CellDB["layouts"][layout]

    -- 尺寸更新：匹配 "size" 结尾的参数（如 "main-size", "pet-size"）
    if not which or strfind(which, "size$") then
        local width, height = unpack(layout["main"]["size"])
        P.Size(playerButton, width, height)
        if layout["pet"]["sameSizeAsMain"] then
            -- 宠物按钮与玩家按钮等大
            P.Size(petButton, width, height)
        else
            -- 宠物按钮使用独立尺寸配置
            P.Size(petButton, layout["pet"]["size"][1], layout["pet"]["size"][2])
        end
    end

    -- 条方向更新：必须在 SetPowerSize 之前设置方向，否则能量条尺寸计算可能出错
    -- NOTE: SetOrientation BEFORE SetPowerSize
    if not which or which == "barOrientation" then
        B.SetOrientation(playerButton, layout["barOrientation"][1], layout["barOrientation"][2])
        B.SetOrientation(petButton, layout["barOrientation"][1], layout["barOrientation"][2])
    end

    -- 能量条尺寸更新：触发条件包括 power 相关参数、条方向变化、能量过滤器变化
    if not which or strfind(which, "power$") or which == "barOrientation" or which == "powerFilter" then
        B.SetPowerSize(playerButton, layout["main"]["powerSize"])
        if layout["pet"]["sameSizeAsMain"] then
            B.SetPowerSize(petButton, layout["main"]["powerSize"])
        else
            B.SetPowerSize(petButton, layout["pet"]["powerSize"])
        end
    end

    -- 布局排列更新：处理 main-arrangement 或 pet-arrangement 时重新计算宠物按钮位置
    if not which or which == "main-arrangement" or which == "pet-arrangement" then
        -- 先清除所有锚点，避免残留锚点干扰新布局
        petButton:ClearAllPoints()
        if layout["main"]["orientation"] == "vertical" then
            -- ===== 垂直布局模式 =====
            -- anchor — 根据主体锚点计算宠物按钮的锚点位置和间距方向
            local point, anchorPoint
            -- 宠物间距：若宠物与主体排列方式相同则沿用主体 Y 间距，否则使用宠物独立 Y 间距
            local petSpacing = layout["pet"]["sameArrangementAsMain"] and layout["main"]["spacingY"] or layout["pet"]["spacingY"]

            if layout["main"]["anchor"] == "BOTTOMLEFT" then
                -- 左下锚定：宠物置于玩家上方
                point, anchorPoint = "BOTTOMLEFT", "TOPLEFT"
            elseif layout["main"]["anchor"] == "BOTTOMRIGHT" then
                -- 右下锚定：宠物置于玩家上方
                point, anchorPoint = "BOTTOMRIGHT", "TOPRIGHT"
            elseif layout["main"]["anchor"] == "TOPLEFT" then
                -- 左上锚定：宠物置于玩家下方（间距取反以向下偏移）
                point, anchorPoint = "TOPLEFT", "BOTTOMLEFT"
                petSpacing = -petSpacing
            elseif layout["main"]["anchor"] == "TOPRIGHT" then
                -- 右上锚定：宠物置于玩家下方（间距取反以向下偏移）
                point, anchorPoint = "TOPRIGHT", "BOTTOMRIGHT"
                petSpacing = -petSpacing
            end

            -- Y 方向偏移应用像素完美缩放
            petButton:SetPoint(point, playerButton, anchorPoint, 0, P.Scale(petSpacing))
        else
            -- ===== 水平布局模式 =====
            -- anchor — 根据主体锚点计算宠物按钮的锚点位置和间距方向
            local point, anchorPoint
            -- 宠物间距：若宠物与主体排列方式相同则沿用主体 X 间距，否则使用宠物独立 X 间距
            local petSpacing = layout["pet"]["sameArrangementAsMain"] and layout["main"]["spacingX"] or layout["pet"]["spacingX"]

            if layout["main"]["anchor"] == "BOTTOMLEFT" then
                -- 左下锚定：宠物置于玩家右侧
                point, anchorPoint = "BOTTOMLEFT", "BOTTOMRIGHT"
            elseif layout["main"]["anchor"] == "BOTTOMRIGHT" then
                -- 右下锚定：宠物置于玩家左侧（间距取反以向左偏移）
                point, anchorPoint = "BOTTOMRIGHT", "BOTTOMLEFT"
                petSpacing = -petSpacing
            elseif layout["main"]["anchor"] == "TOPLEFT" then
                -- 左上锚定：宠物置于玩家右侧
                point, anchorPoint = "TOPLEFT", "TOPRIGHT"
            elseif layout["main"]["anchor"] == "TOPRIGHT" then
                -- 右上锚定：宠物置于玩家左侧（间距取反以向左偏移）
                point, anchorPoint = "TOPRIGHT", "TOPLEFT"
                petSpacing = -petSpacing
            end

            -- X 方向偏移应用像素完美缩放
            petButton:SetPoint(point, playerButton, anchorPoint, P.Scale(petSpacing), 0)
        end
    end

    -- 宠物按钮独立可见性更新：仅在配置为 "pet" 范围更新时触发
    if not which or which == "pet" then
        if layout["pet"]["soloEnabled"] then
            -- 启用宠物显示：注册安全状态驱动
            -- [nopet] hide — 无宠物时隐藏
            -- [vehicleui] hide — 载具界面时隐藏（载具自身有独立框架）
            -- show — 其他情况显示
            -- 条件宏由 Midnight 安全求值，防止 taint
            RegisterAttributeDriver(petButton, "state-visibility", "[nopet] hide; [vehicleui] hide; show")
        else
            -- 禁用宠物显示：注销安全驱动并强制隐藏
            UnregisterAttributeDriver(petButton, "state-visibility")
            petButton:Hide()
        end
    end
end
-- 注册布局更新回调：当 Cell 触发 "UpdateLayout" 事件时调用 SoloFrame_UpdateLayout
-- Cell.RegisterCallback 是 Cell 框架的事件系统，通过回调注册机制实现模块间解耦通信
Cell.RegisterCallback("UpdateLayout", "SoloFrame_UpdateLayout", SoloFrame_UpdateLayout)

-- ============================================================================
-- 以下为已注释掉的旧版可见性更新函数（保留供参考）
-- 原功能：根据 CellDB["general"]["showSolo"] 配置控制 SoloFrame 的全局显隐
-- 已废弃原因：该逻辑已整合到 SoloFrame_UpdateLayout 函数的 visibility 部分，
--   通过 groupType 和 isHidden 联合判断，不再单独依赖 showSolo 开关
-- ============================================================================
-- local function SoloFrame_UpdateVisibility(which)
--     F.Debug("|cffff7fffUpdateVisibility:|r "..(which or "all"))

--     if not which or which == "solo" then
--         if CellDB["general"]["showSolo"] then
--             RegisterAttributeDriver(soloFrame, "state-visibility", "[@raid1,exists] hide;[@party1,exists] hide;[group] hide;show")
--         else
--             UnregisterAttributeDriver(soloFrame, "state-visibility")
--             soloFrame:Hide()
--         end
--     end
-- end
-- Cell.RegisterCallback("UpdateVisibility", "SoloFrame_UpdateVisibility", SoloFrame_UpdateVisibility)
