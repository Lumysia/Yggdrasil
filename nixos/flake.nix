{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager-stable = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
  };

  outputs = { self, nixpkgs-stable, home-manager-stable, ... }@inputs:
    let
      mkSystem = { hostname, modules ? [] }:
        nixpkgs-stable.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/${hostname}
            ./modules
            home-manager-stable.nixosModules.home-manager
            inputs.sops-nix.nixosModules.sops
            {
              networking.hostName = hostname;
            }
          ] ++ modules;
        };
    in
    {
      nixosConfigurations = {
        # Infrastructure
        ## Headquarters
        hq-cat-core = mkSystem {
          hostname = "hq-cat-core";
        };

        hq-cat-games = mkSystem {
          hostname = "hq-cat-games";
        };

        hq-cat-services = mkSystem {
          hostname = "hq-cat-services";
        };

        hq-cat-sandbox = mkSystem {
          hostname = "hq-cat-sandbox";
        };

        hq-nya-services = mkSystem {
          hostname = "hq-nya-services";
        };

      };
    };
}
