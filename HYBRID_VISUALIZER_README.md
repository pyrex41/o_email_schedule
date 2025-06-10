# 🔄 Hybrid Configuration System Visualizer

A powerful, interactive visualization tool for exploring the hybrid configuration system architecture in the email scheduler. Built with **Elm** and **Mermaid.js** for beautiful, functional modeling of complex data flows and decision trees.

## 🌟 Features

### 📊 Multiple Visualization Views
- **Data Flow Architecture**: Interactive flow diagram showing how configuration data moves through the system
- **Decision Tree Process**: Expandable tree showing the decision-making logic with complexity scoring
- **Function Call Graph**: Integration with AST analyzer to show actual function relationships
- **Configuration Flow**: Organization-specific config flow with size profile analysis

### 🎯 Interactive Elements
- **Clickable Nodes**: Click any node to see detailed information
- **Expandable Trees**: Expand/collapse decision tree branches
- **Highlighting**: Visual path highlighting and selection states
- **Filtering**: Filter by complexity, modules, and other criteria

### 🏢 Organization Examples
- **Small Agency** (5k contacts): 20% daily cap, aggressive scheduling
- **Regional Company** (50k contacts): 10% daily cap, balanced approach
- **State Network** (250k contacts): 7% daily cap, conservative with overrides
- **National Corp** (1M+ contacts): 5% daily cap, enterprise-grade with extensive overrides

### 📈 System Insights
- **Size Profile Analysis**: Automatic detection and manual override capabilities
- **Load Balancing Visualization**: See how different profiles affect capacity
- **Configuration Overrides**: Understand how JSON overrides modify base settings
- **System Constants**: View all hardcoded constants and their explanations

## 🚀 Quick Start

### Prerequisites
- **OCaml** with opam
- **Node.js** and npm (for Elm)
- **Python 3** (for development server)

### Installation

1. **Install dependencies**:
   ```bash
   make install-deps
   ```

2. **Build and run the visualizer**:
   ```bash
   make dev
   ```

3. **Open your browser** to `http://localhost:8000`

### Alternative: Manual Steps

1. **Build OCaml components**:
   ```bash
   eval $(opam env)
   dune build
   ```

2. **Generate visualization data**:
   ```bash
   dune exec standalone_visualizer/visualizer_cli.exe -- --hybrid lib/ -o output
   ```

3. **Compile Elm application**:
   ```bash
   cd output
   elm make src/Main.elm --output=elm.js
   ```

4. **Start development server**:
   ```bash
   python3 -m http.server 8000
   ```

## 🎨 Architecture Overview

### Core Components

#### 1. **Elm Frontend** (`src/`)
- **Main.elm**: Main application with UI and interaction logic
- **HybridConfig/Types.elm**: Functional types modeling the configuration system
- **HybridConfig/DataFlow.elm**: Data flow definitions and decision trees
- **HybridConfig/MermaidDiagrams.elm**: Mermaid diagram generation

#### 2. **OCaml Bridge** (`lib/visualizer/hybrid_config_bridge.ml`)
- AST analysis integration
- Data extraction and transformation
- JSON serialization for Elm consumption

#### 3. **Visualization Engine**
- **Mermaid.js**: Diagram rendering with interactive features
- **Modern CSS**: Beautiful, responsive design with smooth animations
- **Functional Architecture**: Pure functions for data transformation

### Data Flow

```
OCaml Source Files
      ↓
AST Analyzer (existing)
      ↓
Hybrid Config Bridge
      ↓
JSON Data Export
      ↓
Elm Application
      ↓
Mermaid Diagrams
      ↓
Interactive Visualization
```

## 📚 Usage Examples

### Command Line Options

```bash
# Basic hybrid configuration visualization
./visualizer_cli.exe --hybrid lib/

# With custom output directory
./visualizer_cli.exe --hybrid lib/ -o my_output

# Auto-serve after generation
./visualizer_cli.exe --hybrid --serve lib/

# Custom port
./visualizer_cli.exe --hybrid --serve --port 9000 lib/
```

### Makefile Targets

```bash
make help              # Show all available commands
make build            # Build OCaml components only
make hybrid-vis       # Generate visualization data
make elm-compile      # Compile Elm to JavaScript
make serve            # Build everything and serve
make clean            # Clean all build artifacts
make test-lib         # Quick test with lib/ directory
```

## 🔍 Visualization Views Explained

### 1. Data Flow View
Shows the complete hybrid configuration data flow:
- **Central Database (Turso)** → Organization config loading
- **Organization Loader** → Configuration parsing
- **Contact Counter** → Size determination
- **Size Profile Calculator** → Load balancing computation
- **Config Override Applier** → Final configuration
- **Email Processing Pipeline** → Scheduling and load balancing

### 2. Decision Tree View
Interactive decision tree showing the process flow:
- **Load Org Config**: Database queries and fallback handling
- **Check Contact Count**: SQLite queries and estimation logic
- **Determine Profile**: Auto-detection thresholds and manual overrides
- **Apply Overrides**: JSON parsing and validation
- **Calculate Capacity**: Size profile to capacity mapping
- **Process Contacts**: Email scheduling logic
- **Check Exclusions**: Business rule application
- **Calculate Priority**: Priority assignment logic
- **Schedule Emails**: Database insertion
- **Balance Load**: Overflow redistribution

### 3. Function Call Graph View
Integration with the existing AST analyzer:
- Shows actual function calls between components
- Complexity-based styling
- Module organization
- Interactive function details

### 4. Configuration Flow View
Organization-specific configuration visualization:
- Dynamic configuration based on selected example org
- Real-time updates when switching between org examples
- Override application visualization
- Load balancing parameter display

## 🎛️ Interactive Features

### Node Interactions
- **Click**: View detailed information in side panel
- **Hover**: Highlight related nodes and connections
- **Expand/Collapse**: For decision tree nodes with children

### Filtering and Controls
- **Complexity Filter**: Show only functions below complexity threshold
- **Module Toggle**: Show/hide module names
- **View Switching**: Seamless switching between visualization types
- **Path Highlighting**: Follow data flow paths

### Details Panel
- **Function Information**: Parameters, return types, complexity
- **Module Context**: Location in codebase
- **Documentation**: Extracted comments and descriptions
- **Related Components**: Clickable links to connected nodes

## 📊 Size Profile Analysis

### Automatic Detection Thresholds
- **Small**: < 10,000 contacts (20% daily cap, 1k batch)
- **Medium**: 10,000 - 99,999 contacts (10% daily cap, 5k batch)
- **Large**: 100,000 - 499,999 contacts (7% daily cap, 10k batch)
- **Enterprise**: 500,000+ contacts (5% daily cap, 25k batch)

### Configuration Override Examples
```json
{
  "daily_send_percentage_cap": 0.03,
  "batch_size": 50000,
  "ed_daily_soft_limit": 2000
}
```

### System Constants
- **ED Percentage**: 30% of daily capacity for effective dates
- **Overage Threshold**: 120% before redistribution
- **Spread Days**: 7 days for overflow distribution
- **Lookback Days**: 35 days for follow-up emails

## 🛠️ Development

### Adding New Visualization Types

1. **Define types** in `HybridConfig/Types.elm`
2. **Add data flow logic** in `HybridConfig/DataFlow.elm`
3. **Create Mermaid generator** in `HybridConfig/MermaidDiagrams.elm`
4. **Update main application** in `Main.elm`

### Extending OCaml Integration

1. **Add data extraction** in `hybrid_config_bridge.ml`
2. **Update JSON serialization** for new data types
3. **Add corresponding Elm decoders**

### Styling and Themes

The visualization uses CSS custom properties for easy theming:
```css
:root {
  --primary-color: #2563eb;
  --secondary-color: #10b981;
  --accent-color: #f59e0b;
  /* ... */
}
```

## 🐛 Troubleshooting

### Common Issues

1. **Elm compilation fails**:
   ```bash
   npm install -g elm@latest
   ```

2. **OCaml build errors**:
   ```bash
   eval $(opam env)
   opam install . --deps-only
   ```

3. **Mermaid diagrams not rendering**:
   - Check browser console for JavaScript errors
   - Ensure Mermaid.js is loaded correctly
   - Verify diagram syntax in generated data

4. **Port already in use**:
   ```bash
   make serve  # Uses port 8000 by default
   # Or specify custom port:
   ./visualizer_cli.exe --hybrid --serve --port 9000 lib/
   ```

### Debug Mode

Enable verbose output for debugging:
```bash
./visualizer_cli.exe --hybrid --verbose lib/
```

## 📈 Performance Considerations

### Large Codebases
- **Complexity filtering**: Use `--max-complexity` flag
- **Module filtering**: Focus on specific modules
- **Batch processing**: Large codebases are processed in chunks

### Browser Performance
- **SVG optimization**: Mermaid generates optimized SVGs
- **Lazy loading**: Decision tree nodes load on expansion
- **Responsive design**: Works on mobile devices

## 🤝 Contributing

### Code Structure
- **Pure functional**: Elm ensures no runtime errors
- **Type safety**: Strong typing throughout the pipeline
- **Modular design**: Easy to extend and modify

### Adding Features
1. Fork the repository
2. Create a feature branch
3. Add your visualization logic
4. Test with `make test-lib`
5. Submit a pull request

## 📄 License

This project is part of the email scheduler system. See the main project license for details.

## 🙏 Acknowledgments

- **Elm Language**: For functional frontend programming
- **Mermaid.js**: For beautiful diagram generation
- **OCaml Community**: For excellent tooling and libraries
- **Functional Programming**: For making complex systems understandable

---

**Happy Visualizing!** 🎉

Explore the hybrid configuration system and understand how size profiles, load balancing, and configuration overrides work together to handle organizations from small agencies to enterprise corporations.