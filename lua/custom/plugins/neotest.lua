return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-neotest/nvim-nio',
    'nvim-lua/plenary.nvim',
    'antoinemadec/FixCursorHold.nvim',
    'nvim-treesitter/nvim-treesitter',
    'williamlouth/neotest-catch2',
  },
  config = function()
    require('neotest').setup {
      adapters = {
        require 'neotest-catch2' {
          args = {
            testSuffixes = { 'Tests' },
            buildPrefixes = { 'cmake-build-debug' },
            buildCommandFn = function(target, root)
              local cmd = 'pushd cmake-build-debug && ninja ' .. target .. ' && popd'
              return cmd
            end,
          },
        },
      },
    }
  end,
}
