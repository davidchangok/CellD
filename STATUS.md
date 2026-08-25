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


---

## 九、VuhDo 3.214 光环实现分析（2026-08 学习）

> 来源：`E:\Game\World of Warcraft\_retail_\Interface\AddOns\VuhDo`（TOC 120100，当前 Version 3.215；3.214 分析基础，3.215 changelog 无实质条目、文件结构无变化）。

### 实测结论（用户确认）

- `/celld testaura` 的 AuraContainer **战斗时能全部显示**，AuraContainer 路线可用。
- **硬性约束**：不得改变 CellD grid 外观；鼠标必须能正常使用；悬停 grid 施法是核心功能，AuraContainer 绝不能拦截鼠标/点击。

### VuhDo 的 12.1 光环方案

1. **能力探测**
   - `VuhDoConst.lua` 用 `C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")` 判断是否存在 12.1 原生 AuraContainer 模板。
   - 存在时 `VUHDO_AURA_MODE_CONTAINERS = true`，进入“容器模式”；可用 `/命令` 强制关闭或强制开启。

2. **双轨架构**
   - **容器模式（AuraContainer 主用）**：每个单位按钮的每个光环锚点创建一个 `AuraContainer`，同时为“指示器覆盖层”（血条染色、边框、圆点）也创建 overlay 容器。
   - **旧手动光环系统保留**：仅用于非光环类 bouquet 条目（状态条、文字等）以及无 AuraContainer 能力/强制关闭时的回退。

3. **AuraContainer 挂载方式（关键）**
   - 普通光环图标容器：parent 仍是单位按钮（`aButton`），但容器本身不是 SecureUnitButton。
   - overlay 容器：parent 指向按钮内的普通 Frame `$parentOlHost`（非 SecureUnitButton），或直接挂到目标血条。
   - 所有 AuraContainer/AuraButton 均 `SetMouseClickEnabled(false)`，鼠标/点击仍由原 secure 按钮负责。
   - 这正好对应 CellD 之前“不要集成到 SecureUnitButton 内”的教训：**不是不能用 AuraContainer，而是不能把它当作 secure 按钮的一部分来接管鼠标/显隐**。

4. **核心 API 用法**
   - `AuraContainer:AddAuraGroup(key, filterString, options)`：动态流式布局，适合“一组同类光环”；
   - `AuraContainer:AddAuraSlot(key, filterString, options)`：固定槽位，适合“列表式法术每个固定位置”；
   - options 中关键字段：
     - `candidateFilters.includeSpellIDs`：让 C 引擎只追踪指定法术（对 secret 环境尤其重要）；
     - `candidateFilters.excludeSpellIDs` / `includeDispelTypes` / `maxDuration`；
     - `templateNames`：使用 VuhDo 自定义的 `CustomAuraButtonTemplate`；
     - `initializeFrame`：初始化按钮外观（图标/文字/冷却/颜色/发光）。
   - `AuraContainer:SetUnit(unit)`、`SetEnabled(true)`、`SetShown(true)`、`UpdateAllAuras()`。
   - `AuraButton` 上使用 `SetIcon`、`SetDurationBar`、`AddDispelTypeTexture`、`SetDurationText` 等原生绑定，让 C 引擎处理 secret 时长/层数/图标。

5. **过滤器翻译**
   - 旧 VuhDo 光环组语法转成原生 filter string，如：
     - `HELPFUL` / `HARMFUL`
     - `PLAYER` / `!PLAYER`
     - `RAID_PLAYER_DISPELLABLE` → 附加 `includeDispelTypes`
     - `NOT_CANCELABLE` → `!CANCELABLE`
   - 列表型光环组（明确 spellId 列表）自动生成 `includeSpellIDs`，这正是 12.1 受限环境下“告诉引擎我要看哪些 secret 光环”的关键。

6. **生命周期管理**
   - 模板按 panel/anchor 缓存；AuraContainer 有对象池，按外观配置生成 pool key。
   - 战斗锁定期间不能创建/改父级时，进入 pending 队列，`CanBeAccessedInContext()` 允许后再补建。
   - 每个单位同步时检查：unit/guid/restricted/assist/disconnected/phase 等门控，必要时 `SetAuraGroupMaxFrameCount(0)` 或清空 filter 来隐藏。
   - `VUHDO_refreshAuraContainer` 调用 `UpdateAllAuras()` + `SetOnUpdateMode(RunWhenVisible)`。

### 对 CellD 的启发 / 可学习点

1. **重新评估 AuraContainer 可行性**：VuhDo 证明“独立 AuraContainer + 非 secure 子 Frame 挂载”可以作为 12.1 光环显示通道。CellD 之前三次回滚可能是因为直接挂在 SecureUnitButton 或试图让它处理鼠标/显隐，而不是因为 AuraContainer 本身不可用。
2. **优先用 `includeSpellIDs` 让引擎追踪已知法术**：CellD 已有 SecretAuraTracker 的追踪列表（官方 secret 名单 + IsSpellKnown + Healers 布局），完全可以转换为 `candidateFilters.includeSpellIDs`，可能比施放事件追踪更完整（队友施放、驱散、提前结束等仍受暴雪限制，但至少自己施放的 HoT 可交给引擎）。
3. **从 Healers 指示器做 POC**：先做一个独立 AuraContainer（挂 UIParent 或按钮的普通 overlay Frame），用 `HELPFUL|PLAYER` + `includeSpellIDs` 渲染奶骑/奶德/戒律常用 HoT；验证战斗内是否显示、是否与 CellD 点击施法共存。
4. **保留 SecretAuraTracker 作为 fallback**：对 AuraContainer 无法表达/未验证的法术继续用施放追踪，两者可并存。
5. **已新增 `Utilities/AuraContainerOverlay.lua`（进行中）**：
   - 每个单位按钮在 `indicatorFrame` 下挂 AuraContainer，AuraContainer/AuraButton 全部禁用鼠标，脱战隐藏、战斗显示；
   - buff/HoT：`HELPFUL` + 同一追踪名单；SecretAuraTracker 在 overlay 激活时跳过手动渲染；
   - debuff 图标：`HARMFUL`，按布局中 debuffs 的 position/size/orientation/num 创建；
   - 驱散染色：`HARMFUL|RAID_PLAYER_DISPELLABLE` + `AddDispelTypeTexture` 使用 `CellDB["debuffTypeColor"]` 染色；
   - 战斗中隐藏旧版 debuffs/dispels 避免重复；
   - 实时同步：`GROUP_ROSTER_UPDATE` 同步现有按钮，`UpdateLayout` 后脱战重建覆盖层；
   - 用户实测通过：战斗显示正常、鼠标/点击施法不受影响、脱战隐藏且 grid 外观不变；已按要求去掉倒计时数字。

### 待验证问题

- VuhDo 在容器模式下始终 `SetEnabled(true)`，是否真的能显示 12.1 战斗 secret 光环？需要游戏内用 CellD 同款场景实测。
- AuraContainer 对“队友施放增益”和“驱散/提前结束”的可见性是否优于施放追踪。
- CellD 的 21 种指示器哪些能映射到 AuraGroup/AuraSlot，哪些仍需静态旧框架。


---

## 十、退出前调试快照（2026-08）

### 当前代码状态
- `Utilities/AuraContainerOverlay.lua`：已支持 buff / debuff / 驱散染色三类 AuraContainer overlay，禁用鼠标，脱战隐藏，战斗显示。
- `Utilities/TestAuraContainer.lua`：已增加第三个测试容器 `C: HARMFUL`，用于确认 AuraContainer 能否直接显示 harmful debuff。
- `RaidFrames/UnitButton.lua`：已修复 `UnitIsCharmed` secret boolean 报错。
- `Indicators/Built-in.lua`：已修复 `nameText:SetSize` 收到 secret 宽高报错。

### VuhDo 参考结论（已对齐）
- 普通 Debuff 组：`filter = "HARMFUL"`，`candidateFilters = nil`
- 驱散染色组：`filter = "HARMFUL|RAID_PLAYER_DISPELLABLE"`
- 不需要 `RAID_IN_COMBAT`，不需要空 `candidateFilters`

### 当前进度（退出前保存）
1. **Debuff 图标已能在 CellD Grid 上显示**（用户确认）。
2. **驱散染色尚未生效（2026-08-19 已按 Grid2/VuhDo 对照修复，待游戏内实测，见第 7 节）**：用户测试了中毒/定身/减速等多种可驱散 Debuff，Grid 上没有出现可驱散变色。
3. 当前代码状态：
   - `AuraContainerOverlay.lua` 已加载（注释掉了 RegisterCallback 和加载时自动 ShowAll 两个加载期执行块，避免模块加载失败）。
   - `TestAuraContainer.lua` 保持简单版本，确保能加载。
   - Debuff overlay：`filter = "HARMFUL"`，`candidateFilters = nil`，已生效。
   - Dispel overlay：`filter = "HARMFUL|RAID_PLAYER_DISPELLABLE"`，`candidateFilters = nil`，尚未变色。
4. 已修复的报错：
   - `TestAuraContainer` 加载失败（由 OnUpdate/C_Timer 代码导致，已移除）。
   - `AuraButton:CanBeAccessedInContext/IsShown` 返回 secret boolean 的报错。
5. **Grid2 4.0.22 / VuhDo 3.215 对照结论（当前焦点：VuhDo 的 `includeDispelTypes`）**：
   - Grid2: `SetAuraBorder` + `customDispelColorMap`；VuhDo: `AddDispelTypeTexture` + `customDispelColorMap`（filter = `HARMFUL|DISPELLABLE` / `HARMFUL|RAID_PLAYER_DISPELLABLE` + `candidateFilters.includeDispelTypes`）
   - 参考文件：`Grid2/modules/StatusAuras.lua`、`Grid2/modules/IndicatorSquare.lua`、`Grid2/GridIndicatorAuras.lua`、`VuhDo/VuhDoAuraContainer.lua`、`VuhDo/VuhDoAuraContainerOverlays.lua`、`VuhDo/VuhDoBouquets.lua`、`VuhDo/VuhDoAuraContainerFilters.lua`
6. **2026-08-19 四轮实测结论 + v4 方案（当前代码状态）**：
   - **实测 1**：slot 按钮 `shown=secret`（已绑定 secret aura）但无边框变色 → **引擎对 secret 光环拒绝渲染驱散类型边框**（SetAuraBorder/customDispelColorMap 会泄露驱散类型，属受限信息）
   - **实测 2**：v2（每类型槽 + includeSpellIDs）三个类型槽**同时绑定**（Disease 槽绑定了非疾病 debuff）→ **引擎对 slot 忽略 includeSpellIDs**；多染色层叠加 → 颜色永远是最上层 Magic 蓝、叠成实色
   - **实测 3**：`icon:GetTexture()` 返回 **secret**（引擎对图标 fileID 也做 secret 包装）→ **图标身份读取通道也被封死**
   - **v4 当前方案（每类型槽 + `includeDispelTypes` + 静态颜色，无需任何法术数据库）**：
     - filter = `"HARMFUL"`（裸 HARMFUL 是唯一实测能绑定+渲染的过滤）
     - `candidateFilters.includeDispelTypes = { [类型]=true }` ← **v4.2 关键修正：必须是键值集合，不是数组！** Grid2 `GridDefaults.lua`：`{ includeDispelTypes = { Magic=true, Curse=true, ... } }`；VuhDo 的 `sAllDispelTypeNames` 同为 set；**v4.0/4.1 传数组 `{"Magic"}` → 引擎解析为空集 → 槽永不绑定 → 完全不渲染（"没变色"的真正根因）**
     - 每个槽 initializeFrame 建整格**静态颜色纹理**（该类型固定色，C 引擎不参与上色，alpha=0.30*1.5=0.45 半透明）
     - 创建顺序 Bleed→Poison→Disease→Curse→Magic（同层级后创建者在上层 = Magic 最高优先级，与 legacy 一致）
     - 无匹配 → 槽不绑定 → 不改变 grid 外观；鼠标全部禁用
     - 附带修复：`SyncButton` 对 `unit=none`（SoloFrame 等未分配单位）跳过绑定
   - 保留（诊断用）：`HandleDebuff` 学习钩子（spellId+icon→type，脱战才可记录）、`/celld testaura dispeldb`
7. 待下次继续（游戏内实测）：
   - **v4.2 已实测通过！**（用户 2026-08-19：裸 `HARMFUL` + `includeDispelTypes` set 格式，风行者之塔显示染色成功）
   - **v4.3/v4.4 教训（均已回退）**：
     - v4.3 `ClearIcon/ClearAuraBorder/...`、v4.4 自定义空模板（无默认部件）**都让槽变 `inaccessible`** → 12.1 受限环境中槽的 aura 分配**依赖 `CustomAuraButtonTemplate` 的默认部件绑定**，不能移除
     - 模板文件 `AuraContainerTemplates.xml` 保留但未引用（LoadUtilities.xml 已移除 Include）
   - **v5.1 用户实测：染色成功显示！**（整格按驱散类型上色，嘉里克船长粉/阿闵绿/修加蓝等）
   - **v5.2 修复（已改，待实测）两个新问题**：
     - **颜色难看** → `AddDispelTypeTexture` 增加 `customDispelColorMap = BuildDispelColorMap()`（CellDB 用户色；VuhDo 生产路径组合；若引擎忽略则回退引擎默认色）
     - **脱战后道标消失**（重要）→ 道标 200025 在 Healers 列表 + SecretAuraTracker 追踪；12.1 脱战后 legacy 刷新不恢复 → `SecretAuraTracker.lua` 的 `PLAYER_REGEN_ENABLED` 改为 `RecheckActiveAuras()`：先清空再用**脱战可读的真实数据**重检（`GetUnitAuraInstanceIDs`+`GetAuraDataByAuraInstanceID`），追踪法术仍挂目标（如 10 分钟道标）→ 重挂图标（真实剩余时长），已消失 → 清理
   - **v5.3 加固（已改）**：脱战防泄漏——`HideAll` 同时 `SetEnabled(false)`（12.1 引擎可能自行恢复容器显隐；Grid2 ReleaseAuraContainer 同款：enable+show 一起关），`SyncButton` 显示时重新 `SetEnabled(true)`
   - **v5.4 严重问题修复（已改，待实测）—— 用户实测反馈两个危险场景**：
     - **染色糊住血条**（治疗看不到低血量）：alpha 从 0.615（双层合成值）降到 **0.30**（legacy highlight 值）——血条可读性恢复
     - **脱战清空后 debuff 无显示**（毒还在挂但 Grid 全空，治疗危险）：12.1 脱战后 legacy 指示器刷新不恢复（`HideLegacyIndicators` 隐藏后无人重新显示，截图实证）→ **驱散染色改为常驻**：`PLAYER_REGEN_ENABLED`/`GROUP_ROSTER_UPDATE`/`PLAYER_ENTERING_WORLD` 后调 `SyncDispelsOutOfCombat()`（引擎用真实数据继续显示/上色）+ `HideLegacyDispels()`（永久隐藏 legacy dispels 防叠加）
   - **v5.6 染色形态终改（已改，待实测）—— 用户实测"60% 数字与血量条显示不一致"（整格染色压缩血量对比，治疗看错血量=危险）**：
     - **边框式染色**：4 条 2px 边 + 底部 3px 信号条，全部 `AddDispelTypeTexture(PreserveAsset)` 引擎按类型着色（CellDB 色表）→ **血条 100% 零遮挡可读**，染色只在边缘/底条（BigWigs 边框思路 + 常驻显隐）
     - 移除整格白色大纹理与 alpha 参数（glowAlpha/highlightAlpha 不再使用）
     - 用户此前观察"远距离队友 = 染色+正常血条并存"即正确形态的标杆
   - 验证协议：`/reload` → 战斗（染色=边框+底条）→ 低血量队友数字与血条**一致可读** → 脱战边框仍显示 → 道标保留
 8. **2026-08-20 血条+染色终改（已改，待游戏内实测）—— 推翻"secret 直喂满宽"误诊，对齐上游 r279**：
    - **误诊链澄清**：此前"secret 直喂 → StatusBar 渲染满宽"的前提错误。真相：`_midnightPctCurve` 解码方案的输出在 Lua 侧仍是 secret（血条数字正确是因 string.format 是 C 通道），战斗中解码永远失败 → `healthPercent` 永远保留**进战前缓存的非 secret 值** → 0..100 分支触发 → **血条冻结在进战时的值**（用户截图铁证：阿间 CellD 90% vs 参照框 80% = 冻结；嘉里克进战 ~100% → 条满 → 染色整格粉）
    - **上游证据**：Cell r279-beta（12.1 生产版）`UpdateHealth`/`UpdateHealthMax` 始终 secret 原值直喂 StatusBar（C++ 原生算比例），secret 时 `healthPercent=0` 哨兵，无解码。已克隆至 `.research/Cell-upstream` 备查
    - **已回退**：删除 `_midnightPctCurve` 及 UpdateHealth/UpdateHealthMax 的 0..100 分支 → 恢复 secret 直喂；UpdateHealthStates secret → `healthPercent=0`（上游同款）；阈值守卫加 `>0` 哨兵判断（战斗中隐藏阈值线）
    - **染色最终形态（用户拍板：两色均需可见）= 血量空缺区染色**：有血=职业色（血条原样零遮挡），空缺区=驱散色（`AddDispelTypeTexture` 引擎按真实类型上色，CellDB 色表，alpha 0.5）；锚点与 `healthBarLoss` 几何一致（纯锚点 C 侧跟随填充，secret 安全）；满血时退化为填充末端 4px 信号条（`DISPEL_MARKER_WIDTH`，否则满血+debuff 无提示）；`hooksecurefunc(Cell.bFuncs,"SetOrientation")` 处理水平/vertical_health 重锚
    - 验证协议：`/reload` → 战斗中队友掉血**血条实时跟随**（不再冻结）→ 有 debuff 时**空缺区显示类型色、有血区职业色不变** → 满血+debuff = 末端 4px 色条 → 脱战行为不变、道标保留
