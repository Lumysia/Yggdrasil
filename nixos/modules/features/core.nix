{ pkgs, lib, config, ... }:

{
  options.features.core.enable = lib.mkEnableOption "Core System Configuration";

  config = lib.mkIf config.features.core.enable {
    # Nix Settings
    nix = {
      settings.experimental-features = [ "nix-command" "flakes" ];
      optimise = {
        automatic = true;
        dates = [ "daily" ];
      };
      gc = {
        automatic = true;
        dates = "daily";
        options = "--delete-old";
      };
    };

    nixpkgs.config.allowUnfree = true;

    # Networking
    networking.networkmanager.enable = true;
    
    # Boot & Kernel
    boot.kernel.sysctl = {
      "net.core.rmem_max" = 8388608;
      "net.core.wmem_max" = 8388608;
    };

    # Locale
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };

    # Base Packages
    environment.systemPackages = with pkgs; [
      zip
      unar
      tree
      btop
      ctop
      uv
      sops
      age
      ssh-to-age
    ];

    # Base Programs
    programs.vim.enable = true;
    programs.git.enable = true;
    programs.tmux.enable = true;
    programs.atop.enable = true;
    services.envfs.enable = true;
  };
}
