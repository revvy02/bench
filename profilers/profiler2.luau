--!strict
--!native
--!optimize 2

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

type DumpCursor = {
	dur: number,
	mem: number,
	children: { [string]: DumpCursor },
}

local ON = false
local TRACK_MEMORY = false
local DEBUG = true

-- Hot-path upvalues (current scope)
local TIME: number
local MEMORY: number
local LABEL: string
local CHILDREN: { [string]: Dump }
local CURSORS: { [string]: DumpCursor }

local LEVEL = 0
local TIME_STACK = {}
local MEMORY_STACK = {}
local LABEL_STACK = {}
local CHILDREN_STACK: { { [string]: Dump } } = {}
local CURSOR_STACK: { { [string]: DumpCursor } } = {}

-- Recursively merge source Dump into target Dump
local function merge_dump_nodes(target: Dump, source: Dump)
	local src_dur = #source.durations
	if src_dur > 0 then
		table.move(source.durations, 1, src_dur, #target.durations + 1, target.durations)
	end

	if target.memories and source.memories then
		local src_mem = #source.memories
		if src_mem > 0 then
			table.move(source.memories, 1, src_mem, #target.memories + 1, target.memories)
		end
	end

	for label, child in source.children do
		local existing = target.children[label]
		if existing then
			merge_dump_nodes(existing, child)
		else
			target.children[label] = child
		end
	end
end

-- Recursively extract un-consumed data from a Dump node using a cursor
local function extract_new(node: Dump, cursor: DumpCursor, update: boolean): Dump?
	local dur_start = cursor.dur + 1
	local dur_end = #node.durations

	local mem_start = cursor.mem + 1
	local mem_end = if node.memories then #(node.memories :: { number }) else 0

	-- Recurse into children
	local new_children: { [string]: Dump } = {}
	local has_new_children = false
	for label, child in node.children do
		local child_cursor = cursor.children[label]
		if not child_cursor then
			child_cursor = { dur = 0, mem = 0, children = {} }
			cursor.children[label] = child_cursor
		end
		local new_child = extract_new(child, child_cursor, update)
		if new_child then
			new_children[label] = new_child
			has_new_children = true
		end
	end

	local has_new_dur = dur_end >= dur_start
	if not has_new_dur and not has_new_children then
		return nil
	end

	if update then
		cursor.dur = dur_end
		cursor.mem = mem_end
	end

	local new_durations = {}
	if has_new_dur then
		table.move(node.durations, dur_start, dur_end, 1, new_durations)
	end

	local new_memories: { number }? = nil
	if node.memories and mem_end >= mem_start then
		new_memories = {}
		table.move(node.memories :: { number }, mem_start, mem_end, 1, new_memories :: { number })
	end

	return {
		label = node.label,
		durations = new_durations,
		memories = new_memories,
		children = new_children,
	}
end

-- update: if true, advances cursors (dump). if false, leaves cursors unchanged (peek).
local function dump_internal(update: boolean): { [string]: Dump }?
	if not ON then
		return nil
	end

	local result: { [string]: Dump } = {}
	local has_result = false

	for label, node in CHILDREN do
		local cursor = CURSORS[label]
		if not cursor then
			cursor = { dur = 0, mem = 0, children = {} }
			CURSORS[label] = cursor
		end
		local new_node = extract_new(node, cursor, update)
		if new_node then
			result[label] = new_node
			has_result = true
		end
	end

	return if has_result then result else nil
end

local DEFAULT_CONFIG: Config = {
	track_memory = false,
	expected_depth = 256,
}

local function PROFILER_ON(config: Config?)
	if ON then
		return
	end

	ON = true
	config = config or DEFAULT_CONFIG

	TRACK_MEMORY = config.track_memory or DEFAULT_CONFIG.track_memory :: boolean

	local max_depth = config.expected_depth or DEFAULT_CONFIG.expected_depth :: number
	TIME_STACK = table.create(max_depth)
	MEMORY_STACK = table.create(max_depth)
	LABEL_STACK = table.create(max_depth)
	CHILDREN_STACK = table.create(max_depth) :: { { [string]: Dump } }
	CURSOR_STACK = table.create(max_depth) :: { { [string]: DumpCursor } }

	LEVEL = 0
	CHILDREN = {}
	CURSORS = {}
end

local function PROFILER_MARK(label: string)
	if DEBUG then
		debug.profilebegin(label)
	end

	if not ON then
		return
	end

	-- Save current scope
	CHILDREN_STACK[LEVEL] = CHILDREN
	CURSOR_STACK[LEVEL] = CURSORS
	TIME_STACK[LEVEL], LABEL_STACK[LEVEL], MEMORY_STACK[LEVEL] = TIME, LABEL, MEMORY

	-- Enter new scope
	LEVEL += 1
	TIME, LABEL = os.clock(), label
	CHILDREN = {}
	CURSORS = {}

	if TRACK_MEMORY then
		MEMORY = gcinfo()
	end
end

local function PROFILER_DONE()
	if DEBUG then
		debug.profileend()
	end

	if not ON or LEVEL == 0 then
		return
	end

	local delta_time = os.clock() - TIME

	local node: Dump = {
		label = LABEL,
		durations = { delta_time },
		memories = if TRACK_MEMORY then { gcinfo() - MEMORY } else nil,
		children = CHILDREN,
	}

	-- Pop scope
	LEVEL -= 1
	TIME, LABEL, MEMORY = TIME_STACK[LEVEL], LABEL_STACK[LEVEL], MEMORY_STACK[LEVEL]
	CHILDREN = CHILDREN_STACK[LEVEL]
	CURSORS = CURSOR_STACK[LEVEL]

	-- Merge into parent's children
	local existing = CHILDREN[node.label]
	if existing then
		merge_dump_nodes(existing, node)
	else
		CHILDREN[node.label] = node
	end
end

local function PROFILER_DUMP(): { [string]: Dump }?
	return dump_internal(true)
end

local function PROFILER_PEEK(): { [string]: Dump }?
	return dump_internal(false)
end

local function PROFILER_ABORT()
	if not ON or LEVEL == 0 then
		return
	end

	local unclosed = LEVEL
	for _ = 1, unclosed do
		PROFILER_DONE()
	end
	warn(`bench.abort() collapsed {unclosed} unclosed mark(s)`)
end

local function PROFILER_OFF(): { [string]: Dump }?
	if not ON then
		return nil
	end

	PROFILER_ABORT()
	local dump = PROFILER_DUMP()

	ON = false
	TRACK_MEMORY = false

	TIME_STACK = nil :: any
	MEMORY_STACK = nil :: any
	LABEL_STACK = nil :: any
	CHILDREN_STACK = nil :: any
	CURSOR_STACK = nil :: any
	CHILDREN = nil :: any
	CURSORS = nil :: any

	return dump
end

local function PROFILER_RAW()
	return {
		children = CHILDREN,
		cursors = CURSORS,
		level = LEVEL,
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
