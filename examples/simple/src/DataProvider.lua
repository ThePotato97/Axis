-- Simple provider that keeps track of non-persistent data while the player is in the game

local DataProvider = {}

DataProvider.AxisName = "DataProvider"

DataProvider._PerPlayerData = {}

DataProvider._ThreadsAwaitingData = {}

-- Resume any waiting threads with the given data
function DataProvider:_ResumeAwaitingThreads(player: Player, data)
	local threads = DataProvider._ThreadsAwaitingData[player]
	if not threads then
		return
	end
	for _, thread in ipairs(threads) do
		task.spawn(thread, data)
	end
	DataProvider._ThreadsAwaitingData[player] = nil
end

-- Hooked up by the PlayersExtension
function DataProvider:OnPlayerAdded(player: Player)
	DataProvider._PerPlayerData[player] = {}
	DataProvider:_ResumeAwaitingThreads(player, DataProvider.PerPlayerData[player])
end

-- Hooked up by the PlayersExtension
-- Clears the data and any awaiting threads
function DataProvider:OnPlayerRemoving(player: Player)
	DataProvider._PerPlayerData[player] = nil
	DataProvider:_ResumeAwaitingThreads(player, nil)
end

-- Get the data for the player (if any)
function DataProvider:GetPlayerData(player: Player)
	return DataProvider._PerPlayerData[player]
end

-- Yield the current thread until the player's data is available
function DataProvider:AwaitPlayerData(player: Player)
	if player.Parent == nil then
		return nil
	end
	local data = DataProvider:GetPlayerData(player)
	if data ~= nil then
		return data
	end
	if not DataProvider._ThreadsAwaitingData[player] then
		DataProvider._ThreadsAwaitingData[player] = {}
	end
	table.insert(DataProvider._ThreadsAwaitingData[player], coroutine.running())
	return coroutine.yield()
end

function DataProvider:AxisStarted() end

return DataProvider
