-- Display-only overlay card. It never changes input mode, shows no cursor and every widget is
-- HitTestInvisible, so the camera and controls keep working while it is on screen.
-- Widget construction pattern follows ue4ss-ModMenu by mattdavida (MIT).
local M={}
local VIS_COLLAPSED,VIS_HITTEST_INVISIBLE=1,3
M.ROWS=50
M.FONT=11
M.WIDTH=380
M.POSITION='TopRight'

local hud,rows,last,serial=nil,{},{},0
local sizeBox
local visible=true

-- Palette: dark slate card, warm gold accents, one color per damage pool.
M.COLORS={
    text={R=0.90,G=0.91,B=0.93,A=1},
    label={R=0.60,G=0.63,B=0.68,A=1},
    dim={R=0.45,G=0.47,B=0.51,A=1},
    accent={R=0.98,G=0.78,B=0.36,A=1},
    on={R=0.42,G=0.90,B=0.55,A=1},
    warn={R=1.00,G=0.52,B=0.45,A=1},
    mul={R=0.78,G=0.62,B=1.00,A=1},
    addmul={R=0.45,G=0.75,B=1.00,A=1},
    amp={R=1.00,G=0.66,B=0.38,A=1},
    attack={R=1.00,G=0.86,B=0.30,A=1},   -- yellow
    support={R=0.45,G=0.70,B=1.00,A=1},  -- blue
    survival={R=1.00,G=0.45,B=0.45,A=1}, -- red
    unknown={R=0.92,G=0.92,B=0.92,A=1},
}
local CARD={R=0.055,G=0.065,B=0.085,A=0.86}
local HEADER={R=0.13,G=0.11,B=0.07,A=0.95}

local function valid(o) return o~=nil and o:IsValid() end
local function construct(path,outer,name)
    local obj=StaticConstructObject(StaticFindObject(path),outer,FName(name))
    assert(valid(obj),'construct failed: '..path)
    return obj
end
local function setVis(w,v) pcall(function() w:SetVisibility(v) end) end
local function rounded(border,color,radius)
    -- RoundedBox brush; falls back to a plain tint if the brush struct cannot be written.
    local ok=pcall(function()
        border:SetBrush({DrawAs=4,TintColor={SpecifiedColor=color,ColorUseRule=0},
            OutlineSettings={CornerRadii={X=radius,Y=radius,Z=radius,W=radius},RoundingType=0,Width=0}})
    end)
    pcall(function() border:SetBrushColor(color) end)
    return ok
end
-- Font is a struct property: editing t.Font.Size only changes a copy, so write it back with SetFont.
local fontApplied
local function style(t,size,color)
    local ok=pcall(function()
        local f=t.Font
        f.Size=size
        t:SetFont(f)
    end)
    if not ok then pcall(function() t.Font.Size=size end) end
    if fontApplied==nil then
        pcall(function() fontApplied=t.Font.Size end)
        if M.log then M.log('font size after set: '..tostring(fontApplied)..' (wanted '..size..')') end
    end
    pcall(function() t:SetColorAndOpacity({SpecifiedColor=color,ColorUseRule=0}) end)
end
-- Long labels end in "…" inside their own bounds instead of drawing over the value column.
local function clip(t)
    pcall(function() t:SetClipping(1) end)          -- EWidgetClipping::ClipToBounds
    pcall(function() t:SetTextOverflowPolicy(1) end) -- ETextOverflowPolicy::Ellipsis
end

local function build()
    serial=serial+1
    local sfx='_'..serial
    local outer=FindFirstOf('GameInstance')
    if not valid(outer) then outer=FindFirstOf('PlayerController') end
    assert(valid(outer),'no GameInstance')
    local w=construct('/Script/UMG.UserWidget',outer,'PBZLab_HUD'..sfx)
    local tree=construct('/Script/UMG.WidgetTree',w,'PBZLab_Tree'..sfx)
    w.WidgetTree=tree
    local canvas=construct('/Script/UMG.CanvasPanel',tree,'PBZLab_Canvas'..sfx)
    tree.RootWidget=canvas

    local size=construct('/Script/UMG.SizeBox',canvas,'PBZLab_Size'..sfx)
    pcall(function() size:SetWidthOverride(M.WIDTH) end)
    sizeBox=size
    local card=construct('/Script/UMG.Border',size,'PBZLab_Card'..sfx)
    rounded(card,CARD,10)
    pcall(function() card:SetPadding({Left=0,Top=0,Right=0,Bottom=8}) end)
    size:SetContent(card)
    local box=construct('/Script/UMG.VerticalBox',card,'PBZLab_Box'..sfx)
    card:SetContent(box)

    rows,last={},{}
    for i=1,M.ROWS do
        local bg=construct('/Script/UMG.Border',box,'PBZLab_RowBg'..i..sfx)
        pcall(function() bg:SetBrushColor({R=0,G=0,B=0,A=0}) end)
        pcall(function() bg:SetPadding({Left=12,Top=1,Right=12,Bottom=1}) end)
        local h=construct('/Script/UMG.HorizontalBox',bg,'PBZLab_Row'..i..sfx)
        bg:SetContent(h)
        -- The label sits in a SizeBox so "inline" rows can give it a fixed column width.
        local lbox=construct('/Script/UMG.SizeBox',h,'PBZLab_LBox'..i..sfx)
        local l=construct('/Script/UMG.TextBlock',lbox,'PBZLab_L'..i..sfx)
        lbox:SetContent(l)
        local r=construct('/Script/UMG.TextBlock',h,'PBZLab_R'..i..sfx)
        clip(l)
        local ls=h:AddChildToHorizontalBox(lbox)
        local rs=h:AddChildToHorizontalBox(r)
        pcall(function() ls:SetVerticalAlignment(2) end)
        pcall(function() rs:SetVerticalAlignment(2) end)
        -- Up to three colored cells for "chips" rows (legend), packed left; collapsed otherwise.
        local chips={}
        for c=1,3 do
            local t=construct('/Script/UMG.TextBlock',h,'PBZLab_C'..i..'_'..c..sfx)
            local cs=h:AddChildToHorizontalBox(t)
            pcall(function()
                cs:SetSize({SizeRule=0,Value=0.0})
                cs:SetPadding({Left=0,Top=0,Right=16,Bottom=0})
                cs:SetVerticalAlignment(2)
            end)
            setVis(t,VIS_COLLAPSED)
            chips[c]=t
        end
        box:AddChildToVerticalBox(bg)
        setVis(bg,VIS_COLLAPSED)
        rows[i]={bg=bg,l=l,r=r,lbox=lbox,ls=ls,rs=rs,chips=chips}
    end

    local slot=canvas:AddChildToCanvas(size)
    pcall(function()
        if M.POSITION=='TopLeft' then
            slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=0,Y=0}})
            slot:SetAlignment({X=0,Y=0})
            slot:SetPosition({X=24,Y=96})
        else
            slot:SetAnchors({Minimum={X=1,Y=0},Maximum={X=1,Y=0}})
            slot:SetAlignment({X=1,Y=0})
            slot:SetPosition({X=-24,Y=96})
        end
        slot:SetAutoSize(true)
    end)
    for _,x in ipairs({w,canvas,size,card,box}) do setVis(x,VIS_HITTEST_INVISIBLE) end
    w:AddToViewport(50)
    hud=w
end

local function ensure()
    if valid(hud) then
        local inViewport=true
        pcall(function() inViewport=hud:IsInViewport() end)
        if inViewport then return true end
    end
    local ok,err=pcall(build)
    if not ok then hud=nil;return false,err end
    return true
end

function M.toggle() visible=not visible;if valid(hud) then setVis(hud,visible and VIS_HITTEST_INVISIBLE or VIS_COLLAPSED) end end
function M.visible() return visible end

M.NAME_W=150 -- label column width of "inline" rows (accessory name), so their tags line up

-- English accessory names are much longer ("ANCIENT ARMOR FRAGMENT·SUPERIOR"), so the card and the
-- name column widen for English text. Re-lays out every row on the next render.
local NARROW,WIDE={width=380,name=150},{width=500,name=300}
function M.setWide(wide)
    local s=wide and WIDE or NARROW
    if M.WIDTH==s.width and M.NAME_W==s.name then return end
    M.WIDTH,M.NAME_W=s.width,s.name
    if valid(sizeBox) then pcall(function() sizeBox:SetWidthOverride(M.WIDTH) end) end
    for i,row in ipairs(rows) do row.mode=nil;last[i]=nil end
end

-- Row layouts: 'lr' label left / value right-aligned; 'inline' fixed-width label with the value
-- left-aligned right after it; 'chips' up to three colored cells packed left.
local function setMode(row,mode)
    if row.mode==mode then return end
    local text=mode~='chips' and VIS_HITTEST_INVISIBLE or VIS_COLLAPSED
    local ch=mode=='chips' and VIS_HITTEST_INVISIBLE or VIS_COLLAPSED
    setVis(row.lbox,text);setVis(row.l,text);setVis(row.r,text)
    for _,t in ipairs(row.chips) do setVis(t,ch) end
    if mode=='inline' then
        pcall(function() row.lbox:SetWidthOverride(M.NAME_W) end)
        pcall(function() row.ls:SetSize({SizeRule=0,Value=0.0}) end)
        pcall(function() row.rs:SetSize({SizeRule=1,Value=1.0});row.rs:SetHorizontalAlignment(1) end)
        pcall(function() row.rs:SetPadding({Left=8,Top=0,Right=0,Bottom=0}) end)
    elseif mode=='lr' then
        pcall(function() row.lbox:ClearWidthOverride() end)
        pcall(function() row.ls:SetSize({SizeRule=1,Value=1.0}) end)
        pcall(function() row.rs:SetSize({SizeRule=0,Value=0.0});row.rs:SetHorizontalAlignment(3) end)
        pcall(function() row.rs:SetPadding({Left=10,Top=0,Right=0,Bottom=0}) end)
    end
    row.mode=mode
end

-- items: array of {kind='title'|'section'|'row'|'inline'|'gap', l=, r=, lc=colorName, rc=colorName}
--   or {kind='chips', cells={{text,colorName},...}} for up to three colored cells on one line.
function M.render(items)
    if not visible then return end
    local ok,err=ensure()
    if not ok then return err end
    for i=1,M.ROWS do
        local row,it=rows[i],items[i]
        if it and it.kind=='chips' then
            local parts={'chips'}
            for c,cell in ipairs(it.cells) do parts[#parts+1]=cell[1]..'/'..cell[2] end
            local key=table.concat(parts,'|')
            if last[i]~=key then
                setMode(row,'chips')
                pcall(function() row.bg:SetBrushColor({R=0,G=0,B=0,A=0}) end)
                pcall(function() row.bg:SetPadding({Left=12,Top=1,Right=12,Bottom=1}) end)
                for c=1,3 do
                    local cell=it.cells[c]
                    style(row.chips[c],M.FONT,M.COLORS[cell and cell[2] or 'text'])
                    pcall(function() row.chips[c]:SetText(FText(cell and cell[1] or '')) end)
                end
                if last[i]==nil or last[i]=='' then setVis(row.bg,VIS_HITTEST_INVISIBLE) end
                last[i]=key
            end
        elseif it then
            local key=(it.kind or 'row')..'|'..(it.l or '')..'|'..(it.r or '')..'|'..(it.lc or '')..'|'..(it.rc or '')
            if last[i]~=key then
                local kind=it.kind or 'row'
                setMode(row,kind=='inline' and 'inline' or 'lr')
                local lsize,lcolor,rcolor=M.FONT,M.COLORS[it.lc or 'label'],M.COLORS[it.rc or 'text']
                local bgColor={R=0,G=0,B=0,A=0}
                local pad={Left=12,Top=1,Right=12,Bottom=1}
                if kind=='title' then
                    lsize=M.FONT+2;lcolor=M.COLORS.accent;rcolor=M.COLORS[it.rc or 'dim']
                    bgColor=HEADER;pad={Left=12,Top=6,Right=12,Bottom=6}
                elseif kind=='section' then
                    lcolor=M.COLORS.accent;pad={Left=12,Top=7,Right=12,Bottom=2}
                elseif kind=='gap' then
                    pad={Left=0,Top=2,Right=0,Bottom=2}
                end
                pcall(function() row.bg:SetBrushColor(bgColor) end)
                pcall(function() row.bg:SetPadding(pad) end)
                style(row.l,lsize,lcolor)
                style(row.r,M.FONT,rcolor)
                pcall(function() row.l:SetText(FText(it.l or '')) end)
                pcall(function() row.r:SetText(FText(it.r or '')) end)
                if last[i]==nil or last[i]=='' then setVis(row.bg,VIS_HITTEST_INVISIBLE) end
                last[i]=key
            end
        elseif last[i]~='' then
            setVis(row.bg,VIS_COLLAPSED)
            last[i]=''
        end
    end
end

function M.destroy()
    if valid(hud) then pcall(function() hud:RemoveFromParent() end) end
    hud=nil
end

return M
