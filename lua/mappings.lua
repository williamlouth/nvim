local treeApi = require 'nvim-tree.api'
vim.keymap.set('n', '<leader>t', treeApi.tree.toggle, { desc = 'Toggle Tree' })
