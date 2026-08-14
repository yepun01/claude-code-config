#!/usr/bin/env bash
set -euo pipefail

# Setup script for Claude Code configuration
# Installs required MCP servers and verifies the environment

echo "=== Claude Code Config Setup ==="

# Check prerequisites
if ! command -v claude &>/dev/null; then
  echo "ERROR: 'claude' CLI not found. Install Claude Code first."
  exit 1
fi

if ! command -v npx &>/dev/null; then
  echo "ERROR: 'npx' not found. Install Node.js first."
  exit 1
fi

NPX_PATH=$(which npx)
echo "Using npx: $NPX_PATH"

# Install MCP servers
echo ""
echo "--- Installing MCP servers ---"

declare -A SERVERS=(
  ["context7"]="@upstash/context7-mcp@latest"
  ["sequential-thinking"]="@modelcontextprotocol/server-sequential-thinking"
  ["open-websearch"]="open-websearch@latest"
  ["playwright"]="@playwright/mcp@latest --headless"
)

for name in "${!SERVERS[@]}"; do
  echo "  Adding $name..."
  claude mcp add "$name" --transport stdio -- "$NPX_PATH" -y ${SERVERS[$name]} 2>/dev/null && \
    echo "    OK" || echo "    SKIP (already exists or error)"
done

# Memory MCP with custom file path
echo "  Adding memory..."
claude mcp add memory --transport stdio \
  -e MEMORY_FILE_PATH="$HOME/.claude/memory/knowledge-graph.jsonl" \
  -- "$NPX_PATH" -y @modelcontextprotocol/server-memory 2>/dev/null && \
  echo "    OK" || echo "    SKIP (already exists or error)"

# Create required directories
mkdir -p ~/.claude/tmp
mkdir -p ~/.claude/memory

# Verify
echo ""
echo "--- Verifying MCP servers ---"
claude mcp list

echo ""
echo "=== Setup complete ==="
echo "Restart Claude Code for changes to take effect."
