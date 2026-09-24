# CellD 上下文转移包（按实际代码校准版）

> **生成时间**: 2026-08-27
> **生成方式**: 逐文件读取工作区实际代码 + `git log`/`git status`/`git diff` 核对，
> **不采信任何文档或旧转移包的代码描述**。
> **上一版转移包的错误已在本文件末尾「勘误」列出。**

---

## 一、项目基本信息

| 项 | 值 |
|---|---|
| 插件 | CellD（从 [enderneko/Cell](https://github.com/enderneko/Cell) r277-beta 分叉） |
| 路径 | `E:\Game\World of Warcraft\_retail_\Interface\AddOns\CellD` |
| 仓库 | GitHub `davidchangok/CellD`，分支 `main` |
| 客户端 | 12.1 (Curse of Ula'tek)，`CellD.toc` = `Interface: 120100` |
| 作者 | David W Zhang |
| 用途 | 奶骑 + 全治疗职业，点击/悬停框架施法 |

### 硬性约束（用户拍板，违反即回滚）
1. **不得改变 CellD grid 外观**
2. **鼠标必须可用；悬停 grid 施法是核心功能**
3. AuraContainer / AuraButton 必须以 `SetMouseClickEnabled(false)` / `SetMouseMotionEnabled(false)` / `EnableMouse(false)` 全穿透

---

## 二、⚠️ 最重要的三个事实（开工前必读）

### 事实 1：git 状态 —— 工作区干净，功能线已收尾
```
HEAD = edc5831 "docs: 记忆终版(2026-08-20 功能线收尾)"   2026-08-27 18:09
git status --short  →  仅 " M CLAUDE.md"（未提交的推送流程文档）
git diff --stat HEAD →  CLAUDE.md | 34 +++
```
`Utilities/AuraContainerOverlay.lua` 最后一次改动是 **`a6e65cf`**，此后**无任何改动**。

### 事实 2：🔴 STATUS.md 第十节描述的 v5.4/v5.6 方案**从未落地到代码**
`STATUS.md` 第 455–467 行写着「v5.4 染色糊住血条 alpha→0.30」「v5.6 边框式染色：4 条 2px 边 + 底部 3px 信号条」「血量空缺区染色 + 满血退化为末端 4px 信号条（`DISPEL_MARKER_WIDTH`）」等。

**实测核对：这些标识符在代码里完全不存在。**

```
grep "DISPEL_MARKER_WIDTH|healthBarLoss|border|Border" AuraContainerOverlay.lua
→ 仅 4 处命中，全部是注释里提到的历史版本名(v1)或 DandersFrames 文件路径引用
```

代码里实际只有：`AnchorDispelTex`（锚定血条填充纹理）+ `DF_Gradient_V` 整格渐变 + `DISPEL_DYE_ALPHA = 1.0`。

> **结论：STATUS.md 第十节是「计划/设想」而非「已实现状态」，不可当作代码描述使用。**
> 这是上一版转移包出现偏差的根本原因 —— 它把文档当成了代码。

### 事实 3：STATUS.md 内部自相矛盾，至少三处结论被后续推翻
| 位置 | 说法 | 实际 |
|---|---|---|
| 第 245 行 | 「AuraContainer 战斗中**不显示** secret 光环」 | 第 315 行「用户实测**能显示**」推翻 |
| 第 252 行 | 「12.1 显示被 secret 化的 buff 在暴雪设计上**不可能**」 | 同上，已被推翻 |
| 第 369/416/426 行 | dispel filter = `HARMFUL\|RAID_PLAYER_DISPELLABLE` | 代码实际是裸 `"HARMFUL"` |
| 第 43 行 | 「放弃 `GetAuraDispelTypeColor` C API（持续返回 nil）」 | 第 168 行「已通过 dsCurve 方案**重新启用**」 |

**读 STATUS.md 时必须注意：第一~六节是 12.0 时代记录，第七节含被推翻的旧结论，第十节是未落地的计划。**

---

## 三、当前代码真实状态（AuraContainerOverlay.lua，968 行）

### 3.1 四类 overlay 实际参数

| 键 | 创建函数 | 实际调用 |
|---|---|---|
| `buffs` | `CreateBuffOverlay` | `AddAuraGroup("secret", "HELPFUL", {maxFrameCount=5, candidateFilters={includeSpellIDs=BuildTrackedIDs()}, ...})` |
| `debuffs` | `CreateDebuffOverlay` | `AddAuraGroup("debuffs", "HARMFUL", {maxFrameCount=5, candidateFilters=nil, layout element 28×28, spacing 2})` |
| `dispels` | `CreateDispelOverlay` | `AddAuraSlot("dispels", "HARMFUL", {...})` ← 返回值存入 `dispelsButton` |
| `defensives` | `CreateDefensiveOverlay` | `AddAuraGroup("defensives", "HELPFUL", {candidateFilters={includeSpellIDs=BuildDefensiveIDs()}})` |

### 3.2 驱散染色（当前唯一未确认有效的功能）—— 代码实况

```lua
-- L488: 裸 HARMFUL（不是转移包说的 HARMFUL|DISPELLABLE）
local slotButton = container:AddAuraSlot("dispels", "HARMFUL", {
    sortMethod = AuraContainerSortMethod.ExpirationOnly,
    sortDirection = AuraContainerSortDirection.Normal,
    initializeFrame = function(auraButton)
        auraButton:ClearAllPoints()
        auraButton:SetAllPoints(button)
        auraButton:SetFrameLevel(auraButton:GetParent():GetFrameLevel() + 1)

        local dim = CreateFrame("Frame", nil, auraButton)   -- dim host 承载 alpha
        dim:SetAllPoints(auraButton)
        dim:SetFrameLevel(auraButton:GetFrameLevel() + 1)

        local tex = dim:CreateTexture(nil, "ARTWORK", nil, 2)
        AnchorDispelTex(tex, button)                        -- 锚定 healthBar:GetStatusBarTexture()
        auraButton._dispelTex = tex                         -- B.SetOrientation hook 重锚用
        tex:SetTexture("Interface\\AddOns\\CellD\\Media\\Gradients\\DF_Gradient_V")
        tex:SetBlendMode("BLEND")
        dim:SetAlpha(DISPEL_DYE_ALPHA)                      -- = 1.0

        auraButton:AddDispelTypeTexture(tex, {
            style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
            showWhenHarmful = true,
            showWhenHelpful = false,
            showWithoutDispelType = false,
            customDispelColorCurve = BuildDispelColorCurve(),   -- ← 曲线
            customDispelColorMap   = BuildDispelColorMap(),     -- ← 同时传了 map
        })
        -- 鼠标三连
    end,
})
containers[button].dispels = container
containers[button].dispelsButton = slotButton   -- L535 已保存 ✅
```

**`BuildDispelColorCurve`（L429-448）实际实现**：
```lua
curve = C_CurveUtil.CreateColorCurve()
curve:SetType(Enum.LuaCurveType.Linear)
curve:AddPoint(0,  CreateColor(0,0,0,0))          -- 锚定 None
-- Magic=1 Curse=2 Disease=3 Poison=4 Bleed=11（硬编码 DB2 ID）
curve:AddPoint(_dispelDB2IDs[t], CreateColor(r,g,b,1))
curve:AddPoint(9, Bleed 色)                        -- Enrage
```

### 3.3 其他已实现机制
- `AnchorDispelTex(tex, button)`：`tex:SetAllPoints(bar:GetStatusBarTexture())`，**绝不 `SetAllPoints(healthBar)`**（否则空区被罩成近均匀色）
- `HideLegacyDispels()` + `HookLegacyDispels()`：`hooksecurefunc(dispels, "SetDispels")` 里 Hide glow/highlight，防 legacy 双层
- `SyncDispelsOutOfCombat()`：脱战常驻刷新（12.1 脱战后 legacy 刷新不恢复）
- `_refreshTimer` / `refreshFrame`：战斗中每 0.5s `UpdateAllAuras()` 兜底
- `ShowAll` / `HideAll`：`HideAll` 双管 `SetEnabled(false)` + `SetShown(false)`
- `hooksecurefunc(Cell.bFuncs, "SetOrientation")`：血条方向切换后重锚纹理
- **已注释掉**：`Cell.RegisterCallback("UpdateLayout")`（L944-955）、加载时自动 `ShowAll()`（L960-968）

### 3.4 调试命令（Core.lua L1097-1124 实现）
```
/celld testaura <unit>        → U.DebugInfoSync（强制创建+同步再打印）
/celld testaura info <unit>   → U.DebugAuraOverlay（只打印）
/celld testaura off           → 隐藏测试容器
```
`U.DebugAuraOverlay` 输出格式（`[dispels]` 分支 L742-758）：
`shown= unit= enabled= size=WxH slot(acc=.. shown=..)`
`[其他]` 分支：`frames=N active=N f1(acc=.. shown=..) ...`
secret 值经 `Str()` 安全转字符串（避免 `invalid value (secret)`）。

---

## 四、📚 参考插件实际代码学习（本次逐行阅读的成果）

### 4.1 DandersFrames —— **首要参考，注释含全部踩坑史**

**文件**：`DandersFrames\Features\Dispel.lua`（3150 行）、`Frames\Border.lua`（3523 行）、`Frames\AuraContainer.lua`（9970 行）

#### 🔴 铁律 1：`customDispelColorCurve` 是唯一的 secret 安全染色通道
`Frames/Border.lua:1829-1844` 原始注释（读自 Live 客户端源码 `Blizzard_CustomAuraButton.lua` build 69382）：
- **map 是裸 Lua 表索引**：`colorMap[auraData.dispelName or "None"]`
  - secret 的 `dispelName` 为 **truthy** → `or "None"` **永不触发** → 匹配不到任何 key → 返回 nil
  - 颜色应用是 `if color then SetVertexColor(...) end`，**没有 else** → 保留 style 步骤画的颜色
  - 对白色打底的 style，这就是"**整个框变白**"的现场报告（Choco/Ortemis, 2026-08-19）
- **curve 在 C 侧解析**：`GetAuraDispelTypeColor(unit, auraInstanceID, curve)` —— 无表索引、不读名字，aura 处于 secret 时照样工作

#### 🔴 铁律 2：**曲线有洞比没有曲线更糟**
`Frames/Border.lua:857-863`：
> 引擎**无条件**让 curve 覆盖 map —— `if options.customDispelColorCurve then color = GetAuraDispelTypeColor(...) end`，**不检查 map 结果**。
> 所以**缺 0 点的 curve 比没有 curve 更糟**：它丢弃了本来正确的 map 查询，代之以 curve 外推的结果。

`DF:GetDispelColorCurve()` 因此强制 `if not haveZero then table.insert(points, 1, {0, ...}) end`（L891-896）。

#### 🔴 铁律 3：无 Enum 表，必须硬编码 DB2 ID
`Frames/Border.lua:816-837`：
> 枚举扫描**从未找到过**（68824 探到 nil，69382 live 再次确认 `/df debug dispelids` 输出 "no Enum table with Magic/Curse/... found"）。
> 回退值：`{None=0, Magic=1, Curse=2, Disease=3, Poison=4, Enrage=9, Bleed=11}`（SpellDispelType DB2 id）
> **⚠ 扫描仍优先** —— 若暴雪将来真发枚举，以枚举为准。

#### 🔴 铁律 4：`AddDispelTypeTexture` **追加**，`SetAuraBorder` **替换**
`Features/Dispel.lua:1751-1756`：
> `SetAuraBorder` 是**废弃别名**（`Blizzard_CustomAuraButton.lua`: "will be removed after 12.1"），内部做 `ClearDispelTypeTextures() + AddDispelTypeTexture()` —— 即**替换**整个纹理列表，这就是"一个槽只能带一个可染色区域"的根本原因。
> `AddDispelTypeTexture` **追加**，所以一个 button 能带多个染色载体。
> 多载体绑定顺序：**只清一次，然后逐个 append**（每个载体单独 clear 会只剩最后一个）。

#### 🔴 铁律 5：alpha 必须放在 dim host 上，不能放纹理上
`Features/Dispel.lua:1775-1779`：
> `AddDispelTypeTexture` 在绑定时取走纹理的 `SecretAspect.Alpha` 和 `.Shown`，**之后两者都不再归我们写**。
> dim host 是普通 Frame，永不受限，是唯一还能对「客户端已锁定的槽子树」生效的杠杆。

#### 🔴 铁律 6：未绑定的载体渲染为**白色**
`Features/Dispel.lua:1764-1773`：
> 载体**出生即 alpha 0**，直到 `AddDispelTypeTexture` 接受它才"揭幕"。
> 因为在创建与绑定之间**没有任何东西给它上色** → 以默认顶点色（**白**）渲染，覆盖它盖住的一切。对渐变载体就是整个框。
> 历史 bug：出生就赋用户 alpha（因为出生通常发生在战斗中，而 style pass 只在脱战） → 让**未绑定的载体最大化可见**。

#### 🔴 铁律 7：必须 `pcall` 包裹绑定 + 失败分支要压暗
`Features/Dispel.lua:1878-1889`：只有成功分支才 `RevealDispelCarriers`；失败分支必须重新压暗（因为 `ClearDispelTypeTextures` 已在 pcall 内跑过 = cleared-but-unbound = 白色环）。

#### 🔴 铁律 8：重试门控的 `nil ~= nil` 陷阱
`Features/Dispel.lua:30-46`：
> `dispelCurveGen` 原本只由 `InvalidateDispelColorCurve` 创建，而它唯一调用者是选项页回调和调试命令 → **没人改过颜色时它整场为 nil** → 重试门 `btn._dfDispelCurveGen ~= DF.dispelCurveGen` 恒为 `nil ~= nil` = **false** → 绑定失败的载体整场不再重试，同时保持白色顶点色显示在每个可驱散 debuff 上。
> 修复：`DF.dispelCurveGen = 0` 在加载时播种。
> **诊断悖论**：`/df debug dispelids` 会调用 invalidator 从而 bump 计数器 → **跑一次诊断就"治好"了这个 bug**。

#### 🟢 可用资产
`Features/Dispel.lua:23-28` 四个渐变纹理（CellD 已有前两个）：
```lua
TOP    = "DF_Gradient_V"      -- 上实心下渐隐
BOTTOM = "DF_Gradient_V_Rev"  -- 下实心上渐隐
LEFT   = "DF_Gradient_H"      -- ← CellD 没有
RIGHT  = "DF_Gradient_H_Rev"  -- ← CellD 没有
```
> `Dispel.lua:20-22` 说明为何用预烘焙纹理：**`WHITE8x8 + SetGradient + CreateColor` 在 secret 值上会报错**。

### 4.2 VuhDo —— **曲线与 map 严格二选一**

`VuhDo\VuhDoAuraContainer.lua` 里同一份 `sAuraBorderOptions` 表被反复改写，**每处都是二选一**：

| 行 | 场景 | 设置 |
|---|---|---|
| 857-858 | 边框边条 | `curve = nil`；`map = VUHDO_getDispelTypeColorMap(...)` |
| 885 | 驱散图标 | `curve = nil` |
| 994 | 图标驱散边框 | `curve = VUHDO_getDispelTypeBorderCurve()` |
| 1050 | 渐变 | `curve = nil` |
| 1259/1265 | 不透明填充 | `curve = 变体构建函数(bright, opacity)` |

**关键观察：VuhDo 从不在同一次 `AddDispelTypeTexture` 里同时给 curve 和 map。**
且 VuhDo 支持 `bright`/`opacity` 变体缓存（`VUHDO_getOrBuildDispelBrightOpacityVariant`，`VuhDoBouquets.lua:629`）。

**filter 用法**（`VuhDoDefaults.lua` / `VuhDoAuraContainerOverlays.lua:1449`）：
- `"HARMFUL|DISPELLABLE"`（容器 overlay 默认）
- `"HARMFUL|RAID_PLAYER_DISPELLABLE"`（`VuhDoDefaults.lua:3234`）
- `"HARMFUL|CROWD_CONTROL"`、`"HARMFUL|PLAYER"`

> 注意：CellD 代码注释里 v4 记录「slot **忽略** `includeSpellIDs`」，而 VuhDo 的 `includeDispelTypes` 是**键值集合**（`{Magic=true,...}`）不是数组 —— CellD 已确认这一点（第十节 v4.2）。

### 4.3 BigWigs
`BigWigs_Plugins\Auras.lua`：
- L2308 `aura:AddDispelTypeTexture(borderRegion, borderOptions)`
- L2323 `aura:AddDispelTypeTexture(aura.dispelIcon, dispelIconOptions)`
- L2390 `auraContainer:AddAuraGroup("debuffs", "HARMFUL", {...})`
- L2489 自定义 `AddDispelTypeTexture` 包装

### 4.4 Grid2
- `modules/StatusAuras.lua` → `filter.borderOptions = CopyTable(Grid2.DispelBorderDefaults, {customDispelColorMap=colorMap})`
- `modules/IndicatorSquare.lua` → `button:ClearAuraBorder(); button:SetAuraBorder(tex, filter.borderOptions)`
- `GridIndicatorAuras.lua` → `container:AddAuraSlot(slotKey, filter.filter, {...})`
- `GridDefaults.lua:254`：`includeDispelTypes` 的 **set 格式**来源
- 默认 filter：`'HARMFUL|RAID'`
- **Grid2 走的是 map 路线（非 curve）** —— 与 DandersFrames/VuhDo 不同

---

## 五、🎯 下一步待办（按优先级，含依据）

### P0-A：曲线与 map 二选一 —— **最可能的染色失败根因**
**依据**：铁律 2 —— 引擎无条件让 curve 覆盖 map。CellD 同时传两者，若 curve 在某类型 ID 上有洞/或 `C_CurveUtil` 行为与预期不符，会**丢弃正确的 map 结果**。
**动作**：参照 VuhDo 的严格二选一，`AddDispelTypeTexture` 只传 `customDispelColorCurve`（战斗 secret 环境），map 仅在曲线不可用时传。
```lua
-- 建议改法（症状：仍无颜色 → 试纯 map；颜色全白 → 曲线有洞）
local curve = BuildDispelColorCurve()
auraButton:AddDispelTypeTexture(tex, {
    style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
    showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = false,
    customDispelColorCurve = curve,
    customDispelColorMap   = curve and nil or BuildDispelColorMap(),
})
```

### P0-B：确认 `C_CurveUtil.CreateColorCurve` 返回值与 API 名
**依据**：`Border.lua:899-901` —— **`CreateColorCurve` 不接构造参数**（传表会被忽略 → 得到**空曲线 → 求值为白色**）；必须 `SetType` + `AddPoint` 构建。
CellD 现状**恰好是对的**（`CreateColorCurve()` 空参 + `SetType` + `AddPoint`）✅。
**待查**：CellD 的 `BuildDispelColorCurve` 在 `C_CurveUtil` 缺失时返回 `nil`（L431），此时应回退 map —— 确认 fallback 路径真的生效。

### P1：`dispelsButton` 是否真的被创建并绑定
**依据**：CellD 已存 `containers[button].dispelsButton`（L535）✅，但 `DebugAuraOverlay` 的 `active` 统计因 `CanBeAccessedInContext` 在受限环境恒 false 而不可用。
**动作**：参照 DandersFrames 的 `btn._dfDispelBindRes` 模式 —— **把绑定结果戳在 button 上**（`pcall` 包住 `AddDispelTypeTexture`，成功/失败都记录），而不是只依赖 `CanBeAccessedInContext`。
> DandersFrames 的同类教训（`Dispel.lua:1801-1812`）：**结果必须记在 button 上，不能只记在全局** —— 全局按 slot key 索引会被每一帧的 "main" 槽互相覆盖，导致"5 个没有任何载体的帧打印 bind=ok x3"。

### P2：补 `DF_Gradient_H` / `DF_Gradient_H_Rev`
**依据**：`Dispel.lua:26-27`。CellD 只有 V 版（`glob` 确认：`DF_Gradient_V.tga`、`DF_Gradient_V_Rev.tga`）。做边框式染色（上下左右四条边）时需要 H 版。

### P3：给曲线加**重试门控**（若引入缓存）
若给 curve 加缓存（CellD 已有 `_dispelColorCurveCache`，L428），需参照 DandersFrames 的 generation counter 模式，并**在加载时播种 0**（铁律 8：`nil ~= nil` 陷阱）。

### P4：未落地功能（若要实现，需从 STATUS.md 第十节取设计，但**那是文档不是代码**）
- 边框式染色（4×2px 边 + 底部 3px 条）
- 血量空缺区染色 + 满血退化为末端 4px 信号条
- bubble alpha 可配置化
实现前**先与用户确认**要哪种形态。

---

## 六、⚠️ 已知边界与陷阱（实测确认）

| 项 | 说明 |
|---|---|
| `/reload` 恰逢战斗中 | 本场无 overlay（战斗锁禁创建），脱战后恢复 |
| 多 debuff 共存 | 引擎单槽取「最先到期」的 aura 类型上色（ExpirationOnly 排序） |
| 会话中改 `debuffTypeColor` | 需 `/reload`（CellDB 色表在 `initializeFrame` 时读取） |
| `CanBeAccessedInContext` | 受限环境**恒 false**，不可作为绑定判据 |
| `icon:GetTexture()` | 返回 **secret**（引擎对图标 fileID 也做 secret 包装）→ 图标身份通道封死 |
| 移除默认部件 | `ClearIcon`/`ClearAuraBorder`/空模板 → 槽变 **inaccessible**。**槽的 aura 分配依赖 `CustomAuraButtonTemplate` 的默认部件绑定**，不能移除 |
| slot 与 `includeSpellIDs` | 引擎对 slot **忽略**该过滤（v2 实测：Disease 槽也绑定了非疾病 debuff） |
| `includeDispelTypes` | 必须是**键值集合** `{Magic=true}`，传数组 `{"Magic"}` → 引擎解析为空集 → 槽永不绑定（v4.0/4.1 失败根因） |
| 血条 | 上游 r279 **secret 直喂**（C++ 原生算比例），**勿改** |
| `_midnightPctCurve` 解码 | **已回退**（输出仍是 secret，是冻结 bug） |

---

## 七、工作约定

- 客户端仅 12.1+，无需怀旧服兼容
- 12.1 战斗代码必须 `pcall` 包裹所有 `C_UnitAuras` 查询 + `F.IsSecretValue` **前置**检查（secret 值不能比较/做表键）
- 本仓库**无 Lua 解释器**，用 Python 脚本做括号平衡检查（跳过 `--` 注释和字符串）
- 提交信息用**中文**，遵循 `feat:`/`fix:`/`docs:`/`chore:`
- 网络受限：`curl --ssl-no-revoke` 可访问外网；研究资料放 `.research/`（已 gitignore）
- **推送**：沙箱会拦截 git-for-windows 的 `sh.exe` 子进程（Win32 error 5）→ 必须走 **PAT 嵌入远端 URL + 空 helper**（详见 `CLAUDE.md` 推送流程章节，**尚未提交**）

### 文档分工
| 文件 | 状态 |
|---|---|
| `STATUS.md` | ⚠️ 468 行，**含大量过时/被推翻/未落地内容**，读时务必对照代码 |
| `CLAUDE.md` | 有 **34 行未提交改动**（推送流程章节） |
| `ARCHITECTURE.md` / `api_reference.md` | 未核对 |

---

## 八、勘误：上一版转移包的错误清单

| 上一版转移包的说法 | 实际 |
|---|---|
| 待办 1「把 filter 从 `HARMFUL\|DISPELLABLE` 改成 `HARMFUL\|RAID`」 | **filter 早已是裸 `"HARMFUL"`**（L488），该待办不成立 |
| 待办 2「保存 `AddAuraSlot` 返回的 AuraButton」 | **早已保存**（L535 `dispelsButton`） |
| 「dispel 用 `SetAuraBorder(tex, {style, customDispelColorMap})`」 | 实际是 `AddDispelTypeTexture(tex, {style, customDispelColorCurve, customDispelColorMap})` |
| 「白色整格纹理」 | 实际是 `DF_Gradient_V` 渐变 + dim host 控 alpha |
| 「锚定 auraButton」 | 实际 `AnchorDispelTex` 锚定血条**填充纹理** |
| 「`customDispelColorMap` 值类型待查」 | 已确认 `CreateColor` 对象；DandersFrames 明确 map **非 secret 安全** |
| 「debuff 150×28 / element 28」 | ✅ 正确（L319 `SetSize(150,28)`，L330-331 element 28×28） |
| 「`RegisterCallback` 和自动 `ShowAll` 已注释掉」 | ✅ 正确（L944-955、L960-968） |
| 「工具 `str_replace_editor`/`bash` 不可用」 | 那是 Claude Code 工具名；DSH 用 `read`/`write`/`edit`/`pwsh`，**均可用** |
| 未提及 | 漏掉了 `HideLegacyDispels`/`SyncDispelsOutOfCombat`/0.5s 刷新/hooksecurefunc 等已实现机制 |
| 未提及 | 漏掉了 `GetAuraDispelTypeColor` 在 CellD 另有 **dsCurve** 路径（`Indicator_Defaults.lua:269-303`、`Built-in.lua:618`） |

---

## 九、交接后第一步建议

1. **先读** `AuraContainerOverlay.lua` L343-537（dispel 全段，含 v1-v5 历史注释）
2. **再读** `DandersFrames\Features\Dispel.lua` L1740-1900 + `Frames\Border.lua` L815-935（铁律原文）
3. **然后问用户**：「当前染色是否仍不生效？」以确认 P0-A 是否为真问题
4. **最后**按 P0-A → P0-B → P1 顺序改，每步**只改一处**，游戏内实测后再进下一步

---

## 十、2026-08-27 本轮已修复清单

> 全部改动集中在 `Utilities/AuraContainerOverlay.lua`，**未提交**。
> 校验：`.research/lua_paren_check.py`（括号平衡）+ `.research/lua_block_check.py`（块结构 / and-or 陷阱）均通过。

### ✅ 修复 1（P0-A）：曲线与 map 严格二选一 — L547-566
```lua
local curve = BuildDispelColorCurve()
local colorMap
if not curve then colorMap = BuildDispelColorMap() end
opts.customDispelColorCurve = curve
opts.customDispelColorMap   = colorMap
```
**过程中拦下的自伤 bug**：初版写成 `curve and nil or BuildDispelColorMap()` —— Lua 的 `and/or` 陷阱使它**恒等于 `BuildDispelColorMap()`**，会静默保持"两条同传"，正是本修正要消除的状态。已改显式 `if`，并加入检查器防回归。

### ✅ 修复 2（比 P0-A 更实质）：曲线改用 Blizzard ColorMixin — L432-478
**证据来自本插件自身注释** `Indicator_Defaults.lua:277-278`：
> "Blizzard native ColorMixin objects (`DEBUFF_TYPE_*_COLOR`) work correctly as dsCurve AddPoint arguments **where Lua `CreateColor()` objects do not**."

原实现用 `CreateColor(r,g,b,1)` 构建**全部**曲线点 —— 正是该警告说不可靠的方式。后果：曲线存在但无效 → 因引擎无条件让 curve 覆盖 map → 连正确的 map 也被丢弃 → 完全无色。

现改为：优先原生 `DEBUFF_TYPE_*_COLOR`；用户自定义色经 `CreateColor` 转换；**六个全局缺任何一个就整条曲线放弃**，交 map 兜底（避免"有洞"的曲线）。

### ✅ 修复 3（P1）：绑定结果戳记 — L577-583
`pcall` 包裹绑定，结果写入 `auraButton._cellDBindRes` / `_cellDColorMode`。
依据 DandersFrames `Dispel.lua:1801-1812`：必须记在 **button** 上（只记全局会被逐帧覆盖），且必须 `pcall`（否则"没绑定"与"没调用"无法区分，表现为沉默）。
调试输出已接入：`[dispels] ... bind=ok curve=yes mode=curve`

### ✅ 修复 4：secret 比较崩溃 — L794
```lua
local bunit = ... or button:GetAttribute("unit")
if F.IsSecretValue and F.IsSecretValue(bunit) then return end   -- 新增
if bunit ~= unit then return end
```
原代码直接 `bunit ~= unit`，若 `bunit` 为 secret 值会**直接 Lua error**（CLAUDE.md 明列的教训）。

### ✅ 修复 5：`Str()` 加固 — L772-783
补 `pcall(tostring, v)` + 二次 `IsSecretValue` 检查（secret 的 `tostring` 返回 secret 字符串）。所有输出点（含原裸 `tostring(w/h/key/frameCount)`）统一改用 `Str()`。

### ✅ 修复 6（安全）：legacy 驱散的单点故障降级保护 — L900-915
**问题**：legacy dispels 被 `Hide()` + `hooksecurefunc` 压住后，若 overlay 绑定失败（引擎拒绝／曲线无效／槽 inaccessible），用户将**完全看不到驱散提示** —— 治疗场景下危险且无 fallback。

**修复**：新增 `OverlayDispelUsable(button)`，只有 `_cellDBindRes` 以 `"ok"` 开头时才隐藏 legacy；否则**保留 legacy 显示，宁可双层也不要全无**。
判据用实测绑定结果，**不用** `CanBeAccessedInContext`（受限环境恒 false）。
加载期调用已加注释说明：此刻容器未创建 → 必然保留 legacy，属预期。

### ✅ 修复 7：死变量清理
- `local P = Cell.pixelPerfectFuncs` —— 全文 0 引用（已比对：Utilities 下其余文件要么用 P 要么不声明，本文件是唯一"声明却不用"的）。容器尺寸来自用户布局（已像素对齐），再 `P.Scale` 会二次缩放。
- `local _dispelTypeSet` —— v4 per-type 槽方案遗留，单槽方案不再需要。

### ✅ 修复 8：API 守卫一致性
`SyncDispelsOutOfCombat` / `SyncButton` 中的 `SetEnabled` / `UpdateAllAuras` 统一加存在性守卫（与文件其余部分一致）。

### 📌 仍未做（需用户确认或游戏内实测）
- **P0-B**：纯 map 对照开关（若曲线路径实测仍无色）
- **P2**：补 `DF_Gradient_H` / `DF_Gradient_H_Rev` 纹理（做边框式染色才需要）
- **P4**：边框式染色 / 血量空缺区染色 —— STATUS.md 第十节有设计，但**那是文档不是代码**，实现前须与用户确认形态

### 🔍 验证步骤
```
/reload
/celld testaura player     ← 脱战即可，看 bind= 与 mode=
```
| 输出 | 含义 | 下一步 |
|---|---|---|
| `bind=ok curve=yes mode=curve` | 绑定成功、走曲线 | 进战斗实测；仍无色 → P0-B |
| `bind=ok curve=no mode=map` | 曲线放弃、走色表 | 说明某 `DEBUFF_TYPE_*_COLOR` 缺失 |
| `bind=FAIL: ...` | 绑定被拒 | 报错文本即原因 |

---

## 十一、2026-08-27 实测崩溃修复（secret boolean 布尔测试）

### 现场报错
```
AuraContainerOverlay.lua:845: attempt to perform boolean test on local 'shown'
  (a secret boolean value, while execution tainted by 'CellD')
  → IterateAllUnitButtons → DebugAuraOverlay → /celld testaura
```

### 根因（**不是"第一次/第二次"，而是"脱战/战斗"**）
- **脱战时** `AuraButton:IsShown()` 返回**普通 boolean** → `ok and shown or nil` 正常
- **战斗中**引擎把返回值 **secret 化** → `ok and shown` 对 secret 值做布尔测试 → 崩溃

故表现为"第一次（脱战/刚进战）有大量信息，第二次（战斗已深入）报错"。

### 修复（2 处，模式相同）
| 位置 | 原代码 | 修复 |
|---|---|---|
| L818-826（dispels 分支） | `isShown = ok and shown or nil` | 先 `IsSecretValue(shownVal)` 判定；secret 时置字符串 `"SECRET"`（仅展示、不参与逻辑） |
| L843-853（frame 循环） | 同上 + `if ... and isShown then` | 同上；计数改为 `isShown == true`（**用 `== true` 而非布尔测试**） |

> ⚠ 关键点：secret boolean **不能**出现在 `and` / `or` / `if 条件` 中，但**可以**用 `== true` 比较吗？
> **不可以。** 正确做法是先用 `F.IsSecretValue` 判定并过滤，之后才允许使用。
> 本修复即：secret → 记为字符串 `"SECRET"`（它不再是 boolean，后续 `Str()` 可安全打印）。

### 为何上一轮漏掉
上一轮我只修了 `bunit ~= unit` 与 `Str()`，**没扫到 `ok and shown or nil`**。
检查器当时只匹配 `and nil or` **字面量**，而这里是 `and shown or`。

### 检查器已强化（`.research/lua_block_check.py`）
新增两条规则：
1. `ok and <var> or ...`，且 `<var>` 由 `pcall(<已知返回 secret 的 API>)` 赋值 → 告警
   （已知 secret API 列表：`IsShown` / `IsVisible` / `IsEnabled` / `CanBeAccessedInContext`）
2. `if` 条件直接测试 `isShown` / `shownVal` 且无 `IsSecretValue` 守卫 → 告警

**全库扫描确认**：`Utilities` / `RaidFrames` / `Indicators` / `Modules` / `Defaults` 下已无同类模式残留。

### ⚠ 附带发现：此 bug 会**掩盖真实的调试信息**
崩溃发生在 `active=0` 计数逻辑上，而 `active` 恰恰是判断"图标是否真的显示"的唯一指标。
即：**越是想看信息，越会因为要看而崩溃**。修复后 `active` 才真正可用 ——
这也是之前所有调试输出 `active=0` 却"图标其实显示了"的原因之一。
