local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local U = Cell.uFuncs
local P = Cell.pixelPerfectFuncs

local Serializer = LibStub:GetLibrary("LibSerialize")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local deflateConfig = {level = 9}

local isImport, imported, exported = false, nil, ""

local importExportFrame, importBtn, title, textArea, includeNicknamesCB, includeCharacterCB
local confirmationFrame
local ignoredIndices = {}

---------------------------------------------------------------------
-- DoImport - 执行配置导入的核心函数
-- 将已解析并校验通过的 imported 表写入 CellDB（及 CellCharacterDB），完成设置覆盖。
-- 处理流程：清理无效数据 → 迁移布局/指示器 → 处理点击施法/布局自动切换 →
--           过滤无效法术 → 过滤用户勾选忽略的分类 → 写入数据库 → 重载或提示。
-- @param noReload boolean - true 时不重载 UI（供外部 API 调用），false/nil 时导入后重载
---------------------------------------------------------------------
local function DoImport(noReload)
    -- 清理 raidDebuffs：只保留当前已加载的副本 debuff 数据，移除不可用的副本条目
    for instanceID in pairs(imported["raidDebuffs"]) do
        if not Cell.snippetVars.loadedDebuffs[instanceID] then
            imported["raidDebuffs"][instanceID] = nil
        end
    end

    -- 经典旧世版本兼容：移除正式服专属功能（快捷施法、快捷协助、治疗吸收预览等不支持的特性）
    if Cell.isMists or Cell.isCata or Cell.isTBC or Cell.isVanilla then
        imported["quickCast"] = nil
        imported["quickAssist"] = nil
        imported["appearance"]["healAbsorb"][1] = false
    end

    -- 布局数据迁移：遍历所有导入的布局，清洗指示器并迁移 powerFilters 格式
    local builtInFound = {}
    for _, layout in pairs(imported["layouts"]) do
        -- 指示器清洗
        for i =  #layout["indicators"], 1, -1 do
            if layout["indicators"][i]["type"] == "built-in" then -- 移除当前版本不支持的内置指示器
                local indicatorName = layout["indicators"][i]["indicatorName"]
                builtInFound[indicatorName] = true
                if not Cell.defaults.indicatorIndices[indicatorName] then
                    tremove(layout["indicators"], i)
                end
            else -- 自定义指示器：过滤无效法术
                F.FilterInvalidSpells(layout["indicators"][i]["auras"])
            end
        end

        -- powerFilters 格式迁移：确保导入的 powerFilters 类型与当前默认值一致（table / boolean）
        for class, t in pairs(Cell.defaults.layout.powerFilters) do
            if type(layout["powerFilters"][class]) ~= type(t) then
                if type(t) == "table" then
                    layout["powerFilters"][class] = F.Copy(t)
                else
                    layout["powerFilters"][class] = true
                end
            end
        end
    end

    -- 补充缺失的内置指示器：若导入的布局缺少当前版本默认的内置指示器，按默认顺序插入
    if F.Getn(builtInFound) ~= Cell.defaults.builtIns then
        for indicatorName, index in pairs(Cell.defaults.indicatorIndices) do
            if not builtInFound[indicatorName] then
                for _, layout in pairs(imported["layouts"]) do
                    tinsert(layout["indicators"], index, Cell.defaults.layout.indicators[index])
                end
            end
        end
    end

    -- 点击施法数据迁移：处理不同版本间的点击施法配置兼容
    -- 规则：同 flavor 直接迁移；不同 flavor 丢弃（防止正式服→经典服数据不兼容）；
    --      经典服 characterDB 中的点击施法仅在同职业间迁移，香草服无双天赋时强制 useCommon
    local clickCastings
    if imported["clickCastings"] then
        if Cell.flavor == imported.flavor then -- 同版本：直接使用
            clickCastings = imported["clickCastings"]
        else -- 跨版本（正式服 → 经典服）：丢弃
            clickCastings = nil
        end
        imported["clickCastings"] = nil

    elseif imported["characterDB"] and imported["characterDB"]["clickCastings"] then
        if (Cell.isVanilla or Cell.isTBC or Cell.isWrath or Cell.isCata) and imported["characterDB"]["clickCastings"]["class"] == Cell.vars.playerClass then -- 经典服→经典服，同职业可迁移
            clickCastings = imported["characterDB"]["clickCastings"]
            if Cell.isVanilla and GetNumTalentGroups() == 1 then -- 香草服无双天赋系统，强制使用通用配置
                clickCastings["useCommon"] = true
            end
        else -- 经典服 → 正式服：丢弃
            clickCastings = nil
        end
        imported["characterDB"]["clickCastings"] = nil
    end

    -- 布局自动切换数据迁移：处理不同版本间的布局自动切换配置兼容
    -- 规则与点击施法对称：同 flavor 直接迁移，跨版本丢弃；经典服 characterDB 仅经典服间迁移
    local layoutAutoSwitch
    if imported["layoutAutoSwitch"] then
        if Cell.flavor == imported.flavor then -- 同版本：直接使用
            layoutAutoSwitch = imported["layoutAutoSwitch"]
        else -- 跨版本（正式服 → 经典服）：丢弃
            layoutAutoSwitch = nil
        end
        imported["layoutAutoSwitch"] = nil

    elseif imported["characterDB"] and imported["characterDB"]["layoutAutoSwitch"] then
        if Cell.isVanilla or Cell.isTBC or Cell.isWrath or Cell.isCata then -- 经典服→经典服：可迁移
            layoutAutoSwitch = imported["characterDB"]["layoutAutoSwitch"]
        else -- 经典服 → 正式服：丢弃
            layoutAutoSwitch = nil
        end
        imported["characterDB"]["layoutAutoSwitch"] = nil
    end

    -- 移除 characterDB：角色专属数据已在上面提取出来，避免覆盖全局 DB
    imported["characterDB"] = nil

    -- 全局过滤无效法术：清理所有法术列表中的陈旧/不存在法术 ID
    F.FilterInvalidSpells(imported["debuffBlacklist"])
    F.FilterInvalidSpells(imported["bigDebuffs"])
    F.FilterInvalidSpells(imported["actions"])
    F.FilterInvalidSpells(imported["aoeHealings"] and imported["aoeHealings"]["custom"])
    F.FilterInvalidSpells(imported["defensives"]["custom"])
    F.FilterInvalidSpells(imported["externals"]["custom"])
    F.FilterInvalidSpells(imported["targetedSpellsList"])
    -- F.FilterInvalidSpells(imported["cleuAuras"])

    -- disable autorun
    -- for i = 1, #imported["snippets"] do
    --     imported["snippets"][i]["autorun"] = false
    -- end

    -- buffTracker 跨版本兼容：不同 flavor 时重置 buffTracker 跟踪列表为当前版本默认值
    if Cell.flavor ~= imported.flavor then
        imported["tools"]["buffTracker"][5] = U.GetBuffTrackerDefaults()
    end

    -- 过滤用户在确认面板中取消勾选的配置分类（ignoredIndices[index] = true 表示跳过）

    for index, ignored in pairs(ignoredIndices) do
        if ignored then
            imported[index] = nil
        end
    end

    -- 写入数据库：将处理后的数据覆盖到 CellDB（及 CellCharacterDB）
    -- 正式服/Mists：点击施法和布局自动切换写入全局 CellDB
    -- 经典服：点击施法和布局自动切换写入角色专属 CellCharacterDB
    if Cell.isRetail or Cell.isMists then
        if not ignoredIndices["clickCastings"] then
            CellDB["clickCastings"] = clickCastings
        end
        if not ignoredIndices["layouts"] then
            CellDB["layoutAutoSwitch"] = layoutAutoSwitch
        end
    else
        if not ignoredIndices["clickCastings"] then
            CellCharacterDB["clickCastings"] = clickCastings
        end
        if not ignoredIndices["layouts"] then
            CellCharacterDB["layoutAutoSwitch"] = layoutAutoSwitch
        end
        CellCharacterDB["revise"] = imported["revise"]
    end

    -- 将剩余的 imported 数据全部写入 CellDB
    for k, v in pairs(imported) do
        CellDB[k] = v
    end

    -- 根据 noReload 参数决定是否重载 UI（外部 API 调用不重载，手动导入则重载确保完整应用）
    if noReload then
        F.Print(L["Profile imported successfully."])
    else
        ReloadUI()
    end
end

---------------------------------------------------------------------
-- GetExportString - 生成导出字符串
-- 将当前配置序列化为可分享的编码字符串。
-- 流程：Copy CellDB → 按参数过滤昵称/角色数据 → 附加 flavor 标识 →
--       Serialize(序列化) → CompressDeflate(压缩) → EncodeForPrint(编码为可打印字符串)
-- @param includeNicknames boolean - 是否包含昵称数据
-- @param includeCharacter boolean - 是否包含角色专属设置（点击施法、布局自动切换等）
-- @return string 以 "!CELL:版本号:ALL!" 为前缀的编码字符串
---------------------------------------------------------------------
local function GetExportString(includeNicknames, includeCharacter)
    -- 导出前缀：标记版本号，用于导入时校验兼容性
    local prefix = "!CELL:"..Cell.versionNum..":ALL!"

    -- 深拷贝 CellDB 避免污染原始数据
    local db = F.Copy(CellDB)

    -- 按需排除昵称数据
    if not includeNicknames then
        db["nicknames"] = nil
    end

    -- 按需包含角色专属数据（经典服专用）
    if includeCharacter then
        db["characterDB"] = F.Copy(CellCharacterDB)
    end

    -- 附加版本 flavor 标识，并清除运行时不导出的临时字段
    db["flavor"] = Cell.flavor
    db["fallbackGroupType"] = nil
    db["fallbackInMythic"] = nil

    -- 三步编码管线：序列化 → 压缩 → 编码为可打印字符串
    local str = Serializer:Serialize(db)
    str = LibDeflate:CompressDeflate(str, deflateConfig)
    str = LibDeflate:EncodeForPrint(str)

    return prefix..str
end

---------------------------------------------------------------------
-- CreateImportConfirmationFrame - 创建导入确认面板
-- 显示在导入/导出主面板上方的模态确认弹窗。
-- 包含 7 个复选框让用户选择要导入的配置分类（默认全部勾选，昵称除外），
-- 以及"是/否"按钮确认或取消导入操作。
-- 用户取消勾选的分类对应的 CellDB key 会被加入 ignoredIndices 表，在 DoImport 中被跳过。
---------------------------------------------------------------------
local function CreateImportConfirmationFrame()
    -- 创建模态确认面板，层级比导入/导出主面板高 300
    confirmationFrame = CreateFrame("Frame", nil, Cell.frames.aboutTab, "BackdropTemplate")
    confirmationFrame:SetSize(361, 165)
    Cell.StylizeFrame(confirmationFrame, {0.1, 0.1, 0.1, 0.95}, Cell.GetAccentColorTable())
    confirmationFrame:EnableMouse(true)
    confirmationFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 300)
    confirmationFrame:SetPoint("TOP", importExportFrame, 0, -25)
    confirmationFrame:Hide()

    -- "否"按钮：取消导入，关闭确认面板和主面板
    local button2 = Cell.CreateButton(confirmationFrame, L["No"], "red", {55, 17})
    button2:SetPoint("BOTTOMRIGHT")
    button2:SetBackdropBorderColor(Cell.GetAccentColorRGB())
    button2:SetScript("OnClick", function()
        confirmationFrame:Hide()
        importExportFrame:Hide()
    end)

    -- "是"按钮：确认导入，执行 DoImport() 后关闭所有面板
    local button1 = Cell.CreateButton(confirmationFrame, L["Yes"], "green", {55, 17})
    button1:SetPoint("BOTTOMRIGHT", button2, "BOTTOMLEFT", P.Scale(1), 0)
    button1:SetBackdropBorderColor(Cell.GetAccentColorRGB())
    button1:SetScript("OnClick", function()
        DoImport()
        confirmationFrame:Hide()
        importExportFrame:Hide()
    end)

    -- 警告文本：提醒用户 Cell 设置将被覆盖（红色高亮）
    local text1 = confirmationFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_TITLE")
    text1:SetPoint("LEFT", 10, 0)
    text1:SetPoint("RIGHT", -10, 0)
    text1:SetPoint("TOP", 0, -10)
    text1:SetSpacing(5)
    text1:SetText("|cFFFF7070"..L["Cell settings will be overwritten!"])

    -- 说明文本：未选中的设置将保留（灰色）
    local text2 = confirmationFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    text2:SetPoint("LEFT", 10, 0)
    text2:SetPoint("RIGHT", -10, 0)
    text2:SetPoint("TOP", text1, "BOTTOM", 0, -5)
    text2:SetSpacing(5)
    text2:SetText( "|cFFB7B7B7"..L["Unselected settings will remain"])

    -- 提示文本：提醒用户备份配置（浅灰色，左下角）
    local text3 = confirmationFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    text3:SetPoint("BOTTOMLEFT", 5, 5)
    text3:SetPoint("RIGHT", button1, "LEFT", -10, 0)
    text3:SetJustifyH("LEFT")
    text3:SetText( "|cFFABABAB"..L["Remember to backup your profile"])

    -- 7 个复选框，每个控制一个配置分类是否导入（勾选=导入，取消勾选=跳过）
    local checkboxes = {}

    -- 1: 通用设置（General）—— 对应 CellDB["general"]
    checkboxes.general = Cell.CreateCheckButton(confirmationFrame, L["General"], function(checked)
        ignoredIndices["general"] = not checked
    end)
    checkboxes.general:SetPoint("TOPLEFT", 15, -55)

    -- 2: 外观设置（Appearance）—— 对应 CellDB["appearance"] 和 CellDB["debuffTypeColor"]
    checkboxes.appearance = Cell.CreateCheckButton(confirmationFrame, L["Appearance"], function(checked)
        ignoredIndices["appearance"] = not checked
        ignoredIndices["debuffTypeColor"] = not checked
    end)
    checkboxes.appearance:SetPoint("TOPLEFT", checkboxes.general, 165, 0)

    -- 3: 点击施法（Click-Castings）—— 对应 CellDB["clickCastings"]
    checkboxes.clickCastings = Cell.CreateCheckButton(confirmationFrame, L["Click-Castings"], function(checked)
        ignoredIndices["clickCastings"] = not checked
    end)
    checkboxes.clickCastings:SetPoint("TOPLEFT", checkboxes.general, "BOTTOMLEFT", 0, -7)

    -- 4: 布局和指示器（Layouts & Indicators）—— 控制 13 个相关 CellDB key
    checkboxes.layouts = Cell.CreateCheckButton(confirmationFrame, L["Layouts"] .. " & " .. L["Indicators"], function(checked)
        ignoredIndices["layouts"] = not checked
        ignoredIndices["layoutAutoSwitch"] = not checked
        ignoredIndices["dispelBlacklist"] = not checked
        ignoredIndices["debuffBlacklist"] = not checked
        ignoredIndices["bigDebuffs"] = not checked
        ignoredIndices["aoeHealings"] = not checked
        ignoredIndices["defensives"] = not checked
        ignoredIndices["externals"] = not checked
        ignoredIndices["targetedSpellsList"] = not checked
        ignoredIndices["targetedSpellsGlow"] = not checked
        ignoredIndices["crowdControls"] = not checked
        ignoredIndices["actions"] = not checked
        ignoredIndices["indicatorPreview"] = not checked
        ignoredIndices["customTextures"] = not checked
    end)
    checkboxes.layouts:SetPoint("TOPLEFT", checkboxes.appearance, "BOTTOMLEFT", 0, -7)

    -- 5: 团队 Debuff（Raid Debuffs）—— 对应 CellDB["raidDebuffs"]
    checkboxes.raidDebuffs = Cell.CreateCheckButton(confirmationFrame, L["Raid Debuffs"], function(checked)
        ignoredIndices["raidDebuffs"] = not checked
    end)
    checkboxes.raidDebuffs:SetPoint("TOPLEFT", checkboxes.clickCastings, "BOTTOMLEFT", 0, -7)

    -- 6: 实用工具（Utilities）—— 控制 tools、法术请求、驱散请求、快捷协助、快捷施法
    checkboxes.utilities = Cell.CreateCheckButton(confirmationFrame, L["Utilities"], function(checked)
        ignoredIndices["tools"] = not checked
        ignoredIndices["spellRequest"] = not checked
        ignoredIndices["dispelRequest"] = not checked
        ignoredIndices["quickAssist"] = not checked
        ignoredIndices["quickCast"] = not checked
    end)
    checkboxes.utilities:SetPoint("TOPLEFT", checkboxes.layouts, "BOTTOMLEFT", 0, -7)

    -- 7: 昵称（Nickname）—— 对应 CellDB["nicknames"]，默认不勾选（隐私考虑）
    checkboxes.nickname = Cell.CreateCheckButton(confirmationFrame, L["Nickname"], function(checked)
        ignoredIndices["nicknames"] = not checked
    end)
    checkboxes.nickname:SetPoint("TOPLEFT", checkboxes.utilities, "BOTTOMLEFT", 0, -7)

    -- OnHide：面板隐藏时同时隐藏遮罩层
    confirmationFrame:SetScript("OnHide", function()
        confirmationFrame:Hide()
        if Cell.frames.aboutTab.mask then Cell.frames.aboutTab.mask:Hide() end
    end)

    -- OnShow：重置 ignoredIndices，默认所有复选框勾选（昵称除外，保护隐私）
    -- 若导入数据中无昵称数据，昵称复选框禁用（不可勾选）
    confirmationFrame:SetScript("OnShow", function()
        wipe(ignoredIndices)
        ignoredIndices["nicknames"] = true

        for name, cb in pairs(checkboxes) do
            if name == "nickname" then
                cb:SetChecked(false)
                cb:SetEnabled(imported["nicknames"])
            else
                cb:SetChecked(true)
            end
        end
    end)
end

---------------------------------------------------------------------
-- CreateImportExportFrame - 创建导入/导出主面板
-- 位于 About 标签页内的主面板，包含：
--   - 关闭按钮、导入按钮
--   - 标题文本（显示"导入"或"导出"及版本号）
--   - 导出选项复选框（包含昵称设置、包含角色设置——经典服专用）
--   - 可滚动的文本框（ScrollEditBox）：导入模式下粘贴编码字符串并实时校验；
--     导出模式下显示编码后的字符串并自动全选高亮
-- 面板复用同一个 textArea，通过 isImport 标志位切换导入/导出行为。
---------------------------------------------------------------------
local function CreateImportExportFrame()
    -- 创建面板 Frame，层级比 About 标签页高 50
    importExportFrame = CreateFrame("Frame", "CellOptionsFrame_ImportExport", Cell.frames.aboutTab, "BackdropTemplate")
    importExportFrame:Hide()
    Cell.StylizeFrame(importExportFrame, nil, Cell.GetAccentColorTable())
    importExportFrame:EnableMouse(true)
    importExportFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
    P.Size(importExportFrame, 430, 170)
    importExportFrame:SetPoint("BOTTOMLEFT", P.Scale(1), 27)

    if not Cell.frames.aboutTab.mask then
        Cell.CreateMask(Cell.frames.aboutTab, nil, {1, -1, -1, 1})
        Cell.frames.aboutTab.mask:Hide()
    end

    -- 关闭按钮（×）：隐藏主面板
    local closeBtn = Cell.CreateButton(importExportFrame, "×", "red", {18, 18}, false, false, "CELL_FONT_SPECIAL", "CELL_FONT_SPECIAL")
    closeBtn:SetPoint("TOPRIGHT", P.Scale(-5), P.Scale(-1))
    closeBtn:SetScript("OnClick", function() importExportFrame:Hide() end)

    -- 导入按钮（仅在导入模式下显示）：点击后弹出确认面板
    -- 点击时降级主面板层级让确认面板突出，同时清除文本框焦点避免误触发文本变更回调
    importBtn = Cell.CreateButton(importExportFrame, L["Import"], "green", {57, 18})
    importBtn:Hide()
    importBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", P.Scale(1), 0)
    importBtn:SetScript("OnClick", function()
        -- 降低主面板层级，确保确认面板显示在上方
        importExportFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 20)

        confirmationFrame:Show()

        -- local text = "|cFFFF7070"..L["All Cell settings will be overwritten!"].."|r\n"..
        --     "|cFFB7B7B7"..L["Autorun will be disabled for all code snippets"].."|r\n"..
        --     L["|cff1Aff1AYes|r - Overwrite"].."\n".."|cffff1A1A"..L["No"].."|r - "..L["Cancel"]
        -- local popup = Cell.CreateConfirmPopup(Cell.frames.aboutTab, 200, text, function(self)
        --     DoImport()
        -- end, function()
        --     importExportFrame:Hide()
        -- end, true)
        -- popup:SetPoint("TOPLEFT", importExportFrame, 117, -25)

        textArea.eb:ClearFocus()
    end)

    -- 标题文本：显示"导入"或"导出"+版本号，导入失败时显示红色错误信息
    title = importExportFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    title:SetPoint("TOPLEFT", 5, -5)

    -- 导出选项：是否包含昵称设置（仅导出模式显示，默认不勾选）
    -- 勾选/取消时重新生成导出字符串并更新文本框
    includeNicknamesCB = Cell.CreateCheckButton(importExportFrame, L["Include Nickname Settings"], function(checked)
        exported = GetExportString(checked, includeCharacterCB:GetChecked())
        textArea:SetText(exported)
    end)
    includeNicknamesCB:SetPoint("TOPLEFT", 5, -25)
    includeNicknamesCB:Hide()

    -- 导出选项：是否包含角色专属设置（仅经典服导出模式显示，默认不勾选）
    -- 包含点击施法和布局自动切换，鼠标悬停时显示 Tooltip 说明
    includeCharacterCB = Cell.CreateCheckButton(importExportFrame, L["Include Character Settings"], function(checked)
        exported = GetExportString(includeNicknamesCB:GetChecked(), checked)
        textArea:SetText(exported)
    end)
    includeCharacterCB:SetPoint("TOPLEFT", includeNicknamesCB, "TOPRIGHT", 200, 0)
    includeCharacterCB:Hide()
    Cell.SetTooltips(includeCharacterCB, "ANCHOR_TOPLEFT", 0, 2, L["Click-Castings"]..", "..L["Layout Auto Switch"])

    -- 可滚动文本框：导入/导出共用的核心编辑区域
    -- 导入模式（isImport=true）：用户粘贴编码字符串后实时解析校验
    --   1. 正则匹配 "^!CELL:(版本号):ALL!(编码数据)$"
    --   2. 版本号兼容性检查（>= MIN_VERSION 且 <= 当前版本）
    --   3. 三步解码：DecodeForPrint → DecompressDeflate → Deserialize
    --   4. 成功则显示版本号并启用导入按钮，失败则显示红色错误信息
    -- 导出模式（isImport=false）：恢复导出字符串并全选高亮（防止用户意外编辑）
    textArea = Cell.CreateScrollEditBox(importExportFrame, function(eb, userChanged)
        if userChanged then
            if isImport then
                imported = nil
                local text = eb:GetText()
                -- 解析编码字符串：匹配前缀格式 "!CELL:版本号:ALL!"
                local version, data = string.match(text, "^!CELL:(%d+):ALL!(.+)$")
                version = tonumber(version)

                if version and data then
                    -- 版本兼容性检查
                    if version >= Cell.MIN_VERSION and version <= Cell.versionNum then
                        local success
                        -- 三步解码：解码为二进制 → 解压缩 → 反序列化为 Lua 表
                        data = LibDeflate:DecodeForPrint(data)
                        success, data = pcall(LibDeflate.DecompressDeflate, LibDeflate, data)
                        success, data = Serializer:Deserialize(data)

                        if success and data then
                            title:SetText(L["Import"]..": r"..version)
                            importBtn:SetEnabled(true)
                            imported = data
                        else
                            title:SetText(L["Import"]..": |cffff2222"..L["Error"])
                            importBtn:SetEnabled(false)
                        end
                    else -- 版本不兼容（太旧或比当前版本还新）
                        title:SetText(L["Import"]..": |cffff2222"..L["Incompatible Version"])
                        importBtn:SetEnabled(false)
                    end
                else
                    title:SetText(L["Import"]..": |cffff2222"..L["Error"])
                    importBtn:SetEnabled(false)
                end
            else
                -- 导出模式：用户编辑后恢复原始导出内容，光标归零并全选
                eb:SetText(exported)
                eb:SetCursorPosition(0)
                eb:HighlightText()
            end
        end
    end)
    Cell.StylizeFrame(textArea.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    textArea:SetPoint("TOPLEFT", 5, -20)
    textArea:SetPoint("BOTTOMRIGHT", -5, 5)

    -- 文本框获得焦点时自动全选内容（方便用户 Ctrl+C 复制导出字符串）
    textArea.eb:SetScript("OnEditFocusGained", function() textArea.eb:HighlightText() end)
    -- 导出模式下鼠标松开时自动全选（防止用户误编辑导出内容）
    textArea.eb:SetScript("OnMouseUp", function()
        if not isImport then
            textArea.eb:HighlightText()
        end
    end)

    -- OnHide：隐藏面板并清理状态，同时隐藏遮罩层
    importExportFrame:SetScript("OnHide", function()
        importExportFrame:Hide()
        isImport = false
        exported = ""
        imported = nil
        Cell.frames.aboutTab.mask:Hide()
    end)

    -- OnShow：提升面板层级确保显示在其他元素上方，显示遮罩层阻止底层交互
    importExportFrame:SetScript("OnShow", function()
        importExportFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
        Cell.frames.aboutTab.mask:Show()
    end)
end

---------------------------------------------------------------------
-- F.ShowImportFrame - 显示导入面板
-- 外部调用入口（通过 Cell 选项界面按钮触发）。
-- 首次调用时惰性创建面板框架；后续调用直接显示。
-- 初始化导入模式：清空文本框、启用导入按钮（初始禁用，等校验通过）、隐藏导出选项复选框。
---------------------------------------------------------------------
local init
function F.ShowImportFrame()
    -- 惰性初始化：首次调用时创建所有 UI 框架
    if not init then
        init = true
        CreateImportExportFrame()
        CreateImportConfirmationFrame()
    end

    importExportFrame:Show()
    isImport = true
    importBtn:Show()
    importBtn:SetEnabled(false) -- 初始禁用，等用户粘贴有效字符串后启用

    exported = ""
    title:SetText(L["Import"])
    textArea:SetText("")
    textArea.eb:SetFocus(true) -- 自动聚焦方便用户粘贴

    -- 导入模式隐藏导出选项复选框，调整文本框布局
    includeNicknamesCB:Hide()
    includeCharacterCB:Hide()
    textArea:SetPoint("TOPLEFT", 5, -20)
    P.Height(importExportFrame, 200)
end

---------------------------------------------------------------------
-- F.ShowExportFrame - 显示导出面板
-- 外部调用入口（通过 Cell 选项界面按钮触发）。
-- 首次调用时惰性创建面板框架；后续调用直接显示。
-- 初始化导出模式：生成导出字符串、全选高亮方便复制、显示导出选项复选框。
---------------------------------------------------------------------
function F.ShowExportFrame()
    if not init then
        init = true
        CreateImportExportFrame()
        CreateImportConfirmationFrame()
    end

    importExportFrame:Show()
    isImport = false
    importBtn:Hide() -- 导出模式不显示导入按钮

    title:SetText(L["Export"]..": "..Cell.version)

    -- 生成导出字符串（默认不包含昵称）
    exported = GetExportString(false)

    textArea:SetText(exported)
    textArea.eb:SetFocus(true) -- 自动聚焦并全选，方便 Ctrl+C 复制

    -- 显示导出选项复选框（昵称默认不勾选；经典服额外显示角色设置选项）
    includeNicknamesCB:SetChecked(false)
    includeNicknamesCB:Show()
    if Cell.isVanilla or Cell.isTBC or Cell.isWrath or Cell.isCata then
        includeCharacterCB:SetChecked(false)
        includeCharacterCB:Show()
    end
    textArea:SetPoint("TOPLEFT", 5, -50)
    P.Height(importExportFrame, 230)
end

---------------------------------------------------------------------
-- Cell.ImportProfile - 供外部"安装器"插件调用的编程式导入 API
-- 外部插件（如配置分享插件）可直接调用此函数，传入编码字符串完成静默导入。
-- 与用户手动导入的区别：不重载 UI（noReload=true），通过返回值告知调用方是否成功。
---------------------------------------------------------------------

---@param profileString string 编码的配置字符串（"!CELL:版本号:ALL!" 格式）
---@param profileName string? 配置名称（预留参数，当前未使用）
---@param ignoredIndicesExternal table? 指定跳过的配置分类，key 为 CellDB 字段名，value 为 boolean
---@return boolean success 导入是否成功
function Cell.ImportProfile(profileString, profileName, ignoredIndicesExternal)
    imported = nil
    -- 解析并解码编码字符串（与 UI 导入流程相同的三步解码管线）
    local version, data = string.match(profileString, "^!CELL:(%d+):ALL!(.+)$")
    version = tonumber(version)

    if version and data then
        if version >= Cell.MIN_VERSION and version <= Cell.versionNum then
            local success
            data = LibDeflate:DecodeForPrint(data) -- 解码为二进制
            success, data = pcall(LibDeflate.DecompressDeflate, LibDeflate, data) -- 解压缩
            success, data = Serializer:Deserialize(data) -- 反序列化为 Lua 表

            if success and data then
                imported = data
            end
        end
    end

    -- 应用外部传入的忽略列表（覆盖默认的 ignoredIndices）
    if ignoredIndicesExternal then
      wipe(ignoredIndices)
      for index, value in pairs(ignoredIndicesExternal) do
        ignoredIndices[index] = value
      end
    end

    -- 解码成功则静默导入（不重载 UI），返回 true
    if imported then
        DoImport(true)
        return true
    end

    return false
end
