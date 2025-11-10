# Metal LSP

[![CI](https://github.com/TimPapler/metal-lsp/actions/workflows/ci.yml/badge.svg)](https://github.com/TimPapler/metal-lsp/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)

A Language Server Protocol (LSP) implementation for Apple's Metal Shading Language, written in Swift.

### Important: This is an implementation that was vibe coded, with a bit of touches here and there to make it work. It's just a tool to get some basic LSP functionality running in Neovim. I don't intend to support other use case. You can always fork and implement features or fixes you deem necesarry. 

## Features

- **Real-time Diagnostics**: Validates Metal shaders using the official Metal compiler (`xcrun metal`)
- **Auto-completion**: Comprehensive completion support for:
  - Built-in types (float4, half3, texture2d, etc.)
  - Math functions (sin, cos, normalize, dot, cross, etc.)
  - Geometric functions
  - Texture operations
  - Metal keywords and attributes
  - Function snippets (kernel, vertex, fragment templates)
- **Hover Information**: Rich documentation for built-in Metal functions and types
  - Function signatures with parameter types
  - Detailed descriptions of what each function does
  - Formatted in Markdown for easy reading
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
- Hover documentation (press `K` in normal mode over any built-in function or type)
- Diagnostics in the sign column

## Hover Information

Hover over any Metal built-in function or type to see documentation:

- Move your cursor over `normalize`, `float4`, `dot`, etc.
- Press `K` in normal mode (or your configured hover key)
- See formatted documentation with function signatures and descriptions

The LSP includes comprehensive documentation for 136+ Metal built-in functions, types, and keywords compiled directly into the binary. Documentation is extracted from the official Metal Shading Language Specification and provides instant O(1) hash map lookups with zero I/O overhead.

Example: Hovering over `normalize` shows:
```
float2 normalize(float2 x)
---
Returns a vector in the same direction as x but with a length of 1.
```

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

### Updating Documentation

The Metal documentation is compiled directly into the binary from Swift code generated from the Metal Shading Language Specification. To regenerate:

```bash
# Regenerate Swift code from spec
make docs-gen
```

This reads `metal-shading-language.md` and generates `Sources/MetalCore/gen/MetalBuiltinData.swift` with ~136 builtin entries. The generated code is committed to the repository for zero-overhead documentation lookups.

### Creating a Release

**Quick Release (Automated):**

```bash
# Bump version, commit, and tag in one command
./scripts/bump-version.sh 0.3.0 --commit

# Push to trigger release
git push && git push --tags
```

**Manual Release (Review First):**

```bash
# 1. Update version
./scripts/bump-version.sh 0.3.0

# 2. Review the change
git diff Sources/MetalCore/Version.swift

# 3. Commit and tag
git add Sources/MetalCore/Version.swift
git commit -m "Bump version to 0.3.0"
git tag v0.3.0

# 4. Push
git push && git push --tags
```

The GitHub Actions CI will automatically:
1. Verify that `Version.swift` matches the tag (fails if mismatch)
2. Build the release binary
3. Create a GitHub release with the binary and installation instructions

**Important:** The version in `Version.swift` must match the git tag. The CI enforces this to prevent version mismatches.

**Obtaining the Metal Shading Language Specification:**

1. Download the official PDF from [Apple's Metal documentation](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)

2. Convert to markdown using marker-pdf:

   ```bash
   # Install marker-pdf
   pip3 install marker-pdf

   # Convert PDF to Markdown (outputs to Metal-Shading-Language-Specification/ directory)
   marker_single Metal-Shading-Language-Specification.pdf --output_format markdown

   # Move/rename the output
   mv Metal-Shading-Language-Specification/Metal-Shading-Language-Specification.md metal-shading-language.md
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

- [x] Hover information for built-in functions
- [ ] Signature help for functions
- [ ] Document symbols
- [ ] Go to definition (requires parsing)
- [ ] Find references
- [ ] Code formatting
- [ ] Incremental compilation for better performance
- [ ] Context-aware completion (filter by scope)

## License

Apache License 2.0 - See LICENSE file for details

## Acknowledgments

- Built with Swift and the Language Server Protocol
- Uses Apple's Metal compiler for validation
- Inspired by the LSP ecosystem and Neovim's built-in LSP support
- You can use this as you wish, modify it ...
