# CellD 发布说明 / Release Notes

## v1.0.3 — 2026-06-29

### 中文

本次版本主要聚焦于核心运行路径的稳定性提升，针对初始化、组队状态切换、单位按钮刷新与通讯回调等高频场景增加了容错保护，降低单个模块异常对整个插件流程的影响。

主要改动：

- 增强了核心事件分发与初始化流程的兜底处理。
- 为通讯发送与回调触发增加了异常保护，避免 malformed payload 或受限上下文导致整体中断。
- 对单位按钮刷新流程做了局部容错，确保单个子更新失败时不影响整轮刷新。
- 更新了 README 的项目说明，补充了当前版本的稳定性与兼容性重点。

### English

This release focuses on improving runtime stability in the addon core. Additional fault tolerance was added around initialization, group-state changes, unit-button refreshes, and comm callbacks to reduce the impact of single-module failures on the overall addon flow.

Key changes:

- Added safer wrappers around core event dispatch and initialization callbacks.
- Hardened comm send/receive paths to avoid cascading failures from malformed payloads or restricted contexts.
- Added local guards around unit-button refresh substeps so one failing update no longer breaks the entire refresh cycle.
- Refreshed the README to better reflect the current project focus and recent reliability work.

---

## v1.0.0 — 2026-06-13

### 中文

CellD 首个正式发布版本，基于 [enderneko 的 Cell](https://github.com/enderneko/Cell) 分叉，专注于魔兽世界 12.0（Midnight）正式服。

**Secret Value 安全加固**是本版本的核心工作。暴雪在 12.0 引入了 Secret Value（opaque type）机制，战斗中的生命值、能量、吸收量、光环持续时间等敏感数据被包装为不可运算的类型。CellD 借鉴 Grid2 和 VuhDo 的实现方案，对全代码进行了 35 次提交的安全审查和修复，确保插件在副本战斗中零报错运行。

主要改动：

- **Midnight 12.0 Secret Value 全面兼容** — 借鉴 Grid2/VuhDo 架构，包括 `issecretvalue` 全局函数委托、`GetAuraDispelTypeColor` C 引擎 API、`canActivePlayerDispel` Secret Boolean Guard、StatusBar 原生 secret 比例处理
- **可驱散减益醒目染色** — Grid2 Square 指示器风格的整格背景着色，第一时间吸引治疗注意
- **副本减益 Boss 筛选** — `ENCOUNTER_START/END` 事件自动切换当前 Boss 列表
- **驱散预览实时更新** — 选项面板中的驱散设置预览实时展示效果
- **盾条 StatusBar 转型** — Frame+纹理 改为 StatusBar，C 引擎原生处理 secret 比例
- **镜像术 / 群体屏障** — 改为 UNIT_AURA 检测，移除受保护的 CLEU 事件
- **Secret String 兼容** — FontString 原生 SetText 显示，跳过字符串操作
- **GUID 操作防护** — IsPlayer/IsPet/IsNPC/IsVehicle 全部加固

已知限制：
- 代码片段、快速协助、Buff Tracker 等模块尚未完成 Midnight 适配
- WeakAuras 在 12.0 中不再支持
- 仅支持简体中文（zhCN）和英文（enUS）

---

### English

First official release of CellD, forked from [enderneko's Cell](https://github.com/enderneko/Cell) and focused exclusively on WoW 12.0 (Midnight) retail.

**Secret Value safety hardening** is the core work of this release. Blizzard introduced the Secret Value (opaque type) mechanism in 12.0, wrapping sensitive combat data in non-comparable types. CellD adopts patterns from Grid2 and VuhDo across 35 commits of security review and fixes, ensuring zero errors during dungeon combat.

Key changes:

- **Midnight 12.0 Secret Value full compatibility** — Grid2/VuhDo-inspired architecture including `issecretvalue` global delegation, `GetAuraDispelTypeColor` C-engine API, `canActivePlayerDispel` Secret Boolean Guard, StatusBar native secret ratio handling
- **Dispellable debuff cell highlighting** — Grid2 Square indicator-style full-cell background tinting
- **Raid debuff per-boss filtering** — `ENCOUNTER_START/END` events auto-switch boss lists
- **Live dispel preview** — dispel settings preview updates in real-time
- **ShieldBar StatusBar migration** — Frame+texture replaced by StatusBar for C-engine secret ratio handling
- **Mirror Image / Mass Barrier** — migrated to UNIT_AURA detection, removed protected CLEU events
- **Secret String compatibility** — FontString native SetText for secrets, skipping string operations
- **GUID operation guards** — IsPlayer/IsPet/IsNPC/IsVehicle all hardened

Known limitations:
- Snippets, Quick Assist, Buff Tracker modules not yet audited for Midnight
- WeakAuras no longer supported in 12.0
- Only Simplified Chinese (zhCN) and English (enUS) locales supported
