# AGENTS.md

## Commit conventions

- Plain English, capitalized titles
- No conventional commit prefixes (no `feat:`, `fix:`, `chore:`)
- No trailing periods
- GPG sign all commits

## Code style

- Nix: 2-space indentation, `with lib;` at the top of each file
- Options: use `mkEnableOption` for feature flags, `mkOption` with proper types
- Submodules: group related options under named submodules (e.g., `kernel`, `services`, `tailscale`)
- Defaults: provide opinionated defaults that match the Shikanime RKE2 deployment

## Module design

- All options under `kix.*`
- Each concern in its own file under `modules/`
- `default.nix` is the entry point that imports all submodules
- Follow the Catppuccin pattern: `nixosModules.default = import ./modules`
