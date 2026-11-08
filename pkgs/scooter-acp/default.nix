{ symlinkJoin, writeShellApplication, nodejs, openssh }:

let
  scooter-acp = writeShellApplication {
    name = "scooter-acp";
    runtimeInputs = [ nodejs ];
    text = ''
      exec node ${./src}/main.mjs "$@"
    '';
  };
  scooter-ssh = writeShellApplication {
    name = "scooter-ssh";
    runtimeInputs = [ openssh ];
    runtimeEnv.SCOOTER_ACP = "${scooter-acp}/bin/scooter-acp";
    text = builtins.readFile ./scooter-ssh.sh;
  };
in
symlinkJoin {
  name = "scooter-acp";
  paths = [ scooter-acp scooter-ssh ];
}
