--!strict

local fs = require("@lune/fs")
local net = require("@lune/net")
local serde = require("@lune/serde")

local createSpinner = require("./createSpinner")
local richPrint = require("./richPrint")

export type UploadPlaceOptions = {
	universeId: number,
	placeId: number,
	apiKey: string,
	filePath: string,
}

export type UploadPlaceResult = {
	versionNumber: number,
}

local function uploadPlaceAsync(options: UploadPlaceOptions): UploadPlaceResult?
	local universeId = options.universeId
	local placeId = options.placeId
	local apiKey = options.apiKey
	local filePath = options.filePath

	local spinner = createSpinner()
	spinner.setText("Uploading place file...")
	spinner.start()

	local readSuccess, placeFile = pcall(fs.readFile, filePath)
	if not readSuccess then
		spinner.stop()
		richPrint("red", "bold", "Failed to read place file")
		return nil
	end

	local res = net.request({
		url = `https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions`,
		method = "POST",
		body = placeFile,
		query = {
			versionType = "Published",
		},
		headers = {
			["x-api-key"] = apiKey,
			["Content-Type"] = "application/octet-stream",
			["Accept"] = "application/json",
		},
	})

	spinner.stop()

	local decodedBody = serde.decode("json", res.body)
	if res.ok then
		richPrint("green", "bold", `Place uploaded successfully (version {decodedBody.versionNumber})`)
		return {
			versionNumber = decodedBody.versionNumber,
		}
	else
		richPrint("red", "bold", "Failed to upload place file")
		print(decodedBody)
		return nil
	end
end

return uploadPlaceAsync
