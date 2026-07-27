# shared/home/diagrams.nix
# Diagram-as-code toolchain for agent-generated architecture diagrams.
#
# Deliberately CLI-only — no MCP servers. Every tool here is driven from Bash
# so the agent can render, read the resulting image back, and self-correct.
# The `diagram` skill (claude/skills/diagram) is the consumer of these.
#
# Tool selection:
#   mmdc (mermaid-cli) — default. Renders natively on GitHub/in Markdown, and
#                        LLMs write Mermaid more reliably than any other DSL.
#                        Bundles @mermaid-js/layout-elk, so `layout: elk` works
#                        without extra setup. Costs a headless Chromium.
#   d2                 — system architecture. Single Go binary, no browser,
#                        better layout on dense graphs, custom SVG icons.
#   rsvg-convert       — SVG → PNG, so the agent can read D2 output back and
#                        check it visually. Needed because d2's own PNG export
#                        is broken in nixpkgs (it tries to fetch a Playwright
#                        driver at runtime from a dead CDN and 404s), and
#                        because resvg drops D2's base64-embedded fonts,
#                        producing label-less images. librsvg keeps the text.
#   dot (graphviz)     — backing engine for Python `diagrams` and torchview.
#   structurizr-cli    — C4: one model, many consistent views; exports to
#                        Mermaid/PlantUML so artifacts stay portable.
#   diagrams-py        — mingrammer/diagrams (cloud + MLOps icon sets).
#
# Note: structurizr-cli and plantuml are JVM-backed and pull a JRE into the
# closure. Set enableC4 = false to drop both if that cost isn't worth it.
{ lib, pkgs, ... }:

let
  enableC4 = true;

  # Wrapped rather than added to the main python3.withPackages env in
  # packages.nix: a second env exporting bin/python3 would collide in PATH.
  diagramsPython = pkgs.python3.withPackages (ps: [ ps.diagrams ]);
in
{
  home.packages = with pkgs; [
    mermaid-cli   # mmdc — Mermaid → SVG/PNG/PDF (headless Chromium)
    d2            # D2 → SVG (dagre/ELK layouts); use rsvg-convert for PNG
    librsvg       # rsvg-convert — SVG → PNG for the render/read-back loop
    graphviz      # dot — used by Python diagrams, torchview, DOT exports

    (writeShellScriptBin "diagrams-py" ''
      exec ${diagramsPython}/bin/python "$@"
    '')
  ] ++ lib.optionals enableC4 [
    structurizr-cli  # C4 model → Mermaid/PlantUML/DOT/JSON
    plantuml         # renders the C4-PlantUML export target
  ];
}
