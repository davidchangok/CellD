-- ===========================================================================
-- Indicator_DefaultSpells.lua
-- 为 Cell 的指示器模块提供默认法术数据，包括：
--   - 团队减伤 / 外部冷却 / 群控技能的硬编码列表
--   - 驱散能力检测（基于专精天赋树节点）
--   - 大秘境点名技能列表（targetedSpells）
--   - 治疗者 HoT/护盾默认指示器配置（首次运行向导）
--   - 所有 Midnight/SecretValue 防护点（防止暴雪隐藏法术名称/ID 时崩溃）
-- ===========================================================================

local _, Cell = ...
local L = Cell.L
local I = Cell.iFuncs        -- 对外暴露的接口函数表（供其他模块调用）
local F = Cell.funcs          -- 内部工具函数表（GetSpellInfo, GetClassColorStr 等）

-- 前向声明：由 I.UpdateDefensives() / I.UpdateExternals() 在运行时填充
-- 这些表在首次调用更新函数之前为 nil，使用时需判空
local builtInDefensives, customDefensives
local builtInExternals, customExternals

-------------------------------------------------
-- dispelBlacklist — 驱散黑名单
-- 作用：抑制特定 debuff 的"可驱散"高亮提示
-- 当前为空表，预留扩展空间；用户或模块可在运行时动态添加 spellId
-------------------------------------------------
local dispelBlacklist = {}

-- 获取默认驱散黑名单（供 Cell 核心模块读取）
function I.GetDefaultDispelBlacklist()
    return dispelBlacklist
end

-------------------------------------------------
-- debuffBlacklist — Debuff 黑名单
-- 作用：过滤掉不应在团队框体上显示的 debuff（如复活虚弱、嗜血疲劳等）
-- 数据结构：spellId 为键的数组（数字索引），统一按 ID 匹配
-- 注意：注释掉的代码原为"按名称匹配"，当前版本直接返回 ID 列表
-------------------------------------------------
local debuffBlacklist = {
    8326, -- 鬼魂 - Ghost
    160029, -- 正在复活 - Resurrecting
    255234, -- 图腾复生 - Totemic Revival
    225080, -- 复生 - Reincarnation
    57723, -- 筋疲力尽 - Exhaustion
    57724, -- 心满意足 - Sated
    80354, -- 时空错位 - Temporal Displacement
    264689, -- 疲倦 - Fatigued
    390435, -- 筋疲力尽 - Exhaustion
    206151, -- 挑战者的负担 - Challenger's Burden
    195776, -- 月羽疫病 - Moonfeather Fever
    352562, -- 起伏机动 - Undulating Maneuvers
    356419, -- 审判灵魂 - Judge Soul
    387847, -- 邪甲术 - Fel Armor
    213213, -- 伪装 - Masquerade
}

-- 获取默认 Debuff 黑名单（返回 spellId 数组）
-- 调用方使用 F.GetSpellInfo(id) 自行转换为名称进行匹配
function I.GetDefaultDebuffBlacklist()
    -- local temp = {}
    -- for i, id in pairs(debuffBlacklist) do
    --     temp[i] = F.GetSpellInfo(id)
    -- end
    -- return temp
    return debuffBlacklist
end

-------------------------------------------------
-- bigDebuffs — 重要 Debuff 列表
-- 作用：标记需要放大显示或特殊处理的副本/词缀 debuff
-- 包含：赛季词缀机制（爆裂、死疽、重伤）以及各资料片副本的重要 debuff
-- 注：已废弃的旧赛季词缀以注释形式保留，方便后续赛季参考复用
-------------------------------------------------
local bigDebuffs = {
    46392, -- 专注打击 - Focused Assault
    -----------------------------------------------
    240443, -- 爆裂 - Burst
    209858, -- 死疽溃烂 - Necrotic Wound
    240559, -- 重伤 - Grievous Wound
    -- 226512, -- 鲜血脓液（血池）
    -----------------------------------------------
    -- NOTE: Thundering Affix - Dragonflight Season 1
    -- 396369, -- 闪电标记
    -- 396364, -- 狂风标记
    -----------------------------------------------
    -- NOTE: Shrouded Affix - Shadowlands Season 4
    -- 373391, -- 梦魇
    -- 373429, -- 腐臭虫群
    -----------------------------------------------
    -- NOTE: Encrypted Affix - Shadowlands Season 3
    -- 尤型拆卸者
    -- 366297, -- 解构
    -- 366288, -- 猛力砸击
    -----------------------------------------------
    -- NOTE: Tormented Affix - Shadowlands Season 2
    -- 焚化者阿寇拉斯
    -- 355732, -- 融化灵魂
    -- 355738, -- 灼热爆破
    -- 凇心之欧罗斯
    -- 356667, -- 刺骨之寒
    -- 刽子手瓦卢斯
    -- 356925, -- 屠戮
    -- 356923, -- 撕裂
    -- 358973, -- 恐惧浪潮
    -- 粉碎者索苟冬
    -- 355806, -- 重压
    -- 358777, -- 痛苦之链
}

function I.GetDefaultBigDebuffs()
    return bigDebuffs
end

-------------------------------------------------
-- aoeHealings — 群体治疗法术列表
-- 数据结构：{ [className] = { [spellId] = trackByName (bool) } }
--   - trackByName = true  → 按法术名称匹配（适用于施法者名称≠玩家名的情况，如召唤物）
--   - trackByName = false → 按法术 ID 匹配（适用于 PVP 天赋等名称可能变化的情况）
-- 用途：在团队框体上显示群疗技能的施法/持续状态指示器
-------------------------------------------------
local aoeHealings = {
    ["DRUID"] = {
        [740] = true,      -- 宁静 - Tranquility
        [145205] = true,   -- 百花齐放 - Efflorescence
    },

    ["EVOKER"] = {
        [355916] = true,   -- 翡翠之花 - Emerald Blossom
        [361361] = true,   -- 婆娑幼苗 - Fluttering Seedlings
        [363534] = true,   -- 回溯 - Rewind
        [367230] = true,   -- 精神之花 - Spiritbloom
        [370984] = true,   -- 翡翠交融 - Emerald Communion
        [371441] = true,   -- 赐命者之焰 - Life-Giver's Flame
        [371879] = true,   -- 生生不息 - Cycle of Life
        [377509] = false,  -- 梦境投影（pvp）- Dream Projection
    },

    ["MONK"] = {
        [115098] = true,   -- 真气波 - Chi Wave
        [123986] = true,   -- 真气爆裂 - Chi Burst
        [115310] = true,   -- 还魂术 - Revival
        [322118] = true,   -- 青龙下凡 (SUMMON) - Invoke Yu'lon, the Jade Serpent
        [388193] = true,   -- 碧火踏 - Jadefire Stomp
        [443028] = true,   -- 天神御身 - Celestial Conduit
        [343819] = false,  -- 迷雾之风 (朱鹤下凡产生的“迷雾之风”的施法者是玩家) - Gust of Mists
    },

    ["PALADIN"] = {
        [85222]  = true,   -- 黎明之光 - Light of Dawn
        [119952] = true,   -- 弧形圣光 - Arcing Light
        [114165] = true,   -- 神圣棱镜 - Holy Prism
        [200654] = true,   -- 提尔的拯救 - Tyr's Deliverance
        [216371] = true,   -- 复仇十字军 - Avenging Crusader
    },

    ["PRIEST"] = {
        [120517] = true,   -- 光晕 - Halo (moved to Archon hero talent in 12.0)
        [34861]  = true,   -- 圣言术：灵 - Holy Word: Sanctify
        [596]    = true,   -- 治疗祷言 - Prayer of Healing
        [64843]  = true,   -- 神圣赞美诗 - Divine Hymn
        -- [110744] = true,   -- 神圣之星 - Divine Star (removed in 12.0)
        [204883] = true,   -- 治疗之环 - Circle of Healing
        [281265] = true,   -- 神圣新星 - Holy Nova
        -- [314867] = true,   -- 暗影盟约 - Shadow Covenant (removed in 12.0)
        [15290]  = true,   -- 吸血鬼的拥抱 - Vampiric Embrace
        [372787] = true,   -- 神言术：佑 - Divine Word: Sanctuary
    },

    ["SHAMAN"] = {
        [1064]   = true,   -- 治疗链 - Chain Heal
        [73920]  = true,   -- 治疗之雨 - Healing Rain
        [108280] = true,   -- 治疗之潮图腾 (SUMMON) - Healing Tide Totem
        [52042]  = true,   -- 治疗之泉图腾 (SUMMON) - Healing Stream Totem
        [197995] = true,   -- 奔涌之流 - Wellspring
        -- [157503] = true,   -- 暴雨图腾 - Cloudburst (removed in 12.0)
        [114911] = true,   -- 先祖指引 - Ancestral Guidance
        [382311] = true,   -- 先祖复苏 - Ancestral Awakening
        [207778] = true,   -- 倾盆大雨 - Downpour
        [114083] = true,   -- 恢复迷雾 (升腾) - Restorative Mists
    },
}

function I.GetAoEHealings()
    return aoeHealings
end

-- 运行时缓存表：builtInAoEHealings 存放内置群疗（过滤用户禁用后），customAoEHealings 存放用户自定义群疗
local builtInAoEHealings = {}
local customAoEHealings = {}

-- 更新群疗法术缓存
-- t["disabled"]: 用户禁用的内置法术 ID 集合
-- t["custom"]: 用户自定义添加的法术 ID 列表
-- 逻辑：先清空两个缓存，再遍历 aoeHealings 硬编码表，跳过被禁用的法术，最终合并用户自定义法术
function I.UpdateAoEHealings(t)
    -- 处理内置法术：遍历所有职业的法术列表，过滤掉被用户禁用的
    wipe(builtInAoEHealings)
    for class, spells in pairs(aoeHealings) do
        for id, trackByName in pairs(spells) do
            if not t["disabled"][id] then -- not disabled
                if trackByName then
                    local name = F.GetSpellInfo(id)
                    if name then
                        builtInAoEHealings[name] = true
                    end
                else
                    builtInAoEHealings[id] = true
                end
            end
        end
    end

    -- user created
    wipe(customAoEHealings)
    for _, id in pairs(t["custom"]) do
        customAoEHealings[id] = true
    end
end

-- 判断某个法术是否为群疗技能
-- 参数 name/id 来自战斗事件（CLEU/UNIT_AURA），优先按名称匹配，其次按 ID 匹配
-- Midnight 12.0.0+ 防护：暴雪可能将法术名称或 ID 标记为 secret value，
--   此时对应的参数在 Lua 端被隐藏。若任一参数为 secret 即跳过检测，避免误判
function I.IsAoEHealing(name, id)
    -- Midnight SecretValue 防护：name 或 id 任一为 secret 则安全退出
    if issecretvalue and (issecretvalue(name) or issecretvalue(id)) then return end
    return builtInAoEHealings[name] or builtInAoEHealings[id] or customAoEHealings[id]
end

-- summonDuration — 召唤物/图腾持续时间表
-- 原始定义用 spellId 作为键，存储持续秒数
-- 下方的 do...end 块将其转换为"法术名称 → 持续时间"的映射，方便运行时按名称查找
local summonDuration = {
    -- evoker
    [377509] = 6, -- 梦境投影（pvp）- Dream Projection

    -- monk
    [322118] = 25, -- 青龙下凡 - Invoke Yu'lon, the Jade Serpent

    -- shaman
    [108280] = 12, -- 治疗之潮图腾 - Healing Tide Totem
    [52042] = 15, -- 治疗之泉图腾 - Healing Stream Totem
}

-- 转换 summonDuration 键名：spellId → 法术名称
-- 原因：战斗事件中召唤物施放法术时，只能拿到法术名称，用名称做键查找更直接
do
    local temp = {}
    for id, duration in pairs(summonDuration) do
        temp[F.GetSpellInfo(id)] = duration
    end
    summonDuration = temp
end

-- 根据法术名称查询召唤物的持续时间（秒），用于指示器计时显示
function I.GetSummonDuration(spellName)
    return summonDuration[spellName]
end

-------------------------------------------------
-- externalCooldowns — 外部冷却技能列表
-- 数据结构：{ [className] = { [spellId] = trackByName (bool) 或 subTable } }
--   - trackByName = true  → 按法术名称追踪（推荐，兼容性更好）
--   - trackByName = false → 按法术 ID 追踪（特殊场景用）
--   - subTable            → 嵌套子法术表（如法师群体屏障含3种护体），主 ID 也加入缓存
-- 用途：在团队框体上显示队友对你施放的减伤/辅助类技能
-------------------------------------------------
local externals = { -- true: 按名称追踪, false: 按 ID 追踪
    ["DEATHKNIGHT"] = {
        [51052] = true, -- 反魔法领域 - Anti-Magic Zone
    },

    ["DEMONHUNTER"] = {
        [196718] = true, -- 黑暗 - Darkness
    },

    ["DRUID"] = {
        [102342] = true, -- 铁木树皮 - Ironbark
    },

    ["EVOKER"] = {
        [374227] = true, -- 微风 - Zephyr
        [357170] = true, -- 时间膨胀 - Time Dilation
        [378441] = true, -- 时间停止 - Time Stop (pvp)
        [374348] = true, -- 新生光焰 - Renewing blaze
    },

    ["MAGE"] = {
        [198158] = true, -- 群体隐形 - Mass Invisibility
        [414660] = { -- 群体屏障 - Mass Barrier
            [414661] = false, -- 寒冰护体 - Ice Barrier
            [414662] = false, -- 烈焰护体 - Blazing Barrier
            [414663] = false, -- 棱光护体 - Prismatic Barrier
            -- [11426] = false, -- 寒冰护体 (self)
            -- [235313] = false, -- 烈焰护体 (self)
            -- [235450] = false, -- 棱光护体 (self)
        },
    },

    ["MONK"] = {
        [116849] = true, -- 作茧缚命 - Life Cocoon
        [202248] = false, -- 偏转冥想 - Guided Meditation
    },

    ["PALADIN"] = {
        [1022] = true, -- 保护祝福 - Blessing of Protection
        [6940] = true, -- 牺牲祝福 - Blessing of Sacrifice
        [204018] = true, -- 破咒祝福 - Blessing of Spellwarding
        [31821] = true, -- 光环掌握 - Aura Mastery
        [210256] = true, -- 庇护祝福 - Blessing of Sanctuary
        [228050] = false, -- 圣盾术 (被遗忘的女王护卫) - Divine Shield
        -- [211210] = true, -- 提尔的保护
        -- [216328] = true, -- 光之优雅
    },

    ["PRIEST"] = {
        [33206] = true, -- 痛苦压制 - Pain Suppression
        [47788] = true, -- 守护之魂 - Guardian Spirit
        [62618] = true, -- 真言术：障 - Power Word: Barrier
        [213610] = true, -- 神圣守卫 - Holy Ward
        [197268] = true, -- 希望之光 - Ray of Hope
    },

    ["ROGUE"] = {
        [114018] = true, -- 潜伏帷幕 - Shroud of Concealment
    },

    ["SHAMAN"] = {
        [98008] = true, -- 灵魂链接图腾 - Spirit Link Totem
        [201633] = true, -- 大地之墙图腾 - Earthen Wall
        [8178] = true, -- 根基图腾 - Grounding Totem
        [383018] = true, -- 石肤图腾 - Stoneskin
    },

    ["WARRIOR"] = {
        [97462] = true, -- 集结呐喊 - Rallying Cry
        [3411] = true, -- 援护 - Intervene
        [213871] = true, -- 护卫 - Bodyguard
    },
}

function I.GetExternals()
    return externals
end

local builtInExternals = {}
local customExternals = {}

-- 内部辅助函数：将单个外部冷却法术加入 builtInExternals 缓存
-- trackByName 为 true 时按法术名称存储，否则按 spellId 存储
local function UpdateExternals(id, trackByName)
    if trackByName then
        local name = F.GetSpellInfo(id)
        if name then
            builtInExternals[name] = true
        end
    else
        builtInExternals[id] = true
    end
end

-- 更新外部冷却法术缓存（用户设置变更时调用）
-- t["disabled"]: 用户禁用的内置法术 ID 集合
-- t["custom"]: 用户自定义添加的法术 ID 列表
-- 特殊处理：嵌套表结构（如法师群体屏障）— 主 ID 直接加入缓存，
--   子法术按各自 trackByName 标记分别处理
function I.UpdateExternals(t)
    -- 处理内置法术：遍历所有职业，跳过被用户禁用的法术
    wipe(builtInExternals)
    for class, spells in pairs(externals) do
        for id, v in pairs(spells) do
            if not t["disabled"][id] then -- 未被用户禁用
                if type(v) == "table" then
                    -- 嵌套表（如法师群体屏障）：主 ID 加入缓存供 I.IsExternalCooldown() 匹配
                    builtInExternals[id] = true
                    for subId, subTrackByName in pairs(v) do
                        UpdateExternals(subId, subTrackByName)
                    end
                else
                    UpdateExternals(id, v)
                end
            end
        end
    end

    -- 处理用户自定义法术
    wipe(customExternals)
    for _, id in pairs(t["custom"]) do
        -- 自定义法术统一按 spellId 存储，注释掉的代码原为按名称存储方案
        customExternals[id] = true
    end
end

local UnitIsUnit = UnitIsUnit
local bos = F.GetSpellInfo(6940) -- 牺牲祝福（特殊处理：只对自己施放时不视为外部冷却）
-- 判断某个法术是否为外部冷却技能
-- 参数 name, id 来自战斗事件；source, target 为施法者和目标 UnitID
-- 特殊逻辑：牺牲祝福（bos）仅在施法者≠目标时才视为外部冷却
-- Midnight 12.0.0+ 防护：name 和 id 可能同时为 secret value，
--   只有两者皆为 secret 时才安全退出（因为此时完全无法识别法术）；
--   若仅 name 为 secret，仍可按 id 继续匹配
function I.IsExternalCooldown(name, id, source, target)
    -- 防护：builtInExternals 在首次 I.UpdateExternals() 调用之前为 nil
    if not builtInExternals then return end
    -- Midnight SecretValue 防护：name 和 id 皆为 secret 时才安全退出
    local nameSecret = issecretvalue and issecretvalue(name)
    local idSecret = issecretvalue and issecretvalue(id)
    if nameSecret and idSecret then return end
    -- 牺牲祝福特殊处理：自己给自己不视为外部冷却
    if not nameSecret and name == bos then
        if source and target then
            return not UnitIsUnit(source, target)
        else
            return true
        end
    else
        return builtInExternals[name] or builtInExternals[id] or customExternals[id]
    end
end

-- 判断某个法术是否为个人减伤技能
-- 参数 name, id 来自战斗事件（CLEU/UNIT_AURA）
-- Midnight 12.0.0+ 防护策略（与 I.IsExternalCooldown 类似但更精细）：
--   - 两者皆为 secret → 安全退出
--   - 仅 name 为 secret → 仅按 id 匹配（跳过 name 查找，避免对 secret 做表键访问）
--   - 仅 id 为 secret → 仅按 name 匹配
--   - 两者都可见 → 同时按 name 和 id 匹配
function I.IsDefensiveCooldown(name, id)
    -- 防护：builtInDefensives 在首次 I.UpdateDefensives() 调用之前为 nil
    if not builtInDefensives then return end
    -- Midnight SecretValue 防护：name 和 id 皆为 secret 时才安全退出
    local nameSecret = issecretvalue and issecretvalue(name)
    local idSecret = issecretvalue and issecretvalue(id)
    if nameSecret and idSecret then return end
    -- 仅 name 为 secret：只能按 id 匹配（builtInDefensives 的 id 键 + customDefensives）
    if nameSecret then return builtInDefensives[id] or customDefensives[id] end
    -- 仅 id 为 secret：只能按 name 匹配（builtInDefensives 的 name 键）
    if idSecret then return builtInDefensives[name] end
    -- 两者都可见：同时按 name 和 id 匹配，任一命中即可
    return builtInDefensives[name] or builtInDefensives[id] or customDefensives[id]
end

-------------------------------------------------
-- defensiveCooldowns — 个人减伤技能列表
-- 数据结构：{ [className] = { [spellId] = trackByName (bool) } }
--   - trackByName = true  → 按法术名称追踪（推荐，适用于绝大多数减伤）
--   - trackByName = false → 按法术 ID 追踪（适用于 PVP 天赋、英雄天赋等名称可能不唯一的场景）
-- 用途：在团队框体上显示队友开启的个人减伤技能指示器
-------------------------------------------------
local defensives = { -- true: 按名称追踪, false: 按 ID 追踪
    ["DEATHKNIGHT"] = {
        [48707] = true, -- 反魔法护罩 - Anti-Magic Shell
        [48792] = true, -- 冰封之韧 - Icebound Fortitude
        [49028] = true, -- 符文刃舞 - Dancing Rune Weapon
        [55233] = true, -- 吸血鬼之血 - Vampiric Blood
        [49039] = false, -- 巫妖之躯 - Lichborne
        [194679] = true, -- 符文分流 - Rune Tap
    },

    ["DEMONHUNTER"] = {
        [196555] = true, -- 虚空行走 - Netherwalk
        [198589] = true, -- 疾影 - Blur
        [187827] = false, -- 恶魔变形 162264(DPS) - Metamorphosis
    },

    ["DRUID"] = {
        [22812] = true, -- 树皮术 - Barkskin
        [61336] = true, -- 生存本能 - Survival Instincts
        [200851] = true, -- 沉睡者之怒 - Rage of the Sleeper
        [102558] = true, -- 化身：乌索克的守护者 - Incarnation: Guardian of Ursoc
        [22842] = true, -- 狂暴回复 - Frenzied Regeneration
    },

    ["EVOKER"] = {
        [363916] = true, -- 黑曜鳞片 - Obsidian Scales
        [374348] = true, -- 新生光焰 - Renewing Blaze
        [370960] = true, -- 翡翠交融 - Emerald Communion
        [431872] = false, -- 瞬息之隔 - Temporality (Chronowarden Hero Talent)
        [377088] = false, -- 活力迸射 - Rush of Vitality
    },

    ["HUNTER"] = {
        [186265] = true, -- 灵龟守护 - Aspect of the Turtle
        [264735] = true, -- 优胜劣汰 - Survival of the Fittest
    },

    ["MAGE"] = {
        [45438] = true, -- 寒冰屏障 - Ice Block
        [414658] = true, -- 深寒凝冰 - Ice Cold
        [113862] = false, -- 强化隐形术 - Greater Invisibility
        [55342] = true, -- 镜像 - Mirror Image (Midnight: UNIT_AURA, no longer CLEU)
        [342246] = true, -- 操控时间 - Alter Time
    },

    ["MONK"] = {
        [115176] = false, -- 禅悟冥想 - Zen Meditation
        [115203] = true, -- 壮胆酒 - Fortifying Brew
        [122278] = true, -- 躯不坏 - Dampen Harm
        [122783] = true, -- 散魔功 - Diffuse Magic
        [125174] = true, -- 业报之触 - Touch of Karma
    },

    ["PALADIN"] = {
        [498] = true, -- 圣佑术 - Divine Protection
        [642] = true, -- 圣盾术 - Divine Shield
        [31850] = true, -- 炽热防御者 - Ardent Defender
        [212641] = true, -- 远古列王守卫 - Guardian of Ancient Kings
        [205191] = true, -- 以眼还眼 - Eye for an Eye
        [389539] = true, -- 戒卫 - Sentinel
        [184662] = true, -- 复仇之盾 - Shield of Vengeance
    },

    ["PRIEST"] = {
        [47585] = true, -- 消散 - Dispersion
        [19236] = true, -- 绝望祷言 - Desperate Prayer
        [586] = true, -- 渐隐术 -- TODO: 373446 通透影像 - Fade
        [193065] = true, -- 防护圣光 - Protective Light
        [27827] = true, -- 救赎之魂 - Spirit of Redemption
    },

    ["ROGUE"] = {
        [1966] = true, -- 佯攻 - Feint
        [5277] = true, -- 闪避 - Evasion
        [31224] = false, -- 暗影斗篷 - Cloak of Shadows
    },

    ["SHAMAN"] = {
        [108271] = true, -- 星界转移 - Astral Shift
        [409293] = true, -- 掘地三尺 - Burrow (PVP)
        [114893] = true, -- 石壁 - Stone Bulwark
    },

    ["WARLOCK"] = {
        [104773] = true, -- 不灭决心 - Unending Resolve
        [212295] = true, -- 虚空守卫 - Nether Ward (PVP)
        [108416] = true, -- 黑暗契约 - Dark Pact
    },

    ["WARRIOR"] = {
        [871] = true, -- 盾墙 - Shield Wall
        [12975] = true, -- 破釜沉舟 - Last Stand
        [23920] = true, -- 法术反射 - Spell Reflection
        [118038] = true, -- 剑在人在 - Die by the Sword
        [184364] = true, -- 狂怒回复 - Enraged Regeneration
    },
}

function I.GetDefensives()
    return defensives
end

-- 运行时缓存表：builtInDefensives 存放内置减伤（过滤用户禁用后），customDefensives 存放用户自定义减伤
local builtInDefensives = {}
local customDefensives = {}

-- 更新个人减伤技能缓存（用户设置变更时调用）
-- t["disabled"]: 用户禁用的内置法术 ID 集合
-- t["custom"]: 用户自定义添加的法术 ID 列表
-- 逻辑：遍历 defensives 硬编码表，跳过用户禁用的法术；
--   trackByName 为 true 的法术按名称存入缓存，方便跨语言/跨版本匹配
function I.UpdateDefensives(t)
    -- 处理内置法术：遍历所有职业，过滤掉被用户禁用的
    wipe(builtInDefensives)
    for class, spells in pairs(defensives) do
        for id, trackByName in pairs(spells) do
            if not t["disabled"][id] then -- 未被用户禁用
                if trackByName then
                    local name = F.GetSpellInfo(id)
                    if name then
                        builtInDefensives[name] = true  -- 按名称存储，兼容多语言客户端
                    end
                else
                    builtInDefensives[id] = true    -- 按 ID 存储，用于特殊场景
                end
            end
        end
    end

    -- 处理用户自定义法术（统一按 spellId 存储）
    wipe(customDefensives)
    for _, id in pairs(t["custom"]) do
        customDefensives[id] = true
    end
end

-------------------------------------------------
-- tankActiveMitigation — 坦克主动减伤技能列表
-- 数据结构：spellId 为键的布尔表，用于在团队框体上高亮显示坦克的常驻减伤
-- tankActiveMitigationNames 是对应的彩色名称字符串数组（含职业颜色），
--   用于向用户展示支持的技能列表（如设置面板提示）
-------------------------------------------------
local tankActiveMitigations = {
    -- death knight
    -- 77535, -- 鲜血护盾
    195181, -- 白骨之盾 - Bone Shield

    -- demon hunter
    203819, -- 恶魔尖刺 - Demon Spikes

    -- druid
    192081, -- 铁鬃 - Ironfur

    -- monk
    215479, -- 酒醒入定 - Shuffle

    -- paladin
    132403, -- 正义盾击 - Shield of the Righteous

    -- warrior
    132404, -- 盾牌格挡 - Shield Block
}

local tankActiveMitigationNames = {
    -- death knight
    -- F.GetClassColorStr("DEATHKNIGHT")..F.GetSpellInfo(77535).."|r", -- 鲜血护盾
    F.GetClassColorStr("DEATHKNIGHT")..F.GetSpellInfo(195181).."|r", -- 白骨之盾

    -- demon hunter
    F.GetClassColorStr("DEMONHUNTER")..F.GetSpellInfo(203819).."|r", -- 恶魔尖刺

    -- druid
    F.GetClassColorStr("DRUID")..F.GetSpellInfo(192081).."|r", -- 铁鬃

    -- monk
    F.GetClassColorStr("MONK")..F.GetSpellInfo(215479).."|r", -- 酒醒入定

    -- paladin
    F.GetClassColorStr("PALADIN")..F.GetSpellInfo(132403).."|r", -- 正义盾击

    -- warrior
    F.GetClassColorStr("WARRIOR")..F.GetSpellInfo(132404).."|r", -- 盾牌格挡
}

-- 转换 tankActiveMitigations：统一为 { [spellId] = true } 格式（原始格式也是按 ID）
-- 注释掉的代码原为按名称转换方案
do
    local temp = {}
    for _, id in pairs(tankActiveMitigations) do
        temp[id] = true
    end
    tankActiveMitigations = temp
end

-- 判断指定 spellId 是否为坦克主动减伤技能
-- Midnight 12.0.0+ 防护：若 spellId 为 secret value 则安全退出
function I.IsTankActiveMitigation(spellId)
    if issecretvalue and issecretvalue(spellId) then return end
    return tankActiveMitigations[spellId]
end

-- 返回坦克主动减伤技能列表的可读字符串（含职业颜色标记），用于设置面板提示
function I.GetTankActiveMitigationString()
    return table.concat(tankActiveMitigationNames, ", ").."."
end

-------------------------------------------------
-- dispels — 驱散能力检测
-- 核心思路：不同专精通过天赋树节点（nodeID）获得驱散能力，检测逻辑如下：
--   1. 获取当前专精 ID（Cell.vars.playerSpecID）
--   2. 查 dispelNodeIDs 表获取该专精下各驱散类型对应的天赋节点
--   3. 调用 C_Traits.GetNodeInfo 检查节点是否已激活（activeRank != 0）
-- 驱散类型键名："Curse"(诅咒), "Disease"(疾病), "Magic"(魔法), "Poison"(中毒), "Bleed"(流血)
-- 值含义：
--   - true (boolean)     → 该专精天生可驱散此类型（无需天赋节点）
--   - number             → 单个天赋节点 ID，需检查激活状态
--   - table (number[])   → 多个天赋节点 ID（任一激活即可），如唤魔师用 Cauterizing Flame
-- 注意：术士的 Magic 驱散依赖宠物技能（吞噬魔法 89808），通过 UNIT_PET 事件单独处理
-------------------------------------------------
-- dispellable 运行时缓存表：{ [dispelType] = true/false }，表示当前角色能否驱散对应类型
local dispellable = {}

-- 查询当前角色是否能驱散指定类型
function I.CanDispel(dispelType)
    if not dispelType then return end
    return dispellable[dispelType]
end

-- dispelNodeIDs：专精 ID → 驱散类型 → 天赋节点信息
-- 键为专精 ID（非职业 ID），从 C_ClassTalents.GetActiveConfigID / Cell.vars.playerSpecID 获取
local dispelNodeIDs = {
    -- DRUID ----------------
        -- 102 - Balance
        [102] = {["Curse"] = 82241, ["Poison"] = 82241},
        -- 103 - Feral
        [103] = {["Curse"] = 82241, ["Poison"] = 82241},
        -- 104 - Guardian
        [104] = {["Curse"] = 82241, ["Poison"] = 82241},
        -- Restoration
        [105] = {["Curse"] = true, ["Magic"] = true, ["Poison"] = true},
    -------------------------

    -- EVOKER ---------------
        -- 1467 - Devastation
        [1467] = {["Curse"] = 93294, ["Disease"] = 93294, ["Poison"] = {93306, 93294}, ["Bleed"] = 93294},
        -- 1468	- Preservation
        [1468] = {["Curse"] = 93294, ["Disease"] = 93294, ["Magic"] = true, ["Poison"] = true, ["Bleed"] = 93294},
        -- 1473 - Augmentation
        [1473] = {["Curse"] = 93294, ["Disease"] = 93294, ["Poison"] = {93306, 93294}, ["Bleed"] = 93294},
    -------------------------

    -- MAGE -----------------
        -- 62 - Arcane
        [62] = {["Curse"] = 62116},
        -- 63 - Fire
        [63] = {["Curse"] = 62116},
        -- 64 - Frost
        [64] = {["Curse"] = 62116},
    -------------------------

    -- MONK -----------------
        -- 268 - Brewmaster
        [268] = {["Disease"] = 101090, ["Poison"] = 101090},
        -- 269 - Windwalker
        [269] = {["Disease"] = 101150, ["Poison"] = 101150},
        -- 270 - Mistweaver
        [270] = {["Disease"] = 101089, ["Magic"] = true, ["Poison"] = 101089},
    -------------------------

    -- PALADIN --------------
        -- 65 - Holy
        [65] = {["Disease"] = 81508, ["Magic"] = true, ["Poison"] = 81508, ["Bleed"] = 81616},
        -- 66 - Protection
        [66] = {["Disease"] = 81507, ["Poison"] = 81507, ["Bleed"] = 81616},
        -- 70 - Retribution
        [70] = {["Disease"] = 81507, ["Poison"] = 81507, ["Bleed"] = 81616},
    -------------------------

    -- PRIEST ---------------
        -- 256 - Discipline
        [256] = {["Disease"] = 82705, ["Magic"] = true},
        -- 257 - Holy
        [257] = {["Disease"] = 82705, ["Magic"] = true},
        -- 258 - Shadow
        [258] = {["Disease"] = 82704, ["Magic"] = 82699},
    -------------------------

    -- SHAMAN ---------------
        -- 262 - Elemental
        [262] = {["Curse"] = 103608, ["Poison"] = 103599},
        -- 263 - Enhancement
        [263] = {["Curse"] = 103608, ["Poison"] = 103599},
        -- 264 - Restoration
        [264] = {["Curse"] = 81073, ["Magic"] = true, ["Poison"] = 103599},
    -------------------------

    -- WARLOCK --------------
        -- 265 - Affliction
        -- [265] = {["Magic"] = function() return IsSpellKnown(89808, true) end},
        -- 266 - Demonology
        -- [266] = {["Magic"] = function() return IsSpellKnown(89808, true) end},
        -- 267 - Destruction
        -- [267] = {["Magic"] = function() return IsSpellKnown(89808, true) end},
    -------------------------
}

-- ===========================================================================
-- 驱散能力检测：事件监听与 dispellable 缓存更新
-- ===========================================================================
-- eventFrame 是驱散检测的专用事件帧，根据职业不同注册不同事件：
--   - 术士：监听 UNIT_PET 事件（宠物召唤/解散时重新检测吞噬魔法）
--   - 其他职业：监听 PLAYER_ENTERING_WORLD 和 TRAIT_CONFIG_UPDATED
--     （切换天赋配置时重新检测节点激活状态）
-- 两次事件触发之间使用 1 秒延迟合并（C_Timer.NewTimer），防止短时间内重复检测
local eventFrame = CreateFrame("Frame")

if UnitClassBase("player") == "WARLOCK" then
    -- 术士专有逻辑：驱散能力来自宠物技能"吞噬魔法"(spellId 89808)
    -- 使用 IsSpellKnown(89808, true) 检测（第二个参数 true 表示包括宠物技能）
    eventFrame:RegisterEvent("UNIT_PET")

    local timer
    eventFrame:SetScript("OnEvent", function(self, event, unit)
        if unit ~= "player" then return end     -- 仅响应玩家自身的宠物事件

        -- 使用 1 秒防抖定时器，避免宠物频繁切换时重复检测
        if timer then
            timer:Cancel()
        end
        timer = C_Timer.NewTimer(1, function()
            -- 更新驱散能力：检查是否学会吞噬魔法（包括宠物技能栏）
            dispellable["Magic"] = IsSpellKnown(89808, true)
        end)

    end)
else
    -- 非术士职业：通过天赋树节点检测驱散能力
    -- PLAYER_ENTERING_WORLD：登录/加载时首次检测
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- TRAIT_CONFIG_UPDATED：切换天赋配置/保存天赋时重新检测
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    -- ACTIVE_PLAYER_SPECIALIZATION_CHANGED 已废弃，改用 TRAIT_CONFIG_UPDATED

    -- UpdateDispellable：根据当前天赋配置重新计算 dispellable 表
    -- 工作流程：
    --   1. 清空 dispellable 缓存
    --   2. 获取当前激活的天赋配置 ID (activeConfigID)
    --   3. 查 dispelNodeIDs 表获取当前专精的各驱散类型节点信息
    --   4. 根据节点信息类型分别处理：boolean（天生可驱）、table（多节点任一激活）、number（单节点激活检测）
    local function UpdateDispellable()
        -- 清空并重建驱散能力缓存
        wipe(dispellable)
        local activeConfigID = C_ClassTalents.GetActiveConfigID()
        if activeConfigID and dispelNodeIDs[Cell.vars.playerSpecID] then
            for dispelType, value in pairs(dispelNodeIDs[Cell.vars.playerSpecID]) do
                if type(value) == "boolean" then
                    -- 天生可驱散（如奶德可驱散诅咒/魔法/中毒）
                    dispellable[dispelType] = value
                elseif type(value) == "table" then
                    -- 多个天赋节点，任一激活即可驱散
                    -- 例如：唤魔师的 Cauterizing Flame(93294) 可驱散多种类型
                    --       或 Poison 同时需要 Expunge(93306) 或 Cauterizing Flame(93294)
                    for _, v in pairs(value) do
                        local nodeInfo = C_Traits.GetNodeInfo(activeConfigID, v)
                        if nodeInfo and nodeInfo.activeRank ~= 0 then
                            dispellable[dispelType] = true
                            break   -- 任一激活即跳出，不再检查其余节点
                        end
                    end
                else
                    -- 单个天赋节点，检查是否已激活
                    local nodeInfo = C_Traits.GetNodeInfo(activeConfigID, value)
                    if nodeInfo and nodeInfo.activeRank ~= 0 then
                        dispellable[dispelType] = true
                    end
                end
            end
        end
    end

    -- 1 秒防抖定时器：合并短时间内的多次事件触发
    local timer

    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" then
            -- 登录后仅需检测一次，此后由 TRAIT_CONFIG_UPDATED 处理
            eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end

        -- 重置防抖定时器：确保事件触发后等待 1 秒再执行检测
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(1, UpdateDispellable)
    end)

    -- 专精切换回调：Cell 框架层的 SpecChanged 事件
    -- 当玩家切换专精时，驱散能力可能变化，需重新检测
    Cell.RegisterCallback("SpecChanged", "Dispellable_SpecChanged", function()
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(1, UpdateDispellable)
    end)
end

-------------------------------------------------
-- drinking — 饮水/进食法术列表
-- 原始定义用 spellId 数组，下方 do...end 块转换为 { [name] = true } 便于按名称匹配
-- 用途：在团队框体上显示正在吃喝回蓝回血的队友状态指示器
-------------------------------------------------
local drinks = {
    170906, -- 食物和饮水 - Food & Drink
    167152, -- 进食饮水 - Refreshment
    430, -- 喝水 - Drink
    43182, -- 饮水 - Drink
    172786, -- 饮料 - Drink
    308433, -- 食物和饮料 - Food & Drink
    369162, -- 饮用 - Drink
    456574, -- 燧烬蜜露 - Cinder Nectar
    461063, -- 静默省思（土灵）- Quiet Contemplation (Earthen)
}

-- 转换 drinks 表键名：spellId → 法术名称（方便运行时按名称匹配）
do
    local temp = {}
    for _, id in pairs(drinks) do
        temp[F.GetSpellInfo(id)] = true
    end
    drinks = temp
end

-- 判断指定法术名是否为饮水/进食技能
-- Midnight 12.0.0+ 防护：若 name 为 secret value 则安全退出
function I.IsDrinking(name)
    if issecretvalue and issecretvalue(name) then return end
    return drinks[name]
end

-------------------------------------------------
-- healer — 治疗者 HoT/护盾默认指示器法术列表
-- 数据结构：spellId 数组（数字索引），包含各治疗职业的核心 HoT、护盾、增疗等 buff
-- 用途：首次运行向导 (F.FirstRun) 自动创建"Healers"图标指示器
--   展示队友身上的持续性治疗效果，帮助治疗者快速了解覆盖情况
-------------------------------------------------
local spells =  {
    -- druid
    8936, -- 愈合 - Regrowth
    774, -- 回春术 - Rejuvenation
    155777, -- 回春术（萌芽） - Rejuvenation (Germination)
    33763, -- 生命绽放 - Lifebloom
    188550, -- 生命绽放 - Lifebloom
    48438, -- 野性成长 - Wild Growth
    102351, -- 塞纳里奥结界 - Cenarion Ward
    102352, -- 塞纳里奥结界 - Cenarion Ward
    391891, -- 激变蜂群 - Adaptive Swarm
    145205, -- 百花齐放 - Efflorescence
    383193, -- 林地护理 - Grove Tending
    439530, -- 共生绽华 - Symbiotic Blooms
    -- 429224, -- 次级塞纳里奥结界 - Minor Cenarion Ward (removed in 12.0, Durability of Nature redesigned)

    -- evoker
    363502, -- 梦境飞行 - Dream Flight
    370889, -- 双生护卫 - Twin Guardian
    364343, -- 回响 - Echo
    355941, -- 梦境吐息 - Dream Breath
    376788, -- 梦境吐息（回响） - Dream Breath (Echo)
    366155, -- 逆转 - Reversion
    367364, -- 逆转（回响） - Reversion (Echo)
    373862, -- 时空畸体 - Temporal Anomaly
    378001, -- 梦境投影（pvp） - Dream Projection (pvp)
    373267, -- 缚誓生命 - Lifebind
    395296, -- 黑檀之力 (self) - Ebon Might
    395152, -- 黑檀之力 - Ebon Might
    360827, -- 炽火龙鳞 - Blistering Scales
    410089, -- 先知先觉 - Prescience
    406732, -- 空间悖论 (self) - Spatial Paradox
    406789, -- 空间悖论 - Spatial Paradox
    445740, -- 纵焰 - Enkindle
    409895, -- 精神之花 - Spiritbloom (Reverberations, Chronowarden Hero Talent)
    410263, -- 炼狱祝福 - Inferno's Blessing
    410686, -- 共生绽放 - Symbiotic Bloom
    413984, -- 流沙 - Shifting Sands

    -- monk
    119611, -- 复苏之雾 - Renewing Mist
    124682, -- 氤氲之雾 - Enveloping Mist
    325209, -- 氤氲之息 - Enveloping Breath
    406139, -- 真气之茧 - Chi Cocoon from Yu'lon
    406220, -- 真气之茧 - Chi Cocoon from Chi-Ji
    450769, -- 和谐化身 - Aspect of Harmony
    450805, -- 净化之魂 - Purified Spirit
    467281, -- 金创药 - Healing Elixir
    115175, -- 抚慰之雾 - Soothing Mist

    -- paladin
    53563, -- 圣光道标 - Beacon of Light
    223306, -- 赋予信仰 - Bestow Faith
    148039, -- 信仰屏障 - Barrier of Faith
    156910, -- 信仰道标 - Beacon of Faith
    200025, -- 美德道标 - Beacon of Virtue
    287280, -- 圣光闪烁 - Glimmer of Light
    156322, -- 永恒之火 - Eternal Flame
    431381, -- 晨光 - Dawnlight
    388013, -- 阳春祝福 - Blessing of Spring
    388007, -- 仲夏祝福 - Blessing of Summer
    388010, -- 暮秋祝福 - Blessing of Autumn
    388011, -- 凛冬祝福 - Blessing of Winter
    200654, -- 提尔的拯救 - Tyr's Deliverance
    1244893, -- 救世主道标 - Beacon of the Savior

    -- priest
    139, -- 恢复 - Renew
    200829, -- 恳求 - Plea (added in 12.0, Disc)
    41635, -- 愈合祷言 - Prayer of Mending
    17, -- 真言术：盾 - Power Word: Shield
    194384, -- 救赎 - Atonement
    77489, -- 圣光回响 - Echo of Light
    372847, -- 光明之泉恢复 - Blessed Bolt
    -- 443526, -- 慰藉预兆 - Premonition of Solace (removed in 12.0)
    1253593, -- 虚空之盾 - Void Shield

    -- shaman
    974, -- 大地之盾 - Earth Shield
    383648, -- 大地之盾（天赋） - Earth Shield
    61295, -- 激流 - Riptide
    382024, -- 大地生命武器 - Earthliving Weapon
    375986, -- 始源之潮 - Primordial Wave
    444490, -- 源水气泡 - Hydrobubble
    -- 73920, -- 治疗之雨 - Healing Rain
    -- 456366, -- 治疗之雨 - Healing Rain
}

-- 首次运行向导：询问用户是否创建"Healers"图标指示器
-- 显示所有硬编码治疗法术的图标预览（每行 11 个），用户确认后自动创建指示器配置
-- 创建的指示器默认属性：右上角、13x13 图标、5 个/行、右到左排列、显示堆叠、仅自己施放
function F.FirstRun()
    -- 构建图标预览字符串（用于弹窗展示）
    local icons = "\n\n"
    for i, id in pairs(spells) do
        local icon = select(2, F.GetSpellInfo(id))
        if icon then
            icons = icons .. "|T"..icon..":0|t"
            if i % 11 == 0 then
                icons = icons .. "\n"    -- 每 11 个图标换行
            end
        end
    end

    -- 创建确认弹窗：包含图标预览和"Yes/No"按钮
    local popup = Cell.CreateConfirmPopup(Cell.frames.anchorFrame, 200, L["Would you like Cell to create a \"Healers\" indicator (icons)?"]..icons, function(self)
        -- 用户点击"是"：在当前布局中创建 Healers 指示器
        local currentLayoutTable = Cell.vars.currentLayoutTable

        -- 计算新指示器名称（indicator1, indicator2, ...）
        local last = #currentLayoutTable["indicators"]
        if currentLayoutTable["indicators"][last]["type"] == "built-in" then
            indicatorName = "indicator1"
        else
            indicatorName = "indicator"..(tonumber(strmatch(currentLayoutTable["indicators"][last]["indicatorName"], "%d+"))+1)
        end

        -- 插入新指示器配置到当前布局末尾
        tinsert(currentLayoutTable["indicators"], {
            ["name"] = "Healers",
            ["indicatorName"] = indicatorName,
            ["type"] = "icons",
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["size"] = {13, 13},
            ["num"] = 5,
            ["numPerLine"] = 5,
            ["orientation"] = "right-to-left",
            ["spacing"] = {0, 0},
            ["font"] = {
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell ".._G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = true,
            ["showDuration"] = false,
            ["showAnimation"] = true,
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}},
            ["auraType"] = "buff",
            ["castBy"] = "me",
            ["auras"] = spells,
        })
        -- 触发 UI 更新事件，通知各模块刷新指示器
        Cell.Fire("UpdateIndicators", Cell.vars.currentLayout, indicatorName, "create", currentLayoutTable["indicators"][last+1])
        CellDB["firstRun"] = false      -- 标记首次运行已完成
        F.ReloadIndicatorList()
    end, function()
        -- 用户点击"否"：也标记完成，不再重复询问
        CellDB["firstRun"] = false
    end)
    popup:SetPoint("TOPLEFT")
    popup:Show()
end

-------------------------------------------------
-- cleuAuras
-------------------------------------------------
-- local cleuAuras = {}

-- function I.UpdateCleuAuras(t)
--     -- reset
--     wipe(cleuAuras)
--     -- insert
--     for _, c in pairs(t) do
--         local icon = select(2, F.GetSpellInfo(c[1]))
--         cleuAuras[c[1]] = {c[2], icon}
--     end
-- end

-- function I.CheckCleuAura(id)
--     return cleuAuras[id]
-- end

-------------------------------------------------
-- targetedSpells — 副本点名技能列表
-- 数据结构：spellId 数组（数字索引），按资料片/副本分组
-- 用途：在团队框体上高亮/闪烁显示被副本技能点名的队友，方便坦克和奶妈提前反应
-- 维护注意：新版本/新赛季大秘境更新后需同步添加新的点名技能 ID
-------------------------------------------------
local targetedSpells = {
    -- Cataclysm -------------------
    -- 格瑞姆巴托
    451971, -- 熔岩之拳
    451224, -- 暗影烈焰笼罩
    451364, -- 残忍打击
    451261, -- 大地之箭
    449444, -- 熔火乱舞
    450100, -- 碾碎

    -- Mists of Pandaria -----------
    -- 青龙寺 - Temple of the Jade Serpent
    106823, -- 翔龙猛袭 - Serpent Strike
    106841, -- 青龙猛袭 - Jade Serpent Strike

    -- Legion ----------------------
    -- 群星庭院 - Court of Stars
    211473, -- 暗影鞭笞 - Shadow Slash
    -- 英灵殿 - Halls of Valor
    193092, -- 放血扫击 - Bloodletting Sweep
    193659, -- 邪炽冲刺 - Felblaze Rush
    192018, -- 光明之盾 - Shield of Light
    196838, -- 血之气息 - Scent of Blood

    -- Battle for Azeroth ----------
    -- 围攻伯拉勒斯
    454438, -- 艾泽里特炸药
    272571, -- 窒息之水
    257063, -- 盐渍飞弹
    256709, -- 钢刃之歌
    -- 暴富矿区！！
    263628, -- 充能护盾
    -- 麦卡贡行动
    1215411, -- 刺破
    291928, -- 巨力震击
    292264, -- 巨力震击
    285152, -- 索敌击飞

    -- Shadowlands -----------------
    -- 通灵战潮 - Necrotic Wake
    320788, -- 冻结之缚 - Frozen Binds
    320596, -- 深重呕吐 - Heaving Retch
    338606, -- 病态凝视 - Morbid Fixation
    343556, -- 病态凝视 - Morbid Fixation
    333479, -- 吐疫
    -- 奈萨里奥的巢穴 - Castle Nathria
    344496, -- 震荡爆发 - Reverberating Eruption
    -- 赎罪大厅 - Halls of Atonement
    319941, -- 碎石之跃 - Stone Shattering Leap
    325535, -- 射击
    326829, -- 邪恶箭矢
    338003, -- 邪恶箭矢
    1235766, -- 致死打击
    1237071, -- 石拳
    322936, -- 粉碎砸击
    -- Mists of Tirna Scithe
    323057, -- 灵魂之箭
    321828, -- 拍手手
    322614, -- 心灵连接 - Mind Link
    463248, -- 排斥
    463217, -- 心能挥砍
    -- 彼界 - De Other Side
    320132, -- 暗影之怒 - Shadowfury
    332234, -- 挥发精油 - Essential Oil
    -- Spires of Ascenscion
    334053, -- 净化冲击波 - Purifying Blast
    317963, -- 知识烦扰 - Burden of Knowledge
    -- Sanguine Depths
    319713, -- 巨兽奔袭 - Juggernaut Rush
    -- 伤逝剧场 - Theater of Pain
    324079, -- 收割之镰 - Reaping Scythe
    333861, -- 回旋利刃 - Ricocheting Blade
    342675, -- 骨矛
    320644, -- 残酷连击
    323515, -- 仇恨打击
    1217138, -- 通灵箭
    -- Plaguefall
    -- 328429, -- 窒息勒压
    356924, -- 屠戮 - Carnage
    356666, -- 刺骨之寒 - Biting Cold
    -- 塔扎维什：琳彩天街
    352796, -- 代理打击
    357512, -- 狂暴冲锋
    347903, -- 垃圾邮件
    354297, -- 凌光箭
    353836, -- 凌光箭
    1240912, -- 穿刺
    350916, -- 安保猛击
    350101, -- 诅咒锁链
    355477, -- 强力脚踢
    -- 塔扎维什：索·莉亚的宏图
    355225, -- 水箭
    356843, -- 盐渍飞弹

    -- Dragonflight ----------------
    -- 化身巨龙牢窟 - Vault of the Incarnates
    375870, -- 致死石爪 - Mortal Stoneclaws
    395906, -- 电化之颌 - Electrified Jaws
    372158, -- 破甲一击 - Sundering Strike
    372056, -- 碾压 - Crush
    375580, -- 西风猛击 - Zephyr Slam
    376276, -- 震荡猛击 - Concussive Slam
    -- 亚贝鲁斯，焰影熔炉 - Aberrus, the Shadowed Crucible
    401022, -- 灾祸掠击 - Calamitous Strike
    407790, -- 身影碎离 - Sunder Shadow
    -- 阿梅达希尔，梦境之愿 - Amirdrassil, the Dream's Hope
    418637, -- 狂怒冲锋 - Furious Charge
    -- 红玉新生法池 - Ruby Life Pools
    372858, -- 灼热打击 - Searing Blows
    381512, -- 风暴猛击 - Stormslam
    -- 奈萨鲁斯 - Neltharus
    374533, -- 炽热挥舞 - Heated Swings
    377018, -- 熔火真金 - Molten Gold
    -- 蕨皮山谷 - Brackenhid Hollow
    381444, -- 野蛮冲撞 - Savage Charge
    373912, -- 腐朽打击 - Decaystrike
    -- 碧蓝魔馆 - Azure Vault
    374789, -- 注能打击 - Infused Strike
    372222, -- 奥术顺劈 - Arcane Cleave
    384978, -- 巨龙打击 - Dragon Strike
    391136, -- 肩部猛击 - Shoulder Slam
    -- 诺库德阻击战 - The Nokhud Offensive
    376827, -- 传导打击 - Conductive Strike
    376829, -- 雷霆打击 - Thunder Strike
    375937, -- 撕裂猛击 - Rending Strike
    375929, -- 野蛮打击 - Savage Strike
    376644, -- 钢铁之矛 - Iron Spear
    376865, -- 静电之矛 - Static Spear
    382836, -- 残杀 - Brutalize

    -- The War Within --------------
    -- 圣焰隐修院
    424420, -- 余烬冲击
    424414, -- 贯穿护甲
    427583, -- 忏悔
    447270, -- 掷矛
    448515, -- 神圣审判
    424421, -- 火球术
    444743, -- 连珠火球
    427357, -- 神圣惩击
    462859, -- 随意射击
    -- 艾拉-卡拉，回响之城
    439506, -- 钻地冲击
    434786, -- 蛛网箭
    438471, -- 贪食撕咬
    -- 矶石宝库
    429545, -- 噤声齿轮
    424888, -- 震地猛击
    459210, -- 暗影爪击
    428711, -- 火成岩锤
    -- 破晨号
    431491, -- 污邪斩击
    451119, -- 深渊轰击
    431303, -- 暗夜箭
    431333, -- 折磨射线
    451107, -- 迸发虫茧
    -- 尼鲁巴尔王宫
    459524, -- 致命之箭
    -- 暗焰裂口
    421277, -- 暗焰之锄
    427011, -- 暗影冲击
    422245, -- 穿岩凿
    422116, -- 鲁莽冲锋
    -- 燧酿酒庄
    432229, -- 醉酿投
    439031, -- 干杯勾拳
    436592, -- 点钞大炮
    440134, -- 蜂蜜料汁
    -- 驭雷栖巢
    445457, -- 湮灭波
    430109, -- 闪电箭
    430238, -- 虚空箭
    474031, -- 虚空碾压
    430805, -- 弧形虚空
    -- 水闸行动
    1213805, -- 射钉枪
    465595, -- 闪电箭
    468631, -- 鱼叉
    459779, -- 滚桶冲锋
    459799, -- 重击
    473690, -- 动能胶质炸药
    473351, -- 电气重碾
    469478, -- 淤泥之爪
    466190, -- 雷霆重拳
    1214468, -- 特技射击
    -- 奥尔达尼生态圆顶
    1229474, -- 啃噬
    1235368, -- 奥术猛袭
    1229510, -- 弧光震击
    1222815, -- 奥术箭
    1221483, -- 电弧能量
    1219482, -- 裂隙利爪
    1226111, -- 不稳定的喷发
}

-- 获取默认点名法术 ID 列表（供指示器配置模块读取）
function I.GetDefaultTargetedSpellsList()
    return targetedSpells
end

-- 获取默认点名法术的发光选项（高亮闪烁配置）
-- 返回格式：{"发光类型", {颜色RGB}, 时长, 间隔, 大小, 厚度}
function I.GetDefaultTargetedSpellsGlow()
    return {"Pixel", {0.95,0.95,0.32,1}, 9, 0.25, 8, 2}
end

-------------------------------------------------
-- Actions — 默认快捷动作（药水/治疗石）
-- 数据结构：{ { spellId, { 点击绑定, 颜色 } }, ... }
--   点击绑定："A" = 左键, "C3" = 中键（如游戏内的 ClickCast 绑定）
--   颜色：RGB 三元组，用于指示器按钮着色
-- 用途：在团队框体上创建快捷使用按钮（如点击队友框体直接使用治疗石）
-- I.ConvertActions 将其转换为 { [spellId] = { 绑定, 颜色 } } 便于快速查找
-------------------------------------------------
local actions = {
    {
        6262, -- 治疗石 - Healthstone
        {"A", {0.4, 1, 0}},      -- 左键点击使用，绿色按钮
    },
    {
        431416, -- 阿加治疗药水 - Algari Healing Potion
        {"A", {1, 0.1, 0.1}},    -- 左键点击使用，红色按钮
    },
    {
        431932, -- 淬火药水 - Tempered Potion
        {"C3", {1, 1, 0}},       -- 中键点击使用，黄色按钮
    },
}

-- 获取默认动作列表（供设置面板加载）
function I.GetDefaultActions()
    return actions
end

-- 将 {数组} 格式的动作列表转换为 { [spellId] = {绑定, 颜色} } 的查找表格式
-- 方便运行时通过 spellId 快速定位对应的点击绑定和按钮颜色
function I.ConvertActions(db)
    local temp = {}
    for _, t in pairs(db) do
        temp[t[1]] = t[2]
    end
    return temp
end

-------------------------------------------------
-- crowdControls — 群体控制技能列表
-- 数据结构：{ [className] = { [spellId] = trackByName (bool) } }
--   - trackByName = true  → 按法术名称追踪（推荐，兼容多语言客户端）
--   - trackByName = false → 按法术 ID 追踪（特殊场景，如天赋被动效果）
-- 包含 "UNCATEGORIZED" 键：存放种族天赋控制技能（不限于特定职业）
-- 用途：在团队框体上显示队友施放的控制技能（眩晕、迷惑、恐惧等），避免重复控制
-------------------------------------------------
local crowdControls = { -- true: 按名称追踪, false: 按 ID 追踪
    ["DEATHKNIGHT"] = {
        [47476] = true, -- 绞袭 - Strangulate (PVP)
        [91800] = true, -- 撕扯 - Gnaw
        [207167] = true, -- 致盲冰雨 - Blinding Sleet
        [210128] = true, -- 复苏 - Reanimation
        [221562] = true, -- 窒息 - Asphyxiate
        [287254] = false, -- 寒冬死神 - Dead of Winter
        [377048] = true, -- 绝对零度 - Absolute Zero
    },

    ["DEMONHUNTER"] = {
        [179057] = true, -- 混乱新星 - Chaos Nova
        [205630] = true, -- 伊利丹之握 - Illidan's Grasp
        [204490] = true, -- 沉默咒符 - Sigil of Silence
        [207684] = true, -- 悲苦咒符 - Sigil of Misery
        [211881] = true, -- 邪能爆发 - Fel Eruption
        [217832] = true, -- 禁锢 - Imprison
        -- [213491] = true, -- 恶魔践踏
    },

    ["DRUID"] = {
        [99] = true, -- 夺魂咆哮 - Incapacitating Roar
        [2637] = true, -- 休眠 - Hibernate
        [5211] = true, -- 蛮力猛击 - Mighty Bash
        [22570] = true, -- 割碎 - Maim
        [33786] = true, -- 旋风 - Cyclone
        [81261] = true, -- 日光术 - Solar Beam
        [127797] = true, -- 乌索尔旋风 - Ursol's Vortex
        [163505] = false, -- 斜掠 - Rake
        [209749] = true, -- 精灵虫群 - Faerie Swarm
        [202244] = true, -- 蛮力冲锋 - Overrun
        [410065] = false, -- 活性树脂 - Reactive Resin
    },

    ["EVOKER"] = {
        [360806] = true, -- 梦游 - Sleep Walk
        [372245] = true, -- 天空霸主 - Terror of the Skies
        [408544] = true, -- 震地猛击 - Seismic Slam
    },

    ["HUNTER"] = {
        [1513] = true, -- 恐吓野兽 - Scare Beast
        [3355] = true, -- 冰冻陷阱 - Freezing Trap
        [24394] = true, -- 胁迫 - Intimidation
        [117526] = true, -- 束缚射击 - Binding Shot
        [213691] = true, -- 驱散射击 - Scatter Shot
        [357021] = false, -- 连续震荡 - Consecutive Concussion
        [407032] = true, -- 粘稠焦油炸弹 - Sticky Tar Bomb
    },

    ["MAGE"] = {
        [118] = true, -- 变形术 - Polymorph
        [31661] = true, -- 龙息术 - Dragon's Breath
        [82691] = true, -- 冰霜之环 - Ring of Frost
        [383121] = true, -- 群体变形 - Mass Polymorph
        [389831] = false, -- 积雪 - Snowdrift
    },

    ["MONK"] = {
        [115078] = true, -- 分筋错骨 - Paralysis
        [119381] = true, -- 扫堂腿 - Leg Sweep
        [198909] = true, -- 赤精之歌 - Song of Chi-Ji
        [202274] = true, -- 热酿 - Hot Trub
        [202346] = true, -- 醉上加醉 - Double Barrel
        [233759] = true, -- 抓钩武器 - Grapple Weapon (PVP)
    },

    ["PALADIN"] = {
        [853] = true, -- 制裁之锤 - Hammer of Justice
        [10326] = true, -- 超度邪恶 - Turn Evil
        [20066] = true, -- 忏悔 - Repentance
        [105421] = true, -- 盲目之光 - Blinding Light
        [234299] = true, -- 制裁之拳 - Fist of Justice
        [255941] = false, -- 灰烬觉醒 - Wake of Ashes
    },

    ["PRIEST"] = {
        [605] = true, -- 精神控制 - Mind Control
        [8122] = true, -- 心灵尖啸 - Psychic Scream
        [9484] = true, -- 束缚亡灵 - Shackle Undead
        [15487] = true, -- 沉默 - Silence
        [64044] = true, -- 心灵惊骇 - Psychic Horror
        [88625] = true, -- 圣言术-罚 - Holy Word: Chastise
        -- [226943] = true, -- 心灵炸弹
    },

    ["ROGUE"] = {
        [408] = true, -- 肾击 - Kidney Shot
        [1776] = true, -- 凿击 - Gouge
        [1833] = true, -- 偷袭 - Cheap Shot
        [2094] = true, -- 致盲 - Blind
        [6770] = true, -- 闷棍 - Sap
        [207777] = true, -- 卸除武装 - Dismantle (PVP)
        [212183] = true, -- 烟雾弹 - Smoke Bomb
    },

    ["SHAMAN"] = {
        [51514] = true, -- 妖术 - Hex
        [77505] = true, -- 地震术 - Earthquake
        [118345] = true, -- 粉碎 - Pulverize
        [118905] = true, -- 静电充能 - Static Charge
        [197214] = true, -- 裂地术 - Sundering
        [305485] = true, -- 闪电磁索 - Lightning Lasso
    },

    ["WARLOCK"] = {
        [710] = true, -- 放逐术 - Banish
        [5484] = true, -- 恐惧嚎叫 - Howl of Terror
        [5782] = true, -- 恐惧 - Fear
        [6358] = true, -- 诱惑 - Seduction
        [6789] = true, -- 死亡缠绕 - Mortal Coil
        [22703] = true, -- 地狱火觉醒 - Infernal Awakening
        [30283] = true, -- 暗影之怒 - Shadowfury
        [89766] = true, -- 巨斧投掷 - Axe Toss
        [196364] = false, -- 痛苦无常 - Unstable Affliction
        [213688] = true, -- 邪能顺劈 - Fel Cleave
    },

    ["WARRIOR"] = {
        [5246] = true, -- 破胆怒吼 - Intimidating Shout
        [132168] = true, -- 震荡波 - Shockwave
        [132169] = true, -- 风暴之锤 - Storm Bolt
        [236077] = true, -- 缴械 - Disarm (PVP)
    },

    ["UNCATEGORIZED"] = {
        [20549] = true, -- 战争践踏 - War Stomp
        [107079] = true, -- 震山掌 - Quaking Palm
        [255723] = true, -- 蛮牛冲撞 - Bull Rush
        [287712] = true, -- 强力一击 - Haymaker
    }
}

function I.GetCrowdControls()
    return crowdControls
end

-- 运行时缓存表：builtInCrowdControls 存放内置群控（过滤用户禁用后），customCrowdControls 存放用户自定义群控
-- 注意：自定义群控按名称存储（与内置减伤/外部冷却按 ID 存储不同），便于用户输入自定义法术
local builtInCrowdControls = {}
local customCrowdControls = {}

-- 更新群控技能缓存（用户设置变更时调用）
-- t["disabled"]: 用户禁用的内置法术 ID 集合
-- t["custom"]: 用户自定义添加的法术 ID 列表（会自动转换为名称存储）
function I.UpdateCrowdControls(t)
    -- 处理内置法术：遍历所有职业（含 "UNCATEGORIZED"），跳过被用户禁用的法术
    wipe(builtInCrowdControls)
    for class, spells in pairs(crowdControls) do
        for id, trackByName in pairs(spells) do
            if not t["disabled"][id] then -- 未被用户禁用
                if trackByName then
                    local name = F.GetSpellInfo(id)
                    if name then
                        builtInCrowdControls[name] = true
                    end
                else
                    builtInCrowdControls[id] = true
                end
            end
        end
    end

    -- 处理用户自定义法术：通过 spellId 获取名称后按名称存储
    -- 与内置减伤/外部冷却不同，自定义群控统一按名称存储以便跨版本匹配
    wipe(customCrowdControls)
    for _, id in pairs(t["custom"]) do
        local name = F.GetSpellInfo(id)
        if name then
            customCrowdControls[name] = true
        end
    end
end

-- 判断某个法术是否为群控技能
-- 参数 name, id 来自战斗事件（CLEU/UNIT_AURA）
-- Midnight 12.0.0+ 防护策略：
--   - 两者皆为 secret → 安全退出（完全无法识别）
--   - 仅 name 为 secret → 仅按 id 匹配（只查 builtInCrowdControls 的 id 键）
--   - 仅 id 为 secret → 按 name 匹配（查 builtInCrowdControls + customCrowdControls 的 name 键）
--   - 两者都可见 → 同时按 name 和 id 匹配
function I.IsCrowdControls(name, id)
    -- Midnight SecretValue 防护：name 和 id 皆为 secret 时才安全退出
    local nameSecret = issecretvalue and issecretvalue(name)
    local idSecret = issecretvalue and issecretvalue(id)
    if nameSecret and idSecret then return end
    -- 仅 name 为 secret：只能按 id 匹配内置群控
    if nameSecret then return builtInCrowdControls[id] end
    -- 仅 id 为 secret：只能按 name 匹配（内置 + 自定义）
    if idSecret then return builtInCrowdControls[name] or customCrowdControls[name] end
    -- 两者都可见：同时按 name 和 id 匹配，任一命中即可
    return builtInCrowdControls[name] or builtInCrowdControls[id] or customCrowdControls[name]
end
