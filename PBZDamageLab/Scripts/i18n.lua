-- Panel text in the game's language. Chinese for zh*, English for everything else.
-- Accessory and weapon names are not here: they are read from the game's own localization.
local M={}

local STRINGS={
    zh={
        title='伤害实验室',hide='%s 隐藏',
        press_summon='按 %s 召唤木桩',removed='木桩已移除，按 %s 召唤',initializing='木桩初始化中…',
        ready='木桩就绪',reset='统计已重置',
        saved='本轮已存为 %s',cleared='对比已清空',scene_changed='场景或角色已切换，木桩已清理',failed='操作失败：%s',
        err_enter_scene='请先进入可自由行动的场景',err_summon_first='先召唤木桩',err_no_ground='前方没有平坦地面',
        err_load='无法加载木桩资产',err_no_space='前方空间不足',
        dummy_hp='木桩生命',
        stats='统计',hits_total='命中 / 总伤害',max_hit='最高一击',combo_cur='当前连招',combo_last='上一段连招',
        combo_detail='  命中 / 时长 / DPS',
        recent='最近命中',dmg='伤害',formula='基础 × 独立 × 加算 × 增幅',no_hits='还没有命中',
        accessories='饰品',attack='攻击',support='辅助',survival='生存',no_acc='未检测到饰品',no_attack_acc='无攻击饰品',
        compare='方案对比',set='方案',per_combo='每段平均  相对A',
        keys='按键',keys1='%s 召唤  %s 重置  %s 移除',keys2='%s/%s/%s 存ABC  %s 清空',
        pool_mul='独立',pool_addmul='加算',pool_addpre='受击加算',pool_amp='增幅',pool_vuln='增伤',pool_elem='元素',pool_na='无伤害加成',
        w_ShachiWeapon='影之武装',w_ShachiAbility='杀气技',w_PerfectDodge='完美闪避',w_Common='通用',w_other='其他',w_Execution='处决',w_pending='通用招式（待定）',
        live_fan='%+.0f%%（移动 %.1f m）',live_duo='%+.0f%%（杀气 %.0f%%）',live_bighit='%+.0f%%（蓄力）',
        mode='模式',mode_dummy='木桩',mode_combat='实战（统计所有敌人）',combat_on='实战模式：开',combat_off='实战模式：关',
        shachi_total='杀气削减',combo_shachi='  杀气削减',
        timer='定时测试',timer_armed='定时测试 %s 秒：打出第一击开始',timer_wait='等待第一击（%d 秒）',
        timer_left='进行中，剩 %.1fs',timer_done='%d 秒结果',timer_detail='  DPS / 命中 / 杀气削减',timer_detail_hp='  DPS / 命中',
        exported='已导出：%s',export_empty='还没有命中，无可导出',export_failed='导出失败（exports 文件夹）',
        export_where='已导出到游戏目录下：',
        combat_badge='● 实战模式',timer_stopped='定时测试已提前结束',timer_cancelled='定时测试已取消',
        timer_hint_cancel='  再按 %s 取消',timer_hint_stop='  再按 %s 提前结束',timer_hint_again='  再按 %s 重新开始',
        version_warn='⚠ 游戏版本 %s 未经验证',
        keys3='%s 实战模式  %s 定时测试  %s 导出',
    },
    en={
        title='Damage Lab',hide='%s hide',
        press_summon='Press %s to summon the dummy',removed='Dummy removed, press %s to summon',initializing='Dummy initializing…',
        ready='Dummy ready',reset='Stats reset',
        saved='Round saved as %s',cleared='Comparison cleared',scene_changed='Scene changed, dummy removed',failed='Failed: %s',
        err_enter_scene='Enter a playable scene first',err_summon_first='Summon the dummy first',err_no_ground='No flat ground ahead',
        err_load='Cannot load the dummy asset',err_no_space='Not enough space ahead',
        dummy_hp='Dummy HP',
        stats='Stats',hits_total='Hits / Total',max_hit='Highest hit',combo_cur='Current combo',combo_last='Last combo',
        combo_detail='  Hits / Time / DPS',
        recent='Recent hits',dmg='Damage',formula='Base × Mult × Add × Amp',no_hits='No hits yet',
        accessories='Accessories',attack='Attack',support='Support',survival='Survival',no_acc='No accessories detected',no_attack_acc='No attack accessories',
        compare='Compare',set='Set',per_combo='Avg/combo  vs A',
        keys='Keys',keys1='%s Summon  %s Reset  %s Remove',keys2='%s/%s/%s Save ABC  %s Clear',
        pool_mul='Mult',pool_addmul='Add',pool_addpre='On-hit add',pool_amp='Amp',pool_vuln='Dmg up',pool_elem='Element',pool_na='No dmg bonus',
        w_ShachiWeapon='Phantom Edge',w_ShachiAbility='Sha-Chi skill',w_PerfectDodge='Perfect dodge',w_Common='Common',w_other='Other',w_Execution='Execution',w_pending='Shared moves (pending)',
        live_fan='%+.0f%% (moved %.1f m)',live_duo='%+.0f%% (Sha-Chi %.0f%%)',live_bighit='%+.0f%% (charged)',
        mode='Mode',mode_dummy='Dummy',mode_combat='Combat (all enemies)',combat_on='Combat mode on',combat_off='Combat mode off',
        shachi_total='Sha-Chi damage',combo_shachi='  Sha-Chi damage',
        timer='Timed test',timer_armed='Timed test %s s: starts on your first hit',timer_wait='Waiting for first hit (%d s)',
        timer_left='Running, %.1fs left',timer_done='%d s result',timer_detail='  DPS / Hits / Sha-Chi',timer_detail_hp='  DPS / Hits',
        exported='Exported: %s',export_empty='No hits to export yet',export_failed='Export failed (exports folder)',
        export_where='Saved in the game folder:',
        combat_badge='● Combat mode',timer_stopped='Timed test stopped early',timer_cancelled='Timed test cancelled',
        timer_hint_cancel='  Press %s again to cancel',timer_hint_stop='  Press %s again to stop',timer_hint_again='  Press %s again to restart',
        version_warn='⚠ Game version %s not verified',
        keys3='%s Combat mode  %s Timed test  %s Export',
    },
}

M.lang='en'
M.override=nil -- 'zh' / 'en' from config.ini, nil = follow the game

function M.detect()
    if M.override=='zh' or M.override=='en' then M.lang=M.override;return M.lang end
    -- FString results come back either as a Lua string or as an object with ToString().
    local function str(v) if type(v)=='string' then return v end return v:ToString() end
    local lib=StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary')
    local ok,code=pcall(function() return str(lib:GetCurrentLanguage()) end)
    if not ok or type(code)~='string' or code=='' then
        ok,code=pcall(function() return str(lib:GetCurrentCulture()) end)
    end
    M.code=ok and code or nil
    if ok and type(code)=='string' and code~='' then
        M.lang=code:lower():sub(1,2)=='zh' and 'zh' or 'en'
    end
    return M.lang
end

-- T('key', ...) formats the string for the current language; unknown keys return the key itself.
function M.T(key,...)
    local s=(STRINGS[M.lang] or STRINGS.en)[key] or STRINGS.en[key] or key
    if select('#',...)>0 then return string.format(s,...) end
    return s
end

return M
