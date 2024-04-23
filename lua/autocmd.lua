local function augroup(name)
  return vim.api.nvim_create_augroup(name, { clear = true })
end

vim.api.nvim_create_autocmd({ 'BufLeave', 'TabLeave', 'FocusLost', 'WinLeave' }, {
  group = augroup 'AutoSave',
  callback = function()
    vim.cmd 'silent! wall'
  end,
})
