# CellD 全代码功能架构图

```
══════════════ CellD.toc 加载顺序 ══════════════
│
├─① Locales/LoadLocales.xml  →  enUS.lua + zhCN.lua  (L 表)
├─② Libs/LoadLibs.xml        →  CallbackHandler, LibGroupInfo, LibCustomGlow,
│                                PixelPerfect, LibSerialize, utf8, FAIAP, ...
├─③ Core.lua    →  Cell={funcs,iFuncs,bFuncs,uFuncs,animations,...}
├─④ Utils.lua   →  F.<200+工具函数>
├─⑤ Revise.lua  →  F.Revise() | CellDB数据迁移 (r4→r277)
├─⑥ Comm/       →  频道通讯 | 昵称管理
├─⑦ Widgets/    →  UI控件工厂 | 指示器设置控件
├─⑧ Defaults/   →  全部默认配置数据
├─⑨ HideBlizzard.lua → 隐藏暴雪框体
├─⑩ Indicators/Base.lua → I.<指示器工厂>
├─⑪ Indicators/Built-in.lua → I.Create*(parent) | 25种内置指示器
├─⑫ Indicators/StatusIcon/AoEHealing/TargetCounter/... → 专项指示器
├─⑬ RaidFrames/MainFrame.lua → 主框架容器
├─⑭ Modules/LoadModules.xml → 全部设置面板模块 + DebuffStatus
├─⑮ Utilities/LoadUtilities.xml → 工具模块
├─⑯ RaidDebuffs/LoadRaidDebuffs.xml → 副本减益数据(12资料片)
├─⑰ RaidFrames/UnitButton.lua  →  单位按钮核心(4476行)
├─⑱ RaidFrames/Groups/* →  框架类型(Solo/Party/Raid/Pet/NPC/Spotlight)
├─⑲ Supporters.lua → 赞助者名单
└─⑳ BlackBox.lua  → /celld blackbox 自检

══════════════ 运行时事件→回调分发图 ══════════════

VARIABLES_LOADED  →  SetCVar("predictedHealth",1)
ADDON_LOADED      →  CellDB 初始化 | F.Revise() | 布局校验 | Cell.loaded=true
PLAYER_LOGIN      →  注册 PEW/GROUP_ROSTER/TALENT/UI_SCALE 事件
                 →  Fire(UpdateAppearance,UpdateTools,UpdateRequests,
                          UpdateQuickCast,UpdateRaidDebuffs,UpdatePixelPerfect,
                          UpdateMenu,UpdateCLEU,UpdateClickCastings)
                 →  I.UpdateAoEHealings/Defensives/Externals/CrowdControls()
                 →  F.HideBlizzardParty/Raid/RaidManager()
GROUP_ROSTER_UPDATE → solo/party/raid 检测 → Fire(GroupTypeChanged) → UpdateLayout
PLAYER_ENTERING_WORLD → 副本进出 | 史诗难度 | Fallback队伍类型 | FirstRun

══════════════ 21种指示器 → UnitButton 事件 → 渲染全链路 ══════════════

一个 UnitButton 上同时运行 21 种指示器 (Base.lua + Built-in.lua):

事件源                    →  UnitButton_OnEvent    →  渲染函数
──────────────────────────────────────────────────────────────────
GROUP_ROSTER_UPDATE       →  _updateRequired=1    →  UnitButton_UpdateAll (pcall)
UNIT_NAME_UPDATE          →  UnitButton_UpdateName →  nameText:UpdateName()
UNIT_HEALTH               →  UpdateHealth         →  healthBar:SetValue(secret)
                          →  UpdateHealthStates   →  healthPercent Calc
                          →  UpdateHealthColor    →  SetStatusBarColor
                          →  UpdateShieldAbsorbs  →  shieldBar:SetValue
                          →  UpdateHealPrediction →  incomingHeal:SetValue
                          →  UpdateHealAbsorbs    →  absorbsBar:SetValue
UNIT_MAXHEALTH            →  UpdateHealthMax      →  SetMinMaxValues(0,secret)
UNIT_POWER/MAXPOWER/DP    →  UpdatePowerStates    →  powerBar:SetValue
                          →  UpdatePowerMax       →  SetMinMaxValues
                          →  UpdatePowerText      →  SetPower_Percent/Number
                          →  CheckPowerEventRegistration
UNIT_AURA                 →  UpdateAuras          →  ForEachAura(GetUnitAuras)
                            ┌─ HandleDebuff ──────────────────────────┐
                            │  GetTemporal() → start/dur/hasSecret    │
                            │  GetDebuffType(dispelName) → "Magic"/"" │
                            │  UpdateRefreshState(auraInfo)            │
                            │  ClassifyDebuff() → big/blacklisted      │
                            │  ↓                                     │
                            │  _debuffs_big/normal → debuffs 指示器   │
                            │  _debuffs_raid→raidDebuffs指示器 (sort) │
                            │  _debuffs_dispel→dispels 指示器         │
                            │  _debuffs→crowdControls 指示器          │
                            └────────────────────────────────────────┘
                            ┌─ HandleBuff ───────────────────────────┐
                            │  IsExternalCooldown(name,id)            │
                            │  IsDefensiveCooldown(name,id)           │
                            │  IsTankActiveMitigation(spellId)        │
                            │  IsDrinking(name)                      │
                            │  ↓                                     │
                            │  externalCooldowns 指示器               │
                            │  defensiveCooldowns 指示器              │
                            │  allCooldowns 指示器                   │
                            │  tankActiveMitigation 指示器            │
                            └────────────────────────────────────────┘
UNIT_HEAL_PREDICTION      →  UpdateHealPrediction → incomingHeal:SetValue
UNIT_ABSORB_AMOUNT_CHANGED → UpdateShieldAbsorbs → shieldBar/overShieldGlow
UNIT_HEAL_ABSORB_AMOUNT_CHANGED → UpdateHealAbsorbs → absorbsBar/overAbsorbGlow
UNIT_THREAT_SITUATION     →  UpdateThreat       →  aggroBlink/Border/Bar
UNIT_ENTERED/EXITED_VEHICLE → _updateRequired=1 (全刷新)
UNIT_FLAGS (afk)          →  UpdateStatusText   →  statusText:SetStatus
UNIT_FACTION (精神控制)    →  UpdateNameTextColor →  变色
UNIT_CONNECTION (离线)    →  _updateRequired=1
UNIT_PORTRAIT_UPDATE      →  宠物刷新触发
PLAYER_TARGET_CHANGED     →  targetHighlight    →  Show/Hide
RAID_TARGET_UPDATE        →  UpdatePlayerRaidIcon → SetRaidTargetIcon
UNIT_TARGET               →  UpdateTargetRaidIcon
READY_CHECK/CONFIRM       →  UpdateReadyCheck   →  readyCheckIcon
ENCOUNTER_START           →  currentEncounterID → UpdateDebuffsForCurrentZone
ENCOUNTER_END             →  currentEncounterID=nil → 恢复全Boss减益

══════════════ 驱动上色完整数据流 (最复杂链路, 13步) ══════════════

① UNIT_AURA("party1") → unit匹配 → UnitButton_UpdateAuras(self, updateInfo)
② ForEachAura → C_UnitAuras.GetUnitAuras("party1","HARMFUL") → 返回光圈数组
③ HandleDebuff(button, auraInfo) 逐光圈处理:
   ├─ auraInfo.dispelName 存在 → debuffType=dispelName 或 "Magic"(secret回退)
   ├─ auraInfo.canActivePlayerDispel → canDispel (F.IsSecretValue guard)
   ├─ indicatorBooleans["dispels"]["dispellableByMe"] 或 canDispel → 过滤
   ├─ indicatorBooleans["dispels"][debuffType] 或 isSecretType → 命中!
   ├─ _topDispelAuraID = auraInstanceID      ← 黑名单检查前
   └─ _debuffs_dispel[key] = {highlight=true, auraID=ID}
④ UnitButton_UpdateDebuffs(button, isFullUpdate):
   ├─ _topDispelAuraID = nil (每轮reset)
   ├─ 遍历 _debuffs_normal → debuffs 指示器 SetCooldown → 左下角图标
   ├─ _debuffs_raid 排序 → raidDebuffs 指示器 → 发光
   ├─ SetDispels(_debuffs_dispel) → ★ 调用 Dispels_SetDispels
   └─ wipe(_debuffs_dispel) (调用后清空)
⑤ Dispels_SetDispels:
   ├─ 遍历 dispelOrder ["Magic","Curse","Disease","Poison","Bleed"]
   │   → match到类型 → found=true, r,g,b=GetDebuffTypeColor(type)
   │   → highlight纹理: SetGradient/SetVertexColor (渐变/entire/current)
   │   → showIcons → SetDispel(type) 图标渲染
   ├─ _secret条目循环: GetDebuffTypeColor("Magic") → 回退蓝色
   └─ found → glow:SetBackdropColor(r,g,b,0.35) ★ 整格半透明上色

══════════════ 全局信号系统 (Cell.Fire ⇄ Cell.RegisterCallback) ══════════════

发射方 (Fire源)             接收方 (Callback注册)
─────────────────────────────────────────────────────────
Core:PLAYER_LOGIN        →  UpdateAppearance/UpdateTools/UpdateRequests/
                            UpdateQuickCast/UpdateRaidDebuffs/UpdatePixelPerfect/
                            UpdateMenu/UpdateCLEU/UpdateClickCastings
                            I.UpdateAoEHealings/Defensives/Externals/CrowdControls
Core:GroupTypeChanged    →  PreUpdateLayout → F.UpdateLayout
Core:SpecChanged         →  UpdateClickCastings/SpecChanged
Core:EnterInstance       →  (副本进入)
Core:LeaveInstance       →  (副本离开)
Layout:UpdateLayout      →  各框架组 (Solo/Party/Raid/Pet/NPC/Spotlight)_UpdateLayout
                         →  RaidDebuffs/Appearance 的 UpdateLayout 回调
Layout:UpdateIndicators   →  UnitButton_UpdateIndicators → 全部指示器重配置
Appearance:UpdateAppearance → B.UpdateColor/UpdateShields/UpdateAnimation/...
RaidDebuffs:RaidDebuffsChanged → Built-in:UpdateDebuffsForCurrentZone
Indicators:UpdateIndicator → UnitButton 指示器属性变更
OptionsFrame:ShowOptionsTab → 各面板 Create*Pane() 延迟创建
General:UpdateMenu         → 主框架 lock/fadeOut/menuPosition
General:UpdateNicknames    → 昵称刷新
General:TranslitNames      → 音译名字刷新

══════════════ SavedVariables 配置树 ══════════════

CellDB (账号级全局)
├─ general             → enableTooltips/hideBlizzard*/locked/fadeOut/
│                        menuPosition/alwaysUpdateAuras/framePriority/translit
├─ nicknames           → mine/sync/custom/list/blacklist
├─ tools               → battleResTimer/buffTracker/deathReport/readyAndPull/marks
├─ appearance          → 材质/缩放/颜色/动画/护盾/AuraIcon/debuffTypeColor/...
├─ clickCastings       → [class]={useCommon,smartRes,[spec]={绑定列表}}
├─ layouts             → [layoutName]={size/power/indicators[25]/orientation/...}
├─ layoutAutoSwitch    → [class/spec]={solo/party/raid/arena/bg15/bg40/...}
├─ spellRequest        → 法术请求设置
├─ dispelRequest       → 驱散请求设置
├─ quickAssist         → 快速协助设置
├─ quickCast           → [class]={[spec]={buttons,glowBuffs,...}}
├─ raidDebuffs         → [instanceId]={[bossId]={[spellId]={order,glow,...}}}
├─ debuffBlacklist     → [spellId]=true
├─ dispelBlacklist     → [spellId]=true
├─ bigDebuffs          → [spellId]=true
├─ debuffTypeColor     → [Magic/Curse/Disease/Poison/Bleed]={r,g,b}
├─ aoeHealings         → {disabled,custom}
├─ defensives          → {disabled,custom}
├─ externals           → {disabled,custom}
├─ crowdControls       → {disabled,custom}
├─ targetedSpellsList  → [spellId]=...
├─ targetedSpellsGlow  → glowOptions
├─ customTextures      → 用户自定义纹理
├─ indicatorPreview    → {scale,showAll}
├─ optionsFramePosition → 选项窗口位置
├─ revise              → "r277" (版本号)
└─ firstRun            → true (首次运行标记)

CellDBBackup           → F.Copy(CellDB) 备份
CellCharacterDB (角色专属)
├─ clickCastings       → (经典服)
├─ layoutAutoSwitch    → (经典服)
└─ revise              → 版本号

══════════════ 单位按钮内部结构 (CellUnitButton_OnLoad 创建) ══════════════

button (SecureUnitButton)
├─ states          → unit/displayedUnit/name/fullName/class/guid/isPlayer/
│                    health/healthMax/healthPercent/healthColor/inVehicle/
│                    inRange/isDead/isDeadOrGhost/hasRezDebuff/hasSoulstone/...
├─ widgets
│   ├─ healthCalculator (Midnight) → HealPredictionCalculator
│   ├─ healPredictionCalculator    → HealPredictionCalculator
│   ├─ healthColorCurve            → C_CurveUtil 曲线
│   ├─ healthBar        → StatusBar (frameLevel+1)
│   ├─ healthBarLoss    → Texture
│   ├─ powerBar         → StatusBar (frameLevel+2)
│   ├─ powerBarLoss     → Texture
│   ├─ incomingHeal     → StatusBar/Texture (frameLevel healthBar+1)
│   ├─ shieldBar        → StatusBar/Texture (midLevelFrame)
│   ├─ shieldBarR       → StatusBar/Texture (ReverseFill)
│   ├─ absorbsBar       → StatusBar/Texture
│   ├─ overShieldGlow/overShieldGlowR → Texture
│   ├─ overAbsorbGlow   → Texture
│   ├─ damageFlashTex   → Texture
│   ├─ targetHighlight  → Frame (frameLevel+3)
│   ├─ mouseoverHighlight → Frame (frameLevel+4)
│   ├─ highLevelFrame   → Frame (frameLevel+140)
│   ├─ midLevelFrame    → Frame (frameLevel+120)
│   ├─ indicatorFrame   → Frame (frameLevel+220)
│   ├─ srGlowFrame      → 法术请求发光
│   ├─ drGlowFrame      → 驱散请求发光
│   └─ tsGlowFrame      → 点名技能发光
├─ indicators       → [25]  (每个对应 CreateXxx 创建)
│   ├─ [1]  nameText          → FontString
│   ├─ [2]  statusText        → FontString
│   ├─ [3]  healthText        → FontString
│   ├─ [4]  powerText         → FontString
│   ├─ [5]  statusIcon        → Frame+atlas
│   ├─ [6]  roleIcon          → Texture
│   ├─ [7]  leaderIcon        → Texture
│   ├─ [8]  combatIcon        → Texture
│   ├─ [9]  readyCheckIcon    → Texture
│   ├─ [10] playerRaidIcon    → Texture
│   ├─ [11] targetRaidIcon    → Texture
│   ├─ [12] aggroBlink        → Frame
│   ├─ [13] aggroBorder       → Frame
│   ├─ [14] aggroBar          → StatusBar
│   ├─ [15] shieldBar         → StatusBar
│   ├─ [16] aoeHealing        → Frame
│   ├─ [17] externalCooldowns → Frame[5]-BorderIcon
│   ├─ [18] defensiveCooldowns → Frame[5]-BorderIcon
│   ├─ [19] allCooldowns      → Frame[5]-BorderIcon
│   ├─ [20] tankActiveMitigation → StatusBar
│   ├─ [21] dispels           → Frame[5] (highlight纹理 + glow Frame + 5个icon)
│   ├─ [22] debuffs           → Frame[10]-BarIcon
│   ├─ [23] raidDebuffs       → Frame[3]-BorderIcon
│   ├─ [24] privateAuras      → Frame (Blizzard AddPrivateAuraAnchor)
│   ├─ [25] targetedSpells    → Frame[3]-BorderIcon
│   ├─ [26] targetCounter     → FontString
│   ├─ [27] crowdControls     → Frame[3]-BorderIcon
│   ├─ [28] actions           → Frame
│   ├─ [29] healthThresholds  → Texture
│   ├─ [30] missingBuffs      → Frame[3]-BorderIcon
│   └─ [31+] customN          → 自定义指示器 (icon/icons/bar/text/rect/color/glow)
├─ _buffs           → {defensiveFound,externalFound,allFound,...}
├─ _debuffs         → {resurrectionFound,crowdControlsFound,_topDispelAuraID}
├─ _buffs_cache     → {[auraInstanceID]=auraInfo} (光环动画缓存)
├─ _debuffs_cache   → {[auraInstanceID]=auraInfo} (光环动画缓存)
├─ _missing_auras   → {[auraInstanceID]=auraInfo}
├─ _buffs_count_cache → 层数缓存
├─ _debuffs_normal  → {[auraID]=true} 普通减益列表
├─ _debuffs_big     → {[auraID]=true} 重要减益列表
├─ _debuffs_dispel  → {["Magic"]=table, ["Curse"]=true, ...}
├─ _debuffs_raid    → {auraID1, auraID2, ...} (排序用)
└─ _debuffs_glow_current → {[glowType]=glowOptions}

══════════════ Midnight 12.0 Secret Value 防护矩阵 ══════════════

模块           秘密值              防护方法                         位置
──────────────────────────────────────────────────────────────────────
血量显示       UnitHealth           Calculator:GetCurrentHealth()     UnitButton:1786
                healthPercent       IsValueNonSecret→缓存回退1     UnitButton:1793
                maxHealth           SetMinMaxValues(0,max) C引擎     UnitButton:2282
能量条          UnitPower           UnitPowerPercent优先→NumberShort UnitButton:1951
                UnitPowerMax        SetMinMaxValues(0,max)           UnitButton:2240
                powerMax<=0        IsSecretValue guard              UnitButton:1888
护盾条          GetDamageAbsorbs    SetMinMaxValues(0,max)+SetValue  Built-in:2264
                maxHealth(secret)   25% fallback宽度                 Built-in:2270
Debuff时间      expirationTime     GetTemporal()→hasSecretTime      UnitButton:1174
                duration           duration=0→边框模式              UnitButton:1181
                DurationObject     GetDuration回退渲染冷却          DebuffStatus:18
Buff分类        spellId/name       IsSecretValue guard              DefaultSpells:342
                canActiveDispel    F.IsSecretValue guard             UnitButton:1227
驱散染色        dispelName(secret) "Magic"回退+_secret键            UnitButton:1164
                颜色来源           GetDebuffTypeColor查CellDB表     Built-in:595
Boss减益        spellName          nameAndID guard→只查spellId      Built-in:876
GUID            UnitGUID           F.IsSecretValue guard             Utils:1514
                string.find        前置guard                        Utils:1516
名字            UnitName(secret)   FontString:SetText原生接受       Utils:1089
                GetWidth/GetHeight  SetSize parent:GetWidth回退      Built-in:1244
                utf8len/utf8sub    IsSecretValue guard              utf8.lua:161
                GetText拼接         F.IsSecretValue guard            Built-in:1226
仇恨条          scaledPercentage   IsValueNonSecret→原生SetValue    UnitButton:2633
点名技能        spellId/startTime  4重guard→提前return             TargetedSpells:147
                sourceGUID         IsSecretValue guard              TargetedSpells:155
施法同调        spellId            IsSecretValue guard              QuickCast:901

══════════════ 配置面板←→CellDB 双向绑定图 ═══════════════════

面板(Modules/)          绑定字段                    Fire事件
────────────────────────────────────────────────────────────────
General:
  可见性                 hideBlizzardParty/Raid/RaidManager
  提示                   enableTooltips/hideTooltipsInCombat/tooltipsPosition
  位置                   locked/fadeOut/menuPosition
  昵称                   nicknames.mine/sync
  Misc                   alwaysUpdateAuras/translit/framePriority
Appearance:
  Cell全局                scale/strata/accentColor/optionsFontSizeOffset/useGameFont
  单位按钮样式             texture/barColor/barAlpha/powerColor/lossColor/deathColor/
                         fullColor/barAnimation/colorThresholds
  护盾/吸收               shield/overshield/overshieldReverseFill/healAbsorb
  高亮                    targetColor/mouseoverColor/highlightSize
  光环图标                auraIconOptions(动画/颜色/持续时间/roundUp/decimal)
  DebuffType颜色          debuffTypeColor[Magic/Curse/Disease/Poison/Bleed]
ClickCastings:
  单位绑定                 clickCastings[class][spec][index]={key,action,spell/target}
  智能复活                 smartResurrection
  全局目标                 alwaysTargeting
  导入导出                序列化→压缩→编码
Layouts:
  布局管理                 layouts[name]={size/power/orientation/spacing/indicators}
  自动切换                 layoutAutoSwitch[class/spec]={场景→布局名}
  框架配置                 solo/party/raid/pet/npc/spotlight
  能量过滤                 powerFilters[class]={role→boolean}
Indicators:
  25种内置+自定义          currentLayoutTable.indicators[1-25+]
  驱散过滤器               dispelFilters(dispellableByMe/Curse/Disease/Magic/Poison/Bleed)
  高亮样式                 highlightType
  图标样式                 iconStyle(blizzard/rhombus)
  驱散黑名单               dispelBlacklist
RaidDebuffs:
  Boss列表                 raidDebuffs[instanceId][bossId][spellId]
  条件/发光/排序           condition/glowType/glowOptions/glowCondition/order
  导入导出                 F.UpdateRaidDebuffs
Utilities:
  战复计时                 tools.battleResTimer
  增益检查                 tools.buffTracker
  死亡通报                 tools.deathReport
  就位/倒计时              tools.readyAndPull
  团队标记                 tools.marks
  快速协助                 quickAssist[spec]
  快捷施法                 quickCast[class][spec]
  增益监控                 quickCast glowBuffs/glowCasts
  法术请求                 spellRequest
  驱散请求                 dispelRequest
About:
  导入导出全部设置          F.Copy(CellDB)→序列化  /  反序列化→DoImport→ReloadUI
  备份管理                 CellDBBackup

══════════════ 副本减益系统 (RaidDebuffs) ═══════════════

加载链:
  RaidDebuffs_Midnight.lua → F.LoadBuiltInDebuffs(debuffs) → unsortedDebuffs[instanceId]
  CellDB["raidDebuffs"] → LoadDB() → loadedDebuffs[instanceId][bossId]
  F.GetDebuffList(instanceName, encounterID) → currentAreaDebuffs

运行时:
  ENCOUNTER_START(id) → currentEncounterID=id → UpdateDebuffsForCurrentZone
  ENCOUNTER_END       → currentEncounterID=nil → 恢复全部Boss减益
  PLAYER_ENTERING_WORLD → F.GetInstanceName() → 定位副本

查询链:
  HandleDebuff → I.GetDebuffOrder(name, spellId, count) → currentAreaDebuffs[spellId]
              → I.GetDebuffGlow(name, spellId, count)   → glowType+options
              → I.IsDebuffUseElapsedTime(name, spellId)  → 时间格式

排序:
  _debuffs_raid[] → sort(cache[a].raidDebuffOrder < cache[b].raidDebuffOrder)

渲染:
  raidDebuffs[1-3]:BorderIcon_SetCooldown(start, dur, type, icon, count, refreshing, useElapsed)
  glow: Pixel/Shine/Proc/ButtonGlow (LibCustomGlow-1.0)

══════════════ 文件间依赖矩阵 (核心文件) ═══════════════

                   Core Utils Revise UnitB Indi:B Indi:Ba Module Widget
Core.lua            -    X      X      X      X      X       X      X
Utils.lua           -    -      -      X      X      X       X      X
Revise.lua          -    -      -      -      X      -       -      -
UnitButton.lua      -    X      -      -      X      X       X      X
Built-in.lua        -    X      -      X      -      X       -      X
Base.lua            -    X      -      -      -      -       -      -
Widgets.lua         -    X      -      -      -      -       -      -
RaidDebuffs.lua     -    X      -      -      X      -       -      -
Indicators.lua      -    X      -      X      X      -       -      X
Appearance.lua      -    X      -      X      -      -       -      X
Layouts.lua         -    X      -      X      -      -       -      X
ClickCastings.lua   -    X      -      -      -      -       -      X
General.lua         -    X      -      -      -      -       -      X
About.lua           -    X      -      -      -      -       -      X
QuickAssist.lua     -    X      -      X      -      -       -      -
QuickCast.lua       -    X      -      -      -      -       -      -
BuffTracker.lua     -    X      -      X      X      -       -      -
BattleRes.lua       -    X      -      -      -      -       -      -
DeathReport.lua     -    X      -      -      -      -       -      -
StatusIcon.lua      -    X      -      X      -      -       -      -
Custom.lua          -    X      -      X      X      -       -      -
Comm.lua            -    X      -      -      -      -       -      -
BlackBox.lua        -    X      -      -      -      -       -      -

X = 有依赖引用 (local F=Cell.funcs / local I=Cell.iFuncs 等)
