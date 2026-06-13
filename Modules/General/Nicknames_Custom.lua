-- 模块初始化：获取 Cell 核心引用、本地化字符串、工具函数及像素级 UI 函数
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 自定义昵称面板主框架
local customNicknamesFrame
-- 全局复用的 UI 控件：启用开关、列表容器、新增/编辑条目面板
local customCB, list, newItem
-- 列表刷新函数，在模块顶部声明以便内部引用
local LoadList
-- 已创建的列表行按钮缓存表，customs[0] 固定为“添加新条目”按钮
local customs = {}

-- 创建自定义昵称浮层面板，包含启用开关、条目列表（带滚动）和新增/编辑表单
local function CreateCustomNicknamesFrame()
    -- 以 GeneralTab 为父框架创建带背景的 Frame，使用 Cell 统一风格和强调色
    customNicknamesFrame = CreateFrame("Frame", "CellOptionsFrame_Nicknames", Cell.frames.generalTab, "BackdropTemplate")
    Cell.StylizeFrame(customNicknamesFrame, nil, Cell.GetAccentColorTable())
    -- 提高层级以确保浮层显示在其他控件之上
    customNicknamesFrame:SetFrameLevel(Cell.frames.generalTab:GetFrameLevel() + 50)
    customNicknamesFrame:Hide()

    -- 定位：从左下角的触发按钮右侧弹出，右下角留出边距
    customNicknamesFrame:SetPoint("LEFT", Cell.frames.generalTab.customNicknamesBtn, "RIGHT", 5, 0)
    customNicknamesFrame:SetPoint("BOTTOMRIGHT", -5, 5)
    customNicknamesFrame:SetHeight(425)

    -- 面板隐藏时的清理：隐藏自身、遮罩，恢复按钮层级，并关闭新增/编辑面板
    customNicknamesFrame:SetScript("OnHide", function()
        customNicknamesFrame:Hide()
        Cell.frames.generalTab.mask:Hide()
        Cell.frames.generalTab.customNicknamesBtn:SetFrameLevel(Cell.frames.generalTab:GetFrameLevel() + 2)
        newItem:Hide()
    end)

    -- 启用/禁用自定义昵称的复选框，切换时触发全局昵称更新事件并控制列表遮罩显隐
    customCB = Cell.CreateCheckButton(customNicknamesFrame, L["Custom Nicknames"], function(checked, self)
        CellDB["nicknames"]["custom"] = checked
        Cell.Fire("UpdateNicknames", "custom", checked)
        if checked then
            list.mask:Hide()
        else
            list.mask:Show()
        end
    end)
    customCB:SetPoint("TOPLEFT", 10, -10)

    -- 鼠标悬停提示：说明功能用途、仅自己可见、以及左键/Shift+左键的操作方式
    customCB:HookScript("OnEnter", function()
        CellTooltip:SetOwner(customCB, "ANCHOR_NONE")
        CellTooltip:SetPoint("BOTTOMLEFT", customCB, "TOPLEFT", 0, 1)
        CellTooltip:AddLine(L["Custom Nicknames"])
        CellTooltip:AddLine("|cffffffff"..L["Only visible to me"])
        CellTooltip:AddDoubleLine("|cffffb5c5"..L["Left-Click"]..":", "|cffffffff"..strlower(L["Edit"]))
        CellTooltip:AddDoubleLine("|cffffb5c5Shift+"..L["Left-Click"]..":", "|cffffffff"..strlower(L["Delete"]))
        CellTooltip:Show()
    end)

    customCB:HookScript("OnLeave", function()
        CellTooltip:Hide()
    end)

    -- 昵称条目列表容器，位于复选框下方，占满面板剩余空间
    list = Cell.CreateFrame(nil, customNicknamesFrame)
    list:SetPoint("TOPLEFT", customCB, "BOTTOMLEFT", 0, -10)
    list:SetPoint("BOTTOMRIGHT", -10, 10)
    list:Show()

    -- 列表遮罩层：当自定义昵称功能关闭时显示“禁用”提示
    Cell.CreateMask(list, L["Disabled"])
    list.mask:Hide()

    -- 新增/编辑条目子面板，覆盖在列表上用于输入玩家名和昵称
    newItem = Cell.CreateFrame(nil, list)
    -- 提升子面板层级使其盖住列表内容
    newItem:SetFrameLevel(list:GetFrameLevel() + 10)
    newItem:SetAllPoints(list)
    -- 当玩家切换目标时自动将目标名称填入玩家名输入框
    newItem:SetScript("OnEvent", function()
        local name = F.UnitFullName("target")
        if name then
            newItem.playerName:SetText(name)
        end
    end)
    -- 面板显示时注册目标变更事件，隐藏时注销以节省性能
    newItem:SetScript("OnShow", function()
        newItem:RegisterEvent("PLAYER_TARGET_CHANGED")
    end)
    newItem:SetScript("OnHide", function()
        newItem:UnregisterEvent("PLAYER_TARGET_CHANGED")
    end)

    -- 玩家名输入框，带有占位提示文本 "Name or Name-Server"
    newItem.playerName = Cell.CreateEditBox(newItem, 20, 20)
    newItem.playerName:SetPoint("LEFT", 5, 0)
    newItem.playerName:SetPoint("RIGHT", -5, 0)
    newItem.playerName:SetPoint("TOP", 0, -127)
    newItem.playerName.tip = newItem.playerName:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    newItem.playerName.tip:SetTextColor(0.4, 0.4, 0.4, 1)
    newItem.playerName.tip:SetPoint("LEFT", 5, 0)
    newItem.playerName.tip:SetText(L["Name or Name-Server"])
    -- 文本变化时实时校验：为空则显示提示并标记无效，非空则隐藏提示并更新存储文本
    newItem.playerName:SetScript("OnTextChanged", function(self, userChanged)
        local text = strtrim(newItem.playerName:GetText())

        if text == "" then
            newItem.playerName.tip:Show()
            newItem.playerName.isValid = false
            newItem.playerName.text = nil
        else
            newItem.playerName.tip:Hide()
            newItem.playerName.isValid = true
            newItem.playerName.text = text
        end

        -- 只有玩家名和昵称都有效时才启用添加/更新按钮
        newItem.add:SetEnabled(newItem.playerName.isValid and newItem.nickname.isValid)
    end)
    -- Tab 键跳转：从玩家名输入框按 Tab 切换到昵称输入框
    newItem.playerName:SetScript("OnTabPressed", function()
        newItem.nickname:SetFocus()
    end)

    -- 昵称输入框，带有占位提示文本 "Nickname"
    newItem.nickname = Cell.CreateEditBox(newItem, 20, 20)
    newItem.nickname:SetPoint("TOPLEFT", newItem.playerName, "BOTTOMLEFT", 0, -5)
    newItem.nickname:SetPoint("TOPRIGHT", newItem.playerName, "BOTTOMRIGHT", 0, -5)
    newItem.nickname.tip = newItem.nickname:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    newItem.nickname.tip:SetTextColor(0.4, 0.4, 0.4, 1)
    newItem.nickname.tip:SetPoint("LEFT", 5, 0)
    newItem.nickname.tip:SetText(L["Nickname"])
    -- 文本变化时实时校验：为空则显示提示并标记无效，非空则隐藏提示并更新存储文本
    newItem.nickname:SetScript("OnTextChanged", function(self, userChanged)
        local text = strtrim(newItem.nickname:GetText())

        if text == "" then
            newItem.nickname.tip:Show()
            newItem.nickname.isValid = false
            newItem.nickname.text = nil
        else
            newItem.nickname.tip:Hide()
            newItem.nickname.isValid = true
            newItem.nickname.text = text
        end

        -- 只有玩家名和昵称都有效时才启用添加/更新按钮
        newItem.add:SetEnabled(newItem.playerName.isValid and newItem.nickname.isValid)
    end)
    -- Tab 键跳转：从昵称输入框按 Tab 切换回玩家名输入框
    newItem.nickname:SetScript("OnTabPressed", function()
        newItem.playerName:SetFocus()
    end)

    -- “添加”按钮：根据是否是编辑模式决定更新已有条目或新增条目
    -- 数据格式为 "玩家名:昵称" 字符串，存储到 CellDB 并触发全局昵称更新事件
    newItem.add = Cell.CreateButton(newItem, L["Add"], "green", {120, 20})
    newItem.add:SetPoint("TOPLEFT", newItem.nickname, "BOTTOMLEFT", 0, -5)
    newItem.add:SetScript("OnClick", function()
        if newItem.updateIndex then
            -- 编辑模式：更新列表中对应索引位置的条目
            CellDB["nicknames"]["list"][newItem.updateIndex] = newItem.playerName.text..":"..newItem.nickname.text
            Cell.Fire("UpdateNicknames", "list-update", newItem.playerName.text, newItem.nickname.text)
        else
            -- 新增模式：向列表末尾追加新条目
            tinsert(CellDB["nicknames"]["list"], newItem.playerName.text..":"..newItem.nickname.text)
            Cell.Fire("UpdateNicknames", "list-add", newItem.playerName.text, newItem.nickname.text)
        end
        newItem:Hide()
        LoadList()
    end)

    -- “取消”按钮：关闭新增/编辑面板，不保存任何修改
    newItem.cancel = Cell.CreateButton(newItem, L["Cancel"], "red", {120, 20})
    newItem.cancel:SetPoint("TOPRIGHT", newItem.nickname, "BOTTOMRIGHT", 0, -5)
    newItem.cancel:SetScript("OnClick", function()
        newItem:Hide()
    end)

    -- 顶部提示文本：引导用户选择一个目标玩家来自动填充名称
    newItem.tip = newItem:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    newItem.tip:SetPoint("LEFT", 5, 0)
    newItem.tip:SetPoint("RIGHT", -5, 0)
    newItem.tip:SetPoint("BOTTOM", newItem.playerName, "TOP", 0, 10)
    newItem.tip:SetText(L["Target a player to autofill the name"])
    newItem.tip:SetTextColor(0.7, 0.7, 0.7, 1)

    -- 为列表创建滚动框架，每步滚动 19 像素
    Cell.CreateScrollFrame(list)
    list.scrollFrame:SetScrollStep(19)

    -- customs[0] 为列表最下方的“新建”图标按钮，点击后打开空白的新增面板
    customs[0] = Cell.CreateButton(list.scrollFrame.content, "", "accent-hover", {20, 20})
    customs[0]:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\new", {16, 16}, {"RIGHT", -1, 0})
    customs[0]:SetScript("OnClick", function()
        -- 清空输入框、显示占位提示、重置校验状态、按钮切换为“添加”模式
        newItem.playerName:SetText("")
        newItem.playerName.tip:Show()
        newItem.playerName.isValid = nil
        newItem.nickname:SetText("")
        newItem.nickname.tip:Show()
        newItem.nickname.isValid = nil
        newItem.add:SetEnabled(false)
        newItem.add:SetText(L["Add"])
        newItem.updateIndex = nil
        newItem:Show()
    end)
end

-------------------------------------------------
-- 函数：刷新自定义昵称列表 UI
-- 从 CellDB 中读取所有条目，为每个条目创建或复用一个行按钮，
-- 左键点击进入编辑模式，Shift+左键点击删除该条目。
-- 列表底部固定显示“新建”按钮（customs[0]）。
-------------------------------------------------
LoadList = function()
    -- 重置滚动框架，清空所有子控件引用
    list.scrollFrame:Reset()

    -- 将“新建”按钮重新挂到滚动内容区域并定位在列表最上方
    customs[0]:SetParent(list.scrollFrame.content)
    customs[0]:Show()
    customs[0]:SetPoint("BOTTOMLEFT")
    customs[0]:SetPoint("RIGHT")

    -- 遍历数据库中的所有自定义昵称条目
    for i, v in ipairs(CellDB["nicknames"]["list"]) do
        -- 按需创建行按钮（对象池复用，避免重复创建）
        if not customs[i] then
            customs[i] = Cell.CreateButton(list.scrollFrame.content, "", "accent-hover", {20, 20})

            -- 左侧玩家名字段
            customs[i].playerName = customs[i]:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
            customs[i].playerName:SetPoint("LEFT", 5, 0)
            customs[i].playerName:SetPoint("RIGHT", customs[i], "CENTER", -5, 0)
            customs[i].playerName:SetJustifyH("LEFT")
            customs[i].playerName:SetWordWrap(false)

            -- 中间分隔线：用 1px 宽的黑色纹理在视觉上分隔玩家名和昵称
            customs[i].separator1 = customs[i]:CreateTexture(nil, "ARTWORK")
            customs[i].separator1:SetPoint("TOP")
            customs[i].separator1:SetPoint("BOTTOM")
            customs[i].separator1:SetColorTexture(0, 0, 0, 1)
            P.Size(customs[i].separator1, 1, 1)

            -- 右侧昵称字段
            customs[i].nickname = customs[i]:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
            customs[i].nickname:SetPoint("LEFT", customs[i], "CENTER", 5, 0)
            customs[i].nickname:SetPoint("RIGHT", -5, 0)
            customs[i].nickname:SetJustifyH("LEFT")
            customs[i].nickname:SetWordWrap(false)

            -- 以下为被注释掉的删除和编辑独立按钮（功能已合并到行按钮的点击/Shift+点击中）
            -- separator2
            -- customs[i].separator2 = customs[i]:CreateTexture(nil, "ARTWORK")
            -- customs[i].separator2:SetPoint("RIGHT", -17, 0)
            -- customs[i].separator2:SetColorTexture(0, 0, 0, 1)
            -- P.Size(customs[i].separator2, 1, 20)

            -- del
            -- customs[i].del = Cell.CreateButton(customs[i], "", "none", {18, 20}, true, true)
            -- customs[i].del:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\delete", {16, 16}, {"CENTER", 0, 0})
            -- customs[i].del:SetPoint("RIGHT")
            -- customs[i].del.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
            -- customs[i].del:SetScript("OnEnter", function()
            --     customs[i]:GetScript("OnEnter")(customs[i])
            --     customs[i].del.tex:SetVertexColor(1, 1, 1, 1)
            -- end)
            -- customs[i].del:SetScript("OnLeave",  function()
            --     customs[i]:GetScript("OnLeave")(customs[i])
            --     customs[i].del.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
            -- end)

            -- edit
            -- customs[i].edit = Cell.CreateButton(customs[i], "", "none", {18, 20}, true, true)
            -- customs[i].edit:SetPoint("RIGHT", customs[i].del, "LEFT", 1, 0)
            -- customs[i].edit:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\info", {16, 16}, {"CENTER", 0, 0})
            -- customs[i].edit.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
            -- customs[i].edit:SetScript("OnEnter", function()
            --     customs[i]:GetScript("OnEnter")(customs[i])
            --     customs[i].edit.tex:SetVertexColor(1, 1, 1, 1)
            -- end)
            -- customs[i].edit:SetScript("OnLeave",  function()
            --     customs[i]:GetScript("OnLeave")(customs[i])
            --     customs[i].edit.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
            -- end)
        end

        -- 解析存储的 "玩家名:昵称" 字符串并更新行内显示文本
        local playerName, nickname = strsplit(":", v, 2)
        customs[i].playerName:SetText(playerName)
        customs[i].nickname:SetText(nickname)

        -- 行按钮点击行为：
        -- 普通左键点击 → 进入编辑模式，打开新增/编辑面板并预填当前数据
        -- Shift+左键点击 → 删除该条目，触发热更新并刷新列表
        customs[i]:SetScript("OnClick", function(self, button)
            if IsShiftKeyDown() then
                -- Shift+点击：从数据库删除条目并触发删除事件
                tremove(CellDB["nicknames"]["list"], i)
                Cell.Fire("UpdateNicknames", "list-delete", playerName)
                LoadList()
            else
                -- 普通点击：将当前条目的数据填入编辑面板，按钮文本切换为“更新”
                newItem.playerName:SetText(playerName)
                newItem.playerName.isValid = true
                newItem.nickname:SetText(nickname)
                newItem.nickname.isValid = true
                newItem.add:SetEnabled(true)
                newItem.add:SetText(_G.UPDATE)
                newItem.updateIndex = i
                newItem:Show()
            end
        end)

        -- 将行按钮挂到滚动内容区域并显示，按顺序从上到下排列
        customs[i]:SetParent(list.scrollFrame.content)
        customs[i]:Show()

        customs[i]:SetPoint("RIGHT")
        if i == 1 then
            -- 第一条紧贴滚动内容区域左上角
            customs[i]:SetPoint("TOPLEFT")
        else
            -- 后续条目依次排列在前一条下方，间隔 1 像素
            customs[i]:SetPoint("TOPLEFT", customs[i-1], "BOTTOMLEFT", 0, 1)
        end
    end

    -- 根据条目数量动态设置滚动内容高度，每行 20px，底部留空一行容纳“新建”按钮
    list.scrollFrame:SetContentHeight(20, #CellDB["nicknames"]["list"]+1, -1)
end

-- 从 CellDB 加载当前设置状态：同步复选框勾选、列表遮罩显隐，并刷新列表内容
local function LoadData()
    customCB:SetChecked(CellDB["nicknames"]["custom"])
    if CellDB["nicknames"]["custom"] then
        list.mask:Hide()
    else
        list.mask:Show()
    end
    LoadList()
end

-- 切换自定义昵称面板的显示/隐藏（由 GeneralTab 的触发按钮调用）
-- 首次调用时惰性创建面板，之后每次切换都重新加载最新数据
function F.ShowCustomNicknames()
    if not customNicknamesFrame then
        CreateCustomNicknamesFrame()
    end

    if customNicknamesFrame:IsShown() then
        -- 已显示则隐藏面板，恢复触发按钮的默认层级
        customNicknamesFrame:Hide()
        Cell.frames.generalTab.customNicknamesBtn:SetFrameLevel(Cell.frames.generalTab:GetFrameLevel() + 2)
    else
        -- 未显示则展示面板，提升按钮层级，显示遮罩，并加载数据
        customNicknamesFrame:Show()
        Cell.frames.generalTab.customNicknamesBtn:SetFrameLevel(Cell.frames.generalTab:GetFrameLevel() + 50)
        Cell.frames.generalTab.mask:Show()
        LoadData()
    end
end