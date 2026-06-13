--[[
    CellD 核心入口模块 (Core.lua)
    ==============================
    CellD 是一款魔兽世界团队框架插件，继承自 enderneko 的 Cell (r277-beta)。
    原作者因工作繁忙已停止更新，由 David W Zhang 继续维护。

    主要职责:
    1. 初始化全局 _G.Cell 命名空间和各子表（funcs/iFuncs/bFuncs/uFuncs/animations）
    2. 定义核心函数 F (CellFuncs): Debug, Print, UpdateLayout
    3. 管理布局自动切换逻辑 (solo/party/raid/battleground/arena)
    4. 注册游戏事件: VARIABLES_LOADED, ADDON_LOADED, PLAYER_LOGIN 等
    5. 初始化所有 SavedVariables 默认值 (CellDB 各类子表)
    6. 处理斜杠命令 (/celld, /cell 兼容)
    7. 管理插件状态: 专精切换、进出副本、团队配置

    全局架构:
    - _G.Cell 主表: 含所有子功能和数据
    - Cell.funcs (F): 核心工具函数集合 (CellFuncs)
    - Cell.iFuncs (I): 指示器相关函数 (CellIndicatorFuncs)
    - Cell.bFuncs (B): 单位按钮相关函数 (CellUnitButtonFuncs)
    - Cell.uFuncs (U): 工具模块函数 (CellUtilityFuncs)
    - Cell.animations: 动画函数集合 (CellAnimations)
    - Cell.pixelPerfectFuncs (P): 像素精确调整函数
    - CellDB: 全局账号级配置保存
    - CellDBBackup: 配置备份

    适配: 魔兽世界 12.0.5+ (Midnight) 正式服，不再支持怀旧服

    安全说明 (Secret Values / Opaque Types):
    暴雪在 12.0.0+ 中对战斗中敏感数据实施了 Secret Value 机制。
    在战斗/首领战/PvP中，UnitHealth/UnitPower/光环持续时间等会返回
    不可运算的 opaque 值。详见 BlackBox 自检模块和 Utils.lua 中的保护措施。
    -- 可通过以下 CVar 在非战斗时强制模拟 Secret Value 限制进行测试:
    -- /run SetCVar("secretCombatRestrictionsForced", 1)
    -- /run SetCVar("secretEncounterRestrictionsForced", 1)
    -- /run SetCVar("secretChallengeModeRestrictionsForced", 1)
    -- /run SetCVar("secretPvPMatchRestrictionsForced", 1)
    -- 重置: /run SetCVar("secretCombatRestrictionsForced", 0)
--]]

---@class Cell
local addonName = select(1, ...)                                   -- 插件文件夹名 "CellD"；用于 ADDON_LOADED 事件的 arg1 比对
local Cell = select(2, ...)                                        -- 插件加载时传入的全局表（由 .toc 文件声明）
_G.Cell = Cell                                                     -- 暴露到全局，供其他插件（如 OmniCD）通过 _G.Cell 访问

---@class Cell
---@field defaults table         -- 默认配置表
---@field frames table           -- UI框架引用
---@field vars table             -- 运行时变量
---@field snippetVars table      -- 代码片段共享变量
---@field funcs CellFuncs        -- 核心函数集
---@field iFuncs CellIndicatorFuncs -- 指示器函数集
---@field bFuncs CellUnitButtonFuncs -- 单位按钮函数集
---@field uFuncs CellUtilityFuncs -- 工具函数集
---@field animations CellAnimations -- 动画函数集

-- Cell 各类子表初始化（在 ADDON_LOADED 前创建，确保其他模块加载时可用）
Cell.defaults = {}                                                 -- 默认配置表，由 Defaults.lua 填充
Cell.frames = {}                                                   -- 所有 UI 框架引用集合（anchorFrame, raidMarksFrame 等）
Cell.vars = {}                                                     -- 运行时状态变量（专精、布局、团队类型等）
Cell.snippetVars = {}                                              -- 代码片段间共享的数据（各 snippet 通过此表通信）
Cell.funcs = {}                                                    -- 核心函数集 F (CellFuncs)，含 Debug/Print/UpdateLayout 等
Cell.iFuncs = {}                                                   -- 指示器函数集 I (CellIndicatorFuncs)
Cell.bFuncs = {}                                                   -- 单位按钮函数集 B (CellUnitButtonFuncs)
Cell.uFuncs = {}                                                   -- 工具模块函数集 U (CellUtilityFuncs)
Cell.animations = {}                                               -- 动画函数集 (CellAnimations)

---@class CellFuncs
local F = Cell.funcs                                               -- 核心函数快捷引用
local I = Cell.iFuncs                                              -- 指示器函数快捷引用
---@type PixelPerfectFuncs
local P = Cell.pixelPerfectFuncs                                   -- 像素精确调整函数快捷引用
local L = Cell.L                                                   -- 本地化字符串表快捷引用

-- CellD 版本共享检查协议版本号（从 1.0.0 起步，与原版 Cell r275 不兼容）
-- 各子模块（Indicators/Layouts/ClickCastings 等）更新时需递增对应版本号
Cell.MIN_VERSION = 1
Cell.MIN_CLICKCASTINGS_VERSION = 1
Cell.MIN_LAYOUTS_VERSION = 1
Cell.MIN_INDICATORS_VERSION = 1
Cell.MIN_DEBUFFS_VERSION = 1
Cell.MIN_QUICKASSIST_VERSION = 1

--[==[@debug@
local debugMode = true                                              -- 调试模式开关（@debug@ 包裹的代码仅在开发版本有效）
--@end-debug@]==]
-- 核心调试输出函数，支持多种参数类型：
--   string/number → print 输出；table → DevTools_Dump 输出；
--   function → 执行该函数；nil → 仅返回 true（用于检测调试模式是否开启）
-- Midnight 环境中若启用了 Secret Value 限制，print 的 opaque 值会显示为占位符
function F.Debug(arg, ...)
    if debugMode then
        if type(arg) == "string" or type(arg) == "number" then
            print(arg, ...)
        elseif type(arg) == "table" then
            DevTools_Dump(arg)
        elseif type(arg) == "function" then
            arg(...)
        elseif arg == nil then
            return true
        end
    end
end

-- 向聊天框输出带 CellD 红色前缀的消息（用户可见日志）
function F.Print(msg)
    print("|cFFFF3030[CellD]|r " .. msg)                            -- CellD 日志前缀（红色高亮）
end

--------------------------------------------------
-- CellParent — 主框架的父级容器，覆盖整个屏幕
-- 所有 Cell UI 元素（团队框体、指示器等）都以 CellParent 为坐标参考系
-- SetFrameLevel(0) 确保 CellParent 位于 UI 底层，不影响其他 UI 交互
--------------------------------------------------
local CellParent = CreateFrame("Frame", "CellParent", UIParent)
CellParent:SetAllPoints(UIParent)
CellParent:SetFrameLevel(0)


-------------------------------------------------
-- layout — 布局自动切换引擎
-- Cell 根据玩家所处游戏上下文（solo/party/raid_mythic/arena 等）
-- 自动切换到预设布局，实现无感界面适配
-------------------------------------------------
-- 战斗中无法立即切换布局，需缓存布局类型等待脱战后执行
local delayedLayoutGroupType                                          -- 缓存战斗中请求切换的布局类型
local delayedFrame = CreateFrame("Frame")                              -- 延迟帧：监听 PLAYER_REGEN_ENABLED 脱战事件
delayedFrame:SetScript("OnEvent", function()
    delayedFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    F.UpdateLayout(delayedLayoutGroupType)                             -- 脱战后立即执行延迟的布局切换
end)

-- 核心布局切换函数
-- layoutGroupType: 布局上下文类型 (solo/party/raid_mythic/raid_instance/raid_outdoor/arena/battleground15/battleground40)
-- 流程: 1) 战斗中延迟到脱战; 2) 查找当前专精/角色的自动切换配置;
--       3) 应用布局(或hide隐藏); 4) 清除指示器缓存; 5) 触发 UpdateLayout/UpdateIndicators 事件
-- 注意：Midnight/SecretValue 环境下此函数仅操作 UI 布局，不涉及战斗敏感数据，无需特殊防护
function F.UpdateLayout(layoutGroupType)
    if InCombatLockdown() then
        F.Debug("|cFF7CFC00F.UpdateLayout(\""..layoutGroupType.."\") DELAYED")
        delayedLayoutGroupType = layoutGroupType                         -- 缓存布局类型
        delayedFrame:RegisterEvent("PLAYER_REGEN_ENABLED")               -- 等待脱战
    else
        F.Debug("|cFF7CFC00F.UpdateLayout(\""..layoutGroupType.."\")")

        -- 布局自动切换优先级：专精级别 > 角色职能（TANK/HEALER/DAMAGER）
        -- CellDB["layoutAutoSwitch"][playerClass][playerSpecID] 对应某职业某专精在不同场景的布局选择
        if CellDB["layoutAutoSwitch"][Cell.vars.playerClass][Cell.vars.playerSpecID] then
            Cell.vars.layoutAutoSwitchBy = "spec"                        -- 按专精切换
            Cell.vars.layoutAutoSwitch = CellDB["layoutAutoSwitch"][Cell.vars.playerClass][Cell.vars.playerSpecID]
        else
            Cell.vars.layoutAutoSwitchBy = "role"                        -- 按职能切换（回退方案）
            Cell.vars.layoutAutoSwitch = CellDB["layoutAutoSwitch"]["role"][Cell.vars.playerSpecRole]
        end

        local layout = Cell.vars.layoutAutoSwitch[layoutGroupType]
        Cell.vars.layoutGroupType = layoutGroupType

        -- "hide" 特殊值：隐藏 Cell 框架，但仍使用 default 布局作为占位
        if layout == "hide" then
            Cell.vars.isHidden = true
            Cell.vars.currentLayout = "default"
            Cell.vars.currentLayoutTable = CellDB["layouts"]["default"]
        else
            Cell.vars.isHidden = false
            Cell.vars.currentLayout = layout
            Cell.vars.currentLayoutTable = CellDB["layouts"][layout]      -- 指向当前生效的布局配置表
        end

        -- 重置所有单位按钮的指示器就绪标志，强制下次更新时重新计算所有指示器
        F.IterateAllUnitButtons(function(b)
            b._indicatorsReady = nil
        end, true)

        Cell.Fire("UpdateLayout", layout)                                -- 通知所有监听者布局已切换
        Cell.Fire("UpdateIndicators")                                    -- 触发指示器完全刷新
    end
end

-- 战场最大人数映射表（某些大型战场如科尔拉克的复仇为 40 人）
local bgMaxPlayers = {
    [2197] = 40, -- 科尔拉克的复仇 (Alterac Valley variant)
}

-- layout auto switch — 布局自动切换调度入口
-- 根据当前 instanceType（pvp/arena/none）和 groupType（solo/party/raid）决定布局类型
-- 注册为 GroupTypeChanged / SpecChanged / LayoutAutoSwitchChanged 的回调
local instanceType                                                      -- 缓存当前副本类型
local function PreUpdateLayout()
    if not (Cell.vars.playerSpecID and Cell.vars.playerSpecRole) then return end  -- 专精信息未就绪时跳过

    if instanceType == "pvp" then
        -- 战场/评级战场：根据地图最大人数决定用 battleground15 还是 battleground40
        local name, _, _, _, _, _, _, id = GetInstanceInfo()
        if bgMaxPlayers[id] then
            if bgMaxPlayers[id] <= 15 then
                Cell.vars.inBattleground = 15
                F.UpdateLayout("battleground15")
            else
                Cell.vars.inBattleground = 40
                F.UpdateLayout("battleground40")
            end
        else
            Cell.vars.inBattleground = 15
            F.UpdateLayout("battleground15")
        end
    elseif instanceType == "arena" then
        Cell.vars.inBattleground = 5 -- 竞技场视为 5 人战场
        F.UpdateLayout("arena")
    else
        -- 非 PvP 场景：根据团队规模选择布局
        Cell.vars.inBattleground = false
        if Cell.vars.groupType == "solo" then
            F.UpdateLayout("solo")
        elseif Cell.vars.groupType == "party" then
            F.UpdateLayout("party")
        else -- raid
            -- 团队副本进一步细分：史诗难度 / 普通英雄副本内 / 野外
            if Cell.vars.inMythic then
                F.UpdateLayout("raid_mythic")
            elseif Cell.vars.inInstance then
                F.UpdateLayout("raid_instance")
            else
                F.UpdateLayout("raid_outdoor")
            end
        end
    end
end
-- 注册三个核心回调：任一变化都触发 PreUpdateLayout 重新评估布局
Cell.RegisterCallback("GroupTypeChanged", "Core_GroupTypeChanged", PreUpdateLayout)
Cell.RegisterCallback("SpecChanged", "Core_SpecChanged", PreUpdateLayout)
Cell.RegisterCallback("LayoutAutoSwitchChanged", "Core_LayoutAutoSwitchChanged", PreUpdateLayout)

-------------------------------------------------
-- events — 游戏事件监听框架
-- eventFrame 是 Core.lua 的核心事件中转站，负责监听所有游戏级事件
-- 通过 SetScript("OnEvent", ...) 动态派发到同名方法
-------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("VARIABLES_LOADED")                           -- 所有 SavedVariables 可用
eventFrame:RegisterEvent("ADDON_LOADED")                               -- 插件逐一加载通知
eventFrame:RegisterEvent("PLAYER_LOGIN")                               -- 角色完全登录
-- eventFrame:RegisterEvent("LOADING_SCREEN_DISABLED")                 -- [已停用] 加载界面消失时触发 GC

-- function eventFrame:LOADING_SCREEN_DISABLED()
--     if not InCombatLockdown() and not UnitAffectingCombat("player") then
--         F.Debug("|cffbbbbbbLOADING_SCREEN_DISABLED: |cffff7777collectgarbage")
--         collectgarbage("collect")
--     end
-- end

-- VARIABLES_LOADED：所有 SavedVariables 数据已加载完毕，但 UI 尚未初始化
function eventFrame:VARIABLES_LOADED()
    SetCVar("predictedHealth", 1)                                      -- 启用生命值预测（让 UnitHealth 返回预估而非精确值）
                                                                       -- Midnight 环境中 predictedHealth 可减少 Secret Value 触发频率
end

-- 本地化缓存常用 API，减少全局查找开销（高频调用路径优化）
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local UnitGUID = UnitGUID
-- local IsInBattleGround = C_PvP.IsBattleground -- NOTE: PLAYER_ENTERING_WORLD 刚触发时无法获取有效值
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata  -- 兼容新旧 API

-- local cellLoaded, omnicdLoaded
-- ADDON_LOADED：核心初始化入口，仅在 arg1 == addonName 时执行一次
-- 负责初始化所有 SavedVariables 默认值、数据迁移（Revise）、布局验证等
-- 这是 CellD 最重的初始化函数，执行顺序很重要（先设默认值，再数据迁移，最后验证）
function eventFrame:ADDON_LOADED(arg1)
    if arg1 == addonName then
        -- CellD 插件加载完成，初始化所有 SavedVariables
        eventFrame:UnregisterEvent("ADDON_LOADED")

        -- 保护性初始化：确保 CellDB/CellDBBackup 是合法表
        if type(CellDB) ~= "table" then CellDB = {} end
        if type(CellDBBackup) ~= "table" then CellDBBackup = {} end

        if type(CellDB["optionsFramePosition"]) ~= "table" then CellDB["optionsFramePosition"] = {} end

        -- 指示器预览设置（默认缩放 2x，不显示所有单位）
        if type(CellDB["indicatorPreview"]) ~= "table" then
            CellDB["indicatorPreview"] = {
                ["scale"] = 2,
                ["showAll"] = false,
            }
        end

        if type(CellDB["customTextures"]) ~= "table" then CellDB["customTextures"] = {} end

        Cell.vars.playerClass, Cell.vars.playerClassID = UnitClassBase("player")

        -- general ----------------------------------------------------------------
        -- 通用设置：工具提示、暴雪框体隐藏、锁定、渐隐、菜单位置、光环更新策略等
        -- "framePriority" 决定 Main / Spotlight / Quick Assist 三个子框架的层级顺序
        if type(CellDB["general"]) ~= "table" then
            CellDB["general"] = {
                ["enableTooltips"] = false,
                ["hideTooltipsInCombat"] = true,
                ["tooltipsPosition"] = {"BOTTOMLEFT", "Default", "TOPLEFT", 0, 15},
                ["hideBlizzardParty"] = true,
                ["hideBlizzardRaid"] = true,
                ["hideBlizzardRaidManager"] = true,
                ["locked"] = false,
                ["fadeOut"] = false,
                ["menuPosition"] = "top_bottom",
                ["alwaysUpdateAuras"] = false,
                ["framePriority"] = {
                    {"Main", true},
                    {"Spotlight", false},
                    {"Quick Assist", false},
                },
                ["useCleuHealthUpdater"] = false,
                ["translit"] = false,
            }
        end
        Cell.vars.alwaysUpdateAuras = CellDB["general"]["alwaysUpdateAuras"]     -- 缓存到 vars 提高访问速度

        -- nicknames --------------------------------------------------------------
        -- 昵称系统："mine" 自定义自己的昵称，"sync" 是否同步，"list" 昵称映射表
        if type(CellDB["nicknames"]) ~= "table" then
            CellDB["nicknames"] = {
                ["mine"] = "",
                ["sync"] = false,
                ["custom"] = false,
                ["list"] = {},
                ["blacklist"] = {},
            }
        end

        -- tools ------------------------------------------------------------------
        -- 内置工具模块：战复计时/增益追踪/死亡报告/就位确认/标记助手
        if type(CellDB["tools"]) ~= "table" then
            CellDB["tools"] = {
                ["battleResTimer"] = {true, false, {}},
                ["buffTracker"] = {false, "left-to-right", 32, {}, {}},
                ["deathReport"] = {false, 10},
                ["readyAndPull"] = {false, "text_button", {"default", 7}, {}},
                ["marks"] = {false, false, "both_h", {}},
                ["fadeOut"] = false,
            }
        end

        -- spellRequest -----------------------------------------------------------
        -- 技能请求模块（能量灌注/激活等外增技能请求与通知）
        if type(CellDB["spellRequest"]) ~= "table" then
            local POWER_INFUSION, POWER_INFUSION_ICON = F.GetSpellInfo(10060)
            local INNERVATE, INNERVATE_ICON = F.GetSpellInfo(29166)

            CellDB["spellRequest"] = {
                ["enabled"] = false,
                ["checkIfExists"] = true,
                ["knownSpellsOnly"] = true,
                ["freeCooldownOnly"] = true,
                ["replyCooldown"] = true,
                ["responseType"] = "me",
                ["timeout"] = 10,
                -- ["replyAfterCast"] = nil,
                ["sharedIconOptions"] = {
                    "beat", -- [1] animation
                    27, -- [2] size
                    "BOTTOMRIGHT", -- [3] anchor
                    "BOTTOMRIGHT", -- [4] anchorTo
                    0, -- [5] x
                    0, -- [6] y
                },
                ["spells"] = {
                    {
                        ["spellId"] = 10060,
                        ["buffId"] = 10060,
                        ["keywords"] = POWER_INFUSION,
                        ["icon"] = POWER_INFUSION_ICON,
                        ["type"] = "icon",
                        ["iconColor"] = {1, 1, 0, 1},
                        ["glowOptions"] = {
                            "pixel", -- [1] glow type
                            {
                                {1,1,0,1}, -- [1] color
                                0, -- [2] x
                                0, -- [3] y
                                9, -- [4] N
                                0.25, -- [5] frequency
                                8, -- [6] length
                                2 -- [7] thickness
                            } -- [2] glowOptions
                        },
                        ["isBuiltIn"] = true
                    },
                    {
                        ["spellId"] = 29166,
                        ["buffId"] = 29166,
                        ["keywords"] = INNERVATE,
                        ["icon"] = INNERVATE_ICON,
                        ["type"] = "icon",
                        ["iconColor"] = {0, 1, 1, 1},
                        ["glowOptions"] = {
                            "pixel", -- [1] glow type
                            {
                                {0, 1, 1, 1}, -- [1] color
                                0, -- [2] x
                                0, -- [3] y
                                9, -- [4] N
                                0.25, -- [5] frequency
                                8, -- [6] length
                                2 -- [7] thickness
                            } -- [2] glowOptions
                        },
                        ["isBuiltIn"] = true
                    },
                },
            }
        end

        -- dispelRequest ----------------------------------------------------------
        -- 驱散请求模块：检测可驱散 debuff 并通知队友驱散
        if type(CellDB["dispelRequest"]) ~= "table" then
            CellDB["dispelRequest"] = {
                ["enabled"] = false,
                ["dispellableByMe"] = true,
                ["responseType"] = "all",
                ["timeout"] = 10,
                ["debuffs"] = {},
                ["type"] = "text",
                ["textOptions"] = {
                    "A",
                    {1, 1, 1, 1}, -- [1] color
                    32, -- [2] size
                    "TOPLEFT", -- [3] anchor
                    "TOPLEFT", -- [4] anchorTo
                    -1, -- [5] x
                    5, -- [6] y
                },
                ["glowOptions"] = {
                    "shine", -- [1] glow type
                    {
                        {1, 0, 0.4, 1}, -- [1] color
                        0, -- [2] x
                        0, -- [3] y
                        9, -- [4] N
                        0.5, -- [5] frequency
                        2, -- [6] scale
                    } -- [2] glowOptions
                }
            }
        end

        -- quickAssist ------------------------------------------------------------
        -- 快速协助模块：点击队友一键对其施放预设技能
        if type(CellDB["quickAssist"]) ~= "table" then CellDB["quickAssist"] = {} end

        -- quickCast --------------------------------------------------------------
        -- 快速施法模块：鼠标悬停在团队框体上按快捷键施法
        if type(CellDB["quickCast"]) ~= "table" then CellDB["quickCast"] = {} end
        -- 清理无效的快速施法配置：移除既未启用也无 buff 条件的条目
        for c, ct in pairs(CellDB["quickCast"]) do
            for s, st in pairs(ct) do
                if not st["enabled"] and st["outerBuff"] == 0 and st["innerBuff"] == 0 then
                    ct[s] = nil
                end
            end
            if F.Getn(ct) == 0 then
                CellDB["quickCast"][c] = nil
            end
        end

        -- appearance -------------------------------------------------------------
        -- 外观设置：缩放、间距、字体等，从 defaults.appearance 深拷贝默认值
        if type(CellDB["appearance"]) ~= "table" then
            CellDB["appearance"] = F.Copy(Cell.defaults.appearance)
        end

        -- color ------------------------------------------------------------------
        -- r103 之前 accentColor 存储在 appearance 中，现已迁移到独立模块
        if CellDB["appearance"]["accentColor"] then -- version < r103 旧数据迁移
            if CellDB["appearance"]["accentColor"][1] == "custom" then
                Cell.OverrideAccentColor(CellDB["appearance"]["accentColor"][2])
            end
        end

        -- click-casting ----------------------------------------------------------
        -- 点击施法模块：鼠标左右键/组合键点击队友框体施放技能
        -- 每个职业有独立的配置表，包含 "common"（通用）和按专精的绑定
        if type(CellDB["clickCastings"]) ~= "table" then CellDB["clickCastings"] = {} end

        -- 为当前职业初始化点击施法默认值（如果尚未配置）
        if type(CellDB["clickCastings"][Cell.vars.playerClass]) ~= "table" then
            CellDB["clickCastings"][Cell.vars.playerClass] = {
                ["useCommon"] = true,
                ["smartResurrection"] = "disabled",
                ["alwaysTargeting"] = {
                    ["common"] = "disabled",
                },
                ["common"] = {
                    {"type1", "target"},
                    {"type2", "togglemenu"},
                },
            }

            -- add resurrections for "common"
            for _, t in pairs(F.GetResurrectionClickCastings(Cell.vars.playerClass)) do
                tinsert(CellDB["clickCastings"][Cell.vars.playerClass]["common"], t)
            end

            -- https://wow.gamepedia.com/SpecializationID
            -- 为各专精（含未选择专精时的 "Initial" 状态）初始化点击施法默认绑定
            local specs = {}
            do
                local specID
                --! 此时 GetNumSpecializations / GetSpecializationInfo 返回 nil
                --  因此使用 GetSpecializationInfoForClassID + GetNumSpecializationsForClassID 替代
                for i = 1, GetNumSpecializationsForClassID(Cell.vars.playerClassID) do
                    specID = GetSpecializationInfoForClassID(Cell.vars.playerClassID, i)
                    tinsert(specs, specID)
                end
                specID = GetSpecializationInfoForClassID(Cell.vars.playerClassID, 5)
                tinsert(specs, specID) -- "Initial" (no spec)
            end

            for _, specID in pairs(specs) do
                CellDB["clickCastings"][Cell.vars.playerClass]["alwaysTargeting"][specID] = "disabled"
                CellDB["clickCastings"][Cell.vars.playerClass][specID] = {
                    {"type1", "target"},
                    {"type2", "togglemenu"},
                }
                -- add resurrections for each spec
                for _, t in pairs(F.GetResurrectionClickCastings(Cell.vars.playerClass)) do
                    tinsert(CellDB["clickCastings"][Cell.vars.playerClass][specID], t)
                end
            end
        end
        Cell.vars.clickCastings = CellDB["clickCastings"][Cell.vars.playerClass]

        -- layouts ----------------------------------------------------------------
        -- 布局系统：存储所有自定义布局配置
        -- "default" 是回退布局，始终存在，不可删除
        if type(CellDB["layouts"]) ~= "table" then
            CellDB["layouts"] = {
                ["default"] = F.Copy(Cell.defaults.layout)
            }
        end

        -- layoutAutoSwitch -------------------------------------------------------
        -- 布局自动切换表结构：
        --   ["role"][TANK/HEALER/DAMAGER][solo/party/raid_mythic/...] = "layoutName"
        --   [playerClass][specID][solo/party/raid_mythic/...] = "layoutName"
        -- 专精级配置优先级高于职能级配置
        if type(CellDB["layoutAutoSwitch"]) ~= "table" then
            CellDB["layoutAutoSwitch"] = {
                ["role"] = {
                    ["TANK"] = F.Copy(Cell.defaults.layoutAutoSwitch),
                    ["HEALER"] = F.Copy(Cell.defaults.layoutAutoSwitch),
                    ["DAMAGER"] = F.Copy(Cell.defaults.layoutAutoSwitch),
                }
            }
        end

        if type(CellDB["layoutAutoSwitch"][Cell.vars.playerClass]) ~= "table" then
            CellDB["layoutAutoSwitch"][Cell.vars.playerClass] = {}
        end

        -- dispelBlacklist --------------------------------------------------------
        -- 驱散黑名单：不需要提示驱散的 debuff 列表
        if type(CellDB["dispelBlacklist"]) ~= "table" then
            CellDB["dispelBlacklist"] = I.GetDefaultDispelBlacklist()
        end
        Cell.vars.dispelBlacklist = F.ConvertTable(CellDB["dispelBlacklist"])      -- 转为运行时高效查找表

        -- debuffBlacklist --------------------------------------------------------
        -- Debuff 黑名单：不在框体上显示的 debuff 列表
        if type(CellDB["debuffBlacklist"]) ~= "table" then
            CellDB["debuffBlacklist"] = I.GetDefaultDebuffBlacklist()
        end
        Cell.vars.debuffBlacklist = F.ConvertTable(CellDB["debuffBlacklist"])

        -- bigDebuffs -------------------------------------------------------------
        -- 大型 Debuff 列表：需要放大显示的 debuff（如点名技能）
        if type(CellDB["bigDebuffs"]) ~= "table" then
            CellDB["bigDebuffs"] = I.GetDefaultBigDebuffs()
        end
        Cell.vars.bigDebuffs = F.ConvertTable(CellDB["bigDebuffs"])

        -- debuffTypeColor --------------------------------------------------------
        -- Debuff 类型颜色配置（魔法/诅咒/中毒/疾病等）
        if type(CellDB["debuffTypeColor"]) ~= "table" then
            I.ResetDebuffTypeColor()
        end

        -- aoeHealings ------------------------------------------------------------
        -- 群体治疗技能追踪（宁静、圣疗等）：disabled 禁用列表 / custom 自定义列表
        if type(CellDB["aoeHealings"]) ~= "table" then CellDB["aoeHealings"] = {["disabled"]={}, ["custom"]={}} end

        -- defensives/externals ---------------------------------------------------
        -- 防御/外增技能追踪：disabled 禁用列表 / custom 自定义列表
        if type(CellDB["defensives"]) ~= "table" then CellDB["defensives"] = {["disabled"]={}, ["custom"]={}} end
        if type(CellDB["externals"]) ~= "table" then CellDB["externals"] = {["disabled"]={}, ["custom"]={}} end

        -- raid debuffs -----------------------------------------------------------
        -- 团队副本 Debuff 配置：按 instanceId -> bossId -> spellId 三级索引
        if type(CellDB["raidDebuffs"]) ~= "table" then CellDB["raidDebuffs"] = {} end
        -- CellDB["raidDebuffs"] = {
        --     [instanceId] = {
        --         ["general"] = {
        --             [spellId] = {order, glowType, glowColor},
        --         },
        --         [bossId] = {
        --             [spellId] = {order, glowType, glowColor},
        --         },
        --     }
        -- }

        -- [已停用] CLEU 光环更新：之前通过战斗日志事件更新光环，现已改用 UNIT_AURA
        -- if type(CellDB["cleuAuras"]) ~= "table" then CellDB["cleuAuras"] = {} end
        -- I.UpdateCleuAuras(CellDB["cleuAuras"])

        -- [已停用] CLEU 发光效果：之前使用战斗日志检测特定光环的发光
        -- if type(CellDB["cleuGlow"]) ~= "table" then
        --     CellDB["cleuGlow"] = {"Pixel", {{0, 1, 1, 1}, 9, 0.25, 8, 2}}
        -- end

        -- targetedSpells ---------------------------------------------------------
        -- 目标技能追踪：检测 BOSS 正在对谁读条（如点名技能）
        if type(CellDB["targetedSpellsList"]) ~= "table" then
            CellDB["targetedSpellsList"] = I.GetDefaultTargetedSpellsList()
        end
        Cell.vars.targetedSpellsList = F.ConvertTable(CellDB["targetedSpellsList"])

        -- 目标技能发光效果配置
        if type(CellDB["targetedSpellsGlow"]) ~= "table" then
            CellDB["targetedSpellsGlow"] = I.GetDefaultTargetedSpellsGlow()
        end
        Cell.vars.targetedSpellsGlow = CellDB["targetedSpellsGlow"]

        -- crowdControls ----------------------------------------------------------
        -- 控制技能追踪：昏迷/恐惧/变形等软硬控
        if type(CellDB["crowdControls"]) ~= "table" then CellDB["crowdControls"] = {["disabled"]={}, ["custom"]={}} end

        -- actions ----------------------------------------------------------------
        -- 动作模块：如右键菜单项、自定义操作等
        if type(CellDB["actions"]) ~= "table" then
            CellDB["actions"] = I.GetDefaultActions()
        end
        Cell.vars.actions = I.ConvertActions(CellDB["actions"])

        -- misc -------------------------------------------------------------------
        -- 版本信息与数据迁移
        Cell.version = GetAddOnMetadata(addonName, "Version") or "1.0.0"
        Cell.versionNum = tonumber(string.match(Cell.version, "%d+"))
        if not CellDB["revise"] then CellDB["firstRun"] = true end           -- 首次运行标记
        F.Revise()                                                           -- 执行数据版本迁移（处理旧版配置兼容性）

        -- validation -------------------------------------------------------------
        -- 验证布局：检查自动切换配置中引用的布局是否真实存在，不存在则回退到 "default"
        for _, roleOrClass in pairs(CellDB["layoutAutoSwitch"]) do
            for _, t in pairs(roleOrClass) do
                for groupType, layout in pairs(t) do
                    if layout ~= "hide" and not CellDB["layouts"][layout] then
                        t[groupType] = "default"
                    end
                end
            end
        end

        -- 标记插件核心加载完成，触发 AddonLoaded 事件通知所有子模块
        Cell.loaded = true
        Cell.Fire("AddonLoaded")
    end

    -- omnicd ---------------------------------------------------------------------
    -- [已停用] OmniCD 团队技能冷却插件集成
    -- 如果后续需要重新启用，取消注释下方代码
    -- if arg1 == "OmniCD" then
    --     omnicdLoaded = true

    --     local E = OmniCD[1]
    --     tinsert(E.unitFrameData, 1, {
    --         [1] = "Cell",
    --         [2] = "CellPartyFrameMember",
    --         [3] = "unitid",
    --         [4] = 1,
    --     })

    --     local function UnitFrames()
    --         if not E.customUF.optionTable.Cell then
    --             E.customUF.optionTable.Cell = "Cell"
    --             E.customUF.optionTable.enabled.Cell = {
    --                 ["delay"] = 1,
    --                 ["frame"] = "CellPartyFrameMember",
    --                 ["unit"] = "unitid",
    --             }
    --         end
    --     end
    --     hooksecurefunc(E, "UnitFrames", UnitFrames)
    -- end

    -- if cellLoaded and omnicdLoaded then
    --     eventFrame:UnregisterEvent("ADDON_LOADED")
    -- end
end

-- 团队配置表：按角色（TANK/HEALER/DAMAGER）存储各职业人数
-- 结构: ["TANK"]["WARRIOR"] = 2, ["TANK"]["ALL"] = 4
Cell.vars.raidSetup = {
    ["TANK"]={["ALL"]=0},
    ["HEALER"]={["ALL"]=0},
    ["DAMAGER"]={["ALL"]=0},
}

-- GROUP_ROSTER_UPDATE：团队/队伍成员变动时触发
-- 流程: 1) 检测 groupType 变化 (solo/party/raid) 并触发 GroupTypeChanged;
--       2) 更新 raidSetup 成员统计;
--       3) 清理多余的 unitButtons;
--       4) 检查权限变化 (助手/团长标记权限);
--       5) 更新 fallbackGroupType 存档
-- skipFallbackUpdate: 内部参数，首次调用时跳过存档写入避免污染
function eventFrame:GROUP_ROSTER_UPDATE(skipFallbackUpdate)
    if IsInRaid() then
        -- 从 solo/party 切换到 raid 时，触发 GroupTypeChanged 事件
        if Cell.vars.groupType ~= "raid" then
            Cell.vars.groupType = "raid"
            F.Debug("|cffffbb77GroupTypeChanged:|r raid")
            Cell.Fire("GroupTypeChanged", "raid")
        end

        -- 重置团队配置统计（每次 roster 更新时全部重建以确保准确性）
        for _, t in pairs(Cell.vars.raidSetup) do
            for class in pairs(t) do
                if class == "ALL" then
                    t["ALL"] = 0
                else
                    t[class] = nil
                end
            end
        end

        -- 遍历所有团队成员，更新 raidSetup 统计和 GUID 映射
        -- GetRaidRosterInfo 返回成员的职业和角色信息
        for i = 1, GetNumGroupMembers() do
            -- 获取第 i 个成员的角色（TANK/HEALER/DAMAGER）
            local _, _, _, _, _, class, _, _, _, _, _, role = GetRaidRosterInfo(i)
            if not role or role == "NONE" then role = "DAMAGER" end          -- 无职责默认视为伤害输出
            -- update ALL
            Cell.vars.raidSetup[role]["ALL"] = Cell.vars.raidSetup[role]["ALL"] + 1
            -- update for each class
            if class then
                if not Cell.vars.raidSetup[role][class] then
                    Cell.vars.raidSetup[role][class] = 1
                else
                    Cell.vars.raidSetup[role][class] = Cell.vars.raidSetup[role][class] + 1
                end
            end
        end

        -- update Cell.unitButtons.raid.units
        for i = GetNumGroupMembers()+1, 40 do
            Cell.unitButtons.raid.units["raid"..i] = nil
            _G["CellRaidFrameMember"..i] = nil
        end
        F.UpdateRaidSetup()

        -- update Cell.unitButtons.party.units
        Cell.unitButtons.party.units["player"] = nil
        Cell.unitButtons.party.units["pet"] = nil
        for i = 1, 4 do
            Cell.unitButtons.party.units["party"..i] = nil
            Cell.unitButtons.party.units["partypet"..i] = nil
        end

    elseif IsInGroup() then
        -- 5 人小队模式
        if Cell.vars.groupType ~= "party" then
            Cell.vars.groupType = "party"
            F.Debug("|cffffbb77GroupTypeChanged:|r party")
            Cell.Fire("GroupTypeChanged", "party")
        end

        -- update Cell.unitButtons.raid.units
        for i = 1, 40 do
            Cell.unitButtons.raid.units["raid"..i] = nil
            _G["CellRaidFrameMember"..i] = nil
        end

        -- update Cell.unitButtons.party.units
        for i = GetNumGroupMembers(), 4 do
            Cell.unitButtons.party.units["party"..i] = nil
            Cell.unitButtons.party.units["partypet"..i] = nil
        end

    else
        -- 单人模式（不在任何队伍中）
        if Cell.vars.groupType ~= "solo" then
            Cell.vars.groupType = "solo"
            F.Debug("|cffffbb77GroupTypeChanged:|r solo")
            Cell.Fire("GroupTypeChanged", "solo")
        end

        -- update Cell.unitButtons.raid.units
        for i = 1, 40 do
            Cell.unitButtons.raid.units["raid"..i] = nil
            _G["CellRaidFrameMember"..i] = nil
        end

        -- update Cell.unitButtons.party.units
        Cell.unitButtons.party.units["player"] = nil
        Cell.unitButtons.party.units["pet"] = nil
        for i = 1, 4 do
            Cell.unitButtons.party.units["party"..i] = nil
            Cell.unitButtons.party.units["partypet"..i] = nil
        end
    end

    -- 检查团队权限是否变化（是否为助手/团长，是否有队伍标记权限）
    -- 权限变化时触发 PermissionChanged 事件，影响菜单显示项等
    if Cell.vars.hasPermission ~= F.HasPermission() or Cell.vars.hasPartyMarkPermission ~= F.HasPermission(true) then
        Cell.vars.hasPermission = F.HasPermission()
        Cell.vars.hasPartyMarkPermission = F.HasPermission(true)
        Cell.Fire("PermissionChanged")
        F.Debug("|cffbb00bbPermissionChanged")
    end

    -- 存档当前团队类型到 CellDB.fallbackGroupType，用于重载/登录恢复
    if not skipFallbackUpdate then
        CellDB.fallbackGroupType = Cell.vars.groupType
    end
end

-- 副本进出状态追踪（用于检测玩家进出副本实例）
local inInstance

-- 回退团队类型验证：PLAYER_ENTERING_WORLD 1 秒后调用
-- IsInRaid/IsInGroup 在登录瞬间返回 false，延迟调用可获取真实状态
-- 如果真实状态与缓存的 groupType 不一致，则纠正并触发 GroupTypeChanged
local function UpdateFallbackGroupType()
    if IsInRaid() then
        CellDB.fallbackGroupType = "raid"
    elseif IsInGroup() then
        CellDB.fallbackGroupType = "party"
    else
        CellDB.fallbackGroupType = "solo"
    end

    if Cell.vars.groupType ~= CellDB.fallbackGroupType then
        Cell.vars.groupType = CellDB.fallbackGroupType
        F.Debug("|cffffbb77GroupTypeChanged:|r", Cell.vars.groupType, "(fallback validation)")
        Cell.Fire("GroupTypeChanged", Cell.vars.groupType)
    end
end

-- PLAYER_ENTERING_WORLD：每次进入游戏世界时触发（登录、重载、进出副本、传送等）
-- 核心职责：检测副本进出、延迟检查史诗难度、回退团队类型恢复、首次运行引导
-- Secret Value 注意：此处使用 IsInInstance/GetInstanceInfo 均非战斗敏感 API，安全
function eventFrame:PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    -- eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    F.Debug("|cffbbbbbb=== PLAYER_ENTERING_WORLD ===")
    Cell.vars.inMythic = false                                                -- 默认非史诗难度

    local isIn, iType = IsInInstance()
    instanceType = iType                                                      -- 更新缓存（供 PreUpdateLayout 使用）
    Cell.vars.inInstance = isIn
    Cell.vars.instanceType = iType

    C_Timer.After(1, UpdateFallbackGroupType)                                  -- 1 秒后验证团队类型（给予 API 初始化时间）

    if isIn then
        F.Debug("|cffff1111*** Entered Instance:|r", iType)
        Cell.Fire("EnterInstance", iType)                                      -- 通知子模块已进入副本

        --! NOTE: 登录/重载时 IsInRaid/IsInGroup 始终返回 false
        --  因此依赖 fallback 机制从 CellDB 恢复之前的团队类型
        if (isInitialLogin or isReloadingUi) and CellDB.fallbackGroupType then
            F.Debug("|cffff1111*** Fallback:|r", Cell.vars.groupType, "->", CellDB.fallbackGroupType, CellDB.fallbackInMythic)
            Cell.vars.groupType = CellDB.fallbackGroupType
            Cell.vars.inMythic = CellDB.fallbackInMythic
            CellDB.fallbackGroupType = nil                                     -- 清除回退标记（仅使用一次）
            CellDB.fallbackInMythic = nil
            Cell.Fire("GroupTypeChanged", Cell.vars.groupType)
        else
            PreUpdateLayout()
        end
        inInstance = true                                                      -- 标记已进入副本

        -- 延迟检查史诗难度：进入副本瞬间 GetInstanceInfo 无法返回 difficultyID
        -- difficultyID == 16 代表史诗难度团队副本
        if iType == "raid" and Cell.vars.groupType == "raid" then
            C_Timer.After(0.5, function()
                local difficultyID, difficultyName = select(3, GetInstanceInfo()) --! 进入副本瞬间无法获取 difficultyID
                Cell.vars.inMythic = difficultyID == 16                        -- 难度 ID 16 = 史诗
                CellDB.fallbackInMythic = Cell.vars.inMythic

                -- 如果检测到史诗难度但布局未切换，则重新触发
                if Cell.vars.inMythic and Cell.vars.layoutGroupType ~= "raid_mythic" then
                    F.Debug("|cffff1111*** Switch to Mythic Raid layout|r")
                    Cell.Fire("EnterInstance", iType)
                    PreUpdateLayout()
                end
            end)
        else
            Cell.vars.inMythic = nil
        end

    elseif inInstance then -- 之前 inInstance=true 但现在不在副本中 → 离开副本
        F.Debug("|cffff1111*** Left Instance|r")
        Cell.Fire("LeaveInstance")                                             -- 通知子模块已离开副本
        PreUpdateLayout()
        inInstance = false

        -- 离副且非战斗时触发完整 GC，释放战斗中无法回收的内存
        -- Midnight 环境中 Secret Value 限制解除后，GC 可回收之前的 opaque 对象
        if not InCombatLockdown() and not UnitAffectingCombat("player") then
            F.Debug("|cffbbbbbb--- LeftInstance: |cffff7777collectgarbage")
            collectgarbage("collect")
        end
    end

    -- 首次运行引导：创建治疗者指示器等默认配置
    if CellDB["firstRun"] then
        F.FirstRun()
    end
end

-- REVIEW:
-- local function RegisterGlobalClickCastings()
--     ClickCastFrames = ClickCastFrames or {}

--     if ClickCastFrames then
--         for frame, options in pairs(ClickCastFrames) do
--             F.RegisterFrame(frame)
--         end
--     end

--     ClickCastFrames = setmetatable({}, {__newindex = function(t, k, v)
--         if v == nil or v == false then
--             F.UnregisterFrame(k)
--         else
--             F.RegisterFrame(k)
--         end
--     end})

--     F.IterateAllUnitButtons(function (b)
--         ClickCastFrames[b] = true
--     end)
-- end

-- 更新当前专精信息到 Cell.vars
-- 专精信息由 GetSpecialization/GetSpecializationInfo 获取
-- 未选专精时显示 "No Spec"，使用默认图标 134400
local function UpdateSpecVars()
    Cell.vars.playerSpecID, Cell.vars.playerSpecName, _, Cell.vars.playerSpecIcon, Cell.vars.playerSpecRole = GetSpecializationInfo(GetSpecialization())
    if not Cell.vars.playerSpecName or Cell.vars.playerSpecName == "" then
        Cell.vars.playerSpecName = L["No Spec"]
        Cell.vars.playerSpecIcon = 134400                                          -- 默认专精图标
    end
end

-- PLAYER_LOGIN：角色完全登录后执行一次性初始化
-- 此时所有 API（GetSpecializationInfo 等）均已可用
function eventFrame:PLAYER_LOGIN()
    F.Debug("|cffbbbbbb=== PLAYER_LOGIN ===")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")                              -- 此后动态注册，替代 RegisterEvent 中的静态注册
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    eventFrame:RegisterEvent("UI_SCALE_CHANGED")                                   -- UI 缩放变化通知

    Cell.vars.playerNameShort = GetUnitName("player")                            -- 简短玩家名（如 "David"）
    Cell.vars.playerNameFull = F.UnitFullName("player")                           -- 完整玩家名（如 "David-Realm"）

    --! 初始化 bgMaxPlayers 战场人数映射表
    -- Midnight 12.0.0 移除了 GetBattlegroundInfo；兼容性守卫
    if GetBattlegroundInfo then
        for i = 1, GetNumBattlegroundTypes() do
            local bgName, _, _, _, _, _, bgId, maxPlayers = GetBattlegroundInfo(i)
            if bgId then
                bgMaxPlayers[bgId] = maxPlayers
            end
        end
    end

    Cell.vars.playerGUID = UnitGUID("player")

    -- 更新专精信息（此时 GetSpecializationInfo 已可用）
    UpdateSpecVars()

    --! 初始化 currentLayout 和 currentLayoutTable（通过 GROUP_ROSTER_UPDATE 回退逻辑）
    eventFrame:GROUP_ROSTER_UPDATE(true)                                         -- skipFallbackUpdate=true 避免污染 CellDB
    -- REVIEW: 全局点击施法帧注册（暂时停用）
    -- RegisterGlobalClickCastings()
    -- 更新点击施法绑定
    Cell.Fire("UpdateClickCastings")
    -- 更新指示器 -- NOTE: GROUP_ROSTER_UPDATE -> GroupTypeChanged -> F.UpdateLayout 已触发 UpdateIndicators
    -- Cell.Fire("UpdateIndicators")
    -- 更新纹理和字体设置
    Cell.Fire("UpdateAppearance")
    Cell.UpdateOptionsFont(CellDB["appearance"]["optionsFontSizeOffset"], CellDB["appearance"]["useGameFont"])
    Cell.UpdateAboutFont(CellDB["appearance"]["optionsFontSizeOffset"])
    -- 更新工具模块
    Cell.Fire("UpdateTools")
    -- 更新请求模块（技能请求/驱散请求）
    Cell.Fire("UpdateRequests")
    -- 更新快速协助 -- NOTE: GroupTypeChanged/SpecChanged 中已更新
    -- Cell.Fire("UpdateQuickAssist")
    -- 更新快速施法
    Cell.Fire("UpdateQuickCast")
    -- 更新团队 Debuff 列表
    Cell.Fire("UpdateRaidDebuffs")
    -- 隐藏暴雪默认框体
    if CellDB["general"]["hideBlizzardParty"] then F.HideBlizzardParty() end
    if CellDB["general"]["hideBlizzardRaid"] then F.HideBlizzardRaid() end
    if CellDB["general"]["hideBlizzardRaidManager"] then F.HideBlizzardRaidManager() end
    -- 锁定状态 & 菜单位置
    Cell.Fire("UpdateMenu")
    -- 更新 CLEU 生命值更新器
    Cell.Fire("UpdateCLEU")
    -- 更新内置与自定义光环追踪
    I.UpdateAoEHealings(CellDB["aoeHealings"])
    I.UpdateDefensives(CellDB["defensives"])
    I.UpdateExternals(CellDB["externals"])
    I.UpdateCrowdControls(CellDB["crowdControls"])
    -- 更新像素精确调整
    Cell.Fire("UpdatePixelPerfect")
    -- 更新子框架优先级层级
    F.UpdateFramePriority()
end

-- 像素精确实时更新函数：UI 缩放变化后重新计算所有元素的像素对齐
local function UpdatePixels()
    if not InCombatLockdown() then
        F.Debug("UI_SCALE_CHANGED: ", UIParent:GetScale(), CellParent:GetEffectiveScale())
        Cell.Fire("UpdatePixelPerfect")                                          -- 更新像素精确数据
        Cell.Fire("UpdateAppearance", "scale")                                    -- 更新外观缩放
    end
end

-- 延迟更新防止频繁触发：UI_SCALE_CHANGED 可能在短时间内多次触发
-- 使用 1 秒防抖，避免遍历所有单位按钮造成性能问题
local updatePixelsTimer
local function DelayedUpdatePixels()
    if updatePixelsTimer then
        updatePixelsTimer:Cancel()
    end
    updatePixelsTimer = C_Timer.NewTimer(1, UpdatePixels)
end

-- UI_SCALE_CHANGED：当 UI 缩放 CVar 或 UIParent 缩放改变时触发
function eventFrame:UI_SCALE_CHANGED()
    DelayedUpdatePixels()
end

-- 钩子：当插件调用 UIParent:SetScale 时也触发延迟像素更新
-- hooksecurefunc 是安全的钩子方式，不影响原始函数，无需 Secret Value 特殊处理
hooksecurefunc(UIParent, "SetScale", DelayedUpdatePixels)

-------------------------------------------------
-- ACTIVE_TALENT_GROUP_CHANGED — 专精切换处理
-- 专精切换时需更新布局、点击施法绑定、快速协助等
-- 注意：进入战场时专精强制切换，加载期间 GetSpecializationInfo 不可用
-------------------------------------------------
local checkSpecFrame = CreateFrame("Frame")                                      -- 辅助帧：处理专精切换延迟重试
checkSpecFrame:SetScript("OnEvent", function()
    eventFrame:ACTIVE_TALENT_GROUP_CHANGED()
end)

-- 事件选择说明：
--   ACTIVE_TALENT_GROUP_CHANGED 会触发两次（原因未知）
--   PLAYER_SPECIALIZATION_CHANGED 升级时也会触发
--   ACTIVE_PLAYER_SPECIALIZATION_CHANGED 仅手动切专精时触发
--   NOTE: ACTIVE_TALENT_GROUP_CHANGED 在 PLAYER_LOGIN 前触发，但 GetSpecializationInfo 还不可用
local prevSpec                                                                   -- 上一次的专精 ID，用于去重
function eventFrame:ACTIVE_TALENT_GROUP_CHANGED()
    -- 战斗中无法切换专精配置，等待脱战
    if InCombatLockdown() then
        checkSpecFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    -- 去重：同一专精短时间内可能触发两次
    local spec = GetSpecialization()
    if prevSpec ~= spec then
        prevSpec = spec
        F.Debug("|cffbbbbbb=== ACTIVE_TALENT_GROUP_CHANGED ===")

        -- 更新专精信息到 Cell.vars
        UpdateSpecVars()

        if not Cell.vars.playerSpecID or Cell.vars.playerSpecID == 0 then
            -- 专精信息获取失败（如进入战场加载期间），等待 PLAYER_ENTERING_WORLD 重试
            prevSpec = nil
            checkSpecFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            F.Debug("|cffffbb77SpecChanged:|r FAILED")
        else
            checkSpecFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            checkSpecFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            F.Debug("|cffffbb77SpecChanged:|r", Cell.vars.playerSpecID, Cell.vars.playerSpecRole)
            -- 如果不使用通用点击施法，则更新为当前专精的独立绑定
            if not CellDB["clickCastings"][Cell.vars.playerClass]["useCommon"] then
                Cell.Fire("UpdateClickCastings")
            end
            Cell.Fire("SpecChanged", Cell.vars.playerSpecID, Cell.vars.playerSpecRole)
        end
    end
end

-- eventFrame 通用事件分发器：将事件名映射到同名方法
-- 例如 "GROUP_ROSTER_UPDATE" 事件 → self:GROUP_ROSTER_UPDATE(...)
eventFrame:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end)

-------------------------------------------------
-- 斜杠命令 (/cell 和 /celld 双入口)
-- /cell 保持与原版 Cell 完全兼容，/celld 是 CellD 专属命令
-- 支持子命令: options/opt, blackbox, healers, rescale, reset, report
-------------------------------------------------
SLASH_CELL1 = "/cell"                                                   -- 兼容原版 Cell 命令
SLASH_CELL2 = "/celld"                                                  -- CellD 新命令（推荐使用）
function SlashCmdList.CELL(msg, editbox)
    local command, rest = msg:match("^(%S*)%s*(.-)$")                   -- 解析命令和参数
    command = strlower(command or "")
    rest = strlower(rest or "")

    if command == "options" or command == "opt" then
        F.ShowOptionsFrame()                                            -- 打开设置面板

    elseif command == "blackbox" then
        -- CellD 黑箱自检: Secret Value 安全测试
        -- 此命令调用 BlackBox 模块运行完整的 Secret Value 安全验证
        -- 包括：安全函数替代验证、直接运算检测、未防护路径扫描
        if CellD_BlackBox then
            CellD_BlackBox()
        else
            F.Print("|cFFFF0000BlackBox 自检模块未加载，请检查插件完整性")
        end

    elseif command == "healers" then
        F.FirstRun()                                                    -- 重新运行首次引导（创建治疗者指示器等）

    elseif command == "rescale" then
        CellDB["appearance"]["scale"] = P.GetRecommendedScale()         -- 根据屏幕分辨率推荐缩放
        ReloadUI()

    elseif command == "reset" then
        -- reset 系列命令：重置各类配置，重置后自动 ReloadUI
        -- 注意：这些操作影响账号下所有角色
        if rest == "position" then
            -- 仅重置所有 UI 元素的位置到屏幕中心
            Cell.frames.anchorFrame:ClearAllPoints()
            Cell.frames.anchorFrame:SetPoint("TOPLEFT", CellParent, "CENTER")
            Cell.vars.currentLayoutTable["position"] = {}
            P.ClearPoints(Cell.frames.readyAndPullFrame)
            Cell.frames.readyAndPullFrame:SetPoint("TOPRIGHT", CellParent, "CENTER")
            CellDB["tools"]["readyAndPull"][4] = {}
            P.ClearPoints(Cell.frames.raidMarksFrame)
            Cell.frames.raidMarksFrame:SetPoint("BOTTOMRIGHT", CellParent, "CENTER")
            CellDB["tools"]["marks"][4] = {}
            P.ClearPoints(Cell.frames.buffTrackerFrame)
            Cell.frames.buffTrackerFrame:SetPoint("BOTTOMLEFT", CellParent, "CENTER")
            CellDB["tools"]["buffTracker"][4] = {}

        elseif rest == "all" then
            -- 完全重置：清空位置，置空 CellDB 触发重建所有默认值
            Cell.frames.anchorFrame:ClearAllPoints()
            Cell.frames.anchorFrame:SetPoint("TOPLEFT", CellParent, "CENTER")
            Cell.frames.readyAndPullFrame:ClearAllPoints()
            Cell.frames.readyAndPullFrame:SetPoint("TOPRIGHT", CellParent, "CENTER")
            Cell.frames.raidMarksFrame:ClearAllPoints()
            Cell.frames.raidMarksFrame:SetPoint("BOTTOMRIGHT", CellParent, "CENTER")
            Cell.frames.buffTrackerFrame:ClearAllPoints()
            Cell.frames.buffTrackerFrame:SetPoint("BOTTOMLEFT", CellParent, "CENTER")
            CellDB = nil                                                  -- 置空后重载，ADDON_LOADED 将重建所有默认值
            ReloadUI()

        elseif rest == "layouts" then
            CellDB["layouts"] = nil
            ReloadUI()

        elseif rest == "clickcastings" then
            CellDB["clickCastings"] = nil
            ReloadUI()

        elseif rest == "raiddebuffs" then
            CellDB["raidDebuffs"] = nil
            ReloadUI()

        elseif rest == "snippets" then
            CellDB["snippets"] = {}                                       -- 清空代码片段
            ReloadUI()

        elseif rest == "quickassist" then
            CellDB["quickAssist"][Cell.vars.playerSpecID] = nil           -- 仅重置当前专精的快速协助
            ReloadUI()
        end

    elseif command == "report" then
        -- /celld report <0-40>：设置死亡报告数量上限，0 表示不限
        rest = tonumber(rest:format("%d"))
        if rest and rest >= 0 and rest <= 40 then
            if rest == 0 then
                F.Print(L["Cell will report all deaths during a raid encounter."])
            else
                F.Print(string.format(L["Cell will report first %d deaths during a raid encounter."], rest))
            end
            CellDB["tools"]["deathReport"][2] = rest
            Cell.Fire("UpdateTools", "deathReport")
        else
            F.Print(L["A 0-40 integer is required."])
        end

    -- [已停用] buff 命令：通过斜杠命令调整 Buff Tracker 图标大小
    -- elseif command == "buff" then
    --     rest = tonumber(rest:format("%d"))
    --     if rest and rest > 0 then
    --         CellDB["tools"]["buffTracker"][3] = rest
    --         F.Print(string.format(L["Buff Tracker icon size is set to %d."], rest))
    --         Cell.Fire("UpdateTools", "buffTracker")
    --     else
    --         F.Print(L["A positive integer is required."])
    --     end

    else
        -- 无参数或无效命令：显示帮助信息
        F.Print(L["Available slash commands"]..":\n"..
            "|cFFFFB5C5/celld options|r: "..L["show Cell options frame"]..".\n"..
            "|cFFFFB5C5/celld healers|r: "..L["create a \"Healers\" indicator"]..".\n"..
            "|cFFFFB5C5/celld rescale|r: "..strlower(L["Apply Recommended Scale"])..".\n"..
            "|cFFFFB5C5/celld blackbox|r: Secret Value 黑箱自检.\n"..
            "|cFFFF7777"..L["These \"reset\" commands below affect all your characters in this account"]..".|r\n"..
            "|cFFFFB5C5/celld reset position|r: "..L["reset Cell position"]..".\n"..
            "|cFFFFB5C5/celld reset layouts|r: "..L["reset all Layouts and Indicators"]..".\n"..
            "|cFFFFB5C5/celld reset clickcastings|r: "..L["reset all Click-Castings"]..".\n"..
            "|cFFFFB5C5/celld reset raiddebuffs|r: "..L["reset all Raid Debuffs"]..".\n"..
            "|cFFFFB5C5/celld reset quickassist|r: "..L["reset Quick Assist for current spec"]..".\n"..
            "|cFFFFB5C5/celld reset all|r: "..L["reset all Cell settings"].."."
        )
    end
end

-- 插件管理面板入口：点击 CellD 图标时打开设置面板
-- 注册在 .toc 文件中
function Cell_OnAddonCompartmentClick()
    F.ShowOptionsFrame()
end