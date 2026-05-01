local treeApi = require 'nvim-tree.api'
vim.keymap.set('n', '<leader>t', treeApi.tree.toggle, { desc = 'Toggle Tree' })

vim.keymap.set('n', '<F6>', require('dap').toggle_breakpoint, { desc = 'Add Breakpoint' })
vim.keymap.set('n', '<F7>', require('dap').step_into, { desc = 'Step Into' })
vim.keymap.set('n', '<F8>', require('dap').step_over, { desc = 'Step Over' })
vim.keymap.set('n', '<F9>', require('dap').continue, { desc = 'Continue' })

-- CMake workflow (CLion-style)
local cmake = require 'custom.cmake'

vim.keymap.set('n', '<s-F12>', cmake.configure, { desc = 'CMake Configure' })
vim.keymap.set('n', '<F24>', cmake.configure, { desc = 'CMake Configure' })
vim.keymap.set('t', '<s-F12>', function() vim.cmd 'stopinsert'; cmake.configure() end, { desc = 'CMake Configure' })
vim.keymap.set('t', '<F24>', function() vim.cmd 'stopinsert'; cmake.configure() end, { desc = 'CMake Configure' })

vim.keymap.set('n', '<s-F11>', cmake.build, { desc = 'CMake Build' })
vim.keymap.set('n', '<F23>', cmake.build, { desc = 'CMake Build' })
vim.keymap.set('t', '<s-F11>', function() vim.cmd 'stopinsert'; cmake.build() end, { desc = 'CMake Build' })
vim.keymap.set('t', '<F23>', function() vim.cmd 'stopinsert'; cmake.build() end, { desc = 'CMake Build' })

vim.keymap.set('n', '<s-F10>', cmake.run_last, { desc = 'Run Last Target' })
vim.keymap.set('n', '<F22>', cmake.run_last, { desc = 'Run Last Target' })
vim.keymap.set('t', '<s-F10>', function() vim.cmd 'stopinsert'; cmake.run_last() end, { desc = 'Run Last Target' })
vim.keymap.set('t', '<F22>', function() vim.cmd 'stopinsert'; cmake.run_last() end, { desc = 'Run Last Target' })

vim.keymap.set('n', '<leader>cr', cmake.select_target, { desc = '[C]Make Select [R]un Target' })
vim.keymap.set('n', '<leader>ct', cmake.select_target, { desc = '[C]Make Select [T]arget' })
vim.keymap.set('n', '<leader>cc', cmake.select_configure_preset, { desc = '[C]Make [C]onfigure Preset' })
vim.keymap.set('n', '<leader>cb', cmake.select_build_preset, { desc = '[C]Make [B]uild Preset' })
vim.keymap.set('n', '<leader>cp', cmake.toggle_panel, { desc = '[C]Make Toggle [P]anel' })

vim.keymap.set('n', '<A-F12>', function() cmake.show_terminal({ focus = true }) end, { desc = 'Open Terminal' })
vim.keymap.set('n', '<F60>', function() cmake.show_terminal({ focus = true }) end, { desc = 'Open Terminal' })
vim.keymap.set('t', '<A-F12>', '<C-\\><C-n><C-w>p', { desc = 'Leave Terminal' })
vim.keymap.set('t', '<F60>', '<C-\\><C-n><C-w>p', { desc = 'Leave Terminal' })

-- Neotest
local function runNearest()
  require('neotest').summary.open()
  require('neotest').run.run()
end
local function runAll()
  require('neotest').summary.open()
  require('neotest').run.run(vim.fn.expand '%')
end
local function debugNearest()
  require('neotest').summary.open()
  require('neotest').run.run { strategy = 'dap' }
end

vim.keymap.set('n', '<s-F9>', debugNearest, { desc = 'Debug nearest test' })
vim.keymap.set('n', '<F18>', debugNearest, { desc = 'Debug nearest test' })
vim.keymap.set('n', '<leader>tn', runNearest, { desc = '[T]est [N]earest' })
vim.keymap.set('n', '<leader>ta', runAll, { desc = '[T]est [A]ll' })

vim.keymap.set('n', '<leader>Q', require('dapui').toggle, { desc = 'Open dapui' })
vim.keymap.set('n', '<leader>W', require('dap').repl.open, { desc = 'Open repl' })

-- CMake presets/target shown in tabline above bufferline (with click handlers)
vim.o.showtabline = 2
