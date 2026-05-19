local ffi = require("ffi")

ffi.cdef[[
  typedef struct {
    char name[128];
    char type_name[64];
    size_t size;
    size_t align;
    size_t offset;
    size_t padding;
  } FieldInfo;

  typedef struct {
    FieldInfo fields[64];
    int field_count;
    size_t total_size;
    size_t packed_size;
    char suggestion[1024];
    char struct_name[128];
    int struct_start_line;
    int struct_end_line;
  } LayoutResult;

  LayoutResult analyze_struct(const char *filepath, int line, int col);
]]

local function find_libclang()
  local llvm = os.getenv("LLVM_PATH")
  local candidates = {
    "libclang.so", "libclang.so.1",
    "libclang-14.so", "libclang-15.so", "libclang-16.so",
    "libclang-17.so", "libclang-18.so", "libclang-19.so",
    "libclang-20.so", "libclang-21.so", "libclang-22.so",
    "/usr/lib/llvm-14/lib/libclang.so",
    "/usr/lib/llvm-15/lib/libclang.so",
    "/usr/lib/llvm-16/lib/libclang.so",
    "/usr/lib/llvm-17/lib/libclang.so",
    "/usr/lib/llvm-18/lib/libclang.so",
    "/usr/lib/llvm-19/lib/libclang.so",
    "/usr/lib/llvm-20/lib/libclang.so",
    "/usr/lib/llvm-21/lib/libclang.so",
    "/usr/lib/llvm-22/lib/libclang.so",
    "/usr/lib/x86_64-linux-gnu/libclang.so",
    "/usr/lib/aarch64-linux-gnu/libclang.so",
    "/usr/local/opt/llvm/lib/libclang.dylib",
    "/opt/homebrew/opt/llvm/lib/libclang.dylib",
    "/Library/Developer/CommandLineTools/usr/lib/libclang.dylib",
  }
  if llvm then
    table.insert(candidates, 1, llvm .. "/lib/libclang.dylib")
    table.insert(candidates, 1, llvm .. "/lib/libclang.so")
  end
  for _, path in ipairs(candidates) do
    if path then
      local ok, lib = pcall(ffi.load, path)
      if ok then return lib, path end
    end
  end
  return nil, nil
end

local function get_plugin_root()
  local src = debug.getinfo(1).source:match("@(.*)")
  return src:match("(.*)/lua/memlay/init%.lua$")
end

local function get_prebuilt_path()
  local uname = vim.loop.os_uname()
  local sysname = uname.sysname:lower()
  local machine = uname.machine:lower()
  local platform
  if     sysname == "linux"  and machine == "x86_64"  then platform = "linux-x86_64"
  elseif sysname == "linux"  and machine == "aarch64" then platform = "linux-aarch64"
  elseif sysname == "darwin" and machine == "arm64"   then platform = "darwin-arm64"
  elseif sysname == "darwin"                          then platform = "darwin-x86_64"
  else return nil end
  return get_plugin_root() .. "/prebuilt/" .. platform .. "/libmemlay.so"
end

local function load_memlay_lib()
  local candidates = {
    get_prebuilt_path(),
    get_plugin_root() .. "/lua/memlay/libmemlay.so",
  }
  for _, path in ipairs(candidates) do
    if path and vim.loop.fs_stat(path) then
      local ok, lib = pcall(ffi.load, path)
      if ok then return lib, path end
    end
  end
  return nil, nil
end

local lib, _ = find_libclang()
if not lib then
  vim.notify(table.concat({
    "[memlay] libclang not found. Install it:",
    "  Ubuntu/Debian : sudo apt install libclang-dev",
    "  Arch          : sudo pacman -S clang",
    "  Fedora        : sudo dnf install clang-devel",
    "  Mac           : brew install llvm",
    "  Custom path   : export LLVM_PATH=/path/to/llvm",
  }, "\n"), vim.log.levels.ERROR)
  return {}
end

local memlay_lib, _ = load_memlay_lib()
if not memlay_lib then
  vim.notify(
    "[memlay] libmemlay.so not found.\n" ..
    "Run :MemlayBuild  or  make -C " .. get_plugin_root() .. "/c/",
    vim.log.levels.ERROR)
  return {}
end

local M = {}

function M.analyze()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("[memlay] buffer has no file", vim.log.levels.WARN)
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col  = cursor[2] + 1
  local result = memlay_lib.analyze_struct(path, line, col)
  if result.field_count == 0 then
    vim.notify("[memlay] no struct found at cursor", vim.log.levels.INFO)
    return
  end
  require("memlay.ui").show(result)
end

function M.setup(opts)
  opts = opts or {}

  vim.keymap.set("n", opts.keymap or "<leader>ml", M.analyze,
    { desc = "memlay: show struct layout" })

  vim.api.nvim_create_user_command("MemlayBuild", function()
    local root = get_plugin_root()
    vim.notify("[memlay] building...", vim.log.levels.INFO)
    vim.fn.jobstart("make -C " .. root .. "/c/", {
      on_stderr = function(_, data)
        if data then vim.notify(table.concat(data, "\n"), vim.log.levels.WARN) end
      end,
      on_exit = function(_, code)
        if code == 0 then
          vim.notify("[memlay] build succeeded — run :MemlayReload", vim.log.levels.INFO)
        else
          vim.notify("[memlay] build failed", vim.log.levels.ERROR)
        end
      end,
    })
  end, { desc = "memlay: build libmemlay.so from source" })

  vim.api.nvim_create_user_command("MemlayDebug", function()
    local path = vim.api.nvim_buf_get_name(0)
    if path == "" then
      print("[memlay] buffer has no file")
      return
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local result = memlay_lib.analyze_struct(path, cursor[1], cursor[2] + 1)
    if result.field_count == 0 then
      print("[memlay] no struct found at cursor")
      return
    end
    local total = tonumber(result.total_size)
    local fc = tonumber(result.field_count)
    print(string.format("total_size=%d  packed_size=%d  field_count=%d",
      total, tonumber(result.packed_size), fc))
    for i = 0, fc - 1 do
      local f = result.fields[i]
      local size    = tonumber(f.size)
      local padding = tonumber(f.padding)
      local bytes   = size + padding
      print(string.format(
        "  [%d] %s %s: size=%d pad=%d bytes=%d off=%d",
        i,
        ffi.string(f.type_name, 64):match("^[^%z]*"),
        ffi.string(f.name, 128):match("^[^%z]*"),
        size, padding, bytes,
        tonumber(f.offset)))
    end
  end, { desc = "memlay: print raw layout values for debugging" })

  vim.api.nvim_create_user_command("MemlayReload", function()
    package.loaded["memlay"]    = nil
    package.loaded["memlay.ui"] = nil
    require("memlay").setup(opts)
    vim.notify("[memlay] reloaded", vim.log.levels.INFO)
  end, { desc = "memlay: reload after build" })
end

M.find_libclang   = find_libclang
M.get_plugin_root = get_plugin_root

return M
