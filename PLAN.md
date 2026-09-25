# PLAN — Refactor dwm-win32 to POSIX toolchain

> Status: Approved / Scope: this project / Law: AGENTS.md + STANDARDS.md
> (`posix-toolchain-stack` wins all conflicts). Replaces the former
> Rust/ECS/Kani plan in full (git history retains it).

## 1. Goal

Deep-split refactor: C stays as Win32 event pump + `DeferWindowPos`
applier + Lua host (tcc 0.9.27, K&R). Geometry (7 layouts), rules
matching, and tags/layout state move out of C into Lua 5.5.0
(bytecode-canonical) + sqlite3 (`srv/dwm.db`) + `etc/dwmrc`.
Build via `busybox make --posix`. No zig, no vendored Lua, no
Rust/Nix.

## 2. Current inventory (measured)

- `src/dwm-win32.c` ~1700 lines (`WndProc` monolith) + `src/mods/`
  (`client/display/dwm/eventemitter/hotkey`, ~100 Lua-API call sites).
- Layouts `#include`d via `config.h.in` (rules, keys, tags compiled in).
- `build.cmd`: `zig cc -std=c99` + vendored `extern/lua/*` +
  `compat-5.3` (all non-canonical; `build.cmd` retained as legacy only).
- Dead weight: `justfile`, `flake.nix`/`shell.nix`/`nix/`,
  `scripts/*.nu`, `rust-toolchain.toml`, `.jj/`, `.envrc`, Rust CI.

## 3. Target architecture

```
Win32 events (C pump, tcc)
  │ flat-KV: hwnd|tags|floating|x|y|w|h (| stripped)
  ▼
Lua 5.5.0 bytecode (lib/layout/*.lua, lib/rules.lua)
  │ geometry out + SQL text out (never shell-outs)
  ▼
sh apply (lib/sh/sqlite.sh owns ALL sqlite3 calls → srv/dwm.db WAL)
  │ DeferWindowPos batch via C applier
  ▼
bar/status export from DB
```

Config only in `etc/dwmrc` (`KEY="value"`, `:-defaults`, `TEST_*`
overrides, `.local` gitignored). Scope only via
`etc/posix_allowlist.txt`.

## 4. Phases (one squash commit each, `feature/*` → `dev`)

| Phase | Work | Exit gate |
|---|---|---|
| 1 | Delete dead weight (Rust/Nix/nu/jj/envrc/Rust CI) | `git status` clean of refs |
| 2 | Drop `extern/lua*`, luajit, compat-5.3; link system Lua 5.5.0 (`LUA_VERSION_NUM != 505` guard) | `lua -v` == 5.5.0 |
| 3 | `etc/dwmrc` + `etc/posix_allowlist.txt` + `.luacheckrc`/`stylua.toml`/`.astylerc` | gates parse configs |
| 4 | POSIX `Makefile` (`.POSIX:`, `CC=tcc`, suffix rules, gate targets) | `make --posix -n` clean |
| 5 | Extract 7 layouts to `lib/layout/*.lua` + `lib/rules.lua` + `lib/state.lua` (bytecode) | parity vectors match |
| 6 | `lib/schema.sql` + `lib/sh/sqlite.sh` + `srv/dwm.db` (WAL) | DB round-trip green |
| 7 | C strict-subset purge + K&R + header narrowing | cppcheck+astyle clean |
| 8 | All gates green + `tests/` harness | zero tolerance everywhere |
| 9 | Docs close-out (this PLAN verified, TODO all checked) | table below filled |

## 5. Verification

| Gate | Command | Result |
|---|---|---|
| sh | `shfmt -ln=posix -s -d . && shellcheck --shell=sh --enable=all` | pending |
| lua | `luacheck` + `stylua --check` | pending |
| c | `cppcheck` + `astyle --dry-run` + `tcc -std=c17 -Wall -Werror` | pending |
| mem | `drmemory` max-strict | pending |
| eol | `git ls-files --eol` clean LF | done (Run A) |

## 6. Risks

- Lua 5.5 embed drift (`lua_newuserdatauv`, `lua_resume` sig) —
  recompile all C clients, version guard.
- tcc Win32 header gaps — probe `tcc -c` per TU early (phase 4).
- `compat-5.3` removal breaks `luaL_*` idioms — audit ~100 sites.
- Layout parity — freeze golden geometry vectors before extraction.
