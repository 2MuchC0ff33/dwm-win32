# AGENTS.md — dwm-win32 Agent Law

> Fail-closed. Violations stop work. No silent fallbacks.

## 0. Index law

- Canonical stack: `posix-toolchain-stack` skill. It wins on every conflict.
- Scope law: `etc/posix_allowlist.txt` (create per project). Only listed
  utilities/options may be invoked.
- POSIX.1-2024 = IEEE 1003.1-2024 / Issue 8. Say `POSIX-mandated (XCU/XSH)`
  vs `admitted extension (pinned, audited)`. Never call Lua, sqlite3,
  flat-KV, or rc files "POSIX".

## 1. Invocation (fail-closed)

- Shell: `busybox sh -c '...'` / `busybox ash -c '...'` only.
- BANNED: `python -c`, `python3 -c`, `node -e`, `pwsh -Command`,
  `powershell -Command`, `bash` shim. Fail closed if busybox missing.
- Quoting: single-quote the `sh -c` script. Never prefix with `$`
  (`$busybox` is wrong). Forward slashes `c:/path`. Quote paths with
  spaces inside: `busybox sh -c 'wc -c "c:/path with spaces/file"'`.
- Use `read`/`grep`/`glob` for search/read; busybox only for pipelines.

## 2. Ladder

1. `sh` — orchestration/glue only. `#!/bin/sh` + `set -eu`. `.` not
   `source`. `printf` not `echo -n/-e`. `type` not `command -v`.
   No `[[`/`((`/arrays/`local`/`function`/`select`.
2. `awk` — all stream/text. `-v var="$val"`, never expand in program.
   `tolower()+match` never `IGNORECASE`. Buffer+`split()` never
   multi-char `RS`. `date +%s` never `systime()/strftime()`.
   `[[:space:]]` never GNU `\s`.
3. `Lua 5.5.0` stdlib-only — primary scripting. Header
   `assert(_VERSION=="Lua 5.5")`. No luarocks/C modules/FFI,
   no `io.popen`/`os.execute`, no `string.dump`/`loadstring`,
   no `require socket|lfs`. Bytecode-canonical: `luac -s -o
   var/build/<n>.luac lib/<n>.lua`, run bytecode only.
4. `C17 via tcc 0.9.27` — hot-path only. K&R `--style=kr`. Allowed
   headers: stdint/inttypes/stdbool/stddef/stdlib/string/stdio/
   limits/assert/float/errno/math/signal/time. No
   `__attribute__/typeof/asm/VLA/_Complex/_Generic/_Atomic`.
5. `sqlite3 3.53.4` — primary DB. `sh` owns ALL invocations. Lua never
   shell-outs. `PRAGMA journal_mode=WAL;` per DB.
6. `flat-KV` — interchange. `|` reserved/stripped. Internal
   `hwnd|tags|floating|x|y|w|h`. Final RFC4180-minimal CSV.
7. `make` — `busybox make --posix` only. First line `.POSIX:`.
   Suffix rules only. No `%`/`include`/`shell`/`wildcard`/`+=` abuse.
8. `*rc` — config only here (`etc/dwmrc`). `KEY="value"`, sourced,
   `:-defaults`, `TEST_*` env overrides. `*.local` overlay gitignored.
   State in `srv/dwm.db`. Lua bytecode run via `lua_bytecode()`
   (`var/build/*.luac`).

## 3. Pins

| Component | Pin |
|---|---|
| busybox | w32 v1.38.0.git-7099 via scoop mingit-busybox 2.55.0.5, 179 applets |
| Lua | 5.5.0, `luac` 5.5.0, `luacheck` 1.2.0, `stylua` 2.5.2 |
| C | tcc 0.9.27, `cppcheck` 2.21.0, `astyle` 3.6.18, `drmemory` 2.6.20434 |
| sqlite3 | 3.53.4 (2026-07-24) |
| fetcher | busybox `wget` frozen `-O -U --tries -q -S --no-check-certificate` only |

Probes:

```sh
lua -v; luac -v; luacheck --version; stylua --version
tcc -vv; sqlite3 --version; cppcheck --version
astyle --version; drmemory -version; busybox | head -n 1
busybox make --posix -n -f Makefile
```

## 4. Gates (all must pass)

```sh
busybox sh -c 'shfmt -ln=posix -s -d . && shellcheck --shell=sh --enable=all *.sh'
busybox sh -c 'luacheck --no-cache --codes --config .luacheckrc lib/*.lua'
busybox sh -c 'stylua --check --verify --respect-ignores lib/*.lua'
busybox sh -c 'cppcheck --std=c17 --language=c --platform=win64 --enable=all --check-level=exhaustive --inconclusive --force --inline-suppr --error-exitcode=1 --library=posix -D_POSIX_C_SOURCE=202405L --suppress=missingIncludeSystem --suppress=checkersReport src/*.c'
busybox sh -c 'astyle --dry-run --error-on-changes --suffix=none src/*.c'
```

Zero tolerance everywhere. tcc accepts `-std=c17` but
`__STDC_VERSION__` stays 199901 — never assert `>=201710L`.

## 5. dwm-win32 annex

- `CC=tcc`. `build.cmd`/zig cc is legacy, not canonical.
- K&R braces (function braces broken, inner attached). No C++ comments
  policy change — `//` allowed per C99 portable subset.
- Win32 guards: `#ifdef _WIN32` / `#ifdef __TINYC__` only.
- `char` signedness: use `uint8_t`/`int8_t` explicitly.
- Windows: pipe Lua stdout through `tr -d '\r'`; `TMPDIR="$ROOT/tmp"`;
  repo-relative or `C:/` paths only.

## 6. Windows notes

System Lua writes CRLF. BusyBox `/tmp` differs from system-Lua `/tmp`.

## 7. Git law (autonomous, fail-closed)

`master` is a pristine upstream mirror — never commit or work there.
`dev` is the integration mainline. Cut every `feature/*` from `dev`,
squash-merge into `dev`. Opencode commits, squash-merges, pushes to
`origin/dev`, and cleans up WITHOUT waiting for operator approval on
every completed run.

```sh
git stash -u
git checkout dev
git checkout -b <feature-branch>
git stash pop
# ... work ...
git add -A
git commit -m "<concise imperative summary>"
git checkout dev
git merge --squash <feature-branch>
git commit -m "<same concise message>"
git push origin dev
git branch -D <feature-branch>
git reflog expire --expire=now --all
git gc --aggressive --prune=now
git fsck --full --strict
```

One commit per run, no merge bubble. Branch commit is squash fodder
only. `fsck` must print silence. Restore harness-mutated fixtures
before staging.

### 7.1 Upstream fork-sync

- `origin` = this fork (sole push target).
- `upstream` = `git@github.com:prabirshrestha/dwm-win32.git`
  (fetch-only, never pushed, never PR'd unless instructed).
- Sync: `git checkout master && git fetch upstream &&
  git merge --ff-only upstream/master && git push origin master`,
  then rebase feature and `git push --force-with-lease` backup.
- `master` stays pristine mirror; project work on `<feature>` only.

## 8. Line endings (fail-closed)

- LF everywhere: `* text=auto eol=lf` in `.gitattributes`.
- Exemptions: `*.cmd`/`*.bat` → `text eol=crlf`; `extern/**` →
  `-text linguist-vendored` (vendored, never renormalized).
- `*.sh` → `text eol=lf` (shebang scripts break on CRLF).
- Per-clone: `git config core.autocrlf false`,
  `git config core.eol lf`, `git config core.safecrlf true`
  (neutralizes mingit global `autocrlf=true`).
- Gate: `git ls-files --eol` must show `i/lf w/lf` for owned text
  (only `.cmd/.bat` may show `w/crlf`).
