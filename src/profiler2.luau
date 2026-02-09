local TIME: number
local MEMORY: number
local LABEL: string

local DELTA_TIME: number
local DELTA_MEMORY: number

local LEVEL = 0
local LABEL_STACK = {}
local TIME_STACK = {}
local MEMORY_STACK = {}

local function mark(label: string)
	TIME_STACK[LEVEL], LABEL_STACK[LEVEL], MEMORY_STACK[LEVEL] = TIME, LABEL, MEMORY

	LEVEL += 1
	TIME, LABEL, MEMORY = os.clock(), label, gcinfo()
end

local function done()
	DELTA_TIME, DELTA_MEMORY = os.clock() - TIME, gcinfo() - MEMORY

	-- at this point DURATION, START, and LABEL are for the current mark that is being completed
	-- we can build whatever structure we want here for dumps

	LEVEL -= 1
	TIME, LABEL, MEMORY = TIME_STACK[LEVEL], LABEL_STACK[LEVEL], MEMORY_STACK[LEVEL]
end

local function dump() end
