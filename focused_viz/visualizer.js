/**
 * OCaml Program Flow Visualizer
 * Interactive JavaScript frontend for visualizing OCaml function call graphs
 */

class OCamlVisualizer {
    constructor() {
        this.data = null;
        this.sourceData = null;
        this.currentFunction = null;
        this.currentView = 'main';
        this.complexityFilter = 20;
        this.showModules = true;
        this.filteredFunctions = [];
        
        this.initializeMermaid();
        this.initializeEventListeners();
        this.loadData();
    }

    /**
     * Initialize Mermaid with proper configuration
     */
    initializeMermaid() {
        mermaid.initialize({
            startOnLoad: false,
            securityLevel: 'loose', // Essential for click functionality
            theme: 'dark',
            flowchart: {
                useMaxWidth: true,
                htmlLabels: true,
                curve: 'basis'
            },
            themeVariables: {
                primaryColor: '#61dafb',
                primaryTextColor: '#e4e4e4',
                primaryBorderColor: '#61dafb',
                lineColor: '#666',
                secondaryColor: '#3a3a3a',
                tertiaryColor: '#2d2d2d'
            }
        });

        // Define global callback for node clicks
        window.callback = (nodeId) => {
            this.selectFunction(nodeId);
        };
    }

    /**
     * Set up event listeners for UI interactions
     */
    initializeEventListeners() {
        // View mode selector
        document.getElementById('view-mode').addEventListener('change', (e) => {
            this.currentView = e.target.value;
            this.updateVisualization();
        });

        // Complexity filter
        const complexitySlider = document.getElementById('complexity-slider');
        const complexityValue = document.getElementById('complexity-value');
        
        complexitySlider.addEventListener('input', (e) => {
            this.complexityFilter = parseInt(e.target.value);
            complexityValue.textContent = `Max: ${this.complexityFilter}`;
            this.updateFunctionList();
            this.updateVisualization();
        });

        // Show modules toggle
        document.getElementById('show-modules-btn').addEventListener('click', (e) => {
            this.showModules = !this.showModules;
            e.target.classList.toggle('active', this.showModules);
            e.target.textContent = this.showModules ? 'Show Modules' : 'Hide Modules';
            this.updateVisualization();
        });

        // Export button
        document.getElementById('export-btn').addEventListener('click', () => {
            this.exportDiagram();
        });

        // Function search
        document.getElementById('function-search').addEventListener('input', (e) => {
            this.filterFunctions(e.target.value);
        });
    }

    /**
     * Load visualization data
     */
    async loadData() {
        try {
            // Load visualization data
            const vizResponse = await fetch('visualization.json');
            if (!vizResponse.ok) {
                throw new Error(`Failed to load visualization data: ${vizResponse.status}`);
            }
            this.data = await vizResponse.json();

            // Load source data
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

        // Update statistics
        this.updateStatistics();
        
        // Initialize function list
        this.updateFunctionList();
        
        // Show initial visualization
        this.updateVisualization();
    }

    /**
     * Update the statistics display
     */
    updateStatistics() {
        const metadata = this.data.metadata;
        document.getElementById('total-functions').textContent = metadata.total_functions;
        document.getElementById('total-modules').textContent = metadata.total_modules;
        document.getElementById('entry-points').textContent = metadata.entry_point_count;
        document.getElementById('cycles').textContent = metadata.cycle_count;
    }

    /**
     * Update the function list in the sidebar
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
            
            // Add special classes based on function properties
            if (entryPoints.has(func.name)) {
                li.classList.add('entry-point');
            }
            if (func.is_recursive) {
                li.classList.add('recursive');
            }
            if (func.complexity_score > 10) {
                li.classList.add('high-complexity');
            }

            const modulePath = func.module_path.length > 0 ? 
                func.module_path.join('.') + '.' : '';

            li.innerHTML = `
                <div class="function-name">${modulePath}${func.name}</div>
                <div class="function-meta">
                    Complexity: ${func.complexity_score} | 
                    Calls: ${func.calls.length} | 
                    ${func.is_recursive ? '🔄 Recursive' : ''} 
                    ${entryPoints.has(func.name) ? '🎯 Entry' : ''}
                </div>
            `;

            li.addEventListener('click', () => {
                this.selectFunction(func.name);
            });

            functionList.appendChild(li);
        });
    }

    /**
     * Filter functions based on search query
     */
    filterFunctions(query) {
        const functionItems = document.querySelectorAll('.function-item');
        const lowercaseQuery = query.toLowerCase();

        functionItems.forEach(item => {
            const functionName = item.querySelector('.function-name').textContent.toLowerCase();
            const isVisible = functionName.includes(lowercaseQuery);
            item.style.display = isVisible ? 'block' : 'none';
        });
    }

    /**
     * Select a function and show its details
     */
    selectFunction(functionName) {
        // Update UI state
        document.querySelectorAll('.function-item').forEach(item => {
            item.classList.remove('selected');
        });

        const selectedItem = Array.from(document.querySelectorAll('.function-item'))
            .find(item => item.querySelector('.function-name').textContent.includes(functionName));
        
        if (selectedItem) {
            selectedItem.classList.add('selected');
        }

        // Find function data
        const func = this.data.analysis.functions.find(f => f.name === functionName);
        if (!func) return;

        this.currentFunction = func;
        this.showFunctionDetails(func);
        this.highlightFunctionInDiagram(functionName);
    }

    /**
     * Show detailed information about a function
     */
    showFunctionDetails(func) {
        const detailsContainer = document.getElementById('details-content');
        const doc = func.documentation;
        
        // Build function signature
        const paramString = func.parameters.length > 0 ? 
            func.parameters.join(' -> ') + ' -> ' : '';
        const signature = `${func.name} : ${paramString}result`;

        let html = `
            <h3>${func.name}</h3>
            <div class="function-signature">${signature}</div>
            
            <div class="metrics-grid">
                <div class="metric-item">
                    <div class="metric-label">Complexity</div>
                    <div class="metric-value">${func.complexity_score}</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">Calls Made</div>
                    <div class="metric-value">${func.calls.length}</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">Recursive</div>
                    <div class="metric-value">${func.is_recursive ? 'Yes' : 'No'}</div>
                </div>
                <div class="metric-item">
                    <div class="metric-label">Module</div>
                    <div class="metric-value">${func.module_path.join('.') || 'Root'}</div>
                </div>
            </div>
        `;

        // Add deprecated warning if applicable
        if (doc.deprecated) {
            html += `<div class="doc-deprecated">⚠️ Deprecated: ${doc.deprecated}</div>`;
        }

        // Add documentation sections
        if (doc.summary) {
            html += `
                <div class="doc-section">
                    <div class="doc-summary">${doc.summary}</div>
                </div>
            `;
        }

        if (doc.description) {
            html += `
                <div class="doc-section">
                    <h4>Description</h4>
                    <div class="doc-description">${doc.description}</div>
                </div>
            `;
        }

        if (doc.parameters && doc.parameters.length > 0) {
            html += `
                <div class="doc-section">
                    <h4>Parameters</h4>
                    <div class="doc-parameters">
                        <ul>
                            ${doc.parameters.map(param => 
                                `<li><code>${param.name}</code> - ${param.description}</li>`
                            ).join('')}
                        </ul>
                    </div>
                </div>
            `;
        }

        if (doc.returns) {
            html += `
                <div class="doc-section">
                    <h4>Returns</h4>
                    <div class="doc-returns">${doc.returns}</div>
                </div>
            `;
        }

        if (doc.examples && doc.examples.length > 0) {
            html += `
                <div class="doc-section">
                    <h4>Examples</h4>
                    <div class="doc-examples">
                        ${doc.examples.map(example => 
                            `<pre><code>${example}</code></pre>`
                        ).join('')}
                    </div>
                </div>
            `;
        }

        if (doc.raises && doc.raises.length > 0) {
            html += `
                <div class="doc-section">
                    <h4>Raises</h4>
                    <div class="doc-raises">
                        <ul>
                            ${doc.raises.map(raise => 
                                `<li><code>${raise.name}</code> - ${raise.description}</li>`
                            ).join('')}
                        </ul>
                    </div>
                </div>
            `;
        }

        // Add function calls
        if (func.calls.length > 0) {
            html += `
                <div class="doc-section">
                    <h4>Calls</h4>
                    <div class="function-calls">
                        ${func.calls.map(call => 
                            `<span class="call-link" onclick="visualizer.selectFunction('${call}')">${call}</span>`
                        ).join(', ')}
                    </div>
                </div>
            `;
        }

        // Add source code viewer if available
        if (this.sourceData && this.sourceData.files[func.file]) {
            html += this.createSourceViewer(func);
        }

        detailsContainer.innerHTML = html;
    }

    /**
     * Create source code viewer for a function
     */
    createSourceViewer(func) {
        const sourceContent = this.sourceData.files[func.file];
        const startLine = func.location.start_line;
        const endLine = func.location.end_line;
        
        // Extract relevant lines with some context
        const lines = sourceContent.split('\n');
        const contextStart = Math.max(0, startLine - 3);
        const contextEnd = Math.min(lines.length, endLine + 3);
        const relevantLines = lines.slice(contextStart, contextEnd);
        
        return `
            <div class="doc-section">
                <h4>Source Code</h4>
                <div class="source-viewer">
                    <div class="source-header">
                        ${func.file}:${startLine}-${endLine}
                    </div>
                    <pre><code>${relevantLines.join('\n')}</code></pre>
                </div>
            </div>
        `;
    }

    /**
     * Update the main visualization
     */
    async updateVisualization() {
        if (!this.data) return;

        const container = document.getElementById('mermaid-container');
        container.innerHTML = '<div class="loading">Rendering diagram...</div>';

        try {
            let diagramDefinition;
            
            switch (this.currentView) {
                case 'modules':
                    diagramDefinition = this.data.diagrams.modules;
                    break;
                case 'low-complexity':
                    diagramDefinition = this.data.diagrams.low_complexity;
                    break;
                default:
                    diagramDefinition = this.generateFilteredDiagram();
                    break;
            }

            // Generate unique ID for this diagram
            const diagramId = `mermaid-${Date.now()}`;
            
            // Clear the container and add new div
            container.innerHTML = `<div id="${diagramId}"></div>`;
            
            // Render the diagram
            const { svg } = await mermaid.render(diagramId, diagramDefinition);
            container.innerHTML = svg;
            
            // Re-attach click handlers
            this.attachDiagramClickHandlers();
            
        } catch (error) {
            console.error('Mermaid rendering error:', error);
            container.innerHTML = `<div class="error">Failed to render diagram: ${error.message}</div>`;
        }
    }

    /**
     * Generate a filtered diagram based on current settings
     */
    generateFilteredDiagram() {
        const functions = this.filteredFunctions;
        const edges = this.data.analysis.edges.filter(edge => 
            functions.some(f => f.name === edge.source) && 
            functions.some(f => f.name === edge.target)
        );

        let diagram = '%%{init: {"flowchart": {"defaultRenderer": "elk"}} }%%\n';
        diagram += 'flowchart TD\n';

        // Add nodes
        functions.forEach(func => {
            const modulePrefix = this.showModules && func.module_path.length > 0 ? 
                func.module_path.join('.') + '.' : '';
            const displayName = modulePrefix + func.name;
            
            const complexityClass = func.complexity_score > 10 ? 'high-complexity' :
                                  func.complexity_score > 5 ? 'medium-complexity' : 'low-complexity';
            
            const recursiveIndicator = func.is_recursive ? ' 🔄' : '';
            
            diagram += `    ${func.name}["${displayName}${recursiveIndicator}"]:::${complexityClass}\n`;
        });

        // Add edges
        edges.forEach(edge => {
            diagram += `    ${edge.source} --> ${edge.target}\n`;
        });

        // Add click handlers
        functions.forEach(func => {
            diagram += `    click ${func.name} callback "Show details for ${func.name}"\n`;
        });

        // Add styles
        diagram += '\n';
        diagram += '    classDef low-complexity fill:#d4edda,stroke:#28a745,stroke-width:2px\n';
        diagram += '    classDef medium-complexity fill:#fff3cd,stroke:#ffc107,stroke-width:2px\n';
        diagram += '    classDef high-complexity fill:#f8d7da,stroke:#dc3545,stroke-width:2px\n';

        return diagram;
    }

    /**
     * Attach click handlers to diagram elements
     */
    attachDiagramClickHandlers() {
        // Find all clickable nodes in the SVG
        const nodes = document.querySelectorAll('#mermaid-container g.node');
        nodes.forEach(node => {
            node.style.cursor = 'pointer';
            node.addEventListener('click', (e) => {
                // Extract function name from node
                const textElement = node.querySelector('text');
                if (textElement) {
                    const fullText = textElement.textContent;
                    // Remove module prefix and emoji indicators
                    const functionName = fullText.replace(/^.*\./, '').replace(/ 🔄$/, '');
                    this.selectFunction(functionName);
                }
            });
        });
    }

    /**
     * Highlight a function in the current diagram
     */
    highlightFunctionInDiagram(functionName) {
        // Remove existing highlights
        document.querySelectorAll('.highlighted-node').forEach(node => {
            node.classList.remove('highlighted-node');
        });

        // Find and highlight the selected function
        const nodes = document.querySelectorAll('#mermaid-container g.node');
        nodes.forEach(node => {
            const textElement = node.querySelector('text');
            if (textElement && textElement.textContent.includes(functionName)) {
                node.classList.add('highlighted-node');
                // Add highlighting style
                const rect = node.querySelector('rect, polygon, circle');
                if (rect) {
                    rect.style.stroke = '#61dafb';
                    rect.style.strokeWidth = '3px';
                    rect.style.filter = 'drop-shadow(0 0 10px #61dafb)';
                }
            }
        });
    }

    /**
     * Export the current diagram
     */
    exportDiagram() {
        const svg = document.querySelector('#mermaid-container svg');
        if (!svg) {
            alert('No diagram to export');
            return;
        }

        // Create a downloadable SVG file
        const svgData = new XMLSerializer().serializeToString(svg);
        const svgBlob = new Blob([svgData], { type: 'image/svg+xml;charset=utf-8' });
        const svgUrl = URL.createObjectURL(svgBlob);
        
        const downloadLink = document.createElement('a');
        downloadLink.href = svgUrl;
        downloadLink.download = `ocaml-flow-${this.currentView}-${Date.now()}.svg`;
        document.body.appendChild(downloadLink);
        downloadLink.click();
        document.body.removeChild(downloadLink);
        URL.revokeObjectURL(svgUrl);
    }

    /**
     * Show error message
     */
    showError(message) {
        const container = document.getElementById('mermaid-container');
        container.innerHTML = `<div class="error">${message}</div>`;
    }
}

// Initialize the visualizer when the page loads
let visualizer;
document.addEventListener('DOMContentLoaded', () => {
    visualizer = new OCamlVisualizer();
});

// Add some utility CSS for highlighting
const style = document.createElement('style');
style.textContent = `
    .highlighted-node {
        animation: pulse 2s infinite;
    }
    
    @keyframes pulse {
        0% { opacity: 1; }
        50% { opacity: 0.7; }
        100% { opacity: 1; }
    }
    
    .call-link {
        color: #61dafb;
        cursor: pointer;
        text-decoration: underline;
        margin-right: 0.5rem;
    }
    
    .call-link:hover {
        color: #21a9c4;
    }
    
    .function-calls {
        line-height: 1.8;
    }
`;
document.head.appendChild(style);