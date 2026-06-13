-- Nicknames_Blacklist.lua
-- 黑名单管理模块：提供玩家昵称黑名单的 UI 面板，支持添加/删除目标玩家的黑名单条目，
-- 并与 Cell 的昵称系统联动，触发 UpdateNicknames 事件通知其他模块刷新显示。
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-- 黑名单面板主框架（懒加载，首次打开时创建）
local nicknameBlacklistFrame
-- 黑名单列表的滚动容器
local list
-- 列表刷新函数（声明在前，因与 CreateNicknameBlacklistFrame 互相引用）
local LoadList
-- 黑名单条目按钮缓存表，按索引复用已有的 UI 控件
local customs = {}

-- 创建黑名单管理面板（懒加载，仅在首次调用 ShowNicknameBlacklist 时执行）
-- 面板位于 generalTab 的 customNicknamesBtn 右侧，包含"拉黑目标"按钮和可滚动列表
local function CreateNicknameBlacklistFrame()
    nicknameBlacklistFrame = CreateFrame("Frame", "CellOptionsFrame_Nicknames", Cell.frames.generalTab, "BackdropTemplate")
    Cell.StylizeFrame(nicknameBlacklistFrame, nil, Cell.GetAccentColorTable())
    -- 面板层级高于 generalTab，确保浮层不被遮挡
    nicknameBlacklistFrame:SetFrameLevel(Cell.frames.generalTab:GetFrameLevel() + 50)
    nicknameBlacklistFrame:Hide()

    nicknameBlacklistFrame:SetPoint("LEFT", Cell.frames.generalTab.customNicknamesBtn, "RIGHT", 5, 0)
    nicknameBlacklistFrame:SetPoint("BOTTOMRIGHT", -5, 5)
    nicknameBlacklistFrame:SetHeight(412)

    -- OnHide 事件：面板关闭时同时隐藏遮罩层，并将触发按钮的层级恢复为正常
    nicknameBlacklistFrame:SetScript("OnHide", function()
        nicknameBlacklistFrame:Hide()
        Cell.frames.generalTab.mask:Hide()
        Cell.frames.generalTab.customNicknamesBtn:SetFrameLevel(Cell.frames.generalTab:GetFrameLevel() + 2)
    end)

    -- "拉黑目标玩家"按钮：将当前目标的全名加入黑名单
    local button = Cell.CreateButton(nicknameBlacklistFrame, L["Blacklist Target Player"], "red", {20, 20})
    button:SetPoint("TOPLEFT", 10, -10)
    button:SetPoint("TOPRIGHT", -10, -10)
    -- OnClick 事件：获取目标玩家全名，若未在黑名单中则添加，触发 UpdateNicknames 事件并刷新列表
    button:SetScript("OnClick", function()
        local name = F.UnitFullName("target")
        if name and not F.TContains(CellDB["nicknames"]["blacklist"], name) then
            tinsert(CellDB["nicknames"]["blacklist"], name)
            Cell.Fire("UpdateNicknames", "blacklist-add", name)
            LoadList()
        end
    end)

    -- 黑名单列表容器：位于"拉黑"按钮下方，占据面板剩余区域
    list = Cell.CreateFrame(nil, nicknameBlacklistFrame)
    list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -10)
    list:SetPoint("BOTTOMRIGHT", -10, 10)
    list:Show()

    -- 为列表容器添加垂直滚动支持，每步滚动 19 像素（与条目行高匹配）
    Cell.CreateScrollFrame(list)
    list.scrollFrame:SetScrollStep(19)
end

-------------------------------------------------
-- 列表刷新函数：根据 CellDB["nicknames"]["blacklist"] 数据重建滚动列表
-- 采用控件复用策略：首次创建条目按钮并缓存到 customs 表，后续刷新只更新文本和点击事件
-------------------------------------------------
LoadList = function()
    -- 重置滚动条状态，清空所有子控件锚点
    list.scrollFrame:Reset()

    for i, name in ipairs(CellDB["nicknames"]["blacklist"]) do
        -- 条目控件复用：若 customs[i] 尚不存在则新建，否则仅更新文本
        if not customs[i] then
            customs[i] = Cell.CreateButton(list.scrollFrame.content, "", "accent-hover", {20, 20})

            -- 删除按钮：位于每条黑名单条目右侧，点击后从列表中移除该玩家
            customs[i].del = Cell.CreateButton(customs[i], "", "none", {18, 20}, true, true)
            customs[i].del:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\delete", {16, 16}, {"CENTER", 0, 0})
            customs[i].del:SetPoint("RIGHT")
            customs[i].del.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
            -- OnEnter 事件：鼠标进入删除按钮时高亮为白色，同时触发父按钮的 OnEnter（背景色变化）
            customs[i].del:SetScript("OnEnter", function()
                customs[i]:GetScript("OnEnter")(customs[i])
                customs[i].del.tex:SetVertexColor(1, 1, 1, 1)
            end)
            -- OnLeave 事件：鼠标离开删除按钮时恢复灰色，同时触发父按钮的 OnLeave（背景色恢复）
            customs[i].del:SetScript("OnLeave",  function()
                customs[i]:GetScript("OnLeave")(customs[i])
                customs[i].del.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
            end)

            -- 玩家名文本：显示在黑名单条目左侧，右边缘与删除按钮之间留 5px 间距
            customs[i].playerName = customs[i]:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
            customs[i].playerName:SetPoint("LEFT", 5, 0)
            customs[i].playerName:SetPoint("RIGHT", customs[i].del, "LEFT", -5, 0)
            customs[i].playerName:SetJustifyH("LEFT")
            customs[i].playerName:SetWordWrap(false)
        end

        customs[i].playerName:SetText(name)

        -- 删除按钮 OnClick 事件：从数据库移除该索引的条目，触发 UpdateNicknames 事件并刷新列表
        customs[i].del:SetScript("OnClick", function()
            tremove(CellDB["nicknames"]["blacklist"], i)
            Cell.Fire("UpdateNicknames", "blacklist-delete", name)
            LoadList()
        end)

        -- 将条目按钮重新挂载到滚动内容区域（Reset 后需重建父子关系）
        customs[i]:SetParent(list.scrollFrame.content)
        customs[i]:Show()

        -- 条目按钮水平撑满，垂直方向依次排列（间隔 1px）
        customs[i]:SetPoint("RIGHT")
        if i == 1 then
            customs[i]:SetPoint("TOPLEFT")
        else
            customs[i]:SetPoint("TOPLEFT", customs[i-1], "BOTTOMLEFT", 0, 1)
        end
    end

    -- 根据黑名单条目数量更新滚动内容高度，行高 20px，行间距 -1px
    list.scrollFrame:SetContentHeight(20, #CellDB["nicknames"]["blacklist"], -1)
end

-- 切换黑名单面板的显示/隐藏状态
-- 首次调用时懒加载创建面板框架；已显示则关闭，未显示则打开并刷新列表
function F.ShowNicknameBlacklist()
    if not nicknameBlacklistFrame then
        CreateNicknameBlacklistFrame()
    end

    if nicknameBlacklistFrame:IsShown() then
        -- 关闭面板：隐藏面板和遮罩，恢复触发按钮的正常层级
        nicknameBlacklistFrame:Hide()
        Cell.frames.generalTab.nicknameBlacklistBtn:SetFrameLevel(Cell.frames.generalTab:GetFrameLevel() + 2)
    else
        -- 打开面板：显示面板和遮罩，提升触发按钮层级防止被面板遮挡，并立即刷新列表
        nicknameBlacklistFrame:Show()
        Cell.frames.generalTab.nicknameBlacklistBtn:SetFrameLevel(Cell.frames.generalTab:GetFrameLevel() + 50)
        Cell.frames.generalTab.mask:Show()
        LoadList()
    end
end