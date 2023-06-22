local api = vim.api
local Menu = require('nui.menu')
local event = require("nui.utils.autocmd").event
local get_connection_files = require('./get_connection_files')
local create_result_buffer = require('./create_result_buffer')
local psql_command = require('./psql_command')
local psql_tunnel = require('./psql_tunnel')
local path = require('plenary.path')

local state = {
  split = nil,
}

local function get_split()
  return state.split
end

local function set_split(winid)
  state.split = winid
end

local function on_split_close()
  set_split(nil)
end

local local_state_dir = path.new(os.getenv('HOME'), '.local', 'state', 'pg.nvim').filename
local settings = {
  state_dir = local_state_dir,
  gpg_exe = '/usr/local/bin/gpg',
}

local connection_map = {}

local popup_options = {
  relative = "win",
  position = '50%',
  size = {
    width =' 25%',
    height = '25%',
  },
  border = {
    style = 'rounded',
    text = {
      top = "Select Connection",
      top_align = "center",
    },
  },
  win_options = {
    winhighlight = "Normal:Normal,FloatBorder:SpecialChar",
  }
}

local function connect_buffer()
  local current_buffer = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  local conn_files = get_connection_files(settings.state_dir, settings)

  local menu_lines = {}
  for f in pairs(conn_files) do
    local file = conn_files[f]
    table.insert(menu_lines, Menu.item(file.name, file))
  end

  local menu = Menu(popup_options, {
    lines = menu_lines,
    max_width = 20,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>" },
      submit = { "<CR>", "<Space>" },
    },
    on_submit = function(item)
      local result_split, buffer
      result_split = get_split()
      -- If we haven't created the split, create it
      -- otherwise just create a new buffer, and pop it
      -- in the split's window

      if connection_map[current_buffer] then
        return
      end

      buffer = vim.api.nvim_create_buf(false, true)
      if result_split == nil then
        result_split = create_result_buffer(current_win, on_split_close)
        set_split(result_split)
      end
      vim.api.nvim_win_set_buf(result_split, buffer)

      local tunnel

      if item.tunnel then
        tunnel = psql_tunnel(item)
      end

      connection_map[current_buffer] = {
        connection = item,
        buffer = buffer,
        tunnel = tunnel,
      }
    end,
  })

  menu:mount()
  menu:on(event.BufLeave, menu.menu_props.on_close, { once = true })
end

local function print_connection_map()
  print('Connection Map', vim.inspect(connection_map))
end

local function run_query(query)
  local current_buffer = vim.api.nvim_get_current_buf()
  local connection_data = connection_map[current_buffer]
  local output = psql_command(connection_data.connection, query)
  vim.api.nvim_buf_set_lines(connection_data.buffer, 0, -1, false, output)
  vim.api.nvim_set_current_win(state.split)
end

local function enter_buffer()
  local current_buffer = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  local connection = connection_map[current_buffer]
  if connection then
    local rs = get_split()
    if rs == nil then
      rs = create_result_buffer(current_win, on_split_close)
      set_split(rs)
      print('created a new split')
    end
    vim.api.nvim_win_set_buf(rs, connection.buffer)
  end
end

return {
  ConnectBuffer = connect_buffer,
  PrintConnMap = print_connection_map,
  RunQuery = run_query,
  EnterBuffer = enter_buffer,
  OnSplitClose = on_split_close,
}
