{
  description = "Reusable GitHub Actions from jpetrucciani";

  inputs.cfg.url = "github:jpetrucciani/nix/f7df2a41d05114640fbc817362f146d6033be470";

  outputs = { self, cfg }:
    let
      inherit (cfg.inputs.nixpkgs) lib;
      forAllSystems = lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      environments = forAllSystems (system:
        let
          pkgs = import cfg { flake = cfg; inherit system; };
        in
        {
          inherit pkgs;
          shell = import ./default.nix { inherit pkgs; };
        });
    in
    {
      devShells = forAllSystems (system: { default = environments.${system}.shell; });
      formatter = forAllSystems (system: environments.${system}.shell.formatter);
      apps = forAllSystems (system:
        lib.mapAttrs
          (_: package: {
            type = "app";
            program = lib.getExe package;
            meta = { inherit (package.meta) description; };
          })
          environments.${system}.shell.scripts);
      checks = forAllSystems (system:
        let
          inherit (environments.${system}) pkgs shell;
        in
        lib.mapAttrs
          (name: command: pkgs.runCommand "actions-${name}" { } ''
            cp -R ${lib.cleanSource self} checkout
            chmod -R u+w checkout
            cd checkout
            ${lib.getExe command}
            touch "$out"
          '')
          shell.scripts);
    };
}
