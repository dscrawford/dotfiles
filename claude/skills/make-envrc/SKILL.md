---
name: make-envrc
description: Generate .envrc, flake.nix, and .dir-locals.el for a project with direnv + nix-direnv + Emacs integration (eglot, dap-mode).
argument-hint: "[language] e.g. 'python', 'node', 'go' — defaults to auto-detect"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Make Envrc

Generate a complete direnv development environment for the current project: `flake.nix`, `.envrc`, and `.dir-locals.el` for Emacs.

## Phase 1: Detect Project

1. If `$ARGUMENTS` specifies a language, use that. Otherwise auto-detect:
   - `pyproject.toml` / `requirements.txt` / `setup.py` → Python
   - `package.json` → Node.js
   - `go.mod` → Go
   - `Cargo.toml` → Rust
2. Detect the package manager: `uv`, `poetry`, `pip`, `npm`, `pnpm`, `yarn`, `cargo`, etc.
3. Detect the Python version from `.python-version`, `pyproject.toml` `requires-python`, or `runtime.txt`.
4. Identify tools the project needs (linters, LSP servers, debuggers, system deps like `chromedriver`).
5. Check if files already exist (`.envrc`, `flake.nix`, `.dir-locals.el`) — if so, read them first and update rather than overwrite.

## Phase 2: Generate flake.nix

Create `flake.nix` with a `devShells.default` that provides:

### Python projects
- The correct Python version from nixpkgs (e.g. `pkgs.python313`)
- Package manager (`uv`, `poetry`, etc.)
- LSP server (`pyright`)
- Any system dependencies detected (e.g. `chromedriver`, `postgresql`, `libffi`)
- If Jupyter notebook support is requested: add `ipykernel` to the devShell packages
- `shellHook` that:
  - Sets `UV_PYTHON` (for uv projects) or activates the virtualenv
  - Runs `uv sync` / `poetry install` if the venv doesn't exist
  - Exports `VIRTUAL_ENV` and prepends `.venv/bin` to `PATH`
  - If Jupyter support: registers a project-specific kernel via `python -m ipykernel install --user --name=<project-name> --display-name="Python (<project-name>)"` (only if the kernel isn't already registered)

### Node.js projects
- Node.js version from `.node-version` or `package.json` engines
- Package manager (`npm`, `pnpm`, `yarn`)
- `typescript-language-server` for LSP
- `shellHook` that runs install if `node_modules` is missing

### Go projects
- Go version matching `go.mod`
- `gopls` for LSP
- `delve` for debugging

### Other languages
- Follow the same pattern: language runtime + LSP + debugger + system deps

## Phase 3: Generate .envrc

Create `.envrc` with:

```bash
nix_direnv_watch_file <dependency-file>   # pyproject.toml, package.json, go.mod, etc.
use flake
```

Watch the primary dependency file so the environment rebuilds when deps change.

## Phase 4: Generate .dir-locals.el

Create `.dir-locals.el` for Emacs integration.

### Python projects
```elisp
((python-mode
  . ((dap-python-executable . "<absolute-path-to-project>/.venv/bin/python")
     (eglot-workspace-configuration
      . (:python (:pythonPath ".venv/bin/python"
                  :venvPath "."
                  :venv ".venv"))))))
```

### Node.js / TypeScript projects
```elisp
((js-mode
  . ((eval . (setq-local exec-path (cons (expand-file-name "node_modules/.bin" (project-root (project-current))) exec-path))))))
```

### Go projects
No `.dir-locals.el` needed — `gopls` and `delve` are found via PATH from direnv.

**Key rules for .dir-locals.el:**
- `dap-python-executable` MUST be an absolute path (dap-mode ignores buffer-local values, and relative paths resolve to nil)
- `eglot-workspace-configuration` can use relative paths (pyright resolves them from workspace root)
- `debugpy` MUST be installed in the venv — check and add it to dev dependencies if missing

## Phase 5: Activate and Verify

1. Stage `flake.nix` and `flake.lock` with git (nix requires tracked files)
2. Run `direnv allow`
3. Verify the environment:
   - Language runtime is correct version
   - LSP server is in PATH
   - Debugger works (e.g. `python -m debugpy --version`)
4. Add `.direnv/` to `.gitignore` if not already there
5. Print a summary of what was created and any manual steps needed
