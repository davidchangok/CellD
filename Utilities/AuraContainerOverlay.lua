-------------------------------------------------
-- AuraContainerOverlay (12.1 战斗 secret 光环显示)
--
-- 目标:
--   在 CellD 现有 grid 上叠加 AuraContainer, 战斗时显示被 secret 化的
--   治疗 HoT/buff; 不改变 grid 外观, 不禁用鼠标/悬停施法。
--
-- 约束:
--   1. 不得改变 CellD grid 模样
--   2. 鼠标必须能正常使用, 悬浮 grid 施法是核心
--   3. AuraContainer/AuraButton 全部禁用鼠标事件, 由原 secure 按钮处理鼠标
--
-- 设计:
--   - 仅战斗(PLAYER_REGEN_DISABLED)时创建/显示
--   - 容器挂在 button.widgets.indicatorFrame 下(普通 Frame, 非 SecureUnitButton)
--   - filter 使用 "HELPFUL" + includeSpellIDs(与 SecretAuraTracker 同一追踪名单)
--   - 脱战隐藏, 交还现有指示器
-------------------------------------------------

local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs
local U = Cell.uFuncs
local P = Cell.pixelPerfectFuncs

Cell.vars = Cell.vars or {}

local AuraContainerCapable = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") ~= nil

local MAX_FRAMES = 5
local containers = {} -- [button] = {buffs=,debuffs=,dispels=,defensives=,dispelsButton=}
local overlayKeys = {"buffs", "debuffs", "dispels", "defensives"} -- 容器键(不含 dispelsButton 等引用)
local shown = false
-- 染色规格(2026-08-20 用户拍板): DF 同款渐变罩染 ——
-- 填充段上"顶部类型色 → 底部透明"的渐变(DF_Gradient_V), 引擎按类型着色;
-- 不透明度在 dim host 帧上(绑定后引擎接管纹理 alpha)。
-- 历史: 血条 secret 直喂=C++ 原生比例(上游 r279 生产验证, 勿改);
-- 曲线解码方案是冻结 bug(EvaluateCurrentHealthPercent 输出仍为 secret, 已回退)。
local DISPEL_DYE_ALPHA = 1.0

-- 染色纹理锚定: 锚定到血条"填充纹理"(StatusBar 内部, 原生按 value 裁剪)——
-- 染色只覆盖填充区域并自动跟随血量(参考 DandersFrames: gradient carrier anchors
-- to the real health fill texture, tracks health with no feed)。空区永远保持深色,
-- 填充边界可读。绝不 SetAllPoints(healthBar) —— 整条锚定会把空区罩成近均匀色,
-- "36% 看起来像满格"(用户实测)。
local function AnchorDispelTex(tex, button)
    local bar = button.widgets and button.widgets.healthBar
    tex:ClearAllPoints()
    if bar and bar.GetStatusBarTexture then
        local sbt = bar:GetStatusBarTexture()
        if sbt then
            tex:SetAllPoints(sbt)
        else
            tex:SetAllPoints(bar)
        end
    else
        tex:SetAllPoints(button)
    end
end

-------------------------------------------------
-- 追踪法术列表(与 SecretAuraTracker.officialSecretSpells 一致)
-------------------------------------------------
local officialSecretSpells = {
    -- Preservation Evoker
    355941, 363502, 364343, 366155, 367364, 373267, 376788, 409895,
    -- Augmentation Evoker
    360827, 395152, 395296, 410089, 410263, 410686, 413984,
    -- Resto Druid
    774, 8936, 33763, 48438, 155777, 439530,
    -- Disc Priest
    17, 194384, 1253593, 1300008, 1300009,
    -- Holy Priest
    139, 41635, 77489,
    -- Mistweaver Monk
    115175, 119611, 124682, 450769, 1292922,
    -- Restoration Shaman
    974, 383648, 61295, 382024, 207400, 444490,
    -- Holy Paladin
    53563, 156322, 156910, 1244893, 200025, 431381,
}

local function BuildTrackedIDs()
    local ids = {}

    if IsSpellKnown then
        for _, id in ipairs(officialSecretSpells) do
            if IsSpellKnown(id) then
                ids[id] = true
            end
        end
        -- ★ 注意: 不做"全量兜底"(IsSpellKnown 不可用时)"——
        --   全量会导致奶德追踪到圣骑道标 200025 等跨职业技能(用户实测异常)
    end

    -- 当前布局中自定义 buff 指示器(Healers 等)的法术列表
    local layoutTable = Cell.vars and Cell.vars.currentLayoutTable
    if layoutTable and layoutTable.indicators then
        for _, ind in ipairs(layoutTable.indicators) do
            local auras = ind and ind["auras"]
            if auras and ind["auraType"] == "buff" then
                for k, v in pairs(auras) do
                    if type(k) == "number" and type(v) == "number" then
                        ids[v] = true
                    end
                end
            end
        end
    end

    -- 内置 externals
    if I and I.GetExternals then
        local externals = I.GetExternals()
        if externals then
            for _, spells in pairs(externals) do
                for id, v in pairs(spells) do
                    if type(id) == "number" then ids[id] = true end
                    if type(v) == "table" then
                        for subId in pairs(v) do
                            ids[subId] = true
                        end
                    end
                end
            end
        end
    end

    return ids
end

-------------------------------------------------
-- 读取与 CombatBuffTracker 一致的布局配置
-------------------------------------------------
local function GetAuraConfig(button)
    local layoutTable = Cell.vars and Cell.vars.currentLayoutTable
    if layoutTable and layoutTable.indicators then
        for _, ind in ipairs(layoutTable.indicators) do
            if ind["type"] == "icons" and ind["auraType"] == "buff" then
                return ind
            end
        end
    end
    return nil
end

-------------------------------------------------
-- AuraButton 初始化(引擎创建按钮时调用)
-------------------------------------------------
local function InitAuraButton(auraButton, config)
    local size = config and config["size"] or {13, 13}
    local w, h
    if type(size[1]) == "table" then
        w = size[1][1] or 13
        h = size[1][2] or 13
    else
        w = size[1] or 13
        h = size[2] or 13
    end
    auraButton:SetSize(w, h)

    local icon = auraButton:CreateTexture(nil, "BORDER")
    icon:SetAllPoints(auraButton)
    auraButton:SetIcon(icon)
    -- 供驱散染色轮询读取: 引擎会把绑定 aura 的图标 fileID 设置到该纹理上
    auraButton._auraIcon = icon

    -- 倒计时不显示数字, 与脱战 Healers 指示器视觉保持一致
    -- (需要数字时再按配置 showDuration 添加)

    -- 鼠标必须保持可用: AuraButton 不接收任何鼠标事件
    auraButton:EnableMouse(false)
    auraButton:SetMouseClickEnabled(false)
    auraButton:SetMouseMotionEnabled(false)
end

-------------------------------------------------
-- 通用布局: 设置 AuraContainer 的位置与流式方向
-------------------------------------------------
local function ApplyContainerLayout(container, button, config, defaultOrientation, maxFrames)
    local size = config and config["size"] or {13, 13}
    local width, height
    maxFrames = maxFrames or MAX_FRAMES

    -- debuffs 的 size 是 {{normalSize}, {bigSize}}
    if type(size[1]) == "table" then
        width = (size[1][1] or 13) * maxFrames
        height = size[1][2] or 13
    else
        width = (size[1] or 13) * maxFrames
        height = size[2] or 13
    end

    container:SetSize(width, height)

    if config and config["position"] and config["position"][1] then
        local pos = config["position"]
        local rel = pos[2] == "button" and button or (button.widgets[pos[2]] or button)
        container:SetPoint(pos[1], rel, pos[3], pos[4] or 0, pos[5] or 0)
    else
        container:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 3)
    end

    local orientation = (config and config["orientation"]) or defaultOrientation or "right-to-left"
    if orientation == "left-to-right" then
        container:SetFlowLayoutAnchorPoint("TOPLEFT")
        container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
        container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    elseif orientation == "top-to-bottom" then
        container:SetFlowLayoutAnchorPoint("TOPLEFT")
        container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Vertical)
        container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Down, AnchorUtil.FlowDirection.Right)
    elseif orientation == "bottom-to-top" then
        container:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
        container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Vertical)
        container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Up, AnchorUtil.FlowDirection.Right)
    else -- right-to-left (默认)
        container:SetFlowLayoutAnchorPoint("TOPRIGHT")
        container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
        container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Down)
    end
    container:SetFlowLayoutPadding(0, 0, 0, 0)
end

-------------------------------------------------
-- 通用容器创建(禁用鼠标)
-------------------------------------------------
local function CreateContainer(button)
    if not AuraContainerCapable then return nil end
    -- 避免战斗锁定期创建 AuraContainer; 应提前在脱战创建
    if InCombatLockdown and InCombatLockdown() then return nil end

    local parent = button.widgets and button.widgets.indicatorFrame
    if not parent then return nil end

    local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")

    -- 鼠标/点击完全交给 secure 按钮
    container:EnableMouse(false)
    container:SetMouseClickEnabled(false)
    container:SetMouseMotionEnabled(false)
    container:SetEnabled(true)
    container:SetShown(false)

    return container
end

-------------------------------------------------
-- 创建 buff(HoT) 覆盖层
-------------------------------------------------
local function CreateBuffOverlay(button)
    if not containers[button] then containers[button] = {} end
    if containers[button].buffs then return containers[button].buffs end

    local container = CreateContainer(button)
    if not container then return nil end

    local config = GetAuraConfig(button)
    ApplyContainerLayout(container, button, config, "right-to-left")

    local ids = BuildTrackedIDs()
    container:AddAuraGroup("secret", "HELPFUL", {
        maxFrameCount = MAX_FRAMES,
        candidateFilters = { includeSpellIDs = ids },
        sortMethod = AuraContainerSortMethod.ExpirationOnly,
        sortDirection = AuraContainerSortDirection.Normal,
        layout = {
            elementSpacing = (config and config["spacing"] and config["spacing"][1]) or 0,
            elementWidth = (config and config["size"] and config["size"][1]) or 13,
            elementHeight = (config and config["size"] and config["size"][2]) or 13,
        },
        templateNames = { "CustomAuraButtonTemplate" },
        initializeFrame = function(auraButton)
            InitAuraButton(auraButton, config)
        end,
    })

    containers[button].buffs = container
    return container
end

-------------------------------------------------
-- 创建 debuff 图标覆盖层
-------------------------------------------------
local function CreateDebuffOverlay(button)
    if not containers[button] then containers[button] = {} end
    if containers[button].debuffs then return containers[button].debuffs end

    local container = CreateContainer(button)
    if not container then return nil end

    local config
    local layoutTable = Cell.vars and Cell.vars.currentLayoutTable
    if layoutTable and layoutTable.indicators then
        for _, ind in ipairs(layoutTable.indicators) do
            if ind["indicatorName"] == "debuffs" then
                config = ind
                break
            end
        end
    end
    -- 调试阶段: 暂时不因布局中禁用 debuffs 而跳过创建, 先确保能看到 debuff
    -- TODO: 稳定后再恢复尊重 config["enabled"]
    if not config then
        -- 布局中未找到 debuffs 配置时使用默认配置, 保证能看到 debuff
        config = {
            ["enabled"] = true,
            ["position"] = {"BOTTOMLEFT", "button", "BOTTOMLEFT", 1, 4},
            ["size"] = {{13, 13}, {17, 17}},
            ["num"] = 3,
            ["orientation"] = "left-to-right",
        }
    end

    local maxFrames = (config and config["num"]) or 3
    local size = config and config["size"] or {{13, 13}, {17, 17}}
    local normalSize = size[1] or {13, 13}

    -- 临时调试: 完全模仿 C 容器的参数, 确认是不是自定义布局/过滤导致不显示
    container:SetSize(150, 28)
    container:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)

    container:AddAuraGroup("debuffs", "HARMFUL", {
        maxFrameCount = 5,
        -- 不限制 includeSpellIDs, 避免战斗中 IsSpellKnown 异常导致空列表
        candidateFilters = nil,
        sortMethod = AuraContainerSortMethod.ExpirationOnly,
        sortDirection = AuraContainerSortDirection.Normal,
        layout = {
            elementSpacing = 2,
            elementWidth = 28,
            elementHeight = 28,
        },
        templateNames = { "CustomAuraButtonTemplate" },
        initializeFrame = function(auraButton)
            InitAuraButton(auraButton, config)
        end,
    })

    containers[button].debuffs = container
    return container
end

-------------------------------------------------
-- 驱散染色 (12.1 受限环境方案 v4, 2026-08-19)
--
-- 实测结论链(用户四轮游戏内反馈):
--   v1(SetAuraBorder/customDispelColorMap): 引擎对 secret 光环拒绝渲染
--     驱散类型边框(颜色会泄露受限信息) → 无颜色
--   v2(每类型槽 + includeSpellIDs): 引擎对 slot 忽略 includeSpellIDs
--     (三种类型槽同时绑定, Disease 槽也绑定了非疾病 debuff) → 多染色层
--     叠加 → 永远显示最上层(Magic 蓝)且叠成实色 → "颜色都一样且不透明"
--   v3(读 icon:GetTexture 反查类型): 引擎把图标 fileID 做了 secret 包装
--     (实测 icon=secret) → 图标身份通道也被堵死
--
-- v5 方案(BigWigs 12.1 实证配方, 当前代码):
--   单个 AuraSlot(filter="HARMFUL") + 整格白色纹理 + AddDispelTypeTexture
--   (style=PreserveAsset, 无自定义色表) → 引擎按绑定 aura 的真实驱散类型
--   给纹理着色(战斗内 secret 环境可用 —— BigWigs_Plugins/Auras.lua 同款,
--   用户实测); 不可驱散(showWithoutDispelType=false)不上色, 保持 grid 外观
--
-- 历史教训(v1-v4 全部被实证无效/不可靠):
--   v1 SetAuraBorder+customDispelColorMap: 引擎不上色
--   v2 per-type 槽+includeSpellIDs: slot 忽略该过滤, 全绑定+叠加
--   v3 icon:GetTexture 反查: fileID 被 secret 包装
--   v4 per-type 槽+includeDispelTypes(集合): 曾成功绑定渲染, 但
--     颜色固定为"该类型静态色"(即使多 debuff 也只显示顶层槽);
--     且 CanBeAccessedInContext 在受限环境恒 false, 无法作为绑定判据
-- 通用教训: 移除/接管默认部件(Clear*/空模板/SetIcon)均会破坏槽绑定;
--   BigWigs 证明引擎侧渲染(图标/边框/着色)在受限环境可用, 插件侧读取全部封死
-------------------------------------------------
local _dispelTypes = {"Magic", "Curse", "Disease", "Poison", "Bleed"}
local _dispelTypeSet = {Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true}

-- 构建 CellDB 用户色映射(AddDispelTypeTexture 的 customDispelColorMap;
-- VuhDo 生产路径 = AddDispelTypeTexture + customDispelColorMap)
-- 懒缓存: 每个按钮的 initializeFrame 都会调用, 避免重复构建(CreateColor 开销)
local _dispelColorMapCache
local function BuildDispelColorMap()
    if _dispelColorMapCache then return _dispelColorMapCache end
    local map = {}
    local fallback = {
        Magic = {0.2, 0.6, 1.0},
        Curse = {0.6, 0.0, 1.0},
        Disease = {0.6, 0.4, 0.0},
        Poison = {0.0, 0.6, 0.0},
        Bleed = {1.0, 0.2, 0.6},
    }
    for _, dispelType in ipairs(_dispelTypes) do
        local c = CellDB and CellDB["debuffTypeColor"] and CellDB["debuffTypeColor"][dispelType]
        if c and c.r and c.g and c.b then
            map[dispelType] = CreateColor(c.r, c.g, c.b, 1)
        else
            local f = fallback[dispelType] or {1, 1, 1}
            map[dispelType] = CreateColor(f[1], f[2], f[3], 1)
        end
    end
    _dispelColorMapCache = map
    return map
end

-- ★ secret 安全的颜色机制(customDispelColorCurve) —— DandersFrames 实测结论:
--   customDispelColorMap 按 auraData.dispelName(secret!) 查表 → 战斗中永远
--   no-op(白色/无色, 即"dispel overlay goes white in dungeons"根因)。
--   曲线 X 轴 = 驱散类型 DB2 ID(引擎内部数字, 非 secret), 引擎经
--   GetAuraDispelTypeColor(unit, auraInstanceID, curve) C 侧解码 → 战斗内正常!
--   ID: None=0 Magic=1 Curse=2 Disease=3 Poison=4 Enrage=9 Bleed=11
--   (Blizzard_CustomAuraButton: 有 customDispelColorCurve 时无条件优先于 map;
--    必须锚定 0 点, 否则曲线在 0 处外推会顶替色表)
--   参考: DandersFrames Frames/Border.lua:843-920 (GetDispelColorCurve)
local _dispelDB2IDs = {None = 0, Magic = 1, Curse = 2, Disease = 3, Poison = 4, Enrage = 9, Bleed = 11}

local function GetCellDispelRGB(dispelType)
    local c = CellDB and CellDB["debuffTypeColor"] and CellDB["debuffTypeColor"][dispelType]
    if c and c.r and c.g and c.b then
        return c.r, c.g, c.b
    end
    local fallback = {
        Magic = {0.2, 0.6, 1.0},
        Curse = {0.6, 0.0, 1.0},
        Disease = {0.6, 0.4, 0.0},
        Poison = {0.0, 0.6, 0.0},
        Bleed = {1.0, 0.2, 0.6},
    }
    local f = fallback[dispelType] or {1, 1, 1}
    return f[1], f[2], f[3]
end

local _dispelColorCurveCache
local function BuildDispelColorCurve()
    if _dispelColorCurveCache then return _dispelColorCurveCache end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end
    local curve = C_CurveUtil.CreateColorCurve()
    if not curve then return nil end
    if curve.SetType and Enum and Enum.LuaCurveType then
        curve:SetType(Enum.LuaCurveType.Linear)
    end
    -- 锚定 0(None=透明, 无驱散类型不上色; 与 showWithoutDispelType=false 双保险)
    curve:AddPoint(_dispelDB2IDs.None, CreateColor(0, 0, 0, 0))
    for _, dispelType in ipairs(_dispelTypes) do
        local r, g, b = GetCellDispelRGB(dispelType)
        curve:AddPoint(_dispelDB2IDs[dispelType], CreateColor(r, g, b, 1))
    end
    -- Enrage(9) → Bleed 色(与原版/Grid2/DF 同款)
    local r, g, b = GetCellDispelRGB("Bleed")
    curve:AddPoint(_dispelDB2IDs.Enrage, CreateColor(r, g, b, 1))
    _dispelColorCurveCache = curve
    return curve
end

-------------------------------------------------
-- 创建驱散染色覆盖层 (v5: BigWigs 12.1 实证配方)
--   引擎按绑定 aura 的真实驱散类型给纹理上色:
--   AddDispelTypeTexture(tex, {style=PreserveAsset, showWhenHarmful=true, ...})
--   BigWigs_Plugins/Auras.lua(2026 用户实测战斗内可用)同款; 区别于
--   v1 的 SetAuraBorder+customDispelColorMap(引擎不处理) 与
--   v2-v4 的 per-type 槽(依赖类型过滤, 均被验证不可靠/无效)
-------------------------------------------------
local function CreateDispelOverlay(button)
    if not containers[button] then containers[button] = {} end
    if containers[button].dispels then return containers[button].dispels end

    -- 仅当用户在布局中启用了 Dispels 指示器才创建
    local config
    local layoutTable = Cell.vars and Cell.vars.currentLayoutTable
    if layoutTable and layoutTable.indicators then
        for _, ind in ipairs(layoutTable.indicators) do
            if ind["indicatorName"] == "dispels" then
                config = ind
                break
            end
        end
    end
    if config and config["enabled"] == false then
        return nil
    end

    local container = CreateContainer(button)
    if not container then return nil end

    -- 覆盖整个单位按钮, 帧层级与 legacy dispels.glow 一致(highLevelFrame+1 = button+141),
    -- 位于 debuff 图标(indicatorFrame +220)之下
    container:SetAllPoints(button)
    container:SetFrameLevel(button:GetFrameLevel() + 141)

    -- 最终规格: 血条填充=职业色原样(零遮挡), 染色=血量空缺区纹理(引擎上色);
    -- 多 debuff 处理: 引擎单槽取"最先到期"的 aura 类型上色(排序 ExpirationOnly);
    -- 如需按 legacy 优先级(Magic>Curse>Disease>Poison>Bleed), 可改 per-type 槽
    local slotButton = container:AddAuraSlot("dispels", "HARMFUL", {
        sortMethod = AuraContainerSortMethod.ExpirationOnly,
        sortDirection = AuraContainerSortDirection.Normal,
        initializeFrame = function(auraButton)
            auraButton:ClearAllPoints()
            auraButton:SetAllPoints(button)
            local parent = auraButton:GetParent()
            if parent then
                auraButton:SetFrameLevel(parent:GetFrameLevel() + 1)
            end
            -- 最终形态(2026-08-20 用户拍板): 全格笼罩半透明染色 ——
            -- 血条=真实血量+真实职业色(secret 直喂), 染色=覆盖整个血条的
            -- 半透明色调层(引擎按真实类型上色), 填充边界透过染色可读
            -- ★ DF 同款渐变染色载体(用户实测"很好"的形态):
            --   1) dim host 帧: 不透明度放在自有的 host 帧上 —— DF 经验: 绑定
            --      (AddDispelTypeTexture) 后引擎接管纹理 alpha, 纹理 SetAlpha 失效;
            --      host 帧 alpha 乘法仍有效(近/远/开关都靠它)
            --   2) 纹理 = DF_Gradient_V(上实心→下透明 = "一半半透明一半全透明"),
            --      引擎 SetVertexColor 按类型着色(customDispelColorCurve, secret 安全)
            --   3) BLEND 混合 + 锚定血条填充纹理(自动跟随真实血量, 空区不罩)
            local dim = CreateFrame("Frame", nil, auraButton)
            dim:SetAllPoints(auraButton)
            dim:SetFrameLevel(auraButton:GetFrameLevel() + 1)
            local tex = dim:CreateTexture(nil, "ARTWORK", nil, 2)
            AnchorDispelTex(tex, button)
            auraButton._dispelTex = tex -- B.SetOrientation hook 重锚用
            tex:SetTexture("Interface\\AddOns\\CellD\\Media\\Gradients\\DF_Gradient_V")
            tex:SetBlendMode("BLEND")
            dim:SetAlpha(DISPEL_DYE_ALPHA)
            auraButton:AddDispelTypeTexture(tex, {
                style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
                showWhenHarmful = true,
                showWhenHelpful = false,
                showWithoutDispelType = false, -- 不可驱散不上色, 保持 grid 外观
                -- ★ secret 安全: 曲线优先(战斗中 secret dispelName 查不到 map);
                -- map 仅作脱战/非 secret 回退
                customDispelColorCurve = BuildDispelColorCurve(),
                customDispelColorMap = BuildDispelColorMap(),
            })
            -- 鼠标必须保持可用: AuraButton 不接收任何鼠标事件
            auraButton:EnableMouse(false)
            auraButton:SetMouseClickEnabled(false)
            auraButton:SetMouseMotionEnabled(false)
        end,
    })

    containers[button].dispels = container
    containers[button].dispelsButton = slotButton
    return container
end

-------------------------------------------------
-- 防御技能覆盖层(12.1 战斗中 legacy 数据 secret 不更新, 引擎通道接管)
-- 与 buff overlay 同源: HELPful + includeSpellIDs(防御技能 aura ID 全职业)
-------------------------------------------------
local function BuildDefensiveIDs()
    local ids = {}
    if I and I.GetDefensives then
        local defs = I.GetDefensives()
        if defs then
            for _, spells in pairs(defs) do
                for id, v in pairs(spells) do
                    if type(id) == "number" and not F.IsSecretValue(id) then
                        ids[id] = true
                    end
                end
            end
        end
    end
    return ids
end

local function CreateDefensiveOverlay(button)
    if not containers[button] then containers[button] = {} end
    if containers[button].defensives then return containers[button].defensives end

    local config
    local layoutTable = Cell.vars and Cell.vars.currentLayoutTable
    if layoutTable and layoutTable.indicators then
        for _, ind in ipairs(layoutTable.indicators) do
            if ind["indicatorName"] == "defensiveCooldowns" then
                config = ind
                break
            end
        end
    end
    if config and config["enabled"] == false then
        return nil
    end

    local container = CreateContainer(button)
    if not container then return nil end

    ApplyContainerLayout(container, button, config, "left-to-right", (config and config["num"]) or 5)

    local ids = BuildDefensiveIDs()
    local size = (config and config["size"]) or {13, 13}
    container:AddAuraGroup("defensives", "HELPFUL", {
        maxFrameCount = (config and config["num"]) or 5,
        candidateFilters = { includeSpellIDs = ids },
        sortMethod = AuraContainerSortMethod.ExpirationOnly,
        sortDirection = AuraContainerSortDirection.Normal,
        layout = {
            elementSpacing = (config and config["spacing"] and config["spacing"][1]) or 0,
            elementWidth = size[1] or 13,
            elementHeight = size[2] or 13,
        },
        templateNames = { "CustomAuraButtonTemplate" },
        initializeFrame = function(auraButton)
            InitAuraButton(auraButton, config)
        end,
    })

    containers[button].defensives = container
    return container
end

-------------------------------------------------
-- 确保某按钮的全部覆盖层已创建
-------------------------------------------------
local function EnsureOverlays(button)
    if not AuraContainerCapable then return end
    if InCombatLockdown and InCombatLockdown() then return end
    CreateBuffOverlay(button)
    CreateDebuffOverlay(button)
    CreateDispelOverlay(button)
    CreateDefensiveOverlay(button)
end

-------------------------------------------------
-- 同步单个按钮
-------------------------------------------------
local function SyncButton(button)
    EnsureOverlays(button)

    local overlays = containers[button]
    if not overlays then return end

    local unit = button.states and (button.states.displayedUnit or button.states.unit) or button:GetAttribute("unit")
    -- 未分配单位(SoloFrame 等隐藏按钮为 "none")时不绑定, 避免污染状态;
    -- 注意: states 字段可能是 secret 值, 必须 IsSecretValue 判断 BEFORE 比较
    if F.IsSecretValue and F.IsSecretValue(unit) then
        unit = nil
    elseif unit == nil or unit == "none" or unit == "" then
        unit = nil
    end

    for _, key in ipairs(overlayKeys) do
        local container = overlays[key]
        if container then
            -- buff 每次同步刷新追踪列表
            if key == "buffs" then
                container:SetAuraGroupCandidateFilters("secret", { includeSpellIDs = BuildTrackedIDs() })
            end

            if unit then
                container:SetUnit(unit)
            end

            if shown and unit and UnitExists(unit) then
                if container.SetEnabled then
                    container:SetEnabled(true)
                end
                container:SetShown(true)
                if container.SetOnUpdateMode then
                    container:SetOnUpdateMode(Enum.OnUpdateMode.RunWhenVisible)
                end
                container:UpdateAllAuras()
            else
                container:SetShown(false)
            end
        end
    end
end

-- 提前创建所有当前按钮的覆盖层(脱战安全创建, 避免战斗锁定期创建)
local function CreateAll()
    if InCombatLockdown and InCombatLockdown() then return end
    F.IterateAllUnitButtons(EnsureOverlays, true)
end

-- 战斗 overlay 生效时隐藏旧版 debuffs/dispels/defensives, 避免重复显示
local function HideLegacyIndicators()
    F.IterateAllUnitButtons(function(button)
        if button.indicators then
            if button.indicators.debuffs then
                button.indicators.debuffs:Hide()
            end
            if button.indicators.dispels then
                button.indicators.dispels:Hide()
            end
            if button.indicators.defensiveCooldowns then
                button.indicators.defensiveCooldowns:Hide()
            end
        end
    end, true)
end

local function ShowAll()
    shown = true
    -- 尽量先确保容器已创建; 若仍在战斗锁定期, EnsureOverlays 内部不保证成功
    CreateAll()
    HideLegacyIndicators()
    F.IterateAllUnitButtons(SyncButton, true)
end

local function HideAll()
    shown = false
    for _, overlays in pairs(containers) do
        if overlays then
            for _, key in ipairs(overlayKeys) do
                local container = overlays[key]
                if container then
                    -- 引擎 12.1 可能自行恢复容器显隐: 显示+启用一起关(Grid2 同款)
                    if container.SetEnabled then
                        container:SetEnabled(false)
                    end
                    container:SetShown(false)
                end
            end
        end
    end
end

-------------------------------------------------
-- 调试: 查看某个单位按钮上的 overlay 状态
-------------------------------------------------
-- 打印辅助: secret 值安全转字符串(secret 的 tostring 返回 secret 字符串,
-- 直接 table.concat/拼接会报 "invalid value (secret)")
local function Str(v)
    if v == nil then return "nil" end
    if F.IsSecretValue and F.IsSecretValue(v) then return "SECRET" end
    return tostring(v)
end

function U.DebugAuraOverlay(unit)
    unit = unit or "player"
    local found = false
    F.IterateAllUnitButtons(function(button)
        local bunit = button.states and (button.states.displayedUnit or button.states.unit) or button:GetAttribute("unit")
        if bunit ~= unit then return end
        found = true
        local name = button:GetName() or tostring(button)
        local overlays = containers[button]
        if not overlays then
            F.Print("CellD AuraOverlay: " .. name .. " -> no overlays")
            return
        end
        for _, key in ipairs(overlayKeys) do
            local container = overlays[key]
            if container then
                local w, h = container:GetSize()

                -- 驱散染色: 单槽 + 引擎按类型着色; acc 在受限环境恒为 false, 仅供参考
                if key == "dispels" then
                    local slotButton = overlays.dispelsButton
                    local state = "no-slot"
                    if slotButton and slotButton.CanBeAccessedInContext then
                        local canAccess = slotButton:CanBeAccessedInContext()
                        -- 战斗锁定期对受保护 AuraButton 调用 IsShown 会抛 forbidden:
                        -- 必须 canAccess 且 pcall 包裹
                        local isShown
                        if canAccess and not (F.IsSecretValue and F.IsSecretValue(canAccess)) then
                            local ok, shown = pcall(slotButton.IsShown, slotButton)
                            isShown = ok and shown or nil
                        end
                        state = "acc=" .. Str(canAccess) .. " shown=" .. Str(isShown)
                    end
                    F.Print(string.format("CellD AuraOverlay: %s [dispels] shown=%s unit=%s enabled=%s size=%sx%s slot(%s)",
                        name, Str(container:IsShown()), Str(container:GetUnit()), Str(container:IsEnabled()),
                        tostring(w), tostring(h), state))
                else
                    local groupKey = key == "buffs" and "secret" or tostring(key)
                    local frameCount = 0
                    local activeFrames = 0
                    local frameStates = {}
                    if container.GetAuraGroupFrameCount then
                        frameCount = container:GetAuraGroupFrameCount(groupKey) or 0
                        for i = 1, math.min(frameCount, 5) do
                            local f = container:GetAuraGroupFrame(groupKey, i)
                            if f and f.CanBeAccessedInContext then
                                local canAccess = f:CanBeAccessedInContext()
                                -- 战斗锁定期对受保护对象调用 IsShown 抛 forbidden: 守卫 + pcall
                                local isShown
                                if canAccess and not (F.IsSecretValue and F.IsSecretValue(canAccess)) then
                                    local ok, shown = pcall(f.IsShown, f)
                                    isShown = ok and shown or nil
                                end
                                frameStates[#frameStates + 1] = "f" .. i .. "(acc=" .. Str(canAccess) .. " shown=" .. Str(isShown) .. ")"
                                if not (F.IsSecretValue and F.IsSecretValue(canAccess)) and canAccess then
                                    if not (F.IsSecretValue and F.IsSecretValue(isShown)) and isShown then
                                        activeFrames = activeFrames + 1
                                    end
                                end
                            end
                        end
                    end
                    F.Print(string.format("CellD AuraOverlay: %s [%s] shown=%s unit=%s enabled=%s size=%sx%s frames=%s active=%s %s",
                        name, tostring(key), Str(container:IsShown()), Str(container:GetUnit()), Str(container:IsEnabled()),
                        tostring(w), tostring(h), tostring(frameCount), tostring(activeFrames), table.concat(frameStates, " ")))
                end
            else
                F.Print("CellD AuraOverlay: " .. name .. " [" .. tostring(key) .. "] = nil")
            end
        end
    end, true)
    if not found then
        F.Print("CellD AuraOverlay: no CellD button found for " .. unit)
    end
end

-- 调试: 先强制创建+同步所有按钮(绑定单位/显隐), 再输出状态
-- 用于脱战(副本内不打怪)验证"单位绑定"是否修复: [dispels] unit= 应为 player 而非 none
function U.DebugInfoSync(unit)
    if not InCombatLockdown() then
        CreateAll()
    end
    F.IterateAllUnitButtons(SyncButton, true)
    U.DebugAuraOverlay(unit)
end

-------------------------------------------------
-- 永久隐藏 legacy dispels(12.1 脱战后其刷新不恢复, 且与常驻 overlay 叠加)
-- 注意: legacy glow/highlight 是 highLevelFrame 子对象, 不受 dispels:Hide() 控制,
-- SetDispels 每次更新会重新 Show → 必须 hooksecurefunc 后置隐藏(零闪烁)
-------------------------------------------------
local function HookLegacyDispels(button)
    local dispels = button.indicators and button.indicators.dispels
    if not dispels or dispels._auraOverlayHooked then return end
    dispels._auraOverlayHooked = true
    hooksecurefunc(dispels, "SetDispels", function(self)
        if self.glow then self.glow:Hide() end
        if self.highlight then self.highlight:Hide() end
    end)
end

local function HideLegacyDispels()
    F.IterateAllUnitButtons(function(button)
        HookLegacyDispels(button)
        if button.indicators and button.indicators.dispels then
            button.indicators.dispels:Hide()
        end
    end, true)
end

-------------------------------------------------
-- 驱散染色常驻同步: 脱战后引擎用真实数据继续显示(12.1 legacy 不恢复,
-- "脱战清空"会导致仍挂着的 debuff 无显示, 治疗看不到 = 危险)
-------------------------------------------------
local function SyncDispelsOutOfCombat()
    F.IterateAllUnitButtons(function(button)
        local overlays = containers[button]
        local container = overlays and overlays.dispels
        if container and overlays.dispelsButton then
            local unit = button.states and (button.states.displayedUnit or button.states.unit) or button:GetAttribute("unit")
            if F.IsSecretValue and F.IsSecretValue(unit) then
                unit = nil
            elseif unit == nil or unit == "none" or unit == "" then
                unit = nil
            end
            if unit then
                container:SetUnit(unit)
                container:SetEnabled(true)
                container:SetShown(true)
                container:UpdateAllAuras()
            end
        end
    end, true)
end

-------------------------------------------------
-- 战斗期轻量刷新: 引擎自身 tick 有延迟, 新 debuff 落地后图标出现略慢;
-- 每 0.5s 调一次 UpdateAllAuras 兜底(仅 shown 期间, 成本极低)
-------------------------------------------------
local _refreshTimer = 0
local refreshFrame = CreateFrame("Frame")
refreshFrame:SetScript("OnUpdate", function(self, elapsed)
    if not shown then
        _refreshTimer = 0
        return
    end
    _refreshTimer = _refreshTimer + elapsed
    if _refreshTimer < 0.5 then return end
    _refreshTimer = 0
    for button, overlays in pairs(containers) do
        if overlays then
            for _, key in ipairs(overlayKeys) do
                local container = overlays[key]
                if container and container.UpdateAllAuras then
                    container:UpdateAllAuras()
                end
            end
        end
    end
end)

-------------------------------------------------
-- 事件
-------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if not AuraContainerCapable then return end

    if event == "PLAYER_REGEN_DISABLED" then
        Cell.vars.auraContainerOverlayActive = true
        ShowAll()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Cell.vars.auraContainerOverlayActive = false
        HideAll()
        CreateAll() -- 为下一场战斗提前创建
        -- 驱散染色常驻: 脱战后引擎用真实数据继续显示(防"脱战清空无显示"危险)
        HideLegacyDispels()
        SyncDispelsOutOfCombat()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not InCombatLockdown() then
            CreateAll()
        end
        if shown then
            F.IterateAllUnitButtons(SyncButton, true)
        else
            HideLegacyDispels()
            SyncDispelsOutOfCombat()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not InCombatLockdown() then
            CreateAll()
        end
        if not shown then
            HideLegacyDispels()
            SyncDispelsOutOfCombat()
        end
    end
end)

-- 模块加载: 隐藏 legacy dispels, 由常驻 overlay 接管
HideLegacyDispels()

-- 血条方向切换(水平 ↔ vertical_health)后重锚染色纹理
-- (锚点依赖方向: 水平=填充右缘→条右缘, 垂直=填充上缘→条上缘)
if Cell.bFuncs and Cell.bFuncs.SetOrientation then
    hooksecurefunc(Cell.bFuncs, "SetOrientation", function(button, ...)
        if type(button) ~= "table" then return end
        local overlays = containers[button]
        local tex = overlays and overlays.dispelsButton and overlays.dispelsButton._dispelTex
        if tex then
            AnchorDispelTex(tex, button)
        end
    end)
end

-- 布局切换后重建覆盖层, 暂时注释排查加载问题
-- if Cell.RegisterCallback then
--     local ok, err = pcall(Cell.RegisterCallback, "UpdateLayout", "AuraContainerOverlay_UpdateLayout", function()
--         if not InCombatLockdown() then
--             HideAll()
--             wipe(containers)
--             CreateAll()
--         end
--     end)
--     if not ok then
--         F.Debug("AuraContainerOverlay RegisterCallback error: " .. tostring(err))
--     end
-- end

Cell.vars.auraContainerOverlayActive = false

-- 如果模块加载时已经在战斗中, 暂时注释排查加载问题
-- if UnitAffectingCombat and UnitAffectingCombat("player") then
--     local ok, err = pcall(function()
--         Cell.vars.auraContainerOverlayActive = true
--         ShowAll()
--     end)
--     if not ok then
--         F.Debug("AuraContainerOverlay init error: " .. tostring(err))
--     end
-- end
