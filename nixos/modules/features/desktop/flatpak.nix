{ lib, config, ... }:

{
  options.features.desktop.flatpak.enable = lib.mkEnableOption "Flatpak Support";

  config = lib.mkIf config.features.desktop.flatpak.enable {
    services.flatpak = {
      enable = true;
      remotes = [{
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }];
      update.onActivation = true;
      packages = [
        "com.github.tchx84.Flatseal"
        "net.agalwood.Motrix"
        "io.github.giantpinkrobots.varia"
        "org.prismlauncher.PrismLauncher"
        "com.geeks3d.furmark"
        "md.obsidian.Obsidian"
        "org.onlyoffice.desktopeditors"
        "com.belmoussaoui.Obfuscate"
        "io.gitlab.news_flash.NewsFlash"
        "io.github.seadve.Mousai"
        "io.gitlab.adhami3310.Impression"
        "com.github.ADBeveridge.Raider"
        "io.github.alainm23.planify"
        "com.belmoussaoui.Decoder"
        "dev.geopjr.Collision"
        "org.gnome.Podcasts"
        "app.drey.Warp"
        "com.github.iwalton3.jellyfin-media-player"
        "io.github.radiolamp.mangojuice"
        "com.usebottles.bottles"
        "io.github.fabrialberio.pinapp"
        "com.github.johnfactotum.Foliate"
        "io.github.amit9838.mousam"
        "com.daniel15.wcc"
        "com.parsecgaming.parsec"
        "org.gimp.GIMP"
        "com.obsproject.Studio"
        "com.rustdesk.RustDesk"
        "io.github.flattool.Warehouse"
        "it.mijorus.gearlever"
        "io.github.ryubing.Ryujinx"
        "org.kde.skanpage"
        "io.emeric.toolblex"
        "com.brave.Browser"
        "net.sapples.LiveCaptions"
        "im.riot.Riot"
        # Untrasted apps
        "com.tencent.WeChat"
        "com.qq.QQ"
      ];
    };
  };
}