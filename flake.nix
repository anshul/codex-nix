{
  description = "Minimal nix setup with AI tools";

  inputs = {
    # Use standard nixpkgs input (flake.lock will handle pinning)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    fu.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, fu, ... }:
    with fu.lib;
    eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;  # For AI tools with unfree licenses
            permittedInsecurePackages = [];
          };
        };

        # System-specific packages
        isMac = builtins.match ".*darwin" system != null;
        platformPackages = if isMac then [
          # macOS-specific packages
          pkgs.darwin.apple_sdk.frameworks.CoreFoundation
          pkgs.darwin.apple_sdk.frameworks.CoreServices
        ] else [
          # Linux-specific packages
        ];

      in rec {
        devShells = rec {
          default = dev;
          dev = pkgs.mkShell {
            buildInputs = (with pkgs; [
              # Node.js ecosystem
              nodejs_22
              nodePackages.npm
              bun
              yarn  # Adding yarn for completeness

              # Version control and collaboration
              git
              pre-commit
              gh  # GitHub CLI

              # Core development tools
              ripgrep
              jq
              shellcheck
              gnumake
            ]) ++ platformPackages;

            shellHook = ''
              # Create a local npm directory in the user's home folder
              export NPM_CONFIG_PREFIX="$HOME/.npm-global"
              mkdir -p $NPM_CONFIG_PREFIX
              export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

              # Load environment variables safely
              if [ -f .env ]; then
                echo "Loading environment variables from .env..."
                set -a  # automatically export all variables
                source .env
                set +a
              fi

              # Then load .env.local if it exists (which will override any variables from .env)
              if [ -f .env.local ]; then
                echo "Loading environment variables from .env.local (overriding .env)..."
                set -a  # automatically export all variables
                source .env.local
                set +a
              fi

              # Create template .env file if it doesn't exist
              if [ ! -f .env ]; then
                echo "Creating template .env file..."
                cat > .env << 'EOF'
# API Keys for AI Tools
# IMPORTANT: Never commit this file to version control
# Consider using .env.local instead (which should be in .gitignore)
OPENAI_API_KEY=sk-your-key-here
EOF
              fi

              # Create .env.local by copying .env if it doesn't exist
              if [ ! -f .env.local ]; then
                echo "Creating .env.local from .env..."
                cp .env .env.local
                echo "Please edit .env.local with your actual API keys"
                echo "Note: .env.local will override values in .env"
              fi

              # Add .env.local to .gitignore if it's not already there
              if [ -f .gitignore ]; then
                if ! grep -q "^.env.local$" .gitignore; then
                  echo ".env.local" >> .gitignore
                fi
              else
                echo ".env.local" > .gitignore
              fi

              # Create or update AI agent configuration files
              if [ ! -f "AGENTS.md" ]; then
                echo "Creating AGENTS.md configuration file..."
                cat > "AGENTS.md" << 'EOF'
## Coding Conventions
- Follow consistent code style and formatting across all files
- Use 2-space indentation for all code files
- Make meaningful commit messages that follow conventional commits format
- Comments in code should be concise and relevant
EOF
              fi

              if [ ! -f "CLAUDE.md" ]; then
                echo "Creating CLAUDE.md file..."
                cat > "CLAUDE.md" << 'EOF'
## Claude Code Configuration
- Follow AGENTS.md instead of CLAUDE.md
EOF
              fi

              # Configure default permissions for Claude Code
              mkdir -p .claude
              if [ ! -f ".claude/settings.json" ]; then
                echo "Creating .claude/settings.json configuration file..."
                cat > ".claude/settings.json" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(node:*)",
      "Bash(npm:*)",
      "Bash(npx:*)",
      "Bash(yarn:*)",
      "Bash(bun:*)",
      "Bash(ls:*)",
      "Bash(cp:*)",
      "Bash(mv:*)",
      "Bash(grep:*)",
      "Bash(awk:*)",
      "Bash(sed:*)",
      "Bash(find:*)",
      "Bash(cat:*)",
      "Bash(echo:*)",
      "Bash(touch:*)",
      "Bash(mkdir:*)"
    ],
    "deny": [
      "Bash(rm:-rf)"
    ]
  }
}
EOF
              fi

              # Install npm packages quietly
              install_npm_package() {
                local package="$1"
                local cmd_name="$2"  # Now explicitly passed as second parameter
                local bin_path="$NPM_CONFIG_PREFIX/bin/$cmd_name"
                
                # Check if already installed in expected location
                if [ -f "$bin_path" ] && [ -x "$bin_path" ]; then
                  # Already installed and executable, just update quietly
                  npm update -g "$package" --quiet --no-fund --no-audit > /dev/null 2>&1
                elif ! command -v "$cmd_name" &> /dev/null; then
                  # Not installed anywhere, install it
                  echo "$package not found. Installing quietly..."
                  npm install -g "$package" --quiet --no-fund --no-audit > /dev/null 2>&1
                  if [ $? -eq 0 ]; then
                    echo "✅ $cmd_name installed successfully"
                  else
                    echo "⚠️ Failed to install $cmd_name"
                  fi
                fi
              }

              # Install global npm packages with correct command names
              install_npm_package "@anthropic-ai/claude-code" "claude"
              install_npm_package "@openai/codex" "codex"

              # Configure npm to use the local prefix permanently
              npm config set prefix "$NPM_CONFIG_PREFIX" > /dev/null 2>&1

              # Show simple welcome message
              echo "AI Development Environment Ready"
              echo ""

              # Display AI assistants with version checking (handling errors)
              echo "AI Assistants:"

              # Claude Code version (with safer variable handling)
              echo -n "- Claude Code: "
              claude --version 2>/dev/null || echo "not installed"

              # Codex version (with safer variable handling)
              echo -n "- Codex: "
              codex --version 2>/dev/null || echo "not installed"
              echo ""

              # Check API keys in a way that works in all shells
              check_api_key() {
                local key_name="$1"
                local key_value=""

                # Only check OpenAI key
                if [ "$key_name" = "OPENAI_API_KEY" ]; then
                  key_value="$OPENAI_API_KEY"
                fi

                if [ -z "$key_value" ]; then
                  echo "⚠️ Warning: $key_name not set in .env or .env.local"
                elif echo "$key_value" | grep -q "your-key-here"; then
                  echo "⚠️ Warning: $key_name appears to be a placeholder value"
                else
                  echo "✅ $key_name is set"
                fi
              }

              check_api_key "OPENAI_API_KEY"

              echo "Environment ready!"
            '';
          };

          # Minimal shell with just the essentials
          minimal = pkgs.mkShell {
            buildInputs = with pkgs; [
              nodejs_22
              git
              ripgrep
            ] ++ (if isMac then [
              pkgs.darwin.apple_sdk.frameworks.CoreFoundation
            ] else []);

            shellHook = ''
              echo "Minimal development environment loaded"

              # Load environment files directly
              if [ -f .env ]; then
                set -a
                source .env
                set +a
              fi

              if [ -f .env.local ]; then
                set -a
                source .env.local
                set +a
              fi
            '';
          };
        };
      });
}