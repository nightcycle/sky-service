--!strict
--Services
local RunService = game:GetService("RunService")
--Packages
local Package = script.Parent
assert(Package)
local Packages = Package.Parent
assert(Packages)
local Maid = require(Packages:WaitForChild("Maid"))
--Modules
--Types
type Maid = Maid.Maid
--Constants
local DAY_DURATION = 30

return function(coreGui: Frame)
	local maid = Maid.new()

	task.spawn(function()
		local SkyService = require(script.Parent)
		SkyService.init(maid)
		maid:GiveTask(RunService.RenderStepped:Connect(function(deltaTime: number)
			local tVal = 0.5 + 0.5 * math.sin(tick() / DAY_DURATION)
			print("RAIN", tVal)
			SkyService.Rain:Set(tVal)
		end))
	end)

	return function()
		maid:Destroy()
	end
end
