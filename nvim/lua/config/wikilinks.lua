local M = {}

local function link_under_cursor(line, cursor_col)
  local search_from = 1

  while true do
    local start_col, end_col, target = line:find("%[%[([^%]]+)%]%]", search_from)
    if not start_col then
      break
    end

    if cursor_col >= start_col and cursor_col <= end_col then
      -- Support Obsidian-style aliases: [[note name|display text]].
      return vim.trim((target:match("^(.-)|") or target))
    end

    search_from = end_col + 1
  end

  search_from = 1

  while true do
    local start_col, end_col, target = line:find("%[[^%]]-%]%(([^%)]+)%)", search_from)
    if not start_col then
      break
    end

    if cursor_col >= start_col and cursor_col <= end_col then
      return vim.trim(target)
    end

    search_from = end_col + 1
  end
end

local function open_link()
  local line = vim.api.nvim_get_current_line()
  local cursor_col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local target = link_under_cursor(line, cursor_col)

  if not target or target == "" then
    vim.cmd("normal! gf")
    return
  end

  if target:match("^%a[%w+.-]*://") then
    vim.notify("gf only opens local note links", vim.log.levels.WARN)
    return
  end

  -- Strip a heading or block reference. Heading jumps can be added later;
  -- opening the linked note remains useful in the meantime.
  target = target:match("^[^#^]+") or target
  target = vim.trim(target)

  if target == "" then
    return
  end

  local is_image = target:lower():match("%.png$")
    or target:lower():match("%.jpe?g$")
    or target:lower():match("%.gif$")
    or target:lower():match("%.webp$")
    or target:lower():match("%.avif$")

  if not target:match("%.md$") and not is_image then
    target = target .. ".md"
  end

  local source_path = vim.api.nvim_buf_get_name(0)
  local source_dir = source_path ~= "" and vim.fs.dirname(source_path) or vim.fn.getcwd()
  local note_path = vim.fs.normalize(source_dir .. "/" .. target)
  local parent_dir = vim.fs.dirname(note_path)

  if not is_image and vim.fn.isdirectory(parent_dir) == 0 then
    vim.fn.mkdir(parent_dir, "p")
  end

  if is_image and vim.fn.filereadable(note_path) == 0 then
    vim.notify("Image not found: " .. note_path, vim.log.levels.WARN)
    return
  end

  -- Keep the source note clean while it is hidden behind the linked note.
  -- The linked note itself remains an unsaved buffer until the user writes it.
  if source_path ~= "" and vim.bo.modified then
    vim.cmd.update()
  end

  vim.cmd.edit(vim.fn.fnameescape(note_path))
end

local function wrap_visual_selection()
  local visual_mode = vim.fn.mode()

  if visual_mode ~= "v" and visual_mode ~= "V" then
    vim.notify("Character-wise and line-wise selections can become note links", vim.log.levels.WARN)
    return
  end

  local anchor = vim.fn.getpos("v")
  local cursor = vim.fn.getpos(".")
  local start_row, start_col = anchor[2] - 1, anchor[3] - 1
  local end_row, end_col = cursor[2] - 1, cursor[3] - 1

  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1] or ""
  local end_exclusive

  if visual_mode == "V" then
    start_col = 0
    end_exclusive = #end_line
  else
    local selected_char = vim.fn.strcharpart(end_line:sub(end_col + 1), 0, 1)
    end_exclusive = math.min(end_col + #selected_char, #end_line)
  end

  local escape = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(escape, "nx", false)

  -- Add the closing delimiter first so the opening delimiter does not move it.
  vim.api.nvim_buf_set_text(0, end_row, end_exclusive, end_row, end_exclusive, { "]]" })
  vim.api.nvim_buf_set_text(0, start_row, start_col, start_row, start_col, { "[[" })
end

local function setup_wikilink_conceal(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = ""
    vim.cmd([[
      syntax region NotesWikiLink matchgroup=NotesWikiLinkDelimiter start=/\[\[/ end=/\]\]/ concealends keepend
    ]])
  end)
end

local function configure_markdown_buffer(buf)
  setup_wikilink_conceal(buf)

  vim.keymap.set("n", "gf", open_link, {
    buffer = buf,
    silent = true,
    desc = "Open or create note link",
  })

  vim.keymap.set("x", "<leader>l", wrap_visual_selection, {
    buffer = buf,
    silent = true,
    desc = "Wrap selection in a note link",
  })
end

function M.setup()
  vim.api.nvim_set_hl(0, "NotesWikiLink", { link = "Identifier", default = true })
  vim.api.nvim_set_hl(0, "NotesWikiLinkDelimiter", { link = "Comment", default = true })

  local group = vim.api.nvim_create_augroup("NotesWikiLinks", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
    callback = function(args)
      configure_markdown_buffer(args.buf)
    end,
  })

  -- Also cover Markdown buffers that are already open when this module is reloaded.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "markdown" then
      configure_markdown_buffer(buf)
    end
  end
end

return M
