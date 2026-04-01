{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/features/core.nix
    ../../modules/features/hardware/nvidia.nix
    ../../modules/features/desktop/gnome.nix
    ../../modules/features/desktop/flatpak.nix
    ../../modules/features/desktop/gaming.nix
    ../../modules/features/services/tailscale.nix
    ../../modules/features/virtualisation/docker.nix
    ../../modules/features/virtualisation/libvirtd.nix
    ../../modules/home/users/ivy.nix
  ];

  # Feature Flags
  features.core.enable = true;
  features.hardware.nvidia.enable = true;
  features.desktop.gnome.enable = true;
  features.desktop.flatpak.enable = true;
  features.desktop.gaming.enable = true;
  features.services.tailscale.enable = true;
  features.virtualisation.docker.enable = true;
  features.virtualisation.libvirtd.enable = true;
  features.user.ivy.enable = true;

  time.timeZone = "America/Toronto";
  
  # Bootloader (Lanzaboote)
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  # Hardware Specialisation
  specialisation.docked.configuration = {
    boot.blacklistedKernelModules = config.boot.blacklistedKernelModules ++ [ "i915" ];
  };

  # Firewall
  networking.firewall = {
    enable = true;
    checkReversePath = false; # Whonix fix
  };

  system.autoUpgrade = {
    enable = true;
    flake = "/home/ivy/Projects/nixos";
    dates = "daily";
  };

  system.stateVersion = "25.05";
}