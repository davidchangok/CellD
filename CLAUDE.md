# CellD — AI 协作记忆入口

CellD 是从 [enderneko/Cell](https://github.com/enderneko/Cell) 分叉的魔兽世界团队框架插件，专用于 **12.x (Midnight) 正式服**，作者 David W Zhang。

## 📚 必读文档（按需加载，不要一次全读）

| 文件 | 内容 | 何时读 |
|------|------|--------|
| `STATUS.md` | **开发状态总账**：已完成工作、12.1 适配完整记录、已知限制、待办 | 每次开始工作前 |
| `ARCHITECTURE.md` | 全代码功能架构图（加载链/21种指示器/信号/数据流） | 涉及新模块/架构问题时 |
| `api_reference.md` | CellD 内部 API 参考 | 写代码时查函数 |
| `CHANGELOG.md` | v1.0.0 → v1.0.5 发布说明 | 发布时 |
| `README.md` / `README_EN.md` | 用户文档 + Midnight Secret Value 安全架构 | 文档更新时 |

## 🔴 当前焦点：12.1 (Curse of Ula'tek) 受限环境适配

**核心事实（2026-08 实测 + 官方文档确认，不要推翻重来）：**

1. 12.1 战斗中友方单位光环对插件**完全不可读**（蓝贴 *"Addons and Auras in Curse of Ula'tek"*）
   - `GetUnitAuraBySpellID` → nil；`GetUnitAuraInstanceIDs`/`GetAuraDataByIndex` → 抛错
   - 治疗 HoT/buff 被移出 "never secret" 名单（官方名单见 `Utilities/SecretAuraTracker.lua` 的 `officialSecretSpells`）
   - 官方 `AuraContainer` 数据源同样受限（已验证，v1.1.0 已 revert）
   - `UnitTarget`/`UNIT_SPELLCAST_TARGETED` 已移除；`UnitName`/`UnitIsUnit` 战斗中返回 secret
   - `GetRestrictedActionStatus` 12.1 失效（恒 false），改用 `UnitAffectingCombat`
2. **唯一合法通道 = 施放事件追踪**（`UNIT_SPELLCAST_SUCCEEDED`，第一方信息）
   - 实现：`Utilities/SecretAuraTracker.lua`（v1.2.0）
   - 目标识别：`Cell.vars.secretAuraHoveredUnit`（UnitButton.lua 的 OnEnter/OnLeave hook）+ GetMouseFocus
   - 显示：复用 `I.CreateAura_Icons` 渲染（Built-in.lua 的 `I.CreateCombatBuffTracker`），视觉与脱战 Healers 指示器一致
   - 时长：脱战扫描自学习（天赋差异自动适配）+ 硬编码兜底
   - 追踪列表：官方 secret 名单 + `IsSpellKnown` 过滤（自动读取角色技能表）+ Healers 布局 + externals
3. **已知边界**（暴雪设计，无法绕过）：键盘施法（鼠标不悬停）无法识别目标；无法感知驱散/提前结束；队友施放的增益不可见

## 🛠 工作约定

- 客户端仅 12.1+（`CellD.toc` = `Interface: 120100`），无需怀旧服兼容
- 12.1 战斗代码必须 `pcall` 包裹所有 `C_UnitAuras` 查询 + `F.IsSecretValue` 前置检查（secret 值不能比较/做表键）
- 修改后验证：本仓库无 Lua 解释器，用 Python 检查脚本（跳过 `--` 注释和字符串）做括号平衡检查
- 提交信息用中文，遵循现有格式（`feat:`/`fix:`/`docs:`/`chore:`）
- 网络受限环境：`curl --ssl-no-revoke` 可访问外网；研究资料放 `.research/`（已 gitignore）
- 用户主要使用场景：奶骑 + 所有治疗职业，点击/悬停框架施法

## ⚠️ 教训（避免重复踩坑）

- 12.1 战斗中不要在事件回调里比较 `UnitName`/`UnitIsUnit` 的返回值（secret 值比较直接 Lua error，且 `IsSecretValue` 检查必须放在 `==` 比较**之前**）
- 追踪列表不要用一次性构建 + 缓存标记（布局初始化时序会导致列表永久缺失）；每次施放重建 + 保留时长缓存
- 战斗中层数（stack）不可知——不要显示层数，避免误导

## 📦 发布流程

```powershell
# 打包发布 zip（用 git ls-files 列表，排除 .gitignore）
git -C . ls-files --cached | Where-Object { $_ -ne '.gitignore' }
# 复制到 TEMP 目录结构 CellD\ 后 Compress-Archive
# 版本号更新: CellD.toc + CHANGELOG.md + release_body.md
```
