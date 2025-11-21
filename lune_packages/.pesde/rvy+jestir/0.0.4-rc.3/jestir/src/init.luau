--!strict

local argparse = require("@pkg/argparse")
local configModule = require("@self/config")
local convertFilePathToRobloxPath = require("@self/sourcemap/convertFilePathToRobloxPath")
local generateTestScript = require("@self/generateTestScript")
local process = require("@lune/process")
local runTestsCloud = require("@self/runner/runTestsCloud")
local runTestsOnce = require("@self/runner/runTestsOnce")
local runTestsServe = require("@self/runner/runTestsServe")
local types = require("@self/runner/types")

type RunTarget = types.RunTarget
type RunTargetConfig = types.RunTargetConfig

local function loadEnvFile(): { [string]: string }
	local fs = require("@lune/fs")
	local envPath = ".env"

	if not fs.isFile(envPath) then
		error("No .env file found")
	end

	local content = fs.readFile(envPath)
	local env = {}

	for line in content:gmatch("[^\r\n]+") do
		local key, value = line:match("^([%w_]+)%s*=%s*(.+)$")
		if key and value then
			-- Remove quotes if present
			value = value:match('^"(.+)"$') or value:match("^'(.+)'$") or value
			env[key] = value
		end
	end

	return env
end

local function getApiKey(): string
	local keyInEnv = process.env.JESTIR_API_KEY
	if keyInEnv then
		return keyInEnv
	end

	local success, envFile = pcall(loadEnvFile)
	if not success then
		error("No environment variable set for JESTIR_API_KEY. Please set it in the environment or in the .env file.")
	end

	return envFile.JESTIR_API_KEY
end

local function parseArgs()
	local parser: any = argparse():name("test"):description("Run tests")

	parser:flag("--verbose", "Enable verbose output")
	parser:flag("--ci", "Run in CI mode")
	parser:flag("--no-error", "Suppress error and info output from rir3")
	parser:flag("--no-warn", "Suppress warning output from rir3")
	parser:option("--target", "Execution target: once, serve, or cloud (default: serve)")
	parser:option("--project", "Project name from jestir.toml to run tests for")
	parser:option("--test-name-pattern", "Pattern to match test names (regex)")
	parser:option("--test-path-pattern", "Pattern to match test file paths (regex)")
	parser:option("--universe-id", "Universe ID for cloud execution")
	parser:option("--place-id", "Place ID for cloud execution")
	parser:option("--place-version", "Place version for cloud execution (optional, uses latest if not specified)")
	parser:option("--api-key", "Roblox Open Cloud API key")
	parser:flag("--upload", "Upload the place file before running tests (cloud only)")
	parser:option("--place", "Path to place file (for once target and cloud with --upload)")
	parser:option("--sourcemap", "Path to sourcemap.json")

	return parser:parse(process.args)
end

local function determineProjects(args, jestirConfig): ({ string }?, string?, string?)
	local projects: { string }? = nil
	local testPathPattern: string? = args.test_path_pattern
	local testNamePattern: string? = args.test_name_pattern

	if args.project then
		if not jestirConfig then
			error("jestir.toml not found. Cannot use --project flag without config file.")
		end

		local projectPath = configModule.getProjectPath(jestirConfig, args.project, convertFilePathToRobloxPath)
		if not projectPath then
			error(`Project "{args.project}" not found in jestir.toml`)
		end

		projects = { projectPath }
	else
		if jestirConfig then
			projects = configModule.getAllProjectPaths(jestirConfig, convertFilePathToRobloxPath)
		end
	end

	return projects, testPathPattern, testNamePattern
end

local function buildConfig(target: RunTarget, args, jestirConfig: any): RunTargetConfig
	if target == "cloud" then
		local apiKey: string = if typeof(args.api_key) == "string" then args.api_key else getApiKey()

		local universeId: string? = args.universe_id
		if not universeId and jestirConfig and typeof(jestirConfig.cloud) == "table" and typeof(jestirConfig.cloud.universe_id) == "string" then
			universeId = jestirConfig.cloud.universe_id
		elseif not universeId and jestirConfig and typeof(jestirConfig.cloud) == "table" and typeof(jestirConfig.cloud.universe_id) == "number" then
			universeId = tostring(jestirConfig.cloud.universe_id)
		end
		if not universeId then
			error("Universe ID required for --target cloud. Provide via --universe-id flag or jestir.toml [cloud] section")
		end

		local placeId: string? = args.place_id
		if not placeId and jestirConfig and typeof(jestirConfig.cloud) == "table" and typeof(jestirConfig.cloud.place_id) == "string" then
			placeId = jestirConfig.cloud.place_id
		elseif not placeId and jestirConfig and typeof(jestirConfig.cloud) == "table" and typeof(jestirConfig.cloud.place_id) == "number" then
			placeId = tostring(jestirConfig.cloud.place_id)
		end
		if not placeId then
			error("Place ID required for --target cloud. Provide via --place-id flag or jestir.toml [cloud] section")
		end

		local placeVersion: string? = args.place_version
		if not placeVersion and jestirConfig and typeof(jestirConfig.cloud) == "table" and typeof(jestirConfig.cloud.place_version) == "string" then
			placeVersion = jestirConfig.cloud.place_version
		elseif not placeVersion and jestirConfig and typeof(jestirConfig.cloud) == "table" and typeof(jestirConfig.cloud.place_version) == "number" then
			placeVersion = tostring(jestirConfig.cloud.place_version)
		end

		local upload: boolean? = args.upload
		if upload == nil and jestirConfig and typeof(jestirConfig.cloud) == "table" and typeof(jestirConfig.cloud.upload) == "boolean" then
			upload = jestirConfig.cloud.upload
		end

		local placePath: string? = nil
		if typeof(args.place) == "string" then
			placePath = args.place
		elseif jestirConfig and typeof(jestirConfig.once) == "table" and typeof(jestirConfig.once.place_file) == "string" then
			placePath = jestirConfig.once.place_file
		end

		return {
			target = "cloud" :: "cloud",
			universeId = universeId,
			placeId = placeId,
			placeVersion = placeVersion,
			apiKey = apiKey,
			upload = upload,
			placePath = placePath,
		}
	elseif target == "once" then
		local placePath: string
		if typeof(args.place) == "string" then
			placePath = args.place
		elseif jestirConfig and typeof(jestirConfig.once) == "table" and typeof(jestirConfig.once.place_file) == "string" then
			placePath = jestirConfig.once.place_file
		else
			error("Place file path required for --target once. Provide via --place flag or jestir.toml [once] section")
		end

		local sourcemapPath: string? = if typeof(args.sourcemap) == "string" then args.sourcemap else "sourcemap.json"

		return {
			target = "once",
			placePath = placePath,
			sourcemapPath = sourcemapPath,
			noError = args.no_error,
			noWarn = args.no_warn,
		}
	else
		local sourcemapPath: string? = if typeof(args.sourcemap) == "string" then args.sourcemap else "sourcemap.json"

		return {
			target = "serve",
			sourcemapPath = sourcemapPath,
			noError = args.no_error,
			noWarn = args.no_warn,
		}
	end
end

local function main(): number
	local args = parseArgs()

	local target: RunTarget = args.target or "serve"
	if target ~= "once" and target ~= "serve" and target ~= "cloud" then
		error(`Invalid target "{target}". Must be one of: once, serve, cloud`)
	end

	local jestirConfig = configModule.loadConfig()
	local projects, testPathPattern, testNamePattern = determineProjects(args, jestirConfig)
	local config = buildConfig(target, args, jestirConfig)
	local scriptContent = generateTestScript({
		verbose = args.verbose or false,
		ci = args.ci or false,
		projects = projects,
		testNamePattern = testNamePattern,
		testPathPattern = testPathPattern,
	})

	local exitCode: number
	if config.target == "cloud" then
		exitCode = runTestsCloud(scriptContent, config)
	elseif config.target == "once" then
		exitCode = runTestsOnce(scriptContent, config)
	else
		exitCode = runTestsServe(scriptContent, config)
	end

	return exitCode
end

process.exit(main())
