{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.knix;
in
with lib;
{
  options.services.knix.addons.flux = mkOption {
    type = types.submodule {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable the Flux addon.";
        };

        instance = {
          version = mkOption {
            type = types.str;
            default = "0.46.0";
            description = "Flux instance chart version.";
          };

          extraConfig = mkOption {
            type = types.attrsOf types.raw;
            default = { };
            description = "Additional Flux instance chart values.";
          };
        };

        operator = {
          version = mkOption {
            type = types.str;
            default = "0.46.0";
            description = "Flux operator chart version.";
          };

          extraConfig = mkOption {
            type = types.attrsOf types.raw;
            default = { };
            description = "Additional Flux operator chart values.";
          };
        };

        tofu = {
          version = mkOption {
            type = types.str;
            default = "0.16.2";
            description = "tofu-controller chart version.";
          };

          extraConfig = mkOption {
            type = types.attrsOf types.raw;
            default = { };
            description = "Additional tofu-controller chart values.";
          };
        };
      };
    };
    default = { };
    description = "Flux addon settings.";
  };

  config = mkIf (cfg.addons.flux.enable && cfg.role == "server") {
    services.knix.charts = {
      flux = {
        inherit (cfg.addons.flux.instance) version;
        createNamespace = true;
        failurePolicy = "abort";
        hash = "sha256-A7ojoUGwSKt+Vi+kFFroNroUxrJzHdLdbrYidHgg8gs=";
        name = "flux-instance";
        repo = "oci://ghcr.io/controlplaneio-fluxcd/charts/flux-instance";
        targetNamespace = "flux-system";
        values = recursiveUpdate {
          instance = {
            cluster.networkPolicy = true;
            distribution = {
              registry = "ghcr.io/fluxcd";
              version = "2.x";
            };
            kustomize.patches = [
              {
                patch = ''
                  - op: add
                    path: /spec/decryption
                    value:
                      provider: sops
                      secretRef:
                        name: sops-age
                '';
                target.kind = "Kustomization";
              }
            ];
          };
        } cfg.addons.flux.instance.extraConfig;
      };

      "flux-operator" = {
        inherit (cfg.addons.flux.operator) version;
        createNamespace = true;
        failurePolicy = "abort";
        hash = "sha256-gt8bZ5oLw05lbUXGTzf6NBppAVuuKl9L9LH4jeROpkM=";
        name = "flux-operator";
        repo = "oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator";
        targetNamespace = "flux-system";
        values = recursiveUpdate {
          web = {
            networkPolicy.create = true;
            config.authentication = {
              anonymous = {
                groups = [ "system:masters" ];
                username = "admin";
              };
              type = "Anonymous";
            };
          };
        } cfg.addons.flux.operator.extraConfig;
      };

      "tofu-controller" = {
        inherit (cfg.addons.flux.tofu) version;
        createNamespace = true;
        failurePolicy = "abort";
        hash = "sha256-YQRWHQwNn+Du9LNcveCBzTnacRDtWNJHwvXxeIxtKcc=";
        name = "tofu-controller";
        repo = "https://flux-iac.github.io/tofu-controller";
        targetNamespace = "flux-system";
        values = recursiveUpdate {
          awsPackage.install = false;
          runner.serviceAccount.allowedNamespaces = [
            "flux-system"
            "shikanime"
          ];
        } cfg.addons.flux.tofu.extraConfig;
      };
    };

    systemd.services.rke2-flux-sops-age = {
      after = [ "rke2-server.service" ];
      description = "Create sops-age secret for flux-system";
      environment.KUBECONFIG = "/etc/rancher/rke2/rke2.yaml";
      preStart = ''
        until ${pkgs.kubectl}/bin/kubectl get namespace flux-system >/dev/null 2>&1; do
          sleep 1
        done
      '';
      script = ''
        if ! ${pkgs.kubectl}/bin/kubectl -n flux-system get secret sops-age >/dev/null 2>&1; then
          ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key | \
            ${pkgs.kubectl}/bin/kubectl -n flux-system create secret generic sops-age \
              --from-file=age.agekey=/dev/stdin \
              --dry-run=client -o yaml | ${pkgs.kubectl}/bin/kubectl apply -f -
        fi
      '';
      serviceConfig.Type = "oneshot";
      wants = [ "rke2-server.service" ];
    };
  };
}
