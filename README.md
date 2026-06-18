# Kix — Kubernetes+nix

Opinionated RKE2 deployment module for NixOS.

## What Kix Does

Kix turns a fresh NixOS install into a production-hardened RKE2 Kubernetes node with:

- **CIS-hardened RKE2 server** — secrets encryption, graceful shutdown, Multus + Canal CNI
- **WireGuard-encrypted pod networking** — Cilium kube-proxy replacement with Hubble observability
- **Flux CD GitOps** — automated cluster state reconciliation from a Git repository
- **Longhorn distributed storage** — auto-discovering additional disks with SSD/HDD tagging
- **Tailscale integration** — secure cluster access with subnet route advertisement
- **IPv6-safe firewall** — blocks public IPv6 egress on the WAN interface while allowing local and tailnet traffic
- **Kernel tuning** — BBR congestion control, bridge netfilter, overlay fs, conntrack limits

## Design

Kix takes inspiration from:

- **numtide** — flake-parts for modular flake composition, treefmt-nix for formatting
- **x-shikanime** — consistent flake structure, devenv shells, cachix substituters
- **Catppuccin** — layered options design with `default` aliases and submodule composition

## Module Structure

```
kix.nixosModules.default          # Entry point — imports all submodules
├── modules/default.nix           # Core RKE2 server + kernel tuning + firewall
├── modules/flux.nix              # Flux CD GitOps (instance, operator, tofu-controller)
└── modules/longhorn.nix          # Longhorn distributed storage
```

## Quick Start

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
            kix.enable = true;
          }
        ];
      };
    };
}
```

That's it. Kix applies its opinionated defaults. Override any option to customize.

## Options Reference

All options live under `kix.*`:

### Core

| Option | Default | Description |
|---|---|---|
| `kix.enable` | `false` | Master switch — enables the full RKE2 stack |
| `kix.clusterCidrIPv4` | `"10.244.0.0/16"` | IPv4 pod CIDR |
| `kix.clusterCidrIPv6` | `"fd00::/108"` | IPv6 pod CIDR |
| `kix.serviceCidr` | `"10.96.0.0/12,fd01::/108"` | Service CIDR |
| `kix.interface` | `"enp1s0"` | WAN interface for firewall policy |
| `kix.nodeCidrMaskSize` | `24` | IPv4 node CIDR mask size |
| `kix.nodeCidrMaskSizeIPv6` | `112` | IPv6 node CIDR mask size |
| `kix.extraConfig` | `{}` | Raw merge into `services.rke2` |

### Kernel Tuning

| Option | Default | Description |
|---|---|---|
| `kix.kernel.modules` | `[ "br_netfilter" "overlay" "tcp_bbr" ]` | Kernel modules to load |
| `kix.kernel.sysctl` | *(production defaults)* | Sysctl values — override individual keys |

### Tailscale

| Option | Default | Description |
|---|---|---|
| `kix.tailscale.enable` | `false` | Enable Tailscale integration |
| `kix.tailscale.useRoutingFeatures` | `"server"` | Tailscale routing mode |
| `kix.tailscale.ssh` | `true` | Enable Tailscale SSH |

### Services

| Option | Default | Description |
|---|---|---|
| `kix.services.avahi.enable` | `true` | Avahi mDNS/DNS-SD |
| `kix.services.openssh.enable` | `true` | OpenSSH server |
| `kix.services.fstrim.enable` | `true` | Periodic fstrim |

### Flux CD

| Option | Default | Description |
|---|---|---|
| `kix.flux.enable` | `false` | Enable Flux GitOps |
| `kix.flux.repoUrl` | `"https://github.com/shikanime/manifests.git"` | Git repository URL |
| `kix.flux.path` | `"clusters/nishir/overlays/tailnet"` | Kustomization path |
| `kix.flux.ref` | `"refs/heads/main"` | Git ref to track |
| `kix.flux.instance.version` | `"0.46.0"` | Flux instance chart version |
| `kix.flux.operator.version` | `"0.46.0"` | Flux operator chart version |
| `kix.flux.tofu.version` | `"0.16.2"` | tofu-controller chart version |

### Longhorn

| Option | Default | Description |
|---|---|---|
| `kix.longhorn.enable` | `false` | Enable Longhorn storage |
| `kix.longhorn.mountRoot` | `"/mnt"` | Mount root scanned for additional disks |
| `kix.longhorn.storageReservedPercent` | `30` | Reserved disk space percentage |

## Examples

### Minimal — just RKE2

```nix
{
  kix.enable = true;
}
```

### Full stack with Flux and Longhorn

```nix
{
  kix = {
    enable = true;
    flux.enable = true;
    longhorn.enable = true;
    tailscale.enable = true;
  };
}
```

### Custom networking

```nix
{
  kix = {
    enable = true;
    clusterCidrIPv4 = "10.42.0.0/16";
    clusterCidrIPv6 = "fd01::/108";
    serviceCidr = "10.43.0.0/16,fd02::/108";
    interface = "eth0";
  };
}
```

### Custom Flux repository

```nix
{
  kix = {
    enable = true;
    flux = {
      enable = true;
      repoUrl = "https://github.com/my-org/cluster-config.git";
      path = "clusters/production";
    };
  };
}
```

### Override kernel sysctl

```nix
{
  kix = {
    enable = true;
    kernel.sysctl = {
      "net.core.rmem_max" = 33554432;
      "vm.max_map_count" = 524288;
    };
  };
}
```

## License

AGPL-3.0-or-later
