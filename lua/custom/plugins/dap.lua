local function my_on_attach()
  local dap = require 'dap'
  dap.adapters.gdb = {
    type = 'executable',
    name = 'gdb',
    args = { '-i', 'dap' },
  }
  dap.configurations.cpp = {
    {
      name = 'Launch',
      type = 'gdb',
      request = 'launch',
      program = '${workspaceFolder}/cmake-build-debug/test/UnitTests/UnitTests',
      cwd = '${workspaceFolder}/cmake-build-debug/',
      stopOnEntry = true,
      args = {},
      runInTerminal = false,
    },
  }
end

return {
  'mfussenegger/nvim-dap',
  config = my_on_attach,
}
