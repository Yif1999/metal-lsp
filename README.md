# Metal LSP

A Language Server Protocol (LSP) implementation for Apple's Metal Shading Language, written in Swift.

## Features

- **Real-time Diagnostics**: Validates Metal shaders using the official Metal compiler (`xcrun metal`)
- **Auto-completion**: Comprehensive completion support for:
  - Built-in types (float4, half3, texture2d, etc.)
  - Math functions (sin, cos, normalize, dot, cross, etc.)
  - Geometric functions
  - Texture operations
  - Metal keywords and attributes
  - Function snippets (kernel, vertex, fragment templates)
- **Neovim Integration**: First-class support for Neovim's built-in LSP client

## Requirements

- macOS (required for Metal compiler)
- Swift 5.9 or later
- Xcode Command Line Tools (for `xcrun metal`)

## Installation

### Build from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/metal-lsp.git
cd metal-lsp

# Build the project
swift build -c release

# The binary will be at .build/release/metal-lsp
# Optionally, copy it to a directory in your PATH
cp .build/release/metal-lsp /usr/local/bin/
```

## Neovim Setup

### Using nvim-lspconfig

If you use [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig), add this to your Neovim configuration:

```lua
-- ~/.config/nvim/init.lua or ~/.config/nvim/lua/lsp-config.lua

local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

-- Define metal-lsp configuration if it doesn't exist
if not configs.metal_lsp then
  configs.metal_lsp = {
    default_config = {
      cmd = { '/path/to/metal-lsp' },  -- Update this path
      filetypes = { 'metal' },
      root_dir = lspconfig.util.root_pattern('.git', 'Package.swift'),
      settings = {},
    },
  }
end

-- Set up the server
lspconfig.metal_lsp.setup({
  on_attach = function(client, bufnr)
    -- Enable completion triggered by <c-x><c-o>
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    -- Key mappings
    local bufopts = { noremap=true, silent=true, buffer=bufnr }
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, bufopts)
    vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, bufopts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
  end,
})
```

### Manual Setup (without nvim-lspconfig)

```lua
-- ~/.config/nvim/init.lua

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'metal',
  callback = function()
    vim.lsp.start({
      name = 'metal-lsp',
      cmd = { '/path/to/metal-lsp' },  -- Update this path
      root_dir = vim.fs.dirname(vim.fs.find({ '.git', 'Package.swift' }, { upward = true })[1]),
    })
  end,
})
```

### File Type Detection

Add Metal file type detection to your Neovim configuration:

```lua
-- ~/.config/nvim/filetype.lua or add to init.lua
vim.filetype.add({
  extension = {
    metal = 'metal',
  },
})
```

Or using the older method:

```vim
" ~/.config/nvim/ftdetect/metal.vim
autocmd BufRead,BufNewFile *.metal setfiletype metal
```

### Optional: Syntax Highlighting

For basic syntax highlighting, add this to your Neovim configuration:

```lua
-- ~/.config/nvim/after/syntax/metal.lua
vim.cmd([[
  syntax keyword metalKeyword kernel vertex fragment constant device threadgroup thread
  syntax keyword metalKeyword struct enum typedef if else for while do switch case default
  syntax keyword metalKeyword break continue return const static inline using namespace
  syntax keyword metalType bool char uchar short ushort int uint half float
  syntax keyword metalType bool2 bool3 bool4 int2 int3 int4 uint2 uint3 uint4
  syntax keyword metalType half2 half3 half4 float2 float3 float4
  syntax keyword metalType float2x2 float3x3 float4x4 half2x2 half3x3 half4x4
  syntax keyword metalType texture1d texture2d texture3d texturecube sampler
  syntax keyword metalFunction sin cos tan asin acos atan atan2 pow exp log sqrt
  syntax keyword metalFunction dot cross length distance normalize reflect refract
  syntax keyword metalFunction min max clamp mix step smoothstep abs ceil floor

  highlight link metalKeyword Keyword
  highlight link metalType Type
  highlight link metalFunction Function
]])
```

## Usage

### Command Line Options

```bash
metal-lsp [OPTIONS]

OPTIONS:
  --verbose         Enable verbose logging to stderr
  --log-messages    Log all JSON-RPC messages to stderr
  --version         Show version information
  --help            Show help information
```

### Example Metal Shader

Create a file `shader.metal`:

```metal
#include <metal_stdlib>
using namespace metal;

kernel void computeShader(
    device float* data [[buffer(0)]],
    uint id [[thread_position_in_grid]]
) {
    data[id] = data[id] * 2.0;
}

vertex float4 vertexShader(uint vertexID [[vertex_id]]) {
    return float4(0.0, 0.0, 0.0, 1.0);
}

fragment float4 fragmentShader(float4 position [[position]]) {
    return float4(1.0, 0.0, 0.0, 1.0);
}
```

Open it in Neovim and you'll get:
- Real-time error checking as you save
- Auto-completion when you type (press `Ctrl-x Ctrl-o` or use your completion plugin)
- Diagnostics in the sign column

## Completion Examples

Type these prefixes and trigger completion:

- `float` → suggests `float`, `float2`, `float3`, `float4`, `float2x2`, etc.
- `kernel` → suggests kernel function template snippet
- `[[` → suggests Metal attributes like `[[buffer(0)]]`, `[[vertex_id]]`, etc.
- `norm` → suggests `normalize`
- `text` → suggests texture types like `texture2d`, `texture3d`, etc.

## Development

### Building for Development

```bash
# Build in debug mode
swift build

# Run tests
swift test

# Run the server directly
.build/debug/metal-lsp --verbose
```

### Debugging

To debug the LSP server, you can log messages to stderr:

```bash
metal-lsp --verbose --log-messages 2> /tmp/metal-lsp.log
```

Then in another terminal:

```bash
tail -f /tmp/metal-lsp.log
```

## Troubleshooting

### LSP not starting

1. Verify the binary path in your Neovim config is correct
2. Check that the binary is executable: `chmod +x /path/to/metal-lsp`
3. Run the binary manually to check for errors: `metal-lsp --verbose`

### No diagnostics appearing

1. Ensure you've saved the file (diagnostics run on save)
2. Check that `xcrun metal` works: `xcrun metal --version`
3. Look at the LSP logs: `:lua vim.lsp.set_log_level('debug')` then check `:LspLog`

### Completions not working

1. Verify the LSP is attached: `:LspInfo`
2. Try manual completion: `Ctrl-x Ctrl-o`
3. Check your completion plugin configuration

## Roadmap

Future enhancements:

- [ ] Hover information for built-in functions
- [ ] Go to definition (requires parsing)
- [ ] Find references
- [ ] Signature help for functions
- [ ] Document symbols
- [ ] Code formatting
- [ ] Incremental compilation for better performance
- [ ] Context-aware completion (filter by scope)
- [ ] VS Code extension

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

Apache License 2.0 - See LICENSE file for details

## Acknowledgments

- Built with Swift and the Language Server Protocol
- Uses Apple's Metal compiler for validation
- Inspired by the LSP ecosystem and Neovim's built-in LSP support
