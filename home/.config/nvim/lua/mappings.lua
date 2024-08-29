require "nvchad.mappings"

local map = vim.keymap.set


local function save_and_quit_all()
  -- Get all buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_option(buf, 'buftype') == '' and vim.api.nvim_buf_get_option(buf, 'modifiable') and vim.api.nvim_buf_get_option(buf, 'modified') then
      if vim.api.nvim_buf_get_name(buf) == '' then
        local file_name = vim.fn.input('Save as: ', '', 'file')
        if file_name ~= '' then
          vim.api.nvim_buf_set_name(buf, file_name)
          vim.cmd('write')
        else
          print('No file name provided. Aborting save and quit.')
          return
        end
      else
        vim.cmd('write')
      end
    end
  end
  -- Quit all windows
  vim.cmd('qa')
end

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

map("n", "<leader>ff", "<cmd> Telescope find_files hidden=true <cr>", { desc = "Find files in cwd" })
map("n", "ff", "<cmd> Telescope find_files hidden=true <cr>", { desc = "Find files in cwd" })

map("n", "<leader>qq", save_and_quit_all, { desc = "Save and quit all windows" })
map('n', '<leader>d', 'yyp', { desc = 'Duplicate current line down' })

map('v', '<Tab>', '>gv', { desc = 'Indent selection' })
map('v', '<S-Tab>', '<gv', { desc = 'Outdent selection' })

