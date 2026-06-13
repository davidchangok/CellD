-- 布局导入导出模块：提供布局数据的导入/导出功能，
-- 支持通过字符串（序列化+压缩+编码）传递布局数据，
-- 并提供 UI 面板供用户手动复制粘贴布局字符串。
-- 同时暴露 Cell.ImportLayout() API 供"安装器"插件直接调用。
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 序列化库：将 Lua 表序列化为字符串
local Serializer = LibStub:GetLibrary("LibSerialize")
-- 压缩/编码库：对序列化后的字符串进行压缩和 Base64 编码
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local deflateConfig = {level = 9} -- 压缩等级 9（最高压缩比）

-- isImport: 当前面板模式 true=导入模式 false=导出模式
-- imported: 解析后的导入数据 {name=布局名, data=布局表}
-- exported: 导出时生成的完整字符串（含前缀+编码数据）
local isImport, imported, exported = false, {}, ""

-- UI 控件引用：导入导出面板、导入按钮、标题文本、文本编辑区域
local importExportFrame, importBtn, title, textArea

---执行实际的布局导入操作
---处理导入数据的清洗、补全和最终写入 CellDB["layouts"]
---@param overwriteExisting boolean true=覆盖同名布局 false=创建带编号的新布局
local function DoImport(overwriteExisting)
    local name, layout = imported["name"], imported["data"]

    -- 清洗导入的 indicators 数据：
    -- 1）移除当前客户端不支持的内建指示器（built-in 类型）
    -- 2）清理自定义指示器中无效的法术 ID
    local builtInFound = {}
    for i =  #layout["indicators"], 1, -1 do
        if layout["indicators"][i]["type"] == "built-in" then -- remove unsupported built-in
            local indicatorName = layout["indicators"][i]["indicatorName"]
            builtInFound[indicatorName] = true
            if not Cell.defaults.indicatorIndices[indicatorName] then
                tremove(layout["indicators"], i)
            end
        else -- remove invalid spells from custom indicators
            F.FilterInvalidSpells(layout["indicators"][i]["auras"])
        end
    end

    -- 修复 powerFilters 数据类型不匹配：
    -- 遍历所有职业，如果导入的 powerFilters 类型与默认值不一致则用默认值替换
    for class, t in pairs(Cell.defaults.layout.powerFilters) do
        if type(layout["powerFilters"][class]) ~= type(t) then
            if type(t) == "table" then
                layout["powerFilters"][class] = F.Copy(t)
            else
                layout["powerFilters"][class] = true
            end
        end
    end

    -- 补全缺失的内建指示器：
    -- 如果导入的布局中缺少某些当前版本支持的内建指示器，
    -- 按默认位置插入，保证布局完整性
    if F.Getn(builtInFound) ~= Cell.defaults.builtIns then
        for indicatorName, index in pairs(Cell.defaults.indicatorIndices) do
            if not builtInFound[indicatorName] then
                tinsert(layout["indicators"], index, Cell.defaults.layout.indicators[index])
            end
        end
    end

    -- texplore(imported.data)

    if overwriteExisting then
        -- 覆盖模式：直接覆写同名布局（常用于首次导入或用户确认覆盖）
        CellDB["layouts"][name] = layout
        Cell.Fire("LayoutImported", name) -- 触发 LayoutImported 事件，通知其他模块刷新
        if importExportFrame then
            importExportFrame:Hide()
        end
    else
        -- 新建模式：若布局名已存在，则在名称后追加递增编号（如 "MyLayout 2"）
        local i = 2
        repeat
            name = imported["name"].." "..i
            i = i + 1
        until not CellDB["layouts"][name]

        CellDB["layouts"][name] = layout
        Cell.Fire("LayoutImported", name)
        if importExportFrame then
            importExportFrame:Hide()
        end
    end
    F.Print(L["Layout imported: %s."]:format(name)) -- 打印导入成功提示
end

---创建布局导入/导出 UI 面板
---面板位于 layoutsTab 内，包含关闭按钮、导入按钮、标题和文本框
---仅在首次调用 ShowLayoutImportFrame/ShowLayoutExportFrame 时懒加载创建
local function CreateLayoutImportExportFrame()
    -- 创建导入导出面板 Frame
    importExportFrame = CreateFrame("Frame", "CellOptionsFrame_LayoutsImportExport", Cell.frames.layoutsTab, "BackdropTemplate")
    importExportFrame:Hide()
    Cell.StylizeFrame(importExportFrame, nil, Cell.GetAccentColorTable())
    importExportFrame:EnableMouse(true)
    importExportFrame:SetFrameLevel(Cell.frames.layoutsTab:GetFrameLevel() + 50) -- 高于 labelsTab 的层级，确保在最前
    P.Size(importExportFrame, 430, 170)
    importExportFrame:SetPoint("TOPLEFT", P.Scale(1), -100)

    -- 创建遮罩层：用于在面板显示时遮挡 layoutsTab 上的其他可交互控件
    if not Cell.frames.layoutsTab.mask then
        Cell.CreateMask(Cell.frames.layoutsTab, nil, {1, -1, -1, 1})
        Cell.frames.layoutsTab.mask:Hide()
    end

    -- 关闭按钮：红色"×"按钮，点击隐藏面板
    local closeBtn = Cell.CreateButton(importExportFrame, "×", "red", {18, 18}, false, false, "CELL_FONT_SPECIAL", "CELL_FONT_SPECIAL")
    closeBtn:SetPoint("TOPRIGHT", P.Scale(-5), P.Scale(-1))
    closeBtn:SetScript("OnClick", function() importExportFrame:Hide() end)

    -- 导入按钮：仅在导入模式下显示，点击后检查布局名是否存在，
    -- 若存在则弹出确认框让用户选择覆盖或新建，否则直接导入
    importBtn = Cell.CreateButton(importExportFrame, L["Import"], "green", {57, 18})
    importBtn:Hide()
    importBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", P.Scale(1), 0)
    importBtn:SetScript("OnClick", function()
        -- 降低面板层级，让弹出确认框能显示在面板上方
        importExportFrame:SetFrameLevel(Cell.frames.layoutsTab:GetFrameLevel() + 20)

        if CellDB["layouts"][imported["name"]] then
            -- 已存在同名布局：弹出确认框，绿色按钮覆盖，红色按钮创建新布局
            local text = L["Overwrite Layout"]..": "..(imported["name"] == "default" and _G.DEFAULT or imported["name"]).."?\n"..
                L["|cff1Aff1AYes|r - Overwrite"].."\n"..L["|cffff1A1ANo|r - Create New"]
            local popup = Cell.CreateConfirmPopup(Cell.frames.layoutsTab, 200, text, function(self)
                DoImport(true) -- 确认覆盖
            end, function(self)
                DoImport(false) -- 取消覆盖，创建新布局
            end, true)
            popup:SetPoint("TOPLEFT", importExportFrame, 117, -50)
            textArea.eb:ClearFocus() -- 清除文本框焦点，防止确认框文字输入到文本框
        else
            DoImport(true) -- 无同名布局，直接导入
        end
    end)

    -- 标题行：显示 "Import" 或 "Export: 布局名"
    title = importExportFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    title:SetPoint("TOPLEFT", 5, -5)

    -- 文本编辑区域：用于粘贴导入字符串或显示导出字符串
    -- 回调函数在文本变化时触发解析/校验
    textArea = Cell.CreateScrollEditBox(importExportFrame, function(eb, userChanged)
        if userChanged then
            if isImport then
                -- 导入模式：用户粘贴或输入布局字符串后自动解析
                imported = {}
                local text = eb:GetText()
                -- 解析格式：!CELL:版本号:LAYOUT:布局名!编码数据
                local version, name, data = string.match(text, "^!CELL:(%d+):LAYOUT:(.+)!(.+)$")
                version = tonumber(version)

                if name and version and data then
                    if version >= Cell.MIN_LAYOUTS_VERSION then -- 版本兼容性检查
                        local success
                        -- 三步还原：解码 -> 解压 -> 反序列化
                        data = LibDeflate:DecodeForPrint(data) -- Base64 解码
                        success, data = pcall(LibDeflate.DecompressDeflate, LibDeflate, data) -- Deflate 解压
                        success, data = Serializer:Deserialize(data) -- 反序列化为 Lua 表

                        if success and data then
                            title:SetText(L["Import"]..": "..(name == "default" and _G.DEFAULT or name))
                            importBtn:SetEnabled(true)
                            imported["name"] = name
                            imported["data"] = data
                        else
                            title:SetText(L["Import"]..": |cffff2222"..L["Error"]) -- 解析失败，红色错误提示
                            importBtn:SetEnabled(false)
                        end
                    else -- 不兼容的布局版本
                        title:SetText(L["Import"]..": |cffff2222"..L["Incompatible Version"])
                        importBtn:SetEnabled(false)
                    end
                else
                    title:SetText(L["Import"]..": |cffff2222"..L["Error"]) -- 无法匹配格式
                    importBtn:SetEnabled(false)
                end
            else
                -- 导出模式：用户修改文本时重置为导出内容（防止用户误改）
                eb:SetText(exported)
                eb:SetCursorPosition(0)
                eb:HighlightText() -- 全选文本便于复制
            end
        end
    end)
    Cell.StylizeFrame(textArea.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    textArea:SetPoint("TOPLEFT", P.Scale(5), P.Scale(-20))
    textArea:SetPoint("BOTTOMRIGHT", P.Scale(-5), P.Scale(5))

    -- 文本框获得焦点时自动全选，方便复制
    textArea.eb:SetScript("OnEditFocusGained", function() textArea.eb:HighlightText() end)
    -- 导出模式下鼠标点击文本框时自动全选
    textArea.eb:SetScript("OnMouseUp", function()
        if not isImport then
            textArea.eb:HighlightText()
        end
    end)

    -- 面板隐藏时重置状态并隐藏遮罩
    importExportFrame:SetScript("OnHide", function()
        importExportFrame:Hide()
        isImport = false
        exported = ""
        imported = {}
        -- 隐藏遮罩层
        Cell.frames.layoutsTab.mask:Hide()
    end)

    -- 面板显示时提升层级并显示遮罩
    importExportFrame:SetScript("OnShow", function()
        -- 确保面板显示在所有 layoutsTab 子控件上方
        importExportFrame:SetFrameLevel(Cell.frames.layoutsTab:GetFrameLevel() + 50)
        Cell.frames.layoutsTab.mask:Show()
    end)
end

-- init 标志：确保 UI 面板仅懒加载创建一次
local init

---显示导入面板
---用户可在此粘贴布局字符串，自动解析校验后点击导入按钮完成导入
function F.ShowLayoutImportFrame()
    if not init then
        init = true
        CreateLayoutImportExportFrame()
    end

    importExportFrame:Show()
    isImport = true
    importBtn:Show()
    importBtn:SetEnabled(false) -- 初始禁用，待解析成功后才启用

    exported = ""
    title:SetText(L["Import"])
    textArea:SetText("")
    textArea.eb:SetFocus(true)
end

---显示导出面板
---将指定布局序列化为可分享的字符串，用户可全选复制
---@param layoutName string 布局名称
---@param layoutTable table 布局数据表
function F.ShowLayoutExportFrame(layoutName, layoutTable)
    if not init then
        init = true
        CreateLayoutImportExportFrame()
    end

    importExportFrame:Show()
    isImport = false
    importBtn:Hide() -- 导出模式隐藏导入按钮

    title:SetText(L["Export"]..": "..(layoutName == "default" and _G.DEFAULT or layoutName))

    -- 构建前缀：!CELL:版本号:LAYOUT:布局名!
    local prefix = "!CELL:"..Cell.versionNum..":LAYOUT:"..layoutName.."!"

    -- 三步编码：序列化 -> 压缩 -> Base64 编码
    exported = Serializer:Serialize(layoutTable)
    exported = LibDeflate:CompressDeflate(exported, deflateConfig) -- Deflate 压缩（等级 9）
    exported = LibDeflate:EncodeForPrint(exported) -- Base64 编码
    exported = prefix..exported -- 拼接前缀与编码数据

    textArea:SetText(exported)
    textArea.eb:SetFocus(true) -- 自动聚焦，便于用户直接 Ctrl+C 复制
end

---------------------------------------------------------------------
-- 供 "installer" 类插件调用的编程接口
-- 其他插件可直接调用 Cell.ImportLayout() 导入布局字符串，
-- 无需经过 UI 面板
---------------------------------------------------------------------

---通过布局字符串导入布局（无需 UI 面板）
---供其他"安装器"插件直接调用，跳过用户手动粘贴步骤
---@param layoutString string 完整的布局编码字符串（格式: !CELL:版本:LAYOUT:名称!编码数据）
---@param overwriteExisting boolean 是否覆盖已存在的同名布局
---@return boolean success 导入是否成功
function Cell.ImportLayout(layoutString, overwriteExisting)
    -- 解析布局字符串：提取版本号、布局名和编码数据
    local version, name, data = string.match(layoutString, "^!CELL:(%d+):LAYOUT:(.+)!(.+)$")
    version = tonumber(version)

    if name and version and data then
        if version >= Cell.MIN_LAYOUTS_VERSION then -- 版本兼容性检查
            local success
            -- 三步还原：Base64 解码 -> Deflate 解压 -> 反序列化
            data = LibDeflate:DecodeForPrint(data)
            success, data = pcall(LibDeflate.DecompressDeflate, LibDeflate, data)
            success, data = Serializer:Deserialize(data)

            if success and data then
                imported = {}
                imported["name"] = name
                imported["data"] = data
                DoImport(overwriteExisting) -- 复用内部导入逻辑（含数据清洗和补全）
                return true
            end
        end
    end

    return false
end
