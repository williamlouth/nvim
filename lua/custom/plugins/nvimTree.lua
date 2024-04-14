local function my_on_attach(bufnr)
  local api = require 'nvim-tree.api'

  local function opts(desc)
    return { desc = 'nvim-tree: ' .. desc, buffer = bufnr, noremap = true, silent = true, noawait = true }
  end
end
return {
  'nvim-tree/nvim-tree.lua',
  config = function()
    require('nvim-tree').setup {
      on_attach = my_on_attach,
    }
  end,
}
