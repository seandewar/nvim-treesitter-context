
local vim = vim
local api = vim.api
local ts_utils = require'nvim-treesitter.ts_utils'
local parsers = require'nvim-treesitter.parsers'

-- Script variables

local winid = nil
local bufnr = api.nvim_create_buf(false, true)
local label = nil


-- Helper functions

local get_line_for_node = function(node, type_patterns, transform_fn)
  local node_type = node:type()
  local is_valid = false
  for _, rgx in ipairs(type_patterns) do
    if node_type:find(rgx) then
      is_valid = true
      break
    end
  end

  if not is_valid then return '' end

  -- local node_text = transform_fn(ts_utils.get_node_text(node)[1] or '')
  local line = api.nvim_buf_get_lines(0, node:start(), node:start() + 1, false)[1]

  return line
end

-- Trim spaces and opening brackets from end
local transform_line = function(line)
  return line:gsub('%s*[%[%(%{]*%s*$', ''):gsub('\n', '')
end

local get_context = function(opts)
  if not parsers.has_parser() then return nil end
  local options = opts or {}
  local type_patterns = options.type_patterns or {'class', 'function', 'method'}
  local transform_fn = options.transform_fn or transform_line
  local separator = options.separator or ' -> '

  local current_node = ts_utils.get_node_at_cursor()
  if not current_node then return nil end

  local matches = {}
  local expr = current_node

  while expr do
    local line = get_line_for_node(expr, type_patterns, transform_fn)
    if line ~= '' and not vim.tbl_contains(matches, line) then
      table.insert(matches, 1, { expr:start(), line })
    end
    expr = expr:parent()
  end

  if #matches == 0 then
    return nil
  end

  return matches
end

local get_gutter_width = function()
  local old_col = api.nvim_call_function('col', { '.' })
  api.nvim_call_function('cursor', { 0, 1 })
  local gutter_width = api.nvim_call_function('wincol', {}) - 1
  api.nvim_call_function('cursor', { 0, old_col })
  return gutter_width
end

local nvim_augroup = function(group_name, definitions)
  api.nvim_command('augroup ' .. group_name)
  api.nvim_command('autocmd!')
  for _, def in ipairs(definitions) do
    local command = table.concat(vim.tbl_flatten{'autocmd', def}, ' ')
    api.nvim_command(command)
  end
  api.nvim_command('augroup END')
end


-- Exports

local M = {}

function M.update_context()
  if api.nvim_get_option('buftype') ~= '' then
    M.close()
    return
  end

  local context = get_context()

  label = nil

  if context then
    local first_visible_line = api.nvim_call_function('line', { 'w0' })

    for i = #context, 1, -1 do
      local match = context[i]
      local line_number, text = unpack(match)

      if line_number < (first_visible_line - 1) then
        label = text
        break
      end
    end
  end

  if label then
    M.open()
  else
    M.close()
  end

  return { winid, get_gutter_width(), context }
end

function M.close()
  if winid ~= nil and api.nvim_win_is_valid(winid) then
    -- Can't close other windows when the command-line window is open
    if api.nvim_call_function('getcmdwintype', {}) ~= '' then
      return
    end

    api.nvim_win_close(winid, true)
  end
  winid = nil
end

function M.open()
  local gutter_width = get_gutter_width()
  local win_width = api.nvim_win_get_width(0) - gutter_width

  if winid == nil or not api.nvim_win_is_valid(winid) then
    winid = api.nvim_open_win(bufnr, false, {
      relative = 'win',
      width = win_width,
      height = 1,
      row = 0,
      col = gutter_width,
      focusable = false,
      style = 'minimal',
    })
  else
    api.nvim_win_set_config(winid, {
      relative = 'win',
      width = win_width,
      row = 0,
      col = gutter_width,
    })
  end

  api.nvim_buf_set_lines(bufnr, 0, -1, false, { label })
end

function M.enable()
  local option_triggers = 'buftype,foldcolumn,number,numberwidth,relativenumber,signcolumn'

  nvim_augroup('treesitter_context', {
    {'OptionSet',   option_triggers,   'silent lua require("treesitter-context").update_context()'},
    {'VimResized',  '*',               'silent lua require("treesitter-context").update_context()'},
    {'CursorMoved', '*',               'silent lua require("treesitter-context").update_context()'},
    {'User',        'SessionSavePre',  'silent lua require("treesitter-context").close()'},
    {'User',        'SessionSavePost', 'silent lua require("treesitter-context").update_context()'},
  })

  M.update_context()
end

function M.disable()
  nvim_augroup('treesitter_context', {})

  M.close()
end

-- Setup

M.enable()

api.nvim_command('command! TSContextEnable  lua require("treesitter-context").enable()')
api.nvim_command('command! TSContextDisable lua require("treesitter-context").disable()')


return M
