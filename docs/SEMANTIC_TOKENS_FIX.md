# 语义高亮 (Semantic Tokens) 修复说明

## 问题描述

在 JetBrains Rider 插件中使用官方 LSP API 时，语义高亮无法正常工作，只能显示基本的数字高亮，而函数、变量、声明等高亮无效。

## 根本原因分析

经过分析，发现以下问题：

1. **SemanticTokensOptions 结构不完整** - 缺少对 `full` 对象和 `range` 属性的正确支持
2. **缺少 range-based 请求处理** - JetBrains 可能会请求 `textDocument/semanticTokens/range`
3. **缺少 delta 请求支持** - JetBrains 可能会请求 `textDocument/semanticTokens/full/delta`
4. **缺少调试日志** - 难以诊断问题

## 修复内容

### 1. 更新 SemanticTokensOptions 结构

**文件**: `Sources/MetalLanguageServer/LSPTypes.swift`

```swift
struct SemanticTokensOptions: Codable {
  let legend: SemanticTokensLegend
  let full: SemanticTokensFullOptions?  // Changed from Bool to object
  let range: Bool?                      // Added range support
  let delta: Bool?                      // Added top-level delta support

  init(legend: SemanticTokensLegend, full: Bool = true, range: Bool? = nil) {
    self.legend = legend
    self.full = full ? SemanticTokensFullOptions(delta: true) : nil
    self.range = range
    self.delta = true
  }
}

struct SemanticTokensFullOptions: Codable {
  let delta: Bool?  // Support delta updates
}
```

### 2. 添加 Range 参数类型

**文件**: `Sources/MetalLanguageServer/LSPTypes.swift`

```swift
struct SemanticTokensRangeParams: Codable {
  let textDocument: TextDocumentIdentifier
  let range: Range
}
```

### 3. 添加 Range 请求处理器

**文件**: `Sources/MetalLanguageServer/LanguageServer.swift`

```swift
private func handleSemanticTokensRange(params: SemanticTokensRangeParams?) throws -> JSONValue {
  // 过滤指定范围内的 tokens 并返回
}
```

### 4. 支持多种 Semantic Tokens 请求

**文件**: `Sources/MetalLanguageServer/LanguageServer.swift`

```swift
case "textDocument/semanticTokens/full":
  // 完整文档的 tokens

case "textDocument/semanticTokens/full/delta":
  // 增量更新（当前返回完整 tokens）

case "textDocument/semanticTokens/range":
  // 范围内的 tokens

case "workspace/semanticTokens/refresh":
  // 刷新请求
```

### 5. 添加调试日志

```swift
// 在 handleSemanticTokens 中添加
if verbose && !tokens.isEmpty {
  let preview = tokens.prefix(10).map { "\($0.type)@[\($0.line):\($0.column)]" }.joined(separator: ", ")
  log("Token preview: \(preview)")
}
```

## Token 类型映射

Legend 中的 token 类型（索引顺序）：
```
0: namespace
1: type          ← float, int, float4 等类型
2: class         ← PascalCase 结构体
3: enum
4: interface
5: struct
6: typeParameter
7: parameter
8: variable       ← 普通变量
9: property       ← 对象属性
10: enumMember
11: event
12: function      ← 函数调用
13: method        ← 方法调用
14: macro         ← #include, #define
15: keyword       ← kernel, vertex, fragment 等
16: modifier
17: comment       ← // 和 /* */
18: string        ← "..."
19: number        ← 1.0, 2 等
20: regexp
21: operator      ← +, -, *, /, = 等
```

MetalLexer 生成的类型：
- `comment` → 17
- `string` → 18
- `macro` → 14
- `number` → 19
- `variable` → 8
- `keyword` → 15
- `type` → 1
- `method` → 13
- `property` → 9
- `function` → 12
- `class` → 2
- `operator` → 21

## 验证修复

### 1. 编译项目
```bash
swift build -c debug
```

### 2. 运行语义高亮测试
```bash
swift test --filter "SemanticTokensTests"
```

预期输出：
```
✔ Test "MetalLexer tokenizes Metal code correctly"
✔ Test "Token encoding produces correct format"
✔ Test "Legend contains all required token types"
✔ Test "SemanticTokensOptions has correct structure"
✔ Test "Range filtering works correctly"
```

### 3. 在 Rider 插件中测试

在你的 Rider 插件中，确保：

1. **正确配置 LSP 服务器**：
   ```kotlin
   class MetalLspServerDescriptor(project: Project) : ProjectWideLspServerDescriptor(project, "Metal") {
     override fun isSupportedFile(file: VirtualFile) = file.extension == "metal"
     override fun createCommandLine() = GeneralCommandLine("/path/to/metal-lsp", "--verbose")
   }
   ```

2. **启用调试日志**：
   ```
   #com.intellij.platform.lsp
   ```

3. **测试文件**：
   ```metal
   #include <metal_stdlib>
   using namespace metal;

   float globalValue = 1.0;

   kernel void computeShader(
       device float* data [[buffer(0)]],
       uint id [[thread_position_in_grid]]
   ) {
       float x = data[id];
       data[id] = x * globalValue;
   }
   ```

预期高亮：
- `#include` - 宏（黄色）
- `using`, `namespace`, `kernel`, `void`, `device`, `uint` - 关键字（紫色）
- `float`, `float*` - 类型（蓝色）
- `globalValue`, `data`, `id`, `x` - 变量（默认）
- `computeShader` - 函数（橙色）
- `1.0`, `0`, `0` - 数字（棕色）
- `[[buffer(0)]]`, `[[thread_position_in_grid]]` - 属性（绿色）
- `//` 注释 - 注释（灰色）

## 如果仍然不工作

### 检查清单

1. **LSP 服务器是否正确启动**：
   ```bash
   /path/to/metal-lsp --verbose --log-messages 2> /tmp/metal-lsp.log
   ```

2. **查看 IDE 日志**：
   ```
   Help → Show Log in Finder → idea.log
   搜索 "semanticTokens" 或 "metal-lsp"
   ```

3. **验证 LSP 通信**：
   在日志中应该看到：
   ```
   [LSP] Semantic tokens requested for file:///...
   [LSP] Returning X tokens, data length: Y
   ```

4. **检查 Legend 顺序**：
   确保 tokenTypes 数组与 JetBrains 期望的顺序完全一致

5. **尝试手动发送请求**：
   ```json
   {
     "jsonrpc": "2.0",
     "id": 1,
     "method": "textDocument/semanticTokens/full",
     "params": {
       "textDocument": {
         "uri": "file:///path/to/test.metal"
       }
     }
   }
   ```

## 常见问题

### Q: 为什么之前能用，现在不行？
A: 可能是 JetBrains LSP API 更新，或者之前使用了不同的 LSP 客户端实现。

### Q: 需要支持 delta 更新吗？
A: 不是必须的，但支持更好。当前实现返回完整 tokens，客户端会缓存。

### Q: 为什么只有数字高亮？
A: 数字的 token 类型是 `number` (索引 19)，可能其他类型的映射有问题，或者 legend 顺序不匹配。

### Q: 如何调试 token 生成？
A: 使用 `--verbose` 参数运行服务器，查看日志中的 "Token preview" 输出。

## 相关文件

- `Sources/MetalCore/MetalLexer.swift` - Token 生成器
- `Sources/MetalCore/MetalToken.swift` - Token 数据结构
- `Sources/MetalLanguageServer/LSPTypes.swift` - LSP 类型定义
- `Sources/MetalLanguageServer/LanguageServer.swift` - LSP 请求处理器
- `Tests/MetalLSPTests/SemanticTokensTests.swift` - 测试
