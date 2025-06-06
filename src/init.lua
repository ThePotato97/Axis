--!strict

-- Axis
-- Stephen Leitnick
-- March 05, 2022

export type ProviderLifecycleFn = (Provider) -> ()

--[=[
	@within Axis
	@interface Provider
	.AxisName string?
	.AxisStarted (Provider) -> ()

	Providers are simple structures that provide top-level structure,
	as well as lifecycle methods to help safeguard communication
	between each other.
]=]
export type Provider = {
	AxisName: string?,
	AxisStarted: ProviderLifecycleFn,
	AxisExtensions: { Extension }?,
	[any]: any,
}

--[=[
	@within Axis
	@interface Extension
	.BeforeStarted (Provider) -> ()

	Extensions allow developers to extend the capabilities
	of providers within Axis.
]=]
export type Extension = {
	BeforeStarted: ProviderLifecycleFn?,
	[any]: any,
}

--[=[
	@class Axis

	Axis is a provider framework. Providers are simple structures that give high-level
	encapsulation of game logic, as well as providing lifecycle methods to help control
	the communication between each other.

	Axis also provides the ability to add extensions, which extend the capabilities of
	providers. Extensions can be added to all providers, or can be added on a per-provider
	basis.

	A typical setup with separate providers and extensions into their own ModuleScripts, and
	then a single script to collect all of those ModuleScripts and add them into Axis. Such
	a script may look like the following:

	```lua
	local Axis = require(somewhere.Axis)

	-- Add providers:
	for _,module in ipairs(somewhere.Providers:GetChildren()) do
		local provider = require(module)
		Axis:AddProvider(provider)
	end

	-- Add extensions:
	for _,module in ipairs(somewhere.Extensions:GetChildren()) do
		local extension = require(module)
		Axis:AddExtension(extension)
	end

	-- Start Axis:
	Axis:Start()
	
	print("Axis started")
	```
]=]
local Axis = {}

Axis._Providers = {}
Axis._Extensions = {}
Axis._Starting = false
Axis._Started = false
Axis._Awaiting = {}

function Axis:_RunExtensions(funcName: string, provider: Provider)
	local function Run(extension: Extension)
		local func = extension[funcName]
		if typeof(func) == "function" then
			func(provider)
		end
	end
	for _, extension: Extension in ipairs(Axis._Extensions) do
		Run(extension)
	end
	if provider.AxisExtensions then
		for _, extension: Extension in ipairs(provider.AxisExtensions) do
			Run(extension)
		end
	end
end

--[=[
	Add an extension to Axis. Extensions will run before certain lifecycle
	methods per provider. Extensions are useful for extending the capabilities
	of providers.

	Here's an example of logging when a provider is about to be prepared and
	started:

	```lua
	local MyExtension = {}

	-- Note the dot-notation for functions instead of colon-notation
	function MyExtension.BeforeStarted(provider)
		print("BeforeStarted provider", provider.AxisName)
	end

	Axis:AddExtension(MyExtension)
	```

	Extensions can also be added at the provider level. This is useful if an
	extension shouldn't apply to all other providers. Adding extensions at the
	provider level is done by adding an extension into the provider's
	`AxisExtension` table:

	```lua
	local MyProvider = {}

	MyProvider.AxisExtensions = {MyExtension}
	```

	Extensions are executed in the order of which they were added. Axis-level
	extensions run before provider-level extensions.

	:::caution Before Start
	Must be called _before_ `Axis:Start()`.
	:::
]=]
function Axis:AddExtension(extension: Extension): Extension
	if Axis._Started or Axis._Starting then
		error("Cannot add extensions after Axis has started", 2)
	end
	table.insert(Axis._Extensions, extension)
	return extension
end

--[=[
	Add a provider to Axis.

	```lua
	local MyProvider = {}

	-- Optional name for memory labeling:
	MyProvider.AxisName = "MyProvider"
	
	function MyProvider:AxisStarted()
		print("Axis started")
	end

	-- Add the provider to Axis:
	Axis:AddProvider(MyProvider)
	```

	:::caution Before Start
	Must be called _before_ `Axis:Start()`.
	:::
]=]
function Axis:AddProvider(provider: Provider): Provider
	if Axis._Started or Axis._Starting then
		error("Cannot add providers after Axis has started", 2)
	elseif table.find(Axis._Providers, provider) ~= nil then
		error("Provider already exists", 2)
	end
	table.insert(Axis._Providers, provider)
	return provider
end

--[=[
	@yields
	Starts Axis and yields the current thread until Axis has fully started.

	```lua
	-- [Add providers/extensions here before starting]
	Axis:Start()
	print("Axis has started")
	```

	:::caution Call Once
	Can only be called once. Calling more than once will throw an error.
	:::

	:::note Yields Only If Necessary
	If any of the AxisPrepare or BeforePrepare functions yield, Axis will yield
	to wait for them to complete. If none yield, then Axis will start immediately
	without any yield.
	:::
]=]
function Axis:Start()
	if Axis._Started or Axis._Starting then
		error("Axis already started", 2)
	end
	Axis._Starting = true

	-- Call all AxisStarted methods:
	for _, provider: Provider in ipairs(Axis._Providers) do
		if typeof(provider.AxisStarted) == "function" then
			task.spawn(function()
				Axis:_RunExtensions("BeforeStarted", provider)
				if provider.AxisName then
					debug.setmemorycategory(provider.AxisName)
				end
				provider:AxisStarted()
			end)
		end
	end

	-- Resume awaiting threads:
	for _, awaitingThread in ipairs(Axis._Awaiting) do
		task.defer(awaitingThread)
	end

	Axis._Starting = false
	Axis._Started = true
end

--[=[
	@yields
	Yields the current thread until Axis has fully started. If Axis
	has already been started, this function simply does nothing.

	```lua
	Axis:AwaitStart()
	print("Axis has started!")
	```
]=]
function Axis:AwaitStart()
	if not Axis._Started then
		return
	end
	table.insert(Axis._Awaiting, coroutine.running())
	coroutine.yield()
end

--[=[
	Calls the callback once Axis has fully started. If Axis has
	already been started, then the callback is immediately called.

	```lua
	Axis:OnStart(function()
		print("Axis has started!")
	end)
	```
]=]
function Axis:OnStart(callback: () -> ())
	if not Axis._Started then
		task.spawn(callback)
		return
	end
	local thread = coroutine.create(callback)
	table.insert(Axis._Awaiting, thread)
end

return Axis
