-- 模块初始化：接收 addonName 与 Cell 核心对象
-- addonName 为当前插件名 "CellD"，Cell 为插件主表
local addonName, Cell = ...
-- F 为 Cell 的工具函数表，提供安全拷贝 F.Copy 等关键方法
-- F.Copy 用于深拷贝表，防止对共享引用的意外修改（SecretValue 防护核心）
local F = Cell.funcs

-- ============================================================================
-- Cell.defaults.appearance — 外观默认配置数据结构
-- 存储所有外观相关设置的默认值，供 CellDB 初始化和重置时使用
-- 每个键对应一个外观选项，取值可以是标量（数字/布尔/字符串）或表
-- 表类型值在重置时必须通过 F.Copy 深拷贝，避免引用共享导致污染
-- ============================================================================
Cell.defaults.appearance = {
    -- 整体缩放比例，默认 1（100% 不缩放）
    ["scale"] = 1,
    -- 框架层级：MEDIUM 为中间层，可选 BACKGROUND / LOW / MEDIUM / HIGH / DIALOG
    ["strata"] = "MEDIUM",
    -- 主题强调色：使用职业颜色（class_color），兜底为 FF4466 粉色
    -- 格式：{颜色来源标识, {R, G, B}}，来源标识决定运行时如何解析颜色
    ["accentColor"] = {"class_color", {1, 0.26667, 0.4}}, -- FF4466
    -- 选项界面字体大小偏移量，0 表示使用默认字体大小
    ["optionsFontSizeOffset"] = 0,
    -- 是否使用魔兽世界原生游戏字体
    ["useGameFont"] = true,
    -- 状态条纹理：默认用 Cell 纹理，_G.DEFAULT 为魔兽世界默认值
    ["texture"] = "Cell ".._G.DEFAULT,
    -- 血条颜色：使用职业颜色（class_color），兜底为深灰色
    ["barColor"] = {"class_color", {0.2, 0.2, 0.2}},
    -- 满血颜色覆盖：false 表示不使用覆盖，{R,G,B} 为兜底灰色
    -- 当第一个元素为 false 时不启用满血颜色覆盖，血条使用正常颜色
    ["fullColor"] = {false, {0.2, 0.2, 0.2}},
    -- 血量损失颜色：使用暗色职业颜色（class_color_dark），兜底为深红色 #AA0000
    -- 用于显示血量损失部分的背景色
    ["lossColor"] = {"class_color_dark", {0.667, 0, 0}},
    -- 死亡颜色覆盖：false 表示不使用覆盖，兜底为深红色
    -- 当单位死亡时，若不覆盖则使用透明度处理而非颜色变化
    ["deathColor"] = {false, {0.545, 0, 0}},
    -- 能量条颜色：使用能量类型颜色（power_color），兜底为灰色
    -- 不同能量类型（法力/怒气/能量等）由 WoW API 返回对应颜色
    ["powerColor"] = {"power_color", {0.7, 0.7, 0.7}},
    -- 血条不透明度：默认 1（完全不透明）
    ["barAlpha"] = 1,
    -- 血量损失区域不透明度：默认 1（完全不透明）
    ["lossAlpha"] = 1,
    -- 背景不透明度：默认 1（完全不透明）
    ["bgAlpha"] = 1,
    -- 血条动画效果："Flash" 为闪烁动画
    -- 用于血量变化时的视觉反馈，可选值如 "Flash" / "Smooth" 等
    ["barAnimation"] = "Flash",
    -- 血量颜色阈值配置，用于根据血量百分比分段着色
    -- 格式：{{低血量颜色}, {中血量颜色}, {高血量颜色}, 低血量阈值, 高血量阈值, 是否启用}
    -- RGB 颜色值 + 百分比阈值，最后一个 bool 控制整体开关
    ["colorThresholds"] = {{1,0,0}, {1,0.7,0}, {0.7,1,0}, 0.05, 0.95, true},
    -- 血量损失颜色阈值配置，结构与 colorThresholds 相同
    -- 控制损失血量部分的颜色分段显示
    ["colorThresholdsLoss"] = {{1,0,0}, {1,0.7,0}, {0.7,1,0}, 0.05, 0.95, true},
    -- 光环图标选项：控制 Buff/Debuff 图标的显示行为
    -- animation: 光环持续时间动画类型 ("duration" 为持续时间旋转动画)
    -- durationRoundUp: 是否向上取整显示持续时间
    -- durationDecimal: 持续时间小数位数 (0 = 整数)
    -- durationColorEnabled: 是否启用持续时间颜色变化
    -- durationColors: 持续时间颜色分段 [{>0颜色}, {>=0.5分钟颜色含alpha}, {>=3分钟颜色含阈值}]
    ["auraIconOptions"] = {
        ["animation"] = "duration",
        ["durationRoundUp"] = false,
        ["durationDecimal"] = 0,
        ["durationColorEnabled"] = false,
        ["durationColors"] = {{0,1,0}, {1,1,0,0.5}, {1,0,0,3}},
    },
    -- 当前目标高亮边框颜色：红粉色 RGBA
    -- 用于标识当前选中的目标单位
    ["targetColor"] = {1, 0.31, 0.31, 1},
    -- 鼠标悬停高亮颜色：白色半透明 RGBA (alpha=0.6)
    -- 用于标识鼠标当前悬停的单位框体
    ["mouseoverColor"] = {1, 1, 1, 0.6},
    -- 高亮边框尺寸：1 像素宽
    ["highlightSize"] = 1,
    -- 超出距离单位的不透明度：0.45（半透明）
    -- 当单位超出法术施法范围时，框体变半透明以提醒玩家
    ["outOfRangeAlpha"] = 0.45,
    -- 治疗预读（Heal Prediction）配置
    -- 格式：{是否启用, 是否显示溢出治疗, {RGBA 覆盖颜色}}
    -- 显示即将到来的治疗量在血条上的预估位置
    ["healPrediction"] = {true, false, {1, 1, 1, 0.4}},
    -- 治疗吸收护盾显示配置
    -- 格式：{是否启用（仅正式服和 Mists 版本）, {RGBA 颜色}}
    -- 显示治疗吸收效果（如瓦尔的意志等）在血条上的视觉提示
    ["healAbsorb"] = {Cell.isRetail or Cell.isMists, {1, 0.1, 0.1, 1}},
    -- 治疗吸收护盾颜色是否反转
    ["healAbsorbInvertColor"] = false,
    -- 护盾显示配置
    -- 格式：{是否启用（非 TBC/经典旧世版本）, {RGBA 覆盖颜色}}
    -- 显示吸收护盾量在血条上的叠加效果
    ["shield"] = {not (Cell.isTBC or Cell.isVanilla), {1, 1, 1, 0.4}},
    -- 过量护盾显示配置
    -- 格式：{是否启用（非 TBC/经典旧世版本）, {RGBA 覆盖颜色}}
    -- 显示超出最大生命值的护盾部分
    ["overshield"] = {not (Cell.isTBC or Cell.isVanilla), {1, 1, 1, 1}},
    -- 过量护盾是否反向填充：false 表示从右/上方向正常填充
    ["overshieldReverseFill"] = false,
}

-- ============================================================================
-- buttonStyleIndices — 按钮样式重置索引表
-- 定义了 ResetButtonStyle 函数需要重置的外观配置键名列表
-- 该列表不包含 scale / strata / optionsFontSizeOffset / useGameFont 等
-- 非按钮级别的全局外观设置，只覆盖单元框体按钮相关的视觉属性
-- 添加新的按钮样式键时，必须同步更新此表
-- ============================================================================
local buttonStyleIndices = {
    "texture",
    "barColor",
    "lossColor",
    "powerColor",
    "barAlpha",
    "lossAlpha",
    "deathColor",
    "bgAlpha",
    "barAnimation",
    "colorThresholds",
    "colorThresholdsLoss",
    "auraIconOptions",
    "targetColor",
    "mouseoverColor",
    "highlightSize",
    "outOfRangeAlpha",
    "healPrediction",
    "healAbsorb",
    "healAbsorbInvertColor",
    "shield",
    "overshield",
    "overshieldReverseFill"
}

-- ============================================================================
-- F.ResetButtonStyle() — 重置按钮样式到默认值
-- ============================================================================
-- 功能：遍历 buttonStyleIndices 中定义的所有外观键，将 CellDB 中的对应值
-- 重置为 Cell.defaults.appearance 中定义的默认值
--
-- SecretValue / Midnight 安全防护要点：
--   对于 table 类型的值，调用 F.Copy 进行深拷贝，确保 CellDB 中的值与
--   默认值表完全独立，防止后续对 CellDB 的修改反向污染默认值定义。
--   对于标量类型（number/string/boolean），Lua 中这些是值类型，
--   直接赋值即安全，无需深拷贝。
--
-- 调用场景：用户在设置界面点击"重置按钮样式"时触发
-- ============================================================================
function F.ResetButtonStyle()
    -- 遍历所有按钮样式索引键
    for _, index in pairs(buttonStyleIndices) do
        -- 类型判断分支：表类型 vs 标量类型，采用不同的赋值策略
        if type(Cell.defaults.appearance[index]) == "table" then
            -- 表类型：使用 F.Copy 深拷贝默认值，创建完全独立的副本
            -- 这是 SecretValue 防护的关键：禁止对配置表做浅引用，
            -- 确保运行时修改不会回溯污染 Cell.defaults.appearance
            CellDB["appearance"][index] = F.Copy(Cell.defaults.appearance[index])
        else
            -- 标量类型（number / string / boolean）：安全直接赋值
            -- Lua 中这些是值类型，赋值即复制，不存在引用共享风险
            CellDB["appearance"][index] = Cell.defaults.appearance[index]
        end
    end
end