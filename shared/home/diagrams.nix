# shared/home/diagrams.nix
# Diagram-as-code toolchain for the `diagram` skill (claude/skills/diagram).
# Deliberately CLI-only, no MCP: the agent renders, reads the image back, and
# self-corrects entirely from Bash.
{ lib, pkgs, ... }:

let
  # structurizr-cli and plantuml are JVM-backed; set false to drop the JRE.
  enableC4 = true;

  # Wrapped rather than merged into packages.nix' python3.withPackages: a second
  # env exporting bin/python3 would collide in PATH.
  diagramsPython = pkgs.python3.withPackages (ps: [ ps.diagrams ]);
in
{
  home.packages = with pkgs; [
    mermaid-cli   # default: LLMs write Mermaid most reliably. Costs a Chromium.
    d2
    # d2's own PNG export is broken in nixpkgs and resvg drops D2's embedded
    # fonts, so rsvg-convert is what turns SVG into readable-back PNG.
    librsvg
    graphviz      # dot — backs Python diagrams and torchview

    (writeShellScriptBin "diagrams-py" ''
      exec ${diagramsPython}/bin/python "$@"
    '')
  ] ++ lib.optionals enableC4 [
    structurizr-cli  # C4 model → Mermaid/PlantUML/DOT/JSON
    plantuml
  ];
}
