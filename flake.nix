{
  description = "devbox: an isolated, egress-filtered container for VS Code + Claude Code";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      # Images are Linux-only. (On macOS you would need a Linux builder; not covered here.)
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;

      mkDevbox = import ./nix/mkDevbox.nix { inherit nixpkgs; };
    in
    {
      # Reusable entry point for per-project flakes (see templates/default).
      lib = {
        inherit mkDevbox;
        defaultAllowedDomains = import ./nix/allowlist.nix;
      };

      packages = forAllSystems (system:
        let box = mkDevbox { inherit system; };
        in {
          default = box.launcher;
          devbox = box.launcher;
          image = box.image;
          gateway = box.gateway;
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/devbox";
        };
      });

      templates.default = {
        path = ./templates/default;
        description = "Per-project devbox with extra packages and allowed domains";
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
