# Bluetooth hardware and Xbox controller support
{ config, lib, pkgs, ... }:

{
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Enable = "Source,Sink,Media";
          Disable = "Socket";
          FastConnectable = true;
          Experimental = true;
        };
      };
    };
    xpadneo.enable = true;
  };
}
