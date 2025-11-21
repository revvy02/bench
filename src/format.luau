local analyzer = require(script.Parent.analyzer)
local config = require(script.Parent.config)
local terminal = require(script.Parent.terminal)

local STAT_METADATA = config.STAT_METADATA
local STAT_DISPLAY_ORDER = config.STAT_DISPLAY_ORDER

-- formatting addon
export type FormatTree = terminal.FormatTree

export type FormatOptions = {
	verbose: boolean?,
}

-- ANSI Color codes
-- Use terminal's style functions for colors
local style = terminal.style

-- Scale thresholds for unit formatting
local SCALE_THRESHOLDS = {
	{ threshold = 1e12, scale = 1e12, prefix = "T", color = style.red },
	{ threshold = 1e9, scale = 1e9, prefix = "G", color = style.red },
	{ threshold = 1e6, scale = 1e6, prefix = "M", color = style.yellow },
	{ threshold = 1e3, scale = 1e3, prefix = "k", color = style.yellow },
	{ threshold = 1, scale = 1, prefix = "", color = style.green },
	{ threshold = 1e-3, scale = 1e-3, prefix = "m", color = style.green },
	{ threshold = 1e-6, scale = 1e-6, prefix = "μ", color = style.yellow },
	{ threshold = 1e-9, scale = 1e-9, prefix = "n", color = style.yellow },
	{ threshold = 0, scale = 1e-12, prefix = "p", color = style.red },
}

-- Configuration for all formatter types
local FORMATTER_CONFIG: {
	[config.StatType]: {
		unit: string?,
		needs_scaling: boolean,
		needs_color: boolean,
		scale_input: number?,
	},
} = {
	time = { unit = "s", needs_scaling = true, needs_color = true },
	bytes = { unit = "B", needs_scaling = true, needs_color = true, scale_input = 1024 },
	count = { needs_scaling = false, needs_color = false },
	percent = { unit = "%", needs_scaling = false, needs_color = false },
	ratio = { needs_scaling = false, needs_color = false },
}

-- Unified formatter for all stat types (returns value and unit strings separately for alignment)
local function _format_value(value: number, stat_type: config.StatType, precision: number): (string, string)
	local formatter_config = FORMATTER_CONFIG[stat_type]

	if formatter_config.needs_scaling then
		local scaled_value = if formatter_config.scale_input then value * formatter_config.scale_input else value
		return terminal.format_scaled_value_plain(scaled_value, formatter_config.unit :: string, SCALE_THRESHOLDS, precision)
	else
		-- For count type, use integer formatting; for others, use decimal precision
		local formatted = if stat_type == "count" then tostring(value) else string.format(`%.{precision}f` :: any, value)
		return formatted, formatter_config.unit or ""
	end
end

-- Apply color to unit string based on stat type and value
local function _apply_unit_color(value_str: string, unit_str: string, stat_type: config.StatType, raw_value: number): string
	if unit_str == "" then
		return value_str
	end

	local config = FORMATTER_CONFIG[stat_type]
	if config.needs_color then
		local color_fn = terminal.get_scale_color(raw_value, SCALE_THRESHOLDS)
		return `{value_str} {color_fn(unit_str)}`
	else
		return `{value_str} {unit_str}`
	end
end

local function _get_comparison_color(delta: number, polarity: config.StatPolarity)
	if polarity == "neutral" then
		return style.white
	end

	local is_increase = delta >= 0

	if polarity == "lower_better" then
		return is_increase and style.red or style.green
	else -- "higher_better"
		return is_increase and style.green or style.red
	end
end

-- Converts the tree to a string for cli
local function _format_tree(tree: { FormatTree }): string
	return terminal.format_tree(tree)
end

-- Convert a single Analysis node to a FormatTree
local function _analysis_to_tree_node(analysis: analyzer.Analysis, verbose: boolean, precision: number): FormatTree
	local label, stats, comparisons, children = analysis.label, analysis.stats, analysis.comparisons, analysis.children

	local stat_children: { FormatTree } = {}

	-- Build table rows for basic stats
	local stat_rows: { { string } } = {}
	for _, stat_name in STAT_DISPLAY_ORDER do
		local metadata = STAT_METADATA[stat_name]

		-- Skip if no metadata (e.g., comparison-only stats)
		if not metadata then
			continue
		end

		-- Skip verbose-only stats if not in verbose mode
		if not verbose and metadata.verboseOnly then
			continue
		end

		local value = stats[stat_name]
		if type(value) == "number" then
			-- Format value and apply colors
			local value_str, unit_str = _format_value(value, metadata.type, precision)
			local formatted_colored = _apply_unit_color(value_str, unit_str, metadata.type, value)

			table.insert(stat_rows, {
				stat_name .. ":",
				formatted_colored,
			})
		end
	end

	-- Format basic stats table and convert to FormatTree children
	if #stat_rows > 0 then
		local formatted_table = terminal.format_table(stat_rows, {
			justify_left = { 1 },
			justify_right = { 2 },
			margin_right = { 10, 0 },
		})

		for line in string.gmatch(formatted_table, "[^\n]+") do
			table.insert(stat_children, { text = line })
		end
	end

	if comparisons then
		-- Sort comparison names for consistent output
		local comp_names: { string } = {}
		for comp_name in comparisons do
			table.insert(comp_names, comp_name)
		end
		table.sort(comp_names)

		-- Collect all comparison tables for batch alignment
		local all_comp_rows: { { { string } } } = {}
		local comp_metadata: { { name: string } } = {}

		for _, comp_name in comp_names do
			local comp_data = comparisons[comp_name]
			if comp_data then
				-- Build table rows for comparison stats
				local rows: { { string } } = {}

				for _, stat_name in STAT_DISPLAY_ORDER do
					local metadata = STAT_METADATA[stat_name]

					-- Skip if no metadata (shouldn't happen for comparison stats, but be safe)
					if not metadata then
						continue
					end

					if not verbose and metadata.verboseOnly then
						continue
					end

					-- Check if this is a significance stat (stored in comp_data.significance)
					local significance_val = comp_data.significance and comp_data.significance[stat_name]
					if significance_val then
						-- Format significance stat (no comparison, just the value)
						local sig_value_str, sig_unit_str = _format_value(significance_val, metadata.type, precision)
						local sig_colored = _apply_unit_color(sig_value_str, sig_unit_str, metadata.type, significance_val)

						table.insert(rows, {
							stat_name .. ":",
							sig_colored,
							"",
							"",
						})
						continue
					end

					local delta_val = comp_data.delta[stat_name]
					local pct_val = comp_data.pct[stat_name]
					local comparison_val = comp_data.stats[stat_name]
					local baseline_val = stats[stat_name]

					if delta_val and pct_val and comparison_val and baseline_val then
						-- Format values and apply colors
						local comp_value_str, comp_unit_str = _format_value(comparison_val, metadata.type, precision)
						local delta_value_str, delta_unit_str = _format_value(math.abs(delta_val), metadata.type, precision)

						local comp_colored = _apply_unit_color(comp_value_str, comp_unit_str, metadata.type, comparison_val)

						-- Calculate ratio
						local ratio = baseline_val / comparison_val
						local baseline_is_better = false
						if metadata.polarity == "lower_better" then
							baseline_is_better = baseline_val < comparison_val
						elseif metadata.polarity == "higher_better" then
							baseline_is_better = baseline_val > comparison_val
						end

						local better_label = metadata.ratioLabels and metadata.ratioLabels.better or "faster"
						local worse_label = metadata.ratioLabels and metadata.ratioLabels.worse or "slower"
						local ratio_label = baseline_is_better and better_label or worse_label
						local ratio_str = ratio >= 1 and string.format("%.2fx %s", ratio, ratio_label) or string.format("%.2fx %s", 1 / ratio, ratio_label)

						-- Apply comparison color to both ratio and delta
						local color_fn = _get_comparison_color(delta_val, metadata.polarity)
						local colored_ratio = style.bold(color_fn(ratio_str))

						-- Build delta string with color (not bold)
						local sign = delta_val >= 0 and "+" or "-"
						local delta_plain = delta_unit_str ~= "" and `{delta_value_str} {delta_unit_str}` or delta_value_str
						local delta_with_prefix = color_fn(sign .. delta_plain)

						table.insert(rows, {
							stat_name .. ":",
							comp_colored,
							delta_with_prefix,
							colored_ratio,
						})
					end
				end

				if #rows > 0 then
					table.insert(all_comp_rows, rows)
					table.insert(comp_metadata, { name = comp_name })
				end
			end
		end

		-- Format all comparison tables with shared column widths
		if #all_comp_rows > 0 then
			local formatted_tables = terminal.format_table_batch(all_comp_rows, {
				justify_left = { 1 },
				justify_right = { 2, 3, 4 },
				margin_right = { 5, 5, 5 },
			})

			-- Convert each formatted table to FormatTree children
			for i, formatted_table in formatted_tables do
				local comp_stat_children: { FormatTree } = {}
				for line in string.gmatch(formatted_table, "[^\n]+") do
					table.insert(comp_stat_children, { text = line } :: FormatTree)
				end

				-- Add comparison header with children
				table.insert(stat_children, {
					text = style.cyan("vs " .. comp_metadata[i].name .. ":"),
					children = comp_stat_children,
				})
			end
		end
	end

	-- Recursively process children analysis nodes
	local analysis_children: { FormatTree }? = nil
	if children then
		analysis_children = {}
		for _, child_node in children do
			table.insert(analysis_children, _analysis_to_tree_node(child_node, verbose, precision))
		end
	end

	-- Combine stat children with analysis children
	local all_children: { FormatTree }? = nil
	if #stat_children > 0 or analysis_children then
		all_children = table.clone(stat_children)
		if analysis_children then
			for _, child in analysis_children do
				table.insert(all_children, child)
			end
		end
	end

	return {
		text = style.white_bold(label),
		children = all_children,
	}
end

local DEFAULT_PRECISION = 3

local function BENCH_format(analysis: analyzer.Analysis, options: FormatOptions?): string
	local opts = options or {} :: FormatOptions
	local verbose = opts.verbose or false
	local precision = DEFAULT_PRECISION

	-- Convert single Analysis node to a tree (uses label from analysis)
	local tree_node = _analysis_to_tree_node(analysis, verbose, precision)

	return _format_tree({ tree_node })
end

return BENCH_format
