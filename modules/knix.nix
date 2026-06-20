{ lib, ... }:

with lib;

{
  options.knix = {
    enable = mkEnableOption "Knix opinionated RKE2 server";

    role = mkOption {
      type = types.enum [
        "agent"
        "server"
      ];
      default = "server";
      description = "The RKE2 node role.";
    };

    clusterCidr = mkOption {
      type = types.str;
      default = "10.244.0.0/16";
      description = "The IPv4 pod CIDR passed to RKE2.";
    };

    clusterCidrIPv6 = mkOption {
      type = types.str;
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
      type = types.str;
      default = "10.96.0.0/12,fd01::/108";
      description = "The service CIDR passed to RKE2.";
    };

    interface = mkOption {
      type = types.str;
      default = "enp1s0";
      description = "The WAN interface used for firewall policy.";
    };

    labels = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "The node labels applied to RKE2 nodes.";
    };

    nodeIP = mkOption {
      type = types.str;
      description = "The node IPs passed to RKE2.";
    };

    serverAddr = mkOption {
      type = types.str;
      description = "The server address passed to RKE2.";
    };

    tokenFile = mkOption {
      type = types.path;
      description = "The token file passed to RKE2.";
    };

    charts = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            createNamespace = mkOption {
              type = types.bool;
              default = true;
              description = "Whether the chart should create its namespace.";
            };

            extraFieldDefinitions = mkOption {
              type = types.attrsOf types.raw;
              default = {
                failurePolicy = "abort";
              };
              description = "Extra chart field definitions passed through to RKE2.";
            };

            hash = mkOption {
              type = types.str;
              description = "The chart hash.";
            };

            name = mkOption {
              type = types.str;
              description = "The chart release name.";
            };

            repo = mkOption {
              type = types.str;
              description = "The chart repository.";
            };

            targetNamespace = mkOption {
              type = types.str;
              default = "flux-system";
              description = "The target namespace for the chart.";
            };

            version = mkOption {
              type = types.str;
              description = "The chart version.";
            };

            values = mkOption {
              type = types.attrsOf types.raw;
              default = { };
              description = "Rendered values for the chart.";
            };
          };
        }
      );
      default = { };
      description = "Rendered chart configuration used by Knix modules.";
    };

    manifests = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            content = mkOption {
              type = types.attrsOf types.raw;
              default = { };
              description = "Rendered manifest content.";
            };
          };
        }
      );
      default = { };
      description = "Manifest settings used by Knix modules.";
    };
  };
}
