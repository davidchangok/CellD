# CellD — 魔兽世界团队框架插件

[![version](https://img.shields.io/github/v/release/davidchangok/CellD)](https://github.com/davidchangok/CellD/releases)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/davidchangok/CellD/blob/main/LICENSE)

**CellD** 是一款优秀的魔兽世界团队框架插件，继承自 [enderneko 的 Cell](https://github.com/enderneko/Cell)。原作者因工作繁忙停止更新后，由 **David W Zhang** 继续维护，专注于正式服最新版本。

---

## 设计理念

CellD 并非追求极限轻量，也不试图面面俱到。它的目标是提供**比以往更好的用户体验**。

灵感来源于：**CompactRaid**、**Grid2**、**Aptechka**、**VuhDo**

---

## 支持版本

- **魔兽世界正式服 12.0.5+（Midnight）**
- 不再支持怀旧服

---

## 主要功能

- **布局系统** — 按队伍类型 / 职责 / 专精自动切换布局，覆盖单人、小队、团队、战场、竞技场
- **自定义外观** — 材质、颜色、透明度、字体、边框全面可调
- **内置点击施法** — 支持键盘快捷键与多键鼠标，无需第三方插件
- **智能复活** — 对死亡单位自动替换为复活法术（支持普通复活 + 战复）
- **丰富的指示器** — 内置数十种指示器（图标、进度条、矩形、文字、发光等），支持无限自定义
- **副本减益** — 带优先级排序的减益列表，内置多种发光效果（像素、闪耀、触发）
- **团队工具** — 就位确认、职责确认、开怪倒计时、补增益检查、死亡通报、世界/目标标记、战复计时
- **特别关注框体** — 额外 15 个单位按钮，可设为目标、焦点、坦克、指定单位等
- **快速协助** — 一键辅助功能（增辉唤魔师适配）
- **黑箱自检** — 内置 Secret Value 安全性检测（`/celld blackbox`）
- **精致的选项界面** — 简洁直观的配置面板，操作体验极佳
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

## 代码片段

**遇到问题请先禁用所有代码片段再测试。**

### 用法

1. CellD 选项 → 关于 → 代码片段
2. 新建 → 粘贴 → 保存 → 勾选自动运行
3. 重载界面

---

## Secret Value 黑箱自检

暴雪在 12.0 版本引入了 Secret Value（opaque type）机制，战斗中的生命值、能量、吸收量等敏感数据会被包装为不可运算的类型。CellD 内置了完整的安全保护措施。

使用 `/celld blackbox` 可随时运行黑箱自检，对所有涉及敏感数据的代码路径进行安全性验证。

> 开发提示：可在非战斗时通过 CVar 强制开启所有限制进行测试：
> ```
> /run SetCVar("secretCombatRestrictionsForced", 1)
> /run SetCVar("secretEncounterRestrictionsForced", 1)
> /run SetCVar("secretChallengeModeRestrictionsForced", 1)
> /run SetCVar("secretPvPMatchRestrictionsForced", 1)
> ```
> 关闭：`/run SetCVar("secretCombatRestrictionsForced", 0)`

---

## 帮助改进副本减益数据

使用 [Instance Spell Collector](https://www.curseforge.com/wow/addons/instance-spell-collector) 收集副本减益数据，然后在 GitHub 上提交 PR 或 Issue。

---

## 相关链接

- **GitHub 仓库**：https://github.com/davidchangok/CellD
- **问题反馈**：https://github.com/davidchangok/CellD/issues
- **原项目 Cell**：https://github.com/enderneko/Cell

---

## 致谢

CellD 基于 [enderneko 的 Cell](https://github.com/enderneko/Cell) 继续开发。感谢原作者和所有代码贡献者的卓越工作。
