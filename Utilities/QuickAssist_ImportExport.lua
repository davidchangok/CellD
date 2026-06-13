local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- LibSerialize: 序列化 Lua 表为字符串 / 反序列化
-- LibDeflate: 压缩 / 解压 + Base64 编码 / 解码，用于减小导出字符串长度
local Serializer = LibStub:GetLibrary("LibSerialize")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local deflateConfig = {level = 9} -- 压缩等级 9（最高压缩比）

-- 导入导出流程的状态变量
-- isImport: 当前面板模式（true=导入，false=导出）
-- imported: 解析成功后暂存的导入数据（反序列化后的 Lua 表）
-- exported: 导出时缓存的完整字符串（含前缀、压缩编码后的数据）
local isImport, imported, exported = false, {}, ""

-- 面板及其子控件的引用缓存
local importExportFrame, importBtn, title, textArea

-- 执行导入：将解析好的 imported 数据写入当前专精的快捷助手设置，然后触发更新并关闭面板
local function DoImport()
    -- 将导入的数据写入当前角色专精对应的 DB 键
    CellDB["quickAssist"][Cell.vars.playerSpecID] = imported
    -- 通知其他模块刷新快捷助手数据
    Cell.Fire("UpdateQuickAssist")
    -- 通知 UI 重新加载快捷助手显示
    Cell.Fire("ReloadQuickAssist")
    -- 关闭导入导出面板
    importExportFrame:Hide()
end

-- 创建导入导出面板（延迟初始化，首次使用时创建）
-- 面板包含：关闭按钮、导入按钮、标题文本、可滚动编辑框
-- 面板覆盖在快捷助手标签页上方，带半透明遮罩
local function CreateQuickAssistImportExportFrame()
    -- 创建主 Frame，挂载在快捷助手标签页下
    importExportFrame = CreateFrame("Frame", "CellOptionsFrame_QuickAssistImportExport", Cell.frames.quickAssistTab, "BackdropTemplate")
    importExportFrame:Hide()
    -- 应用 Cell 统一边框样式和主题色
    Cell.StylizeFrame(importExportFrame, nil, Cell.GetAccentColorTable())
    importExportFrame:EnableMouse(true)
    -- 设置较高的层级使其位于标签页上方
    importExportFrame:SetFrameLevel(Cell.frames.quickAssistTab:GetFrameLevel() + 50)
    P.Size(importExportFrame, 430, 170)
    importExportFrame:SetPoint("TOPLEFT", P.Scale(1), -30)

    -- 创建遮罩层：面板显示时遮挡快捷助手标签页，防止误操作
    -- inset {1, -1, -1, 1} 使遮罩仅覆盖标签页内部区域，避开边框
    if not Cell.frames.quickAssistTab.mask then
        Cell.CreateMask(Cell.frames.quickAssistTab, nil, {1, -1, -1, 1})
        Cell.frames.quickAssistTab.mask:Hide()
    end

    -- 关闭按钮（红色 ×）：点击隐藏导入导出面板，不执行任何数据操作
    local closeBtn = Cell.CreateButton(importExportFrame, "×", "red", {18, 18}, false, false, "CELL_FONT_SPECIAL", "CELL_FONT_SPECIAL")
    closeBtn:SetPoint("TOPRIGHT", P.Scale(-5), P.Scale(-1))
    closeBtn:SetScript("OnClick", function() importExportFrame:Hide() end)

    -- 导入按钮（绿色）：仅在导入模式下显示，初始禁用
    -- 用户粘贴有效数据后启用，点击弹出确认框后执行导入
    importBtn = Cell.CreateButton(importExportFrame, L["Import"], "green", {57, 18})
    importBtn:Hide()
    importBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", P.Scale(1), 0)
    -- 导入按钮点击：降低面板层级让确认弹窗在上方，确认后执行 DoImport
    importBtn:SetScript("OnClick", function()
        -- 降低面板层级，使确认弹窗能正常显示在面板上方
        importExportFrame:SetFrameLevel(Cell.frames.quickAssistTab:GetFrameLevel() + 25)

        -- 弹出确认对话框，询问用户是否覆盖当前快捷助手设置
        local popup = Cell.CreateConfirmPopup(Cell.frames.quickAssistTab, 200, L["Overwrite Quick Assist"].."?", function(self)
            DoImport()
        end, nil, true)
        popup:SetPoint("TOPLEFT", importExportFrame, 117, -50)
        -- 清除编辑框焦点，防止继续触发文本变更回调
        textArea.eb:ClearFocus()
    end)

    -- 标题文本：显示当前模式（"导入"/"导出"），导入校验失败时显示红色错误信息
    title = importExportFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    title:SetPoint("TOPLEFT", 5, -5)

    -- 可滚动编辑框：导入模式下用户在此粘贴编码字符串，导出模式下显示生成的编码字符串
    -- 回调在文本变更时触发（userChanged=true 表示用户编辑，false 表示程序设置文本）
    -- 导入模式：实时解析粘贴的内容，校验格式 → 解码 → 解压 → 反序列化，成功后启用导入按钮
    -- 导出模式：重置编辑框为缓存的 exported 字符串并全选高亮
    textArea = Cell.CreateScrollEditBox(importExportFrame, function(eb, userChanged)
        if userChanged then
            if isImport then
                -- --- 导入模式：实时解析用户粘贴的编码字符串 ---
                imported = {}
                local text = eb:GetText()
                -- 用正则匹配数据格式：!CELL:<版本号>:QUICKASSIST!<Base64编码的压缩数据>
                local version, data = string.match(text, "^!CELL:(%d+):QUICKASSIST!(.+)$")
                version = tonumber(version)

                if version and data then
                    -- 检查版本兼容性：版本号不能低于当前插件最低支持的快捷助手版本
                    if version >= Cell.MIN_QUICKASSIST_VERSION then
                        local success
                        -- 第一步：Base64 解码（LibDeflate.EncodeForPrint 的逆操作）
                        data = LibDeflate:DecodeForPrint(data) -- decode
                        -- 第二步：Deflate 解压（pcall 保护，防止损坏数据导致崩溃）
                        success, data = pcall(LibDeflate.DecompressDeflate, LibDeflate, data) -- decompress
                        -- 第三步：反序列化 Lua 表
                        success, data = Serializer:Deserialize(data) -- deserialize

                        if success and data then
                            -- 全部成功：暂存数据并启用导入按钮
                            imported = data
                            importBtn:SetEnabled(true)
                        else
                            -- 解码/解压/反序列化任一失败：标题显示红色"错误"
                            title:SetText(L["Import"]..": |cffff2222"..L["Error"])
                            importBtn:SetEnabled(false)
                        end
                    else -- 版本不兼容：数据来自更高版本插件，当前版本无法读取
                        title:SetText(L["Import"]..": |cffff2222"..L["Incompatible Version"])
                        importBtn:SetEnabled(false)
                    end
                else
                    -- 格式不匹配：未识别到 !CELL:...:QUICKASSIST! 前缀
                    title:SetText(L["Import"]..": |cffff2222"..L["Error"])
                    importBtn:SetEnabled(false)
                end
            else
                -- 导出模式下用户编辑了文本：重置为原始导出字符串并全选高亮
                eb:SetText(exported)
                eb:SetCursorPosition(0)
                eb:HighlightText()
            end
        end
    end)
    Cell.StylizeFrame(textArea.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    textArea:SetPoint("TOPLEFT", P.Scale(5), P.Scale(-20))
    textArea:SetPoint("BOTTOMRIGHT", P.Scale(-5), P.Scale(5))

    -- 编辑框焦点和鼠标事件：导出模式下自动全选文本，方便用户 Ctrl+C 复制
    -- OnEditFocusGained: 编辑框获得焦点时全选文本
    textArea.eb:SetScript("OnEditFocusGained", function() textArea.eb:HighlightText() end)
    -- OnMouseUp: 鼠标点击编辑框后（仅导出模式）重新全选，确保用户不会意外取消选中
    textArea.eb:SetScript("OnMouseUp", function()
        if not isImport then
            textArea.eb:HighlightText()
        end
    end)

    -- OnHide: 面板隐藏时清理状态
    -- 重置 isImport、清空 exported/imported，隐藏遮罩层
    importExportFrame:SetScript("OnHide", function()
        importExportFrame:Hide()
        isImport = false
        exported = ""
        imported = {}
        -- 隐藏遮罩，恢复快捷助手标签页的正常交互
        Cell.frames.quickAssistTab.mask:Hide()
    end)

    -- OnShow: 面板显示时提升层级并显示遮罩
    -- 提升层级确保面板在标签页所有控件之上，遮罩防止误操作底层控件
    importExportFrame:SetScript("OnShow", function()
        -- 提升面板层级到标签页上方 50
        importExportFrame:SetFrameLevel(Cell.frames.quickAssistTab:GetFrameLevel() + 50)
        -- 显示遮罩，阻止用户操作面板下方的标签页控件
        Cell.frames.quickAssistTab.mask:Show()
    end)
end

-- 延迟初始化标记：确保导入导出面板只在首次使用时创建
local init

-- 打开导入面板：用户粘贴编码字符串 → 自动解析校验 → 点击导入按钮覆盖当前设置
function F.ShowQuickAssistImportFrame()
    if not init then
        init = true
        -- 首次调用时创建面板及其所有子控件
        CreateQuickAssistImportExportFrame()
    end

    -- 显示面板并切换到导入模式
    importExportFrame:Show()
    isImport = true
    importBtn:Show()
    -- 初始禁用导入按钮，直到用户粘贴有效数据
    importBtn:SetEnabled(false)

    exported = ""
    -- 标题显示"导入"
    title:SetText(L["Import"])
    -- 清空编辑框并聚焦，等待用户粘贴
    textArea:SetText("")
    textArea.eb:SetFocus(true)
end

-- 打开导出面板：将快捷助手设置序列化 → 压缩 → Base64编码 → 拼接前缀，显示为可复制字符串
-- quickAssistTable: 当前专精的快捷助手设置表
function F.ShowQuickAssistExportFrame(quickAssistTable)
    if not init then
        init = true
        -- 首次调用时创建面板及其所有子控件
        CreateQuickAssistImportExportFrame()
    end

    -- 无数据时直接返回（不应发生，但安全起见）
    if not quickAssistTable then return end

    -- 显示面板并切换到导出模式
    importExportFrame:Show()
    isImport = false
    -- 导出模式下隐藏导入按钮
    importBtn:Hide()

    -- 标题显示"导出"
    title:SetText(L["Export"])

    -- 构建数据前缀：!CELL:<当前插件版本>:QUICKASSIST!
    -- 版本号用于导入时校验兼容性
    local prefix = "!CELL:"..Cell.versionNum..":QUICKASSIST!"

    -- 导出管线：序列化 → 压缩 → Base64编码 → 拼接前缀
    -- 第一步：将 Lua 表序列化为字符串
    exported = Serializer:Serialize(quickAssistTable) -- serialize
    -- 第二步：使用 Deflate 压缩（等级 9 最高压缩比）
    exported = LibDeflate:CompressDeflate(exported, deflateConfig) -- compress
    -- 第三步：Base64 编码为可打印字符（方便复制粘贴和跨平台传输）
    exported = LibDeflate:EncodeForPrint(exported) -- encode
    -- 第四步：拼接版本前缀，导入时用正则匹配提取
    exported = prefix..exported

    -- 将完整编码字符串填入编辑框并聚焦，用户可直接 Ctrl+A Ctrl+C 复制
    textArea:SetText(exported)
    textArea.eb:SetFocus(true)
end