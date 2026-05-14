---
name: ruflo-neural
description: Ruflo neural pattern training — MoE, Flash Attention, WASM SIMD, pattern learning, model export/import via IPFS. Use when the user needs neural training, pattern analysis, or model management.
argument-hint: "[subcommand] e.g. 'train -p coordination', 'status', 'patterns --action list', 'predict', 'benchmark'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo neural — Neural Pattern Training

Neural pattern training with MoE, Flash Attention, and WASM SIMD acceleration.

## Commands

### status — Check Neural System
```bash
timeout 10 ruflo neural status 2>&1
```

### train — Train Patterns
```bash
# Train coordination patterns
timeout 120 ruflo neural train -p coordination 2>&1

# Train with specific pattern type
timeout 120 ruflo neural train -p security 2>&1
```

### patterns — Manage Cognitive Patterns
```bash
timeout 10 ruflo neural patterns --action list 2>&1
```

### predict — AI Predictions
```bash
timeout 30 ruflo neural predict 2>&1
```

### optimize — Quantize & Compress
```bash
timeout 60 ruflo neural optimize 2>&1
```

### benchmark — Performance Benchmarks
```bash
timeout 120 ruflo neural benchmark 2>&1
```

### list — Pre-trained Models
```bash
timeout 10 ruflo neural list 2>&1
```

### export — Publish to IPFS (Ed25519 signed)
```bash
timeout 60 ruflo neural export 2>&1
```

### import — Import from IPFS with Verification
```bash
timeout 60 ruflo neural import 2>&1
```
