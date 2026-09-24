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
   - 官方 `AuraContainer` 引擎**能渲染**战斗 secret 光环（2026-08-18 实测：`HELPFUL` filter + includeSpellIDs 战斗中显示激流/大地之盾），但**无法集成到 CellD secure 按钮**（鼠标/显隐被引擎 C++ 侧控制，三次尝试 v1.3.0/1.3.1/1.3.2 全部回滚）
   - `UnitTarget`/`UNIT_SPELLCAST_TARGETED` 已移除；`UnitName`/`UnitIsUnit` 战斗中返回 secret
   - `GetRestrictedActionStatus` 12.1 失效（恒 false），改用 `UnitAffectingCombat`
2. **CellD 采用通道 = 施放事件追踪**（`UNIT_SPELLCAST_SUCCEEDED`，第一方信息；AuraContainer 引擎虽能显示 secret 光环但架构不兼容无法集成，施放追踪是 CellD 可用方案）
   - 实现：`Utilities/SecretAuraTracker.lua`（v1.2.0）
   - 目标识别：`Cell.vars.secretAuraHoveredUnit`（UnitButton.lua 的 OnEnter/OnLeave hook）+ GetMouseFocus
   - 显示：复用 `I.CreateAura_Icons` 渲染（Built-in.lua 的 `I.CreateCombatBuffTracker`），视觉与脱战 Healers 指示器一致
   - 时长：脱战扫描自学习（天赋差异自动适配）+ 硬编码兜底
   - 追踪列表：官方 secret 名单 + `IsSpellKnown` 过滤（自动读取角色技能表）+ Healers 布局 + externals
3. **已知边界**（暴雪设计，无法绕过）：键盘施法（鼠标不悬停）无法识别目标；无法感知驱散/提前结束；队友施放的增益不可见
4. **2026-08 新学习（用户已实测）**：VuhDo 3.214 已用 AuraContainer + `includeSpellIDs` 作为 12.1 光环主通道；用户实测 `/celld testaura` 的 AuraContainer 战斗时全部显示，证明“非 secure 子 Frame 挂载 + 禁用鼠标”可避免 CellD 之前的集成冲突。**硬性约束：不得改变 grid 外观，鼠标/悬停施法必须保持可用。** 已新增 `Utilities/AuraContainerOverlay.lua`，包含 buff/debuff/驱散染色/防御技能四类 overlay；**2026-08-20 功能线收尾（已提交推送）**：驱散染色 = DF 同款渐变载体（`Media/Gradients/DF_Gradient_V` + dim host 帧 opacity）+ **`customDispelColorCurve`（DB2 类型 ID，secret 安全；`customDispelColorMap` 按 secret dispelName 查表战斗中永远 no-op，是历史"颜色不对"根因）** + 填充纹理锚定（跟随真实血量）；血条 = 上游 r279 secret 直喂勿改；追踪列表职业化（奶德不显示 200025，移除全量兜底）；**参考实现首选 DandersFrames `Features/Dispel.lua`/`Frames/Border.lua:843`（用户实测"很好"）**，其次 BigWigs/Grid2/VuhDo/原版 Cell（源码均本地）。调试快照见 `STATUS.md` 第十/十一节。

5. **2026-08-27 驱散染色修复完成（用户实测 Grid 已正常上色）**：根因链 = ①`customDispelColorCurve` 与 `customDispelColorMap` **同时传递** —— 引擎无条件让 curve 覆盖 map 且不检查结果，无效曲线会顶掉正确的 map，**必须严格二选一**（VuhDo `VuhDoAuraContainer.lua` 857/885/994/1050/1259 五处实证从不两者同传）；②曲线原用 `CreateColor` 构建，而本插件 `Indicator_Defaults.lua:277` 早已注明 "Blizzard native ColorMixin objects work correctly as dsCurve AddPoint arguments where Lua CreateColor() objects do not" → 改用 `DEBUFF_TYPE_*_COLOR`，六个全局缺任一则整条曲线放弃交 map 兜底（曲线"有洞"比没有更糟）；③调试侧 `CanBeAccessedInContext`（受限环境**恒 false**）被误用作 `IsShown` 读取门控，导致"读不到"被误判为"没显示"，掩盖真因。
   **🔴 12.1 战斗 API 可见性矩阵（实测，排查必读）**：`container` 的 `IsShown`/`IsEnabled`/`GetUnit`/`GetAuraGroupFrame*` 战斗中**均可正常调用**；`container:GetSize()` 返回 **secret 值**（可调用，值受限）；而 **AuraButton/子 frame 的 `IsShown` 与 `CanBeAccessedInContext` 战斗中一律 FORBIDDEN**（调用本身被拒）。→ **限制针对 AuraButton 而非 AuraContainer**；**"图标是否真的显示"战斗中插件侧不可知，`active` 计数在战斗内永远不可信，只能靠肉眼确认**（历史上已因此浪费多轮）。`GetSize()` 返回 secret 本身即"引擎已接管"的有效信号。完整矩阵与因果链见 `HANDOFF.md` 第十一/十二节。
   **secret 铁律**：`IsShown` 等 API 战斗中返回 **secret boolean**，`ok and shown or nil` 这类写法会报 "attempt to perform boolean test on ... secret boolean" —— 必须先 `IsSecretValue` 判定并过滤，secret 值降级为字符串仅作展示。

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
- **AuraContainer 不要集成到 SecureUnitButton 本身**（2026-08-18 三次尝试全部回滚）：引擎托管对象与 SecureUnitButtonTemplate 架构级冲突，鼠标/悬停/点击施法失效、显隐不受 Lua 控制；但 VuhDo 3.214 证明：**作为普通子 Frame（如 `$parentOlHost`）或独立容器挂载、并禁用鼠标事件，是可以与 secure 按钮共存的**。详细分析见 `STATUS.md` 第九节

## 📦 发布流程

```powershell
# 打包发布 zip（用 git ls-files 列表，排除 .gitignore）
git -C . ls-files --cached | Where-Object { $_ -ne '.gitignore' }
# 复制到 TEMP 目录结构 CellD\ 后 Compress-Archive
# 版本号更新: CellD.toc + CHANGELOG.md + release_body.md
```

## 📤 推送流程（GitHub: davidchangok/CellD, main）

**日常（本机终端，推荐）：**
```powershell
git -C 'E:\Game\World of Warcraft\_retail_\Interface\AddOns\CellD' push origin main
# 本机凭据管理器(Windows 凭据/GCM)正常弹窗验证即可
```

**AI 沙箱会话内推送（本会话实测跑通，2026-08-20）：**
- 沙箱会拦截 git-for-windows 的 `sh.exe` 子进程（Win32 error 5: 信号管道被拒）——
  **任何触发凭据助手/askpass/ssh 传输的 push 都会失败**（`git push`/`credential fill`/SSH 均实测失败）
- ✅ **可行路径 = 令牌嵌入远端 URL + 空 helper**（git 的 libcurl 直传，零子进程）：
  ```powershell
  $git='D:\Program Files\Git\cmd\git.exe'
  # 1. 用户提供 GitHub PAT(classic, 勾 repo) —— 浏览器: 头像→Settings→Developer settings
  #    →Personal access tokens→Tokens (classic)→Generate new token(勾 repo)→复制 ghp_...
  $git -C <repo> remote set-url origin "https://davidchangok:<PAT>@github.com/davidchangok/CellD.git"   # 需沙箱升级(danger-full-access, .git/config 写入被拒时)
  $env:GIT_TERMINAL_PROMPT=0
  $git -C <repo> -c 'credential.helper=' push origin main
  # 2. 推送后立即清 URL + 同步本地追踪 ref(均为 .git 写入, 同样需升级):
  $git -C <repo> update-ref refs/remotes/origin/main main
  $git -C <repo> remote set-url origin 'https://github.com/davidchangok/CellD.git'
  # 3. 提醒用户到 GitHub 撤销该 PAT
  ```
- 注意：`.git/config`/`~/.git-credentials` 写入受沙箱 workspace-write 限制，需 `sandbox_permissions` 升级；
  推送成功但追踪 ref 更新失败=远端已好，本地补 `update-ref` 即可
- 验证：`git ls-remote https://github.com/davidchangok/CellD.git HEAD`（无 helper 时可直接执行，零子进程）

**重装系统后从零推送：**
1. 装 Git for Windows（本机在 `D:\Program Files\Git`）→ 配置身份：
   `git config --global user.name "davidchangok"` / `user.email`(GitHub 账户邮箱)
2. 克隆/进入仓库，`git pull`（HTTPS 会提示登录——浏览器登录 GitHub 后凭据管理器自动保存）
3. 之后 `git push origin main` 即可；AI 沙箱推送则走上面的 PAT 路径
