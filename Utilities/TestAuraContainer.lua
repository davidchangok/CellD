-------------------------------------------------
-- TestAuraContainer (临时调试模块)
-- 12.1 战斗中 AuraContainer filter 可用性对比测试
--
-- 背景:
--   12.1 受限环境中, CellD v1.1.0 曾实验 AuraContainer(commit cc36155)
--   用 filter "HELPFUL" 时战斗中不显示被 secret 化的光环, 故 revert。
--   VuhDo 3.214 用 "HELPFUL|PLAYER|RAID_IN_COMBAT" 作为默认 HoT 组 filter,
--   RAID_IN_COMBAT 疑似官方为"战斗中保留显示"预留的 C++ filter token。
--   本模块用双容器并排对比, 游戏内实测确认:
--     A. "HELPFUL"                  (旧实验, 预期战斗中不显示)
--     B. "HELPFUL|RAID_IN_COMBAT"   (VuhDo 方案, 预期战斗中显示)
--   验证完成后删除本模块。
--
-- 用法:
--   /celld testaura [unit]  创建两个并排测试容器(默认 party1, 无队伍用 player)
--   /celld testaura off     隐藏并销毁测试容器
-------------------------------------------------

local _, Cell = ...
local F = Cell.funcs
local U = Cell.uFuncs

-------------------------------------------------
-- 测试追踪法术 = 官方 12.1 secret 名单(never-secret 移除清单)全职业完整列表
-- 与 SecretAuraTracker.officialSecretSpells 一致, 任何治疗职业均可测试
-- 来源: warcraft.wiki.gg Patch 12.1.0 "Aura Classifications"
-------------------------------------------------
local testSpellIDs = {
    [355941] = true, [363502] = true, [364343] = true, [366155] = true, [367364] = true, [373267] = true, [376788] = true, [409895] = true, -- Preservation Evoker
    [360827] = true, [395152] = true, [395296] = true, [410089] = true, [410263] = true, [410686] = true, [413984] = true,                   -- Augmentation Evoker
    [774] = true, [8936] = true, [33763] = true, [48438] = true, [155777] = true, [439530] = true,                                          -- Resto Druid
    [17] = true, [194384] = true, [1253593] = true, [1300008] = true, [1300009] = true,                                                      -- Disc Priest
    [139] = true, [41635] = true, [77489] = true,                                                                                            -- Holy Priest
    [115175] = true, [119611] = true, [124682] = true, [450769] = true, [1292922] = true,                                                    -- Mistweaver Monk
    [974] = true, [383648] = true, [61295] = true, [382024] = true, [207400] = true, [444490] = true,                                        -- Restoration Shaman
    [53563] = true, [156322] = true, [156910] = true, [1244893] = true, [200025] = true, [431381] = true,                                    -- Holy Paladin
}

-------------------------------------------------
-- 状态
-------------------------------------------------
local testFrame -- 容器与标签的宿主 frame(隐藏时一并隐藏)
local containers = {} -- { filterLabel, container }

-------------------------------------------------
-- AuraButton 初始化(引擎创建按钮时调用)
-------------------------------------------------
local function InitAuraButton(auraButton)
    auraButton:SetSize(28, 28)

    local icon = auraButton:CreateTexture(nil, "BORDER")
    icon:SetAllPoints(auraButton)
    auraButton:SetIcon(icon)

    local duration = auraButton:CreateFontString(nil, "OVERLAY")
    duration:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", 0, 0)
    duration:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    duration:SetTextColor(1, 1, 1)
    auraButton:SetDurationText(duration)
end

-------------------------------------------------
-- 创建一个测试容器
-------------------------------------------------
local function CreateTestContainer(parent, anchor, relPoint, offsetX, filter, label)
    local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    container:SetSize(150, 28)
    container:SetPoint(anchor, parent, relPoint, offsetX, 0)
    container:SetEnabled(true)

    container:AddAuraGroup("test", filter, {
        maxFrameCount = 5,
        candidateFilters = {
            includeSpellIDs = testSpellIDs,
        },
        sortMethod = AuraContainerSortMethod.ExpirationOnly,
        sortDirection = AuraContainerSortDirection.Normal,
        layout = {
            elementSpacing = 2,
            elementWidth = 28,
            elementHeight = 28,
        },
        templateNames = { "CustomAuraButtonTemplate" },
        initializeFrame = InitAuraButton,
    })

    container:SetUnit("player")

    local title = container:CreateFontString(nil, "OVERLAY")
    title:SetPoint("BOTTOM", container, "TOP", 0, 4)
    title:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    title:SetTextColor(1, 0.82, 0, 1)
    title:SetText(label)

    containers[#containers + 1] = { label = label, container = container }
    return container
end

-------------------------------------------------
-- 入口: /celld testaura [unit]
-------------------------------------------------
local initialized = false

function U.TestAuraContainer(cmd)
    cmd = cmd or ""
    cmd = strlower(strtrim(cmd))

    -- off: 销毁全部测试容器
    if cmd == "off" or cmd == "hide" then
        if testFrame then
            testFrame:Hide()
            F.Print("CellD AuraContainer 测试已隐藏 (/celld testaura 重新显示)")
        else
            F.Print("CellD AuraContainer 测试尚未创建")
        end
        return
    end

    -- 目标单位: 参数优先, 默认 party1, 无队伍用 player
    local unit = cmd
    if unit == "" then
        unit = UnitExists("party1") and "party1" or "player"
    end
    if not UnitExists(unit) then
        F.Print(string.format("单位 %q 不存在, 请先入队或指定有效单位 (/celld testaura party2)", unit))
        return
    end

    if not initialized then
        -- 首次创建宿主 frame(含两个对比容器)
        testFrame = CreateFrame("Frame", nil, UIParent)
        testFrame:SetSize(400, 120)
        testFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)

        CreateTestContainer(testFrame, "TOPLEFT", "TOPLEFT", 0,  "HELPFUL",                "A: HELPFUL")
        CreateTestContainer(testFrame, "TOPRIGHT", "TOPRIGHT", 0, "HELPFUL|RAID_IN_COMBAT", "B: HELPFUL|RAID_IN_COMBAT")

        initialized = true
    end

    -- 绑定目标单位并显示
    for _, entry in ipairs(containers) do
        entry.container:SetUnit(unit)
    end
    testFrame:Show()

    F.Print(string.format("CellD AuraContainer 测试: 目标 %s — 战斗中施放道标/HoT 后对比 A/B 是否显示图标", unit))
    F.Print("隐藏: /celld testaura off")
end
