vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.clipboard = "unnamedplus"
vim.opt.number = true
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.fillchars:append({ eob = " " })
vim.opt.foldopen:remove("undo")

local frontmatter_highlight_namespace = vim.api.nvim_create_namespace("frontmatter-highlight")

local function frontmatter_range(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  if lines[1] ~= "---" then
    return nil
  end

  for i = 2, #lines do
    if lines[i] == "---" or lines[i] == "..." then
      return 1, i
    end
  end
end

local function highlight_frontmatter(buf)
  vim.api.nvim_buf_clear_namespace(buf, frontmatter_highlight_namespace, 0, -1)

  local _, closing_line = frontmatter_range(buf)
  if not closing_line then
    return
  end

  vim.api.nvim_buf_set_extmark(buf, frontmatter_highlight_namespace, 0, 0, {
    end_row = closing_line - 1,
    end_col = -1,
    end_right_gravity = true,
    hl_group = "Normal",
    priority = 200,
    strict = false,
  })

  local lines = vim.api.nvim_buf_get_lines(buf, 0, closing_line, false)
  for row, line in ipairs(lines) do
    local key = line:match("^(created):") or line:match("^(background):")
    if key then
      vim.api.nvim_buf_set_extmark(buf, frontmatter_highlight_namespace, row - 1, 0, {
        end_col = #key,
        hl_group = "PreProc",
        priority = 210,
      })
    end
  end
end

local function insert_frontmatter(buf, created_at)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local end_line = #lines == 1 and lines[1] == "" and 1 or 0
  created_at = created_at or os.date("%Y-%m-%d %H:%M:%S")

  vim.api.nvim_buf_set_lines(buf, 0, end_line, false, {
    "---",
    'created: "' .. created_at .. '"',
    "background: >-",
    "  ",
    "---",
    "",
  })
end

local function fold_frontmatter(buf)
  local start_line, closing_line = frontmatter_range(buf)
  if not closing_line then
    return
  end

  vim.opt_local.foldmethod = "manual"
  vim.opt_local.foldenable = true
  vim.cmd(("silent! %d,%dfold"):format(start_line, closing_line))
  vim.cmd(("silent! %dfoldclose"):format(start_line))
end

local function toggle_frontmatter_fold(buf)
  local start_line, closing_line = frontmatter_range(buf)
  if not closing_line then
    return
  end

  if vim.fn.foldlevel(start_line) == 0 then
    vim.cmd(("silent! %d,%dfold"):format(start_line, closing_line))
  end

  if vim.fn.foldclosed(start_line) == -1 then
    vim.cmd(("silent! %dfoldclose!"):format(start_line))
  else
    vim.cmd(("silent! %dfoldopen!"):format(start_line))
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    fold_frontmatter(args.buf)
    highlight_frontmatter(args.buf)
    vim.keymap.set("n", "<leader>m", function()
      toggle_frontmatter_fold(args.buf)
    end, {
      buffer = args.buf,
      silent = true,
      desc = "Toggle frontmatter fold",
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = args.buf,
      callback = function()
        highlight_frontmatter(args.buf)
      end,
    })

    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(args.buf) or vim.api.nvim_get_current_buf() ~= args.buf then
        return
      end

      local _, closing_line = frontmatter_range(args.buf)
      local cursor = vim.api.nvim_win_get_cursor(0)
      if closing_line and cursor[1] <= closing_line and closing_line < vim.api.nvim_buf_line_count(args.buf) then
        vim.api.nvim_win_set_cursor(0, { closing_line + 1, 0 })
      end
    end)
  end,
})

vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost" }, {
  pattern = "*.md",
  callback = function(args)
    local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)

    if #lines == 1 and lines[1] == "" then
      insert_frontmatter(args.buf)
    end
  end,
})
