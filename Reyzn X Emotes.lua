--[[
 Reyzn X Emotes v1.0 | standalone universal R15 emote & animation browser
 Built from scratch. Inspired by standard emote catalog and Animator techniques.
 Designed for desktop + mobile. No purchase/access-control bypass.
 FE note: only animations that Roblox successfully loads on a SERVER-CREATED
 Animator of your own character may replicate. Not guaranteed in every game.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer
if not player then return end

local globalEnv = _G
pcall(function()
    if type(getgenv) == "function" then globalEnv = getgenv() end
end)
if type(globalEnv.ReyznXEmotesExit) == "function" then
    pcall(globalEnv.ReyznXEmotesExit)
end

local running = true
local connections = {}
local function trackConnection(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections,c)
    return c
end
local function guarded(fn,...)
    local ok,value=pcall(fn,...)
    if ok then return value end
    return nil
end
local function getRig()
    local char=player.Character
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.RigType~=Enum.HumanoidRigType.R15 then return end
    local animator=hum:FindFirstChildOfClass("Animator")
    -- Do not create a local Animator. It would not replicate.
    if not animator then return end
    return char,hum,animator
end

local packList, emoteList={},{}
local packIds, emoteIds={},{}
local favorites={}
local selectedPack=nil
local movementTracks={}
local movementAnimations={}
local currentMovement=nil
local currentHumanoid=nil
local currentAnimator=nil
local activeEmoteTrack=nil
local activeEmoteAnimation=nil
local activeEmoteRequested=false
local loopEmotes=false
local emoteSpeed=1
local autoApply=true
local searchTerm=""
local currentTab="Emotes"
local localPage=1
local pageSize=22
local catalogPages=nil
local catalogBusy=false
local catalogKeyword=nil
local catalogExhausted=false
local statusText
local searchBox
local render

local function say(msg)
    if statusText and running then statusText.Text=tostring(msg) end
end

local function addEmote(name,id,kind,customAnimId)
    id=tonumber(id)
    if not id or id<1 or emoteIds[id] then return false end
    emoteIds[id]=true
    table.insert(emoteList,{
        kind="Emote", name=tostring(name),id=id,
        origin=kind or "Roblox catalog", fallback=customAnimId
    })
    return true
end
local function addPack(name,clips)
    if packIds[name] then return end
    packIds[name]=true
    table.insert(packList,{kind="Pack",id=name,name=name,clips=clips,origin="R15 Pack"})
end
local emoteDefaults={
    {"Hello",3576686446},
    {"Stadium",3360686498},
    {"Tilt",3360692915},
    {"Shrug",3576968026},
    {"Salute",3360689775},
    {"Point",3576823880},
}
for _,e in ipairs(emoteDefaults) do addEmote(e[1],e[2],"Official Emote") end

-- Default R15 animation-sequence IDs for reliable fallback actions.
local classic={
    {"Wave",507770239},
    {"Cheer",507770677},
    {"Laugh",507770818},
    {"Dance 1",507771019},
    {"Dance 2",507776043},
    {"Dance 3",507777268},
}
for _,e in ipairs(classic) do
    addEmote(e[1],e[2],"Classic Animation",e[2])
end

-- Roblox movement presets; each row is name,run,walk,jump,idle1,idle2,fall,swim,swimidle,climb.

local movementRows = {
    {"Astronaut",891636393,891636393,891627522,891621366,891633237,891617961,891639666,891663592,891609353},
    {"Bubbly",910025107,910034870,910016857,910004836,910009958,910001910,910028158,910030921,909997997},
    {"Cartoony",742638842,742640026,742637942,742637544,742638445,742637151,742639220,742639812,742636889},
    {"Elder",845386501,845403856,845398858,845397899,845400520,845396048,845401742,845403127,845392038},
    {"Knight",657564596,657552124,658409194,657595757,657568135,657600338,657560551,657557095,658360781},
    {"Levitation",616010382,616013216,616008936,616006778,616008087,616005863,616011509,616012453,616003713},
    {"Mage",707861613,707897309,707853694,707742142,707855907,707829716,707876443,707894699,707826056},
    {"Ninja",656118852,656121766,656117878,656117400,656118341,656115606,656119721,656121397,656114359},
    {"Pirate",750783738,750785693,750782230,750781874,750782770,750780242,750784579,750785176,750779899},
    {"Robot",616091570,616095330,616090535,616088211,616089559,616087089,616092998,616094091,616086039},
    {"Rthro",2510198475,2510202577,2510197830,2510197257,2510196951,2510195892,2510199791,2510201162,2510192778},
    {"Stylish",616140816,616146177,616139451,616136790,616138447,616134815,616143378,616144772,616133594},
    {"Superhero",616117076,616122287,616115533,616111295,616113536,616108001,616119360,616120861,616104706},
    {"Toy",782842708,782843345,782847020,782841498,782845736,782846423,782844582,782845186,782843869},
    {"Vampire",1083462077,1083473930,1083455352,1083445855,1083450166,1083443587,1083464683,1083467779,1083439238},
    {"Werewolf",1083216690,1083178339,1083218792,1083195517,1083214717,1083189019,1083222527,1083225406,1083182000},
    {"Zombie",616163682,616168032,616161997,616158929,616160636,616157476,616165109,616166655,616156119},
}

for _,r in ipairs(movementRows) do
    addPack(r[1],{
        run=r[2],walk=r[3],jump=r[4],idle1=r[5],idle2=r[6],
        fall=r[7],swim=r[8],swimidle=r[9],climb=r[10]
    })
end
table.sort(packList,function(a,b) return a.name<b.name end)

local function saveFavorites()
    if type(writefile)=="function" then
        pcall(function()
            writefile("ReyznXEmotes_favorites.json",HttpService:JSONEncode(favorites))
        end)
    end
end
if type(isfile)=="function" and type(readfile)=="function" then
    pcall(function()
        if isfile("ReyznXEmotes_favorites.json") then
            local value=HttpService:JSONDecode(readfile("ReyznXEmotes_favorites.json"))
            if type(value)=="table" then favorites=value end
        end
    end)
end
local function itemKey(it) return it.kind..":"..tostring(it.id) end

local function stopCurrentEmote()
    if activeEmoteTrack then
        pcall(function() activeEmoteTrack:Stop(0.15) end)
        activeEmoteTrack=nil
    end
    if activeEmoteAnimation then
        pcall(function() activeEmoteAnimation:Destroy() end)
        activeEmoteAnimation=nil
    end
    activeEmoteRequested=false
end
local function killMovement()
    for _,t in pairs(movementTracks) do
        pcall(function() t:Stop(0.12) end)
        pcall(function() t:Destroy() end)
    end
    for _,a in ipairs(movementAnimations) do pcall(function() a:Destroy() end) end
    movementTracks={}
    movementAnimations={}
    currentMovement=nil
    currentHumanoid=nil
    currentAnimator=nil
end
local function stopEverything()
    stopCurrentEmote()
    killMovement()
    selectedPack=nil
end

local function playEmote(item)
    local char,hum,animator=getRig()
    if not hum then say("R15 + server Animator required.");return end
    stopCurrentEmote()
    -- Official emotes must be installed on the character's description.
    -- Attempt normal Roblox emote playback before a direct Animation fallback.
    if not item.fallback then
        local description=hum:FindFirstChildOfClass("HumanoidDescription")
        local alias="RZX_"..tostring(item.id)
        if description then
            pcall(function() description:AddEmote(alias,item.id) end)
            local ok,played=pcall(function() return hum:PlayEmoteAsync(alias) end)
            if ok and played then
                activeEmoteRequested=true
                say("Emote requested: "..item.name.." | FE depends on game")
                return
            end
        end
        -- Some environments expose a Roblox-owned emote playback entry point.
        -- It is optional and may be blocked. Failure simply falls through.
        local ok,trackOrResult=pcall(function()
            return hum:PlayEmoteAndGetAnimTrackById(item.id)
        end)
        if ok and trackOrResult then
            if typeof(trackOrResult)=="Instance" and trackOrResult:IsA("AnimationTrack") then
                activeEmoteTrack=trackOrResult
            end
            activeEmoteRequested=true
            say("Emote invoked: "..item.name.." | FE unverified")
            return
        end
    end
    -- Fallback: can play an accessible animation SEQUENCE, but does not
    -- bypass catalog asset permissions and may be invisible to others.
    local animation=Instance.new("Animation")
    animation.AnimationId="rbxassetid://"..tostring(item.fallback or item.id)
    local ok,track=pcall(function() return animator:LoadAnimation(animation) end)
    if not ok or not track then
        animation:Destroy()
        say("Unavailable or restricted: "..item.name)
        return
    end
    track.Priority=Enum.AnimationPriority.Action4
    track.Looped=loopEmotes
    if not pcall(function() track:Play(0.15,1,emoteSpeed) end) then
        pcall(function() track:Destroy() end)
        animation:Destroy()
        say("Failed to play: "..item.name)
        return
    end
    activeEmoteTrack=track
    activeEmoteAnimation=animation
    say("Playing "..item.name.." | Other-player visibility not guaranteed")
    task.delay(2,function()
        if running and activeEmoteTrack==track then
            local length=guarded(function() return track.Length end)
            if not length or length<=0 then
                say("Animation may be unavailable / not loaded in this game.")
            end
        end
    end)
end

-- Smooth movement controller. Uses Movement priority ABOVE Roblox's Core
-- locomotion animations and DOES NOT alter the game's Animate script.
local jumpHoldUntil=0
local idleSwitchAt=0
local idleVariant="idle1"
local lastUpdate=0
local function loadSelectedPack(pack)
    killMovement()
    local _,hum,animator=getRig()
    if not hum then say("R15 + server Animator required.");return false end
    currentHumanoid=hum
    currentAnimator=animator
    for key,id in pairs(pack.clips) do
        local animation=Instance.new("Animation")
        animation.Name="RZX_"..key
        animation.AnimationId="rbxassetid://"..tostring(id)
        table.insert(movementAnimations,animation)
        local ok,t=pcall(function() return animator:LoadAnimation(animation) end)
        if ok and t then
            t.Priority=(key=="idle1" or key=="idle2") and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement
            t.Looped=(key~="jump")
            movementTracks[key]=t
        end
    end
    if not next(movementTracks) then
        killMovement()
        say("Could not load pack "..pack.name)
        return false
    end
    selectedPack=pack
    jumpHoldUntil=0
    idleVariant="idle1"
    idleSwitchAt=os.clock()+8
    say("Pack selected: "..pack.name.." | Preview in movement")
    return true
end
local function selectPose(pose,multiplier)
    if pose==currentMovement then
        local t=pose and movementTracks[pose]
        if t and t.IsPlaying then
            pcall(function() t:AdjustSpeed(multiplier or 1) end)
        end
        return
    end
    if currentMovement and movementTracks[currentMovement] then
        pcall(function() movementTracks[currentMovement]:Stop(0.16) end)
    end
    currentMovement=pose
    local track=pose and movementTracks[pose]
    if track then
        pcall(function() track:Play(0.16,1,multiplier or 1) end)
    end
end
local function updateMovement()
    if not selectedPack then return end
    local now=os.clock()
    if now-lastUpdate<0.09 then return end
    lastUpdate=now
    local char,hum,animator=getRig()
    if not hum or hum~=currentHumanoid or animator~=currentAnimator then
        selectPose(nil)
        return
    end
    if hum.Health<=0 then selectPose(nil);return end
    local state=hum:GetState()
    local pose,speed
    speed=1
    if state==Enum.HumanoidStateType.Dead or state==Enum.HumanoidStateType.Seated
        or state==Enum.HumanoidStateType.PlatformStanding
        or state==Enum.HumanoidStateType.Physics then
        pose=nil
    elseif state==Enum.HumanoidStateType.Swimming then
        pose=hum.MoveDirection.Magnitude>0.08 and "swim" or "swimidle"
    elseif state==Enum.HumanoidStateType.Climbing then
        pose="climb"
        local root=char:FindFirstChild("HumanoidRootPart")
        speed=(root and math.abs(root.AssemblyLinearVelocity.Y)>0.3) and 1 or 0
    elseif state==Enum.HumanoidStateType.Jumping then
        jumpHoldUntil=now+0.3
        pose="jump"
    elseif state==Enum.HumanoidStateType.Freefall or state==Enum.HumanoidStateType.FallingDown then
        pose=now<jumpHoldUntil and "jump" or "fall"
    else
        local root=char:FindFirstChild("HumanoidRootPart")
        local v=root and root.AssemblyLinearVelocity
        local horizontalSpeed=v and Vector3.new(v.X,0,v.Z).Magnitude or 0
        if hum.MoveDirection.Magnitude>0.08 then
            pose=horizontalSpeed>math.max(8,hum.WalkSpeed*0.66) and "run" or "walk"
            speed=math.clamp(horizontalSpeed/(pose=="run" and 16 or 8),0.6,1.8)
        else
            if now>idleSwitchAt then
                idleVariant=idleVariant=="idle1" and "idle2" or "idle1"
                idleSwitchAt=now+math.random(7,13)
            end
            pose=idleVariant
        end
    end
    if pose and not movementTracks[pose] then
        pose=movementTracks.idle1 and "idle1" or nil
    end
    selectPose(pose,speed)
end
trackConnection(RunService.Heartbeat,updateMovement)
trackConnection(player.CharacterAdded,function(char)
    stopCurrentEmote()
    killMovement()
    task.spawn(function()
        char:WaitForChild("Humanoid",12)
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum:WaitForChild("Animator",12) end
        if not running then return end
        if player.Character==char and autoApply and selectedPack then
            -- selectedPack survives killMovement; relink on respawn.
            task.wait(0.4)
            if running and player.Character==char then loadSelectedPack(selectedPack) end
        end
    end)
end)

-- Marketplace results are listed even when a player does not own them.
-- Browsing does not grant animation permissions.
local function mergeCatalogPage(pages)
    local ok,items=pcall(function() return pages:GetCurrentPage() end)
    if not ok or type(items)~="table" then return 0 end
    local added=0
    for _,data in ipairs(items) do
        local id=tonumber(data.Id or data.id)
        local name=data.Name or data.name
        if id and name and addEmote(name,id,"Roblox Catalog") then added=added+1 end
    end
    catalogExhausted=pages.IsFinished
    return added
end
local function catalogQuery(keyword,more)
    if catalogBusy then say("Catalog request in progress."); return end
    if more and (not catalogPages or catalogExhausted) then
        say("No more catalog pages."); return
    end
    catalogBusy=true
    say("Searching official Roblox catalog...")
    task.spawn(function()
        local ok,pages
        if more then
            pages=catalogPages
            ok=pcall(function() pages:AdvanceToNextPageAsync() end)
        else
            local params=CatalogSearchParams.new()
            params.AssetTypes={Enum.AvatarAssetType.EmoteAnimation}
            params.IncludeOffSale=true
            params.Limit=60
            params.SortType=Enum.CatalogSortType.RecentlyCreated
            params.SearchKeyword=keyword or ""
            ok,pages=pcall(function()
                return AvatarEditorService:SearchCatalogAsync(params)
            end)
        end
        if ok and pages then
            if not more then catalogPages=pages;catalogKeyword=keyword or "" end
            local added=mergeCatalogPage(pages)
            say("Catalog loaded: +"..added.." | restricted emotes may not play.")
        else
            say("Catalog blocked/unavailable. Built-in library still works.")
        end
        catalogBusy=false
        if running and render then render() end
    end)
end

-- ========= UI (original, not copied from other projects) =========
local palette={
    base=Color3.fromRGB(13,11,21), panel=Color3.fromRGB(23,20,35),
    row=Color3.fromRGB(34,29,48), purple=Color3.fromRGB(164,101,251),
    white=Color3.fromRGB(240,235,252), muted=Color3.fromRGB(154,146,175)
}
local function new(class,parent,props)
    local obj=Instance.new(class)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent
    return obj
end
local function round(obj,r) new("UICorner",obj,{CornerRadius=UDim.new(0,r)}) end
local function outline(obj,color,trans)
    new("UIStroke",obj,{Color=color or palette.purple,Transparency=trans or 0.55,Thickness=1})
end
local function text(parent,value,x,y,w,h,size,bold,color)
    return new("TextLabel",parent,{
        Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundTransparency=1,Text=tostring(value),
        TextColor3=color or palette.white,
        Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextSize=size or 13,TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd
    })
end
local function button(parent,value,x,y,w,h,isPrimary)
    local obj=new("TextButton",parent,{
        Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundColor3=isPrimary and Color3.fromRGB(95,52,150) or palette.row,
        BorderSizePixel=0,Text=tostring(value),TextColor3=palette.white,
        TextSize=12,Font=Enum.Font.GothamBold,AutoButtonColor=true
    })
    round(obj,8)
    return obj
end

local gui=new("ScreenGui",nil,{
    Name="Reyzn_X_Emotes",ResetOnSpawn=false,IgnoreGuiInset=true,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=300
})
local uiParent=nil
if type(gethui)=="function" then uiParent=guarded(gethui) end
if not uiParent then uiParent=CoreGui end
if not pcall(function() gui.Parent=uiParent end) then
    gui.Parent=player:WaitForChild("PlayerGui")
end
local root=new("Frame",gui,{
    Size=UDim2.fromOffset(628,459),
    Position=UDim2.fromScale(0.5,0.5),AnchorPoint=Vector2.new(0.5,0.5),
    BackgroundColor3=palette.base,BorderSizePixel=0
})
round(root,15);outline(root,palette.purple,0.28)
local scale=new("UIScale",root,{Scale=1})
local function rescale()
    local cam=workspace.CurrentCamera
    if cam then
        scale.Scale=math.clamp(math.min(cam.ViewportSize.X/660,cam.ViewportSize.Y/495),0.48,1)
    end
end
rescale()
if workspace.CurrentCamera then
    trackConnection(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),rescale)
end

local header=new("Frame",root,{BackgroundTransparency=1,Size=UDim2.new(1,0,0,66)})
text(header,"REYZN X",16,9,150,29,21,true,palette.white)
text(header,"EMOTES",122,9,115,29,21,true,palette.purple)
text(header,"Universal R15  /  Emotes + Animation Packs",17,38,475,18,11,false,palette.muted)
local minimize=button(header,"−",548,14,30,30,false)
local close=button(header,"×",586,14,30,30,false)
local bar=new("Frame",root,{Position=UDim2.fromOffset(0,66),
    Size=UDim2.new(1,0,0,1),BorderSizePixel=0,BackgroundColor3=Color3.fromRGB(64,49,89)})
local sidebar=new("Frame",root,{Position=UDim2.fromOffset(12,79),
    Size=UDim2.fromOffset(141,337),BackgroundColor3=palette.panel,BorderSizePixel=0})
round(sidebar,11)
local body=new("Frame",root,{Position=UDim2.fromOffset(164,79),
    Size=UDim2.fromOffset(451,337),BackgroundColor3=palette.panel,BorderSizePixel=0})
round(body,11)
local tabs={}
for i,name in ipairs({"Emotes","Packs","Favorites","Settings"}) do
    tabs[name]=button(sidebar,name,9,10+(i-1)*51,123,40,false)
    trackConnection(tabs[name].MouseButton1Click,function()
        currentTab=name
        searchTerm="";localPage=1
        if searchBox then searchBox.Text="" end
        if render then render() end
    end)
end
text(sidebar,"R15  •  FE depends",9,296,125,22,10,false,palette.muted)

searchBox=new("TextBox",body,{
    Position=UDim2.fromOffset(12,11),Size=UDim2.fromOffset(277,37),
    BackgroundColor3=palette.row,BorderSizePixel=0,
    ClearTextOnFocus=false,Text="",TextColor3=palette.white,
    PlaceholderText="Search name or animation ID",PlaceholderColor3=palette.muted,
    TextSize=13,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left
})
new("UIPadding",searchBox,{PaddingLeft=UDim.new(0,11)})
round(searchBox,8)
local searchCatalog=button(body,"Search Catalog",299,11,140,37,true)
local list=new("ScrollingFrame",body,{
    Position=UDim2.fromOffset(12,60),Size=UDim2.fromOffset(427,216),
    BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,
    ScrollBarImageColor3=palette.purple,CanvasSize=UDim2.fromOffset(0,0)
})
local layout=new("UIListLayout",list,{
    Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder
})
trackConnection(layout:GetPropertyChangedSignal("AbsoluteContentSize"),function()
    list.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+5)
end)
local prev=button(body,"◀ Prev",12,286,88,34,false)
local next=button(body,"Next ▶",351,286,88,34,false)
local pageLabel=text(body,"Page 1",115,287,225,33,12,true,palette.muted)
pageLabel.TextXAlignment=Enum.TextXAlignment.Center
statusText=text(root,"Ready • Reproduction may be restricted by game",15,428,598,22,11,false,palette.muted)

local minimized=false
trackConnection(minimize.MouseButton1Click,function()
    minimized=not minimized
    root.Size=UDim2.fromOffset(628,minimized and 66 or 459)
    bar.Visible=not minimized
    sidebar.Visible=not minimized
    body.Visible=not minimized
    statusText.Visible=not minimized
    minimize.Text=minimized and "+" or "−"
end)

local drag=false
local dragOrigin,dragPosition,dragTouch
trackConnection(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1
        or input.UserInputType==Enum.UserInputType.Touch then
        drag=true
        dragOrigin=input.Position
        dragPosition=root.Position
        dragTouch=input
    end
end)
trackConnection(UserInputService.InputChanged,function(input)
    if drag and (input==dragTouch or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-dragOrigin
        root.Position=UDim2.new(dragPosition.X.Scale,dragPosition.X.Offset+delta.X,
            dragPosition.Y.Scale,dragPosition.Y.Offset+delta.Y)
    end
end)
trackConnection(UserInputService.InputEnded,function(input)
    if input==dragTouch then drag=false end
end)

local function closeUI()
    if not running then return end
    running=false
    stopEverything()
    for _,c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    gui:Destroy()
    if globalEnv.ReyznXEmotesExit==closeUI then globalEnv.ReyznXEmotesExit=nil end
end
globalEnv.ReyznXEmotesExit=closeUI
trackConnection(close.MouseButton1Click,closeUI)

local function clearList()
    for _,child in ipairs(list:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
end
local function listItem(item,index)
    local frame=new("Frame",list,{
        Size=UDim2.new(1,-6,0,51),LayoutOrder=index,
        BackgroundColor3=palette.row,BorderSizePixel=0
    })
    round(frame,8)
    text(frame,item.name,11,5,246,23,13,true)
    text(frame,item.origin,11,28,245,17,10,false,palette.muted)
    local b=button(frame,item.kind=="Pack" and "APPLY" or "PLAY",286,9,76,33,true)
    trackConnection(b.MouseButton1Click,function()
        if item.kind=="Pack" then
            loadSelectedPack(item)
        else
            task.spawn(function() playEmote(item) end)
        end
    end)
    local key=itemKey(item)
    local fav=button(frame,favorites[key] and "★" or "☆",369,9,37,33,false)
    fav.TextSize=18
    fav.TextColor3=palette.purple
    trackConnection(fav.MouseButton1Click,function()
        favorites[key]=not favorites[key] and true or nil
        fav.Text=favorites[key] and "★" or "☆"
        saveFavorites()
        if currentTab=="Favorites" then render() end
    end)
end
local function settingLine(value,index,callback)
    local b=new("TextButton",list,{
        LayoutOrder=index,Size=UDim2.new(1,-6,0,42),
        BackgroundColor3=palette.row,BorderSizePixel=0,
        Text=value,Font=Enum.Font.GothamBold,TextSize=13,
        TextColor3=palette.white
    })
    round(b,8)
    trackConnection(b.MouseButton1Click,callback)
end
local function filtered()
    local base={}
    if currentTab=="Emotes" then base=emoteList
    elseif currentTab=="Packs" then base=packList
    elseif currentTab=="Favorites" then
        for _,it in ipairs(emoteList) do
            if favorites[itemKey(it)] then table.insert(base,it) end
        end
        for _,it in ipairs(packList) do
            if favorites[itemKey(it)] then table.insert(base,it) end
        end
    end
    local result={}
    for _,it in ipairs(base) do
        if searchTerm=="" or string.find(string.lower(it.name),string.lower(searchTerm),1,true)
        or string.find(tostring(it.id),searchTerm,1,true) then
            table.insert(result,it)
        end
    end
    return result
end
render=function()
    if not running then return end
    clearList()
    for name,b in pairs(tabs) do
        b.BackgroundColor3=name==currentTab and Color3.fromRGB(94,51,151) or palette.row
    end
    searchBox.Visible=currentTab~="Settings"
    searchCatalog.Visible=currentTab=="Emotes"
    prev.Visible=currentTab~="Settings"
    next.Visible=currentTab~="Settings"
    if currentTab=="Settings" then
        pageLabel.Text="SETTINGS"
        settingLine("Stop current emote",1,function()
            stopCurrentEmote()
            say("Stopped locally controlled emote.")
        end)
        settingLine("Remove movement pack",2,function()
            selectedPack=nil
            killMovement()
            say("Default character movement restored.")
        end)
        settingLine("Auto-apply on respawn: "..(autoApply and "ON" or "OFF"),3,function()
            autoApply=not autoApply
            render()
        end)
        settingLine("Loop manually played emotes: "..(loopEmotes and "ON" or "OFF"),4,function()
            loopEmotes=not loopEmotes
            if activeEmoteTrack then activeEmoteTrack.Looped=loopEmotes end
            render()
        end)
        settingLine("Emote playback speed: "..tostring(emoteSpeed).."x",5,function()
            if emoteSpeed==1 then emoteSpeed=1.25
            elseif emoteSpeed==1.25 then emoteSpeed=1.5
            elseif emoteSpeed==1.5 then emoteSpeed=0.75
            else emoteSpeed=1 end
            if activeEmoteTrack then
                pcall(function() activeEmoteTrack:AdjustSpeed(emoteSpeed) end)
            end
            render()
        end)
        return
    end
    local items=filtered()
    local totalPages=math.max(1,math.ceil(#items/pageSize))
    localPage=math.clamp(localPage,1,totalPages)
    local first=(localPage-1)*pageSize+1
    for i=first,math.min(#items,first+pageSize-1) do
        listItem(items[i],i-first+1)
    end
    if #items==0 then
        local no=text(list,"No matches. Try a different name or catalog search.",14,11,389,35,12,false,palette.muted)
        no.LayoutOrder=1
    end
    pageLabel.Text=string.format("%d / %d   •   %d items",localPage,totalPages,#items)
    list.CanvasPosition=Vector2.zero
end
trackConnection(searchBox:GetPropertyChangedSignal("Text"),function()
    searchTerm=searchBox.Text
    localPage=1
    render()
end)
trackConnection(searchCatalog.MouseButton1Click,function()
    if catalogBusy then return end
    local query=searchTerm
    if catalogPages and catalogKeyword==query and not catalogExhausted then
        catalogQuery(query,true)
    else
        catalogQuery(query,false)
    end
end)
trackConnection(prev.MouseButton1Click,function()
    localPage=math.max(1,localPage-1)
    render()
end)
trackConnection(next.MouseButton1Click,function()
    localPage=localPage+1
    render()
end)
render()
if not getRig() then
    say("R15 + server-created Animator required.")
else
    say("Ready • Emotes: owned/allowed only • FE may vary by game")
end
-- Catalog browsing is on-demand to avoid infinite loading or startup stalls.
