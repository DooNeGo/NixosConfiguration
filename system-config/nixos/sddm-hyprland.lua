---@module 'hl'

-- Greeter compositor of SDDM: the same Hyprland as the session, with a config of its own so that it shows no
-- "config missing" banner and no default wallpaper. The monitor mode and the layouts are copied from
-- home-config/mathew/hyprland/monitors.lua and home-config/mathew/layouts.nix (another flake): change them together.

hl.monitor({
    output   = "DP-2",
    mode     = "2560x1440@180",
    position = "0x0",
    scale    = 1,
})

hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = 0xff111111,
    },
    input = {
        kb_layout = "us,ru",
        kb_options = "grp:win_space_toggle",
    },
})
