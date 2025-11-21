--!strict

local executeLuauTaskAsync = require("../utility/executeLuauTaskAsync")
local uploadPlaceAsync = require("../utility/uploadPlaceAsync")
local types = require("./types")

type CloudConfig = types.CloudConfig

local function runTestsCloud(scriptContent: string, config: CloudConfig): number
	local universeId = tonumber(config.universeId)
	local placeId = tonumber(config.placeId)

	if not universeId or not placeId then
		print("Error: Invalid universe ID or place ID (must be numbers)")
		return 1
	end

	local placeVersion: number?

	if config.upload then
		if not config.placePath then
			print("Error: --upload flag requires a place file path")
			print("Provide via --place flag or jestir.toml [once.place_file]")
			return 1
		end

		-- Upload the place file and use the returned version number
		local uploadResult = uploadPlaceAsync({
			universeId = universeId,
			placeId = placeId,
			apiKey = config.apiKey,
			filePath = config.placePath,
		})

		if not uploadResult then
			return 1
		end

		placeVersion = uploadResult.versionNumber
	elseif config.placeVersion then
		local versionNum = tonumber(config.placeVersion)
		if not versionNum then
			print("Error: Invalid place version (must be a number)")
			return 1
		end
		placeVersion = versionNum
	end

	if not placeVersion then
		print("Error: Place version is required for cloud execution")
		print("Specify via --place-version flag, jestir.toml [cloud] section, or use --upload flag with a place file")
		return 1
	end

	local success = executeLuauTaskAsync({
		universeId = universeId,
		placeId = placeId,
		placeVersion = placeVersion,
		apiKey = config.apiKey,
		script = scriptContent,
	})

	return if success then 0 else 1
end

return runTestsCloud
