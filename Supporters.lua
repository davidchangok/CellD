local addonName, ns = ...

-- ===========================================================================
-- Supporters.lua - 支持者数据模块
-- 本模块被 Cell/CellD 主插件加载，也可被其他插件通过 cellSupporters 字段引用。
-- 包含三个核心数据结构：
--   supporters1   - 按日期排序的当前支持者列表，包含魔兽角色名（含服务器和颜色标记）
--   supporters2   - 早期支持者记录（部分已丢失），含赞助平台和日期
--   wowSupporters - 从 supporters1 解析出的角色名->等级映射表，供游戏内显示
-- ===========================================================================

-------------------------------------------------
-- supporters (order by date)
-- 当前支持者列表，按赞助日期排序
-- 每个条目是一个 table，包含同一支持者的多个魔兽角色名
-- 角色名格式: "角色名-服务器 (区域)"，可选带颜色代码前缀
-------------------------------------------------
-- 颜色代码含义（WoW UI escape 序列）：
-- mvp: ff8000 (橙色) - 最高级支持者
-- goat: 7fff00 (绿色) - 高级支持者
-- goat: fb6f92 (粉色) - 高级支持者（另一种色调）
-- 青色: 00ffff - 普通支持者
-- 无颜色前缀: 默认颜色，普通支持者

-- supporters1: 当前支持者角色列表（按赞助日期排序）
-- 结构: 最外层 array，每个元素是一个 table 包含同一支持者的所有角色名
-- 每个角色名可以是纯文本 "角色名-服务器 (区域)" 或带颜色前缀 "|cffRRGGBB角色名-服务器 (区域)|r"
local supporters1 = { -- wowIDs
    -- 每个子 table 包含同一支持者的多个魔兽角色名
    -- {"wowID1", "wowID2"...}
    {
        "|cff7fff00Palymoo-TwistingNether (EU)|r",
        "|cff7fff00Dreadsham-TwistingNether (EU)|r",
        "|cff7fff00Dreadninja-TwistingNether (EU)|r",
        "|cff7fff00Dreadfu-TwistingNether (EU)|r",
        "|cff7fff00Dreads-TwistingNether (EU)|r",
    }, -- Palymoo (Ko-fi)
    {
        "|cff7fff00Tithaya-Kel'Thuzad (US)|r",
        "|cff7fff00Yesiram-Kel'Thuzad (US)|r",
    }, -- Chris (Ko-fi)
    {
        "|cff00ffffVollmer-Ragnaros (EU)|r",
        "|cff00ffffVollmerto-Kazzak (EU)|r",
        "|cff00ffffVollmerfire-Ragnaros (EU)|r",
    }, -- Vollmerino (CUF)
    {
        "|cffff8000小兔姬-影之哀伤 (CN)|r",
        "|cffff8000渺渺-影之哀伤 (CN)|r"
    }, -- 呆小七 (爱发电)
    {"夏木沐-伊森利恩 (CN)"}, -- 夏木沐 (爱发电)
    {"七月核桃丶-白银之手 (CN)"}, -- 爱发电用户_ac5d4
    {"芋包-影之哀伤 (CN)", "月刃丶-世界之樹 (TW)", "月刄-影之哀伤 (CN)"}, -- Smile (爱发电)
    {"青乙-影之哀伤 (CN)", "永离诸幻-影之哀伤 (CN)"},
    {
        "|cffff8000黑诺-影之哀伤 (CN)|r",
        "|cffff8000黑丨诺-影之哀伤 (CN)|r",
        "|cffff8000黑丶诺-影之哀伤 (CN)|r"
    },
    {"大领主王大发-莫格莱尼 (CN)"}, -- Shawn (爱发电)
    {"Sjerry-死亡之翼 (CN)"}, -- 爱发电用户_7957f
    {"貼饼子-匕首岭 (CN)"},
    {"|cfffb6f92心耀-冰风岗 (CN)|r"}, -- warbaby (爱不易)
    {"秋末旷夜-凤凰之神 (CN)", "秋末旷叶-凤凰之神 (CN)"}, -- 爱发电用户_760ee (爱发电)
    {"曾經活過-憤怒使者 (TW)"}, -- ZzZ (爱发电)
    {"音速豆奶-白银之手 (CN)"}, -- 爱发电用户_83f12
    {"Hardpp-Illidan (US)", "六月的奶德-艾露恩 (CN)"}, -- 爱发电用户_15402
    {"握握-暗影之月 (TW)"}, -- 爱发电用户_a3e3a
    {"Sonichunter-地獄吼 (TW)", "Katoomba-地獄吼 (TW)"}, -- 爱发电用户_6db77
    {"微樓聽雨-銀翼要塞 (TW)"}, -- 爱发电用户_8xs3
    {"黑哥哥-世界之樹 (TW)"}, -- 爱发电用户_fdc1d
    {"Kuroni-Blackhand (US)"}, -- Kuro (Ko-fi)
    {"Nodwa-Blackhand (US)"}, -- Nodwa (Ko-fi)
    {"Deijava-Illidan (US)"}, -- Kyoman (Ko-fi)
    {"Epriestin-TarrenMill (EU)"}, -- Sharelia (ko-fi)
    {"Nascente-TarrenMill (EU)"}, -- Nascente-Tarren Mill (Ko-fi)
    {"Longmer-Illidan (US)"}, -- 爱发电用户_4116d (爱发电)
    {"Phæro-Antonidas (EU)", "Callistò-Antonidas (EU)"}, -- Phæro (Ko-fi)
    {"Synthatt-Illidan (US)"}, -- Synthatt (Ko-fi)
    {"Holystora-Antonidas (EU)"}, -- devo (Ko-fi)
    {
        "|cffff8000Everessian-Ravencrest (EU)|r",
        "|cffff8000Thundaem-Ravencrest (EU)|r",
        "|cffff8000Shylanelle-Ravencrest (EU)|r",
        "|cffff8000Alenlin-Ravencrest (EU)|r",
        "|cffff8000Kulresh-Ravencrest (EU)|r",
        "|cffff8000Thurådin-Ravencrest (EU)|r",
    }, -- Martin van Vuuren (Ko-fi)
    {"Shendreakah-Zul'jin (US)"}, -- Shendreakah - Zul-jin (Ko-fi)
    {
        "|cffff8000Lucen-Terokkar (EU)|r",
        "|cffff8000Apexion-Terokkar (EU)|r",
        "|cffff8000Moonwhisper-Terokkar (EU)|r",
        "|cffff8000Wildrunner-Terokkar (EU)|r",
    }, -- Serghei Iakovlev (Ko-fi)
    {"Fourdigitiq-Blackrock (EU)"}, -- Rou (Ko-fi)
    {"Leako-Draenor (EU)"}, -- Leako (Ko-fi)
    {"|cffff8000Asuranpala-Draenor (EU)|r"}, -- AsuranDex (Ko-fi)
    {"|cffff8000Poolparty-Khaz'goroth (US)|r"}, -- Poolparty (Ko-fi)
    {"Tenspiritak-Drakthul (EU)"}, -- Tenspiritak (Ko-fi)
    {"Darrágh-Blackrock (EU)"}, -- Jim (Ko-fi)
    {"Cerrmor-Stormrage (US)"}, -- (Ko-fi)
    {"Gordonfreems-Illidan (US)"}, -- Gordon Freeman (Ko-fi)
    {"Saphiren-Azralon (US)"}, -- Saphiren (Ko-fi)
    {"Evangeleena-Outland (EU)"}, -- Milda (Ko-fi)
    {"Æleluia-Hyjal (EU)"}, -- eXtRa (Ko-fi)
    {
        "Druladin-Blackhand (EU)",
        "Drumane-Blackhand (EU)",
        "Drupriest-Blackhand (EU)",
        "Druvoke-Blackhand (EU)",
        "Drumonji-Blackhand (EU)",
    }, -- Ko-fi
    {"Saintara-Blackhand (EU)"}, -- Ko-fi
    {"|cffff8000Lúthieñ-Ravencrest (EU)|r"}, -- Zion (Ko-fi)
    {"Jeânnîne-Hyjal (EU)"}, -- Jânine (Ko-fi)
    {
        "Angelofbliss-TarrenMill (EU)",
        "Angelique-Dawnbringer (EU)",
    }, -- Angelofbliss (Ko-fi)
    {"Stormpork-Silvermoon (EU)"}, -- Magicpork (Ko-fi)
    {"日理万基-罗宁 (CN)"}, -- LPRO (爱发电)
    {"Kimo-海克泰尔 (CN)"}, -- 爱发电用户_30f63 (爱发电)
    {"Fróger-TarrenMill (EU)"}, -- Fróger (Ko-fi)
    {"风不竞-影之哀伤 (CN)"}, -- 空想无量自在 (爱发电)
    {"白夜之翼-影之哀伤 (CN)"}, -- 大宇 (爱发电)
    {"絵野-金色平原 (CN)"}, -- Neet_F (爱发电)
    {"Shichiki-Antonidas (EU)"}, -- Shichiki-EU-Antonidas (Ko-fi)
    {
        "|cfffb6f92露露缇娅-迅捷微风 (CN)|r",
        "|cfffb6f92露露緹婭灬-迅捷微风 (CN)|r",
        "|cfffb6f92露露缇娅丶-迅捷微风 (CN)|r",
        "|cfffb6f92露露緹婭丶-迅捷微风 (CN)|r",
        "|cfffb6f92露露缇娅丶-霜语 (CN)|r",
        "|cfffb6f92露露缇娅灬-霜语 (CN)|r",
        "|cfffb6f92露露缇娅-时光III (CN)|r",
    }, -- 露露缇娅 (爱发电)
    {
        "|cfffb6f92Rëat-Silvermoon (EU)|r",
        "|cfffb6f92Reatsham-Silvermoon (EU)|r",
        "|cfffb6f92Reatvoker-Silvermoon (EU)|r",
    }, -- Reat
    {"Daydream-Dalaran (EU)"}, -- luana11
    {"|cffff8000Aschgewitter-Eredar (EU)|r"}, -- Aschgewitter - Eredar
    {"三号-熊猫酒仙 (CN)"}, -- 爱发电用户_sUE4
    {"远古列王守卫-回音山 (CN)"}, -- 牌牌骑
    {"Huf-ArgentDawn (EU)"}, -- Huf
    {"吕小美-震地者 (CN)"}, -- 假寐的死神 (爱发电)
    {
        "Tdps-Ragnaros (EU)",
        "Rosehip-Ragnaros (EU)",
    }, -- Tdps-Ragnaros
    {"Daanior-Draenor (EU)"}, -- Daanior-Draenor (Ko-fi)
    {"血蹄凯恩嗯-加丁 (CN)"}, -- 爱发电用户_1e94c
    {"墨染雲湮-白银之手 (CN)"}, -- 墨染雲湮-白银之手
    {"Taudri-Mankrik (US)"}, -- Taudry (Ko-fi)
    {"Sproutz-Illidan (US)"}, -- Sproutz (Ko-fi)
    {
        "|cfffb6f92Floofe-Nightslayer (US)|r",
        "|cfffb6f92Mommie-Nightslayer (US)|r",
        "|cfffb6f92Flewf-Nightslayer (US)|r",
        "|cfffb6f92Twoofe-Nightslayer (US)|r",
        "|cfffb6f92Sloofe-Nightslayer (US)|r",
        "|cfffb6f92Ploofe-Nightslayer (US)|r",
    }, -- Floofe (Ko-fi)
    {"无语了捏-回音山 (CN)"}, -- 我有脂肪肝 (爱发电)
    {"月弥-神圣之歌 (CN)"}, -- 爱发电用户_bb967 (爱发电)
    {"|cfffb6f92Darkquinn-Proudmoore (US)|r"}, -- Quinn (Ko-fi)
    {
        "Ekkles-伊弗斯 (TW)",
        "Ekkles-比斯巨兽 (CN)",
        "Ekkles-国王之谷 (CN)",
    }, -- 爱发电用户_ygpT
    {"小凌宝-霜语 (CN)"}, -- 凌宝 (爱发电)
    {
        "無穷丶-霜语 (CN)",
        "无窮丿-霜语 (CN)",
        "無窮丿-霜语 (CN)",
        "无窮灬-霜语 (CN)",
        "无穷丿-霜语 (CN)",
        "无穷灬-霜语 (CN)",
        "无穷丶-霜语 (CN)",
        "无窮丨-霜语 (CN)",
        "無穷灬-霜语 (CN)",
        "無穷丿-霜语 (CN)",
        "無窮丨-霜语 (CN)",
        "觜火猴-霜语 (CN)",
        "壁水貐-霜语 (CN)",
        "张月鹿丶-霜语 (CN)",
        "炫若琉璃-霜语 (CN)",
    }, -- 无穷 (爱发电)
    {"安格籤牛扒-日落沼澤 (TW)"}, -- 安格籤牛扒 @TW 日落沼澤 (Ko-fi)
    {
        "Clarine-霜语 (CN)",
        "Clariest-霜语 (CN)",
        "Claramists-霜语 (CN)",
        "Whitecat-霜语 (CN)",
        "Claramints-霜语 (CN)",
    } -- 爱发电用户_9Yqv (爱发电)
}

-- supporters2: 早期支持者记录（用于致谢展示）
-- 部分早期赞助记录已经丢失，此列表仅作历史留存
-- 格式: { "支持者名称（可含颜色代码）", "赞助平台" }, -- 日期 备注
-- 不参与游戏内的角色名匹配，仅用于 UI 展示
local supporters2 = { -- 有些早期的发电记录已经丢失了……
    {"|cfffb6f92钛锬|r", "爱发电"}, -- 2021-11-15
    {"|cffff8000呆小七|r", "爱发电"}, -- 2021-11-15
    {"黑色之城", "爱发电"}, -- 2022-03-16
    {"flappysmurf", "爱发电"}, -- 2022-04-16
    {"Mike", "爱发电"}, -- 2022-08-06
    {"七月核桃丶", "爱发电"}, -- 2022-08-08 爱发电用户_ac5d4
    {"|cffff8000Smile|r", "爱发电"}, -- 2022-08-11
    {"|cffff8000黑诺|r", "爱发电"}, -- 2022-08-15
    {"古月文武", "爱发电"},
    {"CC", "爱发电"},
    {"Shawn", "爱发电"}, -- 2022-09-16
    {"蓝色-理想", "爱发电"},
    {"席慕容", "爱发电"},
    {"星空", "爱发电"}, -- 2022-10-19
    {"年复一年路西法", "爱发电"}, -- 2022-10-20
    {"阿哲", "爱发电"}, -- 2022-10-23
    {"Sjerry", "爱发电"}, -- 2022-11-04 爱发电用户_7957f
    {"|cfffb6f92warbaby|r", "爱不易"}, -- 2022-11-25
    {"6ND8", "爱发电"}, -- 2022-11-16
    {"伊莉丝翠的眷顾", "爱发电"}, -- 2022-11-18
    {"批歪", "爱发电"},
    {"音速豆奶", "爱发电"}, -- 2022-11-29 爱发电用户_83f12
    {"ZzZ", "爱发电"}, -- 2022-12-10
    {"月神之韧", "爱发电"}, -- 2023-01-01
    {"Smile", "爱发电"}, -- 2023-01-05
    {"Si", "爱发电"}, -- 2023-01-07
    {"晓文", "爱发电"}, -- 2023-01-15
    {"六月的奶德", "爱发电"}, -- 2023-01-26 爱发电用户_15402
    {"握握", "爱发电"}, -- 2023-05-10 爱发电用户_a3e3a
    {"千雪之心", "爱发电"}, -- 2023-05-25 爱发电用户_2a168
    {"朝", "爱发电"}, -- 2023-06-16
    {"Sonichunter", "爱发电"}, -- 2023-06-26
    {"ATOMS. ོ", "爱发电"}, -- 2023-07-13 爱发电用户_4f365
    {"微樓聽雨", "爱发电"}, -- 2023-07-20 爱发电用户_8xs3
    {"往事", "爱发电"}, -- 2023-07-30
    {"哄哄", "爱发电"}, -- 2023-08-15
    {"acm447", "爱发电"}, -- 2023-08-15
    {"|cffff8000花爺|r", "爱发电"}, -- 2023-09-13
    {"黑哥哥", "爱发电"}, -- 2023-09-23 爱发电用户_fdc1d
    {"得闲饮茶", "爱发电"}, -- 2023-12-03
    {"北方", "爱发电"}, -- 2023-12-06
    {"Kuro", "Ko-fi"}, -- 2023-12-15
    {"Nodwa", "Ko-fi"}, -- 2023-12-18
    {"Kyoman", "Ko-fi"}, -- 2023-12-22
    {"Sharelia", "Ko-fi"}, -- 2023-12-25
    {"Longmer", "爱发电"}, -- 2023-12-23 爱发电用户_4116d (爱发电)
    {"Nascente", "Ko-fi"}, -- 2023-12-26
    {"nas4", "爱发电"}, -- 2023-12-27 爱发电用户_nas4 (爱发电)
    {"Phæro", "Ko-fi"}, -- 2024-02-10
    {"Jane", "Ko-fi"}, -- 2024-02-11
    {"拜拜", "爱发电"}, -- 2024-02-26 爱发电用户_bcb32
    {"qwe#6664", "KOOK"}, -- 2024-02-26 爱发电用户_QBbY
    {"Synthatt", "Ko-fi"}, -- 2024-03-26
    {"devo", "Ko-fi"}, -- 2024-04-07
    {"QBbY", "爱发电"}, -- 2024-04-09 爱发电用户_QBbY
    {"|cff7fff00Chris|r", "Ko-fi"}, -- Chris 2024-04-18
    {"Pandora", "Ko-fi"}, -- 2024-04-22
    {"|cffff8000Martin van Vuuren|r", "Ko-fi"}, -- 2024-05-06
    {"Shendreakah", "Ko-fi"}, -- 2024-05-12
    {"8xs3", "爱发电"}, -- 2024-05-12 爱发电用户_8xs3
    {"|cff7fff00Palymoo|r", "Ko-fi"}, -- 2024-05-12
    {"Winkupo", "Ko-fi"}, -- 2024-05-14
    {"|cffff8000Serghei Iakovlev|r", "Ko-fi"}, -- 2024-05-15
    {"Rou", "Ko-fi"}, -- 2024-05-23
    {"Leako", "Ko-fi"}, -- 2024-05-30
    {"lfence", "Ko-fi"}, -- 2024-06-03
    {"|cffff8000AsuranDex|r", "Ko-fi"}, -- 2024-06-24
    {"fca53", "爱发电"}, -- 2024-07-01 爱发电用户_fca53
    {"Likle", "Ko-fi"}, -- 2024-07-03
    {"eWhK", "爱发电"}, -- 2024-07-03 爱发电用户_eWhK
    {"|cffff8000Poolparty|r", "Ko-fi"}, -- 2024-07-07
    {"Tenspiritak", "Ko-fi"}, -- 2024-07-07
    {"Jim", "Ko-fi"}, -- 2024-07-13
    {"Cerrmor-Stormrage", "Ko-fi"}, -- 2024-07-15
    {"Drumonji-Blackhand", "Ko-fi"}, -- 2024-07-19
    {"Intuition", "Ko-fi"}, -- 2024-07-23
    {"Gordon Freeman", "Ko-fi"}, -- 2024-07-25
    {"Saphiren", "Ko-fi"}, -- 2024-07-25
    {"Milda", "Ko-fi"}, -- 2024-07-30
    {"eXtRa", "Ko-fi"}, -- 2024-07-31
    {"男月月", "Ko-fi"}, -- 2024-07-31
    {"Akanma·Starsong", "爱发电"}, -- 2024-08-01
    {"Druladin-Blackhand", "Ko-fi"}, -- 2024-08-12
    {"|cffff8000Zion|r", "Ko-fi"}, -- 2024-08-18
    {"Saintara-Blackhand", "Ko-fi"}, -- 2024-08-23
    {"Jânine", "Ko-fi"}, -- 2024-08-24
    {"Angelofbliss", "Ko-fi"}, -- 2024-08-24
    {"Magicpork", "Ko-fi"}, -- 2024-08-30
    {"LPRO", "爱发电"}, -- 2024-09-08
    {"30f63", "爱发电"}, -- 2024-09-09
    {"760ee", "爱发电"}, -- 2024-09-11
    {"Xonqevo", "Ko-fi"}, -- 2024-09-16
    {"Fróger", "Ko-fi"}, -- 2024-09-21
    {"空想无量自在", "爱发电"}, -- 2024-09-25
    {"大宇", "爱发电"}, -- 2024-09-25
    {"httpete", "Ko-fi"}, -- 2024-09-28
    {"Neet_F", "爱发电"}, -- 2024-09-28
    {"冷冽谷尬舞队队长", "爱发电"}, -- 2024-10-01
    {"Shichiki-EU-Antonidas", "Ko-fi"}, -- 2024-10-03
    {"|cfffb6f92露露缇娅|r", "爱发电"}, -- 2024-12-20
    {"luana11", "Ko-fi"}, -- 2025-01-25
    {"|cffff8000Aschgewitter - Eredar|r", "Ko-fi"}, -- 2025-02-27
    {"爱发电用户_sUE4", "爱发电"}, -- 2025-03-02
    {"无多路", "爱发电"}, -- 2025-03-04
    {"Huf", "Ko-fi"}, -- 2025-03-04
    {"假寐的死神", "爱发电"}, -- 2025-03-05
    {"Tdps-Ragnaros", "Ko-fi"}, -- 2025-03-08
    {"牌牌骑", "爱发电"}, -- 2025-03-08
    {"Daanior-Draenor", "Ko-fi"}, -- 2025-03-23
    {"爱发电用户_1e94c", "爱发电"}, -- 2025-03-31
    {"Kaymi", "Ko-fi"}, -- 2025-04-19
    {"Venarius", "Ko-fi"}, -- 2025-04-24
    {"墨染雲湮-白银之手", "爱发电"}, -- 2025-05-01
    {"Shyn", "Ko-fi"}, -- 2025-05-22
    {"|cffff8000Taudry|r", "Ko-fi"}, -- 2025-07-02
    {"Ko-fi Supporter", "Ko-fi"}, -- 2025-07-03
    {"Sproutz", "Ko-fi"}, -- 2025-07-03
    {"|cffff8000Chrystal|r", "Ko-fi"}, -- 2025-07-04
    {"Natalz", "Ko-fi"}, -- 2025-07-06
    {"|cfffb6f92Floofe|r", "Ko-fi"}, -- 2025-08-07
    {"我有脂肪肝", "爱发电"}, -- 2025-08-07
    {"奶德史塔克-A'lar CN", "Ko-fi"}, -- 2025-08-15
    {"爱发电用户_bb967", "爱发电"}, -- 2025-08-22
    {"施然", "爱发电"}, -- 2025-10-06
    {"|cfffb6f92Quinn|r", "Ko-fi"}, -- 2025-10-28
    {"爱发电用户_ygpT", "爱发电"}, -- 2025-11-06
    {"Sc千寻", "爱发电"}, -- 2026-01-08
    {"凌宝", "爱发电"}, -- 2026-01-18
    {"无穷", "爱发电"}, -- 2026-01-18
    {"安格籤牛扒 @TW 日落沼澤", "Ko-fi"}, -- 2026-01-22
    {"爱发电用户_78176", "爱发电"}, -- 2026-03-03
    {"Yijx", "爱发电"}, -- 2026-03-04
    {"爱发电用户_9Yqv", "爱发电"}, -- 2026-03-05
}

-------------------------------------------------
-- supporters (wow IDs)
-- 游戏内匹配用的支持者测试/白名单
-- key 为 "角色名-服务器" 格式（不含区域代码），value 为等级标记
--   true  = 普通支持者
--   "goat" = 高级支持者（绿色/粉色显示）
-- 这些条目会合并到 wowSupporters 中，与 supporters1 解析结果一起用于游戏内识别
-------------------------------------------------
local tests = {
    ["Rutha-Lycanthoth"] = true,
    ["Programming-BurningLegion"] = true,
    ["Programming-影之哀伤"] = "goat",
    ["篠崎-影之哀伤"] = "goat",
    ["蜜柑-影之哀伤"] = "goat",
    ["萝露-影之哀伤"] = "goat",
}

-- wowSupporters: 角色名到支持者等级的映射表
-- key: "角色名-服务器" (不含区域代码，如 "Palymoo-TwistingNether")
-- value: true (普通) / "goat" (高级) / "mvp" (最高级)
-- 由 supporters1 解析生成，最终合并 tests 表后供 Cell 框架在游戏内进行角色名匹配和颜色显示
local wowSupporters = {}

-- 解析 supporters1 中的所有角色名，提取纯净的 "角色名-服务器" 并映射到对应等级
-- 解析逻辑：
--   1. 带颜色前缀 "|cffRRGGBB...|r" 的角色名 → 提取纯净名，根据颜色码分配等级
--   2. 无颜色前缀的纯文本角色名 → 直接提取，标记为普通支持者 (true)
do
    for _, t in pairs(supporters1) do
        for i, name in pairs(t) do
            local fullName
            -- 判断角色名是否带有颜色前缀（以 "|cff" 开头是 WoW 颜色 escape 序列）
            if strfind(name, "^|") then
                -- 从带颜色标记的字符串中提取纯角色名和服务器名
                -- 匹配格式: |cffRRGGBB角色名-服务器 (区域)|r
                fullName = strmatch(name, "^|cff......(.+%-.+) %(%u%u%)|r$")
                -- 根据颜色代码分配支持者等级
                if strfind(name, "^|cffff8000") then
                    -- 橙色 (#ff8000) → mvp 最高级支持者
                    wowSupporters[fullName] = "mvp"
                else
                    -- 其他颜色 (绿色 #7fff00 / 粉色 #fb6f92 / 青色 #00ffff) → goat 高级支持者
                    wowSupporters[fullName] = "goat"
                end
            else
                -- 无颜色前缀的纯文本角色名
                -- 匹配格式: 角色名-服务器 (区域)
                fullName = strmatch(name, "^(.+%-.+) %(%u%u%)$")
                -- 无颜色标记 → 普通支持者
                wowSupporters[fullName] = true
            end
        end
    end
end

-------------------------------------------------
-- 导出数据供外部访问
-- 根据调用方身份（addonName）决定导出哪些字段：
--   Cell/CellD 本体：导出完整的三组数据（supporters1/2 + wowSupporters）
--   其他插件引用时：仅导出 cellSupporters（精简的角色名->等级映射）
-------------------------------------------------
-- Midnight/SecretValue 防护点：
--   此文件中所有数据均为公开的支持者列表，不涉及隐私或密钥，
--   因此无需 SecretValue 屏蔽。但若未来在此文件末尾添加任何
--   涉及 API key / 用户身份的信息，需使用 F.Safe* 函数包装。
if addonName == "Cell" or addonName == "CellD" then -- Cell / CellD 本体
    ns.supporters1 = supporters1                                   -- 当前支持者角色列表（含颜色标记）
    ns.supporters2 = supporters2                                   -- 早期支持者历史记录
    ns.wowSupporters = Cell.funcs.TMergeOverwrite(wowSupporters, tests) -- 合并 tests 白名单后的最终映射表，供游戏内角色名匹配和颜色显示
else -- 被其他插件引用时
    ns.cellSupporters = wowSupporters                              -- 提供精简的支持者数据（角色名->等级映射）
end