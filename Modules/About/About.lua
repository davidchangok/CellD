local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

local aboutTab = Cell.CreateFrame("CellOptionsFrame_AboutTab", Cell.frames.optionsFrame, nil, nil, true)
Cell.frames.aboutTab = aboutTab
aboutTab:SetAllPoints(Cell.frames.optionsFrame)
aboutTab:Hide()

local authorText, originalAuthorText, supportersText1, supportersText2
local UpdateFont

-------------------------------------------------
-- description
-------------------------------------------------
local descriptionPane
local function CreateDescriptionPane()
    descriptionPane = Cell.CreateTitledPane(aboutTab, "CellD", 422, 80)
    descriptionPane:SetPoint("TOPLEFT", aboutTab, "TOPLEFT", 5, -5)

    local descText = descriptionPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    descText:SetPoint("TOPLEFT", 5, -27)
    descText:SetPoint("RIGHT", -10, 0)
    descText:SetJustifyH("LEFT")
    descText:SetSpacing(5)
    descText:SetText(L["ABOUT"])
end

-------------------------------------------------
-- original author
-------------------------------------------------
local function CreateOriginalAuthorPane()
    local pane = Cell.CreateTitledPane(aboutTab, L["Original Author"], 210, 50)
    pane:SetPoint("TOPLEFT", aboutTab, "TOPLEFT", 5, -110)

    originalAuthorText = pane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    originalAuthorText:SetPoint("TOPLEFT", 5, -27)
    originalAuthorText:SetText("enderneko（原始Cell插件作者）")
end

-------------------------------------------------
-- rewrite author
-------------------------------------------------
local function CreateRewriteAuthorPane()
    local pane = Cell.CreateTitledPane(aboutTab, L["Rewrite Author"], 210, 50)
    pane:SetPoint("TOPLEFT", aboutTab, "TOPLEFT", 222, -110)

    authorText = pane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    authorText:SetPoint("TOPLEFT", 5, -27)
    authorText:SetText("David W Zhang（CellD改写和维护者）")
end

-------------------------------------------------
-- contributors
-------------------------------------------------
local function CreateContributorsPane()
    local pane = Cell.CreateTitledPane(aboutTab, L["Contributors"], 422, 140)
    pane:SetPoint("TOPLEFT", aboutTab, "TOPLEFT", 5, -165)

    local text = pane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    text:SetPoint("TOPLEFT", 5, -27)
    text:SetPoint("RIGHT", -5, 0)
    text:SetSpacing(5)
    text:SetJustifyH("LEFT")
    text:SetText(
        "|cfffb6f92露露缇娅, Reat TV, 钛锬, Floofe, warbaby|r\n"..
        "|cffff0000Wago:|r Ora\n"..
        "|cffff3333YouTube:|r AutomaticJak, JFunkGaming, yumytv\n"..
        "|cff5662f6Discord:|r |cff7fff00clankz.|r, |cff7fff00DreadMesh|r, |cff7fff00Missgunst|r, |cff00ffffVollmerino|r, aba, BinarySunshine, Bruds, Gharr, honeyhoney, leaKsi, Serghei, swirl, Xepheris\n"..
        "|cff999999zhTW:|r RainbowUI, BNS333, Mili\n"..
        "|cff999999koKR:|r 007bb, netaras\n"..
        "|cff999999ptBR:|r cathtail\n"..
        "|cff999999deDE:|r CheersItsJulian\n"..
        "|cff999999ruRU:|r KnewOne, Lucenn, MORROSION\n"..
        "|cff999999frFR:|r epino46, elated_kalam86\n"..
        "|cff999999itIT:|r CeleDev\n"..
        "|cff999999esES/esMX:|r Zurent, maylisdalan, F3R_Lv72"
    )
end

-------------------------------------------------
-- supporters
-------------------------------------------------
local function GetSupporters(t)
    local str = ""
    local n = #t
    for i = 1, n do
        local total = #t[i]
        for j, name in ipairs(t[i]) do
            name = name:gsub("%(.+%)", function(s)
                return "|cff777777"..s.."|r"
            end)
            str = str .. name
            if j ~= total or i ~= n then
                str = str .. "\n"
            end
        end
    end
    return str
end

local function Getsupporters2(t)
    local str = ""
    local n = #t
    for i = 1, n do
        local name = t[i][1] .. " |cff777777("..t[i][2]..")|r"
        str = str .. name
        if i ~= n then
            str = str .. "\n"
        end
    end
    return str
end

local function CreateAnimation(frame)
    local fadeOut = frame:CreateAnimationGroup()
    frame.fadeOut = fadeOut
    fadeOut.alpha = fadeOut:CreateAnimation("Alpha")
    fadeOut.alpha:SetFromAlpha(1)
    fadeOut.alpha:SetToAlpha(0)
    fadeOut.alpha:SetDuration(0.3)
    fadeOut:SetScript("OnFinished", function()
        frame:Hide()
    end)

    local fadeIn = frame:CreateAnimationGroup()
    frame.fadeIn = fadeIn
    fadeIn.alpha = fadeIn:CreateAnimation("Alpha")
    fadeIn.alpha:SetFromAlpha(0)
    fadeIn.alpha:SetToAlpha(1)
    fadeIn.alpha:SetDuration(0.3)
    fadeIn:SetScript("OnPlay", function()
        frame:Show()
    end)
end

local function CreateButton(w, h, tex)
    local supportersBtn = Cell.CreateButton(aboutTab, L["Supporters"], "accent", {w, h})
    supportersBtn:SetToplevel(true)
    supportersBtn:SetPushedTextOffset(0, 0)

    supportersBtn:SetScript("OnHide", function()
        supportersBtn:SetBackdropColor(unpack(supportersBtn.color))
    end)

    supportersBtn:HookScript("OnEnter", function()
        F.HideUtilityList()
    end)

    Cell.StartRainbowText(supportersBtn:GetFontString())

    local iconSize = min(w, h) - 2

    local icon1 = supportersBtn:CreateTexture(nil, "ARTWORK")
    supportersBtn.icon1 = icon1
    P.Point(supportersBtn.icon1, "TOPLEFT", 1, -1)
    P.Size(icon1, iconSize, iconSize)
    icon1:SetTexture(tex)
    icon1:SetVertexColor(0.5, 0.5, 0.5)

    local icon2 = supportersBtn:CreateTexture(nil, "ARTWORK")
    supportersBtn.icon2 = icon2
    P.Point(supportersBtn.icon2, "BOTTOMRIGHT", -1, 1)
    P.Size(icon2, iconSize, iconSize)
    icon2:SetTexture(tex)
    icon2:SetVertexColor(0.5, 0.5, 0.5)

    CreateAnimation(supportersBtn)

    return supportersBtn
end

local function CreateSupportersPane()
    -- pane
    local supportersPane = Cell.CreateTitledPane(aboutTab, "", 100, 100)
    supportersPane:SetPoint("TOPLEFT", aboutTab, "TOPRIGHT", 6, -5)
    supportersPane:SetPoint("BOTTOMLEFT", aboutTab, "BOTTOMRIGHT", 6, 5)
    supportersPane:Hide()

    CreateAnimation(supportersPane)

    local heartIcon = supportersPane:CreateTexture(nil, "OVERLAY")
    heartIcon:SetPoint("TOPRIGHT")
    heartIcon:SetSize(16, 16)
    heartIcon:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\sparkling_heart")

    local bgTex = supportersPane:CreateTexture(nil, "BACKGROUND", nil, 0)
    bgTex:SetPoint("TOPLEFT", -5, 5)
    bgTex:SetPoint("BOTTOMRIGHT", 5, -5)
    bgTex:SetTexture(Cell.vars.whiteTexture)
    bgTex:SetGradient("HORIZONTAL", CreateColor(0.1, 0.1, 0.1, 1), CreateColor(0.1, 0.1, 0.1, 0.7))

    local supportersFrame1 = CreateFrame("Frame", nil, supportersPane)
    supportersFrame1:SetPoint("TOPLEFT", 0, -27)
    supportersFrame1:SetPoint("BOTTOMLEFT")
    supportersFrame1.scroll = Cell.CreateScrollFrame(supportersFrame1)
    supportersFrame1.scroll:SetScrollStep(50)

    supportersText1 = supportersFrame1.scroll.content:CreateFontString(nil, "OVERLAY")
    supportersText1.font = UNIT_NAME_FONT_CHINESE
    supportersText1.size = 13
    UpdateFont(supportersText1)

    supportersText1:SetPoint("TOPLEFT")
    supportersText1:SetSpacing(5)
    supportersText1:SetJustifyH("LEFT")
    supportersText1:SetText(GetSupporters(Cell.supporters1))

    local supportersFrame2 = CreateFrame("Frame", nil, supportersPane)
    supportersFrame2:SetPoint("TOPLEFT", supportersFrame1, "TOPRIGHT", 10, 0)
    supportersFrame2:SetPoint("BOTTOMLEFT", supportersFrame1, "BOTTOMRIGHT")
    supportersFrame2.scroll = Cell.CreateScrollFrame(supportersFrame2)
    supportersFrame2.scroll:SetScrollStep(50)

    supportersText2 = supportersFrame2.scroll.content:CreateFontString(nil, "OVERLAY")
    supportersText2.font = UNIT_NAME_FONT_CHINESE
    supportersText2.size = 13
    UpdateFont(supportersText2)

    supportersText2:SetPoint("TOPLEFT")
    supportersText2:SetSpacing(5)
    supportersText2:SetJustifyH("LEFT")
    supportersText2:SetText(Getsupporters2(Cell.supporters2))

    -- update width
    local elapsedTime = 0
    local function updateFunc(self, elapsed)
        elapsedTime = elapsedTime + elapsed

        supportersFrame1:SetWidth(supportersText1:GetWidth() + 10)
        supportersFrame1.scroll:SetContentHeight(supportersText1:GetHeight() + 5)
        supportersFrame2:SetWidth(supportersText2:GetWidth() + 10)
        supportersFrame2.scroll:SetContentHeight(supportersText2:GetHeight() + 5)
        supportersPane:SetWidth(supportersFrame1:GetWidth() + supportersFrame2:GetWidth() + 10)

        if elapsedTime >= 0.5 then
            supportersPane:SetScript("OnUpdate", nil)
        end
    end
    supportersPane:SetScript("OnShow", function()
        elapsedTime = 0
        supportersPane:SetScript("OnUpdate", updateFunc)
    end)

    -- button
    local supportersBtn1 = CreateButton(17, 157, [[Interface\AddOns\Cell\Media\Icons\right]])
    supportersBtn1:SetPoint("TOPLEFT", aboutTab, "TOPRIGHT", 1, -5)

    local label = supportersBtn1:GetFontString()
    -- if Cell.isRetail then
        label:ClearAllPoints()
        label:SetPoint("CENTER", 6, -5)
        label:SetRotation(-math.pi/2)
    -- else
    --     Cell.StopRainbowText(label)
    --     label:SetWordWrap(true)
    --     label:SetSpacing(0)
    --     label:ClearAllPoints()
    --     label:SetPoint("CENTER")
    --     label:SetText("P\na\nt\nr\no\nn\ns")
    --     Cell.StartRainbowText(label)
    -- end

    local supportersBtn2 = CreateButton(17, 17, [[Interface\AddOns\Cell\Media\Icons\left]])
    -- supportersBtn2:SetPoint("TOPLEFT", aboutTab, "TOPRIGHT", 6, -5)
    supportersBtn2:SetPoint("TOPLEFT", supportersPane)
    supportersBtn2:SetPoint("TOPRIGHT", supportersPane, P.Scale(-20), 0)
    supportersBtn2:Hide()

    supportersBtn1:SetScript("OnClick", function()
        if supportersBtn1.fadeOut:IsPlaying() or supportersBtn1.fadeIn:IsPlaying() then return end
        supportersBtn1.fadeOut:Play()
        supportersBtn2.fadeIn:Play()
        supportersPane.fadeIn:Play()
    end)

    supportersBtn2:SetScript("OnClick", function()
        if supportersBtn2.fadeOut:IsPlaying() or supportersBtn2.fadeIn:IsPlaying() then return end
        supportersBtn1.fadeIn:Play()
        supportersBtn2.fadeOut:Play()
        supportersPane.fadeOut:Play()
    end)
end

-------------------------------------------------
-- links
-------------------------------------------------
local links = {}
local function CreateLink(parent, id, icon, onEnter)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    P.Size(f, 34, 34)
    f:SetBackdrop({bgFile = Cell.vars.whiteTexture})
    f:SetBackdropColor(0, 0, 0, 1)

    links[id] = f

    f.icon = f:CreateTexture(nil, "ARTWORK")
    P.Point(f.icon, "TOPLEFT", 1, -1)
    P.Point(f.icon, "BOTTOMRIGHT", -1, 1)
    f.icon:SetTexture(icon)

    f:SetScript("OnEnter", function()
        f:SetBackdropColor(Cell.GetAccentColorRGB())
        for  _id, _f in pairs(links) do
            if _id ~= id then
                _f:SetBackdropColor(0, 0, 0, 1)
            end
        end
        if onEnter then onEnter() end
    end)

    f:SetScript("OnHide", function()
        f:SetBackdropColor(0, 0, 0, 1)
    end)

    return f
end

local function CreateLinksPane()
    local linksPane = Cell.CreateTitledPane(aboutTab, L["Links"], 422, 100)
    linksPane:SetPoint("TOPLEFT", aboutTab, "TOPLEFT", 5, -330)

    local current

    local linksEB = Cell.CreateEditBox(linksPane, 412, 20)
    linksEB:SetPoint("TOPLEFT", 5, -27)
    linksEB:SetText("https://github.com/davidchangok/CellD")
    linksEB:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            linksEB:SetText(current)
            linksEB:HighlightText()
        end
        linksEB:SetCursorPosition(0)
    end)
    linksEB:SetScript("OnMouseUp", function(self)
        linksEB:HighlightText()
    end)

    --! github (CellD)
    local github = CreateLink(linksPane, "github", "Interface\\AddOns\\Cell\\Media\\Links\\github.tga", function()
        current = "https://github.com/davidchangok/CellD"
        linksEB:SetText(current)
        linksEB:ClearFocus()
    end)
    github:SetPoint("TOPLEFT", linksEB, "BOTTOMLEFT", 0, -7)

    linksEB:SetScript("OnShow", function()
        github:GetScript("OnEnter")()
    end)
end

-------------------------------------------------
-- import & export
-------------------------------------------------
local function CreateImportExportPane()
    local iePane = Cell.CreateTitledPane(aboutTab, L["Import & Export All Settings"], 422, 50)
    iePane:SetPoint("TOPLEFT", 5, -455)

    local importBtn = Cell.CreateButton(iePane, L["Import"], "accent-hover", {134, 20})
    importBtn:SetPoint("TOPLEFT", 5, -27)
    importBtn:SetScript("OnClick", F.ShowImportFrame)
    importBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\import", {16, 16}, {"LEFT", 2, 0})

    local exportBtn = Cell.CreateButton(iePane, L["Export"], "accent-hover", {134, 20})
    exportBtn:SetPoint("TOPLEFT", importBtn, "TOPRIGHT", 5, 0)
    exportBtn:SetScript("OnClick", F.ShowExportFrame)
    exportBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\export", {16, 16}, {"LEFT", 2, 0})

    local backupBtn = Cell.CreateButton(iePane, L["Backups"], "accent-hover", {134, 20})
    backupBtn:SetPoint("TOPLEFT", exportBtn, "TOPRIGHT", 5, 0)
    backupBtn:SetScript("OnClick", F.ShowBackupFrame)
    backupBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\backup", {16, 16}, {"LEFT", 2, 0})
end

-------------------------------------------------
-- functions
-------------------------------------------------
local init
local function ShowTab(tab)
    if tab == "about" then
        if not init then
            init = true
            CreateDescriptionPane()
            CreateOriginalAuthorPane()
            CreateRewriteAuthorPane()
            CreateContributorsPane()
            CreateLinksPane()
            CreateImportExportPane()
            CreateSupportersPane()
        end
        aboutTab:Show()
        descriptionPane:SetTitle("CellD "..Cell.version)
    else
        aboutTab:Hide()
    end
end
Cell.RegisterCallback("ShowOptionsTab", "AboutTab_ShowTab", ShowTab)

UpdateFont = function(fs)
    if not fs then return end
    fs:SetFont(fs.font, fs.size + (CellDB["appearance"]["optionsFontSizeOffset"] or 0), "")
    fs:SetTextColor(1, 1, 1, 1)
    fs:SetShadowColor(0, 0, 0)
    fs:SetShadowOffset(1, -1)
end

function Cell.UpdateAboutFont(offset)
    UpdateFont(originalAuthorText)
    UpdateFont(authorText)
    UpdateFont(supportersText1)
    UpdateFont(supportersText2)
end