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
