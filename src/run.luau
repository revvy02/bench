-- templates for bench runners

local analyzer = require(script.Parent.analyzer)
local cli = require(script.Parent.cli)
local profiler = require(script.Parent.profiler)
local sampler = require(script.Parent.sampler)

local mark, done = profiler.mark, profiler.done

export type WarmupConfig = {
	enabled: boolean?, -- default: true
	iterations: number?, -- default: 5
}

export type ConvergenceConfig = {
	enabled: boolean?, -- default: true
	min_iterations: number?, -- default: 10
	max_iterations: number?, -- default: 10000
	target_cv: number?, -- default: 5.0 (%)
	target_precision: number?, -- default: 0.05 (±5%)
}

export type TemplateConfig<T> = {
	verbose: boolean?,
	track_memory: boolean?,
	baselines: { [string]: (T) -> () },
	comparisons: { [string]: (T) -> () }?,
	params: (() -> T)?,
	before_all: () -> ()?,
	after_all: () -> ()?,
	before_each: () -> ()?,
	after_each: () -> ()?,
	warmup: WarmupConfig?,
	convergence: ConvergenceConfig?,
	min_duration: number?, -- default: 3.0 (seconds), minimum duration before convergence check
	max_duration: number?, -- default: nil (no limit), maximum duration in seconds before auto-stop
	batch: boolean?, -- default: false, run each baseline/comparison to completion sequentially instead of interleaving
	score: ((analyzer.Stats) -> number)?, -- default: (stats) -> stats["time.p50"], used for race mode
	race: boolean?, -- default: true, if false disables race mode even with multiple baselines
}

export type TemplateResult = {
	name: string,
	analysis: analyzer.Analysis,
}

-- Default configuration values
local DEFAULT_WARMUP_ITERATIONS = 5
local DEFAULT_MIN_ITERATIONS = 10
local DEFAULT_MAX_ITERATIONS = 10000
local DEFAULT_TARGET_CV = 5.0
local DEFAULT_TARGET_PRECISION = 0.05
local DEFAULT_MIN_DURATION = 3.0

-- Default score function (lower is better)
local function default_score(stats: analyzer.Stats): number
	return stats["time.p50"] or math.huge
end

-- Utility: Run a single benchmark with lifecycle hooks
local function run_single_benchmark<T>(name: string, fn: (T) -> (), params: (() -> T)?, before_each: (() -> ())?, after_each: (() -> ())?)
	if before_each then
		before_each()
	end
	local generated_params = params and params()
	mark(name)
	fn(generated_params)
	done()
	if after_each then
		after_each()
	end
end

-- Utility: Run a set of benchmarks
local function run_benchmark_set<T>(benchmarks: { [string]: (T) -> () }, params: (() -> T)?, before_each: (() -> ())?, after_each: (() -> ())?)
	for name, fn in benchmarks do
		run_single_benchmark(name, fn, params, before_each, after_each)
	end
end

-- Convergence: Check if we should continue based on convergence criteria
local function should_continue_convergence(
	iteration: number,
	elapsed: number,
	benchmarks_to_check: { string },
	config: {
		min_iterations: number,
		max_iterations: number,
		min_duration: number,
		max_duration: number?,
		target_cv: number,
		target_precision: number,
	}
): boolean
	-- Hard limits
	if iteration >= config.max_iterations then
		return false
	end
	if config.max_duration and elapsed >= config.max_duration then
		return false
	end

	-- Need to reach minimum iterations before checking convergence
	if iteration < config.min_iterations then
		return true
	end

	-- Check convergence every 10 iterations for performance
	if iteration % 10 ~= 0 then
		return true
	end

	local current_dump = profiler.peek()
	if not current_dump then
		return true
	end

	-- Check if all benchmarks have converged
	local all_converged = true
	for _, name in benchmarks_to_check do
		if current_dump[name] and current_dump[name].durations then
			local needs_more = sampler.needs_more_samples(current_dump[name].durations, config.target_cv, config.target_precision)
			if needs_more then
				all_converged = false
				break
			end
		end
	end

	-- Converged if: all stable AND precise AND minimum duration met
	if all_converged and elapsed >= config.min_duration then
		return false
	end

	return true
end

-- Convergence: Check if we should continue based on duration only
local function should_continue_duration(
	iteration: number,
	elapsed: number,
	config: {
		max_duration: number?,
		fallback_iterations: number, -- Used if no max_duration
	}
): boolean
	if config.max_duration then
		return elapsed < config.max_duration
	else
		-- Legacy: fixed iteration count
		return iteration < config.fallback_iterations
	end
end

-- Execution: Run warmup phase
local function run_warmup<T>(
	baselines: { [string]: (T) -> () },
	comparisons: { [string]: (T) -> () }?,
	config: {
		iterations: number,
		params: (() -> T)?,
		before_each: (() -> ())?,
		after_each: (() -> ())?,
	}
)
	for _ = 1, config.iterations do
		run_benchmark_set(baselines, config.params, config.before_each, config.after_each)
		if comparisons then
			run_benchmark_set(comparisons, config.params, config.before_each, config.after_each)
		end
	end
	-- Discard warmup results
	profiler.dump()
end

-- Execution: Run benchmarks with unified logic for both batch and interleaved modes
local function run_benchmarks<T>(
	baselines: { [string]: (T) -> () },
	comparisons: { [string]: (T) -> () }?,
	config: {
		batch: boolean,
		convergence_enabled: boolean,
		params: (() -> T)?,
		before_each: (() -> ())?,
		after_each: (() -> ())?,
		min_iterations: number,
		max_iterations: number,
		min_duration: number,
		max_duration: number?,
		target_cv: number,
		target_precision: number,
	}
)
	profiler.mark("template")

	if config.batch then
		-- BATCH MODE: Run each benchmark to completion sequentially
		local all_benchmarks = {}
		for name, fn in baselines do
			table.insert(all_benchmarks, { name = name, fn = fn })
		end
		if comparisons then
			for name, fn in comparisons do
				table.insert(all_benchmarks, { name = name, fn = fn })
			end
		end

		for _, bench in all_benchmarks do
			local bench_iteration = 0
			local bench_start_time = os.clock()

			if config.convergence_enabled then
				-- Convergence-based execution for this benchmark
				while
					should_continue_convergence(bench_iteration, os.clock() - bench_start_time, { bench.name }, {
						min_iterations = config.min_iterations,
						max_iterations = config.max_iterations,
						min_duration = config.min_duration,
						max_duration = config.max_duration,
						target_cv = config.target_cv,
						target_precision = config.target_precision,
					})
				do
					run_single_benchmark(bench.name, bench.fn, config.params, config.before_each, config.after_each)
					bench_iteration += 1
				end
			else
				-- Duration-based execution for this benchmark
				while
					should_continue_duration(bench_iteration, os.clock() - bench_start_time, {
						max_duration = config.max_duration,
						fallback_iterations = 1000,
					})
				do
					run_single_benchmark(bench.name, bench.fn, config.params, config.before_each, config.after_each)
					bench_iteration += 1
				end
			end
		end
	else
		-- INTERLEAVED MODE: Run all benchmarks together per iteration
		local iteration = 0
		local start_time = os.clock()

		if config.convergence_enabled then
			-- Build list of all benchmark names for convergence checking
			local all_benchmark_names = {}
			for name in baselines do
				table.insert(all_benchmark_names, name)
			end
			if comparisons then
				for name in comparisons do
					table.insert(all_benchmark_names, name)
				end
			end

			-- Convergence-based execution
			while
				should_continue_convergence(iteration, os.clock() - start_time, all_benchmark_names, {
					min_iterations = config.min_iterations,
					max_iterations = config.max_iterations,
					min_duration = config.min_duration,
					max_duration = config.max_duration,
					target_cv = config.target_cv,
					target_precision = config.target_precision,
				})
			do
				run_benchmark_set(baselines, config.params, config.before_each, config.after_each)
				if comparisons then
					run_benchmark_set(comparisons, config.params, config.before_each, config.after_each)
				end
				iteration += 1
			end
		else
			-- Duration-based execution
			while
				should_continue_duration(iteration, os.clock() - start_time, {
					max_duration = config.max_duration,
					fallback_iterations = 1000,
				})
			do
				run_benchmark_set(baselines, config.params, config.before_each, config.after_each)
				if comparisons then
					run_benchmark_set(comparisons, config.params, config.before_each, config.after_each)
				end
				iteration += 1
			end
		end
	end

	profiler.done() -- closes template mark
end

-- Processing: Convert dumps to analyses
local function create_analyses(dumps: { [string]: any }, benchmark_names: { string }): { [string]: analyzer.Analysis }
	local analyses = {}
	for _, name in benchmark_names do
		if dumps[name] then
			analyses[name] = analyzer.analyze(dumps[name])
		end
	end
	return analyses
end

-- Processing: Detect if we're in race mode (multiple baselines, no comparisons)
local function is_race_mode(baselines: { [string]: any }, comparisons: { [string]: any }?): boolean
	if comparisons and next(comparisons) then
		return false
	end

	local baseline_count = 0
	for _ in baselines do
		baseline_count += 1
		if baseline_count > 1 then
			return true
		end
	end

	return false
end

-- Processing: Find the winner in race mode using score function
local function find_winner(analyses: { [string]: analyzer.Analysis }, score_fn: (analyzer.Stats) -> number): (string, analyzer.Analysis)
	local best_name = nil
	local best_analysis = nil
	local best_score = math.huge

	for name, analysis in analyses do
		local score = score_fn(analysis.stats)
		if score < best_score then
			best_score = score
			best_name = name
			best_analysis = analysis
		end
	end

	assert(best_name and best_analysis, "No winner found in race mode")
	return best_name, best_analysis
end

-- Processing: Create comparison results
local function create_comparison_results(
	baseline_analyses: { [string]: analyzer.Analysis },
	comparison_analyses: { [string]: analyzer.Analysis }?
): { TemplateResult }
	local results: { TemplateResult } = {}

	if comparison_analyses and next(comparison_analyses) then
		-- Create comparisons between baselines and comparisons
		for name, analysis in baseline_analyses do
			table.insert(results, {
				name = name,
				analysis = analyzer.compare(analysis, comparison_analyses),
			})
		end
	else
		-- No comparisons, just return analyses
		for name, analysis in baseline_analyses do
			table.insert(results, {
				name = name,
				analysis = analysis,
			})
		end
	end

	return results
end

-- Processing: Sort and format results
local function sort_and_format_results(results: { TemplateResult }, score_fn: (analyzer.Stats) -> number, verbose: boolean?)
	-- Sort by score (ascending, best first)
	table.sort(results, function(a, b)
		local a_score = score_fn(a.analysis.stats)
		local b_score = score_fn(b.analysis.stats)
		return a_score < b_score
	end)

	-- Format and print
	for _, result in results do
		print(cli(result.analysis, {
			verbose = verbose,
		}))
	end
end

local function BENCH_template<T>(benchmark: TemplateConfig<T>)
	-- Parse configuration
	local baselines = benchmark.baselines
	local comparisons = benchmark.comparisons
	local params = benchmark.params
	local before_all = benchmark.before_all
	local after_all = benchmark.after_all
	local before_each = benchmark.before_each
	local after_each = benchmark.after_each

	local warmup_enabled = if benchmark.warmup then (benchmark.warmup.enabled ~= false) else true
	local warmup_iterations = if benchmark.warmup and benchmark.warmup.iterations then benchmark.warmup.iterations else DEFAULT_WARMUP_ITERATIONS

	local convergence_enabled = if benchmark.convergence then (benchmark.convergence.enabled ~= false) else false
	local min_iterations = if benchmark.convergence and benchmark.convergence.min_iterations
		then benchmark.convergence.min_iterations
		else DEFAULT_MIN_ITERATIONS
	local max_iterations = if benchmark.convergence and benchmark.convergence.max_iterations
		then benchmark.convergence.max_iterations
		else DEFAULT_MAX_ITERATIONS
	local target_cv = if benchmark.convergence and benchmark.convergence.target_cv then benchmark.convergence.target_cv else DEFAULT_TARGET_CV
	local target_precision = if benchmark.convergence and benchmark.convergence.target_precision
		then benchmark.convergence.target_precision
		else DEFAULT_TARGET_PRECISION
	local min_duration = benchmark.min_duration or DEFAULT_MIN_DURATION
	local max_duration = benchmark.max_duration
	local batch = benchmark.batch or false
	local score_fn = benchmark.score or default_score
	local race = benchmark.race ~= false -- default true

	-- Initialize profiler
	profiler.on({
		track_memory = benchmark.track_memory,
	})

	-- Lifecycle: before_all
	if before_all then
		before_all()
	end

	-- Phase 1: Warmup
	if warmup_enabled then
		run_warmup(baselines, comparisons, {
			iterations = warmup_iterations,
			params = params,
			before_each = before_each,
			after_each = after_each,
		})
	end

	-- Phase 2: Measurement
	run_benchmarks(baselines, comparisons, {
		batch = batch,
		convergence_enabled = convergence_enabled,
		params = params,
		before_each = before_each,
		after_each = after_each,
		min_iterations = min_iterations,
		max_iterations = max_iterations,
		min_duration = min_duration,
		max_duration = max_duration,
		target_cv = target_cv,
		target_precision = target_precision,
	})

	-- Lifecycle: after_all
	if after_all then
		after_all()
	end

	-- Phase 3: Analysis
	local raw = profiler.raw()
	local dumps = profiler.off().template.children
	assert(dumps, "No dumps found")

	-- Get all baseline names
	local baseline_names = {}
	for name in baselines do
		table.insert(baseline_names, name)
	end

	local baseline_analyses = create_analyses(dumps, baseline_names)
	local comparison_analyses = nil

	-- Race mode detection and transformation
	if race and is_race_mode(baselines, comparisons) then
		-- Find the winner
		local winner_name, winner_analysis = find_winner(baseline_analyses, score_fn)

		-- Transform: winner becomes baseline, rest become comparisons
		comparison_analyses = baseline_analyses
		comparison_analyses[winner_name] = nil
		baseline_analyses = { [winner_name] = winner_analysis }
	elseif comparisons then
		-- Normal comparison mode
		local comparison_names = {}
		for name in comparisons do
			table.insert(comparison_names, name)
		end
		comparison_analyses = create_analyses(dumps, comparison_names)
	end

	-- Phase 4: Create results with comparisons
	local results = create_comparison_results(baseline_analyses, comparison_analyses)

	-- Phase 5: Sort and format
	sort_and_format_results(results, score_fn, benchmark.verbose)

	return raw
end

return BENCH_template
