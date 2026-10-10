return {
  {
    "nvim-telescope/telescope.nvim",
    version = "*",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    config = function()
      local telescope = require("telescope")
      local builtin = require("telescope.builtin")
      local action_state = require("telescope.actions.state")

      local function clear_prompt(prompt_bufnr)
        local picker = action_state.get_current_picker(prompt_bufnr)
        vim.api.nvim_buf_set_lines(prompt_bufnr, 0, -1, false, { "" })
        vim.fn.prompt_setprompt(prompt_bufnr, picker.prompt_prefix)
        picker:_reset_prefix_color()
        vim.api.nvim_win_set_cursor(picker.prompt_win, { 1, 0 })
      end

      telescope.setup({
        defaults = {
          initial_mode = "insert",
          mappings = {
            n = {
              ["j"] = "move_selection_next",
              ["k"] = "move_selection_previous",
              ["dd"] = clear_prompt,
            },
            i = {
              ["<C-u>"] = clear_prompt,
            },
          },
          layout_strategy = "horizontal",
          sorting_strategy = "ascending",
          layout_config = {
            width = 0.99,
            height = 0.99,
            preview_width = 0.55,
            preview_cutoff = 80,
            prompt_position = "top",
          },
        },
      })

      vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
      vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
      vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "List buffers" })
      vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
    end,
  },
}
