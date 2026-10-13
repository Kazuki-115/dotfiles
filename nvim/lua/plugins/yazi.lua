return {
  {
    "mikavilpas/yazi.nvim",
    version = "*",
    event = "VeryLazy",
    dependencies = {
      { "nvim-lua/plenary.nvim", lazy = true },
    },
    init = function()
      local notes_root = vim.fs.normalize(vim.fn.expand("~/notes"))

      local function is_in_notes()
        local cwd = vim.fs.normalize(vim.fn.getcwd())
        return cwd == notes_root or vim.startswith(cwd, notes_root .. "/")
      end

      local function return_to_yazi()
        require("lazy").load({ plugins = { "yazi.nvim" } })
        vim.schedule(function()
          vim.cmd("Yazi toggle")
        end)
      end

      local function delete_current_buffer(force)
        local ok, err = pcall(vim.api.nvim_buf_delete, 0, { force = force })
        if not ok then
          vim.notify(err, vim.log.levels.ERROR)
          return false
        end

        return true
      end

      vim.api.nvim_create_user_command("NotesQ", function(opts)
        if delete_current_buffer(opts.bang) then
          return_to_yazi()
        end
      end, {
        bang = true,
        desc = "Close the current note and return to Yazi",
      })

      vim.api.nvim_create_user_command("NotesWq", function()
        vim.cmd.write()
        if delete_current_buffer(false) then
          return_to_yazi()
        end
      end, {
        desc = "Write and close the current note, then return to Yazi",
      })

      _G.notes_quit_command_abbrev = function(command)
        if vim.fn.getcmdtype() ~= ":" or vim.fn.getcmdline() ~= command or not is_in_notes() then
          return command
        end

        return command == "wq" and "NotesWq" or "NotesQ"
      end

      vim.cmd([[cnoreabbrev <expr> q v:lua.notes_quit_command_abbrev('q')]])
      vim.cmd([[cnoreabbrev <expr> wq v:lua.notes_quit_command_abbrev('wq')]])
    end,
    keys = {
      {
        "<leader>e",
        "<cmd>Yazi<CR>",
        desc = "Open yazi at the current file",
      },
      {
        "<leader>cw",
        "<cmd>Yazi cwd<CR>",
        desc = "Open yazi in the working directory",
      },
    },
    opts = {
      open_for_directories = false,
      -- Use the entire Neovim screen for the Yazi floating window.
      floating_window_scaling_factor = 0.95,
      keymaps = {
        show_help = "<F1>",
        grep_in_directory = false,
        replace_in_directory = false,
      },
      set_keymappings_function = function(yazi_buffer, config, context)
        local actions = require("telescope.actions")
        local keybinding_helpers = require("yazi.keybinding_helpers")
        local yazi_utils = require("yazi.utils")

        local function open_telescope(directory, picker, title)
          picker({
            prompt_title = title .. " in " .. directory,
            cwd = directory,
            attach_mappings = function(prompt_bufnr, map)
              local function return_to_yazi()
                actions.close(prompt_bufnr)
                vim.schedule(function()
                  vim.cmd("Yazi toggle")
                end)
              end

              map("i", "<Esc>", return_to_yazi)
              map("n", "<Esc>", return_to_yazi)
              return true
            end,
          })
        end

        local function open_from_current_directory(picker, title)
          keybinding_helpers.select_current_file_and_close_yazi(config, {
            api = context.api,
            on_file_opened = function(chosen_file)
              local directory = yazi_utils.dir_of(chosen_file).filename
              vim.schedule(function()
                open_telescope(directory, picker, title)
              end)
            end,
          })
        end

        vim.keymap.set("t", "<C-s>", function()
          open_from_current_directory(require("telescope.builtin").find_files, "Find files")
        end, { buffer = yazi_buffer, silent = true })

        vim.keymap.set("t", "<C-g>", function()
          open_from_current_directory(require("telescope.builtin").live_grep, "Live grep")
        end, { buffer = yazi_buffer, silent = true })

        vim.keymap.set("t", "<C-z>", function()
          vim.cmd("confirm qall")
        end, {
          buffer = yazi_buffer,
          silent = true,
          desc = "Quit Neovim and return to the terminal",
        })
      end,
      integrations = {
        grep_in_directory = "telescope",
      },
    },
  },
}
