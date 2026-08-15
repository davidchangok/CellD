## CellD v1.2.0

**12.1 (Curse of Ula'tek) 受限环境全面适配**——战斗中友方单位光环对插件完全不可读，新增施放事件追踪，使奶骑美德道标等增益在战斗中与脱战显示完全一致。

### 主要变更

- **Interface 升级至 120100** — 仅支持 12.1 正式服
- **新增 SecretAuraTracker** — 12.1 战斗中唯一合法通道：监听 `UNIT_SPELLCAST_SUCCEEDED` 施放事件，在自己施放增益后于目标框架显示图标（技能/驱散/Externals 全覆盖）
- **战斗显示与脱战完全一致** — 复用 `I.CreateAura_Icons` 渲染（同 Healers 配置：大小/位置/字体/布局），槽管理支持多增益并存与到期清理
- **追踪列表智能过滤** — 官方 secret 名单 + `IsSpellKnown` 过滤（自动读取当前角色技能表，职业/天赋切换自动适配）+ Healers 布局 + externals
- **目标识别** — OnEnter/OnLeave 悬停记录 + GetMouseFocus（点击/悬停施法精确显示目标框架）
- **时长自学习** — 脱战扫描队伍成员光环缓存真实 duration（天赋差异自动适配），BuildTrackedList 重建保留缓存
- **UNIT_AURA secret 修复** — `isFullUpdate` secret boolean 前置判定 + `ForEachAura` `IsAuraRestricted` 前置跳过 + pcall 兜底，杜绝 "Auras cannot be accessed when secret" 刷屏

### 已知限制（12.1 暴雪设计，无法绕过）

- 键盘施法（鼠标不悬停）无法识别目标；队友施放的增益不可见；无法感知驱散/提前结束
- 战斗中无法读取真实剩余时间与层数（时长来自脱战自学习缓存或硬编码兜底；层数固定不显示避免误导）

仅支持 WoW 12.1 Midnight 正式服。下载：[https://github.com/davidchangok/CellD/releases](https://github.com/davidchangok/CellD/releases)
