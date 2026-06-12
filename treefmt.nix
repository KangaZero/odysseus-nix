# treefmt-nix configuration — one formatter per file type, surfaced through
# `nix fmt` (format in place) and enforced by `just fmt-check` / CI (--ci).
#
#   nix     → nixpkgs-fmt   (*.nix)
#   shell   → shfmt         (*.sh + the extension-less git hook)
#   md/yaml → prettier      (README.md, .github/workflows/*.yml)
_: {
  # Marks the tree root so treefmt resolves paths the same from any subdir.
  projectRootFile = "flake.nix";

  programs = {
    nixpkgs-fmt.enable = true;
    shfmt.enable = true;
    prettier.enable = true;
  };

  settings = {
    # The pre-push hook has no `.sh` extension, so shfmt's default `*.sh`
    # glob misses it — opt it in explicitly.
    formatter.shfmt.includes = [
      "*.sh"
      ".githooks/pre-push"
    ];

    # flake.lock is generated JSON; LICENSE is verbatim. Never reformat.
    global.excludes = [
      "flake.lock"
      "LICENSE"
    ];
  };
}
