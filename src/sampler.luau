--!strict
--!native
--!optimize 2

-- Statistical analysis module for benchmarking
-- Provides confidence intervals, significance testing, and convergence detection

-- Types
export type Sample = { number }

export type AnalyzeOptions = {
	confidence_level: number?, -- default 0.95 (95% CI)
	cv_threshold: number?, -- default 5.0 (%)
	precision_threshold: number?, -- default 0.05 (±5% of mean)
}

export type SampleStats = {
	n: number, -- sample size
	mean: number,
	std: number, -- standard deviation
	variance: number,
	min: number,
	max: number,

	-- Reliability indicators
	se: number, -- standard error
	cv: number, -- coefficient of variation (%)
	ci_lower: number, -- confidence interval lower bound
	ci_upper: number, -- confidence interval upper bound
	ci_width: number, -- width of confidence interval

	-- Robust statistics
	median: number,
	mad: number, -- median absolute deviation (robust alternative to std)
	p10: number, -- 10th percentile
	p50: number, -- 50th percentile (same as median)
	p90: number, -- 90th percentile

	-- Outlier detection (IQR-based)
	iqr: number, -- interquartile range (Q3 - Q1)
	mild_outliers: number, -- count outside Q1-1.5×IQR, Q3+1.5×IQR
	severe_outliers: number, -- count outside Q1-3×IQR, Q3+3×IQR

	-- Quality indicators (for convergence)
	is_stable: boolean, -- CV below threshold
	is_precise: boolean, -- CI narrow enough
}

export type CompareOptions = {
	confidence_level: number?, -- default 0.95
	significance_level: number?, -- default 0.05
	noise_threshold: number?, -- default 0.01 (1% minimum change to be practically significant)
}

export type ComparisonResult = {
	t_statistic: number,
	df: number, -- degrees of freedom
	p_value: number,

	-- Interpretations
	is_significant: boolean, -- p < significance_level
	is_practically_significant: boolean, -- significant AND exceeds noise threshold
	significance_level: number, -- actual threshold passed (0.001, 0.01, 0.05, or 1.0)
	stars: string, -- "", "*", "**", "***"

	-- Effect size
	cohens_d: number,
	effect_size: string, -- "trivial", "small", "medium", "large"

	-- Practical info
	mean_diff: number,
	ci_diff_lower: number, -- CI of the difference
	ci_diff_upper: number,
}

-- Constants
local DEFAULT_CONFIDENCE_LEVEL = 0.95
local DEFAULT_CV_THRESHOLD = 5.0
local DEFAULT_PRECISION_THRESHOLD = 0.05
local DEFAULT_SIGNIFICANCE_LEVEL = 0.05
local DEFAULT_NOISE_THRESHOLD = 0.01 -- 1% minimum change

-- T-distribution critical values (two-tailed) for 95% confidence
-- Source: Standard statistical tables
local T_CRITICAL_95 = {
	[1] = 12.706,
	[2] = 4.303,
	[3] = 3.182,
	[4] = 2.776,
	[5] = 2.571,
	[6] = 2.447,
	[7] = 2.365,
	[8] = 2.306,
	[9] = 2.262,
	[10] = 2.228,
	[11] = 2.201,
	[12] = 2.179,
	[13] = 2.160,
	[14] = 2.145,
	[15] = 2.131,
	[16] = 2.120,
	[17] = 2.110,
	[18] = 2.101,
	[19] = 2.093,
	[20] = 2.086,
	[21] = 2.080,
	[22] = 2.074,
	[23] = 2.069,
	[24] = 2.064,
	[25] = 2.060,
	[26] = 2.056,
	[27] = 2.052,
	[28] = 2.048,
	[29] = 2.045,
	[30] = 2.042,
}

-- T-distribution critical values (two-tailed) for 99% confidence
local T_CRITICAL_99 = {
	[1] = 63.657,
	[2] = 9.925,
	[3] = 5.841,
	[4] = 4.604,
	[5] = 4.032,
	[6] = 3.707,
	[7] = 3.499,
	[8] = 3.355,
	[9] = 3.250,
	[10] = 3.169,
	[11] = 3.106,
	[12] = 3.055,
	[13] = 3.012,
	[14] = 2.977,
	[15] = 2.947,
	[16] = 2.921,
	[17] = 2.898,
	[18] = 2.878,
	[19] = 2.861,
	[20] = 2.845,
	[21] = 2.831,
	[22] = 2.819,
	[23] = 2.807,
	[24] = 2.797,
	[25] = 2.787,
	[26] = 2.779,
	[27] = 2.771,
	[28] = 2.763,
	[29] = 2.756,
	[30] = 2.750,
}

-- Get t-distribution critical value for given degrees of freedom and confidence level
local function get_t_critical(df: number, confidence_level: number): number
	-- Choose the appropriate table
	local table_to_use
	if confidence_level >= 0.99 then
		table_to_use = T_CRITICAL_99
	else
		table_to_use = T_CRITICAL_95
	end

	-- If df is in table, return exact value
	if table_to_use[df] then
		return table_to_use[df]
	end

	-- If df > 30, use normal (z) approximation
	if df > 30 then
		if confidence_level >= 0.99 then
			return 2.576 -- z-score for 99%
		else
			return 1.96 -- z-score for 95%
		end
	end

	-- For missing values between 1-30, use conservative estimate
	-- (use next lower df value, which is slightly larger/more conservative)
	for i = df, 1, -1 do
		if table_to_use[i] then
			return table_to_use[i]
		end
	end

	-- Fallback (shouldn't reach here)
	return 2.0
end

-- Get significance level and stars from t-statistic and degrees of freedom
-- Returns: p_value_threshold, stars, is_significant
local function get_significance_from_t(t: number, df: number, alpha: number): (number, string, boolean)
	local abs_t = math.abs(t)

	-- Two-tailed test thresholds
	-- For large df (> 30), use normal distribution thresholds
	local t_001, t_01, t_05
	if df > 30 then
		t_001 = 3.291 -- p < 0.001
		t_01 = 2.576 -- p < 0.01
		t_05 = 1.96 -- p < 0.05
	else
		-- Use conservative (high) values for small samples
		-- These are approximate thresholds
		t_001 = 4.0
		t_01 = 3.0
		t_05 = 2.2
	end

	if abs_t >= t_001 then
		return 0.001, "***", true
	elseif abs_t >= t_01 then
		return 0.01, "**", true
	elseif abs_t >= t_05 then
		return 0.05, "*", abs_t >= get_t_critical(df, 1 - alpha)
	else
		return 1.0, "", false
	end
end

-- Percentile calculation (sorted input)
local function percentile(sorted: { number }, p: number): number
	local n = #sorted
	if n == 0 then
		return 0
	end
	if n == 1 then
		return sorted[1]
	end

	local index = p * (n - 1) + 1
	local lower = math.floor(index)
	local upper = math.ceil(index)

	if lower == upper then
		return sorted[lower]
	end

	return math.lerp(sorted[lower], sorted[upper], index - lower)
end

-- Detect outliers using IQR method (sorted input)
-- Returns: iqr, mild_outliers_count, severe_outliers_count
local function detect_outliers(sorted: { number }): (number, number, number)
	local n = #sorted
	if n < 4 then
		-- Need at least 4 points for meaningful quartiles
		return 0, 0, 0
	end

	local q1 = percentile(sorted, 0.25)
	local q3 = percentile(sorted, 0.75)
	local iqr = q3 - q1

	if iqr == 0 then
		-- No spread, no outliers
		return 0, 0, 0
	end

	-- Calculate outlier boundaries
	local mild_lower = q1 - 1.5 * iqr
	local mild_upper = q3 + 1.5 * iqr
	local severe_lower = q1 - 3 * iqr
	local severe_upper = q3 + 3 * iqr

	-- Count outliers
	local mild_count = 0
	local severe_count = 0

	for _, value in sorted do
		if value < mild_lower or value > mild_upper then
			mild_count += 1

			if value < severe_lower or value > severe_upper then
				severe_count += 1
			end
		end
	end

	return iqr, mild_count, severe_count
end

-- Calculate Median Absolute Deviation (MAD)
-- MAD = median(|x_i - median(x)|)
-- Returns: mad
local function calculate_mad(sample: { number }, median: number): number
	local n = #sample
	if n == 0 then
		return 0
	end

	-- Calculate absolute deviations from median
	local deviations = table.create(n) :: { number }
	for i, value in sample do
		deviations[i] = math.abs(value - median)
	end

	-- Sort and find median of deviations
	table.sort(deviations)
	return percentile(deviations, 0.5)
end

-- Analyze a single sample
local function ANALYZE(sample: Sample, options: AnalyzeOptions?): SampleStats
	local opts = options or {} :: AnalyzeOptions
	local confidence_level = opts.confidence_level or DEFAULT_CONFIDENCE_LEVEL
	local cv_threshold = opts.cv_threshold or DEFAULT_CV_THRESHOLD
	local precision_threshold = opts.precision_threshold or DEFAULT_PRECISION_THRESHOLD

	local n = #sample

	-- Handle edge cases
	if n == 0 then
		return {
			n = 0,
			mean = 0,
			std = 0,
			variance = 0,
			min = 0,
			max = 0,
			se = 0,
			cv = 0,
			ci_lower = 0,
			ci_upper = 0,
			ci_width = 0,
			median = 0,
			mad = 0,
			p10 = 0,
			p50 = 0,
			p90 = 0,
			iqr = 0,
			mild_outliers = 0,
			severe_outliers = 0,
			is_stable = false,
			is_precise = false,
		}
	end

	if n == 1 then
		local value = sample[1]
		return {
			n = 1,
			mean = value,
			std = 0,
			variance = 0,
			min = value,
			max = value,
			se = 0,
			cv = 0,
			ci_lower = value,
			ci_upper = value,
			ci_width = 0,
			median = value,
			mad = 0,
			p10 = value,
			p50 = value,
			p90 = value,
			iqr = 0,
			mild_outliers = 0,
			severe_outliers = 0,
			is_stable = true,
			is_precise = true,
		}
	end

	-- Calculate basic statistics
	local sorted = table.clone(sample)
	table.sort(sorted)

	local min = sorted[1]
	local max = sorted[n]

	-- Calculate percentiles (from sorted data)
	local p10 = percentile(sorted, 0.1)
	local p50 = percentile(sorted, 0.5)
	local p90 = percentile(sorted, 0.9)
	local median = p50 -- median is the same as p50

	-- Detect outliers using IQR method
	local iqr, mild_outliers, severe_outliers = detect_outliers(sorted)

	-- Calculate MAD (median absolute deviation)
	local mad = calculate_mad(sample, median)

	-- Calculate mean (Kahan summation)
	local sum = 0
	local correction = 0
	for _, value in sample do
		local adjusted_value = value - correction
		local target = sum + adjusted_value

		correction = (target - sum) - adjusted_value
		sum = target            
	end
	local mean = sum / n

	-- Calculate variance and standard deviation
	local variance_sum = 0
	for _, value in sample do
		local diff = value - mean
		variance_sum += diff * diff
	end
	local variance = variance_sum / (n - 1) -- Sample variance (Bessel's correction)
	local std = math.sqrt(variance)

	-- Calculate standard error
	local se = std / math.sqrt(n)

	-- Calculate coefficient of variation (as percentage)
	local cv = if mean ~= 0 then (std / math.abs(mean)) * 100 else 0

	-- Calculate confidence interval
	local df = n - 1
	local t_crit = get_t_critical(df, confidence_level)
	local margin = t_crit * se
	local ci_lower = mean - margin
	local ci_upper = mean + margin
	local ci_width = 2 * margin

	-- Check quality indicators
	local is_stable = cv <= cv_threshold
	local is_precise = if mean ~= 0 then (ci_width / (2 * math.abs(mean))) <= precision_threshold else true

	return {
		n = n,
		mean = mean,
		std = std,
		variance = variance,
		min = min,
		max = max,
		se = se,
		cv = cv,
		ci_lower = ci_lower,
		ci_upper = ci_upper,
		ci_width = ci_width,
		median = median,
		mad = mad,
		p10 = p10,
		p50 = p50,
		p90 = p90,
		iqr = iqr,
		mild_outliers = mild_outliers,
		severe_outliers = severe_outliers,
		is_stable = is_stable,
		is_precise = is_precise,
	}
end

-- Compare two samples using Welch's t-test
local function COMPARE(sample_a: Sample, sample_b: Sample, options: CompareOptions?): ComparisonResult
	local opts = options or {} :: CompareOptions
	local confidence_level = opts.confidence_level or DEFAULT_CONFIDENCE_LEVEL
	local significance_level = opts.significance_level or DEFAULT_SIGNIFICANCE_LEVEL
	local noise_threshold = opts.noise_threshold or DEFAULT_NOISE_THRESHOLD

	local n_a = #sample_a
	local n_b = #sample_b

	-- Handle edge cases
	if n_a == 0 or n_b == 0 then
		return {
			t_statistic = 0,
			df = 0,
			p_value = 1.0,
			is_significant = false,
			is_practically_significant = false,
			significance_level = 1.0,
			stars = "",
			cohens_d = 0,
			effect_size = "trivial",
			mean_diff = 0,
			ci_diff_lower = 0,
			ci_diff_upper = 0,
		}
	end

	-- Calculate means
	local sum_a = 0
	for _, value in sample_a do
		sum_a += value
	end
	local mean_a = sum_a / n_a

	local sum_b = 0
	for _, value in sample_b do
		sum_b += value
	end
	local mean_b = sum_b / n_b

	-- Calculate variances
	local var_sum_a = 0
	for _, value in sample_a do
		local diff = value - mean_a
		var_sum_a += diff * diff
	end
	local var_a = var_sum_a / (n_a - 1) -- Sample variance (Bessel's correction)
	local std_a = math.sqrt(var_a)

	local var_sum_b = 0
	for _, value in sample_b do
		local diff = value - mean_b
		var_sum_b += diff * diff
	end
	local var_b = var_sum_b / (n_b - 1) -- Sample variance (Bessel's correction)
	local std_b = math.sqrt(var_b)

	-- Welch's t-test
	local mean_diff = mean_a - mean_b
	local se_diff = math.sqrt(var_a / n_a + var_b / n_b)

	-- Avoid division by zero
	local t_statistic = if se_diff > 0 then mean_diff / se_diff else 0

	-- Welch-Satterthwaite degrees of freedom
	local df
	if var_a > 0 and var_b > 0 then
		local numerator = (var_a / n_a + var_b / n_b) ^ 2
		local denom_a = (var_a / n_a) ^ 2 / (n_a - 1)
		local denom_b = (var_b / n_b) ^ 2 / (n_b - 1)
		df = numerator / (denom_a + denom_b)
	else
		df = n_a + n_b - 2
	end
	df = math.max(1, math.floor(df)) -- Ensure df >= 1

	-- Get significance
	local p_value, stars, is_significant = get_significance_from_t(t_statistic, df, significance_level)

	-- Calculate Cohen's d (effect size)
	-- Using pooled standard deviation
	local pooled_std
	if n_a > 1 and n_b > 1 then
		local pooled_var = ((n_a - 1) * var_a + (n_b - 1) * var_b) / (n_a + n_b - 2)
		pooled_std = math.sqrt(pooled_var)
	else
		pooled_std = math.max(std_a, std_b)
	end

	local cohens_d = if pooled_std > 0 then mean_diff / pooled_std else 0

	-- Interpret effect size
	local abs_d = math.abs(cohens_d)
	local effect_size
	if abs_d < 0.2 then
		effect_size = "trivial"
	elseif abs_d < 0.5 then
		effect_size = "small"
	elseif abs_d < 0.8 then
		effect_size = "medium"
	else
		effect_size = "large"
	end

	-- Confidence interval of the difference
	local t_crit = get_t_critical(df, confidence_level)
	local ci_margin = t_crit * se_diff
	local ci_diff_lower = mean_diff - ci_margin
	local ci_diff_upper = mean_diff + ci_margin

	-- Calculate practical significance (significant AND exceeds noise threshold)
	local abs_pct_change = if mean_b ~= 0 then math.abs(mean_diff / mean_b) else math.huge
	local is_practically_significant = is_significant and abs_pct_change >= noise_threshold

	return {
		t_statistic = t_statistic,
		df = df,
		p_value = p_value,
		is_significant = is_significant,
		is_practically_significant = is_practically_significant,
		significance_level = p_value,
		stars = stars,
		cohens_d = cohens_d,
		effect_size = effect_size,
		mean_diff = mean_diff,
		ci_diff_lower = ci_diff_lower,
		ci_diff_upper = ci_diff_upper,
	}
end

-- Check if a sample needs more data points to converge
local function NEEDS_MORE_SAMPLES(sample: Sample, target_cv: number?, target_precision: number?): boolean
	local cv_threshold = target_cv or DEFAULT_CV_THRESHOLD
	local precision_threshold = target_precision or DEFAULT_PRECISION_THRESHOLD

	local stats = ANALYZE(sample, {
		cv_threshold = cv_threshold,
		precision_threshold = precision_threshold,
	})

	-- Need more samples if either not stable or not precise
	return not stats.is_stable or not stats.is_precise
end

-- Percentile calculation (public API version)
local function PERCENTILE(sample: Sample, p: number): number
	local sorted = table.clone(sample)
	table.sort(sorted)
	return percentile(sorted, p)
end

return {
	analyze = ANALYZE,
	compare = COMPARE,
	needs_more_samples = NEEDS_MORE_SAMPLES,
	percentile = PERCENTILE,
}
