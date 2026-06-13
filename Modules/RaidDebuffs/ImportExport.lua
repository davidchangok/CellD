-- ============================================================================
-- CellD RaidDebuffs 导入/导出模块
-- 负责将团队减益设置序列化为可分享的文本字符串，以及从剪贴板导入他人分享的设置
-- 数据流程：序列化(Serialize) → 压缩(Deflate) → 编码(Base64) → 添加版本前缀
-- ============================================================================

local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 第三方库：序列化/反序列化与压缩/解压缩
local Serializer = LibStub:GetLibrary("LibSerialize")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local deflateConfig = {level = 9} -- 压缩等级 9，最大化压缩率

-- 状态变量
local isImport, imported = false, {} -- isImport: 当前是导入模式还是导出模式; imported: 暂存已解析的导入数据
local exportedAllBosses, exported = false, "" -- exportedAllBosses: 导出时是否选择了"全部Boss"; exported: 当前导出的字符串缓存
local currentInstanceId, currentBossId, currentBossName -- 导出时记录当前副本/Boss信息，供切换全部/当前Boss时使用
local ShowData -- 前向声明，用于在 CreateDebuffsImportExportFrame 之前引用该函数

-- UI 控件引用
local importExportFrame, importBtn, title, instance, boss, whichBossesBtn, textArea

-- ----------------------------------------------------------------------------
-- CreateDebuffsImportExportFrame()
-- 创建导入/导出浮层面板，包含标题、副本/Boss信息、文本编辑区、操作按钮等全部 UI 元素
-- 该面板在导入和导出两种模式下复用，通过 isImport 标志区分行为
-- ----------------------------------------------------------------------------
local function CreateDebuffsImportExportFrame()
    -- 创建浮层 Frame，挂载在 raidDebuffsTab 上，使用 BackdropTemplate 支持背景样式
    importExportFrame = CreateFrame("Frame", "CellOptionsFrame_RaidDebuffsImportExport", Cell.frames.raidDebuffsTab, "BackdropTemplate")
    importExportFrame:Hide() -- 初始隐藏，由 Show 函数控制显示
    Cell.StylizeFrame(importExportFrame, nil, Cell.GetAccentColorTable())
    importExportFrame:EnableMouse(true) -- 允许鼠标交互，阻止点击穿透到下层
    importExportFrame:SetFrameLevel(Cell.frames.raidDebuffsTab:GetFrameLevel() + 50) -- 提高层级确保浮层显示在最前
    P.Size(importExportFrame, 430, 170) -- 面板尺寸：宽430 x 高170（像素完美缩放）
    importExportFrame:SetPoint("TOPLEFT", P.Scale(1), -100) -- 定位在父框架左上角
    -- 为父框架创建遮罩层，用于在浮层显示时遮挡背景内容
    if not Cell.frames.raidDebuffsTab.mask then
        Cell.CreateMask(Cell.frames.raidDebuffsTab, nil, {1, -1, -1, 1})
        Cell.frames.raidDebuffsTab.mask:Hide()
    end

    -- 关闭按钮（右上角红色 × 按钮）
    local closeBtn = Cell.CreateButton(importExportFrame, "×", "red", {18, 18}, false, false, "CELL_FONT_SPECIAL", "CELL_FONT_SPECIAL")
    closeBtn:SetPoint("TOPRIGHT", -5, -1)
    closeBtn:SetScript("OnClick", function() importExportFrame:Hide() end) -- 点击关闭浮层

    -- 标题文本（显示"导入"或"导出"及统计信息）
    title = importExportFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    title:SetPoint("TOPLEFT", 5, -5)

    -- 副本名称文本（显示当前操作的副本名）
    instance = importExportFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    instance:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)

    -- Boss 名称文本（显示当前操作的 Boss 名，或"全部Boss"）
    boss = importExportFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    boss:SetPoint("TOPLEFT", instance, "BOTTOMLEFT", 0, -5)

    -- 切换按钮：在"当前Boss"与"全部Boss"之间切换（仅导出模式显示）
    whichBossesBtn = Cell.CreateButton(importExportFrame, L["Current Boss"], "blue", {111, 18})
    whichBossesBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", 1, 0)
    whichBossesBtn:Hide()
    whichBossesBtn:SetScript("OnClick", function()
        exportedAllBosses = not exportedAllBosses -- 切换全部/当前Boss标志
        if exportedAllBosses then
            whichBossesBtn:SetText(L["All Bosses"]) -- 按钮文字切换为"全部Boss"
            boss:SetText(L["Boss Name"]..": |cffffffff"..L["All Bosses"]) -- 更新Boss显示为"全部Boss"
            ShowData(currentInstanceId) -- 不传 bossId，导出该副本全部Boss的数据
        else
            whichBossesBtn:SetText(L["Current Boss"]) -- 按钮文字切换为"当前Boss"
            boss:SetText(L["Boss Name"]..": |cffffffff"..currentBossName) -- 恢复显示当前Boss名
            ShowData(currentInstanceId, currentBossId) -- 传入 bossId，仅导出当前Boss数据
        end
    end)

    -- 导入确认按钮（仅导入模式显示）
    -- 用户粘贴导入字符串后，需点击此按钮确认覆盖本地设置
    importBtn = Cell.CreateButton(importExportFrame, L["Import"], "green", {57, 18})
    importBtn:Hide()
    importBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", 1, 0)
    importBtn:SetScript("OnClick", function()
        -- 降低浮层层级，使确认弹窗能够显示在浮层上方
        importExportFrame:SetFrameLevel(Cell.frames.raidDebuffsTab:GetFrameLevel() + 20)

        -- 构造确认弹窗文本：警告用户此操作将覆盖现有设置
        local text = L["This will overwrite your debuffs"].."\n"..
            L["|cff1Aff1AYes|r - Overwrite"].."\n|cffff1A1A"..L["No"].."|r - "..L["Cancel"]
        -- 弹出确认对话框，用户确认后执行实际导入
        local popup = Cell.CreateConfirmPopup(Cell.frames.raidDebuffsTab, 200, text, function(self)
            -- 获取副本和Boss的显示名称
            local instanceName, bossName = F.GetInstanceAndBossName(imported["instanceId"], imported["bossId"])
            local which
            if bossName then
                which = bossName.." ("..instanceName..")" -- 格式：Boss名 (副本名)
            else
                which = instanceName -- 仅副本名（全部Boss情况）
            end
            -- 写入数据库并刷新界面
            F.UpdateRaidDebuffs(imported["instanceId"], imported["bossId"], imported["data"], which)
            F.ShowInstanceDebuffs(imported["instanceId"], imported["bossId"])
            importExportFrame:Hide()
        end, function(self)
            importExportFrame:Hide() -- 用户取消，直接关闭浮层
        end, true)
        popup:SetPoint("TOPLEFT", importExportFrame, 117, -50)

        textArea.eb:ClearFocus() -- 移除编辑框焦点
    end)

    -- 文本编辑区（ScrollEditBox）：用于显示导出字符串或粘贴导入字符串
    -- 回调函数在用户修改文本时触发，执行导入解析或导出文本回写
    textArea = Cell.CreateScrollEditBox(importExportFrame, function(eb, userChanged)
        if userChanged then -- 仅响应用户主动修改，避免程序设置文本时误触发
            if isImport then
                -- ============================================================
                -- 导入模式：解析用户粘贴的字符串
                -- 格式：!CELL:<versionNum>:DEBUFF:<instanceId>:<bossId>!<base64data>
                -- 解析步骤：正则提取 → 版本校验 → 解码 → 解压 → 反序列化
                -- ============================================================
                imported = {}
                local text = eb:GetText()
                -- 使用正则提取版本号、副本ID、Boss标识、数据部分
                local version, instanceId, bossId, data = string.match(text, "^!CELL:(%d+):DEBUFF:(%d+):(.+)!(.+)$")

                local error
                if version and instanceId and bossId and data then
                    version = tonumber(version)
                    instanceId = tonumber(instanceId)

                    -- 校验 bossId 有效性：支持数字ID、"all"（全部Boss）、"general"（通用）
                    local isValidBossId
                    if bossId == "all" then
                        bossId = nil -- nil 表示全部Boss
                        isValidBossId = true
                    elseif bossId == "general" then
                        isValidBossId = true -- general 表示通用减益，无特定Boss
                    else
                        bossId = tonumber(bossId) -- 转换为数字ID
                        if bossId then isValidBossId = true end
                    end

                    local instanceName, bossName = F.GetInstanceAndBossName(instanceId, bossId)

                    if isValidBossId and instanceName then
                        -- 版本兼容性检查：低于最低支持版本则拒绝导入
                        if version >= Cell.MIN_DEBUFFS_VERSION then
                            local success
                            -- 三步逆操作：解码(Base64) → 解压(Deflate) → 反序列化
                            data = LibDeflate:DecodeForPrint(data) -- 第一步：Base64 解码为二进制
                            success, data = pcall(LibDeflate.DecompressDeflate, LibDeflate, data) -- 第二步：Deflate 解压
                            success, data = Serializer:Deserialize(data) -- 第三步：反序列化为 Lua 表

                            if success and data then
                                -- 统计内置和自定义减益数量并显示在标题栏
                                local builtIn, custom = F.CalcRaidDebuffs(instanceId, bossId, data)
                                title:SetText(L["Import"]..": ".."|cff90EE90"..builtIn.." "..L["built-in(s)"].."|r, |cffFFB5C5"..custom.." "..L["custom(s)"].."|r")

                                instance:SetText(L["Instance Name"]..": |cffffffff"..instanceName)
                                boss:SetText(L["Boss Name"]..": |cffffffff"..(bossName or L["All Bosses"]))

                                -- 暂存解析成功的数据，等待用户点击"导入"按钮确认
                                imported["instanceId"] = instanceId
                                imported["bossId"] = bossId
                                imported["data"] = data
                                importBtn:SetEnabled(true) -- 激活导入按钮
                            else
                                error = L["Error"] -- 解压或反序列化失败
                            end
                        else -- 版本不兼容
                            error = L["Incompatible Version"]
                        end
                    else
                        error = L["Error"] -- 无效的副本/Boss ID
                    end
                else
                    error = L["Error"] -- 正则匹配失败，格式不正确
                end

                -- 解析失败时，以红色文字显示错误信息并禁用导入按钮
                if error then
                    title:SetText(L["Import"]..": |cffff2222"..error)
                    instance:SetText(L["Instance Name"]..": |cffff2222"..L["Error"])
                    boss:SetText(L["Boss Name"]..": |cffff2222"..L["Error"])
                    importBtn:SetEnabled(false)
                end
            else
                -- 导出模式：用户修改文本时恢复为原始导出内容（防止误编辑）
                eb:SetText(exported)
                eb:SetCursorPosition(0)
                eb:HighlightText() -- 全选高亮，方便用户 Ctrl+C 复制
            end
        end
    end)
    Cell.StylizeFrame(textArea.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    textArea:SetPoint("TOPLEFT", 5, -60)
    textArea:SetPoint("BOTTOMRIGHT", -5, 5)

    -- 编辑框获得焦点时自动全选文本（方便复制整段导出字符串）
    textArea.eb:SetScript("OnEditFocusGained", function() textArea.eb:HighlightText() end)
    -- 导出模式下点击编辑框自动全选（导入模式下允许用户自由选择粘贴位置）
    textArea.eb:SetScript("OnMouseUp", function()
        if not isImport then
            textArea.eb:HighlightText()
        end
    end)

    -- 浮层隐藏时的清理：重置状态变量，隐藏遮罩层
    importExportFrame:SetScript("OnHide", function()
        importExportFrame:Hide()
        isImport = false -- 重置模式标志
        exported = "" -- 清空导出缓存
        imported = {} -- 清空导入缓存
        Cell.frames.raidDebuffsTab.mask:Hide() -- 隐藏遮罩
    end)

    -- 浮层显示时：提升层级确保可见，显示遮罩层遮挡背景
    importExportFrame:SetScript("OnShow", function()
        -- 提高浮层层级，确保不被其他元素遮挡
        importExportFrame:SetFrameLevel(Cell.frames.raidDebuffsTab:GetFrameLevel() + 50)
        Cell.frames.raidDebuffsTab.mask:Show() -- 显示遮罩，阻止点击穿透到下层界面
    end)
end

-- ----------------------------------------------------------------------------
-- F.ShowRaidDebuffsImportFrame()
-- 以"导入模式"打开浮层面板
-- 用户在此模式下粘贴他人分享的减益设置字符串，面板会自动解析并预览
-- ----------------------------------------------------------------------------
local init -- 懒初始化标志：确保浮层 UI 仅在首次调用时创建
function F.ShowRaidDebuffsImportFrame()
    if not init then
        init = true
        CreateDebuffsImportExportFrame() -- 首次调用时创建浮层（后续复用）
    end

    importExportFrame:Show()
    isImport = true -- 设置为导入模式
    importBtn:Show() -- 显示"导入"确认按钮
    importBtn:SetEnabled(false) -- 初始禁用，等用户粘贴有效数据后再激活
    whichBossesBtn:Hide() -- 导入模式不需要"全部/当前Boss"切换

    exported = ""
    title:SetText(L["Import"]) -- 标题设为"导入"
    instance:SetText(L["Instance Name"]) -- 清空副本名占位
    boss:SetText(L["Boss Name"]) -- 清空Boss名占位
    textArea:SetText("") -- 清空文本区，等待用户粘贴
    textArea.eb:SetFocus(true) -- 自动聚焦编辑框，方便用户直接 Ctrl+V 粘贴
end

-- ----------------------------------------------------------------------------
-- ShowData(instanceId [, bossId])
-- 导出模式核心函数：从 CellDB 中读取指定副本/Boss 的减益数据并序列化为分享字符串
-- 数据流程：读取 DB → 序列化(Serialize) → 压缩(Deflate) → 编码(Base64) → 加版本前缀
-- @param instanceId 副本ID
-- @param bossId (可选) Boss ID，不传时导出该副本全部Boss的数据
-- ----------------------------------------------------------------------------
ShowData = function(instanceId, bossId)
    local data
    if not bossId then -- 未指定 bossId：读取该副本下所有Boss的数据
        if CellDB["raidDebuffs"][instanceId] then
            data = CellDB["raidDebuffs"][instanceId]
        end
    else
        -- 指定了 bossId：仅读取特定Boss的数据
        if CellDB["raidDebuffs"][instanceId] and CellDB["raidDebuffs"][instanceId][bossId] then
            data = CellDB["raidDebuffs"][instanceId][bossId]
        end
    end

    if data then
        -- 统计内置和自定义减益数量，显示在标题栏
        local builtIn, custom = F.CalcRaidDebuffs(instanceId, bossId, data)
        title:SetText(L["Export"]..": ".."|cff90EE90"..builtIn.." "..L["built-in(s)"].."|r, |cffFFB5C5"..custom.." "..L["custom(s)"].."|r")

        -- 构造导出前缀：标识 Cell 版本、数据类型、副本/Boss ID
        local prefix = "!CELL:"..Cell.versionNum..":DEBUFF:"..instanceId..":"..(bossId or "all").."!"
        -- 三步序列化流程：序列化 → 压缩 → 编码
        exported = Serializer:Serialize(data) -- 第一步：Lua 表序列化为字符串
        exported = LibDeflate:CompressDeflate(exported, deflateConfig) -- 第二步：Deflate 压缩
        exported = LibDeflate:EncodeForPrint(exported) -- 第三步：Base64 编码为可打印字符串
        exported = prefix..exported -- 拼接版本/副本/Boss前缀，形成完整导出字符串
    else
        -- 无数据时显示提示（通常意味着没有自定义减益）
        title:SetText(L["Export"]..": ")
        exported = L["No custom debuffs to export!"]
    end

    textArea:SetText(exported) -- 将导出字符串填入文本区
    textArea.eb:SetFocus(true) -- 自动聚焦并全选，方便用户 Ctrl+C 复制
end

-- ----------------------------------------------------------------------------
-- F.ShowRaidDebuffsExportFrame(instanceId, bossId)
-- 以"导出模式"打开浮层面板
-- 将当前选中副本/Boss 的减益设置序列化为可分享的文本字符串
-- @param instanceId 副本ID
-- @param bossId Boss ID
-- ----------------------------------------------------------------------------
function F.ShowRaidDebuffsExportFrame(instanceId, bossId)
    if not init then
        init = true
        CreateDebuffsImportExportFrame() -- 首次调用时创建浮层（后续复用）
    end

    importExportFrame:Show()
    isImport = false -- 设置为导出模式
    importBtn:Hide() -- 导出模式隐藏"导入"确认按钮
    exportedAllBosses = false -- 默认导出当前Boss
    whichBossesBtn:SetText(L["Current Boss"]) -- 按钮显示"当前Boss"
    whichBossesBtn:Show() -- 导出模式显示"全部/当前Boss"切换按钮

    -- 获取并缓存当前副本/Boss信息，供后续切换时使用
    local instanceName, bossName = F.GetInstanceAndBossName(instanceId, bossId)
    currentInstanceId = instanceId
    currentBossId = bossId
    currentBossName = bossName

    title:SetText(L["Export"]..": ") -- 标题设为"导出"
    instance:SetText(L["Instance Name"]..": |cffffffff"..instanceName) -- 显示副本名
    boss:SetText(L["Boss Name"]..": |cffffffff"..bossName) -- 显示Boss名

    ShowData(instanceId, bossId) -- 执行数据读取与序列化
end