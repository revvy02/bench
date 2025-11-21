local module = require(script.Parent.Parent:FindFirstChild("jsdotlua_expect@3.10.0"):FindFirstChild("expect"))
export type Expect  = module.Expect 
export type ExpectObj  = module.ExpectObj 
export type ExpectExtended<E, State = JestMatcherState> = module.ExpectExtended<E, State >
export type MatcherState  = module.MatcherState 
export type Matcher<R> = module.Matcher<R>
return module