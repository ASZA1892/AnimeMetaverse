-- src/client/Animations/AnimationLoader.client.lua
-- Safe animation loader with R15/R6 fallback and placeholder IDs

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationLoader = {}

-- Placeholder animation IDs — replace with custom animations before launch
local ANIMATION_IDS = {
	Jab              = "rbxassetid://139623620775725",
	Cross            = "rbxassetid://522635514",
	Hook             = "rbxassetid://180435571",
	Uppercut         = "rbxassetid://522635514",
	BodyShot         = "rbxassetid://180435571",
	ElbowStrike      = "rbxassetid://522635514",
	Backfist         = "rbxassetid://180435571",
	FrontKick        = "rbxassetid://522635514",
	Roundhouse       = "rbxassetid://180435571",
	LowKick          = "rbxassetid://180435571",
	Dropkick         = "rbxassetid://522635514",
	Stomp            = "rbxassetid://180435571",
	SpinningBackKick = "rbxassetid://522635514",
	KneeStrike       = "rbxassetid://180435571",
	GuardBreak       = "rbxassetid://522635514",
}

local CombatActions
local ok, result = pcall(function()
	return require(ReplicatedStorage.Shared.Types.CombatActions)
end)
if ok and result then
	CombatActions = result
else
	warn("[AnimationLoader] CombatActions module missing; using fallback string.")
end

local player = Players.LocalPlayer

local function getLocalCharacter()
	return player.Character or player.CharacterAdded:Wait()
end

local function getOrCreateAnimationObject(moveId)
	-- Always use our defined IDs first — never pull from character
	local placeholderId = ANIMATION_IDS[moveId]
	if placeholderId then
		local animObj = Instance.new("Animation")
		animObj.AnimationId = placeholderId
		animObj.Name = moveId
		return animObj
	end

	-- Only fall back to ReplicatedStorage folder if no ID defined
	local animationsFolder = ReplicatedStorage:FindFirstChild("Animations")
	if animationsFolder then
		local fromFolder = animationsFolder:FindFirstChild(moveId)
		if fromFolder and fromFolder:IsA("Animation") then
			return fromFolder
		end
	end

	return nil
end

local function safeLoadAndPlay(moveId)
	local character = getLocalCharacter()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid")
	if not humanoid then return false end

	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local animator = humanoid:FindFirstChildOfClass("Animator")

	local animObject = getOrCreateAnimationObject(moveId)
	if not animObject then
		print("[AnimationLoader] No animation found for:", moveId)
		return false
	end

	if isR15 and not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Stop currently playing action tracks only
	local okTracks, playingTracks = pcall(function()
		return humanoid:GetPlayingAnimationTracks()
	end)
	if okTracks and playingTracks then
		for _, track in ipairs(playingTracks) do
			if track.Priority == Enum.AnimationPriority.Action then
				pcall(function() track:Stop(0.05) end)
			end
		end
	end

	task.wait(0.03)

	local okLoad, track = pcall(function()
		if isR15 and animator then
			return animator:LoadAnimation(animObject)
		end
		return humanoid:LoadAnimation(animObject)
	end)

	if not okLoad or not track then
		warn("[AnimationLoader] Failed to load animation for:", moveId)
		return false
	end

	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.05)

	print(string.format("[AnimationLoader] Playing animation for: %s | ID: %s",
		tostring(moveId),
		tostring(animObject.AnimationId)
	))
	return true
end

function AnimationLoader.playAttackAnimation(moveId)
	if not moveId then return end
	safeLoadAndPlay(moveId)
end

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote")
CombatRemote.OnClientEvent:Connect(function(action, data)
	local hitAction = (CombatActions
		and CombatActions.ServerToClient
		and CombatActions.ServerToClient.HIT_CONFIRMED)
		or "HitConfirmed"

	if action == hitAction and data then
		local attacker = data.attacker
		local attackerIsLocal = attacker == player
			or attacker == player.Character
			or (type(attacker) == "number" and attacker == player.UserId)
			or (type(attacker) == "string" and attacker == player.Name)
		if attackerIsLocal then
			AnimationLoader.playAttackAnimation(data.moveId)
		end
	end
end)

print("✅ AnimationLoader initialized (safe mode)")

return AnimationLoader