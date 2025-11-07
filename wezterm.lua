local wezterm = require 'wezterm'
local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end

-- 🎨 APPEARANCE
config.font = wezterm.font('JetBrainsMono Nerd Font', { weight = 'Medium' })
config.font_size = 12.0
config.line_height = 0.9
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}
config.window_decorations = 'RESIZE'
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false

-- ⚙️ FUNCTIONALITY
config.hide_tab_bar_if_only_one_tab = false

-- ⌨️ KEYBINDINGS
config.keys = {
  -- Toggle fullscreen
  {
    key = 'F11',
    mods = 'NONE',
    action = wezterm.action.ToggleFullScreen,
  },

  -- Pane splitting
  {
    key = 'e',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' },
  },
  {
    key = 's',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },

  -- Tab management
  {
    key = 't',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.SpawnTab 'CurrentPaneDomain',
  },
  {
    key = 'l',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.ActivateTabRelative(1),
  },
  {
    key = 'h',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.ActivateTabRelative(-1),
  },
}

-- 📈 STATUS BAR SCRIPT - Throttled version (updates only every 3 seconds)
config.status_update_interval = 5000
local cached_stats = ''
local last_update_time = 0

wezterm.on('update-right-status', function(window, pane)
  local current_time = os.time()
  
  -- Only run the script if 3 seconds have passed since last update
  if current_time - last_update_time >= 5 then
    local script_path = wezterm.home_dir .. '/.config/wezterm/status.sh'
    local success, stdout, stderr = wezterm.run_child_process({ 'bash', script_path })
    
    if success and stdout and stdout ~= '' then
      cached_stats = stdout:gsub('[\r\n]+$', '')
    end
    
    last_update_time = current_time
  end
  
  -- Always update the display with cached stats and current time
  local date_time = wezterm.strftime('%a %b %d | %H:%M')
  local status = cached_stats
  if status ~= '' then
    status = status .. ' | '
  end
  window:set_right_status(status .. date_time)
end)

-- This MUST be the last line in your file
return config
