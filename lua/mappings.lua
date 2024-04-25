local treeApi = require 'nvim-tree.api'
vim.keymap.set('n', '<leader>t', treeApi.tree.toggle, { desc = 'Toggle Tree' })

vim.keymap.set('n', '<F6>', require('dap').toggle_breakpoint, { desc = 'Add Breakpoint' })
vim.keymap.set('n', '<F7>', require('dap').step_into, { desc = 'Step Into' })
vim.keymap.set('n', '<F8>', require('dap').step_over, { desc = 'Step Over' })
vim.keymap.set('n', '<F9>', require('dap').continue, { desc = 'Continue' })

local function runNearest()
  require('neotest').summary.close()
  require('neotest').summary.open()
  require('neotest').run.run()
end
local function runAll()
  require('neotest').summary.close()
  require('neotest').summary.open()
  require('neotest').run.run(vim.fn.expand '%')
end

vim.keymap.set('n', '<s-F10>', runNearest, { desc = 'run nearest test' })
vim.keymap.set('n', '<F22>', runNearest, { desc = 'run nearest test' })

vim.keymap.set('n', '<F24>', runAll, { desc = 'run all tests' })
vim.keymap.set('n', '<s-F12>', runAll, { desc = 'run all tests' })

vim.keymap.set('n', '<leader>Q', require('dapui').toggle, { desc = 'Open dapui' })
vim.keymap.set('n', '<leader>W', require('dap').repl.open, { desc = 'Open repl' })
