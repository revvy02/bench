--!strict
--!native
--!optimize 2

-- incremental tree-building profiler (ported from game-prototype@70a4fbc8)
-- builds the dump tree live during mark/done using a stack
-- done() returns the completed Dump directly — no separate dump/peek

export type Dump = {
	label: string,
	start: number,
	stop: number,
	duration: number,
	children: { Dump },
}

local ON = false
local STACK: { Dump } = {}
local LEVEL = 0
local NOOP = function() end

local BENCH_MARK: (label: string) -> () = debug.profilebegin
local BENCH_DONE: () -> Dump? = NOOP :: any
local BENCH_ABORT: () -> Dump? = NOOP :: any

local function _real_bench_mark(label: string)
	debug.profilebegin(label)

	LEVEL += 1
	local record = {
		label = label,
		start = os.clock(),
		stop = -1,
		duration = -1,
		children = {} :: { Dump },
	}
	table.insert(STACK, record)
end

local function _real_bench_done(): Dump?
	local now = os.clock()
	debug.profileend()

	if LEVEL == 0 then
		warn("bench.done() called without matching mark()")
		return nil
	end

	LEVEL -= 1

	local dump = table.remove(STACK) :: Dump

	dump.stop = now
	dump.duration = now - dump.start

	if LEVEL > 0 then
		local parent = STACK[#STACK]
		table.insert(parent.children :: { Dump }, dump)
	end

	return dump
end

local function _real_bench_abort(): Dump?
	if not ON or #STACK == 0 then
		return nil
	end

	local now = os.clock()
	local unclosed_count = #STACK - 1

	for i = #STACK, 1, -1 do
		local dump = STACK[i]
		dump.stop = now
		dump.duration = now - dump.start

		if i > 1 then
			table.insert(STACK[i - 1].children, dump)
		end

		debug.profileend()
	end

	local root = STACK[1]
	table.clear(STACK)
	LEVEL = 0

	if unclosed_count > 0 then
		warn(`bench.abort() collapsed {unclosed_count} unclosed mark(s)`)
	end

	return root
end

local function PROFILER_ON()
	if not ON then
		ON = true
		BENCH_MARK = _real_bench_mark
		BENCH_DONE = _real_bench_done
		BENCH_ABORT = _real_bench_abort
	end
end

local function PROFILER_OFF(): Dump?
	local dump
	if ON then
		dump = BENCH_ABORT()
		ON = false
		BENCH_MARK = debug.profilebegin
		BENCH_DONE = NOOP :: any
		BENCH_ABORT = NOOP :: any
	end
	return dump
end

local function PROFILER_MARK(label: string)
	BENCH_MARK(label)
end

local function PROFILER_DONE(): Dump?
	return BENCH_DONE()
end

local function PROFILER_ABORT(): Dump?
	return BENCH_ABORT()
end

return {
	on = PROFILER_ON,
	off = PROFILER_OFF,
	mark = PROFILER_MARK,
	done = PROFILER_DONE,
	abort = PROFILER_ABORT,
}
