-- 模块头：从插件变量参数中获取 Cell 核心库
local _, Cell = ...
-- 本地化字符串表，用于多语言支持
local L = Cell.L
-- 通用工具函数集（深拷贝、安全运算等）
local F = Cell.funcs
-- 像素级精确布局函数集
local P = Cell.pixelPerfectFuncs

-- 备份面板主框架引用（延迟创建，首次调用 ShowBackupFrame 时实例化）
local backupFrame
-- 备份条目按钮缓存表，buttons[0] 为"创建备份"按钮，buttons[i] 为第 i 条备份的行控件
local buttons = {}
-- LoadBackups 函数的前向声明，供 CreateItem 内部（删除按钮回调）引用
local LoadBackups
-- 日期格式化模板，用于生成备份描述默认文本
local DATE_FORMAT = "%Y-%m-%d %H:%M:%S"

---------------------------------------------------------------------
-- 创建单条备份行控件
-- 每条备份行包含：版本号标签（左侧）、描述文本（中段）、
--   行本体（作为恢复按钮，点击触发还原确认）、删除按钮（右侧）、重命名按钮（右侧）
-- @param index: 备份在 CellDBBackup 数组中的索引
-- @return b: 整行按钮控件（作为容器），其上附加了 version/text/del/rename 子元素
---------------------------------------------------------------------
local function CreateItem(index)
    -- 创建行本体按钮，覆盖整行区域，同时作为恢复操作的热区
    local b = Cell.CreateButton(backupFrame.list.content, nil, "accent-hover", {20, 20})

    -- 版本号标签（左侧固定位置），显示创建备份时的插件版本
    b.version = b:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    b.version:SetJustifyH("LEFT")
    b.version:SetPoint("LEFT", 5, 0)

    -- 描述文本（中段），显示用户自定义的备份名称，不换行
    b.text = b:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.text:SetPoint("LEFT", 100, 0)
    b.text:SetPoint("RIGHT", -45, 0)

    -- [恢复]按钮逻辑：点击行本体触发，弹出确认框后还原备份数据并重载 UI
    b:SetScript("OnClick", function()
        -- 版本不兼容（低于最低版本要求）的备份禁止恢复
        if b.isInvalid then return end

        -- 弹出确认框前降低备份面板层级，使遮罩层正确显示在面板与确认框之间
        backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 20)
        Cell.frames.aboutTab.mask:Show()

        -- 确认弹窗文本：红色标题"恢复备份？" + 备份描述 + 灰色版本号
        local text = "|cFFFF7070"..L["Restore backup"].."?|r\n"..CellDBBackup[index]["desc"].."\n|cFFB7B7B7"..CellDBBackup[index]["version"]
        local popup = Cell.CreateConfirmPopup(Cell.frames.aboutTab, 200, text, function()
            -- 用户确认：恢复面板层级，将备份数据写回当前配置，重载 UI 使配置生效
            backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
            CellDB = CellDBBackup[index]["DB"]
            if CellCharacterDB then
                CellCharacterDB = CellDBBackup[index]["CharacterDB"]
            end
            ReloadUI()
        end, function()
            -- 用户取消：仅恢复面板层级
            backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
        end)
        popup:SetPoint("TOP", backupFrame, 0, -50)
    end)

    -- [删除]按钮：行右侧的删除图标按钮，图标使用 delete2 纹理
    b.del = Cell.CreateButton(b, "", "none", {20, 20}, true, true)
    b.del:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\delete2", {18, 18}, {"CENTER", 0, 0})
    b.del:SetPoint("RIGHT")
    -- 默认灰色，鼠标悬停时高亮为白色
    b.del.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
    b.del:SetScript("OnEnter", function()
        b:GetScript("OnEnter")(b)
        b.del.tex:SetVertexColor(1, 1, 1, 1)
    end)
    b.del:SetScript("OnLeave",  function()
        b:GetScript("OnLeave")(b)
        b.del.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
    end)
    -- 点击弹出确认框，确认后从数组中移除该备份并刷新列表
    b.del:SetScript("OnClick", function()
        backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 20)
        Cell.frames.aboutTab.mask:Show()

        local text = "|cFFFF7070"..L["Delete backup"].."?|r\n"..CellDBBackup[index]["desc"]
        local popup = Cell.CreateConfirmPopup(Cell.frames.aboutTab, 200, text, function()
            backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
            tremove(CellDBBackup, index)
            LoadBackups()
        end, function()
            backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
        end)
        popup:SetPoint("TOP", backupFrame, 0, -50)
    end)

    -- [重命名]按钮：位于删除按钮左侧，图标使用 rename 纹理
    b.rename = Cell.CreateButton(b, "", "none", {20, 20}, true, true)
    b.rename:SetPoint("RIGHT", b.del, "LEFT", 1, 0)
    b.rename:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\rename", {18, 18}, {"CENTER", 0, 0})
    -- 默认灰色，鼠标悬停时高亮为白色
    b.rename.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
    b.rename:SetScript("OnEnter", function()
        b:GetScript("OnEnter")(b)
        b.rename.tex:SetVertexColor(1, 1, 1, 1)
    end)
    b.rename:SetScript("OnLeave",  function()
        b:GetScript("OnLeave")(b)
        b.rename.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
    end)
    -- 点击弹出编辑框，确认后更新备份描述文本；若输入为空则使用当前日期作为默认名称
    b.rename:SetScript("OnClick", function()
        local popup = Cell.CreatePopupEditBox(backupFrame, function(text)
            if strtrim(text) == "" then text = date() end
            CellDBBackup[index]["desc"] = text
            b.text:SetText(text)
        end)
        popup:SetPoint("TOPLEFT", b)
        popup:SetPoint("BOTTOMRIGHT", b)
        popup:ShowEditBox(CellDBBackup[index]["desc"])
    end)

    return b
end

---------------------------------------------------------------------
-- 创建备份面板主框架（延迟创建，首次调用时执行）
-- 面板布局：标题（左上）、提示滚动文本（标题右侧）、关闭按钮（右上）、
--   可滚动备份列表（主体）、"创建备份"按钮（列表底部）
-- 面板附带遮罩层，点击面板外部区域通过遮罩层拦截事件
---------------------------------------------------------------------
local function CreateBackupFrame()
    -- 以 aboutTab 为父框架创建备份面板，命名便于调试
    backupFrame = CreateFrame("Frame", "CellOptionsFrame_Backup", Cell.frames.aboutTab, "BackdropTemplate")
    backupFrame:Hide()
    Cell.StylizeFrame(backupFrame, nil, Cell.GetAccentColorTable())
    backupFrame:EnableMouse(true)
    -- 面板层级高于 aboutTab 以确保显示在上层
    backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
    P.Size(backupFrame, 430, 185)
    backupFrame:SetPoint("BOTTOMLEFT", P.Scale(1), 27)

    -- 在 aboutTab 上创建半透明遮罩层（仅首次），用于拦截面板外点击
    if not Cell.frames.aboutTab.mask then
        Cell.CreateMask(Cell.frames.aboutTab, nil, {1, -1, -1, 1})
        Cell.frames.aboutTab.mask:Hide()
    end

    -- 标题："备份"（本地化文本）
    local title = backupFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText(L["Backups"])

    -- 提示信息：可滚动的灰色提示文本，位于标题右侧
    local tips = Cell.CreateScrollTextFrame(backupFrame, "|cffb7b7b7"..L["BACKUP_TIPS"], 0.02, nil, 2)
    tips:SetPoint("TOPRIGHT", -30, -1)
    tips:SetPoint("LEFT", title, "RIGHT", 5, 0)

    -- 关闭按钮：红色"×"按钮，点击隐藏面板
    local closeBtn = Cell.CreateButton(backupFrame, "\195\151", "red", {18, 18}, false, false, "CELL_FONT_SPECIAL", "CELL_FONT_SPECIAL")
    closeBtn:SetPoint("TOPRIGHT", P.Scale(-5), P.Scale(-1))
    closeBtn:SetScript("OnClick", function() backupFrame:Hide() end)

    -- 列表容器：在面板主体区域创建可滚动列表框架
    local listFrame = Cell.CreateFrame(nil, backupFrame)
    listFrame:SetPoint("TOPLEFT", 5, -25)
    listFrame:SetPoint("BOTTOMRIGHT", -5, 5)
    listFrame:Show()

    -- 为列表容器添加滚动条支持
    Cell.CreateScrollFrame(listFrame)
    backupFrame.list = listFrame.scrollFrame
    Cell.StylizeFrame(listFrame.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    listFrame.scrollFrame:SetScrollStep(25)

    -- [创建备份]按钮（buttons[0]）：位于列表底部，点击弹出编辑框创建新备份
    buttons[0] = Cell.CreateButton(listFrame.scrollFrame.content, " ", "accent-hover", {20, 20})
    buttons[0]:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create", {18, 18}, {"LEFT", 2, 0})
    buttons[0]:SetScript("OnClick", function(self)
        -- 弹出编辑框，用户输入备份描述文本
        local popup = Cell.CreatePopupEditBox(backupFrame, function(text)
            -- 若输入为空则使用当前日期作为默认名称
            if strtrim(text) == "" then text = date(DATE_FORMAT) end
            -- 将当前全局配置和角色配置（深拷贝）保存为新备份条目
            tinsert(CellDBBackup, {
                ["desc"] = text,
                ["version"] = Cell.version,
                ["versionNum"] = Cell.versionNum,
                ["DB"] = F.Copy(CellDB),
                ["CharacterDB"] = CellCharacterDB and F.Copy(CellCharacterDB),
            })
            -- 刷新列表显示新备份
            LoadBackups()
        end)
        popup:SetPoint("TOPLEFT", self)
        popup:SetPoint("BOTTOMRIGHT", self)
        -- 编辑框预填充当前日期作为默认名称
        popup:ShowEditBox(date(DATE_FORMAT))
    end)
    -- 为创建按钮添加详细提示
    Cell.SetTooltips(buttons[0], "ANCHOR_TOPLEFT", 0, 3, L["Create Backup"], L["BACKUP_TIPS2"])

    -- OnHide 事件处理：面板隐藏时同步隐藏遮罩层
    backupFrame:SetScript("OnHide", function()
        backupFrame:Hide()
        Cell.frames.aboutTab.mask:Hide()
    end)

    -- OnShow 事件处理：面板显示时提升层级并显示遮罩层
    backupFrame:SetScript("OnShow", function()
        backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
        Cell.frames.aboutTab.mask:Show()
    end)
end

---------------------------------------------------------------------
-- 刷新备份列表显示
-- 遍历 CellDBBackup 数组，为每条备份创建或复用行控件，
-- 更新版本号（标记不兼容版本为红色 Invalid）、描述文本，
-- 调整"创建备份"按钮位置，隐藏多余的行控件，更新滚动区域高度
---------------------------------------------------------------------
function LoadBackups()
    -- 重置滚动位置到顶部
    backupFrame.list:ResetScroll()

    -- 遍历所有备份条目：若行控件不存在则创建，存在则复用
    for i, t in pairs(CellDBBackup) do
        if not buttons[i] then
            buttons[i] = CreateItem(i)

            -- 第一行锚定在列表顶部，其余行依次向下排列
            if i == 1 then
                buttons[i]:SetPoint("TOPLEFT", 5, -5)
            else
                buttons[i]:SetPoint("TOPLEFT", buttons[i-1], "BOTTOMLEFT", 0, -5)
            end
            buttons[i]:SetPoint("RIGHT", -5, 0)
        end

        -- 版本检查：低于最低兼容版本的备份标记为无效（红色警告，禁止恢复）
        if t["versionNum"] < Cell.MIN_VERSION then
            buttons[i].version:SetText("|cffff2222"..L["Invalid"])
            buttons[i].isInvalid = true
        else
            buttons[i].version:SetText(t["version"])
            buttons[i].isInvalid = nil
        end
        buttons[i].text:SetText(t["desc"])
        buttons[i]:Show()
    end

    local n = #CellDBBackup

    -- "创建备份"按钮：放置在所有备份条目之后
    buttons[0]:ClearAllPoints()
    buttons[0]:SetPoint("RIGHT", -5, 0)
    if n == 0 then
        buttons[0]:SetPoint("TOPLEFT", 5, -5)
    else
        buttons[0]:SetPoint("TOPLEFT", buttons[n], "BOTTOMLEFT", 0, -5)
    end

    -- 隐藏多余的旧行控件（当备份数量减少时）
    for i = n + 1, #buttons do
        buttons[i]:Hide()
    end

    -- 更新滚动区域内容高度：n 个备份行 + 1 个创建按钮，加上间距
    backupFrame.list:SetContentHeight((n + 1) * P.Scale(20) + (n + 2) * P.Scale(5))
end

---------------------------------------------------------------------
-- 外部调用入口：显示备份面板
-- 首次调用时创建面板框架，随后刷新列表并显示面板
---------------------------------------------------------------------
function F.ShowBackupFrame()
    if not backupFrame then
        CreateBackupFrame()
    end

    LoadBackups()
    backupFrame:Show()
end