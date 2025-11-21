--!strict

export type RunTarget = "cloud" | "once" | "serve"

export type CloudConfig = {
	target: "cloud",
	universeId: string,
	placeId: string,
	placeVersion: string?,
	apiKey: string,
	upload: boolean?,
	placePath: string?,
}

export type OnceConfig = {
	target: "once",
	placePath: string,
	sourcemapPath: string?,
	noError: boolean?,
	noWarn: boolean?,
}

export type ServeConfig = {
	target: "serve",
	sourcemapPath: string?,
	noError: boolean?,
	noWarn: boolean?,
}

export type RunTargetConfig = CloudConfig | OnceConfig | ServeConfig

return nil
