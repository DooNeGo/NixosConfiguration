---@module 'hl'

-- Apps (kitty among them) ask to start maximized, which fills the work area on top of the other windows
-- instead of joining the layout; the request is ignored.
hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Tearing (lower latency) only applies to a fullscreen window; allow_tearing is set in settings.lua.
hl.window_rule({
    match = { class = "^steam_app_.*$" },
    immediate = true,
})

-- "Glass" surfaces (glass.nix): the translucent fill is blurred behind; ignore_alpha keeps fully transparent areas
-- (the gaps between the bar islands) unblurred.
for _, namespace in ipairs({ "waybar", "notifications", "rofi" }) do
    hl.layer_rule({
        name = "glass-" .. namespace,
        match = { namespace = "^" .. namespace .. "$" },
        blur = true,
        ignore_alpha = 0.1,
    })
end
