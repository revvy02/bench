export type StyLer = typeof(setmetatable({} :: {
    open: string,
    close: string,
}, {} :: {
    __call: (self: StyLer, str: string) -> (string),
    __concat: (self: StyLer, other: { 
        open: string, 
        close: string 
    }) -> (StyLer),
}))

export type CreateStyler = (open: string, close: string) -> ()

export type Chalk = typeof(setmetatable({} :: {
    level: number,
    reset: StyLer,
    bold: StyLer,
    dim: StyLer,
    italic: StyLer,
    underline: StyLer,
    overline: StyLer,
    inverse: StyLer,
    hidden: StyLer,
    strikethrough: StyLer,
    black: StyLer,
    red: StyLer,
    green: StyLer,
    yellow: StyLer,
    blue: StyLer,
    magenta: StyLer,
    cyan: StyLer,
    white: StyLer,
    blackBright: StyLer,
    gray: StyLer,
    grey: StyLer,
    redBright: StyLer,
    greenBright: StyLer,
    yellowBright: StyLer,
    blueBright: StyLer,
    magentaBright: StyLer,
    cyanBright: StyLer,
    whiteBright: StyLer,
    bgBlack: StyLer,
    bgRed: StyLer,
    bgGreen: StyLer,
    bgYellow: StyLer,
    bgBlue: StyLer,
    bgMagenta: StyLer,
    bgCyan: StyLer,
    bgWhite: StyLer,
    bgBlackBright: StyLer,
    bgGray: StyLer,
    bgGrey: StyLer,
    bgRedBright: StyLer,
    bgGreenBright: StyLer,
    bgYellowBright: StyLer,
    bgBlueBright: StyLer,
    bgMagentaBright: StyLer,
    bgCyanBright: StyLer,
    bgWhiteBright: StyLer,

    rgb: (red: number, green: number, blue: number) -> StyLer,
    bgRgb: (red: number, green: number, blue: number) -> StyLer,

    hex: (hex: string) -> StyLer,
    bgHex: (hex: string) -> StyLer,

    ansi: (ansi: number) -> StyLer,
    bgAnsi: (ansi: number) -> StyLer,
    ansi256: (ansi: number) -> StyLer,
    bgAnsi256: (ansi: number) -> StyLer,
}, {} :: {
    __call: (_: any, str: string) -> (string),
}))

return {}