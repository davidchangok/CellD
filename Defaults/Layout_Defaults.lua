local addonName, Cell = ...

-- ============================================================================
-- 布局默认配置 (Layout Defaults)
-- 本文件定义所有布局相关的默认值，包括：
--   1. 内置指示器索引映射 (indicatorIndices)
--   2. 各子布局设置 (main / pet / npc / spotlight)
--   3. 全局布局选项 (barOrientation / groupFilter / powerFilters)
--   4. 30 个内置指示器的完整默认配置 (indicators)
--   5. 布局自动切换配置 (layoutAutoSwitch)
-- 注意：本文件为纯数据文件，不含函数逻辑、事件处理或 Midnight/SecretValue 敏感值。
-- ============================================================================

-- number of built-in indicators
-- 内置指示器总数（与 indicatorIndices 和 indicators 数组条目数一致，当前为 30）
Cell.defaults.builtIns = 30

-- ============================================================================
-- 内置指示器名称到索引的映射表
-- 用于在代码中通过 indicatorName 快速查找对应指示器在 indicators 数组中的位置
-- 索引 1-30 与 Cell.defaults.layout.indicators 数组一一对应
-- ============================================================================
Cell.defaults.indicatorIndices = {
    ["nameText"] = 1,           -- 姓名文字
    ["statusText"] = 2,         -- 状态文字
    ["healthText"] = 3,         -- 生命值文字
    ["powerText"] = 4,          -- 能量文字
    ["healthThresholds"] = 5,   -- 血量阈值
    ["statusIcon"] = 6,         -- 状态图标
    ["roleIcon"] = 7,           -- 职责图标
    ["leaderIcon"] = 8,         -- 队长图标
    ["combatIcon"] = 9,         -- 战斗图标
    ["readyCheckIcon"] = 10,    -- 准备检查图标
    ["playerRaidIcon"] = 11,    -- 团队图标（玩家自身）
    ["targetRaidIcon"] = 12,    -- 团队图标（目标）
    ["aggroBlink"] = 13,        -- 仇恨闪烁
    ["aggroBar"] = 14,          -- 仇恨条
    ["aggroBorder"] = 15,       -- 仇恨边框
    ["shieldBar"] = 16,         -- 护盾条
    ["aoeHealing"] = 17,        -- 范围治疗
    ["externalCooldowns"] = 18, -- 外部冷却
    ["defensiveCooldowns"] = 19,-- 个人减伤冷却
    ["allCooldowns"] = 20,      -- 全部冷却（外部+个人）
    ["tankActiveMitigation"] = 21, -- 坦克主动减伤
    ["dispels"] = 22,           -- 驱散
    ["debuffs"] = 23,           -- 负面效果
    ["raidDebuffs"] = 24,       -- 团队负面效果
    ["privateAuras"] = 25,      -- 私有光环
    ["targetedSpells"] = 26,    -- 目标法术
    ["targetCounter"] = 27,     -- 目标计数
    ["crowdControls"] = 28,     -- 控制效果
    ["actions"] = 29,           -- 动作（点击施法）
    ["missingBuffs"] = 30,      -- 缺失增益
}

-- ============================================================================
-- 布局配置表
-- 包含所有子布局（main / pet / npc / spotlight）以及全局布局选项
-- 每个子布局共享以下通用字段（各子布局可覆盖）：
--   size: 框体尺寸 {宽, 高}
--   position: 布局锚点位置 {}
--   powerSize: 能量条高度
--   orientation: 排列方向 "vertical"=垂直 / "horizontal"=水平
--   anchor: 锚点方向
--   spacingX/Y: 单位之间的水平和垂直间距
-- ============================================================================
Cell.defaults.layout = {
    -- ["syncWith"] = "layoutName", -- 可选项：与此布局同步设置
    -- --------------------------------------------------------------------------
    -- 主布局 (main)
    -- 玩家单位框体的默认布局，所有自定义布局均从此派生
    -- --------------------------------------------------------------------------
    ["main"] = {
        ["combineGroups"] = false,   -- 是否合并不同小队显示（忽略小队边界）
        ["sortByRole"] = false,      -- 是否按职责排序（坦克→治疗→输出）
        ["roleOrder"] = {"TANK", "HEALER", "DAMAGER"}, -- 职责排序顺序
        ["hideSelf"] = false,        -- 是否隐藏自己的框体
        ["size"] = {66, 46},         -- 框体尺寸 {宽, 高}
        ["position"] = {},           -- 布局锚点位置（空表示默认位置）
        ["powerSize"] = 2,           -- 能量条高度
        ["orientation"] = "vertical",-- 排列方向 "vertical"=垂直列 / "horizontal"=水平行
        ["anchor"] = "TOPLEFT",      -- 布局锚点方向
        ["spacingX"] = 3,            -- 单位之间水平间距
        ["spacingY"] = 3,            -- 单位之间垂直间距
        ["maxColumns"] = 8,          -- 最大列数（每行最多单位数）
        ["unitsPerColumn"] = 5,      -- 每列单位数（垂直排列时每列显示的单位数）
        ["groupSpacing"] = 0,        -- 不同小队之间的额外间距
    },
    -- --------------------------------------------------------------------------
    -- 宠物布局 (pet)
    -- 宠物/召唤物单位的框体设置，可独立于主布局显示
    -- --------------------------------------------------------------------------
    ["pet"] = {
        ["soloEnabled"] = true,          -- 单人时显示宠物框体
        ["partyEnabled"] = true,         -- 小队时显示宠物框体
        ["partyDetached"] = false,       -- 小队时宠物框体是否脱离主人独立排列
        ["raidEnabled"] = false,         -- 团队时显示宠物框体（默认隐藏以减少屏幕占用）
        ["sameSizeAsMain"] = true,       -- 是否与主布局使用相同尺寸
        ["sameArrangementAsMain"] = true,-- 是否与主布局使用相同排列方式
        ["size"] = {66, 46},
        ["position"] = {},
        ["powerSize"] = 2,
        ["orientation"] = "vertical",
        ["anchor"] = "TOPLEFT",
        ["spacingX"] = 3,
        ["spacingY"] = 3,
    },
    -- --------------------------------------------------------------------------
    -- NPC 布局 (npc)
    -- 友方 NPC / 载具单位的框体设置
    -- --------------------------------------------------------------------------
    ["npc"] = {
        ["enabled"] = true,              -- 是否启用 NPC 框体
        ["separate"] = false,            -- 是否与玩家框体分离显示（true=独立排列）
        ["sameSizeAsMain"] = true,
        ["sameArrangementAsMain"] = true,
        ["size"] = {66, 46},
        ["position"] = {},
        ["powerSize"] = 2,
        ["orientation"] = "vertical",
        ["anchor"] = "TOPLEFT",
        ["spacingX"] = 3,
        ["spacingY"] = 3,
    },
    -- --------------------------------------------------------------------------
    -- 聚焦布局 (spotlight)
    -- 自定义聚焦单位框体，用于突出显示特定单位（如坦克、首领目标、重要 NPC）
    -- units 字段定义需要聚焦监视的单位列表
    -- --------------------------------------------------------------------------
    ["spotlight"] = {
        ["enabled"] = false,             -- 是否启用聚焦框体
        ["hidePlaceholder"] = false,     -- 是否隐藏占位框体（仅在有聚焦单位时显示）
        ["units"] = {},                  -- 需要聚焦监视的单位 GUID 或名称列表
        ["sameSizeAsMain"] = true,
        ["sameArrangementAsMain"] = true,
        ["size"] = {66, 46},
        ["position"] = {},
        ["powerSize"] = 2,
        ["orientation"] = "vertical",
        ["anchor"] = "TOPLEFT",
        ["spacingX"] = 3,
        ["spacingY"] = 3,
    },
    -- 旧版注释保留（向后兼容参考，实际数据结构已升级为键值对格式）
    -- ["npc"] = {true, false, {}, false, {66, 46}}, -- npcEnabled, separateNpc, position, sizeEnabled, size
    -- ["pet"] = {true, false, {}, false, {66, 46}}, -- partyPetsEnabled, raidPetsEnabled, raidPetsPosition, sizeEnabled, size
    -- ["spotlight"] = {false, {}, {}, false, {66, 46}}, -- enabled, units, position, sizeEnabled, size

    -- --------------------------------------------------------------------------
    -- 全局血条方向
    -- 格式: {方向, 是否反转}
    -- 方向: "horizontal"=水平 / "vertical"=垂直
    -- 是否反转: false=从左到右(上到下) / true=从右到左(下到上)
    -- --------------------------------------------------------------------------
    ["barOrientation"] = {"horizontal", false},

    -- --------------------------------------------------------------------------
    -- 小队显示过滤
    -- 8 个布尔值分别控制第 1 至第 8 小队的显示/隐藏
    -- true=显示该小队 / false=隐藏该小队
    -- --------------------------------------------------------------------------
    ["groupFilter"] = {true, true, true, true, true, true, true, true},

    -- --------------------------------------------------------------------------
    -- 能量条显示过滤（按职业和专精）
    -- 控制各职业/专精是否显示能量条（法力条/怒气条/能量条等）
    -- 值为 true 或 {专精=true} 表示显示能量条
    -- PET/VEHICLE/NPC 为特殊分类条目
    -- Midnight 安全提醒：此表仅包含显示选项，不包含任何敏感值或 SecretValue
    -- --------------------------------------------------------------------------
    ["powerFilters"] = {
        ["DEATHKNIGHT"] = {["TANK"] = true, ["DAMAGER"] = true},
        ["DEMONHUNTER"] = {["TANK"] = true, ["DAMAGER"] = true},
        ["DRUID"] = {["TANK"] = true, ["DAMAGER"] = true, ["HEALER"] = true},
        ["EVOKER"] = {["DAMAGER"] = true, ["HEALER"] = true},
        ["HUNTER"] = true,
        ["MAGE"] = true,
        ["MONK"] = {["TANK"] = true, ["DAMAGER"] = true, ["HEALER"] = true},
        ["PALADIN"] = {["TANK"] = true, ["DAMAGER"] = true, ["HEALER"] = true},
        ["PRIEST"] = {["DAMAGER"] = true, ["HEALER"] = true},
        ["ROGUE"] = true,
        ["SHAMAN"] = {["DAMAGER"] = true, ["HEALER"] = true},
        ["WARLOCK"] = true,
        ["WARRIOR"] = {["TANK"] = true, ["DAMAGER"] = true},
        ["PET"] = true,
        ["VEHICLE"] = true,
        ["NPC"] = true,
    },
    -- ============================================================================
    -- 内置指示器配置表 (indicators)
    -- 共 30 个内置指示器，构成 Cell 单元框体的核心视觉元素
    --
    -- 通用字段说明（所有指示器共有）：
    --   name: 用户界面显示名称
    --   indicatorName: 内部标识名（与 indicatorIndices 的键一一对应）
    --   type: 指示器类型，"built-in"=内置 / "custom"=自定义
    --   enabled: 是否启用此指示器
    --   position: 位置锚点 {自身锚点, 相对框体, 相对锚点, x偏移, y偏移}
    --             相对框体可为 "button"（主按钮）、"healthBar"（血条）等
    --   frameLevel: 渲染层级，数值越大越靠前显示
    --
    -- 各指示器的专属字段在下文各自的注释中说明
    -- ============================================================================
    ["indicators"] = {
        -- ======================================================================
        -- 1. 姓名文字 (Name Text)
        -- 显示单位名称，支持自定义字体、颜色、文字宽度
        -- ======================================================================
        {
            ["name"] = "Name Text",
            ["indicatorName"] = "nameText",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"CENTER", "healthBar", "CENTER", 0, 0}, -- 血条中央
            ["frameLevel"] = 1,
            ["font"] = {"Cell ".._G.DEFAULT, 13, "None", true}, -- 字体配置：{字体名, 大小, 描边样式, 是否等宽}
            ["color"] = {"custom_color", {1, 1, 1}}, -- 颜色：{"custom_color"|"class_color", {R,G,B}}
            ["vehicleNamePosition"] = {"TOP", 0}, -- 载具时名称显示位置偏移
            ["textWidth"] = {"percentage", 0.75}, -- 文字最大宽度：{"percentage"|"pixel", 值}
            ["showGroupNumber"] = false, -- 是否在小队号显示（如"[1] 玩家名"）
        }, -- 1
        -- ======================================================================
        -- 2. 状态文字 (Status Text)
        -- 显示单位特殊状态：AFK、离线、死亡、幽灵、假死、饮水、准备检查等
        -- ======================================================================
        {
            ["name"] = "Status Text",
            ["indicatorName"] = "statusText",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"BOTTOM", 0, "justify"}, -- 底部居中对齐，"justify" 表示自适应水平对齐
            ["frameLevel"] = 30, -- 较高层级确保状态文字覆盖在其它元素之上
            ["font"] = {"Cell ".._G.DEFAULT, 11, "None", true},
            ["showTimer"] = true,        -- 显示 AFK 计时器
            ["showBackground"] = true,   -- 显示状态背景条
            ["colors"] = {               -- 各状态的自定义颜色
                ["AFK"] = {1, 0.19, 0.19, 1},       -- 暂离：红色
                ["OFFLINE"] = {1, 0.19, 0.19, 1},    -- 离线：红色
                ["DEAD"] = {1, 0.19, 0.19, 1},       -- 死亡：红色
                ["GHOST"] = {1, 0.19, 0.19, 1},      -- 幽灵：红色
                ["FEIGN"] = {1, 1, 0.12, 1},         -- 假死：黄色
                ["DRINKING"] = {0.12, 0.75, 1, 1},   -- 饮水：蓝色
                ["PENDING"] = {1, 1, 0.12, 1},       -- 准备检查待确认：黄色
                ["ACCEPTED"] = {0.12, 1, 0.12, 1},   -- 准备检查已确认：绿色
                ["DECLINED"] = {1, 0.19, 0.19, 1},   -- 准备检查拒绝：红色
            },
        }, -- 2
        -- ======================================================================
        -- 3. 生命值文字 (Health Text)
        -- 显示血量信息，支持多段格式化（百分比、数值、护盾、治疗吸收）
        -- ======================================================================
        {
            ["name"] = "Health Text",
            ["indicatorName"] = "healthText",
            ["type"] = "built-in",
            ["enabled"] = false, -- 默认关闭（大多数治疗职业通过血量条颜色判断）
            ["position"] = {"TOP", "button", "CENTER", 0, -6}, -- 血条上方居中
            ["frameLevel"] = 2,
            ["font"] = {"Cell ".._G.DEFAULT, 10, "None", true},
            ["format"] = {                -- 多段格式化配置（按显示顺序拼接）
                ["health1"] = {           -- 第一段：血量
                    ["format"] = "effective_percent", -- 格式："effective_percent"=有效血量百分比 / "deficit"=损失血量 / "number"=数值
                    ["color"] = {"custom_color", {1, 1, 1}},
                    ["hideIfEmptyOrFull"] = false, -- 满血或空血时是否隐藏此段
                },
                ["health2"] = {           -- 第二段：附加血量（默认不显示）
                    ["format"] = "none",  -- "none" 表示不显示
                    ["color"] = {"custom_color", {1, 1, 1}},
                    ["hideIfEmptyOrFull"] = false,
                    ["delimiter"] = " ",  -- 与前一段的分隔符
                },
                ["shields"] = {           -- 护盾段：显示护盾吸收量
                    ["format"] = "none",
                    ["color"] = {"custom_color", {0, 1, 0}}, -- 护盾用绿色
                    ["delimiter"] = "+",  -- 护盾前缀 "+"
                },
                ["healAbsorbs"] = {       -- 治疗吸收段：显示治疗吸收量
                    ["format"] = "none",
                    ["color"] = {"custom_color", {1, 0, 0}}, -- 治疗吸收用红色
                    ["delimiter"] = "-",  -- 治疗吸收前缀 "-"
                },
            },
        }, -- 3
        -- ======================================================================
        -- 4. 能量文字 (Power Text)
        -- 显示能量值（法力/怒气/能量/集中值等），可按职业/专精过滤
        -- ======================================================================
        {
            ["name"] = "Power Text",
            ["indicatorName"] = "powerText",
            ["type"] = "built-in",
            ["enabled"] = false,
            ["position"] = {"BOTTOMRIGHT", "button", "BOTTOMRIGHT", 0, 3},
            ["frameLevel"] = 2,
            ["font"] = {"Cell ".._G.DEFAULT, 10, "None", true},
            ["color"] = {"custom_color", {1, 1, 1}},
            ["format"] = "number",           -- 格式："number"=数值 / "percent"=百分比
            ["hideIfEmptyOrFull"] = true,    -- 能量满或空时隐藏
            ["filters"] = {                  -- 按职业/专精过滤显示（与 powerFilters 结构一致）
                ["DEATHKNIGHT"] = {["TANK"] = true, ["DAMAGER"] = true},
                ["DEMONHUNTER"] = {["TANK"] = true, ["DAMAGER"] = true},
                ["DRUID"] = {["TANK"] = true, ["DAMAGER"] = true, ["HEALER"] = true},
                ["EVOKER"] = {["DAMAGER"] = true, ["HEALER"] = true},
                ["HUNTER"] = true,
                ["MAGE"] = true,
                ["MONK"] = {["TANK"] = true, ["DAMAGER"] = true, ["HEALER"] = true},
                ["PALADIN"] = {["TANK"] = true, ["DAMAGER"] = true, ["HEALER"] = true},
                ["PRIEST"] = {["DAMAGER"] = true, ["HEALER"] = true},
                ["ROGUE"] = true,
                ["SHAMAN"] = {["DAMAGER"] = true, ["HEALER"] = true},
                ["WARLOCK"] = true,
                ["WARRIOR"] = {["TANK"] = true, ["DAMAGER"] = true},
                ["PET"] = true,
                ["VEHICLE"] = true,
                ["NPC"] = true,
            },
        }, -- 4
        -- ======================================================================
        -- 5. 血量阈值 (Health Thresholds)
        -- 根据血量百分比显示边框颜色变化，用于血量预警
        -- ======================================================================
        {
            ["name"] = "Health Thresholds",
            ["indicatorName"] = "healthThresholds",
            ["type"] = "built-in",
            ["enabled"] = false,
            ["thickness"] = 1,              -- 边框粗细
            ["thresholds"] = {              -- 阈值列表（按数值降序排列）
                {0.35, {1, 0, 0, 1}},      -- 血量低于 35% 时显示红色边框
                -- 可添加更多阈值，如 {0.50, {1, 1, 0, 1}} 表示低于50%黄色
            },
        }, -- 5
        -- ======================================================================
        -- 6. 状态图标 (Status Icon)
        -- 显示单位状态图标：战斗、休息、PvP 标记、相位等
        -- ======================================================================
        {
            ["name"] = "Status Icon",
            ["indicatorName"] = "statusIcon",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"TOP", "button", "TOP", 0, -3}, -- 框体顶部居中偏下
            ["frameLevel"] = 10,
            ["size"] = {18, 18},            -- 图标尺寸
        }, -- 6
        -- ======================================================================
        -- 7. 职责图标 (Role Icon)
        -- 显示团队职责图标：坦克/治疗/输出
        -- ======================================================================
        {
            ["name"] = "Role Icon",
            ["indicatorName"] = "roleIcon",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["hideDamager"] = false,        -- 是否隐藏输出职责图标（仅显示坦/奶）
            ["position"] = {"TOPLEFT", "button", "TOPLEFT", 0, 0}, -- 左上角
            ["size"] = {11, 11},
            ["roleTexture"] = {             -- 职责图标纹理路径
                "default",                  -- 默认（使用 Cell 内置图标）
                "Interface\\AddOns\\ElvUI\\Core\\Media\\Textures\\Tank.tga",    -- 坦克图标
                "Interface\\AddOns\\ElvUI\\Core\\Media\\Textures\\Healer.tga",  -- 治疗图标
                "Interface\\AddOns\\ElvUI\\Core\\Media\\Textures\\DPS.tga",     -- 输出图标
            },
            ["frameLevel"] = 5,
        }, -- 7
        -- ======================================================================
        -- 8. 队长图标 (Leader Icon)
        -- 显示团队领袖/助理标记
        -- ======================================================================
        {
            ["name"] = "Leader Icon",
            ["indicatorName"] = "leaderIcon",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["hideInCombat"] = true,        -- 战斗中隐藏（减少视觉干扰）
            ["position"] = {"TOPLEFT", "button", "TOPLEFT", 1, -10},
            ["size"] = {11, 11},
        }, -- 8
        -- ======================================================================
        -- 9. 战斗图标 (Combat Icon)
        -- 显示战斗状态图标（进入/脱离战斗）
        -- ======================================================================
        {
            ["name"] = "Combat Icon",
            ["indicatorName"] = "combatIcon",
            ["type"] = "built-in",
            ["enabled"] = false,
            ["position"] = {"BOTTOMRIGHT", "button", "BOTTOMRIGHT", 4, -4},
            ["frameLevel"] = 5,
            ["size"] = {16, 16},
            ["onlyEnableNotInCombat"] = true, -- 仅在非战斗状态显示（提醒未进战斗）
        }, -- 9
        -- ======================================================================
        -- 10. 准备检查图标 (Ready Check Icon)
        -- 显示团队准备检查结果图标（已确认/待确认/拒绝）
        -- ======================================================================
        {
            ["name"] = "Ready Check Icon",
            ["indicatorName"] = "readyCheckIcon",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"CENTER", "button", "CENTER", 0, 0}, -- 框体中央
            ["frameLevel"] = 100,           -- 最高层级，确保准备检查结果清晰可见
            ["size"] = {16, 16},
        }, -- 10
        -- ======================================================================
        -- 11. 团队图标 - 玩家自身 (Raid Icon - player)
        -- 显示玩家自身被标记的团队图标（星星/大饼/钻石等）
        -- ======================================================================
        {
            ["name"] = "Raid Icon (player)",
            ["indicatorName"] = "playerRaidIcon",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"TOP", "button", "TOP", 0, 3}, -- 框体顶部上方
            ["frameLevel"] = 5,
            ["size"] = {14, 14},
            ["alpha"] = 0.77,              -- 半透明，避免遮挡其它元素
        }, -- 11
        -- ======================================================================
        -- 12. 团队图标 - 目标 (Raid Icon - target)
        -- 显示当前目标被标记的团队图标
        -- ======================================================================
        {
            ["name"] = "Raid Icon (target)",
            ["indicatorName"] = "targetRaidIcon",
            ["type"] = "built-in",
            ["enabled"] = false,           -- 默认关闭
            ["position"] = {"TOP", "button", "TOP", -14, 3}, -- 玩家图标左侧偏移
            ["frameLevel"] = 5,
            ["size"] = {14, 14},
            ["alpha"] = 0.77,
        }, -- 12
        -- ======================================================================
        -- 13. 仇恨闪烁 (Aggro Blink)
        -- 获得仇恨时在框体左上角显示红色闪烁警告
        -- ======================================================================
        {
            ["name"] = "Aggro (blink)",
            ["indicatorName"] = "aggroBlink",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"TOPLEFT", "button", "TOPLEFT", 0, 0},
            ["frameLevel"] = 7,
            ["size"] = {11, 11},
        }, -- 13
        -- ======================================================================
        -- 14. 仇恨条 (Aggro Bar)
        -- 显示仇恨百分比进度条，直观展示当前仇恨值占目标仇恨的比例
        -- ======================================================================
        {
            ["name"] = "Aggro (bar)",
            ["indicatorName"] = "aggroBar",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"BOTTOMLEFT", "button", "TOPLEFT", 0, -1}, -- 框体左上方
            ["frameLevel"] = 1,
            ["size"] = {20, 4},            -- 宽20高4的小型条
        }, -- 14
        -- ======================================================================
        -- 15. 仇恨边框 (Aggro Border)
        -- 获得仇恨时高亮整个框体边框
        -- ======================================================================
        {
            ["name"] = "Aggro (border)",
            ["indicatorName"] = "aggroBorder",
            ["type"] = "built-in",
            ["enabled"] = false,           -- 默认关闭（避免与闪烁/仇恨条重复）
            ["frameLevel"] = 3,
            ["thickness"] = 2,             -- 边框粗细
        }, -- 15
        -- ======================================================================
        -- 16. 护盾条 (Shield Bar)
        -- 显示护盾吸收量（如戒律牧的盾、真言术：障等），以覆盖条形式展示
        -- ======================================================================
        {
            ["name"] = "Shield Bar",
            ["indicatorName"] = "shieldBar",
            ["type"] = "built-in",
            ["enabled"] = false,
            ["position"] = {"BOTTOMLEFT", nil, "BOTTOMLEFT", 0, 0}, -- nil 表示覆盖整个血条
            ["frameLevel"] = 5,
            ["height"] = 4,                -- 护盾条高度
            ["color"] = {1, 1, 0, 1},     -- 护盾条颜色：黄色
            ["onlyShowOvershields"] = false, -- 仅显示过量护盾（超过血量上限的护盾部分）
        }, -- 16
        -- ======================================================================
        -- 17. 范围治疗 (AoE Healing)
        -- 显示群体治疗技能的预估治疗量指示条
        -- ======================================================================
        {
            ["name"] = "AoE Healing",
            ["indicatorName"] = "aoeHealing",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["height"] = 10,               -- 预估治疗条高度
            ["color"] = {1, 1, 0},        -- 预估治疗条颜色：黄色
        }, -- 17
        -- ======================================================================
        -- 18. 外部冷却 (External Cooldowns)
        -- 显示其他玩家对你使用的外部减伤技能（如痛苦压制、铁树皮等）
        -- ======================================================================
        {
            ["name"] = "External Cooldowns",
            ["indicatorName"] = "externalCooldowns",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"RIGHT", "button", "RIGHT", 2, 5}, -- 框体右侧
            ["frameLevel"] = 10,
            ["size"] = {12, 20},           -- 图标尺寸 {宽, 高}
            ["showDuration"] = false,      -- 是否在图标上显示剩余时间
            ["showAnimation"] = true,      -- 是否显示激活动画效果
            ["num"] = 2,                   -- 最多同时显示的图标数量
            ["orientation"] = "right-to-left", -- 多个图标的排列方向
            ["font"] = {                   -- 字体配置（两个条目分别用于上下两组冷却文字）
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},    -- 上方冷却文字
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}}, -- 下方冷却文字
            },
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}} -- 图标发光效果：{发光类型, 发光颜色}
        }, -- 18
        -- ======================================================================
        -- 19. 个人减伤冷却 (Defensive Cooldowns)
        -- 显示单位自身使用的减伤技能冷却（如树皮术、冰封之韧等）
        -- ======================================================================
        {
            ["name"] = "Defensive Cooldowns",
            ["indicatorName"] = "defensiveCooldowns",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"LEFT", "button", "LEFT", -2, 5}, -- 框体左侧（与外部冷却对称）
            ["frameLevel"] = 10,
            ["size"] = {12, 20},
            ["showDuration"] = false,
            ["showAnimation"] = true,
            ["num"] = 2,
            ["orientation"] = "left-to-right", -- 从左侧向右排列
            ["font"] = {
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }, -- 19
        -- ======================================================================
        -- 20. 全部冷却 - 外部 + 个人 (All Cooldowns)
        -- 合并显示外部冷却和个人减伤冷却（替代 18+19，节省位置）
        -- ======================================================================
        {
            ["name"] = "Externals + Defensives",
            ["indicatorName"] = "allCooldowns",
            ["type"] = "built-in",
            ["enabled"] = false,           -- 默认关闭，用户可选择启用以替代 18+19
            ["position"] = {"LEFT", "button", "LEFT", -2, 5},
            ["frameLevel"] = 10,
            ["size"] = {12, 20},
            ["showDuration"] = false,
            ["showAnimation"] = true,
            ["num"] = 2,
            ["orientation"] = "left-to-right",
            ["font"] = {
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }, -- 20
        -- ======================================================================
        -- 21. 坦克主动减伤 (Tank Active Mitigation)
        -- 显示坦克主动减伤技能的激活状态（如盾牌格挡、铁骨酒等）
        -- ======================================================================
        {
            ["name"] = "Tank Active Mitigation",
            ["indicatorName"] = "tankActiveMitigation",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"TOPLEFT", "button", "TOPLEFT", 10, 0}, -- 框体左上角右侧偏移
            ["frameLevel"] = 5,
            ["size"] = {20, 6},            -- 宽20高6的小型条
            ["color"] = {"class_color", {0.25, 1, 0}}, -- 默认使用职业颜色，备选绿色
        }, -- 21
        -- ======================================================================
        -- 22. 驱散 (Dispels)
        -- 显示可被自己驱散的负面效果图标（诅咒/疾病/魔法/中毒/流血）
        -- ======================================================================
        {
            ["name"] = "Dispels",
            ["indicatorName"] = "dispels",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"BOTTOMRIGHT", "button", "BOTTOMRIGHT", 0, 4}, -- 右下角
            ["frameLevel"] = 15,
            ["size"] = {12, 12},
            ["filters"] = {                -- 驱散类型过滤
                ["dispellableByMe"] = true, -- 仅显示自己可以驱散的效果
                ["Curse"] = true,          -- 诅咒
                ["Disease"] = true,        -- 疾病
                ["Magic"] = true,          -- 魔法
                ["Poison"] = true,         -- 中毒
                ["Bleed"] = true,          -- 流血
            },
            ["highlightType"] = "gradient-half", -- 高亮样式："gradient-half"=半渐变
            ["iconStyle"] = "blizzard",    -- 图标风格："blizzard"=暴雪默认边框
            ["orientation"] = "right-to-left", -- 从右向左排列多个可驱散图标
        }, -- 22
        -- ======================================================================
        -- 23. 负面效果 (Debuffs)
        -- 显示单位身上的常规负面效果（非团队关键debuff）
        -- ======================================================================
        {
            ["name"] = "Debuffs",
            ["indicatorName"] = "debuffs",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"BOTTOMLEFT", "button", "BOTTOMLEFT", 1, 4}, -- 左下角
            ["frameLevel"] = 5,
            ["size"] = {{13, 13}, {17, 17}}, -- 图标尺寸：{小型, 大型}（根据debuff优先级自动切换）
            ["showDuration"] = false,      -- 不显示持续时间文字
            ["showAnimation"] = true,      -- 显示激活动画
            ["showTooltip"] = false,       -- 悬停不显示提示
            ["enableBlacklistShortcut"] = false, -- 不启用黑名单快捷操作
            ["num"] = 3,                   -- 最多同时显示 3 个 debuff 图标
            ["font"] = {
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["dispellableByMe"] = false,   -- 不过滤仅可驱散（让 dispels 指示器专门处理驱散）
            ["orientation"] = "left-to-right",
        }, -- 23
        -- ======================================================================
        -- 24. 团队负面效果 (Raid Debuffs)
        -- 显示团队副本中的关键负面效果（boss 技能 debuff）
        -- 与普通 debuffs 分开，层级更高、图标更大，便于治疗快速识别
        -- ======================================================================
        {
            ["name"] = "Raid Debuffs",
            ["indicatorName"] = "raidDebuffs",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"CENTER", "button", "CENTER", 0, 3}, -- 框体中央偏上
            ["frameLevel"] = 20,           -- 较高层级
            ["size"] = {22, 22},           -- 较大图标
            ["border"] = 2,                -- 边框宽度
            ["num"] = 1,                   -- 显示 1 个（最重要的团队 debuff）
            ["showDuration"] = true,       -- 显示剩余时间
            ["font"] = {
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["onlyShowTopGlow"] = false,   -- 是否仅在最高优先级 debuff 上显示发光
            ["orientation"] = "left-to-right",
            ["showTooltip"] = false,
        }, -- 24
        -- ======================================================================
        -- 25. 私有光环 (Private Auras)
        -- 显示仅自己可见的光环（如某些 boss 机制的隐藏光环）
        -- privateAuraOptions: {显示私有光环, 显示非私有光环}
        -- ======================================================================
        {
            ["name"] = "Private Auras",
            ["indicatorName"] = "privateAuras",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["position"] = {"TOP", "button", "TOP", 0, 3},
            ["frameLevel"] = 25,           -- 较高层级，重要机制需要醒目
            ["size"] = {18, 18},
            ["privateAuraOptions"] = {true, false}, -- {私有光环=true, 非私有光环=false} 仅显示私有光环
        }, -- 25
        -- ======================================================================
        -- 26. 目标法术 (Targeted Spells)
        -- 显示即将对单位施放的法术（敌对目标施法预警）
        -- ======================================================================
        {
            ["name"] = "Targeted Spells",
            ["indicatorName"] = "targetedSpells",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["showAllSpells"] = false,     -- 仅显示已配置的重要法术（非所有法术）
            ["position"] = {"TOPLEFT", "button", "TOPLEFT", -4, 4}, -- 左上角外侧
            ["frameLevel"] = 50,           -- 很高层级，必须醒目
            ["size"] = {20, 20},
            ["border"] = 2,
            ["num"] = 1,                   -- 显示当前最重要的 1 个目标法术
            ["font"] = {"Cell ".._G.DEFAULT, 12, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
            ["orientation"] = "left-to-right",
        }, -- 26
        -- ======================================================================
        -- 27. 目标计数 (Target Counter)
        -- 显示以该单位为目标的数量（主要 PvP 用途：大战场中显示被集火人数）
        -- ======================================================================
        {
            ["name"] = "Target Counter",
            ["indicatorName"] = "targetCounter",
            ["type"] = "built-in",
            ["enabled"] = false,           -- 默认关闭
            ["position"] = {"TOP", "button", "TOP", 0, 5},
            ["frameLevel"] = 15,
            ["font"] = {"Cell ".._G.DEFAULT, 15, "Outline", false},
            ["color"] = {1, 0.1, 0.1},    -- 红色文字
            ["filters"] = {                -- 环境过滤（在哪些场景下启用）
                ["outdoor"] = false,       -- 野外不启用
                ["pve"] = false,           -- PvE 不启用
                ["pvp"] = true,            -- PvP 启用
            },
        }, -- 27
        -- ======================================================================
        -- 28. 控制效果 (Crowd Controls)
        -- 显示控制类负面效果（昏迷/恐惧/迷惑/定身/沉默等）
        -- ======================================================================
        {
            ["name"] = "Crowd Controls",
            ["indicatorName"] = "crowdControls",
            ["type"] = "built-in",
            ["enabled"] = false,           -- 默认关闭
            ["position"] = {"CENTER", "button", "CENTER", 0, 0}, -- 框体中央
            ["frameLevel"] = 20,
            ["size"] = {22, 22},
            ["border"] = 2,
            ["num"] = 3,                   -- 最多显示 3 个控制效果
            ["showDuration"] = true,
            ["font"] = {
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["dispellableByMe"] = false,
            ["orientation"] = "left-to-right",
        }, -- 28
        -- ======================================================================
        -- 29. 动作 (Actions)
        -- 定义鼠标点击框体时触发的施法动作（左键/右键/中键等）
        -- 默认启用但无具体法术绑定（由用户在设置中配置）
        -- speed: 施法队列速度系数（1=正常速度）
        -- ======================================================================
        {
            ["name"] = "Actions",
            ["indicatorName"] = "actions",
            ["type"] = "built-in",
            ["enabled"] = true,
            ["speed"] = 1,                 -- 施法速度系数
        }, -- 29
        -- ======================================================================
        -- 30. 缺失增益 (Missing Buffs)
        -- 显示单位缺失的重要增益效果（如团队buff、职业buff等），提醒补buff
        -- ======================================================================
        {
            ["name"] = "Missing Buffs",
            ["indicatorName"] = "missingBuffs",
            ["type"] = "built-in",
            ["enabled"] = false,           -- 默认关闭
            ["position"] = {"BOTTOMRIGHT", "button", "BOTTOMRIGHT", 0, 4},
            ["frameLevel"] = 10,
            ["size"] = {13, 13},
            ["orientation"] = "right-to-left", -- 从右向左排列缺失增益图标
        }, -- 30
    },
}

-- ============================================================================
-- 布局自动切换配置 (Layout Auto-Switch)
-- 根据当前游戏环境自动切换到预设的布局
-- 值为布局名称字符串，"default" 表示使用 main 布局
-- 用户可在设置中为每种环境指定不同的自定义布局
-- ============================================================================
-- 环境键说明：
--   solo:            单人（无队伍）
--   party:           5人小队
--   raid_outdoor:    团队野外（非副本）
--   raid_instance:   团队副本（普通/英雄难度）
--   raid_mythic:     史诗团队副本
--   arena:           竞技场（2v2 / 3v3 / 5v5）
--   battleground15:  15人战场（如阿拉希盆地、战歌峡谷等）
--   battleground40:  40人战场（如奥特兰克山谷、阿什兰等）
-- ============================================================================
Cell.defaults.layoutAutoSwitch = {
    ["solo"] = "default",
    ["party"] = "default",
    ["raid_outdoor"] = "default",
    ["raid_instance"] = "default",
    ["raid_mythic"] = "default",
    ["arena"] = "default",
    ["battleground15"] = "default",
    ["battleground40"] = "default",
}