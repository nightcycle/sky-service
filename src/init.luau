--!strict
local Package = script
local Packages = Package.Parent

-- Services
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

-- Packages
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
local SCALE = 1
local UNIT_TO_METER = 1/3
local METERS_PER_UNIT = SCALE / UNIT_TO_METER

-- Types

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

	Enabled: ValueState<boolean>,
	Rain: ValueState<number>,
	CoverageCheckDistance: ValueState<number>,
	Hail: ValueState<number>,
	Snow: ValueState<number>,
	Lightning: ValueState<number>,

	Destroy: (self: SkyService) -> nil,
	new: () -> SkyService,
	init: (maid: Maid) -> nil,
}

-- References
local RainDropTemplate = PrecipitationUtil.getRainDrop()
local RainSoundTemplate = Package:WaitForChild("Library"):WaitForChild("Sound"):WaitForChild("Rain") :: Sound

-- Private functions

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

local currentService: SkyService

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
	local Enabled = _Value(true)
	local Rain = _Value(0)
	local Hail = _Value(0)
	local Snow = _Value(0)
	local Lightning = _Value(0)

	-- Internal states
	local CameraCFrame = _Value(CFrame.new(0, 0, 0))
	local CameraFieldOfView = _Value(70 :: GeometryUtil.Degree)

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
				1,
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
				emitter.Scale = 1
				emitter.Enabled = (eResult == nil or eResult.Position.Y < camera.CFrame.Position.Y)
				emitter.Types.Hail.Weight = Hail:Get()
				emitter.Types.Rain.Weight = Rain:Get()
				emitter.Types.Snow.Weight = Snow:Get()
				PrecipitationUtil.updatePrecipitationEmitter(camera.CFrame, emitter, 1)

			end
		end
	end))

	-- Construct
	local self: SkyService = setmetatable({
		_Maid = _maid,
		CoverageCheckDistance = CoverageCheckDistance,
		CoverageParams = CoverageParams,
		Rain = Rain,
		Hail = Hail,
		Lightning = Lightning,
		Snow = Snow,
		Enabled = Enabled,
	}, SkyService) :: any

	currentService = self

	return self
end

function SkyService.init(maid: Maid)
	local skyService = SkyService.new()
	skyService.CoverageCheckDistance:Set(METERS_PER_UNIT * 500)
	maid:GiveTask(skyService)
	return nil
end

return ServiceProxy(function()
	return currentService or SkyService
end)
