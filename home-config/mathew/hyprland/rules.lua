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

-- "Glass" surfaces (style/): the translucent fill is blurred behind; ignore_alpha keeps fully transparent areas
-- (the gaps between the bar islands) unblurred.
for _, namespace in ipairs({ @glass_layers@ }) do
    hl.layer_rule({
        name = "glass-" .. namespace,
        match = { namespace = "^" .. namespace .. "$" },
        blur = true,
        -- The Waybar menus are popups of the layer surface; the global blur.popups alone does not blur them.
        blur_popups = true,
        ignore_alpha = 0.1,
    })
end
