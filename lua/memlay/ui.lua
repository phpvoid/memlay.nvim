local ffi = require("ffi")
local M = {}
local SEP = "|"
local CHARS_PER_BYTE = 4

local function setup_highlights()
  vim.api.nvim_set_hl(0, "MemlayField",  { fg = "#000000", bg = "#5fafd7", default = false })
  vim.api.nvim_set_hl(0, "MemlayPad",    { fg = "#000000", bg = "#4e4e4e", default = false })
  vim.api.nvim_set_hl(0, "MemlayHeader", { link = "Title",      default = false })
  vim.api.nvim_set_hl(0, "MemlayType",   { link = "Type",       default = false })
  vim.api.nvim_set_hl(0, "MemlayOffset", { link = "Number",     default = false })
  vim.api.nvim_set_hl(0, "MemlayLegend", { link = "NonText",    default = false })
  vim.api.nvim_set_hl(0, "MemlayWarn",   { link = "WarningMsg", default = false })
end
setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = setup_highlights })

local function ascii_trunc(s, maxlen)
  if maxlen <= 0 then return "" end
  if #s <= maxlen then return s end
  if maxlen <= 1 then return s:sub(1, maxlen) end
  return s:sub(1, maxlen - 1) .. ">"
end

local function make_annot(size, padding, maxlen)
  if padding > 0 then
    for _, f in ipairs({ size .. "B +" .. padding .. "P", size .. "B+" .. padding .. "P", "+" .. padding .. "P" }) do
      if #f <= maxlen then return f end
    end
    return ascii_trunc(size .. "B +" .. padding .. "P", maxlen)
  end
  return size .. "B"
end

local TYPE_ALIASES = {
  ["_Bool"] = "bool", ["unsigned char"] = "u8", ["unsigned short"] = "u16",
  ["unsigned int"] = "u32", ["unsigned long"] = "u64",
  ["uint8_t"] = "u8", ["uint16_t"] = "u16", ["uint32_t"] = "u32", ["uint64_t"] = "u64",
  ["int8_t"] = "i8", ["int16_t"] = "i16", ["int32_t"] = "i32", ["int64_t"] = "i64",
}

local function display_type(tname)
  local ptr_struct = tname:match("^struct (%w+) %*$")
  if ptr_struct then return ptr_struct .. "*" end
  local bare_struct = tname:match("^struct (%w+)$")
  if bare_struct then return bare_struct end
  local const_ptr = tname:match("^const (%w+) %*$")
  if const_ptr then return const_ptr .. "*" end
  return TYPE_ALIASES[tname] or tname
end

local function fit_label(tname, name, maxlen)
  local full = tname .. " " .. name
  if #full <= maxlen then return full end
  local type_space = maxlen - (#name + 2)
  if type_space >= 2 then
    return ascii_trunc(tname, type_space) .. " " .. name
  end
  return ascii_trunc(name, maxlen)
end

local function plan_columns(result)
  local fc = tonumber(result.field_count)
  assert(fc and fc > 0, "field_count invalid")
  local total_size = tonumber(result.total_size)
  if total_size == 0 or fc == 0 then return {} end
  local max_width = math.min(vim.o.columns - 10, 76)
  local available = max_width - 3 - (fc - 1) - 1
  local col_widths = {}
  local natural_total = 0
  for i = 0, fc - 1 do
    local f = result.fields[i]
    local w = math.max(6, math.floor((tonumber(f.size) + tonumber(f.padding)) * CHARS_PER_BYTE))
    col_widths[i] = w
    natural_total = natural_total + w
  end
  if natural_total > available then
    local scale = available / natural_total
    natural_total = 0
    for i = 0, fc - 1 do
      col_widths[i] = math.max(6, math.floor(col_widths[i] * scale))
      natural_total = natural_total + col_widths[i]
    end
  end
  return col_widths
end

local function needs_vertical(result)
  return tonumber(result.field_count) > 5
end

local function build_memory_map(result, col_widths, field_start, field_end)
  local total_size = tonumber(result.total_size)
  local fc = tonumber(result.field_count)
  assert(fc and fc > 0, "field_count invalid")
  if total_size == 0 or fc == 0 then return {}, {} end
  field_start = field_start or 0
  field_end = field_end or (fc - 1)
  local ruler_parts, bar_parts, label_parts, annot_parts, bar_highlights, field_starts = {}, {}, {}, {}, {}, {}
  local bar_col, byte_offset, label_col_check = 0, 0, 0

  for i = field_start, field_end do
    local f       = result.fields[i]
    local size    = tonumber(f.size)
    local padding = tonumber(f.padding)
    local name    = ffi.string(f.name)
    local tname   = display_type(ffi.string(f.type_name))
    local col_w   = col_widths[i]
    local is_last = (i == field_end)
    local total_w = col_w + (is_last and 0 or 1)

    -- ruler
    local offset_str = "+" .. tostring(byte_offset)
    table.insert(ruler_parts, offset_str .. string.rep(" ", math.max(0, total_w - #offset_str)))
    byte_offset = byte_offset + size + padding

    -- bar split within this column
    local total_bytes = size + padding
    local field_chars, pad_chars
    if padding == 0 then field_chars, pad_chars = col_w, 0
    elseif size == 0 then field_chars, pad_chars = 0, col_w
    else
      field_chars = math.max(1, math.floor(col_w * size / total_bytes + 0.5))
      pad_chars = col_w - field_chars
    end
    field_starts[i] = { col = bar_col, field_chars = field_chars, pad_chars = pad_chars, size = size, padding = padding }
    table.insert(bar_parts, string.rep(" ", field_chars))
    table.insert(bar_parts, string.rep(" ", pad_chars))

    local hl_base = bar_col + 3
    table.insert(bar_highlights, { hl_base, hl_base + field_chars, "MemlayField" })
    if pad_chars > 0 then
      table.insert(bar_highlights, { hl_base + field_chars, hl_base + field_chars + pad_chars, "MemlayPad" })
    end
    bar_col = bar_col + col_w
    if not is_last then table.insert(bar_parts, SEP); bar_col = bar_col + 1 end

    -- label (fit within col_w, assert width correctness)
    local label = fit_label(tname, name, col_w)
    local padded_label = string.format("%-" .. col_w .. "s", label)
    assert(#padded_label == col_w, string.format("field %d label width %d != col_w %d: '%s'", i, #padded_label, col_w, padded_label))
    table.insert(label_parts, padded_label)

    -- annotation
    local annot = make_annot(size, padding, col_w)
    local padded_annot = string.format("%-" .. col_w .. "s", annot)
    assert(#padded_annot == col_w, string.format("field %d annot width %d != col_w %d: '%s'", i, #padded_annot, col_w, padded_annot))
    table.insert(annot_parts, padded_annot)

    if not is_last then table.insert(label_parts, " "); table.insert(annot_parts, " ") end
    label_col_check = label_col_check + total_w
  end

  -- verify label total width matches bar inner width
  local bar_inner_width = 0
  for i = field_start, field_end do
    bar_inner_width = bar_inner_width + col_widths[i]
    if i < field_end then bar_inner_width = bar_inner_width + 1 end
  end
  assert(label_col_check == bar_inner_width, string.format("total label width %d != bar inner width %d", label_col_check, bar_inner_width))
  table.insert(ruler_parts, "+" .. tostring(total_size))

  -- overlay centered byte counts inside bar blocks
  local bar_string = table.concat(bar_parts)
  local bar_bytes = {}
  for ci = 1, #bar_string do bar_bytes[ci] = bar_string:sub(ci, ci) end
  for i = field_start, field_end do
    local e = field_starts[i]
    if e.field_chars >= 2 then
      local s = tostring(e.size)
      local ss = math.max(e.col, e.col + math.floor((e.field_chars - #s) / 2))
      for ci = 1, math.min(#s, e.field_chars) do bar_bytes[ss + ci] = s:sub(ci, ci) end
    end
    if e.pad_chars >= 2 and e.padding > 0 then
      local p = tostring(e.padding)
      local pc = e.col + e.field_chars
      local ps = math.max(pc, pc + math.floor((e.pad_chars - #p) / 2))
      for ci = 1, math.min(#p, e.pad_chars) do bar_bytes[ps + ci] = p:sub(ci, ci) end
    end
  end

  local bar_content = table.concat(bar_parts)
  local label_str = table.concat(label_parts)
  local annot_str = table.concat(annot_parts)
  assert(#label_str == #bar_content, string.format("label %d != bar %d", #label_str, #bar_content))
  assert(#annot_str == #bar_content, string.format("annot %d != bar %d", #annot_str, #bar_content))

  local bar_row = table.concat(bar_bytes)
  local indent3 = "   "
  return { indent3 .. table.concat(ruler_parts), "  [" .. bar_row .. "]",
           indent3 .. table.concat(label_parts), indent3 .. table.concat(annot_parts) }, bar_highlights
end

local function build_vertical(result)
  local fc = tonumber(result.field_count)
  local total_size = tonumber(result.total_size)
  local lines, highlights = {}, {}
  local BAR_W, OFFSET_W = 24, 7

  -- find largest field as scale anchor
  local max_bytes = 1
  for i = 0, fc - 1 do
    local bytes = tonumber(result.fields[i].size) + tonumber(result.fields[i].padding)
    if bytes > max_bytes then max_bytes = bytes end
  end
  local scale = BAR_W / max_bytes

  -- measure tightest label column width
  local max_label_len = 0
  for i = 0, fc - 1 do
    local f = result.fields[i]
    local label = fit_label(display_type(ffi.string(f.type_name)), ffi.string(f.name), 20)
    if #label > max_label_len then max_label_len = #label end
  end
  local LABEL_W = max_label_len + 2
  local bar_start = 2 + OFFSET_W + LABEL_W + 1

  for i = 0, fc - 1 do
    local f       = result.fields[i]
    local size    = tonumber(f.size)
    local padding = tonumber(f.padding)
    local offset  = tonumber(f.offset)
    local name    = ffi.string(f.name)
    local tname   = display_type(ffi.string(f.type_name))

    local field_chars = math.max(1, math.ceil(size * scale))
    local pad_chars   = math.max(0, math.ceil(padding * scale))
    if field_chars + pad_chars > BAR_W then
      pad_chars = math.max(0, BAR_W - field_chars)
      field_chars = math.min(field_chars, BAR_W)
    end

    -- build bar byte array with centered number overlay
    local bar_bytes = {}
    for ci = 1, field_chars + pad_chars do bar_bytes[ci] = " " end
    if field_chars >= 2 then
      local s = tostring(size)
      local ss = math.max(1, math.floor((field_chars - #s) / 2) + 1)
      for ci = 1, math.min(#s, field_chars) do bar_bytes[ss + ci - 1] = s:sub(ci, ci) end
    end
    if pad_chars >= 3 and padding > 0 then
      local p = tostring(padding)
      local ps = field_chars + math.max(1, math.floor((pad_chars - #p) / 2) + 1)
      for ci = 1, math.min(#p, pad_chars) do bar_bytes[ps + ci - 1] = p:sub(ci, ci) end
    end

    local bar_content = table.concat(bar_bytes)
    local offset_str = string.format("%-" .. OFFSET_W .. "s", "+" .. tostring(offset))
    local label = string.format("%-" .. LABEL_W .. "s", fit_label(tname, name, LABEL_W))
    local annot = make_annot(size, padding, 10)
    local line = "  " .. offset_str .. label .. "[" .. bar_content .. "] " .. annot
    table.insert(lines, line)

    -- verify bar_start points to first bar character, not bracket
    local line_idx = #lines - 1
    assert(line:sub(bar_start + 1, bar_start + 1) ~= "[" and line:sub(bar_start + 1, bar_start + 1) ~= "]",
      string.format("bar_start=%d wrong: char='%s' line='%s'", bar_start, line:sub(bar_start + 1, bar_start + 1), line))

    table.insert(highlights, { line_idx, bar_start, bar_start + field_chars, "MemlayField" })
    if pad_chars > 0 then
      table.insert(highlights, { line_idx, bar_start + field_chars, bar_start + field_chars + pad_chars, "MemlayPad" })
    end
  end
  return lines, highlights
end

local function build_lines(result)
  local NS = vim.api.nvim_create_namespace("memlay")
  local lines, highlights = {}, {}
  local function hl(li, cs, ce, g) table.insert(highlights, { li, cs, ce, g }) end

  local total  = tonumber(result.total_size)
  local packed = tonumber(result.packed_size)
  local sname  = ffi.string(result.struct_name)
  if #sname == 0 then sname = "(anonymous)" end
  table.insert(lines, string.format("  STRUCT: %s   %dB total · %dB minimum", sname, total, packed))

  local col_widths = plan_columns(result)
  local fc = tonumber(result.field_count)
  local bar_width = 0
  for i = 0, fc - 1 do bar_width = bar_width + col_widths[i] end
  bar_width = bar_width + (fc - 1) + 4

  local sep = string.rep("-", math.max(bar_width, #lines[1] + 2))
  if needs_vertical(result) then
    local LABEL_W = 0
    for i = 0, fc - 1 do
      local f = result.fields[i]
      local label = fit_label(display_type(ffi.string(f.type_name)), ffi.string(f.name), 20)
      if #label > LABEL_W then LABEL_W = #label end
    end
    LABEL_W = LABEL_W + 2
    local window_w = 2 + 7 + LABEL_W + 1 + 24 + 2 + 10 + 4
    window_w = math.min(window_w, vim.o.columns - 6)
    sep = string.rep("-", window_w)
  end
  table.insert(lines, sep)

  if needs_vertical(result) then
    local vlines, vhl = build_vertical(result)
    local base = #lines
    for _, vl in ipairs(vlines) do table.insert(lines, vl) end
    for _, h in ipairs(vhl) do hl(base + h[1], h[2], h[3], h[4]) end
  else
    local map_rows, bar_hls = build_memory_map(result, col_widths)
    local base = #lines
    for ri, row in ipairs(map_rows) do
      table.insert(lines, row)
      if ri == 2 then
        for _, h in ipairs(bar_hls) do hl(base + 1, h[1], h[2], h[3]) end
      end
    end
  end

  table.insert(lines, sep)
  local legend = "     = used    = wasted   (P = pad bytes)"
  table.insert(lines, legend)
  local li = #lines - 1
  hl(li, 2, 4, "MemlayField")
  hl(li, 12, 14, "MemlayPad")

  local suggestion = ffi.string(result.suggestion)
  if suggestion ~= "" then
    table.insert(lines, sep)
    if suggestion:sub(1, 7) == "OPTIMAL" then
      table.insert(lines, "  ** layout is already optimal — no reordering helps")
    else
      local sugg_line = "  !! " .. suggestion
      if #sugg_line > #sep - 2 then sugg_line = sugg_line:sub(1, #sep - 5) .. "..." end
      table.insert(lines, sugg_line)
    end
  end
  return lines, highlights, NS
end

local function open_above_struct(result, buf, width, height)
  local cursor_line   = vim.api.nvim_win_get_cursor(0)[1]
  local screen_line   = vim.fn.winline()
  local struct_start  = result.struct_start_line
  local struct_end    = result.struct_end_line
  local struct_top    = screen_line - (cursor_line - struct_start)
  local win_h         = vim.api.nvim_win_get_height(0)
  local struct_h      = struct_end - struct_start + 1
  local rows_above    = struct_top - 1
  local rows_below    = win_h - (struct_top + struct_h - 1)
  if struct_top <= 0 then struct_top = 1; rows_above = 0 end

  local row, anchor
  if rows_above >= height + 1 then
    row, anchor = struct_top - 2, "SW"
  elseif rows_below >= height + 1 then
    row, anchor = struct_top + struct_h - 1, "NW"
  else
    if rows_above >= rows_below then
      row, anchor = math.max(0, struct_top - 2), "SW"
      height = math.min(height, rows_above)
    else
      row, anchor = struct_top + struct_h - 1, "NW"
      height = math.min(height, rows_below)
    end
  end

  local win_width = vim.api.nvim_win_get_width(0)
  if width > win_width then width = win_width end
  return vim.api.nvim_open_win(buf, false, {
    relative = "win", row = row, col = 0, width = width, height = height,
    anchor = anchor, border = "rounded", focusable = true, style = "minimal", zindex = 50,
  })
end

function M.show(result)
  local width
  if needs_vertical(result) then
    local fc = tonumber(result.field_count)
    local max_bytes = 1
    for i = 0, fc - 1 do
      local bytes = tonumber(result.fields[i].size) + tonumber(result.fields[i].padding)
      if bytes > max_bytes then max_bytes = bytes end
    end
    local scale = 24 / max_bytes
    local max_label_len = 0
    for i = 0, fc - 1 do
      local f = result.fields[i]
      local label = fit_label(display_type(ffi.string(f.type_name)), ffi.string(f.name), 20)
      if #label > max_label_len then max_label_len = #label end
    end
    local LABEL_W = max_label_len + 2
    local max_bar = 0
    for i = 0, fc - 1 do
      local f = result.fields[i]
      local fc_chars = math.max(1, math.floor(tonumber(f.size) * scale + 0.5))
      local pc_chars = math.max(0, math.floor(tonumber(f.padding) * scale + 0.5))
      if fc_chars + pc_chars > max_bar then max_bar = fc_chars + pc_chars end
    end
    width = 2 + 7 + LABEL_W + 1 + max_bar + 2 + 10 + 4
    width = math.min(width, vim.o.columns - 4)
  end

  setup_highlights()
  local lines, highlights, NS = build_lines(result)

  if not needs_vertical(result) then
    width = 0
    for _, l in ipairs(lines) do if #l > width then width = #l end end
    width = math.min(width + 4, vim.o.columns - 4)
  end

  local height = math.min(#lines, vim.api.nvim_win_get_height(0) - 2)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, NS, h[4], h[1], h[2], h[3])
  end

  local win = open_above_struct(result, buf, width, height)
  if #lines > height then
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "  -- more: j/k" })
    local hint_idx = vim.api.nvim_buf_line_count(buf) - 1
    vim.api.nvim_buf_add_highlight(buf, NS, "MemlayLegend", hint_idx, 0, -1)
  end

  local function close() pcall(vim.api.nvim_win_close, win, true) end
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave" }, {
    buffer = vim.api.nvim_get_current_buf(), once = true, callback = close,
  })
end

return M
