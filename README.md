# sky-service
A basic package allowing for easy control over precipitation / lightning. 

## set up
Download from wally, then call:
```lua
SkyService.new()
```
After this is called it should be usable just by requiring the package anywhere.

## configuration
### ceiling detection
To determine whether to render precipitation it will shoot raycasts upwards from your position to try and find a ceiling.
```lua
local ceilingCastParams = RaycastParams.new()

SkyService.CoverageCheckDistance:Set(100) -- sets how far up it will check for a ceiling, in this case 100 units
SkyService.CoverageParams:Set(ceilingCastParams) -- sets the raycastParams for the raycasts
```

### enable / disable
Should you want to pause the effects (like for say a loading screen / UI) you can do so:
```lua
SkyService.Enabled:Set(false) -- disables
SkyService.Enabled:Set(true) -- enables
local isEnabled = SkyService.Enabled:Get() -- retrieves current value
```

## effects
For each effect you can pass a number from 0 to 1, with 1 being full throttle, and 0 basically turning it off
### rain
Drops raindrop particles + plays sound + adds splash fx to the screen
```lua
SkyService.Rain:Set(1) -- full rain
SkyService.Rain:Set(0.5) -- light rain
SkyService.Rain:Set(0) -- no rain
```

### snow
Drops snowflake particles
```lua
SkyService.Snow:Set(1) -- blizzard
SkyService.Snow:Set(0.5) -- gentle snow
SkyService.Snow:Set(0) -- no snow
```

### lightning
Currently under repair and doesn't do anything.
