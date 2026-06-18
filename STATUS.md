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
| 冷却动画在 secret 环境丢失 | `expirationTime-duration` 算术不可行 | BorderIcon 类已通过 DurationObject 修复（crowdControls/raidDebuffs/debuffs）；BarIcon 类（防御/外部/全部冷却）因使用 StatusBar 非 Cooldown Frame 暂不支持 |

---

## 四、Quick Assist / Buff Tracker Secret Value 审查 (2026-06-15)

| 文件 | 修复位置 | 修复内容 | 严重度 |
|------|----------|----------|:--:|
| QuickAssist.lua | `OnEvent` | unit 参数 secret guard（对齐 BuffTracker 模式） | 中 |
| QuickAssist.lua | `UpdateAllUnits` | `UnitGUID`→`LGI:GetCachedInfo` 调用前 GUID guard | 高 |
| QuickAssist_Config.lua | `CreatePlayerList` | `GetUnitName` 返回值 secret guard | 中 |
| BuffTracker.lua | `GetUnaffectedString` | `UnitName` 返回值 secret guard | 中 |
| BuffTracker.lua | `SetTooltips` | `UnitName` 返回值 secret guard | 中 |

> QuickAssist_ImportExport.lua —— 无游戏 API 调用，无需修改。
> QuickAssist.lua 已有的 guard（`HandleBuff` IsAuraNonSecret、`UpdateCasts` spellId、`OnTick` GUID、`UpdateAllUnits` name）保持不变。

---

## 四、dsCurve 驱散颜色系统 (2026-06-15)

借鉴 Decursive 的 `dsCurve` 方案，用 `C_CurveUtil.CreateColorCurve()` + `CreateColor()` 构建 Step ColorCurve，
传入 `C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)`，使 Blizzard C 引擎在 secret 环境下
也能返回匹配用户配置颜色的 per-aura 驱散颜色。

### 改动文件 (5 个，~85 行)

| 文件 | 改动 | 
|------|------|
| `Defaults/Indicator_Defaults.lua` | 新增 `DTtoBT` 映射 + `I.UpdateDispelColorCurve()` + 修改 `I.GetAuraDispelColor` 传入 dsCurve + `I.SetDebuffTypeColor`/`I.ResetDebuffTypeColor` 自动重建 curve |
| `Core.lua` | 初始化时调用 `I.UpdateDispelColorCurve()` |
| `RaidFrames/UnitButton.lua` | `HandleDebuff` 中 `_debuffs_dispel` entry 附加 `_dispelColor`（来自 `GetAuraDispelTypeColor`） |
| `Indicators/Built-in.lua` | `Dispels_SetDispels` secret 渲染分支优先读 `info._dispelColor`，fallback `"Magic"` |
| `Modules/Indicators/Indicators.lua` | 预览面板同样优先读 per-aura 颜色 |

### DTtoBT 映射
```
Magic=1  Curse=2  Disease=3  Poison=4  Bleed=11
```
无 dispel(NORMAL)=0 → 暗绿 `(0, 0.3, 0.1, 1)`

> 用户颜色选择器不变，`CellDB["debuffTypeColor"]` 仍是颜色来源；dsCurve 仅作为 secret 环境下的颜色传递通道。

---

## 五、BigDebuffs 深度分析 (2026-06-15)

分析 BigDebuffs 上色与渲染架构，三项可用技术评估：

### 1. DurationObject 冷却绕行 ✅ 已实施
BigDebuffs 在 Midnight 中使用 `C_UnitAuras.GetAuraDuration` + `SetCooldownFromDurationObject` 绕过 secret duration/expirationTime 限制。
CellD 将此能力从 raidDebuffs/debuffs 扩展至 crowdControls：

| 文件 | 改动 |
|------|------|
| `RaidFrames/UnitButton.lua` | `crowdControls:SetCooldown` 传入 `DebuffStatus.GetDurationObject(unit, auraInstanceID)` |

> `defensiveCooldowns`/`externalCooldowns`/`allCooldowns` 使用 `BarIcon`（StatusBar），非 `Cooldown` Frame，无法使用 `SetCooldownFromDurationObject`。
> `tankActiveMitigation` 同理，使用 StatusBar。

### 2. Filter String 预过滤 ❌ 不适用
BigDebuffs 用 `"HARMFUL\|CROWD_CONTROL"` 等 filter 字符串在 API 层预过滤，但它使用的是 `GetAuraDataByIndex`（按索引单取）。
CellD 使用 `GetUnitAuras`（批量获取所有有害/有益），且需要全部有害光环来驱动多个 indicator（debuffs/raidDebuffs/bigDebuffs/dispels/crowdControls），不能按驱散/控场类型预过滤。**当前架构已是最优。**

### 3. Parent 法术继承 ❌ 收益低
BigDebuffs 的法术字典支持 `parent = spellId` 继承。CellD 在外部队（Mass Barrier）中已有一例手动嵌套结构，
但通用继承需要重写 `ConvertSpellTable` 系列函数，改动面大，且 CellD 的法术表是小规模手工维护（不同于 BigDebuffs 的巨量自动生成库）。

### BigDebuffs 其他有价值参考
- `AuraUtil.SetAuraBorderAtlas(border, dispelName, true)` — Midnight 原生 debuff 边框着色 API
- `Cooldown:SetDrawEdge(false)` / `SetDrawBling(false)` — 冷却圈外观优化
- Zone-aware PvE 尺寸覆盖（实例内统一放大 debuff 图标）

---

## 六、下一步计划

1. ~~**Quick Assist / Buff Tracker**~~ ✅ 已完成 Midnight Secret Value 深度审查
2. **Spell Request / Dispel Request** — 网络通信层未做适配
3. **驱散透明度可配置** — 将 alpha 值加入选项面板
4. ~~**`GetAuraDispelTypeColor` 回归监控**~~ ✅ 已通过 dsCurve 方案重新启用 C API 路径
5. **性能优化** — `OnTick` 高频更新中 GUID 比较可进一步优化
