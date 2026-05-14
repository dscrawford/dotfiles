---
name: ruflo-analyze
description: Ruflo code analysis — diff classification, AST parsing, complexity metrics, dependency graphs, circular dependency detection, module boundary analysis. Use when the user needs code analysis, risk assessment, or architectural insights.
argument-hint: "[subcommand] e.g. 'diff --risk', 'complexity src/ --threshold 15', 'circular src/', 'boundaries src/'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo analyze — Code Analysis

Code analysis, diff classification, graph boundaries, and change risk assessment.

## Commands

### diff — Change Risk Assessment
```bash
timeout 30 ruflo analyze diff 2>&1
timeout 30 ruflo analyze diff --risk 2>&1
```

### code — Static Analysis
```bash
timeout 30 ruflo analyze code src/ 2>&1
```

### deps — Dependency Analysis
```bash
timeout 30 ruflo analyze deps 2>&1
timeout 30 ruflo analyze deps --security 2>&1
```

### ast — AST Parsing (tree-sitter via ruvector)
```bash
timeout 30 ruflo analyze ast src/ 2>&1
```

### complexity — Cyclomatic Complexity
```bash
timeout 30 ruflo analyze complexity src/ 2>&1
timeout 30 ruflo analyze complexity src/ --threshold 15 2>&1
```

### symbols — Extract Code Symbols
```bash
timeout 30 ruflo analyze symbols src/ 2>&1
timeout 30 ruflo analyze symbols src/ --type function 2>&1
timeout 30 ruflo analyze symbols src/ --type class 2>&1
```

### imports — Import Dependencies
```bash
timeout 30 ruflo analyze imports src/ 2>&1
timeout 30 ruflo analyze imports src/ --external 2>&1
```

### boundaries — MinCut Code Boundaries
```bash
timeout 30 ruflo analyze boundaries src/ 2>&1
```

### modules — Louvain Community Detection
```bash
timeout 30 ruflo analyze modules src/ 2>&1
```

### dependencies — Full Dependency Graph
```bash
timeout 30 ruflo analyze dependencies src/ 2>&1
timeout 30 ruflo analyze dependencies src/ --format dot 2>&1
timeout 30 ruflo analyze dependencies src/ --format json 2>&1
```

### circular — Circular Dependency Detection
```bash
timeout 30 ruflo analyze circular src/ 2>&1
```

## Output Formats

All commands support `--format text|json|table`:

```bash
timeout 30 ruflo analyze complexity src/ --format json 2>&1
```
