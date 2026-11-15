---@module 'hl'

-- Apple-style motion: springs without bounce (critically damped: damping = 2*sqrt(stiffness) at mass 1), so a
-- movement starts at once, decelerates and stops without overshoot. A spring's response is 2*pi/sqrt(stiffness):
-- 0.4 s for windows. Fades and closing windows are short ease-outs.
hl.config({ animations = { enabled = true } })

hl.curve("smooth", { type = "spring", mass = 1, stiffness = 247, damping = 31.4 })
-- Workspaces: a sharp start that starts slowing down early and reaches the end smoothly, not a spring, which starts from rest.
hl.curve("sharpStart", { type = "bezier", points = { {0.2, 0.8}, {0.35, 1} } })
hl.curve("easeOut", { type = "bezier", points = { {0.25, 0.1}, {0.25, 1} } })

hl.animation({ leaf = "windowsIn",   enabled = true, speed = 4,   spring = "smooth",     style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4,   spring = "smooth" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 2,   bezier = "easeOut",    style = "popin 94%" })
hl.animation({ leaf = "fade",        enabled = true, speed = 2.5, bezier = "easeOut" })
hl.animation({ leaf = "layers",      enabled = true, speed = 2.5, bezier = "easeOut",    style = "fade" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 3.5,   bezier = "sharpStart", style = "slide" })
