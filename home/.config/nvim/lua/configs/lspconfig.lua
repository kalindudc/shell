-- load defaults
require("nvchad.configs.lspconfig").defaults()

local nvlsp = require "nvchad.configs.lspconfig"
local servers = { "html", "cssls" }

local has_new_api = vim.lsp and vim.lsp.config
local lsp = has_new_api and vim.lsp.config or require("lspconfig")

for _, server in ipairs(servers) do
  local config = lsp[server]
  if config and config.setup then
    config.setup({
      on_attach = nvlsp.on_attach,
      on_init = nvlsp.on_init,
      capabilities = nvlsp.capabilities,
    })
  else
    vim.notify(("LSP server config not found for: %s"):format(server), vim.log.levels.WARN)
  end
end
