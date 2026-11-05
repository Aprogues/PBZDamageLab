-- Damage accounting: per-hit records, combo segments split by idle gaps, A/B/C compare slots,
-- a fixed-length timed test, and an on-demand CSV export of the current round.
local M={}
M.SEGMENT_GAP=3.0 -- seconds without a hit before a new combo segment starts
M.RECENT=6
M.KEEP=5000       -- hits kept in memory for the export (a few hundred KB at most)

function M.new()
    return {hits={},count=0,total=0,shachi=0,max=0,segments={},slots={},weapons={},timer=nil,pending={}}
end

function M.reset(s)
    s.hits={};s.count=0;s.total=0;s.shachi=0;s.max=0;s.segments={};s.weapons={};s.pending={}
end

-- Shared moves ('pending', see probes.consume) wait for the next weapon-specific move of the same combo
-- and are credited to that weapon, so a shared move right after a weapon switch goes to the new weapon.
-- If the combo ends first, they go to the weapon used before them (hit.fallback); with none they keep
-- waiting for the next weapon-specific move.
local NOT_A_WEAPON={pending=true,Execution=true,['其他']=true}
local function movePending(s,h,w)
    s.weapons.pending=(s.weapons.pending or 0)-h.dmg
    if s.weapons.pending<0.001 then s.weapons.pending=nil end
    h.weapon=w
    s.weapons[w]=(s.weapons[w] or 0)+h.dmg
end
function M.flushPending(s,now)
    local last=s.pending[#s.pending]
    if not last or now-last.t<=M.SEGMENT_GAP then return end
    local keep={}
    for _,h in ipairs(s.pending) do
        if h.fallback then movePending(s,h,h.fallback) else keep[#keep+1]=h end
    end
    s.pending=keep
end
local function creditWeapon(s,hit)
    local w=hit.weapon
    if not w then return end
    M.flushPending(s,hit.t) -- leftovers of an earlier combo settle first
    if w=='pending' then
        s.pending[#s.pending+1]=hit
        s.weapons.pending=(s.weapons.pending or 0)+hit.dmg
        return
    end
    s.weapons[w]=(s.weapons[w] or 0)+hit.dmg
    if NOT_A_WEAPON[w] then return end
    for _,h in ipairs(s.pending) do movePending(s,h,w) end
    s.pending={}
end

-- Damage per weapon since the last reset, largest first: {{name,total,share},...}
function M.weaponShares(s)
    local r={}
    for name,v in pairs(s.weapons) do r[#r+1]={name,v,s.total>0 and v/s.total or 0} end
    table.sort(r,function(a,b) return a[2]>b[2] end)
    return r
end

local function current(s) return s.segments[#s.segments] end

-- Timed test: arm() waits for the first hit, then counts for `seconds`; the result stays shown.
function M.armTimer(s,seconds)
    s.timer={state='armed',seconds=seconds,total=0,shachi=0,count=0}
end

-- One key drives the timed test: idle/done -> armed, armed -> cancelled, running -> stopped early
-- (the result then covers the time actually played). Returns the status key to show.
function M.timerPress(s,seconds,now)
    local t=s.timer
    if not t or t.state=='done' then M.armTimer(s,seconds);return 'timer_armed' end
    if t.state=='armed' then s.timer=nil;return 'timer_cancelled' end
    t.seconds=math.max(now-t.start,0.001);t.state='done'
    return 'timer_stopped'
end
function M.timerTick(s,now)
    local t=s.timer
    if t and t.state=='running' and now>=t.start+t.seconds then t.state='done' end
end

function M.record(s,hit)
    s.hits[#s.hits+1]=hit
    if #s.hits>M.KEEP then table.remove(s.hits,1) end
    s.count=s.count+1
    s.total=s.total+hit.dmg
    s.shachi=s.shachi+(hit.shachi or 0)
    creditWeapon(s,hit)
    if hit.dmg>s.max then s.max=hit.dmg end
    local seg=current(s)
    if not seg or hit.t-seg.last>M.SEGMENT_GAP then
        seg={first=hit.t,last=hit.t,total=0,shachi=0,count=0}
        s.segments[#s.segments+1]=seg
    end
    seg.last=hit.t;seg.total=seg.total+hit.dmg;seg.shachi=seg.shachi+(hit.shachi or 0);seg.count=seg.count+1
    local t=s.timer
    if t then
        if t.state=='armed' then t.state='running';t.start=hit.t end
        if t.state=='running' and hit.t<t.start+t.seconds then
            t.total=t.total+hit.dmg;t.shachi=t.shachi+(hit.shachi or 0);t.count=t.count+1
        end
    end
end

function M.segment(s) return current(s) end

function M.recent(s)
    local r={}
    for i=#s.hits,math.max(1,#s.hits-M.RECENT+1),-1 do r[#r+1]=s.hits[i] end
    return r
end

-- Saves this round (since the last reset) into slot 'A' / 'B' / 'C'.
function M.save(s,slot,label)
    local n=#s.segments
    local sum=0
    for _,seg in ipairs(s.segments) do sum=sum+seg.total end
    s.slots[slot]={label=label,segments=n,avg=n>0 and sum/n or 0,total=s.total,
        hits=s.count,avgHit=s.count>0 and s.total/s.count or 0}
end

function M.clearSlots(s) s.slots={} end

-- Writes the hits of this round to a CSV file (UTF-8 with BOM so Excel shows CJK names).
-- Only runs when the player presses the export key. Returns the path, or nil and an error.
function M.export(s,path,weaponName)
    if #s.hits==0 then return nil,'empty' end
    local f,err=io.open(path,'wb')
    if not f then return nil,err end
    f:write('\239\187\191')
    f:write('index,time_s,target,weapon,damage,base,mult,add,amp,shachi_damage\n')
    local t0=s.hits[1].t
    for i,h in ipairs(s.hits) do
        f:write(string.format('%d,%.3f,%s,%s,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n',i,h.t-t0,
            (h.target or ''):gsub(',',' '),(weaponName(h.weapon) or ''):gsub(',',' '),
            h.dmg,h.base,h.mul,h.addm,h.amp or 0,h.shachi or 0))
    end
    f:close()
    return path
end

return M
