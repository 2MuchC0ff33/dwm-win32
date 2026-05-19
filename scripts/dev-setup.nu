#!/usr/bin/env nu
# dev-setup.nu
# Thin wrapper around nix develop.
# The canonical setup is: nix develop .

def main [] {
    print "Setting up development environment via Nix..."
    let result = (^nix develop . o+e>| complete)
    if $result.exit_code != 0 {
        error make {msg: $"Environment setup failed: ($result.stderr)"}
    }
    print $"(ansi green)Development environment ready. Run 'nix develop .' to enter.(ansi reset)"
}
