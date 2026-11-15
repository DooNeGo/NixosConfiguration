---@module 'hl'

local mod = "SUPER"
local terminal = "kitty"
local menu = "sh -c 'pkill -x rofi || rofi -show drun'"
local fileManager = "nemo"

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
hl.bind(mod .. " + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"))
hl.bind(mod .. " + V", hl.dsp.exec_cmd("clipboard-pick"))

-- Screenshots (saved to ~/Pictures/Screenshots and copied) and the colour picker.
hl.bind("Print", hl.dsp.exec_cmd("hyprshot -m region"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m window"))
hl.bind("CTRL + Print", hl.dsp.exec_cmd("hyprshot -m output"))
hl.bind(mod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"))

-- Arrow keys: focus; with CTRL: resize the active window by 40 px.
local arrows = {
    left  = { dx = -40, dy = 0 },
    right = { dx = 40,  dy = 0 },
    up    = { dx = 0,   dy = -40 },
    down  = { dx = 0,   dy = 40 },
}
for key, step in pairs(arrows) do
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ direction = key }))
    hl.bind(mod .. " + CTRL + " .. key, hl.dsp.window.resize({ x = step.dx, y = step.dy, relative = true }), { repeating = true })
end

hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

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
    -- Hyprland workspaces are 1-based; digit key codes are XKB 10..18.
    hl.bind(mod .. " + code:" .. (i + 9), hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + code:" .. (i + 9), hl.dsp.window.move({ workspace = i }))
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

