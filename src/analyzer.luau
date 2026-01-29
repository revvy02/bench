-- Stat metadata configuration
local config = require(script.Parent.config)
local profiler = require(script.Parent.profiler)
local sampler = require(script.Parent.sampler)

local STAT_METADATA = config.STAT_METADATA

-- analysis functions
export type Stats = { [string]: number }

export type ComparisonData = {
	stats: Stats,
	delta: { [string]: number },
	pct: { [string]: number },
	significance: { [string]: number }?, -- t_statistic, p_value, is_significant, is_practically_significant, stars, cohens_d, effect_size, ci_diff_lower, ci_diff_upper
}

export type Analysis = {
	label: string,
	stats: Stats,
	comparisons: { [string]: ComparisonData? }?,
	children: { [string]: Analysis }?,
	-- Raw samples for statistical comparisons
	durations: { number },
	memories: { number }?,
}

export type PrunedAnalysis = {
	label: string,
	stats: Stats,
	comparisons: { [string]: ComparisonData? }?,
	children: { [string]: PrunedAnalysis }?,
}

local analyzer = {}

-- Constants
local STAT_SUFFIXES = {
	"min",
	"max",
	"avg",
	"p10",
	"p50",
	"p90",
	"std",
	"mad",
	"cv",
	"median",
	"se",
	"ci_lower",
	"ci_upper",
	"ci_width",
	"iqr",
	"mild_outliers",
	"severe_outliers",
	"is_stable",
	"is_precise",
	"total",
}

-- Compute statistics from array of values with a given prefix (e.g., "time", "mem")
local function compute_stats(values: { number }, prefix: string, target_cv: number?, target_precision: number?): { [string]: number }
	local count = #values

	if count == 0 then
		local empty = {}
		for _, suffix in STAT_SUFFIXES do
			empty[prefix .. "." .. suffix] = 0
		end
		return empty
	end

	-- Use enhanced analysis from utils/analysis
	local stats = sampler.analyze(values, {
		confidence_level = 0.95,
		target_cv = target_cv,
		target_precision = target_precision,
	})

	-- Calculate total (sum of all values)
	local total = 0
	for _, v in values do
		total += v
	end

	-- Convert to flat key-value format with prefix
	return {
		[prefix .. ".min"] = stats.min,
		[prefix .. ".max"] = stats.max,
		[prefix .. ".avg"] = stats.mean,
		[prefix .. ".p10"] = stats.p10,
		[prefix .. ".p50"] = stats.p50,
		[prefix .. ".p90"] = stats.p90,
		[prefix .. ".std"] = stats.std,
		[prefix .. ".mad"] = stats.mad,
		[prefix .. ".cv"] = stats.cv,
		[prefix .. ".median"] = stats.median,
		[prefix .. ".se"] = stats.se,
		[prefix .. ".ci_lower"] = stats.ci_lower,
		[prefix .. ".ci_upper"] = stats.ci_upper,
		[prefix .. ".ci_width"] = stats.ci_width,
		[prefix .. ".iqr"] = stats.iqr,
		[prefix .. ".mild_outliers"] = stats.mild_outliers,
		[prefix .. ".severe_outliers"] = stats.severe_outliers,
		[prefix .. ".is_stable"] = if stats.is_stable then 1 else 0,
		[prefix .. ".is_precise"] = if stats.is_precise then 1 else 0,
		[prefix .. ".total"] = total,
	}
end

local function compute_delta_pct(curr_val: number, target_val: number)
	local delta = curr_val - target_val
	local pct = (delta / target_val) * 100
	return delta, pct
end

local function merge_into(dest: { [string]: number }, source: { [string]: number })
	for key, value in source do
		dest[key] = value
	end
end

-- Compute comparison data between two analysis nodes
local function compare_nodes(
	current_stats: Stats,
	target_stats: Stats,
	current_durations: { number },
	target_durations: { number },
	current_memories: { number }?,
	target_memories: { number }?
): ComparisonData
	local delta: { [string]: number } = {}
	local pct: { [string]: number } = {}
	local significance: { [string]: number } = {}

	-- Iterate over all keys in current stats for basic delta/pct
	for key, curr_val in current_stats do
		local target_val = target_stats[key]
		local metadata = STAT_METADATA[key]

		-- Only compute comparison if stat has metadata
		if target_val and metadata then
			local delta_val, pct_val = compute_delta_pct(curr_val, target_val)
			delta[key] = delta_val
			pct[key] = pct_val
		end
	end

	-- Perform statistical comparison on time samples
	local time_comparison = sampler.compare(current_durations, target_durations, {
		confidence_level = 0.95,
		significance_level = 0.05,
		noise_threshold = 0.01,
	})

	-- Add time significance stats with "time." prefix
	significance["time.t_statistic"] = time_comparison.t_statistic
	significance["time.df"] = time_comparison.df
	significance["time.p_value"] = time_comparison.p_value
	significance["time.is_significant"] = if time_comparison.is_significant then 1 else 0
	significance["time.is_practically_significant"] = if time_comparison.is_practically_significant then 1 else 0
	significance["time.cohens_d"] = time_comparison.cohens_d
	significance["time.mean_diff"] = time_comparison.mean_diff
	significance["time.ci_diff_lower"] = time_comparison.ci_diff_lower
	significance["time.ci_diff_upper"] = time_comparison.ci_diff_upper

	-- Perform statistical comparison on memory samples if present
	if current_memories and target_memories then
		local mem_comparison = sampler.compare(current_memories, target_memories, {
			confidence_level = 0.95,
			significance_level = 0.05,
			noise_threshold = 0.01,
		})

		-- Add memory significance stats with "mem." prefix
		significance["mem.t_statistic"] = mem_comparison.t_statistic
		significance["mem.df"] = mem_comparison.df
		significance["mem.p_value"] = mem_comparison.p_value
		significance["mem.is_significant"] = if mem_comparison.is_significant then 1 else 0
		significance["mem.is_practically_significant"] = if mem_comparison.is_practically_significant then 1 else 0
		significance["mem.cohens_d"] = mem_comparison.cohens_d
		significance["mem.mean_diff"] = mem_comparison.mean_diff
		significance["mem.ci_diff_lower"] = mem_comparison.ci_diff_lower
		significance["mem.ci_diff_upper"] = mem_comparison.ci_diff_upper
	end

	return {
		stats = target_stats,
		delta = delta,
		pct = pct,
		significance = significance,
	}
end

local function BENCH_ANALYZE(dump: profiler.Dump): Analysis
	local stats: Stats = {
		count = #dump.durations,
	}

	-- Merge time stats
	merge_into(stats, compute_stats(dump.durations, "time"))

	-- Merge memory stats if present
	if dump.memories then
		merge_into(stats, compute_stats(dump.memories, "mem"))
	end

	-- Process children
	local child_analysis: { [string]: Analysis }? = nil
	if next(dump.children) then
		child_analysis = {}
		for label, child_dump in dump.children do
			child_analysis[label] = BENCH_ANALYZE(child_dump)
		end
	end

	return {
		label = dump.label,
		stats = stats,
		children = child_analysis,
		comparisons = nil,
		durations = dump.durations,
		memories = dump.memories,
	}
end

local function BENCH_COMPARE(primary: Analysis, comparisons: { [string]: Analysis }): Analysis
	local comparison_data: { [string]: ComparisonData? } = {}

	for comp_name, comp_node in comparisons do
		comparison_data[comp_name] = compare_nodes(primary.stats, comp_node.stats, primary.durations, comp_node.durations, primary.memories, comp_node.memories)
	end

	local child_result: { [string]: Analysis }? = nil

	if primary.children then
		child_result = {}
		for label, child_node in primary.children do
			local child_comparisons: { [string]: Analysis } = {}

			for comp_name, comp_node in comparisons do
				if comp_node.children and comp_node.children[label] then
					child_comparisons[comp_name] = comp_node.children[label]
				end
			end

			if next(child_comparisons) then
				child_result[label] = BENCH_COMPARE(child_node, child_comparisons)
			else
				child_result[label] = child_node
			end
		end
	end

	return {
		label = primary.label,
		stats = primary.stats,
		children = child_result,
		comparisons = comparison_data,
		durations = primary.durations,
		memories = primary.memories,
	}
end

local function BENCH_PRUNE(analysis: Analysis): PrunedAnalysis
	local pruned_children: { [string]: PrunedAnalysis }? = nil
	if analysis.children then
		pruned_children = {}
		for label, child in analysis.children do
			pruned_children[label] = BENCH_PRUNE(child)
		end
	end

	return {
		label = analysis.label,
		stats = analysis.stats,
		comparisons = analysis.comparisons,
		children = pruned_children,
	}
end

analyzer.analyze = BENCH_ANALYZE
analyzer.compare = BENCH_COMPARE
analyzer.prune = BENCH_PRUNE

return analyzer
