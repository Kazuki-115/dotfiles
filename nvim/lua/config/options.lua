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

local notes_root = vim.fs.normalize(vim.fn.expand("~/notes"))

local function is_inside_notes(path)
  path = vim.fs.normalize(path)
  return path == notes_root or vim.startswith(path, notes_root .. "/")
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
    vim.keymap.set("n", "<leader>m", function()
      toggle_frontmatter_fold(args.buf)
    end, {
      buffer = args.buf,
      silent = true,
      desc = "Toggle frontmatter fold",
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

vim.api.nvim_create_autocmd("BufNewFile", {
  pattern = "*.md",
  callback = function(args)
    local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)

    if #lines == 1 and lines[1] == "" then
      insert_frontmatter(args.buf)
    end
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    if vim.fn.argc() == 0
      and vim.api.nvim_buf_get_name(buf) == ""
      and #lines == 1
      and lines[1] == ""
    then
      local cwd = vim.fs.normalize(vim.fn.getcwd())

      if not is_inside_notes(cwd) then
        return
      end

      local created_at = os.date("%Y-%m-%d %H:%M:%S")
      local filename = created_at:gsub(
        "^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)$",
        "%1%2%3-%4%5%6"
      ) .. ".md"
      local path = vim.fs.joinpath(cwd, filename)

      vim.api.nvim_buf_set_name(buf, path)
      insert_frontmatter(buf, created_at)
      vim.bo[buf].filetype = "markdown"
    end
  end,
})
