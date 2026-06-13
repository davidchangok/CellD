-- CellD 指示器导出模块：将布局中的指示器配置序列化、压缩并编码为可分享的字符串
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 序列化与压缩库：用于将指示器配置数据打包为可导出的紧凑字符串
local Serializer = LibStub:GetLibrary("LibSerialize")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local deflateConfig = {level = 9} -- 压缩级别 9（最高压缩比）

-- 当前操作的布局名称（如 "default" 或自定义布局名）
local fromLayout
-- 指示器按钮对象池，按 index 索引复用
local indicatorButtons = {}
-- 当前选中的指示器集合，key 为 index，value 为 true
local selectedIndicators = {}
-- 前向声明：Toggle 切换选中状态，Validate 校验导出按钮是否可点击
local Toggle, Validate

-------------------------------------------------
-- 导出面板父框架：覆盖在指示器标签页上方的全尺寸遮罩层
-------------------------------------------------
local exportParent = CreateFrame("Frame", "CellOptionsFrame_IndicatorsExport", Cell.frames.indicatorsTab)
exportParent:Hide()
exportParent:SetAllPoints(Cell.frames.indicatorsTab)
exportParent:SetFrameLevel(Cell.frames.indicatorsTab:GetFrameLevel() + 50) -- 高于标签页所有子元素

-------------------------------------------------
-- 导出面板子控件声明：来源布局、指示器列表、导出区、文本框、导出按钮
-------------------------------------------------
local from, listFrame, exportFrame, textArea, exportBtn

-- 创建指示器导出面板的完整 UI（列表 + 导出区 + 按钮栏）
local function CreateIndicatorsExportFrame()
    -- 创建标签页遮罩层（首次使用时创建，之后的显示/隐藏由 OnShow/OnHide 控制）
    if not Cell.frames.indicatorsTab.mask then
        Cell.CreateMask(Cell.frames.indicatorsTab, nil, {1, -1, -1, 1})
        Cell.frames.indicatorsTab.mask:Hide()
    end

    -- 左侧指示器列表面板（136x525）
    local listParent = Cell.CreateFrame(nil, exportParent, 136, 525)
    Cell.StylizeFrame(listParent, nil, Cell.GetAccentColorTable())
    listParent:SetPoint("BOTTOMLEFT", 5, 24)
    listParent:Show()

    -- 列表顶部显示来源布局名称
    from = listParent:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    from:SetPoint("TOPLEFT", 5, -5)

    -- 指示器按钮的滚动列表容器
    listFrame = CreateFrame("Frame", nil, listParent, "BackdropTemplate")
    Cell.StylizeFrame(listFrame)
    listFrame:SetPoint("TOPLEFT", 5, -20)
    listFrame:SetPoint("TOPRIGHT", -5, -5)
    listFrame:SetHeight(457)

    -- 创建滚动框架，每次滚动步长 19 像素（与按钮高度匹配）
    Cell.CreateScrollFrame(listFrame)
    listFrame.scrollFrame:SetScrollStep(19)

    -- 右侧导出结果显示区（281x273）
    exportFrame = Cell.CreateFrame(nil, exportParent, 281, 273)
    Cell.StylizeFrame(exportFrame, nil, Cell.GetAccentColorTable())
    exportFrame:SetPoint("BOTTOMLEFT", listParent, "BOTTOMRIGHT", 5, 0)

    -- 导出结果区标题（显示内置/自定义指示器计数）
    local title = exportFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    title:SetPoint("TOPLEFT", 5, -5)

    -- 可滚动编辑框：用于显示和选择导出的编码字符串
    textArea = Cell.CreateScrollEditBox(exportFrame)
    Cell.StylizeFrame(textArea.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    textArea:SetPoint("TOPLEFT", 5, -20)
    textArea:SetPoint("BOTTOMRIGHT", -5, 5)

    -- 编辑框获得焦点时自动全选文本，方便用户 Ctrl+C 复制
    textArea.eb:SetScript("OnEditFocusGained", function() textArea.eb:HighlightText() end)
    -- 鼠标点击时也自动全选（导入模式下不操作，避免干扰粘贴）
    textArea.eb:SetScript("OnMouseUp", function()
        if not isImport then
            textArea.eb:HighlightText()
        end
    end)

    -- 底部控制按钮栏
    -- 导出按钮：将选中的指示器配置序列化、压缩、编码为可分享字符串
    exportBtn = Cell.CreateButton(listParent, L["Export"], "green", {64, 20})
    exportBtn:SetPoint("BOTTOMLEFT", 5, 5)
    exportBtn:SetEnabled(false) -- 未选中任何指示器时禁用
    exportBtn:SetScript("OnClick", function()
        -- 显示导出结果区
        exportFrame:Show()

        local builtIn, custom = 0, 0
        -- data.indicators: 存放选中指示器的完整配置
        -- data.related: 存放与选中指示器类型相关的全局配置（如光环、减伤、技能列表等）
        local data = {
            ["indicators"] = {},
            ["related"] = {},
        }

        -- 遍历所有选中的指示器，构建导出数据
        for index in pairs(selectedIndicators) do
            -- 统计内置/自定义指示器数量
            if indicatorButtons[index].isBuiltIn then
                builtIn = builtIn + 1
            else
                custom = custom + 1
            end

            -- 复制该指示器在布局中的完整配置
            data["indicators"][index] = CellDB["layouts"][fromLayout]["indicators"][index]

            -- 根据指示器类型，包含相关的全局配置数据
            local name = CellDB["layouts"][fromLayout]["indicators"][index]["indicatorName"]
            if name == "aoeHealing" then
                data["related"]["aoeHealings"] = CellDB["aoeHealings"]
            end
            -- 减伤冷却 或 全部冷却 都需要减伤列表
            if name == "defensiveCooldowns" or name == "allCooldowns" then
                data["related"]["defensives"] = CellDB["defensives"]
            end
            -- 外部冷却 或 全部冷却 都需要外部技能列表
            if name == "externalCooldowns" or name == "allCooldowns" then
                data["related"]["externals"] = CellDB["externals"]
            end

            -- Debuff 类型需要黑名单和高亮 Debuff 配置
            if name == "debuffs" then
                data["related"]["debuffBlacklist"] = CellDB["debuffBlacklist"]
                data["related"]["bigDebuffs"] = CellDB["bigDebuffs"]
            -- RaidDebuffs 导出已禁用（注释保留，后续可能需要恢复）
            -- elseif name == "raidDebuffs" then
            --     if Cell.isRetail then
            --         data["related"]["cleuAuras"] = CellDB["cleuAuras"]
            --         data["related"]["cleuGlow"] = CellDB["cleuGlow"]
            --     end
            elseif name == "targetedSpells" then
                data["related"]["targetedSpellsList"] = CellDB["targetedSpellsList"]
                data["related"]["targetedSpellsGlow"] = CellDB["targetedSpellsGlow"]
            elseif name == "actions" then
                data["related"]["actions"] = CellDB["actions"]
            end
        end

        -- 标题显示内置/自定义指示器统计（绿色=内置，粉色=自定义）
        title:SetText(L["Export"]..": ".."|cff90EE90"..builtIn.." "..L["built-in(s)"].."|r, |cffFFB5C5"..custom.." "..L["custom(s)"].."|r")

        -- 构建导出字符串：带版本号前缀 + 序列化 + 压缩 + 可打印编码
        local prefix = "!CELL:"..Cell.versionNum..":INDICATOR:"..(builtIn+custom).."!"

        local exported = Serializer:Serialize(data) -- 序列化为字符串
        exported = LibDeflate:CompressDeflate(exported, deflateConfig) -- Deflate 压缩
        exported = LibDeflate:EncodeForPrint(exported) -- 编码为可打印字符
        exported = prefix..exported -- 拼接版本前缀

        textArea:SetText(exported)
    end)

    -- 关闭按钮：隐藏整个导出面板
    local closeBtn = Cell.CreateButton(listParent, L["Close"], "red", {63, 20})
    closeBtn:SetPoint("BOTTOMLEFT", exportBtn, "BOTTOMRIGHT", P.Scale(-1), 0)
    closeBtn:SetScript("OnClick", function()
        exportParent:Hide()
    end)

    -- 全选按钮：选中列表中所有指示器
    local allBtn = Cell.CreateButton(listParent, L["ALL"], "accent-hover", {64, 20})
    allBtn:SetPoint("BOTTOMLEFT", exportBtn, "TOPLEFT", 0, P.Scale(-1))
    allBtn:SetScript("OnClick", function()
        for i = 1, #indicatorButtons do
            Toggle(i, true)
        end
        Validate()
    end)

    -- 反选按钮：将当前选中状态取反
    local invertBtn = Cell.CreateButton(listParent, L["INVERT"], "accent-hover", {63, 20})
    invertBtn:SetPoint("BOTTOMLEFT", closeBtn, "TOPLEFT", 0, P.Scale(-1))
    invertBtn:SetScript("OnClick", function()
        for i = 1, #indicatorButtons do
            if selectedIndicators[i] then
                Toggle(i, false, true) -- 已选中的取消选中并恢复背景
            else
                Toggle(i, true)
            end
        end
        Validate()
    end)
end

-------------------------------------------------
-- 核心逻辑函数
-------------------------------------------------
-- 校验选中状态：有选中项时启用导出按钮，否则禁用
Validate = function()
    if F.Getn(selectedIndicators) ~= 0 then
        exportBtn:SetEnabled(true)
    else
        exportBtn:SetEnabled(false)
    end
end

-- 切换指定索引指示器的选中状态
-- @param index: 指示器在列表中的序号
-- @param isSelect: true=选中, false=取消选中
-- @param unhighlight: 取消选中时是否还原背景为透明（用于反选操作）
Toggle = function(index, isSelect, unhighlight)
    b = indicatorButtons[index]
    if isSelect then
        -- 选中：标记状态，设背景为悬停色，移除鼠标进出脚本，文字变绿
        selectedIndicators[index] = true
        b:SetBackdropColor(unpack(b.hoverColor))
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
        b:SetTextColor(0, 1, 0)
        b.selected = true
    else
        -- 取消选中：清除标记，恢复鼠标进出交互，文字变白
        selectedIndicators[index] = nil
        b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(self.hoverColor)) end)
        b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(self.color)) end)
        b:SetTextColor(1, 1, 1)
        b.selected = false
        if unhighlight then
            b:SetBackdropColor(0, 0, 0, 0) -- 彻底清除背景高亮
        end
    end
end

-- 加载指定布局中的指示器列表，复用按钮对象池，重置所有选中状态
local function LoadIndicators(layout)
    -- 清空当前选中集合，重置滚动条
    wipe(selectedIndicators)
    listFrame.scrollFrame:Reset()

    local last, n
    -- 遍历布局中的所有指示器配置
    for i, t in pairs(CellDB["layouts"][layout]["indicators"]) do
        local b = indicatorButtons[i]
        -- 按钮对象池：首次遇到此 index 时创建，之后复用
        if not b then
            b = Cell.CreateButton(listFrame.scrollFrame.content, " ", "transparent-accent", {20, 20})
            indicatorButtons[i] = b
            -- 点击切换该指示器的选中状态
            b:SetScript("OnClick", function()
                b.selected = not b.selected
                Toggle(i, b.selected)
                Validate()
            end)
        end

        -- 重置按钮状态到默认（未选中、白色、透明背景、正常鼠标交互）
        b:Show()
        b:SetParent(listFrame.scrollFrame.content)
        b.selected = false
        b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(self.hoverColor)) end)
        b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(self.color)) end)
        b:SetTextColor(1, 1, 1)
        b:SetBackdropColor(0, 0, 0, 0)

        -- 区分内置指示器（显示本地化名称）和自定义指示器（显示原名+类型图标）
        if t["type"] == "built-in" then
            b:SetText(L[t["name"]]) -- 内置指示器使用本地化文本
            b.isBuiltIn = true
        else
            b:SetText(t["name"]) -- 自定义指示器直接显示名称
            b.isBuiltIn = false
            -- 为自定义指示器创建类型图标（共享同一个纹理对象，切换时更新纹理路径）
            if not b.typeIcon then
                b.typeIcon = b:CreateTexture(nil, "ARTWORK")
                b.typeIcon:SetPoint("RIGHT", -2, 0)
                b.typeIcon:SetSize(16, 16)
                b.typeIcon:SetAlpha(0.5)
                b:GetFontString():ClearAllPoints()
                b:GetFontString():SetPoint("LEFT", 5, 0)
                b:GetFontString():SetPoint("RIGHT", b.typeIcon, "LEFT", -2, 0)
            end
            b.typeIcon:SetTexture("Interface\\AddOns\\Cell\\Media\\Indicators\\indicator-"..t["type"])
        end

        -- 垂直排列：每个按钮放在上一个的下方，间距 1 像素
        b:SetPoint("RIGHT")
        if last then
            b:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 1)
        else
            b:SetPoint("TOPLEFT")
        end
        last = b
        n = i
    end

    -- 设置滚动内容高度，确保所有按钮可滚动查看
    listFrame.scrollFrame:SetContentHeight(20, n, -1)
end

-- 导出面板隐藏时：隐藏遮罩层、导出结果显示区和清空文本框
exportParent:SetScript("OnHide", function()
    exportParent:Hide()
    Cell.frames.indicatorsTab.mask:Hide()
    exportFrame:Hide()
    textArea:SetText("")
end)

-- 导出面板显示时：显示遮罩层覆盖底层标签页内容
exportParent:SetScript("OnShow", function()
    Cell.frames.indicatorsTab.mask:Show()
end)

-- 公开接口：显示指示器导出面板
-- @param layout: 布局名称（如 "default" 或自定义布局名）
-- 首次调用时创建 UI，后续调用直接刷新列表并显示
local init
function F.ShowIndicatorsExportFrame(layout)
    if not init then
        init = true
        CreateIndicatorsExportFrame() -- 延迟创建，避免加载时不必要的性能开销
    end

    exportParent:Show()
    -- 布局名称显示："default" 显示为游戏内置的 DEFAULT 全局字符串
    from:SetText(layout == "default" and _G.DEFAULT or layout)
    LoadIndicators(layout)
    fromLayout = layout -- 记录当前操作的布局，供导出按钮使用
end