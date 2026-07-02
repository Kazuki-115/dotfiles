-- Pull in the wezterm API
local wezterm = require 'wezterm'
local act = wezterm.action

local action_required_spinner_frame = 1

local function has_action_required(tab_info)
  local pane_title = tab_info.active_pane.title or ''
  return pane_title:lower():find('action required', 1, true) ~= nil
end

local function animated_action_required_title()
  local frames = {
    ' ACTION REQUIRED',
    ' ACTION REQUIRED',
    ' ACTION REQUIRED',
    ' ACTION REQUIRED',
    ' ACTION REQUIRED',
    ' ACTION REQUIRED',
    ' ACTION REQUIRED',
    ' ACTION REQUIRED',
    ' ACTION REQUIRED',
    ' ACTION REQUIRED',
  }

  return frames[action_required_spinner_frame]
end

local function tab_title(tab_info)
  if has_action_required(tab_info) then
    return animated_action_required_title()
  end

  local title = tab_info.tab_title
  if title and #title > 0 then
    return title
  end

  return tab_info.active_pane.title
end

local function current_tab_title_for_prompt(window, pane)
  local ok, title = pcall(function()
    return window:active_tab():get_title()
  end)

  if ok and title and #title > 0 then
    return title
  end

  local pane_title = pane:get_title()
  if pane_title and #pane_title > 0 then
    return pane_title
  end

  return ''
end

local function hex_to_rgb(hex)
  hex = hex:gsub('#', '')

  return {
    r = tonumber(hex:sub(1, 2), 16),
    g = tonumber(hex:sub(3, 4), 16),
    b = tonumber(hex:sub(5, 6), 16),
  }
end

local function rgb_to_hex(rgb)
  return string.format('#%02x%02x%02x', rgb.r, rgb.g, rgb.b)
end

local function mix_channel(a, b, t)
  return math.floor(a + (b - a) * t + 0.5)
end

local function blend_hex(start_hex, end_hex, t)
  local a = hex_to_rgb(start_hex)
  local b = hex_to_rgb(end_hex)

  return rgb_to_hex({
    r = mix_channel(a.r, b.r, t),
    g = mix_channel(a.g, b.g, t),
    b = mix_channel(a.b, b.b, t),
  })
end

local function gradient_color(index, count)
  local stops = {
    '#3f6fb5',
    '#2f8f83',
    '#4e86a6',
  }

  if count <= 1 then
    return stops[1]
  end

  local position = index / (count - 1)

  if position <= 0.5 then
    return blend_hex(stops[1], stops[2], position / 0.5)
  end

  return blend_hex(stops[2], stops[3], (position - 0.5) / 0.5)
end

local function find_tab_index(tab, tabs)
  for index, candidate in ipairs(tabs) do
    if candidate.tab_id == tab.tab_id then
      return index - 1
    end
  end

  return 0
end

wezterm.on('format-tab-title', function(
  tab,
  tabs,
  panes,
  config,
  hover,
  max_width
)

  local index = find_tab_index(tab, tabs)

  local background = gradient_color(index, #tabs)
  local foreground = '#e6edf3'

  if tab.is_active then
    background = '#0b0f14'
    foreground = '#ffffff'
  else
    background = blend_hex(background, '#10161d', 0.18)
  end

  if hover then
    background = blend_hex(background, '#ffffff', 0.06)
  end

  local title =
    wezterm.truncate_right(
      ' ' .. tab_title(tab) .. ' ',
      max_width - 2
    )

  return {
    { Background = { Color = '#1f1f28' } },
    { Foreground = { Color = background } },
    { Text = '' },

    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = title },

    { Background = { Color = '#1f1f28' } },
    { Foreground = { Color = background } },
    { Text = '' },
  }
end)

wezterm.on('update-status', function(window, pane)
  action_required_spinner_frame =
    (action_required_spinner_frame % 10) + 1

  pcall(function()
    window:invalidate()
  end)
end)

-- This will hold the configuration.
local config = wezterm.config_builder()

-- For example, changing the initial geometry for new windows:
config.initial_cols = 120
config.initial_rows = 28

config.status_update_interval = 300

config.window_background_opacity = 0.95
config.macos_window_background_blur = 0

config.font_size = 14

config.font = wezterm.font_with_fallback {
  'Menlo',
  'Hiragino Sans',
  'Noto Sans CJK JP',
}

-- タブ自体を大きくする
config.window_frame = {
  font_size = 17.0,
}

-- タブの左右の余白を増やす
config.tab_max_width = 32

config.use_fancy_tab_bar = false

-- Option+j / Option+kでタブ移動
config.keys = {
  {
    key = 'j',
    mods = 'OPT',
    action = act.ActivateTabRelative(-1),
  },
  {
    key = 'k',
    mods = 'OPT',
    action = act.ActivateTabRelative(1),
  },
  {
    key = 'J',
    mods = 'CMD|SHIFT',
    action = act.MoveTabRelative(-1),
  },
  {
    key = 'K',
    mods = 'CMD|SHIFT',
    action = act.MoveTabRelative(1),
  },
  {
    key = 'E',
    mods = 'CMD|SHIFT',
    action = wezterm.action_callback(function(window, pane)
      window:perform_action(
        act.PromptInputLine {
          description = 'Rename tab',
          initial_value =
            current_tab_title_for_prompt(window, pane),

          action = wezterm.action_callback(function(
            inner_window,
            inner_pane,
            line
          )
            if line then
              inner_window:active_tab():set_title(line)
            end
          end),
        },
        pane
      )
    end),
  },
  {
    key = 'N',
    mods = 'CMD|SHIFT',
    action = wezterm.action_callback(function(window, pane)
      pane:move_to_new_window()
    end),
  },
  {
    key = 'h',
    mods = 'CTRL|SHIFT',
    action = act.ActivatePaneDirection 'Left',
  },
  {
    key = 'j',
    mods = 'CTRL|SHIFT',
    action = act.ActivatePaneDirection 'Down',
  },
  {
    key = 'k',
    mods = 'CTRL|SHIFT',
    action = act.ActivatePaneDirection 'Up',
  },
  {
    key = 'l',
    mods = 'CTRL|SHIFT',
    action = act.ActivatePaneDirection 'Right',
  },
  {
    key = 'H',
    mods = 'CMD|SHIFT',
    action = act.RotatePanes 'Clockwise',
  },
  {
    key = 'W',
    mods = 'CMD|SHIFT',
    action = act.CloseCurrentPane { confirm = true },
  },
}

config.color_scheme = 'AdventureTime'

config.colors = {
  foreground = '#ffffff',

  ansi = {
    '#000000',
    '#ff5555',
    '#50fa7b',
    '#f1fa8c',
    '#bd93f9',
    '#ff79c6',
    '#8be9fd',
    '#f8f8f2',
  },

  brights = {
    '#4d4d4d',
    '#ff6e6e',
    '#69ff94',
    '#ffffa5',
    '#d6acff',
    '#ff92df',
    '#a4ffff',
    '#ffffff',
  },

  tab_bar = {
    background = '#1f1f28',

    active_tab = {
      bg_color = '#3b4252',
      fg_color = '#ffffff',
    },

    inactive_tab = {
      bg_color = '#2a2f3a',
      fg_color = '#d8dee9',
    },

    inactive_tab_hover = {
      bg_color = '#353b45',
      fg_color = '#ffffff',
    },

    new_tab = {
      bg_color = '#1f1f28',
      fg_color = '#d8dee9',
    },

    new_tab_hover = {
      bg_color = '#353b45',
      fg_color = '#ffffff',
    },
  },
}

return config
