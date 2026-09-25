# TODO — POSIX refactor tracker

> One box per task. Append `(done: <hash>)` at merge time.
> Law: AGENTS.md + STANDARDS.md. Roadmap: PLAN.md.

- [ ] TODO-01 Delete Rust/Nix dead weight (justfile, flake/shell/nix, scripts/*.nu, rust-toolchain, .jj, .envrc, Rust CI) [phase 1]
- [ ] TODO-02 Drop extern/lua*, luajit, luabitop, compat-5.3; link system Lua 5.5.0 [phase 2]
- [ ] TODO-03 etc/dwmrc + etc/posix_allowlist.txt + .luacheckrc/stylua.toml/.astylerc [phase 3]
- [ ] TODO-04 POSIX Makefile (CC=tcc, suffix rules, gate targets) [phase 4]
- [ ] TODO-05 Extract 7 layouts to lib/layout/*.lua bytecode [phase 5]
- [ ] TODO-06 lib/rules.lua + lib/state.lua + lib/schema.sql + lib/sh/sqlite.sh [phase 5–6]
- [ ] TODO-07 C strict-subset purge + K&R + header narrowing [phase 7]
- [ ] TODO-08 All gates green + tests/ harness [phase 8]
- [ ] TODO-09 Docs close-out (PLAN verify table, api.md rewrite, README pointers) [phase 9]
- [ ] TODO-10 (carried from README) child-window tag switching via ismanageable() tweak
- [ ] TODO-11 (carried from README) fullscreen/mstsc maximize resize fix
- [ ] TODO-12 (carried from README) DeferWindowPos batching (Begin/Defer/End)
- [ ] TODO-13 (carried from README) CBTProc + SetWindowsHookEx event path investigation
- [ ] TODO-14 (carried from README) status text via stdin or separate tool
- [ ] TODO-15 (carried from README) crash handler (restore windows/borders)
- [ ] TODO-16 (carried from README) multi-head support
- [ ] TODO-17 Delete config.h.in (replaced by etc/dwmrc) [phase 5]
