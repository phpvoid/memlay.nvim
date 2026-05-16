# memlay.nvim

Memory layout visualizer for C structs inside Neovim.

Put your cursor on any struct and hit `<leader>ml`. memlay shows you exactly how the struct is laid out in memory — which bytes are data, which are padding, and how to fix it.

---

## Why

Padding waste in C structs is invisible and easy to miss. A struct like:

```c
struct Foo {
    char x;    // 1B
    int  n;    // 4B
    char flag; // 1B
};
```

looks like 6 bytes but is actually 12. memlay makes this immediately visible and tells you exactly how to fix it.

---

## Features

- Accurate ABI layout via libclang — not guesswork, not regex
- Proportional memory map showing used bytes vs padding
- Byte counts inside each field block
- Reorder suggestion with exact bytes saved
- Detects already-optimal structs
- Vertical mode for structs with many fields
- Works with typedef struct, pointers, arrays, uint*_t, bool
- Zero config — works out of the box for most setups

---

## Install

### lazy.nvim (recommended)

```lua
{
  "phpopko/memlay.nvim",
  build = "make -C c/",
  ft    = { "c", "cpp" },
  config = function()
    require("memlay").setup({
      keymap = "ml",
    })
  end,
}
```

### packer.nvim

```lua
use {
  "phpopko/memlay.nvim",
  run    = "make -C c/",
  config = function() require("memlay").setup() end,
}
```

---

## Requirements

| Requirement | Version |
|---|---|
| Neovim | >= 0.9 (LuaJIT required) |
| libclang | >= 14 |
| clang + make | for building from source |

### Install libclang

```bash
# Ubuntu / Debian
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
export LLVM_PATH=/path/to/your/llvm
```

---

## Usage

| Action | Default |
|---|---|
| Show layout | `<leader>ml` |
| Close window | `q` or `<Esc>` |
| Scroll (large structs) | `j` / `k` |

Place your cursor anywhere inside a struct definition and trigger the keymap. The popup opens above the struct so it never covers what you're reading.

---

## How it works

memlay has two layers:

**C layer** (`c/parse.c`, `c/layout.c`) — uses libclang to parse the file, find the struct at the cursor position, extract field sizes and alignments, and compute the ABI layout with the four standard alignment rules. Built as a shared library (`libmemlay.so`). The layout logic is fully independent of libclang and tested standalone via `test_layout.c`.

**Lua layer** (`lua/memlay/`) — loads the library via LuaJIT FFI, calls `analyze_struct(filepath, line, col)`, and renders the result in a floating window using Neovim's buffer and highlight API.

No LSP required. No Treesitter. libclang gives accurate results for any type the compiler would accept — pointers, arrays, typedefs, nested structs.

---

## Troubleshooting

Run `:checkhealth memlay` — it tells you exactly what is missing:
memlay
OK   Neovim >= 0.9
OK   LuaJIT 2.1.0
OK   libclang: /usr/lib/llvm-17/lib/libclang.so
OK   libmemlay.so (prebuilt): .../prebuilt/linux-x86_64/libmemlay.so
OK   clang: /usr/bin/clang
OK   make: /usr/bin/make

If `libmemlay.so` is missing, run `:MemlayBuild` to compile from source.

If libclang is not found, set `LLVM_PATH`:

```bash
export LLVM_PATH=/path/to/your/llvm
```

---

## Commands

| Command | Description |
|---|---|
| `:MemlayBuild` | Build `libmemlay.so` from source |
| `:MemlayReload` | Reload plugin after build |
| `:MemlayDebug` | Print raw layout values for struct at cursor |

---

## Configuration

```lua
require("memlay").setup({
  keymap = "<leader>ml",  -- set to false to disable default keymap
})
```

Override highlight colors in your config:

```lua
vim.api.nvim_set_hl(0, "MemlayField", { bg = "#5fafd7", fg = "#000000" })
vim.api.nvim_set_hl(0, "MemlayPad",   { bg = "#4e4e4e", fg = "#000000" })
```

---

## Building from source

```bash
git clone https://github.com/phpopko/memlay.nvim
cd memlay.nvim/c
make
```

Requires `clang` and `libclang-dev`. Output is `lua/memlay/libmemlay.so`.

To run the standalone layout tests with no libclang dependency:

```bash
make test_layout
```

---

## Limitations

- C and C++ only
- Bitfields are skipped
- File must be saved — memlay parses from disk, not the buffer
- Prebuilt binaries are currently provided for Linux x86_64 only — other platforms build from source via `:MemlayBuild`

---
