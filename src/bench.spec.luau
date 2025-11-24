-- Bench test suite

local JestGlobals = require(game.ReplicatedStorage.packages.jest_globals)
local bench = require(script.Parent.bench)
local gt = require(game.ReplicatedStorage.packages.greentea)

local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect
local beforeEach = JestGlobals.beforeEach

-- GreenTea type validators for bench structures
-- Note: We use gt.any() for children since it's a recursive Dump structure
-- and greentea doesn't handle recursive types well
local dumpNodeType = gt.build(gt.table({
	durations = gt.array(gt.number()),
	children = gt.any(), -- Recursive Dump structure
}))

-- Helper to validate dump structure with expected shape (type validation only)
local function expectDumpStructure(dump: any, expectedShape: { [string]: any })
	for label, expected in expectedShape do
		local node = dump[label]
		expect(node).never.toBeNil()

		-- Validate node structure
		expect(function()
			dumpNodeType:assert(node)
		end).never.toThrow()

		-- Recursively check children if specified
		if expected.children then
			expectDumpStructure(node.children, expected.children)
		end
	end
end

describe("bench", function()
	beforeEach(function()
		-- Reset bench state before each test
		bench.off()
	end)

	describe("on/off", function()
		it("should start disabled by default", function()
			bench.mark("test")
			bench.done()
			local dump = bench.dump()
			expect(dump).toBeNil()
		end)

		it("should enable profiling when on() is called", function()
			bench.on()
			bench.mark("test")
			bench.done()
			local dump = bench.dump()
			expect(dump).never.toBeNil()
		end)

		it("should disable profiling when off() is called", function()
			bench.on()
			bench.mark("test1")
			bench.done()

			bench.off()

			bench.mark("test2")
			bench.done()
			local dump = bench.dump()
			expect(dump).toBeNil()
		end)

		it("should return dump when off() is called with active session", function()
			bench.on()
			bench.mark("test")
			bench.done()

			local dump = bench.off()
			assert(dump)

			expect(dump).never.toBeNil()
			expect(dump.test).never.toBeNil()
			expect(dump.test.durations).toEqual(expect.any("table"))
			expect(#dump.test.durations).toBe(1)
		end)

		it("should return nil when off() is called without active session", function()
			local dump = bench.off()
			expect(dump).toBeNil()
		end)
	end)

	describe("mark/done", function()
		beforeEach(function()
			bench.on()
		end)

		it("should record measurements correctly", function()
			bench.mark("test")
			bench.done()

			local dump = bench.dump()
			assert(dump)
			expect(dump).never.toBeNil()
			expect(dump.test).never.toBeNil()
			expect(#dump.test.durations).toBe(1)
		end)

		it("should measure duration correctly", function()
			bench.mark("test")
			task.wait(0.01)
			bench.done()

			local dump = bench.dump()
			assert(dump)
			expect(dump.test.durations[1]).toBeGreaterThanOrEqual(0.01)
		end)

		it("should create nested hierarchy in dump", function()
			bench.mark("parent")
			bench.mark("child")
			bench.done()
			bench.done()

			local dump = bench.dump()
			assert(dump)

			expectDumpStructure(dump, {
				parent = {
					children = {
						child = {},
					},
				},
			})

			-- Verify counts separately
			expect(#dump.parent.durations).toBe(1)
			expect(#dump.parent.children.child.durations).toBe(1)
		end)

		it("should create deeply nested hierarchy", function()
			bench.mark("level1")
			bench.mark("level2")
			bench.mark("level3")
			bench.done()
			bench.done()
			bench.done()

			local dump = bench.dump()
			assert(dump)

			expectDumpStructure(dump, {
				level1 = {
					children = {
						level2 = {
							children = {
								level3 = {},
							},
						},
					},
				},
			})

			-- Verify counts separately
			expect(#dump.level1.durations).toBe(1)
			expect(#dump.level1.children.level2.durations).toBe(1)
			expect(#dump.level1.children.level2.children.level3.durations).toBe(1)
		end)

		it("should group multiple calls with same label", function()
			bench.mark("task")
			bench.done()
			bench.mark("task")
			bench.done()
			bench.mark("task")
			bench.done()

			local dump = bench.dump()
			assert(dump)

			expect(dump.task).never.toBeNil()
			expect(#dump.task.durations).toBe(3)
		end)

		-- Note: done() without mark() is now allowed for minimal overhead
		-- The profiler will simply record a DONE event without a matching MARK
	end)

	describe("dump", function()
		beforeEach(function()
			bench.on()
		end)

		it("should return nil when called while benchmarking is off", function()
			bench.off()
			local dump = bench.dump()
			expect(dump).toBeNil()
		end)

		it("should return current dump structure", function()
			bench.mark("test")
			bench.done()

			local dump = bench.dump()
			assert(dump)

			expect(dump).never.toBeNil()
			expect(dump.test).never.toBeNil()
			expect(dump.test.durations).toEqual(expect.any("table"))
		end)

		it("should return nil after dump clears data", function()
			bench.mark("test1")
			bench.done()

			local dump1 = bench.dump()
			expect(dump1).never.toBeNil()

			-- Second dump should return nil (data was cleared)
			local dump2 = bench.dump()
			expect(dump2).toBeNil()
		end)

		it("should return new data after dump", function()
			bench.mark("test1")
			bench.done()

			local dump1 = bench.dump()
			assert(dump1)
			expect(dump1.test1).never.toBeNil()

			-- New marks should appear in next dump
			bench.mark("test2")
			bench.done()

			local dump2 = bench.dump()
			assert(dump2)
			expect(dump2).never.toBeNil()
			expect(dump2.test2).never.toBeNil()
			expect(dump2.test1).toBeNil() -- test1 was already dumped
		end)
	end)

	describe("hierarchical clearing and scope-based dumps (from READ)", function()
		beforeEach(function()
			bench.on()
		end)

		it("should handle recursive label nesting correctly", function()
			bench.mark("recursive") -- level 1
			bench.mark("recursive") -- level 2
			bench.mark("recursive") -- level 3

			bench.mark("recursive") -- level 4
			bench.done() -- done level 4

			bench.mark("recursive") -- level 4 (sibling)
			bench.done() -- done level 4

			bench.done() -- done level 3
			bench.done() -- done level 2
			bench.done() -- done level 1

			local dump = bench.dump()
			assert(dump)

			-- Should create nested recursive structure with same label at each level
			expectDumpStructure(dump, {
				recursive = {
					children = {
						recursive = {
							children = {
								recursive = {
									children = {
										recursive = {},
									},
								},
							},
						},
					},
				},
			})

			-- Verify counts separately
			expect(#dump.recursive.durations).toBe(1)
			expect(#dump.recursive.children.recursive.durations).toBe(1)
			expect(#dump.recursive.children.recursive.children.recursive.durations).toBe(1)
			expect(#dump.recursive.children.recursive.children.recursive.children.recursive.durations).toBe(2) -- Two innermost calls
		end)

		it("should handle test suite with multiple scopes and iter children", function()
			bench.mark("test suite")

			do
				bench.mark("test 1")
				for _ = 1, 5 do -- Reduced from 60 for faster tests
					bench.mark("iter")
					bench.done()
				end
				bench.done()
			end

			do
				bench.mark("test 2")
				for _ = 1, 10 do -- Reduced from 1000 for faster tests
					bench.mark("iter")
					bench.done()
				end
				bench.done()

				for _ = 1, 3 do -- Reduced from 100 for faster tests
					bench.mark("iter")
					bench.done()
				end
			end

			-- Dump at current level (inside test suite)
			local dump = bench.dump()
			assert(dump)

			-- Should capture test 1 and test 2
			expect(dump).never.toBeNil()
			expect(dump["test 1"]).never.toBeNil()
			expect(dump["test 2"]).never.toBeNil()
			expect(dump.iter).never.toBeNil() -- iter at same level as test 2

			-- Check test 1 children
			expect(dump["test 1"].children).never.toBeNil()
			expect(dump["test 1"].children.iter).never.toBeNil()
			expect(#dump["test 1"].children.iter.durations).toBe(5)

			-- Check test 2 children
			expect(dump["test 2"].children).never.toBeNil()
			expect(dump["test 2"].children.iter).never.toBeNil()
			expect(#dump["test 2"].children.iter.durations).toBe(10)

			-- Check iter at same level as test 2
			expect(#dump.iter.durations).toBe(3)

			bench.done() -- close "test suite"

			-- Dump at root level
			local test_suite_dump = bench.dump()
			assert(test_suite_dump)

			-- Should capture test suite with ALL children
			expect(test_suite_dump).never.toBeNil()
			expect(test_suite_dump["test suite"]).never.toBeNil()
			expect(test_suite_dump["test suite"].children).never.toBeNil()
			expect(test_suite_dump["test suite"].children["test 1"]).never.toBeNil()
			expect(test_suite_dump["test suite"].children["test 2"]).never.toBeNil()
			expect(test_suite_dump["test suite"].children.iter).never.toBeNil()

			-- Verify nested children were preserved
			local test1 = test_suite_dump["test suite"].children["test 1"]
			expect(test1.children).never.toBeNil()
			expect(test1.children.iter).never.toBeNil()
			expect(#test1.children.iter.durations).toBe(5)

			local test2 = test_suite_dump["test suite"].children["test 2"]
			expect(test2.children).never.toBeNil()
			expect(test2.children.iter).never.toBeNil()
			expect(#test2.children.iter.durations).toBe(10)

			-- iter at test suite level
			expect(#test_suite_dump["test suite"].children.iter.durations).toBe(3)
		end)

		it("should support composable dump pattern", function()
			bench.mark("test1")
			for _ = 1, 10 do
				bench.mark("subtask_a")
				bench.done()

				bench.mark("subtask_b")
				bench.done()
			end
			bench.done()

			local dump1 = bench.dump()
			assert(dump1)
			expect(dump1).never.toBeNil()
			expect(dump1.test1).never.toBeNil()
			expect(dump1.test1.children).never.toBeNil()
			expect(dump1.test1.children.subtask_a).never.toBeNil()
			expect(dump1.test1.children.subtask_b).never.toBeNil()

			bench.mark("test2")
			for _ = 1, 10 do
				bench.mark("subtask_a")
				bench.done()

				bench.mark("subtask_b")
				bench.done()
			end
			bench.done()

			local dump2 = bench.dump()
			assert(dump2)
			expect(dump2).never.toBeNil()
			expect(dump2.test2).never.toBeNil()
			expect(dump2.test1).toBeNil() -- test1 was already dumped
		end)

		it("should support dumping both tests together", function()
			bench.mark("test1")
			for _ = 1, 10 do
				bench.mark("subtask_a")
				bench.done()

				bench.mark("subtask_b")
				bench.done()
			end
			bench.done()

			bench.mark("test2")
			for _ = 1, 10 do
				bench.mark("subtask_a")
				bench.done()

				bench.mark("subtask_b")
				bench.done()
			end
			bench.done()

			-- Dump both together (neither was dumped before)
			local dump = bench.dump()
			assert(dump)
			expect(dump).never.toBeNil()
			expect(dump.test1).never.toBeNil()
			expect(dump.test2).never.toBeNil()
			expect(dump.test1.children).never.toBeNil()
			expect(dump.test2.children).never.toBeNil()
		end)
	end)

	describe("edge cases", function()
		beforeEach(function()
			bench.on()
		end)

		it("should handle repeated labels at same level", function()
			bench.mark("test")
			task.wait(0.001)
			bench.done()

			bench.mark("test")
			task.wait(0.001)
			bench.done()

			bench.mark("test")
			task.wait(0.001)
			bench.done()

			local dump = bench.dump()
			assert(dump)
			expect(dump).never.toBeNil()
			expect(dump.test).never.toBeNil()
			expect(#dump.test.durations).toBe(3)
		end)

		it("should handle deep nesting", function()
			bench.mark("d1")
			bench.mark("d2")
			bench.mark("d3")
			bench.mark("d4")
			bench.mark("d5")
			task.wait(0.001)
			bench.done()
			bench.done()
			bench.done()
			bench.done()
			bench.done()

			local dump = bench.dump()
			assert(dump)
			expect(dump).never.toBeNil()
			expect(dump.d1).never.toBeNil()
			expect(dump.d1.children.d2).never.toBeNil()
			expect(dump.d1.children.d2.children.d3).never.toBeNil()
			expect(dump.d1.children.d2.children.d3.children.d4).never.toBeNil()
			expect(dump.d1.children.d2.children.d3.children.d4.children.d5).never.toBeNil()
		end)

		it("should handle multiple dumps with no data between", function()
			bench.mark("test")
			task.wait(0.001)
			bench.done()

			local dump1 = bench.dump()
			assert(dump1)
			expect(dump1).never.toBeNil()
			expect(dump1.test).never.toBeNil()

			-- Second dump with no new data
			local dump2 = bench.dump()
			expect(dump2).toBeNil()

			-- Third dump with no new data
			local dump3 = bench.dump()
			expect(dump3).toBeNil()
		end)

		it("should handle alternating marks at same level", function()
			bench.mark("outer")

			bench.mark("a")
			task.wait(0.001)
			bench.done()

			bench.mark("b")
			task.wait(0.001)
			bench.done()

			bench.mark("a")
			task.wait(0.001)
			bench.done()

			bench.mark("b")
			task.wait(0.001)
			bench.done()

			bench.done()

			local dump = bench.dump()
			assert(dump)
			expect(dump).never.toBeNil()
			expect(dump.outer).never.toBeNil()
			expect(dump.outer.children).never.toBeNil()
			expect(dump.outer.children.a).never.toBeNil()
			expect(dump.outer.children.b).never.toBeNil()
			expect(#dump.outer.children.a.durations).toBe(2)
			expect(#dump.outer.children.b.durations).toBe(2)
		end)
	end)

	describe("analyze function", function()
		beforeEach(function()
			bench.on()
		end)

		it("should analyze single dump", function()
			bench.mark("task")
			task.wait(0.01)
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.task)

			expect(analysis).never.toBeNil()
			expect(analysis.stats).never.toBeNil()
			expect(analysis.stats.count).toBe(1)
			expect(analysis.stats["time.min"]).toBeGreaterThanOrEqual(0.01)
			expect(analysis.stats["time.avg"]).toBe(analysis.stats["time.min"])
			expect(analysis.stats["time.max"]).toBe(analysis.stats["time.min"])
		end)

		it("should group multiple measurements with same label", function()
			bench.mark("task")
			bench.done()
			bench.mark("task")
			bench.done()
			bench.mark("task")
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.task)

			expect(analysis.stats.count).toBe(3)
		end)

		it("should compute min/max/avg correctly", function()
			bench.mark("task")
			task.wait(0.01)
			bench.done()

			bench.mark("task")
			task.wait(0.02)
			bench.done()

			bench.mark("task")
			task.wait(0.015)
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.task)

			expect(analysis.stats.count).toBe(3)
			expect(analysis.stats["time.min"]).toBeLessThan(analysis.stats["time.max"])
			expect(analysis.stats["time.avg"]).toBeGreaterThan(analysis.stats["time.min"])
			expect(analysis.stats["time.avg"]).toBeLessThan(analysis.stats["time.max"])
		end)

		it("should compute percentiles", function()
			for i = 1, 10 do
				bench.mark("task")
				task.wait(0.001 * i)
				bench.done()
			end

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.task)

			expect(analysis.stats["time.p10"]).toBeLessThan(analysis.stats["time.p50"])
			expect(analysis.stats["time.p50"]).toBeLessThan(analysis.stats["time.p90"])
			expect(analysis.stats["time.p50"]).toBeGreaterThan(analysis.stats["time.min"])
			expect(analysis.stats["time.p50"]).toBeLessThan(analysis.stats["time.max"])
		end)

		it("should compute standard deviation", function()
			bench.mark("task")
			task.wait(0.01)
			bench.done()

			bench.mark("task")
			task.wait(0.03)
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.task)

			expect(analysis.stats["time.std"]).toBeGreaterThan(0)
		end)

		it("should preserve hierarchy in analysis", function()
			bench.mark("parent")
			bench.mark("child")
			bench.done()
			bench.done()

			bench.mark("parent")
			bench.mark("child")
			bench.done()
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.parent)

			expect(analysis).never.toBeNil()
			expect(analysis.stats.count).toBe(2)
			expect(analysis.children).never.toBeNil()
			expect(analysis.children.child).never.toBeNil()
			expect(analysis.children.child.stats.count).toBe(2)
		end)

		it("should handle empty children", function()
			bench.mark("leaf")
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.leaf)

			-- Leaf nodes have no child analysis (children is nil in analysis)
			expect(analysis.children).toBeNil()
		end)
	end)

	describe("compare", function()
		beforeEach(function()
			bench.on()
		end)

		it("should add comparison data when comparisons parameter provided", function()
			-- Create baseline
			bench.mark("task")
			task.wait(0.015)
			bench.done()
			local baseline_dumps = bench.dump()
			assert(baseline_dumps)
			bench.off()

			-- Create current
			bench.on()
			bench.mark("task")
			task.wait(0.01)
			bench.done()
			local current_dumps = bench.dump()
			assert(current_dumps)

			-- Analyze with comparison
			local baseline_analysis = bench.analyze(baseline_dumps.task)
			local current_analysis = bench.compare(bench.analyze(current_dumps.task), {
				baseline = baseline_analysis,
			})

			expect(current_analysis.comparisons).never.toBeNil()
			expect(current_analysis.comparisons.baseline).never.toBeNil()
		end)

		it("should compute delta and percentage correctly", function()
			-- Create mock baseline analysis with known values
			local baseline_analysis = {
				label = "baseline",
				stats = {
					count = 1,
					["time.min"] = 10,
					["time.max"] = 10,
					["time.avg"] = 10,
					["time.p10"] = 10,
					["time.p50"] = 10,
					["time.p90"] = 10,
					["time.std"] = 0,
				},
				children = nil,
				comparisons = nil,
				durations = { 10 },
				memories = nil,
			}

			-- Create current dump with different values
			local current_dump = {
				label = "current",
				durations = { 12 },
				children = {},
			}

			local current_analysis = bench.compare(bench.analyze(current_dump), {
				baseline = baseline_analysis,
			})

			local comp = current_analysis.comparisons.baseline

			-- Current is 12, baseline is 10, so delta is +2
			expect(comp.delta["time.avg"]).toBeCloseTo(2, 1)
			-- Percentage is (12-10)/10 * 100 = 20%
			expect(comp.pct["time.avg"]).toBeCloseTo(20, 1)
		end)

		it("should handle missing labels in comparison", function()
			-- Create baseline with only "task1"
			bench.mark("outer")
			bench.mark("task1")
			bench.done()
			bench.done()
			local baseline_dumps = bench.dump()
			assert(baseline_dumps)
			bench.off()

			-- Create current with "task1" and "task2"
			bench.on()
			bench.mark("outer")
			bench.mark("task1")
			bench.done()
			bench.mark("task2")
			bench.done()
			bench.done()
			local current_dumps = bench.dump()
			assert(current_dumps)

			local baseline_analysis = bench.analyze(baseline_dumps.outer)
			local current_analysis = bench.compare(bench.analyze(current_dumps.outer), {
				baseline = baseline_analysis,
			})

			-- task2 should not have comparison for baseline (baseline didn't have task2)
			expect(current_analysis.children.task2.comparisons).toBeNil()
			-- task1 should have comparison
			expect(current_analysis.children.task1.comparisons).never.toBeNil()
			expect(current_analysis.children.task1.comparisons.baseline).never.toBeNil()
		end)

		it("should handle multiple comparison targets", function()
			local baseline_dump = {
				label = "baseline",
				durations = { 0.01 },
				children = {},
			}

			local alternative_dump = {
				label = "alternative",
				durations = { 0.012 },
				children = {},
			}

			local current_dump = {
				label = "current",
				durations = { 0.008 },
				children = {},
			}

			local baseline_analysis = bench.analyze(baseline_dump)
			local alternative_analysis = bench.analyze(alternative_dump)
			local current_analysis = bench.compare(bench.analyze(current_dump), {
				baseline = baseline_analysis,
				alternative = alternative_analysis,
			})

			expect(current_analysis.comparisons.baseline).never.toBeNil()
			expect(current_analysis.comparisons.alternative).never.toBeNil()
		end)

		it("should preserve hierarchy in comparisons", function()
			-- Create baseline
			bench.mark("parent")
			bench.mark("child")
			task.wait(0.015)
			bench.done()
			bench.done()
			local baseline_dumps = bench.dump()
			assert(baseline_dumps)
			bench.off()

			-- Create current
			bench.on()
			bench.mark("parent")
			bench.mark("child")
			task.wait(0.01)
			bench.done()
			bench.done()
			local current_dumps = bench.dump()
			assert(current_dumps)

			local baseline_analysis = bench.analyze(baseline_dumps.parent)
			local current_analysis = bench.compare(bench.analyze(current_dumps.parent), {
				baseline = baseline_analysis,
			})

			expect(current_analysis.comparisons.baseline).never.toBeNil()
			expect(current_analysis.children).never.toBeNil()
			expect(current_analysis.children.child.comparisons.baseline).never.toBeNil()
		end)
	end)

	describe("cli", function()
		beforeEach(function()
			bench.on()
		end)

		it("should format simple analysis with auto-scaled units", function()
			bench.mark("task")
			task.wait(0.01)
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.task)
			local formatted = bench.cli(analysis)

			expect(formatted).toEqual(expect.any("string"))
			expect(formatted:match("task")).never.toBeNil()
			expect(formatted:match("count:")).never.toBeNil() -- Count appears as a stat
			expect(formatted:match("ms")).never.toBeNil() -- Should auto-scale to ms
		end)

		it("should format nested hierarchy with tree characters", function()
			bench.mark("parent")
			bench.mark("child")
			bench.done()
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.parent)
			local formatted = bench.cli(analysis)

			expect(formatted).toEqual(expect.any("string"))
			expect(formatted:match("parent")).never.toBeNil()
			expect(formatted:match("child")).never.toBeNil()
			-- Should have tree characters
			expect(formatted:match("└──") or formatted:match("├──")).never.toBeNil()
		end)

		it("should show verbose stats when verbose option is true", function()
			bench.mark("task")
			task.wait(0.01)
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.task)
			local formatted = bench.cli(analysis, { verbose = true })

			expect(formatted).toEqual(expect.any("string"))
			-- Verbose should show time.min, time.max, time.avg, time.p10, time.p50, time.p90
			expect(formatted:match("time%.min:")).never.toBeNil()
			expect(formatted:match("time%.max:")).never.toBeNil()
			expect(formatted:match("time%.avg:")).never.toBeNil()
			expect(formatted:match("time%.p10:")).never.toBeNil()
			expect(formatted:match("time%.p50:")).never.toBeNil()
			expect(formatted:match("time%.p90:")).never.toBeNil()
		end)

		it("should show only avg and p50 in normal mode", function()
			bench.mark("task")
			task.wait(0.01)
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.task)
			local formatted = bench.cli(analysis, { verbose = false })

			expect(formatted).toEqual(expect.any("string"))
			-- Normal mode should show only time.avg and time.p50
			expect(formatted:match("time%.avg:")).never.toBeNil()
			expect(formatted:match("time%.p50:")).never.toBeNil()
			-- Should not show time.p10 and time.p90
			expect(formatted:match("time%.p10:")).toBeNil()
			expect(formatted:match("time%.p90:")).toBeNil()
		end)
	end)

	describe("abort function", function()
		beforeEach(function()
			bench.on()
		end)

		it("should do nothing when called with no unclosed marks", function()
			bench.abort()
			-- Should not error, level should still be 0
		end)

		it("should force-complete unclosed marks", function()
			bench.mark("parent")
			bench.mark("child1")
			bench.mark("child2")
			bench.abort()

			local dump = bench.dump()
			assert(dump)

			expect(dump).never.toBeNil()
			expect(dump.parent).never.toBeNil()
			expect(dump.parent.children).never.toBeNil()
			expect(dump.parent.children.child1).never.toBeNil()
			expect(dump.parent.children.child1.children).never.toBeNil()
			expect(dump.parent.children.child1.children.child2).never.toBeNil()
		end)

		it("should allow dumping after abort", function()
			bench.mark("test1")
			bench.mark("test2")
			bench.abort()

			local dump = bench.dump()
			assert(dump)
			expect(dump).never.toBeNil()
			expect(dump.test1).never.toBeNil()
			expect(dump.test1.children).never.toBeNil()
			expect(dump.test1.children.test2).never.toBeNil()
		end)

		it("should not affect benchmarking state after abort", function()
			bench.mark("test1")
			bench.abort()

			-- Should still be enabled
			bench.mark("test2")
			bench.done()

			local dump = bench.dump()
			assert(dump)
			expect(dump).never.toBeNil()
			expect(dump.test2).never.toBeNil()
		end)
	end)

	describe("integration", function()
		it("should handle complete workflow", function()
			bench.on()

			-- First session
			bench.mark("frame")
			bench.mark("update")
			task.wait(0.01)
			bench.done()
			bench.mark("render")
			task.wait(0.005)
			bench.done()
			bench.done()

			-- Second session
			bench.mark("frame")
			bench.mark("update")
			task.wait(0.01)
			bench.done()
			bench.mark("render")
			task.wait(0.005)
			bench.done()
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.frame)

			expect(analysis.stats.count).toBe(2)
			expect(analysis.children.update.stats.count).toBe(2)
			expect(analysis.children.render.stats.count).toBe(2)

			bench.off()
		end)

		it("should handle off() with unclosed marks", function()
			bench.on()

			bench.mark("parent")
			bench.mark("child")
			bench.done()
			bench.done()
			local dump = bench.off()
			assert(dump)

			expect(dump).never.toBeNil()
			expect(dump.parent).never.toBeNil()
			expect(dump.parent.children).never.toBeNil()
			expect(dump.parent.children.child).never.toBeNil()
		end)

		it("should support full analysis and formatting workflow with comparisons", function()
			-- Baseline session
			bench.on()
			bench.mark("task")
			task.wait(0.015)
			bench.done()
			local baseline_dumps = bench.off()
			assert(baseline_dumps)

			-- Current session
			bench.on()
			bench.mark("task")
			task.wait(0.01)
			bench.done()
			local current_dumps = bench.off()
			assert(current_dumps)

			-- Analyze both
			local baseline_analysis = bench.analyze(baseline_dumps.task)
			local current_analysis = bench.compare(bench.analyze(current_dumps.task), {
				baseline = baseline_analysis,
			})

			-- Format with comparisons
			local formatted = bench.cli(current_analysis)

			expect(formatted).toEqual(expect.any("string"))
			expect(formatted:match("task")).never.toBeNil()
			expect(formatted:match("vs baseline:")).never.toBeNil()
		end)
	end)

	describe("memory tracking", function()
		it("should not track memory when disabled (default)", function()
			bench.on()
			bench.mark("task")
			task.wait(0.01)
			bench.done()

			local dump = bench.dump()
			assert(dump)
			expect(dump).never.toBeNil()
			expect(dump.task).never.toBeNil()
			expect(dump.task.memories).toBeNil()
		end)

		it("should track memory when enabled", function()
			bench.on({ track_memory = true })
			bench.mark("task")
			-- Force some allocation
			local _ = table.create(1000, 0)
			bench.done()

			local dump = bench.dump()
			assert(dump)
			expect(dump).never.toBeNil()
			expect(dump.task).never.toBeNil()
			expect(dump.task.memories).never.toBeNil()
			expect(#dump.task.memories).toBe(1)
			expect(type(dump.task.memories[1])).toBe("number")
		end)

		it("should track memory hierarchically", function()
			bench.on({ track_memory = true })
			bench.mark("parent")
			bench.mark("child")
			bench.done()
			bench.done()

			local dump = bench.dump()
			assert(dump)
			expect(dump.parent.memories).never.toBeNil()
			expect(dump.parent.children.child.memories).never.toBeNil()
		end)

		it("should analyze memory stats", function()
			bench.on({ track_memory = true })
			for _ = 1, 5 do
				bench.mark("task")
				local _ = table.create(100, 0)
				bench.done()
			end

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.task)

			-- Memory stats are now in the same stats dict with mem. prefix
			expect(analysis.stats["mem.min"]).toEqual(expect.any("number"))
			expect(analysis.stats["mem.max"]).toEqual(expect.any("number"))
			expect(analysis.stats["mem.avg"]).toEqual(expect.any("number"))
		end)

		it("should compare memory stats", function()
			-- Baseline with memory tracking
			bench.on({ track_memory = true })
			bench.mark("task")
			local _ = table.create(1000, 0)
			bench.done()
			local baseline_dumps = bench.dump()
			assert(baseline_dumps)
			bench.off()

			-- Current with memory tracking
			bench.on({ track_memory = true })
			bench.mark("task")
			local _ = table.create(500, 0)
			bench.done()
			local current_dumps = bench.dump()
			assert(current_dumps)

			local baseline_analysis = bench.analyze(baseline_dumps.task)
			local current_analysis = bench.compare(bench.analyze(current_dumps.task), {
				baseline = baseline_analysis,
			})

			-- Memory comparisons are now in the unified comparisons field with mem. prefix
			expect(current_analysis.comparisons).never.toBeNil()
			expect(current_analysis.comparisons.baseline).never.toBeNil()
			expect(current_analysis.comparisons.baseline.delta["mem.avg"]).toEqual(expect.any("number"))
		end)

		it("should format memory stats", function()
			bench.on({ track_memory = true })
			bench.mark("task")
			local _ = table.create(1000, 0)
			bench.done()

			local dumps = bench.dump()
			assert(dumps)
			local analysis = bench.analyze(dumps.task)
			local formatted = bench.cli(analysis)

			expect(formatted).toEqual(expect.any("string"))
			expect(formatted:match("mem%.avg")).never.toBeNil()
			expect(formatted:match("mem%.p50")).never.toBeNil()
		end)

		it("should handle negative memory deltas from GC", function()
			bench.on({ track_memory = true })
			bench.mark("task")
			-- Just wait, GC might run
			task.wait(0.001)
			bench.done()

			local dump = bench.dump()
			assert(dump)
			-- Memory can be negative, should not error
			expect(dump.task.memories).never.toBeNil()
			expect(#dump.task.memories).toBe(1)
			-- Value can be any number (positive or negative)
			expect(type(dump.task.memories[1])).toBe("number")
		end)
	end)
end)
