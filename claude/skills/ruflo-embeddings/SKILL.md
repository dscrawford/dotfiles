---
name: ruflo-embeddings
description: Ruflo vector embeddings — ONNX-based embedding generation, semantic search, similarity comparison, HNSW indexing, hyperbolic embeddings. Use when the user needs embedding operations, semantic search, or vector management.
argument-hint: "[subcommand] e.g. 'init', 'generate -t \"Hello\"', 'search -q \"error handling\"', 'benchmark'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo embeddings — Vector Embeddings

ONNX-based embedding generation, semantic search, and similarity operations.

## Commands

### init — Initialize Embedding Subsystem
```bash
timeout 60 ruflo embeddings init 2>&1

# With specific model
timeout 60 ruflo embeddings init --model all-mpnet-base-v2 2>&1
```

### generate — Create Embeddings
```bash
timeout 30 ruflo embeddings generate -t "Hello world" 2>&1
```

### search — Semantic Similarity Search
```bash
timeout 30 ruflo embeddings search -q "error handling" 2>&1
```

### compare — Text Similarity
```bash
timeout 30 ruflo embeddings compare 2>&1
```

### collections — Manage Namespaces
```bash
timeout 10 ruflo embeddings collections 2>&1
```

### index — HNSW Index Management
```bash
timeout 10 ruflo embeddings index 2>&1
```

### providers — List Embedding Providers
```bash
timeout 10 ruflo embeddings providers 2>&1
```

### chunk — Split Text for Embedding
```bash
timeout 30 ruflo embeddings chunk -t "Long document text..." 2>&1
```

### normalize — Normalize Vectors
```bash
timeout 10 ruflo embeddings normalize 2>&1
```

### hyperbolic — Poincare Ball Embeddings
```bash
timeout 30 ruflo embeddings hyperbolic -a convert 2>&1
```

### neural — RuVector Integration
```bash
timeout 30 ruflo embeddings neural -f drift 2>&1
```

### models — List/Download Models
```bash
timeout 10 ruflo embeddings models 2>&1
```

### cache — Manage Embedding Cache
```bash
timeout 10 ruflo embeddings cache 2>&1
```

### warmup — Preload Model
```bash
timeout 60 ruflo embeddings warmup 2>&1
```

### benchmark — Performance Benchmarks
```bash
timeout 120 ruflo embeddings benchmark 2>&1
```
