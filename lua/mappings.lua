local treeApi = require 'nvim-tree.api'
vim.keymap.set('n', '<leader>t', treeApi.tree.toggle, { desc = 'Toggle Tree' })

vim.keymap.set('n', '<F6>', require('dap').toggle_breakpoint, { desc = 'Add Breakpoint' })
vim.keymap.set('n', '<F7>', require('dap').step_into, { desc = 'Step Into' })
vim.keymap.set('n', '<F8>', require('dap').step_over, { desc = 'Step Over' })
vim.keymap.set('n', '<F9>', require('dap').continue, { desc = 'Continue' })
vim.keymap.set('n', '<s-F10>', require('neotest').run.run, { desc = 'run nearest test' })
vim.keymap.set('n', '<F22>', require('neotest').run.run, { desc = 'run nearest test' })
vim.keymap.set('n', '<F24>', function()
  require('neotest').run.run(vim.fn.expand '%')
end, { desc = 'summary open' })
vim.keymap.set('n', '<s-F12>', function()
  require('neotest').run.run(vim.fn.expand '%')
end, { desc = 'summary open' })

vim.keymap.set('n', '<leader>Q', require('dapui').toggle, { desc = 'Open dapui' })
vim.keymap.set('n', '<leader>W', require('dap').repl.open, { desc = 'Open repl' })
