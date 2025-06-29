{
  description = "Development environment for notion.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: {
        packages.notion-nvim = pkgs.vimUtils.buildVimPlugin {
          dependencies = with pkgs.vimPlugins; [plenary-nvim];
          pname = "notion-nvim";
          version = "unstable";
          src = ./.;

          meta = with pkgs.lib; {
            description = "Neovim plugin for Notion integration";
            homepage = "https://github.com/ALT-F4-LLC/notion.nvim";
            license = licenses.asl20;
            maintainers = [];
            platforms = platforms.all;
          };
        };

        packages.default = self'.packages.notion-nvim;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            entr
            lua5_4
            lua54Packages.busted
            lua54Packages.luacheck
            lua54Packages.luacov
            luajit
            luarocks
            yamllint
          ];

          shellHook = ''
            echo "🚀 Welcome to notion.nvim development environment!"
            echo ""
            echo "Available Lua versions:"
            echo "  - lua: $(lua -v)"
            echo "  - luajit: $(luajit -v)"
            echo ""
            echo "Development tools:"
            echo "  - luarocks: $(luarocks --version)"
            echo "  - busted: $(busted --version)"
            echo "  - luacheck: $(luacheck --version)"
            echo ""
            echo "Quick start:"
            echo "  make test         # Run tests"
            echo "  make test-watch   # Watch and run tests"
            echo "  make lint         # Lint code"
            echo "  make test-coverage# Run tests with coverage"
          '';
        };

        # Formatter for the flake
        formatter = pkgs.nixpkgs-fmt;
      };
    };
}
