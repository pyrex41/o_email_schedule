#!/bin/bash

echo "🚀 Email Scheduler Documentation Generation"
echo "=========================================="

# Step 1: Add function documentation
echo "📝 Step 1: Adding function documentation..."
echo "Please run the function documentation prompt on your AI agent"
echo "Press Enter when complete..."
read

# Step 2: Generate Mermaid diagrams
echo "📊 Step 2: Generating Mermaid diagrams..."
echo "Please run the Mermaid generation prompt on your AI agent"
echo "Press Enter when complete..."
read

# Step 3: Run the OCaml documentation analyzer
echo "🔍 Step 3: Running documentation analyzer..."
ocaml generate_documentation.ml

# Step 4: Generate HTML from Mermaid
echo "🎨 Step 4: Converting Mermaid to HTML..."
mkdir -p docs/html

for file in docs/diagrams/*.mmd; do
    if [ -f "$file" ]; then
        base=$(basename "$file" .mmd)
        echo "Converting $base..."
        
        # Create HTML wrapper
        cat > "docs/html/$base.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>$base - Email Scheduler</title>
    <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
    <script>mermaid.initialize({startOnLoad:true});</script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .mermaid { text-align: center; }
    </style>
</head>
<body>
    <h1>$base</h1>
    <div class="mermaid">
$(cat "$file" | sed '1d;$d')
    </div>
</body>
</html>
EOF
    fi
done

# Step 5: Generate master index
echo "📚 Step 5: Generating documentation index..."
cat > docs/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Email Scheduler - Business Logic Documentation</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #333; }
        .diagram-list { list-style-type: none; padding: 0; }
        .diagram-list li { margin: 10px 0; }
        .diagram-list a { color: #0066cc; text-decoration: none; }
        .diagram-list a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>Email Scheduler - Business Logic Documentation</h1>
    <h2>System Diagrams</h2>
    <ul class="diagram-list">
EOF

for file in docs/html/*.html; do
    if [ -f "$file" ] && [ "$file" != "docs/index.html" ]; then
        base=$(basename "$file" .html)
        echo "        <li><a href=\"html/$base.html\">$base</a></li>" >> docs/index.html
    fi
done

cat >> docs/index.html <<EOF
    </ul>
    <h2>Generated: $(date)</h2>
</body>
</html>
EOF

echo "✅ Documentation generation complete!"
echo "📂 Output location: docs/"
echo "🌐 Open docs/index.html in a browser to view"