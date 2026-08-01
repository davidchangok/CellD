# CellD 发布说明 / Release Notes

## v1.0.5 — 2026-08-01

### 中文

**Comm 通讯前缀与原版 Cell 完全隔离**，CellD 不再与原版 Cell 共享任何 AddOn 通讯频道。

主要内容：

- **11 个 comm 前缀 `CELL_` → `CELLD_`** — 版本广播（`CELLD_VERSION`）、标记同步（`CELLD_MARKS`）、优先级（`CELLD_CPRIO`/`CELLD_PRIO`）、配置传输（`CELLD_SEND`/`CELLD_SEND_PROG`/`CELLD_REQ`）、技能/驱散请求（`CELLD_REQ_S`/`CELLD_REQ_D`）、昵称（`CELLD_NIC`/`CELLD_CNIC`）全面换名
- **游戏内宏文本同步** — 技能/驱散请求宏更新为 `CELLD_REQ_S`/`CELLD_REQ_D`，请在选项面板重新复制宏
- **保留不变** — `CELL_NOTIFY`（WeakAuras 事件名）与 `CELL_NICKTAG_ENABLED`（代码片段常量）不受影响

**注意**：隔离后 CellD 与原版 Cell、以及新旧 CellD 版本之间不再互通（标记/昵称/请求等自动同步仅在同版本 CellD 之间生效）。

### English

**AddOn comm prefixes are now fully isolated from the original Cell**, so CellD no longer shares any addon communication channel with it.

Highlights:

- **11 comm prefixes renamed `CELL_` → `CELLD_`** — version (`CELLD_VERSION`), marks (`CELLD_MARKS`), priority (`CELLD_CPRIO`/`CELLD_PRIO`), config transfer (`CELLD_SEND`/`CELLD_SEND_PROG`/`CELLD_REQ`), spell/dispel request (`CELLD_REQ_S`/`CELLD_REQ_D`), nicknames (`CELLD_NIC`/`CELLD_CNIC`)
- **In-game macro text updated** — spell/dispel request macros now use `CELLD_REQ_S`/`CELLD_REQ_D`; re-copy them from the options panel
- **Unchanged** — `CELL_NOTIFY` (WeakAuras event name) and `CELL_NICKTAG_ENABLED` (code snippet constant)

**Note**: after isolation, CellD no longer interoperates with the original Cell or with older CellD versions (marks/nicknames/requests auto-sync only works between matching CellD versions).

---

## v1.0.4 — 2026-08-01

### 中文

本轮为 **全量代码审计 + 三轮修复**（54 个文件），核心围绕 Midnight 12.0 Secret Value 受限环境防护与历史遗留缺陷清扫。

主要内容：

- **版本检查误报修复** — 原版 Cell（`r275.10-beta`）与 CellD（`1.0.3`）共用 `CELL_VERSION` 通讯前缀且版本号格式不同，`%d+` 提取导致误报"发现新版本"；现仅比较 CellD 语义化版本（`x.y.z` 逐级比较），并修正下载链接指向 CellD 仓库
- **Comm 接收端受限环境防护** — `CELL_SEND`/`CELL_SEND_PROG`/`CELL_REQ` 增加 `IsCommRestricted` 前置检查（战斗 / 大秘境 / PvP 时忽略）
- **BuffTracker 语法恢复** — `local fl function` 语法错误修正，团队 Buff 检查从分叉起失效后恢复
- **导入导出安全强化** — 5 个 ImportExport 模块反序列化统一加 `type(data)=="table"` 校验，DoImport 加缺键防御
- **CellD 媒体路径全库修正** — `AddOns\Cell\Media` → `AddOns\CellD\Media`（29 文件），修复 perl 误替换丢失反斜杠的 12 处
- **Comm/Marks 类型防护** — `CELL_MARKS` 接收端加数字/字符串类型校验，防恶意 payload 报错轰炸
- **Secret Value 防护补充** — NPCFrame secret GUID 比较、`IsSpellReady` secret/nil 安全失败、`GetSpellTooltipInfo` nil 保护、TargetCounter `GetPoint` nil/secret 防护
- **拖拽/越界/索引缺陷** — RaidDebuffs 拖拽 `GetParent()` nil、ColorPicker alpha 手柄父级、BlockColors 索引、circled 表越界、RaidDebuffs 拖拽 nil 防护
- **行为修复** — DeathReport `limit=0`（全部报告）、Revise 无条件覆盖改 `== nil` 条件、soulstone 检测（活着时不再清 flag）、新指示器命名取最大数字后缀+1、`allCooldowns` 去重
- **Midnight 适配** — SR/DR 与 DeathReport 的 CLEU 注册在 Midnight 加条件跳过（12.0 已移除该事件）、全局泄漏清扫、zhCN 补 7 个缺失键

### English

This release is a **full audit + three rounds of fixes** (54 files), focused on Midnight 12.0 Secret Value restricted-context hardening and legacy defect cleanup.

Highlights:

- **Version-check false-positive fix** — original Cell (`r275.10-beta`) and CellD (`1.0.3`) share the `CELL_VERSION` comm prefix with incompatible version formats; `%d+` extraction caused a false "new version" alert. Now only CellD semantic versions (`x.y.z`, compared level-by-level) are checked, and the download link points to the CellD repo
- **Comm receive-side restricted-context guard** — `CELL_SEND`/`CELL_SEND_PROG`/`CELL_REQ` now gated by `IsCommRestricted` (combat / Mythic+ / PvP)
- **BuffTracker syntax restored** — `local fl function` syntax error fixed; raid buff checking works again
- **Import/Export hardening** — 5 ImportExport modules validate `type(data)=="table"` on deserialize; DoImport guards missing keys
- **CellD media paths fixed** — `AddOns\Cell\Media` → `AddOns\CellD\Media` (29 files), including 12 perl-rewrites that lost backslashes
- **Comm/Marks type guards** — `CELL_MARKS` receive-side validates numeric/string payloads
- **Secret Value guards added** — NPCFrame secret GUID compare, `IsSpellReady` secret/nil safe-fail, `GetSpellTooltipInfo` nil protection, TargetCounter `GetPoint` nil/secret guard
- **Drag/index/out-of-range fixes** — RaidDebuffs drag `GetParent()` nil, ColorPicker alpha parent, BlockColors index, circled out-of-range, indicator rename collision
- **Behavior fixes** — DeathReport `limit=0` (report all), Revise no unconditional override, soulstone detection, `allCooldowns` dedup
- **Midnight adaptation** — SR/DR & DeathReport skip CLEU registration on Midnight (event removed in 12.0), global leak sweep, zhCN 7 missing keys

---

## v1.0.3 — 2026-06-29

### 中文

本次发布将插件版本同步更新为 1.0.3，并以当前本地代码基线为准进行发布整理。

主要内容：
- 将 AddOn 版本号更新为 1.0.3
- 保留 /celld 作为当前支持的命令入口，清理 /cell 兼容别名
- 继续以当前 Midnight 12.0 维护状态为基础进行发布

### English

This release bumps the addon version to 1.0.3 and publishes the current local codebase state.

Highlights:
- Bump the addon version to 1.0.3
- Keep /celld as the supported command entrypoint and remove the /cell alias
- Publish the current Midnight 12.0 maintenance baseline

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
