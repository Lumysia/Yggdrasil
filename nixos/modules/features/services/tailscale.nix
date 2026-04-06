{ pkgs, lib, config, ... }:

let
  cfg = config.features.services.tailscale;
in
{
  options.features.services.tailscale.enable = lib.mkEnableOption "Tailscale Mesh VPN";

  # Auth is done manually after first boot: sudo tailscale up --authkey <key>
  # The key is one-time; Tailscale state persists in /var/lib/tailscale afterwards.
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