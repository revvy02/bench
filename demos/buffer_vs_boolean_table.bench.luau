--!native
--!optimize 2

local bench = require(game.ReplicatedStorage.packages.bench)

local N = 1000

return bench.run({
	verbose = false,
	race = true,
	warmup = {
		enabled = true,
		iterations = 100,
	},
	params = function()
		local sparse_indices = table.create(N) :: { number }
		for i = 1, N do
			sparse_indices[i] = (i * 7) % N
		end
		return sparse_indices
	end,
	baselines = {
		[`boolean table size={N}`] = function(sparse_indices)
			bench.mark("create")
			local bools = table.create(N)
			bench.done()

			bench.mark("sparse write")
			for i = 1, N do
				local idx = sparse_indices[i] + 1 -- Convert to 1-based
				bools[idx] = true
			end
			bench.done()

			bench.mark("sparse read")
			for i = 1, N do
				local idx = sparse_indices[i] + 1 -- Convert to 1-based
				local _ = bools[idx]
			end
			bench.done()

			bench.mark("dense write")
			for i = 1, N do
				bools[i] = true
			end
			bench.done()

			bench.mark("dense read")
			for i = 1, N do
				local _ = bools[i]
			end
			bench.done()
		end,

		[`buffer bitset size={N}`] = function(sparse_indices)
			bench.mark("create")
			local bitset = buffer.create(math.ceil(N / 8))
			bench.done()

			bench.mark("sparse write")
			for i = 1, N do
				local bit_idx = sparse_indices[i]
				buffer.writebits(bitset, bit_idx, 1, 1)
			end
			bench.done()

			bench.mark("sparse read")
			for i = 1, N do
				local bit_idx = sparse_indices[i]
				local _ = buffer.readbits(bitset, bit_idx, 1)
			end
			bench.done()

			bench.mark("dense write")
			for i = 0, N - 1 do
				buffer.writebits(bitset, i, 1, 1)
			end
			bench.done()

			bench.mark("dense read")
			for i = 0, N - 1 do
				local _ = buffer.readbits(bitset, i, 1)
			end
			bench.done()
		end,
	},
})
