-- 引入 CellD 核心全局表、本地化模块、通用工具函数和像素完美辅助函数
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 创建"关于"标签页的主容器 Frame，挂载到选项窗口内部
local aboutTab = Cell.CreateFrame("CellOptionsFrame_AboutTab", Cell.frames.optionsFrame, nil, nil, true)
Cell.frames.aboutTab = aboutTab
aboutTab:SetAllPoints(Cell.frames.optionsFrame)
aboutTab:Hide()

-- 保存需要动态更新字体的文本对象引用；UpdateFont 在文件末尾定义为闭包
local authorText, originalAuthorText, supportersText1, supportersText2
local UpdateFont

-------------------------------------------------
-- 面板：CellD 描述信息
-- 展示 CellD 的基本说明文字（本地化字符串 L["ABOUT"]）
-------------------------------------------------
local descriptionPane
local function CreateDescriptionPane()
    descriptionPane = Cell.CreateTitledPane(aboutTab, "CellD", 422, 80)
    descriptionPane:SetPoint("TOPLEFT", aboutTab, "TOPLEFT", 5, -5)

    -- 创建描述文本，使用插件标准字体样式，左对齐并设置行间距
    local descText = descriptionPane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    descText:SetPoint("TOPLEFT", 5, -27)
    descText:SetPoint("RIGHT", -10, 0)
    descText:SetJustifyH("LEFT")
    descText:SetSpacing(5)
    descText:SetText(L["ABOUT"])
end

-------------------------------------------------
-- 面板：原始作者
-- 显示 Cell 插件原作者信息，字体引用存入 originalAuthorText 以便全局字体更新
-------------------------------------------------
local function CreateOriginalAuthorPane()
    local pane = Cell.CreateTitledPane(aboutTab, L["Original Author"], 210, 50)
    pane:SetPoint("TOPLEFT", aboutTab, "TOPLEFT", 5, -110)

    originalAuthorText = pane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    originalAuthorText:SetPoint("TOPLEFT", 5, -27)
    originalAuthorText:SetText("enderneko（原始Cell插件作者）")
end

-------------------------------------------------
-- 面板：改写/维护作者
-- 显示 CellD 的改写和维护者信息，字体引用存入 authorText 以便全局字体更新
-------------------------------------------------
local function CreateRewriteAuthorPane()
    local pane = Cell.CreateTitledPane(aboutTab, L["Rewrite Author"], 210, 50)
    pane:SetPoint("TOPLEFT", aboutTab, "TOPLEFT", 222, -110)

    authorText = pane:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    authorText:SetPoint("TOPLEFT", 5, -27)
    authorText:SetText("David W Zhang（CellD改写和维护者）")
end

-------------------------------------------------
-- 面板：贡献者列表
-- 列出各平台（B站/Wago/YouTube/Discord）及各国翻译贡献者，使用颜色标签区分来源
-------------------------------------------------
local function CreateContributorsPane()
    local pane = Cell.CreateTitledPane(aboutTab, L["Contributors"], 422, 140)
    pane:SetPoint("TOPLEFT", aboutTab, "TOPLEFT", 5, -165)

    -- 贡献者文本使用固定颜色标签区分不同社区平台和语言翻译贡献者
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
-- 支持者名单格式化函数
-------------------------------------------------

-- 将第一类支持者列表（嵌套表结构）格式化为带灰色括号注释的文本
-- 传入形式：{ { "名字1(备注)", "名字2(备注)" }, { ... }, ... }
-- 将括号内的备注文本用灰色（|cff777777）包裹，每个子表末尾不添加多余换行
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

-- 将第二类支持者列表（键值对表结构）格式化为"名字 (金额)"的文本
-- 传入形式：{ { "名字", "金额" }, { "名字", "金额" }, ... }
-- 金额部分用灰色显示
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

-- 为指定 Frame 创建淡入/淡出动画组
-- fadeOut: 透明度从 1 到 0，持续 0.3 秒，完成后隐藏 Frame
-- fadeIn: 透明度从 0 到 1，持续 0.3 秒，播放时先显示 Frame
local function CreateAnimation(frame)
    -- 淡出动画组
    local fadeOut = frame:CreateAnimationGroup()
    frame.fadeOut = fadeOut
    fadeOut.alpha = fadeOut:CreateAnimation("Alpha")
    fadeOut.alpha:SetFromAlpha(1)
    fadeOut.alpha:SetToAlpha(0)
    fadeOut.alpha:SetDuration(0.3)
    fadeOut:SetScript("OnFinished", function()
        frame:Hide()
    end)

    -- 淡入动画组
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

-- 创建支持者面板的切换按钮（如打开/关闭面板的方向箭头按钮）
-- w/h: 按钮宽高, tex: 按钮上装饰图标的纹理路径
-- 按钮启用彩虹文字效果，并在鼠标进入时隐藏工具提示列表
local function CreateButton(w, h, tex)
    local supportersBtn = Cell.CreateButton(aboutTab, L["Supporters"], "accent", {w, h})
    supportersBtn:SetToplevel(true)
    supportersBtn:SetPushedTextOffset(0, 0)

    -- 隐藏时恢复按钮背景色
    supportersBtn:SetScript("OnHide", function()
        supportersBtn:SetBackdropColor(unpack(supportersBtn.color))
    end)

    -- 鼠标进入按钮时隐藏所有工具提示弹窗
    supportersBtn:HookScript("OnEnter", function()
        F.HideUtilityList()
    end)

    -- 启用彩虹渐变文字效果
    Cell.StartRainbowText(supportersBtn:GetFontString())

    local iconSize = min(w, h) - 2

    -- 左上角装饰图标
    local icon1 = supportersBtn:CreateTexture(nil, "ARTWORK")
    supportersBtn.icon1 = icon1
    P.Point(supportersBtn.icon1, "TOPLEFT", 1, -1)
    P.Size(icon1, iconSize, iconSize)
    icon1:SetTexture(tex)
    icon1:SetVertexColor(0.5, 0.5, 0.5)

    -- 右下角装饰图标（与左上角形成对角线对称）
    local icon2 = supportersBtn:CreateTexture(nil, "ARTWORK")
    supportersBtn.icon2 = icon2
    P.Point(supportersBtn.icon2, "BOTTOMRIGHT", -1, 1)
    P.Size(icon2, iconSize, iconSize)
    icon2:SetTexture(tex)
    icon2:SetVertexColor(0.5, 0.5, 0.5)

    -- 为按钮附加淡入淡出动画
    CreateAnimation(supportersBtn)

    return supportersBtn
end

-- 面板：支持者名单（带展开/收起动画的侧滑面板）
-- 位于"关于"主面板的右侧，初始隐藏。包含两类支持者（sponsor和patron）的滚动列表
-- 通过两个按钮（打开/关闭）配合淡入淡出动画实现展开和收起
local function CreateSupportersPane()
    -- 主容器面板，初始隐藏于 aboutTab 右侧
    local supportersPane = Cell.CreateTitledPane(aboutTab, "", 100, 100)
    supportersPane:SetPoint("TOPLEFT", aboutTab, "TOPRIGHT", 6, -5)
    supportersPane:SetPoint("BOTTOMLEFT", aboutTab, "BOTTOMRIGHT", 6, 5)
    supportersPane:Hide()

    -- 为面板附加淡入淡出动画
    CreateAnimation(supportersPane)

    -- 右上角爱心图标装饰
    local heartIcon = supportersPane:CreateTexture(nil, "OVERLAY")
    heartIcon:SetPoint("TOPRIGHT")
    heartIcon:SetSize(16, 16)
    heartIcon:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\sparkling_heart")

    -- 背景渐变纹理：从深色到半透明深色的水平渐变
    local bgTex = supportersPane:CreateTexture(nil, "BACKGROUND", nil, 0)
    bgTex:SetPoint("TOPLEFT", -5, 5)
    bgTex:SetPoint("BOTTOMRIGHT", 5, -5)
    bgTex:SetTexture(Cell.vars.whiteTexture)
    bgTex:SetGradient("HORIZONTAL", CreateColor(0.1, 0.1, 0.1, 1), CreateColor(0.1, 0.1, 0.1, 0.7))

    -- 第一列支持者滚动框（sponsor 列表）
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

    -- 第二列支持者滚动框（patron 列表）
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

    -- 显示后通过 OnUpdate 动态更新面板和各列的宽度以适配文本内容
    -- 在 0.5 秒的累积时间内持续刷新尺寸，之后移除 OnUpdate 以节省性能
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

    -- 打开按钮（右侧"Supporters"竖排彩虹文字按钮）
    local supportersBtn1 = CreateButton(17, 157, [[Interface\AddOns\Cell\Media\Icons\right]])
    supportersBtn1:SetPoint("TOPLEFT", aboutTab, "TOPRIGHT", 1, -5)

    -- 将按钮文字旋转 90 度使其竖排显示
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

    -- 关闭按钮（小号的左箭头，位于面板顶部）
    local supportersBtn2 = CreateButton(17, 17, [[Interface\AddOns\Cell\Media\Icons\left]])
    -- supportersBtn2:SetPoint("TOPLEFT", aboutTab, "TOPRIGHT", 6, -5)
    supportersBtn2:SetPoint("TOPLEFT", supportersPane)
    supportersBtn2:SetPoint("TOPRIGHT", supportersPane, P.Scale(-20), 0)
    supportersBtn2:Hide()

    -- 点击打开按钮：淡出打开按钮，淡入关闭按钮和支持者面板
    supportersBtn1:SetScript("OnClick", function()
        if supportersBtn1.fadeOut:IsPlaying() or supportersBtn1.fadeIn:IsPlaying() then return end
        supportersBtn1.fadeOut:Play()
        supportersBtn2.fadeIn:Play()
        supportersPane.fadeIn:Play()
    end)

    -- 点击关闭按钮：淡入打开按钮，淡出关闭按钮和支持者面板
    supportersBtn2:SetScript("OnClick", function()
        if supportersBtn2.fadeOut:IsPlaying() or supportersBtn2.fadeIn:IsPlaying() then return end
        supportersBtn1.fadeIn:Play()
        supportersBtn2.fadeOut:Play()
        supportersPane.fadeOut:Play()
    end)
end

-------------------------------------------------
-- 面板：链接（GitHub 等）
-- 包含可点击的图标链接和一个只读编辑框，通过鼠标悬停切换编辑框中的链接文本
-------------------------------------------------
local links = {}

-- 创建一个链接图标 Frame
-- parent: 父容器, id: 唯一标识（用于互斥高亮）, icon: 图标纹理路径, onEnter: 额外的 OnEnter 回调
local function CreateLink(parent, id, icon, onEnter)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    P.Size(f, 34, 34)
    f:SetBackdrop({bgFile = Cell.vars.whiteTexture})
    f:SetBackdropColor(0, 0, 0, 1)

    links[id] = f

    -- 图标纹理，铺满整个 Frame 内部
    f.icon = f:CreateTexture(nil, "ARTWORK")
    P.Point(f.icon, "TOPLEFT", 1, -1)
    P.Point(f.icon, "BOTTOMRIGHT", -1, 1)
    f.icon:SetTexture(icon)

    -- 鼠标悬停时用主题强调色高亮当前链接，并重置其他链接为黑色背景
    f:SetScript("OnEnter", function()
        f:SetBackdropColor(Cell.GetAccentColorRGB())
        for  _id, _f in pairs(links) do
            if _id ~= id then
                _f:SetBackdropColor(0, 0, 0, 1)
            end
        end
        if onEnter then onEnter() end
    end)

    -- 隐藏时恢复背景为黑色
    f:SetScript("OnHide", function()
        f:SetBackdropColor(0, 0, 0, 1)
    end)

    return f
end

local function CreateLinksPane()
    local linksPane = Cell.CreateTitledPane(aboutTab, L["Links"], 422, 100)
    linksPane:SetPoint("TOPLEFT", aboutTab, "TOPLEFT", 5, -490)

    -- 保存当前链接 URL，用于防止用户编辑后重置回正确地址
    local current

    -- 只读风格的编辑框：用户无法手动修改内容，修改会被自动还原
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
    -- 点击编辑框时选中全部文本方便复制
    linksEB:SetScript("OnMouseUp", function(self)
        linksEB:HighlightText()
    end)

    -- GitHub 链接图标（CellD 仓库）
    local github = CreateLink(linksPane, "github", "Interface\\AddOns\\Cell\\Media\\Links\\github.tga", function()
        current = "https://github.com/davidchangok/CellD"
        linksEB:SetText(current)
        linksEB:ClearFocus()
    end)
    github:SetPoint("TOPLEFT", linksEB, "BOTTOMLEFT", 0, -7)

    -- 首次显示时自动触发 GitHub 链接的 OnEnter 回调以填充编辑框
    linksEB:SetScript("OnShow", function()
        github:GetScript("OnEnter")()
    end)
end

-------------------------------------------------
-- 面板：导入/导出全部设置
-- 位于"关于"页底部，提供导入、导出和备份三个操作按钮
-------------------------------------------------
local function CreateImportExportPane()
    local iePane = Cell.CreateTitledPane(aboutTab, L["Import & Export All Settings"], 422, 50)
    iePane:SetPoint("BOTTOMLEFT", 5, 5)

    -- 导入按钮：调用 F.ShowImportFrame 打开导入界面
    local importBtn = Cell.CreateButton(iePane, L["Import"], "accent-hover", {134, 20})
    importBtn:SetPoint("TOPLEFT", 5, -27)
    importBtn:SetScript("OnClick", F.ShowImportFrame)
    importBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\import", {16, 16}, {"LEFT", 2, 0})

    -- 导出按钮：调用 F.ShowExportFrame 打开导出界面
    local exportBtn = Cell.CreateButton(iePane, L["Export"], "accent-hover", {134, 20})
    exportBtn:SetPoint("TOPLEFT", importBtn, "TOPRIGHT", 5, 0)
    exportBtn:SetScript("OnClick", F.ShowExportFrame)
    exportBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\export", {16, 16}, {"LEFT", 2, 0})

    -- 备份按钮：调用 F.ShowBackupFrame 打开备份管理界面
    local backupBtn = Cell.CreateButton(iePane, L["Backups"], "accent-hover", {134, 20})
    backupBtn:SetPoint("TOPLEFT", exportBtn, "TOPRIGHT", 5, 0)
    backupBtn:SetScript("OnClick", F.ShowBackupFrame)
    backupBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\backup", {16, 16}, {"LEFT", 2, 0})
end

-------------------------------------------------
-- 核心控制逻辑：标签页切换、字体更新
-------------------------------------------------

-- 标记是否已完成首次初始化（懒加载：只有首次切换到 about 标签页时才创建 UI）
local init
local function ShowTab(tab)
    if tab == "about" then
        -- 首次切换到 about 标签页时创建所有子面板（懒初始化）
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
        -- 显示 about 标签页并动态更新标题为 "CellD <版本号>"
        aboutTab:Show()
        descriptionPane:SetTitle("CellD "..Cell.version)
    else
        -- 切换到其他标签页时隐藏 about 页面
        aboutTab:Hide()
    end
end
-- 注册回调：当选项窗口切换到 about 标签页时触发 ShowTab
Cell.RegisterCallback("ShowOptionsTab", "AboutTab_ShowTab", ShowTab)

-- 更新单个 FontString 的字体、大小、颜色和阴影
-- fs: 需包含 .font（字体名）和 .size（字号）属性的 FontString 对象
-- 字号会加上全局选项中的字体偏移量（optionsFontSizeOffset）
UpdateFont = function(fs)
    if not fs then return end
    fs:SetFont(fs.font, fs.size + (CellDB["appearance"]["optionsFontSizeOffset"] or 0), "")
    fs:SetTextColor(1, 1, 1, 1)
    fs:SetShadowColor(0, 0, 0)
    fs:SetShadowOffset(1, -1)
end

-- 全局字体更新入口：当用户调整选项字体大小时被调用
-- 重新应用字体设置到 about 面板中所有受管理的 FontString 对象
function Cell.UpdateAboutFont(offset)
    UpdateFont(originalAuthorText)
    UpdateFont(authorText)
    UpdateFont(supportersText1)
    UpdateFont(supportersText2)
end