---
name: design-doc
description: Generate or update a LaTeX system design document for the current project. Scans the codebase with parallel agents, builds every diagram as code via the `diagram` skill's CLI toolchain (Mermaid/D2/Structurizr), embeds them as vector PDF, compiles, and verifies every page visually.
argument-hint: "[docs/system_design.tex] path to existing doc to update, or leave blank to create new"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# System Design Document Generator

LaTeX system design doc for any codebase; create or incrementally update.

Owns the document (scan, prose, tables, typography, compile, page-fit verification); owns no diagram syntax — every figure is built by the `diagram` skill's toolchain, embedded as vector PDF. Never hand-write TikZ: unverifiable pre-compile, needs `texliveFull` (2.5 GiB), non-reusable outside the PDF; diagrams-as-code render in ~1s, get image-reviewed first, and double as README assets.

**Read `~/.claude/skills/diagram/SKILL.md` before Phase 4**; its rules (tool choice, node budget, labelled arrows, render/read-back loop) apply verbatim. This file adds only print specifics: palette bridge, PDF export, page sizing.

Activate: system design doc / visual architecture overview requested, or doc update after code changes. Single standalone diagram (README, PR, chat) → use `diagram` directly.

## Phase 1: Mode

`$ARGUMENTS` may name an existing `.tex`; else search `docs/system_design.tex`, `docs/*.tex`. None found → **create mode**. Found → **update mode**: diff vs codebase, touch only affected sections (see Update Mode Details).

## Phase 2: Plan

### 2a. Survey

- Primary language: `**/*.py`, `**/*.ts`, `**/*.go`, `**/*.rs`, `**/*.java`
- Config: `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, `pom.xml`, `flake.nix`
- Top-level modules: `ls src/` or equivalent

### 2b. Segments (each = one doc section + one Phase 3 agent)

Project metadata (language, framework, name, version); entry points (CLI commands, main functions, server startup, routes); one per architectural layer (API routes, service layer, data access, …); data models (classes, dataclasses, structs, schemas, ORM models); database schema (tables, columns, constraints, relationships); external integrations (APIs, services, message queues, caches); configuration (env vars, config files, feature flags).

### 2c. Diagram set — plan *before* scanning

Decide each figure's single question (`diagram`'s "constrain before generating"; skipping yields one unreadable 60-node megadiagram).

| Document section | Diagram | Tool | Direction |
|---|---|---|---|
| High-Level Architecture | Container view: major components + data flow | Mermaid `flowchart`, or D2 if >25 nodes | `TB` |
| Component Detail (per subsystem) | Component view, one per major subsystem | Mermaid `flowchart` | `TB` |
| Data Flow | Input → processing → storage → output, **including failure edges** | Mermaid `flowchart` | `LR` |
| Key Request Path | Interaction over time | Mermaid `sequenceDiagram` | — |
| Data Models | Fields, types, relationships | Mermaid `classDiagram` | — |
| Database Schema | Tables, columns, cardinality | Mermaid `erDiagram` | — |
| Extension Points | Interface + existing impls + dashed "your new impl" | Mermaid `flowchart` | `TB` |
| Multi-view C4 (large systems only) | Context / Container / Component from one model | Structurizr DSL → Mermaid | — |

Print-tightened rules from `diagram`:

- One abstraction level per diagram — never "Postgres" beside `UserRepository.findById`
- Node budget **12–15 in print** (the skill's 15–20 assumes a screen; A4 is narrower); beyond → container view + per-subsystem component views
- Prefer `TB` (portrait page; `LR` width shrinks text at `\textwidth`, see 4d); `LR` only for genuine, short pipelines
- Draw failure edges (timeouts, retries, fallbacks) in Data Flow — generated diagrams' weakest spot

### 2d. Todos

One per segment + one per diagram (user steers scope pre-scan). Update mode adds: diff doc vs codebase; flag stale sections/diagrams.

## Phase 3: Scan (Parallelised)

One Explore agent per segment.

- Batch 1, parallel, single message: 1 metadata + configuration; 2 entry points + CLI/API surface; 3 data models + database schema; 4 external integrations; 5+ per-module deep dives (large projects)
- Batch 2 after batch 1 returns (needs the full component list): A data flow (input → processing → storage → output); B extension points (interfaces, abstract classes, plugin patterns)

Prompt template:

> Explore the project at `{project_root}`; focus on **{segment_name}**. Read all
> relevant source files completely. Return: file paths and purposes; key
> classes/functions with signatures and brief descriptions; relationships to other
> components (imports, calls, inheritance); notable patterns, constraints, quirks.
> Data models: every field with type and constraints. Database schemas: every table,
> column, type, constraint. External integrations: URLs, auth methods, timeouts,
> error handling. Note every failure mode — timeouts, retries, fallbacks — with its
> trigger condition; these become data-flow diagram edges.

Merge: one structured outline; resolve cross-references; identify the main data-flow path and its failure paths; re-check the 2c diagram set (add/drop/split now); mark Phase 2 todos done.

## Phase 4: Diagrams

Sources in `docs/diagrams/`, **committed** — source is the artifact; the PDF is a build output, committed only because the `.tex` needs it.

```
docs/
  system_design.tex
  system_design.pdf
  diagrams/
    architecture.mmd     ← source, committed
    architecture.pdf     ← vector, embedded by \includegraphics
    dataflow.mmd
    dataflow.pdf
```

### 4a. Palette bridge

Colour identity lives in diagram sources, not LaTeX. Use exactly:

| Role | Fill | Stroke | Used for |
|---|---|---|---|
| Primary | `#D6E4F0` | `#4A90D9` | Core components, main logic |
| Abstraction | `#DFF0D8` | `#5CB85C` | Interfaces, base classes, protocols |
| External | `#FCF8E3` | `#F0AD4E` | Third-party services, external actors |
| Storage | `#EBE0F0` | `#9B59B6` | Databases, caches, queues, files |
| Implementation | `#F2DEDE` | `#D9534F` | Concrete impls, data sources |
| Text | — | `#2C3E50` | All label text |

Mermaid — paste into every flowchart:

```
classDef primary  fill:#D6E4F0,stroke:#4A90D9,stroke-width:1.5px,color:#2C3E50
classDef abstract fill:#DFF0D8,stroke:#5CB85C,stroke-width:1.5px,color:#2C3E50
classDef external fill:#FCF8E3,stroke:#F0AD4E,stroke-width:1.5px,color:#2C3E50
classDef storage  fill:#EBE0F0,stroke:#9B59B6,stroke-width:1.5px,color:#2C3E50
classDef impl     fill:#F2DEDE,stroke:#D9534F,stroke-width:1.5px,color:#2C3E50
```

Apply: `node["Label"]:::primary`. D2: `style.fill: "#D6E4F0"; style.stroke: "#4A90D9"`, same pairs. Every colour used needs a Phase 5 legend entry; missing entry = defect.

### 4b. Render for print

Mermaid: PDF directly from `mmdc`; **never via `rsvg-convert`** — librsvg can't render Mermaid's `foreignObject` HTML labels and silently drops every node label (empty boxes); `htmlLabels: false` only half-fixes (labels still missing, spaces collapse); `mmdc`'s Chromium export is correct.

```bash
# --pdfFit crops the page to the diagram (600x77pt) instead of padding to US Letter
mmdc -i docs/diagrams/architecture.mmd -o docs/diagrams/architecture.pdf --pdfFit -b white

# Self-review raster
mmdc -i docs/diagrams/architecture.mmd -o /tmp/dd-review.png -s 2 -b white
```

D2: real SVG text — librsvg works and is the only PDF route:

```bash
d2 --layout elk docs/diagrams/architecture.d2 docs/diagrams/architecture.svg
rsvg-convert -f pdf -o docs/diagrams/architecture.pdf docs/diagrams/architecture.svg
rsvg-convert -z 2  -o /tmp/dd-review.png            docs/diagrams/architecture.svg
```

Structurizr: export to Mermaid, then the Mermaid path:

```bash
structurizr-cli export -workspace docs/workspace.dsl -format mermaid -output docs/diagrams/
```

Non-zero exit = syntax error: read message, fix source, re-render. Never embed a failed render.

### 4c. Read back

`Read` each review PNG against `diagram` Step 5 checklist: overlapping text, removable edge crossings, aspect ratio, legibility, title, legend, every arrow labelled, direction matching label. Fix, re-render. **Cap 3 iterations**; still unreadable → split across two subsections and say so.

### 4d. Page fit

2.2cm margins → `\textwidth` = **470pt**:

```bash
nix-shell -p poppler-utils --run "pdfinfo docs/diagrams/architecture.pdf | grep 'Page size'"
```

- `scale = 470 / native_width_pt`; require `scale >= 0.5` (native width ≤ ~940pt). Mermaid's default 14px label at scale 0.5 ≈ 5pt — the readability floor
- Width > 940pt, in order: `LR`→`TB`; split; landscape page only for a genuinely wide pipeline (`\usepackage{pdflscape}`, wrap in `\begin{landscape}...\end{landscape}`, `\textwidth` ≈ 700pt)
- Aspect ratio worse than ~3:1 → same fix; prefer `TB`

Delete `/tmp/dd-review*.png`.

## Phase 5: LaTeX

Create/update `docs/system_design.tex`. Preamble verified to compile — no TikZ, no `\resizebox`; diagrams arrive pre-sized:

```latex
\documentclass[11pt,a4paper]{article}
\usepackage[T1]{fontenc}
\usepackage{lmodern}
\usepackage[margin=2.2cm,top=2.0cm]{geometry}
\usepackage{graphicx}
\usepackage{xcolor}
\usepackage{tabularx}
\usepackage{booktabs}
\usepackage{enumitem}
\usepackage{fancyhdr}
\usepackage{titlesec}
\usepackage{microtype}
\usepackage{listings}
\usepackage{float}
\usepackage{caption}
\usepackage{pdflscape}          % only if a wide figure needs it
\definecolor{lcBlue}{HTML}{4A90D9}
\definecolor{lcDark}{HTML}{2C3E50}
\definecolor{lcGrayLt}{HTML}{ECF0F1}
\definecolor{lcBg}{HTML}{FAFBFC}
\usepackage[colorlinks=true,linkcolor=lcBlue,urlcolor=lcBlue]{hyperref}
\graphicspath{{diagrams/}}
\pagestyle{fancy}\fancyhf{}
\fancyhead[L]{\small\color{lcDark}PROJECT NAME}
\fancyhead[R]{\small\color{lcDark}vX.Y}
\fancyfoot[C]{\small\thepage}
\renewcommand{\headrulewidth}{0.4pt}
\newcommand{\titlebanner}[2]{%
  \noindent\colorbox{lcBlue}{\parbox[t][2.8cm][c]{\dimexpr\textwidth-2\fboxsep\relax}{%
    \hspace{0.6cm}\begin{minipage}{\dimexpr\textwidth-2cm\relax}
      {\color{white}\Huge\bfseries #1}\\[0.35em]{\color{white}\large #2}
    \end{minipage}}}\par\vspace{1.2em}}
```

Every figure:

```latex
\begin{figure}[H]\centering
  \includegraphics[width=\textwidth]{architecture.pdf}
  \caption{Container view: how a request reaches storage. Mermaid + ELK.}
  \label{fig:architecture}
\end{figure}
```

Caption names tool + layout engine so the next edit reuses them.

Sections:

1. **Title banner** — `\titlebanner{Project}{System Design Document \textperiodcentered\ vX.Y}`
2. **Table of Contents**
3. **Overview** — 2–3 sentences, CLI/API usage example, tech stack
4. **High-Level Architecture** — container figure + legend table covering every colour, shape, line style in the document's figures
5. **Component Detail** — per component: path in `\texttt{}`, `tabularx` + `booktabs` function/method table, component figure where planned
6. **Data Flow** — figure; failure paths in prose beneath
7. **Data Models / Database Schema** — `classDiagram`/`erDiagram` figures + `tabularx` field table (table: types/constraints; diagram: relationships; don't duplicate the field list into the diagram)
8. **External Dependencies** — package table: versions, purposes
9. **Extension Points** — figure + worked "to add a new X, do Y" list
10. **Known Limitations** — table

All tables: `tabularx` at `\linewidth`.

## Phase 6: Compile

```bash
cd docs && nix-shell -p '(texliveSmall.withPackages (ps: with ps; [
  enumitem titlesec microtype fancyhdr float listings caption booktabs pdflscape ]))' \
  --run "pdflatex -interaction=nonstopmode system_design.tex && \
         pdflatex -interaction=nonstopmode system_design.tex"
```

Run `pdflatex` twice (TOC). Confirm `Output written on system_design.pdf`. `texliveSmall` + those nine packages ≈ 137 MiB vs 2.5 GiB `texliveFull` — holds only while TikZ-free; never reintroduce TikZ, fix the figure.

| Error | Fix |
|---|---|
| `File 'X.sty' not found` | Add `X` to `withPackages` (`tabularx`, `xcolor` ship in `texliveSmall`; not valid attribute names) |
| `Cannot determine size of graphic` | `.pdf` not rendered, or `\graphicspath` not pointing at `diagrams/` |
| Figure text microscopic | 4d violation — re-render, don't shrink |
| `Overfull \hbox` on a table | Switch the offending column to `tabularx`'s `X` |

## Phase 7: Verify Every Page

```bash
nix-shell -p poppler-utils --run "pdfinfo docs/system_design.pdf"          # A4: 595.276 x 841.89
nix-shell -p poppler-utils --run "pdftoppm -png -r 110 docs/system_design.pdf /tmp/dd-page"
```

`Read` **every** page image: no figure clipped or past margins; labels legible at 100% zoom; no truncated table or orphaned caption; legend covers every colour and line style actually present; section numbering matches TOC. Fix failures in the `.mmd`/`.d2` source, re-render (Phase 4) — never by LaTeX scaling. `rm -f /tmp/dd-page-*.png /tmp/dd-review*.png`.

## Phase 8: Summary

Report: `.tex`/`.pdf`/`docs/diagrams/` paths; page count; sections + figures with each one's tool and layout engine; diagrams split at the 3-iteration cap; manual-attention items; update mode: what changed.

## Update Mode Details

1. Read the existing `.tex` for structure
2. Scan the codebase for changes since it was written
3. Preserve user customisations (custom text, added sections, modified descriptions) unless the underlying code changed
4. Selectively: new component → subsection + diagram-source node; removed → delete subsection, node, edges; schema change → field table + `erDiagram`; new dependency → dependency table; version bump → banner + `fancyhead`
5. Edit diagram sources incrementally (`.mmd`/`.d2` are line-editable, diffable; one node = one line); re-render/re-review only touched figures (4b–4d)
6. Recompile, re-verify all pages (Phases 6–7) — a resized diagram reflows the doc

## Toolchain

`mmdc`, `d2`, `rsvg-convert` (never for Mermaid SVG), `structurizr-cli` (C4 → Mermaid for multi-view consistency); `pdflatex` via `nix-shell -p '(texliveSmall.withPackages …)'`; `pdfinfo`/`pdftoppm` via `nix-shell -p poppler-utils`. Diagram tools come from `shared/home/diagrams.nix`; if one is missing, the config needs a rebuild — say so; never fall back to an online renderer or hand-written TikZ.
