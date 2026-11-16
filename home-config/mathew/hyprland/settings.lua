---@module 'hl'

hl.config({
    general = {
        gaps_in = @gap_inner@,
        gaps_out = @gap@,
        border_size = 0,
        resize_on_border = true,
        allow_tearing = true,
        layout = "dwindle",
    },
})

hl.config({
    decoration = {
        rounding = @radius_window@,
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
            passes = @blur_passes@,
            vibrancy = 0.1696,
            -- The Waybar menus are popups of a layer surface.
            popups = true,
        },
    },
})

hl.config({
    input = {
        touchpad = {
            natural_scroll = true,
            scroll_factor = 0.5,
            tap_to_click = true,
            tap_and_drag = true,
            drag_lock    = 1,
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
        kb_layout = "@kb_layout@",
        kb_options = "grp:win_space_toggle",
        repeat_delay = 250,
        accel_profile = "flat",
        scroll_factor = 1.7,
    },
})

-- Moonlight/Sunshine virtual mouse: the MacBook trackpad scrolls in fine
-- steps, so it needs a lower factor than a real wheel mouse.
hl.device({
    name = "libvirtualhid-mouse",
    scroll_factor = 0.6,
})
