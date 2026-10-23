{
  description = "Dev shell and smoke test for the BrickLink Studio Flatpak";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      devshell,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ devshell.overlays.default ];
        };

      smokeTest =
        pkgs:
        let
          inherit (pkgs) lib;
          extensionUuid = "smoke-test@bricklink-studio-flatpak";
          shellData = pkgs.linkFarm "smoke-test-shell-data" {
            "gnome-shell/modes/smoke-test.json" = pkgs.writeText "smoke-test.json" (
              builtins.toJSON {
                parentMode = "user";
                hasOverview = false;
                showWelcomeDialog = false;
                enabledExtensions = [ extensionUuid ];
              }
            );
            "gnome-shell/extensions/${extensionUuid}/extension.js" = ./ci/smoke-test/extension.js;
            "gnome-shell/extensions/${extensionUuid}/metadata.json" = pkgs.writeText "metadata.json" (
              builtins.toJSON {
                uuid = extensionUuid;
                name = "Smoke test";
                description = "D-Bus API for ci/smoke-test.sh";
                shell-version = [ (lib.versions.major pkgs.gnome-shell.version) ];
              }
            );
          };
          # Only Flatpak's session services, so host D-Bus services can't change the result.
          dbusConfig = pkgs.writeText "smoke-test-session.conf" ''
            <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
              "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
            <busconfig>
              <type>session</type>
              <keep_umask/>
              <listen>unix:tmpdir=/tmp</listen>
              <auth>EXTERNAL</auth>
              <servicedir>${pkgs.flatpak}/share/dbus-1/services</servicedir>
              <policy context="default">
                <allow send_destination="*" eavesdrop="true"/>
                <allow eavesdrop="true"/>
                <allow own="*"/>
              </policy>
            </busconfig>
          '';
        in
        pkgs.writeShellApplication {
          name = "smoke-test";
          runtimeInputs = with pkgs; [
            coreutils
            dbus
            flatpak
            glib
            gnome-shell
            gnugrep
            gnused
          ];
          runtimeEnv = {
            SMOKE_TEST_SHELL_DATA = shellData;
            SMOKE_TEST_DBUS_CONFIG = dbusConfig;
            # Title bar font, independent of the host's fontconfig.
            FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.adwaita-fonts ]; };
            # nixpkgs' libglvnd and libgbm only look in /run/opengl-driver, which exists only on NixOS.
            __EGL_VENDOR_LIBRARY_FILENAMES = "${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json";
            GBM_BACKENDS_PATH = "${pkgs.mesa}/lib/gbm";
          };
          text = builtins.readFile ./ci/smoke-test.sh;
        };
    in
    {
      packages = forAllSystems (system: {
        smoke-test = smokeTest (pkgsFor system);
      });

      apps = forAllSystems (system: {
        smoke-test = {
          type = "app";
          program = nixpkgs.lib.getExe self.packages.${system}.smoke-test;
        };
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
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
              skopeo
              curl
              jq
            ];
          };
        }
      );
    };
}
