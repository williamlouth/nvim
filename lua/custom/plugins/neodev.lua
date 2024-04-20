return {
  'nvim-neotest/nvim-nio',
  'neodev',
  config = function()
    require('neodev').setup {
      library = { plugins = { 'nvim-dap-ui' }, types = true },
    }
  end,
}
