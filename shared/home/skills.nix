# shared/home/skills.nix
# Claude Code skill scanning and provisioning
{ lib, pkgs, claudeSkills ? {}, ... }:

let
  # Scan claude/skills/ (local) and build home.file entries for each skill directory
  skillsDir = ../../claude/skills;
  skillNames = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir));
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
      agentsSkills = if hasAgentsDir
        then builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir agentsDir))
        else [];
      agentsEntries = mkSkillEntries prefix agentsDir agentsSkills;

      # Layout 2: <app>/agent-harness/cli_anything/<app>/skills/SKILL.md
      topDirs = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir src));
      cliAnythingSkills = builtins.filter (app:
        builtins.pathExists (src + "/${app}/agent-harness/cli_anything/${app}/skills")
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

  # Scan skills bundled in the ruflo npm package
  rufloPackage = pkgs.callPackage ../../pkgs/ruflo {};
  rufloSkillsDir = "${rufloPackage}/lib/node_modules/ruflo/node_modules/@claude-flow/cli/.claude/skills";
  rufloSkillNames = builtins.filter (name:
    (builtins.readDir rufloSkillsDir).${name} == "directory"
  ) (builtins.attrNames (builtins.readDir rufloSkillsDir));
  rufloSkillFiles = mkSkillEntries "ruflo" rufloSkillsDir rufloSkillNames;
in
{
  home.file = localSkillFiles // externalSkillFiles // rufloSkillFiles;
}
