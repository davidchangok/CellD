# CellD — World of Warcraft Raid Frame Addon

[![version](https://img.shields.io/github/v/release/davidchangok/CellD)](https://github.com/davidchangok/CellD/releases)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/davidchangok/CellD/blob/main/LICENSE)

**CellD** is an excellent WoW raid frame addon forked from [enderneko's Cell](https://github.com/enderneko/Cell). As the original author became too busy to maintain it, **David W Zhang** continues this version, focused exclusively on the latest retail version. This version is intended for David W Zhang's personal use (though anyone is welcome to use it).

[中文 README (README.md)](README.md)

---

## Design Philosophy

CellD aims to provide a **better user experience than ever before**.

Inspired by: **CompactRaid**, **Grid2**, **Aptechka**, **VuhDo**

---

## Supported Version

- **WoW Retail 12.0 (Midnight)**
- Classic / expansion variants are no longer supported

## Locale Support

> Due to the maintainer's limited capacity, CellD currently supports only **Simplified Chinese (zhCN)** and **English (enUS)**.
> All other locales (deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhTW) have been removed.
> You may copy language files from the original Cell project if you need other languages.

---

## Key Features

- **Layout System** — auto-switch layouts by group type / role / spec, covering solo, party, raid, battleground, arena
- **Customizable Appearance** — textures, colors, opacity, fonts, borders
- **Real-time Health & Power Display** — Midnight 12.0 Secret Value safe via HealPredictionCalculator + StatusBar native C engine
- **Absorbs / Shield Bar** — real-time shield visualization with reverse-fill overshield detection
- **Health Thresholds Indicator** — multi-level health threshold markers
- **Built-in Click-Casting** — keyboard shortcuts and multi-button mouse, no third-party addons needed
- **Smart Resurrection** — auto-replace with resurrection spells on dead units
- **Rich Indicators** — dozens of built-in indicators (icons, bars, rectangles, text, glow, etc.) with unlimited custom options
- **Raid Debuffs** — priority-sorted debuff lists with multiple glow effects (Pixel, Shine, Proc). Active boss auto-filtering via ENCOUNTER_START/END events
- **Dispellable Debuff Highlighting** — Grid2 IndicatorSquare-inspired full-cell background coloring via Blizzard's `C_UnitAuras.GetAuraDispelTypeColor` C-engine API (pcall-protected) combined with `auraInfo.canActivePlayerDispel` (12.0+ field, NeverSecret). The unit button's own `SetBackdropColor` is used for cell-level tinting, immediately drawing the healer's attention
- **Defensive / External / All Cooldowns** — Mirror Image and Mass Barrier detected via UNIT_AURA
- **Raid Tools** — ready check, role check, pull timer, buff tracker, death report, world/target markers, battle res timer
- **Spotlight Frame** — 15 extra unit buttons configurable as target, focus, tanks, or specific units
- **Quick Assist** — one-click assist (Evoker Augmentation adapted)
- **BlackBox Self-Test** — built-in Secret Value safety verification (`/celld blackbox`) covering all sensitive data code paths
- **Polished Options UI** — clean and intuitive configuration panel with live preview
- **Chinese Code Comments** — all non-third-party source files annotated with detailed Chinese comments covering function roles, data flows, and Midnight Secret Value guard points
- **Compatibility** — [BigDebuffs](https://www.curseforge.com/wow/addons/bigdebuffs)、[OmniCD](https://www.curseforge.com/wow/addons/omnicd)

---

## Midnight 12.0 Secret Value Safety Architecture

Blizzard introduced the Secret Value (opaque type) mechanism in patch 12.0, wrapping sensitive combat data (health, power, absorbs, aura duration, etc.) in non-comparable types. CellD adopts patterns from both **Grid2** and **VuhDo** to harden the entire codebase:

### Core Strategies

| Pattern | Source | Description |
|------|:--:|------|
| `F.IsSecretValue()` → Blizzard `issecretvalue()` | Grid2 | Correctly identifies all secret types |
| `C_UnitAuras.GetUnitAuras` (single API call) | Grid2 | Replaces per-slot iteration |
| `GetAuraDispelTypeColor(auraInstanceID)` | Grid2 / VuhDo | C-engine secret-safe color resolution |
| `auraInfo.canActivePlayerDispel` guard | 12.0 field | NeverSecret → direct dispel check |
| Button `SetBackdropColor` for cell tinting | Grid2 Square | No layer conflicts, full-cell coverage |
| StatusBar `SetMinMaxValues/SetValue` | Grid2 | Native C-engine secret ratio handling |
| Secret String compatibility | Grid2 / VuhDo | `FontString:SetText()` accepts secrets natively |

### Safety Coverage

| Module | Protection |
|------|---------|
| Health Display | `HealPredictionCalculator` → `healthPercent` cache fallback (non-0) → `class_color` mode unaffected |
| Shield/Absorb Bar | `ShieldBar` StatusBar transition → C-engine handles ratio via `SetMinMaxValues(0,max)+SetValue(current)` |
| Power Bar | `powerFilters` nil guard → `ShouldShowPowerBar/Text` fallback `true` |
| Debuff Classification | `hasSecretTime` flag → classify/show never skipped → `DurationObject` fallback for cooldown rendering |
| Dispel Highlighting | `dispelName` secret fallback `"Magic"` → `pcall(GetAuraDispelTypeColor)` → `_dispelsHighlightColor` prevents overwrite |
| Buff Tracking | `Mirror Image/Mass Barrier` migrated to `UNIT_AURA` detection |
| Boss Debuffs | `ENCOUNTER_START/END` auto-switches current boss list |
| Name Display | `UpdateTextWidth/FitWidth` skip string ops on secret, direct `SetText` → `SetSize` fallback `parent:GetWidth` |
| GUID Operations | `F.IsPlayer/IsPet/IsNPC/IsVehicle` prefixed with `IsSecretValue` guard |
| Sorting | `SortRaidDebuffs` cache miss nil guard |

---

## Known Unimplemented Features

- **Code Snippets** — removed from CellD
- **Quick Assist** — Evoker Augmentation module not fully reviewed for Secret Value safety
- **Buff Tracker** — based on original Cell code, pending Secret Value review
- **Spell Request / Dispel Request** — network communication layer not audited
- **BigDebuffs integration** — not yet verified on Midnight 12.0
- **WeakAuras** — no longer supported in 12.0, removed from compatibility list
- **Some utility modules** — `Utilities/` directory retains original Cell implementations

> If you find a feature broken on Midnight 12.0, please report it on [GitHub Issues](https://github.com/davidchangok/CellD/issues).

---

## Installation

1. Download the latest version from [Releases](https://github.com/davidchangok/CellD/releases)
2. Extract to `World of Warcraft\_retail_\Interface\AddOns\`
3. Ensure the folder is named `CellD`
4. Restart the game or `/reload`

---

## Slash Commands

| Command | Function |
| ---- | ---- |
| `/celld` or `/cell` | Show all available commands |
| `/celld options` | Open settings window |
| `/celld healers` | Create "Healers" indicator |
| `/celld rescale` | Apply recommended scale |
| `/celld blackbox` | Secret Value self-test |
| `/celld reset position` | Reset CellD position |
| `/celld reset layouts` | Reset all layouts and indicators |
| `/celld reset clickcastings` | Reset all click-castings |
| `/celld reset raiddebuffs` | Reset all raid debuffs |
| `/celld reset quickassist` | Reset current spec quick assist |
| `/celld reset all` | Reset all settings (use with caution) |
| `/celld report <number>` | Set raid death report count (0–40) |

---

## Help Improve Raid Debuff Data

Use [Instance Spell Collector](https://www.curseforge.com/wow/addons/instance-spell-collector) to collect raid debuff data, then submit a PR or Issue on GitHub.

---

## Links

- **GitHub Repository**: https://github.com/davidchangok/CellD
- **Issue Tracker**: https://github.com/davidchangok/CellD/issues
- **Original Cell**: https://github.com/enderneko/Cell

---

## Technical References

The following addons were referenced during Midnight 12.0 Secret Value compatibility development:

| Addon | Referenced For |
|------|---------|
| [Grid2](https://www.curseforge.com/wow/addons/grid2) | `issecretvalue`/`canaccessvalue` globals, `GetAuraDispelTypeColor` API, Square indicator cell coloring |
| [VuhDo](https://www.curseforge.com/wow/addons/vuhdo) | `hasSecretName` flag pattern, `GetAuraDispelTypeColor(unit, auraID, curve)` usage |

---

## Acknowledgements

CellD is based on [enderneko's Cell](https://github.com/enderneko/Cell). Thanks to the original author and all code contributors for their outstanding work.
