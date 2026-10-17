local function parse_size(text)
  local width, height = text:match("|%s*(%d+)%s*x%s*(%d+)%s*$")
  if width then
    return tonumber(width), tonumber(height)
  end

  width = text:match("|%s*(%d+)%s*$")
  return tonumber(width), nil
end

local function image_size_at_column(line, column)
  for _, spec in ipairs({
    {
      pattern = "!%[([^%]]*)%]%(([^%)]+)%)",
      get_size = function(alt, destination)
        local width, height = parse_size(destination)
        if width then
          return width, height
        end
        return parse_size(alt)
      end,
    },
    {
      pattern = "!%[%[([^%]]+)%]%]",
      get_size = function(target)
        return parse_size(target)
      end,
    },
  }) do
    local search_from = 1

    while true do
      local start_col, end_col, first, second = line:find(spec.pattern, search_from)
      if not start_col then
        break
      end

      if start_col - 1 == column then
        return spec.get_size(first, second)
      end

      search_from = end_col + 1
    end
  end

  return nil, nil
end

local function resolve_image_path(document_path, image_path, fallback)
  image_path = image_path:gsub("|%s*%d+%s*x%s*%d+%s*$", "")
  image_path = image_path:gsub("|%s*%d+%s*$", "")
  image_path = image_path:gsub("%s+$", "")
  return fallback(document_path, image_path)
end

-- A full Sixel clear removes the image from image.nvim's registry. Keep a
-- private reference while the cursor is on its source line so it can be
-- restored without leaving stale pixels behind.
local cursor_hidden_images = {}

local function apply_markdown_image_sizes(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "markdown" then
    return
  end

  local term_size = require("image/utils").term.get_size()
  if not term_size or not term_size.cell_width or not term_size.cell_height then
    return
  end

  local images = require("image").get_images({ buffer = buf, namespace = "markdown" })
  local needs_immediate_terminal_clear = false
  local seen = {}
  for _, image in ipairs(images) do
    seen[image.id] = true
  end
  for id, image in pairs(cursor_hidden_images) do
    if image.buffer == buf and not seen[id] then
      table.insert(images, image)
    end
  end

  for _, image in ipairs(images) do
    local row = image.geometry.y
    local column = image.geometry.x
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local width_px, height_px = image_size_at_column(line, column)
    local width = width_px and math.max(1, math.floor(width_px / term_size.cell_width + 0.5)) or nil
    local height = height_px and math.max(1, math.floor(height_px / term_size.cell_height + 0.5)) or nil
    local cursor_on_image = image.window
      and vim.api.nvim_win_is_valid(image.window)
      and vim.api.nvim_win_get_buf(image.window) == buf
      and vim.api.nvim_win_get_cursor(image.window)[1] - 1 == row
    local geometry_changed = image.notes_width ~= width
      or image.notes_height ~= height
      or image.notes_render_offset_top ~= -1

    if geometry_changed then
      image:clear(true)
      image.geometry.width = width
      image.geometry.height = height
      image.max_width_window_percentage = width and 100 or nil
      image.max_height_window_percentage = height and 100 or nil
      -- Draw on top of the source line instead of one row below it. This also
      -- removes the otherwise empty source row from the rendered layout.
      image.render_offset_top = -1
      image.notes_width = width
      image.notes_height = height
      image.notes_render_offset_top = -1
    end

    if cursor_on_image then
      if not image.notes_hidden_for_cursor then
        cursor_hidden_images[image.id] = image
        -- A full clear schedules a Sixel frame repaint. A shallow clear does
        -- not, which can leave a thin fragment of the old image on screen.
        image:clear()
        needs_immediate_terminal_clear = true
      end
      image.notes_hidden_for_cursor = true
    elseif geometry_changed or image.notes_hidden_for_cursor or not image.is_rendered then
      image.notes_hidden_for_cursor = false
      image:render()
    elseif image.is_rendered then
      cursor_hidden_images[image.id] = nil
    end
  end

  if needs_immediate_terminal_clear then
    -- The Sixel backend normally batches this repaint for 50ms. Clear the
    -- terminal frame now so Neovim does not draw the link text over a still
    -- visible image and make it look like two separate images are vanishing.
    pcall(vim.cmd, "noautocmd mode")
  end
end

return {
  {
    "3rd/image.nvim",
    build = false,
    opts = {
      backend = "sixel",
      processor = "magick_cli",
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = false,
          only_render_image_at_cursor = false,
          floating_windows = false,
          filetypes = { "markdown" },
          resolve_image_path = resolve_image_path,
        },
      },
      max_width_window_percentage = 70,
      max_height_window_percentage = 60,
    },
    config = function(_, opts)
      require("image").setup(opts)

      local group = vim.api.nvim_create_augroup("NotesMarkdownImageSize", { clear = true })
      local function schedule_resize(buf, delay)
        vim.defer_fn(function()
          apply_markdown_image_sizes(buf)
        end, delay or 120)
      end

      vim.api.nvim_create_autocmd({
        "BufEnter",
        "BufWinEnter",
        "BufWritePost",
        "TextChanged",
        "TextChangedI",
      }, {
        group = group,
        pattern = "*.md",
        callback = function(args)
          schedule_resize(args.buf)
        end,
      })

      vim.api.nvim_create_autocmd({ "WinScrolled", "VimResized" }, {
        group = group,
        callback = function()
          schedule_resize(vim.api.nvim_get_current_buf())
        end,
      })

      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        pattern = "*.md",
        callback = function(args)
          apply_markdown_image_sizes(args.buf)
        end,
      })
    end,
  },
}
