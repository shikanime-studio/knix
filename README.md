# Knix

Knix is an opinionated NixOS module set for bootstrapping an RKE2 cluster. It
gives you a solid default cluster layout, while keeping the public surface small
enough to understand and customize.

## What You Get

- An RKE2 server with the project defaults
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

## Topologies

Knix supports three cluster layouts. Pick the one that matches your hardware.

### Single Node

The simplest setup. One machine acts as both server and worker. Good for
homelabs, CI runners, or small production workloads that do not need HA.

```nix
{
  inputs.knix.url = "github:shikanime-studio/knix";

  outputs = { self, nixpkgs, knix, ... }:
    {
      nixosConfigurations.node1 = nixpkgs.lib.nixosSystem {
        modules = [
          knix.nixosModules.default
          {
            knix.enable = true;
            networking.hostName = "node1";
          }
        ];
      };
    };
}
```

The server role is enabled by default in `knix.role`. The single node runs the
control plane, schedules workloads, and serves as the cluster API endpoint at
`https://<nodeIP>:9345`.

Under the hood, Knix also enables the host tuning RKE2 and Longhorn need: bridge
netfilter and overlayfs support, BBR congestion control, tighter neighbor-table
and conntrack limits, and IPv4/IPv6 forwarding defaults that match the cluster
networking model.

### Multi-Server HA

Three or five machines share the control plane. RKE2 forms an etcd quorum across
them, so the cluster survives the loss of one or two servers.

Generate a shared token first:

```sh
openssl rand -hex 32 > rke2-token
```

Store it with sops-nix as `rke2-token`, then reference the decrypted path from
each server configuration.

```nix
# server-1.nix
{
  nixosConfigurations.server1 = nixpkgs.lib.nixosSystem {
    modules = [
      knix.nixosModules.default
      {
        knix = {
          enable = true;
          serverAddr = "https://server1.example.com:9345";
          tokenFile = config.sops.secrets.rke2-token.path;
          nodeIP = "10.0.0.11";
        };
      }
    ];
  };
}
```

Repeat for `server2` and `server3` with their own `nodeIP` values. All three
share the same `serverAddr` and `tokenFile`. The first server to start
initializes etcd; the remaining two join as voters.

For five-node quorum, add two more servers. RKE2 tolerates two failures with
five voters.

### Worker-Only Nodes

Workers join an existing cluster. They do not run the control plane or etcd. Use
them to add compute capacity without expanding the server pool.

```nix
# worker-1.nix
{
  nixosConfigurations.worker1 = nixpkgs.lib.nixosSystem {
    modules = [
      knix.nixosModules.default
      {
        knix = {
          enable = true;
          serverAddr = "https://server1.example.com:9345";
          tokenFile = config.sops.secrets.rke2-token.path;
          nodeIP = "10.0.0.21";
          role = "agent";
        };
      }
    ];
  };
}
```

Workers use the same token as the servers but rely on `serverAddr` to find the
cluster. Set `knix.role = "agent"` on worker-only nodes so RKE2 joins the
existing server pool instead of initializing another control plane.

### Mixed Layout

In practice, most deployments combine topologies. A common pattern is three
server nodes for HA plus two or more workers for capacity:

```text
server1 (control plane + etcd voter) ─┐
server2 (control plane + etcd voter) ─┤── cluster API: https://vip:9345
server3 (control plane + etcd voter) ─┘
worker1 (workload only) ──────────────┘
worker2 (workload only) ──────────────┘
```

Use a virtual IP or DNS round-robin for `serverAddr` so that new workers and API
consumers reach a healthy server.

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
    addons.flux.instance.extraConfig = {
      instance.sync = {
        interval = "1m";
        kind = "GitRepository";
        path = "clusters/production";
        pullSecret = "";
        ref = "refs/heads/main";
        url = "https://github.com/my-org/cluster-config.git";
      };
    };
  };
}
```

## Longhorn

Enable Longhorn when you want persistent storage managed by the cluster:

```nix
{
  knix = {
    enable = true;
    addons.longhorn.enable = true;
    labels = {
      "node.longhorn.io/create-default-disk" = "config";
    };
  };
}
```

Longhorn enables the `node.longhorn.io/create-default-disk=config` label for
`knix.labels` automatically.

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
| `knix.labels`               | `{}`                        | Optional node labels passed to RKE2      |
| `knix.nodeIP`               | `null`                      | Node IPs passed to RKE2                  |
| `knix.serverAddr`           | `""`                        | RKE2 server address                      |
| `knix.tokenFile`            | `null`                      | RKE2 join token file                     |
| `knix.tlsSan`               | `[]`                        | TLS SANs passed to RKE2                  |
| `knix.role`                 | `"server"`                  | RKE2 node role: `"server"` or `"agent"`  |
| `knix.nodeCidrMaskSize`     | `24`                        | IPv4 node CIDR mask size                 |
| `knix.nodeCidrMaskSizeIPv6` | `112`                       | IPv6 node CIDR mask size                 |

### Flux CD

| Option                                  | Default    | Purpose                       |
| --------------------------------------- | ---------- | ----------------------------- |
| `knix.addons.flux.enable`               | `true`     | Enable Flux CD                |
| `knix.charts.flux.version`              | `"0.46.0"` | Flux instance chart version   |
| `knix.charts."flux-operator".version`   | `"0.46.0"` | Flux operator chart version   |
| `knix.charts."tofu-controller".version` | `"0.16.2"` | tofu-controller chart version |

Flux instance sync is passed through
`knix.addons.flux.instance.extraConfig.instance.sync`.

### Longhorn

| Option                             | Default    | Purpose                                      |
| ---------------------------------- | ---------- | -------------------------------------------- |
| `knix.addons.longhorn.enable`      | `true`     | Enable Longhorn                              |
| `knix.charts.longhorn.version`     | `"1.12.0"` | Longhorn chart version                       |
| `knix.addons.longhorn.extraConfig` | `{}`       | Additional Helm values merged into the chart |

Longhorn also keeps the existing disk helper used by the cluster layout.

## How It Is Structured

```text
knix.nixosModules.default   # Main entry point
├── modules/knix.nix        # Public option surface + addon presets
├── modules/rke2.nix        # RKE2 renderer for charts and manifests
├── modules/flux.nix        # Flux CD preset
└── modules/longhorn.nix    # Longhorn preset + host helper
```

## Notes

- `knix.enable = true` is the main switch.
- You can enable Flux and Longhorn independently.
- Monitoring can be enabled on its own as well.

## License

AGPL-3.0-or-later
