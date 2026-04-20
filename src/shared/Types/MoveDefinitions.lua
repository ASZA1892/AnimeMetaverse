-- src/shared/Types/MoveDefinitions.lua
-- Central definition of all physical combat moves
-- Includes context-aware FindMoveByInput

local Constants = require(script.Parent.constants)
local MoveDefinitions = {}

local function createMove(id, data)
	data.id = id
	data.damage = tonumber(data.damage) or 0
	data.hitboxSize = data.hitboxSize or Vector3.new(1, 1, 1)
	data.range = tonumber(data.range) or 1
	data.cooldown = tonumber(data.cooldown) or 0.3
	data.knockback = tonumber(data.knockback) or 0
	if data.slow and type(data.slow) == "table" then
		data.slow.percent = tonumber(data.slow.percent) or 1
		data.slow.duration = tonumber(data.slow.duration) or 0
	end
	return data
end

MoveDefinitions.Moves = {
	-- === MULTI-KEY / CONTEXTUAL MOVES FIRST ===
	Dropkick = createMove("Dropkick", {
		input = { E = true, Sprint = true, Space = true },
		requiresSprint = true,
		damage = 18,
		hitboxSize = Vector3.new(6, 4, 8),
		range = 8,
		cooldown = 0.7,
		knockback = 18,
		lunge = 6,
	}),

	Stomp = createMove("Stomp", {
		input = { E = true, Space = true },
		requiresAirborne = true,
		damage = 20,
		hitboxSize = Vector3.new(6, 3, 6),
		range = 4,
		cooldown = 0.6,
		knockback = 5,
		groundBounce = true,
	}),

	Roundhouse = createMove("Roundhouse", {
		input = { E = true, A = true },
		damage = 15,
		hitboxSize = Vector3.new(7, 4, 5),
		range = 5.5,
		cooldown = 0.45,
		knockback = 7,
		stun = 0.8,
	}),

	LowKick = createMove("LowKick", {
		input = { E = true, Crouch = true },
		damage = 8,
		hitboxSize = Vector3.new(6, 2, 5),
		range = 5,
		cooldown = 0.3,
		knockback = 2,
		slow = { percent = 0.7, duration = 2.0 },
	}),

	Cross = createMove("Cross", {
		input = { M1 = true, W = true },
		damage = Constants.CROSS_DAMAGE,
		hitboxSize = Vector3.new(6, 4, 7),
		range = 6,
		cooldown = 0.35,
		knockback = 8,
		lunge = 3,
		stun = 0,
	}),

	Hook = createMove("Hook", {
		input = { M1 = true, A = true },
		damage = Constants.HOOK_DAMAGE,
		hitboxSize = Vector3.new(7, 4, 5),
		range = 5,
		cooldown = 0.35,
		knockback = 4,
		stagger = true,
		stun = 0.2,
	}),

	Uppercut = createMove("Uppercut", {
		input = { M1 = true, S = true },
		damage = Constants.UPPERCUT_DAMAGE,
		hitboxSize = Vector3.new(5, 5, 5),
		range = 5,
		cooldown = 0.35,
		knockback = 5,
		launch = true,
		launchPower = 25,
	}),

	BodyShot = createMove("BodyShot", {
		input = { M1 = true, Crouch = true },
		damage = 12,
		hitboxSize = Vector3.new(5, 3, 5),
		range = 4.5,
		cooldown = 0.3,
		knockback = 3,
		slow = { percent = 0.8, duration = 1.5 },
	}),

	ElbowStrike = createMove("ElbowStrike", {
		input = { M1 = true, Q = true },
		requiresDash = true,
		damage = 16,
		hitboxSize = Vector3.new(5, 4, 5),
		range = 4,
		cooldown = 0.5,
		knockback = 6,
		stun = 0.5,
	}),

	Backfist = createMove("Backfist", {
		input = { M1 = true, S = true },
		damage = 8,
		hitboxSize = Vector3.new(5, 4, 5),
		range = 4,
		cooldown = 0.25,
		knockback = 3,
		behind = true,
	}),

	-- === SINGLE-KEY MOVES (fallbacks) ===
	FrontKick = createMove("FrontKick", {
		input = { E = true },
		damage = 12,
		hitboxSize = Vector3.new(5, 4, 7),
		range = 6,
		cooldown = 0.4,
		knockback = 10,
		pushback = true,
	}),

	KneeStrike = createMove("KneeStrike", {
		input = { E = true },
		requiresClose = true,
		damage = 12,
		hitboxSize = Vector3.new(4, 4, 4),
		range = 3.5,
		cooldown = 0.35,
		knockback = 5,
		haltMomentum = true,
	}),

	Jab = createMove("Jab", {
		input = { M1 = true },
		damage = Constants.JAB_DAMAGE,
		hitboxSize = Constants.JAB_HITBOX,
		range = Constants.JAB_RANGE,
		cooldown = Constants.ATTACK_COOLDOWN,
		knockback = 5,
	}),

	GuardBreak = createMove("GuardBreak", {
		input = { M2 = true },
		damage = Constants.GUARD_BREAK_DAMAGE,
		hitboxSize = Vector3.new(5, 4, 6),
		range = 5,
		cooldown = 0.8,
		knockback = 12,
		unblockable = true,
		windup = 0.8,
	}),

	SpinningBackKick = createMove("SpinningBackKick", {
		input = { E = true },
		damage = 17,
		hitboxSize = Vector3.new(5, 4, 6),
		range = 5.5,
		cooldown = 0.6,
		knockback = 15,
		stun = 0.3,
	}),
}

function MoveDefinitions.GetMove(id)
	return MoveDefinitions.Moves[id]
end

-- Context‑aware, specificity‑sorted matcher
function MoveDefinitions.FindMoveByInput(inputTable, context)
	context = context or {}

	-- Build a list of moves with a specificity score
	local list = {}
	for id, move in pairs(MoveDefinitions.Moves) do
		local req = move.input or {}
		local keyCount = 0
		for _, v in pairs(req) do
			if v then keyCount = keyCount + 1 end
		end

		-- Context requirements add extra weight
		local contextWeight = 0
		if move.requiresClose then contextWeight = contextWeight + 2 end
		if move.requiresAirborne then contextWeight = contextWeight + 2 end
		if move.requiresSprint or move.requiresDash then contextWeight = contextWeight + 1 end

		table.insert(list, {
			id = id,
			move = move,
			score = keyCount + contextWeight,
		})
	end

	-- Sort: higher score first, then more keys, then by id for stability
	table.sort(list, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		local aKeys = 0
		local bKeys = 0
		for _, v in pairs(a.move.input or {}) do if v then aKeys = aKeys + 1 end end
		for _, v in pairs(b.move.input or {}) do if v then bKeys = bKeys + 1 end end
		if aKeys ~= bKeys then return aKeys > bKeys end
		return a.id < b.id
	end)

	-- Helper to check contextual requirements
	local function contextSatisfied(move)
		if move.requiresClose and not context.isClose then return false end
		if move.requiresAirborne and not context.isAirborne then return false end
		if move.requiresSprint and not context.isSprinting then return false end
		if move.requiresDash and not context.isDashing then return false end
		return true
	end

	-- Find first move that matches input and context
	for _, entry in ipairs(list) do
		local move = entry.move
		local required = move.input or {}
		local match = true
		for key, val in pairs(required) do
			if val == true and not inputTable[key] then
				match = false
				break
			end
		end
		if match and contextSatisfied(move) then
			return move
		end
	end

	return nil
end

return MoveDefinitions