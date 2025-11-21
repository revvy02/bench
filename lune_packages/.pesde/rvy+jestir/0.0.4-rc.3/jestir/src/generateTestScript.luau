--!strict

export type TestOptions = {
	verbose: boolean,
	ci: boolean,
	projects: { string }?,
	testNamePattern: string?,
	testPathPattern: string?,
}

local function generateTestScript(options: TestOptions): string
	local optionsTable = {}

	table.insert(optionsTable, "verbose = " .. tostring(options.verbose))
	table.insert(optionsTable, "ci = " .. tostring(options.ci))
	table.insert(optionsTable, "noStackTrace = true")

	if options.testNamePattern then
		table.insert(optionsTable, `testNamePattern = "{options.testNamePattern}"`)
	end

	if options.testPathPattern then
		table.insert(optionsTable, `testPathPattern = "{options.testPathPattern}"`)
	end

	local optionsString = table.concat(optionsTable, ",\n\t")
	local projectPathsString
	if options.projects and #options.projects > 0 then
		projectPathsString = "{ " .. table.concat(options.projects, ", ") .. " }"
	else
		projectPathsString = "{ game }"
	end

	return [[
local runCLI = require(game.ReplicatedStorage.packages.jest).runCLI

local processServiceExists, ProcessService = pcall(function()
    return game:GetService("ProcessService")
end)

local status, result = runCLI(game, {
    ]] .. optionsString .. [[
}, ]] .. projectPathsString .. [[):awaitStatus()

if status == "Rejected" then
    print(result)
end

if status == "Resolved" and result.results.success then
    if processServiceExists then
        ProcessService:ExitAsync(0)
    end
end

if processServiceExists then
    ProcessService:ExitAsync(1)
end

return nil
    ]]
end

return generateTestScript
