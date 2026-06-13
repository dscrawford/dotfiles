# shared/home/git.nix
# Git configuration
{ gitUser ? null, ... }:

{
  programs.git = {
    enable = true;
    signing.format = null;
    settings = {
      user = if gitUser != null then gitUser else {
        name = "Daniel Crawford";
        email = "daniel.sc.crawford@gmail.com";
      };
      color = {
        ui = "auto";
        branch = true;
        diff = true;
        interactive = true;
        status = true;
        log = true;
      };
      core = {
        pager = "cat";
      };
      filter = {
        # Defined but not applied globally (see git/attributes above). Opt-in
        # per-repo only. required=false so opt-in can't hard-fail a checkout.
        nbstripout = {
          clean = "nbstripout";
          smudge = "cat";
          required = false;
        };
      };
      diff = {
        ipynb = {
          textconv = "nbstripout -t";
        };
      };
    };
  };
}
