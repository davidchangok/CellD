-- ============================================================================
-- CellD 点击施法配置导入导出模块
-- 提供点击施法配置的导入（粘贴编码字符串）和导出（生成可分享的编码字符串）功能
-- 编码管道：Lua表 → LibSerialize序列化 → Deflate压缩 → Base64编码（导出）
-- 解码管道：Base64解码 → Deflate解压 → LibSerialize反序列化 → Lua表（导入）
-- ============================================================================
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 序列化/压缩库：LibSerialize 负责 Lua 表序列化，LibDeflate 负责压缩和 Base64 编码，压缩级别 9 为最高压缩比
local Serializer = LibStub:GetLibrary("LibSerialize")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local deflateConfig = {level = 9}

-- 导入导出面板的状态标记：isImport 标识当前是导入模式还是导出模式，imported 暂存解析后的导入数据，exported 缓存序列化后的导出字符串
local isImport, imported, exported = false, {}, ""

-- UI 控件引用：importExportFrame 为主面板，importBtn 为导入确认按钮，title 为标题文本，textArea 为可滚动编辑框
local importExportFrame, importBtn, title, textArea

-- 执行导入操作：将解析后的点击施法配置数据写入到当前专精或通用配置中，然后刷新界面并关闭导入面板
local function DoImport()
    -- 根据用户设置：如果启用了通用配置则写入 common，否则写入当前专精 ID 对应的配置
    if Cell.vars.clickCastings["useCommon"] then
        Cell.vars.clickCastings["common"] = imported
    else
        Cell.vars.clickCastings[Cell.vars.playerSpecID] = imported
    end

    -- 触发点击施法界面刷新事件，使导入的配置立即生效
    Cell.Fire("UpdateClickCastings")
    importExportFrame:Hide()
end

-- 创建点击施法导入导出面板：包含标题栏、关闭按钮、导入按钮、文本编辑区域以及遮罩层，支持导入和导出两种模式共用同一个界面
local function CreateClickCastingImportExportFrame()
    importExportFrame = CreateFrame("Frame", "CellOptionsFrame_ClickCastingsImportExport", Cell.frames.clickCastingsTab, "BackdropTemplate")
    importExportFrame:Hide()
    Cell.StylizeFrame(importExportFrame, nil, Cell.GetAccentColorTable())
    importExportFrame:EnableMouse(true)
    importExportFrame:SetFrameLevel(Cell.frames.clickCastingsTab:GetFrameLevel() + 50)
    P.Size(importExportFrame, 430, 170)
    importExportFrame:SetPoint("TOPLEFT", P.Scale(1), -160)

    -- 创建遮罩层：覆盖在点击施法标签页上方，阻止用户操作底层控件，仅在导入导出面板显示时可见
    if not Cell.frames.clickCastingsTab.mask then
        Cell.CreateMask(Cell.frames.clickCastingsTab, nil, {1, -1, -1, 1})
        Cell.frames.clickCastingsTab.mask:Hide()
    end

    -- 关闭按钮：点击隐藏导入导出面板
    local closeBtn = Cell.CreateButton(importExportFrame, "×", "red", {18, 18}, false, false, "CELL_FONT_SPECIAL", "CELL_FONT_SPECIAL")
    closeBtn:SetPoint("TOPRIGHT", P.Scale(-5), P.Scale(-1))
    closeBtn:SetScript("OnClick", function() importExportFrame:Hide() end)

    -- 导入按钮：仅在导入模式下显示，点击后弹出确认对话框，确认后将解析的数据写入配置
    importBtn = Cell.CreateButton(importExportFrame, L["Import"], "green", {57, 18})
    importBtn:Hide()
    importBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", P.Scale(1), 0)
    importBtn:SetScript("OnClick", function()
        -- 降低面板层级，使确认弹窗显示在面板上方
        importExportFrame:SetFrameLevel(Cell.frames.clickCastingsTab:GetFrameLevel() + 20)

        -- 弹出覆盖确认对话框，防止误操作覆盖现有配置
        local popup = Cell.CreateConfirmPopup(Cell.frames.clickCastingsTab, 200, L["Overwrite Click-Casting"].."?", function(self)
            DoImport()
        end, nil, true)
        popup:SetPoint("TOPLEFT", importExportFrame, 117, -50)
        textArea.eb:ClearFocus()
    end)

    -- 标题文本：显示当前模式（导入/导出）及职业信息，导入出错时以红色显示错误原因
    title = importExportFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    title:SetPoint("TOPLEFT", 5, -5)

    -- 文本编辑区域：导入模式下用户粘贴编码字符串并自动解析，导出模式下显示已编码的配置数据并自动全选
    textArea = Cell.CreateScrollEditBox(importExportFrame, function(eb, userChanged)
        if userChanged then
            if isImport then
                imported = {}
                local text = eb:GetText()
                -- 解析导入字符串：格式为 !CELL:版本号:CLICKCASTING:职业英文名!Base64编码数据
                -- 依次进行格式匹配 → 版本校验 → Base64解码 → Deflate解压 → LibSerialize反序列化
                local version, class, data = string.match(text, "^!CELL:(%d+):CLICKCASTING:(.+)!(.+)$")
                version = tonumber(version)

                if class and version and data then
                    if version >= Cell.MIN_CLICKCASTINGS_VERSION then
                        local success
                        -- 三步还原管道：Base64解码 → Deflate解压 → LibSerialize反序列化为Lua表
                        data = LibDeflate:DecodeForPrint(data) -- 第一步：Base64 解码为二进制字符串
                        success, data = pcall(LibDeflate.DecompressDeflate, LibDeflate, data) -- 第二步：Deflate 解压缩
                        success, data = Serializer:Deserialize(data) -- 第三步：反序列化为 Lua 表

                        if success and data then
                            title:SetText(L["Import"]..": "..F.GetClassColorStr(class)..F.GetLocalizedClassName(class))
                            imported = data
                            -- 仅当导入数据与当前角色职业相同时才允许导入，防止跨职业配置错误
                            importBtn:SetEnabled(class == Cell.vars.playerClass)
                        else
                            -- 反序列化失败：数据损坏或格式不兼容
                            title:SetText(L["Import"]..": |cffff2222"..L["Error"])
                            importBtn:SetEnabled(false)
                        end
                    else
                        -- 版本低于最低兼容版本：数据来自旧版插件，结构可能不兼容
                        title:SetText(L["Import"]..": |cffff2222"..L["Incompatible Version"])
                        importBtn:SetEnabled(false)
                    end
                else
                    -- 格式不匹配：输入的字符串不符合 !CELL:版本号:CLICKCASTING:职业!数据 的格式
                    title:SetText(L["Import"]..": |cffff2222"..L["Error"])
                    importBtn:SetEnabled(false)
                end
            else
                -- 导出模式下用户手动编辑了文本框，恢复为原始导出字符串并全选，方便复制
                eb:SetText(exported)
                eb:SetCursorPosition(0)
                eb:HighlightText()
            end
        end
    end)
    Cell.StylizeFrame(textArea.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    textArea:SetPoint("TOPLEFT", P.Scale(5), P.Scale(-20))
    textArea:SetPoint("BOTTOMRIGHT", P.Scale(-5), P.Scale(5))

    -- 自动全选文本：获得焦点时全选，导出模式下点击也全选，方便用户一键复制导出字符串
    textArea.eb:SetScript("OnEditFocusGained", function() textArea.eb:HighlightText() end)
    textArea.eb:SetScript("OnMouseUp", function()
        if not isImport then
            textArea.eb:HighlightText()
        end
    end)

    -- 面板隐藏时的事件处理：重置所有状态变量，清空导入导出数据，并隐藏遮罩层
    importExportFrame:SetScript("OnHide", function()
        importExportFrame:Hide()
        isImport = false
        exported = ""
        imported = {}
        -- 隐藏遮罩层，恢复底部点击施法面板的交互
        Cell.frames.clickCastingsTab.mask:Hide()
    end)

    -- 面板显示时的事件处理：提升面板层级确保显示在最前，并显示遮罩层阻挡底层点击
    importExportFrame:SetScript("OnShow", function()
        -- 提升面板层级，确保导入导出面板显示在点击施法配置界面的最上层
        importExportFrame:SetFrameLevel(Cell.frames.clickCastingsTab:GetFrameLevel() + 50)
        Cell.frames.clickCastingsTab.mask:Show()
    end)
end

-- 懒初始化标记：确保导入导出面板只在第一次使用时创建，避免不必要的资源消耗
local init
-- 显示点击施法导入面板：切换到导入模式，清空文本框等待用户粘贴编码字符串
function F.ShowClickCastingImportFrame()
    if not init then
        init = true
        CreateClickCastingImportExportFrame()
    end

    importExportFrame:Show()
    isImport = true
    importBtn:Show()
    importBtn:SetEnabled(false)

    exported = ""
    title:SetText(L["Import"])
    textArea:SetText("")
    textArea.eb:SetFocus(true)
end

-- 显示点击施法导出面板：将当前配置序列化→压缩→Base64编码，生成可分享的导入字符串，并自动全选方便复制
function F.ShowClickCastingExportFrame(clickCastingTable)
    if not init then
        init = true
        CreateClickCastingImportExportFrame()
    end

    importExportFrame:Show()
    isImport = false
    importBtn:Hide()

    title:SetText(L["Export"]..": "..F.GetClassColorStr(Cell.vars.playerClass)..F.GetLocalizedClassName(Cell.vars.playerClass))

    -- 导出数据前缀：!CELL:插件版本号:CLICKCASTING:职业英文名! 用于导入时校验版本和职业
    local prefix = "!CELL:"..Cell.versionNum..":CLICKCASTING:"..Cell.vars.playerClass.."!"

    -- 三步编码管道：LibSerialize序列化 → Deflate压缩 → Base64编码为可打印字符串
    exported = Serializer:Serialize(clickCastingTable) -- 第一步：Lua 表序列化为字符串
    exported = LibDeflate:CompressDeflate(exported, deflateConfig) -- 第二步：Deflate 压缩
    exported = LibDeflate:EncodeForPrint(exported) -- 第三步：Base64 编码为可打印字符串
    exported = prefix..exported

    textArea:SetText(exported)
    textArea.eb:SetFocus(true)
end