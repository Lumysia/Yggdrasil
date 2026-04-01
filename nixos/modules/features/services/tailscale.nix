{ pkgs, lib, config, ... }:

let
  cfg = config.features.services.tailscale;
in
{
  options.features.services.tailscale.enable = lib.mkEnableOption "Tailscale Mesh VPN";

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      (final: prev: {
        tailscale = prev.tailscale.overrideAttrs (oldAttrs: {
          doCheck = false;
        });
      })
    ];

    services.tailscale.enable = true;
    services.tailscale.extraUpFlags = [ 
       "--accept-dns"
       "--snat-subnet-routes=false"
    ];
  };
}