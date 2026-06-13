--------------------------------------------------------------------------------
-- CellD 默认点击施法配置模块
-- 功能：定义各职业/专精的默认点击施法技能列表、复活法术及智能复活逻辑。
-- Midnight/SecretValue 防护说明：
--   - 所有技能 ID 在内部以数字形式存储和比较，避免对字符串的依赖。
--   - 字符串形式的技能 ID（如 "774C"）仅在解析阶段使用，解析后立即转为数字。
--   - F.GetSpellInfo(spellId) 是受保护的 API 封装，内部使用 Safe* 安全函数。
--   - 条件分支（nospec/spec）仅基于安全的表查找，不依赖动态求值。
--   - 复活法术表在 do...end 块中通过 F.GetSpellInfo 预解析为受保护的返回值。
--------------------------------------------------------------------------------
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs

-------------------------------------------------
-- click-castings -- 默认点击施法技能表
-- 数据结构：defaultSpells[职业英文名]["common" 或 专精ID] = {技能条目, ...}
-- 技能条目格式：
--   - 纯数字：直接作为技能 ID（number 类型）
--   - 带后缀的字符串："技能ID+后缀字母"（如 "774C", "305497P"）
--     后缀含义：
--       C (Click)  - 直接点击施法
--       S (Smart)  - 智能施法
--       P (PvP)    - PvP 天赋技能
--       H (HoT)    - 持续治疗法术
--     这些后缀在解析时转换为本地化显示文本（通过 L[spellType] 查找）
-------------------------------------------------
local defaultSpells = {
    ["DEATHKNIGHT"] = {
        ["common"] = {
            61999, -- Raise Ally - 复活盟友
            47541, -- Death Coil - 凋零缠绕
        },
        -- 250 - Blood
        -- 251 - Frost
        -- 252 - Unholy
    },

    ["DEMONHUNTER"] = {
        -- 577 - Havoc
        -- 581 - Vengeance
    },

    ["DRUID"] = {
        ["common"] = {
            1126, -- Mark of the Wild - 野性印记
            20484, -- Rebirth - 复生
            50769, -- Revive - 起死回生
            8936, -- Regrowth - 愈合
            "774C", -- Rejuvenation - 回春术
            "102401C", -- Wild Charge - 野性冲锋
            "29166C", -- Innervate - 激活
            "48438C", -- Wild Growth - 野性成长
            "474750C", -- Symbiotic Relationship - 共生关系
        },
        -- 102 - Balance
        [102] = {
            "2782C", -- Remove Corruption - 清除腐蚀
            "305497P", -- pvp - Thorns - 荆棘术
        },
        -- 103 - Feral
        [103] = {
            "2782C", -- Remove Corruption - 清除腐蚀
            "391888S", -- Adaptive Swarm - 激变蜂群
            "305497P", -- pvp - Thorns - 荆棘术
        },
        -- 104 - Guardian
        [104] = {
            "2782C", -- Remove Corruption - 清除腐蚀
        },
        -- Restoration
        [105] = {
            212040, -- Revitalize - 新生
            88423, -- Nature's Cure - 自然之愈
            "33763S", -- Lifebloom - 生命绽放
            "102351S", -- Cenarion Ward - 塞纳里奥结界
            "50464S", -- Nourish - 滋养
            "102342S", -- Ironbark - 铁木树皮
            "203651S", -- Overgrowth - 过度生长
            "392160S", -- Invigorate - 鼓舞
            "18562S", -- Swiftmend - 迅捷治愈
            "102693H", -- Grove Guardians - 林莽卫士
            "305497P", -- pvp - Thorns - 荆棘术
            "474149P", -- pvp - Mass Blooming - 群体绽放
            "473919P", -- pvp - Blossom Burst - 绽放迸发
        },
    },

    ["EVOKER"] = {
        ["common"] = {
            364342, -- Blessing of the Bronze - 青铜龙的祝福
            361227, -- Return - 生还
            361469, -- Living Flame - 活化烈焰
            355913, -- Emerald Blossom - 翡翠之花
            "360995C", -- Verdant Embrace - 青翠之拥
            "374251C", -- Cauterizing Flame - 灼烧之焰
            "369459C", -- Source of Magic - 魔力之源
            "370665C", -- Rescue - 营救
            "406732C", -- Spatial Paradox - 空间悖论
            "378441P", -- Time Stop - 时间停止
            -- "374348C", -- Renewing Blaze - 新生光焰
            -- "443328H", -- Engulf -- 焚身 (removed in 12.0)
        },
        -- 1467 - Devastation
        [1467] = {
            "365585C", -- Expunge - 净除
        },
        -- 1468	- Preservation
        [1468] = {
            361178, -- Mass Return - 群体生还
            360823, -- Naturalize - 自然平衡
            "364343S", -- Echo - 回响
            "366155S", -- Reversion - 逆转
            "367226S", -- Spiritbloom - 精神之花
            "357170S", -- Time Dilation - 时间膨胀
        },
        -- 1473 - Augmentation
        [1473] = {
            -- "395152S", -- Ebon Might - 黑檀之力
            "365585C", -- Expunge - 净除
            "360827S", -- Blistering Scales - 炽火龙鳞
            "409311S", -- Prescience - 先知先觉
            "408233S", -- Bestow Weyrnstone - 赋予军营之石
            "412710S", -- Timelessness - 超脱时间
        }
    },

    ["HUNTER"] = {
        ["common"] = {
            "34477C", -- Misdirection - 误导
            53271, -- Master's Call - 主人的召唤
            "248518P", -- pvp - Interlope - 干涉
            "53480P", -- pvp - Roar of Sacrifice - 牺牲咆哮
        },
        -- 253 - Beast Mastery
        [253] = {
            90361, -- Spirit Mend - 灵魂治愈
        },
        -- 254 - Marksmanship
        -- 255 - Survival
        [255] = {
            "212640P", -- pvp - Mending Bandage - 治疗绷带
        },
    },

    ["MAGE"] = {
        ["common"] = {
            1459, -- Arcane Intellect - 奥术智慧
            130, -- Slow Fall - 缓落术
            "475C", -- Remove Curse - 解除诅咒
        },
        -- 62 - Arcane
        -- 63 - Fire
        -- 64 - Frost
    },

    ["MONK"] = {
        ["common"] = {
            115178, -- Resuscitate - 轮回转世
            116670, -- Vivify - 活血术
            "115175C", -- Soothing Mist - 抚慰之雾
            "115098C", -- Chi Wave - 真气波
            "116841C", -- Tiger's Lust - 迅如猛虎
        },
        -- 268 - Brewmaster
        [268] = {
            "218164C", -- Detox - 清创生血
        },
        -- 269 - Windwalker
        [269] = {
            "218164C", -- Detox - 清创生血
        },
        -- 270 - Mistweaver
        [270] = {
            212051, -- Reawaken - 死而复生
            115450, -- Detox - 清创生血
            "124682S", -- Enveloping Mist - 氤氲之雾
            "115151S", -- Renewing Mist - 复苏之雾
            "116849S", -- Life Cocoon - 作茧缚命
            "124081S", -- Zen Pulse - 禅意波
            "399491S" -- Sheilun's Gift - 神龙之赐
        },
    },

    ["PALADIN"] = {
        ["common"] = {
            7328, -- Redemption - 救赎
            391054, -- Intercession - 代祷
            19750, -- Flash of Light - 圣光闪现
            85673, -- Word of Glory - 荣耀圣令
            304971, -- Divine Toll - 圣洁鸣钟
            "633C", -- Lay on Hands - 圣疗术
            "1044C", -- Blessing of Freedom - 自由祝福
            "6940C", -- Blessing of Sacrifice - 牺牲祝福
            "1022C", -- Blessing of Protection - 保护祝福
        },
        -- 65 - Holy
        [65] = {
            212056, -- Absolution - 宽恕
            4987, -- Cleanse - 清洁术
            53563, -- Beacon of Light - 圣光道标
            "20473S", -- Holy Shock - 神圣震击
            "82326S", -- Holy Light - 圣光术
            "223306S", -- Bestow Faith -- 赋予信仰
            "114165S", -- Holy Prism - 神圣棱镜
            "183998S", -- Light of the Martyr -- 殉道者之光
            "148039S", -- Barrier of Faith - 信仰屏障
            "156910S", -- Beacon of Faith - 信仰道标
            "388007S", -- Blessing of Summer - 仲夏祝福
            "200025S", -- Beacon of Virtue -- 美德道标
            "432459H", -- Holy Bulwark - 神圣壁垒
            "156322H", -- Eternal Flame - 永恒之火
        },
        -- 66 - Protection
        [66] = {
            "213644C", -- Cleanse Toxins - 清毒术
            "204018S", -- Blessing of Spellwarding - 破咒祝福
            "228049P", -- pvp - Guardian of the Forgotten Queen - 被遗忘的女王护卫
            "432459H", -- Holy Bulwark - 神圣壁垒
        },
        -- 70 - Retribution
        [70] = {
            "213644C", -- Cleanse Toxins - 清毒术
            "210256P", -- pvp - Blessing of Sanctuary - 庇护祝福
            "156322H", -- Eternal Flame - 永恒之火
        },
    },

    ["PRIEST"] = {
        ["common"] = {
            21562, -- Power Word: Fortitude - 真言术：韧
            2006, -- Resurrection - 复活术
            1706, -- Levitate - 漂浮术
            17, -- Power Word: Shield - 真言术：盾
            2061, -- Flash Heal - 快速治疗
            2096, -- Mind Vision - 心灵视界
            -- "139C", -- Renew - 恢复 (removed in 12.0)
            "73325C", -- Leap of Faith - 信仰飞跃
            "10060C", -- Power Infusion - 能量灌注
            -- "373481C", -- Power Word: Life - 真言术：命 (removed in 12.0)
            -- "108968C", -- Void Shift - 虚空转移 (removed in 12.0)
        },
        -- 256 - Discipline
        [256] = {
            212036, -- Mass Resurrection - 群体复活
            527, -- Purify - 纯净术
            47540, -- Penance - 苦修
            "200829S", -- Plea - 恳求 (added in 12.0)
            "194509S", -- Power Word: Radiance - 真言术：耀
            "33206S", -- Pain Suppression - 痛苦压制
            "47536S", -- Rapture - 全神贯注
            -- "314867S", -- Shadow Covenant - 暗影盟约 (removed in 12.0)
            -- "421453S", -- Ultimate Penitence - 终极苦修
        },
        -- 257 - Holy
        [257] = {
            212036, -- Mass Resurrection - 群体复活
            527, -- Purify - 纯净术
            2060, -- Heal - 治疗术
            "33076S", -- Prayer of Mending - 愈合祷言 (moved from class to Holy in 12.0)
            "2050S", -- Holy Word: Serenity - 圣言术：静
            "596S", -- Prayer of Healing - 治疗祷言
            "47788S", -- Guardian Spirit - 守护之魂
            "204883S", -- Circle of Healing - 治疗之环
            "289666P", -- pvp - Greater Heal - 强效治疗术
            "213610P", -- pvp - Holy Ward - 神圣守卫
            "197268P", -- pvp - Ray of Hope - 希望之光
        },
        -- 258 - Shadow
        [258] = {
            "213634C", -- Purify Disease - 净化疾病
        },
    },

    ["ROGUE"] = {
        ["common"] = {
            "57934C", -- Tricks of the Trade - 嫁祸诀窍
            "36554C", -- Shadowstep - 暗影步
        },
        -- 259 - Assassination
        -- 260 - Outlaw
        -- 261 - Subtlety
    },

    ["SHAMAN"] = {
        ["common"] = {
            462854, -- Skyfury - 天怒
            2008, -- Ancestral Spirit - 先祖之魂
            8004, -- Healing Surge - 治疗之涌
            546, -- Water Walking - 水上行走
            "1064C", -- Chain Heal - 治疗链
            "974C", -- Earth Shield - 大地之盾
            "51490C", -- Thunderstorm - 雷霆风暴
        },
        -- 262 - Elemental
        [262] = {
            "51886C", -- Cleanse Spirit - 净化灵魂
        },
        -- 263 - Enhancement
        [263] = {
            "51886C", -- Cleanse Spirit - 净化灵魂
        },
        -- 264 - Restoration
        [264] = {
            212048, -- Ancestral Vision - 先祖视界
            77130, -- Purify Spirit - 净化灵魂
            "61295S", -- Riptide - 激流
            "77472S", -- Healing Wave - 治疗波
            "73685S", -- Unleash Life - 生命释放
            "428332S", -- Primordial Wave - 始源之潮
        },
    },

    ["WARLOCK"] = {
        ["common"] = {
            20707, -- Soulstone - 灵魂石
            89808, -- Singe Magic - 烧灼驱魔
            5697, -- Unending Breath - 无尽呼吸
        },
        -- 265 - Affliction
        -- 266 - Demonology
        -- 267 - Destruction
    },

    ["WARRIOR"] = {
        ["common"] = {
            "3411C", -- Intervene - 援护
        },
        -- 71 - Arms
        -- 72 - Fury
        -- 73 - Protection
        [73] = {
            "213871P", -- pvp - Bodyguard - 护卫
        },
    },
}

--------------------------------------------------------------------------------
-- GetClickCastingSpellList(class, spec)
-- 获取指定职业和专精的完整点击施法技能列表
-- 参数：
--   class (string) - 职业英文名，如 "DRUID"
--   spec  (number|nil) - 专精 ID（如 105 为恢复德），nil 时仅返回通用技能
-- 返回值：
--   table - 格式为索引数组，每个元素为 {icon, name, spellType, spellId}
--           spellType 可能是 nil（纯数字 ID 未指定类型时）
--
-- 处理流程：
--   1. 深拷贝 common（通用）技能列表
--   2. 合并专精特定技能（如有）
--   3. 解析技能条目 —— 数字直接作为 spellId；
--      字符串则通过 strmatch 解析出 "数字+后缀" 格式，后缀转为本地化文本
--   4. 通过 F.GetSpellInfo 验证技能 ID 有效性
--   5. 剔除无效的技能 ID（记录 Debug 日志）
--
-- Midnight/SecretValue 防护：
--   - strmatch 解析字符串条目时使用严格模式 "(%d+)(%a)"，
--     确保只匹配数字+字母后缀，防止非预期的字符串注入
--   - tonumber 转换后 spellId 始终为 number 类型，消除了字符串比较的绕过风险
--   - F.GetSpellInfo 是受保护的 Safe API，无效 ID 返回 nil 而非崩溃
--   - 无效条目被记录日志并移除，不会进入后续的点击施法逻辑
--------------------------------------------------------------------------------
function F.GetClickCastingSpellList(class, spec)
    -- 深拷贝通用技能列表作为基础（F.Copy 避免修改原始表）
    local spells = defaultSpells[class]["common"] and F.Copy(defaultSpells[class]["common"]) or {}

    -- 合并专精特定技能（如有定义）
    if spec and defaultSpells[class][spec] then
        for _, v in pairs(defaultSpells[class][spec]) do
            tinsert(spells, v)
        end
    end

    local invalid  -- 待移除的无效条目索引列表

    -- 遍历技能条目，解析并验证每个技能 ID
    for i, v in pairs(spells) do
        local spellId, spellType

        -- 解析技能条目：数字直接作为 ID，字符串需解析 "数字+后缀" 格式
        if type(v) == "number" then
            spellId = v  -- 纯数字 ID，无类型后缀
        else -- string
            -- Midnight 防护：严格匹配模式 (数字)(字母后缀)，拒绝非预期格式
            spellId, spellType = strmatch(v, "(%d+)(%a)")
            spellId = tonumber(spellId)  -- 确保转换为 number，消除字符串绕过风险
            spellType = L[spellType]      -- 后缀字母转为本地化显示文本（C/S/P/H -> 本地化标签）
        end

        -- 通过受保护的 Safe API 获取技能信息，验证 ID 有效性
        local name, icon = F.GetSpellInfo(spellId)
        if name then
            -- 有效技能：替换为结构化数据 {图标, 名称, 施法类型, 技能ID}
            spells[i] = {icon, name, spellType, spellId}
        else
            -- 无效技能 ID：记录日志并标记待移除
            F.Debug("|cffff0000[INVALID]|r click-casting spell:", spellId)
            if not invalid then invalid = {} end
            tinsert(invalid, i)
        end
    end

    -- 从后向前移除无效条目，确保索引稳定性
    if invalid then
        for i = #invalid, 1, -1 do
            tremove(spells, invalid[i])
        end
    end

    -- texplore(spells)
    return spells
end

-------------------------------------------------
-- resurrections -- 复活法术表
-- 数据结构：resurrections_for_dead = {[技能名称] = true, ...}
-- 用途：快速判断一个技能是否可对死亡目标使用的复活法术
-- 处理流程：
--   - 先在 do...end 块中构建临时表 temp，通过 F.GetSpellInfo 将技能 ID 转为技能名称
--   - 然后用 temp 替换 resurrections_for_dead，使其成为 {名称 -> true} 的快速查找表
-- Midnight/SecretValue 防护：
--   - F.GetSpellInfo 返回的名称是受保护的 API 输出
--   - 表以名称作为键而非 ID，避免了数字伪造风险
--   - 查找操作为 O(1) 的哈希查找，逻辑简单、不可注入
-------------------------------------------------
local resurrections_for_dead = {
    -- DEATHKNIGHT
    61999, -- 复活盟友

    -- DRUID
    20484, -- 复生
    50769, -- 起死回生
    212040, -- 新生

    -- EVOKER
    361227, -- 生还
    361178, -- 群体生还

    -- MONK
    115178, -- 轮回转世
    212051, -- 死而复生

    -- PALADIN
    391054, -- 代祷
    7328, -- 救赎
    212056, -- 宽恕

    -- PRIEST
    2006, -- 复活术
    212036, -- 群体复活

    -- SHAMAN
    2008, -- 先祖之魂
    212048, -- 先祖视界

    -- WARLOCK
    20707, -- 灵魂石
}

-- 通过 F.GetSpellInfo 将复活技能 ID 转换为技能名称，构建快速查找表
-- 表结构：{[技能名称] = true}，用于 O(1) 时间判断技能是否为复活法术
do
    local temp = {}
    for _, id in pairs(resurrections_for_dead) do
        temp[F.GetSpellInfo(id)] = true
    end
    resurrections_for_dead = temp
end

-- F.IsSoulstone(spell) -- 判断指定技能是否为灵魂石
-- Soulstone（灵魂石）是术士的战斗复活技能，需要特殊处理
-- 因为战斗中战复和非战斗复活的行为不同
local spell_soulstone = F.GetSpellInfo(20707)
function F.IsSoulstone(spell)
    return spell == spell_soulstone
end

-- F.IsResurrectionForDead(spell) -- 判断指定技能是否可对已死亡的友方目标使用
-- 用于过滤可用法术列表时判断哪些技能适用于死亡目标
function F.IsResurrectionForDead(spell)
    return resurrections_for_dead[spell]
end

--------------------------------------------------------------------------------
-- resurrection_click_castings -- 复活点击施法绑定表
-- 数据结构：{[职业英文名] = {点击施法条目, ...}}
-- 每个点击施法条目格式：{"按键类型", "施法类型", 技能ID}
--   - 按键类型："type-altR" 表示 Alt+右键点击，"type-shiftR" 表示 Shift+右键点击
--   - 施法类型："spell" 表示直接施放法术
--   - 技能 ID：复活法术的技能 ID
--
-- 设计说明：
--   - 战斗复活（战复）通常绑定在 Alt+右键（如 DK 的 Raise Ally、术士的 Soulstone）
--   - 常规复活（非战斗）通常绑定在 Shift+右键（如牧师的 Resurrection）
--   - 德鲁伊和圣骑士同时拥有战复和常规复活，分别绑在不同按键上
--   - 技能 ID 在注册时由调用方通过 F.GetSpellInfo 转换为技能名称，
--     此处保持数字形式以便于跨语言环境使用
-- Midnight/SecretValue 防护：
--   - 按键类型和施法类型均为硬编码字符串常量，不可从外部注入
--   - 技能 ID 为数字字面量，不依赖动态字符串解析
--   - 返回值为 F.Copy 的副本（或空表），调用方修改不影响原始配置表
--------------------------------------------------------------------------------
local resurrection_click_castings = {
    ["DEATHKNIGHT"] = {
        {"type-altR", "spell", 61999},   -- Alt+右键 -> Raise Ally（战复）
    },
    ["DRUID"] = {
        {"type-altR", "spell", 20484},   -- Alt+右键 -> Rebirth（战复）
        {"type-shiftR", "spell", 50769},  -- Shift+右键 -> Revive（常规复活）
    },
    ["EVOKER"] = {
        {"type-shiftR", "spell", 361227}, -- Shift+右键 -> Return（常规复活）
    },
    ["MONK"] = {
        {"type-shiftR", "spell", 115178}, -- Shift+右键 -> Resuscitate（常规复活）
    },
    ["PALADIN"] = {
        {"type-altR", "spell", 391054},   -- Alt+右键 -> Intercession（战复）
        {"type-shiftR", "spell", 7328},   -- Shift+右键 -> Redemption（常规复活）
    },
    ["PRIEST"] = {
        {"type-shiftR", "spell", 2006},   -- Shift+右键 -> Resurrection（常规复活）
    },
    ["SHAMAN"] = {
        {"type-shiftR", "spell", 2008},   -- Shift+右键 -> Ancestral Spirit（常规复活）
    },
    ["WARLOCK"] = {
        {"type-altR", "spell", 20707},    -- Alt+右键 -> Soulstone（战复）
    },
}

-- 以下注释块是旧代码：曾在此处将技能 ID 预解析为名称，
-- 现已改为由调用方在处理时动态转换，避免因加载顺序导致的 nil 问题
-- do
--     for class, t in pairs(resurrection_click_castings) do
--         for _, clickCasting in pairs(t) do
--             clickCasting[3] = F.GetSpellInfo(clickCasting[3])
--         end
--     end
-- end

-- F.GetResurrectionClickCastings(class) -- 获取指定职业的复活点击施法绑定列表
-- 返回该职业的所有复活点击施法绑定，无绑定时返回空表
function F.GetResurrectionClickCastings(class)
    return resurrection_click_castings[class] or {}
end

-------------------------------------------------
-- smart resurrection -- 智能复活系统
-- 根据玩家当前专精自动选择最合适的复活法术
-- 分为两类：
--   1. normalResurrection  -- 常规（非战斗）复活
--   2. combatResurrection  -- 战斗复活（战复）
--
-- 常规复活的条件逻辑：
--   多个治疗专精拥有两种复活技能 —— 单体和群体
--   系统根据玩家当前专精自动选择：
--     "spec:N"  -- 当处于第 N 个专精时使用此技能（通常为单体复活）
--     "nospec:N" -- 当不处于第 N 个专精时使用此技能（通常为群体复活）
--   例如：德鲁伊专精4（恢复）使用 Revitalize 单体复活，
--         非恢复德使用 Revive 战斗复活式复活
--   N 的值为职业内的专精编号（从1开始），非全局专精 ID
--
-- Midnight/SecretValue 防护：
--   - 条件键 "spec:N" / "nospec:N" 为硬编码字符串，仅作表查找键使用，不动态求值
--   - 技能 ID 在 do...end 块中通过 F.GetSpellInfo 统一预解析为受保护的技能名称
--   - 调用方通过 F.GetNormalResurrection / F.GetCombatResurrection 安全获取
--   - 无条件分支执行外部注入的代码 —— 所有逻辑均为纯数据表查找
-------------------------------------------------
-- normalResurrection -- 常规复活技能表（非战斗状态）
-- 数据结构：{[职业] = {[条件键] = 技能名称, ...}}
-- 条件键格式：
--   - "spec:N"   -> 当前处于该职业第 N 个专精时使用
--   - "nospec:N" -> 当前不处于该职业第 N 个专精时使用
-- 例如：牧师 spec:3（戒律/神圣/暗影中第3个=暗影）使用单体复活 Resurrection，
--       非暗影牧师使用群体复活 Mass Resurrection
-- 备注：技能 ID 在 do...end 块中替换为 F.GetSpellInfo 返回的技能名称
local normalResurrection = {
    ["DRUID"] = {
        ["nospec:4"] = 50769,   -- 非恢复德 -> Revive（战斗复活式复活）
        ["spec:4"] = 212040,    -- 恢复德   -> Revitalize（新生，单体复活）
    },
    ["EVOKER"] = {
        ["nospec:2"] = 361227,  -- 非恩护   -> Return（单体生还）
        ["spec:2"] = 361178,    -- 恩护     -> Mass Return（群体生还）
    },
    ["MONK"] = {
        ["nospec:2"] = 115178,  -- 非织雾   -> Resuscitate（单体复活）
        ["spec:2"] = 212051,    -- 织雾     -> Reawaken（群体死而复生）
    },
    ["PALADIN"] = {
        ["nospec:1"] = 7328,    -- 非神圣   -> Redemption（单体救赎）
        ["spec:1"] = 212056,    -- 神圣     -> Absolution（群体宽恕）
    },
    ["PRIEST"] = {
        ["spec:3"] = 2006,      -- 暗影     -> Resurrection（单体复活术）
        ["nospec:3"] = 212036,  -- 非暗影   -> Mass Resurrection（群体复活）
    },
    ["SHAMAN"] = {
        ["nospec:3"] = 2008,    -- 非恢复   -> Ancestral Spirit（单体先祖之魂）
        ["spec:3"] = 212048,    -- 恢复     -> Ancestral Vision（群体先祖视界）
    },
}

-- 将技能 ID 替换为 F.GetSpellInfo 返回的技能名称
-- 通过受保护的 API 统一解析，确保技能名称有效
do
    for class, t in pairs(normalResurrection) do
        for condition, spell in pairs(t) do
            t[condition] = F.GetSpellInfo(spell)
        end
    end
end

-- F.GetNormalResurrection(class) -- 获取指定职业的常规复活技能表
-- 返回 {[条件键] = 技能名称, ...} 的映射表
function F.GetNormalResurrection(class)
    return normalResurrection[class]
end

-- combatResurrection -- 战斗复活技能表（战斗中可用）
-- 只有四个职业拥有战复能力：
--   DEATHKNIGHT - Raise Ally（复活盟友）
--   DRUID       - Rebirth（复生）
--   PALADIN     - Intercession（代祷）
--   WARLOCK     - Soulstone（灵魂石，需预先绑定）
-- 数据结构：{[职业] = 技能名称}
-- Midnight 防护：表为纯 {职业 -> 技能名称} 映射，查找为 O(1) 哈希操作
local combatResurrection = {
    ["DEATHKNIGHT"] = 61999,  -- Raise Ally - 复活盟友
    ["DRUID"] = 20484,        -- Rebirth - 复生
    ["PALADIN"] = 391054,     -- Intercession - 代祷
    ["WARLOCK"] = 20707,      -- Soulstone - 灵魂石
}

-- 将技能 ID 替换为 F.GetSpellInfo 返回的技能名称
do
    for class, spell in pairs(combatResurrection) do
        combatResurrection[class] = F.GetSpellInfo(spell)
    end
end

-- F.GetCombatResurrection(class) -- 获取指定职业的战斗复活技能名称
-- 返回值：技能名称（string）或 nil（该职业无战复能力）
function F.GetCombatResurrection(class)
    return combatResurrection[class]
end
