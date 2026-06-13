local _, Cell = ...
local L = Cell.L
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs

-------------------------------------------------
-- 自定义指示器模块 (Custom Indicators Module)
-- 职责：管理所有自定义光环指示器的生命周期，包括创建、更新、重置与销毁。
-- 核心数据结构：
--   enabledIndicators[名称] = true              -- 已启用的指示器索引
--   customIndicators["buff"/"debuff"][名称]       -- 按光环类型分组的指示器完整配置
-- 每个指示器配置包含（视类型不同部分字段可能不存在）：
--   auras     - 已转换为内部格式的法术匹配表（key=spellId或法术名, value=优先级order 或 {order, color}）
--   _auras    - 仅在 buff 类型下保存的原始法术列表副本，用于 trackByName 切换时重建 auras
--   type      - 指示器类型（icon/text/bar/bars/rect/icons/color/texture/glow/overlay/block/blocks/border）
--   castBy    - 施法者过滤条件（"me"/"others"/"anyone"）
--   hasColor  - 是否包含颜色映射（有颜色时 auras[spell] 为 {order, color} 而非纯数字）
--   top       - 单目标指示器：当前最高优先级光环的完整数据（start/duration/debuffType/texture/count/refreshing/color）
--   topOrder  - 单目标指示器：当前最高优先级光环的 order 值（初始999，越小优先级越高）
--   found     - 多目标指示器：匹配到的光环列表（{order, start, duration, ...} 条目数组）
--   num       - 多目标指示器：最大显示数量
--
-- Midnight/SecretValue 防护（12.0.0+ 魔兽世界资料片）：
--   受限环境（竞技场/副本/战场/战斗）下光环数据字段（spellId, expirationTime, icon 等）为秘密值。
--   秘密值禁止直接比较（==）、算术运算（+ - * /）或用作表键（t[secret]）。
--   FontString:SetText() 和 SetTexture() 可安全接受秘密值。
--   本模块通过以下方式防护：
--     - F.IsAuraNonSecret()  判断光环整体是否可读
--     - F.IsValueNonSecret() 判断单个字段是否可读
--     - issecretvalue()      检测值是否为秘密值后再用作表键
-------------------------------------------------

-- NOTE for Custom Indicator authors (Midnight 12.0.0+):
-- In restricted contexts (encounters, M+, PvP, combat), aura data fields
-- (spellId, expirationTime, applications, icon, etc.) are Secret Values.
-- - DO NOT compare secret values with == or use arithmetic on them
-- - DO NOT use secret values as table keys
-- - FontString:SetText() and SetTexture() ACCEPT secrets safely
-- - Use issecretvalue(val) to check if a value is secret
-- - Use GetRestrictedActionStatus(0) to check if aura access is restricted

-------------------------------------------------
-- custom indicators
-------------------------------------------------

-- 已启用的指示器索引表：enabledIndicators[indicatorName] = true 表示该指示器当前已启用
local enabledIndicators = {}
-- 自定义指示器完整配置表，按光环类型分组
-- customIndicators["buff"][indicatorName]  = { auras, type, castBy, top, topOrder, found, num, hasColor, ... }
-- customIndicators["debuff"][indicatorName] = 同上结构
local customIndicators = {
    ["buff"] = {},
    ["debuff"] = {},
}

Cell.snippetVars.enabledIndicators = enabledIndicators
Cell.snippetVars.customIndicators = customIndicators

-- 根据布局表中的单条指示器配置，初始化/更新 enabledIndicators 和 customIndicators 内部表
-- 在布局切换、配置变更时调用，将用户设置转换为运行时内部数据结构
-- indicatorTable 来源：Cell.vars.currentLayoutTable.indicators[i]
-- 核心任务：1) 记录启用状态  2) 按指示器类型构建不同的内部配置结构（法术转换、字段初始化）
--! init enabledIndicators & customIndicators
function I.UpdateIndicatorTable(indicatorTable)
    local indicatorName = indicatorTable["indicatorName"]
    local auraType = indicatorTable["auraType"]

    -- 记录启用状态到全局索引表
    -- keep custom indicators in table
    if indicatorTable["enabled"] then enabledIndicators[indicatorName] = true end

    -- 根据指示器类型构建不同的内部配置结构（法术转换方式、单/多目标字段不同）
    -- icons 类型特殊：使用 found/num 存储多个匹配光环，类似内置 Debuffs 指示器
    -- NOTE: icons is different from other custom indicators, more like the Debuffs indicator
    if indicatorTable["type"] == "icons" then
        customIndicators[auraType][indicatorName] = {
            ["auras"] = F.ConvertSpellTable(indicatorTable["auras"], indicatorTable["trackByName"]), -- auras to match
            ["found"] = {},
            ["num"] = indicatorTable["num"],
        }
    elseif indicatorTable["type"] == "bars" or indicatorTable["type"] == "blocks" then
        -- bars/blocks 类型：多目标指示器 + 颜色映射 + found/num 结构
        -- 使用 ConvertSpellTable_WithColor 生成 {spell: {order, color}} 格式的法术表
        customIndicators[auraType][indicatorName] = {
            ["auras"] = F.ConvertSpellTable_WithColor(indicatorTable["auras"], indicatorTable["trackByName"]), -- auras to match
            ["hasColor"] = true,
            ["found"] = {},
            ["num"] = indicatorTable["num"],
        }
    elseif indicatorTable["type"] == "border" then
        -- border 类型：单目标指示器（仅显示最高优先级光环）+ 颜色映射 + top/topOrder 结构
        customIndicators[auraType][indicatorName] = {
            ["auras"] = F.ConvertSpellTable_WithColor(indicatorTable["auras"], indicatorTable["trackByName"]), -- auras to match
            ["hasColor"] = true,
            ["top"] = {},
            ["topOrder"] = {},
        }
    else
        -- 其他类型（icon/text/bar/rect/color/texture/glow/overlay/block）：单目标指示器，无颜色映射
        -- 使用 top/topOrder 结构追踪最高优先级光环
        customIndicators[auraType][indicatorName] = {
            ["auras"] = F.ConvertSpellTable(indicatorTable["auras"], indicatorTable["trackByName"]), -- auras to match
            ["top"] = {}, -- top aura details（最高优先级光环的完整数据）
            ["topOrder"] = {}, -- top aura order（当前最高优先级 order 值，初始999）
        }
    end

    -- 公共属性：指示器显示名称、控件类型、施法者过滤条件
    customIndicators[auraType][indicatorName]["name"] = indicatorTable["name"]
    customIndicators[auraType][indicatorName]["type"] = indicatorTable["type"]
    customIndicators[auraType][indicatorName]["castBy"] = indicatorTable["castBy"]

    if auraType == "buff" then
        -- buff 类型额外保存原始法术 ID 列表的副本（_auras），
        -- 供 trackByName 设置切换时重新生成 auras 匹配表使用
        customIndicators[auraType][indicatorName]["_auras"] = F.Copy(indicatorTable["auras"]) --* save ids
        customIndicators[auraType][indicatorName]["trackByName"] = indicatorTable["trackByName"]
    end
end

-- 根据指示器类型（indicatorTable["type"]）创建对应的 UI 控件实例
-- parent: 单位按钮对象，新控件挂载到 parent.widgets.indicatorFrame 或相应层级
-- indicatorTable: 指示器配置（必须包含 type 字段）
-- 返回值：创建的控件对象，同时注册到 parent.indicators[indicatorName] 供后续访问
-- 支持的类型：icon, text, bar, bars, rect, icons, color, texture, glow, overlay, block, blocks, border
function I.CreateIndicator(parent, indicatorTable)
    local indicatorName = indicatorTable["indicatorName"]
    local indicator
    if indicatorTable["type"] == "icon" then
        indicator = I.CreateAura_BarIcon(nil, parent.widgets.indicatorFrame)
    elseif indicatorTable["type"] == "text" then
        indicator = I.CreateAura_Text(nil, parent.widgets.indicatorFrame)
    elseif indicatorTable["type"] == "bar" then
        indicator = I.CreateAura_Bar(nil, parent.widgets.indicatorFrame)
    elseif indicatorTable["type"] == "bars" then
        indicator = I.CreateAura_Bars(nil, parent.widgets.indicatorFrame, 10)
    elseif indicatorTable["type"] == "rect" then
        indicator = I.CreateAura_Rect(nil, parent.widgets.indicatorFrame)
    elseif indicatorTable["type"] == "icons" then
        indicator = I.CreateAura_Icons(nil, parent.widgets.indicatorFrame, 10)
    elseif indicatorTable["type"] == "color" then
        indicator = I.CreateAura_Color(nil, parent)
    elseif indicatorTable["type"] == "texture" then
        indicator = I.CreateAura_Texture(nil, parent.widgets.indicatorFrame)
    elseif indicatorTable["type"] == "glow" then
        indicator = I.CreateAura_Glow(nil, parent.widgets.highLevelFrame)
    elseif indicatorTable["type"] == "overlay" then
        indicator = I.CreateAura_Overlay(nil, parent)
    elseif indicatorTable["type"] == "block" then
        indicator = I.CreateAura_Block(nil, parent.widgets.indicatorFrame)
    elseif indicatorTable["type"] == "blocks" then
        indicator = I.CreateAura_Blocks(nil, parent.widgets.indicatorFrame, 10)
    elseif indicatorTable["type"] == "border" then
        indicator = I.CreateAura_Border(nil, parent.widgets.highLevelFrame)
    end
    parent.indicators[indicatorName] = indicator

    return indicator
end

-- 移除单个自定义指示器：清理 UI 控件并从所有索引表中注销
-- parent: 单位按钮对象
-- indicatorName: 指示器名称（如 "indicator1"）
-- auraType: 光环类型（"buff" 或 "debuff"），用于从 customIndicators 中移除对应条目
function I.RemoveIndicator(parent, indicatorName, auraType)
    local indicator = parent.indicators[indicatorName]
    indicator:ClearAllPoints()
    indicator:Hide()
    indicator:SetParent(nil)
    parent.indicators[indicatorName] = nil
    enabledIndicators[indicatorName] = nil
    customIndicators[auraType][indicatorName] = nil
end

-- 移除所有自定义指示器控件（名称以 "indicator" 开头的 UI 元素）
-- 用于切换到新布局时清理旧布局的指示器控件
-- 注意：被注释掉的 wipe(enabledIndicators) 和 wipe(customIndicators) 曾用于预览模式，
--       现在由 ResetCustomIndicatorTables 统一处理数据表的清理与重建
-- used for switching to a new layout
function I.RemoveAllCustomIndicators(parent)
    -- if parent ~= CellIndicatorsPreviewButton then
    --     wipe(enabledIndicators)
    --     wipe(customIndicators["buff"])
    --     wipe(customIndicators["debuff"])
    -- end

    for indicatorName, indicator in pairs(parent.indicators) do
        if string.find(indicatorName, "^indicator") then
            indicator:ClearAllPoints()
            indicator:Hide()
            indicator:SetParent(nil)
            parent.indicators[indicatorName] = nil
        end
    end
end

-- 完全重置所有自定义指示器内部数据表，然后从当前布局重新加载
-- 调用时机：布局切换后、配置重置后（由 Cell 核心触发）
-- 流程：
--   1. 清空 enabledIndicators 和 customIndicators["buff"/"debuff"] 的运行时状态
--   2. 遍历当前布局表的 indicators 数组，跳过内置指示器（Cell.defaults.builtIns 个），
--      为每个自定义指示器调用 UpdateIndicatorTable 重建内部结构
function I.ResetCustomIndicatorTables()
    -- 清空所有运行时状态
    -- clear
    wipe(enabledIndicators)
    wipe(customIndicators["buff"])
    wipe(customIndicators["debuff"])

    -- 遍历当前布局的自定义指示器（跳过前 builtIns 个内置指示器），重新初始化
    -- Cell.defaults.builtIns：内置指示器的固定数量，其后的均为自定义指示器
    -- update customs
    for i = Cell.defaults.builtIns + 1, #Cell.vars.currentLayoutTable.indicators do
        I.UpdateIndicatorTable(Cell.vars.currentLayoutTable.indicators[i])
    end
end

---
-- 自定义指示器设置变更回调（注册到 Cell "UpdateIndicators" 事件）
-- 当用户在配置面板中修改任何指示器设置时由 Cell 核心触发
-- layout:        受影响的布局名称（仅当与当前布局匹配时才处理）
-- indicatorName: 指示器名称（如 "indicator1"，必须以 "indicator" 开头）
-- setting:       变更的设置项，可能值为：
--                  "enabled"      - 启用/禁用切换
--                  "auras"        - 法术列表（value=auraType, value2=原始法术表）
--                  "checkbutton"  - 复选框设置（value=配置项名, value2=新布尔值）
--                  其他            - 如 "num"（显示数量）、"castBy"（施法者过滤）
-- value/value2:  新的设置值，含义随 setting 不同而变化
local function UpdateCustomIndicators(layout, indicatorName, setting, value, value2)
    if layout and layout ~= Cell.vars.currentLayout then return end

    if not indicatorName or not string.find(indicatorName, "^indicator") then return end

    -- 根据 setting 类型分发更新
    if setting == "enabled" then
        -- 启用/禁用切换：更新 enabledIndicators 索引表
        if value then
            enabledIndicators[indicatorName] = true
        else
            enabledIndicators[indicatorName] = nil
        end
    elseif setting == "auras" then
        -- 法术列表变更：value = auraType（"buff"/"debuff"），value2 = 原始法术表
        -- 保存原始副本并根据 hasColor 选择正确的转换函数重建 auras 匹配表
        customIndicators[value][indicatorName]["_auras"] = F.Copy(value2) --* save ids
        if customIndicators[value][indicatorName]["hasColor"] then
            customIndicators[value][indicatorName]["auras"] = F.ConvertSpellTable_WithColor(value2, customIndicators[value][indicatorName]["trackByName"])
        else
            customIndicators[value][indicatorName]["auras"] = F.ConvertSpellTable(value2, customIndicators[value][indicatorName]["trackByName"])
        end
    elseif setting == "checkbutton" then
        -- 复选框设置变更（如 trackByName 按名称/ID 匹配切换）
        -- value = 配置项名称，value2 = 新值（布尔）
        if customIndicators["buff"][indicatorName] then
            customIndicators["buff"][indicatorName][value] = value2
            if value == "trackByName" then
                -- trackByName 切换时需重新生成 auras 表（key 从 spellId 变为法术名称或反之）
                if customIndicators["buff"][indicatorName]["hasColor"] then
                    customIndicators["buff"][indicatorName]["auras"] = F.ConvertSpellTable_WithColor(customIndicators["buff"][indicatorName]["_auras"], value2)
                else
                    customIndicators["buff"][indicatorName]["auras"] = F.ConvertSpellTable(customIndicators["buff"][indicatorName]["_auras"], value2)
                end
            end
        elseif customIndicators["debuff"][indicatorName] then
            customIndicators["debuff"][indicatorName][value] = value2
        end
    else -- num, castBy
        -- 其他配置项（num=显示数量上限, castBy=施法者过滤条件等）
        if customIndicators["buff"][indicatorName] then
            customIndicators["buff"][indicatorName][setting] = value
        elseif customIndicators["debuff"][indicatorName] then
            customIndicators["debuff"][indicatorName][setting] = value
        end
    end
end
-- 将 UpdateCustomIndicators 注册为 Cell "UpdateIndicators" 事件回调，监听所有指示器配置变更
Cell.RegisterCallback("UpdateIndicators", "UpdateCustomIndicators", UpdateCustomIndicators)

-------------------------------------------------
-- reset
-------------------------------------------------
---
-- 在每次光环扫描周期开始时重置指定单位按钮上所有自定义指示器的内部状态
-- 调用时机：由 Cell 核心在 UNIT_AURA 事件处理中，开始遍历光环前调用
-- unitButton: 要重置的单位按钮
-- auraType:   要重置的光环类型（"buff" 或 "debuff"）
-- 重置逻辑：
--   1. 隐藏指示器控件（Hide(true) 表示保留内部重置标记）
--   2. 多目标型（有 num 字段）：清空 found[unit] 匹配列表，准备收集新一轮匹配
--   3. 单目标型（无 num 字段）：重置 topOrder[unit]=999，清空 top[unit] 数据
function I.ResetCustomIndicators(unitButton, auraType)
    local unit = unitButton.states.displayedUnit

    for indicatorName, indicatorTable in pairs(customIndicators[auraType]) do
        if enabledIndicators[indicatorName] and unitButton.indicators[indicatorName] then
            unitButton.indicators[indicatorName]:Hide(true)
            if indicatorTable["num"] then
                if not indicatorTable["found"][unit] then
                    indicatorTable["found"][unit] = {}
                else
                    wipe(indicatorTable["found"][unit])
                end
            else
                indicatorTable["topOrder"][unit] = 999
                if not indicatorTable["top"][unit] then
                    indicatorTable["top"][unit] = {}
                else
                    wipe(indicatorTable["top"][unit])
                end
            end
        end
    end
end

-------------------------------------------------
-- update
-------------------------------------------------
---
-- 将匹配到的光环数据写入指示器内部表（indicatorTable），为后续 Show 渲染准备数据
-- indicator:    目标指示器控件（实际未使用，保留以兼容调用签名）
-- indicatorTable: 指示器内部配置表（含 auras/top/topOrder/found/num/hasColor 等字段）
-- unit:         单位标识（用作 top[unit]/found[unit] 的键）
-- spell:        匹配到的法术标识（spellId 或法术名称，已在调用方通过 SecretValue 检查）
-- 其余参数：start, duration, debuffType, icon, count, refreshing 来自 auraInfo
--
-- 两种模式：
--   多目标型（有 num 字段）：追加到 found[unit] 列表，稍后在 ShowCustomIndicators 中排序取前 num 个
--   单目标型（无 num 字段）：比较优先级，仅保留 order 值最小（最高优先级）的光环数据到 top[unit]
--   hasColor 时 auras[spell] 为 {order, color} 表，取 [1] 作为优先级
local function Update(indicator, indicatorTable, unit, spell, start, duration, debuffType, icon, count, refreshing)
    -- 多目标指示器：将光环追加到 found[unit] 匹配列表，后续排序显示前 num 个
    if indicatorTable["num"] then
        if indicatorTable["hasColor"] then
            -- 带颜色：条目格式 {order, start, duration, debuffType, icon, count, refreshing, color}
            tinsert(indicatorTable["found"][unit], {indicatorTable["auras"][spell][1], start, duration, debuffType, icon, count, refreshing, indicatorTable["auras"][spell][2]})
        else
            -- 无颜色：条目格式 {order, start, duration, debuffType, icon, count, refreshing}
            tinsert(indicatorTable["found"][unit], {indicatorTable["auras"][spell], start, duration, debuffType, icon, count, refreshing})
        end
    else
        -- 单目标指示器：仅保留优先级最高（order 值最小）的光环
        if indicatorTable["hasColor"] then
            if indicatorTable["auras"][spell][1] < indicatorTable["topOrder"][unit] then
                indicatorTable["topOrder"][unit] = indicatorTable["auras"][spell][1]
                indicatorTable["top"][unit]["start"] = start
                indicatorTable["top"][unit]["duration"] = duration
                indicatorTable["top"][unit]["debuffType"] = debuffType
                indicatorTable["top"][unit]["texture"] = icon
                indicatorTable["top"][unit]["count"] = count
                indicatorTable["top"][unit]["refreshing"] = refreshing
                indicatorTable["top"][unit]["color"] = indicatorTable["auras"][spell][2]
            end
        else
            if indicatorTable["auras"][spell] < indicatorTable["topOrder"][unit] then
                indicatorTable["topOrder"][unit] = indicatorTable["auras"][spell]
                indicatorTable["top"][unit]["start"] = start
                indicatorTable["top"][unit]["duration"] = duration
                indicatorTable["top"][unit]["debuffType"] = debuffType
                indicatorTable["top"][unit]["texture"] = icon
                indicatorTable["top"][unit]["count"] = count
                indicatorTable["top"][unit]["refreshing"] = refreshing
            end
        end
    end
end

---
-- 核心更新函数：处理单个光环事件，将匹配的光环数据写入对应指示器的内部表
-- 调用时机：Cell 核心在 UNIT_AURA 事件处理中遍历单位的所有光环时逐个调用
-- unitButton: 触发更新的单位按钮对象
-- auraInfo:   WoW API 返回的光环信息表，关键字段：
--   isHelpful       - true=buff, false=debuff（以此判断光环类型）
--   isHarmful       - true=有害效果
--   spellId         - 法术ID（受限环境下为秘密值）
--   name            - 法术名称（受限环境下为秘密值）
--   icon            - 法术图标纹理ID（受限环境下为秘密值，但 SetTexture 可安全接受）
--   duration        - 持续时间（受限环境下可能为秘密值）
--   expirationTime  - 过期时间戳（受限环境下可能为秘密值）
--   applications    - 层数
--   sourceUnit      - 施法者单位（受限环境下为秘密值）
--   dispelName      - 驱散类型名称（受限环境下可能为秘密值）
--   refreshing      - 是否正在刷新
--
-- === Midnight/SecretValue 防护详解（12.0.0+） ===
-- 在竞技场/副本/战场/战斗等受限环境下，部分光环字段被 WoW 客户端标记为秘密值。
-- 秘密值的核心限制：
--   - 禁止使用 == 比较秘密值
--   - 禁止对秘密值进行算术运算（+ - * /）
--   - 禁止将秘密值用作表键（t[secretValue]）
--   - 允许：FontString:SetText(secretValue) 和 SetTexture(secretValue)
-- 本函数通过四层防护确保安全：
--   1. dispelName 安全处理（行 X）：isdessecretvalue 检测，秘密值时降级为空字符串
--   2. duration/expirationTime 安全处理（行 Y）：F.IsAuraNonSecret 整体判断，
--      秘密值时 start=0, duration=0，倒计时显示被隐藏
--   3. sourceUnit 安全处理（行 Z）：F.IsValueNonSecret 安全检测，
--      不可读时 castByMe 默认为 false，不会错误匹配 "me" 过滤
--   4. spell/name 安全处理（循环体内）：用作表键前通过 issecretvalue 过滤，
--      秘密值时跳过该指示器
-- 参见文件顶部 NOTE for Custom Indicator authors 了解更多细节
function I.UpdateCustomIndicators(unitButton, auraInfo)
    local unit = unitButton.states.displayedUnit

    local auraType = auraInfo.isHelpful and "buff" or "debuff"
    local icon = auraInfo.icon
    -- Midnight 12.0.0+: dispelName may be secret; sanitize to avoid table-key/comparison crashes downstream
    -- [SecretValue防护-1] dispelName 安全处理：秘密值时降级为空字符串，避免字符串操作崩溃
    local rawDispelName = auraInfo.dispelName
    local debuffType = auraInfo.isHarmful and ((rawDispelName and (not issecretvalue or not issecretvalue(rawDispelName))) and rawDispelName or "") or nil
    local count = auraInfo.applications
    local duration = auraInfo.duration
    -- Use per-aura check for duration: non-secret auras get real timers, secret ones get zeroed.
    -- [SecretValue防护-2] duration/expirationTime 安全处理：通过 F.IsAuraNonSecret 整体判断
    -- 非秘密光环 → 计算真实剩余时间；秘密光环 → start=0, duration=0（隐藏倒计时）
    local start
    if F.IsAuraNonSecret(auraInfo) then
        start = (auraInfo.expirationTime or 0) - auraInfo.duration
    else
        start = 0
        duration = 0
    end
    -- sourceUnit is secret on restricted auras; castByMe defaults to false when unreadable.
    -- [SecretValue防护-3] sourceUnit 安全处理：通过 F.IsValueNonSecret 安全检测
    -- 不可读时 castByMe 默认为 false，确保 "me" 过滤不会因秘密值错误匹配
    local castByMe = false
    if F.IsValueNonSecret(auraInfo.sourceUnit) then
        castByMe = auraInfo.sourceUnit == "player" or auraInfo.sourceUnit == "pet"
    end

    -- 检查流血效果（Bleed）：部分 debuff 实际是物理流血，需要由 CheckDebuffType 修正 debuffType
    -- check Bleed
    if auraInfo.isHarmful then
        debuffType = I.CheckDebuffType(debuffType, auraInfo.spellId)
    end

    -- 遍历该光环类型下所有自定义指示器，检查是否匹配
    for indicatorName, indicatorTable in pairs(customIndicators[auraType]) do
        if indicatorName and enabledIndicators[indicatorName] and unitButton.indicators[indicatorName] then
            local spell  -- 用作表键的法术标识：按名称跟踪时用 name，否则用 spellId
            --* trackByName
            if indicatorTable["trackByName"] then
                spell = auraInfo.name
            else
                spell = auraInfo.spellId
            end

            -- Midnight 12.0.0+: spell (name or spellId) may be secret; cannot use as table key
            -- [SecretValue防护-4] spell 安全处理：用作表键前通过 issecretvalue 过滤
            -- 秘密值时跳过该指示器（无法安全匹配法术列表）
            -- 特殊路径：当 auras[0] 存在且 duration ~= 0 时匹配所有光环（如"显示全部"模式）
            if spell and (not issecretvalue or not issecretvalue(spell)) and indicatorTable["auras"][spell] or (indicatorTable["auras"][0] and duration ~= 0) then -- is in indicator spell list
                -- 检查施法者过滤条件
                -- check caster
                if (indicatorTable["castBy"] == "me" and castByMe) or (indicatorTable["castBy"] == "others" and not castByMe) or (indicatorTable["castBy"] == "anyone") then
                    if auraType == "buff" then
                        Update(unitButton.indicators[indicatorName], indicatorTable, unit, spell, start, duration, debuffType, icon, count, auraInfo.refreshing)
                    else -- debuff
                        Update(unitButton.indicators[indicatorName], indicatorTable, unit, spell, start, duration, debuffType, icon, count, auraInfo.refreshing)
                    end
                end
            end
        end
    end
end

-------------------------------------------------
-- show
-------------------------------------------------
local sort = table.sort

-- 排序比较器：按优先级（order）升序排列，order 相同时按剩余时间升序
-- 用于多目标指示器（icons/bars/blocks）的匹配光环列表排序
-- a/b 格式：{order, start, duration, ...}，a[1] 和 b[1] 为优先级 order
local function comparator(a, b)
    if a[1] and b[1] then
        return a[1] < b[1]
    else
        return a[2] <= b[2]
    end
end

---
-- 渲染阶段：根据 UpdateCustomIndicators 收集到的数据，实际显示指示器控件
-- 调用时机：Cell 核心在遍历完单位所有光环后调用（在 ResetCustomIndicators 之后，UpdateCustomIndicators 多次调用之后）
-- unitButton: 要渲染的单位按钮
-- auraType:   光环类型（"buff" 或 "debuff"）
--
-- 渲染逻辑分两种模式：
--   多目标型（有 num 字段）：
--     1. 从 found[unit] 取出所有匹配光环
--     2. 按 priority 排序取前 num 个
--     3. 逐个调用 indicator[i]:SetCooldown(...) 渲染到对应子控件
--     4. 调用 indicator:Show() + UpdateSize() 完成最终布局
--   单目标型（无 num 字段）：
--     1. 从 top[unit] 取出最高优先级光环数据
--     2. 直接调用 indicator:SetCooldown(...) 渲染
--   indicator:SetCooldown 参数顺序：start, duration, debuffType, texture, count, refreshing, color
function I.ShowCustomIndicators(unitButton, auraType)
    -- 守卫：指示器控件尚未就绪时跳过（避免在单位按钮初始化阶段错误渲染）
    if not unitButton._indicatorsReady then return end

    local unit = unitButton.states.displayedUnit
    -- 遍历当前光环类型下所有已启用的自定义指示器
    for indicatorName, indicatorTable in pairs(customIndicators[auraType]) do
        local indicator = unitButton.indicators[indicatorName]
        if indicator and enabledIndicators[indicatorName] then
            -- 多目标指示器模式（如 icons/bars/blocks 类型）
            if indicatorTable["num"] then
                local t = indicatorTable["found"][unit]
                if t[1] then
                    sort(t, comparator) -- 按 priority 升序排列
                    -- 仅渲染前 num 个最高优先级的光环
                    for i = 1, indicatorTable["num"] do
                        if not t[i] then break end
                        -- 条目字段索引：1:order, 2:start, 3:duration, 4:debuffType, 5:icon, 6:count, 7:refreshing, 8:color
                        indicator[i]:SetCooldown(t[i][2], t[i][3], t[i][4], t[i][5], t[i][6], t[i][7], t[i][8])
                    end
                    indicator:Show()
                    indicator:UpdateSize() -- 调整多子控件布局尺寸
                end
            else
                -- 单目标指示器模式（如 icon/text/bar/rect/border 类型）
                -- 仅当 top[unit] 中有合法 start 值时渲染（确保有匹配光环）
                if indicatorTable["top"][unit] and indicatorTable["top"][unit]["start"] then
                    indicator:SetCooldown(
                        indicatorTable["top"][unit]["start"],
                        indicatorTable["top"][unit]["duration"],
                        indicatorTable["top"][unit]["debuffType"],
                        indicatorTable["top"][unit]["texture"],
                        indicatorTable["top"][unit]["count"],
                        indicatorTable["top"][unit]["refreshing"],
                        indicatorTable["top"][unit]["color"]
                    )
                end
            end
        end
    end
end