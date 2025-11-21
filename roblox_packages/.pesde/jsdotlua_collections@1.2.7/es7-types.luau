local module = require(script.Parent.Parent:FindFirstChild("jsdotlua_es7-types@1.2.7"):FindFirstChild("es7-types"))
export type Object  = module.Object 
export type Array<T> = module.Array<T>
export type Function  = module.Function 
export type Table<T, V> = module.Table<T, V>
export type Tuple<T, V> = module.Tuple<T, V>
export type mapCallbackFn<K, V> = module.mapCallbackFn<K, V>
export type mapCallbackFnWithThisArg<K, V> = module.mapCallbackFnWithThisArg<K, V>
export type Map<K, V> = module.Map<K, V>
export type WeakMap<K, V> = module.WeakMap<K, V>
export type setCallbackFn<T> = module.setCallbackFn<T>
export type setCallbackFnWithThisArg<T> = module.setCallbackFnWithThisArg<T>
export type Set<T> = module.Set<T>
return module