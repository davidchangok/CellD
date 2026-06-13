---------------------------------------------------------------------
-- BuffTracker - CellD 团队增益追踪模块
-- 功能：检测当前队伍/团队中缺少的团队增益（如耐力、智力、攻强等），
--       并为玩家提供缺失提示、一键施法补充增益及聊天通报功能。
-- 支持版本：Retail（正式服）和 Mists（熊猫人之谜）
---------------------------------------------------------------------
local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local I = Cell.iFuncs
local U = Cell.uFuncs
local P = Cell.pixelPerfectFuncs
local LCG = LibStub("LibCustomGlow-1.0") -- 像素发光库，用于高亮提示缺失增益的按钮
local LGI = LibStub:GetLibrary("LibGroupInfo") -- 团队信息库，获取队员专精等数据
local A = Cell.animations

-- 缓存常用全局 API，提升运行时性能并保证 Secret-mode 兼容（Secret 模式下某些函数调用受限）
local UnitIsConnected = UnitIsConnected
local UnitIsVisible = UnitIsVisible
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsUnit = UnitIsUnit
local UnitIsPlayer = UnitIsPlayer
local UnitGUID = UnitGUID
local UnitClassBase = UnitClassBase
local UnitLevel = UnitLevel
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid

local sort, tinsert, tconcat = table.sort, table.insert, table.concat

---------------------------------------------------------------------
-- data -- 增益数据定义
---------------------------------------------------------------------
-- buffs: 定义所有团队增益的元数据（显示名、图标、提供者职业/法术ID/等级）
local buffs = {}
-- requiredBuffs: 专精ID → 该专精需要的增益名称（如 [250]=血DK → 需要"attackPower"）
local requiredBuffs = {}
-- requiredByEveryone: 所有人都需要的增益（如耐力、全能）
local requiredByEveryone = {}
-- available: 当前队伍中哪些增益有提供者（由准备阶段的职业/等级检查填充）
local available = {}
-- unaffected: 缺失某增益的单位集合，用于统计和提示
local unaffected = {}

-- Retail（正式服）增益配置：6 种主要团队增益，按 order 排序
if Cell.isRetail then
    buffs = {
        -- 耐力增益：牧师 → 真言术：韧
        stamina = {
            tag = ITEM_MOD_STAMINA_SHORT, -- Stamina
            icon = 135987,
            order = 1,
            provider = {
                PRIEST = {id = 21562, level = 6}, -- Power Word: Fortitude - 真言术：韧
            }
        },
        -- 全能增益：德鲁伊 → 野性印记
        versatility = {
            tag = STAT_VERSATILITY, -- Versatility
            icon = 136078,
            order = 2,
            provider = {
                DRUID = {id = 1126, level = 9}, -- Mark of the Wild - 野性印记
            }
        },
        -- 精通增益：萨满 → 天怒
        mastery = {
            tag = STAT_MASTERY, -- Mastery
            icon = 4630367,
            order = 3,
            provider = {
                SHAMAN = {id = 462854, level = 16}, -- Skyfury - 天怒
            }
        },
        -- 智力增益：法师 → 奥术智慧
        intellect = {
            tag = ITEM_MOD_INTELLECT_SHORT, -- Intellect
            icon = 135932,
            order = 4,
            provider = {
                MAGE = {id = 1459, level = 8}, -- Arcane Brilliance - 奥术智慧
            }
        },
        -- 攻击强度增益：战士 → 战斗怒吼
        attackPower = {
            tag = RAID_BUFF_3, -- Attack Power
            icon = 132333,
            order = 5,
            provider = {
                WARRIOR = {id = 6673, level = 10}, -- Battle Shout - 战斗怒吼
            }
        },
        -- 移动速度/功能性增益：唤魔师 → 青铜龙的祝福
        movement = {
            tag = TUTORIAL_TITLE2, -- Movement
            icon = 4622448,
            order = 6,
            provider = {
                EVOKER = {id = 364342, level = 30}, -- Blessing of the Bronze - 青铜龙的祝福
            }
        }
    }

    -- 各专精 ID → 需要的增益（DPS 专精需要攻强，治疗/法系需要智力）
    requiredBuffs = {
        [250] = "attackPower", -- Blood
        [251] = "attackPower", -- Frost
        [252] = "attackPower", -- Unholy

        [577] = "attackPower", -- Havoc
        [581] = "attackPower", -- Vengeance

        [102] = "intellect", -- Balance
        [103] = "attackPower", -- Feral
        [104] = "attackPower", -- Guardian
        [105] = "intellect", -- Restoration

        [1467] = "intellect", -- Devastation
        [1468] = "intellect", -- Preservation

        [253] = "attackPower", -- Beast Mastery
        [254] = "attackPower", -- Marksmanship
        [255] = "attackPower", -- Survival

        [62] = "intellect", -- Arcane
        [63] = "intellect", -- Fire
        [64] = "intellect", -- Frost

        [268] = "attackPower", -- Brewmaster
        [269] = "attackPower", -- Windwalker
        [270] = "intellect", -- Mistweaver

        [65] = "intellect", -- Holy
        [66] = "attackPower", -- Protection
        [70] = "attackPower", -- Retribution

        [256] = "intellect", -- Discipline
        [257] = "intellect", -- Holy
        [258] = "intellect", -- Shadow

        [259] = "attackPower", -- Assassination
        [260] = "attackPower", -- Outlaw
        [261] = "attackPower", -- Subtlety

        [262] = "intellect", -- Elemental
        [263] = "attackPower", -- Enhancement
        [264] = "intellect", -- Restoration

        [265] = "intellect", -- Affliction
        [266] = "intellect", -- Demonology
        [267] = "intellect", -- Destruction

        [71] = "attackPower", -- Arms
        [72] = "attackPower", -- Fury
        [73] = "attackPower", -- Protection
    }

    -- 无论专精，所有人都需要的增益
    requiredByEveryone = {
        stamina = true,
        versatility = true,
        mastery = true,
        movement = true,
    }

    -- 当前队伍中是否有某增益的提供者（初始 false，准备阶段检查后更新）
    available = {
        stamina = false,
        versatility = false,
        mastery = false,
        intellect = false,
        attackPower = false,
        movement = false,
    }

    -- 缺失某增益的单位集合：unaffected[增益名] = { [unitToken]=true, ... }
    unaffected = {
        stamina = {},
        versatility = {},
        mastery = {},
        intellect = {},
        attackPower = {},
        movement = {},
    }

-- Mists（熊猫人之谜）增益配置：5 种团队增益，多种职业可提供同一增益
elseif Cell.isMists then
    buffs = {
        stamina = {
            tag = RAID_BUFF_2, -- Stamina
            icon = 135987,
            order = 1,
            provider = {
                PRIEST = {id = 21562, level = 22}, -- Power Word: Fortitude
                WARLOCK = {id = 109773, level = 82}, -- Dark Intent
                WARRIOR = {id = 469, level = 68}, -- Commanding Shout
            },
        },
        stats = {
            tag = RAID_BUFF_1, -- Stats
            icon = 136078,
            order = 2,
            provider = {
                DRUID = {id = 1126, level = 62}, -- Mark of the Wild
                MONK = {id = 115921, level = 22}, -- Legacy of the Emperor
                PALADIN = {id = 20217, level = 30}, -- Blessing of Kings
            }
        },
        spellPower = {
            tag = RAID_BUFF_5, -- Spell Power
            icon = 135932,
            order = 3,
            provider = {
                MAGE = {id = {1459, 61316}, level = 58}, -- Arcane Brilliance / Dalaran Brilliance
                SHAMAN = {id = 77747, level = 40}, -- Burning Wrath
                WARLOCK = {id = 109773, level = 82}, -- Dark Intent
            }
        },
        attackPower = {
            tag = RAID_BUFF_3, -- Attack Power
            icon = 132333,
            order = 4,
            provider = {
                DEATHKNIGHT = {id = 57330, level = 65}, -- Horn of Winter
                HUNTER = {id = 19506, level = 39}, -- Trueshot Aura
                WARRIOR = {id = 6673, level = 42}, -- Battle Shout
            }
        },
        mastery = {
            tag = RAID_BUFF_7, -- Mastery
            icon = 135908,
            order = 5,
            provider = {
                PALADIN = {id = 19740, level = 81}, -- Blessing of Might
                SHAMAN = {id = 116956, level = 80}, -- Grace of Air
            }
        }
    }

    requiredBuffs = {
        [250] = "attackPower", -- Blood
        [251] = "attackPower", -- Frost
        [252] = "attackPower", -- Unholy

        [102] = "spellPower", -- Balance
        [103] = "attackPower", -- Feral
        [104] = "attackPower", -- Guardian
        [105] = "spellPower", -- Restoration

        [253] = "attackPower", -- Beast Mastery
        [254] = "attackPower", -- Marksmanship
        [255] = "attackPower", -- Survival

        [62] = "spellPower", -- Arcane
        [63] = "spellPower", -- Fire
        [64] = "spellPower", -- Frost

        [268] = "attackPower", -- Brewmaster
        [269] = "attackPower", -- Windwalker
        [270] = "spellPower", -- Mistweaver

        [65] = "spellPower", -- Holy
        [66] = "attackPower", -- Protection
        [70] = "attackPower", -- Retribution

        [256] = "spellPower", -- Discipline
        [257] = "spellPower", -- Holy
        [258] = "spellPower", -- Shadow

        [259] = "attackPower", -- Assassination
        [260] = "attackPower", -- Outlaw
        [261] = "attackPower", -- Subtlety

        [262] = "spellPower", -- Elemental
        [263] = "attackPower", -- Enhancement
        [264] = "spellPower", -- Restoration

        [265] = "spellPower", -- Affliction
        [266] = "spellPower", -- Demonology
        [267] = "spellPower", -- Destruction

        [71] = "attackPower", -- Arms
        [72] = "attackPower", -- Fury
        [73] = "attackPower", -- Protection
    }

    -- 无论专精，所有人都需要的增益
    requiredByEveryone = {
        stamina = true,
        stats = true,
        mastery = true,
    }

    -- 当前队伍中是否有某增益的提供者
    available = {
        stamina = false,
        stats = false,
        spellPower = false,
        attackPower = false,
        mastery = false,
    }

    -- 缺失某增益的单位集合
    unaffected = {
        stamina = {},
        stats = {},
        spellPower = {},
        attackPower = {},
        mastery = {},
    }
end

---------------------------------------------------------------------
-- prepare -- 准备阶段：构建职业增益映射、增益排序、玩家自身增益列表
---------------------------------------------------------------------
-- classBuffs: class → { buffKey → 所需等级 }
-- 例如 classBuffs["PRIEST"] = { stamina = 6 }
local classBuffs = {
    -- class = {
    --     buff = level,
    -- }
}
local buffOrder = {}
local buffsProvidedByMe = {}
local myClass = UnitClassBase("player")

-- 一次性初始化：遍历 buffs 配置，构建 classBuffs 映射、buffOrder 排序、buffsProvidedByMe
do
    local myLevel = UnitLevel("player")

    -- Insert: 将法术名加入 buffs[].names 列表，如果玩家自己可以施法则记录到 buffsProvidedByMe
    local function Insert(class, buffKey, name, icon)
        tinsert(buffs[buffKey]["names"], name)
        if myClass == class and myLevel >= classBuffs[class][buffKey] then
            buffsProvidedByMe[buffKey] = {name, icon}
        end
    end

    for buffKey, buffData in pairs(buffs) do
        tinsert(buffOrder, buffKey)
        buffData.names = {} -- 该增益的所有法术名（用于光环匹配）

        for class, info in pairs(buffData.provider) do
            classBuffs[class] = classBuffs[class] or {}
            classBuffs[class][buffKey] = info.level

            -- 支持单个法术 ID（数字）或多个法术 ID（表，如 Mists 法师的奥术光辉/达拉然光辉）
            if type(info.id) == "table" then
                for _, spellId in ipairs(info.id) do
                    local name, icon = F.GetSpellInfo(spellId)
                    if name then
                        Insert(class, buffKey, name, icon)
                    end
                end
            else
                local name, icon = F.GetSpellInfo(info.id)
                if name then
                    Insert(class, buffKey, name, icon)
                end
            end
        end
    end

    -- 按 order 字段对 buffOrder 排序（决定 UI 中按钮的显示顺序）
    sort(buffOrder, function(a, b)
        return buffs[a]["order"] < buffs[b]["order"]
    end)
end

-- 返回 BuffTracker 的默认设置表（当前为空，由外部工具系统管理设置项）
function U.GetBuffTrackerDefaults()
    return {}
end

-- 返回增益排序列表和增益数据，供外部模块（如设置面板）读取
function U.GetBuffTrackerInfo()
    return buffOrder, buffs
end

-------------------------------------------------
-- vars -- 内部状态变量
-------------------------------------------------
-- enabled: BuffTracker 是否已启用
local enabled
-- myUnit: 玩家单位的 token（如 "player"），遍历时动态更新
local myUnit = ""
-- hasBuffProvider: 当前队伍中是否有至少一个增益提供者
local hasBuffProvider

-- Reset: 重置可用性状态和/或缺失增益记录
-- which: "available" 重置可用增益提供者状态，"unaffected" 清空缺失记录，nil 则全部重置
local fl function Reset(which)
    if not which or which == "available" then
        for k, v in pairs(available) do
            available[k] = false
        end
        hasBuffProvider = false
    end

    if not which or which == "unaffected" then
        for k, v in pairs(unaffected) do
            wipe(unaffected[k])
        end
    end
end

-- GetUnaffectedString: 生成缺失增益的聊天通报文本
-- 如果缺失人数 <= 10，列出所有玩家名；否则显示 "many"（多人）
-- 用于右键点击按钮时自动发送团队/小队聊天消息
local function GetUnaffectedString(buff)
    local list = unaffected[buff]
    local name = buffs[buff]["tag"]

    local players = {}
    for unit in pairs(list) do
        local name = UnitName(unit)
        tinsert(players, name)
    end

    if #players == 0 then
        return
    elseif #players <= 10 then
        return L["Missing Buff"] .. " (" .. name .. "): " .. tconcat(players, ", ")
    else
        return L["Missing Buff"] .. " (" .. name .. "): " .. L["many"]
    end
end

-------------------------------------------------
-- frame -- 主框架：BuffTracker 的容器窗口
-------------------------------------------------
-- 创建 BuffTracker 主框架，挂载到 Cell 的主框架上，支持拖拽移动
local buffTrackerFrame = CreateFrame("Frame", "CellBuffTrackerFrame", Cell.frames.mainFrame, "BackdropTemplate")
Cell.frames.buffTrackerFrame = buffTrackerFrame
P.Size(buffTrackerFrame, 102, 50)
PixelUtil.SetPoint(buffTrackerFrame, "BOTTOMLEFT", CellParent, "CENTER", 1, 1)
buffTrackerFrame:SetClampedToScreen(true) -- 限制框架不超出屏幕边界
-- buffTrackerFrame:SetClampRectInsets(0, 0, -20, 0)
buffTrackerFrame:SetMovable(true)
buffTrackerFrame:RegisterForDrag("LeftButton") -- 左键拖拽移动
buffTrackerFrame:SetScript("OnDragStart", function()
    buffTrackerFrame:StartMoving()
    buffTrackerFrame:SetUserPlaced(false)
end)
buffTrackerFrame:SetScript("OnDragStop", function()
    buffTrackerFrame:StopMovingOrSizing()
    P.SavePosition(buffTrackerFrame, CellDB["tools"]["buffTracker"][4]) -- 保存拖拽后的位置
end)

-------------------------------------------------
-- mover -- 布局模式切换：显示/隐藏占位图标，帮助玩家调整 BuffTracker 位置
-------------------------------------------------
-- mover 模式提示文字
buffTrackerFrame.moverText = buffTrackerFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
buffTrackerFrame.moverText:SetPoint("TOP", 0, -3)
buffTrackerFrame.moverText:SetText(L["Mover"])
buffTrackerFrame.moverText:Hide()

-- fakeIconsFrame: 布局预览用的占位图标容器，在 mover 模式下显示
local fakeIconsFrame = CreateFrame("Frame", nil, buffTrackerFrame)
P.Point(fakeIconsFrame, "BOTTOMRIGHT", buffTrackerFrame)
P.Point(fakeIconsFrame, "TOPLEFT", buffTrackerFrame, "TOPLEFT", 0, -18)
fakeIconsFrame:EnableMouse(true)
fakeIconsFrame:SetFrameLevel(buffTrackerFrame:GetFrameLevel() + 10) -- 置于按钮上层，确保可点击
fakeIconsFrame:Hide()

-- fakeIcons: 用于 mover 模式的占位图标列表
local fakeIcons = {}
-- CreateFakeIcon: 创建占位图标（黑色背景 + 法术图标纹理），用于 mover 模式下预览布局
local function CreateFakeIcon(spellIcon)
    local bg = fakeIconsFrame:CreateTexture(nil, "BORDER")
    bg:SetColorTexture(0, 0, 0, 1)
    P.Size(bg, 32, 32)

    local icon = fakeIconsFrame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(spellIcon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    P.Point(icon, "TOPLEFT", bg, "TOPLEFT", 1, -1)
    P.Point(icon, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", -1, 1)

    -- UpdatePixelPerfect: 像素完美模式下重新计算尺寸和锚点
    function bg:UpdatePixelPerfect()
        P.Resize(bg)
        P.Repoint(bg)
        P.Repoint(icon)
    end

    return bg
end

-- 为每种增益创建一个占位图标
do
    for _, k in ipairs(buffOrder) do
        tinsert(fakeIcons, CreateFakeIcon(buffs[k]["icon"]))
    end
end

-- ShowMover: 切换 mover（布局预览）模式的显示/隐藏
-- show=true: 显示占位图标和绿色边框，允许拖拽调整位置
-- show=false: 隐藏占位图标，恢复正常透明度
local function ShowMover(show)
    if show then
        if not CellDB["tools"]["buffTracker"][1] then return end
        buffTrackerFrame:EnableMouse(true)
        buffTrackerFrame.moverText:Show()
        Cell.StylizeFrame(buffTrackerFrame, {0, 1, 0, 0.4}, {0, 0, 0, 0})
        fakeIconsFrame:Show()
        buffTrackerFrame:SetAlpha(1)
    else
        buffTrackerFrame:EnableMouse(false)
        buffTrackerFrame.moverText:Hide()
        Cell.StylizeFrame(buffTrackerFrame, {0, 0, 0, 0}, {0, 0, 0, 0})
        fakeIconsFrame:Hide()
        buffTrackerFrame:SetAlpha(CellDB["tools"]["fadeOut"] and 0 or 1)
    end
end
Cell.RegisterCallback("ShowMover", "BuffTracker_ShowMover", ShowMover)

-------------------------------------------------
-- buttons -- BuffTracker 的核心 UI：每种增益对应一个图标按钮
-------------------------------------------------
-- sendChannel: 右键通报时使用的聊天频道
local sendChannel
-- UpdateSendChannel: 根据当前组队状态选择发送频道（副本/团队/小队）
local function UpdateSendChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        sendChannel = "INSTANCE_CHAT"
    elseif IsInRaid() then
        sendChannel = "RAID"
    else
        sendChannel = "PARTY"
    end
end

-- CreateBuffButton: 为指定增益创建一个图标按钮
-- 左键（如果玩家可施法）：一键对自己施放该增益
-- 右键：向队伍/团队发送缺失该增益的玩家名单
-- 按钮包含：图标纹理、缺失人数计数文本、鼠标悬停提示、发光动画
local function CreateBuffButton(parent, buff)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
    if parent then b:SetFrameLevel(parent:GetFrameLevel() + 1) end
    P.Size(b, 32, 32)

    b:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
    b:SetBackdropBorderColor(0, 0, 0, 1)

    -- 注册所有可能的点击组合，兼容 ActionButtonUseKeyDown 设置
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "LeftButtonDown", "RightButtonDown") -- NOTE: ActionButtonUseKeyDown will affect this

    -- cast: 如果玩家可以施法该增益，左键点击设置为对自己施放法术的宏
    if buffsProvidedByMe[buff] then
        b:SetAttribute("type1", "macro")
        b:SetAttribute("macrotext1", "/cast [@player] " .. buffsProvidedByMe[buff][1])
    end

    -- chat: 右键点击时，向队伍/团队发送缺失该增益的玩家名单
    b:HookScript("OnClick", function(self, button, down)
        if button == "RightButton" and (down == GetCVarBool("ActionButtonUseKeyDown")) then
            local msg = GetUnaffectedString(buff)
            if msg then
                UpdateSendChannel()
                SendChatMessage(msg, sendChannel)
            end
        end
    end)

    -- 按钮图标纹理（增益法术图标）
    b.texture = b:CreateTexture(nil, "OVERLAY")
    P.Point(b.texture, "TOPLEFT", b, "TOPLEFT", 1, -1)
    P.Point(b.texture, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.texture:SetTexture(buffs[buff]["icon"])
    b.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- 缺失人数计数文本（红色数字，显示在图标左上角）
    b.count = b:CreateFontString(nil, "OVERLAY")
    P.Point(b.count, "TOPLEFT", b.texture, "TOPLEFT", 2, -2)
    b.count:SetFont(GameFontNormal:GetFont(), 14, "OUTLINE")
    b.count:SetShadowColor(0, 0, 0)
    b.count:SetShadowOffset(0, 0)
    b.count:SetTextColor(1, 0, 0)

    -- 鼠标离开时隐藏提示
    b:SetScript("OnLeave", function()
        CellTooltip:Hide()
    end)

    -- SetTooltips: 设置鼠标悬停提示，显示缺失该增益的玩家职业色名单
    function b:SetTooltips(list)
        b:SetScript("OnEnter", function()
            if F.Getn(list) ~= 0 then
                CellTooltip:SetOwner(b, "ANCHOR_TOPLEFT", 0, 3)
                CellTooltip:AddLine(L["Unaffected"] .. " |cffb7b7b7" .. buffs[buff]["tag"])
                for unit in pairs(list) do
                    local class = UnitClassBase(unit)
                    local name = UnitName(unit)
                    if class and name then
                        CellTooltip:AddLine(F.GetClassColorStr(class) .. name .. "|r")
                    end
                end
                CellTooltip:Show()
            end
        end)
    end

    -- SetDesaturated: 控制图标去色（表示该增益已无提供者）
    function b:SetDesaturated(flag)
        b.texture:SetDesaturated(flag)
    end

    -- StartGlow: 启动像素发光动画（表示玩家自己也缺失该增益）
    function b:StartGlow(glowType, ...)
        LCG.PixelGlow_Start(b, ...)
    end

    -- StopGlow: 停止像素发光动画
    function b:StopGlow()
        LCG.PixelGlow_Stop(b)
    end

    -- Reset: 重置按钮到默认状态（去色关闭、计数清空、透明度恢复、发光停止）
    function b:Reset()
        b.texture:SetDesaturated(false)
        b.count:SetText("")
        b:SetAlpha(1)
        b:StopGlow()
    end

    -- UpdatePixelPerfect: 像素完美模式下重新计算按钮及子元素的尺寸和锚点
    function b:UpdatePixelPerfect()
        P.Resize(b)
        P.Repoint(b)
        b:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
        b:SetBackdropBorderColor(0, 0, 0, 1)

        P.Repoint(b.texture)
        P.Repoint(b.count)
    end

    return b
end

-- buttons: buffKey → 对应的按钮对象
local buttons = {}

-- 创建所有增益按钮，初始隐藏，绑定各自的缺失名单到悬停提示
do
    for _, buff in ipairs(buffOrder) do
        buttons[buff] = CreateBuffButton(buffTrackerFrame, buff)
        buttons[buff]:Hide()
        buttons[buff]:SetTooltips(unaffected[buff])
    end
end

-- UpdateButtons: 根据缺失统计更新按钮的显示状态
-- - 无人缺失：半透明 0.5、清除计数、停止发光
-- - 有人缺失：显示计数 N、透明度 1
-- - 玩家自己也缺失：额外启动红色像素发光动画
local function UpdateButtons()
    for _, buff in pairs(buffOrder) do
        if available[buff] then
            local n = F.Getn(unaffected[buff])
            if n == 0 then
                buttons[buff].count:SetText("")
                buttons[buff]:SetAlpha(0.5)
                buttons[buff]:StopGlow()
            else
                buttons[buff].count:SetText(n)
                buttons[buff]:SetAlpha(1)
                if unaffected[buff][myUnit] then
                    -- color, N, frequency, length, thickness
                    buttons[buff]:StartGlow("Pixel", {1, 0.19, 0.19, 1}, 8, 0.25, P.Scale(8), P.Scale(2))
                else
                    buttons[buff]:StopGlow()
                end
            end
        end
    end
end

-- RepointButtons: 根据布局方向和可用增益更新按钮的排列位置
-- 支持四种布局：左到右、右到左、上到下、下到上
-- 战斗中锁定 UI 时注册 PLAYER_REGEN_ENABLED 事件，战斗结束后重新排列
local function RepointButtons()
    if InCombatLockdown() then
        buffTrackerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        -- 根据设置选择排列方向和偏移量
        local point, relativePoint, offsetX, offsetY, firstX, firstY
        if CellDB["tools"]["buffTracker"][2] == "left-to-right" then
            point, relativePoint = "BOTTOMLEFT", "BOTTOMRIGHT"
            offsetX, offsetY = 3, 0
            firstX, firstY = 0, 0
        elseif CellDB["tools"]["buffTracker"][2] == "right-to-left" then
            point, relativePoint = "BOTTOMRIGHT", "BOTTOMLEFT"
            offsetX, offsetY = -3, 0
            firstX, firstY = 0, 0
        elseif CellDB["tools"]["buffTracker"][2] == "top-to-bottom" then
            point, relativePoint = "TOPLEFT", "BOTTOMLEFT"
            offsetX, offsetY = 0, -3
            firstX, firstY = 0, -18
        elseif CellDB["tools"]["buffTracker"][2] == "bottom-to-top" then
            point, relativePoint = "BOTTOMLEFT", "TOPLEFT"
            offsetX, offsetY = 0, 3
            firstX, firstY = 0, 0
        end

        -- 遍历增益按钮：有提供者的显示并依次排列，无提供者的隐藏并重置
        local last
        for _, k in pairs(buffOrder) do
            P.ClearPoints(buttons[k])
            if available[k] then
                buttons[k]:Show()
                if last then
                    P.Point(buttons[k], point, last, relativePoint, offsetX, offsetY)
                else
                    P.Point(buttons[k], point, firstX, firstY)
                end
                last = buttons[k]
            else
                buttons[k]:Hide()
                buttons[k]:Reset()
            end
        end

        -- 占位图标（mover 模式下显示）同样按方向排列
        last = nil
        for _, icon in pairs(fakeIcons) do
            P.ClearPoints(icon)
            if last then
                P.Point(icon, point, last, relativePoint, offsetX, offsetY)
            else
                P.Point(icon, point, buffTrackerFrame, point, firstX, firstY)
            end
            last = icon
        end
    end
end

-- ResizeButtons: 根据设置中的按钮尺寸调整所有按钮和占位图标的大小
-- 同时根据布局方向和按钮数量重新计算并设置主框架的尺寸
-- 战斗中锁定 UI 时延迟到脱离战斗后再执行
local function ResizeButtons()
    if InCombatLockdown() then
        buffTrackerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        local size = CellDB["tools"]["buffTracker"][3]
        for _, i in pairs(fakeIcons) do
            P.Size(i, size, size)
        end
        for _, b in pairs(buttons) do
            P.Size(b, size, size)
        end

        local n = F.Getn(buttons)
        -- 水平布局：宽度 = N*按钮 + (N-1)*间距，高度 = 按钮+18（标题栏）
        if strfind(CellDB["tools"]["buffTracker"][2], "left") then
            buffTrackerFrame:SetSize(n * P.Scale(size) + (n - 1) * P.Scale(3), P.Scale(size + 18))
        else
        -- 垂直布局：宽度 = 按钮，高度 = N*按钮 + (N-1)*间距 + 18
            buffTrackerFrame:SetSize(P.Scale(size), n * P.Scale(size) + (n - 1) * P.Scale(3) + P.Scale(18))
        end
    end
end

-------------------------------------------------
-- fade out -- 淡出效果：非战斗/非 hover 时降低 BuffTracker 透明度
-------------------------------------------------
-- 收集所有按钮到 fadeOuts 列表，用于动画系统的淡入淡出控制
local fadeOuts = {}
for _, b in pairs(buttons) do
    tinsert(fadeOuts, b)
end
-- 将淡入淡出动画挂载到主框架：当设置启用淡出且不在 mover 模式时生效
A.ApplyFadeInOutToParent(buffTrackerFrame, function()
    return CellDB["tools"]["fadeOut"] and not buffTrackerFrame.moverText:IsShown()
end, unpack(fadeOuts))

---------------------------------------------------------------------
-- find aura -- 光环检测：检查指定单位是否有指定增益
---------------------------------------------------------------------
-- 缓存 API 引用
local GetAuraDataBySpellName = C_UnitAuras.GetAuraDataBySpellName

-- UnitBuffExists: 检测单位 unit 上是否存在 buff 增益（通过名称匹配光环）
-- 返回值1: exists (boolean) - 该增益是否存在
-- 返回值2: providedByMe (boolean, 可选) - 增益是否由玩家提供（非 secret 光环且 sourceUnit 为 "player"）
-- Midnight 版本中对非 secret 光环可直接获取 sourceUnit；secret 光环仅报告存在
local function UnitBuffExists(unit, buff)
    local names = buffs[buff]["names"]
    local aura
    for _, name in next, names do
        aura = GetAuraDataBySpellName(unit, name, "HELPFUL")
        if aura then
            -- Midnight 12.0.0+: raid buff spell IDs (1459, 6673, 21562, 462854, etc.) are flagged
            -- non-secret by Blizzard, so their aura fields (including sourceUnit) are real values.
            -- For any unexpected secret aura, treat as present but not provided by player.
            if F.IsAuraNonSecret(aura) then
                return true, aura.sourceUnit == "player"
            else
                return true
            end
        end
    end
end

---------------------------------------------------------------------
-- missing buffs -- 缺失增益指示器：在 Cell 单位框体上显示增益缺失图标
---------------------------------------------------------------------
-- missingBuffsFromMe: unit → { 玩家可以提供的、但该单位缺失的增益名称列表 }
local missingBuffsFromMe = {}
-- hasBuffFromMe: unit → 该单位是否已有玩家提供的增益（用于部分职业的快速判断）
local hasBuffFromMe = {}

-- UpdateMissingBuffs: 记录某单位缺失了玩家可提供的增益
local function UpdateMissingBuffs(unit, buff)
    missingBuffsFromMe[unit] = missingBuffsFromMe[unit] or {}
    tinsert(missingBuffsFromMe[unit], buff)
end

-- ShowMissingBuffs: 在单位框体上显示缺失增益指示器图标
-- 逻辑：
--   1. 先隐藏之前的指示器
--   2. 如果该单位缺失的增益只有 1 个，或玩家是牧师 → 显示对应增益的法术图标
--   3. 否则（多个缺失，且非牧师）→ 显示通用图标（254882）
--   4. 骑士/战士：如果该单位已有玩家提供的任意增益，则不显示（避免重复提示）
local function ShowMissingBuffs(unit)
    I.HideMissingBuffs(unit)

    if not missingBuffsFromMe[unit] then return end

    local num = #missingBuffsFromMe[unit]
    if num == 0 then return end

    -- 骑士和战士：如果该单位已有玩家提供的任一增益，跳过（无需重复提示）
    if myClass == "PALADIN" or myClass == "WARRIOR" then
        if hasBuffFromMe[unit] then return end
    end

    -- 单个缺失或玩家是牧师（牧师只有耐力一个群体增益，直接显示）
    if num == 1 or myClass == "PRIEST" then
        for _, buff in next, missingBuffsFromMe[unit] do
            I.ShowMissingBuff(unit, buffsProvidedByMe[buff][2])
        end
    else
        -- 多个缺失 → 显示通用图标（避免图标过多造成视觉混乱）
        I.ShowMissingBuff(unit, 254882)
    end
end

-------------------------------------------------
-- check -- 核心检查逻辑：检测单个单位的增益缺失情况
-------------------------------------------------
-- CheckUnit: 检测指定单位 unit 的增益状态
-- 流程：
--   1. 清空该单位之前的缺失记录
--   2. 验证单位连接/可见/存活
--   3. 通过 LGI 获取专精 ID，映射到 requiredBuffs 获得该专精需要的增益
--   4. 遍历所有 available 增益：需要的就检查光环，不需要的就清除记录
--   5. 如果缺失且玩家能提供，记录到 missingBuffsFromMe
--   6. 调用 ShowMissingBuffs 显示指示器
-- param updateBtn: 是否在检查完后更新按钮显示
local function CheckUnit(unit, updateBtn)
    -- print("CheckUnit", unit)
    if not hasBuffProvider then return end

    -- 清空该单位之前的缺失记录
    if missingBuffsFromMe[unit] then wipe(missingBuffsFromMe[unit]) end
    hasBuffFromMe[unit] = nil

    -- 仅检查已连接、可见且未死亡/释放的单位
    if UnitIsConnected(unit) and UnitIsVisible(unit) and not UnitIsDeadOrGhost(unit) then
        local guid = UnitGUID(unit)
        -- LGI 通过 GUID 索引缓存；secret GUID 会导致表查询异常，直接跳过
        if Cell.isMidnight and F.IsSecretValue and F.IsSecretValue(guid) then return end
        local info = LGI:GetCachedInfo(guid)
        local spec = info and info.specId -- 当前专精 ID
        local required = spec and requiredBuffs[spec] -- 该专精需要的增益（如 "attackPower"）

        -- 遍历所有增益类型
        for buff, hasProvider in next, available do
            if hasProvider then
                -- 仅检查该专精需要的增益 或 全员必需的增益
                if required == buff or requiredByEveryone[buff] then
                    local exists, providedByMe = UnitBuffExists(unit, buff)
                    if exists then
                        unaffected[buff][unit] = nil -- 增益存在，从缺失名单移除
                        if providedByMe then
                            hasBuffFromMe[unit] = true
                        end
                    else
                        unaffected[buff][unit] = true -- 增益缺失，加入缺失名单
                        if buffsProvidedByMe[buff] then
                            UpdateMissingBuffs(unit, buff)
                        end
                    end
                end
            else
                -- 该增益无提供者，清理该单位的记录
                unaffected[buff][unit] = nil
            end
        end
    else
        -- 单位不可用（离线/不可见/死亡），从所有缺失名单中移除
        for k, t in next, unaffected do
            t[unit] = nil
        end
    end

    ShowMissingBuffs(unit)

    if updateBtn then UpdateButtons() end
end

-- IterateAllUnits: 遍历所有队伍成员，执行完整的两阶段检查
-- 第一阶段：遍历所有成员，根据职业和等级确定哪些增益在当前队伍中可用
--           同时定位玩家自己的 unit token
-- 第二阶段：重新排列按钮，清空缺失记录，逐个检查每个成员的增益状态
local function IterateAllUnits()
    Reset("available")
    myUnit = ""

    -- 第一阶段：检查队伍中每种增益是否有提供者
    local class, level
    for unit in F.IterateGroupMembers() do
        if UnitIsConnected(unit) and UnitIsVisible(unit) then
            class = UnitClassBase(unit)
            level = UnitLevel(unit)
            -- 如果该单位职业有增益能力且等级达标，标记该增益为 available
            if classBuffs[class] then
                for buff, lvl in pairs(classBuffs[class]) do
                    if not available[buff] and level >= lvl then
                        available[buff] = true
                        hasBuffProvider = true
                    end
                end
            end

            -- 记录玩家自己的 unit token
            if UnitIsUnit("player", unit) then
                myUnit = unit
            end
        end
    end

    -- 先重新排列按钮（根据 available 更新可见性），再清空缺失记录
    RepointButtons()
    Reset("unaffected")

    -- 第二阶段：逐个检查每个成员的具体增益状态
    for unit in F.IterateGroupMembers() do
        CheckUnit(unit)
    end

    UpdateButtons()
end

-------------------------------------------------
-- events -- 事件处理：响应团队状态变化，更新增益追踪
-------------------------------------------------
-- UnitUpdated: LGI 回调，当某单位信息更新时触发（如切专精、入队、天赋变化）
-- 忽略宠物和非玩家单位；如果是玩家自己则检查 myUnit，否则直接检查该单位
function buffTrackerFrame:UnitUpdated(event, guid, unit, info)
    -- print(event, guid, unit, info.specId)
    if unit == "player" then
        if UnitIsUnit("player", myUnit) then CheckUnit(myUnit, true) end
    elseif UnitIsPlayer(unit) then -- ignore pets
        CheckUnit(unit, true)
    end
end

-- PLAYER_ENTERING_WORLD: 玩家进入世界后立即取消此事件注册，触发团队列表更新
function buffTrackerFrame:PLAYER_ENTERING_WORLD()
    buffTrackerFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    buffTrackerFrame:GROUP_ROSTER_UPDATE()
end

-- GROUP_ROSTER_UPDATE: 队伍成员列表变化时触发
-- 在组队时注册必须的事件监听（光环、就位确认、标志变化、复活）
-- 离队时取消事件监听、重置状态
-- immediate=true 立即执行全量检查；否则延迟 3 秒（防止频繁进出队伍时重复扫描）
local timer
function buffTrackerFrame:GROUP_ROSTER_UPDATE(immediate)
    if timer then timer:Cancel() end
    if IsInGroup() then
        -- 在队伍中：注册必要的事件监听
        buffTrackerFrame:RegisterEvent("READY_CHECK")
        buffTrackerFrame:RegisterEvent("UNIT_FLAGS")
        buffTrackerFrame:RegisterEvent("PLAYER_UNGHOST")
        buffTrackerFrame:RegisterEvent("UNIT_AURA")
    else
        -- 不在队伍中：取消所有事件监听，重置状态
        buffTrackerFrame:UnregisterEvent("READY_CHECK")
        buffTrackerFrame:UnregisterEvent("UNIT_FLAGS")
        buffTrackerFrame:UnregisterEvent("PLAYER_UNGHOST")
        buffTrackerFrame:UnregisterEvent("UNIT_AURA")

        Reset()
        RepointButtons()
        return
    end

    if immediate then
        IterateAllUnits()
    else
        timer = C_Timer.NewTimer(3, IterateAllUnits) -- 延迟 3 秒，避免频繁触发
    end
end

-- READY_CHECK: 就位确认时立即重新检查所有单位
function buffTrackerFrame:READY_CHECK()
    buffTrackerFrame:GROUP_ROSTER_UPDATE(true)
end

-- UNIT_FLAGS: 单位标志变化（如切换专精、连接状态变化）时延迟检查
function buffTrackerFrame:UNIT_FLAGS()
    buffTrackerFrame:GROUP_ROSTER_UPDATE()
end

-- PLAYER_UNGHOST: 玩家复活后在下一帧检查增益状态
function buffTrackerFrame:PLAYER_UNGHOST()
    buffTrackerFrame:GROUP_ROSTER_UPDATE()
end

-- UNIT_AURA: 单位光环变化时增量检查
-- 仅处理 raid/party/player 类型的单位，忽略宠物等
function buffTrackerFrame:UNIT_AURA(unit)
    -- Midnight 12.0.0+: unit parameter may be a secret string
    if F.IsSecretValue and F.IsSecretValue(unit) then return end
    if IsInRaid() then
        if unit:find("^raid%d+$") then
            CheckUnit(unit, true)
        end
    else
        if unit:find("^party%d$") or unit == "player" then
            CheckUnit(unit, true)
        end
    end
end

-- PLAYER_REGEN_ENABLED: 脱离战斗后执行战斗中锁定的 UI 操作（重排、重设尺寸）
function buffTrackerFrame:PLAYER_REGEN_ENABLED()
    buffTrackerFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    RepointButtons()
    ResizeButtons()
end

-- 通用事件分发：将事件名作为方法名调用（如 "UNIT_AURA" → buffTrackerFrame:UNIT_AURA(...)）
buffTrackerFrame:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end)

-------------------------------------------------
-- functions -- 外部 API：供 Cell 核心调用的入口函数
-------------------------------------------------
-- UpdateTools: Cell 设置变更时调用，负责启用/禁用 BuffTracker
-- which: "buffTracker" 启用/禁用增益追踪, "fadeOut" 仅更新淡出效果, nil 更新全部（含位置）
-- 启用时注册事件和 LGI 回调；禁用时取消所有事件、清空状态、隐藏缺失指示器
local function UpdateTools(which)
    if not which or which == "buffTracker" then
        if CellDB["tools"]["buffTracker"][1] then
            -- 启用 BuffTracker：注册事件和 LGI 回调
            buffTrackerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            buffTrackerFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
            LGI.RegisterCallback(buffTrackerFrame, "GroupInfo_Update", "UnitUpdated")

            -- 如果之前未启用但已在游戏中（手动开启），立即执行全量检查
            if not enabled and which == "buffTracker" then -- already in world, manually enabled
                buffTrackerFrame:GROUP_ROSTER_UPDATE(true)
            end
            enabled = true
            if Cell.vars.showMover then
                ShowMover(true)
            end
        else
            -- 禁用 BuffTracker：取消所有事件和回调，清空状态
            buffTrackerFrame:UnregisterAllEvents()
            LGI.UnregisterCallback(buffTrackerFrame, "GroupInfo_Update")

            Reset()
            myUnit = ""

            enabled = false
            ShowMover(false)

            -- 隐藏所有单位上的缺失增益指示器
            for unit in F.IterateGroupMembers() do
                I.HideMissingBuffs(unit, true)
            end
        end

        RepointButtons()
        ResizeButtons()
    end

    if not which or which == "fadeOut" then
        -- 仅更新淡出效果的透明度
        if CellDB["tools"]["fadeOut"] and not buffTrackerFrame.moverText:IsShown() then
            buffTrackerFrame:SetAlpha(0)
        else
            buffTrackerFrame:SetAlpha(1)
        end
    end

    if not which then -- 全量更新时加载保存的位置
        P.LoadPosition(buffTrackerFrame, CellDB["tools"]["buffTracker"][4])
    end
end
Cell.RegisterCallback("UpdateTools", "BuffTracker_UpdateTools", UpdateTools)

-- UpdatePixelPerfect: Cell 像素完美模式切换时调用，重算所有元素尺寸和锚点
local function UpdatePixelPerfect()
    -- P.Resize(buffTrackerFrame)

    for _, i in pairs(fakeIcons) do
        i:UpdatePixelPerfect()
    end

    for _, b in pairs(buttons) do
        b:UpdatePixelPerfect()
    end
end
Cell.RegisterCallback("UpdatePixelPerfect", "BuffTracker_UpdatePixelPerfect", UpdatePixelPerfect)