local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 纹理选择器面板及其子控件的引用
local textureSelector, scrollFrame, confirmBtn, currentTexturePath
-- 重新加载纹理列表的函数（声明前置，实现在后面）
local LoadTextures
-- 纹理按钮对象池，避免每次刷新重复创建
local buttons = {}
-- 当前选中的纹理路径 和 纹理总数（用于布局计算）
local selectedPath, textureNum

-- 创建纹理选择器面板（懒加载，首次调用时创建）
local function CreateTextureSelector()
    -- 确保遮罩层存在，用于覆盖指示器标签页的背景
    if not Cell.frames.indicatorsTab.mask then
        Cell.CreateMask(Cell.frames.indicatorsTab, nil, {1, -1, -1, 1})
        Cell.frames.indicatorsTab.mask:Hide()
    end

    -- 创建纹理选择器主面板，置于指示器标签页上层
    textureSelector = CreateFrame("Frame", "CellOptionsFrame_TextureSelector", Cell.frames.indicatorsTab, "BackdropTemplate")
    Cell.StylizeFrame(textureSelector, nil, Cell.GetAccentColorTable())
    textureSelector:SetFrameLevel(Cell.frames.indicatorsTab:GetFrameLevel() + 50)
    textureSelector:SetPoint("TOPLEFT", P.Scale(1), -100)
    textureSelector:SetPoint("TOPRIGHT", P.Scale(-1), -100)
    textureSelector:SetHeight(235)

    -- 纹理路径输入框：用于添加自定义纹理，输入形如 "Interface\..." 的路径
    addEB = Cell.CreateEditBox(textureSelector, 355, 20)
    addEB:SetPoint("TOPLEFT", 5, -5)
    -- 提示文字：显示期望的输入格式
    addEB.tip = addEB:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    addEB.tip:SetTextColor(0.4, 0.4, 0.4, 1)
    addEB.tip:SetText("Interface\\... (tga|blp|png|jpg)")
    addEB.tip:SetPoint("LEFT", 5, 0)
    -- 获得焦点时全选文字并隐藏提示
    addEB:SetScript("OnEditFocusGained", function()
        addEB:HighlightText()
        addEB.tip:Hide()
    end)
    -- 失去焦点时取消选中；若输入为空则恢复提示
    addEB:SetScript("OnEditFocusLost", function()
        addEB:HighlightText(0, 0)
        if addEB:GetText() == "" then
            addEB.tip:Show()
        end
    end)

    -- 添加按钮：将输入框中的路径加入自定义纹理列表
    addBtn = Cell.CreateButton(textureSelector, L["Add"], "accent", {66, 20})
    addBtn:SetPoint("TOPLEFT", addEB, "TOPRIGHT", -1, 0)
    -- 点击添加按钮：去除首尾空格，检查路径非空且未重复，然后写入数据库并刷新列表
    addBtn:SetScript("OnClick", function()
        local path = strtrim(addEB:GetText())
        -- 检查路径非空且不存在于自定义纹理列表中
        if path ~= "" and not F.TContains(CellDB["customTextures"], path) then
            -- 写入 CellDB 持久化存储
            tinsert(CellDB["customTextures"], path)
            -- 重新加载纹理列表以显示新增项
            LoadTextures()
        end
    end)

    -- 取消按钮：关闭纹理选择器，不做任何更改
    local cancelBtn = Cell.CreateButton(textureSelector, L["Cancel"], "red", {70, 20})
    cancelBtn:SetPoint("BOTTOMRIGHT")
    cancelBtn:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))
    cancelBtn:SetScript("OnClick", function()
        textureSelector:Hide()
    end)

    -- 确认按钮：关闭选择器并回调传入的 callback，将当前选中的路径传出
    confirmBtn = Cell.CreateButton(textureSelector, L["Confirm"], "green", {70, 20})
    confirmBtn:SetPoint("BOTTOMRIGHT", cancelBtn, "BOTTOMLEFT", P.Scale(1), 0)
    confirmBtn:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))

    -- 纹理列表容器：容纳所有纹理缩略图按钮的滚动区域
    local texFrame = Cell.CreateFrame(nil, textureSelector)
    texFrame:Show()
    texFrame:SetPoint("TOPLEFT", addEB, "BOTTOMLEFT", 0, -10)
    texFrame:SetPoint("BOTTOMRIGHT", -5, 30)
    scrollFrame = Cell.CreateScrollFrame(texFrame, -5, 5)
    scrollFrame:SetScrollStep(55)

    -- 底部当前路径显示：鼠标悬停按钮时显示对应纹理的完整路径
    currentTexturePath = textureSelector:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    currentTexturePath:SetPoint("BOTTOMLEFT", 5, 5)
    currentTexturePath:SetPoint("RIGHT", confirmBtn, "LEFT", -5, 0)
    currentTexturePath:SetJustifyH("LEFT")
    currentTexturePath:SetWordWrap(false)

    -- 面板隐藏时的清理：隐藏遮罩、恢复输入框提示文字、清空输入框内容
    textureSelector:SetScript("OnHide", function()
        Cell.frames.indicatorsTab.mask:Hide()
        textureSelector:Hide()
        addEB.tip:Show()
        addEB:SetText("")
    end)
end

-------------------------------------------------
-- 加载纹理列表：从 CellDB 和内置纹理中收集所有可用纹理，创建或复用按钮对象，按每行7个布局
-------------------------------------------------
LoadTextures = function()
    -- 重置滚动条位置到顶部
    scrollFrame:Reset()

    -- 获取内置纹理列表和合并后的全部纹理列表（内置 + 自定义）
    local builtIns, textures = F.GetTextures()
    textureNum = #textures

    -- 遍历所有纹理，创建或复用按钮对象（对象池模式）
    for i, path in pairs(textures) do
        local b = buttons[i]
        if not b then
            -- 首次创建按钮：50x50 大小，深灰背景，黑色边框
            b = CreateFrame("Button", nil, scrollFrame.content, "BackdropTemplate")
            buttons[i] = b
            P.Size(b, 50, 50)
            b:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
            b:SetBackdropColor(0.115, 0.115, 0.115, 1)
            b:SetBackdropBorderColor(0, 0, 0, 1)
            -- 鼠标移入：高亮边框并显示纹理路径
            b:SetScript("OnEnter", function()
                b:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))
                b.delBtn:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))

                F.FitWidth(currentTexturePath, b.path, "right")
            end)
            -- 鼠标移出：清除路径显示，非选中按钮恢复默认边框
            b:SetScript("OnLeave", function()
                currentTexturePath:SetText("")
                if selectedPath ~= b.path then
                    b:SetBackdropBorderColor(0, 0, 0, 1)
                    b.delBtn:SetBackdropBorderColor(0, 0, 0, 1)
                end
            end)

            -- 纹理缩略图：在按钮内居中显示
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetPoint("TOPLEFT", 5, -5)
            b.tex:SetPoint("BOTTOMRIGHT", -5, 5)

            -- 删除按钮：仅对自定义纹理显示，点击后从数据库移除并刷新列表
            b.delBtn = Cell.CreateButton(b, "×", "red", {13, 13})
            b.delBtn:GetFontString():SetFont("Interface\\AddOns\\Cell\\Media\\Fonts\\font.ttf", 10, "")
            b.delBtn:SetPoint("TOPRIGHT")
            -- 删除按钮的悬停事件委托给父按钮，保持边框高亮行为一致
            b.delBtn:HookScript("OnEnter", function()
                b:GetScript("OnEnter")(b)
            end)
            b.delBtn:HookScript("OnLeave", function()
                b:GetScript("OnLeave")(b)
            end)
            b.delBtn:SetScript("OnClick", function()
                -- 从 CellDB 持久化存储中移除
                F.TRemove(CellDB["customTextures"], b.path)
                -- 重新加载纹理列表
                LoadTextures()
            end)
        end

        -- 将路径绑定到按钮上，供悬停显示和删除操作使用
        b.path = path

        -- 锚点布局：每行7个（top-left锚定到上一行第一个按钮的左下角）
        b:ClearAllPoints()
        b:SetParent(scrollFrame.content)
        b:Show()
        if i == 1 then
            b:SetPoint("TOPLEFT", 5, 0)
        elseif i % 7 == 1 then
            b:SetPoint("TOPLEFT", buttons[i-7], "BOTTOMLEFT", 0, -5)
        else
            b:SetPoint("TOPLEFT", buttons[i-1], "TOPRIGHT", 5, 0)
        end

        -- 设置纹理：Interface 开头的路径用 SetTexture，否则用 SetAtlas（支持图集纹理）
        if strfind(strlower(path), "^interface") then
            b.tex:SetTexture(path)
        else
            b.tex:SetAtlas(path)
        end

        -- 点击按钮：选中该纹理，取消其他按钮的高亮
        b:SetScript("OnClick", function(self, button)
            selectedPath = path
            for j, bb in pairs(buttons) do
                if i ~= j then
                    bb:SetBackdropBorderColor(0, 0, 0, 1)
                end
            end
        end)

        -- 仅自定义纹理（索引超过内置数量的）显示删除按钮
        if i > builtIns then
            b.delBtn:Show()
        else
            b.delBtn:Hide()
        end

        -- 高亮当前已选中的纹理
        if selectedPath == path then
            b:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))
        else
            b:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end

    -- 隐藏多余的按钮（对象池中超出当前纹理数量的按钮从父框架移除并隐藏）
    for i = textureNum+1, #buttons do
        buttons[i]:SetParent(nil)
        buttons[i]:ClearAllPoints()
        buttons[i]:Hide()
    end

    -- 根据纹理数量调整滚动区域内容高度，确保滚动条正确
    scrollFrame:SetContentHeight(50, math.ceil(textureNum/7), 5)
end

-------------------------------------------------
-- 公开函数：Cell.funcs.ShowTextureSelector
-------------------------------------------------
function F.ShowTextureSelector(selected, callback)
    -- 懒加载：首次调用时创建纹理选择器面板
    if not textureSelector then
        CreateTextureSelector()
    end

    -- 显示遮罩层和纹理选择器面板
    Cell.frames.indicatorsTab.mask:Show()
    textureSelector:Show()

    -- 设置默认选中项并加载纹理列表
    selectedPath = selected
    LoadTextures()
    -- 确认按钮的点击回调：关闭面板，调用传入的 callback 并传递选中的路径
    confirmBtn:SetScript("OnClick", function()
        textureSelector:Hide()
        if callback then callback(selectedPath) end
    end)
end