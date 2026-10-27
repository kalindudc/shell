{
  description = "Shell, dotfiles and packages for macOS (nix-darwin) and Linux (Home Manager)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Not packaged in nixpkgs
    evalcache = {
      url = "github:mroth/evalcache";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      user = import ./nix/user.nix;
      unfree = import ./nix/unfree.nix { inherit lib; };

      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f (pkgsFor system));
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = unfree;
        };

      mkDarwin =
        profile:
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs user profile; };
          modules = [
            ./nix/darwin
            home-manager.darwinModules.home-manager
          ];
        };

      mkLinux =
        system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          extraSpecialArgs = {
            inherit inputs user;
            profile = "linux";
          };
          modules = [
            ./nix/home
            ./nix/home/linux.nix
          ];
        };
    in
    {
      # `task switch` picks personal or work on a Mac, and linux-<arch> on Linux.
      darwinConfigurations = lib.genAttrs [ "personal" "work" ] mkDarwin;

      homeConfigurations = {
        linux-x86_64 = mkLinux "x86_64-linux";
        linux-aarch64 = mkLinux "aarch64-linux";
      };

      # install.sh reads the user name and checkout path from here.
      lib = { inherit user; };

      packages = forAllSystems (pkgs: {
        home-manager = home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            bats
            go-task
            nixfmt
            ruby
            shellcheck
            shfmt
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      checks = forAllSystems (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
          linux = self.homeConfigurations."linux-${lib.head (lib.splitString "-" system)}";
          home =
            if pkgs.stdenv.hostPlatform.isDarwin then
              self.darwinConfigurations.personal.config.home-manager.users.${user.username}
            else
              linux.config;
        in
        {
          git-identity = import ./nix/checks/git-identity.nix {
            inherit pkgs;
            gitConfig = home.xdg.configFile."git/config".source;
          };
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin (
          lib.mapAttrs (_: c: c.system) self.darwinConfigurations
        )
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          home = linux.activationPackage;
        }
      );
    };
}
