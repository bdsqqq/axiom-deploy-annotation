# axiom-deploy-annotation

[axiom](https://axiom.co) annotations after every nixos/nix-darwin rebuild.

<picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/c3ba6b6f-50ca-41f9-8c56-6d4fc50403d0" />
    <source media="(prefers-color-scheme: light)" srcset="https://github.com/user-attachments/assets/6c20d9a3-e050-4cea-ad90-003119b67bf3" />
    <img alt="" src="https://github.com/user-attachments/assets/6c20d9a3-e050-4cea-ad90-003119b67bf3" />
</picture>

annotations appear on charts across the axiom app, marking when deployments happened with commit hash, generation number, and store path.

## usage

### add to flake inputs

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    axiom-deploy-annotation.url = "github:bdsqqq/axiom-deploy-annotation";
  };
}
```

### nixos

```nix
{
  imports = [ inputs.axiom-deploy-annotation.nixosModules.default ];
  
  services.axiom-deploy-annotation = {
    enable = true;
    tokenPath = config.sops.secrets.axiom_token.path;  # or any path readable by 'user'
    datasets = [ "logs" "metrics" ];
    repositoryUrl = "https://github.com/you/your-dots";
    user = "youruser";   # service runs as this user
    group = "users";     # service runs as this group
  };
}
```

### nix-darwin

```nix
{
  imports = [ inputs.axiom-deploy-annotation.darwinModules.default ];
  
  services.axiom-deploy-annotation = {
    enable = true;
    tokenPath = config.sops.secrets.axiom_token.path;
    datasets = [ "logs" "metrics" ];
    repositoryUrl = "https://github.com/you/your-dots";
  };
}
```

## options

### common options (nixos + darwin)

| option | type | default | description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | enable the annotation service |
| `tokenPath` | path | `/run/secrets/axiom_token` | path to file containing axiom api token |
| `apiEndpoint` | string | `https://api.axiom.co/v2/annotations` | axiom api endpoint |
| `datasets` | list of strings | `["deployments"]` | axiom datasets to attach annotation to |
| `annotationType` | string | `"nix-deploy"` | type field for the annotation |
| `repositoryUrl` | string or null | `null` | github/gitlab url for commit links |

### nixos-only options

| option | type | default | description |
|--------|------|---------|-------------|
| `user` | string | `"root"` | user to run the service as. tokenPath must be readable by this user |
| `group` | string | `"root"` | group to run the service as |

the service runs with aggressive systemd hardening (`CapabilityBoundingSet=""`, `ProtectSystem=strict`, etc). this means it can only read files owned by the configured user—even when running as root. set `user` to match your secret ownership.

## how it works

### nixos

systemd oneshot service with `restartTriggers = [ config.system.configurationRevision ]`. the service restarts after activation completes, when `/run/current-system` points to the new system.

### nix-darwin

activation script hook that runs during `darwin-rebuild switch`. executes as root during the activation phase.

## requirements

- axiom account and api token with annotation permissions
- `system.configurationRevision` set in your flake (for commit hash tracking)

example flake.nix:

```nix
{
  outputs = { self, nixpkgs, ... }:
    let
      flakeRevision = self.rev or self.dirtyRev or "unknown";
    in {
      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        modules = [{
          system.configurationRevision = flakeRevision;
        }];
      };
    };
}
```

## annotation format

```json
{
  "time": "2024-12-04T19:39:23Z",
  "type": "nix-deploy",
  "datasets": ["logs", "metrics"],
  "title": "myhost gen 42 (abc1234)",
  "description": "nix generation 42 deployed to myhost\n\ncommit: abc1234...\nstore path: /nix/store/...",
  "url": "https://github.com/you/repo/commit/abc1234..."
}
```

## manual annotation

run `axiom-deploy-annotate` to manually create an annotation for the current generation.

## license

mit
