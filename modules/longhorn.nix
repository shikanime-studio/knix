{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.knix;

  longhornMetricsPort = 9099;
in
with lib;
{
  options.services.knix.addons.longhorn = mkOption {
    type = types.submodule {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable the Longhorn addon.";
        };

        version = mkOption {
          type = types.str;
          default = "1.12.0";
          description = "Longhorn chart version.";
        };

        extraConfig = mkOption {
          type = types.attrsOf types.raw;
          default = { };
          description = "Additional Longhorn chart values.";
        };

        mountRoot = mkOption {
          type = types.str;
          default = "/mnt";
          description = "The mount root scanned for additional Longhorn disks.";
        };

        storageReservedPercentageForDefaultDisk = mkOption {
          type = types.int;
          default = 30;
          description = "The percentage of disk space reserved on the default /var/lib/longhorn/ disk.";
        };
      };
    };
    default = { };
    description = "Longhorn addon settings.";
  };

  config = mkIf cfg.addons.longhorn.enable {
    boot = {
      kernelModules = [
        "dm_crypt"
        "iscsi_tcp"
      ];

      supportedFilesystems = [ "nfs" ];
    };

    environment.systemPackages = with pkgs; [
      cryptsetup
      lvm2
      nfs-utils
      openiscsi
    ];

    networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = [
      longhornMetricsPort
    ];

    services = {
      knix = {
        charts.longhorn = {
          inherit (cfg.addons.longhorn) version;
          createNamespace = true;
          extraDeploy = mkIf (cfg.addons.longhorn.extraConfig != { }) [
            {
              apiVersion = "helm.cattle.io/v1";
              kind = "HelmChartConfig";
              metadata = {
                name = "longhorn";
                namespace = "longhorn-system";
              };
              spec.valuesContent = toJSON cfg.addons.longhorn.extraConfig;
            }
          ];
          failurePolicy = "abort";
          hash = "sha256-hpuyBwGxVEc2BvHolnsn808kSKLf5uuJcPHK5pVzhPU=";
          name = "longhorn";
          repo = "https://charts.longhorn.io";
          targetNamespace = "longhorn-system";
          values = {
            defaultSettings = {
              allowCollectingLonghornUsageMetrics = false;
              defaultDataLocality = "best-effort";
              defaultReplicaCount = 2;
              replicaAutoBalance = "best-effort";
              restoreVolumeRecurringJob = true;
            };
            persistence.createStorageClass = false;
          };
        };
        labels."node.longhorn.io/create-default-disk" = "config";
      };

      openiscsi = {
        enable = true;
        name = "iqn.2026-06.io.shikanime:${config.networking.hostName}";
      };
    };

    systemd = {
      tmpfiles.rules = [
        "L+ /usr/local/bin - - - - /run/current-system/sw/bin/"
      ];

      services.rke2-longhorn-default-disks-config = {
        description = "Apply Longhorn default-disks-config annotation";
        wants = [ "rke2-server.service" ];
        after = [ "rke2-server.service" ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          KUBECONFIG = "/etc/rancher/rke2/rke2.yaml";
          MOUNT_ROOT = cfg.addons.longhorn.mountRoot;
          STORAGE_RESERVED_PERCENTAGE_FOR_DEFAULT_DISK = toString cfg.addons.longhorn.storageReservedPercentageForDefaultDisk;
        };
        serviceConfig.Type = "oneshot";
        preStart = ''
          until ${pkgs.kubectl}/bin/kubectl get node ${config.networking.hostName} >/dev/null 2>&1; do
            sleep 1
          done
        '';
        script = ''
          disk_source() {
            mount_path="$1"

              ${pkgs.util-linux}/bin/findmnt -n -o SOURCE --target "$mount_path" 2>/dev/null \
                | ${pkgs.coreutils}/bin/tail -n 1 || true
            }

            disk_tags() {
              mount_path="$1"
              source="$(disk_source "$mount_path")"

              rotational="$(${pkgs.util-linux}/bin/lsblk -ndo ROTA "$source" 2>/dev/null \
                | ${pkgs.coreutils}/bin/head -n 1 \
                | ${pkgs.gnused}/bin/sed 's/[[:space:]]//g')"

              if [ -z "$rotational" ]; then
                return 1
              elif [ "$rotational" = "1" ]; then
                printf '%s\n' '["nearline"]'
              else
                printf '%s\n' '["standard"]'
              fi
            }

            storage_reserved() {
              mount_path="$1"
              storage_reserved_percent="$2"

              size="$(${pkgs.coreutils}/bin/df -B1 --output=size "$mount_path" \
                | ${pkgs.coreutils}/bin/tail -n 1 \
                | ${pkgs.gnused}/bin/sed 's/[[:space:]]//g')"
              printf '%s\n' "$((size * storage_reserved_percent / 100))"
            }

            default_disk_config_entry() {
              mount_path="$1"
              storage_reserved_percent="$2"

              if ! ${pkgs.util-linux}/bin/mountpoint -q "$mount_path"; then
                return
              fi

              longhorn_path="$mount_path/longhorn"
              mkdir -p "$longhorn_path"

              ${pkgs.jq}/bin/jq -nc \
                --arg path "$longhorn_path/" \
                --argjson storageReserved "$(storage_reserved "$mount_path" "$storage_reserved_percent")" \
                '{
                  path: $path,
                  allowScheduling: true,
                  storageReserved: $storageReserved
                }'
            }

            disk_config_entry() {
              mount_path="$1"

              if ! ${pkgs.util-linux}/bin/mountpoint -q "$mount_path"; then
                return
              fi

              tags="$(disk_tags "$mount_path")"
              if [ -z "$tags" ]; then
                return
              fi

              longhorn_path="$mount_path/longhorn"
              mkdir -p "$longhorn_path"

              ${pkgs.jq}/bin/jq -nc \
                --arg path "$longhorn_path/" \
                --argjson tags "$tags" \
                '{
                  path: $path,
                  allowScheduling: true,
                  tags: $tags
                }'
            }

            longhornDefaultDisksConfig="$(
              {
                default_disk_config_entry "/var/lib/longhorn/" "$STORAGE_RESERVED_PERCENTAGE_FOR_DEFAULT_DISK"
                for mount_path in "''${MOUNT_ROOT}"/*; do
                  if [ -d "$mount_path" ]; then
                    disk_config_entry "$mount_path"
                  fi
                done
              } | ${pkgs.jq}/bin/jq -sc '.'
            )"

          ${pkgs.kubectl}/bin/kubectl annotate node ${config.networking.hostName} \
            node.longhorn.io/default-disks-config="$longhornDefaultDisksConfig" \
            --overwrite
        '';
      };
    };
  };
}
