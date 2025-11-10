#!/bin/bash
set -e

# Script to bump version, commit, and tag
# Usage: ./scripts/bump-version.sh 0.3.0 [--commit]

COMMIT_AND_TAG=false

# Parse arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <version> [--commit]"
    echo "Example: $0 0.3.0"
    echo ""
    echo "Options:"
    echo "  --commit    Automatically commit and tag the version change"
    exit 1
fi

NEW_VERSION=$1
if [ "$2" = "--commit" ]; then
    COMMIT_AND_TAG=true
fi

# Validate version format (simple check for x.y.z)
if ! [[ $NEW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in format x.y.z (e.g., 0.3.0)"
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 1
fi

# Check for uncommitted changes
if [ "$COMMIT_AND_TAG" = true ] && ! git diff-index --quiet HEAD --; then
    echo "Error: You have uncommitted changes. Please commit or stash them first."
    git status --short
    exit 1
fi

# Get current version
CURRENT_VERSION=$(grep 'public static let current = ' Sources/MetalCore/Version.swift | sed 's/.*"\(.*\)".*/\1/')
echo "Current version: $CURRENT_VERSION"
echo "New version: $NEW_VERSION"
echo ""

# Update Version.swift
cat > Sources/MetalCore/Version.swift << EOF
import Foundation

/// Version information for metal-lsp
public enum Version {
  /// The current version of metal-lsp
  public static let current = "$NEW_VERSION"
}
EOF

echo "✓ Updated Sources/MetalCore/Version.swift"
echo ""

if [ "$COMMIT_AND_TAG" = true ]; then
    # Show the diff
    echo "Changes:"
    git diff Sources/MetalCore/Version.swift
    echo ""

    # Commit the change
    git add Sources/MetalCore/Version.swift
    git commit -m "Bump version to $NEW_VERSION"
    echo "✓ Committed version change"

    # Create the tag
    git tag "v$NEW_VERSION"
    echo "✓ Created tag v$NEW_VERSION"
    echo ""

    echo "Next steps:"
    echo "  git push && git push --tags"
    echo ""
    echo "This will trigger CI to build and release version $NEW_VERSION"
else
    # Show the change
    echo "New version:"
    cat Sources/MetalCore/Version.swift
    echo ""

    echo "Next steps:"
    echo "  1. Review: git diff Sources/MetalCore/Version.swift"
    echo "  2. Commit: git add Sources/MetalCore/Version.swift && git commit -m 'Bump version to $NEW_VERSION'"
    echo "  3. Tag: git tag v$NEW_VERSION"
    echo "  4. Push: git push && git push --tags"
    echo ""
    echo "Or run again with --commit flag to do steps 2-3 automatically:"
    echo "  ./scripts/bump-version.sh $NEW_VERSION --commit"
fi
