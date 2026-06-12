# CellD

[![version](https://img.shields.io/github/v/release/davidchangok/CellD)](https://github.com/davidchangok/CellD/releases)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/davidchangok/CellD/blob/main/LICENSE)

CellD 是一款优秀的魔兽世界团队框架插件，继承了 [Cell](https://github.com/enderneko/Cell) 的优秀设计，由 **David W Zhang** 继续开发维护。

由于原作者 enderneko 工作繁忙已停止更新，CellD 将继续为正式服最新版本提供支持。

> 灵感来源：**CompactRaid**、**Grid2**、**Aptechka**、**VuhDo**

---

## 支持版本

- **魔兽世界正式服 12.0.5+（Midnight）**
- 不再支持怀旧服（Classic / TBC / Wrath / Cata / Mists）

---

## 主要功能

- **布局系统**：按队伍类型/职责/专精自动切换布局，支持小队、团队、战场、竞技场
- **自定义外观**：材质、颜色、透明度、字体全面可调
- **内置点击施法**：支持键盘快捷键与多键鼠标，无需第三方插件
- **丰富的指示器**：内置数十种指示器，支持无限自定义（图标、进度条、矩形、文本、叠加层、发光、颜色）
- **副本减益**：带优先级排序的减益列表，内置多种发光效果
- **团队工具**：就位确认、职责确认、倒计时、补增益、死亡通报、标记、战复
- **精致的选项界面**：简洁直观的配置面板，操作体验极佳
- **特别关注框体**：额外 15 个单位按钮，可设为目标、焦点、坦克、指定单位等
- **快速协助**：专为增辉唤魔师设计的一键辅助
- **兼容性**：[BigDebuffs](https://www.curseforge.com/wow/addons/bigdebuffs)、[Class Colors](https://www.curseforge.com/wow/addons/classcolors)、[OmniCD](https://www.curseforge.com/wow/addons/omnicd)、[WeakAuras](https://wago.io/weakauras)

---

## 安装方法

1. 下载最新版本：[Releases](https://github.com/davidchangok/CellD/releases)
2. 解压到 `World of Warcraft\_retail_\Interface\AddOns\` 目录
3. 确保文件夹名为 `CellD`
4. 重启游戏或 `/reload`

---

## 斜杠命令

| 命令 | 说明 |
| ---- | ---- |
| `/celld` | 显示所有可用命令 |
| `/celld options` | 打开设置窗口 |
| `/celld blackbox` | 运行 Secret Value 安全性黑箱自检 |
| `/celld healers` | 创建"治疗者"指示器 |
| `/celld rescale` | 应用推荐缩放比例 |
| `/celld reset position` | 重置 CellD 位置 |
| `/celld reset layouts` | 重置全部布局和指示器 |
| `/celld reset clickcastings` | 重置全部点击施法 |
| `/celld reset raiddebuffs` | 重置全部副本减益 |
| `/celld reset snippets` | 重置全部代码片段 |
| `/celld reset quickassist` | 重置当前专精的快速协助 |
| `/celld reset all` | 重置全部设置（慎用） |
| `/celld report <数字>` | 设置团队战中死亡通报数量（0-40） |

> 注：旧的 `/cell` 命令仍然可用，保证向后兼容。

---

## 代码片段

**如果更新后遇到问题，请先检查/禁用代码片段。**

访问 [原 Cell 代码片段仓库](https://github.com/enderneko/Cell/tree/master/.snippets) 获取更多代码片段。

### 使用方法

1. CellD 选项 → 关于 → 代码片段
2. 新建 → 粘贴代码 → 保存 → 勾选"自动运行"
3. 重载界面（`/reload`）

---

## 安全说明

暴雪在魔兽世界 12.0.0（Midnight）中引入了 **Secret Value（秘密数值）** 机制。在战斗/首领战/PvP/大秘境等受限上下文中，生命值、能量值、吸收量、光环持续时间等敏感数据会被包装为无法直接运算的特殊类型。

CellD 已对此进行了全面的安全加固，包括：

- 使用 `pcall` 保护所有敏感 API 调用
- 使用 `issecretvalue()` 检测并跳过加密数据
- 使用暴雪提供的安全替代 API（`CreateUnitHealPredictionCalculator`、`C_CurveUtil` 等）
- 内置黑箱自检模块（`/celld blackbox`）

在游戏中使用 `/celld blackbox` 可随时运行安全性自检。

---

## 计划功能

- [ ] CurseForge / Wago 发布
- [ ] 持续跟进最新团本减益数据
- [ ] 更多代码注释和文档完善

---

## 致谢

CellD 是基于 [Cell](https://github.com/enderneko/Cell) 的分支版本。原始插件的全部设计架构归属于原作者 **enderneko** 和所有为 Cell 做出贡献的开发者。

CellD 将继续秉承 Cell 的设计理念，专注于正式服版本的维护和更新。

---

## 许可证

本项目基于原始 [MIT License](LICENSE) 继续开源。
