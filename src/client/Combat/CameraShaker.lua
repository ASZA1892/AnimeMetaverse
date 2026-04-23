local RunService = game:GetService("RunService")

local CameraShaker = {}

local DEFAULT_FREQUENCY = 20
local MAX_POSITION_OFFSET = 0.3
local MAX_ROTATION_OFFSET = math.rad(1.5)
local EPSILON = 1e-4

local activeShakes = {}
local heartbeatConnection = nil

local lastCamera = nil
local lastOffset = nil
local expectedAppliedCFrame = nil

local randomGenerator = Random.new()

local function cframeClose(a, b)
	if (a.Position - b.Position).Magnitude > EPSILON then
		return false
	end

	local lookDot = a.LookVector:Dot(b.LookVector)
	local upDot = a.UpVector:Dot(b.UpVector)
	return lookDot > (1 - EPSILON) and upDot > (1 - EPSILON)
end

local function sampleNoise(seed, elapsed, frequency)
	-- math.noise is smooth but bounded, ideal for camera shake oscillation.
	return math.noise(seed, elapsed * frequency, 0) * 2
end

local function updateSpring(shake, dt)
	local x = shake.springValue
	local v = shake.springVelocity
	local omega = shake.springOmega

	local acceleration = -2 * omega * v - (omega * omega) * x
	v = v + (acceleration * dt)
	x = x + (v * dt)

	if x < 0 then
		x = 0
		v = 0
	end

	shake.springValue = x
	shake.springVelocity = v
end

local function tryRestorePreviousOffset(camera)
	if lastCamera ~= camera or not lastOffset or not expectedAppliedCFrame then
		return
	end

	-- Remove only if the camera still matches our last applied value.
	if cframeClose(camera.CFrame, expectedAppliedCFrame) then
		camera.CFrame = camera.CFrame * lastOffset:Inverse()
	end
end

local function clearAppliedState()
	lastCamera = nil
	lastOffset = nil
	expectedAppliedCFrame = nil
end

local function stopIfIdle()
	if #activeShakes == 0 and heartbeatConnection then
		local camera = workspace.CurrentCamera
		if camera then
			tryRestorePreviousOffset(camera)
		end

		clearAppliedState()
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

local function onHeartbeat(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	tryRestorePreviousOffset(camera)
	local baseCFrame = camera.CFrame

	local now = os.clock()
	local totalPosition = Vector3.zero
	local totalRotation = Vector3.zero

	local i = 1
	while i <= #activeShakes do
		local shake = activeShakes[i]
		local elapsed = now - shake.startTime

		if elapsed >= shake.duration then
			table.remove(activeShakes, i)
		else
			updateSpring(shake, dt)

			local amplitude = shake.intensity * shake.springValue
			local nx = sampleNoise(shake.posSeeds[1], elapsed, shake.frequency)
			local ny = sampleNoise(shake.posSeeds[2], elapsed, shake.frequency)
			local nz = sampleNoise(shake.posSeeds[3], elapsed, shake.frequency)
			local rx = sampleNoise(shake.rotSeeds[1], elapsed, shake.frequency)
			local ry = sampleNoise(shake.rotSeeds[2], elapsed, shake.frequency)
			local rz = sampleNoise(shake.rotSeeds[3], elapsed, shake.frequency)

			totalPosition = totalPosition + (Vector3.new(nx, ny, nz) * (MAX_POSITION_OFFSET * amplitude))
			totalRotation = totalRotation + (Vector3.new(rx, ry, rz) * (MAX_ROTATION_OFFSET * amplitude))

			i = i + 1
		end
	end

	if #activeShakes == 0 then
		clearAppliedState()
		stopIfIdle()
		return
	end

	local offset = CFrame.new(totalPosition) * CFrame.Angles(totalRotation.X, totalRotation.Y, totalRotation.Z)
	local applied = baseCFrame * offset
	camera.CFrame = applied

	lastCamera = camera
	lastOffset = offset
	expectedAppliedCFrame = applied
end

local function ensureHeartbeat()
	if heartbeatConnection then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
end

function CameraShaker.Shake(intensity, duration, frequency)
	local safeIntensity = math.clamp(tonumber(intensity) or 0, 0, 1)
	local safeDuration = math.max(0, tonumber(duration) or 0)
	local safeFrequency = math.max(0, tonumber(frequency) or DEFAULT_FREQUENCY)

	if safeIntensity <= 0 or safeDuration <= 0 then
		return
	end

	local shake = {
		startTime = os.clock(),
		duration = safeDuration,
		intensity = safeIntensity,
		frequency = safeFrequency,
		springValue = 1,
		springVelocity = 0,
		-- ~1-2% remaining by the end of duration for smooth fade.
		springOmega = 6 / safeDuration,
		posSeeds = {
			randomGenerator:NextNumber(0, 1000),
			randomGenerator:NextNumber(0, 1000),
			randomGenerator:NextNumber(0, 1000),
		},
		rotSeeds = {
			randomGenerator:NextNumber(0, 1000),
			randomGenerator:NextNumber(0, 1000),
			randomGenerator:NextNumber(0, 1000),
		},
	}

	table.insert(activeShakes, shake)
	ensureHeartbeat()
end

return CameraShaker
