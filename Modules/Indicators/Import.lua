local _, Cell = ...
local L = Cell.L           -- 本地化字符串表
local F = Cell.funcs        -- 通用函数集
local I = Cell.iFuncs       -- 指示器专用函数集
local P = Cell.pixelPerfectFuncs  -- 像素精确缩放函数集

-- 序列化库：用于将 Lua 表序列化/反序列化为字符串
local Serializer = LibStub:GetLibrary("LibSerialize")
-- 压缩库：用于对字符串进行 Deflate 压缩/解压
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local deflateConfig = {level = 9}  -- 压缩级别 9（最高压缩率）

-- toLayout: 当前正在导入的目标布局名
-- toLayoutName: 目标布局的显示名称（"default" 布局显示为系统默认名称）
local toLayout, toLayoutName
-- imported: 解析后待导入的完整数据表（包含 indicators 和 related 字段）
local imported

-------------------------------------------------
-- 导入面板 UI 组件
-------------------------------------------------
-- importFrame: 导入浮层面板本体
-- title: 面板顶部的标题文本
-- textArea: 用户粘贴编码字符串的编辑框
local importFrame, title, textArea

-------------------------------------------------
-- 创建指示器导入面板
-- 构建一个浮层窗口，包含：标题、编码文本输入框、预览列表（含滚动条）、导入/关闭按钮
-------------------------------------------------
local function CreateIndicatorsImportFrame()
    -- 如果指示器标签页还没有遮罩层则创建一个，用于导入面板弹出时遮罩背景
    if not Cell.frames.indicatorsTab.mask then
        Cell.CreateMask(Cell.frames.indicatorsTab, nil, {1, -1, -1, 1})
        Cell.frames.indicatorsTab.mask:Hide()
    end

    -- 创建导入浮层面板，尺寸 430x297
    importFrame = Cell.CreateFrame("CellOptionsFrame_IndicatorsImport", Cell.frames.indicatorsTab, 430, 297)
    -- 将面板层级抬高到标签页之上 50 层，确保不被其他 UI 遮挡
    importFrame:SetFrameLevel(Cell.frames.indicatorsTab:GetFrameLevel() + 50)
    Cell.StylizeFrame(importFrame, nil, Cell.GetAccentColorTable())
    importFrame:SetPoint("BOTTOMLEFT", P.Scale(1), 24)

    -- 标题文本：显示 "导入 > 布局名" 及导入状态
    title = importFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    title:SetPoint("TOPLEFT", 5, -5)

    -- 预览列表：解析成功后在此显示所有指示器的名称列表
    local listFrame = CreateFrame("Frame", nil, importFrame, "BackdropTemplate")
    Cell.StylizeFrame(listFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    listFrame:SetPoint("TOPLEFT", 5, -20)
    listFrame:SetPoint("BOTTOMRIGHT", importFrame, "BOTTOMLEFT", 139, 29)
    -- 为列表添加滚动条，步长 19 像素
    Cell.CreateScrollFrame(listFrame)
    listFrame.scrollFrame:SetScrollStep(19)

    -------------------------------------------------
    -- 导入按钮：确认执行导入操作
    -------------------------------------------------
    local importBtn = Cell.CreateButton(importFrame, L["Import"], "green", {67, 20})
    importBtn:SetPoint("BOTTOMLEFT", 5, 5)
    -- 初始禁用，只有解析成功后才启用
    importBtn:SetEnabled(false)
    importBtn:SetScript("OnClick", function()
        -- 降低面板层级，让确认弹窗显示在合适位置
        importFrame:SetFrameLevel(Cell.frames.indicatorsTab:GetFrameLevel() + 20)

        -- 构造确认弹窗的提示文本：显示目标布局名、覆盖警告、是/否选项
        local text = L["Import"].." > "..Cell.GetAccentColorString()..toLayoutName.."|r\n"
            ..L["This may overwrite built-in indicators"].."\n"
            ..L["|cff1Aff1AYes|r - Overwrite"].."\n|cffff1A1A"..L["No"].."|r - "..L["Cancel"]

        -- 显示确认弹窗，用户点击"是"后执行导入合并逻辑
        local popup = Cell.CreateConfirmPopup(Cell.frames.indicatorsTab, 250, text, function(self)
            local toLayoutTable = CellDB["layouts"][toLayout]
            -- 计算当前布局中最后一个自定义指示器的索引位置
            local lastIndex
            local last = #toLayoutTable["indicators"]
            lastIndex = last - Cell.defaults.builtIns

            -- 遍历导入数据中的所有指示器，区分内置与自定义分别处理
            -- indicators
            for i, t in pairs(imported.indicators) do
                if t["type"] == "built-in" then
                    -- 过滤无效的内置指示器（名称必须在默认索引表中存在）
                    if Cell.defaults.indicatorIndices[t.indicatorName] then
                        -- 注意：内置指示器会直接覆盖当前布局中的同名指示器
                        toLayoutTable.indicators[Cell.defaults.indicatorIndices[t.indicatorName]] = t
                    end
                else
                    -- 注意：自定义指示器追加到布局末尾
                    lastIndex = lastIndex + 1
                    t["indicatorName"] = "indicator"..lastIndex
                    -- 注意：移除自定义指示器光环列表中已失效的法术 ID
                    F.FilterInvalidSpells(t["auras"])
                    tinsert(toLayoutTable["indicators"], t)
                end
            end

            -- 导入关联数据：包括黑名单、大debuff、群疗、减伤、外部技能、动作等
            -- related
            for k, v in pairs(imported.related) do
                -- cleuGlow 和 targetedSpellsGlow 不做无效法术过滤（它们是布尔/开关值）
                if k ~= "cleuGlow" and k ~= "targetedSpellsGlow" then
                    F.FilterInvalidSpells(v)
                end

                CellDB[k] = v

                -- 根据键名更新对应的运行时变量
                if k == "debuffBlacklist" then
                    Cell.vars.debuffBlacklist = F.ConvertTable(CellDB[k])
                elseif k == "bigDebuffs" then
                    Cell.vars.bigDebuffs = F.ConvertTable(CellDB[k])
                elseif k == "aoeHealings" then
                    I.UpdateAoEHealings(CellDB[k])
                elseif k == "defensives" then
                    I.UpdateDefensives(CellDB[k])
                elseif k == "externals" then
                    I.UpdateExternals(CellDB[k])
                -- elseif k == "cleuAuras" then
                --     if Cell.isRetail then
                --         I.UpdateCleuAuras(CellDB[k])
                --     elseif Cell.isCata then
                --         CellDB[k] = nil
                --     end
                -- elseif k == "cleuGlow" then
                --     if Cell.isCata then
                --         CellDB[k] = nil
                --     end
                elseif k == "targetedSpellsList" then
                    Cell.vars.targetedSpellsList = F.ConvertTable(CellDB[k])
                elseif k == "targetedSpellsGlow" then
                    Cell.vars.targetedSpellsGlow = CellDB[k]
                elseif k == "actions" then
                    Cell.vars.actions = I.ConvertActions(CellDB[k])
                end
            end

            -- 触发事件：通知 UI 刷新指示器显示
            Cell.Fire("UpdateIndicators", toLayout)
            Cell.Fire("IndicatorsChanged", toLayout)

            importFrame:Hide()
        end, function(self)
            -- 用户点击"否"或取消：关闭弹窗并隐藏导入面板
            importFrame:Hide()
        end, true)
        popup:SetPoint("TOPLEFT", importFrame, 75, -40)

        -- 清除编辑框焦点（防止确认弹窗显示期间误输入）
        textArea.eb:ClearFocus()
    end)

    -------------------------------------------------
    -- 关闭按钮：隐藏导入面板
    -------------------------------------------------
    local closeBtn = Cell.CreateButton(importFrame, L["Close"], "red", {67, 20})
    closeBtn:SetPoint("BOTTOMLEFT", importBtn, "BOTTOMRIGHT", P.Scale(-1), 0)
    closeBtn:SetScript("OnClick", function()
        importFrame:Hide()
    end)

    -------------------------------------------------
    -- 辅助函数：当解析失败时调用，将标题置为红色错误提示并重置 UI 状态
    -------------------------------------------------
    local function Failed(reason)
        title:SetText(L["Import"].." > "..toLayoutName..": |cffff2222"..reason)
        importBtn:SetEnabled(false)
        listFrame.scrollFrame:Reset()
    end

    -------------------------------------------------
    -- 编码文本输入区域
    -- 用户在此粘贴导出的编码字符串，插件自动解析并预览
    -------------------------------------------------
    textArea = Cell.CreateScrollEditBox(importFrame, function(eb, userChanged)
        if userChanged then
            listFrame.scrollFrame:Reset()
            local text = eb:GetText()
            -- 检查文本是否符合 Cell 指示器导出格式：!CELL:版本号:INDICATOR:数据长度!编码数据
            local version, count, data = string.match(text, "^!CELL:(%d+):INDICATOR:(%d+)!(.+)$")
            version = tonumber(version)
            count = tonumber(count)

            if version and count and data then
                if version >= Cell.MIN_INDICATORS_VERSION then
                    local success
                    -- 步骤1: Base64 解码（DecodeForPrint 对应 EncodeForPrint）
                    data = LibDeflate:DecodeForPrint(data) -- decode
                    -- 步骤2: Deflate 解压缩
                    success, data = pcall(LibDeflate.DecompressDeflate, LibDeflate, data) -- decompress
                    -- 步骤3: LibSerialize 反序列化为 Lua 表
                    success, data = Serializer:Deserialize(data) -- deserialize

                    if success and data then
                        -- 校验数据完整性：统计内置与自定义指示器数量，与头部声明的 count 对比
                        local builtIn, custom = 0, 0
                        for i, t in pairs(data["indicators"]) do
                            if t["type"] == "built-in" then
                                builtIn = builtIn + 1
                            else
                                custom = custom + 1
                            end
                        end

                        if builtIn + custom == count then
                            -- 解析成功：标题显示内置/自定义指示器数量
                            title:SetText(L["Import"].." > "..toLayoutName..": |cff90EE90"..builtIn.." "..L["built-in(s)"].."|r, |cffFFB5C5"..custom.." "..L["custom(s)"].."|r")
                            importBtn:SetEnabled(true)
                            imported = data

                            -- 在预览列表中逐项创建按钮，显示每个指示器的名称与类型图标
                            local last
                            for i, t in pairs(data["indicators"]) do
                                local b
                                if t["type"] == "built-in" then
                                    -- 内置指示器：灰色表示在当前版本中已失效的指示器
                                    local color = Cell.defaults.indicatorIndices[t.indicatorName] and "" or "|cff777777"
                                    b = Cell.CreateButton(listFrame.scrollFrame.content, color..L[t["name"]], "transparent-accent", {20, 20})
                                else
                                    -- 自定义指示器：显示类型图标
                                    b = Cell.CreateButton(listFrame.scrollFrame.content, t["name"], "transparent-accent", {20, 20})
                                    b.typeIcon = b:CreateTexture(nil, "ARTWORK")
                                    b.typeIcon:SetPoint("RIGHT", -2, 0)
                                    b.typeIcon:SetSize(16, 16)
                                    b.typeIcon:SetTexture("Interface\\AddOns\\Cell\\Media\\Indicators\\indicator-"..t["type"])
                                    b.typeIcon:SetAlpha(0.5)

                                    b:GetFontString():ClearAllPoints()
                                    b:GetFontString():SetPoint("LEFT", 5, 0)
                                    b:GetFontString():SetPoint("RIGHT", b.typeIcon, "LEFT", -2, 0)
                                end

                                -- 鼠标悬停提示：名称过长被截断时显示完整名称
                                b:HookScript("OnEnter", function()
                                    if b:GetFontString():IsTruncated() then
                                        CellTooltip:SetOwner(b, "ANCHOR_NONE")
                                        CellTooltip:SetPoint("RIGHT", b, "LEFT", -1, 0)
                                        CellTooltip:AddLine(b:GetText())
                                        CellTooltip:Show()
                                    end
                                end)

                                b:HookScript("OnLeave", function()
                                    CellTooltip:Hide()
                                end)

                                b:SetPoint("RIGHT")
                                if last then
                                    b:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 1)
                                else
                                    b:SetPoint("TOPLEFT")
                                end
                                last = b
                            end
                            -- 根据指示器数量调整滚动内容高度
                            listFrame.scrollFrame:SetContentHeight(20, count, -1)
                        else
                            Failed(L["Error"])
                        end
                    else
                        Failed(L["Error"])
                    end
                else -- 版本号不兼容
                    Failed(L["Incompatible Version"])
                end
            else
                Failed(L["Error"])
            end
        end
    end)
    Cell.StylizeFrame(textArea.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    textArea:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 5, 0)
    textArea:SetPoint("BOTTOMRIGHT", -5, 5)

    -------------------------------------------------
    -- 编辑框焦点事件：获得焦点时自动全选文本，方便用户快速粘贴替换
    -------------------------------------------------
    textArea.eb:SetScript("OnEditFocusGained", function() textArea.eb:HighlightText() end)
    textArea.eb:SetScript("OnMouseUp", function()
        if not isImport then
            textArea.eb:HighlightText()
        end
    end)

    -------------------------------------------------
    -- 面板隐藏/显示事件
    -------------------------------------------------
    importFrame:SetScript("OnHide", function()
        importFrame:Hide()
        -- 隐藏背景遮罩
        Cell.frames.indicatorsTab.mask:Hide()
        -- 清空编辑框和预览列表，重置导入按钮状态
        textArea:SetText("")
        listFrame.scrollFrame:Reset()
        importBtn:SetEnabled(false)
    end)

    importFrame:SetScript("OnShow", function()
        -- 提升面板层级确保不被遮挡
        importFrame:SetFrameLevel(Cell.frames.indicatorsTab:GetFrameLevel() + 50)
        -- 显示背景遮罩，阻止用户操作背后的标签页
        Cell.frames.indicatorsTab.mask:Show()
    end)
end

-------------------------------------------------
-- 公开接口
-------------------------------------------------
local init  -- 懒加载标记，确保面板只创建一次
-- 显示指示器导入面板
-- @param layout: 目标布局名（如 "default"、自定义布局名等）
function F.ShowIndicatorsImportFrame(layout)
    if not init then
        init = true
        CreateIndicatorsImportFrame()
    end

    importFrame:Show()
    toLayout = layout
    -- "default" 布局显示为系统语言的"默认"文本
    toLayoutName = toLayout == "default" and _G.DEFAULT or toLayout
    title:SetText(L["Import"].." > "..toLayoutName)
end