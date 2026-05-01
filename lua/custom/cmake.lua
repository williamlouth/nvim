local M = {}

M.build_dir = 'cmake-build-debug'
M.build_type = 'Debug'
M.last_target = nil
M.last_run_target = nil
M.configure_preset = nil
M.build_preset = nil

-- Target history (most recent first, max 5)
local target_history = {}

local function add_to_target_history(name)
  -- Remove if already present
  for i, t in ipairs(target_history) do
    if t == name then
      table.remove(target_history, i)
      break
    end
  end
  -- Insert at front
  table.insert(target_history, 1, name)
  -- Cap at 5
  while #target_history > 5 do
    table.remove(target_history)
  end
end

-- Panel state
local panel = {
  win = nil,
  bufs = { configure = nil, build = nil, run = nil },
  jobs = { configure = nil, build = nil, run = nil },
  active_tab = nil,
  height = 15,
  collapsed = false,
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'CMake' })
end

local function file_exists(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

--- Read and parse CMakePresets.json (or CMakeUserPresets.json) from cwd
local function read_presets()
  local presets_file = vim.fn.getcwd() .. '/CMakePresets.json'
  local user_presets_file = vim.fn.getcwd() .. '/CMakeUserPresets.json'

  local file = nil
  if vim.fn.filereadable(presets_file) == 1 then
    file = presets_file
  elseif vim.fn.filereadable(user_presets_file) == 1 then
    file = user_presets_file
  end

  if not file then
    return nil
  end

  local content = table.concat(vim.fn.readfile(file), '\n')
  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    notify('Failed to parse ' .. vim.fn.fnamemodify(file, ':t'), vim.log.levels.WARN)
    return nil
  end
  return data
end

--- Get configure presets from CMakePresets.json
local function get_configure_presets()
  local data = read_presets()
  if not data or not data.configurePresets then
    return {}
  end
  local presets = {}
  for _, p in ipairs(data.configurePresets) do
    if not p.hidden then
      table.insert(presets, p.name)
    end
  end
  return presets
end

--- Get build presets from CMakePresets.json
local function get_build_presets()
  local data = read_presets()
  if not data or not data.buildPresets then
    return {}
  end
  local presets = {}
  for _, p in ipairs(data.buildPresets) do
    if not p.hidden then
      table.insert(presets, p.name)
    end
  end
  return presets
end

--- Get the binary dir for the active configure preset
local function get_preset_binary_dir()
  local data = read_presets()
  if not data or not data.configurePresets or not M.configure_preset then
    return nil
  end
  for _, p in ipairs(data.configurePresets) do
    if p.name == M.configure_preset and p.binaryDir then
      local dir = p.binaryDir:gsub('%${sourceDir}', vim.fn.getcwd())
      return dir
    end
  end
  return nil
end

local function get_build_dir()
  local preset_dir = get_preset_binary_dir()
  if preset_dir then
    return preset_dir
  end
  return vim.fn.getcwd() .. '/' .. M.build_dir
end

--- Check if the panel window is still valid and visible
local function panel_is_open()
  return panel.win and vim.api.nvim_win_is_valid(panel.win)
end

--- Scroll panel window to bottom
local function scroll_panel_to_bottom()
  if not panel_is_open() then
    return
  end
  local buf = vim.api.nvim_win_get_buf(panel.win)
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(panel.win, { line_count, 0 })
end

--- Build the winbar string with clickable tabs for the panel
local function panel_winbar()
  local tabs = { 'configure', 'build', 'run' }
  local labels = { configure = ' CMake', build = ' Build', run = ' Run' }
  local parts = {}
  -- Stop button first (far left) if something is running
  if panel.active_tab and panel.jobs[panel.active_tab] then
    local stop_click = '%@v:lua.cmake_click_stop@'
    table.insert(parts, stop_click .. '%#CMakePanelStop#  Stop %X')
  end
  for _, tab in ipairs(tabs) do
    local hl = (panel.active_tab == tab) and '%#CMakePanelActive#' or '%#CMakePanelInactive#'
    local click = string.format('%%@v:lua.cmake_click_%s@', tab)
    table.insert(parts, click .. hl .. ' ' .. labels[tab] .. ' %X')
  end
  local left = table.concat(parts, '%#CMakePanelSep# │ ')
  -- Close button on far right
  local close_click = '%@v:lua.cmake_click_close@'
  local close_btn = close_click .. '%#CMakePanelClose# X %X'
  return left .. '%=' .. close_btn
end

--- Ensure the panel window exists at the bottom
local function ensure_panel()
  if panel_is_open() then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'

  vim.cmd('botright ' .. panel.height .. 'split')
  panel.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(panel.win, buf)

  vim.wo[panel.win].number = false
  vim.wo[panel.win].relativenumber = false
  vim.wo[panel.win].signcolumn = 'no'
  vim.wo[panel.win].winfixheight = true

  vim.cmd 'wincmd p'
end

--- Show a specific tab's buffer in the panel
local function show_tab(tab)
  ensure_panel()
  panel.active_tab = tab

  -- Expand if collapsed
  if panel.collapsed then
    panel.collapsed = false
    vim.api.nvim_win_set_height(panel.win, panel.height)
  end

  local buf = panel.bufs[tab]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_win_set_buf(panel.win, buf)
  end

  vim.wo[panel.win].winbar = panel_winbar()
  scroll_panel_to_bottom()
end

--- Kill a running job for a given tab
local function kill_job(tab)
  local job_id = panel.jobs[tab]
  if job_id then
    pcall(vim.fn.jobstop, job_id)
    panel.jobs[tab] = nil
  end
end

--- Create a fresh terminal buffer for a tab and run a command
--- @param tab string
--- @param cmd string
--- @param on_complete function|nil called with exit_code when job finishes
local function run_in_panel(tab, cmd, on_complete)
  kill_job(tab)

  local old_buf = panel.bufs[tab]
  if old_buf and vim.api.nvim_buf_is_valid(old_buf) then
    pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
  end

  ensure_panel()

  local cur_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(panel.win)

  -- Create a fresh empty buffer for termopen (requires unmodified buffer)
  local new_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(panel.win, new_buf)

  local job_id = vim.fn.termopen(cmd, {
    on_exit = function(_, exit_code)
      panel.jobs[tab] = nil
      if on_complete then
        vim.schedule(function()
          on_complete(exit_code)
        end)
      end
    end,
  })

  panel.jobs[tab] = job_id
  panel.bufs[tab] = vim.api.nvim_get_current_buf()
  panel.active_tab = tab

  pcall(vim.api.nvim_buf_set_name, panel.bufs[tab], 'cmake://' .. tab)

  -- Auto-scroll on new output
  local term_buf = panel.bufs[tab]
  vim.api.nvim_buf_attach(term_buf, false, {
    on_lines = function(_, buf)
      if panel_is_open() and vim.api.nvim_win_get_buf(panel.win) == buf then
        vim.schedule(function()
          if panel_is_open() and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_get_buf(panel.win) == buf then
            local lc = vim.api.nvim_buf_line_count(buf)
            pcall(vim.api.nvim_win_set_cursor, panel.win, { lc, 0 })
          end
        end)
      end
    end,
  })

  vim.wo[panel.win].winbar = panel_winbar()
  scroll_panel_to_bottom()

  vim.api.nvim_set_current_win(cur_win)
end

--- Stop the currently active tab's job
function M.stop_current()
  local tab = panel.active_tab
  if not tab then
    notify('Nothing running.', vim.log.levels.INFO)
    return
  end
  if panel.jobs[tab] then
    kill_job(tab)
    notify('Stopped: ' .. tab)
    if panel_is_open() then
      vim.wo[panel.win].winbar = panel_winbar()
    end
  else
    notify('Nothing running in ' .. tab .. ' tab.', vim.log.levels.INFO)
  end
end

--- Collapse panel to just the tab bar (jobs keep running)
function M.collapse_panel()
  if not panel_is_open() then
    return
  end
  panel.collapsed = true
  -- Swap to a blank buffer so no distracting content shows
  local blank = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(panel.win, blank)
  vim.api.nvim_win_set_height(panel.win, 1)
  vim.wo[panel.win].winbar = panel_winbar()
end

-- Global click handlers for panel winbar tabs
-- Signature: (minwid, clicks, button, modifiers) required by %@ statusline clicks
_G.cmake_click_configure = function(_, _, _, _)
  show_tab 'configure'
end

_G.cmake_click_build = function(_, _, _, _)
  show_tab 'build'
end

_G.cmake_click_run = function(_, _, _, _)
  show_tab 'run'
end

_G.cmake_click_stop = function(_, _, _, _)
  M.stop_current()
end

_G.cmake_click_close = function(_, _, _, _)
  M.collapse_panel()
end

_G.cmake_click_target = function(_, _, _, _)
  M.select_target()
end

_G.cmake_click_configure_preset = function(_, _, _, _)
  M.select_configure_preset()
end

_G.cmake_click_build_preset = function(_, _, _, _)
  M.select_build_preset()
end

--- Run cmake configure (Shift+F12)
--- Ensure CMake File API query is set up so configure produces codemodel reply
local function ensure_cmake_api_query(build_dir)
  local query_dir = build_dir .. '/.cmake/api/v1/query'
  vim.fn.mkdir(query_dir, 'p')
  local codemodel_query = query_dir .. '/codemodel-v2'
  if vim.fn.filereadable(codemodel_query) == 0 then
    vim.fn.writefile({}, codemodel_query)
  end
end

function M.configure()
  local configure_presets = get_configure_presets()

  if #configure_presets > 0 then
    local function do_configure(preset)
      M.configure_preset = preset
      -- Try to determine the build dir from the preset to set up the API query
      local presets = read_presets()
      if presets and presets.configurePresets then
        for _, p in ipairs(presets.configurePresets) do
          if p.name == preset and p.binaryDir then
            local bd = p.binaryDir:gsub('%${sourceDir}', vim.fn.getcwd())
            ensure_cmake_api_query(bd)
            break
          end
        end
      end
      local cmd = 'cmake --preset ' .. preset
      notify('Configuring preset: ' .. preset)
      run_in_panel('configure', cmd)
    end

    if M.configure_preset and vim.tbl_contains(configure_presets, M.configure_preset) then
      do_configure(M.configure_preset)
    else
      vim.ui.select(configure_presets, { prompt = 'Select configure preset:' }, function(choice)
        if choice then
          do_configure(choice)
        end
      end)
    end
  else
    local build_dir = get_build_dir()
    vim.fn.mkdir(build_dir, 'p')
    ensure_cmake_api_query(build_dir)
    local cmd = string.format('cmake -B %s -DCMAKE_BUILD_TYPE=%s -G Ninja', M.build_dir, M.build_type)
    notify('Configuring...')
    run_in_panel('configure', cmd)
  end
end

--- Build all targets (Shift+F11)
function M.build()
  local build_presets = get_build_presets()

  if #build_presets > 0 then
    local function do_build(preset)
      M.build_preset = preset
      local cmd = 'cmake --build --preset ' .. preset
      notify('Building all (preset: ' .. preset .. ')')
      run_in_panel('build', cmd)
    end

    if M.build_preset and vim.tbl_contains(build_presets, M.build_preset) then
      do_build(M.build_preset)
    else
      vim.ui.select(build_presets, { prompt = 'Select build preset:' }, function(choice)
        if choice then
          do_build(choice)
        end
      end)
    end
  else
    local build_dir = get_build_dir()
    if not file_exists(build_dir .. '/build.ninja') and not file_exists(build_dir .. '/Makefile') then
      notify('No build system found. Run CMake configure first (Shift+F12).', vim.log.levels.WARN)
      return
    end
    local cmd = 'cmake --build ' .. build_dir
    notify('Building all...')
    run_in_panel('build', cmd)
  end
end

--- Build target then run it (Shift+F10)
function M.run_last()
  if not M.last_run_target then
    notify('No run target selected. Use <leader>cr to select one.', vim.log.levels.WARN)
    return
  end

  local target = M.last_run_target
  local build_dir = get_build_dir()

  -- Helper to find and run the executable
  local function do_run()
    local executable = build_dir .. '/' .. target
    if not file_exists(executable) then
      local found = vim.fn.globpath(build_dir, '**/' .. vim.fn.fnamemodify(target, ':t'), false, true)
      if type(found) == 'table' and #found > 0 then
        executable = found[1]
      elseif type(found) == 'string' and found ~= '' then
        executable = vim.split(found, '\n')[1]
      else
        notify('Executable not found: ' .. target, vim.log.levels.WARN)
        return
      end
    end
    notify('Running: ' .. vim.fn.fnamemodify(executable, ':t'))
    run_in_panel('run', executable)
  end

  -- Build the target first, then run on success
  local build_presets = get_build_presets()
  local cmd
  if #build_presets > 0 and M.build_preset then
    cmd = 'cmake --build --preset ' .. M.build_preset .. ' --target ' .. target
  else
    if not file_exists(build_dir .. '/build.ninja') and not file_exists(build_dir .. '/Makefile') then
      notify('No build system found. Run CMake configure first (Shift+F12).', vim.log.levels.WARN)
      return
    end
    cmd = 'cmake --build ' .. build_dir .. ' --target ' .. target
  end

  notify('Building ' .. target .. '...')
  run_in_panel('build', cmd, function(exit_code)
    if exit_code == 0 then
      do_run()
    else
      notify('Build failed (exit ' .. exit_code .. '). Not running.', vim.log.levels.ERROR)
    end
  end)
end

--- Get list of targets using the CMake File API (codemodel)
--- This is the same method cmake-tools.nvim uses - reads the JSON reply files
--- that CMake generates after configure in <build_dir>/.cmake/api/v1/reply/
local function get_targets(callback)
  local build_dir = get_build_dir()
  if not file_exists(build_dir) then
    notify('Build directory not found. Run CMake configure first.', vim.log.levels.WARN)
    return
  end

  -- Ensure the CMake File API query directory exists so next configure produces a reply
  local query_dir = build_dir .. '/.cmake/api/v1/query'
  vim.fn.mkdir(query_dir, 'p')
  -- Create the codemodel query file if it doesn't exist
  local codemodel_query = query_dir .. '/codemodel-v2'
  if vim.fn.filereadable(codemodel_query) == 0 then
    vim.fn.writefile({}, codemodel_query)
  end

  -- Look for the codemodel reply
  local reply_dir = build_dir .. '/.cmake/api/v1/reply'
  if not file_exists(reply_dir) then
    notify('No CMake API reply found. Run CMake configure first (Shift+F12).', vim.log.levels.WARN)
    return
  end

  -- Find the codemodel JSON file
  local reply_files = vim.fn.globpath(reply_dir, 'codemodel-*.json', false, true)
  if type(reply_files) == 'string' then
    reply_files = reply_files ~= '' and vim.split(reply_files, '\n') or {}
  end
  if #reply_files == 0 then
    notify('No codemodel file found. Run CMake configure first (Shift+F12).', vim.log.levels.WARN)
    return
  end

  -- Parse codemodel JSON
  local codemodel_content = table.concat(vim.fn.readfile(reply_files[1]), '\n')
  local ok, codemodel = pcall(vim.json.decode, codemodel_content)
  if not ok or not codemodel then
    notify('Failed to parse codemodel JSON', vim.log.levels.ERROR)
    return
  end

  -- Extract targets from configurations
  local config_targets = {}
  if codemodel.configurations then
    for _, cfg in ipairs(codemodel.configurations) do
      if cfg.targets then
        config_targets = cfg.targets
        break
      end
    end
  end

  if #config_targets == 0 then
    notify('No targets found in codemodel.', vim.log.levels.WARN)
    return
  end

  -- Read each target's JSON to get name and type
  local targets = {}
  for _, t in ipairs(config_targets) do
    local target_file = reply_dir .. '/' .. t.jsonFile
    if vim.fn.filereadable(target_file) == 1 then
      local target_content = table.concat(vim.fn.readfile(target_file), '\n')
      local tok, target_info = pcall(vim.json.decode, target_content)
      if tok and target_info then
        local name = target_info.name
        local target_type = (target_info.type or ''):lower():gsub('_', ' ')
        -- Skip autogen targets
        if name and not name:find '_autogen' then
          table.insert(targets, { name = name, type = target_type })
        end
      end
    end
  end

  if #targets == 0 then
    notify('No valid targets found.', vim.log.levels.WARN)
    return
  end

  callback(targets)
end

--- Select a build/run target via selector
function M.select_target()
  get_targets(function(targets)
    -- Build items: recent history first, then all remaining targets
    local items = {}
    local seen = {}

    -- Add recent targets first (if they still exist in current targets)
    for _, hist_name in ipairs(target_history) do
      for _, t in ipairs(targets) do
        if t.name == hist_name then
          table.insert(items, { name = t.name, type = t.type, recent = true })
          seen[t.name] = true
          break
        end
      end
    end

    -- Add separator and remaining targets
    for _, t in ipairs(targets) do
      if not seen[t.name] then
        table.insert(items, { name = t.name, type = t.type, recent = false })
      end
    end

    -- Build display list
    local display = {}
    for _, item in ipairs(items) do
      local prefix = item.recent and '⏱ ' or '  '
      table.insert(display, prefix .. item.name .. ' (' .. item.type .. ')')
    end

    vim.ui.select(display, { prompt = 'Select CMake target (recent first):' }, function(_, idx)
      if idx then
        local choice = items[idx].name
        M.last_target = choice
        M.last_run_target = choice
        add_to_target_history(choice)
        notify('Target set: ' .. choice)
        if panel_is_open() then
          vim.wo[panel.win].winbar = panel_winbar()
        end
        vim.cmd 'redrawstatus'
      end
    end)
  end)
end

--- Select configure preset
function M.select_configure_preset()
  local presets = get_configure_presets()
  if #presets == 0 then
    notify('No configure presets found in CMakePresets.json', vim.log.levels.WARN)
    return
  end
  vim.ui.select(presets, { prompt = 'Select configure preset:' }, function(choice)
    if choice then
      M.configure_preset = choice
      notify('Configure preset: ' .. choice)
      if panel_is_open() then
        vim.wo[panel.win].winbar = panel_winbar()
      end
      vim.cmd 'redrawstatus'
    end
  end)
end

--- Select build preset
function M.select_build_preset()
  local presets = get_build_presets()
  if #presets == 0 then
    notify('No build presets found in CMakePresets.json', vim.log.levels.WARN)
    return
  end
  vim.ui.select(presets, { prompt = 'Select build preset:' }, function(choice)
    if choice then
      M.build_preset = choice
      notify('Build preset: ' .. choice)
      if panel_is_open() then
        vim.wo[panel.win].winbar = panel_winbar()
      end
      vim.cmd 'redrawstatus'
    end
  end)
end

--- Toggle panel visibility
function M.toggle_panel()
  if panel_is_open() then
    vim.api.nvim_win_close(panel.win, true)
    panel.win = nil
  else
    if panel.active_tab then
      show_tab(panel.active_tab)
    end
  end
end

--- Get the winbar display string for editor windows
--- Shows: [configure preset] | [build preset] | [target]
--- Each is clickable to select/change
function M.winbar()
  local parts = {}

  -- Configure preset (clickable)
  local cfg_label = M.configure_preset or '[configure]'
  local cfg_click = '%@v:lua.cmake_click_configure_preset@'
  table.insert(parts, cfg_click .. '%#CMakePreset#  ' .. cfg_label .. ' %X')

  -- Build preset (clickable)
  local bld_label = M.build_preset or '[build]'
  local bld_click = '%@v:lua.cmake_click_build_preset@'
  table.insert(parts, bld_click .. '%#CMakePreset#  ' .. bld_label .. ' %X')

  -- Target (clickable)
  local target = M.last_target or '[no target]'
  local tgt_click = '%@v:lua.cmake_click_target@'
  table.insert(parts, tgt_click .. '%#CMakeTarget# 🎯 ' .. target .. ' %X')

  return '%=' .. table.concat(parts, '%#CMakePanelSep# │ ') .. '%*'
end

-- Setup highlights
local function set_highlights()
  vim.api.nvim_set_hl(0, 'CMakePanelActive', { fg = '#1a1b26', bg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'CMakePanelInactive', { fg = '#a9b1d6', bg = '#24283b' })
  vim.api.nvim_set_hl(0, 'CMakePanelSep', { fg = '#565f89', bg = '#24283b' })
  vim.api.nvim_set_hl(0, 'CMakePanelTarget', { fg = '#9ece6a', bg = '#24283b', bold = true })
  vim.api.nvim_set_hl(0, 'CMakePanelStop', { fg = '#f7768e', bg = '#24283b', bold = true })
  vim.api.nvim_set_hl(0, 'CMakePanelClose', { fg = '#f7768e', bg = '#24283b', bold = true })
  vim.api.nvim_set_hl(0, 'CMakeTarget', { fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'CMakePreset', { fg = '#bb9af7', bold = true })
end

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('CMakePanelHL', { clear = true }),
  callback = set_highlights,
})

set_highlights()

return M
