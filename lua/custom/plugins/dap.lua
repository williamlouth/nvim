local function my_on_attach()
  local dap = require 'dap'
  dap.adapters.gdb = {
    type = 'executable',
    name = 'gdb',
    command = 'gdb',
    args = { '-i', 'dap' },
  }
  dap.adapters.cpptools = {
    type = 'executable',
    name = 'cpptools',
    command = vim.fn.stdpath 'data' .. '/mason/bin/OpenDebugAD7',
    args = {},
    attach = {
      pidProperty = 'processId',
      pidSelect = 'ask',
    },
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
