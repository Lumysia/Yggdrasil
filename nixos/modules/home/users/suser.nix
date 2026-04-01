{ pkgs, config, lib, ... }:

{
  options.features.user.suser.enable = lib.mkEnableOption "sUser User Identity";

  config = lib.mkIf config.features.user.suser.enable {
    users.users.suser = {
      isNormalUser = true;
      uid = 1000;
      description = "sUser";
      extraGroups = [ "networkmanager" "wheel" "docker" "podman" ];
    };

    home-manager.users.suser = { pkgs, ... }: {
      home.stateVersion = "25.05";
      nixpkgs.config.allowUnfree = true;
      programs.home-manager.enable = true;

      home.packages = with pkgs; [ ];

      programs.gpg.enable = true;
      
      programs.fastfetch.enable = true;
      programs.git-credential-oauth.enable = true;

      services.gpg-agent = {
        enable = true;
        pinentry.package = pkgs.pinentry-tty;
      };
    };
  };
}
