---
name: make-envrc
description: Generate .envrc, flake.nix, and .dir-locals.el for a project with direnv + nix-direnv + Emacs integration (eglot, dap-mode).
argument-hint: "[language] e.g. 'python', 'node', 'go' — defaults to auto-detect"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Make Envrc

Generate a direnv dev environment: `flake.nix`, `.envrc`, `.dir-locals.el` (Emacs).

## Phase 1: Detect Project

1. Language: `$ARGUMENTS`, else `pyproject.toml`/`requirements.txt`/`setup.py` → Python; `package.json` → Node.js; `go.mod` → Go; `Cargo.toml` → Rust
2. Package manager: `uv`, `poetry`, `pip`, `npm`, `pnpm`, `yarn`, `cargo`, etc.
3. Python version: `.python-version`, `pyproject.toml` `requires-python`, or `runtime.txt`
4. Needed tools: linters, LSP servers, debuggers, system deps like `chromedriver`
5. Existing `.envrc`/`flake.nix`/`.dir-locals.el`: read first, update — don't overwrite

## Phase 2: Generate flake.nix

`devShells.default` providing:

**Python** — correct nixpkgs Python (e.g. `pkgs.python313`); package manager (`uv`, `poetry`, etc.); `pyright`; detected system deps (e.g. `chromedriver`, `postgresql`, `libffi`); `ipykernel` if Jupyter requested. `shellHook`: set `UV_PYTHON` (uv) or activate the virtualenv; `uv sync`/`poetry install` if venv missing; export `VIRTUAL_ENV`, prepend `.venv/bin` to `PATH`. Jupyter: register a project kernel via `python -m ipykernel install --user --name=<project-name> --display-name="Python (<project-name>)"` unless already registered; export `JUPYTER_NOTEBOOK_ARGS="--ServerApp.disable_check_xsrf=True --ServerApp.token=''"` — prevents 403 XSRF errors and skips token auth from Emacs (`ServerApp.token`, not deprecated `NotebookApp.token`).

**Node.js** — version from `.node-version` or `package.json` engines; package manager (`npm`, `pnpm`, `yarn`); `typescript-language-server`; `shellHook` installs if `node_modules` missing.

**Go** — version matching `go.mod`; `gopls` (LSP); `delve` (debug).

**Other** — same pattern: runtime + LSP + debugger + system deps.

## Phase 3: Generate .envrc

```bash
nix_direnv_watch_file <dependency-file>   # pyproject.toml, package.json, go.mod, etc.
use flake
```

Watching the primary dependency file rebuilds the env when deps change.

## Phase 4: Generate .dir-locals.el

**Python**
```elisp
((python-mode
  . ((dap-python-executable . "<absolute-path-to-project>/.venv/bin/python")
     (eglot-workspace-configuration
      . (:python (:pythonPath ".venv/bin/python"
                  :venvPath "."
                  :venv ".venv"))))))
```

**Node.js / TypeScript**
```elisp
((js-mode
  . ((eval . (setq-local exec-path (cons (expand-file-name "node_modules/.bin" (project-root (project-current))) exec-path))))))
```

**Go** — none needed; `gopls`/`delve` found via PATH from direnv.

Rules:
- `dap-python-executable` MUST be absolute (dap-mode ignores buffer-local values; relative paths resolve to nil)
- `eglot-workspace-configuration` can be relative (pyright resolves from workspace root)
- `debugpy` MUST be in the venv — check, add to dev dependencies if missing

## Phase 5: Activate and Verify

1. Stage `flake.nix` + `flake.lock` with git (nix requires tracked files)
2. `direnv allow`
3. Verify: runtime version; LSP in PATH; debugger works (e.g. `python -m debugpy --version`)
4. Add `.direnv/` to `.gitignore` if missing
5. Summarize created files + manual steps
