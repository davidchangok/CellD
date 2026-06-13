-- ============================================================================
-- 指示器复制面板 (Indicators Copy Frame)
-- 用于将一个布局中的指示器配置（位置、样式、参数等）批量复制到另一个布局
-- 支持主从布局关系的智能过滤，防止因同步导致的配置覆盖
-- ============================================================================
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 前向声明：Toggle 和 Validate 因循环引用需要提前声明
local Toggle, Validate
-- from: 源布局名称, to: 目标布局名称
local from, to
-- 指示器按钮缓存表，按索引存储已创建的按钮 frame，避免重复创建
local indicatorButtons = {}
-- 当前用户选中的指示器索引集合，key 为指示器索引，value 为 true
local selectedIndicators = {}

-- UI 元素引用：复制面板框架、源/目标下拉框、指示器列表、操作按钮
local copyFrame, fromDropdown, toDropdown, fromList, copyBtn, closeBtn, allBtn, invertBtn

-- 已废弃：曾用于获取自定义指示器名称映射，现已被直接遍历逻辑替代
-- local function GetCustomIndicatorNames(indicators)
--     local names = {}
--     for i = Cell.defaults.builtIns+1, #indicators do
--         local iTbl = indicators[i]
--         names[iTbl["name"]] = {i, iTbl["indicatorName"]}
--     end
--     return names
-- end

-- ============================================================================
-- CreateIndicatorsCopyFrame()
-- 创建指示器复制面板的完整 UI（惰性初始化，仅首次调用时执行）
-- 面板包含：源布局下拉(fromDropdown)、目标布局下拉(toDropdown)、
-- 指示器选择列表(fromList)以及复制/关闭/全选/反选四个操作按钮
-- ============================================================================
local function CreateIndicatorsCopyFrame()
    -- 确保指示器标签页存在遮罩层（用于面板弹出时拦截底层鼠标事件）
    if not Cell.frames.indicatorsTab.mask then
        Cell.CreateMask(Cell.frames.indicatorsTab, nil, {1, -1, -1, 1})
        Cell.frames.indicatorsTab.mask:Hide()
    end

    -- 创建复制面板主框架：宽度136，高度520，位于指示器标签页内
    copyFrame = Cell.CreateFrame("CellOptionsFrame_IndicatorsCopy", Cell.frames.indicatorsTab, 136, 520)
    -- Cell.frames.indicatorsCopyFrame = copyFrame
    -- 应用统一边框样式（使用当前强调色），提升层级以确保浮于标签页内容之上
    Cell.StylizeFrame(copyFrame, nil, Cell.GetAccentColorTable())
    copyFrame:SetFrameLevel(Cell.frames.indicatorsTab:GetFrameLevel() + 50)
    copyFrame:SetPoint("BOTTOMLEFT", 5, 24)
    copyFrame:Hide()

    -- ===== 源布局与目标布局下拉框 =====
    -- fromDropdown: 选择要从哪个布局复制指示器配置
    -- toDropdown:   选择要将指示器配置复制到哪个布局
    -- 源布局下拉框
    fromDropdown = Cell.CreateDropdown(copyFrame, 126)
    fromDropdown:SetPoint("TOPLEFT", 5, -24)

    -- 目标布局下拉框
    toDropdown = Cell.CreateDropdown(copyFrame, 126)
    toDropdown:SetPoint("TOPLEFT", fromDropdown, "BOTTOMLEFT", 0, -22)

    -- "从" 标签
    local fromText = copyFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    fromText:SetPoint("BOTTOMLEFT", fromDropdown, "TOPLEFT", 0, 1)
    fromText:SetText(L["From"])

    -- "到" 标签
    local toText = copyFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    toText:SetPoint("BOTTOMLEFT", toDropdown, "TOPLEFT", 0, 1)
    toText:SetText(L["To"])

    -- ===== 指示器选择列表 =====
    -- 展示源布局的所有指示器，供用户勾选需要复制的项
    fromList = CreateFrame("Frame", nil, copyFrame, "BackdropTemplate")
    Cell.StylizeFrame(fromList)
    fromList:SetPoint("TOPLEFT", toDropdown, "BOTTOMLEFT", 0, -5)
    fromList:SetPoint("TOPRIGHT", toDropdown, "BOTTOMRIGHT", 0, -5)
    -- fromList:SetPoint("BOTTOM", 0, 34)
    fromList:SetHeight(381)

    -- 创建滚动框架，滚动步长19像素
    Cell.CreateScrollFrame(fromList)
    fromList.scrollFrame:SetScrollStep(19)

    -- ===== 操作按钮 =====

    -- 复制按钮：将选中的指示器配置从源布局复制到目标布局
    -- 内置指示器按索引直接覆盖，自定义指示器追加到目标布局末尾并自动命名
    copyBtn = Cell.CreateButton(copyFrame, L["Copy"], "green", {64, 20})
    copyBtn:SetPoint("BOTTOMLEFT", 5, 5)
    copyBtn:SetEnabled(false) -- 初始禁用，需选择源/目标布局并勾选指示器后才启用
    copyBtn:SetScript("OnClick", function()
        -- 获取目标布局最后一个指示器的编号，用于自定义指示器的自动命名
        local last = #CellDB["layouts"][to]["indicators"]
        last = tonumber(string.match(CellDB["layouts"][to]["indicators"][last]["indicatorName"], "%d+")) or last

        for i in pairs(selectedIndicators) do
            if i <= Cell.defaults.builtIns then -- 内置指示器：直接覆盖（按索引位置复制）
                CellDB["layouts"][to]["indicators"][i] = F.Copy(CellDB["layouts"][from]["indicators"][i])
            else -- 用户自定义指示器：追加到末尾，自动分配新名称
                last = last + 1
                local indicator = F.Copy(CellDB["layouts"][from]["indicators"][i])
                indicator["indicatorName"] = "indicator"..last
                tinsert(CellDB["layouts"][to]["indicators"], indicator)
            end
        end
        -- 触发更新事件，刷新指示器显示和相关 UI
        Cell.Fire("UpdateIndicators", to)
        Cell.Fire("IndicatorsChanged", to)
        copyFrame:Hide()
    end)

    -- 关闭按钮：隐藏复制面板
    closeBtn = Cell.CreateButton(copyFrame, L["Close"], "red", {63, 20})
    closeBtn:SetPoint("BOTTOMLEFT", copyBtn, "BOTTOMRIGHT", P.Scale(-1), 0)
    closeBtn:SetScript("OnClick", function()
        copyFrame:Hide()
    end)

    -- 全选按钮：选中所有指示器
    allBtn = Cell.CreateButton(copyFrame, L["ALL"], "accent-hover", {64, 20})
    allBtn:SetPoint("BOTTOMLEFT", copyBtn, "TOPLEFT", 0, P.Scale(-1))
    allBtn:SetScript("OnClick", function()
        for i = 1, #indicatorButtons do
            Toggle(i, true)
        end
        Validate()
    end)

    -- 反选按钮：将已选中的取消选中，未选中的选中
    invertBtn = Cell.CreateButton(copyFrame, L["INVERT"], "accent-hover", {63, 20})
    invertBtn:SetPoint("BOTTOMLEFT", closeBtn, "TOPLEFT", 0, P.Scale(-1))
    invertBtn:SetScript("OnClick", function()
        for i = 1, #indicatorButtons do
            if selectedIndicators[i] then
                Toggle(i, false, true) -- unhighlight 参数为 true，取消高亮背景
            else
                Toggle(i, true)
            end
        end
        Validate()
    end)

    -- ===== 面板显示/隐藏事件 =====

    -- OnShow: 面板显示时，显示遮罩层以遮挡底层鼠标事件
    copyFrame:SetScript("OnShow", function()
        Cell.frames.indicatorsTab.mask:Show()
    end)

    -- OnHide: 面板隐藏时清理所有状态
    -- 重置遮罩、滚动列表、下拉框选中的项、按钮状态、选中集合和布局变量
    copyFrame:SetScript("OnHide", function()
        copyFrame:Hide()
        Cell.frames.indicatorsTab.mask:Hide() -- 隐藏遮罩
        fromList.scrollFrame:Reset()         -- 重置滚动位置
        fromDropdown:SetSelected()           -- 清空下拉框选中项
        toDropdown:SetSelected()
        copyBtn:SetEnabled(false)            -- 禁用复制按钮
        wipe(selectedIndicators)             -- 清空选中集合
        from, to = nil, nil                  -- 清空布局变量
    end)
end

-------------------------------------------------
-- 核心逻辑函数
-------------------------------------------------

-- Validate() — 校验复制操作是否满足条件，控制复制按钮的启用/禁用
-- 条件1: 必须选择了源布局 (from)
-- 条件2: 必须选择了目标布局 (to)
-- 条件3: 至少选择一个指示器
Validate = function()
    from, to = fromDropdown:GetSelected(), toDropdown:GetSelected()
    if from and to and F.Getn(selectedIndicators) ~= 0 then
        copyBtn:SetEnabled(true)
    else
        copyBtn:SetEnabled(false)
    end
end

-- Toggle(index, isSelect, unhighlight) — 切换指定指示器的选中/取消选中状态
-- index:      指示器在 indicatorButtons 表中的索引
-- isSelect:   true=选中, false/nil=取消选中
-- unhighlight: 可选，取消选中时是否也清除按钮背景高亮（用于反选操作时重置视觉状态）
Toggle = function(index, isSelect, unhighlight)
    b = indicatorButtons[index]
    if isSelect then
        -- 选中状态：记录到集合，按钮变绿，移除鼠标悬停效果
        selectedIndicators[index] = true
        b:SetBackdropColor(unpack(b.hoverColor))
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
        b:SetTextColor(0, 1, 0)
        b.selected = true
    else
        -- 取消选中：从集合中移除，按钮恢复白色，重新启用鼠标悬停效果
        selectedIndicators[index] = nil
        b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(self.hoverColor)) end)
        b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(self.color)) end)
        b:SetTextColor(1, 1, 1)
        b.selected = false
        if unhighlight then
            b:SetBackdropColor(0, 0, 0, 0) -- 清除背景色（透明）
        end
    end
end

-- LoadIndicators(layout) — 加载指定布局的所有指示器按钮到选择列表
-- layout: 布局名称（如 "default" 或用户自定义布局名）
-- 按钮被复用以避免重复创建 frame；内置指示器显示本地化名称，自定义指示器显示原名+类型图标
local function LoadIndicators(layout)
    wipe(selectedIndicators)          -- 清空之前的选中状态
    fromList.scrollFrame:Reset()      -- 重置滚动框架

    local last, n
    for i, t in pairs(CellDB["layouts"][layout]["indicators"]) do
        local b = indicatorButtons[i]
        if not b then
            -- 首次创建按钮：透明背景+强调色悬停效果，20x20 像素
            b = Cell.CreateButton(fromList.scrollFrame.content, " ", "transparent-accent", {20, 20})
            indicatorButtons[i] = b
            b.selected = false
            -- 点击切换选中状态并校验
            b:SetScript("OnClick", function()
                b.selected = not b.selected
                Toggle(i, b.selected)
                Validate()
            end)
        else
            -- 按钮已存在：重置其状态和外观（重新挂载到当前滚动内容区）
            -- reset
            b:Show()
            b:SetParent(fromList.scrollFrame.content)
            b.selected = false
            b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(self.hoverColor)) end)
            b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(self.color)) end)
            b:SetTextColor(1, 1, 1)
            b:SetBackdropColor(0, 0, 0, 0)
        end

        -- 设置按钮文本和图标
        if t["type"] == "built-in" then
            b:SetText(L[t["name"]]) -- 内置指示器使用本地化名称
        else
            b:SetText(t["name"])    -- 自定义指示器使用原始名称
            -- 为自定义指示器创建类型图标（仅在首次需要时创建）
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

        -- 垂直排列按钮：首个按钮锚定到列表左上角，后续按钮依次向下排列
        b:SetPoint("RIGHT")
        if last then
            b:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 1)
        else
            b:SetPoint("TOPLEFT")
        end
        last = b
        n = i
    end

    -- 设置滚动内容总高度：每个按钮20像素高，按钮间-1像素间距
    fromList.scrollFrame:SetContentHeight(20, n, -1)
end

-- LoadToDropdown(from) — 根据选中的源布局加载目标布局下拉框选项
-- 核心规则：如果源布局处于主从同步关系中，自动排除与其存在同步关系的布局，
-- 防止将配置复制到会发生同步覆盖的布局中。
-- 主从关系说明：
--   - "主"布局 (master): 其他布局通过 syncWith 字段引用它，主布局的配置同步给从布局
--   - "从"布局 (slave): 其 syncWith 字段指向某个主布局，自身配置会被主布局覆盖
local function LoadToDropdown(from)
    local masters, slaves = {}, {}

    -- 分析所有布局的主从关系：建立 masters（主->从集合）和 slaves（从->主映射）
    for l, t in pairs(CellDB["layouts"]) do
        local master = t["syncWith"]
        if master then
            if CellDB["layouts"][master] then -- 主布局必须实际存在
                if not masters[master] then masters[master] = {} end
                masters[master][l] = true
                slaves[l] = master
            end
        end
    end

    local indices = {}

    if slaves[from] then -- 情况1: FROM 是从布局 → 排除其主布局及主布局的其他从布局（兄弟布局）
        local master = slaves[from]
        for l, t in pairs(CellDB["layouts"]) do
            -- 排除 FROM 自身、主布局、以及主布局的其他从布局
            if l ~= from and l ~= master and not masters[master][l] then
                if l == "default" then
                    tinsert(indices, 1, "default") -- default 始终置顶
                else
                    tinsert(indices, l)
                end
            end
        end
    elseif masters[from] then -- 情况2: FROM 是主布局 → 排除其所有从布局（防止同步覆盖）
        for l, t in pairs(CellDB["layouts"]) do
            -- 排除 FROM 自身及其从布局
            if l ~= from and not masters[from][l] then
                if l == "default" then
                    tinsert(indices, 1, "default")
                else
                    tinsert(indices, l)
                end
            end
        end
    else -- 情况3: FROM 不在任何主从关系中 → 排除自身即可
        for l, t in pairs(CellDB["layouts"]) do
            if l ~= from then
                if l == "default" then
                    tinsert(indices, 1, "default")
                else
                    tinsert(indices, l)
                end
            end
        end
    end

    -- 构建下拉框选项列表
    local toItems = {}

    for _, l in ipairs(indices) do
        tinsert(toItems, {
            ["text"] = l == "default" and _G.DEFAULT or l, -- default 布局显示为系统默认名称
            ["value"] = l,
            ["onClick"] = function()
                Validate() -- 选择目标布局后重新校验按钮状态
            end,
        })
    end

    toDropdown:SetItems(toItems)
end

-- LoadFromDropdown() — 加载源布局下拉框选项
-- 选项列表包含所有布局：default 布局置顶，其余按遍历顺序排列
-- 选择某个布局后会联动：加载对应指示器列表 + 更新目标布局下拉框
local function LoadFromDropdown()
    local fromItems = {}

    -- default 布局始终排在第一位
    tinsert(fromItems, {
        ["text"] = _G.DEFAULT,
        ["value"] = "default",
        ["onClick"] = function()
            LoadIndicators("default")   -- 加载 default 布局的指示器列表
            Validate()
            toDropdown:ClearItems()     -- 清空并重新加载目标布局下拉框
            LoadToDropdown("default")
        end,
    })

    -- 遍历所有自定义布局（跳过 default）
    for l, t in pairs(CellDB["layouts"]) do
        if l ~= "default" then
            tinsert(fromItems, {
                ["text"] = l,
                ["onClick"] = function()
                    LoadIndicators(l)
                    Validate()
                    toDropdown:ClearItems()
                    LoadToDropdown(l)
                end,
            })
        end
    end

    fromDropdown:SetItems(fromItems)
end

-------------------------------------------------
-- 公开入口
-------------------------------------------------

-- 惰性初始化标记：确保 UI 仅在首次调用时创建
local init

-- F.ShowIndicatorsCopyFrame() — 公开入口函数，由外部代码调用来显示指示器复制面板
-- 首次调用时创建整个 UI（惰性初始化），后续调用仅刷新下拉框数据并显示面板
function F.ShowIndicatorsCopyFrame()
    if not init then
        init = true
        CreateIndicatorsCopyFrame() -- 首次调用：创建面板（含下拉框、列表、按钮等全部 UI）
    end

    -- 每次显示时刷新数据（布局列表可能已变更）
    LoadFromDropdown()    -- 重新加载源布局下拉框
    toDropdown:ClearItems() -- 清空目标布局下拉框（待用户选择源布局后再填充）
    copyFrame:Show()
end