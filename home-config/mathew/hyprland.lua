---@module 'hl'

local mod = "SUPER"
local terminal = "kitty"
local menu = "hyprlauncher"
local fileManager = "nemo"

hl.on("hyprland.start", function()
    hl.exec_cmd("hyprctl output create headless HEADLESS-1")
end)

hl.monitor({
    output   = "HEADLESS-1",
    mode     = "1680x1050@60",
    position = "0x0",
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

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 0,
        resize_on_border = true,
        allow_tearing = true,
        layout = "dwindle",
    },
})

hl.config({
    decoration = {
        rounding = 15,
        rounding_power = 2,
        active_opacity = 1.0,
        inactive_opacity = 0.85,
        shadow = {
            enabled = true,
            range = 15,
            render_power = 3,
        },
        blur = {
            enabled = true,
            size = 4,
            passes = 3,
            vibrancy = 0.1696,
        },
    },
})

hl.config({
    input = {
        touchpad = {
            natural_scroll = true,
            scroll_factor = 0.5,
            tap_to_click = true,    -- тап = клик
            tap_and_drag = true,    -- тап + движение = drag-операция
            drag_lock    = 1,       -- 1: drag lock с таймаутом
            clickfinger_behavior = true,
            middle_button_emulation = true,
            disable_while_typing = true,
        },
    },
})

hl.config({
    dwindle = {
        preserve_split = true,
    },
})

hl.config({
    misc = {
        force_default_wallpaper = 1,
        disable_hyprland_logo = true,
        vrr = 0,
        animate_manual_resizes = true,
    },
})

hl.config({
    input = {
        kb_layout = "us,ru",
        kb_options = "grp:win_space_toggle",
        repeat_delay = 250,
        accel_profile = "flat",
        scroll_factor = 1.7,
    },
})

hl.window_rule({
    match = { class = "pioneergame.exe" },
    immediate = true,
})

hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + M", hl.dsp.exit())
hl.bind(mod .. " + R", hl.dsp.exec_cmd(fileManager))
hl.bind(mod .. " + T", hl.dsp.window.float())
hl.bind(mod .. " + E", hl.dsp.exec_cmd(menu))
hl.bind(mod .. " + P", hl.dsp.window.pseudo())
hl.bind(mod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mod .. " + F", hl.dsp.window.fullscreen())

hl.bind(mod .. " + SHIFT + T", function()
    local ws = hl.get_active_workspace()
    if ws == nil then return end
    local win = nil
    for _, w in ipairs(ws:get_windows()) do
        win = w
        break
    end
    local all_float = (win ~= nil and win.floating)
    for _, w in ipairs(ws:get_windows()) do
        hl.dispatch(hl.dsp.window.float({
            action = all_float and "unset" or "set",
            window = w,
        }))
    end
end)

hl.bind(mod .. " + ALT + left", hl.dsp.window.swap({ direction = "left" }))
hl.bind(mod .. " + ALT + right", hl.dsp.window.swap({ direction = "right" }))
hl.bind(mod .. " + ALT + up", hl.dsp.window.swap({ direction = "up" }))
hl.bind(mod .. " + ALT + down", hl.dsp.window.swap({ direction = "down" }))

for i = 1, 9 do
    hl.bind(mod .. " + code:1" .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + code:1" .. i, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true, locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true, locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { repeating = true, locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { repeating = true, locked = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

