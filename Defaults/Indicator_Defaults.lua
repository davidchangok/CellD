local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs
---@class CellUnitButtonFuncs
local I = Cell.iFuncs

-------------------------------------------------
-- custom indicator
-------------------------------------------------
-- 为每种指示器类型生成默认配置表。
-- 支持的 type 参数:
--   "icon"    - 单个光环图标,显示层数/动画
--   "text"    - 光环文字(层数+持续时间)
--   "bar"     - 单条进度条(按剩余时间着色)
--   "bars"    - 多条进度条(垂直/水平排列)
--   "rect"    - 矩形色块指示器
--   "icons"   - 多个光环图标(网格排列)
--   "color"   - 生命条着色(渐变)
--   "texture" - 纹理叠加图标
--   "glow"    - 外发光效果
--   "overlay" - 覆盖层(半透明着色覆盖血条)
--   "block"   - 单个方块指示器
--   "blocks"  - 多个方块指示器(网格排列)
--   "border"  - 边框高亮
-- auraType 参数: "buff"(增益) 或 "debuff"(减益),影响 castBy 和 trackByName 默认值
function I.GetDefaultCustomIndicatorTable(name, indicatorName, type, auraType)
    local t
    if type == "icon" then
        -- 单个图标指示器: 显示光环图标、层数、施法动画
        -- glowOptions[1] 为发光类型("None"=不发光), [2] 为发光颜色 RGBA
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["size"] = {13, 13},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = true,
            ["showDuration"] = false,
            ["showAnimation"] = true,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "text" then
        -- 文字指示器: 以文字形式显示光环堆叠层数和持续时间
        -- colors[1-3] 分别对应 低/中/高 剩余时间的文字颜色(RGBA)
        -- 中间元素 {false, 0.5, ...} 表示: 不启用自定义触发/阈值=0.5秒/颜色
        -- duration[1]=显示持续时长, [2]=向上取整, [3]=小数位数
        -- stack[1]=显示层数, [2]=圆形数字样式
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["font"] = {"Cell " .. _G.DEFAULT, 12, "Outline", false},
            ["colors"] = {{0, 1, 0, 1}, {false, 0.5, {1, 1, 0, 1}}, {false, 3, {1, 0, 0, 1}}},
            ["auraType"] = auraType,
            ["auras"] = {},
            ["duration"] = {
                true, -- show duration
                false, -- round up duration
                0, -- decimal
            },
            ["stack"] = {
                true, -- show stack
                false, -- circled stack nums
            },
        }
    elseif type == "bar" then
        -- 单条进度指示器: 显示单个光环的剩余时间条
        -- colors[1-3]=时间阈值着色(绿/黄/红), [4]=边框色, [5]=背景色
        -- maxValue[1]=是否启用最大上限, [2]=上限值, [3]=是否自动缩放到单位自身最大血量
        -- orientation="horizontal"(水平) 或 "vertical"(垂直)
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"BOTTOMRIGHT", "button", "TOPRIGHT", 0, -1},
            ["frameLevel"] = 5,
            ["size"] = {18, 4},
            ["colors"] = {{0, 1, 0, 1}, {false, 0.5, {1, 1, 0, 1}}, {false, 3, {1, 0, 0, 1}}, {0, 0, 0, 1}, {0.07, 0.07, 0.07, 0.9}},
            ["orientation"] = "horizontal",
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "LEFT", 1, 0, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "RIGHT", -1, 0, {1, 1, 1}},
            },
            ["showStack"] = false,
            ["showDuration"] = false,
            ["maxValue"] = {false, 10, true},
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "bars" then
        -- 多条进度指示器: 每行/列显示多个进度条,按光环时间排序
        -- num=最多显示条数, numPerLine=每行条数
        -- orientation="top-to-bottom"(从上到下) 或 "right-to-left"/"left-to-right"
        -- spacing={水平间距, 垂直间距}
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 0},
            ["frameLevel"] = 5,
            ["size"] = {18, 4},
            ["num"] = 3,
            ["numPerLine"] = 3,
            ["orientation"] = "top-to-bottom",
            ["spacing"] = {-1, -1},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = false,
            ["showDuration"] = false,
            ["maxValue"] = {false, 10, true},
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "rect" then
        -- 矩形色块指示器: 用纯色矩形块表示光环状态
        -- 颜色按剩余时间分为三档(类似 bar)
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 2},
            ["frameLevel"] = 5,
            ["size"] = {11, 4},
            ["colors"] = {{0, 1, 0, 1}, {false, 0.5, {1, 1, 0, 1}}, {false, 3, {1, 0, 0, 1}}, {0, 0, 0, 1}},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "LEFT", 1, 0, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "RIGHT", -1, 0, {1, 1, 1}},
            },
            ["showStack"] = false,
            ["showDuration"] = false,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "icons" then
        -- 多图标指示器: 在网格中显示多个光环图标(按剩余时间/层数排序)
        -- num=最多显示图标数, numPerLine=每行图标数
        -- orientation 控制排列方向
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["size"] = {13, 13},
            ["num"] = 5,
            ["numPerLine"] = 5,
            ["orientation"] = "right-to-left",
            ["spacing"] = {0, 0},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = true,
            ["showDuration"] = false,
            ["showAnimation"] = true,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "color" then
        -- 生命条着色指示器: 直接修改单位框体的血条颜色
        -- anchor 指定锚定到哪个生命条("healthbar-current"=当前血量条)
        -- colors[1] 为渐变模式("gradient-vertical"=垂直渐变),
        --   [2-4]=自定义颜色(低/中/高), [5-6]=时间阈值触发(<=0.5秒变黄, <=3秒变红)
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["anchor"] = "healthbar-current",
            ["frameLevel"] = 1,
            ["colors"] = {"gradient-vertical", {1, 0, 0.4, 1}, {0, 0, 0, 1}, {0, 1, 0, 1}, {0.5, {1, 1, 0, 1}}, {3, {1, 0, 0, 1}}},
            ["auraType"] = auraType,
            ["auras"] = {},
        }
    elseif type == "texture" then
        -- 纹理指示器: 在单位框体上叠加纹理图片(如圆形模糊光斑)
        -- texture[1]=纹理路径, [2]=旋转角度(弧度), [3]=着色 RGBA
        -- fadeOut=true 表示光环消失时纹理淡出
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOP", "button", "TOP", 0, 0},
            ["size"] = {16, 16},
            ["frameLevel"] = 10,
            ["texture"] = {"Interface\\AddOns\\Cell\\Media\\Shapes\\circle_blurred.tga", 0, {1, 1, 1, 1}},
            ["auraType"] = auraType,
            ["auras"] = {},
            ["fadeOut"] = true,
        }
    elseif type == "glow" then
        -- 外发光指示器: 在单位框体外围显示按钮发光效果
        -- glowOptions[1]=发光样式("Pixel"/"Action"), [2]=颜色RGBA, [3]=线条数,
        --   [4]=每帧步进, [5]=频率, [6]=长度
        -- fadeOut=true 表示光环消失时发光淡出
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["frameLevel"] = 1,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"Pixel", {0.95, 0.95, 0.32, 1}, 9, 0.25, 8, 2},
            ["fadeOut"] = true,
        }
    elseif type == "overlay" then
        -- 覆盖层指示器: 在血条上叠加半透明覆盖层
        -- smooth=false 表示不平滑过渡(直接切换颜色)
        -- colors 含有三档时间阈值的覆盖颜色(绿/黄/红,均带透明度)
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["smooth"] = false,
            ["frameLevel"] = 1,
            ["colors"] = {{0, 0.61, 1, 0.55}, {false, 0.5, {1, 1, 0, 0.5}}, {false, 3, {1, 0, 0, 0.5}}},
            ["orientation"] = "horizontal",
            ["auraType"] = auraType,
            ["auras"] = {},
        }
    elseif type == "block" then
        -- 单个方块指示器: 用方块颜色表示光环堆叠或持续时间
        -- colors[1]="duration" 表示按持续时间着色, 后续为三档颜色(绿/黄/红)+边框色
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["size"] = {10, 10},
            ["colors"] = {"duration", {0, 1, 0, 1}, {false, 0.5, {1, 1, 0, 1}}, {false, 3, {1, 0, 0, 1}}, {0, 0, 0, 1}},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = false,
            ["showDuration"] = false,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "blocks" then
        -- 多个方块指示器: 网格排列多个方块,每个方块代表一个光环
        -- 按剩余时间排序,用颜色表示紧急程度
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["size"] = {10, 10},
            ["num"] = 5,
            ["numPerLine"] = 5,
            ["orientation"] = "right-to-left",
            ["spacing"] = {-1, -1},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = false,
            ["showDuration"] = false,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "border" then
        -- 边框指示器: 高亮单位框体边框
        -- thickness=边框粗细, 不配置颜色则使用光环默认颜色
        -- fadeOut=true 表示光环消失时边框淡出
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["thickness"] = 2,
            ["frameLevel"] = 10,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["fadeOut"] = true,
        }
    end

    -- 根据光环类型设置来源过滤和名称追踪默认值
    if auraType == "buff" then
        -- 增益光环: 默认仅追踪自己施放的
        t["castBy"] = "me"
        if Cell.isRetail then
            -- 正式服: 默认按光环 ID 追踪(避免同名光环误匹配)
            t["trackByName"] = false
        else
            -- 经典怀旧服: 无光环 ID, 只能按名称追踪
            t["trackByName"] = true
        end
    else
        -- 减益光环: 默认追踪任意来源(配合团队职责驱散使用)
        t["castBy"] = "anyone"
    end

    return t
end

-------------------------------------------------
-- dispels: custom debuff type color
-------------------------------------------------

-- Blizzard C API (Midnight 12.0.5): C_UnitAuras.GetAuraDispelTypeColor(auraInstanceID [, curve])
-- internally resolves secrets. pcall guards against stale auraInstanceID.

-- [Midnight/SecretValue 防护点]
-- 通过光环实例 ID 获取驱散类型颜色(RGB)。
-- 使用 pcall 保护调用,防止过期的 auraInstanceID 导致 C API 报错。
-- 返回 nil 表示获取失败(函数不可用、ID 无效或 C API 抛出异常)。
function I.GetAuraDispelColor(auraInstanceID)
    -- 先校验 API 可用性,避免在旧客户端上调用不存在的函数
    if not C_UnitAuras or not C_UnitAuras.GetAuraDispelTypeColor or not auraInstanceID then
        return nil
    end
    -- pcall 安全调用: auraInstanceID 可能对应已消失的光环,
    -- 直接调用会触发 Blizzard 内部错误,pcall 捕获后返回 nil
    local ok, c = pcall(C_UnitAuras.GetAuraDispelTypeColor, auraInstanceID)
    if ok and c then return c.r, c.g, c.b end
    return nil
end

-- [Midnight/SecretValue 防护点]
-- 根据减益类型字符串获取对应的显示颜色。
-- Midnight 12.0.0+ 中 debuffType 可能为 secret value,不能用作表键,
-- 因此先通过 issecretvalue() 检查,若为 secret 则直接返回黑色(0,0,0)。
-- 正常情况下从 CellDB["debuffTypeColor"] 表中查找颜色;
-- 若未找到则使用 fallbackColor(备选颜色)或默认黑色。
function I.GetDebuffTypeColor(debuffType, fallbackColor)
    -- Midnight 12.0.0+: debuffType may be secret; cannot use as table key
    -- 检测 secret value: secret 类型的值作为表键会导致 Lua 错误,
    -- 必须提前拦截,返回安全的默认黑色
    if issecretvalue and issecretvalue(debuffType) then return 0, 0, 0 end
    -- 从用户自定义颜色表中查找该减益类型的颜色
    if debuffType and CellDB["debuffTypeColor"][debuffType] then
        return CellDB["debuffTypeColor"][debuffType]["r"], CellDB["debuffTypeColor"][debuffType]["g"],
            CellDB["debuffTypeColor"][debuffType]["b"]
    elseif fallbackColor then
        -- 使用调用方提供的备选颜色(通常来自光环本身的颜色信息)
        return fallbackColor[1], fallbackColor[2], fallbackColor[3]
    else
        -- 最终兜底: 返回黑色
        return 0, 0, 0
    end
end

-- 设置指定减益类型的自定义颜色(写入持久化配置 CellDB)。
-- 注意: 这里不包含 issecretvalue 防护,因为调用方应在上层确保 debuffType 合法。
function I.SetDebuffTypeColor(debuffType, r, g, b)
    if debuffType and CellDB["debuffTypeColor"][debuffType] then
        CellDB["debuffTypeColor"][debuffType]["r"] = r
        CellDB["debuffTypeColor"][debuffType]["g"] = g
        CellDB["debuffTypeColor"][debuffType]["b"] = b
    end
end

-- Midnight 12.0.0 removed the DebuffTypeColor global; provide a local fallback
-- with the standard Blizzard debuff type colors
-- [Midnight 兼容层]
-- Blizzard 在 Midnight 12.0.0 中移除了全局 DebuffTypeColor 表,
-- 此处提供本地回退表,包含标准的五种驱散类型颜色:
--   "none"    - 无驱散类型(物理类)  红色
--   "Magic"   - 魔法                 蓝色
--   "Curse"   - 诅咒                 紫色
--   "Disease" - 疾病                 棕色
--   "Poison"  - 中毒                 绿色
--   ""        - 空字符串(兼容)       红色
-- I.ResetDebuffTypeColor 会优先尝试使用 WoW 全局表,仅在不可用时回退到此表
local CellDebuffTypeColorFallback = {
    ["none"]    = {r = 0.80, g = 0.00, b = 0.00},
    ["Magic"]   = {r = 0.20, g = 0.60, b = 1.00},
    ["Curse"]   = {r = 0.60, g = 0.00, b = 1.00},
    ["Disease"] = {r = 0.60, g = 0.40, b = 0.00},
    ["Poison"]  = {r = 0.00, g = 0.60, b = 0.00},
    [""]        = {r = 0.80, g = 0.00, b = 0.00},
}

-- 重置减益类型颜色配置为默认值。
-- 在插件初始化或用户选择"恢复默认"时调用。
-- 使用 F.Copy 深拷贝源表,避免后续修改影响原始数据。
-- 额外追加 "Bleed"(流血)类型,因为 Blizzard 默认不包含。
function I.ResetDebuffTypeColor()
    -- copy from WoW global if available, otherwise use local fallback
    -- 优先使用 WoW 全局 DebuffTypeColor 表(Midnight 前可用),
    -- 否则回退到本地定义的 CellDebuffTypeColorFallback
    local source = DebuffTypeColor or CellDebuffTypeColorFallback
    CellDB["debuffTypeColor"] = F.Copy(source)
    -- add Bleed
    -- 追加流血类型(暗红色),暴雪默认表中不含此项
    CellDB["debuffTypeColor"]["Bleed"] = {r = 1, g = 0.2, b = 0.6}
    -- add cleu
    -- CellDB["debuffTypeColor"].cleu = {r=0, g=1, b=1}
end