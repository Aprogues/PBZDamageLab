-- PBZDamageLab: training dummy + damage breakdown + equipped accessory pools/triggers.
-- Hotkeys come from PBZDamageLab/config.ini (defaults: F6 panel, F7 summon, F8 reset, F9 remove,
-- F1/F2/F3 save A/B/C, F4 clear, Insert combat mode, Home timed test, End export). No menu takes
-- input, the camera stays free. Text follows the game language (Chinese for zh*, English otherwise);
-- names come from the game.
local VERSION='1.0.0'
local DIR=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local function log(s) print('[PBZDamageLab] '..tostring(s)..'\n') end
local DEBUG=false -- set from config.ini [Debug] Debug; per-hit lines only go to the log when it is on
local function dlog(s) if DEBUG then log(s) end end

local Config=dofile(DIR..'config.lua')
local I18n=dofile(DIR..'i18n.lua')
local Dummy=dofile(DIR..'dummy.lua')
local Probes=dofile(DIR..'probes.lua')
local Stats=dofile(DIR..'stats.lua')
local Hud=dofile(DIR..'hud.lua')
local Accessories=dofile(DIR..'accessories.lua')
local Weapons=dofile(DIR..'weapons.lua')
local T=I18n.T

local cfg=Config.load(DIR..'../config.ini',log)
DEBUG=tostring(cfg.Debug or ''):lower()=='true'
Hud.POSITION=cfg.Position
Hud.FONT=tonumber(cfg.FontSize) or 11
Hud.log=log
Stats.RECENT=4
local langCfg=(cfg.Language or 'Auto'):lower()
I18n.override=(langCfg=='zh' or langCfg=='en') and langCfg or nil

Probes.init(Accessories)
Probes.debug=DEBUG
Probes.player=Dummy.player
Probes.clock=Dummy.now
Probes.T=T
Probes.lang=function() return I18n.lang end

local state=Stats.new()
local actor,world,owner,readyAt
local ready=false
-- Status is kept as a string key plus arguments and translated when drawn.
local status={'press_summon',cfg.Summon}
local damageHooked=false
local lastEquipScan,lastLangCheck=-100,-100
local lastHudError
local pinned={}
local function pin(fn) pinned[#pinned+1]=fn;return fn end

local function setStatus(key,...) status={key,...} end
local function statusText()
    local args={}
    for i=2,#status do args[#args+1]=T(tostring(status[i])) end
    return T(status[1],table.unpack(args))
end

local function remove(key)
    local old=actor
    actor=nil;world=nil;owner=nil;readyAt=nil;ready=false
    Dummy.destroy(old)
    if key then setStatus(key) else setStatus('removed',cfg.Summon) end
end

-- Combat mode: also count the player's damage to every enemy (bosses included), not only the dummy.
local combat=false
-- Mod folder (…\ue4ss\Mods\PBZDamageLab); exports go to its exports subfolder.
local MODDIR=DIR:gsub('[/\\]Scripts[/\\]?$','')
local exportedPath,exportedAt=nil,0
local homeLoc,lastDummyHit=nil,-100 -- where the dummy was summoned / when it was last hit
local snapCount=0 -- how often the position lock had to put the dummy back (log only)

local function shortClass(o)
    local ok,n=pcall(function() return o:GetClass():GetFName():ToString() end)
    if not ok then return '?' end
    return (n:gsub('^BP_Monster_',''):gsub('^BP_',''):gsub('_C$',''))
end

local onDamage=pin(function(context,event)
    local ok,err=pcall(function()
        local avatar=context:get():GetAvatarActorFromActorInfo()
        if not Dummy.valid(avatar) then return end
        local isDummy=ready and Dummy.valid(actor) and avatar:GetAddress()==actor:GetAddress()
        if not isDummy and not combat then return end
        local p=Dummy.player()
        if not isDummy and p and avatar:GetAddress()==p:GetAddress() then return end -- damage the player took
        local payload=event:get().OptionalObject
        if not Dummy.valid(payload) or payload:GetClass():GetFName():ToString()~='DamageTakenPayload' then return end
        local amount,tags,shachi=Dummy.damage(payload)
        if amount<=0 and shachi<=0 then return end
        local now=Dummy.now(avatar)
        local m=Probes.consume(payload,p,now)
        if not isDummy and not m.fromPlayer then return end -- enemies hurting each other, traps …
        if m.weapon=='Execution' then return end -- executions are not counted
        if Probes.lastHit then Probes.lastHit.tags=tags end
        local denom=m.mul*(1+m.addm)*(1+(m.amp or 0))
        local hit={dmg=amount,shachi=shachi,t=now,mul=m.mul,addm=m.addm,amp=m.amp,source=m.source,weapon=m.weapon,
            fallback=m.fallback,target=isDummy and 'Dummy' or shortClass(avatar),base=denom>0 and amount/denom or amount}
        Stats.record(state,hit)
        if isDummy then
            lastDummyHit=now
            if Dummy.health(actor)<=1 then Dummy.heal(actor) end
        end
        dlog(string.format('HIT dmg=%.4f shachi=%.4f mul=%.4f addm=%.4f amp=%s base=%.4f source=%s weapon=%s target=%s tags=%s',
            hit.dmg,shachi,hit.mul,hit.addm,tostring(hit.amp),hit.base,tostring(hit.source),tostring(hit.weapon),
            hit.target,table.concat(tags,',')))
    end)
    if not ok then log('damage: '..tostring(err)) end
end)

local function ensureHooks()
    if damageHooked then return end
    RegisterHook(Dummy.damageHook,onDamage)
    Probes.installHooks(log)
    damageHooked=true
end

local function spawn()
    local p=Dummy.player();assert(p,'err_enter_scene')
    local t,cls=Dummy.position(p,actor)
    if not t then setStatus(cls);return end
    ensureHooks()
    remove()
    actor=Dummy.spawn(p,t,cls);world=Dummy.world(p);owner=p:GetAddress()
    readyAt=Dummy.now(p)+1.0
    setStatus('initializing')
    log('spawned '..actor:GetFullName())
end

local function guarded(fn)
    return function()
        ExecuteInGameThread(function()
            local ok,err=pcall(fn)
            if not ok then
                log(err)
                -- assert() messages are i18n keys; strip the "file:line:" prefix Lua adds.
                local msg=tostring(err):gsub('^.-:%d+: ','')
                setStatus('failed',msg)
            end
        end)
    end
end

local function equippedLabel()
    local names={}
    for _,e in ipairs(Probes.equipped()) do
        if e.acc.type=='attack' then names[#names+1]=Probes.name(e.acc,e.lv,log) end
    end
    return #names>0 and table.concat(names,'+') or T('no_attack_acc')
end

local function weaponName(folder)
    local key=Weapons[folder]
    local n=key and Probes.text(key,log)
    if n then return n end
    local w=T('w_'..tostring(folder))
    if w~='w_'..tostring(folder) then return w end
    return folder=='其他' and T('w_other') or tostring(folder)
end

local function bind(action,fn)
    local spec=cfg[action]
    local key,mods=Config.key(spec)
    if not key then log('invalid key for '..action..': '..tostring(spec));return end
    if #mods>0 then RegisterKeyBind(key,mods,fn) else RegisterKeyBind(key,fn) end
end

bind('TogglePanel',function() ExecuteInGameThread(function() pcall(Hud.toggle) end) end)
bind('Summon',guarded(spawn))
bind('Remove',guarded(function() remove() end))
bind('Reset',guarded(function()
    Stats.reset(state)
    if ready and Dummy.valid(actor) then Dummy.heal(actor) end
    setStatus('reset')
end))
for _,slot in ipairs({'A','B','C'}) do
    bind('Save'..slot,guarded(function()
        Stats.save(state,slot,equippedLabel())
        setStatus('saved',slot)
    end))
end
bind('ClearCompare',guarded(function() Stats.clearSlots(state);setStatus('cleared') end))
bind('CombatMode',guarded(function()
    combat=not combat
    if combat then ensureHooks() end
    setStatus(combat and 'combat_on' or 'combat_off')
    log('combat mode '..(combat and 'on' or 'off'))
end))
bind('TimedTest',guarded(function()
    local seconds=tonumber(cfg.TimedSeconds) or 30
    local p=Dummy.player()
    local key=Stats.timerPress(state,seconds,p and Dummy.now(p) or 0)
    setStatus(key,tostring(seconds))
end))
-- Export only when asked: one CSV per key press, in PBZDamageLab/exports.
bind('Export',guarded(function()
    local file='PBZDamageLab_'..os.date('%Y%m%d_%H%M%S')..'.csv'
    local path=MODDIR..'\\exports\\'..file
    local okP,err=Stats.export(state,path,weaponName)
    if okP then
        setStatus('exported',file)
        exportedPath=file
        local p=Dummy.player();exportedAt=p and Dummy.now(p) or 0
        log('exported '..path)
    else
        setStatus(err=='empty' and 'export_empty' or 'export_failed')
        log('export failed: '..tostring(err))
    end
end))

-- Game version check: the mod was verified on this engine changelist; other builds get a warning.
local TESTED_CL='302256'
local gameVersion
do
    local okV,v=pcall(function()
        local r=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):GetEngineVersion()
        return type(r)=='string' and r or r:ToString()
    end)
    gameVersion=okV and v or nil
end
local versionVerified=gameVersion==nil or gameVersion:find(TESTED_CL,1,true)~=nil

local function f1(n) return string.format('%.1f',n) end
local function pct(v) return string.format('%+.0f%%',(v or 0)*100) end

local function compose(p,now)
    local L={}
    local function title(l,r) L[#L+1]={kind='title',l=l,r=r} end
    local function section(l,r) L[#L+1]={kind='section',l=l,r=r,rc='dim'} end
    local function row(l,r,rc,lc) L[#L+1]={kind='row',l=l,r=r,rc=rc,lc=lc} end

    L[#L+1]={kind='title',l=T('title')..'  v'..VERSION,r=combat and T('combat_badge') or T('hide',cfg.TogglePanel),rc=combat and 'on' or nil}
    if not versionVerified then row(T('version_warn',tostring(gameVersion)),'',nil,'warn') end
    row(statusText(),'',nil,'dim')
    row(T('mode'),combat and T('mode_combat') or T('mode_dummy'),combat and 'on' or 'text')
    if exportedPath and now-exportedAt<20 then
        row(T('export_where'),'',nil,'on')
        row('…\\ue4ss\\Mods\\PBZDamageLab\\exports\\','',nil,'text')
        row(exportedPath,'',nil,'text')
    end
    if Dummy.valid(actor) and ready then
        local hp,mx=Dummy.health(actor)
        row(T('dummy_hp'),string.format('%.0f / %.0f',hp,mx))
    end

    -- Sha-Chi numbers only mean something on targets with a Sha-Chi bar: real enemies in combat mode.
    -- The dummy has none, so they are hidden outside combat mode.
    local showShachi=combat
    section(T('stats'))
    row(T('hits_total'),string.format('%d  /  %s',state.count,f1(state.total)))
    if showShachi then row(T('shachi_total'),f1(state.shachi)) end
    row(T('max_hit'),f1(state.max))
    for _,w in ipairs(Stats.weaponShares(state)) do
        row('  '..weaponName(w[1]),string.format('%s   %.0f%%',f1(w[2]),w[3]*100))
    end
    local seg=Stats.segment(state)
    if seg then
        local dur=math.max(seg.last-seg.first,0.001)
        local name=(now-seg.last>Stats.SEGMENT_GAP) and T('combo_last') or T('combo_cur')
        row(name..string.format(' #%d',#state.segments),f1(seg.total))
        row(T('combo_detail'),string.format('%d / %.1fs / %s',seg.count,dur,seg.count>1 and f1(seg.total/dur) or '-'))
        if showShachi then row(T('combo_shachi'),f1(seg.shachi)) end
    end

    local tm=state.timer
    if tm then
        section(T('timer'))
        if tm.state=='armed' then
            row(T('timer_wait',tm.seconds),'',nil,'dim')
        else
            local elapsed=tm.state=='running' and math.max(now-tm.start,0.001) or tm.seconds
            local label=tm.state=='running' and T('timer_left',math.max(0,tm.seconds-elapsed)) or T('timer_done',tm.seconds)
            row(label,f1(tm.total),tm.state=='done' and 'on' or 'text')
            if showShachi then
                row(T('timer_detail'),string.format('%s / %d / %s',f1(tm.total/elapsed),tm.count,f1(tm.shachi)))
            else
                row(T('timer_detail_hp'),string.format('%s / %d',f1(tm.total/elapsed),tm.count))
            end
        end
        local hint=tm.state=='armed' and 'timer_hint_cancel' or (tm.state=='running' and 'timer_hint_stop' or 'timer_hint_again')
        row(T(hint,cfg.TimedTest),'',nil,'dim')
    end

    section(T('recent'))
    row(T('dmg'),T('formula'),nil,'dim')
    local recent=Stats.recent(state)
    if #recent==0 then row(T('no_hits'),'',nil,'dim') end
    for _,h in ipairs(recent) do
        local flag=(h.source=='exact' or h.source=='none') and '' or ' ?'
        row(f1(h.dmg),string.format('%s ×%.2f %s %s%s',f1(h.base),h.mul,pct(h.addm),pct(h.amp),flag),
            (h.source=='exact' or h.source=='none') and 'text' or 'dim','text')
    end

    section(T('accessories'))
    L[#L+1]={kind='chips',cells={{T('attack'),'attack'},{T('support'),'support'},{T('survival'),'survival'}}}
    local eq=Probes.equipped()
    if #eq==0 then row(T('no_acc'),'',nil,'dim') end
    for _,e in ipairs(eq) do
        local liveText,on=Probes.live(p,e,now)
        local pool=e.acc.pool
        -- Name color = accessory type; right side is the damage pool tag (plus the live value for the
        -- few accessories that report one), and its color shows the live state
        -- (green = active, dark gray = not active, light gray = not tracked).
        local right=(e.acc.type=='attack' and pool) and Probes.poolName(pool) or ''
        if liveText~='' then right=right..(right~='' and ' · ' or '')..liveText end
        local nameColor=e.acc.type=='support' and 'support' or (e.acc.type=='survival' and 'survival' or 'attack')
        local rc=on==true and 'on' or (on==false and 'dim' or 'label')
        L[#L+1]={kind='inline',l=Probes.name(e.acc,e.lv,log),r=right,lc=nameColor,rc=rc}
    end

    if next(state.slots) then
        section(T('compare'))
        row(T('set'),T('per_combo'),nil,'dim')
        local base=state.slots.A and state.slots.A.avg or nil
        for _,k in ipairs({'A','B','C'}) do
            local s=state.slots[k]
            if s then
                row(k..'  '..s.label,string.format('%s  ×%s',f1(s.avg),base and base>0 and string.format('%.3f',s.avg/base) or '-'),'accent')            end
        end
    end

    section(T('keys'))
    row(T('keys1',cfg.Summon,cfg.Reset,cfg.Remove),'',nil,'dim')
    row(T('keys2',cfg.SaveA,cfg.SaveB,cfg.SaveC,cfg.ClearCompare),'',nil,'dim')
    row(T('keys3',cfg.CombatMode,cfg.TimedTest,cfg.Export),'',nil,'dim')
    return L
end

local tick=pin(function()
    local ok,err=pcall(function()
        local p=Dummy.player()
        local now=p and Dummy.now(p) or 0
        if now-lastLangCheck>3 or now<lastLangCheck then
            lastLangCheck=now
            local before=I18n.lang
            I18n.detect()
            Hud.setWide(I18n.lang=='en')
            if I18n.lang~=before then log('language '..tostring(I18n.code)..' -> '..I18n.lang) end
        end
        Stats.timerTick(state,now)
        Stats.flushPending(state,now)
        if actor then
            if not Dummy.valid(actor) or not p or Dummy.world(p)~=world or p:GetAddress()~=owner then
                remove('scene_changed')
            elseif not ready and readyAt and now>=readyAt then
                Dummy.configure(actor);ready=true;readyAt=nil
                homeLoc=actor:K2_GetActorLocation()
                homeLoc={X=homeLoc.X,Y=homeLoc.Y,Z=homeLoc.Z}
                log('dummy frozen: '..Dummy.freeze(actor))
                snapCount=0
                setStatus('ready')
                log('ready hp='..Dummy.health(actor))
            elseif ready then
                if Dummy.health(actor)<=1 then Dummy.heal(actor) end
                pcall(Dummy.freeze,actor) -- the anim instance can be rebuilt; reapplying is cheap
            end
        end
        if p and now-lastEquipScan>2 then
            lastEquipScan=now
            Probes.refreshEquipped(p)
            Probes.prune(now)
        end
        if p and Hud.visible() then
            local e=Hud.render(compose(p,now))
            if e and tostring(e)~=lastHudError then log('hud: '..tostring(e)) end
            lastHudError=e and tostring(e) or nil
        end
    end)
    if not ok then log('tick: '..tostring(err)) end
    return false
end)
I18n.detect()
Hud.setWide(I18n.lang=='en')
log('loaded v'..VERSION..'; language '..tostring(I18n.code)..' -> '..I18n.lang..'; engine '..tostring(gameVersion)
    ..(versionVerified and ' (verified)' or ' (NOT verified, tested on CL '..TESTED_CL..')')
    ..'; keys: panel='..cfg.TogglePanel..' summon='..cfg.Summon)
LoopInGameThreadWithDelay(250,tick)

-- Position lock runs at ~60 Hz so the dummy never visibly slides (the main tick is only 4 Hz).
local hold=pin(function()
    if not (ready and homeLoc and Dummy.valid(actor)) then return false end
    local ok,moved=pcall(Dummy.holdPosition,actor,homeLoc)
    if ok and moved then
        snapCount=snapCount+1
        if snapCount==1 or snapCount%200==0 then dlog('dummy held in place ('..snapCount..' snaps)') end
    end
    return false
end)
LoopInGameThreadWithDelay(16,hold)
