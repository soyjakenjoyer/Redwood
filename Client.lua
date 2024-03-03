--[[
	Made by Garrett Fletcher (Roblox username RoyStanford) Feb 24, 2016
	
	Client Side Script
	Things to note:
		This code is designed in such a way that makes it extremely easy for the server and client to communicate
		This code will execute every time the player respawns
		OnClientInvoke makes server wait until this player's OnClientInvoke has been declared
		OnClientEvent doesn't make server wait, but the event adds to que and will fire when declared here
		^ These things won't fuck anything up really (Pardon my language, but get used to it b/c it'll show up a lot)
		Events (or their associated functions) can sometimes be fired multiple times when testing offline with different arguments passed (I forget why this happens)
--]]


--//Make sure server is loaded
local serverLoaded = workspace.resources.serverLoaded
while serverLoaded.Value == false do
	wait()
end

--//Make sure global libraries are loaded
while not (_G.gui and _G.objects) do
	wait()
end
local ClientTick = tick()
print("Initializing client script...")

--//Basic Variables
local up = require(workspace.upsilonLibrary)
local data = up.data
local ease = up.ease
local plyr = game.Players.LocalPlayer
local cam = workspace.CurrentCamera
local mouse = plyr:GetMouse()
local gui = _G.gui
local objects = _G.objects

local re = up.revent
local rf = up.rfunc
local online = game.PlaceId ~= 0--for testing online vs offline in studio

local dead = false
local allowJump = true

--//services
local inputService = game:GetService("UserInputService")
local market = game:GetService("MarketplaceService")
local startergui = game.StarterGui

local touchenabled = inputService.TouchEnabled

--//intro gui shit
if not _G.firstSpawnFinished then
	gui.intro.Visible = true
end

--//Make sure character is loaded
while not (plyr.Character and plyr.Character:FindFirstChild("Humanoid")) do
	wait()
end
local char = plyr.Character
mouse.TargetFilter = workspace.ignore
--//Make sure player data has loaded
if not _G.dataReady then
	local dataSuccess = up.InvokeServer("waitForPlayerData")
	if not dataSuccess then
		print("Data took too long to load! PM RoyStanford cause something terrible went wrong :O")
	else
		print("Player data loaded (client)")
	end
	
	_G.dataReady = dataSuccess
end

--print("I have this many cash:", data.getValue("cash"))

--//game stuff
local passes = {
	hasSwat = data.getValue("hasSwat"),
	hasSpecOps = data.getValue("hasSpecOps"),
	hasMerc = data.getValue("hasMerc"),
	hasPilot = data.getValue("hasPilot"),
	hasAtv = data.getValue("hasAtv"),
}
local riotShield

local lastHatRemoval = 0

--//Chat
local chatFrame = gui.chatFrame
local msgTemplate = gui.chatMessage
local chatInput = gui.chatInput

local numChatsToShow = 10
local chatInputMsg = chatInput.Text
local fontHeight = msgTemplate.tag.TextBounds.Y
chatFrame.Size = UDim2.new(0, 500, 0, fontHeight*numChatsToShow)
chatInput.Position = UDim2.new(0, 10, 0, chatFrame.AbsolutePosition.Y + chatFrame.AbsoluteSize.Y)
chatInput.Visible = true

local myColorType = up.findIndex(up.admins, plyr.userId) and "admin" or "ingame"
local lastChat = 0
local isTyping = false

local recentMessages = {}
local messageColors = {
	--//message text color
	["ingame"]	= up.c3(255, 255, 255),
	["admin"]	= up.c3(255, 217, 164),
}

local availableColors = 5--first this amt of nameColors are randomly available
local nameColors = {
	--random player colors
	up.c3(115, 202, 255),	--light blue
	up.c3(202, 115, 255),	--light purple
	up.c3(255, 202, 115),	--yellow/orange
	up.c3(255, 69, 72),		--red
	up.c3(97, 206, 104),	--green
	--------------------------------------------
	--reserved colors
	Color3.new(0, 1, 1),	--neon blue
}

if not _G.nameColorId then
	_G.nameColorId = math.random(availableColors)
end
if not _G.chatLog then
	_G.chatLog = {}
	-------------{{username, message, colortype, tagcolorid}}
end

function makeMessage(username, message, colorType, hisColorId, startup)
	--//make gui object
	local msg = msgTemplate:Clone()
	msg.Position = UDim2.new(0,0,1,0)--to change offset, change tarPos object value
	msg.Size = UDim2.new(1,0,0,fontHeight)
	msg.Parent = chatFrame
	
	--//prep tag and msg
	local tag = msg:WaitForChild("tag")
	tag.Text = username--..":"
	local tagSize = tag.TextBounds.X
	tag.Size = UDim2.new(0,tagSize,1,0)
	
	local msgLabel = msg:WaitForChild("msg")
	msgLabel.Text = message
	local msgXOffset = tagSize+10
	msgLabel.Position = UDim2.new(0,msgXOffset,0,0)
	msgLabel.Size = UDim2.new(1, -msgXOffset, 1, 0)
	
	local maxLines = 3
	while maxLines > 1 and not msgLabel.TextFits do
		msg.Size = msg.Size + UDim2.new(0,0,0,fontHeight)
		maxLines = maxLines - 1
		
		if msg.AbsoluteSize.Y > msgLabel.TextBounds.Y then
			--//went too far, just one continous word causes this issue
			msg.Size = msg.Size - UDim2.new(0,0,0,fontHeight)
			break
		end
	end
	
	--//add color
	hisColorId = hisColorId or 1
	tag.TextColor3 = nameColors[hisColorId]
	if colorType then
		msgLabel.TextColor3 = messageColors[colorType]
	end
	
	--//add to que
	table.insert(recentMessages, 1, msg)
	--//clear from que
	for i = numChatsToShow + 2, #recentMessages do
		recentMessages[i]:Destroy()
		table.remove(recentMessages, i)
	end
	
	--//create log to save on reset
	if not startup then
		table.insert(_G.chatLog, 1, {username, message, colorType, hisColorId})
		
		for i = numChatsToShow + 1, #_G.chatLog do
			table.remove(_G.chatLog, i)
		end
	end
	
	return msg
end

function bumpMessages(startup, bumpAmt)
	for n,msgFrame in pairs(recentMessages) do
		msgFrame.tarPos.Value = msgFrame.tarPos.Value - bumpAmt
	end
	
	for i = #recentMessages, 1, -1 do
		local msgFrame = recentMessages[i]
		local pos = UDim2.new(0, 0, 1, msgFrame.tarPos.Value)
		
		if startup then
			msgFrame.Position = pos
		else
			msgFrame:TweenPosition(pos, "Out", "Quad", .25, true)
			wait(0)
		end
	end
end

function addMessage(username, message, colorType, hisColorId, startup)
	local msgFrame = makeMessage(username, message, colorType, hisColorId, startup)
	msgFrame.Visible = true
	
	bumpMessages(startup, msgFrame.AbsoluteSize.Y)
end

function decodeCommand(msg)
	--//NOTE: THIS CAN'T HANDLE DECIMALS AS ARGUMENTS ATM
	
	--//find command
	local command
	local start, stop = string.find(msg, "/")
	if start and start == 1 then
		local nStart, nStop = string.find(msg, " ")
		
		if not nStart then
			nStart = string.len(msg) + 1
		end
		
		command = string.sub(msg, start + 1, nStart - 1)
	end
	
	if not command then
		return
	else
		command = string.lower(command)
	end
	
	--//find arguments
	local args = {}
	local stringLen = string.len(command) + 1
	local argThere = true
	repeat
		local arg = string.match(msg, "%w+",stringLen+1)
		if arg then
			--print(arg)
			table.insert(args,tonumber(arg) or arg)
			stringLen = stringLen + string.len(arg) + 1
		else argThere = false
		end
	until not argThere
	
	return command, args
end

chatInput.FocusLost:connect(function(enterPressed)
	isTyping = false
	
	if enterPressed then
		local username = plyr.Name
		local message = chatInput.Text
		
		local msgLength = string.len(message)
		local maxMsgLength = 130
		if msgLength > maxMsgLength then
			message = string.sub(message, 1, maxMsgLength-3).."..."
		end
		
		if chatInput.TextBounds.Y > fontHeight then
			--//trying to spam chat box
			chatInput.Text = chatInputMsg
			_G.unfinishedChat = nil
			return
		else
			chatInput.Text = chatInputMsg
			_G.unfinishedChat = nil
		end
		
		local t = tick()
		if msgLength > 0 and t - lastChat > 0.5 then
			lastChat = t
			
			if string.sub(message, 1, 1) == "/" and (up.findIndex(up.admins, plyr.userId) or not online) then
				--//it's a command
				local cmd, args = decodeCommand(message)
				if cmd and args then
					up.FireServer("adminCommand", cmd, args)
				end
			else
				up.FireOtherClients("sendChat", username, message, myColorType, _G.nameColorId)
			end
			addMessage(username, message, myColorType, _G.nameColorId)--takes time to execute
		end
	else
		_G.unfinishedChat = nil
	end
end)

chatInput.Focused:connect(function()
	chatInput.Text = _G.unfinishedChat or ""
	isTyping = true
end)

chatInput.Changed:connect(function(prop)
	if prop == "Text" then
		_G.unfinishedChat = chatInput.Text
	end
end)

if up.customChat then
	startergui:SetCoreGuiEnabled("Chat",false)
else
	chatFrame.Visible = false
	chatInput.Visible = false
end



--//GUI STUFF
local oldFocus = nil
function newFocus(tarGui)
	if oldFocus and oldFocus ~= tarGui then
		oldFocus.Visible = false
		
		--//special cases
		
	end
	
	oldFocus = tarGui
	
	--//misc stuff
	
end

local scoped = false
function toggleSniperScope(show)
	if scoped == show then
		return
	end
	
	if show and (char.Head.Position - cam.CoordinateFrame.p).magnitude >= 1 then
		return
	end
	
	local frame = gui.sniperScope
	frame.Visible = show
	cam.FieldOfView = show and 30 or 70
	scoped = show
end

local noticeId = 0
function showNotice(title, msg)
	local noteFrame = gui.note
	noteFrame.title.Text = title
	noteFrame.desc.Text = msg
	
	noticeId = noticeId + 1
	local id = noticeId
	noteFrame.Visible = true
	
	wait(5)
	
	if id == noticeId then
		noteFrame.Visible = false
	end
end

local noticeId = 0
local notices = {}
local notePos = UDim2.new(0.125, 0, 0.25, 0)
_G.noticesToFade = {}
function smallNotice(msg, pushToHud)
	noticeId = noticeId + 1
	local id = noticeId
	
	for x, la in pairs(notices) do
		local yTar = la.yTar
		yTar.Value = yTar.Value + 24
		la:TweenPosition(notePos + UDim2.new(0, 0, 0, yTar.Value), "Out", "Quint", 0.25, true)
	end
	
	local temp = gui.noticeTemp
	local n = temp:Clone()
	n.Name = "notice"
	up.newVal("Int", 0, "yTar").Parent = n
	n.Parent = temp.Parent
	n.Text = msg
	n.Position = UDim2.new(0.125, 0, 0, -100)
	n.Visible = true
	n:TweenPosition(notePos, "Out", "Quint", 0.4, true)
	table.insert(notices, n)
	
	if pushToHud then
		gui.copTask.desc.Text = string.sub(msg, string.len("All Guards: ") + 1)
	end
	
	wait(10)
	
	local curIn = up.findIndex(notices, n)-- will probably always be 1
	table.remove(notices, curIn)
	
	newMovable("FadeText", {
		["model"] = n,
	})
end

local currentChoice = nil
local choiceFrame = gui.choiceFrame
local choiceMsg = choiceFrame.msg
function displayChoice(choiceKey, msg)
	currentChoice = choiceKey
	choiceFrame.Visible = true
	choiceMsg.Text = msg
end

function sendResult(wasYes)
	if currentChoice then
		if currentChoice == "returnToMenu" and wasYes then
			_G.lastMenu = tick()
		end
		
		up.FireServer("choiceResult", currentChoice, wasYes)
		choiceFrame.Visible = false
	end
end

choiceFrame.yes.MouseButton1Click:connect(function()
	sendResult(true)
end)
choiceFrame.no.MouseButton1Click:connect(function()
	sendResult(false)
end)

--//roles
local roleFrame = gui.roleChoose
function displayRoles()
	roleFrame.Visible = true
	
	for n,v in pairs(roleFrame:GetChildren()) do
		if v.desc.TextFits == false then
			v.desc.TextScaled = true
			
			if v.desc.TextFits == false then
				v.desc.Visible = false
			end
		end
		
		local pos = v.Position
		v:TweenPosition(UDim2.new(pos.X.Scale, pos.X.Offset, 0, 0), "Out", "Quint", .5, true)
		wait()
	end
end

function hideRoles()
	local tttt = .25
	
	for n,v in pairs(roleFrame:GetChildren()) do
		local pos = v.Position
		v:TweenPosition(UDim2.new(pos.X.Scale, pos.X.Offset, -1, 0), "In", "Quad", tttt, true)
		wait()
	end
	
	wait(tttt)	
	roleFrame.Visible = false
end

_G.lastMenu = _G.lastMenu or 0
gui.hud.menu.MouseButton1Click:connect(function()
	if tick() - _G.lastMenu > 60*10 then
		if plyr.TeamColor.Name ~= "White" then
			displayChoice("returnToMenu", "Are you sure you want to return to menu?")
		end
	else
		smallNotice("You must wait before you can switch teams again")
	end
end)

function getNumPlyrsOnTeam(color)
	local amt = 0
	for n,v in pairs(game.Players:GetPlayers()) do
		if v.TeamColor.Name == color then
			amt = amt + 1
		end
	end
	
	return amt
end

function canJoinTeam(choice)
	local numPolice = getNumPlyrsOnTeam("Bright blue")
	local numPrisoners = getNumPlyrsOnTeam("Bright red")
	local numFugitives = getNumPlyrsOnTeam("Bright yellow")
	
	if choice == "police" then
		return numPolice <= numPrisoners + 2 + math.floor(numFugitives/2) and numPolice <= 10
	elseif choice == "prisoners" then
		return numPrisoners <= numPolice + 2 and numPrisoners <= 10
	end
end

local roleDebounce = false
for n,v in pairs(roleFrame:GetChildren()) do
	v.choose.MouseButton1Click:connect(function()
		if roleDebounce then
			return
		end
		
		roleDebounce = true
		local choice = v.Name
		local okay = canJoinTeam(choice)
		if okay then
			local success = up.InvokeServer("requestTeam", choice)
			
			if success then
				hideRoles()
				wait(1)
				fixCamera()
				up.FireServer("reloadMe")
			end
		else
			coroutine.resume(coroutine.create(function()
				smallNotice("Sorry, that would make teams unbalanced.")
			end))
		end
		roleDebounce = false
	end)
	
	local pic = v:WaitForChild("pic")
	local s = pic.AbsoluteSize.X
	pic.Size = UDim2.new(0, s, 0, s)
end

_G.options = _G.options or data.getValue("options")
local options = _G.options
function updateOption(opt)
	local key = opt.Name
	local choice = options[key]
	local but = opt:WaitForChild("choice")
	if choice == true then
		but.BackgroundColor3 = Color3.new(76/255, 199/255, 105/255)
		but.Text = "Yes"
	else
		but.BackgroundColor3 = Color3.new(220/255, 79/255, 79/255)
		but.Text = "No"
	end
	
	--//handle change for things on respawn too
	if key == "diggity" then
		--//diggity
	end
end

function toggleOption(opt)
	local key = opt.Name
	local current = options[key]
	local newChoice = not current
	options[key] = newChoice
	
	updateOption(opt)
	
	--//handle change but not on respawn
	print("setting", key, "to", newChoice)
	if key == "showmotd" or not plyr:FindFirstChild("CanOpenChat") then
		updateTextReader(workspace.AllMovables.TextDisplay)
	elseif key == "outlines" then
		game.Lighting.Outlines = newChoice
	end
	
	data.setValueWithIndex("options", key, newChoice)
end

local optionsFrame = gui.options
local optionsDescs = {
	["showmotd"] = "Show Cafe Message",
	["outlines"] = "Toggle Outlines",
}
local cur = 0
function addOption(name, choice)
	local opt = optionsFrame.opt:Clone()
	opt.Parent = optionsFrame
	opt.Name = name
	
	local desc = optionsDescs[name]
	if desc then
		opt:WaitForChild("desc").Text = desc
	end
	opt:WaitForChild("choice").MouseButton1Click:connect(function()
		toggleOption(opt)
	end)
	
	opt.Position = opt.Position + UDim2.new(0, 0, 0, 30*cur)
	opt.Visible = true
	
	if not choice then
		updateOption(opt)
	end
	
	cur = cur + 1
end

if options then
	for name, choice in pairs(options) do
		addOption(name, choice)
	end
end
optionsFrame.quit.MouseButton1Click:connect(function()
	newFocus()
end)
gui.hud.options.MouseButton1Click:connect(function()
	if optionsFrame.Visible == true then
		newFocus()
	else
		optionsFrame.Visible = true
		newFocus(optionsFrame)
	end
end)

local markers = gui.GUI.Parent:WaitForChild("markers")
local dialogFrame = gui.dialog
function showDialog()
	dialogFrame.Visible = true
end

function hideDialog()
	dialogFrame.Visible = false
end

local currentOptions = {}
local currentDiaDesc
local questLocation
function stopDialog()
	if not currentDiaDesc then
		return
	end
	
	currentDiaDesc.Parent.activate.Visible = true
	currentDiaDesc.Visible = false
	currentDiaDesc = nil
	currentOptions = {}
	questLocation = nil
	hideDialog()
end

local quests = {
	--//max of 3 choices atm
	["Trenton"] = {
		{"Who are you?", "I'm Trenton but you can call me T-Bird. I love playing the bass.", {
			{"What are you doing here?", "I got arrested for rocking out too hard. I just can't help it though, I love music.", nil},
			},
		},
		{"Can you help me?", "Sure, but it'll cost you. Do you have something for me?", {
			{"Nope", "Well then get out of my face! GAHH", nil},
			{"What do you want?", "Hmm.. If you can find my guitar, I'll help you out. Somebody keeps moving it around!", {
				{"How am I going to find a guitar here??", "I'm pretty sure there is one somewhere out in the courtyard.", nil},
			}},
			{"I sure do", "Lets see...", nil, "checkForGuitar"},
			},
		},
	},
}
if plyr.TeamColor.Name == "Bright blue" then
	quests.Trenton = {
		{"Who are you?", "I AIN'T NEVER TALK TO NO POLICE OFFICER", nil}
	}
elseif plyr.TeamColor.Name == "Bright yellow" then
	quests.Trenton = {
		{"Hey buddy!", "I see you managed to escape... Nice job *Burp*", nil}
	}
end

function displayOptions(tbl, response, keyCode)
	if not currentDiaDesc then
		print("i don fucked up")
		return
	end
	
	currentOptions = {}
	
	--//hide choices
	for i = 1,3 do
		local choiceBut = dialogFrame["choice"..i]
		choiceBut.Text = ""
		choiceBut.Visible = false
	end
	
	response = response or "What's up?"
	currentDiaDesc.Text = response
	
	wait(2)
	
	if not currentDiaDesc then
		return
	end
	
	if keyCode then
		--//do something dumbfuck
		if keyCode == "checkForGuitar" then
			local hasGuitar = char:FindFirstChild("hasGuitar") ~= nil
			if hasGuitar then
				up.InvokeServer("giveItem", "Hammer")
				
				displayOptions({
					{"You're welcome", "I've gotta go call Joshua and the Gearys!", nil, "setTrentonJoshua"},
					{"Thanks", "*Slips into coma from overexcitement*", nil, "setTrentonDead"},
				}, "YES YOU FOUND IT!! Thank you so much! Here, have this hammer.")
				
				return--return if you ever display options
			else
				displayOptions(nil, "Quit wasting my time! You don't have anything I want!")
				return--return if you ever display options
			end
		elseif keyCode == "setTrentonDead" then
			quests.Trenton = {
				{"Are you okay?", "*Says nothing more because he is in a coma*", nil}
			}
		elseif keyCode == "setTrentonJoshua" then
			quests.Trenton = {
				{"Yo Trenton", "Let me play my music in peace!", nil}
			}
		end
	end
	
	if tbl then
		for n,choiceInfo in pairs(tbl) do
			local userInput = choiceInfo[1]
			local choiceBut = dialogFrame["choice"..n]
			choiceBut.Text = userInput
			currentOptions[n] = choiceInfo
			choiceBut.Visible = true
		end
		
		return true
	else
		wait(3)
		stopDialog()
		
		return false
	end
end

function activateDialog(but, desc, name)
	if currentDiaDesc then
		return
	end
	
	but.Visible = false
	currentDiaDesc = desc
	desc.Visible = true
	
	--//intial prompts
	local msg
	if name == "Trenton" then
		msg = "...Huh?? Err what do you want?"
	end
	
	local info = quests[name]
	dialogFrame.title.Text = name
	showDialog()
	displayOptions(info, msg)
end
--[[
for name, info in pairs(quests) do
	local billboard = markers:WaitForChild(name)
	if not billboard then
		print("[ ERROR ] Couldn't find quest: ", name)
	else
		local activate = billboard.activate
		local desc = billboard.desc
		activate.MouseButton1Click:connect(function()
			activateDialog(activate, desc, name)
		end)
	end
end
]]

for i = 1,3 do
	local choiceBut = dialogFrame["choice"..i]
	choiceBut.MouseButton1Click:connect(function()
		if currentOptions and currentOptions[i] then
			local choiceInfo = currentOptions[i]
			displayOptions(choiceInfo[3], choiceInfo[2], choiceInfo[4])
		end
	end)
end

local latestChangyChange = 16
function _G.changyChange(trySpeed)
	if dead then
		return
	end
	
	trySpeed = trySpeed or 16
	latestChangyChange = trySpeed
	if char.Humanoid.WalkSpeed ~= trySpeed then
		up.FireServer("changyChange", trySpeed)
	end
end


--//SOUND
local currentMainSound = nil
function playMusic(id, props)
	if currentMainSound then
		if id and string.find(currentMainSound.SoundId, tostring(id)) then
			return
		else
			currentMainSound:Stop()
			currentMainSound:Destroy()
			currentMainSound = nil
		end
	end
	
	if id then
		currentMainSound = up.playSound(id, props)
	end
end


--//ITEM HANDLER
local itemStats = {
	["Wooden Rod"] = {
		itemType = "Tools",
		coolDown = 1,
		isRod = true,
		
		lineOut = false,
		buoy = nil,
	},
	
	["Staff"] = {
		itemType = "Tools",
		coolDown = 0.5,
		doingAction = false,
	},
	
	["Taser"] = {
		isGun = true,
		animationType = "SmallGun",
		fireType = "single",
		coolDown = 1,
		reloadTime = 2.6,
		maxAmmo = 1,
		exAmmo = 20,
		maxExAmmo = 20,
		range = 50,
	},
	
	["AK47"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "automatic",
		sprayRange = 0.8,--degrees
		coolDown = 0.15,
		reloadTime = 1.25,
		maxAmmo = 30,
		exAmmo = 400,
		maxExAmmo = 400,
		range = 500,
		damage = 13,
	},
	
	["AK47-U"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "automatic",
		sprayRange = 0.65,--degrees
		coolDown = 0.15,
		reloadTime = 1.25,
		maxAmmo = 30,
		exAmmo = 400,
		maxExAmmo = 400,
		range = 500,
		damage = 15,
	},
	
	["SPAS-12"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "shotgun",
		amtBullets = 5,
		sprayRange = 4,--degrees
		coolDown = 0.3,
		reloadTime = 2,
		maxAmmo = 8,
		exAmmo = 120,
		maxExAmmo = 120,
		range = 500,
		damage = 6,
	},
	
	["M1014"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "shotgun",
		amtBullets = 5,
		sprayRange = 4.5,--degrees
		coolDown = 0.3,
		reloadTime = 2,
		maxAmmo = 10,
		exAmmo = 140,
		maxExAmmo = 140,
		range = 500,
		damage = 5,
	},
	
	["M16"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "automatic",
		sprayRange = 0.2,--degrees
		coolDown = 0.11,
		reloadTime = 2,
		maxAmmo = 40,
		exAmmo = 500,
		maxExAmmo = 500,
		range = 500,
		damage = 11,
	},
	
	["ACR"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "automatic",
		sprayRange = 0.15,--degrees
		coolDown = 0.11,
		reloadTime = 2,
		maxAmmo = 40,
		exAmmo = 500,
		maxExAmmo = 500,
		range = 500,
		damage = 12,
	},
	
	["M60"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "automatic",
		sprayRange = 0.5,--degrees
		coolDown = 0.125,
		reloadTime = 2.6,
		maxAmmo = 100,
		exAmmo = 1000,
		maxExAmmo = 1000,
		range = 500,
		damage = 11,
	},
	
	["L86A2"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "automatic",
		sprayRange = 0.5,--degrees
		coolDown = 0.125,
		reloadTime = 2.6,
		maxAmmo = 100,
		exAmmo = 1000,
		maxExAmmo = 1000,
		range = 500,
		damage = 8,
	},
	
	["Minigun"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "automatic",
		sprayRange = 0.5,--degrees
		coolDown = 0.125,
		reloadTime = 2.6,
		maxAmmo = 100,
		exAmmo = 1000,
		maxExAmmo = 1000,
		range = 500,
		damage = 11,
	},
	
	["Beretta M9"] = {
		isGun = true,
		animationType = "SmallGun",
		fireType = "single",
		sprayRange = 0.3,
		coolDown = 0.1,
		reloadTime = 2,
		maxAmmo = 10,
		exAmmo = 300,
		maxExAmmo = 300,
		range = 500,
		damage = 12,
	},
	
	["Makarov"] = {
		isGun = true,
		animationType = "SmallGun",
		fireType = "single",
		sprayRange = 0.3,
		coolDown = 0.1,
		reloadTime = 2,
		maxAmmo = 10,
		exAmmo = 300,
		maxExAmmo = 300,
		range = 500,
		damage = 11,
	},
	
	["Revolver"] = {
		isGun = true,
		animationType = "SmallGun",
		fireType = "single",
		sprayRange = 0.5,
		coolDown = 0.25,
		reloadTime = 2,
		maxAmmo = 6,
		exAmmo = 150,
		maxExAmmo = 150,
		range = 500,
		damage = 19,
	},
	
	["S&W 638"] = {
		isGun = true,
		animationType = "SmallGun",
		fireType = "single",
		sprayRange = 0.3,
		coolDown = 0.25,
		reloadTime = 2,
		maxAmmo = 6,
		exAmmo = 150,
		maxExAmmo = 150,
		range = 500,
		damage = 17,
	},
	
	["Dragunov"] = {
		isGun = true,
		hasScope = true,
		animationType = "LongGun",
		fireType = "single",
		sprayRange = 0.01,
		coolDown = 0.3,
		reloadTime = 2,
		maxAmmo = 10,
		exAmmo = 300,
		maxExAmmo = 300,
		range = 1000,
		damage = 25,
	},
	
	["M98B"] = {
		isGun = true,
		hasScope = true,
		animationType = "LongGun",
		fireType = "single",
		sprayRange = 0,
		coolDown = 1,
		reloadTime = 2,
		maxAmmo = 5,
		exAmmo = 100,
		maxExAmmo = 100,
		range = 1000,
		damage = 45,
	},
	
	["Dragunov"] = {
		isGun = true,
		hasScope = true,
		animationType = "LongGun",
		fireType = "single",
		sprayRange = 0,
		coolDown = 1,
		reloadTime = 2,
		maxAmmo = 10,
		exAmmo = 200,
		maxExAmmo = 200,
		range = 1000,
		damage = 30,
	},
	
	["M14"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "single",
		sprayRange = 1,
		coolDown = 0.6,
		reloadTime = 2,
		maxAmmo = 10,
		exAmmo = 300,
		maxExAmmo = 300,
		range = 500,
		damage = 22,
	},
	
	["UMP-45"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "automatic",
		sprayRange = 0.25,--degrees
		coolDown = 0.125,
		reloadTime = 2,
		maxAmmo = 40,
		exAmmo = 600,
		maxExAmmo = 600,
		range = 500,
		damage = 11,
	},
	
	["pistol"] = {
		isGun = true,
		animationType = "SmallGun",
		fireType = "single",
		sprayRange = 0.3,
		coolDown = 0.1,
		reloadTime = 2,
		maxAmmo = 10,
		range = 300,
		damage = 12,
	},
	
	["shotgun"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "shotgun",
		amtBullets = 5,
		sprayRange = 5,--degrees
		coolDown = 0.2,
		reloadTime = 0.75,
		maxAmmo = 8,
		range = 500,
		damage = 15,
	},
	
	["auto"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "automatic",
		sprayRange = 1,
		coolDown = 0.2,
		reloadTime = 0.75,
		maxAmmo = 30,
		range = 500,
		damage = 15,
	},
	
	["dmr"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "single",
		sprayRange = 1,
		coolDown = 0.2,
		reloadTime = 0.75,
		maxAmmo = 15,
		range = 500,
		damage = 15,
	},
	
	["smg"] = {
		isGun = true,
		animationType = "LongGun",
		fireType = "automatic",
		sprayRange = 2,
		coolDown = 0.1,
		reloadTime = 0.75,
		maxAmmo = 50,
		range = 500,
		damage = 15,
	},
	
	["Steak"] = {
		isFood = true,
		animationId = 402619118,
	},
	["Pancakes"] = {
		isFood = true,
		animationId = 402619118,
	},
	["Ham Sandwich"] = {
		isFood = true,
		animationId = 402619118,
	},
	
	["Punch"] = {
		animationId = 402635529,
	},
	["Handcuffs"] = {
		coolDown = 1,
		animationId = 402699946,
	},
	["Shank"] = {
		coolDown = 0.55,
		animationId = 402709587,
	},
	["Hammer"] = {
		coolDown = 0.5,
		animationId = 406545961,
	},
	["Guitar"] = {
		
	},
	["Fake ID Card"] = {
		
	},
	["Parachute"] = {
		
	},
}

--establish names to make it easier
for n,v in pairs(itemStats) do
	itemStats[n].name = n
end

--//item shit
local currentStats = {}--list of stats for items currently in backpack
local inv--declared later (_G.inventory)
local currentWelds

local driving = false--moved up from vehicle code section
local driveType = nil

local backpack = plyr.Backpack
local equippedItem = nil
local b1DownId = 0
local equipId = 0
local reloading = false
function prepItemConnections(item)
	local itemName = item.Name
	if currentStats[itemName] then
		--//already added, so maybe just going from character back to backpack
		return
	end
	
	--//prep stats
	currentStats[itemName] = up.deepCopyTbl(itemStats[itemName])
	local stats = currentStats[itemName]
	if stats.coolDown then
		stats.lastFire = 0
	end
	if stats.maxAmmo then
		stats.curAmmo = stats.maxAmmo
		if not stats.exAmmo then
			stats.exAmmo = stats.maxAmmo * 5
		end
	end
	
	--//connections (they are removed when item is destroyed)
	item.Equipped:connect(function()
		equipId = equipId + 1
		
		--//equip item
		if itemName == "Wooden Rod" then
			
		elseif stats.animationType then
			--[[
			makeWelds(char, stats.animationType)
			up.FireOtherClients("makeWelds", char)
			]]
			playAnimation(stats.animationType)
		elseif item.Name == "Hammer" and not char:FindFirstChild("hostile") and plyr.TeamColor.Name == "Bright red" then
			up.FireServer("becomeHostile")
			gui.hud.fight.Visible = false
			coroutine.resume(coroutine.create(function()
				smallNotice("You pulled out a hammer! You are now hostile and can be legally killed, watch out!")
			end))
		end
		
		equippedItem = item
		if stats.isGun then
			updateAmmoGui(stats)
			mouse.Icon = "http://www.roblox.com/asset/?id=43910485"
		end
		if riotShield and riotShield.Parent and not dead then
			riotShield.Parent = workspace.ignore
		end
	end)
	item.Unequipped:connect(function()
		equipId = equipId + 1
		
		--//unequipping item
		b1DownId = b1DownId + 1
		reloading = false
		equippedItem = nil--should be okay because i believe item is unequipped before next is equipped
		updateAmmoGui()
		
		if itemName == "Wooden Rod" then
			
		elseif itemName == "Punch" then
			_G.stopanim()
			punchCheck(false)
		end
		
		--[[
		if currentWelds then
			removeWelds()
			up.FireOtherClients("removeWelds", plyr)
		end
		]]
		if stats.animationType then
			stopAnimation(stats.animationType)
		end
		
		mouse.Icon = ""
		toggleSniperScope(false)
		if riotShield and riotShield.Parent and not dead then
			riotShield.Parent = workspace
		end
	end)
end
plyr:WaitForChild("Backpack").ChildAdded:connect(function(child)
	if child.ClassName == "Tool" then
		prepItemConnections(child)
	end
end)

function addItemToBackpack(itemName)
	local item = up.InvokeServer("giveItem", itemName)
	
	prepItemConnections(item)
	
	return item
end

function removeItemFromBackpack(itemName)--NOT FE COMPLIANT YET
	while backpack:FindFirstChild(itemName) do
		backpack[itemName]:Destroy()
	end
	
	currentStats[itemName] = nil
end

function updateAmmoGui(stats)
	local frame = gui.itemAmmo
	if stats and equippedItem and stats.curAmmo then
		frame.title.Text = equippedItem.Name
		frame.bigVal.Text = stats.curAmmo
		frame.smallVal.Text = "/"..stats.exAmmo
		
		if reloading then
			frame.bigVal.Text = "0"
			frame.smallVal.Text = "/"..(stats.exAmmo + stats.curAmmo)
		end
		
		frame.Visible = true
	else
		frame.Visible = false
	end
end

function itemCanFire(stats, setForMe)
	if stats.coolDown and stats.lastFire and not reloading then
		local ammoGood = not stats.curAmmo or stats.curAmmo > 0
		local t = tick()
		local cooldownGood = t - stats.lastFire >= stats.coolDown
		local canFire = cooldownGood and ammoGood
		if canFire and setForMe then
			stats.lastFire = t
			
			if stats.curAmmo then
				stats.curAmmo = stats.curAmmo - 1
				updateAmmoGui(stats)
			end
		elseif cooldownGood and not ammoGood then
			reload()
		end
		
		return canFire
	end
end

function playItemSound(type)
	if not equippedItem then
		print("how the fuck is this even being called")
	end
	
	if equippedItem:FindFirstChild("noz") and equippedItem.noz:FindFirstChild(type) then
		local sound = equippedItem.noz[type]
		sound:Play()
		up.FireOtherClients("playSound", sound)
	end
end

function attemptOpenDoor(tar, touching)
	if plyr.TeamColor == BrickColor.new("Bright blue") or tar.Parent:FindFirstChild("allAccess") or plyr.Backpack:FindFirstChild("Fake ID Card") or char:FindFirstChild("Fake ID Card") then
		if tar.Parent.Name ~= "ExSwitch" or tar.Parent.chair.Seat:FindFirstChild("SeatWeld") then--only flip the switch when somebody is in the seat!
			if tar.Parent:FindFirstChild("IsOpen") then
				up.FireServer("updateDoorSystem", tar.Parent)
			elseif tar:FindFirstChild("doorName") then
				up.FireServer("updateDoorSystem", workspace.AllDoors:FindFirstChild(tar.doorName.Value), tar)
			end
		end
	elseif not touching then
		--//notify
		coroutine.resume(coroutine.create(function()
			smallNotice("Only prison guards can open and close doors!")
		end))
	end
end

local canUseItems = true
function b1Down()
	b1DownId = b1DownId + 1
	--//non item shit
	local tar = mouse.Target
	if tar then
		--//doors
		if tar.Name == "glass" and tar.Parent:FindFirstChild("Active") then
			up.FireServer("toggleAlarmLight", tar.Parent)
		elseif tar.Name == "changePrompt" and tar:FindFirstChild("ClickDetector") then
			if plyr:FindFirstChild("CanOpenChat") then
				local free = up.InvokeServer("attemptChangeMOTD")
				if free then
					promptMOTD()
				end
			else
				smallNotice("Chat is disabled in your roblox settings, you cannot post messages.")
			end
		elseif tar:FindFirstChild("ClickDetector") then
			local meetsSpecs = false
			if tar:FindFirstChild("requires") then
				local requirement = tar.requires.Value
				if requirement == "swat" then
					if passes.hasSwat or data.getValue("hasSwat") == true then
						passes.hasSwat = true
						meetsSpecs = true
					else
						market:PromptPurchase(plyr, 402123546, nil, "Robux")
					end
				elseif requirement == "specOps" then
					if passes.hasSpecOps or data.getValue("hasSpecOps") == true then
						passes.hasSpecOps = true
						meetsSpecs = true
					else
						market:PromptPurchase(plyr, 409702167, nil, "Robux")
					end
				elseif requirement == "merc" then
					if passes.hasMerc or data.getValue("hasMerc") == true then
						passes.hasMerc = true
						meetsSpecs = true
					else
						market:PromptPurchase(plyr, 410031807, nil, "Robux")
					end
				elseif requirement == "pilot" then
					if passes.hasPilot or data.getValue("hasPilot") == true then
						passes.hasPilot = true
						meetsSpecs = true
					else
						market:PromptPurchase(plyr, 527547097, nil, "Robux")
					end
				elseif requirement == "trooper" then--atv pass
					if passes.hasAtv or data.getValue("hasAtv") == true then
						passes.hasAtv = true
						meetsSpecs = true
					else
						market:PromptPurchase(plyr, 696160163, nil, "Robux")
					end
				end
			else
				meetsSpecs = true
			end
			
			if (char.Torso.Position - tar.Position).magnitude > tar.ClickDetector.MaxActivationDistance then
				meetsSpecs = false
			end
			
			if meetsSpecs then
				if tar:FindFirstChild("hatOFFSET") and not char:FindFirstChild(tar.Name) then
					up.FireServer("wearHat", tar)
				elseif tar:FindFirstChild("shirtId") then
					up.FireServer("wearShirt", tar.shirtId.Value)
				elseif tar:FindFirstChild("pantsId") then
					up.FireServer("wearPants", tar.pantsId.Value)
				elseif tar.Name == "RiotShield" then
					if not char:FindFirstChild("RiotShield") then
						local shield = up.InvokeServer("giveRiotShield", tar)
						
						if shield then
							if equippedItem then
								shield.Parent = workspace.ignore
							else
								shield.Parent = workspace
							end
							riotShield = shield
						end
					elseif not equippedItem and tar.Anchored == false then--ANCHORED PREVENTS THE ORIGINAL FROM BEING TOGGLED LOL
						--//TOGGLE
						up.FireServer("toggleShield", tar)
					end
				elseif tar:FindFirstChild("gunGiver") and not char:FindFirstChild(tar.Name) and not plyr.Backpack:FindFirstChild(tar.Name) then
					up.InvokeServer("giveItem", tar.Name)
					if plyr.TeamColor.Name == "Bright red" and not plyr.Character:FindFirstChild("hostile") then
						up.FireServer("becomeHostile")
						smallNotice("You are now hostile! Guards can legally kill you now!")
					end
				elseif tar.Name == "quest" and tar:FindFirstChild("questName") then
					local name = tar.questName.Value
					local billboard = markers:FindFirstChild(name)
					
					if not billboard then
						print("[ ERROR ] Couldn't find quest: ", name)
					else
						local activate = billboard.activate
						local desc = billboard.desc
						questLocation = tar
						activateDialog(activate, desc, name)
					end
				elseif tar.Name == "GuitarSpawn" and not char:FindFirstChild("hasGuitar") then
					up.newVal("Bool", true, "hasGuitar").Parent = char--REMEMBER THIS IS LOCAL YOU FUCK
					up.InvokeServer("giveItem", "Guitar")
				end
				
				if tar.Name == "doorSystemButton" then
					attemptOpenDoor(tar)
				elseif tar.Name == "pickupFood" and tar.currentFood.Value ~= "" and not plyr.Backpack:FindFirstChild(tar.currentFood.Value) then
					up.InvokeServer("giveItem", tar.currentFood.Value)
				elseif tar.Name == "removeHats" and tick() - lastHatRemoval > 1 then
					lastHatRemoval = tick()
					up.FireServer("removeHats")
				end
			end
		end
	end
	
	--//item shit
	local item = equippedItem
	if not item then
		return
	end
	
	local itemName = item.Name
	local stats = currentStats[itemName]
	if stats.isRod and itemCanFire(stats, true) then
		if not stats.lineOut then
			--//cast line
			local rodBuoy = item:FindFirstChild("buoy")
			if not rodBuoy then
				print("buoy not found in rod with name:", itemName)
			end
			
			local buoy = stats.buoy
			if not buoy then
				--//make buoy
				buoy = rodBuoy:Clone()
				
				local bp = Instance.new("BodyPosition", buoy)
				bp.MaxForce = Vector3.new(10000, 10000, 10000)
				bp.Position = buoy.Position
				bp.D = 50
				bp.P = 500
				stats.buoy = buoy
			end
			
			buoy.CFrame = rodBuoy.CFrame
			buoy.Parent = workspace.ignore
			
			local bp = buoy.BodyPosition
			bp.Position = buoy.Position
			
			rodBuoy.Transparency = 1
			local xyPos = rodBuoy.Position
			bp.Position = Vector3.new(xyPos.X, _G.seaLevel.p.Y + 3, xyPos.Z)
			
			stats.lineOut = true
		elseif stats.lineOut then
			--//reel line back in
			local rodBuoy = item:FindFirstChild("buoy")
			if not rodBuoy then
				print("buoy not found in rod with name:", itemName)
			end
			
			local buoy = stats.buoy
			buoy.BodyPosition.Position = rodBuoy.Position
			
			wait(0.5)
			
			buoy.Parent = nil
			rodBuoy.Transparency = 0
			stats.lineOut = false
		end
	elseif stats.isGun and canUseItems and (not driving or driveType == "quad") then
		local fireType = stats.fireType
		
		if (fireType == "single" or fireType == "shotgun") and itemCanFire(stats, true) then
			local amtBullets = stats.amtBullets or 1
			for i = 1, amtBullets do
				fireWeapon(stats)
			end
			
			playItemSound("fire")
		elseif fireType == "automatic" then
			local currentId = b1DownId
			while b1DownId == currentId and itemCanFire(stats, true) and canUseItems do
				fireWeapon(stats)
				playItemSound("fire")
				stats.lastFire = tick()
				
				wait(stats.coolDown)
			end
		end
	elseif stats.isFood then
		_G.playanim(stats.animationId, true)
	elseif stats.name == "Punch" and canUseItems and (not driving or driveType == "quad") then
		local isPlaying = _G.playanim(stats.animationId, true)
		punchCheck(isPlaying)
	elseif stats.name == "Handcuffs" and itemCanFire(stats, true) then
		_G.playanim(stats.animationId, true)
		wait(0.4)
		
		--//check to cuff
		local hum = getHumInFront(4, true)
		if hum then
			local tarPlyr = game.Players:FindFirstChild(hum.Parent.Name)
			if tarPlyr and plyr.TeamColor.Name == "Bright blue" then
				up.FireServer("cuff", tarPlyr)
				coroutine.resume(coroutine.create(function()
					smallNotice("You arrested: "..tarPlyr.Name)
				end))
			end
		end
		_G.stopanim()
	elseif stats.name == "Shank" and itemCanFire(stats, true) and canUseItems then
		playItemSound("fire")
		_G.playanim(stats.animationId, true)
		wait(0.4)
		
		--//check to cuff
		local hum, hit = getHumInFront(4)
		if hum then
			up.FireServer("dealDamage", hum, math.random(15, 40))
		elseif hit then
			if hit.Name == "ventOpening" then
				up.FireServer("openVent", hit)
			end
		end
		
		_G.stopanim()
	elseif stats.name == "Hammer" and itemCanFire(stats, true) and canUseItems then
		playItemSound("fire")
		_G.playanim(stats.animationId, true)
		wait(0.3)
		
		--//check to cuff
		local hum, hit = getHumInFront(4)
		if hum then
			up.FireServer("dealDamage", hum, math.random(10, 20))
		elseif hit then
			if hit.Name == "ventOpening" then
				up.FireServer("openVent", hit)
			end
		end
		
		_G.stopanim()
	end
end

function b1Up()
	b1DownId = b1DownId + 1
	local item = equippedItem
	if not item then
		return
	end
	
	local itemName = item.Name
	local stats = currentStats[itemName]
	if itemName == "Staff" then
		
	end
end

function b2Down()
	local item = equippedItem
	if not item then
		return
	end
	
	local itemName = item.Name
	local stats = currentStats[itemName]
	if stats.hasScope then
		toggleSniperScope(true)
	end
end

function b2Up()
	local item = equippedItem
	if not item then
		return
	end
	
	local itemName = item.Name
	local stats = currentStats[itemName]
	if scoped then
		toggleSniperScope(false)
	end
end

function fillAmmo()
	local item = equippedItem
	if item then
		local stats = currentStats[item.Name]
		if stats.exAmmo ~= stats.maxExAmmo then
			stats.exAmmo = stats.maxExAmmo
			updateAmmoGui(stats)
		end
	end
end

function reload()
	local item = equippedItem
	if item and not reloading then
		local stats = currentStats[item.Name]
		if stats.exAmmo > 0 and stats.curAmmo ~= stats.maxAmmo then
			reloading = true
			updateAmmoGui(stats)
			
			local reloadId = equipId
			playItemSound("reload")
			--showPose(stats.animationType.."Reload", stats.reloadTime)
			playAnimation(stats.animationType.."Reload", stats.reloadTime)
			
			wait(stats.reloadTime)
			
			if equipId == reloadId then
				--//completed
				local diff = stats.maxAmmo - stats.curAmmo
				if diff > stats.exAmmo then
					diff = stats.exAmmo
				end
				
				stats.curAmmo = stats.curAmmo + diff
				stats.exAmmo = stats.exAmmo - diff
				reloading = false
				updateAmmoGui(stats)
			end
		end
	end
end


--//ANIMATION
--local currentWelds--I MOVED THIS ABOVE ITEM SHIT

local anis = {
	["LongGun"] = 682722662,
	["LongGunReload"] = 683022954,
	["SmallGun"] = 683077751,
	["SmallGunReload"] = 683086266,
	["getTased"] = 684536915,
	["Crawl"] = 686472306,
	["CrawlIdle"] = 686493216,
}
local aniObjects = {}

function stopAnimation(name)
	if aniObjects[name] then
		local animObject, animTrack = aniObjects[name][1], aniObjects[name][2]
		animTrack:Stop()
		animObject:Destroy()
		
		aniObjects[name] = nil
	end
end

function playAnimation(name, forceTime)
	stopAnimation(name)
	
	local id="rbxassetid://"..anis[name]
	
	local animObject, animTrack = aniObjects[name]
	if not animObject then
		animObject = Instance.new("Animation")
		animObject.Name = name
		animObject.AnimationId = id
		animObject.Parent = char
		
		animTrack = char.Humanoid:LoadAnimation(animObject)
	end
	
	local forceSpeed
	if forceTime then
		local startWait = tick()
		while animTrack.Length == 0 do--neccessary for when player using animation on first try bc it hasn't loaded yet
			wait()
		end
		
		forceSpeed = animTrack.Length/forceTime
	end
	
	animTrack:Play(nil,nil, forceSpeed)
	aniObjects[name] = {animObject, animTrack}
	
	return true
end

local originalAniIds = {--these ids will be overriden
	["idle"] = {
		--Animation1 = "http://www.roblox.com/asset/?id=180435571",
		--Animation2 = "http://www.roblox.com/asset/?id=180435792",
	},
	["walk"] = {
		--WalkAnim = "http://www.roblox.com/asset/?id=180426354"
	},
}

function changeCoreAni(ctype, newId)
	local animScript = char:FindFirstChild("Animate")
	if not animScript then
		print("COULDN'T FIND ROBLOX ANIMATE SCRIPT, MAYBE API HAS CHANGED?")
	end
	
	local objs = {}
	if ctype == "walk" then
		objs = {animScript.walk.WalkAnim}
	elseif ctype == "idle" then
		objs = {animScript.idle.Animation1,animScript.idle.Animation2}
	else
		print(ctype, "animation not supported for override!")
	end
	
	if newId then
		newId = "rbxassetid://"..newId
		
		for n,v in pairs(objs) do
			if not originalAniIds[ctype][v.Name] then
				originalAniIds[ctype][v.Name] = v.AnimationId
			end
			
			v.AnimationId = newId
		end
	else
		for n,v in pairs(objs) do
			v.AnimationId = originalAniIds[ctype][v.Name]
		end
	end
end


--//OBJECTS
_G.movableId = _G.movableId or 0
if not _G.movables then
	_G.movables = {}
end
local movables = _G.movables

local Movable = {}
function Movable:new(callingPlayer, clientId, type, customProps)
	local o = {
		["originalClient"] = callingPlayer,
		["clientId"] = clientId,
		["type"] = type,
		["birth"] = tick(),
	}
	for n,v in pairs(customProps) do
		o[n] = v
	end
	
	local checkModel = false
	--//type specific setup
	if type == "Door" then
		--//defaults
		o.length = 0.5
		o.style = "outExpo"
		
		local door = o.model.Parent
		for n,v in pairs({"length", "style"}) do
			if door:FindFirstChild(v) then
				o[v] = door[v].Value
			end
		end
		
		checkModel = true
	elseif type == "SecurityCamera" then
		o.length = 0.25
		o.style = "outSine"
		
		checkModel = true
	elseif type == "SpinningAlarm" then
		o.speed = math.rad(180)--per second
		
		checkModel = true
	elseif type == "Laser" then
		o.speed = 100--studs per second
		o.range = 500--studs
		o.destroy = true--gets rid of object when finished
	elseif type == "Bullet" then
		o.speed = 1000
		o.distance = 0
		o.range = 3000--studs
		
		if not o.bulletDrop then
			o.bulletDrop = 1/10
		end
		
		o.destroy = true--gets rid of object when finished
	elseif type == "SlidingText" then
		o.speed = 0.15--gui scale per second
		
		checkModel = true
	elseif type == "FadeText" then
		o.length = 1
		o.destroy = true
	elseif type == "ElectricMeter" then
		o.size = 3--how long it gets
		checkModel = true
	elseif type == "changeFov" then
		o.length = 0.25
		o.style = "outSine"
		
		o.model = workspace.CurrentCamera
		o.start = o.model.FieldOfView
		
		checkModel = true
	end
	
	--//check to see if it's already moving
	if checkModel then
		for n,v in pairs(movables) do
			if v.type == type and v.model == o.model then
				v.finished = true
			end
		end
	end
	
	setmetatable(o, self)
	self.__index = self
	table.insert(movables, o)
	return o
end

function Movable:Update(step, curTick)
	if self.finished then
		--//no need to do shit, must have finished up somewhere else
		return true
	end
	
	local type = self.type
	
	if type == "Door" then
		local t = curTick - self.birth
		local per = t/self.length
		
		if per > 1 then
			per = 1
		else
			per = ease[self.style](per, 0, 1, 1)
		end
		
		local tarCf = self.a:lerp(self.b, per)
		self.model:SetPrimaryPartCFrame(tarCf)
		
		if per >= 1 then
			self.finished = true
		end
	elseif type == "SecurityCamera" then
		local t = curTick - self.birth
		local per = t/self.length
		
		if per > 1 then
			per = 1
		else
			per = ease[self.style](per, 0, 1, 1)
		end
		
		local tarCf = self.a:lerp(self.b, per)
		self.model.camera:SetPrimaryPartCFrame(tarCf)
		
		if per >= 1 then
			self.finished = true
		end
	elseif type == "SpinningAlarm" then
		local spin = self.speed * step
		local main = self.model.main
		main.CFrame = main.CFrame * CFrame.Angles(-spin, 0, 0)
		
		self.finished = not self.model.Active.Value
	elseif type == "Laser" then
		local laser = self.model
		
		if self.cleanUp then
			local cleanUpTime = .25
			local per = (curTick - self.cleanUp)/cleanUpTime
			if per > 1 then
				per = 1
				self.finished = true
			else
				per = ease.outSine(per, 0, 1, 1)
			end
			
			--laser.Size = Vector3.new(0.2 + per*0.5, 0.2 + per*0.5, laser.Size.Z)
			laser.Transparency = per
		elseif curTick - self.birth >= 0 then
			self.cleanUp = curTick
		end
	elseif type == "Bullet" then
		local b = self.model
		
		if self.cleanUp then
			local cleanUpTime = .25
			local per = (curTick - self.cleanUp)/cleanUpTime
			if per > 1 then
				per = 1
				self.finished = true
			else
				per = ease.outSine(per, 0, 1, 1)
			end
			
			--b.Size = Vector3.new(0.2 + per*0.5, 0.2 + per*0.5, b.Size.Z)
			b.Transparency = per
		elseif true or self.notFirstTime then
			local drop = self.bulletDrop
			local scanLength = step * self.speed
			print(scanLength)
			
			local lastCF = self.lastCF
			local nextCF = lastCF * CFrame.new(0,0,-scanLength)
			nextCF = nextCF * CFrame.Angles(math.rad(-drop),0,0)
			
			self.distance = self.distance + scanLength
			
			local ray = Ray.new(lastCF.p, (nextCF.p - lastCF.p).unit * scanLength)
			local hit, hitPos, surfaceLv = workspace:FindPartOnRayWithIgnoreList(ray, {char, workspace.ignore})
			if hit then
				local rayLength = (hitPos - lastCF.p).magnitude
				if rayLength < self.bulletLength then
					local hitDist = (hitPos-lastCF.p).magnitude
					b.Size = Vector3.new(b.Size.X, b.Size.Y, hitDist)
					nextCF = lastCF * CFrame.new(0, 0, -hitDist)
				end
				
				self.cleanUp = curTick
				--[[
				streamDone = true
				local hum = gameLib.findHumanoid(hit)
				
				if not hum then
					if hit.Anchored and not hit.Parent:findFirstChild("NOBULLETS") and hit.Transparency ~= 1 then
						--//fancy hit detection and stuffff
						local hole = up.makePart(workspace.ignore.bullets)
						hole.BrickColor = BrickColor.new("Black")
						local size = .4
						hole.Size = Vector3.new(size,size,size)
						hole.CFrame = CFrame.new(hitPos, hitPos + surfaceLv) * CFrame.Angles(0, 0, 2*math.pi*math.random())
						hole.CanCollide = false
						hole.Name = "hole"
						local m = Instance.new("BlockMesh", hole)
						m.Scale = Vector3.new(1, 1, .5)
						--m.MeshType = "Sphere"
						game.Debris:AddItem(hole, 5)
					end
				elseif not justLooks then
					if hum:isA("Humanoid") then
						events.showHitMarker:Fire()
					end
					
					events.humTakeDamage:FireServer(hum, dmg, hit)
				end
				]]
			elseif self.distance >= self.range then
				self.finished = true
			end
			
			b.CFrame = nextCF * CFrame.new(0, 0, b.Size.Z/2)
			
			self.lastCF = nextCF
		else
			self.notFirstTime = true
		end
		
		self.notFirstTime = true
	elseif type == "SlidingText" then
		--//DIGGITY
		local label = self.model
		label.Position = label.Position - UDim2.new(self.speed * step, 0, 0, 0)
		
		local pos = label.Position
		local size = label.Size
		if pos.X.Scale < -size.X.Scale then
			label.Position = UDim2.new(1.1, 0, 0, 0)
		end
	elseif type == "FadeText" then
		local label = self.model
		local per = (curTick - self.birth)/self.length
		if per > 1 then
			per = 1
			self.finished = true
		end
		
		label.TextTransparency = per
		label.TextStrokeTransparency = per
	elseif type == "ElectricMeter" then
		local model = self.model
		local per = (curTick - self.birth)/self.length
		if per > 1 then
			per = 1
			self.finished = true
		end
		
		if self.backwards then
			per = 1 - per
		end
		
		local length = self.size * per
		model.progress.Size = Vector3.new(0.75, length, 0.75)
		model.progress.CFrame = model.barStart.CFrame * CFrame.new(0, length/2, 0)
	elseif type == "changeFov" then
		local per = (curTick - self.birth)/self.length
		if per > 1 then
			per = 1
			self.finished = true
		else
			per = ease[self.style](per, 0, 1, 1)
		end
		
		workspace.CurrentCamera.FieldOfView = (self.tar - self.start) * per + self.start
	end
	
	return self.finished
end

function newMovable(type, customProps)
	_G.movableId = _G.movableId + 1
	local mov = Movable:new(plyr, _G.movableId, type, customProps)
	--table.insert(movables, mov)--this was adding movables to the list twice, which should not have happened
end


--//GAME SPECIFIC SHIT
local creation = tick()
function updateDoorSystem(system)
	local isOpen = system.IsOpen.Value
	local state = isOpen and "open" or "closed"
	
	for n,v in pairs(system:GetChildren()) do
		if v.Name == "door" then
			--//diggity
			--v:SetPrimaryPartCFrame(v[state].Value)
			local a = v:GetPrimaryPartCFrame()
			local b = v[state].Value
			
			if a ~= b then
				local mov = newMovable("Door", {
					["model"] = v,
					["a"] = a,
					["b"] = b,
				})
			end
		end
	end
	
	local status = system:FindFirstChild("status")
	if status then
		if isOpen then
			status.BrickColor = BrickColor.new("Bright red")
		else
			status.BrickColor = BrickColor.new("Bright green")
		end
	end
	
	local audioPart = system:FindFirstChild("audio") or system.door.PrimaryPart
	if audioPart and tick() - creation > 10 then
		up.playSoundIn(audioPart, 396508015)
	end
end

function updateAlarmLight(light)
	local active = light.Active.Value
	local main = light.main
	local glass = light.glass
	
	local color
	if active then
		color = BrickColor.new("Bright red")
		glass.Material = Enum.Material.Neon
		local mov = newMovable("SpinningAlarm", {
			["model"] = light,
		})
		
		playMusic(293499018, {Looped = true, Name = "AlarmSound"})
	else
		color = BrickColor.new("Medium stone grey")
		glass.Material = Enum.Material.SmoothPlastic
		
		playMusic()
	end
	
	for n,v in pairs(main:GetChildren()) do
		if v.ClassName == "SurfaceLight" then
			v.Enabled = active
		end
	end
	
	main.BrickColor = color
	glass.BrickColor = color
end

function updateTextReader(reader)
	local prompt = reader.prompt
	local msg = prompt.msg.Value
	if options.showmotd == false or not plyr:FindFirstChild("CanOpenChat") then
		msg = "Welcome to Redwood Correctional Facility."
	end
	
	local frame = prompt.gui.frame
	local label = frame.label
	label.Text = msg
	label.Position = UDim2.new(1, 0, 0, 0)
	label.Size = UDim2.new(0.1, 0, 1, 0)
	
	local safety = 100
	while not label.TextFits and safety > 0 do
		label.Size = label.Size + UDim2.new(0.1, 0, 0, 0)
		safety = safety - 1
	end
	
	local mov = newMovable("SlidingText", {
		["model"] = label,
	})
end

local inputKey = nil
local textInputId = 0
function showTextInput(key, title, timer)
	inputKey = key
	textInputId = textInputId + 1
	local id = textInputId
	
	local frame = gui.textInput
	frame.msg.Text = "Enter text here"
	frame.Visible = true
	frame:TweenPosition(UDim2.new(0.5, -200, 0.75, -75), "Out", "Quad", 0.25, true)
	
	if timer then
		while timer >= 0 and id == textInputId do
			frame.title.Text = title.." ("..timer..")"
			timer = timer - 1
			wait(1)
		end
		
		if id == textInputId then
			submitTextInput()
		end
	end
end

function submitTextInput()
	local hide = true
	local frame = gui.textInput
	if inputKey == "motd" then
		--//update motd
		local msg = frame.msg.Text
		up.FireServer("updateMOTD", msg)
	end
	
	if hide then
		textInputId = textInputId + 1
		inputKey = nil
		frame:TweenPosition(UDim2.new(0.5, -200, 1, 100), "Out", "Quad", 0.25, true)
		wait(.25)
		if frame.Position.Y.Scale >= 1 then
			frame.Visible = false
		end
	end
end
gui.textInput.but.MouseButton1Click:connect(submitTextInput)

function showCamSelect()
	local frame = gui.camSelect
	frame.Visible = true
	frame:TweenPosition(UDim2.new(0.5, -150, 1, -225), "Out", "Quad", 0.25, true)
end

function hideCamSelect()
	local frame = gui.camSelect
	frame:TweenPosition(UDim2.new(0.5, -150, 1, 100), "Out", "Quad", 0.25, true)
	wait(.25)
	if frame.Position.Y.Offset >= 0 then
		frame.Visible = false
	end
end

local usingSecurityCams = false
local currentSecuritySeat = nil
function enterSecurityCamState()
	usingSecurityCams = true
	showCamSelect()
end

function fixCamera()
	cam.CameraType = Enum.CameraType.Custom
	gui.secCamHud.Visible = false
end

local curSecCam = nil
function stopWatchingCameras()
	if curSecCam then
		up.FireServer("toggleCamControl", curSecCam, false)
	end
	curSecCam = nil
	fixCamera()
end

function leaveSecurityCamState()
	stopWatchingCameras()
	usingSecurityCams = false
	hideCamSelect()
end

local securityCamLoc = workspace.AllMovables.SecurityCams
function controlSecurityCam(name)
	name = name or ""
	local secCam = securityCamLoc:FindFirstChild(name)
	
	if not secCam or (curSecCam and secCam == curSecCam) then
		--//we're done
		stopWatchingCameras()
		return
	end
	
	if curSecCam then
		up.FireServer("toggleCamControl", curSecCam, false)
	end
	
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CoordinateFrame = secCam.camera.lens.CFrame
	curSecCam = secCam
	up.FireServer("toggleCamControl", curSecCam, true)
	
	local camHud = gui.secCamHud
	camHud.corner_tl.camName.Text = secCam.location.Value
	camHud.Visible = true
end

function rotateSecCam(xoff, yoff)
	if not curSecCam then
		return
	end
	
	xoff = xoff * (math.pi/8)
	yoff = yoff * (math.pi/12)
	
	up.FireServer("updateSecurityCamRotation", curSecCam, xoff, yoff)
end

function updateSecurityCamRotation(camToUpdate)
	local camModel = camToUpdate.camera
	local pivotPos = camModel.pivot.Position
	
	local xoff = camToUpdate.xaxis.Value
	local yoff = camToUpdate.yaxis.Value
	
	local a = camModel:GetPrimaryPartCFrame()
	local b = CFrame.new(pivotPos, pivotPos + camToUpdate.axis.CFrame.lookVector) * CFrame.Angles(0, xoff, 0) * CFrame.Angles(yoff, 0, 0)
	
	if a ~= b then
		local mov = newMovable("SecurityCamera", {
			["model"] = camToUpdate,
			["a"] = a,
			["b"] = b,
		})
	end
end

function promptMOTD()
	showTextInput("motd", "Change Cafeteria Message", 60)
end

--//prep cam connections
for n,but in pairs(gui.camSelect.cams:GetChildren()) do
	local seccam = securityCamLoc:FindFirstChild(but.Name)
	if seccam and seccam:FindFirstChild("location") then
		but.Text = seccam.location.Value
	end
		
	but.MouseButton1Click:connect(function()
		--//cam cam cam
		controlSecurityCam(but.Name)
	end)
end

for n,but in pairs(gui.camSelect.arrows:GetChildren()) do
	but.MouseButton1Click:connect(function()
		if but.Name == "up" then
			rotateSecCam(0, 1)
		elseif but.Name == "down" then
			rotateSecCam(0, -1)
		elseif but.Name == "left" then
			rotateSecCam(1, 0)
		elseif but.Name == "right" then
			rotateSecCam(-1, 0)
		end
	end)
end

for n,v in pairs(workspace.CameraChairs:GetChildren()) do
	v.camSeat.ChildAdded:connect(function(child)
		if child:isA("Weld") and child.Part1.Parent == char then
			currentSecuritySeat = v.camSeat
			enterSecurityCamState()
		end
	end)
	v.camSeat.ChildRemoved:connect(function(child)
		if child:isA("Weld") and usingSecurityCams and (not currentSecuritySeat or currentSecuritySeat == v.camSeat) then
			currentSecuritySeat = nil
			leaveSecurityCamState()
		end
	end)
end

function fancyCamText(curTick)
	local sec = math.floor(curTick % 60)
	local dec = math.floor((curTick % 1)*100)
	local mini = math.floor(curTick/60) % 60
	local hr = math.floor(curTick/60/60) % 24
	
	return up.addZeros(hr, 1)..":"..up.addZeros(mini, 1)..":"..up.addZeros(sec, 1)..";"..up.addZeros(dec, 1)
end

function fireRay(origin, target, range)
	local ray = Ray.new(origin, (target - origin).unit * range) 
	return workspace:FindPartOnRayWithIgnoreList(ray, {workspace.ignore, char})
end

function getHumInFront(range, checkBelow)
	local origin = char.Torso.Position + Vector3.new(0, .75, 0)
	local target = origin + char.HumanoidRootPart.CFrame.lookVector
	range = range or 4
	
	local hit, hitPos = fireRay(origin, target, range)
	
	if hit then
		--//check for humanoid
		return up.findHumanoid(hit), hit
	elseif checkBelow then
		target = target + char.HumanoidRootPart.CFrame.lookVector
		hit, hitPos = fireRay(target, target + Vector3.new(0,-1,0), 5)
		
		if hit then
			return up.findHumanoid(hit), hit
		end
	end
end

local punchId = 0
function punchCheck(shouldPunch)
	punchId = punchId + 1
	local id = punchId
	
	if shouldPunch then
		while wait(0.4) and punchId == id do
			--//check for enemy
			local hum = getHumInFront(4)
			if hum then
				up.FireServer("dealDamage", hum, math.random(3, 8))
			end
		end
	end
end

function _G.stopPunching()
	punchCheck(false)
end

---THIS IS AS GOOD A SPOT AS ANY I GUESS
local crawling = false
function toggleCrouch(forceState)--THIS RETURNS THE ORIGINAL STATE OF CRAWLING
	if forceState == crawling then
		return crawling
	end
	
	if not crawling then
		crawling = true
		_G.stopanim()
		
		--override
		_G.forceWalkPose()--FUCK ROBLOX ANIMATIONS FOR WHATEVER REASON IT ONLY WORKS WITH THIS
		_G.forceUpdateCoreAni("idle", anis["CrawlIdle"])
		_G.forceUpdateCoreAni("walk", anis["Crawl"])
	
		
		_G.changyChange(4)
	else
		crawling = false
		
		--reset
		_G.forceWalkPose()
		_G.forceUpdateCoreAni("idle")
		_G.forceUpdateCoreAni("walk")
		
		
		_G.changyChange(16)
	end
	
	return not crawling
end
_G.toggleCrouch = toggleCrouch

local laserTemp = up.makePart()
laserTemp.Parent = nil
laserTemp.Material = Enum.Material.SmoothPlastic
laserTemp.BrickColor = BrickColor.new("Mid gray")
laserTemp.Anchored = true
laserTemp.CanCollide = false
--[[
local pointLight = Instance.new("SurfaceLight")
pointLight.Parent = laserTemp
pointLight.Color = laserTemp.BrickColor.Color
pointLight.Face = "Bottom"
]]
function drawLaser(origin, target, customProps)
	local dist = (origin-target).magnitude
	
	local laser = laserTemp:Clone()
	laser.Parent = workspace.ignore
	laser.Size = Vector3.new(0.2,0.2,dist)
	laser.CFrame = CFrame.new(origin, target) * CFrame.new(0, 0, -dist/2) * CFrame.Angles(0, 0, 2*math.pi*math.random())
	
	local mov = newMovable("Laser", {
		["model"] = laser,
	})
	
	return laser
end

function drawBullet(origin, target, customProps)
	local dist = 80
	
	local laser = laserTemp:Clone()
	laser.Parent = workspace.ignore
	laser.Size = Vector3.new(0.25,0.25,dist)
	if customProps.BrickColor then
		laser.BrickColor = customProps.BrickColor
	end
	
	local bulletOrigin = CFrame.new(origin, target)
	laser.CFrame = bulletOrigin-- * CFrame.new(0, 0, -dist/2)
	
	local mov = newMovable("Bullet", {
		["model"] = laser,
		["bulletLength"] = dist,
		["lastCF"] = bulletOrigin,
	})
end

function fireWeapon(stats)
	local item = equippedItem
	local origin = item.noz.Position
	local destination = mouse.Hit.p
	
	local cf = CFrame.new(origin, destination)
	if stats.sprayRange then
		cf = cf * CFrame.Angles(0, 0, 2*math.pi*math.random()) * CFrame.Angles(math.rad(stats.sprayRange*2)*(math.random()-0.5), 0, 0)
	end
	
	local customProps = {}
	if stats.name == "Taser" then
		customProps.BrickColor = BrickColor.new("Bright yellow")
		customProps.Reflectance = 0.5
		customProps.Material = Enum.Material.Neon
	else
		customProps = nil--noneedd
	end
	
	local ray = Ray.new(cf.p, cf.lookVector * stats.range)
	local hit, hitPos = workspace:FindPartOnRayWithIgnoreList(ray, {workspace.ignore, char})
	drawLaser(origin, hitPos, customProps)
	up.FireOtherClients("drawLaser", origin, hitPos, customProps)
	
	if hit and hit.Name ~= "RiotShield" then
		local hum = up.findHumanoid(hit)
				
		if hum then
			if stats.damage then
				up.FireServer("dealDamage", hum, stats.damage)
			end
			
			if stats.name == "Taser" then
				local tarPlyr = game.Players:FindFirstChild(hum.Parent.Name)
				if tarPlyr then
					up.FireServer("tase", tarPlyr, hitPos)
				end
			end
		end
	end
end


--//VEHICLES
--//config
local maxSpeed = 60
local allowFlip = true

local heliTurnSpeed = math.pi/4
local heliRollTilt = math.pi/8
local heliPitchTilt = math.pi/12
local heliRiseSpeed = 20--how fast it moves up and down

--[[MOVED HIGHER IN CODE
local driving = false
local driveType = nil
]]
local currentCar = nil
local tarSpeed = 0
local curSpeed = 0

local restingStiffness = 0--relax to let other spring pull when turning
local equalStiffness = 40000--pull to align wheels for straight motion
local pullingStiffness = 2000--pull to pull wheel to certain direction
local carStiffness, quadStiffness = 2000,20000--quad doesn't work unless you make this stronger, so pullingStiffness var changes depending

local speedIncrease = 100
local speedDecrease = 100
local lastFlipCheck = nil

function updateWheelSpeed(s)
	if currentCar then
		for n,v in pairs(currentCar:GetChildren()) do
			if v:FindFirstChild("Wheel") then
				v.Wheel.HingeConstraint.AngularVelocity = s
			end
		end
	end
end

local carVars = {}
function assignVariables(vehicle)
	--assign vars and also set up properties for movers
	if driveType == "heli" then
		local engine = vehicle.engine
		carVars.engine = engine
		
		carVars.bPos = engine.BodyPosition
		carVars.bVel = engine.BodyVelocity
		carVars.bGyro = engine.BodyGyro
		
		--//give them THE GOODS BABY
		carVars.bPos.Position = engine.Position
		carVars.bPos.MaxForce = Vector3.new(0, 400000, 0)
		carVars.bGyro.MaxTorque = Vector3.new(400000, 400000, 400000)
		
		--//get yaw
		local direction = engine.CFrame.lookVector
		local heading = math.atan2(direction.x, direction.z)
		
		--//rot
		carVars.yaw = heading + math.pi
		carVars.pitch = 0
		carVars.roll = 0
		
		carVars.turnSpeed = 0
	else
		carVars.leftWheel = vehicle["Left Wheel"]
		carVars.rightWheel = vehicle["Right Wheel"]
		
		carVars.underbar = vehicle.underbar
		carVars.leftSpring = carVars.underbar.leftSpring
		carVars.rightSpring = carVars.underbar.rightSpring
	end
end

function deleteVars()
	carVars = {}
end

local direction = nil
function updateSteering(dir)
	direction = dir
	
	if currentCar then
		if driveType == "heli" then
			if driving and direction == "left" then
				carVars.turnSpeed = heliTurnSpeed
				carVars.roll = heliRollTilt
			elseif driving and direction == "right" then
				carVars.turnSpeed = -heliTurnSpeed
				carVars.roll = -heliRollTilt
			else
				carVars.turnSpeed = 0
				carVars.roll = 0
			end
		else
			if driving and direction == "left" then
				carVars.leftSpring.Stiffness = restingStiffness
				carVars.rightSpring.Stiffness = pullingStiffness
			elseif driving and direction == "right" then
				carVars.rightSpring.Stiffness = restingStiffness
				carVars.leftSpring.Stiffness = pullingStiffness
			else
				carVars.rightSpring.Stiffness = equalStiffness
				carVars.leftSpring.Stiffness = equalStiffness
			end
		end
	end
end

--//vehicle input
local seat = nil
local keysDown = {}
function updateKey(key, isDown, keyCode)
	keysDown[key] = isDown
	
	if isDown == false then
		--check to see if he is still holding down the opposite key
		
		if key == "A" and keysDown.D then
			updateSteering("right")
		elseif key == "D" and keysDown.A then
			updateSteering("left")
		end
	end
end

local speed = 10
function vehicleKeyDown(keyCode)
	if keyCode == Enum.KeyCode.W then
		if driveType == "heli" then
			carVars.forwardSpeed = 40
			carVars.pitch = -heliPitchTilt
		else
			tarSpeed = maxSpeed
		end
		
		updateKey("W", true, keyCode)
	elseif keyCode == Enum.KeyCode.S then
		if driveType == "heli" then
			carVars.forwardSpeed = -20
			carVars.pitch = heliPitchTilt
		else
			tarSpeed = -maxSpeed/3
		end
		
		updateKey("S", true, keyCode)
	elseif keyCode == Enum.KeyCode.A then
		--//left
		--if driveType == "heli" then
			
		--else
			updateSteering("left")
		--end
		
		updateKey("A", true, keyCode)
	elseif keyCode == Enum.KeyCode.D then
		--//right
		--if driveType == "heli" then
			
		--else
			updateSteering("right")
		--end
		
		updateKey("D", true, keyCode)
	elseif keyCode == Enum.KeyCode.E then
		--//fly up
		if driveType == "heli" then
			tarSpeed = heliRiseSpeed
		end
	elseif keyCode == Enum.KeyCode.Q then
		--//fly down
		if driveType == "heli" then
			tarSpeed = -heliRiseSpeed
		end
	end
end

function vehicleKeyUp(keyCode)
	--print("Up:", keyCode)
	if keyCode == Enum.KeyCode.W then
		if driveType == "heli" then
			carVars.forwardSpeed = 0
			carVars.pitch = 0
		else
			tarSpeed = 0
		end
		
		updateKey("W", false, keyCode)
	elseif keyCode == Enum.KeyCode.S then
		if driveType == "heli" then
			carVars.forwardSpeed = 0
			carVars.pitch = 0
		else
			tarSpeed = 0
		end
		
		updateKey("S", false, keyCode)
	elseif keyCode == Enum.KeyCode.A then
		--//left
		--if driveType == "heli" then
			
		--else
			updateSteering(nil)
		--end
		
		updateKey("A", false, keyCode)
	elseif keyCode == Enum.KeyCode.D then
		--//right
		--if driveType == "heli" then
			
		--else
			updateSteering(nil)
		--end
		
		updateKey("D", false, keyCode)
	elseif keyCode == Enum.KeyCode.E then
		--//fly up
		if driveType == "heli" then
			tarSpeed = 0
		end
	elseif keyCode == Enum.KeyCode.Q then
		--//fly down
		if driveType == "heli" then
			tarSpeed = 0
		end
	end
end

local seatEvents = {}
function resetSeatEvent()
	for n,v in pairs(seatEvents) do
		if v then
			v:disconnect()
		end
	end
	
	seatEvents = {}
end

local gotHeliHint = false
function startDriving(tarSeat, vehicleType)
	driving = true
	driveType = vehicleType
	
	if driveType == "quad" then
		pullingStiffness = quadStiffness
	else
		pullingStiffness = carStiffness
	end
	
	if tarSeat then
		seat = tarSeat
		currentCar = seat.Parent
		assignVariables(currentCar)
		
		resetSeatEvent()
		table.insert(seatEvents, seat.Changed:connect(function(prop)
			if prop == "Steer" then
				local val = seat.Steer
				
				if val > 0 then
					vehicleKeyDown(Enum.KeyCode.D)--artificially press for mobile support
				elseif val < 0 then
					vehicleKeyDown(Enum.KeyCode.A)
				else
					vehicleKeyUp(Enum.KeyCode.A)
					vehicleKeyUp(Enum.KeyCode.D)
				end
			elseif prop == "Throttle" then
				local val = seat.Throttle
				
				if val > 0 then
					vehicleKeyDown(Enum.KeyCode.W)
				elseif val < 0 then
					vehicleKeyDown(Enum.KeyCode.S)
				else
					vehicleKeyUp(Enum.KeyCode.W)
					vehicleKeyUp(Enum.KeyCode.S)
				end
			end
		end))
		
		table.insert(seatEvents, seat.ChildRemoved:connect(function(child)
			if child:isA("Weld") then
				stopDriving()
			end
		end))
		
		updateSteering(nil)
		
		if driveType == "heli" then
			if touchenabled then
				gui.heliControls.Visible = true
			end
			
			if not gotHeliHint then
				gotHeliHint = true
				
				coroutine.resume(coroutine.create(function()
					if touchenabled then
						smallNotice("Use the buttons on the right to take off!")
					else
						smallNotice("Push and hold E to take off, Q to fly lower")
					end
				end))
			end
		end
	end
end

function stopDriving()
	if driveType == "heli" then
		--carVars.bPos.MaxForce = Vector3.new(0, 0, 0)
		carVars.bVel.Velocity = Vector3.new(0, 0, 0)
		--carVars.bGyro.MaxTorque = Vector3.new(0, 0, 0)
	else
		tarSpeed = 0
		updateWheelSpeed(0)
	end
	updateSteering(nil)
	
	driving = false
	gui.heliControls.Visible = false
	
	if currentCar then
		up.FireServer("resetNetworkOwnership", currentCar.Drive, driveType == "heli")
	end
	
	driveType = nil
	currentCar = nil
	seat = nil
	
	resetSeatEvent()
end

workspace.carSeated.OnClientEvent:connect(startDriving)

gui.heliControls.up.MouseButton1Down:connect(function()
	vehicleKeyDown(Enum.KeyCode.E)
end)
gui.heliControls.up.MouseButton1Up:connect(function()
	vehicleKeyUp(Enum.KeyCode.E)
end)
gui.heliControls.down.MouseButton1Down:connect(function()
	vehicleKeyDown(Enum.KeyCode.Q)
end)
gui.heliControls.down.MouseButton1Up:connect(function()
	vehicleKeyUp(Enum.KeyCode.Q)
end)


--//Client-server communcation
--//Client Events
local events = {
	--//core
	["showNotice"] = showNotice,
	["smallNotice"] = smallNotice,
	["sendChat"] = addMessage,
	["displayChoice"] = displayChoice,
	
	["showBanScreen"] = function(reason)
		reason = reason or "None given."
		reason = "Reason: "..reason
		
		local banFrame = gui.banFrame
		banFrame.reason.Text = reason
		banFrame.Visible = true
	end,
	
	--//game
	["updateDoorSystem"] = updateDoorSystem,
	["updateAlarmLight"] = updateAlarmLight,
	["playSound"] = function(plyr, sound)
		if sound then
			sound:Play()
		end
	end,
	["drawLaser"] = drawLaser,
	["drawBullet"] = drawBullet,
	["updateSecurityCamRotation"] = updateSecurityCamRotation,
	["updateClock"] = function(minutes)
		local text = up.timerText(minutes)
		gui.hud["clock"].Text = text
	end,
	
	["lockAndShock"] = function(shockPlayer)
		local beingShocked = false
		if shockPlayer and shockPlayer.Name == plyr.Name then
			allowJump = false
			beingShocked = true
		end
		
		local seconds = 5
		newMovable("ElectricMeter", {
			["length"] = seconds,
			["model"] = workspace.electricMeter
		})
		local chair = workspace.AllDoors.ExSwitch.chair
		local sound = up.playSoundIn(chair.sound, 133116870, {Looped = true, Pitch = 0.5,})
		table.insert(_G.deathCleanUp, sound)
		
		local ceilingLights = workspace.executionLights:GetChildren()
		for n,v in pairs(ceilingLights) do
			v.SurfaceLight.Enabled = false
		end
		
		for i = 1, 10*seconds do
			sound.Pitch = sound.Pitch + 0.05
			wait(.1)
		end
		
		local shockSound = up.playSoundIn(chair.sound, 157325701, {Looped = true})
		table.insert(_G.deathCleanUp, shockSound)
		
		local shockBlur
		if beingShocked then
			shockBlur = Instance.new("BlurEffect")
			shockBlur.Size = 0
			shockBlur.Parent = game.Lighting
			
			table.insert(_G.deathCleanUp, shockBlur)
		end
		
		local lights = chair.zapLights:GetChildren()
		for i = 1, 10*5 do
			if lights[1].BrickColor.Name ~= "Bright yellow" then
				for n,v in pairs(lights) do
					v.BrickColor = BrickColor.new("Bright yellow")
					v.Material = Enum.Material.Neon
					v.PointLight.Enabled = true
				end
			else
				for n,v in pairs(lights) do
					v.BrickColor = BrickColor.new("Dark stone grey")
					v.Material = Enum.Material.SmoothPlastic
					v.PointLight.Enabled = false
				end
			end
			
			local randomBool = math.random(2) == 1
			for n,v in pairs(ceilingLights) do
				v.SurfaceLight.Enabled = randomBool
			end
			
			shockBlur.Size = shockBlur.Size + 0.5
			
			wait(.1)
		end
		shockSound:Destroy()
		
		for n,v in pairs(lights) do
			v.BrickColor = BrickColor.new("Dark stone grey")
			v.Material = Enum.Material.SmoothPlastic
			v.PointLight.Enabled = false
		end
		for n,v in pairs(ceilingLights) do
			v.SurfaceLight.Enabled = true
		end
		
		newMovable("ElectricMeter", {
			["length"] = seconds,
			["model"] = workspace.electricMeter,
			["backwards"] = true,
		})
		
		for i = 1, 10*seconds do
			sound.Pitch = sound.Pitch - 0.05
			wait(.1)
		end
		sound:Destroy()
	end,
	
	["disserverani"] = function()--OLD CODE
		script.Parent.animateOthers.Disabled = true
	end,
	
	["setaniinc"] = function(inc)--OLD CODE
		_G.animateOthersInc = inc
	end,
	
	["taseMe"] = function()
		canUseItems = false
		if driving then
			char.Humanoid.Jump = true
		end
		
		_G.changyChange(0)
		playAnimation("getTased")
		wait(2)
		canUseItems = true
		_G.changyChange(16)
	end,
	
	["resetTeamSwitch"] = function()
		_G.lastMenu = tick()
	end,
}
function clientEvent(key, ...)
	if key == "FireOtherClients" then
		--this doesn't fire on client who called the event, and the player who called the event is not passed as an argument by default
		local args = {...}--{firstPlayer, newKey, anything else...}
		local firstPlyr, newKey = args[1], args[2]
		if firstPlyr ~= plyr then
			table.remove(args, 1)--get rid of first player from argument and fire it again
			clientEvent(unpack(args))--this works because now first argument is the new key
		end
	else
		events[key](...)
	end
end
re.OnClientEvent:connect(clientEvent)

--//Client Functions
local functions = {
	["getWalkSpeed"] = function()
		return char.Humanoid.WalkSpeed
	end,
}
function rf.OnClientInvoke(key, ...)
	return functions[key](...)
end


--//omg fuck you i don't need to comment shit
workspace.special.OnClientEvent:connect(function(key, ...)
	local args = {...}
	if key == "promptPilot" then
		market:PromptPurchase(plyr, 527547097, nil, "Robux")
		
		smallNotice("You need the Pilot Pass to fly the Military Helicopter")
	elseif key == "promptAtv" then
		market:PromptPurchase(plyr, 696160163, nil, "Robux")
		
		smallNotice("You need the ATV Access Pass to drive four-wheelers")
	elseif key == "updateAniValIds" then
		local tarPlyr = args[1]--the person who called it so ignore him
		
		if tarPlyr ~= plyr then
			local ids = args[2]
			
			for n,info in pairs(ids) do
				info[1].AnimationId = info[2]
				print("updated", info[1], "with", info[2])
			end
		end
	end
end)


--//hehe casssssssss on my mind (also toothless :D :D)

--//misc fucking vars
local prisonBoundaries = workspace.ignore.prisonBoundaries
local dippedbelowsealevel = nil
local sealevelimmune = plyr.TeamColor.Name == "White"

--//Render Stepped
local minFps
local fpsTime = 0
local lastFpsTick = tick()
local secondLoop = 0

local runService = game:GetService("RunService")
runService.Heartbeat:connect(function(step)--THIS USED TO BE RENDERSTEPPED BUT I HAVE CHANGED IT TO HEARTBEAT
	local curTick = tick()
	
	--//update movables
	for n = #movables,1,-1 do
		local mover = movables[n]
		local finished = mover:Update(step, curTick)
		
		if finished then
			if mover.destroy and mover.model then
				mover.model:Destroy()
			end
			
			table.remove(movables, n)
		end
	end
	
	--//game stuff
	if curSecCam and cam.CameraType == Enum.CameraType.Scriptable then
		cam.CoordinateFrame = curSecCam.camera.lens.CFrame
		gui.secCamHud.corner_bl.timer.Text = fancyCamText(curTick)
	end
	
	--//same as while wait(1) do
	if curTick - secondLoop >= 1 then
		secondLoop = curTick
		
		--//check to make hostile if beyond boundaries
		if plyr.TeamColor.Name == "Bright red" and not char:FindFirstChild("hostile") and not dead then
			local tPos = char.Torso.Position
			for n,v in pairs(prisonBoundaries:GetChildren()) do
				local boundPos = v.Position
				
				local distToBound = (boundPos - tPos).magnitude
				local distToFace = (boundPos + v.CFrame.lookVector - tPos).magnitude
				
				if distToBound > distToFace then
					--//he's outside of this boundary
					up.FireServer("becomeHostile")
					gui.hud.fight.Visible = false
					coroutine.resume(coroutine.create(function()
						smallNotice("You have become hostile for trying to escape the prison! Guards can legally kill you now!")
					end))
					
					break
				end
			end
		end
		
		if not dead and questLocation then
			if (char.Torso.Position - questLocation.Position).Magnitude > 20 then
				stopDialog()
			end
		end
		
		if not sealevelimmune and plyr.TeamColor.Name ~= "White" and char.Humanoid.Health > 0 and char and char:FindFirstChild("Torso") and char.Torso.Position.Y < workspace.minimumLevel.Position.Y then
			if not dippedbelowsealevel then
				dippedbelowsealevel = curTick
			end
			
			coroutine.resume(coroutine.create(function()
				smallNotice("You are too low! You will be killed if you do not go above the map.")
			end))
			
			if curTick - dippedbelowsealevel > 5 then
				--//kill
				up.FireServer("killMeNOW")
				dippedbelowsealevel = -100--to prevent from firing twice dumbass
			end
		else
			dippedbelowsealevel = nil
		end
		
		--//vehicle
		if driveType == "quad" and allowFlip and currentCar and seat then
			local topCf = seat.CFrame * CFrame.new(0, 1, 0)
			
			if topCf.y < seat.Position.Y then
				--it is turned upside down
				if not lastFlipCheck then
					lastFlipCheck = tick()
				elseif tick() - lastFlipCheck > 2 then--after about X seconds turned over it will flip
					--flip!
					print("flipping car!")
					up.FireServer("flipCar", currentCar)
					lastFlipCheck = nil
				end
			else
				lastFlipCheck = nil
			end
		end
	end
	
	--//vehicle update
	local vehicleInc = speedIncrease * step
	if tarSpeed < curSpeed then
		vehicleInc = speedDecrease * step
	end
	
	local diff = math.abs(tarSpeed - curSpeed)
	
	if vehicleInc > diff then
		vehicleInc = diff
	end
	
	if tarSpeed < curSpeed then
		vehicleInc = vehicleInc * -1
	end
	
	curSpeed = curSpeed + vehicleInc
	if driveType == "heli" then
		carVars.bPos.Position = carVars.bPos.Position + Vector3.new(0, curSpeed * step, 0)
		
		if carVars.forwardSpeed then
			carVars.bVel.Velocity = carVars.engine.CFrame.lookVector * carVars.forwardSpeed
		end
		
		--//rotation
		local turnInc = carVars.turnSpeed * step
		carVars.yaw = carVars.yaw + turnInc
		
		--CFrame.Angles(pitch, yaw, roll)
		carVars.bGyro.CFrame = CFrame.new(carVars.engine.Position) * CFrame.Angles(0, carVars.yaw, 0) * CFrame.Angles(carVars.pitch, 0, 0) * CFrame.Angles(0, 0, carVars.roll)
	else
		--//car
		updateWheelSpeed(curSpeed)
	end
	
	--//fps
	local fps = 1/step--1/(curTick-lastFpsTick)
	if not minFps or fps < minFps or curTick - fpsTime > 0.5 then
		minFps = fps
		fpsTime = curTick
	end
	gui.fpsLabel.Text = "Min FPS: "..math.floor(minFps + 0.5)
	lastFpsTick = curTick
end)




--//Misc Events
char.Humanoid.Died:connect(function()
	--//reset global libraries
	_G.gui = nil
	dead = true
	
	--//game
	if char:FindFirstChild("RiotShield") then
		char.RiotShield.Value:Destroy()
	end
end)

char.Humanoid.Changed:connect(function()
	local hum = char.Humanoid
	if hum.Jump then
		if allowJump then
			--//okay let him jump
		else
			hum.Jump = false
		end
	end
end)

local touchDebounce = 0--affects all if statements so if it is super crucial that this is accurate make a seperate debounce
local zapDebounce = false
local imHostile = false
function legTouched(part)
	if part then
		if part.Name == "zapChain" and not zapDebounce then
			zapDebounce = true
			
			up.FireServer("fenceZap", part)
			wait(2)
			
			zapDebounce = false
		elseif (part.Name == "armoryBarrier" or part.Name == "heliBarrier") and not imHostile and plyr.TeamColor.Name ~= "Bright blue" then
			imHostile = true
			up.FireServer("becomeHostile")
			smallNotice("You entered a restricted area! You are now hostile!")
		elseif part.Name == "ammoCrate" and tick() - touchDebounce > 1 then
			touchDebounce = tick()
			fillAmmo()
		elseif part.Name == "removeHats" and tick() - lastHatRemoval > 1 then
			lastHatRemoval = tick()
			up.FireServer("removeHats")
		elseif part.Name == "doorTouch" and part:FindFirstChild("doorTag") and tick() - touchDebounce > 1 then
			local doorSystem = part.doorTag.Value
			if doorSystem.IsOpen.Value == false then
				touchDebounce = tick()
				attemptOpenDoor(doorSystem.doorSystemButton, true)
			end
		end
	end
end

--char:WaitForChild("Left Leg").Touched:connect(legTouched)
char:WaitForChild("Right Leg").Touched:connect(legTouched)

--//Input Events
function keyDown(keyCode, gameProccessedEvent)
	if isTyping or gameProccessedEvent then
		return
	end
	
	if keyCode == Enum.KeyCode.Slash and not _G.preventTyping and up.customChat then
		--//slash key, chat
		chatInput:CaptureFocus()
	elseif keyCode == Enum.KeyCode.R then
		reload()
	end
	
	if driving then
		if keyCode == Enum.KeyCode.Q or keyCode == Enum.KeyCode.E then
			vehicleKeyDown(keyCode)
		end
	end
	
	if curSecCam then
		if keyCode == Enum.KeyCode.W then
			rotateSecCam(0, 1)
		elseif keyCode == Enum.KeyCode.S then
			rotateSecCam(0, -1)
		elseif keyCode == Enum.KeyCode.A then
			rotateSecCam(1, 0)
		elseif keyCode == Enum.KeyCode.D then
			rotateSecCam(-1, 0)
		end
	end
	if keyCode == Enum.KeyCode.C then
		toggleCrouch()
	elseif keyCode == Enum.KeyCode.Equals and tick() - lastHatRemoval > 1 then
		lastHatRemoval = tick()
		up.FireServer("removeHats")
	elseif keyCode == Enum.KeyCode.LeftShift then
		newMovable("changeFov", {
			["tar"] = 80,
		})
		if latestChangyChange > 4 then
			_G.changyChange(latestChangyChange + 4)
		end
	end
end

function keyUp(keyCode, gameProccessedEvent)
	if gameProccessedEvent then
		return--typing
	end
	
	if driving then
		if keyCode == Enum.KeyCode.Q or keyCode == Enum.KeyCode.E then
			vehicleKeyUp(keyCode)
		end
	end
	if keyCode == Enum.KeyCode.LeftShift then
		newMovable("changeFov", {
			["tar"] = 70,
		})
		if latestChangyChange > 16 then
			_G.changyChange(latestChangyChange - 4)
		end
	end
end

inputService.InputBegan:connect(function(inputObject, gameProccessedEvent)
	keyDown(inputObject.KeyCode, gameProccessedEvent)
end)
inputService.InputEnded:connect(function(inputObject, gameProccessedEvent)
	keyUp(inputObject.KeyCode, gameProccessedEvent)
end)
mouse.Button1Down:connect(b1Down)
mouse.Button1Up:connect(b1Up)
mouse.Button2Down:connect(b2Down)
mouse.Button2Up:connect(b2Up)
mouse.Move:connect(function()
	local sniperScope = gui.sniperScope
	
	if sniperScope.Visible then
		local x, y = mouse.X, mouse.Y
		local s = sniperScope.AbsoluteSize
		sniperScope.Position = UDim2.new(0, x-s.X/2, 0, y-s.Y/2)
	end
end)

--//Main
--//Prep chat from last life
for i = #_G.chatLog, 1, -1 do
	local v = _G.chatLog[i]
	addMessage(v[1], v[2], v[3], v[4], true)
end
if _G.unfinishedChat then
	chatInput:CaptureFocus()
end

--[[
for i = 1,6 do
	up.InvokeServer("giveItem", "gun"..i)
end
]]
--[[
for n,v in pairs({"AK47", "SPAS-12","M16", "Beretta M9","M60"}) do
	up.InvokeServer("giveItem", v)
end
]]
if plyr.TeamColor.Name == "Bright blue" then
	--//cops
	for n,v in pairs({"Taser", "Handcuffs", "Beretta M9"}) do
		up.InvokeServer("giveItem", v)
	end
	
	local taskFrame = gui.copTask
	taskFrame.Visible = true
elseif plyr.TeamColor.Name == "Bright red" then
	--//prep criminal gui
	local fightBut = gui.hud.fight
	fightBut.Visible = true
	fightBut.MouseButton1Click:connect(function()
		fightBut.Visible = false
		up.FireServer("becomeHostile")
		smallNotice("You are now hostile! Guards can legally kill you now!")
	end)
end
if plyr.TeamColor.Name == "Bright red" or plyr.TeamColor.Name == "Bright yellow" then
	local shankBut = gui.hud.shank
	shankBut.Visible = true
	shankBut.MouseButton1Click:connect(function()
		market:PromptProductPurchase(plyr, 33755576)
	end)
end

if _G.deathCleanUp then
	for n,v in pairs(_G.deathCleanUp) do
		local a, b = pcall(function()
			if v and v.Parent then
				v:Destroy()
			end
		end)
	end
end
_G.deathCleanUp = {}--items to destroy on death

--//declare if you want
local textDisplay = workspace.AllMovables.TextDisplay
textDisplay.prompt.msg.Changed:connect(function()
	updateTextReader(textDisplay)
end)

function menuSetUpForChoosingRoles()
	char:WaitForChild("Torso")--ayy
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CoordinateFrame = workspace.introCam.CFrame
	gui.intro.Visible = false
	
	wait(2)
	displayRoles()
end

if not _G.firstSpawnFinished then
	addMessage("[ Server ]", "Upsilon library loaded. Client ready.", nil, 6)
	
	--//update door states
	for n,v in pairs(workspace.AllDoors:GetChildren()) do
		updateDoorSystem(v)
	end
	
	--//update camera rotations
	for n,v in pairs(workspace.AllMovables.SecurityCams:GetChildren()) do
		updateSecurityCamRotation(v)
	end
	
	updateTextReader(textDisplay)
	
	--//hide shit
	for n,v in pairs(prisonBoundaries:GetChildren()) do
		v.Transparency = 1
	end
	for n,v in pairs(workspace.ignore.invisibleWalls:GetChildren()) do
		v.Transparency = 1
	end
	
	--//intro
	workspace.introCam.Transparency = 1
	
	if plyr.TeamColor.Name == "White" then
		menuSetUpForChoosingRoles()
	end
	
	_G.firstSpawnFinished = true
else
	fixCamera()--JUST IN CASE DIGGITy
	
	if plyr.TeamColor.Name == "White" then--for if they return to menu
		menuSetUpForChoosingRoles()
	end
end

print(tick() - ClientTick)
