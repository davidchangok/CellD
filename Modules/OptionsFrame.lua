-- ================================================================
-- OptionsFrame 模块
-- Cell 的设置面板主窗口，包含标签页切换、拖拽移动、战斗保护、
-- 外部入口等功能。所有设置子面板通过标签按钮切换显示。
-- ================================================================
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 记录当前显示的标签页 ID，用于避免重复切换同一标签页
local lastShownTab

-- 创建设置面板主窗口，尺寸 432x401，锚定到主框架中央
local optionsFrame = Cell.CreateFrame("CellOptionsFrame", Cell.frames.mainFrame, 432, 401)
Cell.frames.optionsFrame = optionsFrame
PixelUtil.SetPoint(optionsFrame, "CENTER", CellParent, "CENTER", 1, -1)
optionsFrame:SetFrameStrata("DIALOG")
optionsFrame:SetFrameLevel(520)
optionsFrame:SetClampedToScreen(true)          -- 限制窗口不超出屏幕边界
optionsFrame:SetClampRectInsets(0, 0, 40, 0)  -- 底部留出 40px 余量（避免遮挡操作栏）
optionsFrame:SetMovable(true)

-- 为指定按钮注册拖拽功能，使设置面板可通过标签按钮拖动
-- 拖拽开始：StartMoving，并标记为非用户放置（避免系统自动保存位置）
-- 拖拽结束：执行像素级对齐并保存位置到数据库
local function RegisterDragForOptionsFrame(frame)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        optionsFrame:StartMoving()
        optionsFrame:SetUserPlaced(false)
    end)
    frame:SetScript("OnDragStop", function()
        optionsFrame:StopMovingOrSizing()
        P.PixelPerfectPoint(optionsFrame)
        P.SavePosition(optionsFrame, CellDB["optionsFramePosition"])
    end)
end

-------------------------------------------------
-- 标签按钮组：在设置面板顶部创建两行标签按钮
-- 第一行：布局 | 指示器 | 团队减益 | 工具 | （关闭按钮）
-- 第二行：常规 | 外观 | 点击施法 | 关于
-- 所有标签按钮均支持拖拽（除关闭按钮外）
-------------------------------------------------
local generalBtn, appearanceBtn, clickCastingsBtn, aboutBtn, layoutsBtn, indicatorsBtn, debuffsBtn, utilitiesBtn, closeBtn

-- 创建所有标签按钮、设置布局、绑定交互逻辑
local function CreateTabButtons()
    -- 创建各个标签按钮（文本, 颜色主题, 尺寸, ...）
    generalBtn = Cell.CreateButton(optionsFrame, L["General"], "accent-hover", {105, 20}, false, false, "CELL_FONT_WIDGET_TITLE", "CELL_FONT_WIDGET_TITLE_DISABLE")
    appearanceBtn = Cell.CreateButton(optionsFrame, L["Appearance"], "accent-hover", {105, 20}, false, false, "CELL_FONT_WIDGET_TITLE", "CELL_FONT_WIDGET_TITLE_DISABLE")
    layoutsBtn = Cell.CreateButton(optionsFrame, L["Layouts"], "accent-hover", {105, 20}, false, false, "CELL_FONT_WIDGET_TITLE", "CELL_FONT_WIDGET_TITLE_DISABLE")
    clickCastingsBtn = Cell.CreateButton(optionsFrame, L["Click-Castings"], "accent-hover", {120, 20}, false, false, "CELL_FONT_WIDGET_TITLE", "CELL_FONT_WIDGET_TITLE_DISABLE")
    indicatorsBtn = Cell.CreateButton(optionsFrame, L["Indicators"], "accent-hover", {105, 20}, false, false, "CELL_FONT_WIDGET_TITLE", "CELL_FONT_WIDGET_TITLE_DISABLE")
    debuffsBtn = Cell.CreateButton(optionsFrame, L["Raid Debuffs"], "accent-hover", {120, 20}, false, false, "CELL_FONT_WIDGET_TITLE", "CELL_FONT_WIDGET_TITLE_DISABLE")
    utilitiesBtn = Cell.CreateButton(optionsFrame, L["Utilities"], "accent-hover", {105, 20}, false, false, "CELL_FONT_WIDGET_TITLE", "CELL_FONT_WIDGET_TITLE_DISABLE")
    aboutBtn = Cell.CreateButton(optionsFrame, L["About"], "accent-hover", {86, 20}, false, false, "CELL_FONT_WIDGET_TITLE", "CELL_FONT_WIDGET_TITLE_DISABLE")
    -- 关闭按钮使用红色主题和特殊字体
    closeBtn = Cell.CreateButton(optionsFrame, "×", "red", {20, 20}, false, false, "CELL_FONT_SPECIAL", "CELL_FONT_SPECIAL")
    closeBtn:SetScript("OnClick", function()
        optionsFrame:Hide()
    end)

    -- 第一行按钮：布局、指示器、团队减益、工具（从左到右排列在面板顶部上缘）
    layoutsBtn:SetPoint("BOTTOMLEFT", optionsFrame, "TOPLEFT", 0, P.Scale(-1))
    indicatorsBtn:SetPoint("BOTTOMLEFT", layoutsBtn, "BOTTOMRIGHT", P.Scale(-1), 0)
    debuffsBtn:SetPoint("BOTTOMLEFT", indicatorsBtn, "BOTTOMRIGHT", P.Scale(-1), 0)
    utilitiesBtn:SetPoint("BOTTOMLEFT", debuffsBtn, "BOTTOMRIGHT", P.Scale(-1), 0)
    utilitiesBtn:SetPoint("BOTTOMRIGHT", optionsFrame, "TOPRIGHT", 0, P.Scale(-1))
    -- 第二行按钮：常规、外观、点击施法、关于（紧贴第一行上方）
    generalBtn:SetPoint("BOTTOMLEFT", layoutsBtn, "TOPLEFT", 0, P.Scale(-1))
    appearanceBtn:SetPoint("BOTTOMLEFT", generalBtn, "BOTTOMRIGHT", P.Scale(-1), 0)
    clickCastingsBtn:SetPoint("BOTTOMLEFT", appearanceBtn, "BOTTOMRIGHT", P.Scale(-1), 0)
    aboutBtn:SetPoint("BOTTOMLEFT", clickCastingsBtn, "BOTTOMRIGHT", P.Scale(-1), 0)
    closeBtn:SetPoint("BOTTOMLEFT", aboutBtn, "BOTTOMRIGHT", P.Scale(-1), 0)
    closeBtn:SetPoint("BOTTOMRIGHT", utilitiesBtn, "TOPRIGHT", 0, P.Scale(-1))

    -- 为所有标签按钮注册拖拽（用户可通过拖拽标签来移动设置面板）
    RegisterDragForOptionsFrame(generalBtn)
    RegisterDragForOptionsFrame(appearanceBtn)
    RegisterDragForOptionsFrame(layoutsBtn)
    RegisterDragForOptionsFrame(clickCastingsBtn)
    RegisterDragForOptionsFrame(indicatorsBtn)
    RegisterDragForOptionsFrame(debuffsBtn)
    RegisterDragForOptionsFrame(utilitiesBtn)
    RegisterDragForOptionsFrame(aboutBtn)

    -- 为每个按钮分配标识 ID，用于后续逻辑判断和事件触发
    generalBtn.id = "general"
    appearanceBtn.id = "appearance"
    layoutsBtn.id = "layouts"
    clickCastingsBtn.id = "clickCastings"
    indicatorsBtn.id = "indicators"
    debuffsBtn.id = "debuffs"
    utilitiesBtn.id = "utilities"
    aboutBtn.id = "about"

    -- 各标签页对应面板高度，切换标签时动态调整窗口尺寸
    local tabHeight = {
        ["general"] = 535,
        ["appearance"] = 665,
        ["layouts"] = 550,
        ["clickCastings"] = 592,
        ["indicators"] = 607,
        ["debuffs"] = 521,
        ["utilities"] = 400,
        ["about"] = 650,
    }

    -- 切换标签页：如果目标标签与当前不同，调整面板高度并触发 ShowOptionsTab 事件
    local function ShowTab(tab)
        if lastShownTab ~= tab then
            P.Height(optionsFrame, tabHeight[tab])
            Cell.Fire("ShowOptionsTab", tab)
            lastShownTab = tab
        end
    end

    -- 鼠标进入按钮：工具按钮显示下拉列表，其他按钮隐藏列表；同时取消待执行的隐藏计时器
    local function OnEnter(b)
        if b.id == utilitiesBtn.id then
            F.ShowUtilityList(b)
        else
            F.HideUtilityList()
        end
        if utilitiesBtn.timer then
            utilitiesBtn.timer:Cancel()
            utilitiesBtn.timer = nil
        end
    end

    -- 鼠标离开按钮：工具按钮延迟 0.5 秒后检查鼠标是否仍在列表上，若不在则隐藏
    local function OnLeave(b)
        if b.id == utilitiesBtn.id then
            utilitiesBtn.timer = C_Timer.NewTicker(0.5, function()
                if not F.IsUtilityListMouseover() then
                    F.HideUtilityList()
                    utilitiesBtn.timer:Cancel()
                    utilitiesBtn.timer = nil
                end
            end)
        end
    end

    -- 将按钮注册为互斥组并绑定 hover/click 回调
    Cell.CreateButtonGroup({generalBtn, appearanceBtn, layoutsBtn, clickCastingsBtn, indicatorsBtn, debuffsBtn, utilitiesBtn, aboutBtn}, ShowTab, nil, nil, OnEnter, OnLeave)
end

-------------------------------------------------
-- 显示与隐藏逻辑
-- 包含懒初始化、切换显示、位置加载/保存、垃圾回收等功能
-------------------------------------------------
-- 懒初始化标记：首次调用 Init 时才真正创建 UI 元素
local init
local function Init()
    if not init then
        init = true
        P.Resize(optionsFrame)          -- 应用像素级缩放
        P.Reborder(optionsFrame, true)  -- 重绘边框
        CreateTabButtons()              -- 创建标签按钮组
        F.CreateUtilityList(utilitiesBtn) -- 创建工具下拉列表（挂载到工具按钮）
    end
end

-- 切换设置面板显示/隐藏
-- 若面板已显示则隐藏；若未显示则执行懒初始化、默认选中"常规"标签并显示
function F.ShowOptionsFrame()
    Init()

    if optionsFrame:IsShown() then
        optionsFrame:Hide()
        return
    end

    if not lastShownTab then
        generalBtn:Click()
    end

    optionsFrame:Show()
end

-- 面板显示时：尝试从数据库恢复上次保存的位置，若失败则执行像素级居中
optionsFrame:SetScript("OnShow", function()
    if not P.LoadPosition(optionsFrame, CellDB["optionsFramePosition"]) then
        P.PixelPerfectPoint(optionsFrame)
    end
end)

-- 面板隐藏时：在非战斗状态下执行 Lua 垃圾回收以释放内存
-- 参考 DBM 的做法，但注释掉了 UpdateAddOnMemoryUsage() 因为会严重卡顿
optionsFrame:SetScript("OnHide", function()
    -- stolen from dbm
    if not InCombatLockdown() and not UnitAffectingCombat("player") and not IsFalling() then
        F.Debug("|cffbbbbbbCellOptionsFrame_OnHide: |cffff7777collectgarbage")
        collectgarbage("collect")
        -- UpdateAddOnMemoryUsage() -- stuck like hell
    end
end)

-- 外部入口：从团队减益导入流程打开设置面板并跳转到团队减益标签
function F.ShowRaidDebuffsTab()
    Init()
    optionsFrame:Show()
    debuffsBtn:Click()
end

-- 外部入口：从布局导入流程打开设置面板并跳转到布局标签
function F.ShowLayousTab()
    Init()
    optionsFrame:Show()
    layoutsBtn:Click()
end

-- 外部入口：打开设置面板并跳转到工具标签
function F.ShowUtilitiesTab()
    Init()
    optionsFrame:Show()
    utilitiesBtn:Click()
end

-------------------------------------------------
-- 战斗锁定保护系统
-- 防止在战斗中修改受保护的 UI 元素（违反 Blizzard 安全限制）
-- 分为两类保护：帧（覆盖遮罩）和控件（禁用交互）
-------------------------------------------------
-- 受战斗保护的帧列表：战斗中会被遮罩覆盖，阻止用户交互
local protectedFrames = {}
-- 为指定帧应用战斗保护：创建遮罩层并在进入战斗时显示
-- x1,y1,x2,y2 定义遮罩覆盖区域（相对于父框架的偏移）
function F.ApplyCombatProtectionToFrame(f, x1, y1, x2, y2)
    tinsert(protectedFrames, f)
    Cell.CreateCombatMask(f, x1, y1, x2, y2)

    -- 如果调用时已在战斗中，立即显示遮罩
    if InCombatLockdown() then
        f.combatMask:Show()
    end

    -- 钩子：当帧显示时检查战斗状态，确保战斗中始终覆盖
    f:HookScript("OnShow", function()
        if InCombatLockdown() then
            f.combatMask:Show()
        end
    end)
end

-- 受战斗保护的控件列表：战斗中会被禁用
local protectedWidgets = {}
-- 为指定控件应用战斗保护：战斗中禁用控件
function F.ApplyCombatProtectionToWidget(widget)
    tinsert(protectedWidgets, widget)

    if InCombatLockdown() then
        widget:SetEnabled(false)
    end
end

-- 注册战斗状态事件，统一管理所有受保护帧和控件的状态切换
optionsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- 进入战斗
optionsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- 离开战斗
optionsFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- 进入战斗：显示所有保护遮罩，禁用所有保护控件
        for _, f in pairs(protectedFrames) do
            f.combatMask:Show()
        end
        for _, w in pairs(protectedWidgets) do
            w:SetEnabled(false)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- 离开战斗：隐藏所有保护遮罩，启用所有保护控件
        for _, f in pairs(protectedFrames) do
            f.combatMask:Hide()
        end
        for _, w in pairs(protectedWidgets) do
            w:SetEnabled(true)
        end
    end
end)

-------------------------------------------------
-- 回调注册
-------------------------------------------------
-- 响应全局像素级更新事件，重新计算设置面板的缩放尺寸
local function UpdatePixelPerfect()
    P.Resize(optionsFrame)
end
Cell.RegisterCallback("UpdatePixelPerfect", "OptionsFrame_UpdatePixelPerfect", UpdatePixelPerfect)