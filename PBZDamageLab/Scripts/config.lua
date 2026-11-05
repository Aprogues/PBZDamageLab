-- Reads PBZDamageLab/config.ini. Unknown or invalid values fall back to the defaults below.
local M={}
local DEFAULTS={
    TogglePanel='F6',Summon='F7',Reset='F8',Remove='F9',
    SaveA='F1',SaveB='F2',SaveC='F3',ClearCompare='F4',
    CombatMode='INS',TimedTest='HOME',Export='END',TimedSeconds='30',Debug='false',
    Position='TopRight',FontSize='11',Language='Auto',
}

local function parse(text)
    local out={}
    for line in (text..'\n'):gmatch('(.-)\n') do
        line=line:gsub('\r',''):gsub('[;#].*$',''):match('^%s*(.-)%s*$')
        local k,v=line:match('^(%w+)%s*=%s*(.-)%s*$')
        if k then out[k]=v end
    end
    return out
end

function M.load(path,log)
    local values={}
    for k,v in pairs(DEFAULTS) do values[k]=v end
    local f=io.open(path,'rb')
    if f then
        local text=f:read('*a'):gsub('^\239\187\191','');f:close()
        for k,v in pairs(parse(text)) do if v~='' then values[k]=v end end
    end
    return values
end

-- Common spellings mapped to UE4SS Key names (UE4SS calls Insert 'INS' and Delete 'DEL').
local ALIASES={INSERT='INS',DELETE='DEL',PGUP='PAGE_UP',PAGEUP='PAGE_UP',PGDN='PAGE_DOWN',PAGEDOWN='PAGE_DOWN',ESC='ESCAPE'}

-- 'CTRL+F7' -> Key.F7, {ModifierKey.CONTROL}; returns nil for unknown key names.
function M.key(spec)
    local mods={}
    local name=spec:upper()
    while true do
        local m,rest=name:match('^(%u+)%+(.+)$')
        if not m then break end
        if m=='CTRL' then mods[#mods+1]=ModifierKey.CONTROL
        elseif m=='SHIFT' then mods[#mods+1]=ModifierKey.SHIFT
        elseif m=='ALT' then mods[#mods+1]=ModifierKey.ALT end
        name=rest
    end
    name=ALIASES[name] or name
    if type(Key[name])~='number' then return nil end
    return Key[name],mods
end

return M
