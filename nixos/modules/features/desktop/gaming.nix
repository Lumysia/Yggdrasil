{ pkgs, lib, config, ... }:

{
  options.features.desktop.gaming.enable = lib.mkEnableOption "Gaming Optimization & Steam";

  config = lib.mkIf config.features.desktop.gaming.enable {
    programs.steam.enable = true;
    programs.gamemode.enable = true;
  };
}