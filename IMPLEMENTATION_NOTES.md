# Metal LSP - 新功能实现说明

## 概述
本文档描述了三个新 LSP 功能的实现方式和原理。

## 1. Go to Definition (textDocument/definition)

### 工作原理
使用**正则表达式字符匹配**查找符号的声明位置。

### 匹配规则

#### 函数声明
```
Pattern: \b(functionName)\s*\(
匹配例子: kernel void myKernel(
        vertex float4 vertexShader(
        void normalFunction(
```

#### 变量声明
```
Pattern: \b(varName)\s*[=;]
匹配例子: float x = 1.0;
        int count;
        device float* data = nullptr;
```

#### 结构体声明
```
Pattern: \bstruct\s+(structName)\b
匹配例子: struct VertexIn {
        struct Data {
```

### 代码示例
```swift
// 在 MetalSymbolFinder.swift 中
let escapedName = NSRegularExpression.escapedPattern(for: "myVariable")
let regex = try? NSRegularExpression(pattern: "\\b\(escapedName)\\s*[=;]")
let match = regex?.firstMatch(in: line, range: NSRange(...))
```

### 精度
- ✅ 查找简单变量声明：准确
- ✅ 查找函数声明：准确
- ⚠️ 嵌套的初始化：可能有误触发
- ⚠️ 字符串内的关键字：会被错误识别（虽然尝试移除注释）

## 2. Find References (textDocument/references)

### 工作原理
搜索源代码中所有出现该符号的位置（使用全字匹配）。

### 匹配规则
```
Pattern: \b(symbolName)\b
说明: \b 确保只匹配完整的词，不匹配子串

例子:
- myVar 匹配 myVar，不匹配 myVariable
- data 匹配 data[0]，不匹配 dataset
```

### 代码示例
```swift
// 在 MetalSymbolFinder.swift 中
let regex = try? NSRegularExpression(pattern: "\\b\(escapedName)\\b")
let matches = regex?.matches(in: line, range: NSRange(...))
// matches 包含所有全字匹配的位置
```

### 返回值
```swift
[
  (line: 5, column: 12),  // 引用 1
  (line: 7, column: 8),   // 引用 2
  (line: 10, column: 4)   // 引用 3
]
```

## 3. Code Formatting (textDocument/formatting)

### 工作原理

#### 主要方法：使用 clang-format
```swift
// 调用系统的 clang-format
let formatter = Process()
formatter.executableURL = URL(fileURLWithPath: "/usr/bin/clang-format")
formatter.arguments = ["-style={...}"]
// 通过 stdin/stdout 传递代码
```

#### 备选方法：基础格式化
如果 clang-format 不可用，使用内置的基础格式化器：
- 简单缩进修正
- 删除多余空白
- 修复括号配对

### 格式化选项
```swift
struct FormattingOptions: Codable {
  let tabSize: Int                        // 默认 2
  let insertSpaces: Bool                  // 默认 true（使用空格而不是制表符）
  let trimTrailingWhitespace: Bool?       // 删除行尾空白
  let insertFinalNewline: Bool?           // 文件末尾添加换行
  let trimFinalNewlines: Bool?            // 删除末尾多余换行
}
```

### 代码示例
```swift
let formatter = MetalFormatter()
let formatted = formatter.format(
  source: metalCode,
  tabSize: 2,
  insertSpaces: true
)
```

## 技术架构

### 流程图
```
LSP 请求 (textDocument/definition 等)
    ↓
LanguageServer.swift - 处理请求
    ↓
MetalSymbolFinder / MetalFormatter - 处理逻辑
    ↓
正则表达式匹配或格式化
    ↓
返回 LSP 响应
```

### 文件结构
```
Sources/MetalCore/
├── MetalSymbolFinder.swift    ← 符号查找逻辑
├── MetalFormatter.swift        ← 格式化逻辑
└── ...

Sources/MetalLanguageServer/
├── LanguageServer.swift        ← LSP 请求处理
├── LSPTypes.swift             ← LSP 数据类型
└── ...
```

## 限制和已知问题

### 1. 语法分析的局限
```metal
// ❌ 误判案例
int x = data[some_variable];    // 会被认为是变量声明

"string with some_variable"     // 会被找到（虽然有注释移除）

/* int data; */                 // 虽然移除了注释，但边界情况可能失效
```

### 2. 多文件支持
- 当前只支持单文件内的符号查找
- 不支持跨文件的声明查找

### 3. 性能
- 对于大型文件（>10000 行）可能较慢
- 没有缓存机制

## 改进方向

### 短期改进
1. **增强注释移除** - 更精确地处理多行注释
2. **启发式规则** - 改进变量声明的检测（检查左边的类型）
3. **缓存** - 缓存已分析的文件

### 中期改进
1. **轻量级词法分析** - 分割关键字、标识符、字符串等
2. **作用域追踪** - 理解块级作用域
3. **多文件支持** - 跨文件的声明查找

### 长期改进
1. **完整 AST 解析** - 使用专业的 C++ 解析器库
2. **增量编译** - 缓存 AST 结果
3. **智能补全** - 基于上下文的建议

## 测试

### 集成测试位置
```
Tests/MetalLSPTests/LSPIntegrationTests.swift
├── gotoDefinition()        ← 测试 go to definition
├── findReferences()        ← 测试 find references
└── formatting()            ← 测试 code formatting
```

### 运行测试
```bash
swift test
```

## 总结

当前实现采用**正则表达式模式匹配**的方法，这是一个实用的折中方案：

| 特性 | 字符匹配 | AST 分析 |
|------|---------|--------|
| 性能 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 准确性 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 复杂度 | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| 实现时间 | ⭐⭐⭐⭐⭐ | ⭐⭐ |

对于大多数常见的 Metal 代码，这个方法已经足够好了。
