local module = require(script.Parent:FindFirstChild(".pesde"):FindFirstChild("jsdotlua_jest-globals@3.10.0"):FindFirstChild("jest-globals"))
export type MatcherState  = module.MatcherState 
export type ExpectExtended<E, State = MatcherState> = module.ExpectExtended<E, State >
return module