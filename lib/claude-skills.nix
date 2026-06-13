# Claude Code skill sources — add new repos here
# Each entry: { src, skillsDir } where skillsDir is a function from src to the skills directory
{ everything-claude-code, cli-anything, ... }:
{
  everything-claude-code = {
    src = everything-claude-code;
    # .agents/skills/<name>/SKILL.md
    findSkills = src: src + "/.agents/skills";
  };
  cli-anything = {
    src = cli-anything;
    # <app>/agent-harness/cli_anything/<app>/skills/SKILL.md
    # Flattened: scan each top-level app dir for the nested skills path
    findSkills = null;  # uses custom scanner in home.nix
  };
}
