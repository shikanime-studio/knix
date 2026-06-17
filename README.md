# Kix — Kubernetes+nix

Opinionated RKE2 deployment module for NixOS.

## Design

Kix takes inspiration from:

- **numtide** — flake-parts for modular flake composition, treefmt-nix for formatting
- **x-shikanime** — consistent flake structure, devenv shells, cachix substituters
- **Catppuccin** — layered options design with `default` aliases and submodule composition

### Module structure

```
kix.nixosModules.default          # Entry point — imports all submodules
├── rke2/default.nix              # Core RKE2 server + kernel tuning + firewall
├── rke2/flux.nix                 # Flux CD GitOps (instance, operator, tofu-controller)
└── rke2/longhorn.nix             # Longhorn distributed storage
```

### Options namespace

All options live under `kix.rke2`:

```
kix.rke2.enable                  # Master switch
kix.rke2.clusterCidrIPv4         # Pod CIDR (default: 10.244.0.0/16)
kix.rke2.clusterCidrIPv6         # Pod CIDR (default: fd00::/108)
kix.rke2.serviceCidr             # Service CIDR (default: 10.96.0.0/12,fd01::/108)
kix.rke2.interface               # WAN interface (default: enp1s0)
kix.rke2.extraConfig             # Raw merge into services.rke2
kix.rke2.kernel.sysctl           # Kernel sysctl overrides
kix.rke2.kernel.modules          # Kernel modules (default: br_netfilter, overlay, tcp_bbr)
kix.rke2.tailscale.enable        # Tailscale integration
kix.rke2.flux.enable             # Flux CD GitOps
kix.rke2.flux.instance           # Flux instance chart settings
kix.rke2.flux.operator           # Flux operator chart settings
kix.rke2.flux.tofu               # tofu-controller chart settings
kix.rke2.longhorn.enable         # Longhorn storage
kix.rke2.services.avahi          # mDNS/DNS-SD
kix.rke2.services.openssh        # SSH access
kix.rke2.services.fstrim         # Periodic TRIM
```

## Usage

Add kix as a flake input:

```nix
{
  inputs.kix.url = "github:x-shikanime/kix";

  outputs = { self, nixpkgs, kix, ... }:
    {
      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        modules = [
          kix.nixosModules.default
          {
            kix.rke2.enable = true;
            kix.rke2.flux.enable = true;
            kix.rke2.longhorn.enable = true;
          }
        ];
      };
    };
}
```

## License

AGPL-3.0-or-later
