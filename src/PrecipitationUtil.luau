--!strict
--[=[
	--This script contains code copyrighted by boatbomber 2022--
	--Given under a MPL 2.0 License--
		Explanation of license: https://tldrlegal.com/license/mozilla-public-license-2.0-(mpl-2)
	--You can access the original code here: https://github.com/boatbomber/Distortion-Screen-Rain
--]=]

-- Services
local Debris = game:GetService("Debris")

-- Packages
local Package = script.Parent
assert(Package)
local Packages = Package.Parent
assert(Packages)
local Maid = require(Packages:WaitForChild("Maid"))
local Signal = require(Packages:WaitForChild("Signal"))
local GeometryUtil = require(Packages:WaitForChild("GeometryUtil"))
local InstancePool = require(Packages:WaitForChild("InstancePool"))

-- Modules

-- Constants
local EMPTY_VEC = Vector3.new(0, 0, 0)
local GLASS_ENABLED = true
local DROPLET_DIAMETER = 0.06 * 0.5
local DROPLET_DIAMETER_RANGE = DROPLET_DIAMETER * 0.85
local EXTRUSION_COUNT = 4
local MAX_SPAWN_RATE = 10
local DROPLET_COLOR = Color3.fromRGB(226, 244, 255)
local FADE_DURATION = 1.5
local STRETCH_WEIGHT = 2
local FADE_DURATION_RANGE = FADE_DURATION * 0.5
local DEBUG_PRECIPITATION_EMITTERS = false

-- Types
type Maid = Maid.Maid
type Signal = Signal.Signal
type InstancePool = InstancePool.InstancePool

export type Droplet = {
	Instance: BasePart,
	Offset: CFrame,
	StartTick: number,
	Scale: number,
	Stretch: number,
	Duration: number,
	Mesh: SpecialMesh,
}

-- References
local WeatherParticles = Package:WaitForChild("Library"):WaitForChild("Weather") :: Folder
local RainParticles = WeatherParticles:WaitForChild("Rain") :: Folder
local SnowParticles = WeatherParticles:WaitForChild("Snow") :: Folder
local SplashParticles = WeatherParticles:WaitForChild("Splash") :: Folder
local HailParticles = WeatherParticles:WaitForChild("Hail") :: Folder
local RainSound = Package:WaitForChild("Library"):WaitForChild("Sound"):WaitForChild("Rain") :: Sound

-- Class
local PrecipitationUtil = {}
PrecipitationUtil.__index = PrecipitationUtil

function PrecipitationUtil.getRainDrop(): BasePart
	local main = Instance.new("Part")
	main.Name = "Droplet"
	main.Material = Enum.Material.Glass
	main.CastShadow = false
	main.CanCollide = false
	main.CanQuery = false
	main.CanTouch = false
	main.Anchored = true
	main.Locked = true
	main.Transparency = 0.5
	main.Color = DROPLET_COLOR
	main.Size = Vector3.new(1, 1, 1)

	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "Mesh"
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = main

	return main
end

--Creates a random droplet on screen
local function spawnDroplet(dropletPool: InstancePool, droplets: { [BasePart]: Droplet }, parent: Instance): nil
	local scale = DROPLET_DIAMETER
		+ (
			math.random(DROPLET_DIAMETER * 10 * -DROPLET_DIAMETER_RANGE, DROPLET_DIAMETER * 10 * DROPLET_DIAMETER_RANGE)
			/ 10
		)

	local main = dropletPool:Get() :: BasePart
	main.Color = DROPLET_COLOR
	main.Transparency = 0.7

	local mesh = main:FindFirstChildOfClass("SpecialMesh")
	assert(mesh ~= nil)
	mesh.Scale = Vector3.new(1, 1, 1) * scale
	mesh.Offset = EMPTY_VEC

	local droplet: Droplet = {
		["Instance"] = main,
		Offset = CFrame.new(math.random(-120, 120) / 100, math.random(-100, 100) / 100, -1),
		StartTick = tick(),
		Scale = scale,
		Duration = FADE_DURATION - FADE_DURATION_RANGE * 0.5 + math.random() * FADE_DURATION_RANGE,
		Stretch = (math.random(5, 10) / 10) * scale,
		Mesh = mesh,
	}
	droplets[droplet.Instance] = droplet
	main.Parent = parent

	--Create droplet extrusions
	for _ = 1, math.random(EXTRUSION_COUNT) do
		local extrusionScale = (droplet.Scale / 1.5)
			+ (math.random((droplet.Scale / 3) * -100, (droplet.Scale / 3) * 100) / 100)

		local extrusion = dropletPool:Get() :: BasePart
		extrusion.Color = DROPLET_COLOR
		extrusion.Transparency = 0.7

		local extrusionMesh = extrusion:FindFirstChildOfClass("SpecialMesh")
		assert(extrusionMesh ~= nil)

		extrusionMesh.Scale = Vector3.new(extrusionScale, extrusionScale, extrusionScale)
		extrusionMesh.Offset = EMPTY_VEC

		local e2 = extrusionScale * 60
		local extrusionDroplet: Droplet = {
			["Instance"] = extrusion,
			Offset = droplet.Offset * CFrame.new(math.random(-e2, e2) / 100, math.random(-e2, e2) / 100, 0),
			StartTick = tick(),
			Scale = extrusionScale,
			Duration = 0.9 * droplet.Duration,
			Stretch = STRETCH_WEIGHT * (math.random(5, 10) / 10) * extrusionScale,
			Mesh = extrusionMesh,
		}
		extrusion.Parent = parent

		droplets[extrusionDroplet.Instance] = extrusionDroplet
	end
	return nil
end

function PrecipitationUtil.stepCameraDroplets(
	deltaTime: number,
	dropletPool: InstancePool,
	droplets: { [BasePart]: Droplet },
	cameraCFrame: CFrame,
	spawnChance: number,
	isUnderCover: boolean,
	timeSpeed: number,
	spawnWeight: number,
	parent: Instance
): number
	local now = tick()
	for inst: BasePart, droplet: Droplet in pairs(droplets) do
		local startClock = droplet.StartTick

		local elapsed = (now - startClock) * timeSpeed
		if elapsed >= FADE_DURATION then
			droplets[inst] = nil
			dropletPool:Reset(inst)
			continue
		end

		local mesh, scale, stretch = droplet.Mesh, droplet.Scale, droplet.Stretch
		local alpha = (elapsed / FADE_DURATION)
		local quint = alpha * alpha * alpha * alpha
		local y = scale + (stretch * quint)

		inst.Transparency = 0.7 + (0.3 * (alpha * alpha))

		mesh.Scale = Vector3.new(scale, y, scale)
		mesh.Offset = Vector3.new(0, y / -2, 0)
	end

	-- Spawn new drops
	if GLASS_ENABLED and cameraCFrame.LookVector.Y > -0.4 and not isUnderCover then
		spawnChance += deltaTime * spawnWeight * MAX_SPAWN_RATE

		for i = 1, math.floor(spawnChance) do
			spawnDroplet(dropletPool, droplets, parent)
		end

		spawnChance %= 1
	else
		spawnChance %= 1
	end

	-- Animate
	local dropletCF = {}
	local parts = {}

	local dropletCount = 0
	for inst: BasePart, droplet: Droplet in pairs(droplets) do
		dropletCount += 1
		dropletCF[dropletCount] = cameraCFrame * droplet.Offset
		parts[dropletCount] = inst
	end

	workspace:BulkMoveTo(parts, dropletCF, Enum.BulkMoveMode.FireCFrameChanged)

	return spawnChance
end

export type PrecipitationEmitterTypeData = {
	ParticleEmitters: { [number]: ParticleEmitter },
	ImpactParticleEmitters: { [number]: ParticleEmitter },
	ImpactSounds: { [Enum.Material]: Sound },
	Weight: number,
}

export type PrecipitationEmitter = {
	Instance: BasePart,
	SoundEmitter: Attachment,
	Angle: GeometryUtil.Radian,
	Area: number,
	Height: number,
	Distance: number,
	Scale: number,
	Layer: number,
	Enabled: boolean,
	Types: {
		Rain: PrecipitationEmitterTypeData,
		Snow: PrecipitationEmitterTypeData,
		Hail: PrecipitationEmitterTypeData,
	},
}

function PrecipitationUtil.destroyPrecipitationEmitter(precipitationEmitter: PrecipitationEmitter): nil
	for k, data: PrecipitationEmitterTypeData in pairs(precipitationEmitter.Types) do
		for _, particle in pairs(data.ParticleEmitters) do
			Debris:AddItem(particle)
		end
	end
	Debris:AddItem(precipitationEmitter.SoundEmitter)
	Debris:AddItem(precipitationEmitter.Instance)
	return nil
end

function PrecipitationUtil.newPrecipitationEmitter(parent: Instance): PrecipitationEmitter
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Locked = true
	part.Transparency = 1
	part.Parent = parent

	local soundAttachment = Instance.new("Attachment")

	local function newParticle(template: ParticleEmitter)
		local particle = template:Clone()
		particle.Parent = part
		return particle
	end

	return {
		["Instance"] = part,
		SoundEmitter = soundAttachment,
		Angle = 0,
		Area = 1,
		Layer = 0,
		Height = 1,
		Distance = 1,
		Scale = 1,
		Enabled = false,
		Types = {
			Rain = {
				ParticleEmitters = {
					newParticle(RainParticles:WaitForChild("Single") :: ParticleEmitter),
					-- newParticle(RainParticles:FindFirstChild("Cluster")),
				},
				ImpactParticleEmitters = {
					SplashParticles:WaitForChild("Spray") :: ParticleEmitter,
					SplashParticles:WaitForChild("Ripple") :: ParticleEmitter,
				},
				ImpactSounds = {
					[Enum.Material.SmoothPlastic] = RainSound,
				},
				Weight = 0,
			},
			Snow = {
				ParticleEmitters = {
					newParticle(SnowParticles:WaitForChild("Flurry") :: ParticleEmitter),
				},
				ImpactParticleEmitters = {},
				ImpactSounds = {},
				Weight = 0,
			},
			Hail = {
				ParticleEmitters = {
					newParticle(HailParticles:WaitForChild("Single") :: ParticleEmitter),
				},
				ImpactParticleEmitters = {},
				ImpactSounds = {},
				Weight = 0,
			},
		},
	}
end

function PrecipitationUtil.getPointsInArea(
	precipitationEmitter: PrecipitationEmitter,
	count: number
): { [number]: Vector3 }
	local points = {}
	local cf = precipitationEmitter.Instance.CFrame * CFrame.new(-precipitationEmitter.Instance.Size * 0.5)
	for i = 1, count do
		local x = math.random() * precipitationEmitter.Instance.Size.X
		local z = math.random() * precipitationEmitter.Instance.Size.Z
		table.insert(points, (cf * CFrame.new(x, 0, z)).Position)
	end
	return points
end

function PrecipitationUtil.updatePrecipitationEmitter(
	cameraCFrame: CFrame,
	precipitationEmitter: PrecipitationEmitter,
	timeSpeed: number
)
	-- update geometry
	local basePosition = (CFrame.Angles(0, precipitationEmitter.Angle, 0) * CFrame.new(
		0,
		precipitationEmitter.Height,
		-precipitationEmitter.Distance + precipitationEmitter.Instance.Size.Z / 2
	) + cameraCFrame.Position).Position

	precipitationEmitter.Instance.CFrame =
		CFrame.new(basePosition, Vector3.new(cameraCFrame.Position.X, basePosition.Y, cameraCFrame.Position.Z))

	if DEBUG_PRECIPITATION_EMITTERS then
		precipitationEmitter.Instance.Transparency = 0.5
		if precipitationEmitter.Enabled then
			precipitationEmitter.Instance.Color = Color3.new(0, 1, 1)
		else
			precipitationEmitter.Instance.Color = Color3.new(1, 0, 0)
		end
	end

	-- update specific emitters
	for k, emitterData: PrecipitationEmitterTypeData in pairs(precipitationEmitter.Types) do
		for i, emitter in ipairs(emitterData.ParticleEmitters) do
			emitter.Enabled = precipitationEmitter.Enabled
			emitter.Rate = if precipitationEmitter.Enabled
				then
					(
						precipitationEmitter.Area
						* emitter:GetAttribute("BaseRate")
						* emitterData.Weight
						* 0.5 ^ (precipitationEmitter.Layer - 1)
					) / precipitationEmitter.Scale
				else 0

			local baseSize: NumberSequence = emitter:GetAttribute("BaseSize")

			local keypoints: { [number]: NumberSequenceKeypoint } = {}
			for j, keypoint in ipairs(baseSize.Keypoints) do
				keypoints[j] = NumberSequenceKeypoint.new(
					keypoint.Time,
					keypoint.Value * precipitationEmitter.Scale,
					keypoint.Envelope * precipitationEmitter.Scale
				)
			end
			emitter.Size = NumberSequence.new(keypoints)
			emitter.TimeScale = timeSpeed
		end
		-- for i, sound in ipairs(emitterData.Sounds) do
		-- 	sound.Volume = if precipitationEmitter.Enabled then sound:GetAttribute("BaseVolume") * emitterData.Weight else 0
		-- end
	end
end

-- function PrecipitationUtil.impactGround(
-- 	precipitationEmitter: PrecipitationEmitter,
-- 	position: Vector3,
-- 	normal: Vector3,
-- 	groundMaterial: Enum.Material
-- )
-- 	local vec = _Draw.vector(position, normal, Color3.new(1, 0, 0))
-- 	Debris:AddItem(vec)
-- end

return PrecipitationUtil
