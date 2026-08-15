# CellD 开发状态

**日期**: 2026-08-15 | **版本**: 1.2.0（已发布，GitHub Release） | **作者**: David W Zhang

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

---

## 七、12.1 (Curse of Ula'tek) 适配记录 (2026-08)

### 背景：12.1 再次收紧插件光环读取
暴雪蓝贴《Addons and Auras in Curse of Ula'tek》：
- 战斗中（受限环境）友方单位光环对插件**完全不可读**（不再是 secret 值包装，而是查询直接失败）
- 论坛确认：Friendly Cooldown Tracking Disabled with 12.1；Grid2 #1437 "Buffs disappear when entering combat" 同样中招
- 官方替代方案：新增"过滤光环集 / custom aura tracker" API（插件需注册要追踪的光环）

### 用户实测结论（奶骑美德道标 200025）
| 测试 | 结果 |
|------|------|
| `ShouldSpellAuraBeSecret(200025)` | 脱战 false / **战斗中 true** |
| `GetUnitAuraBySpellID("party1", 200025)` 战斗中 | **nil**（精确查询也被屏蔽） |
| `GetHiddenGroupBuffs()` | 无参调用**报错**（参数未知） |
| `SetHiddenGroupBuffs({200025})` | 调用成功（`SET: true`），但查询仍 nil（未证实是名单机制无效还是 party1 未被点名） |
| `UNIT_SPELLCAST_SUCCEEDED` 自己施放 spellId | **非 secret**（方案基石，可用） |
| 12.1 新增 `C_UnitAuras` API（10 个） | `AddAuraSound` `AddBlockedAura` `CancelAuraByInstanceID` `ClearBlockedAuras` `GetGroupBuffVisualAlerts` `GetHiddenGroupBuffs` `RemoveAuraSound` `ResetAuraDataProvider` `SetGroupBuffVisualAlerts` `SetHiddenGroupBuffs` `SwitchAuraDataProvider` |

### 修复：SecretAuraTracker（v1.0.6 应急，commit 5c969ab）
新文件 `Utilities/SecretAuraTracker.lua`（LoadUtilities.xml 注册）：
- **原理**：施放事件确认 + 2 秒窗口内 `GetUnitAuraInstanceIDs` diff 匹配新 secret 光环（最多 3 目标）
- **显示**：目标框架/自己框架（兜底）右上角 18×18 图标 + Cooldown 扫光；**隐藏数字**（数字过大挡图标）
- **时长**：美德道标 9 秒（用户实测 12.1 数值；`tracked` 表可配）
- **图标**：12.1 战斗中 `C_Spell.GetSpellTexture` 返回 nil/secret → 改为脱战缓存 fileID（`RefreshIconCache`：模块加载 + PLAYER_ENTERING_WORLD + PLAYER_REGEN_ENABLED），失败时问号占位
- **清理**：到期 / 脱战（PLAYER_REGEN_ENABLED）自动清理，交还正常指示器

### 已知限制（用户已知情）
- **目标匹配失败**：战斗中队友框架未显示（`GetUnitAuraInstanceIDs` 在受限环境行为未确认，可能被屏蔽）；仅自己框架兜底显示。待研究：`GetAuraDataByIndex` 遍历（BigDebuffs 模式）是否可用作备选
- 战斗中无法读取真实剩余时间，9 秒为固定近似
- `GetHiddenGroupBuffs` / `SwitchAuraDataProvider` 语义未明（网络受限无法查蓝贴全文），若确认是"可见名单"机制可升级为精确追踪
- toc 已更新 `Interface: 120100`

### 最终方案（v1.0.8+ 施放追踪，commit 38bf685）

**追踪列表**（每次施放重建，跨职业自动适配）：
1. **官方 secret 名单**（warcraft.wiki.gg Patch 12.1.0 "Aura Classifications" 的 never-secret 移除清单，全职业 50+ 法术：奶骑 53563/156322/156910/1244893/200025/431381、奶德 774/8936/33763/48438/155777/439530、戒律 17/194384/1253593、神牧 139/41635/77489、奶僧、奶萨、奶龙全系）→ 用 **IsSpellKnown 过滤**（只追踪当前角色已学会的，天赋/职业切换自动适配）
2. Healers 指示器列表 + externals（布局读取）
3. 硬编码兜底（200025=9 秒实测值）

**持续时间**（天赋差异自动适配，无需手工维护）：
- **脱战扫描学习**（PLAYER_REGEN_ENABLED）：遍历队伍成员光环，缓存 tracked 法术的真实 duration
- 脱战施放时从目标光环直接读取
- 战斗中无 duration 缓存时显示图标但无扫光（避免错误时长误导）

**目标识别**（12.1 全通道封死的可行路径）：
- ❌ UnitTarget / UNIT_SPELLCAST_TARGETED：12.1 已移除
- ❌ UnitName / UnitIsUnit：secret 值
- ✅ **OnEnter/OnLeave hook 维护当前悬停单位**（`Cell.vars.secretAuraHoveredUnit`）+ GetMouseFocus 兜底 → 悬停/点击施法场景精确显示目标框架；键盘施法（鼠标不悬停）无法识别目标（12.1 硬限制）

**受限环境判定**：
- ❌ GetRestrictedActionStatus（12.1 失效，恒 false）
- ✅ `UnitAffectingCombat("player")` + `ShouldSpellAuraBeSecret` 补充

**12.1 API 研究结论存档**：
- 法术书：`GetNumSpellBookItems` 已移除，`C_Spell.GetSpellDuration` 不存在，`SpellInfo` 无 duration 字段，`FindSpellBookSlotForSpell` 只对当前职业法术有效
- AuraContainer 公共数据源 = 受限 API（战斗中不显示 secret 光环），已 revert
- `UnitName` PvP 中不再 secret（其他环境仍 secret）

### 待办
1. ~~队友目标匹配增强~~ ✅ v1.0.8 悬停/点击施法方案（键盘施法受限）
2. ~~`SwitchAuraDataProvider` / `GetHiddenGroupBuffs` 语义~~ ✅ 冷却管理器 UI 配置，非光环通道
3. ~~AuraContainer 官方通道~~ ✅ 已验证战斗中不显示 secret 光环，已 revert
4. ~~战斗显示与脱战一致~~ ✅ v1.2.0（复用 `I.CreateAura_Icons` 渲染，槽管理多增益并存）
5. 社区反馈（[暴雪论坛 Friendly Cooldown Tracking Disabled with 12.1](https://us.forums.blizzard.com/en/wow/t/friendly-cooldown-tracking-disabled-with-121/2335400/3)）
6. 全职业实测（用户玩所有治疗职业：换职业验证 IsSpellKnown 过滤 + 时长学习）
7. 发布 v1.2.0 ✅（2026-08-15，GitHub Release + tag v1.2.0）

### 12.1 新 API 语义研究结论（蓝贴全文 + FrameXML 12.1.0 源码确认，2026-08-15）

| API / 机制 | 语义 | 对 CellD 的意义 |
|------------|------|----------------|
| `GetHiddenGroupBuffs` / `SetHiddenGroupBuffs` / `Get/SetGroupBuffVisualAlerts` | **CooldownManagerLayout（12.1 冷却管理器 UI）** 的内部配置函数（`CooldownManagerLayout_*`），供玩家设置界面配置冷却管理器显示哪些团队 buff/提醒 | ❌ 不是光环读取通道，排除 |
| **AuraContainer / AuraButton**（新原生对象类型） | 官方"过滤集显示"通道：插件创建容器 + `AddAuraGroup(filterString, {candidateFilters={includeSpellIDs=...}, maxFrameCount, sortMethod, layout, initializeFrame})`，游戏引擎内部完成光环跟踪/过滤/渲染（`SetIcon`/`SetDurationText` 由游戏自动更新） | ⚠️ **战斗中不显示 secret 光环**！容器公共数据源 = `C_UnitAuras.GetUnitAuraInstanceIDs`/`GetAuraDataByAuraInstanceID`（`Blizzard_AuraContainerSources.lua`），与普通插件 API 同样受限 → 容器只是 non-secret 光环的安全自定义显示方案，**不是绕过 secret 的通道** |
| 12.1 移出 "never secret" 名单 | 蓝贴明确："we have removed the following healer buffs and HoTs from the 'never secret' list" | **美德道标/HoT 战斗中 secret 的根因**（暴雪有意为之） |
| `UNIT_AURA` 事件 | 战斗中负载 fully secret，AuraData 结构永远 fully secret | CellD 增量路径依赖的 addedAuras 在战斗中不可用 |
| `GetUnitAuras` / `GetUnitAuraInstanceIDs` | 战斗中返回 secret vector / 抛 "Auras cannot be accessed when secret"（用户实测） | 全部光环枚举通道失效 |
| `GetUnitAuraBySpellID`（按 ID 查询） | 战斗中返回 nil（用户实测全 party 遍历） | 精确查询失效 |
| 12.1 新增 10 个 C_UnitAuras 函数 | AddAuraSound/CancelAuraByInstanceID/Get·SetHiddenGroupBuffs/Get·SetGroupBuffVisualAlerts/RemoveAuraSound/AddBlockedAura/ClearBlockedAuras/Reset·SwitchAuraDataProvider | 均非光环读取通道 |

**最终结论**：12.1 战斗中显示被 secret 化的友方 buff（美德道标/HoT）在暴雪设计上**不可能**——官方 AuraContainer 也不行。**施放事件追踪（v1.0.8 的 UnitTarget 方案）是唯一合法可行方案**（第一方施放信息）。v1.1.0 AuraContainer 集成已 revert（commit c3976d2）。

### 小队遍历修正
`IterateGroupUnits` 用 `GetNumGroupMembers()` 动态计算（5 人小队 = 自己 + party1-4），不再硬编码 4。

---

## 八、v1.2.0 发布（2026-08-15）

**版本 1.2.0 已发布**（commit 1a0faaa + tag v1.2.0 + GitHub Release）。12.1 受限环境适配进入稳定阶段。

### 从 v1.0.5 → v1.2.0 的完整演进

| 阶段 | 提交 | 内容 |
|------|------|------|
| v1.0.5 基线 | 4c58687 | Comm 前缀隔离，正式发布 |
| UNIT_AURA secret 修复 | 4183364 / 93a34cb | `isFullUpdate` secret boolean 判定 + `ForEachAura` IsAuraRestricted 前置跳过 |
| 12.1 Interface | ed0e33e | Interface 120100，SecretAuraTracker 初版（v1.0.6 应急） |
| 图标/时长修 | c159cea / 5c969ab | 脱战缓存 fileID、9 秒实测值 |
| v1.0.8 通用化 | 1ac7076 | 所有自己施放的增益，UnitTarget 快照识别，脱战自学习时长 |
| AuraContainer 实验 | cc36155 → c3976d2 | v1.1.0 集成后 revert（战斗中不显示 secret 光环，非绕过通道） |
| 追踪列表重建 | 7b1442a | 每次施放重建，修复布局初始化时序导致法术永久缺失 |
| 目标识别路径 | 3536cb7 → d2cdde4 | UnitTarget 移除 → GetMouseFocus → OnEnter/OnLeave 悬停 + UnitAffectingCombat |
| 追踪名单 | e732a28 / 38bf685 | 官方 secret 名单 + IsSpellKnown 过滤（职业/天赋切换自动适配） |
| **v1.2.0 定稿** | 72a456f | 战斗显示与脱战完全一致（复用 `I.CreateAura_Icons`，槽管理多增益并存与到期清理） |
| 审阅修复 | 75851f1 | BuildTrackedList 保留时长缓存、战斗层数固定不显示、SetFont nil 保护、死代码清理 |
| 文档 | 92fc83e / 39a20bb | CLAUDE.md 记忆入口、STATUS.md 12.1 最终方案与 API 研究结论 |

### 最终架构（v1.2.0）

```text
施放事件 (UNIT_SPELLCAST_SUCCEEDED)
  → 追踪列表（官方 secret 名单 + IsSpellKnown + Healers 布局 + externals，每次施放重建）
  → 目标识别（Cell.vars.secretAuraHoveredUnit OnEnter/OnLeave + GetMouseFocus）
  → 渲染：I.CreateAura_Icons（与脱战 Healers 指示器同配置：大小/位置/字体/布局）
  → 槽管理：多增益并存、到期清理
时长：脱战扫描自学习（天赋差异自动适配）+ 硬编码兜底；战斗无缓存时不显示扫光
层数：战斗 stack 不可知，固定不显示
```

### 已知边界（暴雪设计，无法绕过）

- 键盘施法（鼠标不悬停）无法识别目标
- 无法感知驱散/提前结束；队友施放的增益不可见
- 战斗中无法读取真实剩余时间与层数

### 待办（当前）

1. 社区反馈跟进（[暴雪论坛 Friendly Cooldown Tracking Disabled with 12.1](https://us.forums.blizzard.com/en/wow/t/friendly-cooldown-tracking-disabled-with-121/2335400/3)）
2. 全职业实测（换职业验证 IsSpellKnown 过滤 + 时长学习）
3. 版本误报修复游戏内回归（v1.0.4 已含修复，待实战确认）
4. BigDebuffs Midnight 实测（保留兼容代码）
5. 性能优化（OnTick 高频 GUID 比较，需游戏内 profiler）
