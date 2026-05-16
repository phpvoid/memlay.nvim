local M = {}

function M.check()
  vim.health.start("memlay")

  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.error("Neovim 0.9+ required")
  end

  if jit then
    vim.health.ok("LuaJIT " .. jit.version)
  else
    vim.health.error("LuaJIT required for FFI",
      { "Install standard Neovim build from neovim.io" })
  end

  local memlay = require("memlay")
  local _, libclang_path = memlay.find_libclang()
  if libclang_path then
    vim.health.ok("libclang: " .. libclang_path)
  else
    vim.health.error("libclang not found", {
      "Ubuntu/Debian : sudo apt install libclang-dev",
      "Arch          : sudo pacman -S clang",
      "Fedora        : sudo dnf install clang-devel",
      "Mac           : brew install llvm",
      "Custom        : export LLVM_PATH=/path/to/llvm",
    })
  end

  local root = memlay.get_plugin_root()
  local uname = vim.loop.os_uname()
  local platform
  if uname.sysname:lower() == "darwin" then
    platform = uname.machine == "arm64" and "darwin-arm64" or "darwin-x86_64"
  else
    platform = uname.machine == "aarch64" and "linux-aarch64" or "linux-x86_64"
  end

  local prebuilt = root .. "/prebuilt/" .. platform .. "/libmemlay.so"
  local built = root .. "/lua/memlay/libmemlay.so"

  if vim.loop.fs_stat(prebuilt) then
    vim.health.ok("libmemlay.so (prebuilt): " .. prebuilt)
  elseif vim.loop.fs_stat(built) then
    vim.health.ok("libmemlay.so (local build): " .. built)
  else
    vim.health.error("libmemlay.so not found", {
      "Run :MemlayBuild",
      "Or: make -C " .. root .. "/c/",
      "Requires: clang, make, libclang-dev",
    })
  end

  for _, bin in ipairs({ "clang", "make" }) do
    if vim.fn.executable(bin) == 1 then
      vim.health.ok(bin .. ": " .. vim.fn.exepath(bin))
    else
      vim.health.warn(bin .. " not found — only needed to build from source")
    end
  end
end

return M
