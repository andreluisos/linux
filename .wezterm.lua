local wezterm = require("wezterm")
local config = wezterm.config_builder()
config.font = wezterm.font("JetBrainsMono Nerd Font")
config.font_size = 15
config.hide_tab_bar_if_only_one_tab = true
config.default_prog = { "tmux" }
config.window_decorations = "RESIZE"
config.color_scheme = "OneDark"
config.window_background_opacity = 0.8
config.window_padding = {
    left = 0,
    right = 0,
    top = 2,
    bottom = 0,
}
return config
