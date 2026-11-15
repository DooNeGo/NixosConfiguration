---@module 'hl'

hl.monitor({
    output   = "HEADLESS-1",
    mode     = "1680x1050@60",
    -- Right of DP-2: at the same position as DP-2 the two outputs overlap in the layout.
    position = "2560x0",
    scale    = 1,
})

hl.monitor({
    output   = "DP-2",
    mode     = "2560x1440@180",
    position = "0x0",
    scale    = 1,
    cm       = "srgb",
    bitdepth = 10,
    vrr      = 1,
    sdr_min_luminance = 0.005,
    sdr_max_luminance = 400,
})
