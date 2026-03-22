---
name: design-doc
description: Generate or update a Lucidchart-style LaTeX system design document for the current project. Scans the codebase, produces TikZ diagrams, compiles to PDF, and verifies all content fits within page boundaries.
argument-hint: "[docs/system_design.tex] path to existing doc to update, or leave blank to create new"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# System Design Document Generator

Generate a professional LaTeX system design document with Lucidchart-style TikZ diagrams for any codebase. Supports both creation and incremental updates.

## When to Activate

- User asks for a system design document, architecture diagram, or design doc
- User wants to update an existing design doc after code changes
- User asks for a visual overview of the project architecture

## Phase 1: Determine Mode

1. Check if `$ARGUMENTS` specifies a path to an existing `.tex` file.
2. If no argument, search for `docs/system_design.tex` or `docs/*.tex` in the project.
3. **Create mode:** No existing doc found — proceed to Phase 2.
4. **Update mode:** Existing doc found — proceed to Phase 2 but diff against current codebase to identify what changed and only modify affected sections.

## Phase 2: Plan the Scan

Before scanning, build a plan of what segments the document needs to cover. This plan drives parallelised research in Phase 3.

1. **Quick survey:** Use Glob and Grep to get a high-level picture of the repo:
   - `**/*.py`, `**/*.ts`, `**/*.go`, `**/*.rs`, `**/*.java` — identify the primary language
   - Config files: `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, `pom.xml`
   - Directory tree (`ls src/` or equivalent) to identify top-level modules/packages
2. **Identify segments:** Based on the survey, build a list of segments to document. Each segment maps to a future document section. Typical segments:
   - **Project metadata** — language, framework, name, version
   - **Entry points** — CLI commands, main functions, server startup, route definitions
   - One segment **per architectural layer** discovered (e.g. "API routes", "service layer", "data access", "sources")
   - **Data models** — classes, dataclasses, structs, schemas, ORM models
   - **Database schema** — tables, columns, constraints, relationships
   - **External integrations** — APIs, services, message queues, caches
   - **Configuration** — env vars, config files, feature flags
3. **Write the plan as a todo list** using TodoWrite, with one task per segment. This lets the user see and steer what will be documented before the heavy scanning begins.

For **update mode**, also add these tasks:
- Diff existing doc against current codebase to find new/removed/changed components
- Identify sections that need updating vs sections that are still accurate

## Phase 3: Scan the Codebase (Parallelised)

Launch **parallel Explore agents** — one per segment from the Phase 2 plan. Each agent is given a focused scope so it can run independently and return structured findings.

### Agent dispatch rules

- **Independent segments run in parallel.** For example, these can all run at the same time:
  - Agent 1: Project metadata + configuration (config files, env vars)
  - Agent 2: Entry points + CLI/API surface (main files, argparse/route definitions)
  - Agent 3: Data models + database schema (ORM models, migrations, dataclasses)
  - Agent 4: External integrations (HTTP clients, API calls, message queues)
  - Agent 5: Per-module deep dive (one agent per major module/package if the project is large)

- **Data flow and extension points run after** the parallel agents return, because they depend on understanding all components first. Launch these as a second parallel batch:
  - Agent A: Data flow analysis (trace input → processing → storage → output using findings from prior agents)
  - Agent B: Extension points (identify interfaces, abstract classes, plugin patterns)

### Agent prompt template

Each agent should receive a prompt like:

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

### Merging results

After all agents complete:
1. Merge findings into a single structured outline
2. Resolve cross-references (e.g. "SourceA produces Deal objects" + "Deal is defined in base.py")
3. Identify the main data flow path through the system
4. Mark each Phase 2 todo as completed

## Phase 3: Generate LaTeX Document

Create `docs/system_design.tex` (or update existing) using the template structure below.

### Required LaTeX Packages

```latex
geometry, tikz, xcolor, tabularx, booktabs, enumitem, fancyhdr,
titlesec, hyperref, fontenc (T1), lmodern, microtype, listings, float
```

### Required TikZ Libraries

```latex
positioning, arrows.meta, shapes.geometric, shapes.multipart,
shapes.symbols, fit, backgrounds, calc, shadows,
decorations.pathreplacing
```

### Lucidchart Colour Palette

Always define these colours for consistent styling:

| Name | Hex | Usage |
|------|-----|-------|
| `lcBlue` | `#4A90D9` | Primary components, core logic |
| `lcBlueLt` | `#D6E4F0` | Light fill for primary components |
| `lcGreen` | `#5CB85C` | Abstractions, interfaces, base classes |
| `lcGreenLt` | `#DFF0D8` | Light fill for abstractions |
| `lcOrange` | `#F0AD4E` | External services, output, warnings |
| `lcOrangeLt` | `#FCF8E3` | Light fill for external services |
| `lcPurple` | `#9B59B6` | Database, storage, persistence |
| `lcPurpleLt` | `#EBE0F0` | Light fill for database components |
| `lcRed` | `#D9534F` | Concrete implementations, data sources |
| `lcRedLt` | `#F2DEDE` | Light fill for implementations |
| `lcGray` | `#7F8C8D` | Labels, arrows, secondary elements |
| `lcGrayLt` | `#ECF0F1` | Background fills, group boxes |
| `lcDark` | `#2C3E50` | Text colour |
| `lcBg` | `#FAFBFC` | Code listing background |

### TikZ Node Styles

Define these reusable styles in a `\tikzset` block:

- **`comp`** — Primary component box: rounded corners=6pt, drop shadow, parameterised border colour
- **`pill`** — Smaller sub-component: rounded corners=4pt, no shadow
- **`db`** — Database cylinder: `shape border rotate=90`, purple fill. Do NOT use `cylinder uses custom fill` (causes TeX capacity overflow with pdflatex)
- **`arrow`** — Stealth arrowhead, gray, 0.9pt line width
- **`arrlbl`** — Small italic label on arrows, white background
- **`groupbox`** — Dashed rounded rectangle for grouping related components
- **`extcloud`** — Cloud shape for external services. IMPORTANT: Name this `extcloud`, NOT `cloud` (naming it `cloud` conflicts with the TikZ `cloud` shape and causes infinite recursion)

### Document Sections

Generate these sections, adapting content to the actual project:

1. **Title block** — Blue banner using `\begin{tikzpicture}[remember picture, overlay]` with project name and version
2. **Table of Contents**
3. **Overview** — 2-3 sentence description, CLI/API usage example, tech stack summary
4. **High-Level Architecture** — TikZ diagram showing all major components, their relationships, data flow arrows, external services as clouds, database as cylinder. Wrap in `\resizebox{\textwidth}{!}{...}` to prevent overflow
5. **Component Detail** — Subsection per component with:
   - File path in `\texttt{}`
   - Function/method table using `tabularx` with `booktabs` rules
   - For data models: UML-style `rectangle split` nodes showing fields and types
   - For database: Schema card showing columns, types, and constraints
6. **Data Flow** — Flowchart with step nodes and decision diamonds showing how data moves through the system
7. **External Dependencies** — Table of packages/libraries with versions and purposes
8. **Extension Points** — Diagram showing how to add new implementations (interface + existing + dashed "new" node)
9. **Known Limitations** — Table of areas and their limitations

### Diagram Sizing Rules

These rules prevent content from overflowing the page:

1. **Always wrap architecture diagrams** in `\resizebox{\textwidth}{!}{...}` so they auto-scale to page width
2. **Cloud nodes:** Use `minimum width=2.4cm, minimum height=1.2cm` (not larger)
3. **Node distances:** Use `1.1cm and 1.4cm` as default, not larger
4. **Component minimum widths:** 3.0-3.6cm for regular nodes, up to 8cm for spanning nodes
5. **Flowchart step nodes:** Use `text width=10cm` maximum for full-width, `7cm` for left-branch, `4cm` for right-branch
6. **Class diagram nodes:** Use `minimum width=5.5cm` maximum
7. **Tables:** Always use `tabularx` with `\linewidth` to auto-fit page width

## Phase 4: Compile to PDF

1. Compile using nix-shell with texlive:
   ```bash
   cd docs && nix-shell -p texliveFull --run "pdflatex -interaction=nonstopmode system_design.tex && pdflatex -interaction=nonstopmode system_design.tex"
   ```
   Run pdflatex **twice** so the table of contents populates correctly.

2. Verify compilation succeeded by checking for `Output written on system_design.pdf` in the output.

3. If compilation fails, read the error from the last 30 lines of output and fix:
   - **Missing package:** Switch from `texliveSmall` to `texliveFull`
   - **`cloud` name conflict:** Rename style to `extcloud`
   - **`cylinder uses custom fill` overflow:** Remove that option, use plain `fill=`
   - **Undefined control sequence in TikZ:** Check library imports
   - **Overfull hbox:** Add `\resizebox` wrapper or reduce node sizes

## Phase 5: Visual Verification

After successful compilation, verify the PDF renders correctly:

1. Check PDF metadata:
   ```bash
   nix-shell -p poppler-utils --run "pdfinfo docs/system_design.pdf"
   ```
   Confirm page count and page size (should be A4: 595.276 x 841.89 pts).

2. Render pages to images and inspect each one:
   ```bash
   nix-shell -p poppler-utils --run "pdftoppm -png -r 150 docs/system_design.pdf /tmp/design-doc-page"
   ```
   Then use the Read tool to visually inspect each page image:
   - Check that no diagrams are clipped or extend beyond page margins
   - Check that text is readable and tables are not truncated
   - Check that TikZ arrows connect to the correct nodes

3. **If any diagram overflows the page:**
   - Add or adjust `\resizebox{\textwidth}{!}{...}` wrapper
   - Reduce `node distance`, `minimum width`, or `minimum height` values
   - Move external clouds from side-placement to above/below placement
   - Recompile and re-verify (repeat Phase 4-5)

4. Clean up temporary verification images:
   ```bash
   rm -f /tmp/design-doc-page-*.png
   ```

## Phase 6: Summary

Report to the user:
- Path to the generated `.tex` and `.pdf` files
- Page count
- List of sections and diagrams included
- Any known issues or manual adjustments needed
- For update mode: what changed vs the previous version

## Update Mode Details

When updating an existing document:

1. **Read the existing `.tex` file** to understand current structure
2. **Scan the codebase** for changes since the doc was written
3. **Preserve user customisations:** Don't overwrite sections the user may have hand-edited unless the underlying code changed. Look for custom text, additional sections, or modified descriptions.
4. **Update selectively:**
   - New components → add new subsections and update architecture diagram
   - Removed components → delete their sections and remove from diagrams
   - Changed schemas → update the schema card and field tables
   - New dependencies → add to dependency table
   - Version bumps → update title block and header
5. **Rebuild all TikZ diagrams** from scratch based on current codebase state (diagrams are hard to partially update)
6. **Recompile and re-verify** (Phases 4-5)
