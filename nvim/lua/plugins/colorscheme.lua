return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("tokyonight").setup({
        transparent = true,
        styles = {
          sidebars = "transparent",
          floats = "transparent",
        },
      })
      vim.cmd.colorscheme("tokyonight")
      vim.api.nvim_set_hl(0, "LineNr", { fg = "#565f89" })
      vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#7aa2f7", bold = true })
    end,
  },
}
