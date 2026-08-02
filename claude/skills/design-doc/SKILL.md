---
name: design-doc
description: Generate or update a LaTeX system design document for the current project. Scans the codebase with parallel agents, builds every diagram as code via the `diagram` skill's CLI toolchain (Mermaid/D2/Structurizr), embeds them as vector PDF, compiles, and verifies every page visually.
argument-hint: "[docs/system_design.tex] path to existing doc to update, or leave blank to create new"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# System Design Document Generator

Produce a professional LaTeX system design document for any codebase. Supports creation and
incremental updates.

**Division of labour with the `diagram` skill:** this skill owns the *document* — scanning, prose,
tables, typography, compilation, page-fit verification. It owns **no diagram syntax**. Every figure
is built by the `diagram` skill's toolchain and embedded as a vector PDF.

> Do not hand-write TikZ diagrams. The old TikZ path is gone: it could not be visually checked before
> compiling, it pulled in `texliveFull` (2.5 GiB), and its output was not reusable outside the PDF.
> Diagrams-as-code render in ~1s, get reviewed as an image before they reach the page, and the same
> source also serves the README.

**Read `~/.claude/skills/diagram/SKILL.md` before Phase 4.** Its rules — tool choice, node budget,
labelled arrows, the render/read-back loop — apply verbatim. This file only adds what is specific to
print: the palette bridge, PDF export, and page sizing.

## When to Activate

- User asks for a system design document or a visual overview of the project architecture
- User wants to update an existing design doc after code changes

For a single standalone diagram (README, PR, chat), use `diagram` directly — not this skill.

## Phase 1: Determine Mode

1. Check if `$ARGUMENTS` specifies a path to an existing `.tex` file.
2. If no argument, search for `docs/system_design.tex` or `docs/*.tex` in the project.
3. **Create mode:** no existing doc found — proceed to Phase 2.
4. **Update mode:** existing doc found — proceed to Phase 2, but diff against the current codebase
   and modify only affected sections. See *Update Mode Details* at the end.

## Phase 2: Plan the Scan and the Diagram Set

### 2a. Survey

- `**/*.py`, `**/*.ts`, `**/*.go`, `**/*.rs`, `**/*.java` — identify the primary language
- Config files: `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, `pom.xml`, `flake.nix`
- Directory tree (`ls src/` or equivalent) to identify top-level modules

### 2b. Identify segments

Each segment maps to a document section and to one research agent in Phase 3. Typical segments:

- **Project metadata** — language, framework, name, version
- **Entry points** — CLI commands, main functions, server startup, route definitions
- One segment **per architectural layer** discovered (API routes, service layer, data access, …)
- **Data models** — classes, dataclasses, structs, schemas, ORM models
- **Database schema** — tables, columns, constraints, relationships
- **External integrations** — APIs, services, message queues, caches
- **Configuration** — env vars, config files, feature flags

### 2c. Plan the diagram set — *before* any scanning

Decide which figures the document needs and **what single question each one answers**. This is the
`diagram` skill's "constrain before generating" step, applied at document scope. Skipping it is what
produces a doc with one unreadable 60-node megadiagram.

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

Rules carried over from `diagram`, with print-specific tightening:

- **One abstraction level per diagram.** Never mix "Postgres" with `UserRepository.findById`.
- **Node budget: 12–15 for print** (the skill's 15–20 assumes a screen; A4 is narrower). Past that,
  split into a container view plus per-subsystem component views — you have sections for both.
- **Prefer `TB` in a portrait document.** `LR` graphs become wide, and width is what shrinks text
  when the figure is scaled to `\textwidth` (see the sizing budget in Phase 4d). Reserve `LR` for
  genuine pipelines, and keep those short.
- **Draw the failure edges.** Generated diagrams are reliably weakest here. If a component can time
  out, retry, or fall back, that edge belongs in the Data Flow figure.

### 2d. Write the plan as a todo list

One task per segment, plus one per planned diagram. This lets the user steer scope before the heavy
scanning begins.

For **update mode**, also add: diff existing doc against current codebase; identify which sections
and which diagrams are stale.

## Phase 3: Scan the Codebase (Parallelised)

Launch **parallel Explore agents** — one per segment from Phase 2b.

### Agent dispatch rules

- **Independent segments run in parallel**, in a single message. For example:
  - Agent 1: Project metadata + configuration
  - Agent 2: Entry points + CLI/API surface
  - Agent 3: Data models + database schema
  - Agent 4: External integrations
  - Agent 5+: Per-module deep dive (one per major module on large projects)
- **Data flow and extension points run after** the first batch returns, since they depend on knowing
  all components. Launch these as a second parallel batch:
  - Agent A: Data flow (trace input → processing → storage → output)
  - Agent B: Extension points (interfaces, abstract classes, plugin patterns)

### Agent prompt template

> Explore the project at `{project_root}`. Focus specifically on **{segment_name}**.
> Read all relevant source files completely. Return:
> 1. File paths and their purposes
> 2. Key classes/functions with signatures and brief descriptions
> 3. Relationships to other components (imports, calls, inheritance)
> 4. Any notable patterns, constraints, or quirks
>
> For data models: list every field with its type and constraints.
> For database schemas: list every table, column, type, and constraint.
> For external integrations: capture URLs, auth methods, timeouts, error handling.
> Note every failure mode you find — timeouts, retries, fallbacks — with the condition that
> triggers it. These become edges in the data-flow diagram.

### Merging results

1. Merge findings into a single structured outline
2. Resolve cross-references ("SourceA produces Deal objects" + "Deal is defined in base.py")
3. Identify the main data flow path, and its failure paths
4. Confirm the Phase 2c diagram set still fits what was found — add, drop, or split figures now
5. Mark the Phase 2 todos completed

## Phase 4: Build the Diagrams

All sources live in `docs/diagrams/` and are **committed** — the source is the artifact, the PDF is
a build output that happens to also be committed because the `.tex` needs it.

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

The document's colour identity lives in the diagram sources, not in LaTeX. Use exactly these
semantics so every figure and the `.tex` agree.

| Role | Fill | Stroke | Used for |
|---|---|---|---|
| Primary | `#D6E4F0` | `#4A90D9` | Core components, main logic |
| Abstraction | `#DFF0D8` | `#5CB85C` | Interfaces, base classes, protocols |
| External | `#FCF8E3` | `#F0AD4E` | Third-party services, external actors |
| Storage | `#EBE0F0` | `#9B59B6` | Databases, caches, queues, files |
| Implementation | `#F2DEDE` | `#D9534F` | Concrete impls, data sources |
| Text | — | `#2C3E50` | All label text |

**Mermaid** — paste this block into every flowchart:

```
classDef primary  fill:#D6E4F0,stroke:#4A90D9,stroke-width:1.5px,color:#2C3E50
classDef abstract fill:#DFF0D8,stroke:#5CB85C,stroke-width:1.5px,color:#2C3E50
classDef external fill:#FCF8E3,stroke:#F0AD4E,stroke-width:1.5px,color:#2C3E50
classDef storage  fill:#EBE0F0,stroke:#9B59B6,stroke-width:1.5px,color:#2C3E50
classDef impl     fill:#F2DEDE,stroke:#D9534F,stroke-width:1.5px,color:#2C3E50
```

Apply with `node["Label"]:::primary`.

**D2** — `style.fill: "#D6E4F0"; style.stroke: "#4A90D9"`, same pairs.

Every colour used must appear in the document's legend table (Phase 5). A colour with no legend
entry is a defect.

### 4b. Render for print

**Mermaid — export PDF directly from `mmdc`. Never route Mermaid through `rsvg-convert`:**
librsvg cannot render the `foreignObject` HTML labels Mermaid emits, and silently drops every node
label, producing a diagram of empty boxes. `htmlLabels: false` only half-fixes it (node labels stay
missing and spaces collapse). `mmdc`'s own Chromium export is correct.

```bash
# LaTeX artifact — vector, real text. --pdfFit crops the page to the diagram
# (600x77pt) instead of padding it to US Letter with whitespace.
mmdc -i docs/diagrams/architecture.mmd -o docs/diagrams/architecture.pdf --pdfFit -b white

# Self-review raster
mmdc -i docs/diagrams/architecture.mmd -o /tmp/dd-review.png -s 2 -b white
```

**D2** — real SVG text, so librsvg works and is the only PDF route:

```bash
d2 --layout elk docs/diagrams/architecture.d2 docs/diagrams/architecture.svg
rsvg-convert -f pdf -o docs/diagrams/architecture.pdf docs/diagrams/architecture.svg
rsvg-convert -z 2  -o /tmp/dd-review.png            docs/diagrams/architecture.svg
```

**Structurizr** — export to Mermaid, then follow the Mermaid path:

```bash
structurizr-cli export -workspace docs/workspace.dsl -format mermaid -output docs/diagrams/
```

A non-zero exit is a syntax error: read the message, fix the source, re-render. Never embed a
diagram that failed to render.

### 4c. Read the image back

`Read` each review PNG and check it against the `diagram` skill's Step 5 checklist — overlapping
text, removable edge crossings, aspect ratio, legibility, title, legend, **every arrow labelled**,
arrow direction matching its label. Fix and re-render. **Cap at 3 iterations**; if it still doesn't
read, the diagram is too complex — split it across two document subsections and say so.

### 4d. Check it survives the page

A figure that reads fine at native size can become illegible once scaled to `\textwidth`. With the
2.2cm margins in the Phase 5 template, `\textwidth` is **470pt**, so:

```bash
nix-shell -p poppler-utils --run "pdfinfo docs/diagrams/architecture.pdf | grep 'Page size'"
```

- `scale = 470 / native_width_pt`. **Require `scale >= 0.5`** — i.e. native width ≤ ~940pt. Mermaid's
  default 14px label at scale 0.5 lands near 5pt on paper, which is the floor for readability.
- Native width > 940pt → in order of preference: switch `LR` to `TB`; split the diagram; or, only for
  a genuinely wide pipeline, put it on a landscape page (`\usepackage{pdflscape}`, wrap the figure in
  `\begin{landscape}...\end{landscape}` — `\textwidth` there is ~700pt).
- Aspect ratio worse than ~3:1 is the same problem wearing a hat. Prefer `TB`.

Delete `/tmp/dd-review*.png` when done.

## Phase 5: Generate the LaTeX Document

Create or update `docs/system_design.tex`. This preamble is verified to compile — it uses no TikZ
and no `\resizebox` gymnastics, because the diagrams arrive pre-sized.

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

Every figure is included the same way:

```latex
\begin{figure}[H]\centering
  \includegraphics[width=\textwidth]{architecture.pdf}
  \caption{Container view: how a request reaches storage. Mermaid + ELK.}
  \label{fig:architecture}
\end{figure}
```

Name the tool and layout engine in the caption, so the next edit uses the same one.

### Document sections

1. **Title banner** — `\titlebanner{Project}{System Design Document \textperiodcentered\ vX.Y}`
2. **Table of Contents**
3. **Overview** — 2–3 sentence description, CLI/API usage example, tech stack summary
4. **High-Level Architecture** — the container-view figure, **followed by the legend table** mapping
   every colour, shape, and line style used across the document's figures
5. **Component Detail** — a subsection per component: file path in `\texttt{}`, a `tabularx` +
   `booktabs` table of functions/methods, and the component-view figure where one was planned
6. **Data Flow** — the data-flow figure, with failure paths called out in prose beneath it
7. **Data Models / Database Schema** — the `classDiagram` / `erDiagram` figures, plus a `tabularx`
   field table (the table carries types and constraints; the diagram carries relationships — do not
   duplicate the full field list into the diagram)
8. **External Dependencies** — table of packages/libraries with versions and purposes
9. **Extension Points** — the extension figure plus a worked "to add a new X, do Y" list
10. **Known Limitations** — table of areas and their limitations

Tables always use `tabularx` at `\linewidth` so they fit the page.

## Phase 6: Compile

```bash
cd docs && nix-shell -p '(texliveSmall.withPackages (ps: with ps; [
  enumitem titlesec microtype fancyhdr float listings caption booktabs pdflscape ]))' \
  --run "pdflatex -interaction=nonstopmode system_design.tex && \
         pdflatex -interaction=nonstopmode system_design.tex"
```

Run `pdflatex` twice so the table of contents populates. Confirm
`Output written on system_design.pdf` appears.

`texliveSmall` plus those nine packages is ~137 MiB, versus 2.5 GiB for `texliveFull`. That only
holds while the document stays TikZ-free — do not reintroduce TikZ to save a figure; fix the figure.

Common failures:

| Error | Fix |
|---|---|
| `File 'X.sty' not found` | Add `X` to the `withPackages` list (note: `tabularx` and `xcolor` ship in `texliveSmall` and are not valid attribute names) |
| `Cannot determine size of graphic` | The `.pdf` wasn't rendered, or `\graphicspath` doesn't point at `diagrams/` |
| Figure text microscopic | Phase 4d violation — re-render, don't shrink the caption |
| `Overfull \hbox` on a table | Switch the offending column to `tabularx`'s `X` |

## Phase 7: Verify Every Page Visually

```bash
nix-shell -p poppler-utils --run "pdfinfo docs/system_design.pdf"          # A4: 595.276 x 841.89
nix-shell -p poppler-utils --run "pdftoppm -png -r 110 docs/system_design.pdf /tmp/dd-page"
```

`Read` **every** page image and check:

- No figure clipped or past the margins
- Every figure's labels legible at 100% zoom
- No table truncated; no orphaned caption
- The legend table accounts for every colour and line style that actually appears
- Section numbering and TOC page numbers agree

A figure that fails here is fixed in its `.mmd`/`.d2` source and re-rendered (Phase 4), never by
scaling it down in LaTeX. Then clean up: `rm -f /tmp/dd-page-*.png /tmp/dd-review*.png`.

## Phase 8: Summary

Report:

- Paths to the `.tex`, the `.pdf`, and the `docs/diagrams/` sources
- Page count
- Sections and figures included, and which tool + layout engine built each figure
- Any diagram that hit the 3-iteration cap and was split
- Anything needing manual attention
- Update mode: what changed versus the previous version

## Update Mode Details

1. **Read the existing `.tex`** to understand its current structure
2. **Scan the codebase** for changes since the doc was written
3. **Preserve user customisations** — don't overwrite hand-edited prose unless the underlying code
   changed. Look for custom text, added sections, modified descriptions.
4. **Update selectively:**
   - New components → new subsections; add the node to the affected diagram source
   - Removed components → delete the subsection; remove the node and its edges
   - Changed schemas → update the field table and the `erDiagram`
   - New dependencies → add to the dependency table
   - Version bump → update the banner and the `fancyhead`
5. **Edit diagram sources incrementally.** This is the main advantage over the old TikZ approach:
   `.mmd`/`.d2` sources are line-editable and diffable, so adding one node is a one-line change, not
   a rebuild. Re-render and re-review only the figures you touched (Phase 4b–4d).
6. **Recompile and re-verify all pages** (Phases 6–7) — a diagram that changed size reflows the doc.

## Toolchain Reference

| Command | Role here |
|---|---|
| `mmdc` | Mermaid → PDF (`--pdfFit`) for embedding, PNG (`-s 2`) for review |
| `d2` | D2 → SVG (`--layout elk`) |
| `rsvg-convert` | D2 SVG → PDF / PNG. **Never for Mermaid SVG** |
| `structurizr-cli` | C4 model → Mermaid, for multi-view consistency |
| `pdflatex` | via `nix-shell -p '(texliveSmall.withPackages …)'` |
| `pdfinfo` / `pdftoppm` | via `nix-shell -p poppler-utils` — sizing and page review |

The diagram tools come from `shared/home/diagrams.nix`. If one is missing, the config needs a
rebuild — say so rather than falling back to an online renderer or hand-written TikZ.
