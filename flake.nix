{
  description = "Dev shell for the BrickLink Studio Flatpak";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, devshell, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ devshell.overlays.default ];
          };
        in
        {
          default = pkgs.devshell.mkShell {
            name = "bricklink-studio-flatpak";

            packages = with pkgs; [
              flatpak
              flatpak-builder
              ostree
              appstream
              desktop-file-utils
              shared-mime-info
              shellcheck
              python3
              gnupg
              gh
              xvfb
              xdotool
              imagemagick
              curl
              jq
            ];
          };
        }
      );
    };
}
