# fold

## Development

This project uses [shimmer](https://github.com/ricon-family/shimmer) for agent workflows.

To set up shimmer:

1. Clone shimmer to your workspace:
   ```bash
   git clone https://github.com/ricon-family/shimmer.git ~/shimmer
   cd ~/shimmer && mise trust && mise install
   ```

2. Add to your shell config (`~/.zshrc` or `~/.bashrc`):
   ```bash
   eval "$(mise -C ~/shimmer run -q shell)"
   ```

3. Reload your shell and run `shimmer welcome` to verify.
