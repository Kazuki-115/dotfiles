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
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
    "---",
    'created: "' .. os.date("%Y-%m-%d") .. '"',
    "background: >-",
    "  ",
    "---",
    "",
  })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc"
    conceal_frontmatter(args.buf)
  end,
})

vim.api.nvim_create_autocmd("BufNewFile", {
  pattern = "*.md",
  callback = function(args)
    local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)

    if #lines == 1 and lines[1] == "" then
      vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, {
        "# ",
        "",
      })
      insert_frontmatter(args.buf)
    end
  end,
})
