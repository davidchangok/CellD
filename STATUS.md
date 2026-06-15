# CellD 开发状态

**日期**: 2026-06-15 | **版本**: 1.0.0 | **作者**: David W Zhang

---

## 一、已完成的核心工作

### 插件基础
- [x] 从 Cell r277-beta 分叉为 CellD，适配 WoW 12.0 (Midnight) 正式服
- [x] 删除所有怀旧服变体文件（TBC/Wrath/Cata 等 30+ 文件）
- [x] 删除多余语言文件，仅保留 zhCN/enUS
- [x] `ADDON_LOADED` 参数从 `"Cell"` 改为动态 `addonName`
- [x] 全局替换 `Cell` → `CellD` 的字体名、Frame 名
- [x] 删除代码片段 (CodeSnippets) 功能
- [x] 删除 COMBAT_LOG_EVENT_UNFILTERED 依赖，Mirror Image/Mass Barrier 改为 UNIT_AURA 检测

### 选项面板
- [x] 关于页面改造：原作者/改写作者面板、贡献者面板、链接精简
- [x] 删除更新记录按钮及 Changelogs.lua
- [x] README.md/README_EN.md 更新，包含 Secret Value 安全架构文档

### Midnight 12.0 Secret Value 全面防护（63 处替换）
- [x] `issecretvalue` → `F.IsSecretValue` 全局替换（13 个文件）
- [x] `duration=0` 导致 debuff 跳过：新增 `hasSecretTime` flag
- [x] `canActivePlayerDispel` secret boolean guard
- [x] `ForEachAura` 迁移到 `C_UnitAuras.GetUnitAuras`（Grid2 模式）
- [x] ShieldBar Frame → StatusBar 转型，C 引擎处理 secret 比例
- [x] 血量 `healthPercent` 缓存回退（非 0）、`class_color` 模式不受影响
- [x] `F.UnitFullName`/`F.GetNickname`/`LibTranslit` 新增 secret string guard
- [x] `F.IsPlayer/IsPet/IsNPC/IsVehicle` GUID secret guard
- [x] `F.UpdateTextWidth/F.FitWidth` secret string → 直接 `SetText`
- [x] 6 个分类函数 guard 从 OR 改为 AND（`GetDebuffOrder/Glow/IsDebuffUseElapsedTime` 等）
- [x] `powerFilters` nil guard、`ShouldShowPowerBar/Text` 回退

### 驱散染色（核心功能，经多次重构）
- [x] 借鉴 Grid2 IndicatorSquare：独立 Backdrop Frame（frameLevel +141）整格上色
- [x] 颜色来源：`I.GetDebuffTypeColor(dispelType)` 读取 `CellDB["debuffTypeColor"]` 用户自定义色
- [x] `_topDispelAuraID` 在黑名单判断之前赋值，确保 glow 一直可用
- [x] `_debuffs_dispel` 存储 `{highlight=true, auraInstanceID=ID}` table 而非 bool
- [x] Alpha 最终定在 0.35，半透明不遮血条
- [x] highlight 纹理移至 `highLevelFrame`（整格），预览和实际渲染统一
- [x] 放弃 `GetAuraDispelTypeColor` C API（Midnight 12.0 持续返回 nil）
- [x] 放弃 `ColorCurve`（Lua 普通表无法作为 `AddPoint` 参数）

### 其他修复
- [x] `ENCOUNTER_START/END` 事件 per-boss raid debuff 筛选
- [x] `GetDebuffList` 增加 `encounterID` 参数和 nil guard
- [x] `ShieldBar_SetPoint` 删除对 `SetValue` 的覆盖
- [x] `CheckThreshold` secret healthPercent guard
- [x] QuickAssist `HandleBuff`/`OnTick`/`UpdateAllUnits` secret guard
- [x] BattleRes secret cooldown guard
- [x] BuffTracker `UNIT_AURA` secret unit guard
- [x] QuickCast `UpdateName` secret string guard
- [x] CellDropdownList 硬编码 `"CellDropdownList"` 修复

---

## 二、当前架构（驱散上色）

```
HandleDebuff
  → 检测可驱散 debuff（dispelName/indicatorBooleans/canActivePlayerDispel 三重过滤）
  → _topDispelAuraID = auraInstanceID（黑名单检查前赋值）
  → _debuffs_dispel[typeKey] = {highlight=true, auraInstanceID=ID}

UnitButton_UpdateDebuffs
  → self.indicators.dispels:SetDispels(self._debuffs_dispel)

Dispels_SetDispels
  → 遍历 dispelOrder["Magic","Curse","Disease","Poison","Bleed"]
  → found=true → r,g,b = GetDebuffTypeColor(dispelType)
  → glow Frame: SetBackdropColor(r,g,b,0.35) ← 整格半透明上色
  → highlight 纹理: SetTexture + SetGradient ← 渐变等样式（highLevelFrame 上）

图层 Z 轴：按钮背景(0) < 血条(+1) < midLevelFrame(+120) < highLevelFrame(+140) < glow(+141) < 图标/名字(+220)
```

---

## 三、已知限制

| 问题 | 原因 | 严重度 |
|------|------|:--:|
| ShieldBar secret 时 25% 固定宽度 | `GetDamageAbsorbs` secret 值无法算比例 | 低 |
| PvP 中 healthPercent=0 导致血条全红 | secret healthPercent 无法读取 | 中 |
| Overshield 检测 secret 环境失效 | 无法比较吸收值与血量 | 低 |
| `GetAuraDispelTypeColor` API 不可用 | Midnight 12.0 持续返回 nil | 已切换查表 |
| 冷却动画在 secret 环境丢失 | `expirationTime-duration` 算术不可行 | 低 |

---

## 四、下一步计划

1. **Quick Assist / Buff Tracker** — 尚未完成 Midnight Secret Value 深度审查
2. **Spell Request / Dispel Request** — 网络通信层未做适配
3. **驱散透明度可配置** — 将 alpha 值加入选项面板
4. **`GetAuraDispelTypeColor` 回归监控** — 暴雪修复后重新启用 C API 路径
5. **性能优化** — `OnTick` 高频更新中 GUID 比较可进一步优化
