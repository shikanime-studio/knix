# Knix

Knix is the Nix module set I use to bring up an RKE2 cluster with a sensible
default setup. It gives you a ready-to-use base for Kubernetes on NixOS, while
still leaving room to tweak networking, Flux, and storage.

## What You Get

- An RKE2 server with the defaults I rely on
- Pod and service networking defaults that work well with IPv4 and IPv6
- Optional Flux CD integration for GitOps
- Optional Longhorn deployment for persistent storage
- A small option surface under `knix.*`

## Quick Start

Add Knix as a flake input:

```nix
{
  inputs.knix.url = "github:shikanime-studio/knix";

  outputs = { self, nixpkgs, knix, ... }:
    {
      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        modules = [
          knix.nixosModules.default
          {
            knix.enable = true;
          }
        ];
      };
    };
}
```

That is enough to get the default RKE2 stack.

## Common Settings

Use these when you want to adjust the cluster without rewriting the module:

```nix
{
  knix = {
    enable = true;
    nodeIP = "192.168.1.30";
    serverAddr = "https://192.168.1.28:9345";
    tokenFile = config.sops.secrets.rke2-token.path;
    clusterCidr = "10.42.0.0/16";
    clusterCidrIPv6 = "fd01::/108";
    serviceCidr = "10.43.0.0/16,fd02::/108";
    interface = "eth0";
  };
}
```

## Flux CD

Enable Flux when you want the cluster to reconcile itself from a Git repository:

```nix
{
  knix = {
    enable = true;
    flux.enable = true;
    flux.repoUrl = "https://github.com/my-org/cluster-config.git";
    flux.path = "clusters/production";
  };
}
```

## Longhorn

Enable Longhorn when you want persistent storage managed by the cluster:

```nix
{
  knix = {
    enable = true;
    longhorn.enable = true;
  };
}
```

## Options

All options live under `knix.*`.

### Core

| Option                      | Default                     | Purpose                                  |
| --------------------------- | --------------------------- | ---------------------------------------- |
| `knix.enable`               | `false`                     | Turn the Knix module on                  |
| `knix.clusterCidr`          | `"10.244.0.0/16"`           | IPv4 pod CIDR                            |
| `knix.clusterCidrIPv6`      | `"fd00::/108"`              | IPv6 pod CIDR                            |
| `knix.serviceCidr`          | `"10.96.0.0/12,fd01::/108"` | Service CIDR                             |
| `knix.interface`            | `"enp1s0"`                  | WAN interface used by the firewall rules |
| `knix.nodeIP`               | `null`                      | Node IPs passed to RKE2                  |
| `knix.serverAddr`           | `null`                      | RKE2 server address                      |
| `knix.tokenFile`            | `null`                      | RKE2 join token file                     |
| `knix.nodeCidrMaskSize`     | `24`                        | IPv4 node CIDR mask size                 |
| `knix.nodeCidrMaskSizeIPv6` | `112`                       | IPv6 node CIDR mask size                 |

### Flux CD

| Option                       | Default                                        | Purpose                       |
| ---------------------------- | ---------------------------------------------- | ----------------------------- |
| `knix.flux.enable`           | `false`                                        | Enable Flux CD                |
| `knix.flux.repoUrl`          | `"https://github.com/shikanime/manifests.git"` | Git repository used by Flux   |
| `knix.flux.path`             | `"clusters/nishir/overlays/tailnet"`           | Kustomization path            |
| `knix.flux.ref`              | `"refs/heads/main"`                            | Git ref to track              |
| `knix.flux.instance.version` | `"0.46.0"`                                     | Flux instance chart version   |
| `knix.flux.operator.version` | `"0.46.0"`                                     | Flux operator chart version   |
| `knix.flux.tofu.version`     | `"0.16.2"`                                     | tofu-controller chart version |

### Longhorn

| Option                      | Default    | Purpose                                      |
| --------------------------- | ---------- | -------------------------------------------- |
| `knix.longhorn.enable`      | `false`    | Enable Longhorn                              |
| `knix.longhorn.version`     | `"1.12.0"` | Longhorn chart version                       |
| `knix.longhorn.extraConfig` | `{}`       | Additional Helm values merged into the chart |

Longhorn also keeps the existing disk helper used by my cluster setup.

## How It Is Structured

```text
knix.nixosModules.default   # Main entry point
├── modules/knix.nix        # Public option surface
├── modules/rke2.nix        # RKE2 server and cluster defaults
├── modules/flux.nix        # Flux CD integration
└── modules/longhorn.nix    # Longhorn helper + HelmChart deployment
```

## Notes

- `knix.enable = true` is the main switch.
- You can enable Flux and Longhorn independently.
- The module is opinionated by design.

## License

AGPL-3.0-or-later
