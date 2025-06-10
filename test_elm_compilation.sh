#!/bin/bash

# Test Elm Compilation Script

echo "🌳 Testing Elm Compilation..."

# Check if Elm is installed
if ! command -v elm &> /dev/null; then
    echo "❌ Elm is not installed. Installing..."
    npm install -g elm
fi

# Test compilation without generating output
echo "📝 Checking elm.json..."
if [ ! -f "elm.json" ]; then
    echo "❌ elm.json not found in current directory"
    exit 1
fi

echo "🔍 Validating Elm syntax..."
if elm make src/Main.elm --output=/dev/null 2>&1; then
    echo "✅ Elm compilation successful!"
    exit 0
else
    echo "❌ Elm compilation failed. Errors:"
    elm make src/Main.elm --output=/dev/null
    exit 1
fi