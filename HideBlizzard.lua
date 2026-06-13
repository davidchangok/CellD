-- CellD 模块入口：通过变长参数 ... 接收加载器传入的 Cell 全局表
local _, Cell = ...
-- 获取 Cell 的函数工具表，后续通过 F.xxx 方式调用公共函数
local F = Cell.funcs

-- 隐藏父框架：用作所有被隐藏的暴雪原生框架的"回收站"父级
-- 将框架的父级设为此隐藏框架后，框架不会显示且不受 UIParent 显示/隐藏影响
-- stolen from elvui / 此技巧源自 ElvUI
local hiddenParent = CreateFrame("Frame", nil, _G.UIParent)
hiddenParent:SetAllPoints()
hiddenParent:Hide()

-- ============================================================================
-- HideFrame(frame) — 彻底隐藏一个暴雪原生单位框架
--   1. 取消框架及所有已知子元素（血条、能量条、施法条等）的全部事件注册
--   2. 隐藏框架本体
--   3. 将框架的父级重新设到 hiddenParent（"回收站"），防止后续代码将其重新显示
--   这样做的目的是让暴雪原生框架不再消耗任何 CPU 资源响应事件
--   子元素的 UnregisterAllEvents 防止它们独立于父框架响应事件
-- ============================================================================
local function HideFrame(frame)
    -- 防御性检查：框架不存在则直接返回
    if not frame then return end

    -- 取消框架自身所有事件注册并隐藏
    frame:UnregisterAllEvents()
    frame:Hide()
    -- 重设父级到隐藏容器，彻底阻断其显示路径
    frame:SetParent(hiddenParent)

    -- 子元素：血条（兼容 healthBar 和 healthbar 两种命名风格）
    local health = frame.healthBar or frame.healthbar
    if health then
        health:UnregisterAllEvents()
    end

    -- 子元素：能量条/法力条
    local power = frame.manabar
    if power then
        power:UnregisterAllEvents()
    end

    -- 子元素：施法条（兼容 castBar 和 spellbar 两种命名）
    local spell = frame.castBar or frame.spellbar
    if spell then
        spell:UnregisterAllEvents()
    end

    -- 子元素：特殊能量条（如首领战的特殊资源条）
    local altpowerbar = frame.powerBarAlt
    if altpowerbar then
        altpowerbar:UnregisterAllEvents()
    end

    -- 子元素：Buff 图标框
    local buffFrame = frame.BuffFrame
    if buffFrame then
        buffFrame:UnregisterAllEvents()
    end

    -- 子元素：宠物框架（队伍成员框架可能内嵌宠物血条）
    local petFrame = frame.PetFrame
    if petFrame then
        petFrame:UnregisterAllEvents()
    end
end

-- ============================================================================
-- HideBlizzardParty() — 隐藏暴雪原生小队框架
--   1. 取消 UIParent 上的 GROUP_ROSTER_UPDATE 事件监听（防止暴雪代码据此重建队伍框架）
--   2. 处理 CompactPartyFrame（紧凑型小队框架，自 WOD 资料片引入）
--   3. 处理 PartyFrame（经典小队框架）及其成员对象池中的每个活跃成员
--   4. 兜底：按索引名处理旧版遗留的小队成员框架
-- ============================================================================
function F.HideBlizzardParty()
    -- 取消 UIParent 对队伍列表更新事件的监听，从根源阻止暴雪重建队伍框架
    _G.UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")

    -- Midnight 12.0.0+ may have different party frame structure
    -- 注意 Midnight (12.0) 扩展包可能改变了队伍框架结构，此处兼容处理
    if _G.CompactPartyFrame then
        _G.CompactPartyFrame:UnregisterAllEvents()
        _G.CompactPartyFrame:SetParent(hiddenParent)
    end

    if _G.PartyFrame then
        -- 取消事件并清除 OnShow 脚本（防止 Show() 时重新注册事件）
        _G.PartyFrame:UnregisterAllEvents()
        _G.PartyFrame:SetScript("OnShow", nil)
        -- 遍历 PartyFrame 的成员对象池，逐一隐藏所有已激活的成员框架
        if _G.PartyFrame.PartyMemberFramePool then
            for frame in _G.PartyFrame.PartyMemberFramePool:EnumerateActive() do
                HideFrame(frame)
            end
        end
        -- 最后隐藏 PartyFrame 自身
        HideFrame(_G.PartyFrame)
    else
        -- Legacy party frame fallback / 旧版遗留小队框架兜底（怀旧服或极早期版本）
        for i = 1, 4 do
            HideFrame(_G["PartyMemberFrame"..i])
            HideFrame(_G["CompactPartyMemberFrame"..i])
        end
        if _G.PartyMemberBackground then
            HideFrame(_G.PartyMemberBackground)
        end
    end
end

-- ============================================================================
-- HideBlizzardRaid() — 隐藏暴雪原生团队框架
--   暴雪团队框架使用 CompactRaidFrameContainer 作为容器，内部管理所有团队成员框架
--   将其父级设为 hiddenParent 后，整个团队界面即被隐藏
--   同时取消 GROUP_ROSTER_UPDATE 事件防止重建
-- ============================================================================
function F.HideBlizzardRaid()
    -- 取消 UIParent 对队伍列表更新事件的监听，防止暴雪重建团队框架
    _G.UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")

    if _G.CompactRaidFrameContainer then
        _G.CompactRaidFrameContainer:UnregisterAllEvents()
        _G.CompactRaidFrameContainer:SetParent(hiddenParent)
    end
end

-- ============================================================================
-- HideBlizzardRaidManager() — 隐藏暴雪团队管理面板（左侧边栏）
--   团队管理面板是屏幕左侧的竖向面板，包含队伍排列、角色标记等功能
--   通过 SetSetting("IsShown", "0") 将其标记为不显示（持久化设置），
--   然后将框架容器挂到 hiddenParent 下彻底隐藏
-- ============================================================================
function F.HideBlizzardRaidManager()
    -- 持久化设置：将团队管理器的显示状态设为"不显示"(0)，防止 /reload 后重新出现
    if CompactRaidFrameManager_SetSetting then
        CompactRaidFrameManager_SetSetting("IsShown", "0")
    end

    if _G.CompactRaidFrameManager then
        _G.CompactRaidFrameManager:UnregisterAllEvents()
        _G.CompactRaidFrameManager:SetParent(hiddenParent)
    end
end