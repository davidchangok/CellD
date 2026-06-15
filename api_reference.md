# World of Warcraft 12.0.5 (Midnight) Addon API Reference

这是一个专门为大语言模型（如 DeepSeek-R1、Claude 3.5 Sonnet）优化的 API 上下文参考手册。它包含了 WoW 12.0.5 (Interface: 120005) 最核心的 UI 框架、事件机制、数据持久化以及现代 Mixin 开发范式，旨在消除 AI 编写 Lua 插件时的“版本幻觉”。

---

## 1. 插件元数据与生命周期 (.toc)

在大模型为你生成项目脚手架时，务必强制其遵循以下现代 `.toc` 文件规范：

```toc
## Interface: 120005
## Title: CellD
## Notes: Core context reference for World of Warcraft: Midnight (12.0.5)
## Version: 1.0.0
## Author: Developer
## SavedVariables: CellDGlobalDB
## SavedVariablesPerCharacter: CellDCharacterDB

# 库文件加载列表 (如有)
Libs\LibStub\LibStub.lua

# 核心逻辑
Core.lua
UI.lua
```

### AI 提示要点：
* **Interface**: 必须为 `120005`（适配 12.0.5 版本）。
* **SavedVariables**: 全局账户级数据库。
* **SavedVariablesPerCharacter**: 单角色独立数据库。
* 思考过程使用中文

---

## 2. 现代事件系统与初始化架构

现代 WoW API 极力推荐使用面向对象的 Frame 封装以及 Mixin 模式。在指导 AI 编写核心文件（如 `Core.lua`）时，让其采用以下事件流结构：

```lua
-- 创建核心监听框架
local addonName, addonTable = ...
local CoreFrame = CreateFrame("Frame", addonName .. "CoreFrame", UIParent)

-- 注册核心生命周期事件
CoreFrame:RegisterEvent("ADDON_LOADED")
CoreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- 统一事件分发器 (Event Dispatcher)
local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            self:UnregisterEvent("ADDON_LOADED")
            self:InitializeDB()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        self:OnPlayerEnter(isInitialLogin, isReloadingUi)
    end
end

CoreFrame:SetScript("OnEvent", OnEvent)

-- 数据库初始化方法
function CoreFrame:InitializeDB()
    -- 账户全局数据兜底
    CellDGlobalDB = CellDGlobalDB or {}
    CellDGlobalDB.settings = CellDGlobalDB.settings or {
        scale = 1.0,
        theme = "Dark",
    }
    
    -- 角色级数据兜底
    CellDCharacterDB = CellDCharacterDB or {}
    CellDCharacterDB.trackedData = CellDCharacterDB.trackedData or {}
    
    print("|cff00ff00["..addonName.."]|r 数据库加载成功。")
end

-- 玩家进入世界处理
function CoreFrame:OnPlayerEnter(isInitialLogin, isReloadingUi)
    -- 获取玩家阵营进行 UI 适配
    local localizedFaction, englishFaction = UnitFactionGroup("player")
    self.playerFaction = englishFaction -- "Alliance" or "Horde"
end
```

---

## 3. 现代 UI 框架与像素级对齐 (12.0.5 Compliant)

WoW 12.0.x 移除了大量过时的全局 UI 函数，目前所有的面板和控件都必须显式继承相关的内置模板（尤其是 `BackdropTemplate`）。

### 3.1 实例化标准主面板
```lua
-- 生成现代化主面板
local function CreateMainPanel()
    -- 12.0.5 必须显式传递 BackdropTemplate 才能使用 SetBackdrop
    local frame = CreateFrame("Frame", "CellDMainPanel", UIParent, "BackdropTemplate")
    
    frame:SetSize(400, 300)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    
    -- 脚本赋予拖拽能力
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    
    -- 现代扁平化深色系暗调风格样式配置
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    
    -- 柔和深灰底色与极简浅灰边框
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    
    -- 标题配置
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    frame.title:SetText("CellD 配置控制面板")
    
    -- 关闭按钮 (使用内置现代材质)
    frame.closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    
    return frame
end
```

### 3.2 动态阵营图标渲染 (多媒体/贴图资源处理)
在编写带有阵营管理或特定 UI 皮肤的逻辑时，可利用以下接口进行材质的安全替换：
```lua
local function ApplyFactionStyling(frame, faction)
    -- 12.0.5 兼容的路径转义格式
    local texturePath = "Interface\\TargetingFrame\\UI-StatusBar"
    
    if faction == "Alliance" then
        frame:SetBackdropBorderColor(0.1, 0.4, 0.8, 1) -- 联盟蓝
    elseif faction == "Horde" then
        frame:SetBackdropBorderColor(0.8, 0.1, 0.1, 1) -- 部落红
    end
end
```

---

## 4. 数据操作与性能优化规范

为了防止因数据量过大导致游戏画面掉帧（Script Taint / Interface Freeze），所有深层数据读取、循环解析，必须严格控制执行栈。

### 4.1 分时迭代（协程处理大量数据）
让大模型在写大数据扫描时，一律采用协程分步挂起处理：

```lua
local function ChunkedDataScan(largeTable, processElementFunc)
    local co = coroutine.create(function()
        local count = 0
        for id, data in pairs(largeTable) do
            processElementFunc(id, data)
            count = count + 1
            
            -- 每处理 500 条数据挂起一次，让出 CPU 给主游戏线程
            if count % 500 == 0 then
                coroutine.yield()
            end
        end
        print("CellD: 大批量数据扫描完毕。")
    end)
    
    -- 使用 OnUpdate 驱动协程持续运行
    local ticker
    ticker = C_Timer.NewTicker(0.01, function()
        if coroutine.status(co) ~= "dead" then
            local success, err = coroutine.resume(co)
            if not success then
                print("CellD 扫描出错: ", err)
                ticker:Cancel()
            end
        else
            ticker:Cancel()
        end
    end)
end
```

---

## 5. 常用命令与调试接口 (Slash Commands)

标准的交互入口注册方法：

```lua
SLASH_CELLD1 = "/celld"
SLASH_CELLD2 = "/cd"

SlashCmdList["CELLD"] = function(msg)
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = command and command:lower() or ""
    
    if command == "config" or command == "ui" then
        if CellDMainPanel and CellDMainPanel:IsShown() then
            CellDMainPanel:Hide()
        elseif CellDMainPanel then
            CellDMainPanel:Show()
        end
    elseif command == "reset" then
        -- 数据库重置逻辑
        CellDCharacterDB = {}
        ReloadUI()
    else
        print("|cff00ff00CellD 命令列表:|r")
        print("  /celld ui - 打开/关闭主配置面板")
        print("  /celld reset - 重置当前角色插件数据库并重载")
    end
end
```

---

## 6. 面向大模型（DeepSeek / Claude）的专用 Prompts 指导指南

当你在 Claude Code 或 VS Code 内激活本引用手册时，可在提问开头直接贴入如下约束：

> **开发者指令：**
> 请仔细阅读本目录下的 `api_reference.md`。在我接下来的代码生成任务中，你必须严格遵守：
> 1. 所有新创建的 UI 面板必须通过继承 `BackdropTemplate` 来实现自定义边框底色，禁止使用过时的单体 Frame 背景定义。
> 2. 编写逻辑时，优先考虑性能开销。当面临大批量的数据读取或过滤任务时，自动使用提供好的 `ChunkedDataScan` 协程范式。
> 3. 命名空间和局部变量隔离：所有逻辑文件必须使用本地作用域声明，或将其挂载到 `addonTable` 中以避免引发全局污染。
> 4. 当前目标 API 版本至少为 **12.0.5**。