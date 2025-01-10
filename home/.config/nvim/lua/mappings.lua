require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

map("n", "<leader>wq", ":wq<CR>", { desc = "Save and quit Neovim" })
map("n", "<leader>qq", ":q!<CR>", { desc = "Force quit Neovim" })
