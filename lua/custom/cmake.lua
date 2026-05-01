local M = {}

M.build_dir = 'cmake-build-debug'
M.build_type = 'Debug'
M.last_target = nil
M.last_run_target = nil
M.configure_preset = nil
M.build_preset = nil

-- Panel state
local panel = {
  win = nil,
  bufs = { configure = nil, build = nil, run = nil },
  jobs = { configure = nil, build = nil, run = nil },
  active_tab = nil,
  height = 15,
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
  local labels = { configure = ' Configure', build = ' Build', run = ' Run' }
  local parts = {}
  for _, tab in ipairs(tabs) do
    local hl = (panel.active_tab == tab) and '%#CMakePanelActive#' or '%#CMakePanelInactive#'
    local click = string.format('%%@v:lua.cmake_click_%s@', tab)
    table.insert(parts, click .. hl .. ' ' .. labels[tab] .. ' %X')
  end
  -- Add target selector button
  local target_label = M.last_target or 'select target'
  local target_click = '%@v:lua.cmake_click_target@'
  table.insert(parts, target_click .. '%#CMakePanelTarget# 🎯 ' .. target_label .. ' %X')
  return table.concat(parts, '%#CMakePanelSep# │ ')
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
local function run_in_panel(tab, cmd)
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
    on_exit = function()
      panel.jobs[tab] = nil
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

_G.cmake_click_target = function(_, _, _, _)
  M.select_target()
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

--- Build project or specific target (Shift+F11)
function M.build()
  local build_presets = get_build_presets()

  if #build_presets > 0 then
    local function do_build(preset)
      M.build_preset = preset
      local cmd = 'cmake --build --preset ' .. preset
      if M.last_target then
        cmd = cmd .. ' --target ' .. M.last_target
      end
      notify('Building preset: ' .. preset)
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
    local cmd = 'cmake --build ' .. M.build_dir
    if M.last_target then
      cmd = cmd .. ' --target ' .. M.last_target
    end
    notify('Building...')
    run_in_panel('build', cmd)
  end
end

--- Run last target (Shift+F10)
function M.run_last()
  if not M.last_run_target then
    notify('No run target selected. Use <leader>cr to select one.', vim.log.levels.WARN)
    return
  end
  local executable = get_build_dir() .. '/' .. M.last_run_target
  if not file_exists(executable) then
    local found = vim.fn.globpath(get_build_dir(), '**/' .. vim.fn.fnamemodify(M.last_run_target, ':t'), false, true)
    if type(found) == 'table' and #found > 0 then
      executable = found[1]
    elseif type(found) == 'string' and found ~= '' then
      executable = vim.split(found, '\n')[1]
    else
      notify('Executable not found: ' .. M.last_run_target .. '. Build first (Shift+F11).', vim.log.levels.WARN)
      return
    end
  end
  notify('Running: ' .. vim.fn.fnamemodify(executable, ':t'))
  run_in_panel('run', executable)
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
    -- Build display list with type annotations
    local display = {}
    for _, t in ipairs(targets) do
      table.insert(display, t.name .. ' (' .. t.type .. ')')
    end
    vim.ui.select(display, { prompt = 'Select CMake target:' }, function(_, idx)
      if idx then
        local choice = targets[idx].name
        M.last_target = choice
        M.last_run_target = choice
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

--- Get the winbar display string for editor windows (clickable to select target)
function M.winbar()
  local target = M.last_target or '[no target]'
  return '%@v:lua.cmake_click_target@%#CMakeTarget# CMake: ' .. target .. ' %X%*'
end

-- Setup highlights
local function set_highlights()
  vim.api.nvim_set_hl(0, 'CMakePanelActive', { fg = '#1a1b26', bg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'CMakePanelInactive', { fg = '#a9b1d6', bg = '#24283b' })
  vim.api.nvim_set_hl(0, 'CMakePanelSep', { fg = '#565f89', bg = '#24283b' })
  vim.api.nvim_set_hl(0, 'CMakePanelTarget', { fg = '#9ece6a', bg = '#24283b', bold = true })
  vim.api.nvim_set_hl(0, 'CMakeTarget', { fg = '#7aa2f7', bold = true })
end

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('CMakePanelHL', { clear = true }),
  callback = set_highlights,
})

set_highlights()

return M
