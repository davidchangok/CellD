local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

local utilitiesTab = Cell.CreateFrame("CellOptionsFrame_UtilitiesTab", Cell.frames.optionsFrame, nil, nil, true)
Cell.frames.utilitiesTab = utilitiesTab
utilitiesTab:SetAllPoints(Cell.frames.optionsFrame)
utilitiesTab:Hide()

-------------------------------------------------
-- 工具类别列表面板
-- list
-------------------------------------------------
local buttons = {}           -- 工具类别按钮组
local listFrame              -- 工具选择列表容器
local lastShown              -- 当前显示的工具类别ID

-- 配置按钮上字体字符串的布局：左右各留3像素边距，启用自动换行，行间距3像素
local function UpdateFontString(b)
    local fs = b:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", 3, 0)
    fs:SetPoint("RIGHT", -3, 0)
    fs:SetWordWrap(true)
    fs:SetSpacing(3)
end

-- 在选项面板中创建工具类别选择列表（如团队工具、技能请求、驱散请求等）
-- @param anchor 列表的锚点控件，列表将显示在其右侧
function F.CreateUtilityList(anchor)
    listFrame = CreateFrame("Frame", nil, Cell.frames.optionsFrame, "BackdropTemplate")
    Cell.StylizeFrame(listFrame, {0,1,0,0.1}, {0,0,0,1})
    listFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 1, 0)
    listFrame:Hide()

    Cell.StylizeFrame(listFrame, nil, Cell.GetAccentColorTable())

    -- update width to show full text
    local dumbFS1 = listFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    dumbFS1:SetText(L["Quick Assist"])
    local dumbFS2 = listFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    dumbFS2:SetText(L["Dispel Request"])

    -- buttons
    buttons["raidTools"] = Cell.CreateButton(listFrame, L["Raid Tools"], "transparent-accent", {20, 20}, true)
    buttons["raidTools"].id = "raidTools"
    buttons["raidTools"]:SetPoint("TOPLEFT")
    buttons["raidTools"]:SetPoint("TOPRIGHT")

    buttons["spellRequest"] = Cell.CreateButton(listFrame, L["Spell Request"], "transparent-accent", {20, 20}, true)
    buttons["spellRequest"].id = "spellRequest"
    buttons["spellRequest"]:SetPoint("TOPLEFT", buttons["raidTools"], "BOTTOMLEFT")
    buttons["spellRequest"]:SetPoint("TOPRIGHT", buttons["raidTools"], "BOTTOMRIGHT")

    buttons["dispelRequest"] = Cell.CreateButton(listFrame, L["Dispel Request"], "transparent-accent", {20, 20}, true)
    buttons["dispelRequest"].id = "dispelRequest"
    buttons["dispelRequest"]:SetPoint("TOPLEFT", buttons["spellRequest"], "BOTTOMLEFT")
    buttons["dispelRequest"]:SetPoint("TOPRIGHT", buttons["spellRequest"], "BOTTOMRIGHT")

    if Cell.isRetail then
        buttons["quickAssist"] = Cell.CreateButton(listFrame, L["Quick Assist"], "transparent-accent", {20, 20}, true)
        buttons["quickAssist"].id = "quickAssist"
        buttons["quickAssist"]:SetPoint("TOPLEFT", buttons["dispelRequest"], "BOTTOMLEFT")
        buttons["quickAssist"]:SetPoint("TOPRIGHT", buttons["dispelRequest"], "BOTTOMRIGHT")

        buttons["quickCast"] = Cell.CreateButton(listFrame, L["Quick Cast"], "transparent-accent", {20, 20}, true)
        buttons["quickCast"].id = "quickCast"
        buttons["quickCast"]:SetPoint("TOPLEFT", buttons["quickAssist"], "BOTTOMLEFT")
        buttons["quickCast"]:SetPoint("TOPRIGHT", buttons["quickAssist"], "BOTTOMRIGHT")
        P.Size(listFrame, ceil(max(dumbFS1:GetStringWidth(), dumbFS2:GetStringWidth())) + 13, 20*5)
    else
        P.Size(listFrame, ceil(max(dumbFS1:GetStringWidth(), dumbFS2:GetStringWidth())) + 13, 20*3)
    end

    local highlight = Cell.CreateButtonGroup(buttons, function(id)
        lastShown = id
        anchor:Click()
        Cell.Fire("ShowUtilitySettings", id)
        listFrame:Hide()
    end)
    highlight("raidTools")
end

-- 显示工具类别选择列表，设置其层级为TOOLTIP确保不被遮挡
function F.ShowUtilityList()
    listFrame:SetFrameStrata("TOOLTIP")
    listFrame:Show()
end

-- 隐藏工具类别选择列表
function F.HideUtilityList()
    if listFrame then listFrame:Hide() end
end

-- 判断鼠标是否悬停在工具类别选择列表上（用于防止误关闭）
function F.IsUtilityListMouseover()
    return listFrame and listFrame:IsMouseOver()
end

-------------------------------------------------
-- 各工具子面板高度配置（用于自动调整选项面板高度）
-- show
-------------------------------------------------
local utilityHeight = {
    ["raidTools"] = 340,
    ["spellRequest"] = 400,
    ["dispelRequest"] = 420,
    ["quickAssist"] = 510,
    ["quickCast"] = 510,
}

local init  -- 首次初始化标记（延迟到首次切到此Tab时才执行）
-- 处理选项Tab切换事件：当切换到"utilities"Tab时显示工具面板，切换走时隐藏
local function ShowTab(tab)
    if tab == "utilities" then
        if not init then
            init = true
            lastShown = lastShown or "raidTools"  -- 首次打开默认显示团队工具
        end
        Cell.Fire("ShowUtilitySettings", lastShown)  -- 触发显示上次浏览的工具子面板
        utilitiesTab:Show()
    else
        utilitiesTab:Hide()
    end
end
-- 注册选项Tab切换事件的回调：监听ShowOptionsTab事件以控制工具面板显隐
Cell.RegisterCallback("ShowOptionsTab", "UtilitiesTab_ShowTab", ShowTab)

-- 注册工具子面板切换事件的回调：根据选择的工具类别动态调整选项面板高度
Cell.RegisterCallback("ShowUtilitySettings", "UtilitiesTab_ShowUtilitySettings", function(which)
    P.Height(Cell.frames.optionsFrame, utilityHeight[which])
end)

-- 从外部直接打开快速协助面板（例如快捷键触发）
function F.ShowQuickAssistTab()
    buttons["quickAssist"]:Click()
end