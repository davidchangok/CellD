local _, Cell = ...
local L = Cell.L
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs
---@type CellAnimations
local A = Cell.animations
---@type PixelPerfectFuncs
local P = Cell.pixelPerfectFuncs

local LCG = LibStub("LibCustomGlow-1.0")
local LibTranslit = LibStub("LibTranslit-1.0")

-- 空函数占位符，用作未初始化的 SetValue 等方法的默认实现
local function noop() end

-------------------------------------------------
-- shared functions
-- 以下函数为冷却类指示器（防御冷却/外部冷却/所有冷却等）提供通用的 mixin 接口。
-- 每个 Create*Cooldowns 创建 Frame 容器后，将这些共享函数赋值给容器的方法，
-- 实现代码复用。所有共享函数通过遍历容器的子对象来批量操作。
-------------------------------------------------
-- 设置冷却指示器容器及所有子图标的统一尺寸
function I.Cooldowns_SetSize(self, width, height)
    self.width = width
    self.height = height

    for i = 1, #self do
        self[i]:SetSize(width, height)
    end

    self:UpdateSize()
end

-- 根据实际显示的图标数量动态更新容器尺寸。
-- iconsShown 参数在外部调用时传入（如 UnitButton_UpdateBuffs 或预览），
-- 为 nil 时则通过遍历子对象 IsShown() 自动计算。
function I.Cooldowns_UpdateSize(self, iconsShown)
    if not (self.width and self.height and self.orientation) then return end -- not init

    if iconsShown then -- call from I.UnitButton_UpdateBuffs or preview
        for i = iconsShown + 1, #self do
            self[i]:Hide()
        end
        if iconsShown ~= 0 then
            if self.orientation == "horizontal" then
                self:_SetSize(self.width*iconsShown-P.Scale(iconsShown-1), self.height)
            else
                self:_SetSize(self.width, self.height*iconsShown-P.Scale(iconsShown-1))
            end
        end
    else
        for i = 1, #self do
            if self[i]:IsShown() then
                if self.orientation == "horizontal" then
                    self:_SetSize(self.width*i-P.Scale(i-1), self.height)
                else
                    self:_SetSize(self.width, self.height*i-P.Scale(i-1))
                end
            end
        end
    end
end

-- 带间距版本的容器尺寸更新（图标间有 P.Scale(1) 像素间距）。
-- 用于 RaidDebuffs 和 CrowdControls 等需要图标间留白的指示器。
function I.Cooldowns_UpdateSize_WithSpacing(self, iconsShown)
    if not (self.width and self.height and self.orientation) then return end -- not init

    if iconsShown then -- call from I.UnitButton_UpdateBuffs or preview
        for i = iconsShown + 1, #self do
            self[i]:Hide()
        end
        if iconsShown ~= 0 then
            if self.orientation == "horizontal" then
                self:_SetSize(self.width * iconsShown + P.Scale(iconsShown - 1), self.height)
            else
                self:_SetSize(self.width, self.height * iconsShown + P.Scale(iconsShown - 1))
            end
        end
    else
        for i = 1, #self do
            if self[i]:IsShown() then
                if self.orientation == "horizontal" then
                    self:_SetSize(self.width * i + P.Scale(i - 1), self.height)
                else
                    self:_SetSize(self.width, self.height * i + P.Scale(i - 1))
                end
            end
        end
    end
end

-- 批量设置所有子图标的边框样式
function I.Cooldowns_SetBorder(self, border)
    for i = 1, #self do
        self[i]:SetBorder(border)
    end
end

-- 批量设置所有子图标的字体（可变参数透传）
function I.Cooldowns_SetFont(self, ...)
    for i = 1, #self do
        self[i]:SetFont(...)
    end
end

-- 批量控制所有子图标是否显示冷却持续时间数字
function I.Cooldowns_ShowDuration(self, show)
    for i = 1, #self do
        self[i]:ShowDuration(show)
    end
end

-- 批量控制所有子图标是否显示冷却动画（时钟式扫描线）
function I.Cooldowns_ShowAnimation(self, show)
    for i = 1, #self do
        self[i]:ShowAnimation(show)
    end
end

-- 批量更新所有子图标的像素完美对齐（重新定位和调整尺寸）
function I.Cooldowns_UpdatePixelPerfect(self)
    P.Repoint(self)
    for i = 1, #self do
        self[i]:UpdatePixelPerfect()
    end
end

-- 设置冷却指示器的排列方向（紧贴排列，图标间无间距）。
-- 支持四种方向：left-to-right / right-to-left / top-to-bottom / bottom-to-top。
-- 通过计算 point1/point2 与偏移量 x/y，将所有子图标沿指定方向依次锚定。
function I.Cooldowns_SetOrientation(self, orientation)
    local point1, point2, x, y

    if orientation == "left-to-right" then
        point1 = "TOPLEFT"
        point2 = "TOPRIGHT"
        self.orientation = "horizontal"
        x = -1
        y = 0
    elseif orientation == "right-to-left" then
        point1 = "TOPRIGHT"
        point2 = "TOPLEFT"
        self.orientation = "horizontal"
        x = 1
        y = 0
    elseif orientation == "top-to-bottom" then
        point1 = "TOPLEFT"
        point2 = "BOTTOMLEFT"
        self.orientation = "vertical"
        x = 0
        y = 1
    elseif orientation == "bottom-to-top" then
        point1 = "BOTTOMLEFT"
        point2 = "TOPLEFT"
        self.orientation = "vertical"
        x = 0
        y = -1
    end

    for i = 1, #self do
        P.ClearPoints(self[i])
        if i == 1 then
            P.Point(self[i], point1)
        else
            P.Point(self[i], point1, self[i-1], point2, x, y)
        end
    end

    self:UpdateSize()
end

-- 带间距版本的排列方向设置（图标间有 P.Scale(1) 像素间距）。
-- 与无间距版本的差异在于偏移量 x/y 使用 ±1（而非 0），正负号也相反。
function I.Cooldowns_SetOrientation_WithSpacing(self, orientation)
    local point1, point2, x, y

    if orientation == "left-to-right" then
        point1 = "TOPLEFT"
        point2 = "TOPRIGHT"
        self.orientation = "horizontal"
        x = 1
        y = 0
    elseif orientation == "right-to-left" then
        point1 = "TOPRIGHT"
        point2 = "TOPLEFT"
        self.orientation = "horizontal"
        x = -1
        y = 0
    elseif orientation == "top-to-bottom" then
        point1 = "TOPLEFT"
        point2 = "BOTTOMLEFT"
        self.orientation = "vertical"
        x = 0
        y = -1
    elseif orientation == "bottom-to-top" then
        point1 = "BOTTOMLEFT"
        point2 = "TOPLEFT"
        self.orientation = "vertical"
        x = 0
        y = 1
    end

    for i = 1, #self do
        P.ClearPoints(self[i])
        if i == 1 then
            P.Point(self[i], point1)
        else
            P.Point(self[i], point1, self[i-1], point2, x, y)
        end
    end

    self:UpdateSize()
end

-------------------------------------------------
-- CreateDefensiveCooldowns
-- 创建"防御减伤冷却"指示器容器。缓存 parent 原始 _SetSize 方法后，
-- 将共享函数 mixin 为容器方法。预创建 5 个 Aura_BarIcon 作为子图标槽位。
-- Mixin 模式：容器._SetSize = 原始 SetSize（Frame 默认），容器.SetSize = 共享函数，
--   使得外部调用 SetSize 时触发自定义逻辑同时保留底层能力。
-------------------------------------------------
function I.CreateDefensiveCooldowns(parent)
    local defensiveCooldowns = CreateFrame("Frame", parent:GetName().."DefensiveCooldownParent", parent.widgets.indicatorFrame)
    parent.indicators.defensiveCooldowns = defensiveCooldowns
    -- defensiveCooldowns:SetSize(20, 10)
    defensiveCooldowns:Hide()

    defensiveCooldowns._SetSize = defensiveCooldowns.SetSize
    defensiveCooldowns.SetSize = I.Cooldowns_SetSize
    defensiveCooldowns.UpdateSize = I.Cooldowns_UpdateSize
    defensiveCooldowns.SetFont = I.Cooldowns_SetFont
    defensiveCooldowns.SetOrientation = I.Cooldowns_SetOrientation
    defensiveCooldowns.ShowDuration = I.Cooldowns_ShowDuration
    defensiveCooldowns.ShowAnimation = I.Cooldowns_ShowAnimation
    defensiveCooldowns.SetupGlow = I.Glow_SetupForChildren
    defensiveCooldowns.UpdatePixelPerfect = I.Cooldowns_UpdatePixelPerfect

    for i = 1, 5 do
        local name = parent:GetName().."DefensiveCooldown"..i
        local frame = I.CreateAura_BarIcon(name, defensiveCooldowns)
        tinsert(defensiveCooldowns, frame)
    end
end

-------------------------------------------------
-- CreateExternalCooldowns
-- 创建"外部增益冷却"指示器容器（如队友给予的减伤技能如痛苦压制、铁木树皮等）。
-- 结构与 DefensiveCooldowns 完全相同，预创建 5 个 Aura_BarIcon 子图标。
-------------------------------------------------
function I.CreateExternalCooldowns(parent)
    local externalCooldowns = CreateFrame("Frame", parent:GetName().."ExternalCooldownParent", parent.widgets.indicatorFrame)
    parent.indicators.externalCooldowns = externalCooldowns
    externalCooldowns:Hide()

    externalCooldowns._SetSize = externalCooldowns.SetSize
    externalCooldowns.SetSize = I.Cooldowns_SetSize
    externalCooldowns.UpdateSize = I.Cooldowns_UpdateSize
    externalCooldowns.SetFont = I.Cooldowns_SetFont
    externalCooldowns.SetOrientation = I.Cooldowns_SetOrientation
    externalCooldowns.ShowDuration = I.Cooldowns_ShowDuration
    externalCooldowns.ShowAnimation = I.Cooldowns_ShowAnimation
    externalCooldowns.SetupGlow = I.Glow_SetupForChildren
    externalCooldowns.UpdatePixelPerfect = I.Cooldowns_UpdatePixelPerfect

    for i = 1, 5 do
        local name = parent:GetName().."ExternalCooldown"..i
        local frame = I.CreateAura_BarIcon(name, externalCooldowns)
        tinsert(externalCooldowns, frame)
    end
end

-------------------------------------------------
-- CreateAllCooldowns
-- 创建"所有冷却"指示器容器（显示单位身上的所有冷却类光环）。
-- 结构与上述两个冷却指示器完全相同，预创建 5 个 Aura_BarIcon 子图标。
-------------------------------------------------
function I.CreateAllCooldowns(parent)
    local allCooldowns = CreateFrame("Frame", parent:GetName().."AllCooldownParent", parent.widgets.indicatorFrame)
    parent.indicators.allCooldowns = allCooldowns
    allCooldowns:Hide()

    allCooldowns._SetSize = allCooldowns.SetSize
    allCooldowns.SetSize = I.Cooldowns_SetSize
    allCooldowns.UpdateSize = I.Cooldowns_UpdateSize
    allCooldowns.SetFont = I.Cooldowns_SetFont
    allCooldowns.SetOrientation = I.Cooldowns_SetOrientation
    allCooldowns.ShowDuration = I.Cooldowns_ShowDuration
    allCooldowns.ShowAnimation = I.Cooldowns_ShowAnimation
    allCooldowns.SetupGlow = I.Glow_SetupForChildren
    allCooldowns.UpdatePixelPerfect = I.Cooldowns_UpdatePixelPerfect

    for i = 1, 5 do
        local name = parent:GetName().."AllCooldown"..i
        local frame = I.CreateAura_BarIcon(name, allCooldowns)
        tinsert(allCooldowns, frame)
    end
end

-------------------------------------------------
-- CreateTankActiveMitigation
-- 创建"坦克主动减伤"进度条指示器。使用 StatusBar 配合 OnUpdate 脚本
-- 以 0.1 秒间隔递增进度条值，实现平滑的冷却剩余时间可视化。
-- SetCooldown(start, duration) 设置总时长和已过时间，进度条从 start 开始递增。
-- 支持 class_color（职业颜色）或自定义颜色两种着色模式。
-------------------------------------------------
function I.CreateTankActiveMitigation(parent)
    local bar = Cell.CreateStatusBar(parent:GetName().."TankActiveMitigation", parent.widgets.indicatorFrame, 20, 6, 100)
    parent.indicators.tankActiveMitigation = bar
    bar:Hide()

    bar:SetStatusBarTexture(Cell.vars.whiteTexture)
    bar:GetStatusBarTexture():SetAlpha(0)
    bar:SetReverseFill(true)

    local tex = bar:CreateTexture(nil, "BORDER", nil, -1)
    bar.tex = tex
    tex:SetColorTexture(F.GetClassColor(Cell.vars.playerClass))
    tex:SetPoint("TOPLEFT")
    tex:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMLEFT")

    local elapsedTime = 0
    bar:SetScript("OnUpdate", function(self, elapsed)
        if elapsedTime >= 0.1 then
            bar:SetValue(bar:GetValue() + elapsedTime)
            elapsedTime = 0
        end
        elapsedTime = elapsedTime + elapsed
    end)

    function bar:SetCooldown(start, duration)
        if bar.cType == "class_color" then
            if not parent.states.class then parent.states.class = UnitClassBase(parent.states.unit) end --? why sometimes parent.states.class == nil ???
            tex:SetColorTexture(F.GetClassColor(parent.states.class))
        else
            tex:SetColorTexture(bar.cTable[1], bar.cTable[2], bar.cTable[3])
        end
        bar:SetMinMaxValues(0, duration)
        bar:SetValue(GetTime()-start)
        bar:Show()
    end

    function bar:SetColor(cType, cTable)
        bar.cType = cType
        bar.cTable = cTable
    end
end

-------------------------------------------------
-- CreateDebuffs
-- Debuff 指示器：最多显示 10 个可自定义尺寸的 debuff 图标（可设置普通大小和"大图标"大小）。
-- 内部函数区别于共享函数：Debuff 支持两种尺寸（normalSize / bigSize）、
-- 自定义对齐方式（hAlignment / vAlignment），以及黑名单快捷键功能。
-------------------------------------------------
-- 设置 Debuff 图标尺寸：接受 normalSize 和 bigSize 两个数组参数（如 {20, 20}）。
-- 存储后清除 PixelPerfect 可能误存的 width/height 数据。
local function Debuffs_SetSize(self, normalSize, bigSize)
    for i = 1, 10 do
        P.Size(self[i], normalSize[1], normalSize[2])
    end
    -- store sizes for SetCooldown
    self.normalSize = normalSize
    self.bigSize = bigSize
    -- remove wrong data from PixelPerfect
    self.width = nil
    self.height = nil

    self:UpdateSize()
end

-- 更新 Debuff 容器尺寸：累加所有可见图标的实际宽度（horizontal）或高度（vertical）来计算。
-- 注意子图标可能因 bigDebuff 而有不同宽度，无法用 width*i 直接计算。
local function Debuffs_UpdateSize(self, iconsShown)
    if not (self.normalSize and self.bigSize and self.orientation) then return end -- not init

    if iconsShown then
        for i = iconsShown + 1, 10 do
            self[i]:Hide()
        end
    end

    local size = 0
    for i = 1, 10 do
        if self[i]:IsShown() then
            size = size + self[i].width
        end
    end
    if self.orientation == "left-to-right" or self.orientation == "right-to-left"  then
        self:_SetSize(P.Scale(size), P.Scale(self.normalSize[2]))
    else
        self:_SetSize(P.Scale(self.normalSize[1]), P.Scale(size))
    end
end

local function Debuffs_SetFont(self, ...)
    for i = 1, 10 do
        self[i]:SetFont(...)
    end
end

-- 重写 SetPoint 以记录水平和垂直对齐方式（hAlignment / vAlignment）。
-- 对齐信息随后被 SetOrientation 用来确定每个子图标的锚点（如 "TOPLEFT" vs "TOPLEFT"）。
-- 必须先调用 SetPoint 再调用 SetOrientation。
local function Debuffs_SetPoint(self, point, relativeTo, relativePoint, x, y)
    self:_SetPoint(point, relativeTo, relativePoint, x, y)

    if string.find(point, "LEFT$") then
        self.hAlignment = "LEFT"
    elseif string.find(point, "RIGHT$") then
        self.hAlignment = "RIGHT"
    else
        self.hAlignment = ""
    end

    if string.find(point, "^TOP") then
        self.vAlignment = "TOP"
    elseif string.find(point, "^BOTTOM") then
        self.vAlignment = "BOTTOM"
    else
        self.vAlignment = ""
    end

    if self.hAlignment == "" and self.vAlignment == "" then
        self.vAlignment = "CENTER"
    end

    -- self[1]:ClearAllPoints()
    -- self[1]:SetPoint(self.vAlignment..self.hAlignment)
    -- --! update icons
    self:SetOrientation(self.orientation or "left-to-right")
end

--! NOTE: SetPoint must be invoked before SetOrientation
-- 设置 Debuff 图标排列方向。与共享 Cooldowns_SetOrientation 的关键区别：
-- 使用 hAlignment / vAlignment 拼接锚点字符串（如 "TOPLEFT"），
-- 支持所有 9 种对齐组合（TOP/BOTTOM/CENTER x LEFT/RIGHT/CENTER）。
-- 必须先调用 SetPoint（记录对齐方式）再调用 SetOrientation。
local function Debuffs_SetOrientation(self, orientation)
    self.orientation = orientation
    local point1, point2, v, h
    v = self.vAlignment == "CENTER" and "" or self.vAlignment
    h = self.hAlignment
    if orientation == "left-to-right" then
        point1 = v.."LEFT"
        point2 = v.."RIGHT"
    elseif orientation == "right-to-left" then
        point1 = v.."RIGHT"
        point2 = v.."LEFT"
    elseif orientation == "top-to-bottom" then
        point1 = "TOP"..h
        point2 = "BOTTOM"..h
    elseif orientation == "bottom-to-top" then
        point1 = "BOTTOM"..h
        point2 = "TOP"..h
    end

    for i = 1, 10 do
        P.ClearPoints(self[i])
        if i == 1 then
            P.Point(self[i], point1)
        else
            P.Point(self[i], point1, self[i-1], point2)
        end
    end

    self:UpdateSize()
end

-- 控制 Debuff 图标的鼠标悬停提示。
-- 开启时绑定 OnEnter（显示 spell 或 aura 提示）和 OnLeave（隐藏提示）。
-- 鼠标点击默认禁用，除非开启了黑名单快捷键功能。
local function Debuffs_ShowTooltip(debuffs, show)
    debuffs.showTooltip = show

    for i = 1, 10 do
        if show then
            debuffs[i]:SetScript("OnEnter", function(self)
                if self.index then
                    F.ShowTooltips(debuffs.parent, "spell", debuffs.parent.states.displayedUnit, self.index, "HARMFUL")
                elseif self.auraInstanceID then
                    F.ShowTooltips(debuffs.parent, "aura", debuffs.parent.states.displayedUnit, self.auraInstanceID, "HARMFUL")
                end
            end)

            debuffs[i]:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            -- https://warcraft.wiki.gg/wiki/API_ScriptRegion_EnableMouse
            if not debuffs.enableBlacklistShortcut then
                debuffs[i]:SetMouseClickEnabled(false)
            end
        else
            debuffs[i]:SetScript("OnEnter", nil)
            debuffs[i]:SetScript("OnLeave", nil)
            if debuffs.enableBlacklistShortcut then
                debuffs[i]:SetMouseMotionEnabled(false)
            else
                debuffs[i]:EnableMouse(false)
            end
        end
    end
end

-- 启用/禁用 Debuff 黑名单快捷键功能。
-- 开启时绑定 OnMouseUp：按住 Ctrl+Alt+右键点击 Debuff 图标将对应 spellId 加入黑名单，
-- 随后触发 UpdateIndicators 事件通知所有布局刷新，并重新加载指示器选项。
-- 关闭时清除脚本并恢复鼠标状态。
local function Debuffs_EnableBlacklistShortcut(debuffs, enabled)
    debuffs.enableBlacklistShortcut = enabled

    for i = 1, 10 do
        if enabled then
            debuffs[i]:SetScript("OnMouseUp", function(self, button, isInside)
                if button == "RightButton" and isInside and IsLeftAltKeyDown() and IsLeftControlKeyDown()
                    and self.spellId and not F.TContains(CellDB["debuffBlacklist"], self.spellId) then
                    -- print msg
                    local name, icon = F.GetSpellInfo(self.spellId)
                    if name and icon then
                        F.Print(L["Added |T%d:0|t|cFFFF3030%s(%d)|r into debuff blacklist."]:format(icon, name, self.spellId))
                    end
                    -- update db
                    tinsert(CellDB["debuffBlacklist"], self.spellId)
                    Cell.vars.debuffBlacklist = F.ConvertTable(CellDB["debuffBlacklist"])
                    Cell.Fire("UpdateIndicators", Cell.vars.currentLayout, "", "debuffBlacklist")
                    -- refresh
                    F.ReloadIndicatorOptions(Cell.defaults.indicatorIndices.debuffs)
                end
            end)
        else
            debuffs[i]:SetScript("OnMouseUp", nil)
            if debuffs.showTooltip then
                debuffs[i]:SetMouseClickEnabled(false)
            else
                debuffs[i]:EnableMouse(false)
            end
        end
    end
end

-- 创建 Debuff 指示器容器，预创建 10 个 Aura_BarIcon 子图标。
-- 每个子图标的 SetCooldown 被重写以支持 isBigDebuff 参数：
--   当 isBigDebuff 为 true 时使用 bigSize，否则使用 normalSize。
function I.CreateDebuffs(parent)
    local debuffs = CreateFrame("Frame", parent:GetName().."DebuffParent", parent.widgets.indicatorFrame)
    parent.indicators.debuffs = debuffs
    debuffs:Hide()
    debuffs.parent = parent

    debuffs._SetSize = debuffs.SetSize
    debuffs.SetSize = Debuffs_SetSize
    debuffs.UpdateSize = Debuffs_UpdateSize
    debuffs.SetFont = Debuffs_SetFont

    debuffs.hAlignment = ""
    debuffs.vAlignment = ""
    debuffs._SetPoint = debuffs.SetPoint
    debuffs.SetPoint = Debuffs_SetPoint
    debuffs.SetOrientation = Debuffs_SetOrientation

    debuffs.ShowDuration = I.Cooldowns_ShowDuration
    debuffs.ShowAnimation = I.Cooldowns_ShowAnimation
    debuffs.UpdatePixelPerfect = I.Cooldowns_UpdatePixelPerfect

    debuffs.ShowTooltip = Debuffs_ShowTooltip
    debuffs.EnableBlacklistShortcut = Debuffs_EnableBlacklistShortcut

    for i = 1, 10 do
        local name = parent:GetName().."Debuff"..i
        local frame = I.CreateAura_BarIcon(name, debuffs)
        tinsert(debuffs, frame)

        frame._SetCooldown = frame.SetCooldown
        function frame:SetCooldown(start, duration, debuffType, texture, count, refreshing, isBigDebuff)
            frame:_SetCooldown(start, duration, debuffType, texture, count, refreshing)
            if isBigDebuff then
                P.Size(frame, debuffs.bigSize[1], debuffs.bigSize[2])
            else
                P.Size(frame, debuffs.normalSize[1], debuffs.normalSize[2])
            end
        end
    end
end

-------------------------------------------------
-- CreateDispels
-- 可驱散 Debuff 指示器：最多显示 5 个图标（按 Magic/Curse/Disease/Poison/Bleed 顺序）。
-- 支持多种高亮模式（gradient / gradient-half / entire / current / current+），
-- 通过 dispelOrder 优先级列表遍历驱散类型，并利用 Midnight API 获取光环实际颜色。
-------------------------------------------------
-- 设置驱散图标尺寸。水平排列时图标半重叠（offset = width/2），垂直排列时类似。
local function Dispels_SetSize(self, width, height)
    self.width = width
    self.height = height

    self:_SetSize(width, height)
    for i = 1, 5 do
        self[i]:SetSize(width, height)
    end

    if self._orientation then
        self:SetOrientation(self._orientation)
    else
        self:UpdateSize()
    end
end

local function Dispels_UpdateSize(self, iconsShown)
    if not (self.orientation and self.width and self.height) then return end

    local width, height = self.width, self.height
    if iconsShown then -- SetDispels
        if self.orientation == "horizontal"  then
            width = self.width + (iconsShown - 1) * floor(self.width / 2)
            height = self.height
        else
            width = self.width
            height = self.height + (iconsShown - 1) * floor(self.height / 2)
        end
    else
        for i = 1, 5 do
            if self[i]:IsShown() then
                if self.orientation == "horizontal"  then
                    width = self.width + (i - 1) * floor(self.width / 2)
                    height = self.height
                else
                    width = self.width
                    height = self.height + (i - 1) * floor(self.height / 2)
                end
            else
                break
            end
        end
    end

    self:_SetSize(width, height)
end

-- 驱散类型优先级顺序：魔法 > 诅咒 > 疾病 > 中毒 > 流血。
-- SetDispels 按此顺序遍历，只显示需高亮的类型。
local dispelOrder = {"Magic", "Curse", "Disease", "Poison", "Bleed"}
-- 核心函数：根据 dispelTypes 表决定显示哪些图标以及高亮颜色。
-- dispelTypes 结构: { Magic = true/false/{highlight=true, auraInstanceID=n}, Curse = ..., ... }
-- Midnight 12.0.0+: 优先通过 auraInstanceID 获取光环实际颜色（I.GetAuraDispelColor），
--   因为同一驱散类型的不同光环可能有不同颜色（暴雪 C 引擎支持）。
--   同时在全单元上覆盖一层 color wash 纹理（glow）作为全局可见性提示。
local function Dispels_SetDispels(self, dispelTypes)
    local r, g, b = 0, 0, 0
    local found

    self.highlight:Hide()

    local i = 0
    for _, dispelType in ipairs(dispelOrder) do
        local info = dispelTypes[dispelType]
        local showHighlight = (type(info) == "table" and info.highlight) or (type(info) == "boolean" and info)
        local auraID = type(info) == "table" and info.auraInstanceID or nil
        if showHighlight then
            if not found and self.highlightType ~= "none" and dispelType then
                found = true
                -- Midnight 12.0.0+: Blizzard C-engine API (Grid2/VuhDo pattern)
                if auraID then
                    local cr, cg, cb = I.GetAuraDispelColor(auraID)
                    if cr then
                        r, g, b = cr, cg, cb
                    else
                        r, g, b = I.GetDebuffTypeColor(dispelType)
                    end
                else
                    r, g, b = I.GetDebuffTypeColor(dispelType)
                end
                if self.highlightType == "entire" then
                    self.highlight:SetTexture(Cell.vars.whiteTexture)
                    self.highlight:SetVertexColor(r, g, b, 0.5)
                elseif self.highlightType == "current" or self.highlightType == "current+" then
                    self.highlight:SetTexture(Cell.vars.texture)
                    self.highlight:SetVertexColor(r, g, b, 1)
                elseif self.highlightType == "gradient" or self.highlightType == "gradient-half" then
                    self.highlight:SetTexture(Cell.vars.whiteTexture)
                    self.highlight:SetGradient("VERTICAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 0))
                end
                self.highlight:Show()
            end
            if self.showIcons then
                i = i + 1
                self[i]:SetDispel(dispelType)
            end
        end
    end

    -- Full-cell color wash on midLevelFrame (above health bar, always visible)
    if found then
        self.glow:SetColorTexture(r, g, b, 0.45)
        self.glow:Show()
    else
        self.glow:Hide()
    end

    self:UpdateSize(i)

    -- hide unused
    for j = i+1, 5 do
        self[j]:Hide()
    end
end

local function Dispels_SetDispel_Blizzard(self, dispelType)
    self:SetTexture("Interface\\AddOns\\Cell\\Media\\Debuffs\\"..dispelType)
    self:Show()
end

local function Dispels_SetDispel_Rhombus(self, dispelType)
    self:SetTexture("Interface\\AddOns\\Cell\\Media\\Debuffs\\Rhombus")
    self:SetVertexColor(I.GetDebuffTypeColor(dispelType))
    self:Show()
end

local function Dispels_SetIconStyle(self, style)
    self.showIcons = style ~= "none"
    for i = 1, 5 do
        if style == "rhombus" then
            self[i].SetDispel = Dispels_SetDispel_Rhombus
        else -- blizzard
            self[i].SetDispel = Dispels_SetDispel_Blizzard
            self[i]:SetVertexColor(1, 1, 1, 1)
        end
    end
end

--! SetSize must be invoked before this
local function Dispels_SetOrientation(self, orientation)
    self._orientation = orientation
    local point, x, y
    if orientation == "left-to-right" then
        point = "TOPLEFT"
        x = floor(self.width / 2)
        y = 0
        self.orientation = "horizontal"
    elseif orientation == "right-to-left" then
        point = "TOPRIGHT"
        x = -floor(self.width / 2)
        y = 0
        self.orientation = "horizontal"
    elseif orientation == "top-to-bottom" then
        point = "TOPLEFT"
        x = 0
        y = -floor(self.height / 2)
        self.orientation = "vertical"
    elseif orientation == "bottom-to-top" then
        point = "BOTTOMLEFT"
        x = 0
        y = floor(self.height / 2)
        self.orientation = "vertical"
    end

    for i = 1, 5 do
        self[i]:ClearAllPoints()
        if i == 1 then
            self[i]:SetPoint(point)
        else
            self[i]:SetPoint(point, self[i-1], point, x, y)
        end
    end

    self:UpdateSize()
end

-- 更新驱散高亮模式。支持 6 种模式：
--   "none"           - 无高亮
--   "gradient"       - 整个血量条渐变（从上到下不透明->透明）
--   "gradient-half"  - 血量条左半渐变（从左到右不透明->透明）
--   "entire"         - 整个血量条半透明覆盖（alpha 0.5）
--   "current"        - 覆盖当前血量区域（紧跟 StatusBar 纹理，drawLayer -7）
--   "current+"       - 同 current，但使用 ADD 混合模式产生发光效果
local function Dispels_UpdateHighlight(self, highlightType)
    self.highlightType = highlightType
    self.highlight:SetBlendMode("BLEND")

    if highlightType == "none" then
        self.highlight:Hide()
    elseif highlightType == "gradient" then
        -- self.highlight:SetParent(self.parent.widgets.indicatorFrame)
        self.highlight:ClearAllPoints()
        self.highlight:SetAllPoints(self.parent.widgets.healthBar)
        self.highlight:SetTexture(Cell.vars.whiteTexture)
        self.highlight:SetDrawLayer("ARTWORK", 0)
    elseif highlightType == "gradient-half" then
        -- self.highlight:SetParent(self.parent.widgets.indicatorFrame)
        self.highlight:ClearAllPoints()
        self.highlight:SetPoint("BOTTOMLEFT", self.parent.widgets.healthBar)
        self.highlight:SetPoint("TOPRIGHT", self.parent.widgets.healthBar, "RIGHT")
        self.highlight:SetTexture(Cell.vars.whiteTexture)
        self.highlight:SetDrawLayer("ARTWORK", 0)
    elseif highlightType == "entire" then
        -- self.highlight:SetParent(self.parent.widgets.indicatorFrame)
        self.highlight:ClearAllPoints()
        self.highlight:SetAllPoints(self.parent.widgets.healthBar)
        self.highlight:SetTexture(Cell.vars.whiteTexture)
        self.highlight:SetDrawLayer("ARTWORK", 0)
    elseif highlightType == "current" then
        -- self.highlight:SetParent(self.parent.widgets.healthBar)
        self.highlight:ClearAllPoints()
        self.highlight:SetAllPoints(self.parent.widgets.healthBar:GetStatusBarTexture())
        self.highlight:SetTexture(Cell.vars.texture)
        self.highlight:SetDrawLayer("ARTWORK", -7)
    elseif highlightType == "current+" then
        -- self.highlight:SetParent(self.parent.widgets.healthBar)
        self.highlight:ClearAllPoints()
        self.highlight:SetAllPoints(self.parent.widgets.healthBar:GetStatusBarTexture())
        self.highlight:SetTexture(Cell.vars.texture)
        self.highlight:SetDrawLayer("ARTWORK", -7)
        self.highlight:SetBlendMode("ADD")
    end
end

-- 创建驱散指示器容器。
-- 包含两层纹理：
--   highlight - 血量条上的高亮覆盖纹理（创建在 midLevelFrame 上，位于血量条上方但低于指示器）
--   glow      - 全单元 color wash 纹理（创建在 midLevelFrame 上，drawLayer -7，覆盖整个单元）
-- OnHide 时同时隐藏两层纹理。
function I.CreateDispels(parent)
    local dispels = CreateFrame("Frame", parent:GetName().."DispelParent", parent.widgets.indicatorFrame)
    parent.indicators.dispels = dispels
    dispels.parent = parent
    dispels:Hide()

    dispels:SetScript("OnHide", function()
        dispels.highlight:Hide()
        dispels.glow:Hide()
    end)

    -- Health bar highlight texture (original Cell design — "gradient-half" etc.)
    -- 血量条高亮覆盖纹理：创建在 midLevelFrame 上，位于血量条上方、指示器下方
    dispels.highlight = parent.widgets.midLevelFrame:CreateTexture(parent:GetName().."DispelHighlight")
    dispels.highlight:Hide()

    -- Full-cell color wash texture on midLevelFrame (above health bar, below indicators)
    dispels.glow = parent.widgets.midLevelFrame:CreateTexture(parent:GetName().."DispelGlow", "ARTWORK", nil, -7)
    dispels.glow:SetAllPoints(parent)
    dispels.glow:SetBlendMode("BLEND")
    dispels.glow:Hide()

    dispels._SetSize = dispels.SetSize
    dispels.SetSize = Dispels_SetSize
    dispels.UpdateSize = Dispels_UpdateSize
    dispels.SetDispels = Dispels_SetDispels
    dispels.UpdateHighlight = Dispels_UpdateHighlight
    dispels.SetIconStyle = Dispels_SetIconStyle
    dispels.SetOrientation = Dispels_SetOrientation

    for i = 1, 5 do
        local icon = dispels:CreateTexture(parent:GetName().."Dispel"..i, "ARTWORK")
        tinsert(dispels, icon)
        icon:Hide()

        icon:SetDrawLayer("ARTWORK", 6-i)
        icon.SetDispel = Dispels_SetDispel_Blizzard
    end
end

-------------------------------------------------
-- CreateRaidDebuffs
-- 团队副本 Debuff 指示器：根据当前区域和首领战 ID 动态加载需要高亮的 debuff 列表。
-- 核心数据流：Cell.LoadAreaDebuffs → RaidDebuffsChanged 回调 → currentAreaDebuffs 表更新 →
--              GetDebuffOrder / GetDebuffGlow / IsDebuffUseElapsedTime 查询。
-- 事件驱动：ENCOUNTER_START/END 切换 currentEncounterID（首领战列表 vs 区域全局列表）。
-- Midnight 保护：spellId/spellName/count 可能为 secret value，查询和比较前先检查。
-------------------------------------------------
-- 当前区域的 Debuff 配置数据（来自 RaidDebuffs/ 目录下的数据文件）。
-- 结构: { [spellId] = {order, condition, glowCondition, ...}, ... }
local currentAreaDebuffs = {}
-- 当前活跃的首领战 ID（nil 表示无首领战，加载区域全局列表）
local currentEncounterID -- active boss encounter ID (nil = no boss)

-- 全局事件监听 Frame，只在 ENCOUNTER_START/END 和 PLAYER_ENTERING_WORLD 时更新缓存
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")

-- 根据当前区域（和可选的首领战 ID）刷新 currentAreaDebuffs 缓存。
-- instanceName 参数用于 RaidDebuffsChanged 回调的过滤：仅当变化涉及当前区域时才更新。
local function UpdateDebuffsForCurrentZone(instanceName)
    wipe(currentAreaDebuffs)
    local iName = F.GetInstanceName()
    if iName == "" then return end

    if iName == instanceName or instanceName == nil then
        currentAreaDebuffs = F.GetDebuffList(iName, currentEncounterID)
        F.Debug("|cffff77AARaidDebuffsChanged:|r", iName, currentEncounterID and ("boss:"..currentEncounterID) or "all")
    end
end
-- 注册 RaidDebuffsChanged 回调：当 Cell.LoadAreaDebuffs 更新区域 debuff 数据时触发
Cell.RegisterCallback("RaidDebuffsChanged", "UpdateDebuffsForCurrentZone", UpdateDebuffsForCurrentZone)
-- 事件处理脚本：
--   ENCOUNTER_START - 记录首领战 ID，加载该首领专属 debuff 列表
--   ENCOUNTER_END   - 清除首领战 ID，恢复为区域全局 debuff 列表
--   PLAYER_ENTERING_WORLD - 进入新区域时重置首领追踪并加载全局列表
eventFrame:SetScript("OnEvent", function(_, event, encounterID)
    if event == "ENCOUNTER_START" then
        currentEncounterID = encounterID
        UpdateDebuffsForCurrentZone()
    elseif event == "ENCOUNTER_END" then
        currentEncounterID = nil
        UpdateDebuffsForCurrentZone()
    else
        -- PLAYER_ENTERING_WORLD: reset boss tracking
        currentEncounterID = nil
        UpdateDebuffsForCurrentZone()
    end
end)

-- 条件检查函数：比较 currentValue 和 checkedValue 是否满足 operator 关系。
-- 支持 = / > / >= / < / <= / ~= 六种比较运算符。
-- Midnight 12.0.0+: debuff 的 applications（层数）可能是 secret value，
--   在比较前使用 issecretvalue 检查，若任一值为 secret 则直接返回 nil（不满足）。
local function CheckCondition(operator, checkedValue, currentValue)
    -- Midnight 12.0.0+: applications (count) may be secret even when spellId is not;
    -- comparisons on secret values throw errors
    if issecretvalue and (issecretvalue(currentValue) or issecretvalue(checkedValue)) then return end
    if operator == "=" then
        if currentValue == checkedValue then return true end
    elseif operator == ">" then
        if currentValue > checkedValue then return true end
    elseif operator == ">=" then
        if currentValue >= checkedValue then return true end
    elseif operator == "<" then
        if currentValue < checkedValue then return true end
    elseif operator == "<=" then
        if currentValue <= checkedValue then return true end
    else -- ~=
        if currentValue ~= checkedValue then return true end
    end
end

-- 查询指定 spell 的配置排序索引（order），用于决定 RaidDebuff 图标的显示优先级。
-- 先按 spellId 查表，失败后按 spellName 查表。同时检查 condition 条件（Stack 层数比较）。
-- Midnight 12.0.0+: spellId/spellName 可能为 secret value，首先分别检查 issecretvalue，
--   只有非 secret 的键才用于查表。双重 "if not t then return end" 是防御性代码。
function I.GetDebuffOrder(spellName, spellId, count)
    -- Midnight 12.0.0+: spellId/spellName may be secret; cannot use as table key.
    -- Only bail if BOTH are secret — a non-secret spellId or spellName allows lookup.
    local idSecret = issecretvalue and issecretvalue(spellId)
    local nameSecret = issecretvalue and issecretvalue(spellName)
    local t
    if not idSecret then t = currentAreaDebuffs[spellId] end
    if not t and not nameSecret then t = currentAreaDebuffs[spellName] end
    if not t then return end
    if not t then return end

    -- check condition
    local show
    if t["condition"][1] == "Stack" then
        show = CheckCondition(t["condition"][2], t["condition"][3], count)
    else -- no condition
        show = true
    end

    if show then return t["order"] end
end

-- 查询指定 spell 的发光配置（glowType / glowOptions）。
-- 先检查 glowCondition（可选层数条件），满足时返回发光类型和参数，否则返回 "None"。
-- Midnight 保护逻辑同 GetDebuffOrder。
function I.GetDebuffGlow(spellName, spellId, count)
    -- Midnight 12.0.0+: spellId/spellName may be secret; cannot use as table key.
    -- Only bail if BOTH are secret — a non-secret spellId or spellName allows lookup.
    local idSecret = issecretvalue and issecretvalue(spellId)
    local nameSecret = issecretvalue and issecretvalue(spellName)
    local t
    if not idSecret then t = currentAreaDebuffs[spellId] end
    if not t and not nameSecret then t = currentAreaDebuffs[spellName] end
    if not t then return end
    if not t then return end

    local showGlow
    if t["glowCondition"] then
        if t["glowCondition"][1] == "Stack" then
            showGlow = CheckCondition(t["glowCondition"][2], t["glowCondition"][3], count)
        end
    else
        showGlow = true
    end

    if showGlow then
        return t["glowType"], t["glowOptions"]
    else
        return "None", nil
    end
end

-- 查询指定 spell 是否应使用"已过时间"（elapsed）而非"剩余时间"来显示冷却。
-- 某些 debuff 需要显示已持续时间（如某些首领机制计时），而非默认的冷却倒计时。
-- Midnight 保护逻辑同上。
function I.IsDebuffUseElapsedTime(spellName, spellId)
    -- Midnight 12.0.0+: spellId/spellName may be secret; cannot use as table key.
    -- Only bail if BOTH are secret — a non-secret spellId or spellName allows lookup.
    local idSecret = issecretvalue and issecretvalue(spellId)
    local nameSecret = issecretvalue and issecretvalue(spellName)
    local t
    if not idSecret then t = currentAreaDebuffs[spellId] end
    if not t and not nameSecret then t = currentAreaDebuffs[spellName] end
    if not t then return end
    if not t then return end

    return t["useElapsedTime"]
end

-- 显示 RaidDebuff 发光效果。支持四种发光类型（由 LibCustomGlow 提供）：
--   "Normal" - 按钮发光（ButtonGlow）
--   "Pixel"  - 像素边框发光（PixelGlow）
--   "Shine"  - 自动施法发光（AutoCastGlow）
--   "Proc"   - 触发发光（ProcGlow）
-- noHiding 参数为 true 时跳过停止其他发光类型的步骤（用于同类型发光叠加更新）。
local function RaidDebuffs_ShowGlow(self, glowType, glowOptions, noHiding)
    if glowType == "Normal" then
        if not noHiding then
            LCG.PixelGlow_Stop(self.parent)
            LCG.AutoCastGlow_Stop(self.parent)
            LCG.ProcGlow_Stop(self.parent)
        end
        LCG.ButtonGlow_Start(self.parent, glowOptions[1])
    elseif glowType == "Pixel" then
        if not noHiding then
            LCG.ButtonGlow_Stop(self.parent)
            LCG.AutoCastGlow_Stop(self.parent)
            LCG.ProcGlow_Stop(self.parent)
        end
        -- color, N, frequency, length, thickness
        LCG.PixelGlow_Start(self.parent, glowOptions[1], glowOptions[2], glowOptions[3], glowOptions[4], glowOptions[5])
    elseif glowType == "Shine" then
        if not noHiding then
            LCG.ButtonGlow_Stop(self.parent)
            LCG.PixelGlow_Stop(self.parent)
            LCG.ProcGlow_Stop(self.parent)
        end
        -- color, N, frequency, scale
        LCG.AutoCastGlow_Start(self.parent, glowOptions[1], glowOptions[2], glowOptions[3], glowOptions[4])
    elseif glowType == "Proc" then
        if not noHiding then
            LCG.ButtonGlow_Stop(self.parent)
            LCG.PixelGlow_Stop(self.parent)
            LCG.AutoCastGlow_Stop(self.parent)
        end
        -- color, duration
        LCG.ProcGlow_Start(self.parent, {color=glowOptions[1], duration=glowOptions[2], startAnim=false})
    else
        LCG.ButtonGlow_Stop(self.parent)
        LCG.PixelGlow_Stop(self.parent)
        LCG.AutoCastGlow_Stop(self.parent)
        LCG.ProcGlow_Stop(self.parent)
    end
end

-- 发光停止函数的查找表，按 glowType 分发到对应的 LibCustomGlow Stop 方法
local hiders = {
    ["Normal"] = LCG.ButtonGlow_Stop,
    ["Pixel"] = LCG.PixelGlow_Stop,
    ["Shine"] = LCG.AutoCastGlow_Stop,
    ["Proc"] = LCG.ProcGlow_Stop,
}

-- 隐藏 RaidDebuff 发光效果。
-- 若未指定 glowType 则停止所有类型的发光；否则仅停止指定类型。
local function RaidDebuffs_HideGlow(self, glowType)
    if not glowType then
        for _, stop in pairs(hiders) do
            stop(self.parent)
        end
    else
        hiders[glowType](self.parent)
    end
end

local function RaidDebuffs_ShowTooltip(raidDebuffs, show)
    for i = 1, 3 do
        if show then
            raidDebuffs[i]:SetScript("OnEnter", function(self)
                if self.index then
                    F.ShowTooltips(raidDebuffs.parent, "spell", raidDebuffs.parent.states.displayedUnit, self.index, "HARMFUL")
                elseif self.auraInstanceID then
                    F.ShowTooltips(raidDebuffs.parent, "aura", raidDebuffs.parent.states.displayedUnit, self.auraInstanceID, "HARMFUL")
                end
            end)
            raidDebuffs[i]:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        else
            raidDebuffs[i]:SetScript("OnEnter", nil)
            raidDebuffs[i]:SetScript("OnLeave", nil)
            raidDebuffs[i]:EnableMouse(false)
        end
    end
end

-- 创建 RaidDebuffs 指示器容器。预创建 3 个带边框的图标（Aura_BorderIcon）。
-- 使用 hooksecurefunc 钩住 Hide() 方法确保隐藏时清理所有发光效果（避免发光残留）。
-- 使用带间距（WithSpacing）版本的共享函数以在图标间留出视觉间隔。
function I.CreateRaidDebuffs(parent)
    local raidDebuffs = CreateFrame("Frame", parent:GetName().."RaidDebuffParent", parent.widgets.indicatorFrame)
    parent.indicators.raidDebuffs = raidDebuffs
    raidDebuffs:Hide()
    raidDebuffs.parent = parent

    hooksecurefunc(raidDebuffs, "Hide", RaidDebuffs_HideGlow)
    -- raidDebuffs:SetScript("OnHide", RaidDebuffs_HideGlow)

    raidDebuffs._SetSize = raidDebuffs.SetSize
    raidDebuffs.SetSize = I.Cooldowns_SetSize
    raidDebuffs.SetBorder = I.Cooldowns_SetBorder
    raidDebuffs.UpdateSize = I.Cooldowns_UpdateSize_WithSpacing
    raidDebuffs.ShowDuration = I.Cooldowns_ShowDuration
    raidDebuffs.SetOrientation = I.Cooldowns_SetOrientation_WithSpacing
    raidDebuffs.SetFont = I.Cooldowns_SetFont
    raidDebuffs.ShowGlow = RaidDebuffs_ShowGlow
    raidDebuffs.HideGlow = RaidDebuffs_HideGlow
    raidDebuffs.UpdatePixelPerfect = I.Cooldowns_UpdatePixelPerfect

    raidDebuffs.ShowTooltip = RaidDebuffs_ShowTooltip

    for i = 1, 3 do
        local frame = I.CreateAura_BorderIcon(parent:GetName().."RaidDebuff"..i, raidDebuffs, 2)
        tinsert(raidDebuffs, frame)
        -- frame:SetScript("OnShow", raidDebuffs.UpdateSize)
        -- frame:SetScript("OnHide", raidDebuffs.UpdateSize)
    end
end

-------------------------------------------------
-- private auras
-- 私有光环（Private Aura）指示器：利用暴雪 10.1+ 的 C_UnitAuras.AddPrivateAuraAnchor API
-- 将私有光环图标直接渲染到指定的 Frame 容器上。私有光环无法通过传统 Aura API 获取，
-- 只能通过此专用锚点系统显示。
-------------------------------------------------
-- 更新私有光环锚点：先移除旧锚点（若存在），再为新 unit 添加锚点。
-- showCountdownFrame / showCountdownNumbers 控制冷却倒计时框和数字的显示。
-- iconInfo 配置图标尺寸和居中锚定方式。
local function PrivateAuras_UpdatePrivateAuraAnchor(self, unit)
    -- remove old
    if self.auraAnchorID then
        C_UnitAuras.RemovePrivateAuraAnchor(self.auraAnchorID)
        self.unit = nil
        self.auraAnchorID = nil
    end

    -- add new
    if unit then
        local _showCountdownFrame, _showCountdownNumbers = true, false
        if type(self.showCountdownFrame) == "boolean" then _showCountdownFrame = self.showCountdownFrame end
        if type(self.showCountdownNumbers) == "boolean" then _showCountdownNumbers = self.showCountdownNumbers end

        self.unit = unit
        self.auraAnchorID = C_UnitAuras.AddPrivateAuraAnchor({
            unitToken = unit,
            auraIndex = 1,
            parent = self,
            isContainer = false,
            showCountdownFrame = _showCountdownFrame,
            showCountdownNumbers = _showCountdownNumbers,
            iconInfo = {
                iconWidth = self:GetWidth(),
                iconHeight = self:GetHeight(),
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = self,
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
            },
            -- durationAnchor = {
            --     point = "BOTTOMRIGHT",
            --     relativeTo = self,
            --     relativePoint = "BOTTOMRIGHT",
            --     offsetX = 0,
            --     offsetY = 0,
            -- },
        })
    end
end

function I.CreatePrivateAuras(parent)
    local privateAuras = CreateFrame("Frame", parent:GetName().."PrivateAuraParent", parent.widgets.indicatorFrame)
    parent.indicators.privateAuras = privateAuras
    privateAuras:Hide()

    privateAuras.UpdatePrivateAuraAnchor = PrivateAuras_UpdatePrivateAuraAnchor
    privateAuras._SetSize = privateAuras.SetSize

    function privateAuras:SetSize(width, height)
        privateAuras:_SetSize(width, height)
        privateAuras:UpdatePrivateAuraAnchor(privateAuras.unit)
    end

    function privateAuras:UpdateOptions(t)
        self.showCountdownFrame = t[1]
        self.showCountdownNumbers = t[2]
        privateAuras:UpdatePrivateAuraAnchor(privateAuras.unit)
    end
end

-------------------------------------------------
-- player raid icon
-- 玩家团队标记指示器（如星星、月亮等）：读取"UI-RaidTargetingIcons"图集。
-- 当玩家被标记为团队目标时显示对应图标。
-------------------------------------------------
function I.CreatePlayerRaidIcon(parent)
    -- local playerRaidIcon = parent.widgets.indicatorFrame:CreateTexture(parent:GetName().."PlayerRaidIcon", "ARTWORK", nil, -7)
    -- parent.indicators.playerRaidIcon = playerRaidIcon
    -- playerRaidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    local playerRaidIcon = CreateFrame("Frame", parent:GetName().."PlayerRaidIcon", parent.widgets.indicatorFrame)
    parent.indicators.playerRaidIcon = playerRaidIcon
    playerRaidIcon.tex = playerRaidIcon:CreateTexture(nil, "ARTWORK")
    playerRaidIcon.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    playerRaidIcon.tex:SetAllPoints(playerRaidIcon)
    playerRaidIcon:Hide()
end

-------------------------------------------------
-- target raid icon
-- 目标团队标记指示器：与 PlayerRaidIcon 使用同一图集，但显示的是目标（target）的团队标记。
-------------------------------------------------
function I.CreateTargetRaidIcon(parent)
    local targetRaidIcon = CreateFrame("Frame", parent:GetName().."TargetRaidIcon", parent.widgets.indicatorFrame)
    parent.indicators.targetRaidIcon = targetRaidIcon
    targetRaidIcon.tex = targetRaidIcon:CreateTexture(nil, "ARTWORK")
    targetRaidIcon.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    targetRaidIcon.tex:SetAllPoints(targetRaidIcon)
    targetRaidIcon:Hide()
end

-------------------------------------------------
-- name text
-- 名字文本指示器：显示单位名称，支持昵称系统、音译、载具名称、
-- 小队编号前缀显示，以及动态文本宽度裁剪。
-- 创建两个 FontString：name（主名称）和 vehicle（载具/宠物主人名称）。
-- 自定义字体 CELL_FONT_NAME 必须设置初始颜色和阴影，否则窗口缩放时阴影会丢失。
-------------------------------------------------
-- 专用于 NameText 的字体实例，必须初始化阴影/颜色属性以防窗口缩放时阴影消失
local font_name = CreateFont("CELL_FONT_NAME")
font_name:SetFont(GameFontNormal:GetFont(), 13, "")
--! NOTE: VERY IMPORTANT, if not set, shadows will DISAPPER when wow window size changed
font_name:SetTextColor(1, 1, 1, 1)
font_name:SetShadowColor(0, 0, 0)
font_name:SetShadowOffset(1, -1)

-- StatusText 和 HealthText 等共用的字体实例，同样的阴影初始化要求
local font_status = CreateFont("CELL_FONT_STATUS")
font_status:SetFont(GameFontNormal:GetFont(), 11, "")
--! NOTE: VERY IMPORTANT, if not set, shadows will DISAPPER when wow window size changed
font_status:SetTextColor(1, 1, 1, 1)
font_status:SetShadowColor(0, 0, 0)
font_status:SetShadowOffset(1, -1)

-- 创建名字文本指示器。包含两个 FontString 子层：name（主名称）和 vehicle（载具/宠物主人名）。
-- OnShow 时将按需联动显示 vehicle 文本。
-- 同时绑定 healthBar 的 OnSizeChanged 事件：血量条尺寸变化时重新计算文本宽度。
function I.CreateNameText(parent)
    local nameText = CreateFrame("Frame", parent:GetName().."NameText", parent.widgets.indicatorFrame)
    parent.indicators.nameText = nameText
    nameText:Hide()

    nameText.name = nameText:CreateFontString(parent:GetName().."NameText_Name", "OVERLAY", "CELL_FONT_NAME")

    nameText.vehicle = nameText:CreateFontString(parent:GetName().."NameText_Vehicle", "OVERLAY", "CELL_FONT_STATUS")
    nameText.vehicle:SetTextColor(0.8, 0.8, 0.8, 1)
    nameText.vehicle:Hide()

    nameText:SetScript("OnShow", function()
        if nameText.vehicleEnabled then
            nameText.vehicle:Show()
        end
    end)
    nameText:SetScript("OnHide", function()
        nameText.vehicle:Hide()
    end)

    -- 设置字体、大小、描边和阴影。阴影开关同时作用于 name 和 vehicle 两个 FontString。
    function nameText:SetFont(font, size, outline, shadow)
        font = F.GetFont(font)

        local flags
        if outline == "None" then
            flags = ""
        elseif outline == "Outline" then
            flags = "OUTLINE"
        else
            flags = "OUTLINE,MONOCHROME"
        end

        nameText.name:SetFont(font, size, flags)
        nameText.vehicle:SetFont(font, size-2, flags)

        if shadow then
            nameText.name:SetShadowOffset(1, -1)
            nameText.name:SetShadowColor(0, 0, 0, 1)
            nameText.vehicle:SetShadowOffset(1, -1)
            nameText.vehicle:SetShadowColor(0, 0, 0, 1)
        else
            nameText.name:SetShadowOffset(0, 0)
            nameText.name:SetShadowColor(0, 0, 0, 0)
            nameText.vehicle:SetShadowOffset(0, 0)
            nameText.vehicle:SetShadowColor(0, 0, 0, 0)
        end
        nameText.shadow = shadow

        nameText:UpdateName()
        if parent.states.inVehicle or nameText.isPreview then
            nameText:UpdateVehicleName()
        end
    end

    nameText._SetPoint = nameText.SetPoint
    -- 重写 SetPoint：覆盖 relativeTo 后同时更新 name 和 vehicle 两个 FontString 的锚点。
    -- vehicle 的锚点根据 name 的垂直对齐（TOP/BOTTOM）决定紧贴在 name 上方或下方。
    function nameText:SetPoint(point, relativeTo, relativePoint, x, y)
        -- override relativeTo
        nameText:_SetPoint(point, relativeTo, relativePoint, x, y)

        -- update name
        nameText.name:ClearAllPoints()
        nameText.name:SetPoint(point)

        -- update vehicle
        local vp, _, vrp, _, vy = nameText.vehicle:GetPoint(1)
        if vp and vrp and vy then
            if string.find(vp, "TOP") then
                vp, vrp = "TOP", "BOTTOM"
            else -- BOTTOM
                vp, vrp = "BOTTOM", "TOP"
            end

            nameText.vehicle:ClearAllPoints()
            if string.find(point, "LEFT") then
                nameText.vehicle:SetPoint(vp.."LEFT", nameText.name, vrp.."LEFT", 0, vy)
            elseif string.find(point, "RIGHT") then
                nameText.vehicle:SetPoint(vp.."RIGHT", nameText.name, vrp.."RIGHT", 0, vy)
            else -- "CENTER"
                nameText.vehicle:SetPoint(vp, nameText.name, vrp, 0, vy)
            end
        end
    end

    -- 更新名称显示。核心逻辑：
    --   1. 玩家单位通过昵称系统获取显示名（Cell.NickTag 或内置昵称表）
    --   2. 非玩家单位直接使用 states.name
    --   3. 若开启音译（Translit），对非 secret 名称进行拉丁转写
    --   4. 小队宠物显示主人的名称（通过 CELL_SHOW_GROUP_PET_OWNER_NAME 控制位置）
    --   5. 团队中显示小队编号前缀（如 "2-名字"）
    -- Midnight 防护：GetText() 可能返回 secret，无法拼接或测试——先检查是否为 secret。
    --   GetWidth/GetHeight 对 secret 文本也返回 secret，回退到父按钮尺寸。
    function nameText:UpdateName()
        local name

        -- supporter rainbow
        -- if nameText.name.rainbow then
        --     nameText.name.updater:SetScript("OnUpdate", nil)
        --     if nameText.name.timer then
        --         nameText.name.timer:Cancel()
        --         nameText.name.timer = nil
        --     end
        -- end

        -- only check nickname for players
        if parent.states.isPlayer then
            if CELL_NICKTAG_ENABLED and Cell.NickTag then
                name = Cell.NickTag:GetNickname(parent.states.name, nil, true)
            end
            name = name or F.GetNickname(parent.states.name, parent.states.fullName)
        else
            name = parent.states.name
        end

        if Cell.loaded and CellDB["general"]["translit"] and not F.IsSecretValue(name) then
            name = LibTranslit:Transliterate(name)
        end

        F.UpdateTextWidth(nameText.name, name, nameText.width, parent.widgets.healthBar)

        if CELL_SHOW_GROUP_PET_OWNER_NAME and parent.isGroupPet then
            local owner = F.GetPlayerUnit(parent.states.unit)
            owner = UnitName(owner)
            if CELL_SHOW_GROUP_PET_OWNER_NAME == "VEHICLE" then
                F.UpdateTextWidth(nameText.vehicle, owner, nameText.width, parent.widgets.healthBar)
            elseif CELL_SHOW_GROUP_PET_OWNER_NAME == "NAME" then
                F.UpdateTextWidth(nameText.name, owner, nameText.width, parent.widgets.healthBar)
            end
        end

        local displayedText = nameText.name:GetText()
        -- Midnight: secret text -> GetText() returns secret, can't concatenate or test
        local hasText = displayedText and not F.IsSecretValue(displayedText)
        if not F.IsSecretValue(parent.states.name) and hasText then
            if nameText.isPreview then
                if nameText.showGroupNumber then
                    nameText.name:SetText("|cffbbbbbb7-|r"..displayedText)
                end
            else
                if IsInRaid() and nameText.showGroupNumber then
                    local raidIndex = UnitInRaid(parent.states.unit)
                    if raidIndex then
                        local subgroup = select(3, GetRaidRosterInfo(raidIndex))
                        nameText.name:SetText("|cffbbbbbb"..subgroup.."-|r"..displayedText)
                    end
                end
            end
        end

        -- Midnight: GetWidth()/GetHeight() return secret when text is secret.
        -- Use parent button dimensions as fallback to keep name visible.
        if not F.IsSecretValue(parent.states.name) then
            nameText:SetSize(nameText.name:GetWidth(), nameText.name:GetHeight())
        else
            nameText:SetSize(parent:GetWidth() - 4, 18)
        end
    end

    -- 更新载具名称（或宠物主人名称）的文本内容及宽度
    function nameText:UpdateVehicleName()
        F.UpdateTextWidth(nameText.vehicle, nameText.isPreview and L["vehicle name"] or UnitName(parent.states.displayedUnit), nameText.width, parent.widgets.healthBar)
    end

    -- 设置载具名称相对于主名称的位置：TOP（上方）/ BOTTOM（下方）/ Hide（隐藏）。
    -- pTable = {position, offsetY}，如 {"TOP", 2} 表示在主名称上方偏移 2 像素。
    function nameText:UpdateVehicleNamePosition(pTable)
        local p = nameText:GetPoint(1) or ""
        if string.find(p, "LEFT") then
            p = "LEFT"
        elseif string.find(p, "RIGHT") then
            p = "RIGHT"
        else -- "CENTER"
            p = ""
        end

        nameText.vehicle:ClearAllPoints()
        if pTable[1] == "TOP" then
            nameText.vehicle:Show()
            nameText.vehicle:SetPoint("BOTTOM"..p, nameText.name, "TOP"..p, 0, pTable[2])
            nameText.vehicleEnabled = true
        elseif pTable[1] == "BOTTOM" then
            nameText.vehicle:Show()
            nameText.vehicle:SetPoint("TOP"..p, nameText.name, "BOTTOM"..p, 0, pTable[2])
            nameText.vehicleEnabled = true
        else -- Hide
            nameText.vehicle:Hide()
            nameText.vehicleEnabled = false
        end
    end

    -- 更新文本最大宽度（血量条宽度），同时刷新 name 和 vehicle 两个文本
    function nameText:UpdateTextWidth(width)
        nameText.width = width

        nameText:UpdateName()

        if parent.states.inVehicle or nameText.isPreview then
            F.UpdateTextWidth(nameText.vehicle, nameText.isPreview and L["Vehicle Name"] or UnitName(parent.states.displayedUnit), width, parent.widgets.healthBar)
        end
    end

    -- 预览模式下的颜色更新：支持 class_color 或自定义颜色
    function nameText:UpdatePreviewColor(color)
        if color[1] == "class_color" then
            nameText.name:SetTextColor(F.GetClassColor(Cell.vars.playerClass))
        else
            nameText.name:SetTextColor(unpack(color[2]))
        end
    end

    function nameText:SetColor(r, g, b)
        nameText.name:SetTextColor(r, g, b)
    end

    function nameText:ShowGroupNumber(show)
        nameText.showGroupNumber = show
        nameText:UpdateName()
    end

    parent.widgets.healthBar:SetScript("OnSizeChanged", function()
        if parent.states.name then
            nameText:UpdateName()

            if parent.states.inVehicle or nameText.isPreview then
                nameText:UpdateVehicleName()
            end
        end
    end)
end

-------------------------------------------------
-- status text
-- 状态文本指示器：显示单位的预设状态标签（如"AFK"、"断开连接"、"死亡"等）。
-- 包含两个 FontString：text（状态文本）和 timer（计时器，如 AFK 时长）。
-- 支持背景渐变着色、文本对齐方式（justify/left/right），以及可选的计时器显示。
-------------------------------------------------
local function StatusText_SetFont(self, font, size, outline, shadow)
    font = F.GetFont(font)

    local flags
    if outline == "None" then
        flags = ""
    elseif outline == "Outline" then
        flags = "OUTLINE"
    else
        flags = "OUTLINE,MONOCHROME"
    end

    self.text:SetFont(font, size, flags)
    self.timer:SetFont(font, size, flags)

    if shadow then
        self.text:SetShadowOffset(1, -1)
        self.text:SetShadowColor(0, 0, 0, 1)
        self.timer:SetShadowOffset(1, -1)
        self.timer:SetShadowColor(0, 0, 0, 1)
    else
        self.text:SetShadowOffset(0, 0)
        self.text:SetShadowColor(0, 0, 0, 0)
        self.timer:SetShadowOffset(0, 0)
        self.timer:SetShadowColor(0, 0, 0, 0)
    end
    self.shadow = shadow

    self:SetHeight(self.text:GetHeight()+P.Scale(1)*2)
end

local function StatusText_GetStatus(self)
    return self.status
end

-- 设置状态文本并应用对应颜色。若状态为 nil 或颜色表未初始化则隐藏整个指示器。
local function StatusText_SetStatus(self, status)
    -- print("status: " .. (status or "nil"))
    self.status = status
    if status and self.colors then
        self.text:SetText(L[status])
        self.text:SetTextColor(unpack(self.colors[status]))
        self.timer:SetTextColor(unpack(self.colors[status]))
        self:SetHeight(self.text:GetHeight()+P.Scale(1)*2)
    else
        self:Hide()
    end
end

local function StatusText_SetColors(self, colors)
    self.colors = colors
end

local function StatusText_SetShowTimer(self, show)
    self.showTimer = show
end

local function StatusText_ShowBackground(self, show)
    if show then
        self.bg:Show()
    else
        self.bg:Hide()
    end
end

-- 设置状态文本位置和对齐方式。
-- justify 控制文本和计时器的分布：
--   "justify" - 左右分散对齐（文本左对齐，计时器右对齐）
--   "left"    - 左对齐（计时器在文本右侧）
--   "right"   - 右对齐（计时器在文本左侧）
-- 背景渐变和文本锚点随 justify 模式相应调整。
local function StatusText_SetPosition(self, point, yOffset, justify)
    self:ClearAllPoints()
    self:SetPoint("LEFT", self.parent.widgets.healthBar)
    self:SetPoint("RIGHT", self.parent.widgets.healthBar)
    self:SetPoint(point, self.parent.widgets.healthBar, 0, P.Scale(yOffset))

    self.text:ClearAllPoints()
    self.timer:ClearAllPoints()
    if justify == "justify" then
        self.text:SetPoint("LEFT")
        self.text:SetJustifyH("LEFT")
        self.timer:SetPoint("RIGHT")
        self.timer:SetJustifyH("RIGHT")
        self.bg:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.777), CreateColor(0, 0, 0, 0))
    elseif justify == "left" then
        self.text:SetPoint("LEFT")
        self.text:SetJustifyH("LEFT")
        self.timer:SetPoint("LEFT", self.text, "RIGHT", 2, 0)
        self.timer:SetJustifyH("LEFT")
        self.bg:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.777), CreateColor(0, 0, 0, 0))
    else
        self.text:SetPoint("RIGHT")
        self.text:SetJustifyH("RIGHT")
        self.timer:SetPoint("RIGHT", self.text, "LEFT", -2, 0)
        self.timer:SetJustifyH("RIGHT")
        self.bg:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.777))
    end

    self:SetHeight(self.text:GetHeight()+P.Scale(1)*2)
end

-- 全局缓存表：记录每个 guid 的状态开始时间（GetTime()），用于 StatusText 计时器计算 AFK 等时长。
-- 当角色状态结束时（HideTimer 带 reset=true）清除对应缓存条目。
local startTimeCache = {}
-- 显示计时器：创建 C_Timer.NewTicker（每秒更新）动态显示状态持续时间。
-- Midnight 12.0.0+: NPC/Boss 单位的 guid 可能为 secret value，需先检查 issecretvalue。
local function StatusText_ShowTimer(self)
    if not self.showTimer then
        self:HideTimer(true)
        return
    end

    self.timer:Show()

    -- Midnight 12.0.0+: guid may be secret for NPC/boss units
    local showGuid = self.parent.states.guid
    if not (issecretvalue and issecretvalue(showGuid)) then
        if showGuid and not startTimeCache[showGuid] then startTimeCache[showGuid] = GetTime() end
    end

    self.ticker = C_Timer.NewTicker(1, function()
        if not self.parent.states.guid and self.parent.states.unit then -- ElvUI AFK mode
            self.parent.states.guid = UnitGUID(self.parent.states.unit)
        end
        local tickGuid = self.parent.states.guid
        if tickGuid and not (issecretvalue and issecretvalue(tickGuid)) and startTimeCache[tickGuid] then
            self.timer:SetFormattedText(F.FormatTime(GetTime() - startTimeCache[tickGuid]))
        else
            self.timer:SetText("")
        end
    end)
end

local function StatusText_HideTimer(self, reset)
    self.timer:Hide()
    self.timer:SetText("")
    if reset then
        if self.ticker then self.ticker:Cancel() end
        -- Midnight 12.0.0+: guid may be secret for NPC/boss units
        local guid = self.parent.states.guid
        if guid and not (issecretvalue and issecretvalue(guid)) then
            startTimeCache[guid] = nil
        end
    end
end

function I.CreateStatusText(parent)
    local statusText = CreateFrame("Frame", parent:GetName().."StatusText", parent.widgets.indicatorFrame)
    parent.indicators.statusText = statusText
    statusText:SetIgnoreParentAlpha(true)
    statusText:Hide()

    statusText.parent = parent

    statusText.bg = statusText:CreateTexture(nil, "ARTWORK")
    statusText.bg:SetTexture(Cell.vars.whiteTexture)
    -- statusText.bg:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.777), CreateColor(0, 0, 0, 0))
    statusText.bg:SetAllPoints(statusText)

    local text = statusText:CreateFontString(nil, "ARTWORK", "CELL_FONT_STATUS")
    statusText.text = text

    local timer = statusText:CreateFontString(nil, "ARTWORK", "CELL_FONT_STATUS")
    statusText.timer = timer

    statusText.GetStatus = StatusText_GetStatus
    statusText.SetStatus = StatusText_SetStatus
    statusText.SetColors = StatusText_SetColors
    statusText.SetPosition = StatusText_SetPosition
    statusText.SetFont = StatusText_SetFont
    statusText.SetShowTimer = StatusText_SetShowTimer
    statusText.ShowBackground = StatusText_ShowBackground
    statusText.ShowTimer = StatusText_ShowTimer
    statusText.HideTimer = StatusText_HideTimer
end

-------------------------------------------------
-- health text
-- 血量文本指示器：高度可配置的格式化系统，支持多种显示格式组合。
--
-- 核心架构：
--   1. formatter 表：包含所有格式的"普通路径"函数（标准 Lua 运算）
--   2. midnightFormatter 表：Midnight 专用的"secret 安全路径"函数（通过 HealPredictionCalculator C 方法）
--   3. BuildPattern：将用户配置转换为可格式化的模式字符串（color + delimiter + "%s" + suffix）
--   4. HealthText_SetValue：根据是否为 secret value 分发到对应路径
--
-- 支持的格式：health / deficit / effective / shields / healabsorbs，各有完整/简短/百分比变体。
-- 注意：effective_* 在 Midnight 路径下退化到 health_*（无对应的 calculator 方法），
--   shields_percent / healabsorbs_percent 退化到简短绝对值。
-------------------------------------------------
local sub = string.sub
local gsub = string.gsub
local find = string.find
local format = string.format
local tinsert = table.insert

-- 普通（非 Midnight）格式化函数查找表。
-- key 为格式名（如 "health"、"deficit"、"effective" 等），value 为对应的格式化函数。
-- 每个函数接受 (pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs) 参数。
-- hideIfEmptyOrFull 为 true 时：血量为 0 或满血返回空字符串（隐藏该段文本）。
local formatter = {
    ["none"] = function()
        return ""
    end,

    -- health
    ["health"] = function(pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs)
        if hideIfEmptyOrFull and (health == 0 or health == maxHealth) then return "" end
        return pattern:format(health)
    end,
    ["health_short"] = function(pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs)
        if hideIfEmptyOrFull and (health == 0 or health == maxHealth) then return "" end
        return pattern:format(F.FormatNumber(health))
    end,
    ["health_percent"] = function(pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs)
        if hideIfEmptyOrFull and (health == 0 or health == maxHealth) then return "" end
        return pattern:format(F.Round(health / maxHealth * 100))
    end,
    ["deficit"] = function(pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs)
        if hideIfEmptyOrFull and (health == 0 or health == maxHealth) then return "" end
        return pattern:format(health - maxHealth)
    end,
    ["deficit_short"] = function(pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs)
        if hideIfEmptyOrFull and (health == 0 or health == maxHealth) then return "" end
        return pattern:format(F.FormatNumber(health - maxHealth))
    end,
    ["deficit_percent"] = function(pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs)
        if hideIfEmptyOrFull and (health == 0 or health == maxHealth) then return "" end
        return pattern:format(F.Round((health - maxHealth) / maxHealth * 100))
    end,

    -- effective health
    ["effective"] = function(pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs)
        if hideIfEmptyOrFull and (health == 0 or health == maxHealth) and absorbs == 0 and healAbsorbs == 0 then return "" end
        return pattern:format(health + absorbs - healAbsorbs)
    end,
    ["effective_short"] = function(pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs)
        if hideIfEmptyOrFull and (health == 0 or health == maxHealth) and absorbs == 0 and healAbsorbs == 0 then return "" end
        return pattern:format(F.FormatNumber(health + absorbs - healAbsorbs))
    end,
    ["effective_percent"] = function(pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs)
        if hideIfEmptyOrFull and (health == 0 or health == maxHealth) and absorbs == 0 and healAbsorbs == 0 then return "" end
        return pattern:format(F.Round((health + absorbs - healAbsorbs) / maxHealth * 100))
    end,

    -- shields
    ["shields"] = function(pattern, health, maxHealth, absorbs, healAbsorbs)
        if absorbs == 0 then return "" end
        return pattern:format(absorbs)
    end,
    ["shields_short"] = function(pattern, health, maxHealth, absorbs, healAbsorbs)
        if absorbs == 0 then return "" end
        return pattern:format(F.FormatNumber(absorbs))
    end,
    ["shields_percent"] = function(pattern, health, maxHealth, absorbs, healAbsorbs)
        if absorbs == 0 then return "" end
        return pattern:format(F.Round(absorbs / maxHealth * 100))
    end,

    -- heal absorbs
    ["healabsorbs"] = function(pattern, health, maxHealth, absorbs, healAbsorbs)
        if healAbsorbs == 0 then return "" end
        return pattern:format(healAbsorbs)
    end,
    ["healabsorbs_short"] = function(pattern, health, maxHealth, absorbs, healAbsorbs)
        if healAbsorbs == 0 then return "" end
        return pattern:format(F.FormatNumber(healAbsorbs))
    end,
    ["healabsorbs_percent"] = function(pattern, health, maxHealth, absorbs, healAbsorbs)
        if healAbsorbs == 0 then return "" end
        return pattern:format(F.Round(healAbsorbs / maxHealth * 100))
    end,
}

-- 根据用户配置构建格式化模式字符串。
--   若 delimiter 非 nil：前缀添加灰色分隔符（如 "|cffababab/|r"）。
--   若 color[1] == "class_color"：返回纯 "%s" 模式（颜色在上游由 SetTextColor 处理）。
--   否则：返回嵌入 HEX 颜色代码的模式字符串（如 "|cffFF0000%s|r"）。
local function BuildPattern(config)
    if config.format == "none" then
        return ""
    end

    local prefix
    if config.delimiter == nil then
        prefix = ""
    else
        prefix = "|cffababab" .. config.delimiter .. "|r"
    end

    local suffix = config.format:find("percent$") and "%%" or ""

    if config.color[1] == "class_color" then
        return prefix .. "%s" .. suffix
    else
        return prefix .. "|cff" .. F.ConvertRGBToHEX(F.ConvertRGB_256(unpack(config.color[2]))) .. "%s" .. suffix .. "|r"
    end
end

-- Fallback width when GetStringWidth returns a secret-tainted value (rejected by SetWidth).
local function SafeTextWidth(fontString, fontSize)
    local w = fontString:GetStringWidth()
    if Cell.isMidnight and F.IsSecretValue and F.IsSecretValue(w) then
        return fontSize and fontSize * 4 or 60
    end
    return w
end

-- 12.0.5 secret-safe formatters. HealPredictionCalculator returns secret numbers even
-- in normal gameplay; Lua arithmetic and comparisons throw. Values go through calculator
-- methods and C-implemented pass-throughs (string.format, AbbreviateNumbers,
-- BreakUpLargeNumbers). effective_* and *_percent variants without a calc method fall
-- back to the closest supported format.

-- 懒加载的 C_CurveUtil 曲线对象，用于将 secret 0.0-1.0 比率映射为明文的 0-100 或 -100-0 百分比。
-- 仅在 Midnight 环境下且实际需要时创建（通过 GetMidnightCurves 懒初始化）。
-- pct01to100: 0.0→0, 1.0→100（健康百分比等正值）
-- pct01toNeg100: 0.0→0, 1.0→-100（亏损百分比等负值，仅用于 deficit_percent）
local _pct01to100, _pct01toNeg100
local function GetMidnightCurves()
    if _pct01to100 then return _pct01to100, _pct01toNeg100 end
    if not C_CurveUtil then return nil, nil end
    _pct01to100 = C_CurveUtil.CreateCurve()
    _pct01to100:AddPoint(0.0, 0.0)
    _pct01to100:AddPoint(1.0, 100.0)
    _pct01toNeg100 = C_CurveUtil.CreateCurve()
    _pct01toNeg100:AddPoint(0.0, 0.0)
    _pct01toNeg100:AddPoint(1.0, -100.0)
    return _pct01to100, _pct01toNeg100
end

-- Midnight secret-safe 格式化函数表，与 formatter 表对称。
-- key 与 formatter 相同，但函数签名不同：
--   普通路径: function(pattern, hideIfEmptyOrFull, health, maxHealth, absorbs, healAbsorbs)
--   Midnight 路径: function(pattern, calc)
-- calc 是单位的 HealPredictionCalculator 对象，所有数值通过其 C 方法获取（绕过 Lua secret 限制）。
-- 注意：
--   - health_percent / deficit_percent 使用 string.format("%.0f", ..) 而非 F.Round（避免对 secret 做算术）
--   - deficit / deficit_short 在数值前硬编码 "-" 号（无法对 secret 取负）
--   - effective_* 退化到 health_*（calculator 无 effective health 方法）
--   - shields_percent / healabsorbs_percent 退化到简短绝对值
local midnightFormatter = {
    none = function() return "" end,

    health = function(pattern, calc) return pattern:format(calc:GetCurrentHealth()) end,
    health_short = function(pattern, calc) return pattern:format(AbbreviateNumbers(calc:GetCurrentHealth())) end,
    -- Percent formatters round via %.0f since F.Round would do arithmetic on a secret.
    health_percent = function(pattern, calc)
        local pos = GetMidnightCurves()
        return pattern:format(string.format("%.0f", calc:EvaluateCurrentHealthPercent(pos)))
    end,

    -- Sign is embedded in the string (can't negate a secret).
    deficit = function(pattern, calc) return pattern:format("-"..BreakUpLargeNumbers(calc:GetMissingHealth())) end,
    deficit_short = function(pattern, calc) return pattern:format("-"..AbbreviateNumbers(calc:GetMissingHealth())) end,
    deficit_percent = function(pattern, calc)
        local _, neg = GetMidnightCurves()
        return pattern:format(string.format("%.0f", calc:EvaluateMissingHealthPercent(neg)))
    end,

    -- effective_* degrades to health_* (no calc method for effective health).
    effective = function(pattern, calc) return pattern:format(calc:GetCurrentHealth()) end,
    effective_short = function(pattern, calc) return pattern:format(AbbreviateNumbers(calc:GetCurrentHealth())) end,
    effective_percent = function(pattern, calc)
        local pos = GetMidnightCurves()
        return pattern:format(string.format("%.0f", calc:EvaluateCurrentHealthPercent(pos)))
    end,

    shields = function(pattern, calc) return pattern:format(calc:GetTotalDamageAbsorbs()) end,
    shields_short = function(pattern, calc) return pattern:format(AbbreviateNumbers(calc:GetTotalDamageAbsorbs())) end,
    -- *_percent variants degrade to short absolute (no calc method for absorbs percent).
    shields_percent = function(pattern, calc) return pattern:format(AbbreviateNumbers(calc:GetTotalDamageAbsorbs())) end,

    healabsorbs = function(pattern, calc) return pattern:format(calc:GetTotalHealAbsorbs()) end,
    healabsorbs_short = function(pattern, calc) return pattern:format(AbbreviateNumbers(calc:GetTotalHealAbsorbs())) end,
    healabsorbs_percent = function(pattern, calc) return pattern:format(AbbreviateNumbers(calc:GetTotalHealAbsorbs())) end,
}

-- 设置血量文本的显示格式（4 段组合：health1 / health2 / shields / healAbsorbs）。
-- 将 _no_sign 后缀剥离后查找格式化函数，并构建对应的模式字符串。
-- 同时保存格式名称到 _*_format 字段供 Midnight 路径查找 midnightFormatter。
local function HealthText_SetFormat(self, format)
    local h1 = format.health1.format:gsub("_no_sign$", "")
    local h2 = format.health2.format:gsub("_no_sign$", "")
    local sh = format.shields.format:gsub("_no_sign$", "")
    local ha = format.healAbsorbs.format:gsub("_no_sign$", "")

    self.GetHealth1 = formatter[h1]
    self.GetHealth2 = formatter[h2]
    self.GetShields = formatter[sh]
    self.GetHealAbsorbs = formatter[ha]

    -- Names kept for the Midnight secret path to look up a different formatter table.
    self._health1_format = h1
    self._health2_format = h2
    self._shields_format = sh
    self._healAbsorbs_format = ha

    self.health1 = BuildPattern(format.health1)
    self.health1_hideIfEmptyOrFull = format.health1.hideIfEmptyOrFull
    self.health2 = BuildPattern(format.health2)
    self.health2_hideIfEmptyOrFull = format.health2.hideIfEmptyOrFull
    self.shields = BuildPattern(format.shields)
    self.healAbsorbs = BuildPattern(format.healAbsorbs)
end

-- 核心值设置函数：根据是否处于 Midnight 且数值被污染为 secret，分发到两条路径。
--   Secret 路径：通过 calculator C 方法获取格式化后的文本，使用 SetFormattedText 和 SafeTextWidth。
--   普通路径：使用普通 formatter 函数做 Lua 运算，使用 SetFormattedText 和 GetStringWidth。
-- maxHealth 为 0 时修正为 1（避免除零）。
local function HealthText_SetValue(self, health, maxHealth, shields, healAbsorbs, calc)
    -- Secret path routes the user's format through calculator methods; calc is the unit's HealPredictionCalculator.
    if Cell.isMidnight and calc and F.IsSecretValue and (F.IsSecretValue(health) or F.IsSecretValue(maxHealth)) then
        local f1 = midnightFormatter[self._health1_format or "none"] or midnightFormatter.none
        local f2 = midnightFormatter[self._health2_format or "none"] or midnightFormatter.none
        local fs = midnightFormatter[self._shields_format or "none"] or midnightFormatter.none
        local fh = midnightFormatter[self._healAbsorbs_format or "none"] or midnightFormatter.none
        self.text:SetFormattedText("%s%s%s%s",
            f1(self.health1, calc),
            f2(self.health2, calc),
            fs(self.shields, calc),
            fh(self.healAbsorbs, calc))
        local _, fontSize = self.text:GetFont()
        self:SetWidth(SafeTextWidth(self.text, fontSize))
        return
    end

    maxHealth = maxHealth == 0 and 1 or maxHealth

    self.text:SetFormattedText("%s%s%s%s",
        self.GetHealth1(self.health1, self.health1_hideIfEmptyOrFull, health, maxHealth, shields, healAbsorbs),
        self.GetHealth2(self.health2, self.health2_hideIfEmptyOrFull, health, maxHealth, shields, healAbsorbs),
        self.GetShields(self.shields, health, maxHealth, shields, healAbsorbs),
        self.GetHealAbsorbs(self.healAbsorbs, health, maxHealth, shields, healAbsorbs))
    self:SetWidth(self.text:GetStringWidth())
end

local function HealthText_SetFont(self, font, size, outline, shadow)
    font = F.GetFont(font)

    local flags
    if outline == "None" then
        flags = ""
    elseif outline == "Outline" then
        flags = "OUTLINE"
    else
        flags = "OUTLINE,MONOCHROME"
    end

    self.text:SetFont(font, size, flags)

    if shadow then
        self.text:SetShadowOffset(1, -1)
        self.text:SetShadowColor(0, 0, 0, 1)
    else
        self.text:SetShadowOffset(0, 0)
        self.text:SetShadowColor(0, 0, 0, 0)
    end

    self:SetSize(SafeTextWidth(self.text, size), size)
end

local function HealthText_SetPoint(self, point, relativeTo, relativePoint, x, y)
    self.text:ClearAllPoints()
    if string.find(point, "LEFT$") then
        self.text:SetPoint("LEFT")
    elseif string.find(point, "RIGHT$") then
        self.text:SetPoint("RIGHT")
    else
        self.text:SetPoint("CENTER")
    end
    self:_SetPoint(point, relativeTo, relativePoint, x, y)
    I.JustifyText(self.text, point)
end

local function HealthText_SetColor(self, r, g, b)
    self.text:SetTextColor(r, g, b)
end

local function HealthText_UpdatePreviewColor(self, color)
    -- if color[1] == "class_color" then
        self.text:SetTextColor(F.GetClassColor(Cell.vars.playerClass))
    -- else
    --     self.text:SetTextColor(unpack(color[2]))
    -- end
end

function I.CreateHealthText(parent)
    local healthText = CreateFrame("Frame", parent:GetName().."HealthText", parent.widgets.indicatorFrame)
    parent.indicators.healthText = healthText
    healthText:Hide()

    local text = healthText:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    healthText.text = text

    healthText.GetHealth1 = formatter.none
    healthText.GetHealth2 = formatter.none
    healthText.GetShields = formatter.none
    healthText.GetHealAbsorbs = formatter.none

    healthText.SetFont = HealthText_SetFont
    healthText._SetPoint = healthText.SetPoint
    healthText.SetPoint = HealthText_SetPoint
    healthText.SetFormat = HealthText_SetFormat
    healthText.SetValue = HealthText_SetValue
    healthText.SetColor = HealthText_SetColor
    healthText.UpdatePreviewColor = HealthText_UpdatePreviewColor
end

-------------------------------------------------
-- power text
-- 能量文本指示器：显示单位的能量值（法力/怒气/能量等），支持百分比和数字两种格式。
--
-- Midnight 注意事项：
--   能量值在 Cell 的污染执行上下文中返回为 secret value（无 power 侧的 calculator 存在）。
--   hideIfEmptyOrFull 在 secret 路径中为无操作（需要比较运算）。
--   FontString 一旦持有过 secret 文本，其后 GetStringWidth 也返回 secret，需用 SafeTextWidth。
--
-- SetPower_Percentage 在 Midnight 上有优选路径：通过 UnitPowerPercent(unit, powerType, useCurve, curve)
--   从 C 层直接返回纯数字 0-100，完全绕过 secret value 限制（pcall 保护）。失败时回退到 secret 安全路径。
-------------------------------------------------
-- Secret 路径下的宽度回退：使用 fontSize * 4 或 60 作为安全估算宽度。
local function SetPower_SecretWidth(self)
    local _, fontSize = self.text:GetFont()
    self:SetWidth(fontSize and fontSize * 4 or 60)
    self:Show()
end

local function SetPower_Percentage(self, current, max, unit)
    -- Preferred path on Midnight: UnitPowerPercent(unit, powerType, useCurve, curve) returns
    -- a plain 0-100 number directly from the C layer, bypassing the secret-value restriction
    -- on UnitPower. pcall because the API can throw in some restricted contexts.
    if unit and Cell.isMidnight and UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, pct = pcall(UnitPowerPercent, unit, nil, true, CurveConstants.ScaleTo100)
        if ok and type(pct) == "number" then
            local _, fontSize = self.text:GetFont()
            self.text:SetFormattedText("%d%%", pct)
            self:SetWidth(SafeTextWidth(self.text, fontSize))
            self:Show()
            return
        end
    end
    -- Fallback when the UnitPowerPercent path isn't available or fails: abbreviated if secret, else arithmetic.
    if Cell.isMidnight and F.IsSecretValue and (F.IsSecretValue(current) or F.IsSecretValue(max)) then
        self.text:SetText(AbbreviateNumbers and AbbreviateNumbers(current) or tostring(current))
        return SetPower_SecretWidth(self)
    end
    if self.hideIfEmptyOrFull and (current == 0 or current == max) then
        self:Hide()
    else
        local _, fontSize = self.text:GetFont()
        self.text:SetFormattedText("%d%%", current/max*100)
        self:SetWidth(SafeTextWidth(self.text, fontSize))
        self:Show()
    end
end

local function SetPower_Number(self, current, max)
    if Cell.isMidnight and F.IsSecretValue and (F.IsSecretValue(current) or F.IsSecretValue(max)) then
        self.text:SetText(current)
        return SetPower_SecretWidth(self)
    end
    if self.hideIfEmptyOrFull and (current == 0 or current == max) then
        self:Hide()
    else
        local _, fontSize = self.text:GetFont()
        self.text:SetText(current)
        self:SetWidth(SafeTextWidth(self.text, fontSize))
        self:Show()
    end
end

local function SetPower_Number_Short(self, current, max)
    if Cell.isMidnight and F.IsSecretValue and (F.IsSecretValue(current) or F.IsSecretValue(max)) then
        -- F.FormatNumber does comparisons that would throw on secrets.
        self.text:SetText(AbbreviateNumbers and AbbreviateNumbers(current) or tostring(current))
        return SetPower_SecretWidth(self)
    end
    if self.hideIfEmptyOrFull and (current == 0 or current == max) then
        self:Hide()
    else
        local _, fontSize = self.text:GetFont()
        self.text:SetText(F.FormatNumber(current))
        self:SetWidth(SafeTextWidth(self.text, fontSize))
        self:Show()
    end
end

local function PowerText_SetFont(self, font, size, outline, shadow)
    font = F.GetFont(font)

    local flags
    if outline == "None" then
        flags = ""
    elseif outline == "Outline" then
        flags = "OUTLINE"
    else
        flags = "OUTLINE,MONOCHROME"
    end

    self.text:SetFont(font, size, flags)

    if shadow then
        self.text:SetShadowOffset(1, -1)
        self.text:SetShadowColor(0, 0, 0, 1)
    else
        self.text:SetShadowOffset(0, 0)
        self.text:SetShadowColor(0, 0, 0, 0)
    end

    self:SetSize(SafeTextWidth(self.text, size), size)
end

local function PowerText_SetPoint(self, point, relativeTo, relativePoint, x, y)
    self.text:ClearAllPoints()
    if string.find(point, "LEFT$") then
        self.text:SetPoint("LEFT")
    elseif string.find(point, "RIGHT$") then
        self.text:SetPoint("RIGHT")
    else
        self.text:SetPoint("CENTER")
    end
    self:_SetPoint(point, relativeTo, relativePoint, x, y)
end

local function PowerText_SetFormat(self, format)
    if format == "percentage" then
        self.SetValue = SetPower_Percentage
    elseif format == "number" then
        self.SetValue = SetPower_Number
    else
        self.SetValue = SetPower_Number_Short
    end
end

local function PowerText_SetColor(self, r, g, b)
    self.text:SetTextColor(r, g, b)
end

local function PowerText_SetHideIfEmptyOrFull(self, hideIfEmptyOrFull)
    self.hideIfEmptyOrFull = hideIfEmptyOrFull
end

local function PowerText_UpdatePreviewColor(self, color)
    local r, g, b
    if color[1] == "power_color" then
        r, g, b = F.GetPowerColor("player")
    elseif color[1] == "class_color" then
        r, g, b = F.GetClassColor(Cell.vars.playerClass)
    else
        r, g, b = unpack(color[2])
    end
    self.text:SetTextColor(r, g, b)
end

function I.CreatePowerText(parent)
    local powerText = CreateFrame("Frame", parent:GetName().."PowerText", parent.widgets.indicatorFrame)
    parent.indicators.powerText = powerText
    powerText:Hide()

    local text = powerText:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    powerText.text = text

    powerText.SetFont = PowerText_SetFont
    powerText._SetPoint = powerText.SetPoint
    powerText.SetPoint = PowerText_SetPoint
    powerText.SetFormat = PowerText_SetFormat
    powerText.SetColor = PowerText_SetColor
    powerText.SetHideIfEmptyOrFull = PowerText_SetHideIfEmptyOrFull
    powerText.UpdatePreviewColor = PowerText_UpdatePreviewColor
    powerText.SetValue = noop
end

-------------------------------------------------
-- role icon
-- 职责图标指示器：显示单位的团队职责（坦克/治疗/伤害输出）。
-- 支持多种图标风格（default/blizzard/ffxiv/miirgui 等），通过纹理坐标裁剪大图集实现。
-- 同时支持"载具-根类型"和"载具"两种特殊图标。
-------------------------------------------------
local ICON_PATH = "Interface\\AddOns\\Cell\\Media\\Roles\\"

-- 获取大图集（如 Default2_ROLES、Blizzard2_ROLES）中对应职责的纹理坐标
local function GetTexCoordsForRole(role)
    if role == "TANK" then
        return 0, 67/256, 67/256, 134/256
    elseif role == "HEALER" then
        return 67/256, 134/256, 0, 67/256
    elseif role == "DAMAGER" then
        return 67/256, 134/256, 67/256, 134/256
    end
end

local function GetTexCoordsForRoleSmall(role)
    if role == "TANK" then
        return 0, 19/64, 22/64, 41/64
    elseif role == "HEALER" then
        return 20/64, 39/64, 1/64, 20/64
    elseif role == "DAMAGER" then
        return 20/64, 39/64, 22/64, 41/64
    end
end

local function RoleIcon_SetRole(self, role)
    self.tex:SetTexCoord(0, 1, 0, 1)
    self.tex:SetVertexColor(1, 1, 1)

    if role == "TANK" or role == "HEALER" or (not self.hideDamager and role == "DAMAGER") then
        if self.texture == "default" then
            self.tex:SetTexture(ICON_PATH .. "Default_" .. role)
        elseif self.texture == "default2" then
            self.tex:SetTexture(ICON_PATH .. "Default2_ROLES")
            self.tex:SetTexCoord(GetTexCoordsForRole(role))
        elseif self.texture == "blizzard" then
            self.tex:SetTexture(ICON_PATH .. "Blizzard_ROLES")
            self.tex:SetTexCoord(GetTexCoordsForRoleSmall(role))
        elseif self.texture == "blizzard2" then
            self.tex:SetTexture(ICON_PATH .. "Blizzard2_ROLES")
            self.tex:SetTexCoord(GetTexCoordsForRole(role))
        elseif self.texture == "blizzard3" then
            self.tex:SetTexture(ICON_PATH .. "Blizzard3_" .. role)
        elseif self.texture == "blizzard4" then
            self.tex:SetTexture(ICON_PATH .. "Blizzard4_" .. role)
        elseif self.texture == "ffxiv" then
            self.tex:SetTexture(ICON_PATH .. "FFXIV_" .. role)
        elseif self.texture == "miirgui" then
            self.tex:SetTexture(ICON_PATH .. "MiirGui_" .. role)
        elseif self.texture == "mattui" then
            self.tex:SetTexture(ICON_PATH .. "MattUI_ROLES")
            self.tex:SetTexCoord(GetTexCoordsForRoleSmall(role))
        elseif self.texture == "custom" then
            self.tex:SetTexture(self[role])
        end
        self:Show()
    elseif role == "VEHICLE-ROOT" then
        self.tex:SetTexture(ICON_PATH .. "VEHICLE")
        self:Show()
    elseif role == "VEHICLE" then
        self.tex:SetTexture(ICON_PATH .. "VEHICLE")
        self.tex:SetVertexColor(0.6, 0.6, 1)
        self:Show()
    else
        self:Hide()
    end
end

local function RoleIcon_SetRoleTexture(self, t)
    self.texture = t[1]
    self.TANK = t[2]
    self.HEALER = t[3]
    self.DAMAGER = t[4]
end

local function RoleIcon_HideDamager(self, hide)
    self.hideDamager = hide
end

local function RoleIcon_UpdatePixelPerfect(self)
    P.Resize(self)
    P.Repoint(self)
end

function I.CreateRoleIcon(parent)
    local roleIcon = CreateFrame("Frame", parent:GetName().."RoleIcon", parent.widgets.indicatorFrame)
    parent.indicators.roleIcon = roleIcon
    -- roleIcon:SetPoint("TOPLEFT", indicatorFrame)
    -- roleIcon:SetSize(11, 11)

    roleIcon.tex = roleIcon:CreateTexture(nil, "ARTWORK")
    roleIcon.tex:SetAllPoints()

    roleIcon.SetRole = RoleIcon_SetRole
    roleIcon.SetRoleTexture = RoleIcon_SetRoleTexture
    roleIcon.HideDamager = RoleIcon_HideDamager
    roleIcon.UpdatePixelPerfect = RoleIcon_UpdatePixelPerfect
end

-------------------------------------------------
-- party assignment icon
-------------------------------------------------
function I.CreatePartyAssignmentIcon(parent)
    local partyAssignmentIcon = parent.widgets.indicatorFrame:CreateTexture(parent:GetName().."PartyAssignmentIcon", "ARTWORK", nil, -7)
    parent.indicators.partyAssignmentIcon = partyAssignmentIcon
    partyAssignmentIcon:Hide()

    function partyAssignmentIcon:UpdateAssignment(unit)
        if GetPartyAssignment("MAINTANK", unit) then
            partyAssignmentIcon:SetTexture("Interface\\GroupFrame\\UI-Group-MainTankIcon")
            partyAssignmentIcon:Show()
        elseif GetPartyAssignment("MAINASSIST", unit) then
            partyAssignmentIcon:SetTexture("Interface\\GroupFrame\\UI-Group-MainAssistIcon")
            partyAssignmentIcon:Show()
        else
            partyAssignmentIcon:Hide()
        end
    end

    function partyAssignmentIcon:UpdatePixelPerfect()
        P.Resize(partyAssignmentIcon)
        P.Repoint(partyAssignmentIcon)
    end
end

-------------------------------------------------
-- leader icon
-- 队长图标指示器：显示单位的队伍/团队领导身份（队长/助理）。
-- 使用暴雪原生图标 "UI-Group-LeaderIcon" 和 "UI-Group-AssistantIcon"。
-------------------------------------------------
function I.CreateLeaderIcon(parent)
    local leaderIcon = parent.widgets.indicatorFrame:CreateTexture(parent:GetName().."LeaderIcon", "ARTWORK", nil, -7)
    parent.indicators.leaderIcon = leaderIcon
    -- leaderIcon:SetPoint("TOPLEFT", roleIcon, "BOTTOM")
    -- leaderIcon:SetPoint("TOPLEFT", 0, -11)
    -- leaderIcon:SetSize(11, 11)
    leaderIcon:Hide()

    function leaderIcon:SetIcon(isLeader, isAssistant)
        if isLeader then
            leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            leaderIcon:Show()
        elseif isAssistant then
            leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
            leaderIcon:Show()
        else
            leaderIcon:Hide()
        end
    end

    function leaderIcon:UpdatePixelPerfect()
        P.Resize(leaderIcon)
        P.Repoint(leaderIcon)
    end
end

-------------------------------------------------
-- ready check icon
-- 就绪检查图标指示器：显示单位在就绪检查中的状态（就绪/等待/未就绪）。
-- 使用自定义图标替代暴雪自带纹理（注释记录了 10.1.5 前后暴雪纹理的变更）。
-------------------------------------------------
-- READY_CHECK_WAITING_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Waiting"
-- READY_CHECK_READY_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
-- READY_CHECK_NOT_READY_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-NotReady"
-- READY_CHECK_AFK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-NotReady"
-- ↓↓↓ since 10.1.5
-- READY_CHECK_WAITING_TEXTURE = "UI-LFG-PendingMark"
-- READY_CHECK_READY_TEXTURE = "UI-LFG-ReadyMark"
-- READY_CHECK_NOT_READY_TEXTURE = "UI-LFG-DeclineMark"
-- READY_CHECK_AFK_TEXTURE = "UI-LFG-DeclineMark"

-- 就绪检查状态的图标和颜色映射表
local READY_CHECK_STATUS = {
    ready = {t = "Interface\\AddOns\\Cell\\Media\\Icons\\readycheck-ready", c = {0, 1, 0, 1}},
    waiting = {t = "Interface\\AddOns\\Cell\\Media\\Icons\\readycheck-waiting", c = {1, 1, 0, 1}},
    notready = {t = "Interface\\AddOns\\Cell\\Media\\Icons\\readycheck-notready", c = {1, 0, 0, 1}},
}

function I.CreateReadyCheckIcon(parent)
    local readyCheckIcon = CreateFrame("Frame", parent:GetName().."ReadyCheckIcon", parent.widgets.indicatorFrame)
    parent.indicators.readyCheckIcon = readyCheckIcon
    readyCheckIcon:Hide()
    readyCheckIcon:SetIgnoreParentAlpha(true)

    readyCheckIcon.tex = readyCheckIcon:CreateTexture(nil, "ARTWORK")
    readyCheckIcon.tex:SetAllPoints(readyCheckIcon)

    function readyCheckIcon:SetStatus(status)
        readyCheckIcon.tex:SetTexture(READY_CHECK_STATUS[status].t)
        -- readyCheckIcon.tex:SetAtlas(READY_CHECK_STATUS[status].t)
        readyCheckIcon:Show()

    end
end

-------------------------------------------------
-- aggro border
-- 仇恨边框指示器：在单元按钮的内侧边缘显示四边渐变边框，表示该单位正在看当前玩家。
-- 四边（top/bottom/left/right）分别使用渐变纹理，产生从边框中心到外侧的淡出效果。
-- ShowAggro(r, g, b) 可按威胁类型切换颜色。
-------------------------------------------------
function I.CreateAggroBorder(parent)
    local aggroBorder = CreateFrame("Frame", parent:GetName().."AggroBorder", parent, "BackdropTemplate")
    parent.indicators.aggroBorder = aggroBorder
    -- 锚定在单元按钮内侧（偏移 1 像素，避免覆盖按钮边缘）
    P.Point(aggroBorder, "TOPLEFT", parent, "TOPLEFT", 1, -1)
    P.Point(aggroBorder, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 1)
    aggroBorder:Hide()

    local top = aggroBorder:CreateTexture(nil, "BORDER")
    local bottom = aggroBorder:CreateTexture(nil, "BORDER")
    local left = aggroBorder:CreateTexture(nil, "BORDER")
    local right = aggroBorder:CreateTexture(nil, "BORDER")

    top:SetTexture(Cell.vars.whiteTexture)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(5)

    bottom:SetTexture(Cell.vars.whiteTexture)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(5)

    left:SetTexture(Cell.vars.whiteTexture)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(5)

    right:SetTexture(Cell.vars.whiteTexture)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(5)

    top:SetGradient("VERTICAL", CreateColor(1, 0.1, 0.1, 0.2), CreateColor(1, 0.1, 0.1, 1))
    bottom:SetGradient("VERTICAL", CreateColor(1, 0.1, 0.1, 1), CreateColor(1, 0.1, 0.1, 0.2))
    left:SetGradient("HORIZONTAL", CreateColor(1, 0.1, 0.1, 1), CreateColor(1, 0.1, 0.1, 0.2))
    right:SetGradient("HORIZONTAL", CreateColor(1, 0.1, 0.1, 0.2), CreateColor(1, 0.1, 0.1, 1))

    function aggroBorder:ShowAggro(r, g, b)
        top:SetGradient("VERTICAL", CreateColor(r, g, b, 0.2), CreateColor(r, g, b, 1))
        bottom:SetGradient("VERTICAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 0.2))
        left:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 0.2))
        right:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.2), CreateColor(r, g, b, 1))
        aggroBorder:Show()
    end

    function aggroBorder:SetThickness(n)
        top:SetHeight(n)
        bottom:SetHeight(n)
        left:SetWidth(n)
        right:SetWidth(n)
    end

    function aggroBorder:UpdatePixelPerfect()
        P.Repoint(aggroBorder)
    end
end

-------------------------------------------------
-- aggro blink
-- 仇恨闪烁指示器：一个持续闪烁的矩形块（REPEAT 循环 Alpha 动画），表示该单位正在看当前玩家。
-- 使用 AnimationGroup 实现 1→0 Alpha 往复闪烁，Show 时自动播放，Hide 时自动停止。
-- ShowAggro(r, g, b) 可按威胁类型切换颜色。
-------------------------------------------------
function I.CreateAggroBlink(parent)
    local aggroBlink = CreateFrame("Frame", parent:GetName().."AggroBlink", parent.widgets.indicatorFrame, "BackdropTemplate")
    parent.indicators.aggroBlink = aggroBlink
    -- aggroBlink:SetPoint("TOPLEFT")
    -- aggroBlink:SetSize(10, 10)
    aggroBlink:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
    aggroBlink:SetBackdropColor(1, 0, 0, 1)
    aggroBlink:SetBackdropBorderColor(0, 0, 0, 1)
    aggroBlink:Hide()

    local blink = aggroBlink:CreateAnimationGroup()
    aggroBlink.blink = blink
    blink:SetLooping("REPEAT")

    local alpha = blink:CreateAnimation("Alpha")
    blink.alpha = alpha
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetDuration(0.5)

    aggroBlink:SetScript("OnShow", function(self)
        self.blink:Play()
    end)

    aggroBlink:SetScript("OnHide", function(self)
        self.blink:Stop()
    end)

    function aggroBlink:ShowAggro(r, g, b)
        aggroBlink:SetBackdropColor(r, g, b)
        aggroBlink:Show()
    end

    function aggroBlink:UpdatePixelPerfect()
        P.Resize(aggroBlink)
        P.Repoint(aggroBlink)
        aggroBlink:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
        aggroBlink:SetBackdropColor(1, 0, 0, 1)
        aggroBlink:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

-------------------------------------------------
-- shield bar
-- 护盾条指示器：将单位的吸收护盾总量可视化为一个重叠在血量条上的 StatusBar。
--
-- Midnight 12.0.0+ 设计要点：
--   使用 StatusBar 而非 Frame+texture。StatusBar 的 SetMinMaxValues / SetValue
--   在 C 引擎中原生处理 secret value，无需 Lua 算术计算比例。
--   Grid2 参考：StatusShields.lua 出于同样原因使用 StatusBar。
--
-- SetValue(current, max) 重写：当 max 为明文的非 secret 值时正常设值；
--   否则回退为显示 25% 宽度的"存在性指示器"（至少让玩家知道有护盾存在）。
-------------------------------------------------
-- 特殊锚点模式："HEALTH_BAR" 锚定到血量条（带像素完美偏移）。
local function ShieldBar_SetPoint(bar, point, anchorTo, anchorPoint, x, y)
    if point == "HEALTH_BAR" then
        bar:_SetPoint("TOPLEFT", bar.parentHealthBar, P.Scale(-1), P.Scale(1))
        bar:_SetPoint("BOTTOMLEFT", bar.parentHealthBar, P.Scale(-1), P.Scale(-1))
    else
        bar:_SetPoint(point, anchorTo, anchorPoint, x, y)
    end
end

function I.CreateShieldBar(parent)
    -- Midnight 12.0.0+: Use StatusBar instead of Frame+texture.
    -- StatusBar's SetMinMaxValues / SetValue natively handle secret values
    -- in C engine, computing the ratio without Lua arithmetic.
    -- Grid2 reference: StatusShields.lua uses StatusBar for the same reason.
    local shieldBar = Cell.CreateStatusBar(parent:GetName().."ShieldBarIndicator", parent.widgets.indicatorFrame, 20, 6, 100, false, nil, nil, nil, {1, 1, 0, 1})
    parent.indicators.shieldBar = shieldBar
    shieldBar:Hide()

    shieldBar._SetPoint = shieldBar.SetPoint
    shieldBar.SetPoint = ShieldBar_SetPoint

    shieldBar.parentHealthBar = parent.widgets.healthBar
    shieldBar._SetMinMaxValues = shieldBar.SetMinMaxValues
    shieldBar._SetValue = shieldBar.SetValue

    -- Override SetValue to take current+max pair from caller
    function shieldBar:SetValue(current, max)
        if max and F.IsValueNonSecret(max) and max > 0 then
            self:_SetMinMaxValues(0, max)
            self:_SetValue(current)
        else
            -- Fallback for secret max: show 25% width as presence indicator
            self:_SetMinMaxValues(0, 100)
            self:_SetValue(25)
        end
    end

    function shieldBar:SetColor(r, g, b, a)
        shieldBar:SetStatusBarColor(r, g, b, a or 1)
    end

    function shieldBar:UpdatePixelPerfect()
        P.Resize(shieldBar)
        P.Repoint(shieldBar)
        P.Reborder(shieldBar)
    end
end

-------------------------------------------------
-- health threshold
-- 血量阈值指示器：在血量条上标记用户自定义的阈值线（如 30%/50%/70% 等）。
-- CheckThreshold(percent) 找到第一个大于当前血量百分比的阈值，在对应位置显示彩色标记线。
-- 支持水平（竖线标记）和垂直（横线标记）两种方向。
-- 预览模式下（CellIndicatorsPreviewButton）会一次性显示所有配置的阈值线。
-------------------------------------------------
function I.CreateHealthThresholds(parent)
    local healthThresholds = CreateFrame("Frame", parent:GetName().."HealthThresholds", parent.widgets.highLevelFrame)
    parent.indicators.healthThresholds = healthThresholds
    healthThresholds:SetAllPoints(parent.widgets.healthBar)

    healthThresholds.tex = healthThresholds:CreateTexture(nil, "ARTWORK")

    -- 设置标记线的粗细（像素）
    function healthThresholds:SetThickness(thickness)
        healthThresholds.thickness = thickness
        P.Size(healthThresholds.tex, thickness, thickness)
    end

    -- 设置阈值线方向：horizontal（竖线）或 vertical（横线）
    function healthThresholds:SetOrientation(orientation)
        healthThresholds.orientation = orientation
        healthThresholds.tex:ClearAllPoints()
        if orientation == "horizontal" then
            healthThresholds.tex:SetPoint("TOP")
            healthThresholds.tex:SetPoint("BOTTOM")
        else
            healthThresholds.tex:SetPoint("LEFT")
            healthThresholds.tex:SetPoint("RIGHT")
        end
    end

    -- 根据当前血量百分比查找应显示的阈值线。
    -- 遍历排序后的阈值列表，找到第一个 t[1] > percent 的条目，
    -- 在血量条的 t[1] 比例位置绘制彩色标记（使用该条目的颜色 t[2]）。
    function healthThresholds:CheckThreshold(percent)
        local found
        for i, t in ipairs(Cell.vars.healthThresholds) do
            if percent < t[1] then
                found = i
                break
            end
        end
        if found then
            if healthThresholds.orientation == "horizontal" then
                healthThresholds.tex:SetPoint("LEFT", Cell.vars.healthThresholds[found][1] * parent.widgets.healthBar:GetWidth(), 0)
            else
                healthThresholds.tex:SetPoint("BOTTOM", 0, Cell.vars.healthThresholds[found][1] * parent.widgets.healthBar:GetHeight())
            end
            healthThresholds.tex:SetColorTexture(unpack(Cell.vars.healthThresholds[found][2]))
            healthThresholds:Show()
        else
            healthThresholds:Hide()
        end
    end

    if parent == CellIndicatorsPreviewButton then
        healthThresholds.tex:Hide()

        function healthThresholds:UpdateThresholdsPreview()
            for i, t in ipairs(Cell.vars.healthThresholds) do
                healthThresholds[i] = healthThresholds[i] or healthThresholds:CreateTexture(nil, "ARTWORK")
                P.Size(healthThresholds[i], healthThresholds.thickness, healthThresholds.thickness)
                healthThresholds[i]:SetColorTexture(unpack(t[2]))
                -- healthThresholds[i]:SetBlendMode("ADD")

                healthThresholds[i]:ClearAllPoints()
                if healthThresholds.orientation == "horizontal" then
                    healthThresholds[i]:SetPoint("TOP")
                    healthThresholds[i]:SetPoint("BOTTOM")
                    healthThresholds[i]:SetPoint("LEFT", t[1] * parent.widgets.healthBar:GetWidth(), 0)
                else
                    healthThresholds[i]:SetPoint("LEFT")
                    healthThresholds[i]:SetPoint("RIGHT")
                    healthThresholds[i]:SetPoint("BOTTOM", 0, t[1] * parent.widgets.healthBar:GetHeight())
                end
                healthThresholds[i]:Show()
            end
            -- hide unused
            for i = #Cell.vars.healthThresholds+1, #healthThresholds do
                if healthThresholds[i] then
                    healthThresholds[i]:Hide()
                end
            end
        end
    end
end

-- 排序并保存血量阈值配置。
-- 从当前布局表中读取阈值数据，按百分比值升序排序后写入 Cell.vars.healthThresholds。
-- sort and save
function I.UpdateHealthThresholds()
    Cell.vars.healthThresholds = Cell.vars.currentLayoutTable.indicators[Cell.defaults.indicatorIndices.healthThresholds].thresholds
    F.Sort(Cell.vars.healthThresholds, 1, "ascending")
end

-------------------------------------------------
-- power word : shield 怀旧服API太落后，蛋疼！
-- 真言盾（Power Word: Shield）指示器：为牧师职业设计的专用圆形指示器。
-- 使用三层 Cooldown 帧实现：shieldAmount（护盾量环形填充）、shieldCooldown（护盾持续时间）、
-- weakenedSoulCooldown（虚弱灵魂持续时间）。三层从内到外叠加，底层为暗色填充圆。
-------------------------------------------------
function I.CreatePowerWordShield(parent)
    local powerWordShield = CreateFrame("Frame", parent:GetName().."PowerWordShield", parent.widgets.indicatorFrame, "BackdropTemplate")
    parent.indicators.powerWordShield = powerWordShield
    powerWordShield:Hide()

    powerWordShield:SetBackdrop({bgFile = [[Interface\AddOns\Cell\Media\Shapes\circle_filled.tga]]})
    powerWordShield:SetBackdropColor(0, 0, 0, 0.75)

    --! shield amount
    local shieldAmount = CreateFrame("Cooldown", parent:GetName().."PowerWordShieldAmount", powerWordShield)
    -- shieldAmount:SetAllPoints(powerWordShield)
    shieldAmount:SetSwipeTexture([[Interface\AddOns\Cell\Media\Shapes\circle_filled.tga]])
    -- shieldAmount:SetSwipeTexture(Cell.vars.whiteTexture)
    shieldAmount:SetSwipeColor(1, 1, 0)
    shieldAmount.noCooldownCount = true -- disable omnicc
    shieldAmount:SetHideCountdownNumbers(true)

    --! innerBG
    local innerBG = shieldAmount:CreateTexture(nil, "OVERLAY")
    innerBG:SetPoint("CENTER")
    innerBG:SetTexture([[Interface\AddOns\Cell\Media\Shapes\circle_filled.tga]], "CLAMP", "CLAMP", "TRILINEAR")
    innerBG:SetVertexColor(0, 0, 0, 1)

    --! shield duration
    local shieldCooldown = CreateFrame("Cooldown", parent:GetName().."PowerWordShieldDuration", powerWordShield)
    shieldCooldown:SetFrameLevel(shieldAmount:GetFrameLevel() + 1)
    -- shieldCooldown:SetPoint("CENTER")
    shieldCooldown:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
    shieldCooldown:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))
    shieldCooldown:SetSwipeTexture([[Interface\AddOns\Cell\Media\Shapes\circle_filled.tga]])
    shieldCooldown:SetSwipeColor(0, 1, 0)
    shieldCooldown.noCooldownCount = true -- disable omnicc
    shieldCooldown:SetHideCountdownNumbers(true)
    shieldCooldown:Hide()
    shieldCooldown:SetScript("OnCooldownDone", function()
        shieldCooldown:Hide()
    end)

    --! weakened soul duration
    local weakendedSoulCooldown = CreateFrame("Cooldown", parent:GetName().."WeakenedSoulDuration", powerWordShield)
    weakendedSoulCooldown:SetFrameLevel(shieldAmount:GetFrameLevel() + 2)
    -- weakendedSoulCooldown:SetPoint("CENTER")
    weakendedSoulCooldown:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
    weakendedSoulCooldown:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))
    weakendedSoulCooldown:SetSwipeTexture([[Interface\AddOns\Cell\Media\Shapes\circle_filled.tga]])
    weakendedSoulCooldown:SetSwipeColor(1, 0, 0)
    weakendedSoulCooldown.noCooldownCount = true -- disable omnicc
    weakendedSoulCooldown:SetHideCountdownNumbers(true)
    weakendedSoulCooldown:Hide()
    weakendedSoulCooldown:SetScript("OnCooldownDone", function()
        weakendedSoulCooldown:Hide()
    end)

    powerWordShield._SetSize = powerWordShield.SetSize
    function powerWordShield:SetSize(width, height)
        powerWordShield.size = width
        powerWordShield:UpdatePixelPerfect()
    end

    function powerWordShield:UpdatePixelPerfect()
        local size = powerWordShield.size
        if not size then return end

        powerWordShield:_SetSize(P.Scale(size), P.Scale(size))
        innerBG:SetSize(P.Scale(ceil(size/2)+2), P.Scale(ceil(size/2)+2))

        shieldCooldown:SetSize(P.Scale(ceil(size/2)), P.Scale(ceil(size/2)))
        weakendedSoulCooldown:SetSize(P.Scale(ceil(size/2)), P.Scale(ceil(size/2)))

        shieldAmount:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
        shieldAmount:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))
    end

    function powerWordShield:SetShape(shape)
        local tex = "Interface\\AddOns\\Cell\\Media\\Shapes\\"..shape.."_filled.tga"
        powerWordShield:SetBackdrop({bgFile = tex})
        powerWordShield:SetBackdropColor(0, 0, 0, 0.75)
        shieldAmount:SetSwipeTexture(tex)
        innerBG:SetTexture(tex, "CLAMP", "CLAMP", "TRILINEAR")
        shieldCooldown:SetSwipeTexture(tex)
        weakendedSoulCooldown:SetSwipeTexture(tex)
    end

    -- 更新护盾量显示（环形填充进度）。
    -- 使用 Cooldown 帧的圆弧擦除来表现护盾吸收量/最大值的比例。
    -- resetMax 为 true 时重置最大值缓存（用于护盾刷新场景）。
    -- 当有护盾剩余时缩放环形到 CENTER 填充模式；无护盾时恢复为全尺寸覆盖。
    function powerWordShield:UpdateShield(value, max, resetMax)
        if resetMax then
            powerWordShield.max = nil
        elseif max then
            powerWordShield.max = max
        end
        -- print("remain:", value, "max:", powerWordShield.max, resetMax and "(reset)" or "")

        shieldCooldown:ClearAllPoints()
        weakendedSoulCooldown:ClearAllPoints()

        if value > 0 and powerWordShield.max then
            local progress = (powerWordShield.max - value) / powerWordShield.max
            local start = GetTime() - (progress * 100)
            shieldAmount:SetCooldown(start, 100)
            shieldAmount:Pause()
            shieldCooldown:SetPoint("CENTER")
            weakendedSoulCooldown:SetPoint("CENTER")
        else
            shieldCooldown:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
            shieldCooldown:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))
            weakendedSoulCooldown:SetPoint("TOPLEFT", P.Scale(1), P.Scale(-1))
            weakendedSoulCooldown:SetPoint("BOTTOMRIGHT", P.Scale(-1), P.Scale(1))
        end
    end

    local function Update()
        if not (shieldCooldown:IsShown() or weakendedSoulCooldown:IsShown()) then
            powerWordShield:Hide()
        end
    end

    -- 设置护盾持续时间（绿色环形倒计时擦除）。
    -- start/duration 为 nil 时隐藏护盾帧并检查是否需要隐藏整个指示器。
    function powerWordShield:SetShieldCooldown(start, duration)
        if start and duration then
            powerWordShield:Show()
            shieldCooldown:Show()
            shieldCooldown:SetCooldown(start, duration)
        else
            shieldCooldown:Hide()
            shieldAmount:Hide()
            Update()
        end
    end

    -- 设置虚弱灵魂持续时间（红色环形倒计时擦除）。
    -- start/duration 为 nil 时隐藏帧并检查是否需要隐藏整个指示器。
    -- isMine 参数保留但当前未使用（为未来区分自己施放的虚弱灵魂预留）。
    function powerWordShield:SetWeakenedSoulCooldown(start, duration, isMine)
        if start and duration then
            powerWordShield:Show()
            weakendedSoulCooldown:Show()
            weakendedSoulCooldown:SetCooldown(start, duration)
        else
            weakendedSoulCooldown:Hide()
            Update()
        end
    end
end

-------------------------------------------------
-- crowd controls
-- 群体控制指示器：显示单位受到的控制类光环（如眩晕、恐惧、变形等）。
-- 结构与 RaidDebuffs 相似，使用带间距的共享函数和 Aura_BorderIcon（带边框图标）。
-- 预创建 3 个图标槽位。
-------------------------------------------------
function I.CreateCrowdControls(parent)
    local crowdControls = CreateFrame("Frame", parent:GetName().."CrowdControlsParent", parent.widgets.indicatorFrame)
    parent.indicators.crowdControls = crowdControls
    crowdControls:Hide()

    crowdControls._SetSize = crowdControls.SetSize
    crowdControls.SetSize = I.Cooldowns_SetSize
    crowdControls.SetBorder = I.Cooldowns_SetBorder
    crowdControls.UpdateSize = I.Cooldowns_UpdateSize_WithSpacing
    crowdControls.ShowDuration = I.Cooldowns_ShowDuration
    crowdControls.SetOrientation = I.Cooldowns_SetOrientation_WithSpacing
    crowdControls.SetFont = I.Cooldowns_SetFont
    crowdControls.UpdatePixelPerfect = I.Cooldowns_UpdatePixelPerfect

    for i = 1, 3 do
        local frame = I.CreateAura_BorderIcon(parent:GetName().."CrowdControl"..i, crowdControls, 2)
        tinsert(crowdControls, frame)
        -- frame:SetScript("OnShow", crowdControls.UpdateSize)
        -- frame:SetScript("OnHide", crowdControls.UpdateSize)
    end
end

--------------------------------------------------
-- Combat Icon
-- 战斗图标指示器：当单位处于战斗状态时显示交叉剑图标，并带有闪烁光效。
-- 双层纹理设计：tex（剑图标本体）+ flashTex（ADD 混合的辉光纹理，带循环眨眼动画）。
-- CombatIcon_OnEvent 由外部定义，负责监听战斗状态事件并控制显示/隐藏。
--------------------------------------------------
local function CombatIcon_UpdatePixelPerfect(self)
    P.Resize(self)
    P.Repoint(self)
end

function I.CreateCombatIcon(parent)
    local combatIcon = CreateFrame("Frame", parent:GetName() .. "CombatIcon", parent.widgets.indicatorFrame)
    parent.indicators.combatIcon = combatIcon
    combatIcon.root = parent
    combatIcon:Hide()

    combatIcon.tex = combatIcon:CreateTexture(nil, "ARTWORK", nil, 0)
    combatIcon.tex:SetAllPoints()
    combatIcon.tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\combat", nil, nil, "TRILINEAR")
    -- combatIcon.tex:SetAtlas("combat_swords-dynamicIcon")

    -- 辉光纹理层：drawLayer -5（在剑图标下方），ADD 混合模式产生发光效果
    combatIcon.flashTex = combatIcon:CreateTexture(nil, "ARTWORK", nil, -5)
    combatIcon.flashTex:SetAllPoints()
    combatIcon.flashTex:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\combat_glow", nil, nil, "TRILINEAR")
    -- combatIcon.flashTex:SetAtlas("combat_swords-flash")
    combatIcon.flashTex:SetBlendMode("ADD")

    -- 创建 Alpha 闪烁动画（loop=REPEAT），在显示时自动播放
    A.CreateBlinkAnimation(combatIcon.flashTex, nil, true)

    combatIcon:SetScript("OnEvent", CombatIcon_OnEvent)

    combatIcon.UpdatePixelPerfect = CombatIcon_UpdatePixelPerfect

    return combatIcon
end

-------------------------------------------------
-- missing buffs
-- 缺失 Buff 指示器：显示单位身上缺少的团队 Buff（如智力、耐力等）。
-- 最多显示 3 个图标，每个图标在尺寸变化时自动触发按钮发光效果。
-- 由 BuffTracker 插件提供数据（通过 GROUP_ROSTER_UPDATE 触发），
-- EnableMissingBuffs / UpdateMissingBuffsFilters 控制启用和过滤条件。
-------------------------------------------------
function I.CreateMissingBuffs(parent)
    local missingBuffs = CreateFrame("Frame", parent:GetName().."MissingBuffParent", parent.widgets.indicatorFrame)
    parent.indicators.missingBuffs = missingBuffs
    missingBuffs:Hide()

    missingBuffs._SetSize = missingBuffs.SetSize
    missingBuffs.SetSize = I.Cooldowns_SetSize
    missingBuffs.UpdateSize = I.Cooldowns_UpdateSize
    missingBuffs.SetOrientation = I.Cooldowns_SetOrientation
    missingBuffs.UpdatePixelPerfect = I.Cooldowns_UpdatePixelPerfect

    for i = 1, 3 do
        local name = parent:GetName().."MissingBuff"..i
        local frame = I.CreateAura_BarIcon(name, missingBuffs)
        tinsert(missingBuffs, frame)
        -- 图标尺寸变化时自动触发按钮发光（LibCustomGlow ButtonGlow），持续提示缺失
        frame:HookScript("OnSizeChanged", function()
            LCG.ButtonGlow_Start(frame)
        end)
    end
end

-- 全局开关：是否启用缺失 Buff 指示器
local missingBuffsEnabled = false
function I.EnableMissingBuffs(enabled)
    missingBuffsEnabled = enabled

    if enabled and CellDB["tools"]["buffTracker"][1] then
        CellBuffTrackerFrame:GROUP_ROSTER_UPDATE(true)
    end
end

-- 更新缺失 Buff 的过滤条件并触发刷新。
-- noUpdate 为 true 时仅存储过滤配置而不立即刷新（用于批量配置）。
function I.UpdateMissingBuffsFilters(filters, noUpdate)
    if filters then missingBuffsFilters = filters end

    if not noUpdate and missingBuffsEnabled and CellDB["tools"]["buffTracker"][1] then
        CellBuffTrackerFrame:GROUP_ROSTER_UPDATE(true)
    end
end

-- 隐藏指定 Cell 单元按钮上的所有 3 个缺失 Buff 图标
local function HideMissingBuffs(b)
    for i = 1, 3 do
        b.indicators.missingBuffs[i]:Hide()
    end
end

-- 每个 unit 当前显示的缺失 Buff 数量计数器
local missingBuffsCounter = {}
-- 隐藏指定单位的缺失 Buff 指示器，并清除计数器。
-- force 参数允许在全局开关关闭时仍然强制隐藏。
function I.HideMissingBuffs(unit, force)
    if not (missingBuffsEnabled or force) then return end
    missingBuffsCounter[unit] = nil
    F.HandleUnitButton("unit", unit, HideMissingBuffs)
end

-- 在指定 Cell 单元按钮上显示一个缺失 Buff 图标（指定 index 位置和 icon 纹理）
local function ShowMissingBuff(b, index, icon)
    b.indicators.missingBuffs:UpdateSize(index)

    local f = b.indicators.missingBuffs[index]
    f:SetCooldown(0, 0, nil, icon, 0)
    LCG.ButtonGlow_Start(f)
end

-- 为指定单位显示一个缺失 Buff 图标。
-- 使用 missingBuffsCounter 跟踪每个单位的累计计数，最多显示 3 个。
function I.ShowMissingBuff(unit, icon)
    if not missingBuffsEnabled then return end

    missingBuffsCounter[unit] = (missingBuffsCounter[unit] or 0) + 1
    if missingBuffsCounter[unit] > 3 then return end

    F.HandleUnitButton("unit", unit, ShowMissingBuff, missingBuffsCounter[unit], icon)
end