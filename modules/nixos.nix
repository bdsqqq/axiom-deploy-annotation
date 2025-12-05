# NixOS module for Axiom deploy annotations
{ lib, pkgs, config, ... }:

let
  cfg = config.services.axiom-deploy-annotation;
  stateDir = "/var/lib/axiom-deploy-annotation";
  
  annotateScript = pkgs.writeShellScript "axiom-deploy-annotate" ''
    set -euo pipefail

    AXIOM_TOKEN_PATH="${cfg.tokenPath}"
    AXIOM_API="${cfg.apiEndpoint}"
    STATE_DIR="${stateDir}"
    STATE_FILE="$STATE_DIR/last-generation"

    mkdir -p "$STATE_DIR"

    if [[ ! -f "$AXIOM_TOKEN_PATH" ]]; then
      echo "axiom-deploy-annotate: token not found at $AXIOM_TOKEN_PATH, skipping"
      exit 0
    fi

    PROFILE_PATH="/nix/var/nix/profiles/system"

    if [[ ! -L "$PROFILE_PATH" ]]; then
      echo "axiom-deploy-annotate: system profile not found, skipping"
      exit 0
    fi

    CURRENT_GEN="$(readlink "$PROFILE_PATH" | grep -oE '[0-9]+' | tail -1)"
    
    if [[ -f "$STATE_FILE" ]]; then
      LAST_GEN="$(cat "$STATE_FILE")"
      if [[ "$CURRENT_GEN" == "$LAST_GEN" ]]; then
        echo "axiom-deploy-annotate: gen $CURRENT_GEN already annotated, skipping"
        exit 0
      fi
    fi

    AXIOM_TOKEN="$(cat "$AXIOM_TOKEN_PATH")"
    HOSTNAME="$(hostname -s)"
    TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    STORE_PATH="$(readlink -f "$PROFILE_PATH")"
    
    GIT_REV=""
    if [[ -x "/run/current-system/sw/bin/nixos-version" ]]; then
      GIT_REV="$(/run/current-system/sw/bin/nixos-version --configuration-revision 2>/dev/null)" || true
    fi
    GIT_REV="''${GIT_REV%-dirty}"
    GIT_REV_SHORT="''${GIT_REV:0:7}"

    echo "axiom-deploy-annotate: creating annotation for $HOSTNAME gen $CURRENT_GEN ($GIT_REV_SHORT)..."

    DATASETS_JSON='${builtins.toJSON cfg.datasets}'
    
    ${lib.optionalString (cfg.repositoryUrl != null) ''
    URL=""
    if [[ -n "$GIT_REV" ]]; then
      URL="${cfg.repositoryUrl}/commit/$GIT_REV"
    fi
    ''}

    PAYLOAD=$(cat <<EOF
{
  "time": "$TIMESTAMP",
  "type": "${cfg.annotationType}",
  "datasets": $DATASETS_JSON,
  "title": "$HOSTNAME gen $CURRENT_GEN''${GIT_REV_SHORT:+ ($GIT_REV_SHORT)}",
  "description": "nix generation $CURRENT_GEN deployed to $HOSTNAME\n\ncommit: $GIT_REV\nstore path: $STORE_PATH"${lib.optionalString (cfg.repositoryUrl != null) '',
  "url": "$URL"''}
}
EOF
    )

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$AXIOM_API" \
      -H "Authorization: Bearer $AXIOM_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" 2>&1) || true

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)

    if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
      echo "$CURRENT_GEN" > "$STATE_FILE"
      echo "axiom-deploy-annotate: annotation created for $HOSTNAME gen $CURRENT_GEN"
    else
      echo "axiom-deploy-annotate: axiom api returned $HTTP_CODE (non-fatal)"
    fi
  '';
in
{
  options.services.axiom-deploy-annotation = {
    enable = lib.mkEnableOption "Axiom deploy annotations";
    
    tokenPath = lib.mkOption {
      type = lib.types.path;
      default = "/run/secrets/axiom_token";
      description = "Path to file containing the Axiom API token";
    };
    
    apiEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://api.axiom.co/v2/annotations";
      description = "Axiom API endpoint for annotations";
    };
    
    datasets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "deployments" ];
      example = [ "logs" "metrics" ];
      description = "Axiom datasets to attach the annotation to";
    };
    
    annotationType = lib.mkOption {
      type = lib.types.str;
      default = "nix-deploy";
      description = "Type field for the annotation";
    };
    
    repositoryUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://github.com/user/repo";
      description = "GitHub/GitLab repository URL for commit links";
    };
  };
  
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "axiom-deploy-annotate" ''
        exec ${annotateScript}
      '')
    ];
    
    systemd.services.axiom-deploy-annotation = {
      description = "Create Axiom annotation after NixOS rebuild";
      wantedBy = [ "multi-user.target" ];
      
      restartTriggers = [ config.system.configurationRevision ];
      
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      
      path = with pkgs; [ coreutils gnugrep curl jq nettools ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = annotateScript;
        StateDirectory = "axiom-deploy-annotation";
      };
    };
  };
}
