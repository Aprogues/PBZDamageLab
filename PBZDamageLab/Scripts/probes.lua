-- Reads the player's equipped accessories, their live trigger state, and the damage
-- modifiers each attack (bullet) carries when it starts. Every read is pcall-guarded.
local M={}
local ACC='/PBZCombatAsset/Prototypes/GameplayEffects/Accessories/New/'

local list
local classes={}
local equipped={}      -- array of {acc=, lv=}
local snaps={}         -- bullet address -> {mul, addm, amp, t}
local pendingPre={}    -- bullet address -> {addm, t} from pre-take modifiers (per hit)

local function valid(o) return o~=nil and o:IsValid() end
local function try(fn,...) local ok,a,b,c=pcall(fn,...);if ok then return a,b,c end return nil end
local function class(path)
    local c=classes[path]
    if c==nil then c=LoadAsset(path) or false;classes[path]=c end
    return c or nil
end
local function effectCount(asc,path)
    local c=class(path)
    if not valid(c) then return 0 end
    return asc:GetGameplayEffectCount(c,CreateInvalidObject(),true)
end
local function addr(o) if valid(o) then return o:GetAddress() end return nil end

-- Accessories with no trigger condition: they only limit which attacks they boost (weapon type,
-- Sha-Chi combos, element, Phantom Edge, summons, shields). Wearing them = working, so always lit.
local ALWAYS={
    Attack=true,Long=true,Double=true,Tang=true,HeavyAttackDamage=true,HeavyAttackShachi=true,
    Elemental=true,Ignite=true,ShachiAttack=true,BreakShield=true,Poison=true,Control=true,
    PowerWeapon=true,ShachiWeapon=true,Electrified=true,
}

-- Accessories whose condition is checked on the target when a hit lands: lit when a recent hit
-- received their value (per refine level, from the unpacked abilities). preAdds / preMuls are the
-- modifiers added at hit time; an empty values table means "any value" (绝技护符·改 is not in its data).
local RECENT=3.0 -- seconds a hit keeps a conditional accessory lit

-- To tell apart accessories that add the same value (追杀令·改 / 影动猎杀仪·改 / 神射之眼 are all
-- +15%), each one's ability graph is hooked: while it runs, any hit-time modifier it applies is
-- attributed to it. If the hooks cannot be installed, matching falls back to the value.
local ATTRIBUTED={
    BreakAttack={'GA_Accessory_BreakAttack_Lv1','GA_Accessory_BreakAttack_Lv2'},
    ActHit={'GA_Accessory_ActHit_Lv1','GA_Accessory_ActHit_Lv2'},
    Ranged={'GA_Accessory_Ranged_Lv1','GA_Accessory_Ranged_Lv2'},
    Rider={'GA_Accessory_Rider_Lv1','GA_Accessory_Rider_Lv2'},
    UltimateBreak={'GA_Accessory_UltimateBreak_Lv1','GA_Accessory_UltimateBreak_Lv2'},
}
local running={}       -- stack of accessory keys whose ability graph is executing right now
-- Bullet data folders named after a weapon type, not a weapon: their moves are shared.
local GENERIC_FOLDERS={LongBlade=true,TangBlade=true,DoubleBlade=true,Common=true,ShachiAbility=false}
-- Inside a weapon-type folder, these sub-folders belong to one weapon (value = key in weapons.lua);
-- every other sub-folder (Air, PerfectDodge, Global, HorseCartCombat …) holds moves the type shares.
local TYPE_WEAPONS={
    LongBlade={Default='LongBlade',ChiRen='ChiRen',GuiTouBlade='GuiTouBlade',JigSaw='Jigsaw'},
    TangBlade={Default='TangBlade',WoodenSword='WoodenSword',WoodenSword_Default='WoodenSword'},
    DoubleBlade={AAAAAA='DoubleBlade',AB='DoubleBlade',BBBB='DoubleBlade',CCC='DoubleBlade',
        Jade='Jade',YuuBlade='YuuBlade',JueYing='JueYing'},
}
local EXECUTION_SUBS={ExE=true,SimpleExe=true} -- execution moves, wherever they are filed
local attributionOn=false
local HIT_VALUES={
    UltimateBreak={list='preMuls',values={}},
    Rider={list='preAdds',values={0.25,0.40}},
    BreakAttack={list='preAdds',values={0.07,0.15}},
    ActHit={list='preAdds',values={0.07,0.15}},
    Ranged={list='preAdds',values={0.15,0.25}},
}

function M.init(accessories) list=accessories end
function M.poolName(p) return M.T and M.T('pool_'..p) or p end

-- Display names come from the game's own localization at runtime (current game language);
-- the mod ships only the keys. Falls back to the internal key if the lookup fails.
local names={}
local nameMethodLogged=false
local function lookup(key)
    local lib=StaticFindObject('/Script/Engine.Default__KismetTextLibrary')
    local out={}
    local ok,ret=pcall(function() return lib:FindTextInLocalizationTable('Default',key,out,'') end)
    if not ok then return nil,'call failed: '..tostring(ret) end
    for _,c in ipairs({out.OutText,out[1],out}) do
        local okS,s=pcall(function() return c:ToString() end)
        if okS and type(s)=='string' and s~='' and s~=key then return s,'out param' end
    end
    return nil,'not found (ret='..tostring(ret)..')'
end
-- Cached per language so switching the game language refreshes the names.
local cacheLang
function M.text(key,log)
    local lang=M.lang and M.lang() or ''
    if lang~=cacheLang then names={};cacheLang=lang end
    local n=names[key]
    if n==nil then
        local s,how=lookup(key)
        if log and not nameMethodLogged then log('name lookup '..key..': '..tostring(s)..' via '..tostring(how));nameMethodLogged=true end
        n=s and s:gsub('<[^>]*>','') or false
        names[key]=n
    end
    return n or nil
end
-- Some languages lack the upgraded names (e.g. en-US has no text for Item_Accessory_030_2). Then the
-- base name gets the game's own level suffix, taken from an accessory whose upgraded names exist
-- (Mother's Talisman ·REFINE, Ancient Armor Fragment ·SUPERIOR), or "+n" if even that is missing.
local LEVEL_REF={nil,'Item_Accessory_023_1','Item_Accessory_050_2'}
local function present(s) return s and s~='' and s or nil end
function M.name(acc,lv,log)
    local keys=acc.nameKeys or {}
    local n=keys[lv] and present(M.text(keys[lv],log))
    if n then return n end
    local base=keys[1] and present(M.text(keys[1],log))
    if base then
        if lv<=1 then return base end
        local ref=LEVEL_REF[lv] and present(M.text(LEVEL_REF[lv],log))
        local suffix=ref and ref:match('·([^·]+)$')
        return base..(suffix and ('·'..suffix) or ('+'..(lv-1)))
    end
    return acc.key..(lv>1 and ('+'..(lv-1)) or '')
end

-- Scans every accessory GE on the player; highest level found wins.
function M.refreshEquipped(p)
    if not valid(p) then return end
    local asc=p.AbilitySystemComponent
    local found={}
    for _,acc in ipairs(list) do
        for lv=#acc.ge,1,-1 do
            local n=try(effectCount,asc,acc.ge[lv])
            if n and n>0 then found[#found+1]={acc=acc,lv=lv};break end
        end
    end
    table.sort(found,function(a,b)
        local order={attack=1,support=2,survival=3}
        if order[a.acc.type]~=order[b.acc.type] then return order[a.acc.type]<order[b.acc.type] end
        return a.acc.id<b.acc.id
    end)
    equipped=found
end
function M.equipped() return equipped end

local function ampOf(p)
    return try(function()
        local a=p.AttributeSetBase.Amplification_Physical
        return a.CurrentValue-a.BaseValue
    end)
end
M.ampOf=ampOf

local function firstInstance(className)
    for _,o in ipairs(FindAllOf(className) or {}) do
        if valid(o) and not o:GetFullName():find('Default__',1,true) then return o end
    end
    return nil
end

local function anyEffect(asc,...)
    for _,path in ipairs({...}) do
        if effectCount(asc,path)>0 then return true end
    end
    return false
end
local function ge(name) return ACC..name..'.'..name:match('[^/]+$')..'_C' end

-- Whether a worn accessory is giving its bonus right now, plus an optional live-value text:
-- true = lit (active), false = dark (condition not met), nil = not tracked (support / survival).
-- Popular accessories with a changing bonus (舞扇, 同心双鱼佩, 绝望护符) also return that value.
function M.live(p,e,now)
    local key,lv=e.acc.key,e.lv
    if ALWAYS[key] then return '',true end
    local asc=p.AbilitySystemComponent
    local T=M.T or function(k) return k end
    local on
    if key=='Combo' then
        on=try(anyEffect,asc,ge('Combo/GE_Accessory_Combo_DamageBuff_Lv1'),
            ge('Combo/GE_Accessory_Combo_DamageBuff_Lv2'),ge('Combo/GE_Accessory_Combo_DamageBuff_Lv3'))
    elseif key=='AnimMovement' then
        -- Bonus grows with the distance moved during the current attack.
        local ga=firstInstance('GA_Accessory_AnimMovement_Lv'..lv..'_C')
        local v,d=nil,nil
        if ga then
            v,d=try(function()
                local dist=ga['Total Distance']
                return math.min(dist*ga['Distance Damage Multiplier'],ga['Max Amplification']),dist
            end)
        end
        if not v then return '',false end
        return T('live_fan',v*100,d/100),v>0.005
    elseif key=='LowShachi' then
        -- Game formula (GEC_Accessory_LowShachi): coefficient x MapRangeClamped(Sha-Chi ratio, 0.1..0.9 -> 1..0),
        -- coefficient 0.2 base / 0.3 refined. Matches the dummy measurement exactly.
        local r=try(function() local a=p.AttributeSetBase;return a.Shachi.CurrentValue/a.Shachi_Max.CurrentValue end)
        if not r then return '',false end
        local coef=lv>=2 and 0.30 or 0.20
        local v=coef*math.max(0,math.min(1,(0.9-r)/0.8))
        return T('live_duo',v*100,r*100),v>0
    elseif key=='BigHit' then
        -- The next hit's bonus builds up over 4 s without attacking.
        local ga=firstInstance('GA_Accessory_BigHit_Lv'..lv..'_C')
        local v=ga and now and try(function()
            return math.min(1,math.max(0,(now-ga['Last Hit Time'])/4))*ga['Additive Multiplier']
        end)
        if not v then return '',false end
        return T('live_bighit',v*100),v>0.005
    elseif key=='Counter' then
        on=try(anyEffect,asc,ge('GE_Accessory_Counter_Effect'),ge('GE_Accessory_Counter_Effect_Lv2'))
    elseif key=='Bleed' then
        on=try(anyEffect,asc,ge('GE_Accessory_Bleed_PlayerBuff_Lv1'),ge('GE_Accessory_Bleed_PlayerBuff_Lv2'))
    elseif key=='Execution' then
        on=try(anyEffect,asc,ge('GE_Accessory_Execution_Effect'),ge('GE_Accessory_Execution_Effect_Lv2'))
    elseif key=='LowHealth' then
        on=try(function() local a=p.AttributeSetBase;return a.Health.CurrentValue<a.Health_Max.CurrentValue-0.5 end)
    elseif HIT_VALUES[key] then
        -- Target conditions (rider, broken, distance, attacking, ultimate): a recent hit got the value.
        local h=M.lastHit
        if not h or not now or now-h.t>RECENT then return '',false end
        -- Once attribution has been seen working, trust it: it tells same-value accessories apart.
        if attributionOn and M.attributionSeen then return '',(h.preKeys or {})[key]==true end
        local spec=HIT_VALUES[key]
        local want=spec.values[lv] or spec.values[#spec.values]
        for _,v in ipairs(h[spec.list] or {}) do
            if want==nil or math.abs(v-want)<0.001 then return '',true end
        end
        return '',false
    else
        return '',nil
    end
    return '',on==true
end

-- Identity of an attack: the object itself plus two levels of outers. The modifier module and the
-- damage payload refer to the same attack through different objects, so both sides store/look up all.
local debugLeft=12
local function ids(o)
    local r={}
    local cur=o
    for _=1,3 do
        local a=addr(cur)
        if not a then break end
        r[#r+1]=a
        local okO,outer=pcall(function() return cur:GetOuter() end)
        if not okO then break end
        cur=outer
    end
    return r
end
local function describe(o)
    local okN,n=pcall(function() return o:GetFullName() end)
    return okN and n or tostring(o)
end
local lastSnap

-- Per-attack modifier capture. Damage of a bullet is fixed when it starts, so this is what the hit used.
local function onAddModifier(self,tag,op,value)
    local ok=pcall(function()
        local t=tag:get().TagName:ToString()
        if t~='Damage.Attack.Target.PhysicalDamage' then return end
        local module=self:get()
        local keys=ids(module)
        local okB,bullet=pcall(function() return module.Bullet end)
        if okB then for _,a in ipairs(ids(bullet)) do keys[#keys+1]=a end end
        if #keys==0 then return end
        local p=M.player and M.player()
        local now=p and M.clock(p) or os.clock()
        local s=snaps[keys[1]]
        -- While modifiers keep arriving for the same live bullet (charge ticks re-add them every
        -- ~0.2 s), it is one attack: keep its first amplification, multiply each distinct Multiply
        -- value once, and keep the first additive-multiplier group. Bullets are pooled, so a gap
        -- over 1 s means a new attack reusing the object.
        if not s or now-s.t>1.0 then
            s={muls={},addm=0,addmLocked=false,amp=p and ampOf(p) or nil,t=now,groupT=now}
            for _,k in ipairs(keys) do snaps[k]=s end
            if M.debug and debugLeft>0 and M.log then
                debugLeft=debugLeft-1
                M.log('mod module='..describe(module)..' bullet='..(okB and describe(bullet) or 'n/a')..' keys='..table.concat(keys,','))
            end
        end
        if now-s.groupT>0.05 and s.addm~=0 then s.addmLocked=true end
        s.t=now;s.groupT=now
        lastSnap=s
        local o,v=op:get(),value:get()
        if o==1 then s.muls[string.format('%.5f',v)]=v
        elseif o==2 and not s.addmLocked then s.addm=s.addm+v end
    end)
    return ok
end

-- Pre-take modifiers (e.g. 绝望护符, 斩骑符) are applied per hit to the damage payload.
local function onPreTake(self,a,b,c,d)
    pcall(function()
        local payload=self:get()
        local okS,srcObj=pcall(function() return payload.DamageSource end)
        local srcKeys=okS and ids(srcObj) or {}
        if #srcKeys==0 then return end
        local tag,op,val
        for _,param in ipairs({a,b,c,d}) do
            local okP,v=pcall(function() return param:get() end)
            if okP then
                if type(v)=='number' then
                    if op==nil and v==math.floor(v) and v>=0 and v<=5 then op=v else val=val or v end
                elseif v~=nil then
                    local okT,name=pcall(function() return v.TagName:ToString() end)
                    if okT then tag=name end
                end
            end
        end
        -- One accessory applies the same value to several damage tags; count the physical/general one.
        local relevant=tag==nil or tag:find('PhysicalDamage',1,true) or tag:find('GeneralDamage',1,true)
        if (op==1 or op==2) and val and relevant then
            local e=pendingPre[srcKeys[1]] or {addm=0,mul=1,adds={},muls={},keys={}}
            if op==2 then e.addm=e.addm+val;e.adds[#e.adds+1]=val
            else e.mul=e.mul*val;e.muls[#e.muls+1]=val end
            local who=running[#running]
            if who then e.keys[who]=true;M.attributionSeen=true end
            for _,k in ipairs(srcKeys) do pendingPre[k]=e end
        end
    end)
end

function M.installHooks(log)
    M.log=log
    local ok1,err1=pcall(RegisterHook,'/Script/SGameCombatSystem.BulletAttackModule:AddModifier',onAddModifier)
    log(ok1 and 'bullet modifier hook ok' or ('bullet modifier hook failed: '..tostring(err1)))
    local ok2,err2=pcall(RegisterHook,'/Script/SGameAttributes.DamagePreTakePayload:ApplyModifyToChildren',onPreTake)
    log(ok2 and 'pre-take hook ok' or ('pre-take hook failed: '..tostring(err2)))
    -- Pre-hook pushes the accessory key while its ability graph runs, post-hook pops it.
    local installed,failed=0,0
    for key,classes in pairs(ATTRIBUTED) do
        for _,name in ipairs(classes) do
            local ok=pcall(function()
                LoadAsset(ACC..name..'.'..name..'_C')
                RegisterHook(ACC..name..'.'..name..'_C:ExecuteUbergraph_'..name,
                    function() running[#running+1]=key end,
                    function() running[#running]=nil end)
            end)
            if ok then installed=installed+1 else failed=failed+1 end
        end
    end
    attributionOn=installed>0
    log(string.format('accessory attribution hooks: %d ok, %d failed',installed,failed))
end

-- Called from the damage event: returns the modifiers this hit's bullet started with.
-- source: 'exact' = matched by attack identity, 'guess' = latest attack start (fallback), nil = none.
local hitDebugLeft=12
function M.consume(payload,p,now)
    local keys={}
    local okS,srcObj=pcall(function() return payload.DamageSource end)
    if okS then keys=ids(srcObj) end
    local s,matched
    for _,k in ipairs(keys) do
        if snaps[k] then s=snaps[k];matched=k;break end
    end
    if M.debug and hitDebugLeft>0 and M.log then
        hitDebugLeft=hitDebugLeft-1
        M.log('hit source='..(okS and describe(srcObj) or 'n/a')..' keys='..table.concat(keys,',')..' matched='..tostring(matched))
    end
    -- No snapshot means the attack carried no bullet modifiers at all (plain light attacks).
    local r={mul=1,addm=0,amp=nil,source='none',weapon='其他'}
    -- The bullet data asset path names the weapon, e.g. .../Players/Hun/BulletData/PoJun/BD_...
    if okS then
        local name=describe(srcObj)
        local folder=name:match('/Players/%w+/BulletData/([%w_]+)/') or name:match('/Players/%w+/[%w_]+/([%w_]+)/') or '其他'
        local sub=name:match('/Players/%w+/BulletData/[%w_]+/([%w_]+)/')
        if name:find('Execution',1,true) or (sub and EXECUTION_SUBS[sub]) then
            -- Executions reuse one weapon's execution data (e.g. LongBlade/GuiTouBlade) for everyone.
            folder='Execution'
        elseif TYPE_WEAPONS[folder] and sub and TYPE_WEAPONS[folder][sub] then
            folder=TYPE_WEAPONS[folder][sub] -- a weapon filed under its type, e.g. LongBlade/JigSaw
            M.lastWeapon=folder
        elseif GENERIC_FOLDERS[folder] then
            -- Moves every weapon of the type shares (air attacks …) do not say which weapon is in hand.
            -- The hit waits ('pending'): Stats credits it to the next weapon-specific move in the same
            -- combo (right after a weapon switch that is the new weapon), or, if the combo ends first,
            -- to the weapon used before it (fallback).
            r.fallback=M.lastWeapon
            folder='pending'
        elseif name:find('/Players/',1,true) and folder~='其他' then
            M.lastWeapon=folder
        end
        r.weapon=folder
        -- Player attacks come from …/ActorData/Players/… bullet data; enemy attacks do not.
        r.fromPlayer=name:find('/Players/',1,true)~=nil
    end
    r.bulletMuls,r.preAdds,r.preMuls={},{},{}
    if s then
        local mul=1
        for _,v in pairs(s.muls) do mul=mul*v;r.bulletMuls[#r.bulletMuls+1]=v end
        r.mul,r.addm,r.amp,r.source=mul,s.addm,s.amp,'exact'
    end
    if r.amp==nil and p then r.amp=ampOf(p) end
    for _,k in ipairs(keys) do
        local pre=pendingPre[k]
        if pre then
            r.addm=r.addm+pre.addm
            r.mul=r.mul*pre.mul
            r.preAdds,r.preMuls,r.preKeys=pre.adds,pre.muls,pre.keys
            for _,kk in ipairs(keys) do pendingPre[kk]=nil end
            break
        end
    end
    M.lastHit={t=now,bulletMuls=r.bulletMuls,preAdds=r.preAdds,preMuls=r.preMuls,preKeys=r.preKeys or {},weapon=r.weapon}
    return r
end

function M.prune(now)
    for k,s in pairs(snaps) do if now-s.t>30 then snaps[k]=nil end end
end

return M
