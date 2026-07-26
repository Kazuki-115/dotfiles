require("config.lazy")
require("config.options")
require("config.keymaps")

require("lazy").setup("plugins", {
  install = { colorscheme = { "habamax" } },
  checker = { enabled = true },
})
