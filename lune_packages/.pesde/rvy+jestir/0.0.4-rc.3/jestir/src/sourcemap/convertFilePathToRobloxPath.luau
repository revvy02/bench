--!strict

local fs = require("@lune/fs")
local serde = require("@lune/serde")

type SourcemapNode = {
	name: string?,
	className: string?,
	filePaths: { string }?,
	children: { SourcemapNode }?,
}

-- Count path segments in a file path
local function countPathSegments(path: string): number
	local count = 0
	for _ in path:gmatch("[^/\\]+") do
		count = count + 1
	end
	return count
end

local function findInSourcemap(node: SourcemapNode, targetFilePath: string, currentPath: { string }, isDirectory: boolean, targetDepth: number?): string?
	if isDirectory and node.filePaths then
		for _, filePath in node.filePaths do
			local escapedTarget = targetFilePath:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
			if filePath:find("^" .. escapedTarget .. "[/\\]") then
				local pathStr = "game"
				for i = 1, targetDepth or #currentPath do
					if currentPath[i] then
						pathStr = pathStr .. `["{currentPath[i]}"]`
					end
				end
				return pathStr
			end
		end
	end

	if not isDirectory and node.filePaths then
		for _, filePath in node.filePaths do
			if filePath == targetFilePath or filePath:find(targetFilePath, 1, true) then
				local pathStr = "game"
				for _, name in currentPath do
					pathStr = pathStr .. `["{name}"]`
				end
				return pathStr
			end
		end
	end

	-- Recursively search children
	if node.children then
		for _, child in node.children do
			local newPath = table.clone(currentPath)
			table.insert(newPath, child.name)
			local result = findInSourcemap(child, targetFilePath, newPath, isDirectory, targetDepth)
			if result then
				return result
			end
		end
	end

	return nil
end

-- Loads the sourcemap.json file from the current working directory
local function loadSourcemap(): SourcemapNode
	local sourcemapPath = "sourcemap.json"
	if not fs.isFile(sourcemapPath) then
		error("sourcemap.json not found. Please build the project first with rojo.")
	end

	local sourcemapContent = fs.readFile(sourcemapPath)
	return serde.decode("json", sourcemapContent)
end

-- Converts a file system path to a Roblox instance path using the sourcemap
-- Returns the Roblox path and whether the input was a file (vs directory)
local function convertFilePathToRobloxPath(filePath: string): (string, boolean)
	local sourcemapData = loadSourcemap()

	-- Normalize the input file path (remove leading './', '../', etc.)
	local normalizedPath = filePath:gsub("^%.%./", ""):gsub("^%./", "")

	-- Check if this is a file or directory
	local isFile = fs.isFile(filePath)
	local isDirectory = fs.isDir(filePath)

	-- For directories, calculate how deep the target directory path is
	-- This tells us how many segments of the currentPath to use
	local targetDepth: number? = nil
	if isDirectory then
		targetDepth = countPathSegments(normalizedPath)
	end

	-- Search for the path in the sourcemap
	local robloxPath = findInSourcemap(sourcemapData, normalizedPath, {}, isDirectory, targetDepth)

	if not robloxPath then
		error(`Could not find file path "{filePath}" in sourcemap.json`)
	end

	return robloxPath, isFile
end

return convertFilePathToRobloxPath
