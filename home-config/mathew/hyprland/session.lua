---@module 'hl'

hl.on("hyprland.start", function()
    hl.exec_cmd("hyprctl output create headless HEADLESS-1")
    -- Set by the hyprland-mathew and hyprland-headless-mathew system units (remote start): lock before anything is visible on DP-2.
    if os.getenv("HYPRLAND_START_LOCKED") then
        hl.exec_cmd("hyprlock")
    end
end)
