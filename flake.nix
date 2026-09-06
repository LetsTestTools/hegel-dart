{
  description = "hegeltest - Property-based testing for Dart, powered by Hegel's native fuzzing engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            dart
            lefthook
            git
          ];

          shellHook = ''
            if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && command -v lefthook >/dev/null 2>&1; then
              lefthook install >/dev/null 2>&1 || echo "⚠️ Warning: failed to install lefthook git hooks"
            fi
            echo "🔧 hegeltest dev shell"
            echo "   Dart:     $(dart --version 2>&1)"
            echo "   Lefthook: $(lefthook version 2>/dev/null)"
            echo ""
          '';
        };
      }
    );
}
