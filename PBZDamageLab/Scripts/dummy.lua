-- Training dummy: spawn, lock health, refill. All functions run on the game thread.
-- Spawn and attribute handling adapted from PBZTrainingDummy by xbunax (MIT), see LICENSE-PBZTrainingDummy.txt.
local M={}
-- The dummy is the game's developer hit-only dummy (golden-mask man): it never fights back or deflects,
-- has no Sha-Chi bar and never breaks, so damage numbers are clean and repeatable.
local MOBS='/Game/RenewalContent/Actors/Mobs/Normal/'
M.CLASS=MOBS..'BP_Monster_GoldMaskMan_Dummy_OnlyHit.BP_Monster_GoldMaskMan_Dummy_OnlyHit_C'
local CONFIG='/PBZCombatAsset/Config/GlobalConfig_Combined_Normal.GlobalConfig_Combined_Normal'
local EFFECT='/PBZCombatAsset/Prototypes/GameplayEffects/'

M.MAX_HP=10000
M.damageHook='/PBZCombatAsset/Prototypes/Abilities/GA_CommonUtilitiesPassive.GA_CommonUtilitiesPassive_C:OnTaken'

function M.valid(o) return o~=nil and o:IsValid() end
local function lib(n) return StaticFindObject('/Script/'..n) end

function M.player()
    local pc=FindFirstOf('PlayerController')
    if not M.valid(pc) then return nil end
    local p=pc.Pawn
    if not M.valid(p) or not p:IsA('/Script/ProjectPBZ.PBZCharacter') then return nil end
    return p
end
function M.now(p) return lib('Engine.Default__GameplayStatics'):GetTimeSeconds(p) end
function M.world(p) return p:GetWorld():GetAddress() end

-- Finds flat ground 1.8 m in front of the player and loads the dummy class.
function M.position(p,old)
    local loc=p:K2_GetActorLocation();local f=p:GetActorForwardVector()
    local x,y=loc.X+f.X*180,loc.Y+f.Y*180
    local hit={};local ignore={p}
    if M.valid(old) then ignore[#ignore+1]=old end
    local ok=lib('Engine.Default__KismetSystemLibrary'):LineTraceSingle(p,
        {X=x,Y=y,Z=loc.Z+100},{X=x,Y=y,Z=loc.Z-300},0,false,ignore,0,hit,true,
        {R=0,G=0,B=0,A=0},{R=0,G=0,B=0,A=0},0)
    if not ok or not hit.ImpactNormal or hit.ImpactNormal.Z<0.65 then
        return nil,'err_no_ground'
    end
    local cls=LoadAsset(M.CLASS)
    assert(M.valid(cls),'err_load')
    local half=cls:GetCDO().CapsuleComponent:GetScaledCapsuleHalfHeight()
    return lib('Engine.Default__KismetMathLibrary'):MakeTransform(
        {X=hit.ImpactPoint.X,Y=hit.ImpactPoint.Y,Z=hit.ImpactPoint.Z+half+3},
        {Pitch=0,Yaw=p:K2_GetActorRotation().Yaw+180,Roll=0},{X=1,Y=1,Z=1}),cls
end

function M.spawn(p,t,cls)
    local gs=lib('Engine.Default__GameplayStatics')
    -- Reflected deferred spawn avoids this UE4SS build's incompatible native UWorld wrapper.
    local a=gs:BeginDeferredActorSpawnFromClass(p,cls,t,2,p,0)
    assert(M.valid(a),'err_no_space')
    local ok,err=pcall(function()
        a.AutoPossessAI=0
        gs:FinishSpawningActor(a,t,0)
        a:SpawnDefaultController()
        a['Attribute Component']:ReinitializeAttributes()
        local asc=a.AbilitySystemComponent
        asc:BP_ApplyGameplayEffectToSelf(LoadAsset(EFFECT..'GE_AIDisableAction.GE_AIDisableAction_C'),1,asc:MakeEffectContext())
    end)
    if not ok then M.destroy(a);error(err) end
    return a
end

-- Attribute references come from asset structs: a GameplayAttribute returned by a UFunction
-- loses its FieldPathProperty in this UE4SS build and must not be passed back.
local function attr(gePath)
    return LoadAsset(gePath):GetCDO().Modifiers[1].Attribute
end
-- Percentage Preserved Attributes is a map current -> maximum (Health -> Health_Max, Shachi -> Shachi_Max …).
local function preserved()
    local cfg=LoadAsset(CONFIG)
    local out={}
    cfg['Mechanic Config']['Percentage Preserved Attributes']:ForEach(function(k,v)
        local a,b=k:get(),v:get()
        out[a.AttributeName:ToString()]=a;out[b.AttributeName:ToString()]=b
    end)
    return out,cfg
end
local function attributes()
    local p,cfg=preserved()
    assert(p.Health_Max,'Health_Max attribute unavailable')
    return cfg['Mechanic Config']['Health Attribute'],p.Health_Max,attr(EFFECT..'GE_LockHealth.GE_LockHealth_C')
end

local function set(a,attribute,value)
    lib('SGameAttributes.Default__AttributeUtils'):ModifyCharacterAttributeValue(a,attribute,3,value)
end

function M.configure(a)
    local hp,mx,mn=attributes()
    set(a,mn,1)
    set(a,mx,M.MAX_HP)
    set(a,hp,M.MAX_HP)
    a:SetDisableMovement(true)
end

-- Keeps the dummy standing on its spot: animations play in place (deflects, hit reactions) but
-- their root motion no longer moves it, and it cannot walk. Returns what was applied, for the log.
function M.freeze(a)
    local done={}
    local ok=pcall(function()
        local anim=a.Mesh:GetAnimInstance()
        if M.valid(anim) and anim.RootMotionMode~=1 then anim:SetRootMotionMode(1) end -- IgnoreRootMotion
    end)
    if ok then done[#done+1]='rootmotion' end
    ok=pcall(function()
        local cm=a.CharacterMovement
        cm.MaxWalkSpeed=0;cm.MaxAcceleration=0;cm.Velocity={X=0,Y=0,Z=0}
    end)
    if ok then done[#done+1]='walk' end
    return table.concat(done,',')
end

-- Backstop for pushes that bypass animation (knockback forces): snaps it back to where it was
-- summoned whenever it has slid more than 2 cm. Called many times a second.
function M.holdPosition(a,loc)
    local cur=a:K2_GetActorLocation()
    local dx,dy=cur.X-loc.X,cur.Y-loc.Y
    if dx*dx+dy*dy>2*2 then
        a:K2_SetActorLocation({X=loc.X,Y=loc.Y,Z=loc.Z},false,{},true)
        pcall(function() a.CharacterMovement.Velocity={X=0,Y=0,Z=0} end)
        return true
    end
    return false
end

function M.heal(a)
    local hp=attributes()
    set(a,hp,a.AttributeSetBase.Health_Max.CurrentValue)
end

function M.destroy(a)
    if not M.valid(a) then return end
    local controller=a.Controller
    a:K2_DestroyActor()
    if M.valid(controller) then controller:K2_DestroyActor() end
end

function M.health(a) return a.AttributeSetBase.Health.CurrentValue,a.AttributeSetBase.Health_Max.CurrentValue end

-- Returns health damage, Sha-Chi damage (Damage.Damage.Target.AngerDamage.*) and every damage tag
-- the hit carried with a positive value. Poise and attacker resource gain are not counted.
function M.damage(payload)
    local total,shachi,tags=0,0,{}
    for key,value in pairs(payload:GetDamageData()) do
        local tag=key:get().TagName:ToString()
        local v=value:get()
        if type(v)=='number' and v==v and v>0 and v<math.huge then
            tags[#tags+1]=tag
            if tag:match('^Damage%.Damage%.Target%.GeneralDamage%.') then total=total+v
            elseif tag:match('^Damage%.Damage%.Target%.AngerDamage') then shachi=shachi+v end
        end
    end
    return total,tags,shachi
end

return M
