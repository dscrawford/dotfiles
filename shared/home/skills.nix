# shared/home/skills.nix
# Claude Code skill scanning and provisioning
# Only whitelisted skills are installed to keep the system prompt small (~130K+ tokens saved).
# To re-enable a skill, add its name to the appropriate whitelist below.
{ lib, pkgs, claudeSkills ? {}, ... }:

let
  # Whitelist of skills to install (all others are ignored)
  enabledLocalSkills = [
    "deep-research"
    "design-doc"
    "make-envrc"
    "update-readme"
  ];

  enabledExternalSkills = [
    # everything-claude-code
    "everything-claude-code:api-design"
    "everything-claude-code:coding-standards"
    "everything-claude-code:e2e-testing"
    "everything-claude-code:investor-materials"
    "everything-claude-code:investor-outreach"
    "everything-claude-code:market-research"
    "everything-claude-code:security-review"
    "everything-claude-code:strategic-compact"
    "everything-claude-code:tdd-workflow"
    "everything-claude-code:verification-loop"
    # cli-anything
    "cli-anything:adguardhome"
    "cli-anything:audacity"
    "cli-anything:blender"
    "cli-anything:browser"
    "cli-anything:confluence"
    "cli-anything:jira"
    "cli-anything:ollama"
    "cli-anything:slack"
  ];

  isEnabled = whitelist: name: builtins.elem name whitelist;

  # Scan claude/skills/ (local) and build home.file entries for each skill directory
  skillsDir = ../../claude/skills;
  skillNames = builtins.filter (isEnabled enabledLocalSkills)
    (builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir)));
  localSkillFiles = lib.listToAttrs (builtins.concatMap (skill:
    let
      dir = skillsDir + "/${skill}";
      files = builtins.attrNames (builtins.readDir dir);
    in map (file: lib.nameValuePair
      ".claude/skills/${skill}/${file}"
      { source = dir + "/${file}"; force = true; }
    ) files
  ) skillNames);

  # Scan external Claude skill sources (from flake inputs)
  # Supports two layouts:
  #   1. .agents/skills/<name>/SKILL.md  (everything-claude-code)
  #   2. <app>/agent-harness/cli_anything/<app>/skills/SKILL.md  (cli-anything)
  mkSkillEntries = prefix: dir: skillDirs:
    lib.listToAttrs (builtins.concatMap (skill:
      let
        skillDir = dir + "/${skill}";
        files = builtins.attrNames (lib.filterAttrs (_: type: type == "regular") (builtins.readDir skillDir));
      in map (file: lib.nameValuePair
        ".claude/skills/${prefix}:${skill}/${file}"
        { source = skillDir + "/${file}"; force = true; }
      ) files
    ) skillDirs);

  scanExternalSkills = prefix: src:
    let
      # Layout 1: .agents/skills/<name>/SKILL.md
      agentsDir = src + "/.agents/skills";
      hasAgentsDir = builtins.pathExists agentsDir;
      agentsSkills = builtins.filter (name: isEnabled enabledExternalSkills "${prefix}:${name}")
        (if hasAgentsDir
         then builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir agentsDir))
         else []);
      agentsEntries = mkSkillEntries prefix agentsDir agentsSkills;

      # Layout 2: <app>/agent-harness/cli_anything/<app>/skills/SKILL.md
      topDirs = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir src));
      cliAnythingSkills = builtins.filter (app:
        isEnabled enabledExternalSkills "${prefix}:${app}"
        && builtins.pathExists (src + "/${app}/agent-harness/cli_anything/${app}/skills")
      ) topDirs;
      cliAnythingEntries = lib.listToAttrs (builtins.concatMap (app:
        let
          skillDir = src + "/${app}/agent-harness/cli_anything/${app}/skills";
          files = builtins.attrNames (lib.filterAttrs (_: type: type == "regular") (builtins.readDir skillDir));
        in map (file: lib.nameValuePair
          ".claude/skills/${prefix}:${app}/${file}"
          { source = skillDir + "/${file}"; force = true; }
        ) files
      ) cliAnythingSkills);
    in agentsEntries // cliAnythingEntries;

  externalSkillFiles = lib.concatMapAttrs (prefix: entry: scanExternalSkills prefix entry.src) claudeSkills;

in
{
  home.file = localSkillFiles // externalSkillFiles;
}
