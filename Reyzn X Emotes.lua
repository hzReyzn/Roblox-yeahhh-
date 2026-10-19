--[[
 Reyzn X Emotes v1.3 | standalone universal R15 emote & animation browser
 Built from scratch. Inspired by standard emote catalog and Animator techniques.
 Designed for desktop + mobile. No purchase/access-control bypass.
 FE note: only animations that Roblox successfully loads on a SERVER-CREATED
 Animator of your own character may replicate. Not guaranteed in every game.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local AssetService = game:GetService("AssetService")
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
local packBundleIds={}
local favorites={}
local selectedPack=nil
local movementTracks={}
local movementAnimations={}
local currentMovement=nil
local currentHumanoid=nil
local currentAnimator=nil
local appliedCatalogHumanoid=nil
local originalCatalogDescriptions=setmetatable({},{__mode="k"})
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
-- Independent cursors prevent emote searches and movement-pack searches from clashing.
local catalogSessions = {
    Emotes={pages=nil,keyword=nil,finished=false},
    Packs={pages=nil,keyword=nil,finished=false},
}
local catalogBusy=false
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
local function addPack(name,clips,bundleId)
    name=tostring(name)
    if packIds[name] or (bundleId and packBundleIds[bundleId]) then return false end
    packIds[name]=true
    if bundleId then packBundleIds[bundleId]=true end
    local entry={
        kind="Pack", id=bundleId or name, name=name, clips=clips,
        bundleId=bundleId, origin=bundleId and "Avatar Catalog Bundle" or "R15 Pack"
    }
    table.insert(packList,entry)
    return true
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

-- Additional emote catalog IDs (curated reference metadata, not a guarantee of access).
-- Reference: https://github.com/MainScripts352/Database/blob/main/Roblox%20Emotes.json
-- Facial animation assets are excluded; they are not full-body emotes.
local referenceEmotes = {
    {"Top Rock",3570535774},
    {"Jacks",3570649048},
    {"Shy",3576717965},
    {"T",3576719440},
    {"Robot",3576721660},
    {"Fashionable",3576745472},
    {"Around Town",3576747102},
    {"Louder",3576751796},
    {"Sneaky",3576754235},
    {"Hype Dance",3696757129},
    {"Superhero Reveal",3696759798},
    {"Air Guitar",3696761354},
    {"Heisman Pose",3696763549},
    {"Cha-Cha",3696764866},
    {"Twirl",3716633898},
    {"Monkey",3716636630},
    {"Side to Side",3762641826},
    {"Greatest",3762654854},
    {"Swish",3821527813},
    {"Godlike",3823158750},
    {"Get Out",3934984583},
    {"Dizzy",3934986896},
    {"Fancy Feet",3934988903},
    {"Celebrate",3994127840},
    {"Fishing",3994129128},
    {"Bodybuilder",3994130516},
    {"Tree",4049634387},
    {"Line Dance",4049646104},
    {"Haha",4102315500},
    {"Idol",4102317848},
    {"Zombie",4212496830},
    {"Dorky Dance",4212499637},
    {"Fast Hands",4272351660},
    {"Baby Dance",4272484885},
    {"Drum Master - Royal Blood",6531538868},
    {"Dolphin Dance",5938365243},
    {"Sad",4849502101},
    {"Floss Dance",5917570207},
    {"BURBERRY LOLA ATTITUDE - NIMBUS",10147924028},
    {"Vans Ollie",18305539673},
    {"Rodeo Dance - Lil Nas XvLNX",5938397555},
    {"Samba Step Dance",14620757085},
    {"Hero Landing",5104377791},
    {"Elton John - Rock Out",11753545334},
    {"Paris Hilton Sanasa",16126526506},
    {"TWICE What Is Love",13344121112},
    {"Agree",4849487550},
    {"Rock On",5915782672},
    {"TWICE Fancy",13520623514},
    {"Baby Queen - Dramatic Bow",14353419229},
    {"Hips Poppin - Zara Larsson",6797919579},
    {"Mean Mug - Tommy Hilfiger",10214415687},
    {"You can't sit with us - Sunmi",9983549160},
    {"BLACKPINK Ice Cream",16181840356},
    {"Wake Up Call - KSI",7202900159},
    {"BLACKPINK - Lovesick Girls",16874600526},
    {"Victory - 24kGoldn",9178397781},
    {"MANIAC - Stray Kids",11309309359},
    {"Secret Handshake Dance",120642514156293},
    {"BLACKPINK - How You Like That",16874596971},
    {"BLACKPINK Pink Venom - I Bring the Pain Like",14548710952},
    {"Sturdy Dance - Ice Spice",17746270218},
    {"Boom Boom Clap - George Ezra",10370934040},
    {"Nicki Minaj Anaconda",15571539403},
    {"TWICE Strategy",106862678450011},
    {"Mean Girls Dance Break",15963348695},
    {"Floor Rock Freeze - Tommy Hilfiger",10214411646},
    {"Elton John - Cat Man",11435175895},
    {"Olivia Rodrigo Head Bop",15554010118},
    {"Cartwheel - George Ezra",10370929905},
    {"Daves Spin Move - Glass Animals",16276501655},
    {"Super Charge",10478368365},
    {"Cha Cha",6865013133},
    {"Paris Hilton - Iconic IT Grrrl",15392932768},
    {"TWICE Like Ooh-Ahh",14124050904},
    {"Olympic Dismount",18666650035},
    {"HOLIDAY Dance - Lil Nas X LNX",5938396308},
    {"TWICE Moonlight Sunrise",12715393154},
    {"Show Dem Wrists - KSI",7202898984},
    {"Cobra Arms - Tai Verdes",7942964447},
    {"SpongeBob Imaginaaation",18443268949},
    {"Sidekicks - George-Ezra",10370922566},
    {"Take Me Under - Zara Larsson",6797938823},
    {"Sol de Janeiro - Samba",16276506814},
    {"Jumping Wave",4940602656},
    {"Wanna play?",16646438742},
    {"thhsv3",14109936431},
    {"Rock Out - BebevRexha",18225077553},
    {"Head Banging",5915779725},
    {"High Wave",5915776835},
    {"Victory Dance",15506503658},
    {"BLACKPINK Don't know what to do",18855609889},
    {"Uprise - Tommy Hilfiger",10275057230},
    {"SpongeBob Dance",18443271885},
    {"Paris Hilton - Sliving For The Groove",15392927897},
    {"Arm Twist",9710992846},
    {"Chicken Dance",4849493309},
    {"Alo Yoga Pose - Triangle",12507120275},
    {"Elton John - Heart Shuffle",17748346932},
    {"Ay-Yo Dance Move NCT - 127",12804173616},
    {"Rock Guitar - Royal Blood",6532155086},
    {"Quiet Waves",7466046574},
    {"Rolling Stones Guitar Strum",18148839527},
    {"BLACKPINK As If It's Your Last",18855603653},
    {"Flowing Breeze",7466047578},
    {"BLACKPINK Kill This Love",16181843366},
    {"Jawny - Stomp",16392120020},
    {"Nicki Minaj That's That Super Bass Emote",15571536896},
    {"Beauty Touchdown",16303091119},
    {"Gashina - SUNMI",9528294735},
    {"NBA WNBA Fadeaway",18526373545},
    {"Rock n Roll",15506496093},
    {"TWICE ABCD by Nayeon",18933761755},
    {"Drummer Moves - Twenty One Pilots",7422838770},
    {"Vroom Vroom",18526410572},
    {"NBA Monster Dunk",82163305721376},
    {"TWICE Feel Special",14900153406},
    {"Block Partier",6865011755},
    {"BLACKPINK Shut Down - Part 1",14901369589},
    {"Bunny Hop",4646296016},
    {"AOK - Tai Verdes",7942960760},
    {"Panini Dance - Lil Nas X LNX",5915781665},
    {"Confused",4940592718},
    {"Olivia Rodrigo good 4 u",15554013003},
    {"TWICE Pop by Nayeon",13768975574},
    {"Frosty Flair - Tommy Hilfiger",10214406616},
    {"Disagree",4849495710},
    {"Kick It Dance Move - NCT 127",12259888240},
    {"Happy",4849499887},
    {"Fashion Klossette - Runway my way",126683684984862},
    {"Power Blast",4849497510},
    {"Bored",5230661597},
    {"The Conductor - George Ezra",10370926562},
    {"Air Guitar",15506499986},
    {"Elton John - Piano Jump",11453096488},
    {"V Pose - Tommy Hilfiger",10214418283},
    {"Sticker Dance Move - NCT 127",12259885838},
    {"Samba",6869813008},
    {"Yungblud Happier Jump",15610015346},
    {"BLACKPINK Pink Venom - Get em Get em Get em",14548709888},
    {"BLACKPINK DDU-DU DDU-DU",16553262614},
    {"Jumping Cheer",5895009708},
    {"Charli xcx - Apple Dance",18946876350},
    {"hh1",14851596394},
    {"Air Dance",4646302011},
    {"Country Line Dance - Lil Nas X (LNX)",5915780563},
    {"BURBERRY LOLA ATTITUDE - HYDRO",10147926081},
    {"BLACKPINK JENNIE You and Me",15439457146},
    {"BLACKPINK LISA Money",15679957363},
    {"KATSEYE - Touch",139021427684680},
    {"Cuco - Levitate",15698511500},
    {"Flex Walk",15506506103},
    {"Nicki Minaj Boom Boom Boom",15571538346},
    {"gdmc",13694143234},
    {"bby",14851599382},
    {"Baby Queen - Bouncy Twirl",14353423348},
    {"TWICE I GOT YOU part 1",16215060261},
    {"HUGO Lets Drive",17360720445},
    {"Rise Above - The Chainsmokers",13071993910},
    {"Swan Dance",7466048475},
    {"Cower",4940597758},
    {"newdance",14352435946},
    {"Elton John - Heart Skip",11309263077},
    {"TWICE The Feels",12874468267},
    {"Up and Down - Twenty One Pilots",7422843994},
    {"Elton John - Still Standing",11435177473},
    {"TMNT Dance",18665886405},
    {"Boxing Punch - KSI",7202896732},
    {"Skadoosh Emote - Kung Fu Panda 4",16371235025},
    {"Festive Dance",15679955281},
    {"ALTÉGO - Couldn t Care Less",5938394742},
    {"On The Outside - Twenty One Pilots",7422841700},
    {"Saturday Dance - Twenty One Pilots",7422833723},
    {"Wisp - air guitar",17370797454},
    {"Skibidi Toilet - Titan Speakerman Laser Spin",103102322875221},
    {"Sandwich Dance",4390121879},
    {"BLACKPINK JISOO Flower",15439454888},
    {"Hwaiting (í™”ì´íŒ…)",9528291779},
    {"Tommy K-Pop Mic Drop",14024722653},
    {"hh2",14851597817},
    {"Chappell Roan HOT TO GO",79312439851071},
    {"BLACKPINK Pink Venom - Straight to Ya Dome",14548711723},
    {"Tommy - Archer",13823339506},
    {"ericdoa - dance",15698510244},
    {"The Zabb",71389516735424},
    {"HIPMOTION - Amaarae",16572756230},
    {"YUNGBLUD HIGH KICK",14022978026},
    {"Cursty",4646306583},
    {"Chill Vibes - George Ezra",10370918044},
    {"BLACKPINK Boombayah Emote",16553259683},
    {"GloRilla - Tomorrow Dance",15689315657},
    {"Keeping Time",4646306072},
    {"Annyeong (ì•ˆë…•)",9528286240},
    {"Shrek Roar",18524331128},
    {"Man City Bicycle Kick",13422286833},
    {"Imagine Dragons Bones Dance",15689314578},
    {"NBA Monster Dunk",117511481049460},
    {"Man City Backflip",13694140956},
    {"Mae Stephens - Arm-Wave",16584496781},
    {"ms2",16584496763},
    {"Y",4391211308},
    {"Hyperfast 5G Dance Move",9408642191},
    {"Rock Star - Royal Blood",6533100850},
    {"th-afsc",14024725245},
    {"Olivia Rodrigo Fall Back to Float",15554016057},
    {"Dancin' Shoes - Twenty One Pilots",7405123844},
    {"Mae Stephens - Piano Hands",16553249658},
    {"Team USA Breaking Emote",18526338976},
    {"TWICE Set Me Free - Dance 2",12715397488},
    {"Tantrum",5104374556},
    {"Shuffle",4391208058},
    {"Break Dance",5915773992},
    {"Nicki Minaj Starships",15571540519},
    {"High Hands",9710994651},
    {"TWICE I GOT YOU-l part 2",16256253954},
    {"BLACKPINK Shut Down - Part 2",14901371589},
    {"BURBERRY LOLA ATTITUDE - REFLEX",10147921916},
    {"Drum Solo - Royal Blood",6532844183},
    {"Bone Chillin Bop",15123050663},
    {"Applaud",5915779043},
    {"BURBERRY LOLA ATTITUDE - GEM",10147916560},
    {"Arm Wave",5915773155},
    {"Sleep",4689362868},
    {"Lasso Turn - Tai Verdes",7942972744},
    {"Mini Kong",17000058939},
    {"Fashion Spin",130046968468383},
    {"Paris Hilton - Checking My Angles",15392937495},
    {"d4vd - Backflip",15694504637},
    {"Alo Yoga Pose - Lotus Position",12507097350},
    {"It Ain't My Fault - Zara Larsson",6797948622},
    {"Baby Queen - Air Guitar Knee Slide",14353417553},
    {"2 Baddies Dance Move - NCT 127",12259890638},
    {"Beckon",5230615437},
    {"Elton John - Elevate",11394056822},
    {"TWICE LIKEY",14900151704},
    {"Baby Queen - Strut",14353425085},
    {"Alo Yoga Pose - Warrior II",12507106431},
    {"Fashion Roadkill",73683655527605},
    {"TWICE Set Me Free - Dance 1",12715395038},
    {"Man City Scorpion Kick",13694139364},
    {"BURBERRY LOLA ATTITUDE - BLOOM",10147919199},
}
for _,e in ipairs(referenceEmotes) do
    addEmote(e[1], e[2], "Catalog Reference")
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
-- Extra public R15 movement packs; IDs are clip assets, not bundle IDs.
addPack("Oldschool",{
    run=5319900634,walk=5319909330,jump=5319917561,
    idle1=5319922112,idle2=5319922112,fall=5319914476,
    swim=5319927054,swimidle=5319927054,climb=5319931619
})
addPack("Bold",{
    run=16738337225,walk=16738340646,jump=16738336650,
    idle1=16738333868,idle2=16738334710,fall=16738333171,
    swim=16738339158,swimidle=16738339817,climb=16738332169
})
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
-- Preserve the character's appearance and restore only animation properties.
local descriptionSlots = {
    run="RunAnimation", walk="WalkAnimation", jump="JumpAnimation",
    fall="FallAnimation", climb="ClimbAnimation", idle1="IdleAnimation",
    swim="SwimAnimation",
}
local function restoreCatalogDescription()
    local hum=appliedCatalogHumanoid
    if not hum then return true end
    local original=originalCatalogDescriptions[hum]
    if not original or not hum.Parent then
        appliedCatalogHumanoid=nil
        return true
    end
    local ok,err=pcall(function()
        local current=hum:GetAppliedDescription()
        for slot,property in pairs(descriptionSlots) do
            current[property]=original[property]
        end
        hum:ApplyDescriptionAsync(current)
        current:Destroy()
    end)
    if ok then
        appliedCatalogHumanoid=nil
        originalCatalogDescriptions[hum]=nil
    else
        warn("[Reyzn X Emotes] Couldn't restore catalog animations:",err)
    end
    return ok
end
local function stopEverything()
    stopCurrentEmote()
    killMovement()
    restoreCatalogDescription()
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
-- Discover modern UGC + official R15 animation bundles without hardcoded IDs.
-- Bundle search results contain bundle IDs, NOT playable animation IDs.
-- Resolve each bundle to its animation assets only when it is selected.
-- Bundle items are avatar asset IDs, not necessarily direct Animator track IDs.
-- Keep both name and AssetType matching for legacy and newer bundle formats.
local bundleTypeToSlot = {
    RunAnimation="run", WalkAnimation="walk", JumpAnimation="jump",
    FallAnimation="fall", ClimbAnimation="climb",
    SwimAnimation="swim", IdleAnimation="idle1",
    ["53"]="run",["55"]="walk",["52"]="jump",
    ["50"]="fall",["48"]="climb",["54"]="swim",["51"]="idle1"
}
local function getAssetSlot(asset)
    local rawType=asset.AssetType or asset.assetType or asset.AssetTypeId or asset.assetTypeId
    local typeName
    if typeof(rawType)=="EnumItem" then
        typeName=rawType.Name
    elseif rawType~=nil then
        typeName=tostring(rawType)
        typeName=string.gsub(typeName,"^Enum%.AvatarAssetType%.","")
    end
    local slot=typeName and bundleTypeToSlot[typeName]
    if slot then return slot end
    if rawType~=nil and typeName~="" then return nil end
    -- Fallback only if metadata omitted, not for random non-animation assets.
    local n=string.lower(tostring(asset.Name or asset.name or ""))
    if string.find(n,"run",1,true) then return "run" end
    if string.find(n,"walk",1,true) then return "walk" end
    if string.find(n,"jump",1,true) then return "jump" end
    if string.find(n,"fall",1,true) then return "fall" end
    if string.find(n,"climb",1,true) then return "climb" end
    if string.find(n,"swim",1,true) then return "swim" end
    if string.find(n,"idle",1,true) then return "idle1" end
    return nil
end
local function resolveBundlePack(pack)
    if pack.clips then return true end
    local bundleId=tonumber(pack.bundleId)
    if not bundleId then return false end
    local a=guarded(function()
        return AvatarEditorService:GetItemDetailsAsync(bundleId,Enum.AvatarItemType.Bundle)
    end)
    local list=a and (a.BundledItems or a.Items)
    if type(list)~="table" or #list==0 then
        local b=guarded(function() return AssetService:GetBundleDetailsAsync(bundleId) end)
        list=b and (b.Items or b.BundledItems)
    end
    if type(list)~="table" or #list==0 then
        say("Roblox didn't provide bundle assets for: "..pack.name)
        return false
    end
    local clips={}
    local seen=0
    for _,asset in ipairs(list) do
        local id=tonumber(asset.Id or asset.id)
        local slot=getAssetSlot(asset)
        if id and id>0 and slot then
            if slot=="idle1" and clips.idle1 then slot="idle2" end
            if slot=="swim" and clips.swim then slot="swimidle" end
            if not clips[slot] then
                clips[slot]=id
                seen=seen+1
            end
        end
    end
    if seen<3 then
        say(string.format("Found only %d locomotion clips in %s.",seen,pack.name))
        return false
    end
    clips.idle2=clips.idle2 or clips.idle1
    clips.swimidle=clips.swimidle or clips.swim
    pack.clips=clips
    return true
end

local function loadSelectedPack(pack)
    if appliedCatalogHumanoid and not restoreCatalogDescription() then
        say("Could not restore previous catalog pack.")
        return false
    end
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
local function applyCatalogPack(pack)
    local char,hum=getRig()
    if not hum then
        say("R15 + Animator required.")
        return false
    end
    -- Avatar bundle item IDs are normally applied through a HumanoidDescription.
    -- They can fail when fed directly into Animator:LoadAnimation.
    local original=originalCatalogDescriptions[hum]
    if not original then
        original=guarded(function() return hum:GetAppliedDescription() end)
        if not original then
            say("This game doesn't allow reading your avatar description.")
            return false
        end
        originalCatalogDescriptions[hum]=original
    end
    local current=guarded(function() return hum:GetAppliedDescription() end)
    if not current then
        say("Cannot read current avatar description.")
        return false
    end
    local changed=0
    for slot,property in pairs(descriptionSlots) do
        local id=pack.clips[slot]
        if id and id>0 then
            current[property]=id
            changed=changed+1
        end
    end
    if changed<3 then
        current:Destroy()
        say("This bundle doesn't contain enough R15 movement clips.")
        return false
    end
    say("Applying "..pack.name.." via avatar animations...")
    local ok,err=pcall(function() hum:ApplyDescriptionAsync(current) end)
    current:Destroy()
    if not ok then
        warn("[Reyzn X Emotes] ApplyDescription failed:",err)
        say("Roblox blocked applying this pack. See console for details.")
        return false
    end
    killMovement()
    selectedPack=pack
    appliedCatalogHumanoid=hum
    say("Applied "..pack.name.." via avatar system. FE may vary.")
    return true
end
local function activatePack(pack)
    if not pack.bundleId then
        loadSelectedPack(pack)
        return
    end
    if not pack.clips then
        say("Reading bundle clips: "..pack.name)
        if not resolveBundlePack(pack) then
            return
        end
    end
    applyCatalogPack(pack)
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
            if running and player.Character==char then
                if selectedPack.bundleId then
                    -- Apply the catalog bundle to the newly spawned Humanoid.
                    appliedCatalogHumanoid=nil
                    activatePack(selectedPack)
                else
                    loadSelectedPack(selectedPack)
                end
            end
        end
    end)
end)

-- Marketplace results are listed even when a player does not own them.
-- Browsing does not grant animation permissions.
-- Search emotes and ANIMATION BUNDLES separately. Roblox limits catalog
-- results to 120 per API page, so an Emotes click consumes two pages = 240.
local function mergeCatalogPage(pages,tab)
    local ok,items=pcall(function() return pages:GetCurrentPage() end)
    if not ok or type(items)~="table" then return 0,0 end
    local added=0
    for _,data in ipairs(items) do
        local id=tonumber(data.Id or data.id)
        local name=data.Name or data.name
        if id and name then
            if tab=="Emotes" then
                if addEmote(name,id,"Roblox Catalog") then added=added+1 end
            elseif tab=="Packs" and (data.ItemType=="Bundle" or data.BundleType=="Animations") then
                if addPack(name,nil,id) then
                    added=added+1
                end
            end
        end
    end
    return added,#items
end

local function catalogQuery(keyword)
    local tab=currentTab
    if tab~="Emotes" and tab~="Packs" then return end
    if catalogBusy then say("Catalog request already running.");return end
    local session=catalogSessions[tab]
    keyword=keyword or ""
    if session.keyword==keyword and session.pages and session.finished then
        say("All available pages loaded for this search.")
        return
    end
    local continuing=session.pages and session.keyword==keyword and not session.finished
    catalogBusy=true
    say((tab=="Emotes" and "Loading up to 240 emotes..." or "Finding up to 120 R15 bundles..."))
    task.spawn(function()
        local pages
        local ok=true
        if continuing then
            pages=session.pages
            ok=pcall(function() pages:AdvanceToNextPageAsync() end)
        else
            local params=CatalogSearchParams.new()
            params.IncludeOffSale=true
            params.SortType=Enum.CatalogSortType.RecentlyCreated
            params.SearchKeyword=keyword
            params.Limit=120 -- hard maximum supported by Roblox
            if tab=="Emotes" then
                params.AssetTypes={Enum.AvatarAssetType.EmoteAnimation}
            else
                params.BundleTypes={Enum.BundleType.Animations}
            end
            ok,pages=pcall(function()
                return AvatarEditorService:SearchCatalogAsync(params)
            end)
            if ok and pages then
                session.pages=pages
                session.keyword=keyword
                session.finished=false
            end
        end
        local added,received=0,0
        if ok and pages then
            local pageCount=(tab=="Emotes") and 2 or 1
            for i=1,pageCount do
                local count,raw=mergeCatalogPage(pages,tab)
                added=added+count
                received=received+raw
                session.finished=pages.IsFinished
                if session.finished then break end
                if i<pageCount then
                    local advanced=pcall(function()
                        pages:AdvanceToNextPageAsync()
                    end)
                    if not advanced then
                        ok=false
                        break
                    end
                end
            end
            say(string.format("%s: %d catalog results / +%d new.%s",
                tab,received,added,ok and "" or " Next page failed."))
        else
            say("Catalog access blocked here; precached items still work.")
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
local searchCatalog=button(body,"Load 240 Emotes",299,11,140,37,true)
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
            task.spawn(function() activatePack(item) end)
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
    searchCatalog.Visible=currentTab=="Emotes" or currentTab=="Packs"
    searchCatalog.Text=currentTab=="Emotes" and "Load 240 Emotes" or "Find 120 Packs"
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
            local restored=restoreCatalogDescription()
            say(restored and "Default character movement restored." or "Restore failed; see console.")
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
    catalogQuery(searchTerm)
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
    say("Ready • FE depends on Roblox/game permissions")
end
-- Catalog browsing is on-demand to avoid infinite loading or startup stalls.
