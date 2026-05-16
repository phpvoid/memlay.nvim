# memlay.nvim

Visualizes C struct memory layout in a Neovim floating window.

Hit `<leader>ml` with your cursor inside any struct. Shows which bytes
are data, which are padding, and how to reorder fields to eliminate waste.

---

## The Classic Problem

```c
struct Foo {
    char x;    // 1B
    int  n;    // 4B
    char flag; // 1B
};
```

This is 12 bytes, not 6. The compiler inserts 3 bytes of padding after
`x` and 3 bytes after `flag` to satisfy alignment requirements. memlay
makes this visible and tells you the optimal field order.

---

## Features

- ABI-accurate layout via libclang
- Proportional memory map with byte counts
- Padding waste highlighted per field
- Reorder suggestion with bytes saved
- Vertical mode for large structs
- Handles pointers, arrays, typedefs, uint*_t, bool

---

## Install

**lazy.nvim**

```lua
{
  "phpvoid/memlay.nvim",
  build = "make -C c/",
  ft    = { "c", "cpp" },
  config = function()
    require("memlay").setup()
  end,
}
```

**packer**

```lua
use {
  "phpvoid/memlay.nvim",
  run    = "make -C c/",
  config = function() require("memlay").setup() end,
}
```

---

## Requirements

- Neovim >= 0.9 with LuaJIT
- libclang >= 14

```bash
# Ubuntu/Debian
sudo apt install libclang-dev

# Arch
sudo pacman -S clang

# Fedora
sudo dnf install clang-devel

# macOS
brew install llvm
```

If libclang is in a non-standard location:
```bash
export LLVM_PATH=/path/to/llvm
```

---

## Usage

| Key | Action |
|-----|--------|
| `<leader>ml` | Show layout |
| `q` / `<Esc>` | Close |
| `j` / `k` | Scroll (large structs) |

Cursor can be anywhere inside the struct definition.

---

## Commands

| Command | Description |
|---------|-------------|
| `:MemlayBuild` | Compile libmemlay.so from source |
| `:MemlayReload` | Reload after build |
| `:MemlayDebug` | Print raw layout values at cursor |

Run `:checkhealth memlay` to diagnose setup issues.

---

## Configuration

```lua
require("memlay").setup({
  keymap = "ml",  -- false to disable
})
```

Highlight groups:
```lua
vim.api.nvim_set_hl(0, "MemlayField", { bg = "#5fafd7", fg = "#000000" })
vim.api.nvim_set_hl(0, "MemlayPad",   { bg = "#4e4e4e", fg = "#000000" })
```

---

## How it works

Two components:

- `c/parse.c` — libclang walks the AST to find the struct at the cursor
  position and extracts field types, sizes, and alignments
- `c/layout.c` — applies the four standard ABI alignment rules to compute
  offsets and padding; no libclang dependency, tested standalone
- `lua/memlay/` — LuaJIT FFI calls into the shared library, renders
  results using the Neovim buffer and highlight API

---

## Limitations

- C and C++ only
- Bitfields are skipped
- Buffer must be saved before triggering

---
