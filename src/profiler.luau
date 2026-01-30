--!strict
--!native
--!optimize 2

-- ██████╗ ██╗   ██╗██╗   ██╗    ██╗    ██╗██╗   ██╗███████╗    ██╗  ██╗███████╗██████╗ ███████╗    ██╗      ██████╗ ██╗      ██████╗ ██╗      ██████╗  ██╗ ██████╗  ██╗ ██████╗  ██╗ ██████╗  ██╗ ██████╗ ██╗      ██████╗
-- ██╔══██╗██║   ██║╚██╗ ██╔╝    ██║    ██║██║   ██║╚══███╔╝    ██║  ██║██╔════╝██╔══██╗██╔════╝    ██║     ██╔═████╗██║     ██╔═████╗██║     ██╔═████╗███║██╔═████╗███║██╔═████╗███║██╔═████╗███║██╔═████╗██║     ██╔═████╗
-- ██████╔╝██║   ██║ ╚████╔╝     ██║ █╗ ██║██║   ██║  ███╔╝     ███████║█████╗  ██████╔╝█████╗      ██║     ██║██╔██║██║     ██║██╔██║██║     ██║██╔██║╚██║██║██╔██║╚██║██║██╔██║╚██║██║██╔██║╚██║██║██╔██║██║     ██║██╔██║
-- ██╔══██╗╚██╗ ██╔╝  ╚██╔╝      ██║███╗██║██║   ██║ ███╔╝      ██╔══██║██╔══╝  ██╔══██╗██╔══╝      ██║     ████╔╝██║██║     ████╔╝██║██║     ████╔╝██║ ██║████╔╝██║ ██║████╔╝██║ ██║████╔╝██║ ██║████╔╝██║██║     ████╔╝██║
-- ██║  ██║ ╚████╔╝    ██║       ╚███╔███╔╝╚██████╔╝███████╗    ██║  ██║███████╗██║  ██║███████╗    ███████╗╚██████╔╝███████╗╚██████╔╝███████╗╚██████╔╝ ██║╚██████╔╝ ██║╚██████╔╝ ██║╚██████╔╝ ██║╚██████╔╝███████╗╚██████╔╝
-- ╚═╝  ╚═╝  ╚═══╝     ╚═╝        ╚══╝╚══╝  ╚═════╝ ╚══════╝    ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝    ╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝  ╚═╝ ╚═════╝  ╚═╝ ╚═════╝  ╚═╝ ╚═════╝  ╚═╝ ╚═════╝ ╚══════╝ ╚═════╝

-- absolute minimal profiler design - just log events, almost all overhead diverted to dump
-- idk why this took so long to come up with, best solution for what I wanted ended up being super simple

export type Config = {
	track_memory: boolean?,
	expected_results: number?,
	expected_depth: number?,
}

export type Dump = {
	label: string,
	durations: { number },
	memories: { number }?,
	children: { [string]: Dump },
}

local ON = false
local TRACK_MEMORY = false
local DEBUG = true
local MAX_RESULTS: number
local MAX_DEPTH: number

local count: number
local labels: { string? }
local times: { number }
local memories: { number }

local last_dump_index: { number } -- Per-level dump tracking
local current_level: number -- Only used during dump, not during recording

local DEFAULT_CONFIG: Config = {
	track_memory = false,
	expected_results = 100000,
	expected_depth = 256,
}

-- Recursively merge source Dump node into target Dump node
local function merge_dump_nodes(target: Dump, source: Dump)
	-- Merge durations
	for _, dur in source.durations do
		table.insert(target.durations, dur)
	end
	-- Merge memories
	if target.memories and source.memories then
		for _, mem in source.memories do
			table.insert(target.memories, mem)
		end
	end
	-- Recursively merge children
	for child_label, child_node in source.children do
		local existing_child = target.children[child_label]
		if existing_child then
			merge_dump_nodes(existing_child, child_node)
		else
			target.children[child_label] = child_node
		end
	end
end

-- update_index: if true, updates last_dump_index (destructive read like dump)
--               if false, leaves last_dump_index unchanged (non-destructive read like peek)
local function dump_internal(update_index: boolean): { [string]: Dump }?
	if not ON then
		return nil
	end

	-- Compute current level by replaying all events
	local computed_level = 0
	for i = 1, count do
		if labels[i] then
			computed_level += 1
		else
			computed_level -= 1
		end
	end
	current_level = computed_level

	local start_i = (last_dump_index[current_level] or 0) + 1
	local end_i = count

	if start_i > end_i then
		return nil
	end

	if update_index then
		last_dump_index[current_level] = end_i
	end

	-- Root holds everything at depth > current level
	local root: { [string]: Dump } = {}

	-- Stack-based reconstruction
	type StackEntry = {
		node: Dump,
		start_time: number,
		start_mem: number?,
	}
	local node_stack: { StackEntry } = {}

	-- Compute starting level by replaying events before start_i
	-- This fixes the bug where dump() at non-zero level with start_i > 1
	-- would incorrectly start level tracking at 0
	local level = 0
	for i = 1, start_i - 1 do
		if labels[i] then
			level += 1
		else
			level -= 1
		end
	end

	for i = start_i, end_i do
		local label = labels[i]
		if label then
			-- MARK event - increment level
			level += 1

			-- Only process events at depth > current level
			if level > current_level then
				-- Create new node and push onto stack
				local new_node: Dump = {
					label = label,
					durations = {},
					memories = if TRACK_MEMORY then {} else nil,
					children = {},
				}

				table.insert(node_stack, {
					node = new_node,
					start_time = times[i],
					start_mem = if TRACK_MEMORY then memories[i] else nil,
				})
			end
		else
			-- DONE event - only process if at depth > current level
			if level > current_level then
				if #node_stack > 0 then
					local entry = table.remove(node_stack) :: StackEntry

					-- Compute duration
					local duration = times[i] - entry.start_time
					table.insert(entry.node.durations, duration)

					if TRACK_MEMORY and entry.node.memories and entry.start_mem then
						local mem_delta = memories[i] - entry.start_mem
						table.insert(entry.node.memories, mem_delta)
					end

					-- Add to parent's children (or root if no parent)
					local parent_children = if #node_stack > 0 then node_stack[#node_stack].node.children else root
					local existing = parent_children[entry.node.label]

					if existing then
						-- Merge with existing node (multiple calls to same label)
						merge_dump_nodes(existing, entry.node)
					else
						-- Add new node
						parent_children[entry.node.label] = entry.node
					end
				end
			end

			-- Decrement level after processing
			level -= 1
		end
	end

	return next(root) and root or nil
end

-- Dump: consume data (destructive read - updates last_dump_count)
local function PROFILER_DUMP(): { [string]: Dump }?
	return dump_internal(true)
end

-- Peek: observe data without consuming (non-destructive read - preserves last_dump_count)
local function PROFILER_PEEK(): { [string]: Dump }?
	return dump_internal(false)
end

local function PROFILER_ON(config: Config?)
	if ON then
		return
	end

	ON = true
	config = config or DEFAULT_CONFIG

	TRACK_MEMORY = config.track_memory or DEFAULT_CONFIG.track_memory
	MAX_RESULTS = config.expected_results or DEFAULT_CONFIG.expected_results :: number
	MAX_DEPTH = config.expected_depth or DEFAULT_CONFIG.expected_depth :: number

	-- Allocate event arrays
	labels = table.create(MAX_RESULTS) :: { string? }
	times = table.create(MAX_RESULTS) :: { number }
	last_dump_index = table.create(MAX_DEPTH) :: { number }

	if TRACK_MEMORY then
		memories = table.create(MAX_RESULTS) :: { number }
	end

	count = 0
	current_level = 0
end

local function PROFILER_OFF(): { [string]: Dump }?
	if not ON then
		return nil
	end

	local dump = PROFILER_DUMP()

	ON = false
	TRACK_MEMORY = false

	labels = nil :: any
	times = nil :: any
	memories = nil :: any
	last_dump_index = nil :: any
	count = nil :: any
	current_level = nil :: any

	return dump
end

local function PROFILER_MARK(label: string)
	if DEBUG then
		debug.profilebegin(label)
	end

	if not ON then
		return
	end

	count += 1
	labels[count] = label
	times[count] = os.clock()

	if TRACK_MEMORY then
		memories[count] = gcinfo()
	end
end

local function PROFILER_DONE()
	if DEBUG then
		debug.profileend()
	end

	if not ON then
		return
	end

	count += 1
	times[count] = os.clock()

	if TRACK_MEMORY then
		memories[count] = gcinfo()
	end
end

local function PROFILER_ABORT()
	if not ON or count == 0 then
		return
	end

	-- Count unclosed marks
	local unclosed_count = 0
	local level = 0

	for i = 1, count do
		local label = labels[i]
		if label then
			level += 1
			unclosed_count += 1
		else
			level -= 1
			unclosed_count -= 1
		end
	end

	-- Synthesize DONE events for unclosed marks
	if unclosed_count > 0 then
		for _ = 1, unclosed_count do
			PROFILER_DONE()
		end
		warn(`bench.abort() collapsed {unclosed_count} unclosed mark(s)`)
	end
end

local function PROFILER_RAW()
	return {
		labels = labels,
		times = times,
		memories = memories,
		count = count,
	}
end

local function PROFILER_DEBUG(enabled: boolean)
	DEBUG = enabled
end

return {
	on = PROFILER_ON,
	off = PROFILER_OFF,
	mark = PROFILER_MARK,
	done = PROFILER_DONE,
	dump = PROFILER_DUMP,
	peek = PROFILER_PEEK,
	abort = PROFILER_ABORT,
	raw = PROFILER_RAW,
	debug = PROFILER_DEBUG,
}
