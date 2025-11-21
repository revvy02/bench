--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local types = require("./types")

type OnceConfig = types.OnceConfig

local TEMP_DIR = ".jestir"

local function runTestsOnce(scriptContent: string, config: OnceConfig): number
	local placePath = config.placePath

	if not fs.isFile(placePath) then
		error(`Place file not found at path: {placePath}`)
	end

	if not fs.isDir(TEMP_DIR) then
		fs.writeDir(TEMP_DIR)
	end

	local timestamp = os.time()
	local tempPlaceName = `test-{timestamp}.rbxl`
	local tempPlacePath = `{TEMP_DIR}/{tempPlaceName}`
	local placeContent = fs.readFile(placePath)
	fs.writeFile(tempPlacePath, placeContent)

	local args = {
		"once",
		"-s",
		scriptContent,
		"--place",
		tempPlacePath,
	}

	if config.noError then
		table.insert(args, "--no-error")
		table.insert(args, "--no-info")
	end

	if config.noWarn then
		table.insert(args, "--no-warn")
	end

	local result = process.exec("rir3", args, {
		stdio = "forward",
	})

	if fs.isFile(tempPlacePath) then
		fs.removeFile(tempPlacePath)
	end

	return result.code
end

return runTestsOnce
