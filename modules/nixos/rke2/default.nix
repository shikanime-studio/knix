# Kix — Opinionated RKE2 deployment module
#
# Provides a batteries-included, production-hardened RKE2 server configuration
# with sensible defaults for networking, storage, and GitOps.
#
# Design principles:
# - CIS-hardened by default
# - WireGuard-encrypted pod networking via Cilium + Multus
# - Flux CD for GitOps reconciliation
# - Longhorn for distributed block storage
# - Tailscale integration for secure cluster access
# - IPv6-safe firewall rules (blocks public IPv6 egress on WAN)
{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.kix.rke2;

  clusterCidr = filter (cidr: cidr != null) [
    cfg.clusterCidrIPv4
    cfg.clusterCidrIPv6
  ];

  rke2ApiServerPort = 6443;
  rke2SupervisorPort = 9345;
  kubeletMetricsPort = 10250;
  etcdClientPort = 2379;
  etcdPeerPort = 2380;
  etcdMetricsPort = 2381;
  canalHealthCheckPort = 9099;
  wireguardPort = 51820;
  wireguardIPv6Port = 51821;

  nodePortRange = {
    from = 30000;
    to = 32767;
  };
in
with lib;
{
  imports = [
    ./rke2/longhorn.nix
    ./rke2/flux.nix
  ];

  options.kix.rke2 = mkOption {
    type = types.submodule {
      options = {
        enable = mkEnableOption "Kix opinionated RKE2 server";

        clusterCidrIPv4 = mkOption {
          type = types.nullOr types.str;
          default = "10.244.0.0/16";
          description = "The IPv4 pod CIDR passed to RKE2.";
        };

        clusterCidrIPv6 = mkOption {
          type = types.nullOr types.str;
          default = "fd00::/108";
          description = "The IPv6 pod CIDR passed to RKE2.";
        };

        nodeCidrMaskSize = mkOption {
          type = types.int;
          default = 24;
          description = "The IPv4 node CIDR mask size passed to the controller manager.";
        };

        nodeCidrMaskSizeIPv6 = mkOption {
          type = types.int;
          default = 112;
          description = "The IPv6 node CIDR mask size passed to the controller manager.";
        };

        serviceCidr = mkOption {
          type = types.nullOr types.str;
          default = "10.96.0.0/12,fd01::/108";
          description = "The service CIDR passed to RKE2.";
        };

        interface = mkOption {
          type = types.str;
          default = "enp1s0";
          description = "The WAN interface used for firewall policy.";
        };

        extraConfig = mkOption {
          type = types.attrsOf types.raw;
          default = { };
          description = "Additional direct values merged into services.rke2.";
        };

        # Kernel tuning — applied automatically when RKE2 is enabled
        kernel = mkOption {
          type = types.submodule {
            options = {
              sysctl = mkOption {
                type = types.attrsOf (types.either types.int types.str);
                default = {
                  # File and Inotify limits
                  "fs.file-max" = 2097152;
                  "fs.inotify.max_user_instances" = 8192;
                  "fs.inotify.max_user_watches" = 524288;

                  # Bridge networking for CNIs
                  "net.bridge.bridge-nf-call-ip6tables" = 1;
                  "net.bridge.bridge-nf-call-iptables" = 1;

                  # Networking queueing and buffer sizing
                  "net.core.default_qdisc" = "fq";
                  "net.core.netdev_max_backlog" = 16384;
                  "net.core.rmem_default" = 7340032;
                  "net.core.rmem_max" = 16777216;
                  "net.core.somaxconn" = 4096;
                  "net.core.wmem_default" = 7340032;
                  "net.core.wmem_max" = 16777216;

                  # Forwarding, TCP autotuning, and BBR
                  "net.ipv4.ip_forward" = 1;
                  "net.ipv4.conf.all.rp_filter" = 0;
                  "net.ipv4.conf.default.rp_filter" = 0;
                  "net.ipv4.ip_local_port_range" = "1024 65535";
                  "net.ipv4.tcp_congestion_control" = "bbr";
                  "net.ipv4.tcp_fin_timeout" = 15;
                  "net.ipv4.tcp_keepalive_time" = 600;
                  "net.ipv4.tcp_mtu_probing" = 1;
                  "net.ipv4.tcp_rmem" = "4096 87380 16777216";
                  "net.ipv4.tcp_wmem" = "4096 65536 16777216";

                  # GC thresholds for ARP/Neighbor tables
                  "net.ipv4.neigh.default.gc_thresh1" = 1024;
                  "net.ipv4.neigh.default.gc_thresh2" = 2048;
                  "net.ipv4.neigh.default.gc_thresh3" = 4096;
                  "net.ipv6.conf.all.forwarding" = 1;
                  "net.ipv6.conf.default.forwarding" = 1;

                  # Conntrack limits
                  "net.netfilter.nf_conntrack_max" = 262144;

                  # Prevent mmap OOM crashes
                  "vm.max_map_count" = 262144;
                };
                description = "Sysctl values applied to all RKE2 nodes.";
              };

              modules = mkOption {
                type = types.listOf types.str;
                default = [
                  "br_netfilter"
                  "overlay"
                  "tcp_bbr"
                ];
                description = "Kernel modules loaded on RKE2 nodes.";
              };
            };
          };
          default = { };
          description = "Kernel tuning applied automatically when RKE2 is enabled.";
        };

        # Tailscale integration
        tailscale = mkOption {
          type = types.submodule {
            options = {
              enable = mkEnableOption "Tailscale integration for RKE2 nodes";

              useRoutingFeatures = mkOption {
                type = types.enum [
                  "client"
                  "server"
                  "both"
                ];
                default = "server";
                description = "Tailscale routing mode.";
              };

              advertisePodCIDR = mkOption {
                type = types.bool;
                default = true;
                description = "Whether to advertise the pod CIDR as a Tailscale subnet route.";
              };

              ssh = mkOption {
                type = types.bool;
                default = true;
                description = "Whether to enable Tailscale SSH.";
              };
            };
          };
          default = { };
          description = "Tailscale integration settings.";
        };

        # Service defaults — avahi, openssh, etc.
        services = mkOption {
          type = types.submodule {
            options = {
              avahi = mkOption {
                type = types.submodule {
                  options = {
                    enable = mkEnableOption "Avahi mDNS/DNS-SD for RKE2 nodes";
                  };
                };
                default = {
                  enable = true;
                };
                description = "Avahi mDNS settings.";
              };

              openssh = mkOption {
                type = types.submodule {
                  options = {
                    enable = mkEnableOption "OpenSSH for RKE2 nodes";
                  };
                };
                default = {
                  enable = true;
                };
                description = "OpenSSH settings.";
              };

              fstrim = mkOption {
                type = types.submodule {
                  options = {
                    enable = mkEnableOption "periodic fstrim for RKE2 nodes";
                  };
                };
                default = {
                  enable = true;
                };
                description = "Periodic fstrim settings.";
              };
            };
          };
          default = { };
          description = "Service defaults for RKE2 nodes.";
        };
      };
    };
    default = { };
    description = "Kix opinionated RKE2 deployment module.";
  };

  config = mkIf cfg.enable {
    # Kernel tuning
    boot.kernelModules = cfg.kernel.modules;
    boot.kernel.sysctl = mkMerge [
      cfg.kernel.sysctl
      {
        "net.ipv4.conf.${cfg.interface}.rp_filter" = 0;
        "net.ipv6.conf.${cfg.interface}.accept_ra" = 2;
        "net.ipv6.conf.${cfg.interface}.autoconf" = 1;
        "net.ipv6.conf.${cfg.interface}.accept_ra_defrtr" = 0;
        "net.ipv6.conf.${cfg.interface}.accept_ra_pinfo" = 1;
        "net.ipv6.conf.${cfg.interface}.accept_ra_mtu" = 1;
        "net.ipv6.conf.${cfg.interface}.accept_redirects" = 0;
      }
    ];

    # RKE2 server configuration
    services.rke2 = mkMerge [
      {
        enable = true;
        role = "server";
        cisHardening = true;
        manifests = {
          rke2-canal-config.content = {
            apiVersion = "helm.cattle.io/v1";
            kind = "HelmChartConfig";
            metadata = {
              name = "rke2-canal";
              namespace = "kube-system";
            };
            spec.valuesContent = builtins.toJSON {
              flannel = {
                backend = "wireguard";
                iface = cfg.interface;
              };
              encryption = {
                enabled = true;
                type = "wireguard";
              };
              gatewayAPI = {
                enabled = true;
                gatewayClass.create = true;
              };
              hubble = {
                enabled = true;
                relay.enabled = true;
                ui.enabled = true;
              };
              ipam.mode = "kubernetes";
              k8s = {
                requireIPv4PodCIDR = cfg.clusterCidrIPv4 != null;
                requireIPv6PodCIDR = cfg.clusterCidrIPv6 != null;
              };
              k8sServiceHost = "localhost";
              k8sServicePort = "6443";
              kubeProxyReplacement = true;
              operator.prometheus.enabled = true;
              prometheus.enabled = true;
            };
          };

          rke2-coredns-config.content = {
            apiVersion = "helm.cattle.io/v1";
            kind = "HelmChartConfig";
            metadata = {
              name = "rke2-coredns";
              namespace = "kube-system";
            };
            spec.valuesContent = builtins.toJSON {
              nodelocal.enabled = true;
            };
          };

          rke2-multus-config.content = {
            apiVersion = "helm.cattle.io/v1";
            kind = "HelmChartConfig";
            metadata = {
              name = "rke2-multus";
              namespace = "kube-system";
            };
            spec.valuesContent = builtins.toJSON {
              manifests.dhcpDaemonSet = true;
            };
          };

          rke2-traefik-config.content = {
            apiVersion = "helm.cattle.io/v1";
            kind = "HelmChartConfig";
            metadata = {
              name = "rke2-traefik";
              namespace = "kube-system";
            };
            spec.valuesContent = builtins.toJSON {
              providers.kubernetesGateway.enabled = true;
            };
          };
        };
        extraFlags = [
          (optionalString (clusterCidr != [ ]) "--cluster-cidr=${concatStringsSep "," clusterCidr}")
          "--cni=multus,canal"
          "--ingress-controller=traefik"
          "--kube-controller-manager-arg=node-cidr-mask-size-ipv4=${toString cfg.nodeCidrMaskSize}"
          "--kube-controller-manager-arg=node-cidr-mask-size-ipv6=${toString cfg.nodeCidrMaskSizeIPv6}"
          (optionalString (cfg.serviceCidr != null) "--service-cidr=${cfg.serviceCidr}")
          "--secrets-encryption"
        ];
        gracefulNodeShutdown.enable = true;
      }
      cfg.extraConfig
    ];

    # Firewall — IPv6-safe rules
    networking.firewall = {
      extraCommands = ''
        # Keep public IPv6 egress off the WAN interface so runtimes fall back
        # to IPv4 while still allowing local and tailnet traffic.
        ip6tables -A OUTPUT -o ${cfg.interface} -d ::1/128 -j ACCEPT
        ip6tables -A OUTPUT -o ${cfg.interface} -d fe80::/10 -j ACCEPT
        ip6tables -A OUTPUT -o ${cfg.interface} -d fc00::/7 -j ACCEPT
        ip6tables -A OUTPUT -o ${cfg.interface} -d fd00::/108 -j ACCEPT
        ip6tables -A OUTPUT -o ${cfg.interface} -d fd01::/108 -j ACCEPT
        ip6tables -A OUTPUT -o ${cfg.interface} -d 2000::/3 -j REJECT --reject-with icmp6-addr-unreachable
      '';
      extraStopCommands = ''
        ip6tables -D OUTPUT -o ${cfg.interface} -d ::1/128 -j ACCEPT 2>/dev/null || true
        ip6tables -D OUTPUT -o ${cfg.interface} -d fe80::/10 -j ACCEPT 2>/dev/null || true
        ip6tables -D OUTPUT -o ${cfg.interface} -d fc00::/7 -j ACCEPT 2>/dev/null || true
        ip6tables -D OUTPUT -o ${cfg.interface} -d fd00::/108 -j ACCEPT 2>/dev/null || true
        ip6tables -D OUTPUT -o ${cfg.interface} -d fd01::/108 -j ACCEPT 2>/dev/null || true
        ip6tables -D OUTPUT -o ${cfg.interface} -d 2000::/3 -j REJECT --reject-with icmp6-addr-unreachable 2>/dev/null || true
      '';
      interfaces.${cfg.interface} = {
        allowedTCPPorts = [
          rke2ApiServerPort
          rke2SupervisorPort
          kubeletMetricsPort
          etcdClientPort
          etcdPeerPort
          etcdMetricsPort
          canalHealthCheckPort
        ];
        allowedUDPPorts = [
          wireguardPort
          wireguardIPv6Port
        ];
        allowedTCPPortRanges = [ nodePortRange ];
      };
    };

    # Tailscale integration
    services.tailscale = mkIf cfg.tailscale.enable {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = cfg.tailscale.useRoutingFeatures;
      extraUpFlags = [ "--ssh" ];
    };

    # Service defaults
    services.avahi = mkIf cfg.services.avahi.enable {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };

    services.openssh = mkIf cfg.services.openssh.enable {
      enable = true;
      openFirewall = true;
    };

    services.fstrim = mkIf cfg.services.fstrim.enable {
      enable = true;
    };

    # DNS preference — IPv4 over IPv6 for public resolution
    networking.getaddrinfo.precedence = {
      "::1/128" = 50;
      "::/0" = 40;
      "2002::/16" = 30;
      "::/96" = 20;
      "::ffff:0:0/96" = 100;
    };
  };
}
