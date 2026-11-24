{ pkgs ? let cfg = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.cfg.locked;
  in import
    (fetchTarball {
      name = "source";
      url = "https://github.com/${cfg.owner}/${cfg.repo}/archive/${cfg.rev}.tar.gz";
      sha256 = cfg.narHash;
    })
    { }
}:
let
  formatter = pkgs.jfmt { projectRootFile = "flake.nix"; };
  scripts = {
    lint = pkgs.pog {
      name = "actions-lint";
      description = "Check source formatting, shell scripts, and GitHub workflows";
      runtimeInputs = [ formatter pkgs.actionlint pkgs.shellcheck ];
      script = ''
        jfmt --ci --walk filesystem
        actionlint .github/workflows/*.yml
      '';
    };
    test = pkgs.pog {
      name = "actions-test";
      description = "Run Nix configuration and signed cache tests in temporary local stores";
      runtimeInputs = with pkgs; [ _nix bash coreutils gnused jq ];
      script = ''
        bash nix/setup/tests/config.sh
        bash nix/publish-cache/benchmarks/local.sh 0
      '';
    };
  };
in
pkgs.mkShell {
  name = "actions";
  packages = (with pkgs; [ actionlint bash jq shellcheck shfmt ]) ++ [ formatter ] ++ builtins.attrValues scripts;
  passthru = { inherit formatter scripts; };
}
