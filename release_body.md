## CellD v1.0.4

本轮为**全量代码审计 + 三轮修复**（54 个文件），核心围绕 Midnight 12.0 Secret Value 受限环境防护与历史遗留缺陷清扫。

### 主要修复

- **版本检查误报修复** — 原版 Cell（`r275.10-beta`）与 CellD（`1.0.3`）共用 `CELL_VERSION` 通讯前缀且版本号格式不同，`%d+` 提取导致误报"发现新版本"；现仅比较 CellD 语义化版本（`x.y.z` 逐级比较），下载链接修正指向 CellD 仓库
- **Comm 接收端受限环境防护** — `CELL_SEND`/`CELL_SEND_PROG`/`CELL_REQ` 增加 `IsCommRestricted` 前置检查（战斗 / 大秘境 / PvP 时忽略）
- **BuffTracker 语法恢复** — `local fl function` 语法错误修正，团队 Buff 检查恢复
- **导入导出安全强化** — 5 个 ImportExport 模块反序列化统一加 `type(data)=="table"` 校验
- **CellD 媒体路径全库修正** — `AddOns\Cell\Media` → `AddOns\CellD\Media`（29 文件）
- **Secret Value 防护补充** — NPCFrame secret GUID、`IsSpellReady`、`GetSpellTooltipInfo`、TargetCounter `GetPoint`
- **行为修复** — DeathReport `limit=0`、soulstone 检测、`allCooldowns` 去重、指示器重名
- **Midnight 适配** — SR/DR 与 DeathReport 跳过已移除的 CLEU 事件注册、全局泄漏清扫、zhCN 补键

### 说明

仅支持 WoW 12.0 Midnight 正式服。下载：[https://github.com/davidchangok/CellD/releases](https://github.com/davidchangok/CellD/releases)
