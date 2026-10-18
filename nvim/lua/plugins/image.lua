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

      if column == nil or start_col - 1 == column then
        local width, height = spec.get_size(first, second)
        return width, height, true
      end

      search_from = end_col + 1
    end
  end

  return nil, nil, false
end

local function resolve_image_path(document_path, image_path, fallback)
  image_path = image_path:gsub("|%s*%d+%s*x%s*%d+%s*$", "")
  image_path = image_path:gsub("|%s*%d+%s*$", "")
  image_path = image_path:gsub("%s+$", "")
  return fallback(document_path, image_path)
end

local markdown_image_state = nil
local markdown_edit_generation = 0
local markdown_cursor_history = {}

local function remove_stale_image_padding(image)
  if not image or not image.buffer or not vim.api.nvim_buf_is_valid(image.buffer) then
    return
  end

  local namespace = image.global_state and image.global_state.extmarks_namespace
  if not namespace then
    return
  end

  -- An asynchronous render from the pre-edit image can recreate its extmark
  -- after the replacement image has already rendered. Both marks then reserve
  -- the same virtual rows, doubling the apparent image height. Keep only the
  -- extmark owned by the current image at this exact anchor.
  local matching = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(
    image.buffer, namespace, 0, -1, { details = true }
  )) do
    local id, row, col = mark[1], mark[2], mark[3]
    if row == image.geometry.y and col == image.geometry.x then
      matching[#matching + 1] = id
    end
  end

  if #matching <= 1 then
    return
  end

  local keep = matching[#matching]
  for _, id in ipairs(matching) do
    if id == image.internal_id then
      keep = id
      break
    end
  end
  for _, id in ipairs(matching) do
    if id ~= keep then
      pcall(vim.api.nvim_buf_del_extmark, image.buffer, namespace, id)
    end
  end
end

local function repaint_without_hidden_image(image)
  local state = image and image.global_state
  if not state or not state.backend then
    return
  end

  -- A shallow Image:clear() removes the image from Sixel's desired frame but
  -- does not schedule that empty frame for painting. Clear the terminal frame
  -- without deleting any Image objects, then queue every other visible image
  -- again. This removes leftover pixels while keeping the hidden image ready
  -- to return when the cursor leaves its source line.
  pcall(state.backend.clear)
  for _, other in pairs(state.images or {}) do
    if other ~= image and not other.notes_hidden_for_cursor then
      pcall(other.render, other)
    end
  end
  state.images[image.id] = image
end

local function configure_markdown_image_before_render(image, options)
  if not image or not options or options.namespace ~= "markdown" then
    return image
  end

  local buf = options.buffer
  local row = options.id and tonumber(options.id:match("^%d+:%d+:(%d+):")) or nil
  if not buf or not row or not vim.api.nvim_buf_is_valid(buf) then
    return image
  end

  local term_size = require("image/utils").term.get_size()
  if not term_size or not term_size.cell_width or not term_size.cell_height then
    return image
  end

  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local width_px, height_px = image_size_at_column(line, nil)
  local width = width_px and math.max(1, math.floor(width_px / term_size.cell_width + 0.5)) or nil
  local height = height_px and math.max(1, math.floor(height_px / term_size.cell_height + 0.5)) or nil
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  local configure_geometry = image.notes_changedtick ~= changedtick

  if configure_geometry then
    image.geometry.width = width
    image.geometry.height = height
    image.max_width_window_percentage = width and 100 or nil
    image.max_height_window_percentage = height and 100 or nil
    image.render_offset_top = -1
    image.notes_width = width
    image.notes_height = height
    image.notes_render_offset_top = -1
  end
  markdown_image_state = image.global_state

  -- Every render entry point must honor cursor hiding, including core
  -- decorators, document refreshes and asynchronous transform completion.
  -- CursorMoved alone cannot prevent those callbacks restoring padding.
  image.notes_changedtick = changedtick
  if not image.notes_original_render then
    image.notes_original_render = image.render
    image.render = function(self, geometry)
      if not vim.api.nvim_buf_is_valid(self.buffer) then
        return
      end
      if self.notes_changedtick ~= vim.api.nvim_buf_get_changedtick(self.buffer) then
        self:clear()
        return
      end
      if geometry then
        self.geometry = vim.tbl_deep_extend("force", self.geometry, geometry)
      end
      local win = self.window
      if win and vim.api.nvim_win_is_valid(win)
        and vim.api.nvim_win_get_buf(win) == self.buffer
        and vim.api.nvim_win_get_cursor(win)[1] == self.geometry.y + 1
      then
        self:clear(true)
        self.notes_hidden_for_cursor = true
        self.global_state.images[self.id] = self
        return
      end
      return self.notes_original_render(self)
    end
  end

  return image
end

local function suspend_markdown_images_while_editing(buf)
  markdown_edit_generation = markdown_edit_generation + 1
  local generation = markdown_edit_generation
  local state = markdown_image_state

  if state and state.enabled then
    state.enabled = false
    -- Remove both the current Sixel frame and its virtual padding immediately.
    -- Keeping the old padding during the debounce makes Enter move the cursor
    -- relative to an image position that no longer exists.
    if vim.api.nvim_buf_is_valid(buf) then
      for _, image in ipairs(require("image").get_images({ buffer = buf, namespace = "markdown" })) do
        pcall(image.clear, image)
      end
    end
    pcall(state.backend.clear)
    pcall(vim.cmd, "redraw!")
  end

  vim.defer_fn(function()
    if generation ~= markdown_edit_generation then
      return
    end

    if state then
      -- Restore images in unaffected buffers, then ask the Markdown
      -- integration to create one fresh image at the edited buffer's final
      -- location.
      require("image").enable()
    end

    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf, modeline = false })
    end
  end, 100)
end

local function install_markdown_image_factory_hook()
  local image_api = require("image")
  if image_api.notes_markdown_factory_hook then
    return
  end

  local original_from_file = image_api.from_file
  image_api.from_file = function(path, options)
    return configure_markdown_image_before_render(original_from_file(path, options), options)
  end
  image_api.notes_markdown_factory_hook = true
end

local function keep_cursor_visible_after_image_restore(image, buf)
  image.notes_restore_generation = (image.notes_restore_generation or 0) + 1
  local generation = image.notes_restore_generation

  local function keep_visible(attempt)
    if image.notes_restore_generation ~= generation then
      return
    end
    local win = image.window
    if not win
      or not vim.api.nvim_win_is_valid(win)
      or not vim.api.nvim_buf_is_valid(buf)
      or vim.api.nvim_win_get_buf(win) ~= buf
    then
      return
    end

    local cursor = vim.api.nvim_win_get_cursor(win)
    if math.abs(cursor[1] - (image.geometry.y + 1)) ~= 1 then
      return
    end

    remove_stale_image_padding(image)

    vim.api.nvim_win_call(win, function()
      local saved_view = image.notes_view_before_hide
      local restored_saved_view = false
      if saved_view then
        local current_view = vim.fn.winsaveview()
        local candidate_view = vim.deepcopy(current_view)
        candidate_view.topline = saved_view.topline
        candidate_view.topfill = saved_view.topfill
        candidate_view.leftcol = saved_view.leftcol
        candidate_view.skipcol = saved_view.skipcol
        vim.fn.winrestview(candidate_view)

        -- Keep the old viewport only when the cursor is genuinely visible
        -- with the final image padding. During asynchronous rendering,
        -- screenpos() can temporarily report 0 even though the settled image
        -- fits; later attempts will retry the same saved viewport.
        if vim.fn.screenpos(win, cursor[1], cursor[2] + 1).row > 0 then
          restored_saved_view = true
        else
          vim.fn.winrestview(current_view)
        end
      end

      -- Keep the image at its configured size. If adding virtual padding put
      -- the adjacent cursor line outside the viewport, reveal it at the
      -- nearest edge instead of shrinking the image or restoring an old
      -- topline that no longer matches the edited buffer.
      local screen_row = vim.fn.screenpos(win, cursor[1], cursor[2] + 1).row
      if not restored_saved_view and screen_row == 0 then
        if cursor[1] > image.geometry.y + 1 then
          vim.cmd("normal! zb")
        else
          vim.cmd("normal! zt")
        end
      elseif not restored_saved_view then
        local win_info = vim.fn.getwininfo(win)[1]
        local window_bottom = win_info and (win_info.winrow + win_info.height - 1) or vim.o.lines
        if cursor[1] > image.geometry.y + 1 and screen_row >= window_bottom then
          -- Leave one visible row below the cursor without changing image
          -- dimensions. This is a one-screen-row scroll through virtual
          -- padding, not a jump to a different buffer line.
          vim.cmd([[execute "normal! 1\<C-e>"]])
        end
      end

      markdown_cursor_history[win] = {
        row = cursor[1] - 1,
        view = vim.fn.winsaveview(),
      }

    end)
    -- Rendering and virtual padding settle asynchronously. Recheck without
    -- restoring a stale saved view or changing the image geometry.
    if attempt < 3 then
      vim.defer_fn(function()
        keep_visible(attempt + 1)
      end, 80)
    else
      image.notes_view_before_hide = nil
    end
  end

  vim.schedule(function()
    keep_visible(1)
  end)
end

local function apply_markdown_image_sizes(buf, refresh_position, movement)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "markdown" then
    return
  end

  local term_size = require("image/utils").term.get_size()
  if not term_size or not term_size.cell_width or not term_size.cell_height then
    return
  end

  local images = require("image").get_images({ buffer = buf, namespace = "markdown" })
  local needs_immediate_terminal_clear = false

  for _, image in ipairs(images) do
    remove_stale_image_padding(image)
    local row = image.geometry.y
    local column = image.geometry.x
    local line_count = vim.api.nvim_buf_line_count(buf)
    if type(row) ~= "number" or row < 0 or row >= line_count then
      pcall(image.clear, image)
      goto continue
    end

    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local width_px, height_px, image_still_exists = image_size_at_column(line, column)
    if not image_still_exists then
      pcall(image.clear, image)
      goto continue
    end

    local width = width_px and math.max(1, math.floor(width_px / term_size.cell_width + 0.5)) or nil
    local height = height_px and math.max(1, math.floor(height_px / term_size.cell_height + 0.5)) or nil
    local cursor_on_image = image.window
      and vim.api.nvim_win_is_valid(image.window)
      and vim.api.nvim_win_get_buf(image.window) == buf
      and vim.api.nvim_win_get_cursor(image.window)[1] - 1 == row
    local cursor_below_image = image.window
      and vim.api.nvim_win_is_valid(image.window)
      and vim.api.nvim_win_get_buf(image.window) == buf
      and vim.api.nvim_win_get_cursor(image.window)[1] - 1 == row + 1
    local geometry_changed = image.notes_width ~= width
      or image.notes_height ~= height
      or image.notes_render_offset_top ~= -1
    local crossed_image = movement
      and movement.previous_row ~= nil
      and ((movement.previous_row < row and movement.current_row > row)
        or (movement.previous_row > row and movement.current_row < row))

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

    if crossed_image then
      image.notes_view_before_hide = movement.previous_view
      image.notes_hidden_for_cursor = false
      local rendered = pcall(image.render, image)
      if not rendered then
        pcall(image.clear, image)
      else
        keep_cursor_visible_after_image_restore(image, buf)
      end
      goto continue
    end

    if cursor_on_image then
      if not image.notes_hidden_for_cursor then
        image.notes_view_before_hide = vim.api.nvim_win_call(image.window, vim.fn.winsaveview)
        -- Hide both the Sixel frame and its virtual padding while the source
        -- is being edited. Keeping invisible padding here makes `j` cross a
        -- large empty region and can scroll all preceding text off-screen.
        -- A shallow clear keeps the image object registered, so leaving the
        -- source line can render it again without reparsing the document.
        image:clear(true)
        repaint_without_hidden_image(image)
        needs_immediate_terminal_clear = true
      end
      image.notes_hidden_for_cursor = true
    elseif refresh_position or geometry_changed or image.notes_hidden_for_cursor or not image.is_rendered
      or cursor_below_image
    then
      local was_hidden_for_cursor = image.notes_hidden_for_cursor
      image.notes_hidden_for_cursor = false
      local rendered = pcall(image.render, image)
      if not rendered then
        pcall(image.clear, image)
      elseif was_hidden_for_cursor or cursor_below_image then
        keep_cursor_visible_after_image_restore(image, buf)
      end
    end

    ::continue::
  end

  if needs_immediate_terminal_clear then
    -- The Sixel backend normally batches this repaint for 50ms. Clear the
    -- terminal frame now so Neovim does not draw the link text over a still
    -- visible image and make it look like two separate images are vanishing.
    pcall(vim.cmd, "redraw!")
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
      install_markdown_image_factory_hook()

      local group = vim.api.nvim_create_augroup("NotesMarkdownImageSize", { clear = true })
      local resize_generation = {}
      local function schedule_resize(buf, delay, refresh_position)
        resize_generation[buf] = (resize_generation[buf] or 0) + 1
        local generation = resize_generation[buf]
        vim.defer_fn(function()
          if resize_generation[buf] ~= generation then
            return
          end
          apply_markdown_image_sizes(buf, refresh_position)
        end, delay or 120)
      end

      vim.api.nvim_create_autocmd({
        "BufEnter",
        "BufWinEnter",
        "BufWritePost",
      }, {
        group = group,
        pattern = "*.md",
        callback = function(args)
          local win = vim.api.nvim_get_current_win()
          if vim.api.nvim_win_get_buf(win) == args.buf then
            markdown_cursor_history[win] = {
              row = vim.api.nvim_win_get_cursor(win)[1] - 1,
              view = vim.api.nvim_win_call(win, vim.fn.winsaveview),
            }
          end
          schedule_resize(args.buf)
        end,
      })

      vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        pattern = "*.md",
        callback = function(args)
          suspend_markdown_images_while_editing(args.buf)
        end,
      })

      vim.api.nvim_create_autocmd({ "WinScrolled", "VimResized" }, {
        group = group,
        callback = function()
          -- Recalculate screen position and viewport cropping after Neovim
          -- has finished scrolling. A rendered image can otherwise retain
          -- the shorter bottom-cropped frame it had before the scroll while
          -- its extmark continues to reserve the full image height.
          schedule_resize(vim.api.nvim_get_current_buf(), 20, true)
        end,
      })

      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        pattern = "*.md",
        callback = function(args)
          local win = vim.api.nvim_get_current_win()
          local current_row = vim.api.nvim_win_get_cursor(win)[1] - 1
          local previous = markdown_cursor_history[win]
          if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
            schedule_resize(args.buf, 30, true)
          else
            -- CursorMoved can run before the resulting viewport scroll is
            -- reflected in screenpos(), so refresh now and once more after
            -- the screen has settled.
            apply_markdown_image_sizes(args.buf, true, {
              previous_row = previous and previous.row or nil,
              previous_view = previous and previous.view or nil,
              current_row = current_row,
            })
            schedule_resize(args.buf, 20, true)
          end
          markdown_cursor_history[win] = {
            row = current_row,
            view = vim.api.nvim_win_call(win, vim.fn.winsaveview),
          }
        end,
      })

      vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        callback = function(args)
          resize_generation[args.buf] = nil
          for win, _ in pairs(markdown_cursor_history) do
            if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) == args.buf then
              markdown_cursor_history[win] = nil
            end
          end
        end,
      })
    end,
  },
}
