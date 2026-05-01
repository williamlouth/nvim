return {
  'akinsho/bufferline.nvim',
  lazy = false,
  priority = 900,
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    vim.opt.showtabline = 2

    require('bufferline').setup {
      options = {
        always_show_bufferline = true,
        offsets = {
          {
            filetype = 'NvimTree',
            text = 'File Explorer',
            highlight = 'Directory',
            separator = true,
          },
        },
        show_buffer_close_icons = true,
        show_close_icon = false,
        separator_style = 'slant',
        custom_areas = {
          right = function()
            local cmake = require 'custom.cmake'
            local parts = {}

            local cfg_label = cmake.configure_preset or '[configure]'
            table.insert(parts, { text = '%@v:lua.cmake_click_configure_preset@  ' .. cfg_label .. ' %X', fg = '#bb9af7' })

            local bld_label = cmake.build_preset or '[build]'
            table.insert(parts, { text = '%@v:lua.cmake_click_build_preset@  ' .. bld_label .. ' %X', fg = '#bb9af7' })

            local target = cmake.last_target or '[no target]'
            table.insert(parts, { text = '%@v:lua.cmake_click_target@ 🎯 ' .. target .. ' %X', fg = '#7aa2f7' })

            return parts
          end,
        },
      },
    }

    -- Navigate between buffer tabs
    vim.keymap.set('n', '<Tab>', ':BufferLineCycleNext<CR>', { desc = 'Next buffer tab', silent = true })
    vim.keymap.set('n', '<S-Tab>', ':BufferLineCyclePrev<CR>', { desc = 'Previous buffer tab', silent = true })
    vim.keymap.set('n', '<leader>x', ':bdelete<CR>', { desc = 'Close buffer tab', silent = true })
  end,
}
