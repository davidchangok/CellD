local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 职责过滤面板：挂在布局Tab上的弹出式浮层，用于按职业和职责筛选单位框体显示
local powerFilters = Cell.CreateFrame("CellOptionsFrame_PowerFilters", Cell.frames.layoutsTab, 285, 205)
Cell.frames.powerFilters = powerFilters
-- 将面板层级提升至布局Tab之上，确保浮层不被遮挡
powerFilters:SetFrameLevel(Cell.frames.layoutsTab:GetFrameLevel() + 50)

local selectedLayout, selectedLayoutTable

-- ======================================
-- 职业-职责映射表 (CLASS_ROLES)
-- 定义各职业在不同资料片版本中可担任的职责。
-- TBC/Vanilla 时代所有职业表中有全部三种职责（实际可选与否由后续按钮控制）。
-- 正式服/其他版本则按实际游戏内置的职业职责分布严格定义。
-- ======================================
local CLASS_ROLES
if Cell.isTBC or Cell.isVanilla then
    CLASS_ROLES = {
        ["DRUID"] = {"TANK", "HEALER", "DAMAGER"},
        ["HUNTER"] = {"TANK", "HEALER", "DAMAGER"},
        ["MAGE"] = {"TANK", "HEALER", "DAMAGER"},
        ["PALADIN"] = {"TANK", "HEALER", "DAMAGER"},
        ["PRIEST"] = {"TANK", "HEALER", "DAMAGER"},
        ["ROGUE"] = {"TANK", "HEALER", "DAMAGER"},
        ["SHAMAN"] = {"TANK", "HEALER", "DAMAGER"},
        ["WARLOCK"] = {"TANK", "HEALER", "DAMAGER"},
        ["WARRIOR"] = {"TANK", "HEALER", "DAMAGER"},
        ["PET"] = {"DAMAGER"},
        ["VEHICLE"] = {"DAMAGER"},
        ["NPC"] = {"DAMAGER"},
    }
else
    CLASS_ROLES = {
        ["DEATHKNIGHT"] = {"TANK", "DAMAGER"},
        ["DEMONHUNTER"] = {"TANK", "DAMAGER"},
        ["DRUID"] = {"TANK", "HEALER", "DAMAGER"},
        ["EVOKER"] = {"HEALER", "DAMAGER"},
        ["HUNTER"] = {"DAMAGER"},
        ["MAGE"] = {"DAMAGER"},
        ["MONK"] = {"TANK", "HEALER", "DAMAGER"},
        ["PALADIN"] = {"TANK", "HEALER", "DAMAGER"},
        ["PRIEST"] = {"HEALER", "DAMAGER"},
        ["ROGUE"] = {"DAMAGER"},
        ["SHAMAN"] = {"HEALER", "DAMAGER"},
        ["WARLOCK"] = {"DAMAGER"},
        ["WARRIOR"] = {"TANK", "DAMAGER"},
        ["PET"] = {"DAMAGER"},
        ["VEHICLE"] = {"DAMAGER"},
        ["NPC"] = {"DAMAGER"},
    }
end

-- ======================================
-- UpdateButton(b, enabled)
-- 更新职责按钮的视觉状态：
--   enabled=true  → 按钮激活（彩色），禁用鼠标悬停效果
--   enabled=false → 按钮未激活（去饱和），恢复鼠标悬停变色
-- ======================================
local function UpdateButton(b, enabled)
    b.tex:SetDesaturated(not enabled)
    if enabled then
        b:SetBackdropColor(unpack(b.hoverColor))
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
    else
        b:SetBackdropColor(unpack(b.color))
        b:SetScript("OnEnter", function()
            b:SetBackdropColor(unpack(b.hoverColor))
        end)
        b:SetScript("OnLeave", function()
            b:SetBackdropColor(unpack(b.color))
        end)
    end
end

-- ======================================
-- CreatePowerFilter(parent, class, buttons, color, bgColor)
-- 为一个职业创建职责过滤条，包含：
--   - 职业名称标签（玩家职业用职业色，特殊单位用绿色）
--   - 右侧排列的职责图标按钮（TANK/HEALER/DAMAGER）
-- 每个职责按钮点击后会切换对应职责的过滤状态并立即生效。
-- 返回值 filter 上附带 :Load() 方法，用于从数据库恢复按钮状态。
-- ======================================
local function CreatePowerFilter(parent, class, buttons, color, bgColor)
    local filter = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Cell.StylizeFrame(filter, color, bgColor)
    P.Size(filter, 135, 20)

    filter.text = filter:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    filter.text:SetPoint("LEFT", 5, 0)
    -- 职业名称标签：特殊单位（载具/宠物/NPC）用亮绿色，玩家职业用对应职业色
    if class == "VEHICLE" or class == "PET" or class == "NPC" then
        filter.text:SetText("|cff00ff33"..L[class])
    else
        filter.text:SetText(F.GetClassColorStr(class)..F.GetLocalizedClassName(class))
    end

    filter.buttons = {}
    local last
    -- 从右向左排列职责图标按钮（TANK/HEALER/DAMAGER）
    for i = #buttons, 1, -1 do
        local b = Cell.CreateButton(filter, nil, "accent-hover", {20, 20})
        filter.buttons[buttons[i]] = b
        b:SetTexture(F.GetDefaultRoleIcon(buttons[i]), {16, 16}, {"CENTER", 0, 0})

        if last then
            b:SetPoint("BOTTOMRIGHT", last, "BOTTOMLEFT", P.Scale(1), 0)
        else
            b:SetPoint("BOTTOMRIGHT", filter)
        end
        last = b

        -- 职责按钮点击事件：切换该职业/职责的过滤状态
        b:SetScript("OnClick", function()
            local selected
            -- 仅有一种职责的职业（如猎人只有DAMAGER），powerFilters[class] 为布尔值，直接取反
            if type(selectedLayoutTable["powerFilters"][class]) == "boolean" then
                selectedLayoutTable["powerFilters"][class] = not selectedLayoutTable["powerFilters"][class]
                selected = selectedLayoutTable["powerFilters"][class]
            -- 多种职责的职业，按具体职责键值取反
            else
                selectedLayoutTable["powerFilters"][class][buttons[i]] = not selectedLayoutTable["powerFilters"][class][buttons[i]]
                selected = selectedLayoutTable["powerFilters"][class][buttons[i]]
            end
            UpdateButton(b, selected)
            -- 若当前正在编辑的布局恰好是当前使用的布局，则立即刷新单位框体
            if selectedLayout == Cell.vars.currentLayout then
                Cell.Fire("UpdateLayout", selectedLayout, "powerFilter")
            end
        end)
    end

    -- filter:Load() —— 从布局配置中读取当前职业的过滤状态，刷新所有职责按钮的视觉
    function filter:Load()
        if type(selectedLayoutTable["powerFilters"][class]) == "boolean" then
            UpdateButton(filter.buttons["DAMAGER"], selectedLayoutTable["powerFilters"][class])
        else
            for role, b in pairs(filter.buttons) do
                UpdateButton(b, selectedLayoutTable["powerFilters"][class][role])
            end
        end
    end

    return filter
end

-------------------------------------------------
-- 创建所有职业过滤条
-- 根据资料片版本决定哪些职业需要创建，以及它们的布局位置和面板高度。
-- 各职业过滤条以两列瀑布流方式排列，左上角为第一行两个，向下依次堆叠。
-------------------------------------------------
local dkF, dhF, druidF, evokerF, hunterF, mageF, monkF, paladinF, priestF, rogueF, shamanF, warlockF, warriorF, petF, vehicleF, npcF

-- CreateFilters() —— 根据当前资料片版本创建所有职业的过滤条并设置其布局位置
local function CreateFilters()
    druidF = CreatePowerFilter(powerFilters, "DRUID", CLASS_ROLES["DRUID"])
    hunterF = CreatePowerFilter(powerFilters, "HUNTER", CLASS_ROLES["HUNTER"])
    mageF = CreatePowerFilter(powerFilters, "MAGE", CLASS_ROLES["MAGE"])
    paladinF = CreatePowerFilter(powerFilters, "PALADIN", CLASS_ROLES["PALADIN"])
    priestF = CreatePowerFilter(powerFilters, "PRIEST", CLASS_ROLES["PRIEST"])
    rogueF = CreatePowerFilter(powerFilters, "ROGUE", CLASS_ROLES["ROGUE"])
    shamanF = CreatePowerFilter(powerFilters, "SHAMAN", CLASS_ROLES["SHAMAN"])
    warlockF = CreatePowerFilter(powerFilters, "WARLOCK", CLASS_ROLES["WARLOCK"])
    warriorF = CreatePowerFilter(powerFilters, "WARRIOR", CLASS_ROLES["WARRIOR"])
    petF = CreatePowerFilter(powerFilters, "PET", CLASS_ROLES["PET"])
    vehicleF = CreatePowerFilter(powerFilters, "VEHICLE", CLASS_ROLES["VEHICLE"])
    npcF = CreatePowerFilter(powerFilters, "NPC", CLASS_ROLES["NPC"])

    -- 正式服：全部职业（含死亡骑士、恶魔猎手、武僧、唤魔师），面板高度205
    if Cell.isRetail then
        P.Height(powerFilters, 205)

        dkF = CreatePowerFilter(powerFilters, "DEATHKNIGHT", CLASS_ROLES["DEATHKNIGHT"])
        dhF = CreatePowerFilter(powerFilters, "DEMONHUNTER", CLASS_ROLES["DEMONHUNTER"])
        monkF = CreatePowerFilter(powerFilters, "MONK", CLASS_ROLES["MONK"])
        evokerF = CreatePowerFilter(powerFilters, "EVOKER", CLASS_ROLES["EVOKER"])

        dkF:SetPoint("TOPLEFT", 5, -5)
        dhF:SetPoint("TOPLEFT", 145, -5)
        druidF:SetPoint("TOPLEFT", dkF, "BOTTOMLEFT", 0, -5)
        evokerF:SetPoint("TOPLEFT", dhF, "BOTTOMLEFT", 0, -5)
        hunterF:SetPoint("TOPLEFT", druidF, "BOTTOMLEFT", 0, -5)
        mageF:SetPoint("TOPLEFT", evokerF, "BOTTOMLEFT", 0, -5)
        monkF:SetPoint("TOPLEFT", hunterF, "BOTTOMLEFT", 0, -5)
        paladinF:SetPoint("TOPLEFT", mageF, "BOTTOMLEFT", 0, -5)
        priestF:SetPoint("TOPLEFT", monkF, "BOTTOMLEFT", 0, -5)
        rogueF:SetPoint("TOPLEFT", paladinF, "BOTTOMLEFT", 0, -5)
        shamanF:SetPoint("TOPLEFT", priestF, "BOTTOMLEFT", 0, -5)
        warlockF:SetPoint("TOPLEFT", rogueF, "BOTTOMLEFT", 0, -5)
        warriorF:SetPoint("TOPLEFT", shamanF, "BOTTOMLEFT", 0, -5)
        petF:SetPoint("TOPLEFT", warlockF, "BOTTOMLEFT", 0, -5)
        vehicleF:SetPoint("TOPLEFT", warriorF, "BOTTOMLEFT", 0, -5)
        npcF:SetPoint("TOPLEFT", petF, "BOTTOMLEFT", 0, -5)

    -- 熊猫人之谜：死亡骑士 + 武僧，面板高度180
    elseif Cell.isMists then
        P.Height(powerFilters, 180)

        dkF = CreatePowerFilter(powerFilters, "DEATHKNIGHT", CLASS_ROLES["DEATHKNIGHT"])
        monkF = CreatePowerFilter(powerFilters, "MONK", CLASS_ROLES["MONK"])

        dkF:SetPoint("TOPLEFT", 5, -5)
        druidF:SetPoint("TOPLEFT", 145, -5)
        hunterF:SetPoint("TOPLEFT", dkF, "BOTTOMLEFT", 0, -5)
        mageF:SetPoint("TOPLEFT", druidF, "BOTTOMLEFT", 0, -5)
        monkF:SetPoint("TOPLEFT", hunterF, "BOTTOMLEFT", 0, -5)
        paladinF:SetPoint("TOPLEFT", mageF, "BOTTOMLEFT", 0, -5)
        priestF:SetPoint("TOPLEFT", monkF, "BOTTOMLEFT", 0, -5)
        rogueF:SetPoint("TOPLEFT", paladinF, "BOTTOMLEFT", 0, -5)
        shamanF:SetPoint("TOPLEFT", priestF, "BOTTOMLEFT", 0, -5)
        warlockF:SetPoint("TOPLEFT", rogueF, "BOTTOMLEFT", 0, -5)
        warriorF:SetPoint("TOPLEFT", shamanF, "BOTTOMLEFT", 0, -5)
        petF:SetPoint("TOPLEFT", warlockF, "BOTTOMLEFT", 0, -5)
        vehicleF:SetPoint("TOPLEFT", warriorF, "BOTTOMLEFT", 0, -5)
        npcF:SetPoint("TOPLEFT", petF, "BOTTOMLEFT", 0, -5)

    -- 大灾变/巫妖王之怒：仅增加死亡骑士，面板高度180
    elseif Cell.isCata or Cell.isWrath then
        P.Height(powerFilters, 180)

        dkF =  CreatePowerFilter(powerFilters, "DEATHKNIGHT", CLASS_ROLES["DEATHKNIGHT"])

        dkF:SetPoint("TOPLEFT", 5, -5)
        druidF:SetPoint("TOPLEFT", 145, -5)
        hunterF:SetPoint("TOPLEFT", dkF, "BOTTOMLEFT", 0, -5)
        mageF:SetPoint("TOPLEFT", druidF, "BOTTOMLEFT", 0, -5)
        paladinF:SetPoint("TOPLEFT", hunterF, "BOTTOMLEFT", 0, -5)
        priestF:SetPoint("TOPLEFT", mageF, "BOTTOMLEFT", 0, -5)
        rogueF:SetPoint("TOPLEFT", paladinF, "BOTTOMLEFT", 0, -5)
        shamanF:SetPoint("TOPLEFT", priestF, "BOTTOMLEFT", 0, -5)
        warlockF:SetPoint("TOPLEFT", rogueF, "BOTTOMLEFT", 0, -5)
        warriorF:SetPoint("TOPLEFT", shamanF, "BOTTOMLEFT", 0, -5)
        petF:SetPoint("TOPLEFT", warlockF, "BOTTOMLEFT", 0, -5)
        vehicleF:SetPoint("TOPLEFT", warriorF, "BOTTOMLEFT", 0, -5)
        npcF:SetPoint("TOPLEFT", petF, "BOTTOMLEFT", 0, -5)

    -- TBC / 经典旧世：只有9个原版职业，面板高度155
    elseif Cell.isTBC or Cell.isVanilla then
        P.Height(powerFilters, 155)

        druidF:SetPoint("TOPLEFT", 5, -5)
        hunterF:SetPoint("TOPLEFT", 145, -5)
        mageF:SetPoint("TOPLEFT", druidF, "BOTTOMLEFT", 0, -5)
        paladinF:SetPoint("TOPLEFT", hunterF, "BOTTOMLEFT", 0, -5)
        priestF:SetPoint("TOPLEFT", mageF, "BOTTOMLEFT", 0, -5)
        rogueF:SetPoint("TOPLEFT", paladinF, "BOTTOMLEFT", 0, -5)
        shamanF:SetPoint("TOPLEFT", priestF, "BOTTOMLEFT", 0, -5)
        warlockF:SetPoint("TOPLEFT", rogueF, "BOTTOMLEFT", 0, -5)
        warriorF:SetPoint("TOPLEFT", shamanF, "BOTTOMLEFT", 0, -5)
        petF:SetPoint("TOPLEFT", warlockF, "BOTTOMLEFT", 0, -5)
        vehicleF:SetPoint("TOPLEFT", warriorF, "BOTTOMLEFT", 0, -5)
        npcF:SetPoint("TOPLEFT", petF, "BOTTOMLEFT", 0, -5)
    end
end

-------------------------------------------------
-- 事件脚本与面板控制
-------------------------------------------------
-- OnHide 事件：面板隐藏时同步隐藏遮罩层，并将触发按钮的层级恢复为普通状态
powerFilters:SetScript("OnHide", function()
    powerFilters:Hide()
    Cell.frames.layoutsTab.mask:Hide()
    -- 按钮层级回到略高于布局Tab，使其不再高亮突出
    Cell.frames.layoutsTab.powerFilterBtn:SetFrameLevel(Cell.frames.layoutsTab:GetFrameLevel() + 1)
end)

local init
-- ShowPowerFilters(l, lt) —— 切换职责过滤面板的显示/隐藏
-- l: 当前选中的布局名, lt: 当前选中布局的配置表
-- 首次调用时执行延迟初始化：创建所有过滤控件并应用像素完美和主题色
function F.ShowPowerFilters(l, lt)
    selectedLayout, selectedLayoutTable = l, lt

    -- 延迟初始化：只在第一次打开面板时创建控件，节省启动时的资源开销
    if not init then
        init = true
        powerFilters:UpdatePixelPerfect()
        powerFilters:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))
        CreateFilters()
    end

    -- 面板已显示则关闭，未显示则打开（toggle 模式）
    if powerFilters:IsShown() then
        powerFilters:Hide()
        -- 按钮层级略高于Tab，表示面板处于关闭状态
        Cell.frames.layoutsTab.powerFilterBtn:SetFrameLevel(Cell.frames.layoutsTab:GetFrameLevel() + 2)
    else
        powerFilters:Show()
        -- 按钮层级远高于Tab，配合高亮表示面板处于打开状态
        Cell.frames.layoutsTab.powerFilterBtn:SetFrameLevel(Cell.frames.layoutsTab:GetFrameLevel() + 50)
        -- 显示遮罩层，用于点击面板外部区域时关闭面板
        Cell.frames.layoutsTab.mask:Show()

        -- 从数据库加载各职业过滤条的当前状态，刷新按钮视觉
        druidF:Load()
        hunterF:Load()
        mageF:Load()
        paladinF:Load()
        priestF:Load()
        rogueF:Load()
        shamanF:Load()
        warlockF:Load()
        warriorF:Load()
        petF:Load()
        vehicleF:Load()
        npcF:Load()

        -- 仅在包含这些职业的资料片版本中加载对应过滤条
        if Cell.isRetail or Cell.isMists or Cell.isCata or Cell.isWrath then
            dkF:Load()
        end

        if Cell.isRetail or Cell.isMists then
            monkF:Load()
        end

        if Cell.isRetail then
            dhF:Load()
            evokerF:Load()
        end
    end
end

-- HidePowerFilters() —— 外部接口：强制隐藏职责过滤面板（例如切换布局时调用）
function F.HidePowerFilters()
    powerFilters:Hide()
end