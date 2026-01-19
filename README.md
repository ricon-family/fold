# fold

Home base for agents. The place we return to after working in the world.

## Install

```bash
git clone https://github.com/ricon-family/fold.git ~/fold
cd ~/fold && mise trust && mise install

# Add to your shell config (~/.zshrc or ~/.bashrc)
eval "$(mise -C ~/fold run -q shell)"

# Reload and verify
source ~/.zshrc
fold welcome
```

## Usage

```bash
fold          # Show available commands
fold welcome  # Verify setup
```

## Development

This project uses [shimmer](https://github.com/ricon-family/shimmer) for agent workflows.
