local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local U = Cell.uFuncs
local P = Cell.pixelPerfectFuncs
local LCG = LibStub("LibCustomGlow-1.0")

-------------------------------------------------
-- raid tools -- 团队工具面板：战斗复活计时器、死亡报告、Buff追踪器、就绪/倒数按钮、标记栏等
-------------------------------------------------
-- rtPane: 团队工具面板容器
-- resCB: 战斗复活计时器开关 CheckButton
-- resDetachCB: 战斗复活计时器"分离显示"开关
-- reportCB: 死亡报告开关
-- buffCB: Buff 追踪器开关
-- buffDropdown: Buff 追踪器布局方向下拉框
-- sizeEditBox: Buff 图标尺寸编辑框
-- buffButtons: 经典版本 Buff 图标按钮集合（table）
-- readyPullCB: 就绪检查/倒计时按钮开关
-- styleDropdown: 就绪/倒计时按钮样式下拉框
-- pullDropdown: 倒计时插件来源下拉框（默认/MRT/DBM/BigWigs）
-- secEditBox: 倒计时秒数编辑框
-- marksBarCB: 标记栏开关
-- marksDropdown: 标记栏样式下拉框（目标标记/世界标记/两者/水平/垂直）
-- marksShowSoloCB: "仅自己时也显示标记栏"开关
-- fadeOutToolsCB: 鼠标离开时淡出这些按钮的开关
local rtPane
local resCB, resDetachCB, reportCB, buffCB, buffDropdown, sizeEditBox, buffButtons, readyPullCB, styleDropdown, pullDropdown, secEditBox, marksBarCB, marksDropdown, marksShowSoloCB, fadeOutToolsCB

-- 创建"团队工具"设置面板，包含所有团队相关工具的控件
local function CreateRTPane()
    rtPane = Cell.CreateTitledPane(Cell.frames.utilitiesTab, L["Raid Tools"].." |cFF777777"..L["only in group"], 422, 167)
    rtPane:SetPoint("TOPLEFT", 5, -5)
    rtPane:SetPoint("BOTTOMRIGHT", -5, 5)

    -- 解锁/锁定按钮：解锁后可拖拽移动界面元素（按钮显示绿色光晕）
    local unlockBtn = Cell.CreateButton(rtPane, L["Unlock"], "accent", {77, 17})
    unlockBtn:SetPoint("TOPRIGHT", rtPane)
    unlockBtn.locked = true
    unlockBtn:SetScript("OnClick", function(self)
        if self.locked then
            -- 解锁：切换到"锁定"文字，显示移动框架，启动绿色像素光晕
            unlockBtn:SetText(L["Lock"])
            self.locked = false
            Cell.vars.showMover = true
            LCG.PixelGlow_Start(unlockBtn, {0,1,0,1}, 9, 0.25, 8, 1)
        else
            -- 锁定：恢复到"解锁"文字，隐藏移动框架，停止光晕
            unlockBtn:SetText(L["Unlock"])
            self.locked = true
            Cell.vars.showMover = false
            LCG.PixelGlow_Stop(unlockBtn)
        end
        Cell.Fire("ShowMover", Cell.vars.showMover)
    end)

    -- 战斗复活计时器设置 -- 仅正式服可用（启用条件：Cell.isRetail）
    -- 战斗复活计时器主开关：勾选后启用战斗复活计时器显示
    resCB = Cell.CreateCheckButton(rtPane, L["Battle Res Timer"], function(checked, self)
        CellDB["tools"]["battleResTimer"][1] = checked
        resDetachCB:SetEnabled(checked)
        Cell.Fire("UpdateTools", "battleResTimer")
    end, L["Battle Res Timer"], L["Only show during encounter or in mythic+"])
    resCB:SetPoint("TOPLEFT", rtPane, "TOPLEFT", 5, -27)
    resCB:SetEnabled(Cell.isRetail) -- 仅正式服可启用（战斗复活是正式服机制）

    -- 战斗复活计时器"分离显示"开关：将计时器从团队工具面板中分离为独立浮动窗口
    resDetachCB = Cell.CreateCheckButton(rtPane, L["Detached"], function(checked, self)
        CellDB["tools"]["battleResTimer"][2] = checked
        Cell.Fire("UpdateTools", "battleResTimer")
    end)
    resDetachCB:SetPoint("TOPLEFT", resCB, "BOTTOMRIGHT", 5, -5)

    -- 死亡报告设置 -- 在团队遭遇战中自动报告队友死亡信息
    -- 死亡报告主开关：勾选后启用死亡报告功能，战斗中自动在团队频道报告死亡信息
    reportCB = Cell.CreateCheckButton(rtPane, L["Death Report"], function(checked, self)
        CellDB["tools"]["deathReport"][1] = checked
        Cell.Fire("UpdateTools", "deathReport")
    end)
    reportCB:SetPoint("TOPLEFT", resCB, "BOTTOMLEFT", 0, -35)
    -- 鼠标悬停提示：显示当前报告设置和 CPU 使用警告
    reportCB:HookScript("OnEnter", function()
        CellTooltip:SetOwner(reportCB, "ANCHOR_TOPLEFT", 0, 2)
        CellTooltip:AddLine(L["Death Report"].." |cffff2727"..L["HIGH CPU USAGE"])
        CellTooltip:AddLine("|cffff2727" .. L["Disabled in battlegrounds and arenas"])
        CellTooltip:AddLine("|cffffffff" .. L["Report deaths to group"])
        CellTooltip:AddLine("|cffffffff" .. L["Use |cFFFFB5C5/cell report X|r to set the number of reports during a raid encounter"])
        CellTooltip:AddLine("|cffffffff" .. L["Current"]..": |cFFFFB5C5"..(CellDB["tools"]["deathReport"][2]==0 and L["all"] or string.format(L["first %d"], CellDB["tools"]["deathReport"][2])))
        CellTooltip:Show()
    end)
    reportCB:HookScript("OnLeave", function()
        CellTooltip:Hide()
    end)

    -- Buff 追踪器设置 -- 检查团队成员是否缺少关键团队增益（如智力、耐力、爪子等）
    -- Buff 追踪器主开关：勾选后启用 Buff 追踪器，控制布局下拉框、尺寸编辑框和经典版 Buff 按钮的启用状态
    buffCB = Cell.CreateCheckButton(rtPane, L["Buff Tracker"], function(checked, self)
        CellDB["tools"]["buffTracker"][1] = checked
        buffDropdown:SetEnabled(checked)
        sizeEditBox:SetEnabled(checked)
        if buffButtons then
            for buff, b in pairs(buffButtons) do
                b:SetEnabled(checked)
            end
        end
        Cell.Fire("UpdateTools", "buffTracker")
    end, L["Buff Tracker"].." |cffff7727"..L["MODERATE CPU USAGE"], L["Check if your group members need some raid buffs"],
    Cell.isRetail and L["|cffffb5c5Left-Click:|r cast the spell"] or "|cffffb5c5(Shift)|r "..L["|cffffb5c5Left-Click:|r cast the spell"],
    L["|cffffb5c5Right-Click:|r report unaffected"])
    -- L["Use |cFFFFB5C5/cell buff X|r to set icon size"],
    -- "|cffffffff" .. L["Current"]..": |cFFFFB5C5"..CellDB["tools"]["buffTracker"][3])
    buffCB:SetPoint("TOPLEFT", reportCB, "BOTTOMLEFT", 0, -15)

    -- Buff 追踪器布局方向下拉框：控制 Buff 图标从左到右/从右到左/从上到下/从下到上的排列方向
    buffDropdown = Cell.CreateDropdown(rtPane, 120)
    buffDropdown:SetPoint("TOPLEFT", buffCB, "BOTTOMRIGHT", 5, -5)
    buffDropdown:SetItems({
        {
            ["text"] = L["left-to-right"],
            ["value"] = "left-to-right",
            ["onClick"] = function()
                CellDB["tools"]["buffTracker"][2] = "left-to-right"
                Cell.Fire("UpdateTools", "buffTracker")
            end,
        },
        {
            ["text"] = L["right-to-left"],
            ["value"] = "right-to-left",
            ["onClick"] = function()
                CellDB["tools"]["buffTracker"][2] = "right-to-left"
                Cell.Fire("UpdateTools", "buffTracker")
            end,
        },
        {
            ["text"] = L["top-to-bottom"],
            ["value"] = "top-to-bottom",
            ["onClick"] = function()
                CellDB["tools"]["buffTracker"][2] = "top-to-bottom"
                Cell.Fire("UpdateTools", "buffTracker")
            end,
        },
        {
            ["text"] = L["bottom-to-top"],
            ["value"] = "bottom-to-top",
            ["onClick"] = function()
                CellDB["tools"]["buffTracker"][2] = "bottom-to-top"
                Cell.Fire("UpdateTools", "buffTracker")
            end,
        },
    })

    -- Buff 图标尺寸编辑框：输入数字（如 16, 20, 24）来自定义 Buff 追踪器图标大小
    sizeEditBox = Cell.CreateEditBox(rtPane, 38, 20, false, false, true)
    sizeEditBox:SetPoint("TOPLEFT", buffDropdown, "TOPRIGHT", 5, 0)
    sizeEditBox:SetMaxLetters(3) -- 限制输入最多3个字符（最大尺寸999）

    -- 尺寸确认按钮（OK）：仅当输入的值与当前值不同时显示，点击后保存新尺寸
    sizeEditBox.confirmBtn = Cell.CreateButton(rtPane, "OK", "accent", {27, 20})
    sizeEditBox.confirmBtn:SetPoint("TOPLEFT", sizeEditBox, "TOPRIGHT", P.Scale(-1), 0)
    sizeEditBox.confirmBtn:Hide()
    sizeEditBox.confirmBtn:SetScript("OnHide", function()
        sizeEditBox.confirmBtn:Hide() -- 隐藏时再次确保自身隐藏
    end)
    sizeEditBox.confirmBtn:SetScript("OnClick", function()
        CellDB["tools"]["buffTracker"][3] = tonumber(sizeEditBox:GetText())
        Cell.Fire("UpdateTools", "buffTracker")
        sizeEditBox.confirmBtn:Hide()
        sizeEditBox:ClearFocus()
    end)

    -- OnTextChanged 事件：用户手动输入时，如果新值有效且与当前值不同则显示确认按钮
    sizeEditBox:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            local newSize = tonumber(self:GetText())
            if newSize and newSize > 0 and newSize ~= CellDB["tools"]["buffTracker"][3] then
                sizeEditBox.confirmBtn:Show()
            else
                sizeEditBox.confirmBtn:Hide()
            end
        end
    end)

    -- 经典版本（Vanilla/TBC/Wrath/Cata）创建 Buff 图标按钮：每个 Buff 类型一个可点击图标
    if Cell.isVanilla or Cell.isTBC or Cell.isWrath or Cell.isCata then
        buffButtons = {}

        local buffOrder, buffs = U.GetBuffTrackerInfo() -- 获取 Buff 列表和图标信息

        local last
        for i, buff in ipairs(buffOrder) do
            -- 创建单个 Buff 图标按钮，20x20 像素
            local b = Cell.CreateButton(rtPane, "", "accent-hover", {20, 20})
            buffButtons[buff] = b

            -- 按钮上的 Buff 图标纹理（使用 0.08-0.92 纹理坐标裁剪边框以去除图标自带边框）
            local tex = b:CreateTexture(nil, "ARTWORK")
            P.Point(tex, "TOPLEFT", b, "TOPLEFT", 1, -1)
            P.Point(tex, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
            tex:SetTexture(buffs[buff]["buff1"]["icon"])
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- 启用时图标显示正常色彩
            b:SetScript("OnEnable", function()
                tex:SetDesaturated(false)
            end)
            -- 禁用时图标变为灰色（去饱和）
            b:SetScript("OnDisable", function()
                tex:SetDesaturated(true)
            end)

            -- 点击切换是否追踪该 Buff：已追踪状态不透明度为1，未追踪为0.25
            b:SetScript("OnClick", function()
                CellDB["tools"]["buffTracker"][5][buff] = not CellDB["tools"]["buffTracker"][5][buff]
                Cell.Fire("UpdateTools", "buffTracker")
                if CellDB["tools"]["buffTracker"][5][buff] then
                    b:SetAlpha(1)
                else
                    b:SetAlpha(0.25)
                end
            end)

            -- 水平排列：第一个按钮定位在尺寸编辑框右侧，后续按钮依次向右排列
            if last then
                b:SetPoint("TOPLEFT", last, "TOPRIGHT", 2, 0)
            else
                b:SetPoint("TOPLEFT", sizeEditBox, "TOPRIGHT", 5, 0)
            end

            last = b
        end
    end

    -- 就绪检查与倒计时按钮设置
    -- 就绪检查/倒计时按钮主开关：勾选后启用就绪检查和拉怪倒计时按钮，同时启用样式、插件、秒数子控件
    readyPullCB = Cell.CreateCheckButton(rtPane, L["ReadyCheck and PullTimer buttons"], function(checked, self)
        CellDB["tools"]["readyAndPull"][1] = checked
        styleDropdown:SetEnabled(checked)
        pullDropdown:SetEnabled(checked)
        secEditBox:SetEnabled(checked)
        Cell.Fire("UpdateTools", "buttons")
    end, L["ReadyCheck and PullTimer buttons"], L["Only show when you have permission to do this"], L["readyCheckTips"], L["pullTimerTips"])
    readyPullCB:SetPoint("TOPLEFT", buffCB, "BOTTOMLEFT", 0, -43)
    Cell.RegisterForCloseDropdown(readyPullCB) -- 点击按钮时关闭已打开的下拉框

    -- 就绪/倒计时按钮样式下拉框：文字按钮 / 图标按钮水平 / 图标按钮垂直
    styleDropdown = Cell.CreateDropdown(rtPane, 120)
    styleDropdown:SetPoint("TOPLEFT", readyPullCB, "BOTTOMRIGHT", 5, -5)
    styleDropdown:SetItems({
        {
            ["text"] = L["Ready"].." / "..L["Pull"],
            ["value"] = "text_button",
            ["onClick"] = function()
                CellDB["tools"]["readyAndPull"][2] = "text_button"
                Cell.Fire("UpdateTools", "readyAndPull")
            end,
        },
        {
            ["text"] = "|TInterface\\AddOns\\Cell\\Media\\Icons\\ready:14|t / |TInterface\\AddOns\\Cell\\Media\\Icons\\pull:14|t A",
            ["value"] = "icon_button_h",
            ["onClick"] = function()
                CellDB["tools"]["readyAndPull"][2] = "icon_button_h"
                Cell.Fire("UpdateTools", "readyAndPull")
            end,
        },
        {
            ["text"] = "|TInterface\\AddOns\\Cell\\Media\\Icons\\ready:14|t / |TInterface\\AddOns\\Cell\\Media\\Icons\\pull:14|t B",
            ["value"] = "icon_button_v",
            ["onClick"] = function()
                CellDB["tools"]["readyAndPull"][2] = "icon_button_v"
                Cell.Fire("UpdateTools", "readyAndPull")
            end,
        },
    })

    -- 倒计时插件来源下拉框：选择使用哪个插件执行倒计时（默认系统/MRT/DBM/BigWigs）
    pullDropdown = Cell.CreateDropdown(rtPane, 109)
    pullDropdown:SetPoint("TOPLEFT", styleDropdown, "TOPRIGHT", 5, 0)
    pullDropdown:SetItems({
        {
            ["text"] = L["Default"],
            ["value"] = "default",
            ["onClick"] = function()
                CellDB["tools"]["readyAndPull"][3][1] = "default"
                Cell.Fire("UpdateTools", "readyAndPull")
            end,
        },
        {
            ["text"] = "MRT",
            ["value"] = "mrt",
            ["onClick"] = function()
                CellDB["tools"]["readyAndPull"][3][1] = "mrt"
                Cell.Fire("UpdateTools", "readyAndPull")
            end,
        },
        {
            ["text"] = "DBM",
            ["value"] = "dbm",
            ["onClick"] = function()
                CellDB["tools"]["readyAndPull"][3][1] = "dbm"
                Cell.Fire("UpdateTools", "readyAndPull")
            end,
        },
        {
            ["text"] = "BigWigs",
            ["value"] = "bw",
            ["onClick"] = function()
                CellDB["tools"]["readyAndPull"][3][1] = "bw"
                Cell.Fire("UpdateTools", "readyAndPull")
            end,
        },
    })

    -- 倒计时秒数编辑框：输入数字自定义倒计时时长（如 5, 10, 15 秒）
    secEditBox = Cell.CreateEditBox(rtPane, 38, 20, false, false, true)
    secEditBox:SetPoint("TOPLEFT", pullDropdown, "TOPRIGHT", 5, 0)
    secEditBox:SetMaxLetters(3) -- 限制输入最多3个字符

    -- 秒数确认按钮（OK）：仅当输入的值与当前值不同时显示，点击后保存新秒数
    secEditBox.confirmBtn = Cell.CreateButton(rtPane, "OK", "accent", {27, 20})
    secEditBox.confirmBtn:SetPoint("TOPLEFT", secEditBox, "TOPRIGHT", P.Scale(-1), 0)
    secEditBox.confirmBtn:Hide()
    secEditBox.confirmBtn:SetScript("OnHide", function()
        secEditBox.confirmBtn:Hide()
    end)
    secEditBox.confirmBtn:SetScript("OnClick", function()
        CellDB["tools"]["readyAndPull"][3][2] = tonumber(secEditBox:GetText())
        Cell.Fire("UpdateTools", "readyAndPull")
        secEditBox.confirmBtn:Hide()
    end)

    -- OnTextChanged 事件：用户手动输入时，如果新值有效且与当前值不同则显示确认按钮
    secEditBox:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            local newSec = tonumber(self:GetText())
            if newSec and newSec > 0 and newSec ~= CellDB["tools"]["readyAndPull"][3][2] then
                secEditBox.confirmBtn:Show()
            else
                secEditBox.confirmBtn:Hide()
            end
        end
    end)

    -- 标记栏设置 -- 在游戏中显示目标标记/世界标记的快捷栏
    -- 标记栏主开关：勾选后启用标记栏，同时启用标记样式下拉框和"仅自己时显示"开关
    marksBarCB = Cell.CreateCheckButton(rtPane, L["Marks Bar"], function(checked, self)
        CellDB["tools"]["marks"][1] = checked
        marksDropdown:SetEnabled(checked)
        marksShowSoloCB:SetEnabled(checked)
        Cell.Fire("UpdateTools", "marks")
    end, L["Marks Bar"], L["Only show when you have permission to do this"], L["marksTips"])
    marksBarCB:SetPoint("TOPLEFT", readyPullCB, "BOTTOMLEFT", 0, -43)
    Cell.RegisterForCloseDropdown(marksBarCB) -- 点击按钮时关闭已打开的下拉框

    -- 标记栏样式下拉框：目标标记/世界标记/两者 x 水平/垂直，共6种组合（经典版本禁用世界标记相关选项）
    marksDropdown = Cell.CreateDropdown(rtPane, 217)
    marksDropdown:SetPoint("TOPLEFT", marksBarCB, "BOTTOMRIGHT", 5, -5)
    marksDropdown:SetItems({
        {
            ["text"] = L["Target Marks"].." ("..L["Horizontal"]..")",
            ["value"] = "target_h",
            ["onClick"] = function()
                CellDB["tools"]["marks"][3] = "target_h"
                Cell.Fire("UpdateTools", "marks")
            end,
        },
        {
            ["text"] = L["Target Marks"].." ("..L["Vertical"]..")",
            ["value"] = "target_v",
            ["onClick"] = function()
                CellDB["tools"]["marks"][3] = "target_v"
                Cell.Fire("UpdateTools", "marks")
            end,
        },
        {
            ["text"] = L["World Marks"].." ("..L["Horizontal"]..")",
            ["value"] = "world_h",
            ["disabled"] = Cell.isVanilla or Cell.isTBC or Cell.isWrath,
            ["onClick"] = function()
                CellDB["tools"]["marks"][3] = "world_h"
                Cell.Fire("UpdateTools", "marks")
            end,
        },
        {
            ["text"] = L["World Marks"].." ("..L["Vertical"]..")",
            ["value"] = "world_v",
            ["disabled"] = Cell.isVanilla or Cell.isTBC or Cell.isWrath,
            ["onClick"] = function()
                CellDB["tools"]["marks"][3] = "world_v"
                Cell.Fire("UpdateTools", "marks")
            end,
        },
        {
            ["text"] = L["Both"].." ("..L["Horizontal"]..")",
            ["value"] = "both_h",
            ["disabled"] = Cell.isVanilla or Cell.isTBC or Cell.isWrath,
            ["onClick"] = function()
                CellDB["tools"]["marks"][3] = "both_h"
                Cell.Fire("UpdateTools", "marks")
            end,
        },
        {
            ["text"] = L["Both"].." ("..L["Vertical"]..")",
            ["value"] = "both_v",
            ["disabled"] = Cell.isVanilla or Cell.isTBC or Cell.isWrath,
            ["onClick"] = function()
                CellDB["tools"]["marks"][3] = "both_v"
                Cell.Fire("UpdateTools", "marks")
            end,
        }
    })

    -- "仅自己时也显示"开关：勾选后即使只有自己一个人在队伍中也显示标记栏
    marksShowSoloCB = Cell.CreateCheckButton(rtPane, L["Show Solo"], function(checked, self)
        CellDB["tools"]["marks"][2] = checked
        Cell.Fire("UpdateTools", "marks")
    end)
    marksShowSoloCB:SetPoint("TOPLEFT", marksDropdown, "BOTTOMLEFT", 0, -8)

    -- 鼠标离开时淡出这些按钮：勾选后当鼠标移开时淡化团队工具按钮
    fadeOutToolsCB = Cell.CreateCheckButton(rtPane, L["Fade Out These Buttons"], function(checked, self)
        CellDB["tools"]["fadeOut"] = checked
        Cell.Fire("UpdateTools", "fadeOut")
    end)
    fadeOutToolsCB:SetPoint("TOPLEFT", marksBarCB, "BOTTOMLEFT", 0, -70)

    -- 高亮区域：覆盖从 buffCB 到 marksShowSoloCB 之间的所有控件
    -- 鼠标悬停在 fadeOutToolsCB 上时，该区域显示像素光晕以指示哪些按钮会被淡出影响
    local region = CreateFrame("Frame", nil, rtPane)
    region:SetPoint("TOPLEFT", buffCB, -5, 5)
    region:SetPoint("BOTTOM", marksShowSoloCB, 0, -5)
    region:SetPoint("RIGHT", -5, 0)

    fadeOutToolsCB:HookScript("OnEnter", function()
        LCG.PixelGlow_Start(region, Cell.GetAccentColorTable(1), 27, 0.1, 17, 1)
    end)
    fadeOutToolsCB:HookScript("OnLeave", function()
        LCG.PixelGlow_Stop(region)
    end)
end

-------------------------------------------------
-- 面板显示/隐藏控制：由 "ShowUtilitySettings" 回调触发
-------------------------------------------------
local init -- 首次初始化标记，确保面板只创建一次
local function ShowUtilitySettings(which)
    if which == "raidTools" then
        -- 首次调用时创建面板并应用战斗保护（战斗中自动隐藏面板的4边各偏移4像素的安全边距）
        if not init then
            CreateRTPane()
            F.ApplyCombatProtectionToFrame(rtPane, -4, 4, 4, -4)
        end

        rtPane:Show() -- 显示面板

        -- if init then return end
        init = true

        -- 将 CellDB 中保存的设置同步到面板各控件的显示状态
        -- 战斗复活计时器状态同步
        resCB:SetChecked(CellDB["tools"]["battleResTimer"][1])
        resDetachCB:SetChecked(CellDB["tools"]["battleResTimer"][2])
        resDetachCB:SetEnabled(Cell.isRetail and CellDB["tools"]["battleResTimer"][1])
        -- 死亡报告状态同步
        reportCB:SetChecked(CellDB["tools"]["deathReport"][1])

        -- Buff 追踪器状态同步（主开关、布局方向、图标尺寸、经典版按钮状态）
        buffCB:SetChecked(CellDB["tools"]["buffTracker"][1])
        buffDropdown:SetSelectedValue(CellDB["tools"]["buffTracker"][2])
        sizeEditBox:SetText(CellDB["tools"]["buffTracker"][3])
        Cell.SetEnabled(CellDB["tools"]["buffTracker"][1], buffDropdown, sizeEditBox)
        if buffButtons then
            for buff, b in pairs(buffButtons) do
                b:SetEnabled(CellDB["tools"]["buffTracker"][1])
                b:SetAlpha(CellDB["tools"]["buffTracker"][5][buff] and 1 or 0.25)
            end
        end

        -- 就绪检查/倒计时状态同步（主开关、按钮样式、插件来源、倒计时秒数）
        readyPullCB:SetChecked(CellDB["tools"]["readyAndPull"][1])
        styleDropdown:SetSelectedValue(CellDB["tools"]["readyAndPull"][2])
        pullDropdown:SetSelectedValue(CellDB["tools"]["readyAndPull"][3][1])
        secEditBox:SetText(CellDB["tools"]["readyAndPull"][3][2])
        Cell.SetEnabled(CellDB["tools"]["readyAndPull"][1], styleDropdown, pullDropdown, secEditBox)

        -- 标记栏状态同步（主开关、样式选择、仅自己时显示）
        marksDropdown:SetEnabled(CellDB["tools"]["marks"][1])
        marksBarCB:SetChecked(CellDB["tools"]["marks"][1])
        marksDropdown:SetSelectedValue(CellDB["tools"]["marks"][3])
        marksShowSoloCB:SetChecked(CellDB["tools"]["marks"][2])

        -- 淡出按钮状态同步
        fadeOutToolsCB:SetChecked(CellDB["tools"]["fadeOut"])

    elseif init then
        -- 切换到其他工具面板时隐藏本面板
        rtPane:Hide()
    end
end
-- 注册回调：当用户切换到"团队工具"设置页时，Cell 核心会触发 "ShowUtilitySettings" 事件
Cell.RegisterCallback("ShowUtilitySettings", "RaidTools_ShowUtilitySettings", ShowUtilitySettings)