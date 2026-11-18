---@module 'hl'

hl.on("hyprland.start", function()
    -- Set by the hyprland-headless-mathew system unit (remote start), not by a login at SDDM: a remote session streams
    -- HEADLESS-1; a local login at SDDM has no extra monitor. The lock is hyprlock-initial.service (hyprlock-initial.nix).
    if os.getenv("HYPRLAND_START_LOCKED") then
        hl.exec_cmd("hyprctl output create headless HEADLESS-1")
    end
end)
