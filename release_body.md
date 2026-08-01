## CellD v1.0.5

**Comm 通讯前缀与原版 Cell 完全隔离**——CellD 不再与原版 Cell 共享任何 AddOn 通讯频道。

### 主要变更

- **11 个 comm 前缀 `CELL_` → `CELLD_`** — 版本广播（`CELLD_VERSION`）、标记同步（`CELLD_MARKS`）、优先级（`CELLD_CPRIO`/`CELLD_PRIO`）、配置传输（`CELLD_SEND`/`CELLD_SEND_PROG`/`CELLD_REQ`）、技能/驱散请求（`CELLD_REQ_S`/`CELLD_REQ_D`）、昵称（`CELLD_NIC`/`CELLD_CNIC`）
- **游戏内宏文本同步** — 技能/驱散请求宏更新为 `CELLD_REQ_S`/`CELLD_REQ_D`，请在选项面板重新复制宏
- **保留不变** — `CELL_NOTIFY`（WeakAuras 事件名）与 `CELL_NICKTAG_ENABLED`（代码片段常量）不受影响

### 注意

隔离后 CellD 与原版 Cell、以及新旧 CellD 版本之间不再互通（标记/昵称/请求等自动同步仅在同版本 CellD 之间生效）。

仅支持 WoW 12.0 Midnight 正式服。下载：[https://github.com/davidchangok/CellD/releases](https://github.com/davidchangok/CellD/releases)
