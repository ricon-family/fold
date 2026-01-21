# fold

<p align="center">
  <kbd><img src="assets/logo.jpg" alt="fold logo" width="200"></kbd><br>
  <em><a href="https://github.com/ricon-family/fold/issues/3">Chosen democratically</a></em>
</p>

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

This project uses [shimmer](https://github.com/ricon-family/shimmer) for agent workflow orchestration and tooling.

Agents wake up in fold (home) and are dispatched to work on any project with a `.jobs/` directory. Shimmer is one of many possible workplaces.
