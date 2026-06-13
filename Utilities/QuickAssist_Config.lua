-- =========================================================================== --
--  QuickAssist 配置面板 (QuickAssist_Config.lua)
--  ----------------------------------------------------------------------- --
--  功能：为 Cell 的 QuickAssist 功能提供完整的配置界面
--  包含四个子页面：Layout(布局) / Style(样式) / Spells(法术) + 过滤器自动切换面板
--  所有配置按专精(specID)独立存储于 CellDB["quickAssist"][specID]
--  通过 Cell 回调系统响应显示/重载/更新事件
-- =========================================================================== --
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local U = Cell.uFuncs
local A = Cell.animations
local P = Cell.pixelPerfectFuncs
-- LCG: LibCustomGlow 库，用于给按钮添加自定义光效
local LCG = LibStub("LibCustomGlow-1.0")

-- ----------------------------------------------------------------------- --
--                                 defaults                                --
-- ----------------------------------------------------------------------- --
-- 以下默认配置表定义了各职业的爆发增益(Buffs)和爆发施法(Casts)列表
-- 格式：buff为法术ID，cast为"法术ID:持续时间"
local defaultOffensiveBuffs = {
    ["DEATHKNIGHT"] = {
        47568, -- Empower Rune Weapon, 符文武器增效
    },
    ["DEMONHUNTER"] = {
    },
    ["DRUID"] = {
        102543, -- Incarnation: Avatar of Ashamane, 化身：阿莎曼之灵
        102560, -- Incarnation: Chosen of Elune, 化身：艾露恩之眷
    },
    ["EVOKER"] = {
        375087, -- Dragonrage, 狂龙之怒
    },
    ["HUNTER"] = {
        288613, -- Trueshot, 百发百中
        360952, -- Coordinated Assault, 协同进攻
        359844, -- Call of the Wild, 荒野的召唤
    },
    ["MAGE"] = {
        12472, -- Icy Veins, 冰冷血脉
        365362, -- Arcane Surge, 奥术涌动
    },
    ["MONK"] = {
    },
    ["PALADIN"] = {
        31884, -- Avenging Wrath, 复仇之怒
        231895, -- Crusade, 征伐
    },
    ["PRIEST"] = {
        194249, -- Voidform, 虚空形态
    },
    ["ROGUE"] = {
        121471, -- Shadow Blades, 暗影之刃
        13750, -- Adrenaline Rush, 冲动
    },
    ["SHAMAN"] = {
        333957, -- Feral Spirit, 野性狼魂
    },
    ["WARLOCK"] = {
    },
    ["WARRIOR"] = {
        107574, -- Avatar, 天神下凡
    },
}

local defaultOffensiveCasts = {
    ["DEATHKNIGHT"] = {
        "49206:25", -- Summon Gargoyle, 召唤石像鬼
        "42650:30", -- Army of the Dead, 亡者大军
    },
    ["DEMONHUNTER"] = {
        "191427:20", -- Metamorphosis, 恶魔变形
    },
    ["DRUID"] = {
    },
    ["EVOKER"] = {
    },
    ["HUNTER"] = {
    },
    ["MAGE"] = {
        "190319:12", -- Combustion, 燃烧
    },
    ["MONK"] = {
        "123904:20", -- Invoke Xuen, the White Tiger, 白虎下凡
    },
    ["PALADIN"] = {
    },
    ["PRIEST"] = {
    },
    ["ROGUE"] = {
        "360194:16", -- Deathmark, 死亡印记
    },
    ["SHAMAN"] = {
        "192249:30", -- Storm Elemental, 风暴元素
    },
    ["WARLOCK"] = {
        "1122:30", -- Summon Infernal, 召唤地狱火
        "205180:20", -- Summon Darkglare, 召唤黑眼
        "265187:15", -- Summon Demonic Tyrant, 召唤恶魔暴君
    },
    ["WARRIOR"] = {
    },
}

-- 默认职责过滤：仅显示伤害输出(DAMAGER)，隐藏坦克和治疗
local defaultRoleFilter = {
    ["TANK"] = false,
    ["HEALER"] = false,
    ["DAMAGER"] = true,
}

-- 默认职业过滤：遍历所有职业，全部启用
local defaultClassFilter = {}
for class in F.IterateClasses() do
    tinsert(defaultClassFilter, {class, true})
end

-- 默认专精过滤：所有职业的所有专精全部启用
-- 结构: {{"CLASSNAME", {{specID, enabled}, ...}}, ...}
local defaultSpecFilter = {
    {
        "DEATHKNIGHT",
        {
            {250, true}, -- Blood 鲜血
            {251, true}, -- Frost 冰霜
            {252, true}, -- Unholy 邪恶
        },
    },
    {
        "DEMONHUNTER",
        {
            {581, true}, -- Vengeance 复仇
            {577, true}, -- Havoc 浩劫
        },
    },
    {
        "DRUID",
        {
            {104, true}, -- Guardian 守护
            {105, true}, -- Restoration 恢复
            {103, true}, -- Feral 野性
            {102, true}, -- Balance 平衡
        },
    },
    {
        "EVOKER",
        {
            {1468, true}, -- Preservation 恩护
            {1467, true}, -- Devastation 湮灭
            {1473, true}, -- Augmentation 增辉
        },
    },
    {
        "HUNTER",
        {
            {255, true}, -- Survival 生存
            {253, true}, -- Beast Mastery 野兽控制
            {254, true}, -- Marksmanship 射击
        },
    },
    {
        "MAGE",
        {
            {62, true}, -- Arcane 奥术
            {63, true}, -- Fire 火焰
            {64, true}, -- Frost 冰霜
        },
    },
    {
        "MONK",
        {
            {268, true}, -- Brewmaster 酒仙
            {270, true}, -- Mistweaver 织雾
            {269, true}, -- Windwalker 踏风
        },
    },
    {
        "PALADIN",
        {
            {66, true}, -- Protection 防护
            {65, true}, -- Holy 神圣
            {70, true}, -- Retribution 惩戒
        },
    },
    {
        "PRIEST",
        {
            {256, true}, -- Discipline 戒律
            {257, true}, -- Holy 神圣
            {258, true}, -- Shadow 暗影
        },
    },
    {
        "ROGUE",
        {
            {259, true}, -- Assassination 奇袭
            {260, true}, -- Combat 狂徒
            {261, true}, -- Subtlety 敏锐
        },
    },
    {
        "SHAMAN",
        {
            {264, true}, -- Restoration 恢复
            {263, true}, -- Enhancement 增强
            {262, true}, -- Elemental 元素
        },
    },
    {
        "WARLOCK",
        {
            {265, true}, -- Affliction 痛苦
            {266, true}, -- Demonology 恶魔
            {267, true}, -- Destruction 毁灭
        },
    },
    {
        "WARRIOR",
        {
            {73, true}, -- Protection 防护
            {71, true}, -- Arms 武器
            {72, true}, -- Fury 狂怒
        },
    },
}
-- 预加载所有专精图标到 specIcons 表，key 为 specID
local specIcons = {}
for _, t in pairs(defaultSpecFilter) do
    for _, st in pairs(t[2]) do
        specIcons[st[1]] = select(4, GetSpecializationInfoForSpecID(st[1]))
    end
end
-- for class, classId in F.IterateClasses() do
--     local t = {class, {}}
--     for i = 1, GetNumSpecializationsForClassID(classId) do
--         local id, _, _, icon = GetSpecializationInfoForClassID(classId, i)
--         specIcons[id] = icon
--         tinsert(t[2], {id, true})
--     end
--     tinsert(defaultSpecFilter, t)
-- end

-- QuickAssist 默认配置表，用作新专精的初始化模板
-- 结构：enabled(总开关) -> layout(布局) -> filters(单位过滤) -> filterAutoSwitch(场景自动切换) -> style(样式) -> spells(法术监控)
local defaultQuickAssistTable = {
    ["enabled"] = false,
    -- layout：按钮排列布局设置
    ["layout"] = {
        ["size"] = {75, 25},
        ["position"] = {},
        ["orientation"] = "horizontal",
        ["anchor"] = "TOPLEFT",
        ["maxColumns"] = 4,
        ["unitsPerColumn"] = 5,
        ["spacingX"] = 3,
        ["spacingY"] = 3,
    },
    ["filters"] = {
        {
            "role",
            F.Copy(defaultRoleFilter),
            -- {["role"] = enabled,...}
            -- {{"class", enabled},...}
            -- {name,...}
            false,
        },
        {"role", F.Copy(defaultRoleFilter), false},
        {"role", F.Copy(defaultRoleFilter), false},
        {"role", F.Copy(defaultRoleFilter), false},
        {"role", F.Copy(defaultRoleFilter), false},
        {"role", F.Copy(defaultRoleFilter), false},
        {"role", F.Copy(defaultRoleFilter), false},
    },
    ["filterAutoSwitch"] = {
        ["party"] = 1,
        ["raid"] = 1,
        ["mythic"] = 1,
        ["arena"] = 1,
        ["battleground"] = 1,
    },
    -- sytle
    ["style"] = {
        ["texture"] = "Cell ".._G.DEFAULT,
        ["hpColor"] = {"custom", {0.117, 0.117, 0.117, 1}},
        ["lossColor"] = {"class_color", {0.25, 0, 0, 1}},
        ["oorAlpha"] = 0.45,
        ["targetColor"] = {1, 0.31, 0.31, 1},
        ["mouseoverColor"] = {1, 1, 1, 0.6},
        ["highlightSize"] = 1,
        ["name"] = {
            ["color"] = {"class_color", {1, 1, 1}},
            ["width"] = {"percentage", 0.75},
            ["font"] = {"Cell ".._G.DEFAULT, 12, "Outline", false},
            ["position"] = {"CENTER", 0, 0},
        },
    },
    -- spells
    ["spells"] = {
        ["mine"] = {
            ["buffs"] = {
                {0, "icon", {0.95, 0.36, 0.71, 1}},
                {0, "icon", {0.23, 0.81, 0.67, 1}},
                {0, "icon", {0.61, 0.36, 0.9, 1}},
                {0, "icon", {0, 0.73, 0.98, 1}},
                {0, "icon", {0.98, 0.34, 0.03, 1}},
            },
            ["bar"] = {
                ["position"] = {"TOPRIGHT", "BOTTOMRIGHT", 0, 1},
                ["orientation"] = "top-to-bottom",
                ["size"] = {75, 4},
            },
            ["icon"] = {
                ["position"] = {"BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0},
                ["orientation"] = "right-to-left",
                ["size"] = {12, 20},
                ["glow"] = "None",
                ["showStack"] = true,
                ["showDuration"] = false,
                ["showAnimation"] = true,
                ["font"] = {
                    {"Cell ".._G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                    {"Cell ".._G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
                },
            },

        },
        ["offensives"] = {
            ["enabled"] = true,
            ["buffs"] = F.Copy(defaultOffensiveBuffs),
            ["casts"] = F.Copy(defaultOffensiveCasts),
            ["glow"] = {
                ["fadeOut"] = false,
                ["options"] = {"None", {0.95, 0.95, 0.32, 1}},
            },
            ["icon"] = {
                ["position"] = {"TOPLEFT", "TOPLEFT", 0, 0},
                ["orientation"] = "left-to-right",
                ["size"] = {12, 20},
                ["glow"] = "Proc",
                ["glowColor"] = {1, 1, 1, 1},
                ["showStack"] = true,
                ["showDuration"] = false,
                ["showAnimation"] = true,
                ["font"] = {
                    {"Cell ".._G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                    {"Cell ".._G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
                },
            },
        },
    },
}

-- 获取 QuickAssist 默认配置表的深拷贝，避免多个专精共用同一表引用
function F.GetDefaultQuickAssistTable()
    return F.Copy(defaultQuickAssistTable)
end

-- ----------------------------------------------------------------------- --
--                               config pane                               --
--  QuickAssist 配置选项卡，锚定在 utilitiesTab 上
--  所有配置子面板均创建在此选项卡内
-- ----------------------------------------------------------------------- --
local quickAssistTab = Cell.CreateFrame("CellOptionsFrame_QuickAssistTab", Cell.frames.utilitiesTab, nil, nil, true)
Cell.frames.quickAssistTab = quickAssistTab
quickAssistTab:SetAllPoints(Cell.frames.utilitiesTab)
quickAssistTab:Hide()

-- ----------------------------------------------------------------------- --
--                                  shared                                 --
-- ----------------------------------------------------------------------- --
-- 全局配置表引用（指向 CellDB 中当前专精的配置子表）
local quickAssistTable, layoutTable, styleTable, spellTable
-- 当前选中的过滤器编号、当前选中职业、当前活跃的过滤器编号
local selectedFilter, selectedClass, activeFilter
-- 延迟绑定的加载函数（在文件末尾定义，此处声明以支持相互引用）
local LoadDB, LoadLayout, LoadStyle, LoadSpells, LoadList, LoadMyBuff, ShowFilter, LoadAutoSwitch, UpdateAutoSwitch
-- UI 常量：锚点列表、排列方向、字体描边、光效类型
local anchorPoints = {"BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "LEFT", "RIGHT", "TOP", "TOPLEFT", "TOPRIGHT"}
local orientations = {"left-to-right", "right-to-left", "top-to-bottom", "bottom-to-top"}
local outlines = {"None", "Outline", "Monochrome"}
local glows = {"None", "Normal", "Pixel", "Shine", "Proc"}

-- ----------------------------------------------------------------------- --
--                              button preview                             --
--  右侧预览按钮：实时反映 Layout / Style / Spells 配置变更
--  previewButton: 预览按钮本体（使用 CellQuickAssistPreviewButtonTemplate）
--  previewButtonBG: 预览按钮的背景框
--  showIndicatorPreview: 是否在预览中循环展示法术指示器动画
-- ----------------------------------------------------------------------- --
local previewButton, previewButtonBG, showIndicatorPreview

local function GetHealthColor(r, g, b)
    -- 根据样式配置计算血条颜色和背景（损失血量）颜色
    -- r, g, b 为职业色，用于 class_color / class_color_dark 模式
    -- 返回值：hpR, hpG, hpB, hpA, lossR, lossG, lossB, lossA
    local hpR, hpG, hpB, lossR, lossG, lossB

    -- hp
    if styleTable["hpColor"][1] == "class_color" then
        hpR, hpG, hpB = r, g, b
    elseif styleTable["hpColor"][1] == "class_color_dark" then
        hpR, hpG, hpB = r*0.2, g*0.2, b*0.2
    else
        hpR = styleTable["hpColor"][2][1]
        hpG = styleTable["hpColor"][2][2]
        hpB = styleTable["hpColor"][2][3]
    end

    -- bg
    if styleTable["lossColor"][1] == "class_color" then
        lossR, lossG, lossB = r, g, b
    elseif styleTable["lossColor"][1] == "class_color_dark" then
        lossR, lossG, lossB = r*0.2, g*0.2, b*0.2
    else
        lossR = styleTable["lossColor"][2][1]
        lossG = styleTable["lossColor"][2][2]
        lossB = styleTable["lossColor"][2][3]
    end

    -- alpha
    hpA =  styleTable["hpColor"][1] == "custom" and styleTable["hpColor"][2][4] or 1
    lossA =  styleTable["lossColor"][1] == "custom" and styleTable["lossColor"][2][4] or 1

    return hpR, hpG, hpB, hpA, lossR, lossG, lossB, lossA
end

local function UpdatePreviewButton()
    -- 在配置界面右侧创建/更新 QuickAssist 按钮的实时预览
    -- 应用当前的布局尺寸、样式颜色、名字文本、法术图标等所有配置到预览按钮上
    -- 如果 QuickAssist 未启用，则隐藏预览
    if not quickAssistTab:IsVisible() then return end

    if not previewButton then
        previewButton = CreateFrame("Button", "CellQuickAssistPreviewButton", quickAssistTab, "CellQuickAssistPreviewButtonTemplate")
        previewButton:SetPoint("BOTTOMLEFT", quickAssistTab, "BOTTOMRIGHT", 5, 270)
        previewButton:UnregisterAllEvents()
        previewButton:SetScript("OnEnter", nil)
        previewButton:SetScript("OnLeave", nil)
        previewButton:SetScript("OnShow", nil)
        previewButton:SetScript("OnHide", nil)
        previewButton:SetScript("OnUpdate", nil)
        previewButton:Show()

        if CELL_BORDER_SIZE ~= 0 then
            previewButton:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(CELL_BORDER_SIZE)})
            previewButton:SetBackdropBorderColor(unpack(CELL_BORDER_COLOR))
        end

        previewButton.healthBar:SetPoint("TOPLEFT", previewButton, "TOPLEFT", P.Scale(1), P.Scale(-1))
        previewButton.healthBar:SetPoint("BOTTOMRIGHT", previewButton, "BOTTOMRIGHT", P.Scale(-1), P.Scale(1))
        previewButton.healthBar:SetMinMaxValues(0, 2)
        previewButton.healthBar:SetValue(1)

        U.QuickAssist_CreateIndicators(previewButton)

        previewButton:SetScript("OnShow", function(self, elapsed)
            self.elapsed = 13
        end)

        previewButtonBG = Cell.CreateFrame("CellQuickAssistPreviewButtonBG", quickAssistTab)
        previewButtonBG:SetPoint("TOPLEFT", previewButton, 0, 20)
        previewButtonBG:SetPoint("BOTTOMRIGHT", previewButton, "TOPRIGHT")
        Cell.StylizeFrame(previewButtonBG, {0.1, 0.1, 0.1, 0.77}, {0, 0, 0, 0})
        previewButtonBG:Show()

        local previewText = previewButtonBG:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_TITLE")
        previewText:SetPoint("TOP", 0, -3)
        previewText:SetText(Cell.GetAccentColorString()..L["Preview"])
    end

    if not quickAssistTable or not quickAssistTable["enabled"] then
        -- QuickAssist 未启用时隐藏预览
        previewButton:Hide()
        previewButtonBG:Hide()
        return
    end

    previewButton:Show()
    previewButtonBG:Show()

    -- size ------------------------------------------------------------------ --
    -- 应用布局尺寸到预览按钮
    P.Size(previewButton, layoutTable["size"][1], layoutTable["size"][2])

    -- color ----------------------------------------------------------------- --
    -- 应用状态条纹理
    local tex = F.GetBarTextureByName(styleTable["texture"])
    previewButton.healthBar:SetStatusBarTexture(tex)
    previewButton.healthLoss:SetTexture(tex)

    local hpR, hpG, hpB, hpA, lossR, lossG, lossB, lossA = GetHealthColor(F.GetClassColor(Cell.vars.playerClass))
    previewButton.healthBar:SetStatusBarColor(hpR, hpG, hpB, hpA)
    previewButton.healthLoss:SetVertexColor(lossR, lossG, lossB, lossA)

    if styleTable["name"]["color"][1] == "class_color" then
        -- 名字使用职业色
        previewButton.nameText:SetTextColor(F.GetClassColor(Cell.vars.playerClass))
    else
        -- 名字使用自定义颜色
        previewButton.nameText:SetTextColor(unpack(styleTable["name"]["color"][2]))
    end

    -- update nameText ------------------------------------------------------- --
    -- 更新预览按钮上的名字文本位置、字体、字号、描边和阴影
    previewButton.nameText:ClearAllPoints()
    previewButton.nameText:SetPoint(unpack(styleTable["name"]["position"]))

    local font, fontSize, fontOutline, fontShadow = unpack(styleTable["name"]["font"])
    font = F.GetFont(font)

    local fontFlags
    if fontOutline == "None" then
        fontFlags = ""
    elseif fontOutline == "Outline" then
        fontFlags = "OUTLINE"
    else
        fontFlags = "OUTLINE,MONOCHROME"
    end

    previewButton.nameText:SetFont(font, fontSize, fontFlags)

    if fontShadow then
        previewButton.nameText:SetShadowOffset(1, -1)
        previewButton.nameText:SetShadowColor(0, 0, 0, 1)
    else
        previewButton.nameText:SetShadowOffset(0, 0)
        previewButton.nameText:SetShadowColor(0, 0, 0, 0)
    end

    previewButton.name = Cell.vars.playerNameShort
    previewButton.nameText.width = styleTable["name"]["width"]
    previewButton.nameText:UpdateName()

    -- offensiveIcons：更新爆发法术图标指示器的位置、尺寸、排列方向和字体
    local oit = spellTable["offensives"]["icon"]
    local offensiveIcons = previewButton.offensiveIcons
    -- point
    P.ClearPoints(offensiveIcons)
    P.Point(offensiveIcons, oit["position"][1], b, oit["position"][2], oit["position"][3], oit["position"][4])
    -- size
    P.Size(offensiveIcons, oit["size"][1], oit["size"][2])
    -- orientation
    offensiveIcons:SetOrientation(oit["orientation"])
    -- font
    offensiveIcons:SetFont(unpack(oit["font"]))
    offensiveIcons:ShowDuration(oit["showDuration"])
    offensiveIcons:ShowAnimation(oit["showAnimation"])
    offensiveIcons:ShowStack(oit["showStack"])

    -- offensiveGlow：更新爆发法术光效设置
    local ogt = spellTable["offensives"]["glow"]
    local offensiveGlow = previewButton.offensiveGlow
    offensiveGlow:SetFadeOut(ogt["fadeOut"])
    offensiveGlow:SetupGlow(ogt["options"])

    -- buffIcons：更新自身增益图标指示器的位置、尺寸、排列方向和字体
    local bit = spellTable["mine"]["icon"]
    local buffIcons = previewButton.buffIcons
    -- point
    P.ClearPoints(buffIcons)
    P.Point(buffIcons, bit["position"][1], b, bit["position"][2], bit["position"][3], bit["position"][4])
    -- size
    P.Size(buffIcons, bit["size"][1], bit["size"][2])
    -- orientation
    buffIcons:SetOrientation(bit["orientation"])
    -- font
    buffIcons:SetFont(unpack(bit["font"]))
    buffIcons:ShowDuration(bit["showDuration"])
    buffIcons:ShowAnimation(bit["showAnimation"])
    buffIcons:ShowStack(bit["showStack"])

    -- buffBars：更新自身增益计时条指示器的位置、尺寸和排列方向
    local bbt = spellTable["mine"]["bar"]
    local buffBars = previewButton.buffBars
    -- point
    P.ClearPoints(buffBars)
    P.Point(buffBars, bbt["position"][1], b, bbt["position"][2], bbt["position"][3], bbt["position"][4])
    -- size
    P.Size(buffBars, bbt["size"][1], bbt["size"][2])
    -- orientation
    buffBars:SetOrientation(bbt["orientation"])

    -- show indicators：每13秒循环展示预览用的法术指示器动画
    -- 当 spell 标签页激活时(showIndicatorPreview=true)，循环显示爆发和自身增益的冷却动画
    previewButton.elapsed = 13
    previewButton:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= 13 then
            -- 每13秒重置计时器，循环播放冷却动画预览
            self.elapsed = 0

            if showIndicatorPreview then
                -- offensives
                if spellTable["offensives"]["enabled"] then
                    self.offensiveIcons:Show()
                    self.offensiveIcons[1]:SetCooldown(GetTime(), 13, nil, 135875, 0, false, oit["glowColor"], oit["glow"])
                    self.offensiveIcons[2]:SetCooldown(GetTime(), 13, nil, 135838, 0, false, oit["glowColor"], oit["glow"])
                    self.offensiveIcons:UpdateSize(2)
                else
                    self.offensiveIcons:Hide()
                end
                self.offensiveGlow:SetCooldown(GetTime(), 13)
                -- buffs
                self.buffIcons:Show()
                self.buffIcons[1]:SetCooldown(GetTime(), 13, nil, 5199639, 0, false, spellTable["mine"]["buffs"][1][3], bit["glow"])
                self.buffIcons[2]:SetCooldown(GetTime(), 13, nil, 5061347, 0, false, spellTable["mine"]["buffs"][2][3], bit["glow"])
                self.buffIcons:UpdateSize(2)
                self.buffBars:Show()
                self.buffBars[1]:SetCooldown(GetTime(), 13, spellTable["mine"]["buffs"][1][3])
                self.buffBars[2]:SetCooldown(GetTime(), 13, spellTable["mine"]["buffs"][2][3])
                self.buffBars:UpdateSize(2)
            else
                self.offensiveIcons:Hide()
                self.buffIcons:Hide()
                self.buffBars:Hide()
                self.offensiveGlow:Hide()
            end
        end
    end)
end
-- 注册回调：配置重载或更新时刷新预览按钮
Cell.RegisterCallback("ReloadQuickAssist", "UpdatePreviewButton", UpdatePreviewButton)
Cell.RegisterCallback("UpdateQuickAssist", "UpdatePreviewButton", UpdatePreviewButton)

-- ----------------------------------------------------------------------- --
--                              layout preview                             --
--  在 CellQuickAssistFrame 上叠加的布局预览层
--  创建最多40个可拖拽的方块来展示按钮在团队框架中的排列效果
--  拖拽方块可移动整个 QuickAssist 框架的位置
-- ----------------------------------------------------------------------- --
local layoutPreviewFrame
local layoutPreviewButtons = {}

local function UpdateLayoutPreview()
    -- 创建/更新布局预览框架，展示按钮在团队框架中的排列方式
    -- 根据锚点、排列方向、单位数、列数等参数计算每个预览方块的位置
    -- 预览方块支持拖拽以调整整个 QuickAssist 框架的位置
    if not layoutPreviewFrame then
        layoutPreviewFrame = CreateFrame("Frame", "CellQuickAssistPreviewFrame", CellQuickAssistFrame)
        layoutPreviewFrame:SetAllPoints(CellQuickAssistFrame)
        layoutPreviewFrame:SetFrameLevel(1)
        layoutPreviewFrame:Hide()

        A.CreateFadeIn(layoutPreviewFrame, 0, 1, 0.5)
        A.CreateFadeOut(layoutPreviewFrame, 1, 0, 0.5)

        for i = 1, 40 do
            layoutPreviewButtons[i] = CreateFrame("Frame", nil, layoutPreviewFrame, "BackdropTemplate")
            layoutPreviewButtons[i]:SetBackdrop({bgFile=Cell.vars.whiteTexture, edgeFile=Cell.vars.whiteTexture, edgeSize=P.Scale(1)})
            layoutPreviewButtons[i]:SetBackdropColor(0, 0, 0, 0.5)
            layoutPreviewButtons[i]:SetBackdropBorderColor(0, 0, 0, 1)
            layoutPreviewButtons[i]:EnableMouse(true)
            layoutPreviewButtons[i].text = layoutPreviewButtons[i]:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
            layoutPreviewButtons[i].text:SetPoint("CENTER")
            layoutPreviewButtons[i].text:SetText(i)
            -- drag
            layoutPreviewButtons[i]:RegisterForDrag("LeftButton")
            layoutPreviewButtons[i]:SetScript("OnDragStart", function()
                CellQuickAssistAnchorFrame:StartMoving()
                CellQuickAssistAnchorFrame:SetUserPlaced(false)
            end)

            layoutPreviewButtons[i]:SetScript("OnDragStop", function()
                CellQuickAssistAnchorFrame:StopMovingOrSizing()
                P.SavePosition(CellQuickAssistAnchorFrame, layoutTable["position"])
            end)
        end
    end

    local point, relativePoint, groupRelativePoint, unitSpacing, groupSpacing
    local spacing, x, y = layoutTable["spacingX"], layoutTable["spacingY"]

    -- 根据排列方向和锚点计算每个预览方块的锚点、相对锚点和间距方向
    if layoutTable["orientation"] == "horizontal" then
        if layoutTable["anchor"] == "BOTTOMLEFT" then
            point, relativePoint, groupRelativePoint = "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT"
            unitSpacing = layoutTable["spacingX"]
            groupSpacing = layoutTable["spacingY"]
        elseif layoutTable["anchor"] == "BOTTOMRIGHT" then
            point, relativePoint, groupRelativePoint = "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT"
            unitSpacing = -layoutTable["spacingX"]
            groupSpacing = layoutTable["spacingY"]
        elseif layoutTable["anchor"] == "TOPLEFT" then
            point, relativePoint, groupRelativePoint = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT"
            unitSpacing = layoutTable["spacingX"]
            groupSpacing = -layoutTable["spacingY"]
        elseif layoutTable["anchor"] == "TOPRIGHT" then
            point, relativePoint, groupRelativePoint = "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT"
            unitSpacing = -layoutTable["spacingX"]
            groupSpacing = -layoutTable["spacingY"]
        end
    else
        if layoutTable["anchor"] == "BOTTOMLEFT" then
            point, relativePoint, groupRelativePoint = "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT"
            unitSpacing = layoutTable["spacingY"]
            groupSpacing = layoutTable["spacingX"]
        elseif layoutTable["anchor"] == "BOTTOMRIGHT" then
            point, relativePoint, groupRelativePoint = "BOTTOMRIGHT", "TOPRIGHT", "BOTTOMLEFT"
            unitSpacing = layoutTable["spacingY"]
            groupSpacing = -layoutTable["spacingX"]
        elseif layoutTable["anchor"] == "TOPLEFT" then
            point, relativePoint, groupRelativePoint = "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT"
            unitSpacing = -layoutTable["spacingY"]
            groupSpacing = layoutTable["spacingX"]
        elseif layoutTable["anchor"] == "TOPRIGHT" then
            point, relativePoint, groupRelativePoint = "TOPRIGHT", "BOTTOMRIGHT", "TOPLEFT"
            unitSpacing = -layoutTable["spacingY"]
            groupSpacing = -layoutTable["spacingX"]
        end
    end

    -- 按最大列数和每列单位数循环排列预览方块
    local n = 1
    local first

    for i = 1, layoutTable["maxColumns"] do

        local last
        for j = 1, layoutTable["unitsPerColumn"] do
            local b = layoutPreviewButtons[n]
            b:Show()
            b:ClearAllPoints()
            P.Size(b, layoutTable["size"][1], layoutTable["size"][2])

            if last then -- not the first in this row/column
                if layoutTable["orientation"] == "horizontal" then
                    b:SetPoint(point, last, relativePoint, unitSpacing, 0)
                else
                    b:SetPoint(point, last, relativePoint, 0, unitSpacing)
                end
            elseif first then -- not the first row/column
                if layoutTable["orientation"] == "horizontal" then
                    b:SetPoint(point, first, groupRelativePoint, 0, groupSpacing)
                else
                    b:SetPoint(point, first, groupRelativePoint, groupSpacing, 0)
                end
            else -- first row/column
                b:SetPoint(point)
            end
            last = b

            n = n + 1
            if n > 40 then
                break
            end
        end

        if n > 40 then
            break
        else
            first = layoutPreviewButtons[n-layoutTable["unitsPerColumn"]]
        end
    end

    -- hide
    for i = n, 40 do
        layoutPreviewButtons[i]:Hide()
    end
end

local function ShowLayoutPreview()
    -- 显示布局预览（带淡入动画），当 layout 标签页激活时调用
    if not layoutTable then return end
    if not layoutPreviewFrame then
        UpdateLayoutPreview()
    end
    layoutPreviewFrame:FadeIn()
end

local function HideLayoutPreview()
    -- 隐藏布局预览（带淡出动画），当离开 layout 标签页时调用
    if not layoutPreviewFrame then return end
    layoutPreviewFrame:FadeOut()
end

-- ----------------------------------------------------------------------- --
--                               all widgets                               --
-- ----------------------------------------------------------------------- --
local qaPane, qaPopup, qaDualPopup
local qaEnabledCB
local layoutBtn, styleBtn, spellBtn

-- layout
local anchorDropdown, orientationDropdown, widthSlider, heightSlider, xSlider, ySlider, unitsSlider, maxSlider
local filterTypeDropdown, hideSelfCB, roleFilter, classFilter, specFilter, nameFilter, nameListFrame, filterResetBtn, filterResetTips
local filterButtons = {}
local autoSwitchFrame, partyDropdown, raidDropdown, mythicDropdown, arenaDropdown, bgDropdown, partyText, raidText, mythicText, arenaText, bgText

-- style
local hpColorDropdown, hpCP, lossColorDropdown, bgCP, textureDropdown, alphaSlider
local targetColorPicker, mouseoverColorPicker, highlightSizeSlider
local nameColorDropdown, nameCP, nameWidth, nameAnchorDropdown, nameXSlider, nameYSlider, nameFontDropdown, nameOutlineDropdown, nameSizeSilder, nameShadowCB

-- spells
local myBuffWidgets = {}
local classButtons, buffButtons, castButtons = {}, {}, {}

local buffsPane, buffsAddBtn, castsPane, castsAddBtn, offensivesEnabledCB

local function UpdateWidgets(enabled)
    -- 根据 QuickAssist 启用状态，统一启用/禁用所有配置控件
    -- 当禁用时切换到 layout 标签页，并隐藏所有弹出面板
    Cell.SetEnabled(enabled, layoutBtn, styleBtn, spellBtn)

    -- NOTE: switch to layout on disable
    Cell.SetEnabled(enabled, anchorDropdown, orientationDropdown, widthSlider, heightSlider, xSlider, ySlider, unitsSlider, maxSlider)
    Cell.SetEnabled(enabled, autoSwitchFrame, filterTypeDropdown, hideSelfCB, roleFilter, classFilter, nameFilter)

    for _, b in pairs(filterButtons) do
        Cell.SetEnabled(enabled, b)
    end

    qaPopup:Hide()
    qaPopup:Hide()
    nameListFrame:Hide()
    filterResetBtn:Hide()
    filterResetTips:Hide()
end

-- ----------------------------------------------------------------------- --
--                            quick assist pane                            --
-- ----------------------------------------------------------------------- --
local function CreateQuickAssistPane()
    -- 创建 QuickAssist 主配置面板，包含：
    -- - 启用/禁用复选框
    -- - 导入/导出按钮
    -- - 法术ID输入弹窗(qaPopup)：输入ID时实时预览法术信息
    -- - 双输入弹窗(qaDualPopup)：同时输入法术ID和持续时间
    qaPane = Cell.CreateTitledPane(quickAssistTab, L["Quick Assist"].." |cFF777777"..L["only in group"], 422, 80)
    qaPane:SetPoint("TOPLEFT", 5, -5)

    local qaTips = qaPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    qaTips:SetPoint("TOPLEFT", 5, -25)
    qaTips:SetJustifyH("LEFT")
    qaTips:SetSpacing(5)
    qaTips:SetText(L["Create several buttons for quick casting and buff monitoring"].."\n"..L["These settings are spec-specific"])

    -- enabled ----------------------------------------------------------------------
    qaEnabledCB = Cell.CreateCheckButton(qaPane, L["Enabled"], function(checked, self)
        -- QuickAssist 启用/禁用回调：
        -- 1. 首次启用时为当前专精创建配置表
        -- 2. 更新数据库、预览和整体状态
        -- 3. 启用时显示布局预览，禁用时隐藏并切换到 layout 标签页
        if not CellDB["quickAssist"][Cell.vars.playerSpecID] then
            CellDB["quickAssist"][Cell.vars.playerSpecID] = F.Copy(defaultQuickAssistTable)
        end

        CellDB["quickAssist"][Cell.vars.playerSpecID]["enabled"] = checked
        LoadDB()
        UpdatePreviewButton()

        if checked then
            ShowLayoutPreview()
        else
            HideLayoutPreview()
            layoutBtn:GetScript("OnClick")()
        end

        Cell.Fire("UpdateQuickAssist")
    end)
    qaEnabledCB:SetPoint("TOPLEFT", qaPane, 5, -75)

    -- import/export --------------------------------------------------------- --
    local export = Cell.CreateButton(qaPane, nil, "accent-hover", {27, 17}, nil, nil, nil, nil, nil, L["Export"])
    export:SetPoint("TOPRIGHT")
    export:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\export", {15, 15}, {"CENTER", 0, 0})
    export:SetScript("OnClick", function()
        -- 导出：将当前 QuickAssist 配置序列化为可分享的字符串
        F.ShowQuickAssistExportFrame(quickAssistTable)
    end)

    local import = Cell.CreateButton(qaPane, nil, "accent-hover", {27, 17}, nil, nil, nil, nil, nil, L["Import"])
    import:SetPoint("TOPRIGHT", export, "TOPLEFT", -1, 0)
    import:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\import", {15, 15}, {"CENTER", 0, 0})
    import:SetScript("OnClick", function()
        -- 导入：打开导入弹窗，粘贴导出的配置字符串来加载 QuickAssist 设置
        F.ShowQuickAssistImportFrame()
    end)

    -- popup ------------------------------------------------------------------------
    qaPopup = Cell.CreatePopupEditBox(qaPane)
    qaPopup:SetNumeric(true)
    qaPopup:SetFrameStrata("DIALOG")

    qaPopup:SetScript("OnTextChanged", function()
        local spellId = tonumber(qaPopup:GetText())
        if not spellId then
            CellSpellTooltip:Hide()
            return
        end

        local name, icon = F.GetSpellInfo(spellId)
        if not name then
            CellSpellTooltip:Hide()
            return
        end

        CellSpellTooltip:SetOwner(qaPopup, "ANCHOR_NONE")
        CellSpellTooltip:SetPoint("TOPLEFT", qaPopup, "BOTTOMLEFT", 0, -1)
        CellSpellTooltip:SetSpellByID(spellId, icon)
        CellSpellTooltip:Show()
    end)

    qaPopup:HookScript("OnHide", function()
        CellSpellTooltip:Hide()
    end)

    -- dualPopup --------------------------------------------------------------------
    qaDualPopup = Cell.CreateDualPopupEditBox(qaPane, "ID", L["Duration"], true)
    qaDualPopup.left:HookScript("OnTextChanged", function(self)
        local spellId = tonumber(self:GetText())
        if not spellId then
            CellSpellTooltip:Hide()
            return
        end

        local name, icon = F.GetSpellInfo(spellId)
        if not name then
            CellSpellTooltip:Hide()
            return
        end

        CellSpellTooltip:SetOwner(self, "ANCHOR_NONE")
        CellSpellTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -1)
        CellSpellTooltip:SetSpellByID(spellId, icon)
        CellSpellTooltip:Show()
    end)

    qaDualPopup:HookScript("OnHide", function()
        CellSpellTooltip:Hide()
    end)
end

-- ----------------------------------------------------------------------- --
--                                  setup                                  --
-- ----------------------------------------------------------------------- --
local setupPane
local pages = {}
local function CreateSetupPane()
    -- 创建设置面板，包含 Layout / Style / Spells 三个标签页切换按钮
    -- 使用 ButtonGroup 实现互斥切换，切换时显示/隐藏对应页面
    setupPane = Cell.CreateTitledPane(quickAssistTab, L["Setup"], 422, 384)
    setupPane:SetPoint("TOPLEFT", P.Scale(5), P.Scale(-120))

    spellBtn = Cell.CreateButton(setupPane, L["Spells"], "accent-hover", {100, 17})
    spellBtn:SetPoint("TOPRIGHT")
    spellBtn.id = "spell"

    styleBtn = Cell.CreateButton(setupPane, L["Style"], "accent-hover", {100, 17})
    styleBtn:SetPoint("TOPRIGHT", spellBtn, "TOPLEFT", P.Scale(1), 0)
    styleBtn.id = "style"

    layoutBtn = Cell.CreateButton(setupPane, L["Layout"], "accent-hover", {100, 17})
    layoutBtn:SetPoint("TOPRIGHT", styleBtn, "TOPLEFT", P.Scale(1), 0)
    layoutBtn.id = "layout"

    Cell.CreateButtonGroup({layoutBtn, styleBtn, spellBtn}, function(tab)
        -- 标签页切换：显示对应页面，隐藏其他页面
        -- spell 标签页激活时启用指示器预览动画
        -- show & hide
        for name, page in pairs(pages) do
            if name == tab then
                page:Show()
            else
                page:Hide()
            end
        end

        if previewButton then
            showIndicatorPreview = tab == "spell"
            previewButton.elapsed = 13
        end
    end)
end

-- ----------------------------------------------------------------------- --
--                                  layout                                 --
-- ----------------------------------------------------------------------- --

-- role filter ----------------------------------------------------------- --
local function UpdateRoleFilter(role)
    -- 切换指定职责（TANK/HEALER/DAMAGER）的过滤状态
    -- 如果当前筛选器是活跃的，立即触发 UpdateQuickAssist 事件更新按钮显示
    quickAssistTable["filters"][selectedFilter][2][role] = not quickAssistTable["filters"][selectedFilter][2][role]
    ShowFilter(selectedFilter) -- call SetRoles
    if selectedFilter == activeFilter then
        Cell.Fire("UpdateQuickAssist", "filter")
    end
end

local ROLE_FILTER_SIZE = 100
local function CreateRoleFilter(parent)
    -- 创建职责过滤控件（TANK / HEALER / DAMAGER 三选按钮）
    -- 选中状态显示彩色图标，未选中显示灰色
    -- 包含 SetRoles(t) 方法用于更新按钮显示状态
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(P.Scale(ROLE_FILTER_SIZE)*3-P.Scale(1)*2, P.Scale(20))
    f:Hide()

    local tank = Cell.CreateButton(f, _G.TANK, "blue-hover", {ROLE_FILTER_SIZE, 20})
    tank:SetTexture(F.GetDefaultRoleIcon("TANK"), {16, 16}, {"LEFT", 2, 0})
    tank:SetPoint("TOPLEFT")
    tank:SetScript("OnClick", function() UpdateRoleFilter("TANK") end)

    local healer = Cell.CreateButton(f, _G.HEALER, "green-hover", {ROLE_FILTER_SIZE, 20})
    healer:SetTexture(F.GetDefaultRoleIcon("HEALER"), {16, 16}, {"LEFT", 2, 0})
    healer:SetPoint("TOPLEFT", tank, "TOPRIGHT", P.Scale(-1), 0)
    healer:SetScript("OnClick", function() UpdateRoleFilter("HEALER") end)

    local damager = Cell.CreateButton(f, _G.DAMAGER, "red-hover", {ROLE_FILTER_SIZE, 20})
    damager:SetTexture(F.GetDefaultRoleIcon("DAMAGER"), {16, 16}, {"LEFT", 2, 0})
    damager:SetPoint("TOPLEFT", healer, "TOPRIGHT", P.Scale(-1), 0)
    damager:SetScript("OnClick", function() UpdateRoleFilter("DAMAGER") end)

    function f:SetRoles(t)
        tank.tex:SetAlpha(t.TANK and 1 or 0.4)
        tank.tex:SetDesaturated(not t.TANK)
        if t.TANK then
            tank:SetTextColor(1, 1, 1)
        else
            tank:SetTextColor(0.4, 0.4, 0.4)
        end

        healer.tex:SetAlpha(t.HEALER and 1 or 0.4)
        healer.tex:SetDesaturated(not t.HEALER)
        if t.HEALER then
            healer:SetTextColor(1, 1, 1)
        else
            healer:SetTextColor(0.4, 0.4, 0.4)
        end

        damager.tex:SetAlpha(t.DAMAGER and 1 or 0.4)
        damager.tex:SetDesaturated(not t.DAMAGER)
        if t.DAMAGER then
            damager:SetTextColor(1, 1, 1)
        else
            damager:SetTextColor(0.4, 0.4, 0.4)
        end
    end

    return f
end

-- class filter ---------------------------------------------------------- --
local CLASS_FILTER_SIZE = 24
local function CreateClassFilter(parent)
    -- 创建职业过滤控件（13个职业图标按钮）
    -- 点击切换启用/禁用，拖拽可改变职业排序顺序
    -- 包含 SetClasses(t) 方法用于更新按钮的启用状态和排列位置
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(412, P.Scale(CLASS_FILTER_SIZE))
    f:Hide()

    local buttons = {}
    -- local last
    for class in F.IterateClasses() do
        buttons[class] = Cell.CreateButton(f, nil, "accent-hover", {CLASS_FILTER_SIZE, CLASS_FILTER_SIZE})
        buttons[class]:SetTexture("classicon-"..strlower(class), {CLASS_FILTER_SIZE-4, CLASS_FILTER_SIZE-4}, {"CENTER", 0, 0}, true, true)
        buttons[class]._class = class

        buttons[class]:SetScript("OnClick", function()
            -- 点击职业按钮：切换该职业过滤器的启用/禁用状态
            -- find class
            for i, t in pairs(quickAssistTable["filters"][selectedFilter][2]) do
                if t[1] == class then
                    t[2] = not t[2]
                    break
                end
            end
            f:SetClasses(quickAssistTable["filters"][selectedFilter][2])
            if selectedFilter == activeFilter then
                Cell.Fire("UpdateQuickAssist", "filter")
            end
        end)

        buttons[class]:SetScript("OnEnter", function(self) self:SetBackdropColor(F.GetClassColor(class)) end)

        buttons[class]:SetMovable(true)
        buttons[class]:RegisterForDrag("LeftButton")

        buttons[class]:SetScript("OnDragStart", function(self)
            self:SetFrameStrata("TOOLTIP")
            self:StartMoving()
            self:SetUserPlaced(false)
        end)

        buttons[class]:SetScript("OnDragStop", function(self)
            -- 拖拽结束：检测鼠标下的职业按钮，交换两个职业的排序位置
            self:StopMovingOrSizing()
            self:SetFrameStrata("LOW")
            -- self:Hide() --! Hide() will cause OnDragStop trigger TWICE!!!
            C_Timer.After(0.05, function()
                local b = F.GetMouseFocus()
                if b ~= self and b and b._class then
                    local oldIndex, oldValue, newIndex
                    for i, t in pairs(quickAssistTable["filters"][selectedFilter][2]) do
                        if class == t[1] then
                            oldValue = t
                            oldIndex = i
                        elseif b._class == t[1] then
                            newIndex = i
                        end
                    end
                    -- print(class, oldIndex, "->", b._class, newIndex)

                    if oldIndex and oldValue and newIndex then
                        tremove(quickAssistTable["filters"][selectedFilter][2], oldIndex)
                        tinsert(quickAssistTable["filters"][selectedFilter][2], newIndex, oldValue)
                        if selectedFilter == activeFilter then
                            Cell.Fire("UpdateQuickAssist", "filter")
                        end
                    end
                end
                f:SetClasses(quickAssistTable["filters"][selectedFilter][2])
            end)
        end)
    end

    function f:SetClasses(t)
        -- 根据配置表更新职业按钮的显示状态和排列顺序
        for k, v in pairs(t) do
            local class, enabled = v[1], v[2]
            -- state
            if enabled then
                buttons[class]:SetBackdropBorderColor(F.GetClassColor(class))
                buttons[class].tex:SetDesaturated(false)
                buttons[class]:SetAlpha(1)
            else
                buttons[class]:SetBackdropBorderColor(0, 0, 0)
                buttons[class].tex:SetDesaturated(true)
                buttons[class]:SetAlpha(0.75)
            end

            -- order
            buttons[class]:SetFrameStrata("DIALOG")
            buttons[class]:ClearAllPoints()
            buttons[class]:SetPoint("TOPLEFT", (k-1)*(P.Scale(CLASS_FILTER_SIZE)+P.Scale(3)), 0)
            buttons[class]:Show()
        end
    end

    return f
end

-- name filter ----------------------------------------------------------- --
local players = {}
local names = {}

-- update button
local function UpdatePlayerList()
    -- 更新玩家名册列表的显示：已在过滤名单中的玩家降低透明度并显示序号
    for _, b in pairs(players) do
        if not b:IsShown() then break end

        b.label:SetAlpha(1)
        b.index:SetText("")

        for k, n in pairs(names) do
            if n == b.name then
                b.label:SetAlpha(0.3)
                b.index:SetText(k)
                break
            end
        end
    end
end

local function CreatePlayerList(parent, box)
    -- 创建玩家名册列表（名字过滤器辅助控件）
    -- 显示当前队伍/团队中的所有玩家，点击切换是否纳入名字过滤名单
    -- playerlist
    local playerListFrame = CreateFrame("Frame", nil, parent)
    playerListFrame:SetSize(70, 17)
    playerListFrame:SetPoint("TOPLEFT", parent, "TOPRIGHT", 5, 0)

    for i = 1, 40 do
        players[i] = Cell.CreateButton(playerListFrame, i, nil, {90, 18})
        players[i].label = players[i]:GetFontString()
        players[i].label:ClearAllPoints()
        players[i].label:SetPoint("LEFT", P.Scale(13), 0)

        players[i].index = players[i]:CreateFontString(nil, "OVERLAY")
        players[i].index:SetFont("Interface\\AddOns\\Cell\\Media\\Fonts\\Accidental_Presidency.ttf", 12)
        players[i].index:SetShadowColor(0, 0, 0)
        players[i].index:SetShadowOffset(1, -1)
        players[i].index:SetPoint("LEFT", P.Scale(1), 0)

        if i == 1 then
            players[i]:SetPoint("TOPLEFT")
        elseif i % 20 == 1 then
            players[i]:SetPoint("TOPLEFT", players[i-20], "TOPRIGHT", P.Scale(-1), 0)
        else
            players[i]:SetPoint("TOPLEFT", players[i-1], "BOTTOMLEFT", 0, P.Scale(1))
        end

        players[i]:SetScript("OnClick", function(self)
            local found
            for k, n in pairs(names) do
                if n == self.name then
                    found = k
                    break
                end
            end
            if found then
                tremove(names, found)
            else
                tinsert(names, self.name)
            end

            box:SetText(table.concat(names, "\n"))
            UpdatePlayerList()
        end)
    end

    playerListFrame:SetScript("OnShow", function()
        -- 显示时刷新：加载当前过滤名单，遍历队伍成员填充玩家列表
        names = F.Copy(quickAssistTable["filters"][selectedFilter][2])

        local i = 1
        for unit in F.IterateGroupMembers() do
            players[i]:Show()

            local name = GetUnitName(unit, true)
            local class = UnitClassBase(unit)

            players[i].name = name

            F.UpdateTextWidth(players[i].label, name, {"percentage", 0.8}, players[i])
            players[i].label:SetTextColor(F.GetClassColor(class))

            i = i + 1
        end

        for j = i, 40 do
            players[j]:Hide()
        end

        UpdatePlayerList()
    end)
end

local function CreateNameFilter(parent)
    -- 创建名字过滤器控件
    -- 点击按钮弹出名册面板，支持手动输入名字或从队伍列表中点击选择
    -- 包含保存/放弃按钮，支持多行文本输入（每行一个名字）
    local b = Cell.CreateButton(parent, L["Name List"], "accent-hover", {200, 20})
    b.frameLevel = b:GetFrameLevel()
    b:Hide()

    nameListFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Cell.StylizeFrame(nameListFrame, nil, Cell.GetAccentColorTable())
    nameListFrame:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 5)
    nameListFrame:SetFrameLevel(parent:GetFrameLevel()+50)
    nameListFrame:SetSize(200, 280)
    nameListFrame:Hide()

    local box = Cell.CreateScrollEditBox(nameListFrame)
    box:SetPoint("TOPLEFT", 5, -5)
    box:SetPoint("BOTTOMRIGHT", -5, 30)

    box.eb:SetScript("OnTextChanged", function(self, userChanged)
        -- 用户手动编辑名字列表时，解析每行名字并更新名册高亮状态
        if not userChanged then return end
        names = {strsplit("\n", box:GetText())}
        UpdatePlayerList()
    end)

    nameListFrame:SetScript("OnShow", function()
        b:SetFrameLevel(parent:GetFrameLevel()+50)
        Cell.CreateMask(Cell.frames.utilitiesTab, nil, {1, -1, -1, 1})
        box:SetText(table.concat(quickAssistTable["filters"][selectedFilter][2], "\n"))
    end)

    nameListFrame:SetScript("OnHide", function()
        b:SetFrameLevel(b.frameLevel)
        nameListFrame:Hide()
        Cell.frames.utilitiesTab.mask:Hide()
    end)

    CreatePlayerList(nameListFrame, box)

    local saveBtn = Cell.CreateButton(nameListFrame, L["Save"], "green", {93, 20})
    saveBtn:SetPoint("BOTTOMLEFT", 5, 5)
    saveBtn:SetScript("OnClick", function()
        for i = #names, 1, -1 do
            names[i] = strtrim(names[i])
            if names[i] == "" then
                tremove(names, i)
            end
        end
        quickAssistTable["filters"][selectedFilter][2] = F.Copy(names)
        nameListFrame:Hide()
        if selectedFilter == activeFilter then
            Cell.Fire("UpdateQuickAssist", "filter")
        end
    end)

    local discardBtn = Cell.CreateButton(nameListFrame, L["Discard"], "red", {92, 20})
    discardBtn:SetPoint("BOTTOMRIGHT", -5, 5)
    discardBtn:SetScript("OnClick", function()
        nameListFrame:Hide()
    end)

    b:SetScript("OnClick", function()
        if nameListFrame:IsShown() then
            nameListFrame:Hide()
        else
            nameListFrame:Show()
        end
    end)

    return b
end

-- spec filter ----------------------------------------------------------- --
local SPEC_FILTER_SIZE = 24
local function CreateSpecFilter(parent)
    -- 创建专精过滤控件（按职业分组显示专精图标按钮）
    -- 点击切换启用/禁用，拖拽可改变职业排序
    -- 包含 SetSpecs(t) 方法用于更新所有专精按钮的启用状态和职业排列位置
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(412, P.Scale(SPEC_FILTER_SIZE)*4)
    f:Hide()

    local frames = {}
    local buttons = {}

    for _, ct in pairs(defaultSpecFilter) do
        local class = ct[1]

        -- class frame
        frames[class] = CreateFrame("Frame", nil, f)
        frames[class]:SetSize(P.Scale(SPEC_FILTER_SIZE), P.Scale(SPEC_FILTER_SIZE)*#ct[2]+P.Scale(1)*(#ct[2]-1))
        frames[class]._class = class

        frames[class]:SetMovable(true)

        frames[class].onDragStart = function()
            frames[class]:SetFrameStrata("TOOLTIP")
            frames[class]:StartMoving()
            frames[class]:SetUserPlaced(false)
        end

        frames[class].onDragStop = function(self)
            -- 拖拽结束：检测鼠标下的职业分组，交换两个职业在专精过滤列表中的排序位置
            frames[class]:StopMovingOrSizing()
            frames[class]:SetFrameStrata("LOW")
            -- self:Hide() --! Hide() will cause OnDragStop trigger TWICE!!!
            C_Timer.After(0.05, function()
                local mf = F.GetMouseFocus()
                if mf then mf = mf:GetParent() end
                if mf ~= self and mf and mf._class then
                    local oldIndex, oldValue, newIndex
                    for i, t in pairs(quickAssistTable["filters"][selectedFilter][2]) do
                        if class == t[1] then
                            oldValue = t
                            oldIndex = i
                        elseif mf._class == t[1] then
                            newIndex = i
                        end
                    end
                    -- print(class, oldIndex, "->", mf._class, newIndex)

                    if oldIndex and oldValue and newIndex then
                        tremove(quickAssistTable["filters"][selectedFilter][2], oldIndex)
                        tinsert(quickAssistTable["filters"][selectedFilter][2], newIndex, oldValue)
                        if selectedFilter == activeFilter then
                            Cell.Fire("UpdateQuickAssist", "filter")
                        end
                    end
                end
                f:SetSpecs(quickAssistTable["filters"][selectedFilter][2])
            end)
        end

        -- spec buttons
        local last
        for _, st in pairs(ct[2]) do
            local spec = st[1]
            buttons[spec] = Cell.CreateButton(frames[class], nil, "accent-hover", {SPEC_FILTER_SIZE, SPEC_FILTER_SIZE})
            buttons[spec]:SetTexture(specIcons[spec], {SPEC_FILTER_SIZE-4, SPEC_FILTER_SIZE-4}, {"CENTER", 0, 0}, false, true)
            buttons[spec].tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)

            buttons[spec]:SetScript("OnClick", function()
                -- 点击专精按钮：切换该专精过滤器的启用/禁用状态
                -- find spec
                for _, t in pairs(quickAssistTable["filters"][selectedFilter][2]) do
                    if t[1] == class then
                        for _, _t in pairs(t[2]) do
                            if _t[1] == spec then
                                _t[2] = not _t[2]
                                break
                            end
                        end
                        break
                    end
                end
                f:SetSpecs(quickAssistTable["filters"][selectedFilter][2])
                if selectedFilter == activeFilter then
                    Cell.Fire("UpdateQuickAssist", "filter")
                end
            end)

            buttons[spec]:SetScript("OnEnter", function(self) self:SetBackdropColor(F.GetClassColor(class)) end)

            buttons[spec]:RegisterForDrag("LeftButton")
            buttons[spec]:SetScript("OnDragStart", frames[class].onDragStart)
            buttons[spec]:SetScript("OnDragStop", frames[class].onDragStop)


            if last then
                buttons[spec]:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, P.Scale(-1))
            else
                buttons[spec]:SetPoint("TOPLEFT")
            end
            last = buttons[spec]
        end
    end

    function f:SetSpecs(t)
        -- 根据配置表更新专精按钮的职业排列顺序和各专精的启用/禁用状态
        for k, ct in pairs(t) do
            local class = ct[1]
            -- class order
            frames[class]:SetFrameStrata("DIALOG")
            frames[class]:ClearAllPoints()
            frames[class]:SetPoint("TOPLEFT", (k-1)*(P.Scale(SPEC_FILTER_SIZE)+P.Scale(3)), 0)
            frames[class]:Show()

            -- spec state
            for _, st in pairs(ct[2]) do
                local spec, enabled = unpack(st)
                if enabled then -- enabled
                    buttons[spec]:SetBackdropBorderColor(F.GetClassColor(class))
                    buttons[spec].tex:SetDesaturated(false)
                    buttons[spec]:SetAlpha(1)
                else
                    buttons[spec]:SetBackdropBorderColor(0, 0, 0)
                    buttons[spec].tex:SetDesaturated(true)
                    buttons[spec]:SetAlpha(0.75)
                end
            end
        end
    end

    return f
end


-- class order ----------------------------------------------------------- --
--[[
local ORDER_ICON_SIZE = 24
local function CreateClassOrderWidget(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", P.Scale(5), P.Scale(-27))
    P.Size(f, 412, ORDER_ICON_SIZE)

    local buttons = {}
    for class in F.IterateClasses() do
        buttons[class] = Cell.CreateButton(f, nil, "accent-hover", {ORDER_ICON_SIZE, ORDER_ICON_SIZE})
        buttons[class]:SetTexture("classicon-"..strlower(class), {ORDER_ICON_SIZE-4, ORDER_ICON_SIZE-4}, {"CENTER", 0, 0}, true, true)
        buttons[class]._class = class

        buttons[class]:SetMovable(true)
        buttons[class]:RegisterForDrag("LeftButton")

        buttons[class]:SetScript("OnDragStart", function(self)
            self:SetFrameStrata("TOOLTIP")
            self:StartMoving()
            self:SetUserPlaced(false)
        end)

        buttons[class]:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self:SetFrameStrata("LOW")
            -- self:Hide() --! Hide() will cause OnDragStop trigger TWICE!!!
            C_Timer.After(0.05, function()
                local b = F.GetMouseFocus()
                if b and b._class then
                    local classToIndex = F.ConvertTable(layoutTable["order"])
                    -- print(self._class, "->", b._class)

                    local oldIndex = classToIndex[self._class]
                    tremove(layoutTable["order"], oldIndex)

                    local newIndex = classToIndex[b._class]
                    tinsert(layoutTable["order"], newIndex, self._class)

                    Cell.Fire("UpdateQuickAssist", "order")
                end
                f:Load(layoutTable["order"])
            end)
        end)
    end

    function f:Load(t)
        for i, class in pairs(t) do
            buttons[class]:SetFrameStrata("DIALOG")
            buttons[class]:Show()
            buttons[class]:ClearAllPoints()
            buttons[class]:SetPoint("TOPLEFT", (i-1)*(P.Scale(ORDER_ICON_SIZE)+P.Scale(3)), 0)
        end
    end

    return f
end
]]

local HighlightFilter
-- 罗马数字标签，用于7个过滤器按钮的显示
local romanNumerals = {"I", "II", "III", "IV", "V", "VI", "VII"}

local function CreateLayoutPane()
    -- 创建布局配置页面，包含：
    -- - 锚点/排列方向下拉框
    -- - 宽度/高度/间距(X/Y)滑块
    -- - 每列单位数/最大列数滑块
    -- - 单位过滤器（类型下拉框、7个过滤器按钮、职责/职业/专精/名字过滤控件）
    -- 页面显示/隐藏时自动显示/隐藏布局预览
    pages.layout = CreateFrame("Frame", nil, quickAssistTab)
    pages.layout:SetAllPoints(setupPane)
    pages.layout:Hide()

    pages.layout:SetScript("OnShow", ShowLayoutPreview)
    pages.layout:SetScript("OnHide", HideLayoutPreview)

    anchorDropdown = Cell.CreateDropdown(pages.layout, 117)
    anchorDropdown:SetPoint("TOPLEFT", 5, -42)
    anchorDropdown:SetLabel(L["Anchor Point"])

    local points = {"BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT", "TOPRIGHT"}
    local items = {}
    for _, p in pairs(points) do
        tinsert(items, {
            ["text"] = L[p],
            ["value"] = p,
            ["onClick"] = function()
                layoutTable["anchor"] = p
                Cell.Fire("UpdateQuickAssist", "layout")
                UpdateLayoutPreview()
            end
        })
    end
    anchorDropdown:SetItems(items)

    orientationDropdown = Cell.CreateDropdown(pages.layout, 117)
    orientationDropdown:SetPoint("TOPLEFT", anchorDropdown, "TOPRIGHT", 30, 0)
    orientationDropdown:SetLabel(L["Orientation"])
    orientationDropdown:SetItems({
        {
            ["text"] = L["Horizontal"],
            ["value"] = "horizontal",
            ["onClick"] = function()
                layoutTable["orientation"] = "horizontal"
                unitsSlider:SetLabel(L["Units Per Row"])
                maxSlider:SetLabel(L["Max Rows"])
                Cell.Fire("UpdateQuickAssist", "layout")
                UpdateLayoutPreview()
            end,
        },
        {
            ["text"] = L["Vertical"],
            ["value"] = "vertical",
            ["onClick"] = function()
                layoutTable["orientation"] = "vertical"
                unitsSlider:SetLabel(L["Units Per Column"])
                maxSlider:SetLabel(L["Max Columns"])
                Cell.Fire("UpdateQuickAssist", "layout")
                UpdateLayoutPreview()
            end,
        },
    })

    widthSlider = Cell.CreateSlider(L["Width"], pages.layout, 20, 300, 117, 1)
    widthSlider:SetPoint("TOPLEFT", anchorDropdown, 0, -50)
    widthSlider.afterValueChangedFn = function(value)
        layoutTable["size"][1] = value
        Cell.Fire("UpdateQuickAssist", "layout")
        UpdateLayoutPreview()
    end

    heightSlider = Cell.CreateSlider(L["Height"], pages.layout, 20, 300, 117, 1)
    heightSlider:SetPoint("TOPLEFT", widthSlider, 0, -50)
    heightSlider.afterValueChangedFn = function(value)
        layoutTable["size"][2] = value
        Cell.Fire("UpdateQuickAssist", "layout")
        UpdateLayoutPreview()
    end

    xSlider = Cell.CreateSlider(L["Spacing"].." X", pages.layout, -1, 100, 117, 1)
    xSlider:SetPoint("TOPLEFT", orientationDropdown, 0, -50)
    xSlider.afterValueChangedFn = function(value)
        layoutTable["spacingX"] = value
        Cell.Fire("UpdateQuickAssist", "layout")
        UpdateLayoutPreview()
    end

    ySlider = Cell.CreateSlider(L["Spacing"].." Y", pages.layout, -1, 100, 117, 1)
    ySlider:SetPoint("TOPLEFT", xSlider, 0, -50)
    ySlider.afterValueChangedFn = function(value)
        layoutTable["spacingY"] = value
        Cell.Fire("UpdateQuickAssist", "layout")
        UpdateLayoutPreview()
    end

    unitsSlider = Cell.CreateSlider(L["Units Per Column"], pages.layout, 2, 20, 117, 1)
    unitsSlider:SetPoint("TOPLEFT", xSlider, "TOPRIGHT", 30, 0)
    unitsSlider.afterValueChangedFn = function(value)
        layoutTable["unitsPerColumn"] = value
        Cell.Fire("UpdateQuickAssist", "layout")
        UpdateLayoutPreview()
    end

    maxSlider = Cell.CreateSlider(L["Max Columns"], pages.layout, 1, 10, 117, 1)
    maxSlider:SetPoint("TOPLEFT", unitsSlider, 0, -50)
    maxSlider.afterValueChangedFn = function(value)
        layoutTable["maxColumns"] = value
        Cell.Fire("UpdateQuickAssist", "layout")
        UpdateLayoutPreview()
    end

    --* filter ---------------------------------------------------------------- --
    local filterPane = Cell.CreateTitledPane(pages.layout, L["Unit Filter"], 422, 175)
    filterPane:SetPoint("TOPLEFT", 0, -210)

    filterTypeDropdown = Cell.CreateDropdown(filterPane, 117)
    filterTypeDropdown:SetPoint("TOPLEFT", 5, -27)
    filterTypeDropdown:SetItems({
        {
            ["text"] = L["Role Filter"],
            ["value"] = "role",
            ["onClick"] = function()
                if quickAssistTable["filters"][selectedFilter][1] ~= "role" then
                    quickAssistTable["filters"][selectedFilter][1] = "role"
                    quickAssistTable["filters"][selectedFilter][2] = F.Copy(defaultRoleFilter)
                    ShowFilter(selectedFilter)
                    if selectedFilter == activeFilter then
                        Cell.Fire("UpdateQuickAssist", "filter")
                    end
                end
            end,
        },
        {
            ["text"] = L["Class Filter"],
            ["value"] = "class",
            ["onClick"] = function()
                if quickAssistTable["filters"][selectedFilter][1] ~= "class" then
                    quickAssistTable["filters"][selectedFilter][1] = "class"
                    quickAssistTable["filters"][selectedFilter][2] = F.Copy(defaultClassFilter)
                    ShowFilter(selectedFilter)
                    if selectedFilter == activeFilter then
                        Cell.Fire("UpdateQuickAssist", "filter")
                    end
                end
            end,
        },
        {
            ["text"] = L["Spec Filter"],
            ["value"] = "spec",
            ["onClick"] = function()
                if quickAssistTable["filters"][selectedFilter][1] ~= "spec" then
                    quickAssistTable["filters"][selectedFilter][1] = "spec"
                    quickAssistTable["filters"][selectedFilter][2] = F.Copy(defaultSpecFilter)
                    ShowFilter(selectedFilter)
                    if selectedFilter == activeFilter then
                        Cell.Fire("UpdateQuickAssist", "filter")
                    end
                end
            end,
        },
        {
            ["text"] = L["Name Filter"],
            ["value"] = "name",
            ["onClick"] = function()
                if quickAssistTable["filters"][selectedFilter][1] ~= "name" then
                    quickAssistTable["filters"][selectedFilter][1] = "name"
                    quickAssistTable["filters"][selectedFilter][2] = {}
                    quickAssistTable["filters"][selectedFilter][3] = false
                    ShowFilter(selectedFilter)
                    if selectedFilter == activeFilter then
                        Cell.Fire("UpdateQuickAssist", "filter")
                    end
                end
            end,
        },
    })

    hideSelfCB = Cell.CreateCheckButton(filterPane, L["Hide Self"].." ("..L["Party"]..")", function(checked, self)
        quickAssistTable["filters"][selectedFilter][3] = checked
        if selectedFilter == activeFilter then
            Cell.Fire("UpdateQuickAssist", "filter")
        end
    end)
    hideSelfCB:SetPoint("TOPLEFT", filterTypeDropdown, "TOPRIGHT", 30, -3)

    roleFilter = CreateRoleFilter(filterPane)
    roleFilter:SetPoint("TOPLEFT", filterTypeDropdown, "BOTTOMLEFT", 0, -10)

    classFilter = CreateClassFilter(filterPane)
    classFilter:SetPoint("TOPLEFT", filterTypeDropdown, "BOTTOMLEFT", 0, -10)

    specFilter = CreateSpecFilter(filterPane)
    specFilter:SetPoint("TOPLEFT", filterTypeDropdown, "BOTTOMLEFT", 0, -10)

    nameFilter = CreateNameFilter(filterPane)
    nameFilter:SetPoint("TOPLEFT", filterTypeDropdown, "BOTTOMLEFT", 0, -10)

    filterResetBtn = Cell.CreateButton(filterPane, L["Reset"], "accent", {50, 17})
    filterResetBtn:SetPoint("BOTTOMLEFT")
    filterResetBtn:SetScript("OnClick", function()
        -- 重置当前过滤器到默认值（仅对 class/spec 类型有效）
        if quickAssistTable["filters"][selectedFilter][1] == "class" then
            quickAssistTable["filters"][selectedFilter][2] = F.Copy(defaultClassFilter)
            classFilter:SetClasses(quickAssistTable["filters"][selectedFilter][2])
        elseif quickAssistTable["filters"][selectedFilter][1] == "spec" then
            quickAssistTable["filters"][selectedFilter][2] = F.Copy(defaultSpecFilter)
            specFilter:SetSpecs(quickAssistTable["filters"][selectedFilter][2])
        end

        if selectedFilter == activeFilter then
            Cell.Fire("UpdateQuickAssist", "filter")
        end
    end)

    filterResetTips = filterPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    filterResetTips:SetPoint("LEFT", filterResetBtn, "RIGHT", 5, 0)
    filterResetTips:SetText("|cffababab"..L["Left-Click"]..": "..L["toggle"]..", "..L["Left-Drag"]..": "..L["change the order"])

    for i = 7, 1, -1 do
        filterButtons[i] = Cell.CreateButton(filterPane, romanNumerals[i], "accent-hover", {37, 17})
        filterButtons[i].id = i

        if i == 7 then
            filterButtons[i]:SetPoint("TOPRIGHT")
        else
            filterButtons[i]:SetPoint("TOPRIGHT", filterButtons[i+1], "TOPLEFT", P.Scale(1), 0)
        end
    end

    HighlightFilter = Cell.CreateButtonGroup(filterButtons, function(id)
        -- 过滤器切换按钮组：点选 I-VII 切换到对应编号的过滤器
        selectedFilter = id
        ShowFilter(id)
    end)

    --* order ----------------------------------------------------------------- --
    -- local orderPane = Cell.CreateTitledPane(pages.layout, L["Class Order"], 422, 80)
    -- orderPane:SetPoint("TOPLEFT", 0, P.Scale(-330))

    -- classOrderWidget = CreateClassOrderWidget(orderPane)

    -- orderResetBtn = Cell.CreateButton(orderPane, L["Reset"], "accent", {50, 17})
    -- orderResetBtn:SetPoint("TOPRIGHT")
    -- orderResetBtn:SetScript("OnClick", function()
    --     layoutTable["order"] = F.GetSortedClasses()
    --     classOrderWidget:Load(layoutTable["order"])
    --     Cell.Fire("UpdateQuickAssist", "order")
    -- end)
end

-- ----------------------------------------------------------------------- --
--                            filter auto switch                           --
-- ----------------------------------------------------------------------- --
local asterisk
local function CreateAutoSwitchFrame()
    -- 创建过滤器自动切换面板（位于布局页面右侧）
    -- 为每种队伍类型（小队/团队/史诗钥石/竞技场/战场）配置对应的过滤器编号
    -- 当前队伍类型会用星号(*)标记，文本高亮显示
    autoSwitchFrame = Cell.CreateFrame("CellQuickAssistFilterAutoSwitchFrame", pages.layout, 160, 185)
    autoSwitchFrame:SetPoint("BOTTOMLEFT", quickAssistTab, "BOTTOMRIGHT", 5, 0)
    autoSwitchFrame:Show()

    local autoSwitchPane = Cell.CreateTitledPane(autoSwitchFrame, L["Filter Auto Switch"], 150, 171)
    autoSwitchPane:SetPoint("TOPLEFT", 5, -5)

    asterisk = autoSwitchPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    asterisk:SetText("*")

    local items = {}
    for i = 0, 7 do
        tinsert(items, {
            ["text"] = i == 0 and "|cffc7c7c7"..L["Hide"] or romanNumerals[i],
            ["value"] = i,
            ["onClick"] = function(_, _, id)
                quickAssistTable["filterAutoSwitch"][id] = i
                if Cell.vars.quickAssistGroupType == id then
                    if i == 0 then
                        filterButtons[1]:GetScript("OnClick")()
                        selectedFilter = 1
                    else
                        filterButtons[i]:GetScript("OnClick")()
                        selectedFilter = i
                    end
                    Cell.Fire("UpdateQuickAssist", "filter")
                end
            end
        })
    end

    -- party
    partyDropdown = Cell.CreateDropdown(autoSwitchPane, 40, nil, true, true)
    partyDropdown:SetPoint("TOPLEFT", 5, -27)
    partyDropdown.id = "party"
    partyDropdown:SetItems(items)

    partyText = autoSwitchPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    partyText:SetPoint("LEFT", partyDropdown, "RIGHT", 5, 0)
    partyText:SetText(_G.PARTY)

    -- raid
    raidDropdown = Cell.CreateDropdown(autoSwitchPane, 40, nil, true, true)
    raidDropdown:SetPoint("TOPLEFT", partyDropdown, "BOTTOMLEFT", 0, -10)
    raidDropdown.id = "raid"
    raidDropdown:SetItems(items)

    raidText = autoSwitchPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    raidText:SetPoint("LEFT", raidDropdown, "RIGHT", 5, 0)
    raidText:SetText(_G.RAID)

    -- mythic
    mythicDropdown = Cell.CreateDropdown(autoSwitchPane, 40, nil, true, true)
    mythicDropdown:SetPoint("TOPLEFT", raidDropdown, "BOTTOMLEFT", 0, -10)
    mythicDropdown.id = "mythic"
    mythicDropdown:SetItems(items)

    mythicText = autoSwitchPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    mythicText:SetPoint("LEFT", mythicDropdown, "RIGHT", 5, 0)
    mythicText:SetText(_G.RAID.." ".._G.PLAYER_DIFFICULTY6)

    -- arena
    arenaDropdown = Cell.CreateDropdown(autoSwitchPane, 40, nil, true, true)
    arenaDropdown:SetPoint("TOPLEFT", mythicDropdown, "BOTTOMLEFT", 0, -10)
    arenaDropdown.id = "arena"
    arenaDropdown:SetItems(items)

    arenaText = autoSwitchPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    arenaText:SetPoint("LEFT", arenaDropdown, "RIGHT", 5, 0)
    arenaText:SetText(_G.ARENA)

    -- battleground
    bgDropdown = Cell.CreateDropdown(autoSwitchPane, 40, nil, true, true)
    bgDropdown:SetPoint("TOPLEFT", arenaDropdown, "BOTTOMLEFT", 0, -10)
    bgDropdown.id = "battleground"
    bgDropdown:SetItems(items)

    bgText = autoSwitchPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    bgText:SetPoint("LEFT", bgDropdown, "RIGHT", 5, 0)
    bgText:SetText(_G.BATTLEGROUND)
end

-- ----------------------------------------------------------------------- --
--                                  style                                  --
-- ----------------------------------------------------------------------- --

-- texture --------------------------------------------------------------- --
local LSM = LibStub("LibSharedMedia-3.0", true)
local textures, textureNames

local function LoadTextures()
    -- 加载 SharedMedia 状态条纹理列表，将"Cell 默认"纹理置顶
    local items = {}
    local defaultTexture, defaultTextureName = "Interface\\AddOns\\Cell\\Media\\statusbar.tga", "Cell ".._G.DEFAULT
    textures, textureNames = F.Copy(LSM:HashTable("statusbar")), F.Copy(LSM:List("statusbar"))

    -- make default texture first
    F.TRemove(textureNames, defaultTextureName)
    tinsert(textureNames, 1, defaultTextureName)

    for _, name in pairs(textureNames) do
        tinsert(items, {
            ["text"] = name,
            ["texture"] = textures[name],
            ["onClick"] = function()
                styleTable["texture"] = name
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        })
    end
    textureDropdown:SetItems(items)
end

-- name width ------------------------------------------------------------ --
local function CreateNameWidth(parent)
    -- 创建名字文本宽度配置控件，支持三种模式：
    -- 1. 无限制：文本不截断
    -- 2. 百分比：按按钮宽度的百分比限制（25%/50%/75%/100%）
    -- 3. 长度：按英文字符数和非英文字符数分别限制
    -- 包含 SetNameWidth(t) 方法用于从配置表加载当前设置
    local f = CreateFrame("Frame", nil, parent)
    P.Size(f, 117, 20)

    local dropdown, percentDropdown, lengthEB, lengthEB2

    dropdown = Cell.CreateDropdown(f, 117)
    dropdown:SetPoint("TOPLEFT")
    dropdown:SetLabel(L["Text Width"])
    dropdown:SetItems({
        {
            ["text"] = L["Unlimited"],
            ["onClick"] = function()
                styleTable["name"]["width"] = "unlimited"
                Cell.Fire("UpdateQuickAssist", "style")
                percentDropdown:Hide()
                lengthEB:Hide()
                lengthEB2:Hide()
                lengthEB.value = nil
                lengthEB2.value = nil
            end,
        },
        {
            ["text"] = L["Percentage"],
            ["onClick"] = function()
                styleTable["name"]["width"] = {"percentage", 0.75}
                Cell.Fire("UpdateQuickAssist", "style")
                percentDropdown:SetSelectedValue(0.75)
                percentDropdown:Show()
                lengthEB:Hide()
                lengthEB2:Hide()
                lengthEB.value = nil
                lengthEB2.value = nil
            end,
        },
        {
            ["text"] = L["Length"],
            ["onClick"] = function()
                styleTable["name"]["width"] = {"length", 5, 3}
                Cell.Fire("UpdateQuickAssist", "style")
                percentDropdown:Hide()
                lengthEB:SetText(5)
                lengthEB:Show()
                lengthEB2:SetText(3)
                lengthEB2:Show()
                lengthEB.value = 5
                lengthEB2.value = 3
            end,
        },
    })

    percentDropdown = Cell.CreateDropdown(f, 75)
    percentDropdown:SetPoint("TOPLEFT", dropdown, "TOPRIGHT", 30, 0)
    Cell.SetTooltips(percentDropdown.button, "ANCHOR_TOP", 0, 3, L["Name Width / UnitButton Width"])
    percentDropdown:SetItems({
        {
            ["text"] = "100%",
            ["value"] = 1,
            ["onClick"] = function()
                styleTable["name"]["width"][2] = 1
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
        {
            ["text"] = "75%",
            ["value"] = 0.75,
            ["onClick"] = function()
                styleTable["name"]["width"][2] = 0.75
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
        {
            ["text"] = "50%",
            ["value"] = 0.5,
            ["onClick"] = function()
                styleTable["name"]["width"][2] = 0.5
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
        {
            ["text"] = "25%",
            ["value"] = 0.25,
            ["onClick"] = function()
                styleTable["name"]["width"][2] = 0.25
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
    })

    lengthEB = Cell.CreateEditBox(f, 34, 20, false, false, true)
    lengthEB:SetPoint("TOPLEFT", dropdown, "TOPRIGHT", 30, 0)

    lengthEB.text = lengthEB:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    lengthEB.text:SetText(L["En"])
    lengthEB.text:SetPoint("BOTTOMLEFT", lengthEB, "TOPLEFT", 0, 1)

    lengthEB.confirmBtn = Cell.CreateButton(lengthEB, "OK", "accent", {27, 20})
    lengthEB.confirmBtn:SetPoint("TOPLEFT", lengthEB, "TOPRIGHT", -1, 0)
    lengthEB.confirmBtn:Hide()
    lengthEB.confirmBtn:SetScript("OnHide", function()
        lengthEB.confirmBtn:Hide()
    end)
    lengthEB.confirmBtn:SetScript("OnClick", function()
        local length = tonumber(lengthEB:GetText())
        lengthEB:SetText(length)
        lengthEB:ClearFocus()
        lengthEB.confirmBtn:Hide()
        lengthEB.value = length

        styleTable["name"]["width"][2] = length
        Cell.Fire("UpdateQuickAssist", "style")
    end)

    lengthEB:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            local length = tonumber(self:GetText())
            if length and length ~= lengthEB.value and length ~= 0 then
                lengthEB.confirmBtn:Show()
            else
                lengthEB.confirmBtn:Hide()
            end
        end
    end)

    lengthEB2 = Cell.CreateEditBox(f, 33, 20, false, false, true)
    lengthEB2:SetPoint("TOPLEFT", lengthEB, "TOPRIGHT", 25, 0)

    lengthEB2.text = lengthEB2:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    lengthEB2.text:SetText(L["Non-En"])
    lengthEB2.text:SetPoint("BOTTOMLEFT", lengthEB2, "TOPLEFT", 0, 1)

    lengthEB2.confirmBtn = Cell.CreateButton(lengthEB2, "OK", "accent", {27, 20})
    lengthEB2.confirmBtn:SetPoint("TOPLEFT", lengthEB2, "TOPRIGHT", -1, 0)
    lengthEB2.confirmBtn:Hide()
    lengthEB2.confirmBtn:SetScript("OnHide", function()
        lengthEB2.confirmBtn:Hide()
    end)
    lengthEB2.confirmBtn:SetScript("OnClick", function()
        local length = tonumber(lengthEB2:GetText())
        lengthEB2:SetText(length)
        lengthEB2:ClearFocus()
        lengthEB2.confirmBtn:Hide()
        lengthEB2.value = length

        styleTable["name"]["width"][3] = length
        Cell.Fire("UpdateQuickAssist", "style")
    end)

    lengthEB2:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            local length = tonumber(self:GetText())
            if length and length ~= lengthEB2.value and length ~= 0 then
                lengthEB2.confirmBtn:Show()
            else
                lengthEB2.confirmBtn:Hide()
            end
        end
    end)

    function f:SetNameWidth(t)
        if t == "unlimited" then
            dropdown:SetSelectedItem(1)
            percentDropdown:Hide()
            lengthEB:Hide()
            lengthEB2:Hide()
        elseif t[1] == "percentage" then
            dropdown:SetSelectedItem(2)
            percentDropdown:SetSelectedValue(t[2])
            percentDropdown:Show()
            lengthEB:Hide()
            lengthEB2:Hide()
        elseif t[1] == "length" then
            dropdown:SetSelectedItem(3)
            lengthEB:SetText(t[2])
            lengthEB.value = t[2]
            lengthEB:Show()
            lengthEB2:SetText(t[3])
            lengthEB2.value = t[3]
            lengthEB2:Show()
            percentDropdown:Hide()
        end
    end

    return f
end

local function CreateStylePane()
    -- 创建样式配置页面，包含：
    -- - 血条颜色/损失颜色下拉框和自定义颜色选择器
    -- - 纹理下拉框、超出范围透明度滑块
    -- - 目标高亮/鼠标悬停高亮颜色选择器、高亮边框大小滑块
    -- - 名字文本子面板：颜色、宽度模式、锚点、偏移、字体、字号、描边、阴影
    pages.style = CreateFrame("Frame", nil, quickAssistTab)
    pages.style:SetAllPoints(setupPane)
    pages.style:Hide()

    hpColorDropdown = Cell.CreateDropdown(pages.style, 160)
    hpColorDropdown:SetPoint("TOPLEFT", pages.style, "TOPLEFT", 5, -42)
    hpColorDropdown:SetLabel(L["Health Bar Color"])
    hpColorDropdown:SetItems({
        {
            ["text"] = L["Class Color"],
            ["value"] = "class_color",
            ["onClick"] = function()
                styleTable["hpColor"][1] = "class_color"
                hpCP:Hide()
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
        {
            ["text"] = L["Class Color (dark)"],
            ["value"] = "class_color_dark",
            ["onClick"] = function()
                styleTable["hpColor"][1] = "class_color_dark"
                hpCP:Hide()
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
        {
            ["text"] = L["Custom Color"],
            ["value"] = "custom",
            ["onClick"] = function()
                styleTable["hpColor"][1] = "custom"
                hpCP:Show()
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
    })

    hpCP = Cell.CreateColorPicker(pages.style, "", true, function(r, g, b, a)
        styleTable["hpColor"][2][1] = r
        styleTable["hpColor"][2][2] = g
        styleTable["hpColor"][2][3] = b
        styleTable["hpColor"][2][4] = a
        Cell.Fire("UpdateQuickAssist", "style")
    end)
    hpCP:SetPoint("LEFT", hpColorDropdown, "RIGHT", 2, 0)

    lossColorDropdown = Cell.CreateDropdown(pages.style, 160)
    lossColorDropdown:SetPoint("TOPLEFT", hpColorDropdown, "TOPRIGHT", 57, 0)
    lossColorDropdown:SetLabel(L["Health Loss Color"])
    lossColorDropdown:SetItems({
        {
            ["text"] = L["Class Color"],
            ["value"] = "class_color",
            ["onClick"] = function()
                styleTable["lossColor"][1] = "class_color"
                bgCP:Hide()
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
        {
            ["text"] = L["Class Color (dark)"],
            ["value"] = "class_color_dark",
            ["onClick"] = function()
                styleTable["lossColor"][1] = "class_color_dark"
                bgCP:Hide()
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
        {
            ["text"] = L["Custom Color"],
            ["value"] = "custom",
            ["onClick"] = function()
                styleTable["lossColor"][1] = "custom"
                bgCP:Show()
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
    })

    bgCP = Cell.CreateColorPicker(pages.style, "", true, function(r, g, b, a)
        styleTable["lossColor"][2][1] = r
        styleTable["lossColor"][2][2] = g
        styleTable["lossColor"][2][3] = b
        styleTable["lossColor"][2][4] = a
        Cell.Fire("UpdateQuickAssist", "style")
    end)
    bgCP:SetPoint("LEFT", lossColorDropdown, "RIGHT", 2, 0)

    textureDropdown = Cell.CreateDropdown(pages.style, 160, "texture")
    textureDropdown:SetPoint("TOPLEFT", hpColorDropdown, 0, -50)
    textureDropdown:SetLabel(L["Texture"])
    LoadTextures()

    alphaSlider = Cell.CreateSlider(L["Out of Range Alpha"], pages.style, 0, 100, 160, 1)
    alphaSlider:SetPoint("TOPLEFT", textureDropdown, "TOPRIGHT", 57, 0)
    alphaSlider.afterValueChangedFn = function(value)
        styleTable["oorAlpha"] = value/100
        Cell.Fire("UpdateQuickAssist", "style")
    end

    targetColorPicker = Cell.CreateColorPicker(pages.style, L["Target Highlight Color"], true, function(r, g, b, a)
        styleTable["targetColor"][1] = r
        styleTable["targetColor"][2] = g
        styleTable["targetColor"][3] = b
        styleTable["targetColor"][4] = a
        Cell.Fire("UpdateQuickAssist", "style")
    end)
    targetColorPicker:SetPoint("TOPLEFT", textureDropdown, "BOTTOMLEFT", 0, -20)

    mouseoverColorPicker = Cell.CreateColorPicker(pages.style, L["Mouseover Highlight Color"], true, function(r, g, b, a)
        styleTable["mouseoverColor"][1] = r
        styleTable["mouseoverColor"][2] = g
        styleTable["mouseoverColor"][3] = b
        styleTable["mouseoverColor"][4] = a
        Cell.Fire("UpdateQuickAssist", "style")
    end)
    mouseoverColorPicker:SetPoint("TOPLEFT", targetColorPicker, "BOTTOMLEFT", 0, -10)

    highlightSizeSlider = Cell.CreateSlider(L["Highlight Size"], pages.style, -5, 5, 160, 1)
    highlightSizeSlider:SetPoint("TOPLEFT", alphaSlider, 0, -50)
    highlightSizeSlider.afterValueChangedFn = function(value)
        styleTable["highlightSize"] = value
        Cell.Fire("UpdateQuickAssist", "style")
    end

    --* name ------------------------------------------------------------------ --
    local namePane = Cell.CreateTitledPane(pages.style, L["Name Text"], 422, 190)
    namePane:SetPoint("TOPLEFT", 0, -195)

    nameColorDropdown = Cell.CreateDropdown(namePane, 117)
    nameColorDropdown:SetPoint("TOPLEFT", namePane, 5, -42)
    nameColorDropdown:SetLabel(L["Color"])
    nameColorDropdown:SetItems({
        {
            ["text"] = L["Class Color"],
            ["value"] = "class_color",
            ["onClick"] = function()
                styleTable["name"]["color"][1] = "class_color"
                nameCP:Hide()
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
        {
            ["text"] = L["Custom Color"],
            ["value"] = "custom",
            ["onClick"] = function()
                styleTable["name"]["color"][1] = "custom"
                nameCP:Show()
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        },
    })

    nameCP = Cell.CreateColorPicker(namePane, "", false, function(r, g, b, a)
        styleTable["name"]["color"][2][1] = r
        styleTable["name"]["color"][2][2] = g
        styleTable["name"]["color"][2][3] = b
        Cell.Fire("UpdateQuickAssist", "style")
    end)
    nameCP:SetPoint("LEFT", nameColorDropdown, "RIGHT", 2, 0)

    nameWidth = CreateNameWidth(namePane)
    nameWidth:SetPoint("TOPLEFT", nameColorDropdown, "TOPRIGHT", 30, 0)

    nameAnchorDropdown = Cell.CreateDropdown(namePane, 117)
    nameAnchorDropdown:SetPoint("TOPLEFT", nameColorDropdown, 0, -50)
    nameAnchorDropdown:SetLabel(L["Anchor Point"])

    items = {}
    for _, v in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[v],
            ["value"] = v,
            ["onClick"] = function()
                styleTable["name"]["position"][1] = v
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        })
    end
    nameAnchorDropdown:SetItems(items)

    nameXSlider = Cell.CreateSlider(L["X Offset"], namePane, -100, 100, 117, 1)
    nameXSlider:SetPoint("TOPLEFT", nameAnchorDropdown, "TOPRIGHT", 30, 0)
    nameXSlider.afterValueChangedFn = function(value)
        styleTable["name"]["position"][2] = value
        Cell.Fire("UpdateQuickAssist", "style")
    end

    nameYSlider = Cell.CreateSlider(L["Y Offset"], namePane, -100, 100, 117, 1)
    nameYSlider:SetPoint("TOPLEFT", nameXSlider, "TOPRIGHT", 30, 0)
    nameYSlider.afterValueChangedFn = function(value)
        styleTable["name"]["position"][3] = value
        Cell.Fire("UpdateQuickAssist", "style")
    end

    nameFontDropdown = Cell.CreateDropdown(namePane, 117)
    nameFontDropdown:SetPoint("TOPLEFT", nameAnchorDropdown, 0, -50)
    nameFontDropdown:SetLabel(L["Font"])

    local items, fonts, defaultFontName, defaultFont = F.GetFontItems()
    for _, item in pairs(items) do
        item["onClick"] = function()
            styleTable["name"]["font"][1] = item["text"]
            Cell.Fire("UpdateQuickAssist", "style")
        end
    end
    nameFontDropdown:SetItems(items)

    function nameFontDropdown:SetFont(font)
        nameFontDropdown:SetSelected(font, fonts[font])
    end

    nameOutlineDropdown = Cell.CreateDropdown(namePane, 117)
    nameOutlineDropdown:SetPoint("TOPLEFT", nameFontDropdown, "TOPRIGHT", 30, 0)
    nameOutlineDropdown:SetLabel(L["Outline"])

    items = {}
    for _, v in pairs(outlines) do
        tinsert(items, {
            ["text"] = L[v],
            ["value"] = v,
            ["onClick"] = function()
                styleTable["name"]["font"][3] = v
                Cell.Fire("UpdateQuickAssist", "style")
            end,
        })
    end
    nameOutlineDropdown:SetItems(items)

    nameSizeSilder = Cell.CreateSlider(L["Size"], namePane, 5, 50, 117, 1)
    nameSizeSilder:SetPoint("TOPLEFT", nameOutlineDropdown, "TOPRIGHT", 30, 0)
    nameSizeSilder.afterValueChangedFn = function(value)
        styleTable["name"]["font"][2] = value
        Cell.Fire("UpdateQuickAssist", "style")
    end

    nameShadowCB = Cell.CreateCheckButton(namePane, L["Shadow"], function(checked, self)
        styleTable["name"]["font"][4] = checked
        Cell.Fire("UpdateQuickAssist", "style")
    end)
    nameShadowCB:SetPoint("TOPLEFT", nameFontDropdown, "BOTTOMLEFT", 0, -10)
end

-- ----------------------------------------------------------------------- --
--                                  spells                                 --
-- ----------------------------------------------------------------------- --

-- icon options ---------------------------------------------------------- --
local iconOptionsFrame
local currentIconOptionBtn, currentIconIndex

local function CreateIconOptions(parent)
    -- 创建图标指示器选项弹窗面板，包含两个子标签页：
    -- - Icon 标签页：锚点、相对锚点、排列方向、光效类型、光效颜色、偏移、尺寸、显示动画开关
    -- - Font 标签页（stackFont/durationFont）：字体、字号、描边、阴影、锚点、偏移、颜色
    -- 显示时自动创建遮罩层以阻止点击穿透
    iconOptionsFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Cell.StylizeFrame(iconOptionsFrame, nil, Cell.GetAccentColorTable())
    iconOptionsFrame:SetFrameLevel(parent:GetFrameLevel()+50)
    iconOptionsFrame:Hide()

    iconOptionsFrame:SetHeight(190)
    iconOptionsFrame:SetPoint("TOP", 0, -90)
    iconOptionsFrame:SetPoint("LEFT")
    iconOptionsFrame:SetPoint("RIGHT")

    -- icon tab -------------------------------------------------------------- --
    local iconTab = CreateFrame("Frame", nil, iconOptionsFrame)
    iconTab:SetAllPoints(iconOptionsFrame)
    iconTab:Hide()

    local iconAnchorDropdown = Cell.CreateDropdown(iconTab, 117)
    iconAnchorDropdown:SetPoint("TOPLEFT", 5, -27)
    iconAnchorDropdown:SetLabel(L["Anchor Point"])
    local items = {}
    for _, point in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[point],
            ["value"] = point,
            ["onClick"] = function()
                spellTable[currentIconIndex]["icon"]["position"][1] = point
                Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
            end,
        })
    end
    iconAnchorDropdown:SetItems(items)

    local iconRelativeToDropdown = Cell.CreateDropdown(iconTab, 117)
    iconRelativeToDropdown:SetPoint("TOPLEFT", iconAnchorDropdown, "TOPRIGHT", 30, 0)
    iconRelativeToDropdown:SetLabel(L["To UnitButton's"])
    items = {}
    for _, point in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[point],
            ["value"] = point,
            ["onClick"] = function()
                spellTable[currentIconIndex]["icon"]["position"][2] = point
                Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
            end,
        })
    end
    iconRelativeToDropdown:SetItems(items)

    local iconOrientationDropdown = Cell.CreateDropdown(iconTab, 117)
    iconOrientationDropdown:SetPoint("TOPLEFT", iconRelativeToDropdown, "TOPRIGHT", 30, 0)
    iconOrientationDropdown:SetLabel(L["Orientation"])
    items = {}
    for _, o in pairs(orientations) do
        tinsert(items, {
            ["text"] = L[o],
            ["value"] = o,
            ["onClick"] = function()
                spellTable[currentIconIndex]["icon"]["orientation"] = o
                Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
            end,
        })
    end
    iconOrientationDropdown:SetItems(items)

    local iconGlowDropdown = Cell.CreateDropdown(iconTab, 117)
    iconGlowDropdown:SetPoint("TOPLEFT", iconOrientationDropdown, 0, -50)
    iconGlowDropdown:SetLabel(L["Glow"])
    items = {}
    for _, g in pairs(glows) do
        tinsert(items, {
            ["text"] = L[g],
            ["value"] = g,
            ["onClick"] = function()
                spellTable[currentIconIndex]["icon"]["glow"] = g
                Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
            end,
        })
    end
    iconGlowDropdown:SetItems(items)

    local iconGlowCP = Cell.CreateColorPicker(iconTab, L["Glow Color"], false, nil, function(r, g, b)
        spellTable[currentIconIndex]["icon"]["glowColor"][1] = r
        spellTable[currentIconIndex]["icon"]["glowColor"][2] = g
        spellTable[currentIconIndex]["icon"]["glowColor"][3] = b
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end)
    iconGlowCP:SetPoint("TOPLEFT", iconGlowDropdown, 0, -50)

    local iconXSlider = Cell.CreateSlider(L["X Offset"], iconTab, -100, 100, 117, 1)
    iconXSlider:SetPoint("TOPLEFT", iconAnchorDropdown, 0, -50)
    iconXSlider.afterValueChangedFn = function(value)
        spellTable[currentIconIndex]["icon"]["position"][3] = value
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end

    local iconYSlider = Cell.CreateSlider(L["Y Offset"], iconTab, -100, 100, 117, 1)
    iconYSlider:SetPoint("TOPLEFT", iconXSlider, "TOPRIGHT", 30, 0)
    iconYSlider.afterValueChangedFn = function(value)
        spellTable[currentIconIndex]["icon"]["position"][4] = value
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end

    local iconWidthSlider = Cell.CreateSlider(L["Width"], iconTab, 5, 100, 117, 1)
    iconWidthSlider:SetPoint("TOPLEFT", iconXSlider, 0, -50)
    iconWidthSlider.afterValueChangedFn = function(value)
        spellTable[currentIconIndex]["icon"]["size"][1] = value
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end

    local iconHeightSlider = Cell.CreateSlider(L["Height"], iconTab, 5, 100, 117, 1)
    iconHeightSlider:SetPoint("TOPLEFT", iconWidthSlider, "TOPRIGHT", 30, 0)
    iconHeightSlider.afterValueChangedFn = function(value)
        spellTable[currentIconIndex]["icon"]["size"][2] = value
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end

    local iconShowAnimationCB = Cell.CreateCheckButton(iconTab, L["showAnimation"], function(checked)
        spellTable[currentIconIndex]["icon"]["showAnimation"] = checked
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end)
    iconShowAnimationCB:SetPoint("TOPLEFT", iconWidthSlider, 0, -40)

    function iconTab:Load(t)
        iconTab:Show()

        iconAnchorDropdown:SetSelectedValue(t["position"][1])
        iconRelativeToDropdown:SetSelectedValue(t["position"][2])
        iconOrientationDropdown:SetSelectedValue(t["orientation"])
        iconGlowDropdown:SetSelectedValue(t["glow"])
        iconXSlider:SetValue(t["position"][3])
        iconYSlider:SetValue(t["position"][4])
        iconWidthSlider:SetValue(t["size"][1])
        iconHeightSlider:SetValue(t["size"][2])
        iconShowAnimationCB:SetChecked(t["showAnimation"])

        if currentIconIndex == "offensives" then
            iconGlowCP:Show()
            iconGlowCP:SetColor(t["glowColor"])
        else
            iconGlowCP:Hide()
        end
    end

    -- font tab -------------------------------------------------------------- --
    local fontTab = CreateFrame("Frame", nil, iconOptionsFrame)
    fontTab:SetAllPoints(iconOptionsFrame)
    fontTab:Hide()

    local fontIndex

    local iconShowStackCB = Cell.CreateCheckButton(fontTab, L["showStack"], function(checked)
        spellTable[currentIconIndex]["icon"]["showStack"] = checked
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end)
    iconShowStackCB:SetPoint("TOPLEFT", 5, -27)

    local iconDurationDropdown = Cell.CreateDropdown(fontTab, 117)
    iconDurationDropdown:SetPoint("TOPLEFT", 5, -27)
    iconDurationDropdown:SetLabel(L["showDuration"])

    local function ShowDuration(_, show)
        spellTable[currentIconIndex]["icon"]["showDuration"] = show
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end

    iconDurationDropdown:SetItems({
        {
            ["text"] = L["Never"],
            ["value"] = false,
            ["onClick"] = ShowDuration,
        },
        {
            ["text"] = L["Always"],
            ["value"] = true,
            ["onClick"] = ShowDuration,
        },
        {
            ["text"] = "< 75%",
            ["value"] = 0.75,
            ["onClick"] = ShowDuration,
        },
        {
            ["text"] = "< 50%",
            ["value"] = 0.5,
            ["onClick"] = ShowDuration,
        },
        {
            ["text"] = "< 25%",
            ["value"] = 0.25,
            ["onClick"] = ShowDuration,
        },
        {
            ["text"] = "< 15 "..L["sec"],
            ["value"] = 15,
            ["onClick"] = ShowDuration,
        },
        {
            ["text"] = "< 10 "..L["sec"],
            ["value"] = 10,
            ["onClick"] = ShowDuration,
        },
        {
            ["text"] = "< 5 "..L["sec"],
            ["value"] = 5,
            ["onClick"] = ShowDuration,
        },
    })

    local iconFontDropdown = Cell.CreateDropdown(fontTab, 117)
    iconFontDropdown:SetPoint("TOPLEFT", iconShowStackCB, 0, -50)
    iconFontDropdown:SetLabel(L["Font"])

    local items, fonts, defaultFontName, defaultFont = F.GetFontItems()
    for _, item in pairs(items) do
        item["onClick"] = function()
            spellTable[currentIconIndex]["icon"]["font"][fontIndex][1] = item["text"]
            Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
        end
    end
    iconFontDropdown:SetItems(items)

    function iconFontDropdown:SetFont(font)
        iconFontDropdown:SetSelected(font, fonts[font])
    end

    local iconFontOutlineDropdown = Cell.CreateDropdown(fontTab, 117)
    iconFontOutlineDropdown:SetPoint("TOPLEFT", iconFontDropdown, "TOPRIGHT", 30, 0)
    iconFontOutlineDropdown:SetLabel(L["Outline"])

    items = {}
    for _, v in pairs(outlines) do
        tinsert(items, {
            ["text"] = L[v],
            ["value"] = v,
            ["onClick"] = function()
                spellTable[currentIconIndex]["icon"]["font"][fontIndex][3] = v
                Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
            end,
        })
    end
    iconFontOutlineDropdown:SetItems(items)

    local iconFontSizeSlider = Cell.CreateSlider(L["Size"], fontTab, 5, 50, 117, 1)
    iconFontSizeSlider:SetPoint("TOPLEFT", iconFontOutlineDropdown, "TOPRIGHT", 30, 0)
    iconFontSizeSlider.afterValueChangedFn = function(value)
        spellTable[currentIconIndex]["icon"]["font"][fontIndex][2] = value
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end

    local iconShadowCB = Cell.CreateCheckButton(fontTab, L["Shadow"], function(checked)
        spellTable[currentIconIndex]["icon"]["font"][fontIndex][4] = checked
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end)
    iconShadowCB:SetPoint("TOPLEFT", iconFontOutlineDropdown, 0, 50)

    local iconFontAnchorDropdown = Cell.CreateDropdown(fontTab, 117)
    iconFontAnchorDropdown:SetPoint("TOPLEFT", iconFontDropdown, 0, -50)
    iconFontAnchorDropdown:SetLabel(L["Anchor Point"])

    items = {}
    for _, v in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[v],
            ["value"] = v,
            ["onClick"] = function()
                spellTable[currentIconIndex]["icon"]["font"][fontIndex][5] = v
                Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
            end,
        })
    end
    iconFontAnchorDropdown:SetItems(items)

    local iconFontXSlider = Cell.CreateSlider(L["X Offset"], fontTab, -50, 50, 117, 1)
    iconFontXSlider:SetPoint("TOPLEFT", iconFontAnchorDropdown, "TOPRIGHT", 30, 0)
    iconFontXSlider.afterValueChangedFn = function(value)
        spellTable[currentIconIndex]["icon"]["font"][fontIndex][6] = value
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end

    local iconFontYSlider = Cell.CreateSlider(L["Y Offset"], fontTab, -50, 50, 117, 1)
    iconFontYSlider:SetPoint("TOPLEFT", iconFontXSlider, "TOPRIGHT", 30, 0)
    iconFontYSlider.afterValueChangedFn = function(value)
        spellTable[currentIconIndex]["icon"]["font"][fontIndex][7] = value
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end

    local iconFontCP = Cell.CreateColorPicker(fontTab, L["Color"], false, nil, function(r, g, b)
        spellTable[currentIconIndex]["icon"]["font"][fontIndex][8][1] = r
        spellTable[currentIconIndex]["icon"]["font"][fontIndex][8][2] = g
        spellTable[currentIconIndex]["icon"]["font"][fontIndex][8][3] = b
        Cell.Fire("UpdateQuickAssist", currentIconIndex.."-indicator")
    end)
    iconFontCP:SetPoint("TOPLEFT", iconFontSizeSlider, 0, 50)

    function fontTab:Load(t, fIndex)
        fontTab:Show()
        fontIndex = fIndex

        if fIndex == 1 then
            iconDurationDropdown:Hide()
            iconShowStackCB:Show()
            iconShowStackCB:SetChecked(spellTable[currentIconIndex]["icon"]["showStack"])
        else
            iconShowStackCB:Hide()
            iconDurationDropdown:Show()
            iconDurationDropdown:SetSelectedValue(spellTable[currentIconIndex]["icon"]["showDuration"])
        end
        iconFontDropdown:SetFont(t[1])
        iconFontOutlineDropdown:SetSelectedValue(t[3])
        iconFontSizeSlider:SetValue(t[2])
        iconShadowCB:SetChecked(t[4])
        iconFontAnchorDropdown:SetSelectedValue(t[5])
        iconFontXSlider:SetValue(t[6])
        iconFontYSlider:SetValue(t[7])
        iconFontCP:SetColor(t[8])
    end

    -- buttons --------------------------------------------------------------- --
    local buttons = {}
    buttons["icon"] = Cell.CreateButton(iconOptionsFrame, L["Icon"], "accent-hover", {100, 17})
    buttons["icon"]:SetPoint("BOTTOMLEFT", iconOptionsFrame, "TOPLEFT")
    buttons["icon"].id = "icon"

    buttons["stackFont"] = Cell.CreateButton(iconOptionsFrame, L["stackFont"], "accent-hover", {100, 17})
    buttons["stackFont"]:SetPoint("BOTTOMLEFT", buttons["icon"], "BOTTOMRIGHT", P.Scale(-1), 0)
    buttons["stackFont"].id = "stackFont"

    buttons["durationFont"] = Cell.CreateButton(iconOptionsFrame, L["durationFont"], "accent-hover", {100, 17})
    buttons["durationFont"]:SetPoint("BOTTOMLEFT", buttons["stackFont"], "BOTTOMRIGHT", P.Scale(-1), 0)
    buttons["durationFont"].id = "durationFont"

    Cell.CreateButtonGroup(buttons, function(id)
        if id == "icon" then
            fontTab:Hide()
            iconTab:Load(spellTable[currentIconIndex]["icon"])
        elseif id == "stackFont" then
            iconTab:Hide()
            fontTab:Load(spellTable[currentIconIndex]["icon"]["font"][1], 1)
        else
            iconTab:Hide()
            fontTab:Load(spellTable[currentIconIndex]["icon"]["font"][2], 2)
        end
    end)

    iconOptionsFrame:SetScript("OnShow", function()
        currentIconOptionBtn:SetFrameLevel(parent:GetFrameLevel()+50)
        Cell.CreateMask(Cell.frames.utilitiesTab, nil, {1, -1, -1, 1})
        buttons["icon"]:GetScript("OnClick")()
        F.Debug("|cff33937FQuickAssist_ShowIconOptions:|r", currentIconIndex)
    end)

    iconOptionsFrame:SetScript("OnHide", function()
        currentIconOptionBtn:SetFrameLevel(currentIconOptionBtn.frameLevel)
        iconOptionsFrame:Hide()
        Cell.frames.utilitiesTab.mask:Hide()
    end)
end

local function SetIconOptions_OnClick(b)
    -- 为图标/指示器设置按钮绑定点击事件：切换图标选项弹窗的显示/隐藏
    -- b.index 指定是 "mine"（自身增益）还是 "offensives"（爆发法术）
    b.frameLevel = b:GetFrameLevel()
    b:SetScript("OnClick", function()
        currentIconIndex = b.index
        currentIconOptionBtn = b
        if iconOptionsFrame:IsShown() then
            iconOptionsFrame:Hide()
        else
            iconOptionsFrame:Show()
        end
    end)
end

-- bar options ----------------------------------------------------------- --
local barOptionsFrame
local currentBarOptionBtn, currentBarIndex

local function CreateBarOptions(parent)
    -- 创建计时条指示器选项弹窗面板，配置项包括：
    -- - 锚点、相对锚点、排列方向（仅垂直方向）
    -- - X/Y偏移滑块、宽度/高度滑块
    -- 显示时自动创建遮罩层
    barOptionsFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Cell.StylizeFrame(barOptionsFrame, nil, Cell.GetAccentColorTable())
    barOptionsFrame:SetFrameLevel(parent:GetFrameLevel()+50)
    barOptionsFrame:Hide()

    barOptionsFrame:SetHeight(170)
    barOptionsFrame:SetPoint("TOP", 0, -73)
    barOptionsFrame:SetPoint("LEFT")
    barOptionsFrame:SetPoint("RIGHT")

    local barAnchorDropdown = Cell.CreateDropdown(barOptionsFrame, 117)
    barAnchorDropdown:SetPoint("TOPLEFT", 5, -27)
    barAnchorDropdown:SetLabel(L["Anchor Point"])
    local items = {}
    for _, point in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[point],
            ["value"] = point,
            ["onClick"] = function()
                spellTable[currentBarIndex]["bar"]["position"][1] = point
                Cell.Fire("UpdateQuickAssist", currentBarIndex.."-indicator")
            end,
        })
    end
    barAnchorDropdown:SetItems(items)

    local barRelativeToDropdown = Cell.CreateDropdown(barOptionsFrame, 117)
    barRelativeToDropdown:SetPoint("TOPLEFT", barAnchorDropdown, "TOPRIGHT", 30, 0)
    barRelativeToDropdown:SetLabel(L["To UnitButton's"])
    items = {}
    for _, point in pairs(anchorPoints) do
        tinsert(items, {
            ["text"] = L[point],
            ["value"] = point,
            ["onClick"] = function()
                spellTable[currentBarIndex]["bar"]["position"][2] = point
                Cell.Fire("UpdateQuickAssist", currentBarIndex.."-indicator")
            end,
        })
    end
    barRelativeToDropdown:SetItems(items)

    local barOrientationDropdown = Cell.CreateDropdown(barOptionsFrame, 117)
    barOrientationDropdown:SetPoint("TOPLEFT", barRelativeToDropdown, "TOPRIGHT", 30, 0)
    barOrientationDropdown:SetLabel(L["Orientation"])
    items = {}
    for _, o in pairs(orientations) do
        if strfind(o, "top") then
            tinsert(items, {
                ["text"] = L[o],
                ["value"] = o,
                ["onClick"] = function()
                    spellTable[currentBarIndex]["bar"]["orientation"] = o
                    Cell.Fire("UpdateQuickAssist", currentBarIndex.."-indicator")
                end,
            })
        end
    end
    barOrientationDropdown:SetItems(items)

    -- local barGlowDropdown = Cell.CreateDropdown(barOptionsFrame, 117)
    -- barGlowDropdown:SetPoint("TOPLEFT", barOrientationDropdown, 0, -50)
    -- barGlowDropdown:SetLabel(L["Glow"])
    -- items = {}
    -- for _, g in pairs(glows) do
    --     tinsert(items, {
    --         ["text"] = L[g],
    --         ["value"] = g,
    --         ["onClick"] = function()
    --             spellTable[currentBarIndex]["bar"]["glow"] = g
    --             Cell.Fire("UpdateQuickAssist", currentBarIndex.."-indicator")
    --         end,
    --     })
    -- end
    -- barGlowDropdown:SetItems(items)

    -- local barGlowCP = Cell.CreateColorPicker(barOptionsFrame, L["Glow Color"], false, nil, function(r, g, b)
    --     spellTable[currentBarIndex]["bar"]["glowColor"][1] = r
    --     spellTable[currentBarIndex]["bar"]["glowColor"][2] = g
    --     spellTable[currentBarIndex]["bar"]["glowColor"][3] = b
    --     Cell.Fire("UpdateQuickAssist", currentBarIndex.."-indicator")
    -- end)
    -- barGlowCP:SetPoint("TOPLEFT", barGlowDropdown, 0, -50)

    local barXSlider = Cell.CreateSlider(L["X Offset"], barOptionsFrame, -100, 100, 117, 1)
    barXSlider:SetPoint("TOPLEFT", barAnchorDropdown, 0, -50)
    barXSlider.afterValueChangedFn = function(value)
        spellTable[currentBarIndex]["bar"]["position"][3] = value
        Cell.Fire("UpdateQuickAssist", currentBarIndex.."-indicator")
    end

    local barYSlider = Cell.CreateSlider(L["Y Offset"], barOptionsFrame, -100, 100, 117, 1)
    barYSlider:SetPoint("TOPLEFT", barXSlider, "TOPRIGHT", 30, 0)
    barYSlider.afterValueChangedFn = function(value)
        spellTable[currentBarIndex]["bar"]["position"][4] = value
        Cell.Fire("UpdateQuickAssist", currentBarIndex.."-indicator")
    end

    local barWidthSlider = Cell.CreateSlider(L["Width"], barOptionsFrame, 10, 300, 117, 1)
    barWidthSlider:SetPoint("TOPLEFT", barXSlider, 0, -50)
    barWidthSlider.afterValueChangedFn = function(value)
        spellTable[currentBarIndex]["bar"]["size"][1] = value
        Cell.Fire("UpdateQuickAssist", currentBarIndex.."-indicator")
    end

    local barHeightSlider = Cell.CreateSlider(L["Height"], barOptionsFrame, 3, 300, 117, 1)
    barHeightSlider:SetPoint("TOPLEFT", barWidthSlider, "TOPRIGHT", 30, 0)
    barHeightSlider.afterValueChangedFn = function(value)
        spellTable[currentBarIndex]["bar"]["size"][2] = value
        Cell.Fire("UpdateQuickAssist", currentBarIndex.."-indicator")
    end

    function barOptionsFrame:Load(t)
        barAnchorDropdown:SetSelectedValue(t["position"][1])
        barRelativeToDropdown:SetSelectedValue(t["position"][2])
        barOrientationDropdown:SetSelectedValue(t["orientation"])
        barXSlider:SetValue(t["position"][3])
        barYSlider:SetValue(t["position"][4])
        barWidthSlider:SetValue(t["size"][1])
        barHeightSlider:SetValue(t["size"][2])
    end

    barOptionsFrame:SetScript("OnShow", function()
        currentBarOptionBtn:SetFrameLevel(parent:GetFrameLevel()+50)
        Cell.CreateMask(Cell.frames.utilitiesTab, nil, {1, -1, -1, 1})
        F.Debug("|cff33937FQuickAssist_ShowBarOptions:|r", currentBarIndex)
    end)

    barOptionsFrame:SetScript("OnHide", function()
        currentBarOptionBtn:SetFrameLevel(currentBarOptionBtn.frameLevel)
        barOptionsFrame:Hide()
        Cell.frames.utilitiesTab.mask:Hide()
    end)
end

local function SetBarOptions_OnClick(b)
    -- 为计时条设置按钮绑定点击事件：切换计时条选项弹窗的显示/隐藏
    -- 显示时自动加载当前配置到各控件
    b.frameLevel = b:GetFrameLevel()
    b:SetScript("OnClick", function()
        currentBarIndex = b.index
        currentBarOptionBtn = b
        if barOptionsFrame:IsShown() then
            barOptionsFrame:Hide()
        else
            barOptionsFrame:Show()
            barOptionsFrame:Load(spellTable[currentBarIndex]["bar"])
        end
    end)
end

-- glow options ---------------------------------------------------------- --
local glowOptionsFrame
local currentGlowOptionBtn, currentGlowIndex

local function CreateGlowOptions(parent)
    -- 创建光效选项弹窗面板，支持五种光效类型：
    -- - None：无光效
    -- - Normal：标准光效
    -- - Pixel：像素光效（线条数、频率、长度、粗细）
    -- - Shine：闪光效（粒子数、频率、缩放）
    -- - Proc：触发光效（持续时间）
    -- 包含 fadeOut 复选框和光效颜色选择器
    glowOptionsFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Cell.StylizeFrame(glowOptionsFrame, nil, Cell.GetAccentColorTable())
    glowOptionsFrame:SetFrameLevel(parent:GetFrameLevel()+50)
    glowOptionsFrame:Hide()

    glowOptionsFrame:SetWidth(274)
    glowOptionsFrame:SetPoint("TOP", 0, -73)
    glowOptionsFrame:SetPoint("RIGHT")

    local glowFadeOutCB = Cell.CreateCheckButton(glowOptionsFrame, L["fadeOut"], function(checked)
        spellTable[currentGlowIndex]["glow"]["fadeOut"] = checked
        Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
    end)
    glowFadeOutCB:SetPoint("TOPLEFT", 5, -10)

    local glowType = Cell.CreateDropdown(glowOptionsFrame, 117)
    glowType:SetLabel(L["Glow Type"])
    glowType:SetPoint("TOPLEFT", glowFadeOutCB, "BOTTOMLEFT", 0, -25)

    local glowColor = Cell.CreateColorPicker(glowOptionsFrame, L["Glow Color"], false, nil, function(r, g, b)
        spellTable[currentGlowIndex]["glow"]["options"][2][1] = r
        spellTable[currentGlowIndex]["glow"]["options"][2][2] = g
        spellTable[currentGlowIndex]["glow"]["options"][2][3] = b
        Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
    end)
    glowColor:SetPoint("LEFT", glowType, "RIGHT", 25, 0)

    -- glowNumber
    local glowLines = Cell.CreateSlider(L["Lines"], glowOptionsFrame, 1, 30, 117, 1, function(value)
        spellTable[currentGlowIndex]["glow"]["options"][3] = value
        Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
    end)
    glowLines:SetPoint("TOPLEFT", glowType, 0, -50)

    local glowParticles = Cell.CreateSlider(L["Particles"], glowOptionsFrame, 1, 30, 117, 1, function(value)
        spellTable[currentGlowIndex]["glow"]["options"][3] = value
        Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
    end)
    glowParticles:SetPoint("TOPLEFT", glowType, 0, -50)

    -- glowDuration
    local glowDuration = Cell.CreateSlider(L["Duration"], glowOptionsFrame, 0.1, 3, 117, 0.1, function(value)
        spellTable[currentGlowIndex]["glow"]["options"][3] = value
        Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
    end)
    glowDuration:SetPoint("TOPLEFT", glowType, 0, -50)

    -- glowFrequency
    local glowFrequency = Cell.CreateSlider(L["Frequency"], glowOptionsFrame, -2, 2, 117, 0.01, function(value)
        spellTable[currentGlowIndex]["glow"]["options"][4] = value
        Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
    end)
    glowFrequency:SetPoint("TOPLEFT", glowLines, "TOPRIGHT", 30, 0)

    -- glowLength
    local glowLength = Cell.CreateSlider(L["Length"], glowOptionsFrame, 1, 20, 117, 1, function(value)
        spellTable[currentGlowIndex]["glow"]["options"][5] = value
        Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
    end)
    glowLength:SetPoint("TOPLEFT", glowLines, "BOTTOMLEFT", 0, -40)

    -- glowThickness
    local glowThickness = Cell.CreateSlider(L["Thickness"], glowOptionsFrame, 1, 20, 117, 1, function(value)
        spellTable[currentGlowIndex]["glow"]["options"][6] = value
        Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
    end)
    glowThickness:SetPoint("TOPLEFT", glowLength, "TOPRIGHT", 30, 0)

    -- glowScale
    local glowScale = Cell.CreateSlider(L["Scale"], glowOptionsFrame, 50, 500, 117, 1, function(value)
        spellTable[currentGlowIndex]["glow"]["options"][5] = value
        Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
    end, nil, true)
    glowScale:SetPoint("TOPLEFT", glowLines, "BOTTOMLEFT", 0, -40)

    glowType:SetItems({
        {
            ["text"] = L["None"],
            ["value"] = "None",
            ["onClick"] = function()
                glowOptionsFrame:SetHeight(80)
                glowColor:SetColor({0.95,0.95,0.32,1})
                glowLines:Hide()
                glowParticles:Hide()
                glowDuration:Hide()
                glowFrequency:Hide()
                glowLength:Hide()
                glowThickness:Hide()
                glowScale:Hide()
                spellTable[currentGlowIndex]["glow"]["options"] = {"None", {0.95,0.95,0.32,1}}
                Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
            end,
        },
        {
            ["text"] = L["Normal"],
            ["value"] = "Normal",
            ["onClick"] = function()
                glowOptionsFrame:SetHeight(80)
                glowColor:SetColor({0.95,0.95,0.32,1})
                glowLines:Hide()
                glowParticles:Hide()
                glowDuration:Hide()
                glowFrequency:Hide()
                glowLength:Hide()
                glowThickness:Hide()
                glowScale:Hide()
                spellTable[currentGlowIndex]["glow"]["options"] = {"Normal", {0.95,0.95,0.32,1}}
                Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
            end,
        },
        {
            ["text"] = L["Pixel"],
            ["value"] = "Pixel",
            ["onClick"] = function()
                glowOptionsFrame:SetHeight(185)
                glowColor:SetColor({0.95,0.95,0.32,1})
                glowLines:Show()
                glowLines:SetValue(9)
                glowFrequency:Show()
                glowFrequency:SetValue(0.25)
                glowLength:Show()
                glowLength:SetValue(8)
                glowThickness:Show()
                glowThickness:SetValue(2)
                glowParticles:Hide()
                glowDuration:Hide()
                glowScale:Hide()
                spellTable[currentGlowIndex]["glow"]["options"] = {"Pixel", {0.95,0.95,0.32,1}, 9, 0.25, 8, 2}
                Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
            end,
        },
        {
            ["text"] = L["Shine"],
            ["value"] = "Shine",
            ["onClick"] = function()
                glowOptionsFrame:SetHeight(185)
                glowColor:SetColor({0.95,0.95,0.32,1})
                glowParticles:Show()
                glowParticles:SetValue(9)
                glowFrequency:Show()
                glowFrequency:SetValue(0.5)
                glowScale:Show()
                glowScale:SetValue(100)
                glowLines:Hide()
                glowDuration:Hide()
                glowLength:Hide()
                glowThickness:Hide()
                spellTable[currentGlowIndex]["glow"]["options"] = {"Shine", {0.95,0.95,0.32,1}, 9, 0.5, 1}
                Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
            end,
        },
        {
            ["text"] = L["Proc"],
            ["value"] = "Proc",
            ["onClick"] = function()
                glowOptionsFrame:SetHeight(135)
                glowColor:SetColor({0.95,0.95,0.32,1})
                glowDuration:Show()
                glowDuration:SetValue(1)
                glowParticles:Hide()
                glowFrequency:Hide()
                glowScale:Hide()
                glowLines:Hide()
                glowLength:Hide()
                glowThickness:Hide()
                spellTable[currentGlowIndex]["glow"]["options"] = {"Proc", {0.95,0.95,0.32,1}, 1}
                Cell.Fire("UpdateQuickAssist", currentGlowIndex.."-indicator")
            end,
        },
    })

    function glowOptionsFrame:Load(fadeOut, t)
        glowFadeOutCB:SetChecked(fadeOut)
        glowType:SetSelectedValue(t[1])
        glowColor:SetColor(t[2])

        if t[1] == "None" or t[1] == "Normal" then
            glowLines:Hide()
            glowParticles:Hide()
            glowDuration:Hide()
            glowFrequency:Hide()
            glowLength:Hide()
            glowThickness:Hide()
            glowScale:Hide()
            glowOptionsFrame:SetHeight(80)
        else
            if t[1] == "Pixel" then
                glowLines:Show()
                glowLines:SetValue(t[3])
                glowFrequency:Show()
                glowFrequency:SetValue(t[4])
                glowLength:Show()
                glowLength:SetValue(t[5])
                glowThickness:Show()
                glowThickness:SetValue(t[6])

                glowParticles:Hide()
                glowDuration:Hide()
                glowScale:Hide()
                glowOptionsFrame:SetHeight(185)

            elseif t[1] == "Shine" then
                glowParticles:Show()
                glowParticles:SetValue(t[3])
                glowFrequency:Show()
                glowFrequency:SetValue(t[4])
                glowScale:Show()
                glowScale:SetValue(t[5]*100)

                glowLines:Hide()
                glowDuration:Hide()
                glowLength:Hide()
                glowThickness:Hide()
                glowOptionsFrame:SetHeight(185)

            elseif t[1] == "Proc" then
                glowDuration:Show()
                glowDuration:SetValue(t[3])

                glowLines:Hide()
                glowParticles:Hide()
                glowFrequency:Hide()
                glowLength:Hide()
                glowScale:Hide()
                glowThickness:Hide()
                glowOptionsFrame:SetHeight(135)
            end
        end
    end

    glowOptionsFrame:SetScript("OnShow", function()
        currentGlowOptionBtn:SetFrameLevel(parent:GetFrameLevel()+50)
        Cell.CreateMask(Cell.frames.utilitiesTab, nil, {1, -1, -1, 1})
        F.Debug("|cff33937FQuickAssist_ShowGlowOptions:|r", currentGlowIndex)
    end)

    glowOptionsFrame:SetScript("OnHide", function()
        currentGlowOptionBtn:SetFrameLevel(currentGlowOptionBtn.frameLevel)
        barOptionsFrame:Hide()
        Cell.frames.utilitiesTab.mask:Hide()
    end)
end

local function SetGlowOptions_OnClick(b)
    -- 为光效设置按钮绑定点击事件：切换光效选项弹窗的显示/隐藏
    -- 显示时自动加载当前 fadeOut 和光效选项配置
    b.frameLevel = b:GetFrameLevel()
    b:SetScript("OnClick", function()
        currentGlowIndex = b.index
        currentGlowOptionBtn = b
        if glowOptionsFrame:IsShown() then
            glowOptionsFrame:Hide()
        else
            glowOptionsFrame:Show()
            glowOptionsFrame:Load(spellTable[currentGlowIndex]["glow"]["fadeOut"], spellTable[currentGlowIndex]["glow"]["options"])
        end
    end)
end

-- my buff --------------------------------------------------------------- --
local function CreateMyBuffWidget(parent, index)
    -- 创建单个"我的增益"配置控件，包含：
    -- - 左键点击：弹出法术ID输入框，设置该槽位监控的法术
    -- - 右键点击：清除该槽位
    -- - 鼠标悬停：显示法术提示信息
    -- - 类型下拉框：切换 Icon（图标）或 Bar（计时条）显示方式
    -- - 颜色选择器：设置该增益的颜色标记
    local b = Cell.CreateButton(parent, " ", "accent-hover", {180, 20})
    b:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create", {16, 16}, {"LEFT", 2, 0})
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:GetFontString():SetJustifyH("LEFT")

    b:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            -- 左键：弹出输入框，输入法术ID来设置该槽位监控的法术
            local popup = Cell.CreatePopupEditBox(qaPane, function(text)
                local spellId = tonumber(text)
                local spellName, spellIcon = F.GetSpellInfo(spellId)

                if spellId and spellName then
                    b.id = spellId
                    b.icon = spellIcon
                    b:SetText(spellName)
                    b.tex:SetTexture(spellIcon)
                    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    spellTable["mine"]["buffs"][index][1] = spellId
                    Cell.Fire("UpdateQuickAssist", "mine")
                else
                    F.Print(L["Invalid spell id."])
                end
            end)
            popup:ClearAllPoints()
            popup:SetAllPoints(b)
            popup:ShowEditBox("")
            popup:SetTips("|cffababab"..L["Input spell id"])
        else
            -- 右键：清除该槽位的法术设置
            b.icon = nil
            b:SetText("")
            b.tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create")
            b.tex:SetTexCoord(0, 1, 0, 1)
            spellTable["mine"]["buffs"][index][1] = 0
            Cell.Fire("UpdateQuickAssist", "mine")
        end
    end)

    -- 鼠标悬停时显示法术提示信息
    b:HookScript("OnEnter", function(self)
        if self.id and self.icon then
            CellSpellTooltip:SetOwner(self, "ANCHOR_NONE")
            CellSpellTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
            CellSpellTooltip:SetSpellByID(self.id, self.icon)
            CellSpellTooltip:Show()
        end
    end)

    b:HookScript("OnLeave", function(self)
        CellSpellTooltip:Hide()
    end)

    b.type = Cell.CreateDropdown(b, 55, nil, true)
    b.type:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 2)
    -- P.Height(b.type, 17)
    b.type:SetItems({
        {
            ["text"] = L["Icon"],
            ["value"] = "icon",
            ["onClick"] = function()
                spellTable["mine"]["buffs"][index][2] = "icon"
                Cell.Fire("UpdateQuickAssist", "mine")
                b.cp:EnableAlpha(true)
                b.cp:SetColor(spellTable["mine"]["buffs"][index][3])
            end
        },
        {
            ["text"] = L["Bar"],
            ["value"] = "bar",
            ["onClick"] = function()
                spellTable["mine"]["buffs"][index][2] = "bar"
                spellTable["mine"]["buffs"][index][3][4] = 1 -- reset alpha
                Cell.Fire("UpdateQuickAssist", "mine")
                b.cp:EnableAlpha(false)
                b.cp:SetColor(spellTable["mine"]["buffs"][index][3])
            end
        },
    })

    b.cp = Cell.CreateColorPicker(b, "", false, function(r, g, b, a)
        spellTable["mine"]["buffs"][index][3][1] = r
        spellTable["mine"]["buffs"][index][3][2] = g
        spellTable["mine"]["buffs"][index][3][3] = b
        spellTable["mine"]["buffs"][index][3][4] = a
        Cell.Fire("UpdateQuickAssist", "mine")
    end)
    b.cp:SetPoint("BOTTOMLEFT", b.type, "BOTTOMRIGHT", 2, 3)

    return b
end

local function CreateSpellsPane()
    -- 创建法术监控配置页面，包含两大区域：
    -- 左侧：自身增益追踪器（5个槽位，每个可配置法术ID、显示类型、颜色）
    -- 右侧：爆发法术追踪器（按职业分类的增益/施法列表，支持添加/删除/排序）
    -- 底部包含重置按钮和首次使用帮助提示面板
    pages.spell = CreateFrame("Frame", nil, quickAssistTab)
    pages.spell:SetAllPoints(setupPane)
    pages.spell:Hide()

    CreateIconOptions(pages.spell)
    CreateBarOptions(pages.spell)
    CreateGlowOptions(pages.spell)

    --* buff tracker ---------------------------------------------------------- --
    local myIconsBtn = Cell.CreateButton(pages.spell, L["Icons"], "accent-hover", {80, 20})
    myIconsBtn:SetPoint("TOPLEFT", 5, -42)
    myIconsBtn.index = "mine"
    SetIconOptions_OnClick(myIconsBtn)

    local myBarsBtn = Cell.CreateButton(pages.spell, L["Bars"], "accent-hover", {80, 20})
    myBarsBtn:SetPoint("TOPLEFT", myIconsBtn, "TOPRIGHT", P.Scale(-1), 0)
    myBarsBtn.index = "mine"
    SetBarOptions_OnClick(myBarsBtn)

    local buffTrackerText = pages.spell:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    buffTrackerText:SetPoint("BOTTOMLEFT", myIconsBtn, "TOPLEFT", 0, 1)
    buffTrackerText:SetText(L["Buffs Tracker"].." ("..L["mine"]..")")

    for i = 1, 5 do
        myBuffWidgets[i] = CreateMyBuffWidget(pages.spell, i)
        if i == 1 then
            myBuffWidgets[i]:SetPoint("TOPLEFT", myIconsBtn, 0, -60)
        else
            myBuffWidgets[i]:SetPoint("TOPLEFT", myBuffWidgets[i-1], 0, -57)
        end
    end

    --* offensives tracker ---------------------------------------------------- --
    local offensiveIconsBtn = Cell.CreateButton(pages.spell, L["Icons"], "accent-hover", {80, 20})
    offensiveIconsBtn:SetPoint("TOPLEFT", 222, -42)
    offensiveIconsBtn.index = "offensives"
    SetIconOptions_OnClick(offensiveIconsBtn)

    local offensiveGlowsBtn = Cell.CreateButton(pages.spell, L["Glows"], "accent-hover", {80, 20})
    offensiveGlowsBtn:SetPoint("TOPLEFT", offensiveIconsBtn, "TOPRIGHT", P.Scale(-1), 0)
    offensiveGlowsBtn.index = "offensives"
    SetGlowOptions_OnClick(offensiveGlowsBtn)

    local offensivesTrackerText = pages.spell:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    offensivesTrackerText:SetPoint("BOTTOMLEFT", offensiveIconsBtn, "TOPLEFT", 0, 1)
    offensivesTrackerText:SetText(L["Offensives Tracker"])

    offensivesEnabledCB = Cell.CreateCheckButton(pages.spell, L["Enabled"], function(checked)
        spellTable["offensives"]["enabled"] = checked
        Cell.Fire("UpdateQuickAssist", "offensives")
    end)
    offensivesEnabledCB:SetPoint("TOPLEFT", offensiveIconsBtn, "BOTTOMLEFT", 0, -12)

    for class, _, i in F.IterateClasses() do
        classButtons[i] = Cell.CreateButton(pages.spell, nil, "accent-hover", {24, 24})
        classButtons[i].id = class
        classButtons[i]:SetTexture("classicon-"..strlower(class), {20, 20}, {"CENTER", 0, 0}, true)
        classButtons[i].tex:SetDesaturated(true)

        classButtons[i].hoverColor = {F.GetClassColor(class)}

        -- classButtons[i].ShowTooltip = function()
        --     CellTooltip:SetOwner(classButtons[i], "ANCHOR_NONE")
        --     CellTooltip:SetPoint("BOTTOMLEFT", classButtons[i], "TOPLEFT", 0, 1)
        --     CellTooltip:AddLine(F.GetClassColorStr(class)..F.GetLocalizedClassName(class))
        --     CellTooltip:Show()
        -- end
        -- classButtons[i].HideTooltip = function()
        --     CellTooltip:Hide()
        -- end

        if i == 1 then
            classButtons[i]:SetPoint("TOPLEFT", offensiveIconsBtn, 0, -60)
        elseif i % 7 == 1 then
            classButtons[i]:SetPoint("TOPLEFT", classButtons[i-7], "BOTTOMLEFT", 0, -2)
        else
            classButtons[i]:SetPoint("TOPLEFT", classButtons[i-1], "TOPRIGHT", 2, 0)
        end
    end

    Cell.CreateButtonGroup(classButtons, function(class, b)
        selectedClass = class
        LoadList(buffsPane, buffButtons, buffsAddBtn, spellTable["offensives"]["buffs"][selectedClass] or {})
        LoadList(castsPane, castButtons, castsAddBtn, spellTable["offensives"]["casts"][selectedClass] or {}, ":")
    end, function(_, b)
        b.tex:SetDesaturated(false)
        b:SetBackdropBorderColor(F.GetClassColor(b.id))
    end, function(_, b)
        b.tex:SetDesaturated(true)
        b:SetBackdropBorderColor(0, 0, 0, 1)
    end)

    --* buffs ----------------------------------------------------------------- --
    buffsPane = Cell.CreateTitledPane(pages.spell, L["Buffs"], 205, 85)
    buffsPane:SetPoint("TOPLEFT", 217, -165)
    Cell.CreateTipsButton(buffsPane, 17, "BOTTOMRIGHT", "UNIT_AURA")

    buffsAddBtn = Cell.CreateButton(buffsPane, nil, "accent-hover", {24, 24})
    buffsAddBtn:SetPoint("TOPLEFT", 5, -27)
    buffsAddBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create", {20, 20}, {"CENTER", 0, 0})
    buffsAddBtn:SetScript("OnClick", function()
        -- 添加爆发增益：弹出法术ID输入框，验证后加入当前职业的 buffs 列表
        local popup = Cell.CreatePopupEditBox(qaPane, function(text)
            local spellId = tonumber(text)
            local spellName = F.GetSpellInfo(spellId)
            if spellId and spellName then
                if not spellTable["offensives"]["buffs"][selectedClass] then
                    spellTable["offensives"]["buffs"][selectedClass] = {}
                end
                tinsert(spellTable["offensives"]["buffs"][selectedClass], spellId)
                LoadList(buffsPane, buffButtons, buffsAddBtn, spellTable["offensives"]["buffs"][selectedClass])
                Cell.Fire("UpdateQuickAssist", "offensives")
            else
                F.Print(L["Invalid spell id."])
            end
        end)
        popup:ClearAllPoints()
        popup:SetPoint("LEFT", buffsPane, 5, 0)
        popup:SetPoint("RIGHT", buffsPane, -4, 0)
        popup:SetPoint("TOP", buffsAddBtn)
        popup:ShowEditBox("")
        popup:SetTips("|cffababab"..L["Input spell id"])
    end)

    --* casts ----------------------------------------------------------------- --
    castsPane = Cell.CreateTitledPane(pages.spell, L["Casts"], 205, 85)
    castsPane:SetPoint("TOPLEFT", 217, -265)
    Cell.CreateTipsButton(castsPane, 17, "BOTTOMRIGHT", "UNIT_SPELLCAST_SUCCEEDED")

    castsAddBtn = Cell.CreateButton(castsPane, nil, "accent-hover", {24, 24})
    castsAddBtn:SetPoint("TOPLEFT", 5, -27)
    castsAddBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create", {20, 20}, {"CENTER", 0, 0})
    castsAddBtn:SetScript("OnClick", function()
        -- 添加爆发施法：弹出双输入框（法术ID + 持续时间），验证后加入当前职业的 casts 列表
        local popup = Cell.CreateDualPopupEditBox(qaPane, "ID", L["Duration"], true, function(spellId, duration)
            local spellName = F.GetSpellInfo(spellId)
            if spellId and spellName and duration then
                if not spellTable["offensives"]["casts"][selectedClass] then
                    spellTable["offensives"]["casts"][selectedClass] = {}
                end
                tinsert(spellTable["offensives"]["casts"][selectedClass], spellId..":"..duration)
                LoadList(castsPane, castButtons, castsAddBtn, spellTable["offensives"]["casts"][selectedClass], ":")
                Cell.Fire("UpdateQuickAssist", "offensives")
            else
                F.Print(L["Invalid"])
            end
        end)
        popup.left:SetWidth(P.Scale(90))
        popup:SetPoint("LEFT", castsPane, 5, 0)
        popup:SetPoint("RIGHT", castsPane, -4, 0)
        popup:SetPoint("TOP", castsAddBtn)
        popup:ShowEditBox()
    end)

    -- reset ----------------------------------------------------------------- --
    local resetBtn = Cell.CreateButton(pages.spell, L["Reset Offensive Spells"], "accent", {205, 17}, nil, nil, nil, nil, nil, L["Reset Offensive Spells"], L["[Ctrl+Left-Click] to reset these settings"])
    resetBtn:SetPoint("BOTTOMRIGHT")
    resetBtn:SetScript("OnClick", function()
        -- Ctrl+点击重置爆发法术列表为默认值，并刷新UI
        if IsControlKeyDown() then
            spellTable["offensives"]["buffs"] = F.Copy(defaultOffensiveBuffs)
            spellTable["offensives"]["casts"] = F.Copy(defaultOffensiveCasts)
            classButtons[1]:GetScript("OnClick")()
            Cell.Fire("UpdateQuickAssist", "offensives")
        end
    end)

    -- tips ------------------------------------------------------------------ --
    local tip1 = pages.spell:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    tip1:SetText("|cffababab"..L["Tip: right-click to delete"])
    tip1:SetPoint("BOTTOMLEFT")

    if not CellDB["quickAssistHelpViewed"] then
        local helpFrame = CreateFrame("Frame", nil, pages.spell, "BackdropTemplate")
        helpFrame:SetAllPoints(pages.spell)
        helpFrame:SetHeight(310)
        helpFrame:EnableMouse(true)
        helpFrame:SetFrameLevel(pages.spell:GetFrameLevel()+25)
        Cell.StylizeFrame(helpFrame, {0.1, 0.1, 0.1, 0.99})

        local helpText = helpFrame:CreateFontString(nil, "OVERLAY")
        helpText:SetFont(UNIT_NAME_FONT_CHINESE, 12 + CellDB["appearance"]["optionsFontSizeOffset"], "")
        helpText:SetTextColor(1, 1, 1, 1)
        helpText:SetShadowColor(0, 0, 0)
        helpText:SetShadowOffset(1, -1)
        helpText:SetText([[
|cffe52b50It's better to use OmniCD to track offensive CDs|r
|cff00ff7fBut if you'd like to contribute to built-in offensive list:|r
1. open |cfffff2b2Cell\Utilities\QuickAssistConfig.lua|r
2. edit |cfffff2b2defaultOffensiveBuffs|r and |cfffff2b2defaultOffensiveCasts|r
3. create a PR on GitHub
*. fill the list by pressing "Reset Offensive Spells" button

|cffe52b50用 OmniCD 来监控爆发是更好的选择|r
|cff00ff7f但如果你想要帮忙补充内置爆发法术列表：|r
1. 打开 |cfffff2b2Cell\Utilities\QuickAssistConfig.lua|r
2. 修改 |cfffff2b2defaultOffensiveBuffs|r 和 |cfffff2b2defaultOffensiveCasts|r
3. 在 GitHub 上提交 PR
*. 点击“重置爆发法术”按钮来刷新列表
        ]])
        helpText:SetPoint("LEFT", 10, 0)
        helpText:SetPoint("RIGHT", -10, 0)
        helpText:SetJustifyH("LEFT")
        helpText:SetSpacing(5)

        local helpBtn = Cell.CreateButton(helpFrame, "OK", "accent", {205, 20})
        helpBtn:SetPoint("BOTTOMLEFT")
        helpBtn:SetPoint("BOTTOMRIGHT")
        helpBtn:SetScript("OnClick", function()
            helpFrame:Hide()
            CellDB["quickAssistHelpViewed"] = true
        end)
    end
end

-- ----------------------------------------------------------------------- --
--                                   load                                  --
-- ----------------------------------------------------------------------- --
ShowFilter = function(index)
    -- 显示指定编号的过滤器控件
    -- 根据过滤器类型（role/class/spec/name）显示对应的控件并隐藏其他类型的控件
    -- role 模式下显示职责按钮；class/spec 模式下额外显示重置按钮和拖拽提示
    -- name 模式下隐藏"隐藏自己"复选框，显示名字输入按钮
    local t = quickAssistTable["filters"][index]

    filterTypeDropdown:SetSelectedValue(t[1])
    hideSelfCB:SetChecked(t[3])

    roleFilter:Hide()
    classFilter:Hide()
    specFilter:Hide()
    nameFilter:Hide()
    nameListFrame:Hide()
    filterResetBtn:Hide()
    filterResetTips:Hide()

    if t[1] == "role" then
        roleFilter:SetRoles(t[2])
        roleFilter:Show()
        hideSelfCB:Show()
        hideSelfCB:SetText(L["Hide Self"].." ("..L["Party"]..")")
    elseif t[1] == "class" then
        classFilter:SetClasses(t[2])
        classFilter:Show()
        hideSelfCB:Show()
        filterResetBtn:Show()
        filterResetTips:Show()
        hideSelfCB:SetText(L["Hide Self"].." ("..L["Party"]..")")
    elseif t[1] == "spec" then
        specFilter:SetSpecs(t[2])
        specFilter:Show()
        hideSelfCB:Show()
        filterResetBtn:Show()
        filterResetTips:Show()
        hideSelfCB:SetText(L["Hide Self"])
    elseif t[1] == "name" then
        nameFilter:Show()
        hideSelfCB:Hide()
    end
end

LoadAutoSwitch = function(t)
    -- 加载过滤器自动切换下拉框的当前值
    -- 为每种队伍类型（party/raid/mythic/arena/battleground）设置对应的过滤器编号
    partyDropdown:SetSelectedValue(t["party"])
    raidDropdown:SetSelectedValue(t["raid"])
    mythicDropdown:SetSelectedValue(t["mythic"])
    arenaDropdown:SetSelectedValue(t["arena"])
    bgDropdown:SetSelectedValue(t["battleground"])
end

LoadLayout = function()
    -- 从 layoutTable 加载所有布局控件的当前值
    anchorDropdown:SetSelectedValue(layoutTable["anchor"])
    orientationDropdown:SetSelectedValue(layoutTable["orientation"])

    if layoutTable["orientation"] == "horizontal" then
        unitsSlider:SetLabel(L["Units Per Row"])
        maxSlider:SetLabel(L["Max Rows"])
    else
        unitsSlider:SetLabel(L["Units Per Column"])
        maxSlider:SetLabel(L["Max Columns"])
    end

    widthSlider:SetValue(layoutTable["size"][1])
    heightSlider:SetValue(layoutTable["size"][2])

    xSlider:SetValue(layoutTable["spacingX"])
    ySlider:SetValue(layoutTable["spacingY"])

    unitsSlider:SetValue(layoutTable["unitsPerColumn"])
    maxSlider:SetValue(layoutTable["maxColumns"])
end

LoadStyle = function()
    -- 从 styleTable 加载所有样式控件的当前值（纹理、颜色、透明度、名字文本等）
    textureDropdown:SetSelected(styleTable["texture"], textures[styleTable["texture"]])
    hpColorDropdown:SetSelectedValue(styleTable["hpColor"][1])
    lossColorDropdown:SetSelectedValue(styleTable["lossColor"][1])
    if styleTable["hpColor"][1] == "custom" then hpCP:Show() else hpCP:Hide() end
    hpCP:SetColor(styleTable["hpColor"][2])
    if styleTable["lossColor"][1] == "custom" then bgCP:Show() else bgCP:Hide() end
    bgCP:SetColor(styleTable["lossColor"][2])
    alphaSlider:SetValue(styleTable["oorAlpha"]*100)

    targetColorPicker:SetColor(styleTable["targetColor"])
    mouseoverColorPicker:SetColor(styleTable["mouseoverColor"])
    highlightSizeSlider:SetValue(styleTable["highlightSize"])

    nameColorDropdown:SetSelectedValue(styleTable["name"]["color"][1])
    nameWidth:SetNameWidth(styleTable["name"]["width"])
    if styleTable["name"]["color"][1] == "custom" then nameCP:Show() else nameCP:Hide() end
    nameCP:SetColor(styleTable["name"]["color"][2])
    nameAnchorDropdown:SetSelectedValue(styleTable["name"]["position"][1])
    nameXSlider:SetValue(styleTable["name"]["position"][2])
    nameYSlider:SetValue(styleTable["name"]["position"][3])
    nameFontDropdown:SetFont(styleTable["name"]["font"][1])
    nameSizeSilder:SetValue(styleTable["name"]["font"][2])
    nameOutlineDropdown:SetSelectedValue(styleTable["name"]["font"][3])
    nameShadowCB:SetChecked(styleTable["name"]["font"][4])
end

LoadMyBuff = function(b, t)
    -- 加载单个"我的增益"槽位的配置到控件
    -- t[1]=0 表示未设置；否则加载法术名称、图标、显示类型和颜色
    b.id = nil
    b.icon = nil

    if t[1] == 0 then -- no setting: 法术ID为0表示未配置
        b:SetText("")
        b.tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create")
        b.tex:SetTexCoord(0, 1, 0, 1)
    else
        local name, icon = F.GetSpellInfo(t[1])
        if name and icon then
            b:SetText(name)
            b.tex:SetTexture(icon)
            b.id = t[1]
            b.icon = icon
        else
            b:SetText("|cffff2222"..L["Invalid"])
            b.tex:SetTexture(134400)
        end
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    b.type:SetSelectedValue(t[2])
    b.cp:SetColor(t[3])
    b.cp:EnableAlpha(t[2] == "icon")
end

-- list shared
local BUTTONS_SIZE = 24
local BUTTONS_PER_ROW = 7
local BUTTONS_SPACING = 2
local BUTTONS_MAX = 14

LoadList = function(parent, buttons, addBtn, t, separator)
    -- 加载爆发法术列表（增益/施法）到按钮网格
    -- 按钮动态创建，最多 BUTTONS_MAX 个；点击右键删除对应法术
    -- separator 参数用于区分纯增益（无分隔符）和施法（用":"分隔ID和持续时间）
    for i, id in pairs(t) do
        if not buttons[i] then
            buttons[i] = Cell.CreateButton(parent, nil, "accent-hover", {BUTTONS_SIZE, BUTTONS_SIZE})
            buttons[i]:RegisterForClicks("RightButtonUp")

            buttons[i]:SetTexture(134400, {BUTTONS_SIZE-4, BUTTONS_SIZE-4}, {"CENTER", 0, 0})
            buttons[i].tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            if separator then
                buttons[i].duration = buttons[i]:CreateFontString(nil, "OVERLAY")
                buttons[i].duration:SetFont(GameFontNormal:GetFont(), 12, "OUTLINE")
                buttons[i].duration:SetTextColor(1, 1, 1, 1)
                buttons[i].duration:SetShadowColor(0, 0, 0, 0)
                buttons[i].duration:SetShadowOffset(0, 0)
                buttons[i].duration:SetJustifyH("CENTER")
                buttons[i].duration:SetPoint("BOTTOMRIGHT")
            end

            buttons[i]:HookScript("OnEnter", function(self)
                if self.id and self.icon then
                    CellSpellTooltip:SetOwner(self, "ANCHOR_NONE")
                    CellSpellTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
                    CellSpellTooltip:SetSpellByID(self.id, self.icon)
                    CellSpellTooltip:Show()
                end
            end)

            buttons[i]:HookScript("OnLeave", function(self)
                CellSpellTooltip:Hide()
            end)

        end

        buttons[i]:SetScript("OnClick", function()
            tremove(t, i)
            LoadList(parent, buttons, addBtn, t, separator)
            Cell.Fire("UpdateQuickAssist", "offensives")
        end)

        if separator then
            local duration
            id, duration = strsplit(separator, id)
            buttons[i].duration:SetText(duration)
        end

        local name, icon = F.GetSpellInfo(id)
        if not name then icon = 134400 end
        buttons[i].id = id
        buttons[i].icon = icon

        buttons[i].tex:SetTexture(icon)

        buttons[i]:ClearAllPoints()
        if i == 1 then
            buttons[i]:SetPoint("TOPLEFT", 5, -27)
        elseif (i - 1) % BUTTONS_PER_ROW == 0 then
            buttons[i]:SetPoint("TOPLEFT", buttons[i-BUTTONS_PER_ROW], "BOTTOMLEFT", 0, -BUTTONS_SPACING)
        else
            buttons[i]:SetPoint("TOPLEFT", buttons[i-1], "TOPRIGHT", BUTTONS_SPACING, 0)
        end

        buttons[i]:Show()
    end

    local n = #t

    -- hide
    for i = n+1, #buttons do
        buttons[i]:Hide()
    end

    -- update add button
    if n == BUTTONS_MAX then --max
        addBtn:Hide()
    else
        addBtn:ClearAllPoints()
        if n == 0 then
            addBtn:SetPoint("TOPLEFT", 5, -27)
        elseif n % BUTTONS_PER_ROW == 0 then
            addBtn:SetPoint("TOPLEFT", buttons[n-BUTTONS_PER_ROW+1], "BOTTOMLEFT", 0, -BUTTONS_SPACING)
        else
            addBtn:SetPoint("TOPLEFT", buttons[n], "TOPRIGHT", BUTTONS_SPACING, 0)
        end
        addBtn:Show()
    end
end

LoadSpells = function()
    -- 加载所有法术配置：5个"我的增益"槽位、爆发法术列表和启用状态
    for i = 1, 5 do
        LoadMyBuff(myBuffWidgets[i], spellTable["mine"]["buffs"][i])
    end

    classButtons[1]:GetScript("OnClick")()
    offensivesEnabledCB:SetChecked(spellTable["offensives"]["enabled"])
end

LoadDB = function()
    -- 从 CellDB 加载当前专精的 QuickAssist 配置表，然后分别加载各子配置到UI控件
    -- 如果未启用则禁用所有控件并返回
    quickAssistTable = CellDB["quickAssist"][Cell.vars.playerSpecID]

    if not quickAssistTable or not quickAssistTable["enabled"] then
        qaEnabledCB:SetChecked(false)
        UpdateWidgets(false)
        layoutTable = nil
        styleTable = nil
        spellTable = nil
        return
    end

    layoutTable = quickAssistTable["layout"]
    styleTable = quickAssistTable["style"]
    spellTable = quickAssistTable["spells"]

    -- update before all loads
    UpdateWidgets(quickAssistTable["enabled"])

    qaEnabledCB:SetChecked(quickAssistTable["enabled"])

    LoadLayout()
    LoadStyle()
    LoadSpells()

    selectedFilter = Cell.vars.quickAssistGroupType and quickAssistTable["filterAutoSwitch"][Cell.vars.quickAssistGroupType] or 0
    if selectedFilter == 0 then selectedFilter = 1 end
    HighlightFilter(selectedFilter)
    ShowFilter(selectedFilter)
    LoadAutoSwitch(quickAssistTable["filterAutoSwitch"])
    UpdateAutoSwitch()
end

local init
local function ShowUtilitySettings(which)
    -- 响应 ShowUtilitySettings 回调：显示/隐藏 QuickAssist 配置选项卡
    -- 首次调用时延迟创建所有子面板（延迟初始化以减少加载时性能开销）
    -- which == "quickAssist" 时显示，否则隐藏
    if which == "quickAssist" then
        if not init then
            CreateQuickAssistPane()
            CreateSetupPane()
            CreateLayoutPane()
            CreateStylePane()
            CreateSpellsPane()
            CreateAutoSwitchFrame()

            F.ApplyCombatProtectionToFrame(quickAssistTab)
            F.ApplyCombatProtectionToFrame(autoSwitchFrame)
        end

        if not init then
            init = true
            layoutBtn:GetScript("OnClick")()
        end
        LoadDB()
        quickAssistTab:Show()
        UpdatePreviewButton()

    elseif init then
        quickAssistTab:Hide()
    end
end
-- 注册回调：当用户点击 QuickAssist 工具标签时显示/隐藏配置面板
Cell.RegisterCallback("ShowUtilitySettings", "QuickAssist_ShowUtilitySettings", ShowUtilitySettings)

local function Reload()
    -- 响应专精切换或 ReloadQuickAssist 事件：重新加载配置并更新UI
    -- 如果配置页面可见，根据启用状态决定是否显示布局预览
    if init then
        LoadDB()
        UpdatePreviewButton()
        layoutBtn:GetScript("OnClick")()
        if quickAssistTab:IsVisible() then
            if quickAssistTable and quickAssistTable["enabled"] then
                ShowLayoutPreview()
            else
                HideLayoutPreview()
            end
        end
    end
end
-- 注册回调：专精切换时重新加载配置
Cell.RegisterCallback("SpecChanged", "QuickAssistConfig_SpecChanged", Reload)
-- 注册回调：外部模块请求重载 QuickAssist 配置时响应
Cell.RegisterCallback("ReloadQuickAssist", "ReloadQuickAssist", Reload)

UpdateAutoSwitch = function()
    -- 响应 UpdateQuickAssist 事件：根据当前队伍类型自动切换激活的过滤器
    -- 从 filterAutoSwitch 配置中读取当前队伍类型对应的过滤器编号
    -- 更新星号(*)标记到当前队伍类型的标签旁，并用高亮色标记当前队伍类型文本
    if not (init and quickAssistTable and quickAssistTable["enabled"]) then return end

    activeFilter = Cell.vars.quickAssistGroupType and quickAssistTable["filterAutoSwitch"][Cell.vars.quickAssistGroupType] or 0

    if activeFilter == 0 then
        -- 配置为"隐藏"时默认使用过滤器 I
        filterButtons[1]:GetScript("OnClick")()
        selectedFilter = 1
    else
        filterButtons[activeFilter]:GetScript("OnClick")()
        selectedFilter = activeFilter
    end

    asterisk:ClearAllPoints()
    if Cell.vars.quickAssistGroupType == "party" then
        asterisk:SetPoint("LEFT", partyText, "RIGHT")
        partyText:SetTextColor(Cell.GetAccentColorRGB())
        raidText:SetTextColor(1, 1, 1)
        mythicText:SetTextColor(1, 1, 1)
        arenaText:SetTextColor(1, 1, 1)
        bgText:SetTextColor(1, 1, 1)
    elseif Cell.vars.quickAssistGroupType == "raid" then
        asterisk:SetPoint("LEFT", raidText, "RIGHT")
        partyText:SetTextColor(1, 1, 1)
        raidText:SetTextColor(Cell.GetAccentColorRGB())
        mythicText:SetTextColor(1, 1, 1)
        arenaText:SetTextColor(1, 1, 1)
        bgText:SetTextColor(1, 1, 1)
    elseif Cell.vars.quickAssistGroupType == "mythic" then
        asterisk:SetPoint("LEFT", mythicText, "RIGHT")
        partyText:SetTextColor(1, 1, 1)
        raidText:SetTextColor(1, 1, 1)
        mythicText:SetTextColor(Cell.GetAccentColorRGB())
        arenaText:SetTextColor(1, 1, 1)
        bgText:SetTextColor(1, 1, 1)
    elseif Cell.vars.quickAssistGroupType == "arena" then
        asterisk:SetPoint("LEFT", arenaText, "RIGHT")
        partyText:SetTextColor(1, 1, 1)
        raidText:SetTextColor(1, 1, 1)
        mythicText:SetTextColor(1, 1, 1)
        arenaText:SetTextColor(Cell.GetAccentColorRGB())
        bgText:SetTextColor(1, 1, 1)
    elseif Cell.vars.quickAssistGroupType == "battleground" then
        asterisk:SetPoint("LEFT", bgText, "RIGHT")
        partyText:SetTextColor(1, 1, 1)
        raidText:SetTextColor(1, 1, 1)
        mythicText:SetTextColor(1, 1, 1)
        arenaText:SetTextColor(1, 1, 1)
        bgText:SetTextColor(Cell.GetAccentColorRGB())
    else -- solo
        partyText:SetTextColor(1, 1, 1)
        raidText:SetTextColor(1, 1, 1)
        mythicText:SetTextColor(1, 1, 1)
        arenaText:SetTextColor(1, 1, 1)
        bgText:SetTextColor(1, 1, 1)
    end
end
-- 注册回调：QuickAssist 配置变更时更新自动切换状态（星号标记和颜色高亮）
Cell.RegisterCallback("UpdateQuickAssist", "UpdateAutoSwitch", UpdateAutoSwitch)
