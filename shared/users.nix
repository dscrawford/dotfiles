# users.nix
{ pkgs, ... }:
{
  users.users.host = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    packages = with pkgs; [
      tree
    ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCZpsvf05hWJxKDmb5i1z8WLCo+paq4duftOhSDq0DAYrW0MguieW7LxgnuVvfy63N3rNjENPDXb/rUu85r9Mky4dIbRMrgGf+tTz5WM43TjpSFVkZDxeDGGF6fFGcv/gQGrDBLZhYooQp9Ip0Bb2LWYhxcYpQZumLiRxgRevcMQKZVvpmXj5fcq1OvokisFgqgudtl/qzolmHOTl/svTVqUVh58I2gBWp6PqHBTlviKj9MfoMm4V5uAcVfyZpmbhUDcBVWn44pUzDnJELSfG8rTopBYw7XTRpCGciGaG2o4uRt+0fSXHmOO+OQrHOzDHJMcj4lgB3AozvDTHr9tySg29WlDHVr7uUS81rSa30+gSYl/OtkKx9aO7GDoZ/eJyi48wOc4QSshAbpl6sc6LCnya2zEDBewxkgMCHfURWmfl0esAL2FYvetmtsig6RI03yMo2lwTRbvqK8A0bTybw0XAZb8quxQ/uW09yIa+kfe4i3nVKuQCETc71hXhGhQuk= daniel@nixos"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhfSPSaZFyOzSYPzKPJv21QcBlQKIBnrhNjIJjp8pOZ"
      # Inter-node SSH for cert sync and cluster management
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPlUsTsTPDRmtYfW8V7SZeC7FksMroDQTrym8+0q0Bl host@node1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL9iILobBfuJjGtNLxbcO/iSePIF+PDG++nJKZwe3gmK host@node2"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKiLnKrEG6sZ3jivCVW11lKHBVUBWh+pjrJVrFo0t6Dk host@node3"
    ];
    home = "/home/host";
  };
}
