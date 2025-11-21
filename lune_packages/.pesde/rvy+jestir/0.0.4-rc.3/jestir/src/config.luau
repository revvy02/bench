--!strict

local fs = require("@lune/fs")
local serde = require("@lune/serde")

export type JestirConfig = {
	once: {
		place_file: string?,
	}?,
	cloud: {
		place_id: string?,
		universe_id: string?,
		place_version: string?,
		publish: boolean?,
	}?,
	projects: {
		[string]: string,
	}?,
}

local function loadConfig(): JestirConfig?
	local configPath = "jestir.toml"

	if not fs.isFile(configPath) then
		return nil
	end

	local content = fs.readFile(configPath)
	local config = serde.decode("toml", content)

	return config :: JestirConfig
end

local function getAllProjectPaths(config: JestirConfig, convertFilePathToRobloxPath: (string) -> (string, string?)): { string }
	local paths = {}

	if config.projects then
		for projectName, projectPath in config.projects do
			local robloxPath, _ = convertFilePathToRobloxPath(projectPath)
			if robloxPath and robloxPath ~= "" then
				table.insert(paths, robloxPath)
			end
		end
	end

	return paths
end

local function getProjectPath(config: JestirConfig, projectName: string, convertFilePathToRobloxPath: (string) -> (string, string?)): string?
	if not config.projects then
		return nil
	end

	local projectPath = config.projects[projectName]
	if not projectPath then
		return nil
	end

	local robloxPath, _ = convertFilePathToRobloxPath(projectPath)
	return if robloxPath ~= "" then robloxPath else nil
end

return {
	loadConfig = loadConfig,
	getAllProjectPaths = getAllProjectPaths,
	getProjectPath = getProjectPath,
}
