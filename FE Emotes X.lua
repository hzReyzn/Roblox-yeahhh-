--[[
 FE Emotes X | Universal R15 Animation Browser (v1.0)
 Independent community tool | Mobile + Desktop
 Official Roblox catalog search is optional (some games/executors block HTTP).
 Catalog visibility DOES NOT mean ownership or playback permission.
 Other players see tracks ONLY if Roblox/game replication and asset access allow it.
 No ownership, permission or server checks are bypassed.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local localPlayer = Players.LocalPlayer
if not localPlayer then return end

local environment = _G
pcall(function()
    if type(getgenv) == "function" then environment = getgenv() end
end)
if type(environment.FEEmotesXCleanup) == "function" then
    pcall(environment.FEEmotesXCleanup)
end

local connections = {}
local gui
local alive = true
local humanoid, animator, character
local playingEmote, playingAnimation
local selectedPack = nil
local autoReapply = true
local loopEmotes = false
local playSpeed = 1
local originals = setmetatable({}, {__mode = "k"})
local currentTab = "Emotes"
local searchText = ""
local currentPage = 1
local pageSize = 35
local emotes = {}
local packs = {}
local knownEmotes = {}
local knownPacks = {}
local favorites = {}
local statusLabel, counterLabel
local render

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end
local function status(message)
    if alive and statusLabel then statusLabel.Text = tostring(message) end
end
local function keyOf(item)
    return item.kind .. ":" .. tostring(item.id)
end
local function addEmote(name, id, source)
    id = tonumber(id)
    if not id or id <= 0 or knownEmotes[id] then return false end
    knownEmotes[id] = true
    table.insert(emotes, {name = name or ("Emote " .. id), id = id, kind = "Emote", source = source or "Catalog"})
    return true
end
local function addPack(name, id, animations, source)
    local k = tostring(id or name)
    if knownPacks[k] then return false end
    knownPacks[k] = true
    table.insert(packs, {
        name = name, id = id or name, kind = "Pack",
        clips = animations, source = source or "Roblox"
    })
    return true
end

-- Starter library: Roblox default R15 emote ANIMATION IDs, not catalog listing IDs.
addEmote("Classic Wave", 507770239, "R15")
addEmote("Classic Point", 507770453, "R15")
addEmote("Classic Cheer", 507770677, "R15")
addEmote("Classic Laugh", 507770818, "R15")
addEmote("Classic Dance 1", 507771019, "R15")
addEmote("Classic Dance 2", 507776043, "R15")
addEmote("Classic Dance 3", 507777268, "R15")

-- Verified public movement clip references from create.roblox.com/docs/animation/using
-- Columns: name, run, walk, jump, idle1, idle2, fall, swim, swimidle, climb.
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
for _, row in ipairs(movementRows) do
    addPack(row[1], row[1], {
        run=row[2], walk=row[3], jump=row[4],
        idle1=row[5], idle2=row[6], fall=row[7],
        swim=row[8], swimidle=row[9], climb=row[10]
    }, "Roblox Reference")
end

local function getRig()
    character = localPlayer.Character
    if not character then return nil end
    humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then return nil end
    -- NEVER create a client-side Animator: tracks would not replicate.
    animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return nil end
    return humanoid
end

local function stopEmote()
    if playingEmote then
        pcall(function() playingEmote:Stop(0.18) end)
        playingEmote = nil
    end
    if playingAnimation then
        playingAnimation:Destroy()
        playingAnimation = nil
    end
end

local function playEmote(item)
    if not getRig() then status("R15 + server Animator required.") return end
    stopEmote()
    local animation = Instance.new("Animation")
    animation.AnimationId = "rbxassetid://" .. tostring(item.id)
    local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
    if not ok or not track then
        animation:Destroy()
        status("Cannot load: " .. item.name .. " (permissions/game).")
        return
    end
    track.Priority = Enum.AnimationPriority.Action
    track.Looped = loopEmotes
    local played = pcall(function()
        track:Play(0.15, 1, playSpeed)
    end)
    if not played then
        pcall(function() track:Destroy() end)
        animation:Destroy()
        status("Unable to play this emote.")
        return
    end
    playingEmote = track
    playingAnimation = animation
    status("Playing " .. item.name .. " | FE not guaranteed")
end

-- Animate children used by Roblox's default R15 movement script.
local slots = {
    run={"run","RunAnim"}, walk={"walk","WalkAnim"},
    jump={"jump","JumpAnim"}, idle1={"idle","Animation1"},
    idle2={"idle","Animation2"}, fall={"fall","FallAnim"},
    climb={"climb","ClimbAnim"}, swim={"swim","Swim"},
    swimidle={"swimidle","SwimIdle"}
}
local function findSlots(animate)
    local result = {}
    for key, path in pairs(slots) do
        local folder = animate:FindFirstChild(path[1])
        local clip = folder and folder:FindFirstChild(path[2])
        if clip and clip:IsA("Animation") then result[key] = clip end
    end
    return result
end
local function reloadAnimate(animate)
    pcall(function()
        animate.Disabled = true
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if track ~= playingEmote then track:Stop(0.12) end
            end
        end
        animate.Disabled = false
    end)
end
local function applyPack(pack, quiet)
    if not getRig() then status("This requires a standard R15 character.") return false end
    local animate = character:FindFirstChild("Animate")
    if not animate or not animate:IsA("LocalScript") then
        status("This game uses a custom/unsupported Animate system.")
        return false
    end
    local available = findSlots(animate)
    if next(available) == nil then
        status("No standard R15 animation slots in this game.")
        return false
    end
    if not originals[animate] then
        originals[animate] = {}
        for slot, clip in pairs(available) do originals[animate][slot] = clip.AnimationId end
    end
    local changed = 0
    for slot, clip in pairs(available) do
        local id = pack.clips[slot]
        if id then
            clip.AnimationId = "rbxassetid://" .. tostring(id)
            changed = changed + 1
        end
    end
    if changed == 0 then status("This pack has no matching R15 clips.") return false end
    selectedPack = pack
    reloadAnimate(animate)
    if not quiet then status("Applied " .. pack.name .. " (" .. changed .. " slots)") end
    return true
end
local function resetPack()
    selectedPack = nil
    local c = localPlayer.Character
    local animate = c and c:FindFirstChild("Animate")
    local saved = animate and originals[animate]
    if not saved then status("No original animations saved for this spawn.") return end
    local available = findSlots(animate)
    for slot, assetId in pairs(saved) do
        if available[slot] then available[slot].AnimationId = assetId end
    end
    reloadAnimate(animate)
    status("Original animations restored.")
end

-- Optional catalog browser. Loads in pages; does not confer purchase/access.
local cursors = {Emotes=nil, Packs=nil}
local finished = {Emotes=false, Packs=false}
local requestBusy = false
local function getJson(url)
    local ok, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if ok and type(result) == "table" then return result end
    local requestFn
    pcall(function()
        requestFn = (syn and syn.request) or http_request or request
    end)
    if type(requestFn) == "function" then
        local good, response = pcall(requestFn, {Url=url, Method="GET"})
        if good and response and (response.StatusCode == 200 or response.StatusCode == 201) then
            local decoded, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
            if decoded and type(data) == "table" then return data end
        end
    end
    return nil
end

-- Catalog bundle listings use bundle IDs. Contents include animation asset IDs.
local function bundleClips(bundleId)
    local data = getJson("https://catalog.roblox.com/v1/bundles/" .. tostring(bundleId) .. "/details")
    if not data or type(data.items) ~= "table" then return nil end
    local clips = {}
    for _, item in ipairs(data.items) do
        local n = string.lower(tostring(item.name or ""))
        local assetType = tonumber(item.assetType)
        local k
        if assetType == 48 or string.find(n,"climb",1,true) then k="climb"
        elseif assetType == 50 or string.find(n,"fall",1,true) then k="fall"
        elseif assetType == 52 or string.find(n,"jump",1,true) then k="jump"
        elseif assetType == 53 or string.find(n,"run",1,true) then k="run"
        elseif assetType == 55 or string.find(n,"walk",1,true) then k="walk"
        elseif assetType == 54 or string.find(n,"swim",1,true) then
            k = string.find(n,"idle",1,true) and "swimidle" or "swim"
        elseif assetType == 51 or string.find(n,"idle",1,true) then
            k = clips.idle1 and "idle2" or "idle1"
        end
        if k and tonumber(item.id) then clips[k] = tonumber(item.id) end
    end
    if next(clips) then
        if clips.idle1 and not clips.idle2 then clips.idle2 = clips.idle1 end
        return clips
    end
    return nil
end
local function catalogLoadMore(keyword)
    if requestBusy then status("Catalog request already running.") return end
    if finished[currentTab] and (not keyword or keyword == "") then
        status("End of currently available catalog results.")
        return
    end
    if currentTab ~= "Emotes" and currentTab ~= "Packs" then
        status("Choose Emotes or Packs to search the catalog.")
        return
    end
    local tab = currentTab
    requestBusy = true
    status("Loading Roblox catalog...")
    task.spawn(function()
        local cat = tab == "Emotes" and "39" or "38"
        local url = "https://catalog.roblox.com/v1/search/items/details?Category=12&Subcategory="
            .. cat .. "&Limit=30&SortType=3"
        if keyword and keyword ~= "" then
            url = url .. "&Keyword=" .. HttpService:UrlEncode(keyword)
        elseif cursors[tab] then
            url = url .. "&Cursor=" .. HttpService:UrlEncode(cursors[tab])
        end
        local data = getJson(url)
        local added = 0
        if data and type(data.data) == "table" then
            for _, item in ipairs(data.data) do
                if tab == "Emotes" and tonumber(item.assetType) == 61 then
                    if addEmote(item.name, item.id, "Catalog") then added = added + 1 end
                elseif tab == "Packs" and item.itemType == "Bundle" then
                    -- Resolve bundle animation IDs only when user selects it.
                    if addPack(item.name, item.id, nil, "Catalog Bundle") then
                        added = added + 1
                    end
                end
            end
            if not keyword or keyword == "" then
                cursors[tab] = data.nextPageCursor
                finished[tab] = (data.nextPageCursor == nil)
            end
            status("Catalog: +" .. added .. " items. Playback depends on access.")
        else
            status("Catalog unavailable here. Built-in library still works.")
        end
        requestBusy = false
        if alive and render then render() end
    end)
end

local function choosePack(item)
    if not item.clips then
        if requestBusy then status("Wait for the current catalog request.") return end
        requestBusy = true
        status("Reading " .. item.name .. " bundle clips...")
        task.spawn(function()
            local resolved = bundleClips(item.id)
            requestBusy = false
            if not alive then return end
            if not resolved then
                status("Couldn't retrieve animation clips for this bundle.")
                return
            end
            item.clips = resolved
            applyPack(item)
        end)
    else
        applyPack(item)
    end
end

-- ---------- Modern compact UI ----------
local purple = Color3.fromRGB(172, 112, 255)
local bg = Color3.fromRGB(12, 11, 21)
local panel = Color3.fromRGB(23, 21, 37)
local card = Color3.fromRGB(33, 29, 49)
local light = Color3.fromRGB(242, 239, 255)
local muted = Color3.fromRGB(165, 157, 189)

local function create(className, parent, props)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local function corner(obj, px)
    create("UICorner", obj, {CornerRadius=UDim.new(0,px)})
end
local function stroke(obj, clr, transparency)
    create("UIStroke", obj, {Color=clr or purple, Thickness=1, Transparency=transparency or 0.5})
end
local function label(parent, value, size, pos, dim, color, bold)
    return create("TextLabel", parent, {
        BackgroundTransparency=1, Text=value, TextColor3=color or light,
        Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextSize=size or 14, TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,
        Position=pos or UDim2.fromOffset(0,0),
        Size=dim or UDim2.fromOffset(100,26)
    })
end
local function button(parent, value, pos, dim, colored)
    local b = create("TextButton",parent, {
        Text=value, TextSize=13, Font=Enum.Font.GothamBold,
        TextColor3=light, BackgroundColor3=colored and Color3.fromRGB(95,52,154) or card,
        Position=pos, Size=dim, BorderSizePixel=0, AutoButtonColor=true
    })
    corner(b,9)
    return b
end

gui = create("ScreenGui", nil, {
    Name="FE_Emotes_X", ResetOnSpawn=false, IgnoreGuiInset=true, ZIndexBehavior=Enum.ZIndexBehavior.Sibling
})
local parented = pcall(function() gui.Parent = CoreGui end)
if not parented then gui.Parent = localPlayer:WaitForChild("PlayerGui") end

local main = create("Frame",gui,{
    Size=UDim2.fromOffset(590,440), Position=UDim2.fromScale(0.5,0.5),
    AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=bg, BorderSizePixel=0
})
corner(main,17)
stroke(main,purple,0.35)
local uiScale = create("UIScale",main,{Scale=1})
local function adapt()
    local cam = workspace.CurrentCamera
    if cam then
        uiScale.Scale = math.clamp(math.min(cam.ViewportSize.X/625,cam.ViewportSize.Y/475),0.55,1)
    end
end
adapt()
if workspace.CurrentCamera then connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),adapt) end

local header = create("Frame",main,{
    Size=UDim2.new(1,0,0,64),BackgroundTransparency=1
})
label(header,"FE EMOTES",21,UDim2.fromOffset(17,10),UDim2.fromOffset(165,26),light,true)
label(header,"X",21,UDim2.fromOffset(155,10),UDim2.fromOffset(36,26),purple,true)
label(header,"R15   •   Emotes + Movement Packs",11,UDim2.fromOffset(18,37),UDim2.fromOffset(310,20),muted)
local minimize = button(header,"−",UDim2.fromOffset(509,14),UDim2.fromOffset(31,31))
local close = button(header,"×",UDim2.fromOffset(546,14),UDim2.fromOffset(31,31))
local separator = create("Frame",main,{
    Position=UDim2.fromOffset(0,64),Size=UDim2.new(1,0,0,1),
    BackgroundColor3=Color3.fromRGB(63,51,86),BorderSizePixel=0
})
local nav = create("Frame",main,{
    Size=UDim2.fromOffset(126,328),Position=UDim2.fromOffset(12,80),
    BackgroundColor3=panel,BorderSizePixel=0
})
corner(nav,12)
local contentArea = create("Frame",main,{
    Size=UDim2.fromOffset(429,330),Position=UDim2.fromOffset(149,79),
    BackgroundColor3=panel,BorderSizePixel=0
})
corner(contentArea,12)

local navButtons = {}
for i, title in ipairs({"Emotes","Packs","Favorites","Settings"}) do
    local b = button(nav,title,UDim2.fromOffset(8,10+(i-1)*55),UDim2.fromOffset(110,43))
    b.TextXAlignment = Enum.TextXAlignment.Center
    navButtons[title] = b
    connect(b.MouseButton1Click,function()
        currentTab=title
        currentPage=1
        searchText=""
        if render then render() end
    end)
end
label(nav,"FE ≠ guaranteed",10,UDim2.fromOffset(10,295),UDim2.fromOffset(110,18),muted)

local search = create("TextBox", contentArea,{
    PlaceholderText="Search emotes or packs...",Text="",ClearTextOnFocus=false,
    TextColor3=light,PlaceholderColor3=muted,Font=Enum.Font.Gotham,
    TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundColor3=card,BorderSizePixel=0,
    Position=UDim2.fromOffset(12,12),Size=UDim2.fromOffset(275,35)
})
create("UIPadding",search,{PaddingLeft=UDim.new(0,12)})
corner(search,9)
local online = button(contentArea,"Online",UDim2.fromOffset(297,12),UDim2.fromOffset(120,35),true)
local scroller = create("ScrollingFrame",contentArea,{
    Position=UDim2.fromOffset(12,58),Size=UDim2.fromOffset(405,207),
    BackgroundTransparency=1,BorderSizePixel=0,
    ScrollBarThickness=3,ScrollBarImageColor3=purple,
    CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.None
})
local listLayout = create("UIListLayout",scroller,{
    Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder
})
local prev = button(contentArea,"◀ Prev",UDim2.fromOffset(12,277),UDim2.fromOffset(92,32))
local nextBtn = button(contentArea,"Next ▶",UDim2.fromOffset(326,277),UDim2.fromOffset(91,32))
counterLabel = label(contentArea,"Page 1",12,UDim2.fromOffset(112,278),UDim2.fromOffset(203,29),muted,true)
counterLabel.TextXAlignment = Enum.TextXAlignment.Center

statusLabel = label(main,"Ready | Playback/FE depends on game permissions",11,
    UDim2.fromOffset(18,413),UDim2.fromOffset(558,19),muted)
local minimized = false
connect(minimize.MouseButton1Click,function()
    minimized = not minimized
    main.Size = UDim2.fromOffset(590,minimized and 64 or 440)
    nav.Visible=not minimized
    contentArea.Visible=not minimized
    statusLabel.Visible=not minimized
    separator.Visible=not minimized
    minimize.Text=minimized and "+" or "−"
end)
local function cleanup()
    if not alive then return end
    alive = false
    stopEmote()
    -- Restore movement on close, if this character is still present.
    pcall(function()
        local c = localPlayer.Character
        local a = c and c:FindFirstChild("Animate")
        local saved = a and originals[a]
        if saved then
            local paths = findSlots(a)
            for slot,id in pairs(saved) do
                if paths[slot] then paths[slot].AnimationId=id end
            end
            reloadAnimate(a)
        end
    end)
    for _, conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    if gui then gui:Destroy() end
    if environment.FEEmotesXCleanup == cleanup then
        environment.FEEmotesXCleanup = nil
    end
end
environment.FEEmotesXCleanup = cleanup
connect(close.MouseButton1Click,cleanup)

-- Drag from the header (mouse or touch)
local dragging, dragOrigin, startPos, dragInput
connect(header.InputBegan,function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        dragging=true
        dragOrigin=input.Position
        startPos=main.Position
        dragInput=input
    end
end)
connect(UserInputService.InputChanged,function(input)
    if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta=input.Position-dragOrigin
        main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,
                                startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end
end)
connect(UserInputService.InputEnded,function(input)
    if input == dragInput then dragging=false end
end)

local function wipeRows()
    for _, child in ipairs(scroller:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
end
local function rowItem(item,i)
    local row = create("Frame",scroller,{
        BackgroundColor3=card,Size=UDim2.new(1,-6,0,45),
        BorderSizePixel=0,LayoutOrder=i
    })
    corner(row,8)
    label(row,item.name,13,UDim2.fromOffset(12,5),UDim2.fromOffset(236,22),light,true)
    label(row,item.source or item.kind,10,UDim2.fromOffset(12,26),UDim2.fromOffset(220,14),muted)
    local action = button(row,item.kind=="Pack" and "APPLY" or "PLAY",
        UDim2.fromOffset(271,8),UDim2.fromOffset(71,29),true)
    connect(action.MouseButton1Click,function()
        if item.kind=="Pack" then choosePack(item) else playEmote(item) end
    end)
    local k=keyOf(item)
    local fav=button(row,favorites[k] and "★" or "☆",
        UDim2.fromOffset(349,8),UDim2.fromOffset(33,29))
    fav.TextSize=19
    fav.TextColor3=purple
    connect(fav.MouseButton1Click,function()
        favorites[k]=not favorites[k] and true or nil
        fav.Text=favorites[k] and "★" or "☆"
    end)
end
local settingsRows = {}
local function settingButton(textText, y, fn)
    local b=button(scroller,textText,UDim2.fromOffset(0,0),
        UDim2.new(1,-6,0,44))
    b.LayoutOrder=y
    connect(b.MouseButton1Click,fn)
    return b
end
local function getCurrentItems()
    local all = {}
    local source = (currentTab=="Packs") and packs or emotes
    if currentTab=="Favorites" then
        source={}
        for _,item in ipairs(emotes) do if favorites[keyOf(item)] then table.insert(source,item) end end
        for _,item in ipairs(packs) do if favorites[keyOf(item)] then table.insert(source,item) end end
    end
    for _,item in ipairs(source) do
        if searchText=="" or string.find(string.lower(item.name),string.lower(searchText),1,true)
           or string.find(tostring(item.id),searchText,1,true) then
            table.insert(all,item)
        end
    end
    return all
end
render = function()
    if not alive then return end
    wipeRows()
    for name,b in pairs(navButtons) do
        b.BackgroundColor3=(name==currentTab) and Color3.fromRGB(95,52,154) or card
    end
    search.Visible=currentTab~="Settings"
    online.Visible=(currentTab=="Emotes" or currentTab=="Packs")
    prev.Visible=currentTab~="Settings"
    nextBtn.Visible=currentTab~="Settings"
    if search.Text ~= searchText then search.Text=searchText end
    if currentTab=="Settings" then
        counterLabel.Text="OPTIONS"
        scroller.CanvasPosition=Vector2.new(0,0)
        local stop=settingButton("Stop Current Emote",1,function() stopEmote() status("Emote stopped.") end)
        local reset=settingButton("Restore Default Animations",2,resetPack)
        local auto=settingButton("Reapply Pack on Respawn: "..(autoReapply and "ON" or "OFF"),3,function()
            autoReapply=not autoReapply
            if render then render() end
        end)
        local looping=settingButton("Loop Emotes: "..(loopEmotes and "ON" or "OFF"),4,function()
            loopEmotes=not loopEmotes
            if playingEmote then playingEmote.Looped=loopEmotes end
            if render then render() end
        end)
        local speed=settingButton("Emote Speed: "..tostring(playSpeed).."x (tap to cycle)",5,function()
            if playSpeed==1 then playSpeed=1.25 elseif playSpeed==1.25 then playSpeed=1.5
            elseif playSpeed==1.5 then playSpeed=0.75 else playSpeed=1 end
            if playingEmote then pcall(function() playingEmote:AdjustSpeed(playSpeed) end) end
            if render then render() end
        end)
        scroller.CanvasSize=UDim2.fromOffset(0,5*50)
        return
    end
    local items=getCurrentItems()
    local pages=math.max(1,math.ceil(#items/pageSize))
    currentPage=math.clamp(currentPage,1,pages)
    local first=(currentPage-1)*pageSize+1
    for index=first,math.min(#items,first+pageSize-1) do
        rowItem(items[index],index-first+1)
    end
    if #items==0 then
        local empty=label(scroller,"No matches. Try Online or another search.",13,
            UDim2.fromOffset(12,12),UDim2.new(1,-12,0,55),muted)
        empty.LayoutOrder=1
    end
    counterLabel.Text=string.format("%d / %d  •  %d items",currentPage,pages,#items)
    scroller.CanvasSize=UDim2.fromOffset(0,math.max(207,math.min(#items-first+1,pageSize)*51))
    scroller.CanvasPosition=Vector2.new(0,0)
end

connect(prev.MouseButton1Click,function()
    currentPage=math.max(1,currentPage-1)
    render()
end)
connect(nextBtn.MouseButton1Click,function()
    currentPage=currentPage+1
    render()
end)
connect(search:GetPropertyChangedSignal("Text"),function()
    searchText=search.Text
    currentPage=1
    render()
end)
connect(online.MouseButton1Click,function()
    if searchText~="" then
        catalogLoadMore(searchText)
    else
        catalogLoadMore()
    end
end)
connect(localPlayer.CharacterAdded,function(c)
    character=c
    stopEmote()
    task.spawn(function()
        local h=c:WaitForChild("Humanoid",12)
        if not alive or not h then return end
        local a=h:WaitForChild("Animator",12)
        if not alive or not a then return end
        if autoReapply and selectedPack then
            c:WaitForChild("Animate",12)
            if alive and localPlayer.Character==c then
                task.wait(0.6)
                applyPack(selectedPack,true)
                status("Reapplied " .. selectedPack.name .. " after respawn.")
            end
        end
    end)
end)
render()
if not getRig() then
    status("R15 player with server-created Animator needed.")
else
    status("Ready | Choose emote/pack. FE depends on the game.")
end
-- Initial background catalog page (safe fallback if HTTP blocked).
task.defer(function()
    if alive then
        currentTab="Emotes"
        catalogLoadMore()
    end
end)
