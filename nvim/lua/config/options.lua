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

local frontmatter_namespace = vim.api.nvim_create_namespace("frontmatter")

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

local function conceal_frontmatter(buf)
  vim.api.nvim_buf_clear_namespace(buf, frontmatter_namespace, 0, -1)

  local _, closing_line = frontmatter_range(buf)
  if closing_line then
    vim.api.nvim_buf_set_extmark(buf, frontmatter_namespace, 0, 0, {
      end_row = closing_line - 1,
      end_col = 0,
      conceal_lines = "",
    })
  end
end

local function insert_frontmatter(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local end_line = #lines == 1 and lines[1] == "" and 1 or 0

  vim.api.nvim_buf_set_lines(buf, 0, end_line, false, {
    "---",
    'title: ""',
    'created: "' .. os.date("%Y-%m-%d") .. '"',
    "background: >-",
    "  ",
    "---",
    "",
  })
end

local function close_frontmatter_popup(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function open_frontmatter_popup()
  local source_buf = vim.api.nvim_get_current_buf()
  local start_line, closing_line = frontmatter_range(source_buf)

  if not closing_line then
    insert_frontmatter(source_buf)
    start_line, closing_line = frontmatter_range(source_buf)
    conceal_frontmatter(source_buf)
  end

  local source_lines = vim.api.nvim_buf_get_lines(source_buf, start_line - 1, closing_line, false)
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(popup_buf, "frontmatter://" .. source_buf)
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, source_lines)
  vim.bo[popup_buf].buftype = "acwrite"
  vim.bo[popup_buf].bufhidden = "wipe"
  vim.bo[popup_buf].filetype = "yaml"
  vim.bo[popup_buf].swapfile = false
  vim.bo[popup_buf].modified = false

  local width = 0
  for _, line in ipairs(source_lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(math.max(width + 4, 32), math.floor(vim.o.columns * 0.8))
  local height = math.min(math.max(#source_lines, 3), math.floor(vim.o.lines * 0.6))
  local win = vim.api.nvim_open_win(popup_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Frontmatter ",
    title_pos = "center",
  })

  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false

  for i, line in ipairs(source_lines) do
    if line:match("^background:%s*") then
      local target_line = i
      if line:match("[>|][+-]?%s*$") and source_lines[i + 1] then
        target_line = i + 1
      end
      vim.api.nvim_win_set_cursor(win, { target_line, #source_lines[target_line] })
      break
    end
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = popup_buf,
    callback = function()
      local edited_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)

      if edited_lines[1] ~= "---" or edited_lines[#edited_lines] ~= "---" and edited_lines[#edited_lines] ~= "..." then
        vim.notify("Frontmatter requires opening and closing delimiters", vim.log.levels.ERROR)
        return
      end

      vim.api.nvim_buf_set_lines(source_buf, start_line - 1, closing_line, false, edited_lines)
      vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, edited_lines)
      vim.bo[popup_buf].modified = false
      conceal_frontmatter(source_buf)
      vim.notify("Frontmatter saved", vim.log.levels.INFO)
    end,
  })

  vim.keymap.set("n", "q", function()
    close_frontmatter_popup(win)
  end, { buffer = popup_buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    close_frontmatter_popup(win)
  end, { buffer = popup_buf, silent = true })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc"
    vim.keymap.set("n", "<leader>m", open_frontmatter_popup, {
      buffer = args.buf,
      silent = true,
      desc = "Edit frontmatter in floating window",
    })
    conceal_frontmatter(args.buf)
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
      local filename = os.date("%Y%m%d-%H%M%S.md")
      local path = vim.fs.joinpath(vim.fn.getcwd(), filename)

      vim.api.nvim_buf_set_name(buf, path)
      insert_frontmatter(buf)
      vim.bo[buf].filetype = "markdown"
    end
  end,
})
