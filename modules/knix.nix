{ lib, ... }:

with lib;

{
  options.services.knix = {
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
      type = types.nullOr types.str;
      default = null;
      description = "The node IPs passed to RKE2.";
    };

    serverAddr = mkOption {
      type = types.str;
      default = "";
      description = "The server address passed to RKE2.";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
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

            failurePolicy = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "The chart failure policy passed through to RKE2.";
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

            extraDeploy = mkOption {
              type = types.listOf types.attrs;
              default = [ ];
              description = "Extra resources deployed alongside the chart via RKE2 extraDeploy.";
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

    extraConfig = mkOption {
      type = types.attrsOf (types.either types.str (types.either types.bool (types.listOf types.str)));
      default = { };
      description = ''
        Extra RKE2 flags expressed as an attrset of flag name to value.
        String values render as --name=value. List values are comma
        joined: --name=v1,v2. Boolean true renders as bare --name.
        Merged from all knix modules and joined into
        services.rke2.extraFlags by mkExtraFlags.
      '';
    };
  };
}
