{
  description = "Axiom deploy annotations for NixOS and nix-darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosModules.default = import ./modules/nixos.nix;
    nixosModules.axiom-deploy-annotation = self.nixosModules.default;
    
    darwinModules.default = import ./modules/darwin.nix;
    darwinModules.axiom-deploy-annotation = self.darwinModules.default;
  };
}
