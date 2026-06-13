local _, Cell = ...
-- 模块别名：L=本地化，F=通用函数，B=按钮逻辑函数，A=动画，P=像素级精确控制
local L = Cell.L
local F = Cell.funcs
local B = Cell.bFuncs
local A = Cell.animations
local P = Cell.pixelPerfectFuncs

-- NPCFrame 主框架：使用 SecureHandlerStateTemplate 实现安全的按组/宠物状态锚点切换
local npcFrame = CreateFrame("Frame", "CellNPCFrame", Cell.frames.mainFrame, "SecureHandlerStateTemplate")
Cell.frames.npcFrame = npcFrame
-- 调试用：将 NPCFrame 染成红色边框以可视化布局
-- Cell.StylizeFrame(npcFrame, {1, 0.5, 0.5})

-- 锚点映射表：不同队伍类型下 NPCFrame 的对齐参考框架
-- solo → 单人时玩家框架，party → 小队宠物按钮，raid → 团队NPC锚点
local anchors = {
    ["solo"] = CellSoloFramePlayer,
    ["party"] = CellPartyFrameHeaderUnitButton1Pet,
    ["raid"] = CellNPCFrameAnchor,
}

-- 把锚点框架注入到 secure 环境中，使 secure handler 片段可通过 GetFrameRef 引用它们
for k, v in pairs(anchors) do
    npcFrame:SetFrameRef(k, v)
end

-------------------------------------------------
-- separateAnchor
-- 独立锚点：当 NPCFrame 设置为"与主框架分离"模式时，可拖拽的锚点按钮
-- 用于用户自由拖动 NPC 单位框体的位置，不受主框架排列约束
-------------------------------------------------
-- 提示框（tooltip）相对锚点的位置参数，由 UpdatePosition() 按布局方向动态计算
local tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY

-- 独立锚点框架：支持 BackdropTemplate 以绘制背景，可拖动并约束在屏幕内
local separateAnchor = CreateFrame("Frame", "CellSeparateNPCFrameAnchor", Cell.frames.mainFrame, "BackdropTemplate")
Cell.frames.separateNpcFrameAnchor = separateAnchor
separateAnchor:SetMovable(true)
separateAnchor:SetClampedToScreen(true)
P.Size(separateAnchor, 20, 10)
-- 初始位置：放在 CellParent 中心偏右上，默认大小 20x10
PixelUtil.SetPoint(separateAnchor, "TOPLEFT", CellParent, "CENTER", 1, -1)
-- 调试用：将独立锚点染成半透明绿色以可视化
-- Cell.StylizeFrame(separateAnchor, {0, 1, 0, 0.4})

-- 悬停感应框架：比 separateAnchor 四周各多 1px，用于扩大鼠标悬停检测区域
local hoverFrame = CreateFrame("Frame", nil, npcFrame)
hoverFrame:SetPoint("TOP", separateAnchor, 0, 1)
hoverFrame:SetPoint("BOTTOM", separateAnchor, 0, -1)
hoverFrame:SetPoint("LEFT", separateAnchor, -1, 0)
hoverFrame:SetPoint("RIGHT", separateAnchor, 1, 0)

-- 应用淡入淡出动画：鼠标悬停时淡入，离开后延时淡出
A.ApplyFadeInOutToMenu(separateAnchor, hoverFrame)

-- 拖拽句柄按钮：用户通过拖拽此按钮来移动独立锚点位置
-- 命名为 "dumb" 因为它本身无边框/背景，只是一个透明的拖拽接收器
local dumb = Cell.CreateButton(separateAnchor, nil, "accent", {20, 10}, false, true)
dumb:Hide()
dumb:SetFrameStrata("MEDIUM")
dumb:SetAllPoints(separateAnchor)
-- OnDragStart：开始拖动，标记为用户放置（非自动布局）
dumb:SetScript("OnDragStart", function()
    separateAnchor:StartMoving()
    separateAnchor:SetUserPlaced(false)
end)
-- OnDragStop：停止拖动，保存位置到当前布局配置的 npc.position 字段
dumb:SetScript("OnDragStop", function()
    separateAnchor:StopMovingOrSizing()
    P.SavePosition(separateAnchor, Cell.vars.currentLayoutTable["npc"]["position"])
end)
-- OnEnter 钩子：显示 tooltip 提示这是"友好NPC框架"，同时触发悬停淡入动画
dumb:HookScript("OnEnter", function()
    hoverFrame:GetScript("OnEnter")(hoverFrame)
    CellTooltip:SetOwner(dumb, "ANCHOR_NONE")
    CellTooltip:SetPoint(tooltipPoint, dumb, tooltipRelativePoint, tooltipX, tooltipY)
    CellTooltip:AddLine(L["Friendly NPC Frame"])
    CellTooltip:Show()
end)
-- OnLeave 钩子：隐藏 tooltip，触发悬停淡出动画
dumb:HookScript("OnLeave", function()
    hoverFrame:GetScript("OnLeave")(hoverFrame)
    CellTooltip:Hide()
end)

-- UpdateSeparateAnchor: 根据是否有可见 NPC 按钮来决定独立锚点的显/隐
-- 仅在 layout["npc"]["separate"] == true 时生效
-- 同时管理淡入淡出动画：有可见按钮→显示锚点并播放淡入；无可见按钮→隐藏锚点
function npcFrame:UpdateSeparateAnchor()
    local show
    if Cell.vars.currentLayoutTable["npc"]["separate"] then
        for _, b in ipairs(Cell.unitButtons.npc) do
            show = b:IsShown()
            if show then break end
        end
    end

    -- 启用/禁用鼠标悬停检测
    hoverFrame:EnableMouse(show)
    if show then
        dumb:Show()
        -- 如果全局设置了淡出效果
        -- NOTE: SecretValue 直接读取 CellDB["general"]["fadeOut"]，可考虑使用 F.SafeGet 安全函数
        if CellDB["general"]["fadeOut"] then
            if hoverFrame:IsMouseOver() then
                separateAnchor.fadeIn:Play()  -- 鼠标已在锚点上→直接淡入
            else
                separateAnchor.fadeOut:GetScript("OnFinished")(separateAnchor.fadeOut)  -- 触发淡出结束状态（完全隐藏）
            end
        end
    else
        dumb:Hide()
    end
end

-------------------------------------------------
-- NOTE: update each npc unit button
-- pointUpdater: 安全的按钮重排片段（SecureHandler snippet）
-- 在 secure 环境中遍历所有可见的 boss1~8 按钮，按方向（垂直/水平）重新排列位置
-- 最后调用 UpdateSeparateAnchor() 同步独立锚点状态
-------------------------------------------------
local pointUpdater = [[
    local orientation, point, anchorPoint, unitSpacing = ...
    -- print(orientation, point, anchorPoint, unitSpacing)
    local last  -- 上一个可见按钮，用于链式锚定
    for i = 1, 8 do
        local button = self:GetFrameRef("button"..i)
        button:ClearAllPoints()
        if button:IsVisible() then
            if last then
                -- NOTE: anchor to last  （锚定到上一个可见按钮）
                if orientation == "vertical" then
                    button:SetPoint(point, last, anchorPoint, 0, unitSpacing)
                else
                    button:SetPoint(point, last, anchorPoint, unitSpacing, 0)
                end
            else
                -- 第一个可见按钮：锚定到 NPCFrame 的左上角
                button:SetPoint("TOPLEFT", self)
            end
            last = button
        end
    end

    -- 重排完成后再同步独立锚点的显隐和淡入淡出状态
    self:CallMethod("UpdateSeparateAnchor")
]]
-- 把重排片段保存为 NPCFrame 的一个 secure attribute
npcFrame:SetAttribute("pointUpdater", pointUpdater)

-------------------------------------------------
-- create buttons
-- 创建 8 个 NPC/Boss 单位按钮（boss1 ~ boss8）
-- boss1-5 由暴雪 API 原生支持健康/光环更新；boss6-8 需要额外处理（见下方 CLEU/Midnight 回退逻辑）
-------------------------------------------------
for i = 1, 8 do
    -- 每个按钮继承 CellUnitButtonTemplate，作为 NPCFrame 的子框架
    local button = CreateFrame("Button", npcFrame:GetName().."Button"..i, npcFrame, "CellUnitButtonTemplate")
    tinsert(Cell.unitButtons.npc, button)  -- 注册到全局 NPC 按钮列表
    -- Cell.unitButtons.npc.units["boss"..i] = button
    -- button.type = "npc" -- layout setup

    -- 按钮显示时，建立 unit→button 的快速查找映射
    button:HookScript("OnShow", function()
        Cell.unitButtons.npc.units["boss"..i] = button
    end)
    -- 按钮隐藏时，清除映射
    button:HookScript("OnHide", function()
        Cell.unitButtons.npc.units["boss"..i] = nil
    end)

    -- 安全绑定 unit 属性：让 WoW 的 secure 系统自动驱动此按钮跟踪对应 boss
    button:SetAttribute("unit", "boss"..i)
    -- button:SetAttribute("unit", "player")
    -- for testing ------------------------------
    -- 测试代码（已注释）：将某些 boss 按钮改为跟踪 target/player 用于开发调试
    -- if i == 1 then
    --     button:SetAttribute("unit", "target")
    --     RegisterUnitWatch(button)
    -- end
    -- if i == 7 then
    --     button:SetAttribute("unit", "player")
    --     RegisterUnitWatch(button)
    -- elseif i == 2 then
    --     button:SetAttribute("unit", "target")
    --     RegisterAttributeDriver(button, "state-visibility", "[@target, exists] show; hide")
    -- elseif i == 4 then
    --     button:SetAttribute("unit", "target")
    --     RegisterAttributeDriver(button, "state-visibility", "[@target, help] show; hide")
    -- elseif i == 6 then
    --     button:SetAttribute("unit", "target")
    --     RegisterAttributeDriver(button, "state-visibility", "[@target, harm] show; hide")
    -- end

    -- if i >= 6 then
    --     UnregisterAttributeDriver(button, "state-visibility")
    --     button:SetAttribute("unit", "target")
    --     RegisterUnitWatch(button)

    --     local bar = Cell.CreateStatusBar(nil, button, 10, 5, 1, false, nil, nil, Cell.vars.whiteTexture, {1, 1, 1, 1})
    --     bar:SetFrameLevel(button.widgets.healthBar:GetFrameLevel() + 1)
    --     bar.border:Hide()

    --     bar:SetPoint("BOTTOMLEFT", button.widgets.healthBar)
    --     bar:SetPoint("BOTTOMRIGHT", button.widgets.healthBar)
    --     bar:SetScript("OnUpdate", function()
    --         local health = UnitHealth("boss"..i)
    --         local healthMax = UnitHealthMax("boss"..i)
    --         bar:SetValue(health / healthMax)
    --     end)
    -- end
    ---------------------------------------------

    -- NOTE: save reference for re-point
    -- 将按钮引用注入 secure 环境，使 secure handler 可通过 GetFrameRef 访问
    npcFrame:SetFrameRef("button"..i, button)

    -- NOTE: update each npc unitbutton's point on show/hide
    -- button.helper：SecureHandlerShowHideTemplate 辅助框架
    -- 在按钮显隐时自动触发 pointUpdater，重新排列所有可见按钮的位置
    button.helper = CreateFrame("Frame", nil, button, "SecureHandlerShowHideTemplate")
    button.helper:SetFrameRef("npcFrame", npcFrame)
    button.helper:SetAttribute("pointUpdater", [[
        local orientation = self:GetAttribute("orientation")
        local point = self:GetAttribute("point")
        local anchorPoint = self:GetAttribute("anchorPoint")
        local unitSpacing = self:GetAttribute("unitSpacing")

        local npcFrame = self:GetFrameRef("npcFrame")
        -- 通过 RunFor 在 NPCFrame 的 secure 环境中执行 pointUpdater 重排片段
        self:RunFor(npcFrame, npcFrame:GetAttribute("pointUpdater"), orientation, point, anchorPoint, unitSpacing)
    ]])
    -- _onshow / _onhide：SecureHandlerShowHideTemplate 的内置回调，在按钮显/隐时自动触发
    button.helper:SetAttribute("_onshow", [[ self:RunAttribute("pointUpdater") ]])
    button.helper:SetAttribute("_onhide", [[ self:RunAttribute("pointUpdater") ]])
end

-------------------------------------------------
-- FIXME: fix health updating boss678
-- ! BLIZZARD, FIX IT!
-- NOTE: On Midnight (12.0.0+) COMBAT_LOG_EVENT_UNFILTERED is unavailable.
-- Boss6-8 health/aura updates fall back entirely to the periodic poll
-- (elapsed3 >= 5) and UNIT_HEALTH / UNIT_AURA unit events registered below.
-- The CLEU path is guarded by Cell.isMidnight.
--
-- 背景说明：
-- 暴雪原生 API 中 boss1~boss5 的 UnitHealth/UnitAura 等函数直接有效，
-- 但 boss6~boss8 的数据更新不实时。在非 Midnight 版本（< 12.0.0）中，
-- 通过监听 COMBAT_LOG_EVENT_UNFILTERED 事件来获取 boss6-8 的血量/光环变动。
-- 在 Midnight 版本（>= 12.0.0）中，COMBAT_LOG_EVENT_UNFILTERED 被移除，
-- 只能依赖周期性轮询（elapsed3 >= 5秒）和 UNIT_HEALTH/UNIT_AURA 单位事件。
--
-- boss678_guidToButton：GUID → 按钮的反向查找表，用于 CLEU 事件中快速定位按钮
-- boss678_buttonToGuid：按钮索引(i) → GUID 的正向查找表，用于检测单位切换
-------------------------------------------------
local boss678_guidToButton = {}
local boss678_buttonToGuid = {}

-- CLEU 监听框架：在非 Midnight 下用于监听战斗日志事件更新 boss6-8
local cleu = CreateFrame("Frame")

if not Cell.isMidnight then
    -- 非 Midnight 路径：使用 COMBAT_LOG_EVENT_UNFILTERED
    -- 每当目标 GUID 匹配 boss678_guidToButton 中的记录时，根据子事件类型更新血量或光环
    cleu:SetScript("OnEvent", function()
        local timestamp, subEvent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()
        if boss678_guidToButton[destGUID] then
            if subEvent == "SPELL_HEAL" or subEvent == "SPELL_PERIODIC_HEAL" or subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE" then
                B.UpdateHealth(boss678_guidToButton[destGUID])
            elseif subEvent == "SPELL_AURA_REFRESH" or subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REMOVED" or subEvent == "SPELL_AURA_APPLIED_DOSE" or subEvent == "SPELL_AURA_REMOVED_DOSE" then
                B.UpdateAuras(boss678_guidToButton[destGUID])
            end
        end
    end)
else
    -- Midnight: use UNIT_HEALTH and UNIT_AURA for boss6-8 unit events.
    -- These events fire for units that WoW tracks; boss6-8 visibility may be
    -- limited but is better than nothing and complements the periodic poll.
    --
    -- Midnight 路径：COMBAT_LOG_EVENT_UNFILTERED 不可用
    -- 改用 RegisterUnitEvent 注册 UNIT_HEALTH / UNIT_MAXHEALTH / UNIT_AURA
    -- 当事件触发时，遍历 boss6-8 按钮找到匹配 unit 的按钮并更新对应数据
    cleu:SetScript("OnEvent", function(self, event, unit)
        local button = unit and F.HandleUnitButton and nil
        -- resolve unit to button via the boss678 unit map
        -- 遍历 boss6-8 按钮，根据 unit 参数匹配对应的按钮
        for idx = 6, 8 do
            local b = Cell.unitButtons.npc[idx]
            if b and b.states and b.states.unit == unit then
                if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                    B.UpdateHealth(b)
                elseif event == "UNIT_AURA" then
                    B.UpdateAuras(b)
                end
                break
            end
        end
    end)
end

-- 为 boss6~8 按钮安装额外的生命周期和轮询钩子
-- boss1-5 数据由暴雪 API 原生驱动，无需额外处理；boss6-8 的 GUID 跟踪和 CLEU/UNIT 事件注册在此处完成
for i = 6, 8 do
    local button = Cell.unitButtons.npc[i]
    -- OnShow 钩子：按钮显示时建立 GUID 映射并注册事件
    button.helper:HookScript("OnShow", function()
        local guid = UnitGUID(button.states.unit)
        if not guid then return end

        -- 建立双向 GUID ↔ 按钮映射
        boss678_buttonToGuid[i] = guid
        boss678_guidToButton[guid] = button

        -- update now  （立即获取当前血量/光环数据）
        B.UpdateAll(button)

        if Cell.isMidnight then
            -- Register unit events for this boss slot on Midnight
            -- Midnight 下为此 boss 单位注册 UNIT_HEALTH / UNIT_MAXHEALTH / UNIT_AURA 事件
            local unit = button.states.unit
            if unit then
                cleu:RegisterUnitEvent("UNIT_HEALTH", unit)
                cleu:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
                cleu:RegisterUnitEvent("UNIT_AURA", unit)
            end
        end
    end)

    -- OnHide 钩子：按钮隐藏时清理 GUID 映射和事件注册
    button.helper:HookScript("OnHide", function()
        -- 移除 GUID 映射
        boss678_guidToButton[boss678_buttonToGuid[i] or ""] = nil
        boss678_buttonToGuid[i] = nil

        -- 重置所有轮询计时器
        button.helper.elapsed = nil
        button.helper.elapsed2 = nil
        button.helper.elapsed3 = nil

        if not Cell.isMidnight then
            -- 如果 boss6-8 全部隐藏，注销 COMBAT_LOG_EVENT_UNFILTERED 事件以节省性能
            if F.Getn(boss678_buttonToGuid) == 0 then
                cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            end
        end
        -- Note: unit events registered via RegisterUnitEvent are automatically
        -- unregistered when no units match; no explicit cleanup needed.
    end)

    -- OnUpdate 三阶段轮询钩子：
    -- elapsed  (0.25s)：GUID 变化检测——单位切换时更新映射并刷新全部数据
    -- elapsed2 (1s)   ：CLEU 事件注册保活（非 Midnight）——确保 COMBAT_LOG_EVENT_UNFILTERED 始终注册
    -- elapsed3 (5s)   ：血量回退轮询——作为 CLEU/UNIT 事件失败时的兜底更新
    button.helper:HookScript("OnUpdate", function(self, elapsed)
        button.helper.elapsed = (button.helper.elapsed or 0) + elapsed
        button.helper.elapsed2 = (button.helper.elapsed2 or 0) + elapsed
        button.helper.elapsed3 = (button.helper.elapsed3 or 0) + elapsed

        -- 每 0.25 秒检查 GUID 是否变化（如目标切换、单位刷新）
        if button.helper.elapsed >= 0.25 then
            local guid = UnitGUID(button.states.unit)
            -- check old guid
            if guid and boss678_buttonToGuid[i] ~= guid then --! unit changed（单位已切换）
                -- remove old  （移除旧 GUID 映射）
                boss678_guidToButton[boss678_buttonToGuid[i] or ""] = nil
                -- add new  （添加新 GUID 映射）
                boss678_buttonToGuid[i] = guid
                boss678_guidToButton[guid] = button
                -- update now  （立即刷新全部数据）
                B.UpdateAll(button)
            end
            button.helper.elapsed = 0
        end

        if not Cell.isMidnight then
            -- 每 1 秒确保 COMBAT_LOG_EVENT_UNFILTERED 已注册（非 Midnight 下用于实时健康/光环更新）
            if button.helper.elapsed2 >= 1 then
                if not cleu:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED") then
                    cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                end
                button.helper.elapsed2 = 0
            end
        end

        -- 每 5 秒强制更新血量和最大血量——作为所有事件路径的最终兜底
        if button.helper.elapsed3 >= 5 then
            B.UpdateHealth(button)
            B.UpdateHealthMax(button)
            button.helper.elapsed3 = 0
        end
    end)
end

-------------------------------------------------
-- update point when group type changed
-- _onstate-groupstate：SecureHandlerStateTemplate 的状态变化回调
-- 当队伍类型在 solo → party → raid 之间切换时自动触发，重新锚定 NPCFrame 位置
-------------------------------------------------
npcFrame:SetAttribute("_onstate-groupstate", [[
    -- print("groupstate", newstate)
    self:SetAttribute("group", newstate)  -- 记录当前队伍类型

    local petstate = self:GetAttribute("pet")
    local anchor = self:GetFrameRef(newstate)  -- 获取对应队伍类型的锚点框架引用
    local orientation = self:GetAttribute("orientation")
    local point = self:GetAttribute("point")
    local anchorPoint = self:GetAttribute("anchorPoint")
    local groupAnchorPoint = self:GetAttribute("groupAnchorPoint")
    local unitSpacing = self:GetAttribute("unitSpacing")
    local groupSpacing = self:GetAttribute("groupSpacing")

    self:ClearAllPoints()

    if orientation == "vertical" then
        if newstate == "raid" then
            -- 团队模式：直接锚定到 NPC 锚点框架
            self:SetPoint(point, anchor)

        elseif newstate == "party" then
            -- NOTE: at first time petstate == nil
            -- 小队模式：根据是否有宠物决定锚定到 solo 还是 party 锚点
            if petstate == "nopet" then
                self:SetPoint(point, self:GetFrameRef("solo"), groupAnchorPoint, groupSpacing, 0)
            else
                self:SetPoint(point, self:GetFrameRef("party"), groupAnchorPoint, groupSpacing, 0)
            end

        else -- solo
            -- 单人模式：锚定到 solo（玩家）框架
            self:SetPoint(point, anchor, groupAnchorPoint, groupSpacing, 0)
        end
    else
        if newstate == "raid" then
            self:SetPoint(point, anchor)

        elseif newstate == "party" then
            -- NOTE: at first time petstate == nil
            if petstate == "nopet" then
                self:SetPoint(point, self:GetFrameRef("solo"), groupAnchorPoint, 0, groupSpacing)
            else
                self:SetPoint(point, self:GetFrameRef("party"), groupAnchorPoint, 0, groupSpacing)
            end

        else -- solo
            self:SetPoint(point, anchor, groupAnchorPoint, 0, groupSpacing)
        end
    end

    -- NOTE: update each npc button
    -- NPCFrame 锚点变动后，重新排列所有可见按钮位置
    self:RunAttribute("pointUpdater", orientation, point, anchorPoint, unitSpacing)
]])

-------------------------------------------------
-- update point when pet state changed
-- _onstate-petstate：SecureHandlerStateTemplate 的宠物状态变化回调
-- 仅在 party（小队）模式下才有影响：有宠物时 NPCFrame 锚定到宠物按钮之后，无宠物时锚定到玩家按钮之后
-------------------------------------------------
npcFrame:SetAttribute("_onstate-petstate", [[
    -- print("petstate", newstate)
    self:SetAttribute("pet", newstate)  -- 记录当前宠物状态

    -- 仅在小队模式下需要因宠物状态变化而重新锚定 NPCFrame
    if self:GetAttribute("group") == "party" then
        local orientation = self:GetAttribute("orientation")
        local point = self:GetAttribute("point")
        local anchorPoint = self:GetAttribute("anchorPoint")
        local groupAnchorPoint = self:GetAttribute("groupAnchorPoint")
        local unitSpacing = self:GetAttribute("unitSpacing")
        local groupSpacing = self:GetAttribute("groupSpacing")

        self:ClearAllPoints()

        if orientation == "vertical" then
            if newstate == "nopet" then
                -- 无宠物：锚定到 solo（玩家）框架
                self:SetPoint(point, self:GetFrameRef("solo"), groupAnchorPoint, groupSpacing, 0)
            else
                -- 有宠物：锚定到 party（小队宠物按钮）框架
                self:SetPoint(point, self:GetFrameRef("party"), groupAnchorPoint, groupSpacing, 0)
            end
        else
            if newstate == "nopet" then
                self:SetPoint(point, self:GetFrameRef("solo"), groupAnchorPoint, 0, groupSpacing)
            else
                self:SetPoint(point, self:GetFrameRef("party"), groupAnchorPoint, 0, groupSpacing)
            end
        end
    end
]])
-- RegisterStateDriver(npcFrame, "petstate", "[@pet,exists] pet; [@partypet1,exists] pet1; [@partypet2,exists] pet2; [@partypet3,exists] pet3; [@partypet4,exists] pet4; nopet")

-------------------------------------------------
-- functions
-------------------------------------------------
-- UpdatePosition: 更新独立锚点模式下 NPCFrame 的位置和 tooltip 方向
-- 仅在 layout["npc"]["separate"] == true 时重新计算锚点关系和 tooltip 位置参数
-- 根据锚点方向（BOTTOMLEFT/BOTTOMRIGHT/TOPLEFT/TOPRIGHT）和菜单位置（top_bottom/left_right）动态计算
local function UpdatePosition()
    local layout = Cell.vars.currentLayoutTable

    -- update npcFrame anchor if separate from main
    if layout["npc"]["separate"] then
        npcFrame:ClearAllPoints()
        -- 加载已保存的独立锚点位置
        P.LoadPosition(separateAnchor, layout["npc"]["position"])

        local anchor
        if layout["pet"]["sameArrangementAsMain"] then
            anchor = layout["main"]["anchor"]  -- 跟随主框架的锚点方向
        else
            anchor = layout["npc"]["anchor"]  -- 使用 NPC 自身的锚点方向
        end

        -- 根据菜单位置模式计算 separateAnchor 尺寸、NPCFrame 锚点和 tooltip 位置
        -- NOTE: SecretValue 直接读取 CellDB["general"]["menuPosition"]，可考虑使用 F.SafeGet 安全函数
        if CellDB["general"]["menuPosition"] == "top_bottom" then
            P.Size(separateAnchor, 20, 10)  -- 水平方向：锚点横向 20x10
            if anchor == "BOTTOMLEFT" then
                npcFrame:SetPoint("BOTTOMLEFT", separateAnchor, "TOPLEFT", 0, 4)
                tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPLEFT", "BOTTOMLEFT", 0, -3
            elseif anchor == "BOTTOMRIGHT" then
                npcFrame:SetPoint("BOTTOMRIGHT", separateAnchor, "TOPRIGHT", 0, 4)
                tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPRIGHT", "BOTTOMRIGHT", 0, -3
            elseif anchor == "TOPLEFT" then
                npcFrame:SetPoint("TOPLEFT", separateAnchor, "BOTTOMLEFT", 0, -4)
                tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMLEFT", "TOPLEFT", 0, 3
            elseif anchor == "TOPRIGHT" then
                npcFrame:SetPoint("TOPRIGHT", separateAnchor, "BOTTOMRIGHT", 0, -4)
                tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMRIGHT", "TOPRIGHT", 0, 3
            end
        else
            P.Size(separateAnchor, 10, 20)  -- 垂直方向：锚点纵向 10x20
            if anchor == "BOTTOMLEFT" then
                npcFrame:SetPoint("BOTTOMLEFT", separateAnchor, "BOTTOMRIGHT", 4, 0)
                tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMRIGHT", "BOTTOMLEFT", -3, 0
            elseif anchor == "BOTTOMRIGHT" then
                npcFrame:SetPoint("BOTTOMRIGHT", separateAnchor, "BOTTOMLEFT", -4, 0)
                tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "BOTTOMLEFT", "BOTTOMRIGHT", 3, 0
            elseif anchor == "TOPLEFT" then
                npcFrame:SetPoint("TOPLEFT", separateAnchor, "TOPRIGHT", 4, 0)
                tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPRIGHT", "TOPLEFT", -3, 0
            elseif anchor == "TOPRIGHT" then
                npcFrame:SetPoint("TOPRIGHT", separateAnchor, "TOPLEFT", -4, 0)
                tooltipPoint, tooltipRelativePoint, tooltipX, tooltipY = "TOPLEFT", "TOPRIGHT", 3, 0
            end
        end
    end

    npcFrame:UpdateSeparateAnchor()
end

-- UpdateMenu: 响应全局 UpdateMenu 回调，处理锁定状态、淡出效果和位置变更
-- which 参数为 nil 时执行全部更新；为 "lock"/"fadeOut"/"position" 时仅执行对应更新
local function UpdateMenu(which)
    if not which or which == "lock" then
        -- 锁定状态切换：锁定时禁用拖拽按钮注册（无法拖动）；解锁时注册左键拖拽
        -- NOTE: SecretValue 直接读取 CellDB["general"]["locked"]，可考虑使用 F.SafeGet 安全函数
        if CellDB["general"]["locked"] then
            dumb:RegisterForDrag()
        else
            dumb:RegisterForDrag("LeftButton")
        end
    end

    if not which or which == "fadeOut" then
        -- 淡出效果切换：开启淡出→播放淡出动画；关闭淡出→播放淡入（始终可见）
        -- NOTE: SecretValue 直接读取 CellDB["general"]["fadeOut"]，可考虑使用 F.SafeGet 安全函数
        if CellDB["general"]["fadeOut"] then
            separateAnchor.fadeOut:Play()
        else
            separateAnchor.fadeIn:Play()
        end
    end

    if which == "position" then
        UpdatePosition()
    end
end
-- 注册到全局 UpdateMenu 回调，使用唯一标识 "NPCFrame_UpdateMenu"
Cell.RegisterCallback("UpdateMenu", "NPCFrame_UpdateMenu", UpdateMenu)

-- NPCFrame_UpdateLayout: NPCFrame 的全局布局更新入口
-- 由全局 UpdateLayout 回调触发，参数 layout 为触发布局的源布局表，which 指示触发更新的具体字段
--
-- 更新流程：
--   1. 可见性检查（isHidden 时直接隐藏）
--   2. 尺寸更新（sameSizeAsMain 控制是否跟随主框架）
--   3. 血条方向更新
--   4. 能量条尺寸更新
--   5. 宠物锚点更新（party 锚点跟随宠物配置变化）
--   6. 排列更新（sameArrangementAsMain 控制是否跟随主框架排列）
--   7. 独立锚点位置更新
--   8. 单位按钮的 attribute driver 注册/注销
local function NPCFrame_UpdateLayout(layout, which)
    -- visibility
    -- 全局隐藏标志：直接隐藏 NPCFrame（如 solo 时不显示等场景）
    if Cell.vars.isHidden then
        UnregisterAttributeDriver(npcFrame, "state-visibility")
        npcFrame:Hide()
        return
    end
    -- 注册可见性驱动：只要有 raid1 或 party1 成员即显示，否则也显示（solo 模式默认可见）
    RegisterAttributeDriver(npcFrame, "state-visibility", "[@raid1,exists] show;[@party1,exists] show;show")

    -- update
    layout = Cell.vars.currentLayoutTable

    -- 尺寸更新：响应 size 相关字段变化（如 width, height, sameSizeAsMain 等）
    if not which or strfind(which, "size$") then
        local width, height
        if layout["npc"]["sameSizeAsMain"] then
            width, height = unpack(layout["main"]["size"])  -- 跟随主框架尺寸
        else
            width, height = unpack(layout["npc"]["size"])  -- 使用独立尺寸
        end

        P.Size(npcFrame, width, height)

        for _, b in ipairs(Cell.unitButtons.npc) do
            P.Size(b, width, height)
        end
    end

    -- NOTE: SetOrientation BEFORE SetPowerSize
    -- 血条方向更新：必须在能量条尺寸更新之前设置，因为能量条位置依赖于血条方向
    if not which or which == "barOrientation" then
        for _, b in ipairs(Cell.unitButtons.npc) do
            B.SetOrientation(b, layout["barOrientation"][1], layout["barOrientation"][2])
        end
    end

    -- 能量条尺寸更新：响应 power、barOrientation、powerFilter 字段变化
    if not which or strfind(which, "power$") or which == "barOrientation" or which == "powerFilter" then
        for _, b in ipairs(Cell.unitButtons.npc) do
            if layout["npc"]["sameSizeAsMain"] then
                B.SetPowerSize(b, layout["main"]["powerSize"])
            else
                B.SetPowerSize(b, layout["npc"]["powerSize"])
            end
        end
    end

    -- 宠物锚点更新：当宠物框架的 partyEnabled 或 partyDetached 变更时
    -- 重新决定 NPCFrame 在小队模式下的锚点引用（跟随宠物按钮还是小队按钮）
    if not which or which == "pet" then
        if not layout["pet"]["partyEnabled"] or layout["pet"]["partyDetached"] then
            npcFrame:SetFrameRef("party", CellPartyFrameHeaderUnitButton1)
            anchors["party"] = CellPartyFrameHeaderUnitButton1
        else
            npcFrame:SetFrameRef("party", CellPartyFrameHeaderUnitButton1Pet)
            anchors["party"] = CellPartyFrameHeaderUnitButton1Pet
        end
    end

    -- 排列更新：响应 arrangement、npc、pet 字段变化
    -- 这是最核心的布局逻辑，计算锚点方向、间距等参数并重新定位 NPCFrame 和所有按钮
    if not which or strfind(which, "arrangement$") or which == "npc" or which == "pet" then
        local groupType = F.GetGroupType()
        npcFrame:ClearAllPoints()

        -- 获取排列参数：sameArrangementAsMain 决定是否复用主框架设置
        local orientation, anchor, spacingX, spacingY
        if layout["npc"]["sameArrangementAsMain"] then
            orientation = layout["main"]["orientation"]
            anchor = layout["main"]["anchor"]
            spacingX = layout["main"]["spacingX"]
            spacingY = layout["main"]["spacingY"]
        else
            orientation = layout["npc"]["orientation"]
            anchor = layout["npc"]["anchor"]
            spacingX = layout["npc"]["spacingX"]
            spacingY = layout["npc"]["spacingY"]
        end

        -- 根据方向和锚点计算具体的 point/相对定位参数
        local point, anchorPoint, groupAnchorPoint, unitSpacing, groupSpacing
        if orientation == "vertical" then
            if anchor == "BOTTOMLEFT" then
                point, anchorPoint, groupAnchorPoint = "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT"
                unitSpacing = spacingY
                groupSpacing = spacingX
            elseif anchor == "BOTTOMRIGHT" then
                point, anchorPoint, groupAnchorPoint = "BOTTOMRIGHT", "TOPRIGHT", "BOTTOMLEFT"
                unitSpacing = spacingY
                groupSpacing = -spacingX
            elseif anchor == "TOPLEFT" then
                point, anchorPoint, groupAnchorPoint = "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT"
                unitSpacing = -spacingY
                groupSpacing = spacingX
            elseif anchor == "TOPRIGHT" then
                point, anchorPoint, groupAnchorPoint = "TOPRIGHT", "BOTTOMRIGHT", "TOPLEFT"
                unitSpacing = -spacingY
                groupSpacing = -spacingX
            end

            if not layout["npc"]["separate"] then
                -- update whole NPCFrame point
                -- 非独立模式：NPCFrame 整体锚定到对应的队伍锚点框架
                if groupType == "raid" then
                    npcFrame:SetPoint(point, anchors["raid"])

                elseif groupType == "party" then
                    if npcFrame:GetAttribute("pet") == "nopet" then
                        npcFrame:SetPoint(point, anchors["solo"], groupAnchorPoint, P.Scale(groupSpacing), 0)
                    else
                        npcFrame:SetPoint(point, anchors["party"], groupAnchorPoint, P.Scale(groupSpacing), 0)
                    end

                else -- solo
                    npcFrame:SetPoint(point, anchors["solo"], groupAnchorPoint, P.Scale(groupSpacing), 0)
                end
            end
        else
            if anchor == "BOTTOMLEFT" then
                point, anchorPoint, groupAnchorPoint = "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT"
                unitSpacing = spacingX
                groupSpacing = spacingY
            elseif anchor == "BOTTOMRIGHT" then
                point, anchorPoint, groupAnchorPoint = "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT"
                unitSpacing = -spacingX
                groupSpacing = spacingY
            elseif anchor == "TOPLEFT" then
                point, anchorPoint, groupAnchorPoint = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT"
                unitSpacing = spacingX
                groupSpacing = -spacingY
            elseif anchor == "TOPRIGHT" then
                point, anchorPoint, groupAnchorPoint = "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT"
                unitSpacing = -spacingX
                groupSpacing = -spacingY
            end

            if not layout["npc"]["separate"] then
                -- update whole NPCFrame point
                if groupType == "raid" then
                    npcFrame:SetPoint(point, anchors["raid"])

                elseif groupType == "party" then
                    if npcFrame:GetAttribute("pet") == "nopet" then
                        npcFrame:SetPoint(point, anchors["solo"], groupAnchorPoint, 0, P.Scale(groupSpacing))
                    else
                        npcFrame:SetPoint(point, anchors["party"], groupAnchorPoint, 0, P.Scale(groupSpacing))
                    end

                else -- solo
                    npcFrame:SetPoint(point, anchors["solo"], groupAnchorPoint, 0, P.Scale(groupSpacing))
                end
            end
        end

        -- save point data
        -- 将计算好的定位参数存入 secure attribute，供 secure handler 片段使用
        npcFrame:SetAttribute("orientation", orientation)
        npcFrame:SetAttribute("point", point)
        npcFrame:SetAttribute("anchorPoint", anchorPoint)
        npcFrame:SetAttribute("groupAnchorPoint", groupAnchorPoint)
        npcFrame:SetAttribute("unitSpacing", P.Scale(unitSpacing))
        npcFrame:SetAttribute("groupSpacing", P.Scale(groupSpacing))

        -- 为每个按钮的 helper 设置相同的定位参数
        local last
        for i = 1, 8 do
            local button = Cell.unitButtons.npc[i]
            button.helper:SetAttribute("orientation", orientation)
            button.helper:SetAttribute("point", point)
            button.helper:SetAttribute("anchorPoint", anchorPoint)
            button.helper:SetAttribute("unitSpacing", P.Scale(unitSpacing))

            -- update each npc button now
            -- 立即更新可见按钮的位置（不通过 secure handler 延迟更新）
            if button:IsVisible() then
                button:ClearAllPoints()
                if last then
                    if orientation == "vertical" then
                        button:SetPoint(point, last, anchorPoint, 0, P.Scale(unitSpacing))
                    else
                        button:SetPoint(point, last, anchorPoint, P.Scale(unitSpacing), 0)
                    end
                else
                    button:SetPoint("TOPLEFT", npcFrame)
                end
                last = button
            end
        end
    end

    if not which or strfind(which, "arrangement$") or which == "npc" then
        UpdatePosition()
    end

    -- NPC 启用/禁用切换：注册或注销 secure attribute drivers
    if not which or which == "npc" then
        if layout["npc"]["enabled"] then
            -- NOTE: RegisterAttributeDriver
            -- 为每个 boss 按钮注册可见性驱动：仅当对应 boss 存在且为友方(help)时显示
            for i, b in ipairs(Cell.unitButtons.npc) do
                RegisterAttributeDriver(b, "state-visibility", "[@boss"..i..", help] show; hide")
                -- RegisterAttributeDriver(b, "state-visibility", "[@player, help] show; hide")
            end
            if layout["npc"]["separate"] then
                -- 独立模式：注销 groupstate/petstate 驱动，NPCFrame 位置由 UpdatePosition 手动管理
                UnregisterStateDriver(npcFrame, "groupstate")
                UnregisterStateDriver(npcFrame, "petstate")
                -- load separate npc frame position
                P.LoadPosition(separateAnchor, layout["npc"]["position"])
            else
                -- RegisterStateDriver(npcFrame, "groupstate", "[group:raid] raid;[group:party] party;solo")
                -- 非独立模式：注册状态驱动，队伍类型变化时自动触发 _onstate-groupstate 回调重定位
                RegisterStateDriver(npcFrame, "groupstate", "[@raid1,exists] raid;[@party1,exists] party;solo")
                -- 宠物状态驱动：宠物存在/类型变化时自动触发 _onstate-petstate 回调重定位
                RegisterStateDriver(npcFrame, "petstate", "[@pet,exists] pet; [@partypet1,exists] pet1; [@partypet2,exists] pet2; [@partypet3,exists] pet3; [@partypet4,exists] pet4; nopet")
            end
        else
            -- NOTE: RegisterAttributeDriver
            -- NPC 框架禁用：注销所有按钮的可见性驱动并隐藏按钮
            for _, b in ipairs(Cell.unitButtons.npc) do
                UnregisterAttributeDriver(b, "state-visibility")
                b:Hide()
            end
        end
    end
end
-- 注册到全局 UpdateLayout 回调，使用唯一标识 "NPCFrame_UpdateLayout"
Cell.RegisterCallback("UpdateLayout", "NPCFrame_UpdateLayout", NPCFrame_UpdateLayout)

-- （已废弃）NPCFrame_UpdateVisibility：旧版的可见性更新回调
-- 原用于根据 showSolo/showParty 设置独立控制 solo/party 模式下的显隐
-- 现已被 NPCFrame_UpdateLayout 中的统一可见性逻辑替代，故注释保留供参考
-- local function NPCFrame_UpdateVisibility(which)
--     if not which or which == "solo" or which == "party" then
--         local showSolo = CellDB["general"]["showSolo"] and "show" or "hide"
--         local showParty = CellDB["general"]["showParty"] and "show" or "hide"
--         -- RegisterAttributeDriver(npcFrame, "state-visibility", "[group:raid] show; [group:party] "..showParty.."; "..showSolo)
--         RegisterAttributeDriver(npcFrame, "state-visibility", "[@raid1,exists] show;[@party1,exists] "..showParty..";"..showSolo)
--     end
-- end
-- Cell.RegisterCallback("UpdateVisibility", "NPCFrame_UpdateVisibility", NPCFrame_UpdateVisibility)