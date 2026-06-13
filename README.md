# CellD — 魔兽世界团队框架插件

[![version](https://img.shields.io/github/v/release/davidchangok/CellD)](https://github.com/davidchangok/CellD/releases)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/davidchangok/CellD/blob/main/LICENSE)

**CellD** 是一款优秀的魔兽世界团队框架插件，继承自 [enderneko 的 Cell](https://github.com/enderneko/Cell)。原作者因工作繁忙停止更新后，由 **David W Zhang** 维护这个版本，专注于正式服最新版本。此版本仅供 David W Zhang 使用（当然任何人都可以随便用）。

---

## 设计理念

CellD 致力于提供**比以往更好的用户体验**。

灵感来源于：**CompactRaid**、**Grid2**、**Aptechka**、**VuhDo**

---

## 支持版本

- **魔兽世界正式服 12.0（Midnight）**
- 不再支持怀旧服

---

## 主要功能

- **布局系统** — 按队伍类型 / 职责 / 专精自动切换布局，覆盖单人、小队、团队、战场、竞技场
- **自定义外观** — 材质、颜色、透明度、字体、边框全面可调
- **实时血量与能量显示** — Midnight 12.0 Secret Value 环境安全渲染，使用 HealPredictionCalculator + StatusBar 原生 C 引擎处理
- **吸收量 / 护盾条** — 吸收盾、过量护盾（Overshield）实时可视化，反色填充
- **生命阈值指示器** — 多级血量阈值标识
- **内置点击施法** — 支持键盘快捷键与多键鼠标，无需第三方插件
- **智能复活** — 对死亡单位自动替换为复活法术（支持普通复活 + 战复）
- **丰富的指示器** — 内置数十种指示器（图标、进度条、矩形、文字、发光等），支持无限自定义
- **副本减益** — 带优先级排序的减益列表，内置多种发光效果（像素、闪耀、触发），支持当前活跃 Boss 自动筛选
- **可驱散减益醒目染色** — 借鉴 Grid2 IndicatorSquare 架构，通过 Blizzard `C_UnitAuras.GetAuraDispelTypeColor` C 引擎 API（含 `pcall` 保护）获取颜色，结合 `canActivePlayerDispel`（12.0 新字段，NeverSecret）判断当前角色驱散能力。在单元格背景上以选项定义的驱散颜色整格染色（按钮自身 `SetBackdropColor`），第一时间吸引治疗注意
- **防御 / 外部 / 全技能冷却** — Mirror Image、Mass Barrier 等特殊技能通过 UNIT_AURA 检测
- **团队工具** — 就位确认、职责确认、开怪倒计时、补增益检查、死亡通报、世界/目标标记、战复计时
- **特别关注框体** — 额外 15 个单位按钮，可设为目标、焦点、坦克、指定单位等
- **快速协助** — 一键辅助功能（增辉唤魔师适配）
- **黑箱自检** — 内置 Secret Value 安全性检测（`/celld blackbox`），覆盖所有敏感数据代码路径
- **精致的选项界面** — 简洁直观的配置面板，操作体验极佳，预览按钮实时展示效果
- **兼容性** — [BigDebuffs](https://www.curseforge.com/wow/addons/bigdebuffs)、[OmniCD](https://www.curseforge.com/wow/addons/omnicd)、[WeakAuras](https://wago.io/weakauras)

---

## 安装方法

1. 下载最新版本：[Releases](https://github.com/davidchangok/CellD/releases)
2. 解压到 `World of Warcraft\_retail_\Interface\AddOns\` 目录
3. 确保文件夹名为 `CellD`
4. 重启游戏或 `/reload`

---

## 斜杠命令

| 命令 | 功能 |
| ---- | ---- |
| `/celld` 或 `/cell` | 显示所有可用命令 |
| `/celld options` | 打开设置窗口 |
| `/celld healers` | 创建"治疗者"指示器 |
| `/celld rescale` | 应用推荐缩放比例 |
| `/celld blackbox` | Secret Value 黑箱自检 |
| `/celld reset position` | 重置 CellD 位置 |
| `/celld reset layouts` | 重置全部布局和指示器 |
| `/celld reset clickcastings` | 重置全部点击施法 |
| `/celld reset raiddebuffs` | 重置全部副本减益 |
| `/celld reset snippets` | 重置全部代码片段 |
| `/celld reset quickassist` | 重置当前专精的快速协助 |
| `/celld reset all` | 重置全部设置（慎用） |
| `/celld report <数字>` | 设置团队战中死亡通报数量（0–40） |

---

## Midnight 12.0 Secret Value 安全架构

暴雪在 12.0 版本引入了 Secret Value（opaque type）机制，战斗中的生命值、能量、吸收量、光环持续时间等敏感数据被包装为不可运算的类型。CellD 借鉴 **Grid2** 和 **VuhDo** 两个插件的方案，对全代码进行了安全加固：

### 核心策略

| 方案 | 借鉴来源 | 说明 |
|------|:--:|------|
| `F.IsSecretValue()` → Blizzard `issecretvalue()` 全局函数 | Grid2 | 正确识别所有 secret 类型（number、string、boolean、fileID） |
| `C_UnitAuras.GetUnitAuras` 替代逐槽遍历 | Grid2 | 单次 API 调用获取完整光环数组 |
| `GetAuraDispelTypeColor(auraInstanceID)` C 引擎 API | Grid2 / VuhDo | 内部解析 secret，返回正确颜色 |
| `auraInfo.canActivePlayerDispel` Secret Boolean Guard | 12.0 新字段 | NeverSecret → 直接判断驱散能力 |
| 按钮自身 `SetBackdropColor` 整格染色 | Grid2 Square 指示器 | 无层级冲突，覆盖整个单元格 |
| StatusBar + `SetMinMaxValues/SetValue` C 引擎处理 | Grid2 | 盾条/血量条原生支持 secret 值比例计算 |
| Secret String 兼容 | Grid2 / VuhDo | `FontString:SetText()` 原生接受 secret，跳过 `utf8len/utf8sub` 截断 |

### 安全防护清单

| 模块 | 防护措施 |
|------|---------|
| 血量显示 | `HealPredictionCalculator` → `healthPercent` 缓存回退（非 0）→ `class_color` 模式不受影响 |
| 盾条/吸收量 | `ShieldBar` StatusBar 转型 → `SetMinMaxValues(0,max)+SetValue(current)` C 引擎处理比例 |
| 能量条 | `powerFilters` nil guard → `ShouldShowPowerBar/Text` 回退 `true` |
| Debuff 分类 | `hasSecretTime` flag → 分类/显示不跳过 → `DurationObject` 回退渲染冷却 |
| 驱散染色 | `dispelName` secret 时回退 `"Magic"` → `pcall(GetAuraDispelTypeColor)` 取色 → `_dispelsHighlightColor` 标记防止覆盖 |
| 有益技能 | `Mirror Image/Mass Barrier` 改由 `UNIT_AURA` 检测 |
| Boss 减益 | `ENCOUNTER_START/END` 自动切换当前 Boss 列表 |
| 名字显示 | `UpdateTextWidth/FitWidth` secret 时跳过字符串操作，直接 `SetText` → `SetSize` 回退 `parent:GetWidth` |
| GUID 操作 | `F.IsPlayer/IsPet/IsNPC/IsVehicle` 前置 `IsSecretValue` guard |
| 排序 | `SortRaidDebuffs` cache miss nil guard |

### 黑箱自检

使用 `/celld blackbox` 可随时运行黑箱自检，对所有涉及敏感数据的代码路径进行安全性验证。17 项测试覆盖基础 API、吸收量、光环数据、速度检测、安全函数自测、指示器路径、模块安全、配置完整性、CVar 状态。

> 开发提示：可在非战斗时通过 CVar 强制开启所有限制进行测试：
> ```
> /run SetCVar("secretCombatRestrictionsForced", 1)
> /run SetCVar("secretEncounterRestrictionsForced", 1)
> /run SetCVar("secretChallengeModeRestrictionsForced", 1)
> /run SetCVar("secretPvPMatchRestrictionsForced", 1)
> ```
> 关闭：`/run SetCVar("secretCombatRestrictionsForced", 0)`

---

## 代码片段

**遇到问题请先禁用所有代码片段再测试。**

### 用法

1. CellD 选项 → 关于 → 代码片段
2. 新建 → 粘贴 → 保存 → 勾选自动运行
3. 重载界面

---

## 帮助改进副本减益数据

使用 [Instance Spell Collector](https://www.curseforge.com/wow/addons/instance-spell-collector) 收集副本减益数据，然后在 GitHub 上提交 PR 或 Issue。

---

## 相关链接

- **GitHub 仓库**：https://github.com/davidchangok/CellD
- **问题反馈**：https://github.com/davidchangok/CellD/issues
- **原项目 Cell**：https://github.com/enderneko/Cell

---

## 技术参考

本插件在 Midnight 12.0 Secret Value 兼容性开发过程中参考了以下优秀插件的实现：

| 插件 | 参考内容 |
|------|---------|
| [Grid2](https://www.curseforge.com/wow/addons/grid2) | `issecretvalue`/`canaccessvalue` 全局原语、`GetAuraDispelTypeColor` API、Square 指示器整格染色 |
| [VuhDo](https://www.curseforge.com/wow/addons/vuhdo) | `hasSecretName` 标记模式、`GetAuraDispelTypeColor(unit, auraID, curve)` 用法 |

---

## 致谢

CellD 基于 [enderneko 的 Cell](https://github.com/enderneko/Cell) 继续开发。感谢原作者和所有代码贡献者的卓越工作。
