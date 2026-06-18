# AGENTS.md

## Commit conventions

- Plain English, capitalized titles
- No conventional commit prefixes (no `feat:`, `fix:`, `chore:`)
- No trailing periods
- GPG sign all commits

## Code style

- Nix: 2-space indentation, `with lib;` at the top of each file
- Options: use `mkEnableOption` for feature flags, `mkOption` with proper types
- Submodules: group related options under named submodules (e.g., `kernel`)
- Defaults: provide opinionated defaults that match the Shikanime RKE2
  deployment

## Module design

- All options under `knix.*`
- Keep a thin `modules/default.nix` aggregator that imports the submodules
- Keep root options in `modules/knix.nix`
- Keep RKE2 deployment config in `modules/rke2.nix`
- Keep each concern in its own file under `modules/`
- Follow the Catppuccin pattern: `nixosModules.default = import ./modules`
