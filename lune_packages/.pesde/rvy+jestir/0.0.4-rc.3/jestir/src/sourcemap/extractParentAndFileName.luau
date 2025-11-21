--!strict

local function extractParentAndFileName(robloxPath: string): (string?, string?)
	local fileName = robloxPath:match('%["([^"]+)"%]$')
	if not fileName then
		return nil, nil
	end

	local parentPath = robloxPath:match('^(.+)%[')
	return parentPath, fileName
end

return extractParentAndFileName
