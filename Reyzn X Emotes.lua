--[[
 Reyzn X Emotes v1.9-emote-priority-test | standalone universal R15 emote & animation browser
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
local catalogAnimationIds={}
local packRequestGeneration=0
-- Persistent animation-ID cache. Stores only catalog asset ID -> animation content ID.
-- Optional: executors without file APIs continue using the in-memory cache.
-- Reading and writing are protected so a damaged file never blocks startup.
local catalogCacheFile="ReyznXEmotes_animation_ids_v1.json"
local catalogCacheDirty=false
local catalogCacheSaving=false
local restoredCatalogIds=0
local function validCacheId(n)
    return type(n)=="number" and n>0 and n<9007199254740992 and n%1==0
end
do
    if type(readfile)=="function" then
        local ok,raw=pcall(function()
            if type(isfile)=="function" and not isfile(catalogCacheFile) then return nil end
            return readfile(catalogCacheFile)
        end)
        if ok and type(raw)=="string" and #raw<250000 then
            local parsedOk,parsed=pcall(function() return HttpService:JSONDecode(raw) end)
            if parsedOk and type(parsed)=="table"
                and parsed.version==1 and type(parsed.assets)=="table" then
                for assetKey,contentValue in pairs(parsed.assets) do
                    local assetId=tonumber(assetKey)
                    local contentId=tonumber(contentValue)
                    if validCacheId(assetId) and validCacheId(contentId)
                        and assetId~=contentId then
                        catalogAnimationIds[assetId]=contentId
                        restoredCatalogIds=restoredCatalogIds+1
                    end
                end
            end
        end
    end
end

local function queueCatalogCacheSave()
    if type(writefile)~="function" or catalogCacheSaving then return end
    catalogCacheSaving=true
    task.spawn(function()
        -- Write outside the animation-loading callback, after the batch settles.
        task.wait(0.35)
        while catalogCacheDirty do
            catalogCacheDirty=false
            local assets={}
            for assetId,contentId in pairs(catalogAnimationIds) do
                if validCacheId(assetId) and validCacheId(contentId)
                    and assetId~=contentId then
                    assets[tostring(assetId)]=contentId
                end
            end
            local ok,err=pcall(function()
                writefile(catalogCacheFile,HttpService:JSONEncode({
                    version=1,assets=assets
                }))
            end)
            if not ok then
                warn("[Reyzn X Emotes] Couldn't save animation cache: "..tostring(err))
                break
            end
            if catalogCacheDirty then task.wait(0.2) end
        end
        catalogCacheSaving=false
    end)
end

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
local function addPack(name,clips,bundleId,catalogAssets)
    name=tostring(name)
    if packIds[name] or (bundleId and packBundleIds[bundleId]) then return false end
    packIds[name]=true
    if bundleId then packBundleIds[bundleId]=true end
    local entry={
        kind="Pack", id=bundleId or name, name=name, clips=clips,
        bundleId=bundleId, catalogAssets=catalogAssets or false,
        origin=bundleId and "Avatar Catalog Bundle" or (catalogAssets and "Catalog Clips (FLY method)" or "R15 Pack")
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
-- Reference test: these are the same SSJ3 catalog package asset IDs
-- used in FLY-SSJ3; they are NOT direct animation content IDs.
-- Resolve them only when this pack is selected, just like FLY.
addPack("SSJ3 Goku DBZ (FLY)",{
    idle1=102994438121065, idle2=102994438121065,
    walk=107411587365865, run=107411587365865,
    climb=82749924026067, fall=138553022046795
},nil,true)
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
-- Eight independently draggable on-screen emote shortcuts.
-- Files are optional; when unavailable the bindings last for this session.
local fastKeyFile="ReyznXEmotes_fastkeys_v1.json"
local FAST_KEY_COUNT=8 -- backwards-compatible with saved F1-F5
local fastKeyBindings={}
local fastKeyPositions={}
local fastKeyButtons={}
local function validFastKeyId(id)
    return type(id)=="number" and id>0 and id<9007199254740992
        and id%1==0
end
do
    if type(readfile)=="function" then
        local ok,raw=pcall(function()
            if type(isfile)=="function" and not isfile(fastKeyFile) then return nil end
            return readfile(fastKeyFile)
        end)
        if ok and type(raw)=="string" and #raw<16000 then
            local decodedOk,data=pcall(function() return HttpService:JSONDecode(raw) end)
            if decodedOk and type(data)=="table" and data.version==1 then
                for i=1,FAST_KEY_COUNT do
                    local entry=type(data.slots)=="table" and data.slots[tostring(i)]
                    if type(entry)=="table" and validFastKeyId(entry.id) then
                        local fallback=entry.fallback
                        if not validFastKeyId(fallback) then fallback=nil end
                        fastKeyBindings[i]={
                            kind="Emote",
                            id=entry.id,
                            name=type(entry.name)=="string"
                                and string.sub(entry.name,1,90) or ("Emote "..tostring(entry.id)),
                            fallback=fallback
                        }
                    end
                    local position=type(data.positions)=="table"
                        and data.positions[tostring(i)]
                    if type(position)=="table" and type(position.x)=="number"
                        and type(position.y)=="number"
                        and position.x>=0 and position.x<=1
                        and position.y>=0 and position.y<=1 then
                        fastKeyPositions[i]={x=position.x,y=position.y}
                    end
                end
            end
        end
    end
end
local function saveFastKeys()
    if type(writefile)~="function" then return end
    local slots,positions={},{}
    for i=1,FAST_KEY_COUNT do
        local entry=fastKeyBindings[i]
        if entry then
            slots[tostring(i)]={
                id=entry.id,name=entry.name,fallback=entry.fallback
            }
        end
        if fastKeyPositions[i] then
            positions[tostring(i)]=fastKeyPositions[i]
        end
    end
    local ok,err=pcall(function()
        writefile(fastKeyFile,HttpService:JSONEncode({
            version=1,slots=slots,positions=positions
        }))
    end)
    if not ok then
        warn("[Reyzn X Emotes] Could not save FastKeys:",err)
    end
end
local function updateFastKeyButton(i)
    local visual=fastKeyButtons[i]
    if not visual then return end
    local entry=fastKeyBindings[i]
    visual.name.Text=entry and entry.name or "EMPTY"
    visual.button.BackgroundColor3=entry
        and Color3.fromRGB(82,43,140) or Color3.fromRGB(33,29,47)
end
local function assignFastKey(i,item)
    if type(i)~="number" or i<1 or i>FAST_KEY_COUNT or item.kind~="Emote" then return end
    fastKeyBindings[i]={kind="Emote",id=item.id,name=item.name,fallback=item.fallback}
    updateFastKeyButton(i)
    saveFastKeys()
    say("FastKey "..i.." assigned: "..item.name)
end
local function clearFastKey(i)
    fastKeyBindings[i]=nil
    updateFastKeyButton(i)
    saveFastKeys()
end

local function itemKey(it) return it.kind..":"..tostring(it.id) end

-- Emote / movement-pack coexistence.
-- Do not destroy or unselect a movement pack while an emote is playing.
-- Official Roblox emotes can use the server-created Animator, so capture
-- their Action tracks and restore movement when they stop.
local emoteGeneration=0
local emoteMovementPaused=false
local emoteAnimator=nil
local emotePlayedConnection=nil
local emoteStoppedConnection=nil

local function disconnectEmoteListeners()
    if emotePlayedConnection then
        emotePlayedConnection:Disconnect()
        emotePlayedConnection=nil
    end
    if emoteStoppedConnection then
        emoteStoppedConnection:Disconnect()
        emoteStoppedConnection=nil
    end
end

local function finishEmote(token)
    if token~=emoteGeneration then return end
    disconnectEmoteListeners()
    emoteMovementPaused=false
    emoteAnimator=nil
    activeEmoteRequested=false
    -- The next movement heartbeat chooses the correct locomotion pose.
    -- Resetting currentMovement also forces a replay if the last pose
    -- had been stopped to give the emote priority.
    currentMovement=nil
    if activeEmoteAnimation then
        if activeEmoteTrack then
            pcall(function() activeEmoteTrack:Destroy() end)
        end
        pcall(function() activeEmoteAnimation:Destroy() end)
        activeEmoteAnimation=nil
    end
    activeEmoteTrack=nil
end

local function stopCurrentEmote()
    emoteGeneration=emoteGeneration+1
    disconnectEmoteListeners()
    emoteMovementPaused=false
    emoteAnimator=nil
    if activeEmoteTrack then
        pcall(function() activeEmoteTrack:Stop(0.15) end)
        activeEmoteTrack=nil
    end
    if activeEmoteAnimation then
        pcall(function() activeEmoteAnimation:Destroy() end)
        activeEmoteAnimation=nil
    end
    activeEmoteRequested=false
    currentMovement=nil
end

local function beginEmotePriority(animator)
    local token=emoteGeneration
    emoteMovementPaused=true
    emoteAnimator=animator
    -- Stop only the custom locomotion tracks. Keep them loaded in memory,
    -- retain selectedPack, and let updateMovement resume them afterward.
    for _,track in pairs(movementTracks) do
        pcall(function()
            if track.IsPlaying then track:Stop(0.12) end
        end)
    end
    currentMovement=nil

    local alreadyPlaying={}
    local existing=guarded(function() return animator:GetPlayingAnimationTracks() end)
    if type(existing)=="table" then
        for _,track in ipairs(existing) do alreadyPlaying[track]=true end
    end

    local function captureTrack(track,explicit)
        if not running or token~=emoteGeneration
            or emoteAnimator~=animator or activeEmoteTrack then return end
        if alreadyPlaying[track] and not explicit then return end
        for _,movementTrack in pairs(movementTracks) do
            if movementTrack==track then return end
        end
        -- Ignore ordinary idle/walk/run tracks fired by Animate.
        local priority=guarded(function() return track.Priority end)
        if not explicit and (not priority
            or priority.Value<Enum.AnimationPriority.Action.Value) then return end
        activeEmoteTrack=track
        if emotePlayedConnection then
            emotePlayedConnection:Disconnect()
            emotePlayedConnection=nil
        end
        emoteStoppedConnection=track.Stopped:Connect(function()
            -- Small fade buffer before restoring locomotion.
            task.delay(0.18,function()
                if running and token==emoteGeneration then finishEmote(token) end
            end)
        end)
    end
    emotePlayedConnection=animator.AnimationPlayed:Connect(captureTrack)

    return token,captureTrack
end

-- The official API can yield while Roblox fetches the emote. Start its
-- no-track timeout AFTER the API returns, so slow network requests never
-- reactivate locomotion before their emote has begun.
local function watchOfficialEmote(token,animator,captureTrack)
    task.delay(1.25,function()
        if not running or token~=emoteGeneration
            or not emoteMovementPaused or activeEmoteTrack then return end
        local found=guarded(function() return animator:GetPlayingAnimationTracks() end)
        if type(found)=="table" then
            for _,track in ipairs(found) do
                captureTrack(track)
                if activeEmoteTrack then break end
            end
        end
        -- Do not permanently suppress the selected movement pack if Roblox
        -- did not expose a playable emote track.
        if not activeEmoteTrack then finishEmote(token) end
    end)
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
    packRequestGeneration=packRequestGeneration+1
    stopCurrentEmote()
    killMovement()
    selectedPack=nil
end

local function playEmote(item)
    local char,hum,animator=getRig()
    if not hum then say("R15 + server Animator required.");return end
    stopCurrentEmote()
    local token,captureTrack=beginEmotePriority(animator)
    -- Use the original official Roblox playback methods to keep FE behavior.
    -- The controller only pauses local movement tracks until the emote stops.
    if not item.fallback then
        local description=hum:FindFirstChildOfClass("HumanoidDescription")
        local alias="RZX_"..tostring(item.id)
        if description then
            pcall(function() description:AddEmote(alias,item.id) end)
            local ok,played=pcall(function() return hum:PlayEmoteAsync(alias) end)
            if token~=emoteGeneration then return end
            if ok and played then
                activeEmoteRequested=true
                watchOfficialEmote(token,animator,captureTrack)
                say("Emote requested: "..item.name.." | movement resumes afterward")
                return
            end
        end
        -- Optional Roblox-owned playback entry point; unchanged.
        local ok,trackOrResult=pcall(function()
            return hum:PlayEmoteAndGetAnimTrackById(item.id)
        end)
        if token~=emoteGeneration then return end
        if ok and trackOrResult then
            if typeof(trackOrResult)=="Instance" and trackOrResult:IsA("AnimationTrack") then
                captureTrack(trackOrResult,true)
            end
            activeEmoteRequested=true
            watchOfficialEmote(token,animator,captureTrack)
            say("Emote invoked: "..item.name.." | movement resumes afterward")
            return
        end
    end
    -- Accessible sequence fallback, without changing asset permissions.
    local animation=Instance.new("Animation")
    animation.AnimationId="rbxassetid://"..tostring(item.fallback or item.id)
    local ok,track=pcall(function() return animator:LoadAnimation(animation) end)
    if token~=emoteGeneration then
        if ok and track then pcall(function() track:Destroy() end) end
        animation:Destroy()
        return
    end
    if not ok or not track then
        animation:Destroy()
        finishEmote(token)
        say("Unavailable or restricted: "..item.name)
        return
    end
    track.Priority=Enum.AnimationPriority.Action4
    track.Looped=loopEmotes
    activeEmoteAnimation=animation
    if not pcall(function() track:Play(0.15,1,emoteSpeed) end) then
        pcall(function() track:Destroy() end)
        animation:Destroy()
        activeEmoteAnimation=nil
        finishEmote(token)
        say("Failed to play: "..item.name)
        return
    end
    captureTrack(track)
    activeEmoteRequested=true
    say("Playing "..item.name.." | movement resumes afterward")
    task.delay(2,function()
        if running and token==emoteGeneration and activeEmoteTrack==track then
            local length=guarded(function() return track.Length end)
            if not length or length<=0 then
                say("Animation may be unavailable / not loaded in this game.")
            end
        end
    end)
    -- A truly unavailable clip may never emit Stopped. Do not keep
    -- suppressing the movement pack forever in that case.
    task.delay(7,function()
        if running and token==emoteGeneration and activeEmoteTrack==track then
            local length=guarded(function() return track.Length end)
            if not length or length<=0 then
                pcall(function() track:Stop(0.15) end)
                finishEmote(token)
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
    if rawType~=nil and typeName~="" and typeName~="Animation" and typeName~="24" and typeName~="Asset" then return nil end
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
    local clips={}
    local seen=0
    local function collect(list)
        if type(list)~="table" then return end
        for _,asset in ipairs(list) do
            local id=tonumber(asset.Id or asset.id)
            local slot=getAssetSlot(asset)
            if id and id>0 and slot then
                if slot=="idle1" and clips.idle1 then
                    -- An extra idle can use the same asset type.
                    if clips.idle1~=id then slot="idle2" else slot=nil end
                elseif slot=="swim" and clips.swim then
                    if clips.swim~=id then slot="swimidle" else slot=nil end
                end
                if slot and not clips[slot] then
                    clips[slot]=id
                    seen=seen+1
                end
            end
        end
    end

    local a=guarded(function()
        return AvatarEditorService:GetItemDetailsAsync(bundleId,Enum.AvatarItemType.Bundle)
    end)
    if a then collect(a.BundledItems or a.Items) end

    -- Retry with the dedicated bundle-details endpoint when the catalog
    -- metadata is missing or incomplete. Do not treat a bundle ID as a clip.
    if seen<3 then
        local b=guarded(function() return AssetService:GetBundleDetailsAsync(bundleId) end)
        if b then collect(b.Items or b.BundledItems) end
    end
    if seen<3 then
        say(string.format("Only %d R15 clips found in %s (unsupported bundle).",seen,pack.name))
        return false
    end
    clips.idle2=clips.idle2 or clips.idle1
    clips.swimidle=clips.swimidle or clips.swim
    pack.clips=clips
    return true
end

-- Same package-to-content resolution used in the user's FLY-SSJ3.
-- An Avatar Catalog package asset can contain an Animation instance
-- pointing to a DIFFERENT animation content ID. The package ID is not
-- necessarily accepted by Animator:LoadAnimation.
local function resolveCatalogAnimation(assetId)
    assetId=tonumber(assetId)
    if not assetId or assetId<1 then return nil end
    if catalogAnimationIds[assetId] then return catalogAnimationIds[assetId] end
    local ok,objects=pcall(function()
        return game:GetObjects("rbxassetid://"..tostring(assetId))
    end)
    if not ok or type(objects)~="table" then return nil end
    local resolvedId
    local function inspect(object)
        if resolvedId or not object:IsA("Animation") then return end
        local animationId=tostring(object.AnimationId or "")
        local contentId=animationId:match("^rbxassetid://(%d+)$")
            or animationId:match("[?&]id=(%d+)")
            or animationId:match("^(%d+)$")
        local number=tonumber(contentId)
        if number and number>0 and number~=assetId then
            resolvedId=number
        end
    end
    for _,object in ipairs(objects) do
        pcall(function()
            inspect(object)
            for _,child in ipairs(object:GetDescendants()) do inspect(child) end
        end)
        pcall(function() object:Destroy() end)
    end
    if resolvedId then
        catalogAnimationIds[assetId]=resolvedId
        catalogCacheDirty=true
    end
    return resolvedId
end

local function resolveCatalogMovementClips(pack,request)
    if pack.playableClips then return pack.playableClips end
    local original=pack.clips
    if type(original)~="table" then return nil end
    local resolved,attempted,successful,total={},{},0,0
    for _,slot in ipairs({"idle1","idle2","walk","run","jump","fall","climb","swim","swimidle"}) do
        local assetId=original[slot]
        if assetId then
            total=total+1
            say("Resolving "..pack.name..": "..total.." catalog clips checked...")
            local clipId=attempted[assetId]
            if clipId==nil then
                -- Allow the HUD and game to draw a frame before another
                -- synchronous GetObjects request. This reduces continuous
                -- stalls on mobile without changing the working FLY method.
                if not catalogAnimationIds[assetId] then
                    task.wait(0.05)
                    if not running or request~=packRequestGeneration then return nil end
                end
                clipId=resolveCatalogAnimation(assetId) or false
                attempted[assetId]=clipId
            end
            if not running or request~=packRequestGeneration then return nil end
            if clipId then
                resolved[slot]=clipId
                successful=successful+1
            end
        end
    end
    if successful==0 then
        warn("[Reyzn X Emotes] No actual AnimationIds extracted from "..pack.name..
            ". GetObjects may be blocked, or package assets are not loadable.")
        say("No playable clip IDs extracted: "..pack.name.." (FLY method unavailable).")
        return nil
    end
    resolved.idle2=resolved.idle2 or resolved.idle1
    resolved.swimidle=resolved.swimidle or resolved.swim
    pack.playableClips=resolved
    pack.resolvedCount=successful
    pack.originalClipCount=total
    if catalogCacheDirty then queueCatalogCacheSave() end
    return resolved
end

local function loadSelectedPack(pack,clips)
    clips=clips or pack.clips
    if type(clips) ~= "table" then
        say("This pack has no playable animation IDs.")
        return false
    end
    killMovement()
    local _,hum,animator=getRig()
    if not hum then say("R15 + server Animator required.");return false end
    currentHumanoid=hum
    currentAnimator=animator
    for key,id in pairs(clips) do
        local animation=Instance.new("Animation")
        animation.Name="RZX_"..key
        animation.AnimationId="rbxassetid://"..tostring(id)
        table.insert(movementAnimations,animation)
        local ok,t=pcall(function() return animator:LoadAnimation(animation) end)
        if ok and t then
            -- FLY-SSJ3 uses Action priority for its catalog tracks.
            t.Priority=(pack.bundleId or pack.catalogAssets)
                and Enum.AnimationPriority.Action
                or ((key=="idle1" or key=="idle2")
                    and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement)
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
    if pack.bundleId or pack.catalogAssets then
        say(string.format("Resolved %d/%d package slots • %s",
            pack.resolvedCount or 0,pack.originalClipCount or 0,pack.name))
    else
        say("Pack selected: "..pack.name.." | Preview in movement")
    end
    -- Loading an AnimationTrack does not guarantee that Roblox can download
    -- the clip. Check Length after a short delay and report blocked assets.
    if pack.bundleId or pack.catalogAssets then
        task.delay(8,function()
            if not running or selectedPack~=pack or currentAnimator~=animator then return end
            local playable,total=0,0
            for _,t in pairs(movementTracks) do
                total=total+1
                local length=guarded(function() return t.Length end)
                if length and length>0 then playable=playable+1 end
            end
            if playable==0 then
                warn("[Reyzn X Emotes] Catalog clips resolved, but no tracks report usable content. Roblox asset permissions may still block them.")
                say("No tracks ready: "..pack.name.." (check Roblox asset permissions).")
            elseif playable<total then
                say(string.format("%s: %d/%d tracks ready • try moving to load others.",pack.name,playable,total))
            else
                say("Movement pack ready: "..pack.name.." | FE depends on game.")
            end
        end)
    end
    return true
end
-- Resolve catalog package IDs into inner AnimationIds before loading.
-- Built-in classic packs already contain direct sequence IDs and are unchanged.
local function activatePack(pack)
    packRequestGeneration=packRequestGeneration+1
    local request=packRequestGeneration
    local char,hum,animator=getRig()
    if not hum then say("R15 + server Animator required.");return end
    if pack.bundleId and not pack.clips then
        say("Reading bundle clips: "..pack.name)
        if not resolveBundlePack(pack) then return end
    end
    if not running or request~=packRequestGeneration then return end
    local clips=pack.clips
    if pack.bundleId or pack.catalogAssets then
        say("Extracting real AnimationIds from "..pack.name.."...")
        clips=resolveCatalogMovementClips(pack,request)
        if not clips then return end
    end
    local liveChar,liveHum,liveAnimator=getRig()
    if not running or request~=packRequestGeneration
        or liveChar~=char or liveHum~=hum or liveAnimator~=animator then return end
    loadSelectedPack(pack,clips)
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
    -- A playing emote has exclusive control of movement animation layers.
    -- As soon as it stops, selectedPack and its loaded tracks are unchanged.
    if emoteMovementPaused then return end
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
        if pose=="walk" and movementTracks.run then pose="run"
        elseif pose=="run" and movementTracks.walk then pose="walk"
        elseif pose=="swimidle" and movementTracks.swim then pose="swim"
        else pose=movementTracks.idle1 and "idle1" or nil end
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
                activatePack(selectedPack)
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
    base=Color3.fromRGB(10,10,15), panel=Color3.fromRGB(18,17,25),
    row=Color3.fromRGB(27,26,36), purple=Color3.fromRGB(180,140,245),
    white=Color3.fromRGB(235,237,247), muted=Color3.fromRGB(184,181,201)
}
local Design
local function new(class,parent,props)
    local obj=Instance.new(class)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent
    if Design then Design:register(obj,parent) end
    return obj
end
local function round(obj,r) new("UICorner",obj,{CornerRadius=UDim.new(0,r)}) end
local function outline(obj,color,trans)
    new("UIStroke",obj,{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=color or palette.purple,Transparency=trans or 0.55,Thickness=1})
end
-- Presentation only. No catalog, animation, favorite or FastKey controller is
-- called here. Decorations never capture input; the existing controls own it.
Design=(function()
    local TweenService=game:GetService("TweenService")
    local C={obsidian=Color3.fromRGB(10,10,15),graphite=Color3.fromRGB(27,26,36),
        chrome=Color3.fromRGB(235,237,247),silver=Color3.fromRGB(184,181,201),
        violet=Color3.fromRGB(157,103,239),cyan=Color3.fromRGB(141,220,255),
        pink=Color3.fromRGB(212,152,219),deep=Color3.fromRGB(60,31,99)}
    local self={alive=true,scopes=setmetatable({},{__mode="k"}),
        alphas=setmetatable({},{__mode="k"}),buttons={},tweens={},links={},
        factors={window=0,launcher=0},fireImages={},backgroundImages={},fires={}}
    local function fx(class,parent,props)
        local o=Instance.new(class)
        for k,v in pairs(props or {})do o[k]=v end
        if o:IsA("GuiObject")then o.Active=false;o.BorderSizePixel=0;o.AutoLocalize=false end
        o.Parent=parent;return o
    end
    local function gradient(o,colors,rotation)
        local points={}
        for i,c in ipairs(colors)do points[i]=ColorSequenceKeypoint.new((i-1)/(#colors-1),c)end
        return new("UIGradient",o,{Color=ColorSequence.new(points),Rotation=rotation or 25})
    end
    local function stroke(o,opacity,width)
        return new("UIStroke",o,{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,
            Color=Color3.new(1,1,1),Transparency=opacity,Thickness=width or 1})
    end
    local function watch(signal,fn)
        local c=signal:Connect(fn);self.links[#self.links+1]=c;return c
    end
    function self:tween(o,duration,props)
        local old=self.tweens[o]
        if old then old:Cancel();self.tweens[o]=nil end
        if not self.alive then return end
        local t=TweenService:Create(o,TweenInfo.new(duration,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),props)
        self.tweens[o]=t
        t.Completed:Once(function()if self.tweens[o]==t then self.tweens[o]=nil end end)
        t:Play()
    end
    function self:register(o,parent)
        local scope=self.scopes[parent]
        if not scope then return end
        self.scopes[o]=scope
        local values={}
        if o:IsA("GuiObject")then
            values.BackgroundTransparency=o.BackgroundTransparency
            if o:IsA("TextLabel")or o:IsA("TextButton")or o:IsA("TextBox")then values.TextTransparency=o.TextTransparency end
            if o:IsA("ImageLabel")or o:IsA("ImageButton")then values.ImageTransparency=o.ImageTransparency end
            if o:IsA("ScrollingFrame")then values.ScrollBarImageTransparency=o.ScrollBarImageTransparency end
        elseif o:IsA("UIStroke")then values.Transparency=o.Transparency end
        if next(values)then
            self.alphas[o]=values
            for property,value in pairs(values)do o[property]=1-(1-value)*self.factors[scope] end
        end
    end
    function self:base(o,property,value)
        local values=self.alphas[o]
        if values then values[property]=value end
        o[property]=1-(1-value)*(self.factors[self.scopes[o]] or 1)
    end
    function self:fade(scope,value)
        self.factors[scope]=value
        for o,values in pairs(self.alphas)do
            if self.scopes[o]==scope and o.Parent then
                for property,base in pairs(values)do o[property]=1-(1-base)*value end
            end
        end
    end
    function self:metal(o,subtle)
        o.BackgroundColor3=Color3.new(1,1,1)
        gradient(o,subtle and {Color3.fromRGB(24,23,32),C.obsidian,Color3.fromRGB(29,27,39)}
            or {Color3.fromRGB(36,33,47),C.obsidian,Color3.fromRGB(46,43,59)},28)
        local edge=stroke(o,subtle and .78 or .56)
        gradient(edge,{C.deep,C.silver,C.violet,C.cyan,C.deep},22)
        return edge
    end
    function self:button(b,primary)
        if self.buttons[b]then return end
        b.AutoButtonColor=false
        self:base(b,"BackgroundTransparency",1);self:base(b,"TextTransparency",1)
        local face=new("Frame",b,{Name="MetalFace",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),
            Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,ZIndex=1,Active=false})
        round(face,9)
        local colors=primary and {Color3.fromRGB(47,30,69),Color3.fromRGB(15,18,27),Color3.fromRGB(42,51,67)}
            or {Color3.fromRGB(36,33,47),C.obsidian,Color3.fromRGB(37,34,48)}
        local metal=gradient(face,colors,27)
        local edge=stroke(face,primary and .35 or .64)
        local edgeLight=gradient(edge,{C.deep,C.violet,C.chrome,C.cyan,C.deep},24)
        local press=new("UIScale",face,{Scale=1})
        -- A separate label stays chrome-white; dark UIGradients affect only
        -- the surface, never the text. Existing .Text callbacks are mirrored.
        local caption=new("TextLabel",face,{Name="MetalCaption",Size=UDim2.fromScale(1,1),
            BackgroundTransparency=1,Text=b.Text,TextColor3=b.TextColor3,TextSize=b.TextSize,
            FontFace=Font.new("rbxassetid://12187375422",Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),
            TextWrapped=b.TextWrapped,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=4,Active=false})
        local flash=new("Frame",face,{Name="PressLight",Size=UDim2.fromScale(1,1),BackgroundColor3=C.cyan,
            BackgroundTransparency=1,BorderSizePixel=0,ZIndex=2,Active=false})
        round(flash,9)
        local flashG=gradient(flash,{C.violet,C.cyan,C.chrome},25)
        flashG.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.55,.35),NumberSequenceKeypoint.new(1,1)})
        local blend=new("NumberValue",b,{Value=0})
        local record={face=face,caption=caption,metal=metal,edge=edge,edgeLight=edgeLight,scale=press,blend=blend,links={},primary=primary}
        self.buttons[b]=record
        local function bind(signal,fn)record.links[#record.links+1]=signal:Connect(fn)end
        for _,property in ipairs({"Text","TextColor3","TextSize","TextWrapped"})do
            bind(b:GetPropertyChangedSignal(property),function()caption[property]=b[property]end)
        end
        bind(blend.Changed,function()self:base(flash,"BackgroundTransparency",1-blend.Value*.24)end)
        bind(b.InputBegan,function(input)
            if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
            record.pointer=input;self:tween(press,.08,{Scale=.975})
            local old=self.tweens[blend];if old then old:Cancel();self.tweens[blend]=nil end
            blend.Value=1;self:tween(blend,.4,{Value=0})
        end)
        bind(b.MouseEnter,function()self:base(edge,"Transparency",.28)end)
        bind(b.MouseLeave,function()self:base(edge,"Transparency",record.selected and .25 or (primary and .35 or .64))end)
        bind(b.Destroying,function()
            for _,c in ipairs(record.links)do c:Disconnect()end
            for _,o in ipairs({press,blend})do if self.tweens[o]then self.tweens[o]:Cancel();self.tweens[o]=nil end end
            self.buttons[b]=nil
        end)
    end
    function self:select(b,selected)
        local r=self.buttons[b];if not r then return end
        r.selected=selected
        if not r.indicator then
            r.indicator=new("Frame",r.face,{Name="SelectionLight",Position=UDim2.new(0,0,.5,-10),
                Size=UDim2.fromOffset(2,20),BackgroundColor3=C.cyan,BorderSizePixel=0,Active=false,ZIndex=4})
            round(r.indicator,2)
        end
        r.indicator.Visible=selected
        r.metal.Color=selected and ColorSequence.new({
            ColorSequenceKeypoint.new(0,Color3.fromRGB(48,30,70)),ColorSequenceKeypoint.new(.55,Color3.fromRGB(18,17,28)),
            ColorSequenceKeypoint.new(1,Color3.fromRGB(42,56,71))}) or ColorSequence.new({
            ColorSequenceKeypoint.new(0,C.graphite),ColorSequenceKeypoint.new(.55,C.obsidian),ColorSequenceKeypoint.new(1,C.graphite)})
        b.TextColor3=selected and C.chrome or C.silver
        self:base(r.edge,"Transparency",selected and .25 or .64)
    end
    function self:windowControl(b,isClose)
        local r=self.buttons[b]
        r.caption.Visible=false
        for i=1,(isClose and 2 or 1)do
            local mark=new("Frame",r.face,{Name="ControlMark",AnchorPoint=Vector2.new(.5,.5),
                Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(isClose and 13 or 12,1.5),
                BackgroundColor3=C.chrome,BorderSizePixel=0,ZIndex=4,Active=false,
                Rotation=isClose and (i==1 and 45 or -45)or 0})
            round(mark,1)
        end
    end
    function self:shortcuts(keys)
        -- Existing TextButton colors still carry the binding state. Only this
        -- noninteractive backdrop mirrors them; gesture/binding code is untouched.
        for _,key in ipairs(keys)do
            local b=key.button
            local face=fx("Frame",b,{Name="FastKeyMetal",Size=UDim2.fromScale(1,1),
                BackgroundColor3=Color3.new(1,1,1),ZIndex=0})
            round(face,9)
            local wash=gradient(face,{C.graphite,C.obsidian,C.graphite},28)
            local edge=stroke(face,.58)
            gradient(edge,{C.deep,C.violet,C.silver,C.cyan},30)
            local function sync()
                wash.Color=ColorSequence.new({
                    ColorSequenceKeypoint.new(0,b.BackgroundColor3:Lerp(C.graphite,.5)),
                    ColorSequenceKeypoint.new(.5,C.obsidian),
                    ColorSequenceKeypoint.new(1,b.BackgroundColor3:Lerp(C.graphite,.6))})
            end
            sync();watch(b:GetPropertyChangedSignal("BackgroundColor3"),sync)
            key.number.FontFace=Font.new("rbxassetid://12187375422",Enum.FontWeight.Bold,Enum.FontStyle.Normal)
            key.number.TextSize=16
        end
    end
    function self:background(parent)
        local img=new("ImageLabel",parent,{Name="AmethystArtwork",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
            Image="",ImageTransparency=.83,ScaleType=Enum.ScaleType.Crop,ZIndex=1,Active=false})
        round(img,13);self.backgroundImages[#self.backgroundImages+1]=img;return img
    end
    local function noise(seed)return (math.sin(seed*12.9898+78.233)*43758.5453)%1 end
    function self:fire(parent,name,width,height,perimeter)
        local host=fx("Frame",parent,{Name=name,Size=UDim2.fromOffset(width,height),BackgroundTransparency=1,ClipsDescendants=false,ZIndex=0})
        local f={host=host,roots={},wisps={},embers={},perimeter=perimeter}
        local points={}
        if perimeter then
            for side,count in ipairs(perimeter)do for i=1,count do points[#points+1]={side=side,fraction=(i-.5)/count}end end
        else for i=1,8 do points[i]={fraction=(i-.5)/8}end end
        local function image(parent,core)
            local img=fx("ImageLabel",parent,{Image="",Size=UDim2.fromOffset(1,1),BackgroundTransparency=1,
                ImageTransparency=1,AnchorPoint=Vector2.new(.5,1),ScaleType=Enum.ScaleType.Stretch})
            if not core then img.ImageRectOffset=Vector2.new(110,0);img.ImageRectSize=Vector2.new(1040,1254)end
            local wash=gradient(img,core and {Color3.fromRGB(151,62,246),C.cyan,C.chrome}
                or {Color3.fromRGB(205,63,161),Color3.fromRGB(151,62,246),Color3.fromRGB(213,181,255),C.cyan},90)
            wash.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(.2,.02),
                NumberSequenceKeypoint.new(.78,0),NumberSequenceKeypoint.new(1,1)})
            self.fireImages[#self.fireImages+1]=img;return img
        end
        for i,p in ipairs(points)do
            local seed=i*1.713+(perimeter and #name*.23 or 0)
            local node=fx("Frame",host,{Size=UDim2.fromOffset(1,1),BackgroundTransparency=1})
            f.roots[i]={node=node,layers={image(node,false),image(node,false)},core=image(node,true),
                seed=seed,fraction=p.fraction,side=p.side,height=.85+noise(seed)*.29,rate=.61+noise(seed)*.18}
        end
        for i=1,6 do
            f.wisps[i]={node=image(host,true),seed=i*1.391,rate=.53+noise(i)*.17}
            local ember=fx("Frame",host,{Size=UDim2.fromOffset(1.3,3.5),BackgroundTransparency=1,
                BackgroundColor3=i%2==0 and C.cyan or C.pink,AnchorPoint=Vector2.new(.5,.5)})
            fx("UICorner",ember,{CornerRadius=UDim.new(0,2)})
            f.embers[i]={node=ember,seed=i*.713,rate=.38+noise(i+6)*.22}
        end
        self.fires[#self.fires+1]=f;return f
    end
    local function updateFire(f,time,opacity)
        local w,h=f.host.Size.X.Offset,f.host.Size.Y.Offset
        for _,p in ipairs(f.roots)do
            local x,y=-3+(w+6)*p.fraction,h+2
            local height,width=(h+40)*p.height,47
            if f.perimeter then
                if p.side==1 or p.side==3 then
                    x=10+(w-20)*p.fraction;y=p.side==1 and 4 or h+13
                    width=math.clamp(w/f.perimeter[p.side]*1.4,18,66);height=(p.side==1 and 64 or 55)*p.height
                else x=p.side==2 and w+3 or -3;y=16+(h-24)*p.fraction;width=38;height=math.clamp(h/f.perimeter[p.side]*1.45,66,92)*p.height end
            end
            p.node.Position=UDim2.fromOffset(x,y)
            for layer,img in ipairs(p.layers)do
                local age=(time*p.rate+p.seed+(layer-1)*.5)%1
                local bend=math.sin(time*2.5+p.seed)*2+math.sin(time*4.3-p.seed)*.7
                img.Position=UDim2.fromOffset(bend+math.sin(age*math.pi)*(layer==1 and -3 or 3),-age*5)
                img.Size=UDim2.fromOffset(width*(1.1-age*.2),height*(.73+age*.53));img.Rotation=bend*(layer==1 and -1.5 or 2)
                img.ImageTransparency=1-math.sin(age*math.pi)^2*.87*opacity
            end
            p.core.Position=UDim2.fromOffset(math.sin(time*3-p.seed)*1.5,0)
            p.core.Size=UDim2.fromOffset(width*.63,height*.76);p.core.Rotation=math.sin(time*2.6+p.seed)*3
            p.core.ImageTransparency=1-(.36+.12*math.sin(time*3.1+p.seed)^2)*opacity
        end
        for _,p in ipairs(f.wisps)do
            local age=(time*p.rate+p.seed)%1
            local x=-5+(w+10)*noise(p.seed)+math.sin(age*4+p.seed)*5*age
            local y=h+8-age*(h+65)
            if f.perimeter then
                local side=math.floor(p.seed*10)%3
                if side==0 then y=3-age*60 else x=side==1 and -8 or w+8;y=h*noise(p.seed+2)-age*62 end
            end
            p.node.Position=UDim2.fromOffset(x,y);p.node.Size=UDim2.fromOffset(22*(1-age*.38),42+age*13)
            p.node.Rotation=math.sin(time*2+p.seed)*7;p.node.ImageTransparency=1-math.sin(age*math.pi)^2*.66*opacity
        end
        for _,p in ipairs(f.embers)do
            local age=(time*p.rate+p.seed)%1
            local x=-8+(w+16)*noise(p.seed+4)+math.sin(age*5+p.seed)*4
            local y=h+6-age*(h+54)
            if f.perimeter then
                local side=math.floor(p.seed*10)%3
                if side==0 then y=-8-age*48 else x=(side==1 and -11 or w+11)+math.sin(age*5+p.seed)*3;y=h*noise(p.seed+5)-age*64 end
            end
            p.node.Position=UDim2.fromOffset(x,y);p.node.BackgroundTransparency=1-math.sin(age*math.pi)^2*.62*opacity
        end
    end
    function self:attach(root,gui)
        self.root=root;self.gui=gui;self.scopes[root]="window"
        root.BackgroundTransparency=1;root.ClipsDescendants=false
        -- Opaque surface masks inward flames; they stay outside the silhouette.
        self.surface=new("Frame",root,{Name="ObsidianSurface",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,ZIndex=1,Active=false})
        round(self.surface,15);self:metal(self.surface,true);self:background(self.surface)
        for i=1,3 do
            local glow=new("Frame",root,{Name="AmethystHalo",Position=UDim2.fromOffset(-i*2,-i*2),
                Size=UDim2.new(1,i*4,1,i*4),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=0,Active=false})
            round(glow,15+i*2);local edge=stroke(glow,.86+i*.025,2)
            gradient(edge,{C.deep,C.violet,C.cyan,C.pink,C.deep},24)
        end
        self.windowFire=self:fire(root,"WindowFire",628,459,{10,5,8,5})
        self.opacity=new("NumberValue",gui,{Name="WindowVisualOpacity",Value=0})
        self.launcherOpacity=new("NumberValue",gui,{Name="LauncherVisualOpacity",Value=0})
        watch(self.opacity.Changed,function()
            self:fade("window",self.opacity.Value)
            if self.opacity.Value==0 and self.minimized then root.Visible=false end
        end)
        watch(self.launcherOpacity.Changed,function()
            self:fade("launcher",self.launcherOpacity.Value)
            if self.launcherOpacity.Value==0 and not self.minimized and self.launcher then self.launcher.Visible=false end
        end)
        watch(UserInputService.InputEnded,function(input)
            for _,r in pairs(self.buttons)do
                if r.pointer==input or (r.pointer and r.pointer.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1)then
                    r.pointer=nil;self:tween(r.scale,.22,{Scale=1})
                end
            end
        end)
        watch(UserInputService.WindowFocusReleased,function()
            for _,r in pairs(self.buttons)do r.pointer=nil;self:tween(r.scale,.18,{Scale=1})end
        end)
        watch(gui.Destroying,function()self:destroy()end)
    end
    function self:attachLauncher(launcher,fallback)
        self.launcher=launcher;self.scopes[launcher]="launcher"
        self.alphas[launcher]={BackgroundTransparency=1,ImageTransparency=0}
        self.scopes[fallback]="launcher";self.alphas[fallback]={BackgroundTransparency=1,TextTransparency=0}
        self.logoFire=self:fire(self.gui,"MinimizedLogoFire",66,66)
        self.logoFire.host.ZIndex=59;self.logoFire.host.Visible=false
        self:fade("launcher",0)
    end
    function self:setMinimized(value)
        self.minimized=value
        if value then self.launcher.Visible=true else self.root.Visible=true end
        self:tween(self.opacity,.26,{Value=value and 0 or 1})
        self:tween(self.launcherOpacity,.26,{Value=value and 1 or 0})
    end
    function self:loadArtwork()
        task.spawn(function()
            local custom=getcustomasset or getsynasset
            if type(custom)~="function"then return end
            for _,asset in ipairs({
                {file="ReyznXEmotes_flame_v1.png",path="flame-wisp-v1.png",size=1172326,images=self.fireImages},
                {file="ReyznXEmotes_background_v2.jpg",path="background-cyber-v2.jpg",size=167325,images=self.backgroundImages,jpeg=true},
            })do
                local function valid(b)
                    return type(b)=="string"and #b==asset.size and (asset.jpeg and b:sub(1,3)==string.char(255,216,255)
                        or not asset.jpeg and b:sub(1,8)==string.char(137,80,78,71,13,10,26,10))
                end
                local cached=false
                if type(readfile)=="function"then local ok,b=pcall(readfile,asset.file);cached=ok and valid(b)end
                if not cached and type(writefile)=="function"then
                    local ok,b=pcall(function()return game:HttpGet("https://raw.githubusercontent.com/hzReyzn/Ghislain/main/assets/reyzn-x/"..asset.path)end)
                    if not self.alive then return end
                    if ok and valid(b)then cached=pcall(writefile,asset.file,b)end
                end
                if cached and self.alive then
                    local ok,uri=pcall(custom,asset.file)
                    if ok and type(uri)=="string"and uri~=""then
                        for _,img in ipairs(asset.images)do if img.Parent then img.Image=uri end end
                    end
                end
            end
        end)
    end
    function self:start()
        self:setMinimized(false);self:loadArtwork()
        local elapsed,budget=0,0
        watch(RunService.Heartbeat,function(dt)
            if not self.alive then return end
            elapsed+=dt;budget+=dt
            if budget<1/60 then return end
            budget=budget%(1/60)
            local showWindow=self.root.Visible and self.opacity.Value>.001
            self.windowFire.host.Visible=showWindow
            if showWindow then
                updateFire(self.windowFire,elapsed,self.opacity.Value)
                for _,r in pairs(self.buttons)do if r.selected then r.edgeLight.Offset=Vector2.new(math.sin(elapsed*.45)*.26,0)end end
            end
            local showLogo=self.launcher.Visible and self.launcherOpacity.Value>.001
            self.logoFire.host.Visible=showLogo
            if showLogo then
                self.logoFire.host.Position=self.launcher.Position
                updateFire(self.logoFire,elapsed,self.launcherOpacity.Value)
            end
        end)
    end
    function self:destroy()
        if not self.alive then return end
        self.alive=false
        for _,c in ipairs(self.links)do c:Disconnect()end
        for _,r in pairs(self.buttons)do for _,c in ipairs(r.links)do c:Disconnect()end end
        for _,t in pairs(self.tweens)do t:Cancel()end
        table.clear(self.links);table.clear(self.buttons);table.clear(self.tweens)
        table.clear(self.fireImages);table.clear(self.backgroundImages);table.clear(self.fires)
        table.clear(self.alphas);table.clear(self.scopes)
    end
    return self
end)()

local function text(parent,value,x,y,w,h,size,bold,color)
    return new("TextLabel",parent,{
        Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundTransparency=1,Text=tostring(value),
        TextColor3=color or palette.white,
        FontFace=Font.new("rbxassetid://12187375422",bold and Enum.FontWeight.SemiBold or Enum.FontWeight.Medium,Enum.FontStyle.Normal),
        TextSize=size or 16,TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=4
    })
end
local function button(parent,value,x,y,w,h,isPrimary)
    local obj=new("TextButton",parent,{
        Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundColor3=isPrimary and Color3.fromRGB(95,52,150) or palette.row,
        BorderSizePixel=0,Text=tostring(value),TextColor3=palette.white,
        TextSize=16,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=3
    })
    round(obj,9)
    Design:button(obj,isPrimary)
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
Design:attach(root,gui)
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

local header=new("Frame",root,{BackgroundTransparency=1,Size=UDim2.new(1,0,0,66),ZIndex=3})
local headerLogo=new("ImageLabel",header,{
    Name="BrandLogo",Position=UDim2.fromOffset(12,8),
    Size=UDim2.fromOffset(50,50),Image="",
    BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit
})
local headerLogoFallback=text(header,"R",18,10,40,40,29,true,palette.purple)
headerLogoFallback.TextXAlignment=Enum.TextXAlignment.Center
text(header,"REYZN X",73,14,122,32,24,true,palette.white)
text(header,"FE EMOTES",207,14,180,32,21,true,palette.purple)
local minimize=button(header,"−",530,14,38,38,false)
local close=button(header,"×",577,14,38,38,false)
Design:windowControl(minimize,false)
Design:windowControl(close,true)
local bar=new("Frame",root,{Position=UDim2.fromOffset(14,66),
    Size=UDim2.new(1,-28,0,1),BorderSizePixel=0,BackgroundColor3=palette.muted,BackgroundTransparency=.8,ZIndex=3})
new("UIGradient",bar,{Color=ColorSequence.new({ColorSequenceKeypoint.new(0,palette.purple),
    ColorSequenceKeypoint.new(.55,Color3.fromRGB(141,220,255)),ColorSequenceKeypoint.new(1,palette.purple)}),
    Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.8),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,.8)})})
local sidebar=new("Frame",root,{Position=UDim2.fromOffset(12,79),
    Size=UDim2.fromOffset(141,337),BackgroundColor3=palette.panel,BackgroundTransparency=.5,BorderSizePixel=0,ZIndex=3})
round(sidebar,11);Design:metal(sidebar,true)
local body=new("Frame",root,{Position=UDim2.fromOffset(164,79),
    Size=UDim2.fromOffset(451,337),BackgroundColor3=palette.panel,BackgroundTransparency=.78,BorderSizePixel=0,ZIndex=3})
round(body,11);Design:metal(body,true)
local tabs={}
for i,name in ipairs({"Emotes","Packs","Favorites","Settings"}) do
    local displayName = name=="Emotes" and "FE Emotes" or (name=="Packs" and "Animations" or name)
    tabs[name]=button(sidebar,displayName,9,10+(i-1)*51,123,40,false)
    trackConnection(tabs[name].MouseButton1Click,function()
        currentTab=name
        searchTerm="";localPage=1
        if searchBox then searchBox.Text="" end
        if render then render() end
    end)
end

searchBox=new("TextBox",body,{
    Position=UDim2.fromOffset(12,11),Size=UDim2.fromOffset(277,37),
    BackgroundColor3=palette.row,BorderSizePixel=0,
    ClearTextOnFocus=false,Text="",TextColor3=palette.white,
    PlaceholderText="Search name or animation ID",PlaceholderColor3=palette.muted,
    TextSize=16,FontFace=Font.new("rbxassetid://12187375422",Enum.FontWeight.Medium,Enum.FontStyle.Normal),
    TextXAlignment=Enum.TextXAlignment.Left,ZIndex=3
})
new("UIPadding",searchBox,{PaddingLeft=UDim.new(0,11)})
round(searchBox,9)
outline(searchBox,palette.muted,.82)
local searchCatalog=button(body,"Load more",299,11,140,37,true)
local list=new("ScrollingFrame",body,{
    Position=UDim2.fromOffset(12,60),Size=UDim2.fromOffset(427,226),
    BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,
    ScrollBarImageColor3=palette.purple,CanvasSize=UDim2.fromOffset(0,0),ZIndex=3
})
local layout=new("UIListLayout",list,{
    Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder
})
trackConnection(layout:GetPropertyChangedSignal("AbsoluteContentSize"),function()
    list.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+5)
end)
local prev=button(body,"◀ Prev",12,296,88,32,false)
local next=button(body,"Next ▶",351,296,88,32,false)
local pageLabel=text(body,"Page 1",115,296,225,32,14,true,palette.muted)
pageLabel.TextXAlignment=Enum.TextXAlignment.Center
statusText=text(root,"Ready",15,427,598,22,13,false,palette.muted)

-- FastKeys are independent ScreenGui children, so they remain visible
-- when the main window is minimized. Eight small keys start at upper-right,
-- safely above the usual mobile jump button.
local FAST_SIZE=48
local FAST_GAP=5
local fastKeyPicker
local fastKeyPickerTitle
local fastKeyPickerOptions={}
local fastKeyPendingEmote=nil
local function openFastKeyPicker(item)
    if not item or item.kind~="Emote" then return end
    fastKeyPendingEmote=item
    fastKeyPickerTitle.Text="Assign emote: "..tostring(item.name)
    for i=1,FAST_KEY_COUNT do
        local bound=fastKeyBindings[i]
        fastKeyPickerOptions[i].Text="F"..i.."\n"..(bound and bound.name or "Empty")
    end
    fastKeyPicker.Visible=true
end

fastKeyPicker=new("Frame",root,{
    Name="FastKeyChooser",
    Position=UDim2.fromOffset(99,153),
    Size=UDim2.fromOffset(430,171),
    BackgroundColor3=palette.panel,BorderSizePixel=0,
    ZIndex=40,Visible=false
})
round(fastKeyPicker,12)
Design:metal(fastKeyPicker,false)
fastKeyPickerTitle=new("TextLabel",fastKeyPicker,{
    Position=UDim2.fromOffset(14,8),Size=UDim2.fromOffset(352,29),
    BackgroundTransparency=1,Text="Choose FastKey",
    TextColor3=palette.white,FontFace=Font.new("rbxassetid://12187375422",Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),
    TextSize=17,TextXAlignment=Enum.TextXAlignment.Left,
    TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=41
})
local pickerClose=new("TextButton",fastKeyPicker,{
    Position=UDim2.fromOffset(389,8),Size=UDim2.fromOffset(30,30),
    BackgroundColor3=palette.row,BorderSizePixel=0,
    Text="×",TextColor3=palette.white,Font=Enum.Font.GothamBold,
    TextSize=19,ZIndex=42
})
round(pickerClose,7)
Design:button(pickerClose,false)
Design:windowControl(pickerClose,true)
trackConnection(pickerClose.MouseButton1Click,function()
    fastKeyPicker.Visible=false
    fastKeyPendingEmote=nil
end)
for i=1,FAST_KEY_COUNT do
    local slotIndex=i
    local key=new("TextButton",fastKeyPicker,{
        Position=UDim2.fromOffset(15+((i-1)%4)*103,48+math.floor((i-1)/4)*58),
        Size=UDim2.fromOffset(94,51),
        BackgroundColor3=palette.row,BorderSizePixel=0,
        Font=Enum.Font.GothamBold,TextSize=10,
        TextColor3=palette.white,TextWrapped=true,
        Text="F"..i.."\nEmpty",ZIndex=42
    })
    round(key,8)
    key.TextSize=13
    Design:button(key,false)
    fastKeyPickerOptions[i]=key
    trackConnection(key.MouseButton1Click,function()
        if fastKeyPendingEmote then
            assignFastKey(slotIndex,fastKeyPendingEmote)
        end
        fastKeyPendingEmote=nil
        fastKeyPicker.Visible=false
    end)
end

local activeFastKeyGesture=nil
local function viewportDimensions()
    local camera=workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(900,600)
end
for i=1,FAST_KEY_COUNT do
    local slotIndex=i
    local col=(i-1)%2
    local row=math.floor((i-1)/2)
    local initial=UDim2.new(1,-(10+(1-col)*(FAST_SIZE+FAST_GAP)+FAST_SIZE),
        0,82+row*(FAST_SIZE+FAST_GAP))
    local saved=fastKeyPositions[i]
    if saved then initial=UDim2.fromScale(saved.x,saved.y) end
    local key=new("TextButton",gui,{
        Name="ReyznFastKey"..i,
        Position=initial,
        Size=UDim2.fromOffset(FAST_SIZE,FAST_SIZE),
        BackgroundColor3=palette.row,BorderSizePixel=0,
        Text="",AutoButtonColor=true,Active=true,
        ZIndex=35
    })
    round(key,9)
    outline(key,palette.purple,0.3)
    local number=new("TextLabel",key,{
        BackgroundTransparency=1,Position=UDim2.fromOffset(2,3),
        Size=UDim2.fromOffset(44,19),Text="F"..i,
        Font=Enum.Font.GothamBold,TextSize=14,
        TextColor3=palette.white,ZIndex=36
    })
    local name=new("TextLabel",key,{
        BackgroundTransparency=1,Position=UDim2.fromOffset(3,25),
        Size=UDim2.fromOffset(42,16),Text="EMPTY",
        Font=Enum.Font.Gotham,TextSize=9,
        TextColor3=palette.white,ZIndex=36,
        TextTruncate=Enum.TextTruncate.AtEnd
    })
    fastKeyButtons[i]={button=key,name=name,number=number}
    updateFastKeyButton(i)
    trackConnection(key.InputBegan,function(input)
        if not running or activeFastKeyGesture then return end
        local kind=input.UserInputType
        if kind~=Enum.UserInputType.MouseButton1
            and kind~=Enum.UserInputType.Touch then return end
        activeFastKeyGesture={
            index=slotIndex,input=input,
            origin=input.Position,
            initial=key.AbsolutePosition,
            moved=false
        }
    end)
end
trackConnection(UserInputService.InputChanged,function(input)
    local g=activeFastKeyGesture
    if not g then return end
    local mouse=(g.input.UserInputType==Enum.UserInputType.MouseButton1
        and input.UserInputType==Enum.UserInputType.MouseMovement)
    if input~=g.input and not mouse then return end
    local delta=input.Position-g.origin
    if delta.Magnitude>=9 then g.moved=true end
    if not g.moved then return end
    local view=viewportDimensions()
    local x=math.clamp(g.initial.X+delta.X,4,math.max(4,view.X-FAST_SIZE-4))
    local y=math.clamp(g.initial.Y+delta.Y,44,math.max(44,view.Y-FAST_SIZE-4))
    fastKeyButtons[g.index].button.Position=UDim2.fromOffset(x,y)
end)
trackConnection(UserInputService.InputEnded,function(input)
    local g=activeFastKeyGesture
    if not g then return end
    local mouseUp=(g.input.UserInputType==Enum.UserInputType.MouseButton1
        and input.UserInputType==Enum.UserInputType.MouseButton1)
    if input~=g.input and not mouseUp then return end
    activeFastKeyGesture=nil
    if g.moved then
        local key=fastKeyButtons[g.index].button
        local view=viewportDimensions()
        fastKeyPositions[g.index]={
            x=math.clamp(key.AbsolutePosition.X/math.max(1,view.X),0,1),
            y=math.clamp(key.AbsolutePosition.Y/math.max(1,view.Y),0,1)
        }
        saveFastKeys()
        return
    end
    local emote=fastKeyBindings[g.index]
    if emote then
        task.spawn(function()
            if running then playEmote(emote) end
        end)
    else
        say("FastKey F"..g.index.." is empty. Tap KEY beside an emote to assign it.")
    end
end)


Design:shortcuts(fastKeyButtons)

local minimized=false
-- Only Emotes is changed. As in Reyzn X, the logo is saved with
-- writefile and displayed with getcustomasset/getsynasset.
local logoLauncher=new("ImageButton",gui,{
    Name="EmotesLogoLauncher",Size=UDim2.fromOffset(66,66),
    Position=UDim2.fromOffset(16,155),
    Image="",ScaleType=Enum.ScaleType.Fit,
    BackgroundTransparency=1,BorderSizePixel=0,
    AutoButtonColor=false,Active=true,Visible=false,ZIndex=60
})
-- The PNG has its own rounded shape. No secondary frame or border.
local launcherFallback=new("TextLabel",logoLauncher,{
    Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
    Text="R",TextColor3=palette.purple,
    Font=Enum.Font.GothamBold,TextSize=38,ZIndex=61
})
Design:attachLauncher(logoLauncher,launcherFallback)
local function decodeLogo(data)
    if type(data)~="string" or #data<60 or #data>200000 then return nil end
    local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local output,carry,bits={},0,0
    for i=1,#data do
        local ch=data:sub(i,i)
        if ch=="=" then break end
        local pos=alphabet:find(ch,1,true)
        if pos then
            carry=carry*64+(pos-1)
            bits=bits+6
            if bits>=8 then
                bits=bits-8
                local m=2^bits
                output[#output+1]=string.char(math.floor(carry/m))
                carry=carry%m
            end
        elseif not ch:match("%s") then
            return nil
        end
    end
    return table.concat(output)
end
local function validLogo(bytes)
    return type(bytes)=="string" and #bytes>64 and #bytes<180000
       and bytes:sub(1,8)==string.char(137,80,78,71,13,10,26,10)
end
task.spawn(function()
    local customAsset=getcustomasset or getsynasset
    if type(customAsset)~="function" then
        warn("[Reyzn X Emotes] Logo requires getcustomasset/getsynasset.")
        return
    end
    local filename="ReyznXEmotes_R_logo_centered_v2.png"
    local cached=false
    if type(readfile)=="function" then
        local ok,bytes=pcall(function() return readfile(filename) end)
        cached=ok and validLogo(bytes)
    end
    if not cached and type(writefile)=="function" then
        local url="https://raw.githubusercontent.com/hzReyzn/Roblox-yeahhh-/reyzn-emotes-v18-logo-8keys-test/assets/reyzn-emotes-logo-centered-v2.b64"
        local ok,encoded=pcall(function() return game:HttpGet(url) end)
        if ok then
            local bytes=decodeLogo(encoded)
            if validLogo(bytes) then
                cached=pcall(function() writefile(filename,bytes) end)
            end
        end
    end
    if not cached or not running then return end
    local ok,uri=pcall(customAsset,filename)
    if ok and type(uri)=="string" and uri~="" and running then
        headerLogo.Image=uri
        logoLauncher.Image=uri
        headerLogoFallback.Visible=false
        launcherFallback.Visible=false
    end
end)
local function setMinimized(value)
    minimized=value
    Design:setMinimized(value)
    if value then
        fastKeyPicker.Visible=false
        fastKeyPendingEmote=nil
    end
end
local launcherGesture
trackConnection(logoLauncher.InputBegan,function(input)
    if not running or launcherGesture then return end
    if input.UserInputType==Enum.UserInputType.MouseButton1
       or input.UserInputType==Enum.UserInputType.Touch then
        launcherGesture={
            start=input.Position,
            origin=logoLauncher.AbsolutePosition,
            input=input,moved=false
        }
    end
end)
trackConnection(UserInputService.InputChanged,function(input)
    local g=launcherGesture
    if not g then return end
    local mouse=g.input.UserInputType==Enum.UserInputType.MouseButton1
       and input.UserInputType==Enum.UserInputType.MouseMovement
    if input~=g.input and not mouse then return end
    local delta=input.Position-g.start
    if delta.Magnitude>=9 then g.moved=true end
    if g.moved then
        local cam=workspace.CurrentCamera
        local view=cam and cam.ViewportSize or Vector2.new(900,600)
        logoLauncher.Position=UDim2.fromOffset(
            math.clamp(g.origin.X+delta.X,4,math.max(4,view.X-70)),
            math.clamp(g.origin.Y+delta.Y,40,math.max(40,view.Y-70))
        )
    end
end)
trackConnection(UserInputService.InputEnded,function(input)
    local g=launcherGesture
    if not g then return end
    local mouseUp=g.input.UserInputType==Enum.UserInputType.MouseButton1
       and input.UserInputType==Enum.UserInputType.MouseButton1
    if input~=g.input and not mouseUp then return end
    launcherGesture=nil
    if running and not g.moved then setMinimized(false) end
end)
trackConnection(minimize.MouseButton1Click,function()
    setMinimized(true)
end)

-- Free-area drag: top, sides, bottom and empty panel space.
-- Never steal gestures from tabs, search, buttons or the scrolling list.
local drag=false
local dragOrigin,dragPosition,dragTouch
local function pointInside(object,point)
    if not object or not object.Visible then return false end
    local pos,size=object.AbsolutePosition,object.AbsoluteSize
    return point.X>=pos.X and point.Y>=pos.Y
        and point.X<=pos.X+size.X and point.Y<=pos.Y+size.Y
end
local function overInteractiveControl(point)
    if pointInside(close,point) or pointInside(minimize,point) then return true end
    if minimized then return false end
    if pointInside(searchBox,point) or pointInside(searchCatalog,point)
        or pointInside(list,point) or pointInside(prev,point)
        or pointInside(next,point) then return true end
    for _,tab in pairs(tabs) do
        if pointInside(tab,point) then return true end
    end
    return false
end
local function beginDrag(input)
    if not running or drag then return end
    local kind=input.UserInputType
    if kind~=Enum.UserInputType.MouseButton1
        and kind~=Enum.UserInputType.Touch then return end
    if not pointInside(root,input.Position)
        or pointInside(fastKeyPicker,input.Position)
        or overInteractiveControl(input.Position) then return end
    drag=true
    dragOrigin=input.Position
    dragPosition=root.Position
    dragTouch=input
end
-- Listen on every noninteractive background, not just the header.
-- This includes the edge margins on the root Frame.
for _,surface in ipairs({root,header,bar,sidebar,body,statusText,pageLabel,Design.surface,Design.backgroundImages[1]}) do
    surface.Active=true
    trackConnection(surface.InputBegan,beginDrag)
end
trackConnection(UserInputService.InputChanged,function(input)
    if not drag or not dragTouch then return end
    local isPointer=(dragTouch.UserInputType==Enum.UserInputType.MouseButton1
        and input.UserInputType==Enum.UserInputType.MouseMovement)
    if input==dragTouch or isPointer then
        local delta=input.Position-dragOrigin
        root.Position=UDim2.new(dragPosition.X.Scale,dragPosition.X.Offset+delta.X,
            dragPosition.Y.Scale,dragPosition.Y.Offset+delta.Y)
    end
end)
trackConnection(UserInputService.InputEnded,function(input)
    if input==dragTouch or (dragTouch
        and dragTouch.UserInputType==Enum.UserInputType.MouseButton1
        and input.UserInputType==Enum.UserInputType.MouseButton1) then
        drag=false
        dragTouch=nil
    end
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
        BackgroundColor3=palette.row,BackgroundTransparency=.14,BorderSizePixel=0
    })
    round(frame,10);Design:metal(frame,true)
    local isEmote=item.kind=="Emote"
    -- Single clean title: origin labels were decorative clutter.
    text(frame,item.name,11,11,isEmote and 197 or 258,28,17,true)
    local b=button(frame,isEmote and "PLAY" or "APPLY",
        isEmote and 222 or 286,7,isEmote and 72 or 76,37,true)
    trackConnection(b.MouseButton1Click,function()
        if isEmote then
            task.spawn(function() playEmote(item) end)
        else
            task.spawn(function() activatePack(item) end)
        end
    end)
    if isEmote then
        local assign=button(frame,"KEY",302,7,60,37,false)
        assign.TextColor3=palette.purple
        trackConnection(assign.MouseButton1Click,function()
            openFastKeyPicker(item)
        end)
    end
    local key=itemKey(item)
    local fav=button(frame,favorites[key] and "★" or "☆",369,7,37,37,false)
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
        LayoutOrder=index,Size=UDim2.new(1,-6,0,46),
        BackgroundColor3=palette.row,BorderSizePixel=0,
        Text=value,Font=Enum.Font.GothamBold,TextSize=16,
        TextColor3=palette.white
    })
    round(b,9)
    Design:button(b,false)
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
        Design:select(b,name==currentTab)
    end
    searchBox.Visible=currentTab~="Settings"
    searchCatalog.Visible=currentTab=="Emotes" or currentTab=="Packs"
    searchCatalog.Text="Load more"
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
            say("Default movement restored (custom tracks removed).")
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
        settingLine("Clear saved animation ID cache",6,function()
            table.clear(catalogAnimationIds)
            for _,pack in ipairs(packList) do
                pack.playableClips=nil
            end
            catalogCacheDirty=true
            queueCatalogCacheSave()
            say(type(writefile)=="function"
                and "Saved animation IDs cleared. Reapply a pack to refresh."
                or "Session cache cleared (file storage unavailable).")
        end)
        for i=1,FAST_KEY_COUNT do
            local slotIndex=i
            local bound=fastKeyBindings[i]
            settingLine("Clear F"..i..": "..(bound and bound.name or "Empty"),6+i,function()
                clearFastKey(slotIndex)
                say("FastKey F"..slotIndex.." cleared.")
                render()
            end)
        end
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
    say("Ready | "..restoredCatalogIds.." cached")
end
-- Catalog browsing is on-demand to avoid infinite loading or startup stalls.
Design:start()
