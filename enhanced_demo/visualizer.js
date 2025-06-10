/**
 * Enhanced OCaml Program Flow Visualizer
 * Complete interactive JavaScript frontend for visualizing OCaml function call graphs
 * with full source code display and documentation
 */

class EnhancedOCamlVisualizer {
    constructor() {
        this.data = null;
        this.sourceData = null;
        this.currentFunction = null;
        this.currentView = 'overview';
        this.complexityFilter = 20;
        this.showModules = true;
        this.filteredFunctions = [];
        this.searchQuery = '';
        
        this.initializeMermaid();
        this.initializeEventListeners();
        this.loadData();
    }

    /**
     * Initialize Mermaid with enhanced configuration
     */
    initializeMermaid() {
        mermaid.initialize({
            startOnLoad: false,
            securityLevel: 'loose',
            theme: 'dark',
            flowchart: {
                useMaxWidth: true,
                htmlLabels: true,
                curve: 'basis',
                nodeSpacing: 100,
                rankSpacing: 150
            },
            themeVariables: {
                primaryColor: '#61dafb',
                primaryTextColor: '#e4e4e4',
                primaryBorderColor: '#61dafb',
                lineColor: '#666',
                secondaryColor: '#3a3a3a',
                tertiaryColor: '#2d2d2d',
                background: '#1e1e1e',
                mainBkg: '#2d2d2d',
                secondBkg: '#3a3a3a'
            }
        });

        // Global callback for node clicks
        window.functionClick = (nodeId) => {
            this.selectFunction(nodeId);
        };
    }

    /**
     * Initialize event listeners
     */
    initializeEventListeners() {
        // Complexity filter
        const complexitySlider = document.getElementById('complexity-filter');
        const complexityValue = document.getElementById('complexity-value');
        if (complexitySlider) {
            complexitySlider.addEventListener('input', (e) => {
                this.complexityFilter = parseInt(e.target.value);
                complexityValue.textContent = this.complexityFilter;
                this.updateVisualization();
                this.updateFunctionList();
            });
        }

        // Show modules toggle
        const showModulesToggle = document.getElementById('show-modules');
        if (showModulesToggle) {
            showModulesToggle.addEventListener('change', (e) => {
                this.showModules = e.target.checked;
                this.updateVisualization();
            });
        }

        // Search functionality
        const searchInput = document.getElementById('function-search');
        if (searchInput) {
            searchInput.addEventListener('input', (e) => {
                this.searchQuery = e.target.value.toLowerCase();
                this.filterFunctions();
            });
        }

        // View mode buttons
        document.querySelectorAll('.view-mode-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const mode = e.target.dataset.mode;
                this.setViewMode(mode);
            });
        });

        // Export button
        const exportBtn = document.getElementById('export-diagram');
        if (exportBtn) {
            exportBtn.addEventListener('click', () => {
                this.exportDiagram();
            });
        }

        // Close details panel
        const closeDetailsBtn = document.getElementById('close-details');
        if (closeDetailsBtn) {
            closeDetailsBtn.addEventListener('click', () => {
                this.closeDetailsPanel();
            });
        }
    }

    /**
     * Load visualization and source data
     */
    async loadData() {
        try {
            // Load main visualization data
            const vizResponse = await fetch('visualization.json');
            if (!vizResponse.ok) {
                throw new Error(`Failed to load visualization data: ${vizResponse.status}`);
            }
            this.data = await vizResponse.json();

            // Load source code data
            const sourceResponse = await fetch('source_data.json');
            if (sourceResponse.ok) {
                this.sourceData = await sourceResponse.json();
            }

            this.initializeVisualization();
        } catch (error) {
            this.showError(`Failed to load data: ${error.message}`);
        }
    }

    /**
     * Initialize the visualization with loaded data
     */
    initializeVisualization() {
        if (!this.data) return;

        this.updateStatistics();
        this.updateFunctionList();
        this.updateVisualization();
        
        // Show welcome message
        this.showWelcomeMessage();
    }

    /**
     * Update statistics display
     */
    updateStatistics() {
        const metadata = this.data.metadata;
        const stats = this.data.analysis.complexity_stats;
        
        document.getElementById('total-functions').textContent = metadata.total_functions;
        document.getElementById('total-modules').textContent = metadata.total_modules;
        document.getElementById('entry-points').textContent = metadata.entry_point_count;
        document.getElementById('cycles').textContent = metadata.cycle_count;
        
        // Additional stats
        document.getElementById('min-complexity').textContent = stats.min;
        document.getElementById('max-complexity').textContent = stats.max;
        document.getElementById('avg-complexity').textContent = stats.average.toFixed(1);
    }

    /**
     * Update function list in sidebar
     */
    updateFunctionList() {
        const functions = this.data.analysis.functions;
        const entryPoints = new Set(this.data.analysis.entry_points);
        const cyclicFunctions = new Set(this.data.analysis.cycles.flat());
        
        // Filter functions based on complexity
        this.filteredFunctions = functions.filter(func => 
            func.complexity_score <= this.complexityFilter
        );

        const functionList = document.getElementById('function-list');
        functionList.innerHTML = '';

        this.filteredFunctions.forEach(func => {
            const li = document.createElement('li');
            li.className = 'function-item';
            li.dataset.functionName = func.name;
            
            // Add special classes
            if (entryPoints.has(func.name)) {
                li.classList.add('entry-point');
            }
            if (func.is_recursive) {
                li.classList.add('recursive');
            }
            if (func.complexity_score > 10) {
                li.classList.add('high-complexity');
            } else if (func.complexity_score > 5) {
                li.classList.add('medium-complexity');
            } else {
                li.classList.add('low-complexity');
            }

            const modulePath = func.module_path.length > 0 ? 
                func.module_path.join('.') + '.' : '';

            // Create detailed function info
            const paramCount = func.parameters.length;
            const callCount = func.calls.length;
            const docStatus = func.documentation && func.documentation.summary ? '📖' : '';
            
            li.innerHTML = `
                <div class="function-header">
                    <span class="function-name">${modulePath}${func.name}</span>
                    <span class="function-indicators">
                        ${func.is_recursive ? '🔄' : ''}
                        ${entryPoints.has(func.name) ? '🎯' : ''}
                        ${docStatus}
                    </span>
                </div>
                <div class="function-signature">
                    ${this.formatParameters(func.parameters)}${func.return_type ? ` → ${func.return_type}` : ''}
                </div>
                <div class="function-metrics">
                    <span class="complexity">C: ${func.complexity_score}</span>
                    <span class="params">P: ${paramCount}</span>
                    <span class="calls">→: ${callCount}</span>
                    <span class="lines">L: ${func.end_line - func.start_line + 1}</span>
                </div>
            `;

            li.addEventListener('click', () => {
                this.selectFunction(func.name);
            });

            functionList.appendChild(li);
        });
    }

    /**
     * Format function parameters for display
     */
    formatParameters(parameters) {
        if (parameters.length === 0) return '()';
        
        const paramStrings = parameters.map(param => {
            if (param.type && param.type !== null) {
                return `${param.name}: ${param.type}`;
            } else {
                return param.name;
            }
        });
        
        return `(${paramStrings.join(', ')})`;
    }

    /**
     * Filter functions based on search query
     */
    filterFunctions() {
        const functionItems = document.querySelectorAll('.function-item');
        
        functionItems.forEach(item => {
            const functionName = item.dataset.functionName.toLowerCase();
            const visible = this.searchQuery === '' || functionName.includes(this.searchQuery);
            item.style.display = visible ? 'block' : 'none';
        });
    }

    /**
     * Update the main visualization
     */
    updateVisualization() {
        if (!this.data) return;

        const diagram = this.generateEnhancedMermaidDiagram();
        const container = document.getElementById('mermaid-container');
        
        if (container) {
            container.innerHTML = '';
            
            mermaid.render('mermaid-diagram', diagram).then((result) => {
                container.innerHTML = result.svg;
                
                // Add click handlers to nodes
                const nodes = container.querySelectorAll('.node');
                nodes.forEach(node => {
                    const nodeId = this.extractNodeId(node);
                    if (nodeId) {
                        node.style.cursor = 'pointer';
                        node.addEventListener('click', () => {
                            this.selectFunction(nodeId);
                        });
                    }
                });
            }).catch(error => {
                console.error('Mermaid rendering error:', error);
                container.innerHTML = `<div class="error">Diagram rendering failed: ${error.message}</div>`;
            });
        }
    }

    /**
     * Generate enhanced Mermaid diagram with better styling
     */
    generateEnhancedMermaidDiagram() {
        const functions = this.data.analysis.functions.filter(func => 
            func.complexity_score <= this.complexityFilter
        );
        const edges = this.data.analysis.edges;
        
        let diagram = `flowchart TD\n`;
        
        // Add nodes with enhanced information
        functions.forEach(func => {
            const nodeId = func.name;
            const modulePath = this.showModules && func.module_path.length > 0 ? 
                func.module_path.join('.') + '.' : '';
            
            const displayName = `${modulePath}${func.name}`;
            const paramInfo = func.parameters.length > 0 ? `(${func.parameters.length})` : '()';
            const complexityInfo = `[${func.complexity_score}]`;
            
            const nodeLabel = `"${displayName}${paramInfo}\\n${complexityInfo}"`;
            
            const complexityClass = this.getComplexityClass(func.complexity_score);
            const extraClasses = [];
            
            if (func.is_recursive) extraClasses.push('recursive');
            if (this.data.analysis.entry_points.includes(func.name)) extraClasses.push('entry-point');
            
            const allClasses = [complexityClass, ...extraClasses].join(' ');
            
            diagram += `    ${nodeId}[${nodeLabel}]:::${allClasses}\n`;
        });
        
        // Add edges
        const validFunctions = new Set(functions.map(f => f.name));
        edges.forEach(edge => {
            if (validFunctions.has(edge.source) && validFunctions.has(edge.target)) {
                diagram += `    ${edge.source} --> ${edge.target}\n`;
            }
        });
        
        // Add styling classes
        diagram += `\n`;
        diagram += `    classDef low-complexity fill:#d4edda,stroke:#28a745,stroke-width:2px,color:#000\n`;
        diagram += `    classDef medium-complexity fill:#fff3cd,stroke:#ffc107,stroke-width:2px,color:#000\n`;
        diagram += `    classDef high-complexity fill:#f8d7da,stroke:#dc3545,stroke-width:2px,color:#000\n`;
        diagram += `    classDef recursive fill:#e1ecf4,stroke:#0366d6,stroke-width:3px,stroke-dasharray: 5 5\n`;
        diagram += `    classDef entry-point fill:#f0f9ff,stroke:#0ea5e9,stroke-width:3px\n`;
        
        return diagram;
    }

    /**
     * Get complexity class for styling
     */
    getComplexityClass(score) {
        if (score > 10) return 'high-complexity';
        if (score > 5) return 'medium-complexity';
        return 'low-complexity';
    }

    /**
     * Extract node ID from DOM element (utility function)
     */
    extractNodeId(element) {
        // Try to find node ID from various attributes
        const id = element.id || element.dataset.id;
        if (id) return id;
        
        // Try to extract from class names or other attributes
        const classes = element.className.split(' ');
        for (const cls of classes) {
            if (cls.startsWith('node-')) {
                return cls.substring(5);
            }
        }
        
        return null;
    }

    /**
     * Select and display function details
     */
    selectFunction(functionName) {
        const func = this.data.analysis.functions.find(f => f.name === functionName);
        if (!func) return;

        this.currentFunction = func;
        this.showFunctionDetails(func);
        
        // Highlight in function list
        document.querySelectorAll('.function-item').forEach(item => {
            item.classList.remove('selected');
        });
        
        const selectedItem = document.querySelector(`[data-function-name="${functionName}"]`);
        if (selectedItem) {
            selectedItem.classList.add('selected');
            selectedItem.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
    }

    /**
     * Show detailed function information in the details panel
     */
    showFunctionDetails(func) {
        const detailsPanel = document.getElementById('details-panel');
        const detailsContent = document.getElementById('details-content');
        
        if (!detailsPanel || !detailsContent) return;

        // Build comprehensive function details
        let html = `
            <div class="function-details">
                <div class="function-title">
                    <h2>${func.module_path.length > 0 ? func.module_path.join('.') + '.' : ''}${func.name}</h2>
                    <div class="function-badges">
                        ${func.is_recursive ? '<span class="badge recursive">Recursive</span>' : ''}
                        ${this.data.analysis.entry_points.includes(func.name) ? '<span class="badge entry-point">Entry Point</span>' : ''}
                        <span class="badge complexity-${this.getComplexityClass(func.complexity_score)}">
                            Complexity: ${func.complexity_score}
                        </span>
                    </div>
                </div>
                
                <div class="function-signature-detail">
                    <h3>Signature</h3>
                    <code class="signature">
                        ${func.name}${this.formatParameters(func.parameters)}${func.return_type ? ` → ${func.return_type}` : ''}
                    </code>
                </div>
        `;

        // Add documentation if available
        if (func.documentation && func.documentation.summary) {
            html += `
                <div class="function-documentation">
                    <h3>Documentation</h3>
                    <div class="doc-summary">${func.documentation.summary}</div>
            `;
            
            if (func.documentation.description) {
                html += `<div class="doc-description">${func.documentation.description}</div>`;
            }
            
            if (func.documentation.parameters && func.documentation.parameters.length > 0) {
                html += `<div class="doc-parameters">
                    <h4>Parameters:</h4>
                    <ul>`;
                func.documentation.parameters.forEach(param => {
                    html += `<li><code>${param.name}</code>: ${param.description}</li>`;
                });
                html += `</ul></div>`;
            }
            
            if (func.documentation.returns) {
                html += `<div class="doc-returns"><strong>Returns:</strong> ${func.documentation.returns}</div>`;
            }
            
            html += `</div>`;
        }

        // Add function metrics
        html += `
            <div class="function-metrics-detail">
                <h3>Metrics</h3>
                <div class="metrics-grid">
                    <div class="metric">
                        <span class="metric-label">Lines</span>
                        <span class="metric-value">${func.end_line - func.start_line + 1}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">Parameters</span>
                        <span class="metric-value">${func.parameters.length}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">Calls</span>
                        <span class="metric-value">${func.calls.length}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">Complexity</span>
                        <span class="metric-value">${func.complexity_score}</span>
                    </div>
                </div>
            </div>
        `;

        // Add function calls information
        if (func.calls.length > 0) {
            html += `
                <div class="function-calls">
                    <h3>Function Calls (${func.calls.length})</h3>
                    <div class="calls-list">
            `;
            func.calls.forEach(call => {
                html += `<span class="call-item" data-function="${call}">${call}</span>`;
            });
            html += `</div></div>`;
        }

        // Add callers information
        const callers = this.findCallers(func.name);
        if (callers.length > 0) {
            html += `
                <div class="function-callers">
                    <h3>Called By (${callers.length})</h3>
                    <div class="callers-list">
            `;
            callers.forEach(caller => {
                html += `<span class="caller-item" data-function="${caller}">${caller}</span>`;
            });
            html += `</div></div>`;
        }

        // Add source code
        html += `
            <div class="function-source">
                <h3>Source Code</h3>
                <div class="source-info">
                    <span>Lines ${func.start_line}-${func.end_line}</span>
                </div>
                <pre class="source-code"><code class="language-ocaml">${this.escapeHtml(func.source_code)}</code></pre>
            </div>
        `;

        html += `</div>`;

        detailsContent.innerHTML = html;
        detailsPanel.classList.add('visible');

        // Add click handlers for function references
        detailsContent.querySelectorAll('.call-item, .caller-item').forEach(item => {
            item.addEventListener('click', () => {
                const functionName = item.dataset.function;
                this.selectFunction(functionName);
            });
        });
    }

    /**
     * Find functions that call the given function
     */
    findCallers(functionName) {
        return this.data.analysis.edges
            .filter(edge => edge.target === functionName)
            .map(edge => edge.source);
    }

    /**
     * Close the details panel
     */
    closeDetailsPanel() {
        const detailsPanel = document.getElementById('details-panel');
        if (detailsPanel) {
            detailsPanel.classList.remove('visible');
        }
        
        // Remove selection highlighting
        document.querySelectorAll('.function-item').forEach(item => {
            item.classList.remove('selected');
        });
        
        this.currentFunction = null;
    }

    /**
     * Set view mode
     */
    setViewMode(mode) {
        document.querySelectorAll('.view-mode-btn').forEach(btn => {
            btn.classList.remove('active');
        });
        
        document.querySelector(`[data-mode="${mode}"]`).classList.add('active');
        
        this.currentView = mode;
        this.updateVisualization();
    }

    /**
     * Export diagram as SVG
     */
    exportDiagram() {
        const svgElement = document.querySelector('#mermaid-container svg');
        if (!svgElement) return;

        const svgData = new XMLSerializer().serializeToString(svgElement);
        const blob = new Blob([svgData], { type: 'image/svg+xml' });
        const url = URL.createObjectURL(blob);
        
        const link = document.createElement('a');
        link.href = url;
        link.download = 'ocaml-function-diagram.svg';
        link.click();
        
        URL.revokeObjectURL(url);
    }

    /**
     * Show welcome message
     */
    showWelcomeMessage() {
        const detailsContent = document.getElementById('details-content');
        if (detailsContent) {
            detailsContent.innerHTML = `
                <div class="welcome-message">
                    <h2>OCaml Program Flow Visualizer</h2>
                    <p>Click on any function in the diagram or sidebar to view its details, source code, and documentation.</p>
                    
                    <div class="help-section">
                        <h3>Features:</h3>
                        <ul>
                            <li><strong>Function Details:</strong> Click any function to see its source code, parameters, and documentation</li>
                            <li><strong>Complexity Filter:</strong> Use the slider to filter functions by complexity</li>
                            <li><strong>Search:</strong> Type in the search box to find specific functions</li>
                            <li><strong>Export:</strong> Export the diagram as SVG</li>
                        </ul>
                    </div>
                    
                    <div class="legend">
                        <h3>Legend:</h3>
                        <div class="legend-items">
                            <div class="legend-item">
                                <span class="legend-color low-complexity"></span>
                                <span>Low Complexity (≤5)</span>
                            </div>
                            <div class="legend-item">
                                <span class="legend-color medium-complexity"></span>
                                <span>Medium Complexity (6-10)</span>
                            </div>
                            <div class="legend-item">
                                <span class="legend-color high-complexity"></span>
                                <span>High Complexity (>10)</span>
                            </div>
                            <div class="legend-item">
                                <span class="legend-symbol">🔄</span>
                                <span>Recursive Function</span>
                            </div>
                            <div class="legend-item">
                                <span class="legend-symbol">🎯</span>
                                <span>Entry Point</span>
                            </div>
                            <div class="legend-item">
                                <span class="legend-symbol">📖</span>
                                <span>Has Documentation</span>
                            </div>
                        </div>
                    </div>
                </div>
            `;
        }
        
        const detailsPanel = document.getElementById('details-panel');
        if (detailsPanel) {
            detailsPanel.classList.add('visible');
        }
    }

    /**
     * Show error message
     */
    showError(message) {
        const container = document.getElementById('mermaid-container');
        if (container) {
            container.innerHTML = `
                <div class="error-message">
                    <h3>Error</h3>
                    <p>${message}</p>
                    <p>Please check the console for more details.</p>
                </div>
            `;
        }
        console.error(message);
    }

    /**
     * Escape HTML for safe display
     */
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
}

// Initialize the visualizer when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new EnhancedOCamlVisualizer();
});

// Add CSS for enhanced styling
const style = document.createElement('style');
style.textContent = `
    .function-item {
        padding: 8px 12px;
        margin: 4px 0;
        border-radius: 6px;
        cursor: pointer;
        transition: all 0.2s ease;
        border-left: 4px solid transparent;
    }
    
    .function-item:hover {
        background-color: rgba(255, 255, 255, 0.1);
        transform: translateX(2px);
    }
    
    .function-item.selected {
        background-color: rgba(97, 218, 251, 0.2);
        border-left-color: #61dafb;
    }
    
    .function-item.low-complexity { border-left-color: #28a745; }
    .function-item.medium-complexity { border-left-color: #ffc107; }
    .function-item.high-complexity { border-left-color: #dc3545; }
    
    .function-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        font-weight: bold;
    }
    
    .function-name {
        font-family: 'JetBrains Mono', monospace;
    }
    
    .function-signature {
        font-size: 0.8em;
        color: #888;
        font-family: 'JetBrains Mono', monospace;
        margin: 2px 0;
    }
    
    .function-metrics {
        display: flex;
        gap: 8px;
        font-size: 0.7em;
        color: #666;
    }
    
    .function-metrics span {
        background: rgba(255, 255, 255, 0.1);
        padding: 1px 4px;
        border-radius: 3px;
    }
    
    .function-indicators {
        font-size: 0.8em;
    }
    
    .details-panel {
        max-height: 80vh;
        overflow-y: auto;
    }
    
    .function-details h2 {
        color: #61dafb;
        margin-bottom: 16px;
        font-family: 'JetBrains Mono', monospace;
    }
    
    .function-badges {
        display: flex;
        gap: 8px;
        margin-top: 8px;
    }
    
    .badge {
        padding: 4px 8px;
        border-radius: 12px;
        font-size: 0.7em;
        font-weight: bold;
        text-transform: uppercase;
    }
    
    .badge.recursive {
        background: #e1ecf4;
        color: #0366d6;
    }
    
    .badge.entry-point {
        background: #f0f9ff;
        color: #0ea5e9;
    }
    
    .badge.complexity-low-complexity {
        background: #d4edda;
        color: #28a745;
    }
    
    .badge.complexity-medium-complexity {
        background: #fff3cd;
        color: #ffc107;
    }
    
    .badge.complexity-high-complexity {
        background: #f8d7da;
        color: #dc3545;
    }
    
    .function-signature-detail {
        margin: 16px 0;
        padding: 12px;
        background: rgba(255, 255, 255, 0.05);
        border-radius: 6px;
    }
    
    .signature {
        font-family: 'JetBrains Mono', monospace;
        font-size: 1.1em;
        color: #61dafb;
    }
    
    .metrics-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 12px;
        margin-top: 8px;
    }
    
    .metric {
        display: flex;
        justify-content: space-between;
        padding: 8px;
        background: rgba(255, 255, 255, 0.05);
        border-radius: 4px;
    }
    
    .metric-label {
        color: #888;
    }
    
    .metric-value {
        font-weight: bold;
        color: #61dafb;
    }
    
    .calls-list, .callers-list {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        margin-top: 8px;
    }
    
    .call-item, .caller-item {
        padding: 4px 8px;
        background: rgba(97, 218, 251, 0.2);
        border-radius: 4px;
        cursor: pointer;
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.9em;
        transition: background-color 0.2s ease;
    }
    
    .call-item:hover, .caller-item:hover {
        background: rgba(97, 218, 251, 0.4);
    }
    
    .source-code {
        background: #1e1e1e;
        padding: 16px;
        border-radius: 6px;
        overflow-x: auto;
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.9em;
        line-height: 1.4;
        border: 1px solid #333;
    }
    
    .source-info {
        margin-bottom: 8px;
        color: #888;
        font-size: 0.8em;
    }
    
    .welcome-message {
        padding: 20px;
        text-align: center;
    }
    
    .help-section, .legend {
        margin-top: 24px;
        text-align: left;
    }
    
    .legend-items {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 8px;