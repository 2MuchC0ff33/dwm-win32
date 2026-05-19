# justfile — human interface to project tasks

# ─────────────────────────────────────────
# HELP
# ─────────────────────────────────────────

# Show available recipes
default:
    @just --list --unsorted

# ─────────────────────────────────────────
# NIX ENVIRONMENT (PRIMARY)
# ─────────────────────────────────────────

# Enter hermetic development shell
shell:
    nix develop .

# Verify environment integrity
deps:
    nix flake check

# Build for current platform
build:
    nix build .

# Cross-compile for all targets
cross:
    nix build .#all

# Cross-compile for one target
cross-one TARGET:
    nix build .#{{TARGET}}

# CI check
ci:
    nix build .#checks

# ─────────────────────────────────────────
# SETUP (LEGACY — for non-Nix users)
# ─────────────────────────────────────────

# Install all required tools (legacy)
setup-legacy:
    nu scripts/dev-setup.nu

# Verify all required tools present (legacy)
deps-legacy:
    nu scripts/check-deps.nu

# ─────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────

# Clean build artifacts
clean:
    cargo clean
    rm -rf result
