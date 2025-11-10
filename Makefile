.PHONY: all build install clean test docs-gen uninstall

# Default target
all: build

# Build the project
build:
	@echo "Building metal-lsp..."
	swift build -c release

# Install to ~/.local/bin
install: build
	@echo "Installing metal-lsp to ~/.local/bin..."
	@mkdir -p ~/.local/bin
	@cp -f .build/release/metal-lsp ~/.local/bin/
	@chmod +x ~/.local/bin/metal-lsp
	@echo "Installed metal-lsp to ~/.local/bin/metal-lsp"
	@echo "Make sure ~/.local/bin is in your PATH"

# Uninstall from ~/.local/bin
uninstall:
	@echo "Uninstalling metal-lsp..."
	@rm -f ~/.local/bin/metal-lsp
	@echo "Uninstalled metal-lsp"

# Run tests
test:
	@echo "Running tests..."
	swift test

# Generate documentation Swift code from spec
docs-gen:
	@echo "Building doc generator..."
	swift build --product metal-doc-generator
	@if [ ! -f metal-shading-language.md ]; then \
		echo "Error: metal-shading-language.md not found"; \
		echo "Please convert the Metal spec PDF to markdown first"; \
		exit 1; \
	fi
	@echo "Generating Swift code from spec..."
	@mkdir -p Sources/MetalCore/gen
	.build/debug/metal-doc-generator metal-shading-language.md Sources/MetalCore/gen/MetalBuiltinData.swift
	@echo "Generated Sources/MetalCore/gen/MetalBuiltinData.swift"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	swift package clean
	@rm -rf .build
	@echo "Cleaned"

# Development build (debug)
dev:
	@echo "Building metal-lsp (debug)..."
	swift build
