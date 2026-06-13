-- TargetCounter Indicator
-- 目标计数器指示器：统计每个队友/团队成员当前被多少个敌方 nameplate 选为目标
-- 工作原理：持续扫描所有可见 nameplate 的 target，若 target 指向小队/团队成员则累加计数

local _, Cell = ...
local L = Cell.L
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs

-- 缓存全局函数引用，提升运行时性能
local UnitGUID = UnitGUID
local UnitCanAttack = UnitCanAttack
local UnitIsOtherPlayersPet = UnitIsOtherPlayersPet

-------------------------------------------------
-- events
-------------------------------------------------

-- 当前可见的敌对 nameplate 集合
-- key: nameplateUnitToken（nameplate 的单位标识），value: true（仅用于集合存在性检查）
local nameplates = {
    -- nameplateUnitId = true,
}

-- nameplate 当前目标的映射表
-- key: nameplateUnitToken，value: targetGUID（该 nameplate 当前锁定的目标 GUID）
local nameplateTargets = {
    -- nameplateUnitId = targetGUID,
}

-- 目标计数器核心数据结构：反向索引，记录每个友方单位被哪些 nameplate 锁定
-- key: friendGUID（友方单位 GUID），value: {[enemyNameplateToken]=true, ...}（所有锁定该友方单位的敌对 nameplate 集合）
local counter = {
    -- friendGUID = {enemyGUID=true, ...},
}

-- 事件处理框架：创建一个不可见 Frame 作为事件接收器
-- 通过元表方法 self[eventName] 将事件分派到对应的同名处理函数，实现事件名到处理函数的一对一映射
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end)

-- 事件处理：nameplate 被移除（消失、死亡、超出距离等）
-- 清理 nameplates 和 nameplateTargets 中对应的条目，保持数据一致性
function eventFrame:NAME_PLATE_UNIT_REMOVED(unit)
    nameplates[unit] = nil
    nameplateTargets[unit] = nil
end

-- 事件处理：nameplate 被添加（进入视野、新生成等）
-- 过滤条件：仅保留可被玩家攻击且非其他玩家宠物的单位（即非友方、非中立、非宠物）
function eventFrame:NAME_PLATE_UNIT_ADDED(unit)
    if not unit or not UnitCanAttack(unit, "player") or UnitIsOtherPlayersPet(unit) then return end
    nameplates[unit] = true
end

-- 全量扫描当前所有可见 nameplate
-- 在进入世界或启用指示器时调用，将现有 nameplate 全部纳入追踪
local function ScanNameplates()
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        eventFrame:NAME_PLATE_UNIT_ADDED(nameplate.namePlateUnitToken)
    end
end

-- 更新单个单位按钮上的计数器显示
-- 作为回调传递给 F.HandleUnitButton，由框架负责查找对应的按钮并调用
local function SetCount(b, count)
    b.indicators.targetCounter:SetCount(count)
end

-- 定时器对象引用，用于周期性计算目标计数
local ticker
-- 启动周期性计算定时器
-- 每 0.25 秒执行一次完整的扫描-计算-刷新流程
local function StartTicker()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.25, function()
        -- ===== 阶段1：重置 =====
        -- 清空上一轮的计算结果，为新一轮计算做准备
        -- 注意：nameplates 表不清空，因为它由事件 NAME_PLATE_UNIT_ADDED/REMOVED 维护
        for _, ct in pairs(counter) do
            wipe(ct)
        end

        -- ===== 阶段2：检查与计算 =====
        -- 遍历所有可见的敌对 nameplate，检查其当前目标
        for unit in pairs(nameplates) do
            local target = UnitGUID(unit.."target")

            -- Midnight 12.0.0+ 防护：UnitGUID 对 nameplate 目标可能返回 secret strings
            -- issecretvalue 检查防止 secret value 被存入表或进行后续运算，避免违反 Blizzard 安全策略
            -- Midnight 12.0.0+: UnitGUID for nameplate targets may return secret strings
            if Cell.isMidnight and issecretvalue and issecretvalue(target) then
                nameplateTargets[unit] = nil
            elseif not target then -- no target
                nameplateTargets[unit] = nil
            elseif not Cell.vars.guids[target] then -- target doesn't exists in player's group
                -- 目标不在当前队伍/团队中，清除记录并确保 counter 中不存在该项
                nameplateTargets[unit] = nil
                counter[target] = nil
            else
                -- 目标在队伍/团队中，更新 nameplate 到目标的映射
                nameplateTargets[unit] = target
            end

            -- 重新获取经过上述过滤后的有效目标
            target = nameplateTargets[unit]
            if target and Cell.vars.guids[target] then -- valid target exists
                if not counter[target] then counter[target] = {} end -- init
                -- 在 counter 中建立反向索引：友方目标 -> 锁定它的 nameplate 集合
                counter[target][unit] = true
            end
        end

        -- ===== 阶段3：更新指示器显示 =====
        -- 遍历所有队伍/团队成员，更新其目标计数器指示器
        -- 计数 = 锁定该成员的敌对 nameplate 数量
        for guid in pairs(Cell.vars.guids) do
            F.HandleUnitButton("guid", guid, SetCount, counter[guid] and F.Getn(counter[guid]) or 0)
        end
    end)
end

-- 停止周期性计算定时器
-- 释放定时器资源，将引用置 nil 以便垃圾回收
local function StopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end

-- 区域过滤器配置和模块启用状态
-- counterEnabled: 目标计数器是否已启用
-- zoneFilters: 按场景类型配置的启用过滤，包含 "outdoor"、"pvp"、"pve" 三个键
local counterEnabled, zoneFilters = false, {}

-- 事件处理：玩家进入世界（包括登录、切换地图、进出副本等）
-- 核心职责：根据当前场景类型和用户配置决定是否启用/停用目标计数器
function eventFrame:PLAYER_ENTERING_WORLD()
    -- ===== 重置 =====
    -- 清空所有运行时数据并重置所有指示器显示为 0
    wipe(nameplates)
    wipe(counter)
    F.IterateAllUnitButtons(function(b)
        b.indicators.targetCounter:SetCount(0)
    end, true)

    -- 获取当前实例类型
    local isIn, iType = IsInInstance()

    -- 根据实例类型匹配对应的区域过滤配置
    -- iType 为 "none" 表示户外（野外），"pvp"/"arena" 表示 PvP 场景，
    -- 其余（"party"/"raid"/"scenario"）归入 PvE 场景
    local isValidZone
    if not isIn or iType == "none" then
        isValidZone = zoneFilters["outdoor"]
    elseif iType == "pvp" or iType == "arena" then
        isValidZone = zoneFilters["pvp"]
    else -- party, raid, scenario
        isValidZone = zoneFilters["pve"]
    end

    -- 根据启用状态和区域过滤结果决定启动或停止追踪
    if counterEnabled and isValidZone then
        -- 启用：注册 nameplate 事件，扫描现有 nameplate，启动定时器
        eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        ScanNameplates()
        StartTicker()
    else
        -- 停用：注销事件（停止接收新 nameplate 通知），停止定时器
        eventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
        eventFrame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
        StopTicker()
    end
end

-- 公共接口：启用/禁用目标计数器指示器
-- @param enabled: true 启用，false 禁用
-- 启用时注册 PLAYER_ENTERING_WORLD 事件以感知场景切换，
-- 并立即调用 PLAYER_ENTERING_WORLD 处理函数检查当前场景状态
function I.EnableTargetCounter(enabled)
    if enabled then
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        counterEnabled = true
    else
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        counterEnabled = false
    end
    eventFrame:PLAYER_ENTERING_WORLD() -- check now
    -- texplore(nameplateTargets)
end

-- 公共接口：更新区域过滤器配置
-- @param filters: 包含 "outdoor"/"pvp"/"pve" 键的配置表，值为 true/false
-- @param noUpdate: 如果为 true，仅更新配置而不立即触发场景检查
function I.UpdateTargetCounterFilters(filters, noUpdate)
    if filters then zoneFilters = filters end
    if not noUpdate and counterEnabled then
        eventFrame:PLAYER_ENTERING_WORLD()
    end
end

-------------------------------------------------
-- CreateTargetCounter
-------------------------------------------------

-- 公共接口：为目标计数器指示器创建 UI 组件
-- 每个单位按钮（cell unit button）在初始化时会调用此函数创建其专属的目标计数器子 Frame
-- @param parent: 父 Frame，即单位按钮本身
function I.CreateTargetCounter(parent)
    -- 创建指示器子 Frame，命名规则为 <父Frame名>.."TargetCounter"
    local targetCounter = CreateFrame("Frame", parent:GetName().."TargetCounter", parent)
    parent.indicators.targetCounter = targetCounter
    targetCounter:Hide()

    -- 创建字体字符串，使用 CELL_FONT_STATUS 字体对象模板，
    -- 继承 Cell 状态文字的字体样式，确保视觉一致性
    local text = targetCounter:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    targetCounter.text = text
    -- stack:SetJustifyH("RIGHT")
    text:SetPoint("CENTER", 1, 0)

    -- 设置字体样式（字体名、字号、描边、阴影）
    -- @param font: 字体路径或别名，通过 F.GetFont 解析为实际路径
    -- @param size: 字号
    -- @param outline: 描边类型（"None" 无描边 / "Outline" 普通描边 / 其他：粗描边 MONOCHROME）
    -- @param shadow: 是否启用阴影
    -- 同时根据指示器相对于父 Frame 的锚点位置自动调整文字对齐方向
    function targetCounter:SetFont(font, size, outline, shadow)
        font = F.GetFont(font)

        local flags
        if outline == "None" then
            flags = ""
        elseif outline == "Outline" then
            flags = "OUTLINE"
        else
            flags = "OUTLINE,MONOCHROME"
        end

        text:SetFont(font, size, flags)

        -- 阴影设置：向右下偏移 1 像素，黑色半透明
        if shadow then
            text:SetShadowOffset(1, -1)
            text:SetShadowColor(0, 0, 0, 1)
        else
            text:SetShadowOffset(0, 0)
            text:SetShadowColor(0, 0, 0, 0)
        end

        -- 根据当前锚点自动调整文字对齐方向，使计数器文字紧贴指示器边缘
        local point = targetCounter:GetPoint(1)
        text:ClearAllPoints()
        if string.find(point, "LEFT") then
            text:SetPoint("LEFT")
        elseif string.find(point, "RIGHT") then
            text:SetPoint("RIGHT")
        else
            text:SetPoint("CENTER")
        end
        targetCounter:SetSize(size+3, size+3)
    end

    -- 重写 SetPoint 方法（装饰器模式）
    -- 保存原始 SetPoint 引用，在新方法中先处理文字对齐，再调用原始锚点设置
    -- 确保改变指示器位置时文字对齐方向始终跟随锚点方向
    targetCounter._SetPoint = targetCounter.SetPoint
    function targetCounter:SetPoint(point, relativeTo, relativePoint, x, y)
        text:ClearAllPoints()
        if string.find(point, "LEFT") then
            text:SetPoint("LEFT")
        elseif string.find(point, "RIGHT") then
            text:SetPoint("RIGHT")
        else
            text:SetPoint("CENTER")
        end
        targetCounter:_SetPoint(point, relativeTo, relativePoint, x, y)
    end

    -- 设置计数器显示数值
    -- @param n: 目标数量。为 0 时隐藏指示器，非 0 时显示并设置文字
    function targetCounter:SetCount(n)
        if n == 0 then
            targetCounter:Hide()
        else
            targetCounter:Show()
        end
        text:SetText(n)
    end

    -- 设置计数器文字颜色
    -- @param r, g, b: RGB 颜色分量（0-1 范围）
    function targetCounter:SetColor(r, g, b)
        text:SetTextColor(r, g, b)
    end
end
