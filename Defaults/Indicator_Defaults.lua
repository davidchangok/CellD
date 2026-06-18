local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs
---@class CellUnitButtonFuncs
local I = Cell.iFuncs

-------------------------------------------------
-- custom indicator
-------------------------------------------------
function I.GetDefaultCustomIndicatorTable(name, indicatorName, type, auraType)
    local t
    if type == "icon" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["size"] = {13, 13},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = true,
            ["showDuration"] = false,
            ["showAnimation"] = true,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "text" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["font"] = {"Cell " .. _G.DEFAULT, 12, "Outline", false},
            ["colors"] = {{0, 1, 0, 1}, {false, 0.5, {1, 1, 0, 1}}, {false, 3, {1, 0, 0, 1}}},
            ["auraType"] = auraType,
            ["auras"] = {},
            ["duration"] = {
                true, -- show duration
                false, -- round up duration
                0, -- decimal
            },
            ["stack"] = {
                true, -- show stack
                false, -- circled stack nums
            },
        }
    elseif type == "bar" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"BOTTOMRIGHT", "button", "TOPRIGHT", 0, -1},
            ["frameLevel"] = 5,
            ["size"] = {18, 4},
            ["colors"] = {{0, 1, 0, 1}, {false, 0.5, {1, 1, 0, 1}}, {false, 3, {1, 0, 0, 1}}, {0, 0, 0, 1}, {0.07, 0.07, 0.07, 0.9}},
            ["orientation"] = "horizontal",
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "LEFT", 1, 0, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "RIGHT", -1, 0, {1, 1, 1}},
            },
            ["showStack"] = false,
            ["showDuration"] = false,
            ["maxValue"] = {false, 10, true},
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "bars" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 0},
            ["frameLevel"] = 5,
            ["size"] = {18, 4},
            ["num"] = 3,
            ["numPerLine"] = 3,
            ["orientation"] = "top-to-bottom",
            ["spacing"] = {-1, -1},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = false,
            ["showDuration"] = false,
            ["maxValue"] = {false, 10, true},
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "rect" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 2},
            ["frameLevel"] = 5,
            ["size"] = {11, 4},
            ["colors"] = {{0, 1, 0, 1}, {false, 0.5, {1, 1, 0, 1}}, {false, 3, {1, 0, 0, 1}}, {0, 0, 0, 1}},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "LEFT", 1, 0, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "RIGHT", -1, 0, {1, 1, 1}},
            },
            ["showStack"] = false,
            ["showDuration"] = false,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "icons" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["size"] = {13, 13},
            ["num"] = 5,
            ["numPerLine"] = 5,
            ["orientation"] = "right-to-left",
            ["spacing"] = {0, 0},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = true,
            ["showDuration"] = false,
            ["showAnimation"] = true,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "color" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["anchor"] = "healthbar-current",
            ["frameLevel"] = 1,
            ["colors"] = {"gradient-vertical", {1, 0, 0.4, 1}, {0, 0, 0, 1}, {0, 1, 0, 1}, {0.5, {1, 1, 0, 1}}, {3, {1, 0, 0, 1}}},
            ["auraType"] = auraType,
            ["auras"] = {},
        }
    elseif type == "texture" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOP", "button", "TOP", 0, 0},
            ["size"] = {16, 16},
            ["frameLevel"] = 10,
            ["texture"] = {"Interface\\AddOns\\Cell\\Media\\Shapes\\circle_blurred.tga", 0, {1, 1, 1, 1}},
            ["auraType"] = auraType,
            ["auras"] = {},
            ["fadeOut"] = true,
        }
    elseif type == "glow" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["frameLevel"] = 1,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"Pixel", {0.95, 0.95, 0.32, 1}, 9, 0.25, 8, 2},
            ["fadeOut"] = true,
        }
    elseif type == "overlay" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["smooth"] = false,
            ["frameLevel"] = 1,
            ["colors"] = {{0, 0.61, 1, 0.55}, {false, 0.5, {1, 1, 0, 0.5}}, {false, 3, {1, 0, 0, 0.5}}},
            ["orientation"] = "horizontal",
            ["auraType"] = auraType,
            ["auras"] = {},
        }
    elseif type == "block" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["size"] = {10, 10},
            ["colors"] = {"duration", {0, 1, 0, 1}, {false, 0.5, {1, 1, 0, 1}}, {false, 3, {1, 0, 0, 1}}, {0, 0, 0, 1}},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = false,
            ["showDuration"] = false,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "blocks" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["position"] = {"TOPRIGHT", "button", "TOPRIGHT", 0, 3},
            ["frameLevel"] = 5,
            ["size"] = {10, 10},
            ["num"] = 5,
            ["numPerLine"] = 5,
            ["orientation"] = "right-to-left",
            ["spacing"] = {-1, -1},
            ["font"] = {
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "TOPRIGHT", 2, 1, {1, 1, 1}},
                {"Cell " .. _G.DEFAULT, 11, "Outline", false, "BOTTOMRIGHT", 2, -1, {1, 1, 1}},
            },
            ["showStack"] = false,
            ["showDuration"] = false,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["glowOptions"] = {"None", {0.95, 0.95, 0.32, 1}}
        }
    elseif type == "border" then
        t = {
            ["name"] = name,
            ["indicatorName"] = indicatorName,
            ["type"] = type,
            ["enabled"] = true,
            ["thickness"] = 2,
            ["frameLevel"] = 10,
            ["auraType"] = auraType,
            ["auras"] = {},
            ["fadeOut"] = true,
        }
    end

    if auraType == "buff" then
        t["castBy"] = "me"
        if Cell.isRetail then
            t["trackByName"] = false
        else
            t["trackByName"] = true
        end
    else
        t["castBy"] = "anyone"
    end

    return t
end

-------------------------------------------------
-- dispels: custom debuff type color
-------------------------------------------------
-- Blizzard C API (Midnight 12.0.5): C_UnitAuras.GetAuraDispelTypeColor(auraInstanceID [, curve])
-- internally resolves secrets. pcall guards against stale auraInstanceID.
-- Returns the per-aura dispel color from Blizzard's C engine.
-- Without a curve, the API returns the built-in color for that aura's dispel type.
-- Grid2 StatusAuras.lua:79 pattern: GetAuraDispelTypeColor(unit, auraInstanceID, colorCurve)
-- Requires unit parameter in Midnight 12.0. pcall guards against stale auraInstanceID.

-- DTtoBT: dispel type string → Blizzard dispel bitfield enum for dsCurve AddPoint x-values
local DTtoBT = {["Magic"]=1, ["Curse"]=2, ["Disease"]=3, ["Poison"]=4, ["Bleed"]=11}

function I.UpdateDispelColorCurve()
    if not C_CurveUtil then return end
    if not I._dsCurve then I._dsCurve = C_CurveUtil.CreateColorCurve(); I._dsCurve:SetType(Enum.LuaCurveType.Step) end
    I._dsCurve:ClearPoints()
    I._dsCurve:AddPoint(0, CreateColor(0, 0.3, 0.1, 1))
    for tn, bv in pairs(DTtoBT) do local c = CellDB["debuffTypeColor"] and CellDB["debuffTypeColor"][tn]
        if c then I._dsCurve:AddPoint(bv, CreateColor(c.r, c.g, c.b, 1)) end
    end
end

-- Match an (r,g,b) color against user-configured debuffTypeColor to find nearest type
local _dispelTypes = {"Magic", "Curse", "Disease", "Poison", "Bleed"}
function I.FindDebuffTypeByColor(r, g, b)
    if not r or type(r) ~= "number" or F.IsSecretValue(r) then return "Magic" end
    local best, bestDist = "Magic", 999
    for _, dt in ipairs(_dispelTypes) do
        local tr, tg, tb = I.GetDebuffTypeColor(dt)
        local dist = (r-tr)*(r-tr) + (g-tg)*(g-tg) + (b-tb)*(b-tb)
        if dist < bestDist then bestDist = dist; best = dt end
    end
    return best
end

function I.GetAuraDispelColor(unit, auraInstanceID)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDispelTypeColor or not unit or not auraInstanceID then
        return nil
    end
    local ok, c = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, auraInstanceID, I._dsCurve)
    if ok and c then
        if type(c.GetRGB) == "function" then
            local cr, cg, cb = c:GetRGB()
            if cr and type(cr) == "number" and not F.IsSecretValue(cr) then return cr, cg, cb end
        end
        local cr, cg, cb = c.r, c.g, c.b
        if cr and type(cr) == "number" and not F.IsSecretValue(cr) then return cr, cg, cb end
    end
    return nil
end

function I.GetDebuffTypeColor(debuffType, fallbackColor)
    -- Midnight 12.0.0+: debuffType may be secret; cannot use as table key
    if F.IsSecretValue and F.IsSecretValue(debuffType) then return 0, 0, 0 end
    if debuffType and CellDB["debuffTypeColor"][debuffType] then
        return CellDB["debuffTypeColor"][debuffType]["r"], CellDB["debuffTypeColor"][debuffType]["g"],
            CellDB["debuffTypeColor"][debuffType]["b"]
    elseif fallbackColor then
        return fallbackColor[1], fallbackColor[2], fallbackColor[3]
    else
        return 0, 0, 0
    end
end

function I.SetDebuffTypeColor(debuffType, r, g, b)
    if debuffType and CellDB["debuffTypeColor"][debuffType] then
        CellDB["debuffTypeColor"][debuffType]["r"] = r
        CellDB["debuffTypeColor"][debuffType]["g"] = g
        CellDB["debuffTypeColor"][debuffType]["b"] = b
    end
    I.UpdateDispelColorCurve()
end

-- Midnight 12.0.0 removed the DebuffTypeColor global; provide a local fallback
-- with the standard Blizzard debuff type colors
local CellDebuffTypeColorFallback = {
    ["none"]    = {r = 0.80, g = 0.00, b = 0.00},
    ["Magic"]   = {r = 0.20, g = 0.60, b = 1.00},
    ["Curse"]   = {r = 0.60, g = 0.00, b = 1.00},
    ["Disease"] = {r = 0.60, g = 0.40, b = 0.00},
    ["Poison"]  = {r = 0.00, g = 0.60, b = 0.00},
    [""]        = {r = 0.80, g = 0.00, b = 0.00},
}

function I.ResetDebuffTypeColor()
    local source = DebuffTypeColor or CellDebuffTypeColorFallback
    CellDB["debuffTypeColor"] = F.Copy(source)
    CellDB["debuffTypeColor"]["Bleed"] = {r = 1, g = 0.2, b = 0.6}
    I.UpdateDispelColorCurve()
end