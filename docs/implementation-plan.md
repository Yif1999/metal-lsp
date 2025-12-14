## Plan: Symbol Index 与 AST 驱动的鲁棒实现

TL;DR — 构建轻量级的 Metal 源解析器與符号索引（SymbolIndex），在文档打开/保存时异步索引声明与引用，处理 include 路径并提供精确的 `textDocument/definition`、`textDocument/references`，以及基于 AST 的 `textDocument/formatting`（支持外部 formatter 回退）。

### Steps
1. 设计并添加 `Sources/MetalCore/SymbolIndex.swift`（索引存储与查询）。
2. 实现 `Sources/MetalCore/MetalParser.swift`（解析声明与引用，记录位置）。
3. 在 `Sources/MetalLanguageServer/LanguageServer.swift` 注册并实现 definition/references/formatting 处理。
4. 扩展 `Sources/MetalLanguageServer/DocumentManager.swift`：在 open/save 时触发索引更新与增量解析。
5. 添加 `Sources/MetalCore/Formatter.swift`：基于 AST 的格式化，支持外部 `clang-format` 回退与超时策略。

### Further Considerations
1. 索引应异步执行并支持 cancellation、增量更新与持久化缓存，避免全盘阻塞。
2. 包含路径解析复用 `Sources/MetalCore/MetalCompiler.swift` 的 include 逻辑以定位头文件与跨文件声明。
3. 添加集成测试（`Tests/MetalLSPTests/LSPIntegrationTests.swift`）覆盖同文件/跨文件定义、引用和格式化行为。
