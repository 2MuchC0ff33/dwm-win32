# STANDARDS.md — Canonical POSIX Toolchain Law

> Version: 2.0.0 / Status: Approved / Scope: this project only.
> Replaces v1.0.0 Rust/Kani/Nix standard in full.

## 0. Identity

- POSIX.1-2024 = IEEE 1003.1-2024 / Issue 8. Issue 8 names C17
  (ISO/IEC 9899:2018). DBMS out of scope.
- MANDATE: say `POSIX-mandated (XCU/XSH)` vs `admitted extension
  (pinned, audited)`.
- FORBIDDEN: calling Lua, sqlite3, flat-KV, rc files "POSIX".
- Index: `posix-toolchain-stack` skill wins all conflicts.
- Scope: `etc/posix_allowlist.txt` per-project allow-list. Only
  listed utilities/options may be invoked.

## 1. Stack

| # | Component | Status | Pin | Use |
|---|---|---|---|---|
| 1 | sh glue | mandated | busybox-w32 v1.38.0.git-7099 (mingit-busybox 2.55.0.5) | orchestration, pipes only |
| 2 | awk stream | mandated | busybox awk | filters, splits, parsing |
| 3 | Lua logic | admitted | 5.5.0 stdlib-only, luacheck 1.2.0, stylua 2.5.2 | primary scripting, bytecode-canonical |
| 4 | C hot-path | optional-standard c17 | tcc 0.9.27, cppcheck 2.21.0, astyle 3.6.18, drmemory 2.6.20434 | measured hot paths only |
| 5 | sqlite3 state | admitted | 3.53.4 (2026-07-24) | persistence, sh owns invocations |
| 6 | flat-KV | convention | `|` reserved/stripped | inter-stage interchange |
| 7 | make build | optional-standard | `busybox make --posix` | DAG only, suffix rules |
| 8 | *rc config | convention | `KEY="value"` sourced | all knobs, no hard-codes |
| 9 | fetcher | exception | busybox wget frozen flags | HTTPS fetch only |

## 2. Language rules

- MANDATE sh: `#!/bin/sh` + `set -eu`. `.` not `source`. `printf`
  not `echo -n/-e`. `type` not `command -v`. No `[[`/`((`/arrays/
  `local`/`function`/`select`. No Issue-8 `$''`/`;&`/`read -d` here.
- MANDATE awk: `-v var="$val"`, never expand in program.
  `tolower()+match` never `IGNORECASE`. Buffer+`split()` never
  multi-char `RS`. `date +%s` never `systime()/strftime()`.
  `[[:space:]]` never `\s`.
- MANDATE Lua: header `assert(_VERSION=="Lua 5.5")`. No
  luarocks/C/FFI, no `io.popen`/`os.execute`, no
  `string.dump`/`loadstring`, no `require socket|lfs`.
  Build `luac -s -o var/build/<n>.luac lib/<n>.lua`; run bytecode.
- MANDATE C: tcc-compatible C17 subset, K&R `--style=kr`.
  Allowed headers: stdint/inttypes/stdbool/stddef/stdlib/string/
  stdio/limits/assert/float/errno/math/signal/time.
  FORBIDDEN: `__attribute__`/`typeof`/`asm`/VLA/`_Complex`/
  `_Generic`/`_Atomic`. `//` comments allowed. `uint8_t`/`int8_t`
  explicit. Never assert `__STDC_VERSION__>=201710L` (tcc reports 199901).
- MANDATE sqlite: `sh` owns all CLI calls. Lua generates/parses
  text only. `PRAGMA journal_mode=WAL;` per DB.
- MANDATE KV: strip `|` from data. Internal
  `hwnd|tags|floating|x|y|w|h` (window records).
  Final RFC4180-minimal CSV.
- MANDATE make: first line `.POSIX:`. Suffix rules only. Recipes
  are `sh`. No `%`/`include`/`shell`/`wildcard`.
- MANDATE rc: `KEY="value"`, explicit `. ./etc/*.rc`, `:-defaults`,
  `TEST_*` env wins, `*.local` overlay gitignored.
- FORBIDDEN fetcher: curl, aria2c, `wget --timeout`, `timeout` applet.

## 3. Windows

- MANDATE: pipe Lua stdout through `tr -d '\r'`.
- MANDATE: `TMPDIR="$ROOT/tmp"` for Lua/sqlite temp.
- MANDATE: repo-relative or `C:/` paths only.

## 4. Gates

All must pass, zero tolerance. See AGENTS.md §4 for commands:
shfmt+shellcheck, luacheck+stylua, cppcheck+astyle, drmemory,
`busybox make --posix -n -f Makefile`.

## 5. Probes

```sh
lua -v; luac -v; luacheck --version; stylua --version
tcc -vv; sqlite3 --version; cppcheck --version
astyle --version; drmemory -version; busybox | head -n 1
```

## 6. Git

- MANDATE: `master` is a pristine upstream mirror — never commit
  there. `dev` is the integration mainline: cut `feature/*` from
  `dev`, squash-merge into `dev`, one commit per run, no merge
  bubble. Push to `origin/dev` and full cleanup sweep are autonomous
  (no operator wait). Remotes: `origin` = this fork (sole push
  target); `upstream` = `git@github.com:prabirshrestha/dwm-win32.git`
  (fetch-only). Procedure: AGENTS.md §7.
- MANDATE: LF everywhere (`* text=auto eol=lf`); only `.cmd`/`.bat`
  are CRLF; `extern/**` is `-text` vendored. Procedure: AGENTS.md §8.
