--[[
    CellD 工具函数模块 (Utils.lua)
    =================================
    提供全局工具函数（CellFuncs / F 命名空间）。
    包含: 职业系统、颜色转换、表操作、法术信息、单位迭代等核心工具。

    重要: 该文件在游戏加载时执行顶层代码，任何未保护的 API 调用失败
    都会导致整个文件加载中断，进而使所有核心函数为 nil。

    Secret Value 保护:
    战斗中敏感数据（生命值、能量、吸收量等）会被包装为 opaque 类型，
    不可直接比较或运算。本模块提供 F.IsSecretValue / F.SafeNumber
    / F.SafeCompareGE 等安全包装函数。
--]]
---@class Cell
local Cell = select(2, ...)
-- 本地化字符串表，用于多语言支持
local L = Cell.L
---@class CellFuncs
-- F 命名空间：所有全局工具函数的容器，供各模块调用
local F = Cell.funcs
---@type CellIndicatorFuncs
-- I 命名空间：指示器相关函数的容器
local I = Cell.iFuncs

-- 12.0.5: UnitFactionGroup 已移除，使用 C_UnitInfo.GetFactionGroup
-- 获取玩家阵营：优先使用旧 API，失败则回退到 C_UnitInfo.GetFactionGroup，都失败则默认 "Neutral"
local ok, faction = pcall(UnitFactionGroup, "player")
if not ok then ok, faction = pcall(C_UnitInfo.GetFactionGroup, "player") end
Cell.vars.playerFaction = ok and faction or "Neutral"

-------------------------------------------------
-- 游戏版本检测 (CellD: 仅支持 12.0.5+ 正式服)
-- 通过布尔标志判断当前游戏版本，供各模块进行版本分支逻辑
-- isMidnight: 12.0+ 版本引入 SecretValue 机制，所有敏感数据（血量/蓝量/光环等）在战斗中被包装为 opaque 类型
-------------------------------------------------
Cell.isAsian = LOCALE_zhCN or LOCALE_zhTW or LOCALE_koKR  -- 亚洲地区（中文/韩文），影响数字格式化
Cell.isRetail = true                                                -- CellD 仅正式服
Cell.isMidnight = true                                              -- CellD 仅 12.0+，SecretValue 防护的关键判断依据
Cell.isVanilla = false
Cell.isTBC = false
Cell.isWrath = false
Cell.isCata = false
Cell.isMists = false
Cell.isTWW = false                                                  -- 已进入 Midnight
Cell.flavor = "retail"

-------------------------------------------------
-- 职业系统初始化 (12.0.5 适配)
-- C_ClassInfo API 替代了废弃的 LocalizedClassList / GetNumClasses / GetClassInfo
-- localizedClass: 职业文件名为键，本地化职业名称为值（如 WARRIOR -> "战士"）
-- sortedClasses: 排序后的职业文件名列表
-- classFileToID: 职业文件名 -> 职业ID 映射
-- classIDToFile: 职业ID -> 职业文件名 映射
-------------------------------------------------
local localizedClass = {}
local sortedClasses = {}
local classFileToID = {}
local classIDToFile = {}

-- 硬编码零售服13职业列表作为回退方案
-- 当 C_ClassInfo API 不可用时（如旧版本或加载阶段），使用此回退确保职业系统仍能工作
local FALLBACK_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK",
    "MONK", "DRUID", "DEMONHUNTER", "EVOKER"
}
local FALLBACK_IDS = {1,2,3,4,5,6,7,8,9,10,11,12,13}

-- 尝试通过 C_ClassInfo API 初始化
-- 使用 pcall 保护，防止 API 不可用时中断整个文件加载
local classInitOk = pcall(function()
    for i = 1, C_ClassInfo.GetNumClasses() do
        local className, classFile, classID = C_ClassInfo.GetClassInfo(i)
        if classFile then
            tinsert(sortedClasses, classFile)
            classFileToID[classFile] = classID or i
            classIDToFile[classID or i] = classFile
        end
    end
    sort(sortedClasses)

    -- 本地化职业名称
    -- 将职业文件名映射到本地化名称（如 WARRIOR -> "战士" / "Warrior"）
    pcall(function()
        localizedClass = LocalizedClassList() or {}
    end)
end)

if not classInitOk then
    -- 回退：使用硬编码职业列表
    sortedClasses = {}
    for i, f in ipairs(FALLBACK_CLASSES) do
        tinsert(sortedClasses, f)
        classFileToID[f] = FALLBACK_IDS[i]
        classIDToFile[FALLBACK_IDS[i]] = f
    end
    sort(sortedClasses)

    -- 尝试旧 API 获取本地化名称
    pcall(function()
        localizedClass = LocalizedClassList()
    end)
    -- 如果旧 API 也不可用，使用 FillLocalizedClassList
    if not next(localizedClass) then
        pcall(FillLocalizedClassList, localizedClass)
    end
end

-- 根据职业文件名获取职业ID（如 "WARRIOR" -> 1）
function F.GetClassID(classFile)
    return classFileToID[classFile]
end

-- 获取本地化职业名称，支持通过文件名或ID查询
function F.GetLocalizedClassName(classFileOrID)
    if type(classFileOrID) == "string" then
        return localizedClass[classFileOrID] or classFileOrID
    elseif type(classFileOrID) == "number" and classIDToFile[classFileOrID] then
        return localizedClass[classIDToFile[classFileOrID]] or classFileOrID
    end
    return ""
end

-- 迭代所有职业，返回文件名、ID、序号
-- 用于循环遍历所有13个职业
function F.IterateClasses()
    local i = 0
    return function()
        i = i + 1
        if i <= #sortedClasses then
            return sortedClasses[i], classFileToID[sortedClasses[i]], i
        end
    end
end

-- 返回排序后职业列表的副本（避免外部修改原表）
function F.GetSortedClasses()
    return F.Copy(sortedClasses)
end

-------------------------------------------------
-- 经典版天赋系统
-- CellD 仅正式服，此段为保留的经典版兼容代码（暂不执行）
-- Cata 版：直接使用 GetActiveTalentGroup + 预存的专精图标/名称
-- Wrath/TBC/Vanilla 版：遍历天赋页找投入点数最多的作为当前专精
-------------------------------------------------
if Cell.isCata then
    function F.GetActiveTalentInfo()
        local which = GetActiveTalentGroup() == 1 and L["Primary Talents"] or L["Secondary Talents"]
        return which, Cell.vars.playerSpecIcon, Cell.vars.playerSpecName
    end

elseif Cell.isWrath or Cell.isTBC or Cell.isVanilla then
    function F.GetActiveTalentInfo()
        local which = GetActiveTalentGroup() == 1 and L["Primary Talents"] or L["Secondary Talents"]

        local maxPoints = 0
        local specName, specIcon, specFileName

        for i = 1, GetNumTalentTabs() do
            local id, name, description, icon, pointsSpent, background = GetTalentTabInfo(i)
            if pointsSpent > maxPoints then
                maxPoints = pointsSpent
                specIcon = icon
                specName = name
            -- elseif pointsSpent == maxPoints then
            --     specIcon = 132148
            end
        end

        return which, specIcon or 134400, specName or L["No Spec"]
    end
end

-- local specRoles = {
--     ["DeathKnightBlood"] = "DAMAGER",
--     ["DeathKnightFrost"] = "TANK",
--     ["DeathKnightUnholy"] = "DAMAGER",

--     ["DruidRestoration"] = "HEALER",
--     ["DruidBalance"] = "DAMAGER",
--     -- ["DruidFeralCombat"] = nil,

--     ["HunterBeastMastery"] = "DAMAGER",
--     ["HunterSurvival"] = "DAMAGER",
--     ["HunterMarksmanship"] = "DAMAGER",

--     ["MageFrost"] = "DAMAGER",
--     ["MageArcane"] = "DAMAGER",
--     ["MageFire"] = "DAMAGER",

--     ["PaladinHoly"] = "HEALER",
--     ["PaladinCombat"] = "DAMAGER",
--     ["PaladinProtection"] = "TANK",

--     ["PriestShadow"] = "DAMAGER",
--     ["PriestHoly"] = "HEALER",
--     ["PriestDiscipline"] = "HEALER",

--     ["RogueCombat"] = "DAMAGER",
--     ["RogueSubtlety"] = "DAMAGER",
--     ["RogueAssassination"] = "DAMAGER",

--     ["ShamanElementalCombat"] = "DAMAGER",
--     ["ShamanEnhancement"] = "DAMAGER",
--     ["ShamanRestoration"] = "HEALER",

--     ["WarlockSummoning"] = "DAMAGER",
--     ["WarlockDestruction"] = "DAMAGER",
--     ["WarlockCurses"] = "DAMAGER",

--     ["WarriorArms"] = "DAMAGER",
--     ["WarriorFury"] = "DAMAGER",
--     ["WarriorProtection"] = "TANK",
-- }

-- function F.GetPlayerRole()

-- end

-------------------------------------------------
-- 颜色转换与渐变
-- 提供 RGB/HEX/HSB 互转、颜色渐变、职业色等核心工具
-------------------------------------------------
-- RGB 归一化：[0,255] -> [0,1]，可选去饱和度参数
function F.ConvertRGB(r, g, b, desaturation)
    if not desaturation then desaturation = 1 end
    r = r / 255 * desaturation
    g = g / 255 * desaturation
    b = b / 255 * desaturation
    return r, g, b
end

-- RGB 反归一化：[0,1] -> [0,255]，用于 UI 控件设置颜色
function F.ConvertRGB_256(r, g, b)
    return floor(r * 255), floor(g * 255), floor(b * 255)
end

-- RGB 转为十六进制字符串（如 FF8800），用于聊天上色等场景
function F.ConvertRGBToHEX(r, g, b)
    local result = ""

    for key, value in pairs({r, g, b}) do
        local hex = ""

        while(value > 0)do
            local index = math.fmod(value, 16) + 1
            value = math.floor(value / 16)
            hex = string.sub("0123456789ABCDEF", index, index) .. hex
        end

        if(string.len(hex) == 0)then
            hex = "00"

        elseif(string.len(hex) == 1)then
            hex = "0" .. hex
        end

        result = result .. hex
    end

    return result
end

-- HEX 十六进制字符串转为 RGB [0,255]（如 "FF8800" -> 255, 136, 0）
function F.ConvertHEXToRGB(hex)
    hex = hex:gsub("#","")
    return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
end

-- https://wowpedia.fandom.com/wiki/ColorGradient
-- function F.ColorGradient(perc, r1,g1,b1, r2,g2,b2, r3,g3,b3)
--     perc = perc or 1
--     if perc >= 1 then
--         return r3, g3, b3
--     elseif perc <= 0 then
--         return r1, g1, b1
--     end

--     local segment, relperc = math.modf(perc * 2)
--     local rr1, rg1, rb1, rr2, rg2, rb2 = select((segment * 3) + 1, r1,g1,b1, r2,g2,b2, r3,g3,b3)

--     return rr1 + (rr2 - rr1) * relperc, rg1 + (rg2 - rg1) * relperc, rb1 + (rb2 - rb1) * relperc
-- end

-- 三色线性渐变：percent 在 [lowBound, highBound] 区间内，在 c1/c2/c3 之间平滑过渡
-- c1/c2/c3 是 {r,g,b} 格式的三元组
function F.ColorGradient(perc, c1, c2, c3, lowBound, highBound)
    local r1, g1, b1 = c1[1], c1[2], c1[3]
    local r2, g2, b2 = c2[1], c2[2], c2[3]
    local r3, g3, b3 = c3[1], c3[2], c3[3]

    lowBound = lowBound or 0
    highBound = highBound or 1
    perc = perc or 1

    if perc >= highBound then
        return r3, g3, b3
    elseif perc <= lowBound then
        return r1, g1, b1
    end

    perc = (perc - lowBound) / (highBound - lowBound)

    local segment, relperc = math.modf(perc * 2)
    local rr1, rg1, rb1, rr2, rg2, rb2 = select((segment * 3) + 1, r1,g1,b1, r2,g2,b2, r3,g3,b3)

    return rr1 + (rr2 - rr1) * relperc, rg1 + (rg2 - rg1) * relperc, rb1 + (rb2 - rb1) * relperc
end

-- 三色阈值模式：percent 按区间分段使用 c1/c2/c3，不渐变
-- useThresholdColor=true 时退化为 ColorGradient 渐变模式
function F.ColorThreshold(perc, c1, c2, c3, lowBound, highBound, useThresholdColor)
    if useThresholdColor then
        return F.ColorGradient(perc, c1, c2, c3, lowBound, highBound)
    end

    lowBound = lowBound or 0
    highBound = highBound or 1
    perc = perc or 1

    if perc >= highBound then
        return c3[1], c3[2], c3[3]
    elseif perc >= lowBound then
        return c2[1], c2[2], c2[3]
    else
        return c1[1], c1[2], c1[3]
    end
end

--! From ColorPickerAdvanced by Feyawen-Llane
--[[ Convert RGB to HSV ---------------------------------------------------
    Inputs:
        r = Red [0, 1]
        g = Green [0, 1]
        b = Blue [0, 1]
    Outputs:
        H = Hue [0, 360]
        S = Saturation [0, 1]
        B = Brightness [0, 1]
]]--
function F.ConvertRGBToHSB(r, g, b)
    local colorMax = max(max(r, g), b)
    local colorMin = min(min(r, g), b)
    local delta = colorMax - colorMin
    local H, S, B

    -- WoW's LUA doesn't handle floating point numbers very well (Somehow 1.000000 != 1.000000   WTF?)
    -- So we do this weird conversion of, Number to String back to Number, to make the IF..THEN work correctly!
    colorMax = tonumber(format("%f", colorMax))
    r = tonumber(format("%f", r))
    g = tonumber(format("%f", g))
    b = tonumber(format("%f", b))

    if (delta > 0) then
        if (colorMax == r) then
            H = 60 * (((g - b) / delta) % 6)
        elseif (colorMax == g) then
            H = 60 * (((b - r) / delta) + 2)
        elseif (colorMax == b) then
            H = 60 * (((r - g) / delta) + 4)
        end

        if (colorMax > 0) then
            S = delta / colorMax
        else
            S = 0
        end

        B = colorMax
    else
        H = 0
        S = 0
        B = colorMax
    end

    if (H < 0) then
        H = H + 360
    end

    return H, S, B
end

--[[ Convert HSB to RGB ---------------------------------------------------
    Inputs:
        h = Hue [0, 360]
        s = Saturation [0, 1]
        b = Brightness [0, 1]
    Outputs:
        R = Red [0,1]
        G = Green [0,1]
        B = Blue [0,1]
]]--
function F.ConvertHSBToRGB(h, s, b)
    local chroma = b * s
    local prime = (h / 60) % 6
    local X = chroma * (1 - abs((prime % 2) - 1))
    local M = b - chroma
    local R, G, B

    if (0 <= prime) and (prime < 1) then
        R = chroma
        G = X
        B = 0
    elseif (1 <= prime) and (prime < 2) then
        R = X
        G = chroma
        B = 0
    elseif (2 <= prime) and (prime < 3) then
        R = 0
        G = chroma
        B = X
    elseif (3 <= prime) and (prime < 4) then
        R = 0
        G = X
        B = chroma
    elseif (4 <= prime) and (prime < 5) then
        R = X
        G = 0
        B = chroma
    elseif (5 <= prime) and (prime < 6) then
        R = chroma
        G = 0
        B = X
    else
        R = 0
        G = 0
        B = 0
    end

    R = R + M
    G = G + M
    B =  B + M

    return R, G, B
end

-- 颜色反转：r/g/b 各自 1.0 - 原值，用于暗/亮主题切换
function F.InvertColor(r, g, b)
    return 1 - r, 1 - g, 1 - b
end

-------------------------------------------------
-- 数字处理
-- 四舍五入、数字格式化（千/万/亿 或 K/M/B）
-------------------------------------------------
-- 四舍五入，支持指定小数位数
function F.Round(num, numDecimalPlaces)
    if numDecimalPlaces and numDecimalPlaces >= 0 then
        local mult = 10 ^ numDecimalPlaces
        num = num * mult
        if num >= 0 then
            return floor(num + 0.5) / mult
        else
            return ceil(num - 0.5) / mult
        end
    end

    if num >= 0 then
        return floor(num + 0.5)
    else
        return ceil(num - 0.5)
    end
end

-- 亚洲地区数字单位（中文/韩文使用千/万/亿，非英文的 K/M/B）
local symbol_1K, symbol_10K, symbol_1B
if LOCALE_zhCN then
    symbol_1K, symbol_10K, symbol_1B = "千", "万", "亿"
elseif LOCALE_zhTW then
    symbol_1K, symbol_10K, symbol_1B = "千", "萬", "億"
elseif LOCALE_koKR then
    symbol_1K, symbol_10K, symbol_1B = "천", "만", "억"
end

local abs = math.abs

-- 数字格式化为可读字符串：
--   亚洲地区：千 -> 万 -> 亿（以万为一跳）
--   其他地区：K -> M -> B（以千为一跳）
if Cell.isAsian then
    function F.FormatNumber(n)
        if abs(n) >= 100000000 then
            return F.Round(n / 100000000, 2) .. symbol_1B
        elseif abs(n) >= 10000 then
            return F.Round(n / 10000, 1) .. symbol_10K
        else
            return n
        end
    end
else
    function F.FormatNumber(n)
        if abs(n) >= 1000000000 then
            return F.Round(n / 1000000000, 2) .. "B"
        elseif abs(n) >= 1000000 then
            return F.Round(n / 1000000, 2) .. "M"
        elseif abs(n) >= 1000 then
            return F.Round(n / 1000, 1) .. "K"
        else
            return n
        end
    end
end

-------------------------------------------------
-- 字符串处理
-- 首字母大写、数字分割、UTF-8 子串、文本宽度适配
-------------------------------------------------
-- 首字母大写，lowerOthers=true 时其余字母转为小写
function F.UpperFirst(str, lowerOthers)
    if lowerOthers then
        str = strlower(str)
    end
    return (str:gsub("^%l", string.upper))
end

-- 按分隔符拆分字符串并转为数字数组，非数字项保留原字符串
function F.SplitToNumber(sep, str)
    if not str then return end

    local ret = {strsplit(sep, str)}
    for i, v in ipairs(ret) do
        ret[i] = tonumber(v) or ret[i] -- keep non number
    end
    return unpack(ret)
end

-- UTF-8 字符字节宽度判断：1-4 字节
local function Chsize(char)
    if not char then
        return 0
    elseif char > 240 then
        return 4
    elseif char > 225 then
        return 3
    elseif char > 192 then
        return 2
    else
        return 1
    end
end

-- UTF-8 安全的字符串截取：按字符数而非字节数切割，保证中文不乱码
function F.Utf8sub(str, startChar, numChars)
    if not str then return "" end
    local startIndex = 1
    while startChar > 1 do
        local char = string.byte(str, startIndex)
        startIndex = startIndex + Chsize(char)
        startChar = startChar - 1
    end

    local currentIndex = startIndex

    while numChars > 0 and currentIndex <= #str do
        local char = string.byte(str, currentIndex)
        currentIndex = currentIndex + Chsize(char)
        numChars = numChars -1
    end
    return str:sub(startIndex, currentIndex - 1)
end

-- 文本宽度适配：自动截断过长文本并添加 "..." 省略号
-- alignment="right" 时从右侧截断（前置 "..."），否则从左侧截断（后置 "..."）
-- SecretValue 防护：secret 字符串无法被测量/截断（utf8len/utf8sub 抛出错误），
-- 但 FontString:SetText() 原生接受 secret 值用于显示，故直接设置文本后返回
function F.FitWidth(fs, text, alignment)
    -- Midnight 12.0.0+: secret strings can't be measured/truncated,
    -- but FontString:SetText() accepts secret values for display.
    if F.IsSecretValue(text) then
        fs:SetText(text)
        return
    end
    fs:SetText(text)

    if fs:IsTruncated() then
        for i = 1, string.utf8len(text) do
            if strlower(alignment) == "right" then
                fs:SetText("..."..string.utf8sub(text, i))
            else
                fs:SetText(string.utf8sub(text, i).."...")
            end

            if not fs:IsTruncated() then
                break
            end
        end
    end
end

-------------------------------------------------
-- 表操作工具
-- 提供表长度、键查找、深拷贝、插入/删除、排序、转换等功能
-------------------------------------------------
-- 获取表的元素数量（非数组长度 #t，使用 pairs 遍历所有键）
function F.Getn(t)
    local count = 0
    for _ in next, t do
        count = count + 1
    end
    return count
end

-- 逆查：在表中查找元素 e 对应的键
function F.GetIndex(t, e)
    for i, v in pairs(t) do
        if e == v then
            return i
        end
    end
    return nil
end

-- 获取表的所有键列表
function F.GetKeys(t)
    local keys = {}
    for k in pairs(t) do
        tinsert(keys, k)
    end
    return keys
end

-- 递归深拷贝表（包括嵌套子表），避免引用共享
function F.Copy(t)
    local newTbl = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            newTbl[k] = F.Copy(v)
        else
            newTbl[k] = v
        end
    end
    return newTbl
end

-- 检查表中是否包含某个值
function F.TContains(t, v)
    for _, value in pairs(t) do
        if value == v then return true end
    end
    return false
end

-- 在第一个空槽插入元素（稀疏数组填充）
function F.TInsert(t, v)
    local i, done = 1
    repeat
        if not t[i] then
            t[i] = v
            done = true
        end
        i = i + 1
    until done
end

-- 仅当元素不存在时才插入，避免重复
function F.TInsertIfNotExists(t, ...)
    local n = select("#", ...)
    if n == 0 then return end

    if n == 1 then
        local v = ...
        if not F.TContains(t, v) then
            tinsert(t, v)
        end
    else
        local values = F.ConvertTable(t, true)
        for i = 1, n do
            local v = select(i, ...)
            if not values[v] then
                tinsert(t, v)
            end
        end
        values = nil
    end

end

-- 从数组中移除所有等于 v 的元素（倒序遍历避免索引错位）
function F.TRemove(t, v)
    for i = #t, 1, -1 do
        if t[i] == v then
            table.remove(t, i)
        end
    end
end

-- 合并多个表，后面的表覆盖前面的同名键
function F.TMergeOverwrite(...)
    local n = select("#", ...)
    if n == 0 then return {} end

    local temp = F.Copy(...)
    for i = 2, n do
        local t = select(i, ...)
        for k, v in pairs(t) do
            temp[k] = v
        end
    end
    return temp
end

-- 只保留指定键，删除其余所有键（白名单模式）
function F.RemoveElementsExceptKeys(tbl, ...)
    local keys = {}

    for i = 1, select("#", ...) do
        local k = select(i, ...)
        keys[k] = true
    end

    for k in pairs(tbl) do
        if not keys[k] then
            tbl[k] = nil
        end
    end
end

-- 删除指定的键（黑名单模式）
function F.RemoveElementsByKeys(tbl, ...)
    for i = 1, select("#", ...) do
        local k = select(i, ...)
        tbl[k] = nil
    end
end

-- 多键排序：最多支持三级排序（按 k1/k2/k3 字段，分别指定 ascending/descending）
function F.Sort(t, k1, order1, k2, order2, k3, order3)
    table.sort(t, function(a, b)
        if a[k1] ~= b[k1] then
            if order1 == "ascending" then
                return a[k1] < b[k1]
            else -- "descending"
                return a[k1] > b[k1]
            end
        elseif k2 and order2 and a[k2] ~= b[k2] then
            if order2 == "ascending" then
                return a[k2] < b[k2]
            else -- "descending"
                return a[k2] > b[k2]
            end
        elseif k3 and order3 and a[k3] ~= b[k3] then
            if order3 == "ascending" then
                return a[k3] < b[k3]
            else -- "descending"
                return a[k3] > b[k3]
            end
        end
    end)
end

-- 字符串按分隔符拆分为表，convertToNum=true 时将有效数字转为数值类型
function F.StringToTable(s, sep, convertToNum)
    local t = {}
    for i, v in pairs({string.split(sep, s)}) do
        v = strtrim(v)
        if v ~= "" then
            if convertToNum then
                v = tonumber(v)
                if v then tinsert(t, v) end
            else
                tinsert(t, v)
            end
        end
    end
    return t
end

-- 表转字符串：用分隔符连接数组元素
function F.TableToString(t, sep)
    return table.concat(t, sep)
end

-- 数组转查找表：{v1, v2, ...} -> {[v1] = k1, [v2] = k2, ...}，用于 O(1) 查找
function F.ConvertTable(t, value)
    local temp = {}
    for k, v in ipairs(t) do
        temp[v] = value or k
    end
    return temp
end

-- 法术ID表转查找表，convertIdToName=true 时以法术名称为键
function F.ConvertSpellTable(t, convertIdToName)
    if not convertIdToName then
        return F.ConvertTable(t)
    end

    local temp = {}
    for k, v in ipairs(t) do
        local name = F.GetSpellInfo(v)
        if name then
            temp[name] = k
        end
    end
    return temp
end

function F.ConvertSpellTable_WithColor(t, convertIdToName)
    local temp = {}
    for k, st in ipairs(t) do
        local index

        if convertIdToName then
            index = F.GetSpellInfo(st[1])
        else
            index = st[1]
        end

        if index then
            temp[index] = {k, st[2]}
        end
    end
    return temp
end

-- 按职业分类的法术表转为统一查找表（所有职业法术打平为 {[id]=true}）
function F.ConvertSpellTable_WithClass(t)
    local temp = {}
    for class, ct in pairs(t) do
        for _, id in ipairs(ct) do
            local name = F.GetSpellInfo(id)
            if name then
                temp[id] = true
            end
        end
    end
    return temp
end

-- 法术持续时间表转换："spellId:duration" 格式字符串拆分为键值对
-- convertIdToName=true 时以法术名为键，否则以数字ID为键
function F.ConvertSpellDurationTable(t, convertIdToName)
    local temp = {}
    for _, v in ipairs(t) do
        local id, duration = strsplit(":", v)
        local name = F.GetSpellInfo(id)
        if name then
            if convertIdToName then
                temp[name] = tonumber(duration)
            else
                temp[tonumber(id)] = tonumber(duration)
            end
        end
    end
    return temp
end

-- 按职业分类的持续时间表转为 {[id] = {duration, icon}} 格式
function F.ConvertSpellDurationTable_WithClass(t)
    local temp = {}
    for class, ct in pairs(t) do
        for k, v in ipairs(ct) do
            local id, duration = strsplit(":", v)
            local name, icon = F.GetSpellInfo(id)
            if name then
                temp[tonumber(id)] = {tonumber(duration), icon}
            end
        end
    end
    return temp
end

-- 差集计算：返回在 previous 中但不在 after 中的元素
function F.CheckTableRemoved(previous, after)
    local aa = {}
    local ret = {}

    for k,v in pairs(previous) do aa[v] = true end
    for k,v in pairs(after) do aa[v] = nil end

    for k,v in pairs(previous) do
        if aa[v] then
            tinsert(ret, v)
        end
    end
    return ret
end

-- 过滤无效法术：从列表中移除游戏中不存在的法术ID
function F.FilterInvalidSpells(t)
    if not t then return end
    for i = #t, 1, -1 do
        local spellId
        if type(t[i]) == "number" then
            spellId = t[i]
        else -- table
            spellId = t[i][1]
        end
        if not F.GetSpellInfo(spellId) then
            tremove(t, i)
        end
    end
end

-------------------------------------------------
-- 通用工具
-- 单位全名、短名、时间格式化
-------------------------------------------------
-- function F.GetRealmName()
--     return string.gsub(GetRealmName(), " ", "")
-- end

-- 获取单位全名（含服务器名），如 "PlayerName-ServerName"
-- SecretValue 防护：Midnight 12.0.0+ 下玩家名可能为 secret string，直接返回而不拼接服务器名
function F.UnitFullName(unit)
    if not unit or not UnitIsPlayer(unit) then return end

    local name = GetUnitName(unit, true)
    -- Midnight 12.0.0+: name may be a secret string
    if F.IsSecretValue(name) then return name end

    --? name might be nil in some cases?
    if name and not string.find(name, "-") then
        local server = GetNormalizedRealmName()
        --? server might be nil in some cases?
        if server then
            name = name.."-"..server
        end
    end

    return name
end

-- 从全名（含服务器）提取短名，如 "PlayerName-ServerName" -> "PlayerName"
function F.ToShortName(fullName)
    if not fullName then return "" end
    local shortName = strsplit("-", fullName)
    return shortName
end

-- 秒数格式化为简短时间字符串（h/m/s）
function F.FormatTime(s)
    if s >= 3600 then
        return "%dh", ceil(s / 3600)
    elseif s >= 60 then
        return "%dm", ceil(s / 60)
    end
    return "%ds", floor(s)
end

-- function F.SecondsToTime(seconds)
--     local m = seconds / 60
--     local s = seconds % 60
--     return format("%d:%02d", m, s)
-- end

-- 游戏全局格式化字符串（如 "%d sec", "%.1f min" 等，根据客户端语言变化）
local SEC = _G.SPELL_DURATION_SEC
local MIN = _G.SPELL_DURATION_MIN

-- 检测全局格式化字符串中的小数位模式，用于去除多余的小数位
-- 例如 "%.1f" -> 去除 ".%0" 模板，"%.2f" -> 去除 ".%00" 模板
local PATTERN_SEC
local PATTERN_MIN
if strfind(SEC, "1f") then
    PATTERN_SEC = "%.0"
elseif strfind(SEC, "2f") then
    PATTERN_SEC = "%.00"
end
if strfind(MIN, "1f") then
    PATTERN_MIN = "%.0"
elseif strfind(MIN, "2f") then
    PATTERN_MIN = "%.00"
end

-- 秒数转为游戏内置的时长显示格式（如 "5 min" / "30 sec"），去除多余小数位
function F.SecondsToTime(seconds)
    if seconds > 60 then
        return gsub(format(MIN, seconds / 60), PATTERN_MIN, "")
    else
        return gsub(format(SEC, seconds), PATTERN_SEC, "")
    end
end

-------------------------------------------------
-- 单位按钮迭代与管理
-- Cell 的 RaidFrameHeader 在合并/分离布局下使用不同 header 命名：
--   combinedHeader  = 合并布局（所有小队在同一容器）
--   separatedHeaders = 分离布局（每小队独立 header）
-- unitButtons 结构: solo/party/raid/pet/npc/spotlight/quickAssist 子表，每个包含按钮对象和 units 映射
-------------------------------------------------
local combinedHeader = "CellRaidFrameHeader0"
local separatedHeaders = {"CellRaidFrameHeader1", "CellRaidFrameHeader2", "CellRaidFrameHeader3", "CellRaidFrameHeader4", "CellRaidFrameHeader5", "CellRaidFrameHeader6", "CellRaidFrameHeader7", "CellRaidFrameHeader8"}

-- REVIEW:
-- Cell.clickCastFrames = {}
-- Cell.clickCastFrameQueue = {}

-- function F.RegisterFrame(frame)
--     Cell.clickCastFrames[frame] = true
--     Cell.clickCastFrameQueue[frame] = true  -- put into queue
--     Cell.Fire("UpdateQueuedClickCastings")
-- end

-- function F.UnregisterFrame(frame)
--     Cell.clickCastFrames[frame] = nil       -- ignore
--     Cell.clickCastFrameQueue[frame] = false -- mark for only cleanup
--     Cell.Fire("UpdateQueuedClickCastings")
-- end

-- 遍历所有单位按钮并执行回调
-- updateCurrentGroupOnly: 仅更新当前队伍类型的按钮
-- updateQuickAssists: 同时更新快捷协助按钮（正式服最多40个）
-- skipShared: 跳过 NPC 和 spotlight 等共享按钮
function F.IterateAllUnitButtons(func, updateCurrentGroupOnly, updateQuickAssists, skipShared)
    -- solo
    if not updateCurrentGroupOnly or (updateCurrentGroupOnly and Cell.vars.groupType == "solo") then
        for _, b in pairs(Cell.unitButtons.solo) do
            func(b)
        end
    end

    -- party
    if not updateCurrentGroupOnly or (updateCurrentGroupOnly and Cell.vars.groupType == "party") then
        for index, b in pairs(Cell.unitButtons.party) do
            if index ~= "units" then
                func(b)
            end
        end
    end

    -- raid
    if not updateCurrentGroupOnly or (updateCurrentGroupOnly and Cell.vars.groupType == "raid") then
        if not updateCurrentGroupOnly or Cell.vars.currentLayoutTable.main.combineGroups then
            for _, b in ipairs(Cell.unitButtons.raid[combinedHeader]) do
                func(b)
            end
        end

        if not updateCurrentGroupOnly or not Cell.vars.currentLayoutTable.main.combineGroups then
            for _, header in ipairs(separatedHeaders) do
                for _, b in ipairs(Cell.unitButtons.raid[header]) do
                    func(b)
                end
            end
        end

        -- arena pet
        for _, b in pairs(Cell.unitButtons.arena) do
            func(b)
        end
    end

    -- group pet
    if not updateCurrentGroupOnly or (updateCurrentGroupOnly and Cell.vars.groupType == "raid") or (updateCurrentGroupOnly and Cell.vars.groupType == "party") then
        for index, b in pairs(Cell.unitButtons.pet) do
            if index ~= "units" then
                func(b)
            end
        end
    end

    if not skipShared then
        -- npc
        for _, b in ipairs(Cell.unitButtons.npc) do
            func(b)
        end

        -- spotlight
        for _, b in pairs(Cell.unitButtons.spotlight) do
            func(b)
        end
    end

    if Cell.isRetail and updateQuickAssists then
        for i = 1, 40 do
            func(Cell.unitButtons.quickAssist[i])
        end
    end
end

-- 仅遍历共享单位按钮（NPC 和 Spotlight 关注目标）
function F.IterateSharedUnitButtons(func)
    -- npc
    for _, b in ipairs(Cell.unitButtons.npc) do
        func(b)
    end

    -- spotlight
    for _, b in pairs(Cell.unitButtons.spotlight) do
        func(b)
    end
end

-- 根据 unit token 获取对应的单位按钮
-- 返回: normal(主按钮), spotlights(关注列表), quickAssist(快捷协助)
-- 根据当前队伍类型（raid/party/solo）和战场状态查找对应按钮
function F.GetUnitButtonByUnit(unit, getSpotlights, getQuickAssist)
    if not unit then return end

    local normal, spotlights, quickAssist

    if Cell.vars.groupType == "raid" then
        if Cell.vars.inBattleground == 5 then
            normal = Cell.unitButtons.raid.units[unit] or Cell.unitButtons.npc.units[unit] or Cell.unitButtons.arena[unit]
        else
            normal = Cell.unitButtons.raid.units[unit] or Cell.unitButtons.npc.units[unit] or Cell.unitButtons.pet.units[unit]
        end
    elseif Cell.vars.groupType == "party" then
        normal = Cell.unitButtons.party.units[unit] or Cell.unitButtons.npc.units[unit]
    else -- solo
        normal = Cell.unitButtons.solo[unit] or Cell.unitButtons.npc.units[unit]
    end

    if getSpotlights then
        spotlights = {}
        for _, b in pairs(Cell.unitButtons.spotlight) do
            if b.unit and UnitIsUnit(b.unit, unit) then
                tinsert(spotlights, b)
            end
        end
    end

    if getQuickAssist then
        quickAssist = Cell.unitButtons.quickAssist.units[unit]
    end

    return normal, spotlights, quickAssist
end

-- 通过 GUID 获取单位按钮（先查 Cell.vars.guids 映射表转为 unit token）
function F.GetUnitButtonByGUID(guid, getSpotlights, getQuickAssist)
    return F.GetUnitButtonByUnit(Cell.vars.guids[guid], getSpotlights, getQuickAssist)
end

-- 通过玩家全名获取单位按钮（先查 Cell.vars.names 映射表转为 unit token）
function F.GetUnitButtonByName(name, getSpotlights, getQuickAssist)
    return F.GetUnitButtonByUnit(Cell.vars.names[name], getSpotlights, getQuickAssist)
end

-- 对指定单位的主按钮和所有 spotlight 按钮执行回调
-- type 为 "guid" 或 "name" 时先从映射表转换为 unit token
function F.HandleUnitButton(type, unit, func, ...)
    if not unit then return end

    if type == "guid" then
        unit = Cell.vars.guids[unit]
    elseif type == "name" then
        unit = Cell.vars.names[unit]
    end

    if not unit then return end

    local handled, normal

    if Cell.vars.groupType == "raid" then
        if Cell.vars.inBattleground == 5 then
            normal = Cell.unitButtons.raid.units[unit] or Cell.unitButtons.npc.units[unit] or Cell.unitButtons.arena[unit]
        else
            normal = Cell.unitButtons.raid.units[unit] or Cell.unitButtons.npc.units[unit] or Cell.unitButtons.pet.units[unit]
        end
    elseif Cell.vars.groupType == "party" then
        normal = Cell.unitButtons.party.units[unit] or Cell.unitButtons.npc.units[unit]
    else -- solo
        normal = Cell.unitButtons.solo[unit] or Cell.unitButtons.npc.units[unit]
    end

    if normal then
        func(normal, ...)
        handled = true
    end

    for _, b in pairs(Cell.unitButtons.spotlight) do
        if b.states.unit and UnitIsUnit(b.states.unit, unit) then
            func(b, ...)
            handled = true
        end
    end

    return handled
end

-- 按指定宽度模式更新文本：
--   "unlimited": 直接设置全文
--   "percentage": 按父框宽度百分比截断
--   "length": 按字符数截断（英文/非英文分别指定长度）
-- SecretValue 防护：secret 字符串无法测量/截断，直接 SetText 后返回
function F.UpdateTextWidth(fs, text, width, relativeTo)
    if not text or not width then return end
    -- Midnight 12.0.0+: secret strings can't be measured/truncated
    -- (utf8len/utf8sub throw on secrets), but FontString:SetText()
    -- accepts secret values natively for display.
    local isSecret = F.IsSecretValue(text)

    if width == "unlimited" or isSecret then
        fs:SetText(text)
    elseif width[1] == "percentage" then
        local percent = width[2] or 0.75
        local width = relativeTo:GetWidth() - 2
        for i = string.utf8len(text), 0, -1 do
            fs:SetText(string.utf8sub(text, 1, i))
            if fs:GetWidth() / width <= percent then
                break
            end
        end
    elseif width[1] == "length" then
        if string.len(text) == string.utf8len(text) then -- en
            fs:SetText(string.utf8sub(text, 1, width[2]))
        else -- non-en
            fs:SetText(string.utf8sub(text, 1, width[3]))
        end
    end
end

-- 获取团队标记图标转义序列（|T 纹理标记），用于在文本中嵌入标记图标
-- index 1-8 对应 8 种团队标记（星星/大饼/菱形等）
function F.GetMarkEscapeSequence(index)
    index = index - 1
    local left, right, top, bottom
    local coordIncrement = 64 / 256
    left = mod(index , 4) * coordIncrement
    right = left + coordIncrement
    top = floor(index / 4) * coordIncrement
    bottom = top + coordIncrement
    return string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcons:0:0:0:0:64:64:%d:%d:%d:%d|t", left*64, right*64, top*64, bottom*64)
end

-- local scriptObjects = {}
-- local frame = CreateFrame("Frame")
-- frame:RegisterEvent("PLAYER_REGEN_DISABLED")
-- frame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- frame:SetScript("OnEvent", function(self, event)
--     if event == "PLAYER_REGEN_ENABLED" then
--         for _, obj in pairs(scriptObjects) do
--             obj:Show()
--         end
--     else
--         for _, obj in pairs(scriptObjects) do
--             obj:Hide()
--         end
--     end
-- end)
-- function F.SetHideInCombat(obj)
--     tinsert(scriptObjects, obj)
-- end

-------------------------------------------------
-- 全局函数本地引用（性能优化：避免频繁全局查找）
-- 将高频调用的 WoW API 提升为本地变量，减少 _G 表访问开销
-------------------------------------------------
local UnitGUID = UnitGUID
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local UnitIsPlayer = UnitIsPlayer
local UnitIsUnit = UnitIsUnit
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid
local UnitPlayerOrPetInParty = UnitPlayerOrPetInParty
local UnitPlayerOrPetInRaid = UnitPlayerOrPetInRaid
local UnitClass = UnitClass
local UnitClassBase = UnitClassBase
local UnitName = UnitName
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
-- UnitInPartyIsAI: 12.0+ 追随者地下城 API，旧版本不可用时退化为空函数
local UnitInPartyIsAI = UnitInPartyIsAI or function() end

-------------------------------------------------
-- 框架颜色与职业颜色
-- 支持默认职业色、自定义职业色（CUSTOM_CLASS_COLORS 插件）、宠物/NPC 颜色
-------------------------------------------------
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
-- 获取职业颜色 RGB [0,1]，优先使用 CUSTOM_CLASS_COLORS 插件自定义色
function F.GetClassColor(class)
    if class and class ~= "" and RAID_CLASS_COLORS[class] then
        if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class] then
            return CUSTOM_CLASS_COLORS[class].r, CUSTOM_CLASS_COLORS[class].g, CUSTOM_CLASS_COLORS[class].b
        else
            return RAID_CLASS_COLORS[class]:GetRGB()
        end
    else
        return 1, 1, 1
    end
end

-- 获取职业颜色转义序列（|c 格式），用于聊天或文本着色
function F.GetClassColorStr(class)
    if class and class ~= "" and RAID_CLASS_COLORS[class] then
        if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class] then
            return "|c"..CUSTOM_CLASS_COLORS[class].colorStr
        else
            return "|c"..RAID_CLASS_COLORS[class].colorStr
        end
    else
        return "|cffffffff"
    end
end

-- 根据单位获取颜色：玩家->职业色，宠物->浅蓝(0.5,0.5,1)，NPC/载具->绿色(0,1,0.2)
function F.GetUnitClassColor(unit, class, guid)
    class = class or select(2, UnitClass(unit))
    guid = guid or UnitGUID(unit)

    if UnitIsPlayer(unit) or UnitInPartyIsAI(unit) then -- player
        return F.GetClassColor(class)
    elseif F.IsPet(guid, unit) then -- pet
        return 0.5, 0.5, 1
    else -- npc / vehicle
        return 0, 1, 0.2
    end
end


-- 获取单位能量条颜色，返回 r, g, b, powerType
-- 优先使用 PowerBarColor 表，特殊处理法力值（默认太暗）和狂乱值
-- 回退：若无 powerToken 映射，使用 powerType 索引或 altR/altG/altB
function F.GetPowerColor(unit)
    local r, g, b, t
    -- https://wow.gamepedia.com/API_UnitPowerType
    local powerType, powerToken, altR, altG, altB = UnitPowerType(unit)
    t = powerType

    local info = PowerBarColor[powerToken]
    if powerType == 0 then -- MANA
        info = {r=0, g=0.5, b=1} -- default mana color is too dark!
    elseif powerType == 13 then -- INSANITY
        info = {r=0.6, g=0.2, b=1}
    end

    if info then
        --The PowerBarColor takes priority
        r, g, b = info.r, info.g, info.b
    else
        if not altR then
            -- Couldn't find a power token entry. Default to indexing by power type or just mana if  we don't have that either.
            info = PowerBarColor[powerType] or PowerBarColor["MANA"]
            r, g, b = info.r, info.g, info.b
        else
            r, g, b = altR, altG, altB
        end
    end
    return r, g, b, t
end

-- 获取能量条最终颜色（含损失色），根据用户设置应用 class_color / power_color_dark / custom 等模式
-- 返回值: r, g, b（满能量色）, lossR, lossG, lossB（能量损失部分色）, powerType
function F.GetPowerBarColor(unit, class)
    local r, g, b, lossR, lossG, lossB, t
    r, g, b, t = F.GetPowerColor(unit)

    if not Cell.loaded then
        return r, g, b, r*0.2, g*0.2, b*0.2, t
    end

    if CellDB["appearance"]["powerColor"][1] == "power_color_dark" then
        lossR, lossG, lossB = r, g, b
        r, g, b = r*0.2, g*0.2, b*0.2
    elseif CellDB["appearance"]["powerColor"][1] == "class_color" then
        r, g, b = F.GetClassColor(class)
        lossR, lossG, lossB = r*0.2, g*0.2, b*0.2
    elseif CellDB["appearance"]["powerColor"][1] == "custom" then
        r, g, b = unpack(CellDB["appearance"]["powerColor"][2])
        lossR, lossG, lossB = r*0.2, g*0.2, b*0.2
    else
        lossR, lossG, lossB = r*0.2, g*0.2, b*0.2
    end
    return r, g, b, lossR, lossG, lossB, t
end

-- 获取生命条颜色（含损失色），根据用户设置支持：
--   满血特殊色 / 职业色 / 阈值渐变 / 自定义色 等多种模式
-- 返回值: barR, barG, barB（生命色）, lossR, lossG, lossB（生命损失部分色）
function F.GetHealthBarColor(percent, isDeadOrGhost, r, g, b)
    if not Cell.loaded then
        return r, g, b, r*0.2, g*0.2, b*0.2
    end

    local barR, barG, barB, lossR, lossG, lossB
    percent = percent or 1

    -- bar
    if percent == 1 and Cell.vars.useFullColor then
        barR = CellDB["appearance"]["fullColor"][2][1]
        barG = CellDB["appearance"]["fullColor"][2][2]
        barB = CellDB["appearance"]["fullColor"][2][3]
    else
        if CellDB["appearance"]["barColor"][1] == "class_color" then
            barR, barG, barB = r, g, b
        elseif CellDB["appearance"]["barColor"][1] == "class_color_dark" then
            barR, barG, barB = r*0.2, g*0.2, b*0.2
        elseif CellDB["appearance"]["barColor"][1] == "threshold1" then
            local c = CellDB["appearance"]["colorThresholds"]
            barR, barG, barB = F.ColorThreshold(percent, c[1], c[2], c[3], c[4], c[5], c[6])
        elseif CellDB["appearance"]["barColor"][1] == "threshold2" then
            local c = CellDB["appearance"]["colorThresholds"]
            if percent >= c[5] then
                barR, barG, barB = r, g, b -- full: class color
            else
                barR, barG, barB = F.ColorThreshold(percent, c[1], c[2], {r, g, b}, c[4], c[5], c[6])
            end
        elseif CellDB["appearance"]["barColor"][1] == "threshold3" then
            local c = CellDB["appearance"]["colorThresholds"]
            if percent >= c[5] then
                barR, barG, barB = r*0.2, g*0.2, b*0.2 -- full: class color
            else
                barR, barG, barB = F.ColorThreshold(percent, c[1], c[2], {r*0.2, g*0.2, b*0.2}, c[4], c[5], c[6])
            end
        else
            barR = CellDB["appearance"]["barColor"][2][1]
            barG = CellDB["appearance"]["barColor"][2][2]
            barB = CellDB["appearance"]["barColor"][2][3]
        end
    end

    -- loss
    if isDeadOrGhost and Cell.vars.useDeathColor then
        lossR = CellDB["appearance"]["deathColor"][2][1]
        lossG = CellDB["appearance"]["deathColor"][2][2]
        lossB = CellDB["appearance"]["deathColor"][2][3]
    else
        if CellDB["appearance"]["lossColor"][1] == "class_color" then
            lossR, lossG, lossB = r, g, b
        elseif CellDB["appearance"]["lossColor"][1] == "class_color_dark" then
            lossR, lossG, lossB = r*0.2, g*0.2, b*0.2
        elseif CellDB["appearance"]["lossColor"][1] == "threshold1" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            lossR, lossG, lossB = F.ColorThreshold(percent, c[1], c[2], c[3], c[4], c[5], c[6])
        elseif CellDB["appearance"]["lossColor"][1] == "threshold2" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            if isDeadOrGhost or percent <= c[4] then
                lossR, lossG, lossB = r, g, b  -- dead: class color
            else
                lossR, lossG, lossB = F.ColorThreshold(percent, {r, g, b}, c[2], c[3], c[4], c[5], c[6])
            end
        elseif CellDB["appearance"]["lossColor"][1] == "threshold3" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            if isDeadOrGhost or percent <= c[4] then
                lossR, lossG, lossB = r*0.2, g*0.2, b*0.2  -- dead: class color
            else
                lossR, lossG, lossB = F.ColorThreshold(percent, {r*0.2, g*0.2, b*0.2}, c[2], c[3], c[4], c[5], c[6])
            end
        else
            lossR = CellDB["appearance"]["lossColor"][2][1]
            lossG = CellDB["appearance"]["lossColor"][2][2]
            lossB = CellDB["appearance"]["lossColor"][2][3]
        end
    end

    return barR, barG, barB, lossR, lossG, lossB
end

-------------------------------------------------
-- 单位/队伍迭代
-- 提供小队成员数、子组查询、宠物单位转换、队伍类型判断等工具
-------------------------------------------------
-- 获取指定小队编号中的成员数量
function F.GetNumSubgroupMembers(group)
    local n = 0
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if subgroup == group then
            n = n + 1
        end
    end
    return n
end

-- 获取指定小队中所有成员的 unit token 列表（如 "raid1", "raid2" 等）
function F.GetUnitsInSubGroup(group)
    local units = {}
    for i = 1, GetNumGroupMembers() do
        -- name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(raidIndex)
        local name, _, subgroup = GetRaidRosterInfo(i)
        if subgroup == group then
            tinsert(units, "raid"..i)
        end
    end
    return units
end

-- 根据玩家全名查找其团队编号、小队编号和权限等级
function F.GetRaidInfoByName(fullName)
    for i = 1, GetNumGroupMembers() do
        -- rank: Returns 2 if the raid member is the leader of the raid, 1 if the raid member is promoted to assistant, and 0 otherwise.
        local name, rank, subgroup = GetRaidRosterInfo(i)
        if name == fullName then
            return i, subgroup, rank
        end
    end
end

-- 根据小队编号和队内序号查找团队成员（如 group=3, index=2 表示第3小队第2名成员）
function F.GetRaidInfoBySubgroupIndex(group, index)
    local currentIndex = 0
    for i = 1, GetNumGroupMembers() do
        local name, rank, subgroup = GetRaidRosterInfo(i)
        if subgroup == group then
            currentIndex = currentIndex + 1
            if currentIndex == index then
                return i, name, rank -- found
            end
        elseif subgroup > group and currentIndex ~= 0 then
            return -- nil if not found
        end
    end
end

-- 获取玩家的宠物 unit token：party 中为 "pet"/"partypetN"，raid 中为 "raidpetN"
function F.GetPetUnit(playerUnit)
    if Cell.vars.groupType == "party" then
        if playerUnit == "player" then
            return "pet"
        else
            return "partypet"..select(3, strfind(playerUnit, "^party(%d+)$"))
        end
    elseif Cell.vars.groupType == "raid" then
        return "raidpet"..select(3, strfind(playerUnit, "^raid(%d+)$"))
    else
        return "pet"
    end
end

-- 从宠物 unit token 反查玩家 unit token（如 "raidpet3" -> "raid3"）
function F.GetPlayerUnit(petUnit)
    if petUnit == "pet" then
        return "player"
    else
        return petUnit:gsub("pet", "")
    end
end

-- 迭代所有队伍成员（含玩家自己），返回 unit token 迭代器
-- party 中从 "player" 开始，然后 "party1".."partyN"
-- raid 中从 "raid1" 开始到 "raidN"
function F.IterateGroupMembers()
    local groupType = IsInRaid() and "raid" or "party"
    local numGroupMembers = GetNumGroupMembers()
    local i

    if groupType == "party" then
        i = 0
        numGroupMembers = numGroupMembers - 1
    else
        i = 1
    end

    return function()
        local ret
        if i == 0 then
            ret = "player"
        elseif i <= numGroupMembers and i > 0 then
            ret = groupType .. i
        end
        i = i + 1
        return ret
    end
end

-- 迭代所有队伍宠物的 unit token
function F.IterateGroupPets()
    local groupType = IsInRaid() and "raid" or "party"
    local numGroupMembers = GetNumGroupMembers()
    local i = groupType == "party" and 0 or 1

    return function()
        local ret
        if i == 0 and groupType == "party" then
            ret = "pet"
        elseif i <= numGroupMembers and i > 0 then
            ret = groupType .. "pet" .. i
        end
        i = i + 1
        return ret
    end
end

-- 判断当前队伍类型："raid" / "party" / "solo"
function F.GetGroupType()
    if IsInRaid() then
        return "raid"
    elseif IsInGroup() then
        return "party"
    else
        return "solo"
    end
end

-- 判断单位是否在当前队伍中（含玩家和宠物）
-- ignorePets=true 时排除宠物
function F.UnitInGroup(unit, ignorePets)
    if ignorePets then
        return UnitIsUnit(unit, "player") or UnitInParty(unit) or UnitInRaid(unit) or UnitInPartyIsAI(unit)
    else
        return UnitIsUnit(unit, "player") or UnitIsUnit(unit, "pet") or UnitPlayerOrPetInParty(unit) or UnitPlayerOrPetInRaid(unit) or UnitInPartyIsAI(unit)
    end
end

-- UnitTokenFromGUID 的反操作：根据目标 unit 查找其在队伍中的 unit token
-- 如 target 为队伍中某人时返回 "party2" 或 "raid5"
function F.GetTargetUnitID(target)
    if UnitIsUnit(target, "player") then
        return "player"
    elseif UnitIsUnit(target, "pet") then
        return "pet"
    end

    if not F.UnitInGroup(target) then return end

    if UnitIsPlayer(target) or UnitInPartyIsAI(target) then
        for unit in F.IterateGroupMembers() do
            if UnitIsUnit(target, unit) then
                return unit
            end
        end
    else
        for unit in F.IterateGroupPets() do
            if UnitIsUnit(target, unit) then
                return unit
            end
        end
    end
end

-- 获取目标单位的宠物 unit token（如 target 为 "raid3" -> "raidpet3"）
function F.GetTargetPetID(target)
    if UnitIsUnit(target, "player") then
        return "pet"
    end

    if not F.UnitInGroup(target) then return end

    if UnitIsPlayer(target) or UnitInPartyIsAI(target) then
        for unit in F.IterateGroupMembers() do
            if UnitIsUnit(target, unit) then
                return F.GetPetUnit(unit)
            end
        end
    end
end

-- https://wowpedia.fandom.com/wiki/UnitFlag
local OBJECT_AFFILIATION_MINE = 0x00000001
local OBJECT_AFFILIATION_PARTY = 0x00000002
local OBJECT_AFFILIATION_RAID = 0x00000004

-- 根据 unitFlags 判断是否友方（MINE / PARTY / RAID 任一标志位设置即为友方）
function F.IsFriend(unitFlags)
    if not unitFlags then return false end
    return (bit.band(unitFlags, OBJECT_AFFILIATION_MINE) ~= 0) or (bit.band(unitFlags, OBJECT_AFFILIATION_RAID) ~= 0) or (bit.band(unitFlags, OBJECT_AFFILIATION_PARTY) ~= 0)
end

-- 判断 GUID 是否属于玩家单位
-- Midnight 12.0.0+ 防护：GUID 可能为 secret，对 secret 执行 string.find 会抛出错误
--   安全策略：secret GUID 直接返回 false，视为非玩家
function F.IsPlayer(guid)
    -- Midnight 12.0.0+: guid may be secret; string.find on secret throws (Grid2 pattern)
    if F.IsSecretValue(guid) then return false end
    if guid then
        return string.find(guid, "^Player")
    end
end

-- 判断 GUID/unit 是否属于宠物单位
-- 优先通过 unit token 后缀匹配（如 "raidpet3"），否则通过 GUID 前缀 "^Pet" 匹配
-- SecretValue 防护：secret GUID 返回 false
function F.IsPet(guid, unit)
    if unit then
        return strfind(unit, "pet%d*$")
    end
    if F.IsSecretValue(guid) then return false end
    if guid then
        return string.find(guid, "^Pet")
    end
end

-- 判断 GUID 是否属于 NPC
-- SecretValue 防护：secret GUID 返回 false
function F.IsNPC(guid)
    if F.IsSecretValue(guid) then return false end
    if guid then
        return string.find(guid, "^Creature")
    end
end

-- 判断 GUID 是否属于载具
-- SecretValue 防护：secret GUID 返回 false
function F.IsVehicle(guid)
    if F.IsSecretValue(guid) then return false end
    if guid then
        return string.find(guid, "^Vehicle")
    end
end

-- 获取当前目标的 unit token / 名称 / 职业信息
function F.GetTargetUnitInfo()
    if UnitIsUnit("target", "player") then
        return "player", UnitName("player"), UnitClassBase("player")
    elseif UnitIsUnit("target", "pet") then
        return "pet", UnitName("pet")
    end
    if not F.UnitInGroup("target") then return end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if UnitIsUnit("target", "raid"..i) then
                return "raid"..i, UnitName("raid"..i), UnitClassBase("raid"..i)
            end
            if UnitIsUnit("target", "raidpet"..i) then
                return "raidpet"..i, UnitName("raidpet"..i)
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers()-1 do
            if UnitIsUnit("target", "party"..i) then
                return "party"..i, UnitName("party"..i), UnitClassBase("party"..i)
            end
            if UnitIsUnit("target", "partypet"..i) then
                return "partypet"..i, UnitName("partypet"..i)
            end
        end
    end
end

-- 判断当前玩家是否有团队管理权限（队长/助理）
-- 队伍标记权限：在 5人小队中所有人都可以标记
function F.HasPermission(isPartyMarkPermission)
    if isPartyMarkPermission and IsInGroup() and not IsInRaid() then return true end
    return UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player"))
end

-------------------------------------------------
-- LibSharedMedia 材质/字体管理
-- 通过 LibSharedMedia-3.0 库统一管理状态条材质和字体
-- 注册 Cell 内置资源到 LSM，供用户选择自定义
-------------------------------------------------
Cell.vars.texture = "Interface\\AddOns\\Cell\\Media\\statusbar.tga"
Cell.vars.emptyTexture = "Interface\\AddOns\\Cell\\Media\\empty.tga"
Cell.vars.whiteTexture = "Interface\\AddOns\\Cell\\Media\\white.tga"

local LSM = LibStub("LibSharedMedia-3.0", true)
LSM:Register("statusbar", "Cell ".._G.DEFAULT, Cell.vars.texture)
LSM:Register("font", "Visitor", [[Interface\Addons\Cell\Media\Fonts\visitor.ttf]], 255)

-- 获取当前设置的状态条材质路径，同时更新 Cell.vars.texture 供 UnitButton_OnLoad 使用
function F.GetBarTexture()
    --! update Cell.vars.texture for further use in UnitButton_OnLoad
    if LSM:IsValid("statusbar", CellDB["appearance"]["texture"]) then
        Cell.vars.texture = LSM:Fetch("statusbar", CellDB["appearance"]["texture"])
    else
        Cell.vars.texture = "Interface\\AddOns\\Cell\\Media\\statusbar.tga"
    end
    return Cell.vars.texture
end

-- 按名称获取状态条材质路径（不更新 Cell.vars.texture），回退为默认材质
function F.GetBarTextureByName(name)
    if LSM:IsValid("statusbar", name) then
        return LSM:Fetch("statusbar", name)
    end
    return "Interface\\AddOns\\Cell\\Media\\statusbar.tga"
end

-- 获取字体路径：优先级 LSM字体 > 直接 .ttf 路径 > 游戏默认字体 / Cell 内置字体
function F.GetFont(font)
    if font and LSM:IsValid("font", font) then
        return LSM:Fetch("font", font)
    elseif type(font) == "string" and strfind(strlower(font), ".ttf$") then
        return font
    else
        if CellDB["appearance"]["useGameFont"] then
            return GameFontNormal:GetFont()
        else
            return "Interface\\AddOns\\Cell\\Media\\Fonts\\Accidental_Presidency.ttf"
        end
    end
end

local defaultFontName = "Cell ".._G.DEFAULT
local defaultFont
-- 获取字体选项列表（供下拉菜单使用），返回 items（选项表）、fonts（字体映射）、默认字体名和路径
function F.GetFontItems()
    if CellDB["appearance"]["useGameFont"] then
        defaultFont = GameFontNormal:GetFont()
    else
        defaultFont = "Interface\\AddOns\\Cell\\Media\\Fonts\\Accidental_Presidency.ttf"
    end

    local items = {}
    local fonts, fontNames

    -- if LSM then
        fonts, fontNames = F.Copy(LSM:HashTable("font")), F.Copy(LSM:List("font"))
        -- insert default font
        tinsert(fontNames, 1, defaultFontName)
        fonts[defaultFontName] = defaultFont

        for _, name in pairs(fontNames) do
            tinsert(items, {
                ["text"] = name,
                ["font"] = fonts[name],
                -- ["onClick"] = function()
                --     CellDB["appearance"]["font"] = name
                --     Cell.Fire("UpdateAppearance", "font")
                -- end,
            })
        end
    -- else
    --     fontNames = {defaultFontName}
    --     fonts = {[defaultFontName] = defaultFont}

    --     tinsert(items, {
    --         ["text"] = defaultFontName,
    --         ["font"] = defaultFont,
    --         -- ["onClick"] = function()
    --         --     CellDB["appearance"]["font"] = defaultFontName
    --         --     Cell.Fire("UpdateAppearance", "font")
    --         -- end,
    --     })
    -- end
    return items, fonts, defaultFontName, defaultFont
end

-------------------------------------------------
-- 纹理坐标与旋转
-- 提供纹理裁剪（GetTexCoord）、旋转（RotateTexture）、纹理资源列表等工具
-------------------------------------------------
-- 根据宽高计算纹理 UV 裁剪坐标，使纹理在保持比例的情况下居中裁剪
function F.GetTexCoord(width, height)
    -- ULx,ULy, LLx,LLy, URx,URy, LRx,LRy
    local texCoord = {0.12, 0.12, 0.12, 0.88, 0.88, 0.12, 0.88, 0.88}
    local aspectRatio = width / height

    local xRatio = aspectRatio < 1 and aspectRatio or 1
    local yRatio = aspectRatio > 1 and 1 / aspectRatio or 1

    for i, coord in ipairs(texCoord) do
        local aspectRatio = (i % 2 == 1) and xRatio or yRatio
        texCoord[i] = (coord - 0.5) * aspectRatio + 0.5
    end

    return texCoord
end

-- function F.RotateTexture(tex, degrees)
--     local angle = math.rad(degrees)
--     local cos, sin = math.cos(angle), math.sin(angle)
--     tex:SetTexCoord((sin - cos), -(cos + sin), -cos, -sin, sin, -cos, 0, 0)
-- end

-- https://wowpedia.fandom.com/wiki/Applying_affine_transformations_using_SetTexCoord
-- 通过 SetTexCoord 实现纹理旋转（基于仿射变换公式）
local s2 = sqrt(2)
local function CalculateCorner(degrees)
    local r = math.rad(degrees)
    return 0.5 + math.cos(r) / s2, 0.5 + math.sin(r) / s2
end
-- 旋转纹理指定角度，使用四个角点的纹理坐标进行仿射变换
function F.RotateTexture(texture, degrees)
    local LRx, LRy = CalculateCorner(degrees + 45)
    local LLx, LLy = CalculateCorner(degrees + 135)
    local ULx, ULy = CalculateCorner(degrees + 225)
    local URx, URy = CalculateCorner(degrees - 45)

    texture:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
end

-- wow atlases
local wowAtlases = {
    "playerpartyblip",
    "Artifacts-PerkRing-WhiteGlow",
    "AftLevelup-WhiteIconGlow",
    "LootBanner-IconGlow",
    "AftLevelup-WhiteStarBurst",
    "ChallengeMode-WhiteSpikeyGlow",
    "UI-QuestPoiCampaign-OuterGlow",
    "vignettekill",
    "PetJournal-FavoritesIcon",
    "dungeonskull",
    "questnormal",
    "questturnin",
    "bags-icon-addslots",
    "communities-chat-icon-plus",
    "communities-chat-icon-minus",
}

-- wow textures
local wowTextures = {

}

-- shapes
local shapes = {
    "circle_blurred",
    "circle_filled",
    "circle_thin",
    "circle",
    "heart_filled",
    "heart",
    "rhombus",
    "rhombus_filled",
    "square_filled",
    "square",
    "star_filled",
    "star",
    "starburst_filled",
    "starburst",
    "triangle_filled",
    "triangle",
}

-- weakauras
local powaTextures = {
    9, 10, 12, 13, 14, 15, 21, 22, 25, 27, 29,
    37, 38, 39, 40, 41, 42, 43, 44,
    49, 51, 52, 53, 58, 78, 118, 84,
    96, 97, 98, 99, 100, 114, 115, 116, 132, 138, 143
}

-- 获取所有可用纹理路径列表：内置形状 + WoW 图集 + WeakAuras 纹理 + 自定义纹理
-- 返回 builtIns（内置纹理性数量）和完整纹理列表
function F.GetTextures()
    local builtIns = #wowAtlases + #wowTextures + #shapes

    local t = {}

    -- wow atlases
    for _, wa in pairs(wowAtlases) do
        tinsert(t, wa)
    end

    -- wow textures
    for _, wt in pairs(wowTextures) do
        tinsert(t, wt)
    end

    -- built-ins
    for _, s in pairs(shapes) do
        tinsert(t, "Interface\\AddOns\\Cell\\Media\\Shapes\\"..s..".tga")
    end

    -- add weakauras textures
    if WeakAuras then
        builtIns = builtIns + #powaTextures
        for _, powa in pairs(powaTextures) do
            tinsert(t, "Interface\\AddOns\\WeakAuras\\PowerAurasMedia\\Auras\\Aura"..powa..".tga")
        end
    end

    -- customs
    for _, path in pairs(CellDB["customTextures"]) do
        tinsert(t, path)
    end

    return builtIns, t
end

-- 获取默认职责图标路径（TANK/HEALER/DAMAGER），NONE 返回空字符串
function F.GetDefaultRoleIcon(role)
    if not role or role == "NONE" then return "" end
    return "Interface\\AddOns\\Cell\\Media\\Roles\\Default_" .. role
end

-- 获取默认职责图标转义序列（|T 格式），用于在文本中嵌入图标
function F.GetDefaultRoleIconEscapeSequence(role, size)
    if not role or role == "NONE" then return "" end
    return "|TInterface\\AddOns\\Cell\\Media\\Roles\\Default_" .. role .. ":" .. (size or 0) .. "|t"
end

-------------------------------------------------
-- 框架/鼠标焦点
-------------------------------------------------
-- 获取当前鼠标焦点对象，兼容新旧 API
function F.GetMouseFocus()
    if GetMouseFoci then
        return GetMouseFoci()[1]
    else
        return GetMouseFocus()
    end
end

-------------------------------------------------
-- 副本/区域名称
-------------------------------------------------
-- 获取当前副本或区域名称
function F.GetInstanceName()
    if IsInInstance() then
        local name = GetInstanceInfo()
        if not name then name = GetRealZoneText() end
        return name
    else
        local mapID = C_Map.GetBestMapForUnit("player")
        if type(mapID) ~= "number" or mapID < 1 then
            return ""
        end

        local info = MapUtil.GetMapParentInfo(mapID, Enum.UIMapType.Continent, true)
        if info then
            return info.name, info.mapID
        end

        return ""
    end
end

-------------------------------------------------
-- 法术信息
-- 提供法术名称/图标查询、冷却判断、最大等级查找等功能
-- 零售版使用 C_Spell API，经典版使用旧 GetSpellInfo API
-------------------------------------------------
-- https://wow.gamepedia.com/UIOBJECT_GameTooltip
-- local function EnumerateTooltipLines_helper(...)
--     for i = 1, select("#", ...) do
--        local region = select(i, ...)
--        if region and region:GetObjectType() == "FontString" then
--           local text = region:GetText() -- string or nil
--           print(region:GetName(), text)
--        end
--     end
-- end

-- https://wowpedia.fandom.com/wiki/Patch_10.0.2/API_changes
-- 获取法术提示文本（tooltip），用于显示法术说明
local lines = {}
function F.GetSpellTooltipInfo(spellId)
    wipe(lines)

    local name, icon = F.GetSpellInfo(spellId)
    if not name then return end

    local data = C_TooltipInfo.GetSpellByID(spellId)
    for i, line in ipairs(data.lines) do
        TooltipUtil.SurfaceArgs(line)
        -- line.leftText
        -- line.rightText
    end

    return name, icon, table.concat(lines, "\n")
end

-- 获取法术名称和图标ID
-- 零售版（Retail/Mists）：使用 C_Spell.GetSpellInfo + C_Spell.GetSpellTexture
-- 经典版：使用旧 GetSpellInfo API，支持 rank 后缀
if Cell.isRetail or Cell.isMists then
    local GetSpellInfo = C_Spell.GetSpellInfo
    local GetSpellTexture = C_Spell.GetSpellTexture
    function F.GetSpellInfo(spellId)
        if not spellId then return end
        local info = GetSpellInfo(spellId)
        if not info then return end

        if not info.iconID then -- when?
            info.iconID = GetSpellTexture(spellId)
        end

        return info.name, info.iconID
    end
else
    -- 经典版：支持 "spellId:rank" 格式拆分
    local GetSpellInfo = GetSpellInfo
    function F.GetSpellInfo(spellId)
        if not spellId then return end
        local rank
        spellId, rank = strsplit(":", spellId)
        local name, _, icon = GetSpellInfo(spellId)
        return name, icon, tonumber(rank)
    end
end

-- 经典版法术等级系统
-- 多语言正则匹配法术等级后缀（如 "Rank 3", "等级 3", "Rang 3" 等）
-- CellD 仅正式服，此段为保留的经典版兼容代码（暂不执行）
if Cell.isWrath or Cell.isTBC or Cell.isVanilla then
    local GetSpellInfo = GetSpellInfo
    local GetNumSpellTabs = GetNumSpellTabs
    local GetSpellTabInfo = GetSpellTabInfo
    local GetSpellBookItemName = GetSpellBookItemName

    local MATCH_PATTERN, FORMAT_PATTERN = "Rank (%d+)", "Rank %d"
    if LOCALE_deDE or LOCALE_frFR then
        MATCH_PATTERN = "Rang (%d+)"
        FORMAT_PATTERN = "Rang %d"
    elseif LOCALE_esES or LOCALE_esMX then
        MATCH_PATTERN = "Rango (%d+)"
        FORMAT_PATTERN = "Rango %d"
    -- elseif LOCALE_itIT then -- not supported in classic
    --     MATCH_PATTERN = "Grado (%d+)"
    --     FORMAT_PATTERN = "Grado %d"
    elseif LOCALE_koKR then
        MATCH_PATTERN = "(%d+) 레벨"
        FORMAT_PATTERN = "%d 레벨"
    elseif LOCALE_ptBR then
        MATCH_PATTERN = "Grau (%d+)"
        FORMAT_PATTERN = "Grau %d"
    elseif LOCALE_ruRU then
        MATCH_PATTERN = "Уровень (%d+)"
        FORMAT_PATTERN = "Уровень %d"
    elseif LOCALE_zhCN then
        MATCH_PATTERN = "等级 (%d+)"
        FORMAT_PATTERN = "等级 %d"
    elseif LOCALE_zhTW then
        MATCH_PATTERN = "等級 (%d+)"
        FORMAT_PATTERN = "等級 %d"
    end

    FORMAT_PATTERN = "(" .. FORMAT_PATTERN .. ")"

    function F.GetRankSuffix(rank)
        return FORMAT_PATTERN:format(rank)
    end

    function F.GetMaxSpellRank(spellId)
        local spellName = select(1, GetSpellInfo(spellId))
        if not spellName then return end

        local maxRank = 0
        local bookType = BOOKTYPE_SPELL

        local totalSpells = 0
        for tab = 1, GetNumSpellTabs() do
            local name, texture, offset, numSpells = GetSpellTabInfo(tab)
            totalSpells = totalSpells + numSpells
        end

        -- local spellSubText
        for i = 1, totalSpells do
            local name, subText = GetSpellBookItemName(i, bookType)
            if name == spellName and subText then
                local rank = tonumber(subText:match(MATCH_PATTERN))
                -- spellSubText = subText
                if rank and rank > maxRank then
                    maxRank = rank
                end
            end
        end

        -- if spellSubText then
        --     print("----------------------------------------------")
        --     print(spellSubText, MATCH_PATTERN, tonumber(spellSubText:match(MATCH_PATTERN)))
        --     print("Max Rank of " .. spellName .. ": " .. maxRank)
        --     print("----------------------------------------------")
        -- else
        --     print("Rank info not found: " .. spellName)
        -- end

        return maxRank
    end
end

-- 获取法术冷却信息（startTime, duration），兼容新旧 API
if C_Spell.GetSpellCooldown then
    local GetSpellCooldown = C_Spell.GetSpellCooldown
    F.GetSpellCooldown = function(spellId)
        local info = GetSpellCooldown(spellId)
        if info then
            return info.startTime, info.duration
        end
    end
else
    F.GetSpellCooldown = function(spellId)
        local start, duration = GetSpellCooldown(spellId)
        return start, duration
    end
end

-- 判断法术是否可用（无冷却或仅剩 GCD）
-- 返回 true（可用）或 false, cdLeft（不可用，剩余冷却时间）
-- 61304 = 全职业通用 GCD 法术ID
function F.IsSpellReady(spellId)
    local start, duration = F.GetSpellCooldown(spellId)
    if start == 0 or duration == 0 then
        return true
    else
        local _, gcd = F.GetSpellCooldown(61304) --! check gcd
        if duration == gcd then -- spell ready
            return true
        else
            local cdLeft = start + duration - GetTime()
            return false, cdLeft
        end
    end
end

-------------------------------------------------
-- 宏管理
-- 通过 UPDATE_MACROS 事件维护宏索引列表，供点击施法等模块使用
-------------------------------------------------
local mc = CreateFrame("Frame")
mc:RegisterEvent("UPDATE_MACROS")

local macroIndices = {}
-- UPDATE_MACROS 事件处理：重新收集全局宏（1-120）和角色宏（121-138）的索引
mc:SetScript("OnEvent", function()
    wipe(macroIndices)

    local global, perChar = GetNumMacros()
    for i = 1, global do
        tinsert(macroIndices, i)
    end
    for i = 1, perChar do
        tinsert(macroIndices, 120 + i)
    end
end)

-- 返回当前宏索引列表（全局宏 + 角色宏）
function F.GetMacroIndices()
    return macroIndices
end

-------------------------------------------------
-- 光环/减益查询
-- 提供按法术ID / 减益类型查找光环的功能
-- 零售版使用 AuraUtil.ForEachAura 迭代器
-- 经典版使用 UnitDebuff 索引遍历
-- SecretValue 防护：Midnight 12.0.0+ 战斗限制下光环字段可能为 opaque 类型，需要前置检查
-------------------------------------------------
-- name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod = UnitAura
-- NOTE: FrameXML/AuraUtil.lua
-- AuraUtil.FindAura(predicate, unit, filter, predicateArg1, predicateArg2, predicateArg3)
-- predicate(predicateArg1, predicateArg2, predicateArg3, ...)
-- 内部谓词函数：比较光环的法术ID是否匹配
local function predicate(...)
    local idToFind = ...
    local id = select(13, ...)
    return idToFind == id
end

-- 按法术ID查找单位身上的单个光环（BUFF 或 DEBUFF）
function F.FindAuraById(unit, type, spellId)
    if type == "BUFF" then
        return AuraUtil.FindAura(predicate, unit, "HELPFUL", spellId)
    else
        return AuraUtil.FindAura(predicate, unit, "HARMFUL", spellId)
    end
end

-- 零售版：通过 AuraUtil.ForEachAura 迭代查找减益
-- Midnight 12.0.0+ SecretValue 防护：限制环境下光环字段全部为 secret，直接返回空表
if Cell.isRetail then
    -- 按法术ID列表查找单位身上的减益集合
    function F.FindDebuffByIds(unit, spellIds)
        -- Midnight 12.0.0+: aura fields are secret during restricted contexts
        if Cell.isMidnight and F.IsAuraRestricted() then return {} end
        local debuffs = {}
        AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
            if spellIds[spellId] then
                debuffs[spellId] = I.CheckDebuffType(debuffType, spellId)
            end
        end)
        return debuffs
    end

    -- 按减益类型（Magic/Disease/Poison/Curse 等）查找减益集合
    -- types="all" 时返回所有减益
    function F.FindAuraByDebuffTypes(unit, types)
        -- Midnight 12.0.0+: aura fields are secret during restricted contexts
        if Cell.isMidnight and F.IsAuraRestricted() then return {} end
        local debuffs = {}
        AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
            if types == "all" or types[debuffType] then
                debuffs[spellId] = I.CheckDebuffType(debuffType, spellId)
            end
        end)
        return debuffs
    end
else
    -- 经典版：通过 UnitDebuff 索引遍历（最多40个减益）
    function F.FindDebuffByIds(unit, spellIds)
        local debuffs = {}
        for i = 1, 40 do
            local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitDebuff(unit, i)
            if not name then
                break
            end

            if spellIds[spellId] then
                debuffs[spellId] = I.CheckDebuffType(debuffType, spellId)
            end
        end
        return debuffs
    end

    function F.FindAuraByDebuffTypes(unit, types)
        local debuffs = {}
        for i = 1, 40 do
            local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitDebuff(unit, i)
            if not name then
                break
            end

            if types == "all" or types[debuffType] then
                debuffs[spellId] = I.CheckDebuffType(s, spellId)
            end
        end
        return debuffs
    end
end

-------------------------------------------------
-- OmniCD 联动：更新插件位置
-------------------------------------------------
-- 当框架改变时通知 OmniCD 刷新其定位（延迟0.5秒避免竞态）
function F.UpdateOmniCDPosition(frame)
    if OmniCD and OmniCD[1].db and OmniCD[1].db.position.uf == frame then
        C_Timer.After(0.5, function()
            OmniCD[1].Party:UpdatePosition()
        end)
    end
end

-------------------------------------------------
-- LibGetFrame 框架优先级
-- 与 LibGetFrame 库配合，按用户设置的优先级（Main/Spotlight/QuickAssist）
-- 控制点击施法对多框架的响应顺序
-------------------------------------------------
local frame_priorities = {}
local inited_priorities = {}
local modified_priorities = {}
local spotlightPriorityEnabled
local quickAssistPriorityEnabled

-- 根据用户设置更新框架优先级正则列表，如 "^CellNormalUnitFrame$", "^CellSpotlightUnitFrame$" 等
function F.UpdateFramePriority()
    wipe(frame_priorities)
    wipe(modified_priorities)
    spotlightPriorityEnabled = nil
    quickAssistPriorityEnabled = nil

    for i, t  in pairs(CellDB["general"]["framePriority"]) do
        if t[2] then
            if t[1] == "Main" then
                tinsert(frame_priorities, i, "^CellNormalUnitFrame$")
            elseif t[1] == "Spotlight" then
                tinsert(frame_priorities, i, "^CellSpotlightUnitFrame$")
                spotlightPriorityEnabled = true
            else
                tinsert(frame_priorities, i, "^CellQuickAssistUnitFrame$")
                quickAssistPriorityEnabled = true
            end
        else
            tinsert(frame_priorities, i, "^CellPlaceholder$")
        end
    end

    F.Debug(frame_priorities)
end

-- LibGetFrame 回调：根据 unit 查找对应的框架对象及命名，按优先级填充 frames 表
function Cell.GetUnitFramesForLGF(unit, frames, priorities)
    frames = frames or {}

    local normal, spotlights, quickAssist = F.GetUnitButtonByUnit(unit, spotlightPriorityEnabled, quickAssistPriorityEnabled)

    if normal then
        frames[normal.widgets.highLevelFrame] = "CellNormalUnitFrame"
    end

    if spotlights then
        -- for _, spotlight in pairs(spotlights) do
        --     if not strfind(spotlight.unit, "target$") and spotlight.widgets and spotlight.widgets.highLevelFrame then
        --         frames[spotlight.widgets.highLevelFrame] = "CellSpotlightUnitFrame"
        --         break
        --     end
        -- end
        --! just use the first (can be "XXtarget", whatever)
        if spotlights[1] then
            frames[spotlights[1].widgets.highLevelFrame] = "CellSpotlightUnitFrame"
        end
    end

    if quickAssist then
        frames[quickAssist] = "CellQuickAssistUnitFrame"
    end

    if not inited_priorities[priorities] then
        inited_priorities[priorities] = true
        for i = 1, 3 do
            tinsert(priorities, i, "^CellPlaceholder$")
        end
    end

    if not modified_priorities[priorities] then
        modified_priorities[priorities] = true
        for i, p in ipairs(frame_priorities) do
            priorities[i] = p
        end
    end

    return frames
end

-------------------------------------------------
-- 距离检测系统
-- 核心功能：判断单位是否在施法/交互范围内（F.IsInRange）
-- 策略链：UnitInRange（仅队伍）-> 友方法术距离 -> 敌对法术/道具距离 -> 交互距离
-- Midnight 12.0.0+ SecretValue 防护：UnitInRange 在战斗中可能返回 secret boolean
--   此时 checked 为 secret，无法判断是否检测成功，需要跳过此路径回退到法术距离检测
-- 每个职业在 friendSpells/harmSpells/deadSpells 中配置了用于距离检测的代表性法术
-------------------------------------------------
local UnitIsVisible = UnitIsVisible
local UnitInRange = UnitInRange
local UnitCanAssist = UnitCanAssist
local UnitCanAttack = UnitCanAttack
local UnitCanCooperate = UnitCanCooperate
local IsSpellInRange = C_Spell.IsSpellInRange
local IsItemInRange = C_Item.IsItemInRange
local CheckInteractDistance = CheckInteractDistance
local UnitIsDead = UnitIsDead
local IsSpellKnownOrOverridesKnown = IsSpellKnownOrOverridesKnown
-- local GetSpellTabInfo = GetSpellTabInfo
-- local GetNumSpellTabs = GetNumSpellTabs
-- local GetSpellBookItemName = GetSpellBookItemName
-- local BOOKTYPE_SPELL = BOOKTYPE_SPELL
local IsSpellBookKnown = C_SpellBook.IsSpellKnown

-- 判断法术是否已知（包括覆盖已知和法术书已知两种检测）
local function IsSpellKnown(spellId)
    return IsSpellKnownOrOverridesKnown(spellId) or IsSpellBookKnown(spellId)
end

-- 判断单位是否与玩家在同一相位（零售服用 UnitPhaseReason，经典服用 UnitInPhase）
local UnitInSamePhase
if Cell.isRetail then
    UnitInSamePhase = function(unit)
        return not UnitPhaseReason(unit)
    end
else
    UnitInSamePhase = UnitInPhase
end

-- 获取当前玩家职业文件名（如 "PRIEST", "MAGE" 等），用于距离检测法术查表
local ok, pc = pcall(UnitClassBase, "player")
local playerClass = ok and pc or "WARRIOR"

-- 各职业用于距离检测的友方法术ID
local friendSpells = {
    -- ["DEATHKNIGHT"] = 47541,
    -- ["DEMONHUNTER"] = ,
    ["DRUID"] = (Cell.isWrath or Cell.isTBC or Cell.isVanilla) and 5185 or 8936, -- 治疗之触 / 愈合
    -- FIXME: [361469 活化烈焰] 会被英雄天赋 [431443 时序烈焰] 替代，但它而且有问题
    -- IsSpellInRange 始终返回 nil
    ["EVOKER"] = 355913, -- 翡翠之花
    -- ["HUNTER"] = 136,
    ["MAGE"] = 1459, -- 奥术智慧 / 奥术光辉
    ["MONK"] = 116670, -- 活血术
    ["PALADIN"] = Cell.isRetail and 19750 or 635, -- 圣光闪现 / 圣光术
    ["PRIEST"] = (Cell.isWrath or Cell.isTBC or Cell.isVanilla) and 2050 or 2061, -- 次级治疗术 / 快速治疗
    -- ["ROGUE"] = Cell.isWrath and 57934,
    ["SHAMAN"] = Cell.isRetail and 8004 or 331, -- 治疗之涌 / 治疗波
    ["WARLOCK"] = 5697, -- 无尽呼吸
    -- ["WARRIOR"] = 3411, -- 援护
}

-- 各职业用于检测死亡单位距离的法术（复活类法术的射程）
local deadSpells = {
    ["EVOKER"] = 361227, -- resurrection range, need separately for evoker
}

-- 各职业用于检测宠物距离的法术（仅猎人：治疗宠物）
local petSpells = {
    ["HUNTER"] = 136,
}

-- 各职业用于检测敌对单位距离的法术ID
local harmSpells = {
    ["DEATHKNIGHT"] = 47541, -- 凋零缠绕
    ["DEMONHUNTER"] = 185123, -- 投掷利刃
    ["DRUID"] = 5176, -- 愤怒
    -- FIXME: [361469 活化烈焰] 会被英雄天赋 [431443 时序烈焰] 替代，但它而且有问题
    -- IsSpellInRange 始终返回 nil
    ["EVOKER"] = 362969, -- 碧蓝打击
    ["HUNTER"] = 75, -- 自动射击
    ["MAGE"] = Cell.isRetail and 116 or 133, -- 寒冰箭 / 火球术
    ["MONK"] = 117952, -- 碎玉闪电
    ["PALADIN"] = 20271, -- 审判
    ["PRIEST"] = Cell.isRetail and 589 or 585, -- 暗言术：痛 / 惩击
    ["ROGUE"] = 1752, -- 影袭
    ["SHAMAN"] = Cell.isRetail and 188196 or 403, -- 闪电箭
    ["WARLOCK"] = 234153, -- 吸取生命
    ["WARRIOR"] = 355, -- 嘲讽
}

-- local friendItems = {
--     ["DEATHKNIGHT"] = 34471,
--     ["DEMONHUNTER"] = 34471,
--     ["DRUID"] = 34471,
--     ["EVOKER"] = 1180, -- 30y
--     ["HUNTER"] = 34471,
--     ["MAGE"] = 34471,
--     ["MONK"] = 34471,
--     ["PALADIN"] = 34471,
--     ["PRIEST"] = 34471,
--     ["ROGUE"] = 34471,
--     ["SHAMAN"] = 34471,
--     ["WARLOCK"] = 34471,
--     ["WARRIOR"] = 34471,
-- }

-- 各职业用于距离检测的道具ID（回退方案，当法术距离 API 不可用时使用）
local harmItems = {
    ["DEATHKNIGHT"] = 28767, -- 40y
    ["DEMONHUNTER"] = 28767, -- 40y
    ["DRUID"] = 28767, -- 40y
    ["EVOKER"] = 24268, -- 25y
    ["HUNTER"] = 28767, -- 40y
    ["MAGE"] = 28767, -- 40y
    ["MONK"] = 28767, -- 40y
    ["PALADIN"] = 835, -- 30y
    ["PRIEST"] = 28767, -- 40y
    ["ROGUE"] = 28767, -- 40y
    ["SHAMAN"] = 28767, -- 40y
    ["WARLOCK"] = 28767, -- 40y
    ["WARRIOR"] = 28767, -- 40y
}

-- local FindSpellIndex
-- if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
--     FindSpellIndex = function(spellName)
--         if not spellName or spellName == "" then return end
--         return C_SpellBook.FindSpellBookSlotForSpell(spellName)
--     end
-- else
--     local function GetNumSpells()
--         local _, _, offset, numSpells = GetSpellTabInfo(GetNumSpellTabs())
--         return offset + numSpells
--     end

--     FindSpellIndex = function(spellName)
--         if not spellName or spellName == "" then return end
--         for i = 1, GetNumSpells() do
--             local spell = GetSpellBookItemName(i, BOOKTYPE_SPELL)
--             if spell == spellName then
--                 return i
--             end
--         end
--     end
-- end

-- 法术距离检测封装：兼容 C_Spell.IsSpellInRange 和旧 IsSpellInRange API
local UnitInSpellRange
if C_Spell and C_Spell.IsSpellInRange then
    UnitInSpellRange = function(spellName, unit)
        return IsSpellInRange(spellName, unit)
    end
else
    UnitInSpellRange = function(spellName, unit)
        return IsSpellInRange(spellName, unit) == 1
    end
end

-- 距离检测初始化框架：监听 SPELLS_CHANGED 事件动态加载法术名称
local rc = CreateFrame("Frame")
rc:RegisterEvent("SPELLS_CHANGED")

-- 运行时距离检测法术名称（由 SPELLS_CHANGED 事件异步加载）
local spell_friend, spell_pet, spell_harm, spell_dead
-- 各职业自定义覆盖表（允许用户通过配置修改距离检测法术）
CELL_RANGE_CHECK_FRIENDLY = {}
CELL_RANGE_CHECK_HOSTILE = {}
CELL_RANGE_CHECK_DEAD = {}
CELL_RANGE_CHECK_PET = {}

-- 异步加载法术名称：通过 Spell:CreateFromSpellID 确保法术数据已加载后再获取名称
local function LoadSpellName(spellID, callback)
    if spellID and IsSpellKnown(spellID) then
        local spell = Spell:CreateFromSpellID(spellID)
        spell:ContinueOnSpellLoad(function()
            callback(spell:GetSpellName())
            -- print("Loaded spell for range check:", spellID, spell:GetSpellName())
        end)
    else
        callback(nil)
    end
end

-- SPELLS_CHANGED 事件处理器：根据玩家职业和自定义覆盖表加载距离检测法术名称
local function SPELLS_CHANGED()
    local friend_id = CELL_RANGE_CHECK_FRIENDLY[playerClass] or friendSpells[playerClass]
    local harm_id = CELL_RANGE_CHECK_HOSTILE[playerClass] or harmSpells[playerClass]
    local dead_id = CELL_RANGE_CHECK_DEAD[playerClass] or deadSpells[playerClass]
    local pet_id = CELL_RANGE_CHECK_PET[playerClass] or petSpells[playerClass]

    LoadSpellName(friend_id, function(name) spell_friend = name end)
    LoadSpellName(harm_id, function(name) spell_harm = name end)
    LoadSpellName(dead_id, function(name) spell_dead = name end)
    LoadSpellName(pet_id, function(name) spell_pet = name end)

    -- F.Debug(
    --     "[RANGE CHECK]",
    --     "\nfriend:", spell_friend or "nil",
    --     "\npet:", spell_pet or "nil",
    --     "\nharm:", spell_harm or "nil",
    --     "\ndead:", spell_dead or "nil"
    -- )
end

-- 延迟处理 SPELLS_CHANGED（1秒去抖动），防止短期内重复触发导致性能问题
local timer
local function DELAYED_SPELLS_CHANGED()
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(1, SPELLS_CHANGED)
end

rc:SetScript("OnEvent", DELAYED_SPELLS_CHANGED)

-- 核心距离检测函数
-- 策略链（按优先级尝试）：
--   1. player 自身 -> 总是 true
--   2. 队伍成员 + 非 check 模式 -> UnitInRange（快速检测，仅队伍有效）
--      SecretValue 防护：checked 为 secret 时跳过此步
--   3. 友方单位 -> 先检查连接/相位，再查友方法术距离、宠物法术距离
--   4. 敌对单位 -> 先查敌方法术距离，再回道具距离
--   5. 非战斗 -> CheckInteractDistance(28码)
--   6. 战斗中且以上均失败 -> 保守返回 true（避免误判）
function F.IsInRange(unit, check)
    if not UnitIsVisible(unit) then
        return false
    end

    if UnitIsUnit("player", unit) then
        return true

    elseif not check and F.UnitInGroup(unit) then
        -- NOTE: UnitInRange only works with group players/pets
        --! but not available for PLAYER PET when SOLO
        local inRange, checked = UnitInRange(unit)
        -- Midnight 12.0.0+: UnitInRange returns secret booleans during restricted contexts
        if Cell.isMidnight and issecretvalue and issecretvalue(checked) then
            return F.IsInRange(unit, true)
        end
        if not checked then
            return F.IsInRange(unit, true)
        end
        return inRange

    else
        if UnitCanAssist("player", unit) then -- or UnitCanCooperate("player", unit)
            if not (UnitIsConnected(unit) and UnitInSamePhase(unit)) then
                return false
            end

            if UnitIsDead(unit) then
                if spell_dead then
                    return UnitInSpellRange(spell_dead, unit)
                end
            elseif spell_friend then
                return UnitInSpellRange(spell_friend, unit)
            end

            local inRange, checked = UnitInRange(unit)
            -- Midnight 12.0.0+: UnitInRange returns secret booleans during restricted contexts
            if Cell.isMidnight and issecretvalue and issecretvalue(checked) then
                -- Skip, fall through to pet/interact checks below
            elseif checked then
                return inRange
            end

            if UnitIsUnit(unit, "pet") and spell_pet then
                -- no spell_friend, use spell_pet
                return UnitInSpellRange(spell_pet, unit)
            end

        elseif UnitCanAttack("player", unit) then
            if UnitIsDead(unit) then
                return CheckInteractDistance(unit, 4) -- 28 yards
            elseif spell_harm then
                return UnitInSpellRange(spell_harm, unit)
            end
            return IsItemInRange(harmItems[playerClass], unit)
        end

        if not InCombatLockdown() then
            return CheckInteractDistance(unit, 4) -- 28 yards
        end

        return true
    end
end

-------------------------------------------------
-- RangeCheck 调试窗口 /cellrc
-- 实时显示目标的距离检测结果（按各策略路径分解）
-------------------------------------------------
local debug = CreateFrame("Frame", "CellRangeCheckDebug", CellParent, "BackdropTemplate")
debug:SetBackdrop({bgFile = Cell.vars.whiteTexture})
debug:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
debug:SetBackdropBorderColor(0, 0, 0, 1)
debug:SetPoint("LEFT", 300, 0)
debug:Hide()

debug.text = debug:CreateFontString(nil, "OVERLAY")
debug.text:SetFont(GameFontNormal:GetFont(), 13, "")
debug.text:SetShadowColor(0, 0, 0)
debug.text:SetShadowOffset(1, -1)
debug.text:SetJustifyH("LEFT")
debug.text:SetSpacing(5)
debug.text:SetPoint("LEFT", 5, 0)

-- 调试信息第1部分：单位信息和基础距离判断
local function GetResult1()
    local inRange, checked = UnitInRange("target")

    return "UnitID: " .. (F.GetTargetUnitID("target") or "target") ..
        "\n|cffffff00F.IsInRange:|r " .. (F.IsInRange("target") and "true" or "false") ..
        "\nUnitInRange: " .. (checked and "checked" or "unchecked") .. " " .. (inRange and "true" or "false") ..
        "\nUnitIsVisible: " .. (UnitIsVisible("target") and "true" or "false") ..
        "\n\nUnitCanAssist: " .. (UnitCanAssist("player", "target") and "true" or "false") ..
        "\nUnitCanCooperate: " .. (UnitCanCooperate("player", "target") and "true" or "false") ..
        "\nUnitCanAttack: " .. (UnitCanAttack("player", "target") and "true" or "false") ..
        "\n\nUnitIsConnected: " .. (UnitIsConnected("target") and "true" or "false") ..
        "\nUnitInSamePhase: " .. (UnitInSamePhase("target") and "true" or "false") ..
        "\nUnitIsDead: " .. (UnitIsDead("target") and "true" or "false") ..
        "\n\nspell_friend: " .. (spell_friend and (spell_friend .. " " .. (UnitInSpellRange(spell_friend, "target") and "true" or "false")) or "none") ..
        "\nspell_dead: " .. (spell_dead and (spell_dead .. " " .. (UnitInSpellRange(spell_dead, "target") and "true" or "false")) or "none") ..
        "\nspell_pet: " .. (spell_pet and (spell_pet .. " " .. (UnitInSpellRange(spell_pet, "target") and "true" or "false")) or "none") ..
        "\nspell_harm: " .. (spell_harm and (spell_harm .. " " .. (UnitInSpellRange(spell_harm, "target") and "true" or "false")) or "none")
end

-- 调试信息第2部分：道具距离和交互距离
local function GetResult2()
    if UnitCanAttack("player", "target") then
        return "IsItemInRange: " .. (IsItemInRange(harmItems[playerClass], "target") and "true" or "false") ..
            "\nCheckInteractDistance(28y): " .. (CheckInteractDistance("target", 4) and "true" or "false")
    else
        return "IsItemInRange: " .. (InCombatLockdown() and "notAvailable" or (IsItemInRange(harmItems[playerClass], "target") and "true" or "false")) ..
            "\nCheckInteractDistance(28y): " .. (InCombatLockdown() and "notAvailable" or (CheckInteractDistance("target", 4) and "true" or "false"))
    end
end

-- OnUpdate：每0.25秒刷新调试信息显示
debug:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed >= 0.25 then
        self.elapsed = 0
        local result = GetResult1() .. "\n\n" .. GetResult2()
        result = string.gsub(result, "none", "|cffabababnone|r")
        result = string.gsub(result, "true", "|cff00ff00true|r")
        result = string.gsub(result, "false", "|cffff0000false|r")
        result = string.gsub(result, " checked", " |cff00ff00checked|r")
        result = string.gsub(result, "unchecked", "|cffff0000unchecked|r")

        debug.text:SetText("|cffff0066Cell Range Check (Target)|r\n\n" .. result)

        debug:SetSize(debug.text:GetStringWidth() + 10, debug.text:GetStringHeight() + 20)
    end
end)

-- 目标切换事件：有目标显示，无目标隐藏
debug:SetScript("OnEvent", function()
    if not UnitExists("target") then
        debug:Hide()
        return
    end

    debug:Show()
end)

-- /cellrc 命令：切换距离检测调试窗口的显示/隐藏
SLASH_CELLRC1 = "/cellrc"
function SlashCmdList.CELLRC()
    if debug:IsEventRegistered("PLAYER_TARGET_CHANGED") then
        debug:UnregisterEvent("PLAYER_TARGET_CHANGED")
        debug:Hide()
    else
        debug:RegisterEvent("PLAYER_TARGET_CHANGED")
        if UnitExists("target") then
            debug:Show()
        end
    end
end

---------------------------------------------------------------------
-- 专精数据（预留，Mists 版本待实现）
---------------------------------------------------------------------
if Cell.isMists then

end

-------------------------------------------------
-- Secret Value 安全工具 (Patch 12.0.0+ / Midnight)
-- Midnight 12.0.0+ 引入 opaque secret 类型保护敏感战斗数据
-- 战斗中生命值/能量/光环信息/冷却等被包装为不可直接读取的 secret 值
-- 本模块提供安全判断和防护包装函数，所有对敏感数据的运算必须经过这些函数
-------------------------------------------------
-- 判断值是否为 secret（opaque）类型
-- issecretvalue() 是 12.0.0+ WoW 原生 API
-- 旧版本或不可用时返回 false（所有值视为普通值）
function F.IsSecretValue(val)
    if issecretvalue then
        return issecretvalue(val)
    end
    return false
end

-- GetRestrictedActionStatus() 返回非 secret 的 boolean
-- 用于判断当前是否处于光环/冷却限制状态
-- Enum.RestrictedActionType.SecretAuras = 0    （光环数据被限制）
-- Enum.RestrictedActionType.SecretCooldowns = 1 （冷却数据被限制）
-- 判断当前战斗环境是否限制光环数据访问（所有光环字段被包装为 secret）
function F.IsAuraRestricted()
    if GetRestrictedActionStatus and Enum and Enum.RestrictedActionType then
        local isRestricted = GetRestrictedActionStatus(Enum.RestrictedActionType.SecretAuras)
        return isRestricted == true
    end
    return false
end

-- 判断当前战斗环境是否限制冷却数据访问
function F.IsCooldownRestricted()
    if GetRestrictedActionStatus and Enum and Enum.RestrictedActionType then
        local isRestricted = GetRestrictedActionStatus(Enum.RestrictedActionType.SecretCooldowns)
        return isRestricted == true
    end
    return false
end

-- Per-aura non-secret check: returns true if the aura's fields are real (non-secret) values.
-- On Midnight 12.0.0+, Blizzard flags certain spells as non-secret; their auraInfo fields
-- (spellId, expirationTime, duration, etc.) return real values instead of secrets.
-- If spellId is readable (non-secret), ALL fields for this aura are non-secret.
-- 按光环判断是否非 secret：Midnight 12.0+ 中暴雪将某些法术标记为非 secret
-- 若 spellId 可读（非 secret），则该光环的所有字段（名称/图标/持续时间等）均为真实值
function F.IsAuraNonSecret(auraInfo)
    if not Cell.isMidnight then return true end
    if not issecretvalue then return true end
    return not issecretvalue(auraInfo.spellId)
end

-- Proactive check: queries whether a spell ID will produce secret aura values.
-- Uses C_Secrets.ShouldSpellAuraBeSecret() if available (Midnight 12.0.0+).
-- Returns true if the spell's aura data will be non-secret (readable).
-- 主动查询：判断某个法术ID的光环数据是否会被包装为 secret
-- 使用 C_Secrets.ShouldSpellAuraBeSecret() API（Midnight 12.0.0+）
-- API 不可用时保守假设为 secret（返回 false）
function F.IsSpellAuraNonSecret(spellId)
    if not Cell.isMidnight then return true end
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        return not C_Secrets.ShouldSpellAuraBeSecret(spellId)
    end
    return false -- assume secret if API unavailable
end

-- Generic check: returns true if a given value is NOT a secret value.
-- Works for any return value from WoW APIs that may produce secrets on Midnight 12.0.0+.
-- 通用 secret 检测：判断任意 WoW API 返回值是否为非 secret 的真实值
function F.IsValueNonSecret(val)
    if not Cell.isMidnight then return true end
    if not issecretvalue then return true end
    return not issecretvalue(val)
end