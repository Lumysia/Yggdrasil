{ pkgs, lib, config, ... }:

{
  options.features.desktop.gnome.enable = lib.mkEnableOption "Gnome Desktop Environment";

  config = lib.mkIf config.features.desktop.gnome.enable {
    # X11 / Wayland
    services.xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    # Display Manager & Desktop Environment
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    # Audio
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      raopOpenFirewall = true;
      extraConfig.pipewire."10-airplay"."context.modules" = [
        { name = "libpipewire-module-raop-discover"; }
      ];
    };

    # Fonts & Input
    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5.addons = with pkgs; [
        rime-data
        fcitx5-rime
        fcitx5-gtk
      ];
    };

    fonts.packages = with pkgs; [
      noto-fonts-cjk-sans
      mplus-outline-fonts.githubRelease
    ];

    # Gnome Settings
    programs.dconf.profiles.user.databases = [
      {
        settings."org/gnome/mutter".experimental-features = [
          "scale-monitor-framebuffer"
          "variable-refresh-rate"
          "xwayland-native-scaling"
        ];
      }
    ];
  };
}