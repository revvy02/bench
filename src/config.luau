export type StatType = "time" | "count" | "percent" | "bytes" | "ratio"
export type StatPolarity = "lower_better" | "higher_better" | "neutral"

export type StatMetadata = {
	name: string,
	type: StatType,
	verboseOnly: boolean,
	polarity: StatPolarity,
	ratioLabels: {
		better: string,
		worse: string,
	}?,
}

local STAT_METADATA: { [string]: StatMetadata } = {
	-- Count stat
	count = {
		name = "count",
		type = "count",
		verboseOnly = false,
		polarity = "neutral",
		ratioLabels = {
			better = "more",
			worse = "fewer",
		},
	},

	-- Time stats (lower is better)
	["time.min"] = {
		name = "time.min",
		type = "time",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "faster",
			worse = "slower",
		},
	},
	["time.max"] = {
		name = "time.max",
		type = "time",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "faster",
			worse = "slower",
		},
	},
	["time.avg"] = {
		name = "time.avg",
		type = "time",
		verboseOnly = false,
		polarity = "lower_better",
		ratioLabels = {
			better = "faster",
			worse = "slower",
		},
	},
	["time.p10"] = {
		name = "time.p10",
		type = "time",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "faster",
			worse = "slower",
		},
	},
	["time.p50"] = {
		name = "time.p50",
		type = "time",
		verboseOnly = false,
		polarity = "lower_better",
		ratioLabels = {
			better = "faster",
			worse = "slower",
		},
	},
	["time.p90"] = {
		name = "time.p90",
		type = "time",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "faster",
			worse = "slower",
		},
	},
	["time.std"] = {
		name = "time.std",
		type = "time",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "faster",
			worse = "slower",
		},
	},
	["time.cv"] = {
		name = "time.cv",
		type = "percent",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "more stable",
			worse = "less stable",
		},
	},
	["time.mad"] = {
		name = "time.mad",
		type = "time",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "more stable",
			worse = "less stable",
		},
	},
	["time.mild_outliers"] = {
		name = "time.mild_outliers",
		type = "count",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "fewer outliers",
			worse = "more outliers",
		},
	},
	["time.total"] = {
		name = "time.total",
		type = "time",
		verboseOnly = false,
		polarity = "lower_better",
		ratioLabels = {
			better = "faster",
			worse = "slower",
		},
	},

	-- Memory stats (lower is better)
	["mem.min"] = {
		name = "mem.min",
		type = "bytes",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "less",
			worse = "more",
		},
	},
	["mem.max"] = {
		name = "mem.max",
		type = "bytes",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "less",
			worse = "more",
		},
	},
	["mem.avg"] = {
		name = "mem.avg",
		type = "bytes",
		verboseOnly = false,
		polarity = "lower_better",
		ratioLabels = {
			better = "less",
			worse = "more",
		},
	},
	["mem.p10"] = {
		name = "mem.p10",
		type = "bytes",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "less",
			worse = "more",
		},
	},
	["mem.p50"] = {
		name = "mem.p50",
		type = "bytes",
		verboseOnly = false,
		polarity = "lower_better",
		ratioLabels = {
			better = "less",
			worse = "more",
		},
	},
	["mem.p90"] = {
		name = "mem.p90",
		type = "bytes",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "less",
			worse = "more",
		},
	},
	["mem.std"] = {
		name = "mem.std",
		type = "bytes",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "less",
			worse = "more",
		},
	},
	["mem.cv"] = {
		name = "mem.cv",
		type = "percent",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "more stable",
			worse = "less stable",
		},
	},
	["mem.mad"] = {
		name = "mem.mad",
		type = "bytes",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "more stable",
			worse = "less stable",
		},
	},
	["mem.mild_outliers"] = {
		name = "mem.mild_outliers",
		type = "count",
		verboseOnly = true,
		polarity = "lower_better",
		ratioLabels = {
			better = "fewer outliers",
			worse = "more outliers",
		},
	},
	["mem.total"] = {
		name = "mem.total",
		type = "bytes",
		verboseOnly = false,
		polarity = "lower_better",
		ratioLabels = {
			better = "less",
			worse = "more",
		},
	},

	-- Comparison significance stats
	["time.p_value"] = {
		name = "time.p_value",
		type = "ratio",
		verboseOnly = true,
		polarity = "neutral",
	},
	["time.is_practically_significant"] = {
		name = "time.is_practically_significant",
		type = "count",
		verboseOnly = true,
		polarity = "neutral",
	},
	["mem.p_value"] = {
		name = "mem.p_value",
		type = "ratio",
		verboseOnly = true,
		polarity = "neutral",
	},
	["mem.is_practically_significant"] = {
		name = "mem.is_practically_significant",
		type = "count",
		verboseOnly = true,
		polarity = "neutral",
	},
}

-- Display order for stats (non-verbose first, then verbose-only)
local STAT_DISPLAY_ORDER: { string } = {
	-- Time stats (non-verbose: p50, avg, total first)
	"time.p50",
	"time.avg",
	"time.total",
	"time.min",
	"time.max",
	"time.p10",
	"time.p90",
	"time.std",
	"time.cv",
	"time.mad",
	"time.mild_outliers",

	-- Memory stats (non-verbose: p50, avg, total first)
	"mem.p50",
	"mem.avg",
	"mem.total",
	"mem.min",
	"mem.max",
	"mem.p10",
	"mem.p90",
	"mem.std",
	"mem.cv",
	"mem.mad",
	"mem.mild_outliers",

	-- Comparison significance stats (verbose-only)
	"time.p_value",
	"time.is_practically_significant",
	"mem.p_value",
	"mem.is_practically_significant",

	-- Count last
	"count",
}

return {
	STAT_METADATA = STAT_METADATA,
	STAT_DISPLAY_ORDER = STAT_DISPLAY_ORDER,
}
