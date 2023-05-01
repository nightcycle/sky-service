--!strict
-- Services
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

-- Packages
local Package = script
local Packages = Package.Parent
assert(Packages)
local Maid = require(Packages:WaitForChild("Maid"))
local Signal = require(Packages:WaitForChild("Signal"))
local ColdFusion = require(Packages:WaitForChild("ColdFusion"))
local PhysicsUtil = require(Packages:WaitForChild("PhysicsUtil"))
local CurveUtil = require(Packages:WaitForChild("CurveUtil"))
local GeometryUtil = require(Packages:WaitForChild("GeometryUtil"))
local ServiceProxy = require(Packages:WaitForChild("ServiceProxy"))
local InstancePool = require(Packages:WaitForChild("InstancePool"))

-- Modules
local PrecipitationUtil = require(script:WaitForChild("PrecipitationUtil"))

-- Constants
local RAIN_DROP_AMOUNT = 200
local UP_VECTOR = Vector3.new(0, 1, 0)
local PRECIPITATION_HEIGHT = 15
local EMITTER_ANGLE_SLICES = 8
local EMITTER_MAX_DISTANCE = 60
local EMITTER_LAYERS = 4
local EMITTER_MIN_RADIUS = 6
-- local MAX_IMPACTS_PER_SECOND = 1
local SCALE = 1
local UNIT_TO_METER = 1/3
local METERS_PER_UNIT = SCALE / UNIT_TO_METER
local CLOUD_COVER = 0.5
local INITIAL_TIME = 12
local SUN_INTENSITY = 0.5
local ATMOSPHERE_DENSITY = 0.5

-- Types
type AtmosphereData = {
	Fog: number,
	Hue: number,
	Brightness: number,
	Contrast: number,
	Saturation: number,
	CelestialAngle: number,
	[any]: nil,
}

type Maid = Maid.Maid
type Signal = Signal.Signal
type State<T> = ColdFusion.State<T>
type ValueState<T> = ColdFusion.ValueState<T>
type InstancePool = InstancePool.InstancePool
type Droplet = PrecipitationUtil.Droplet
type PrecipitationEmitter = PrecipitationUtil.PrecipitationEmitter
type PrecipitationEmitterTypeData = PrecipitationUtil.PrecipitationEmitterTypeData

export type SkyService = {
	__index: SkyService,
	_Maid: Maid,
	CoverageParams: ValueState<RaycastParams>,
	MetersPerUnit: ValueState<number>,
	Visibility: ValueState<number>,
	Temperature: ValueState<number>,
	TimeOfDay: ValueState<number>,
	TimeSpeed: ValueState<number>,
	Clouds: ValueState<number>,
	Brightness: ValueState<number>,
	LightDirection: ValueState<Vector3>,
	WindDirection: ValueState<Vector3>,
	WindSpeed: ValueState<PhysicsUtil.KilometersPerHour>,
	Rain: ValueState<number>,
	Scale: ValueState<number>,
	CoverageCheckDistance: ValueState<number>,
	Hail: ValueState<number>,
	Snow: ValueState<number>,
	Lightning: ValueState<number>,
	Enabled: ValueState<number>,
	Destroy: (self: SkyService) -> nil,
	new: () -> SkyService,
	init: (maid: Maid) -> nil,
}

local AtmosphereDataRegistry: { [number]: AtmosphereData } = {
	[0 / 24] = { --1 Midnight
		Fog = 0.6,
		Hue = 0.65,
		Brightness = 0.15,
		Contrast = 0.15,
		Saturation = 0.25,
		CelestialAngle = 0,
	},
	[3 / 24] = { --2 Early morning
		Fog = 0.6,
		Hue = 0.65,
		Brightness = 0.2,
		Contrast = 0.25,
		Saturation = 0.25,
		CelestialAngle = 0.25,
	},
	[5 / 24] = { --3 Early morning
		Fog = 0.6,
		Hue = 0.65,
		Brightness = 0.3,
		Contrast = 0.25,
		Saturation = 0.25,
		CelestialAngle = 0.5,
	},
	[6 / 24] = { --4 Dawn
		Fog = 0.6,
		Hue = 0.85,
		Brightness = 0.5,
		Contrast = 0.25,
		Saturation = 0.35,
		CelestialAngle = 0.8,
	},
	[8 / 24] = { --5 Sunrise
		Fog = 0.5,
		Hue = 0.99,
		Brightness = 0.7,
		Contrast = 0.25,
		Saturation = 0.5,
		CelestialAngle = 1,
	},
	[9 / 24] = { --6 Morning
		Fog = 0.4,
		Hue = 0.65,
		Brightness = 0.8,
		Contrast = 0.1,
		Saturation = 0.1,
		CelestialAngle = 0.8,
	},
	[12 / 24] = { --7 Noon
		Fog = 0.4,
		Hue = 0.625,
		Brightness = 1,
		Contrast = 0.05,
		Saturation = 0,
		CelestialAngle = 0.5,
	},
	[15 / 24] = { --8 Afternoon
		Fog = 0.4,
		Hue = 0.6,
		Brightness = 0.7,
		Contrast = 0.1,
		Saturation = 0.1,
		CelestialAngle = 0.85,
	},
	[16 / 24] = { --9 Sunset
		Fog = 0.5,
		Hue = 0.99,
		Brightness = 0.7,
		Contrast = 0.25,
		Saturation = 0.35,
		CelestialAngle = 0.93,
	},
	[18 / 24] = { --10 Dusk
		Fog = 0.6,
		Hue = 0.85,
		Brightness = 0.3,
		Contrast = 0.3,
		Saturation = 0.25,
		CelestialAngle = 1,
	},
	[19 / 24] = { --11 Night
		Fog = 0.6,
		Hue = 0.65,
		Brightness = 0.1,
		Contrast = 0.3,
		Saturation = 0.25,
		CelestialAngle = 0.9,
	},
	[21 / 24] = { --12 9 PM
		Fog = 0.6,
		Hue = 0.65,
		Brightness = 0.1,
		Contrast = 0.25,
		Saturation = 0.25,
		CelestialAngle = 0.5,
	},
}

-- References
local RainDropTemplate = PrecipitationUtil.getRainDrop()
local RainSoundTemplate = Package:WaitForChild("Library"):WaitForChild("Sound"):WaitForChild("Rain") :: Sound

-- Class
local SkyService: SkyService = {} :: any
SkyService.__index = SkyService

function SkyService:Destroy()
	self._Maid:Destroy()
	local t: any = self
	for k, v in pairs(t) do
		t[k] = nil
	end
	setmetatable(t, nil)
	return nil
end

function _setHSV(col: Color3, h: number?, s: number?, v: number?): Color3
	local hC, sC, vC = col:ToHSV()
	if h then
		hC = math.clamp(h, 0, 1)
	end
	if s then
		sC = math.clamp(s, 0, 1)
	end
	if v then
		vC = math.clamp(v, 0, 1)
	end
	return Color3.fromHSV(hC, sC, vC)
end

function incrementHSV(col: Color3, h: number, s: number, v: number): Color3
	local hC, sC, vC = col:ToHSV()

	-- Hue
	hC += h
	if hC > 1 then
		hC -= 1
	elseif hC < 0 then
		hC += 1
	end
	hC = math.clamp(hC, 0, 1)

	-- Saturation
	sC = math.clamp(sC + s, 0, 1)

	-- Value
	vC = math.clamp(vC + v, 0, 1)

	return Color3.fromHSV(hC, sC, vC)
end

function getAtmosphereData(timeOfDay: number): AtmosphereData
	local startKey = 0
	for k: number, v in pairs(AtmosphereDataRegistry) do
		if k > startKey and k < timeOfDay then
			startKey = k
		end
	end
	local finishKey = math.huge
	local alpha = 0
	if startKey == 0 then
		finishKey = 3 / 24
		alpha = (timeOfDay - startKey) / finishKey
	elseif startKey == 21 / 24 then
		finishKey = 0
		alpha = (timeOfDay - startKey) / (1 - startKey)
	else
		for k: number, v in pairs(AtmosphereDataRegistry) do
			if k > startKey and k < finishKey then
				finishKey = k
			end
		end
		alpha = (timeOfDay - startKey) / (finishKey - startKey)
	end
	local startData = AtmosphereDataRegistry[startKey]
	local finishData = AtmosphereDataRegistry[finishKey]

	-- print("START", startData, "Finish", finishData, "ALPHA", alpha, "TOD", timeOfDay, "SK", startKey, "FK", finishKey)
	return {
		Fog = CurveUtil.lerp(startData.Fog, finishData.Fog, alpha),
		Hue = CurveUtil.lerp(startData.Hue, finishData.Hue, alpha),
		Brightness = CurveUtil.lerp(startData.Brightness, finishData.Brightness, alpha),
		Contrast = CurveUtil.lerp(startData.Contrast, finishData.Contrast, alpha),
		Saturation = CurveUtil.lerp(startData.Saturation, finishData.Saturation, alpha),
		CelestialAngle = CurveUtil.lerp(startData.CelestialAngle, finishData.CelestialAngle, alpha),
	}
end

local currentService: SkyService
local proxy = ServiceProxy(function()
	return currentService or SkyService
end)

function SkyService.new(): SkyService
	-- Unpack workspace
	local _maid = Maid.new()
	local _fuse = ColdFusion.fuse(_maid)
	local _new = _fuse.new
	local _import = _fuse.import
	local _bind = _fuse.bind

	local _Value = _fuse.Value
	local _Computed = _fuse.Computed

	-- Internal variables
	local droplets: { [BasePart]: Droplet } = {}
	local dropletSpawnChance = 0

	-- External parameters states
	local CoverageParams = _Value(RaycastParams.new())
	local CoverageCheckDistance = _Value(500)
	local MetersPerUnit = _Value(1 / 2)
	local Visibility = _Value(0.65)
	local Clouds = _Value(CLOUD_COVER)
	local Temperature = _Value(0.5)
	local TimeOfDay = _Value(INITIAL_TIME / 24)
	local TimeSpeed = _Value(1)
	local Brightness = _Value(0.5)
	local LightDirection = _Value(Vector3.new(1, -1, 1))
	local WindDirection = _Value(Vector3.new(0, 0, 1))
	local WindSpeed = _Value(0 :: PhysicsUtil.KilometersPerHour)
	local Rain = _Value(0)
	local Hail = _Value(0)
	local Snow = _Value(0)
	local Lightning = _Value(0)
	local Scale = _Value(1)
	local Enabled = _Value(true)

	-- Internal states
	local CameraCFrame = _Value(CFrame.new(0, 0, 0))
	local CameraFieldOfView = _Value(70 :: GeometryUtil.Degree)
	local ClockTime = _Computed(function(timeOfDay: number)
		return math.clamp(timeOfDay * 24, 0, 23.999)
	end, TimeOfDay)
	local Precipitation = _Computed(function(rain: number, hail: number, snow: number): number
		return math.max(rain, hail, snow)
	end, Rain, Hail, Snow)
	local AtmosphereData = _Computed(function(timeOfDay: number)
		return getAtmosphereData(timeOfDay)
	end, TimeOfDay)
	local Ambient = _Computed(function(atmosphereData: AtmosphereData, brightness: number)
		-- print(atmosphereData)
		return Color3.fromHSV(
			atmosphereData.Hue,
			atmosphereData.Saturation,
			0.75 + 0.125 * brightness + 0.125 * atmosphereData.Brightness
		)
	end, AtmosphereData, Brightness)
	local VaporColor = _Computed(function(precip: number, atmosphereData: AtmosphereData): Color3
		return Color3.fromHSV(224 / 360, (35 / 255) + precip * (40 / 255), 0.05 + 0.9 * atmosphereData.Brightness)
	end, Precipitation, AtmosphereData)

	-- Internal instances
	local dropletFolder = Instance.new("Folder")
	dropletFolder.Name = "ScreenDroplets"
	_maid:GiveTask(dropletFolder)

	local dropletPool: InstancePool = InstancePool.new(RainDropTemplate, RAIN_DROP_AMOUNT)
	_maid:GiveTask(dropletPool)

	local emitterFolder = Instance.new("Folder")
	emitterFolder.Name = "WeatherEmitters"
	emitterFolder.Parent = workspace
	_maid:GiveTask(emitterFolder)

	local emitters: { [number]: PrecipitationEmitter } = {}
	local deltaAngle = math.rad(360 / EMITTER_ANGLE_SLICES)
	local thickness = (EMITTER_MAX_DISTANCE - EMITTER_MIN_RADIUS) / EMITTER_LAYERS

	for d = 1, EMITTER_LAYERS do
		local distance = EMITTER_MIN_RADIUS + d * thickness
		local circumference = distance * math.pi * 2
		local width = circumference * deltaAngle / math.rad(360)
		for i = 1, EMITTER_ANGLE_SLICES do
			local emitter = PrecipitationUtil.newPrecipitationEmitter(emitterFolder)
			emitter.Angle = deltaAngle * i
			emitter.Distance = distance
			emitter.Layer = d
			emitter.Area = width * thickness
			emitter.Height = PRECIPITATION_HEIGHT
			emitter.Instance.Name = tostring(math.deg(emitter.Angle))
			emitter.Instance.Size = Vector3.new(width, 0, thickness)
			table.insert(emitters, emitter)
			_maid:GiveTask(function()
				PrecipitationUtil.destroyPrecipitationEmitter(emitter)
			end)
		end
	end

	-- Mount to instances
	local terrain = workspace:WaitForChild("Terrain")
	local cloudParameters = {
		Parent = terrain,
		Color = VaporColor,
		Density = _Computed(function(precip: number, atmosphereData: AtmosphereData): number
			return math.max(precip * 0.75, atmosphereData.Brightness * 0.5 + 0.5)
		end, Precipitation, AtmosphereData),
		Cover = Clouds,
	} :: any
	local clouds: Clouds? = terrain:FindFirstChild("Clouds") :: any
	if clouds then
		_bind(clouds :: Clouds)(cloudParameters)
	else
		clouds = _new("Clouds")(cloudParameters) :: any
	end

	_bind(game:GetService("Lighting"):WaitForChild("Sky") :: Sky)({
		SunAngularSize = _Computed(function(atmosphereData: AtmosphereData)
			return 10 + 10 * atmosphereData.CelestialAngle
		end, AtmosphereData),
		MoonAngularSize = _Computed(function(atmosphereData: AtmosphereData)
			return 5 + 5 * atmosphereData.CelestialAngle
		end, AtmosphereData),
	})
	_bind(game:GetService("Lighting"):WaitForChild("Atmosphere") :: Atmosphere)({
		Density = _Computed(function(visibility: number, metersPerUnit: number)
			return ATMOSPHERE_DENSITY + (1 - visibility) * 0.3
		end, Visibility, MetersPerUnit),
		Color = VaporColor,
		Decay = _Computed(function(vaporColor: Color3)
			return incrementHSV(vaporColor, 0, 0, -0.1)
		end, VaporColor),
	})
	_bind(game:GetService("Lighting"):WaitForChild("SunRaysEffect") :: SunRaysEffect)({
		Intensity = _Computed(function(atmosphereData: AtmosphereData)
			return 0.25 * SUN_INTENSITY
				+ 0.75 * atmosphereData.Brightness * SUN_INTENSITY
		end, AtmosphereData),
	})
	_bind(game:GetService("Lighting") :: Lighting)({
		ClockTime = ClockTime,
		OutdoorAmbient = Ambient,
		Brightness = AtmosphereData:Read("Brightness"):Multiply(Brightness :: any):Add(2.5 :: any),
		ColorShift_Top = Ambient,
	})

	local rainSound: Sound = RainSoundTemplate:Clone()
	rainSound.Looped = true
	_maid:GiveTask(rainSound)
	SoundService:PlayLocalSound(rainSound)
	_bind(rainSound)({
		Volume = Rain,
	})

	-- Update loop
	_maid:GiveTask(RunService.RenderStepped:Connect(function(deltaTime: number)
		if not Enabled:Get() then
			return
		end
		local camera = workspace.CurrentCamera
		if camera then
			if camera ~= dropletFolder.Parent then
				dropletFolder.Parent = camera
			end

			-- update camera
			CameraCFrame:Set(camera.CFrame)
			CameraFieldOfView:Set(camera.FieldOfView)

			-- step droplets
			local isCovered = workspace:Raycast(
				camera.CFrame.Position + UP_VECTOR * CoverageCheckDistance:Get(),
				-UP_VECTOR * CoverageCheckDistance:Get(),
				CoverageParams:Get()
			) ~= nil
			dropletSpawnChance = PrecipitationUtil.stepCameraDroplets(
				deltaTime,
				dropletPool,
				droplets,
				camera.CFrame,
				dropletSpawnChance,
				isCovered,
				TimeSpeed:Get(),
				Rain:Get(),
				dropletFolder
			)

			-- step particles
			for i, emitter in ipairs(emitters) do
				local eResult = workspace:Raycast(
					emitter.Instance.Position + UP_VECTOR * CoverageCheckDistance:Get(),
					-UP_VECTOR * CoverageCheckDistance:Get() * 2,
					CoverageParams:Get()
				)
				emitter.Scale = Scale:Get()
				emitter.Enabled = (eResult == nil or eResult.Position.Y < camera.CFrame.Position.Y)
				emitter.Types.Hail.Weight = Hail:Get()
				emitter.Types.Rain.Weight = Rain:Get()
				emitter.Types.Snow.Weight = Snow:Get()
				PrecipitationUtil.updatePrecipitationEmitter(camera.CFrame, emitter, TimeSpeed:Get())
				-- local impactCount = 0
				-- local points: { [number]: Vector3 } = PrecipitationUtil.getPointsInArea(emitter, impactCount)
				-- for j, point in ipairs(points) do
				-- 	if deltaTime * MAX_IMPACTS_PER_SECOND < math.random() then
				-- 		local result = workspace:Raycast(point, -UP_VECTOR * emitter.Height * 2, CoverageParams:Get())
				-- 		if result then
				-- 			PrecipitationUtil.impactGround(emitter, result.Position, result.Normal, result.Material)
				-- 		end
				-- 	end
				-- end
			end
		end
	end))

	-- Construct
	local self: SkyService = setmetatable({
		_Maid = _maid,
		MetersPerUnit = MetersPerUnit,
		Visibility = Visibility,
		CoverageCheckDistance = CoverageCheckDistance,
		Temperature = Temperature,
		TimeOfDay = TimeOfDay,
		TimeSpeed = TimeSpeed,
		CoverageParams = CoverageParams,
		Brightness = Brightness,
		LightDirection = LightDirection,
		WindDirection = WindDirection,
		WindSpeed = WindSpeed,
		Rain = Rain,
		Clouds = Clouds,
		Hail = Hail,
		Lightning = Lightning,
		Snow = Snow,
		Scale = Scale,
		Enabled = Enabled,
	}, SkyService) :: any

	currentService = self

	return self
end

function SkyService.init(maid: Maid)
	local skyService = SkyService.new()
	skyService.MetersPerUnit:Set(METERS_PER_UNIT)
	skyService.CoverageCheckDistance:Set(METERS_PER_UNIT * 500)
	skyService.Scale:Set(SCALE)
	maid:GiveTask(skyService)
	return nil
end

return proxy
