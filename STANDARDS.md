# Complete Project Standard Framework

> **Version:** 1.0.0
> **Status:** Approved
> **Scope:** All projects under this organization — new development, rewrites, and migrations
> **License:** MIT OR Apache-2.0 (same as project code)

---

## Preamble

### P.1 Document Purpose

This standard is the **single source of truth** for ALL software development under this
organization. Every rule, recommendation, and mandate exists for one of four reasons:

1. **Correctness** — the code MUST do what it says, provably
2. **Maintainability** — the code MUST be readable by any team member, now and in 5 years
3. **Portability** — the code MUST build and run on any target platform without modification
4. **Auditability** — every decision MUST be visible, reviewable, and explainable

### P.2 How To Read This Document

| Marker | Meaning |
|--------|---------|
| `MANDATE` | Absolute requirement. Project does not comply without this. |
| `SHOULD` | Strong recommendation. Deviation MUST be documented in the project's README with rationale. |
| `MAY` | Optional choice. Pick per-project. |
| `FORBIDDEN` | Never do this. No exceptions without governance board approval. |
| `RATIONALE` | Explains WHY a rule exists. Not optional reading — understanding why prevents cargo-culting. |

### P.3 How To Apply This Standard

```
Step 1:  Copy the repository structure (Part 2)
Step 2:  Update Cargo.toml metadata for your project (Part 3)
Step 3:  Run dev-setup.nu to install the toolchain (Part 11)
Step 4:  Configure CI pipeline per-project (Part 6, 7, 9)
Step 5:  Consult Part 13 to remove sections that don't apply to your project type
Step 6:  Record this STANDARDS.md as the first tracked state
Step 7:  Open an issue for every deviation from this standard you discover during setup
```

### P.4 Standard Versioning

This standard itself follows semantic versioning. Changes are tracked in the VCS history
of `STANDARDS.md`. Projects pin to a specific version by copying the standard at that
version. When the standard updates, projects evaluate migration at their own cadence,
but MUST comply with the new standard within 6 months of release.

---

## Part 0: Guiding Philosophies

### 0.1 Suckless-Inspired Code Design

#### 0.1.1 What It Means HERE

The suckless philosophy — software should do one thing, do it well, and be as simple as
possible — applies to the **code you ship to users**, not the infrastructure around it.

The code you write MUST be:

- **Minimal**: every line justifies its existence. If removing it doesn't break core
  functionality, remove it.
- **Single-purpose**: one function, one responsibility. One module, one concern.
  One binary, one job.
- **Readable**: a competent Rust developer should understand any function in under
  30 seconds. If they can't, the function is too complex.
- **Self-contained**: prefer local reasoning over cross-module mental state.
  Pure functions over side-effectful ones. Data-in, data-out.

#### 0.1.2 What It Does NOT Mean

Suckless does NOT mean:

- No dependencies (use libraries; don't rewrite libc)
- No abstractions (abstractions are fine when they MAKE CODE SIMPLER)
- No tooling (tooling is infrastructure, not shipped code)
- C language (Rust is safer while equally expressive)
- Terminal-only (GUI applications can be minimal too)

#### 0.1.3 Code Design Rules

```
MANDATE: No file exceeds 500 lines without justification in a comment at the top.
MANDATE: No function exceeds 40 lines (one terminal screen).
MANDATE: One purpose per function. If a function has "and" in its name,
         it does too many things.
MANDATE: No dead code. If it compiles but is never called, remove it.
MANDATE: No commented-out code. Use VCS history (`jj log` / `pijul log`).
MANDATE: Every public item MUST have a doc comment explaining what it is,
         what it does, and (if applicable) when it panics.
FORBIDDEN: Conditional compilation (#[cfg]) for platform-specific code
           without a clear module boundary. Use separate files, not cfg gates
           scattered through shared code.
FORBIDDEN: Builder patterns when a constructor with named fields suffices.
           Builder pattern is reserved for cases with >5 optional parameters.
SHOULD: Avoid trait objects in performance-sensitive paths
        (dynamic dispatch prevents Kani proof and hurts cache locality).
SHOULD: Prefer enums over trait objects for fixed-variant polymorphism.
SHOULD: If you can implement a helper in <20 lines without a dependency,
        do it rather than importing a crate.
```

#### 0.1.4 Code Review Checklist (Suckless Section)

Every PR SHALL be evaluated against:

- [ ] Can any line be removed without breaking functionality?
- [ ] Does every function do exactly one thing?
- [ ] Would a new team member understand this in 30 seconds?
- [ ] Is the dependency justified, or could we inline a ~20 line helper?
- [ ] Is there any dead code, commented-out code, or `todo!()` / `unimplemented!()`?
- [ ] Are there any silent defaults or hidden behaviors?
- [ ] Does any abstraction add complexity without proportional benefit?

---

### 0.2 Data-Oriented Design & Data-Driven Programming

#### 0.2.1 First Principles

**Design data structures first, algorithms second.** Data defines behavior. Code is just
the interpreter of data. This is the opposite of OOP (which hides data behind methods)
and the opposite of functional programming (which centers transformations over data).

The Five Laws of Data-Oriented Design:

```
1. DATA defines the behavior — not code, not types, not inheritance.
2. TRANSFORM data linearly — sequential memory access is the fastest path
   between two points in a CPU.
3. SEPARATE hot from cold — frequently accessed fields live together in dense
   arrays; rarely accessed fields live elsewhere.
4. BANISH indirection — no pointer chasing, no virtual dispatch, no linked lists
   in hot paths. Flat arrays with integer indices.
5. MEASURE everything — intuition about performance is wrong >50% of the time.
   Cache misses are the only performance metric that matters.
```

#### 0.2.2 Struct of Arrays (SoA) Over Array of Structs (AoS)

**BAD — Array of Structs (AoS):**

```rust
// FORBIDDEN in hot paths
pub struct Entity {
    position: [f32; 3],
    velocity: [f32; 3],
    health: u32,
    name: String,
    description: String,
    quest_log: Vec<QuestEntry>,
}

// Iteration touches ALL fields per entity, evicting cache lines unnecessarily
fn update_positions(entities: &mut [Entity]) {
    for e in entities {
        e.position[0] += e.velocity[0]; // cache line loaded: position + velocity + health + name ptr + desc ptr + quest ptr
        e.position[1] += e.velocity[1]; // only position and velocity needed!
        e.position[2] += e.velocity[2]; // 75% of cache load is WASTED
    }
}
```

**GOOD — Struct of Arrays (SoA):**

```rust
// MANDATE in hot paths
pub struct EntityActive {
    positions: Vec<[f32; 3]>,
    velocities: Vec<[f32; 3]>,
    healths: Vec<u32>,
}

pub struct EntityPassive {
    names: Vec<String>,
    descriptions: Vec<String>,
    quest_logs: Vec<Vec<QuestEntry>>,
}

// Iteration touches ONLY needed fields — dense, contiguous, cache-efficient
fn update_positions(active: &mut EntityActive) {
    for i in 0..active.positions.len() {
        // cache line loaded: position[i] + velocity[i] — both needed, no waste
        active.positions[i][0] += active.velocities[i][0];
        active.positions[i][1] += active.velocities[i][1];
        active.positions[i][2] += active.velocities[i][2];
    }
}
```

**RATIONALE:** Modern CPUs load cache lines (~64 bytes) from memory. If you iterate AoS
over 1000 entities, you load every field into cache even when you only need two. The
cache is evicted and reloaded on the next pass. SoA keeps hot data contiguous and dense,
achieving near-theoretical memory bandwidth.

#### 0.2.3 Hot/Cold Splitting

**MANDATE:** Any struct with fields accessed at different frequencies MUST be split
into hot and cold parts.

**Detection heuristic:** If a field is accessed in <20% of the functions that operate
on the struct, it's cold. Split it.

```rust
// BEFORE: Monolithic struct, all fields together
pub struct Player {
    // HOT (every frame)
    position: [f32; 3],
    rotation: [f32; 4],
    health: u32,
    stamina: u32,

    // COLD (rarely)
    display_name: String,
    guild_id: u64,
    achievement_flags: u64,
    inventory: Vec<ItemStack>,
    quest_progress: HashMap<QuestId, QuestState>,
    chat_bans: Vec<(Instant, String)>,
}

// AFTER: Hot/cold split
pub struct PlayerHot {
    positions: Vec<[f32; 3]>,
    rotations: Vec<[f32; 4]>,
    healths: Vec<u32>,
    staminas: Vec<u32>,
}

pub struct PlayerCold {
    display_names: Vec<String>,
    guild_ids: Vec<u64>,
    achievement_flags: Vec<u64>,
    inventories: Vec<Vec<ItemStack>>,
    quest_progresses: Vec<HashMap<QuestId, QuestState>>,
}

// Both use the same slot index to correlate
```

#### 0.2.4 Branchless Programming

**MANDATE** in hot paths: prefer lookup tables, arithmetic, and bit manipulation over
conditional branches.

```rust
// BAD: Branch = branch misprediction penalty on unpredictable data
fn clamp_bad(value: i32, min: i32, max: i32) -> i32 {
    if value < min { min }
    else if value > max { max }
    else { value }
}

// GOOD: Branchless (using conditional move via select)
fn clamp_good(value: i32, min: i32, max: i32) -> i32 {
    // On x86, this compiles to CMP + CMOV — no branch, no mispredict
    value.max(min).min(max)
}
```

**Pattern: Branchless selection:**

```rust
// BAD:
let result = if condition { a } else { b };

// GOOD (for hot paths):
let result = [b, a][condition as usize];
```

**RATIONALE:** Branch misprediction costs 10-20 cycles on modern CPUs. For unpredictable
data (e.g., random values, user input), branches are slower than arithmetic every time.
For predictable data (e.g., iteration bounds, sentinel checks), branches are fine.

#### 0.2.5 Data-Driven State Machines

**MANDATE:** State machines MUST be defined as data (tables), not as code (match arms).

```rust
// FORBIDDEN: State machine as control flow
fn handle_state(state: State, event: Event) -> State {
    match (state, event) {
        (State::Idle, Event::Start) => State::Running,
        (State::Running, Event::Stop) => State::Idle,
        (State::Running, Event::Error) => State::Error,
        (State::Error, Event::Reset) => State::Idle,
        _ => state, // silent default — FORBIDDEN
    }
}

// MANDATE: State machine as data
use std::collections::HashMap;

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub enum State { Idle, Running, Paused, Error }

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub enum Event { Start, Stop, Pause, Resume, Error, Reset }

// Data table: rows = current state, columns = event
// Each cell = (next_state, action_index) or None for illegal transition
pub struct StateTransition {
    pub next_state: State,
    pub action_id: u8, // index into action dispatch table
}

// MANDATE: Transitions defined as DATA, not code
// FORBIDDEN: silent defaults — every (state, event) pair is explicitly defined
pub static STATE_TABLE: &[[Option<StateTransition>; 6]; 4] = &[
    // Idle
    [Some(StateTransition { next_state: State::Running, action_id: 0 }),
     None, // Start
     None, // Stop — illegal from Idle
     None, // Pause — illegal from Idle
     None, // Resume — illegal from Idle
     None, // Error — no error in Idle
     Some(StateTransition { next_state: State::Idle, action_id: 1 })], // Reset
    // Running
    [None, // Start — illegal, already running
     Some(StateTransition { next_state: State::Idle, action_id: 2 }),
     ...],
    ...
];
```

**RATIONALE:** Data-driven state machines are:
- **Verifiable**: you can mechanically check every transition is defined
- **Auditable**: the entire state space is visible in one table
- **Provable**: Kani can prove exhaustiveness trivially
- **Changeable**: add states/events by editing DATA, not control flow

---

### 0.3 SPARK-Inspired Formal Verification Mandate

#### 0.3.1 What SPARK Proves for Ada, What Kani Proves for Rust

| Property | Ada/SPARK | Rust/Kani |
|----------|-----------|-----------|
| No buffer overflows | Proof of correct indexing | Kani bounds check proof |
| No null pointer dereference | Proof of non-null | Rust type system (Option)
| No use-after-free | Ada manages manually | Rust borrow checker |
| No integer overflow | Proof of range constraints | Kani arithmetic proof + overflow-checks |
| No unhandled exceptions | Proof of exception freedom | Kani panic-freedom proof |
| Pre/post condition contracts | `Pre`/`Post` aspects | `kani::requires`/`kani::ensures` |
| Type invariants | `Type_Invariant` aspect | `kani::invariant` |
| Freedom from deadlock | Proof of locking order | Separate proof layer |

#### 0.3.2 The Proof Pyramid

```
┌─────────────────────────────────────────────────────────────────┐
│                KANI MODEL CHECKING (all paths)                   │
│  Proves: no panics, no overflow, no bounds errors, invariants   │
│  Scope: ALL public functions in library code                    │
│  Cost: 30-60 min CI per 1000 LOC                                │
│  Tool: cargo kani                                               │
├─────────────────────────────────────────────────────────────────┤
│              PROPERTY-BASED TESTING (proptest)                   │
│  Proves: algebraic properties, idempotence, round-trips         │
│  Scope: any function Kani cannot handle (FFI, unbounded loops)  │
│  Coverage: 10,000+ random cases per property                    │
│  Tool: proptest                                                  │
├─────────────────────────────────────────────────────────────────┤
│                    FUZZING (cargo-fuzz)                          │
│  Proves: no crashes on arbitrary inputs                         │
│  Scope: all I/O boundaries, parsing, deserialization            │
│  Duration: CI runs for 5 min per target                         │
│  Tool: cargo fuzz                                               │
├─────────────────────────────────────────────────────────────────┤
│              STATIC ANALYSIS (clippy + rustc)                    │
│  Proves: lint rules, coding standards, pattern correctness      │
│  Scope: every compilation                                       │
│  Enforced: -Dwarnings, -Funsafe_code                            │
│  Tool: cargo clippy, rustc                                      │
├─────────────────────────────────────────────────────────────────┤
│            TYPE SYSTEM (Rust borrow checker + trait system)      │
│  Proves: memory safety, thread safety, type correctness         │
│  Scope: every compilation                                       │
│  Enforced: compiler, non-negotiable                              │
└─────────────────────────────────────────────────────────────────┘
```

**MANDATE:** Every codebase SHALL have all five layers.
**MANDATE:** CI SHALL fail if ANY layer reports a violation.

#### 0.3.3 Proof Tiers for Source Annotations

Every public item in the codebase SHALL be annotated with its proof tier:

```rust
/// Calculates the bounding box for a set of positions.
///
/// [PROVED] Kani harness in proofs/harnesses/spatial_proofs.rs
/// - Asserts: result.min[i] <= result.max[i] for all i
/// - Asserts: no panic on empty input (returns degenerate bbox)
/// - Coverage: empty, single, many, collinear inputs
pub fn bounding_box(positions: &[[f32; 3]]) -> BBox { ... }

/// Deserializes a network config from DER bytes.
///
/// [PROVED] Kani harness in proofs/harnesses/der_proofs.rs
/// - Asserts: no panic on any valid DER input
/// - Asserts: no panic on any invalid DER input (returns ParseError)
/// - Asserts: round-trip property for valid configs
/// - Bounds: max input 16MB, max nesting 32
pub fn parse_network_config(bytes: &[u8]) -> Result<NetworkConfig, ParseError> { ... }

/// Sends a packet over the network.
///
/// [TESTED] proptest in tests/proptest/network.rs
/// - Properties: send + receive roundtrip, ordering preserved
/// - Coverage: 10_000 random payload sizes and distributions
/// [LINTED] Standard clippy + rustc lints only
/// Note: Kani cannot prove syscall behavior. We prove up to the syscall boundary.
pub fn send_packet(conn: &mut Connection, payload: &[u8]) -> io::Result<()> { ... }

/// FFI bridge to the BlazingFastHash C library.
///
/// [FFI_AUDITED] SAFETY reviewed by @alice and @bob on 2024-03-15
/// - Unsafe block #1: pointer dereference (line 127), validated non-null + aligned
/// - Unsafe block #2: FFI call (line 132), function pointer validated at init
/// - No panic paths in safe wrapper before FFI call
pub unsafe fn blazing_fast_hash(input: &[u8]) -> u64 { ... }
```

**MANDATE:** One of `[PROVED]`, `[TESTED]`, `[LINTED]`, or `[FFI_AUDITED]` on every
`pub fn` doc comment. CI SHALL fail if a pub fn lacks this annotation.

#### 0.3.4 What Is NOT Proved (Honest Boundaries)

We formally acknowledge these trust boundaries:

| Domain | Trusted Component | Mitigation |
|--------|-------------------|------------|
| Kernel syscalls | Linux/Windows/macOS kernel | Rely on kernel correctness. Verify syscall results at the type level. |
| CPU/hardware | Processor microcode, RAM, disk | ECC memory for servers. CPU errata reviewed before deployment. |
| LLVM codegen | `rustc` backend | Use upstream stable LLVM. File bugs. Pin versions in CI. |
| Third-party deps | Crates in dependency tree | Every dep MUST be `#![forbid(unsafe_code)]` or FFI_AUDITED. `cargo-deny` enforces. |
| Cryptographic primitives | `ring`, `rustls` etc. | Use audited, well-known crates. Never roll your own crypto. |

---

### 0.4 Why Verbose Tooling Enables Minimal Code

**RATIONALE (ADHD-friendly design):**

When every tool in the chain enforces correctness, you don't need to hold the entire
correctness argument in your head. The machine catches:

- Off-by-one errors (Kani)
- Uninitialized state (Rust compiler)
- Formatting inconsistencies (rustfmt)
- Stylistic issues (clippy)
- Undefined behavior (MIRI)
- Security vulnerabilities (cargo-audit)

This lets you focus your cognitive energy on **architecture, data design, and logic** —
the parts of programming that actually require human creativity.

The deal is explicit:

> We invest heavily in tooling upfront so we can write the simplest possible code
> and trust that the toolchain catches everything else.

---

## Part 1: The Full Stack Decision

### 1.1 Decision Table

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Language** | Rust | Memory safety + zero-cost abstractions + formal verification tooling |
| **Edition** | 2021 (migrate to 2024 when Kani fully supports it) | 2021 is proven with Kani. 2024 adds ergonomic improvements but Kani compatibility is still rolling out. |
| **`std` policy** | `std` by default. `no_std` is opt-in via feature flag for embedded targets. | Pragmatism: most projects need I/O, allocation, concurrency, networking. |
| **Build system** | `just` (human interface) + `xtask` (Rust automation) | Single source of truth in Rust. Thin shell wrapper for tab-completion and discoverability. |
| **Cross-compilation** | `cargo-zigbuild` (Zig linker) | "Build once, run anywhere." Zig cc bundles musl, glibc, and all target libs in one binary. No per-target toolchain installation. |
| **Linker** | Zig `cc` (via `cargo-zigbuild`) | Produces statically-linked, portable binaries for any target. Eliminates linker version mismatches. |
| **Shell** | Nushell | Structured data pipelines, typed variables, no string-whispering. |
| **VCS (philosophical ideal)** | **Pijul** | Patch-theory-based VCS. Formally grounded merge model eliminates merge conflicts at the mathematical level. MANDATE: all new projects shall target pijul as the long-term VCS. | |---|---|---|
| **VCS (practical implementation)** | **Jujutsu (`jj`)** with git backend | Change-oriented VCS, 100% git-compatible. Adopted until pijul reaches production maturity. Zero migration risk — interoperates with existing GitHub/GitLab infrastructure. |
| **Formal verification** | Kani model checker | SPARK-equivalent proof of runtime safety. Proves no panics, no overflow, no bounds errors, arbitrary invariants. |
| **DOD architecture** | ECS (`hecs`) for stateful apps | SoA by construction, cache-friendly, data-driven. `hecs` chosen for minimalism (~2000 LOC, no macros). |
| **Data serialization** | ASN.1 + DER (Distinguished Encoding Rules) | Deterministic encoding, schema-enforced, cryptography-grade. Only DER — never BER, CER, XER, or JER. |
| **Documentation** | AsciiDoc (source of truth) + Vale (prose lint) | Strict build pipeline with `--failure-level=WARN`. README.md generated from README.adoc at release for crates.io. |
| **Editor** | Helix | Modal editor with built-in LSP, tree-sitter, and minimal configuration. |
| **Package registry** | crates.io (public libs), custom registry (internal) | `publish = false` in Cargo.toml until explicitly set to `true`. |
| **CI** | Per-project (not prescribed) | GitHub Actions, GitLab CI, Buildkite, etc. Chosen per-project. The standard documents what CI MUST enforce, not which CI system. |

### 1.2 Toolchain Versions Matrix

> **MANDATE:** Every project SHALL pin ALL tool versions via Nix Flakes.
> **MANDATE:** Every project SHALL provide a `flake.nix` at repository root.
> **MANDATE:** Every project SHALL lock `rust-toolchain.toml` to an exact version.

| Layer | Source | Pinning |
|-------|--------|---------|
| System tools (zig, asciidoctor, pandoc, vale, cmake, etc.) | nixpkgs via `flake.nix` | `flake.lock` (merkle tree of ALL transitive deps) |
| Rust toolchain (rustc, cargo, clippy, rustfmt, etc.) | fenix overlay via `rust-toolchain.toml` | Exact version (e.g. `"1.85.0"`) |
| Project binary | `crane.buildPackage` in Nix sandbox | `Cargo.lock` + `flake.lock` (dual merkle) |

**MANDATE:** All `cargo install` SHALL use `--locked`.
**MANDATE:** `cargo install` is FORBIDDEN in CI — CI builds happen inside Nix sandbox.

### 1.3 Target Architecture Matrix (Build Once, Run Anywhere)

| Target Triple | Libc | Use Case | `cargo-zigbuild` Support |
|---------------|------|----------|--------------------------|
| `x86_64-unknown-linux-musl` | musl | Linux servers, Docker, CI | Full |
| `aarch64-unknown-linux-musl` | musl | ARM servers, Raspberry Pi | Full |
| `x86_64-pc-windows-gnu` | mingw | Windows desktop/server | Full |
| `x86_64-pc-windows-msvc` | MSVC | Windows (MSVC interop) | Partial (uses system MSVC) |
| `aarch64-apple-darwin` | macOS | Apple Silicon Macs | Full (requires macOS build host) |
| `x86_64-apple-darwin` | macOS | Intel Macs | Full (requires macOS build host) |
| `wasm32-wasi` | WASI | WebAssembly server-side | Full |
| `wasm32-unknown-unknown` | none | Web browser (WASM + JS) | Via wasm-pack, not zigbuild |
| `riscv64gc-unknown-linux-musl` | musl | RISC-V Linux | Full |
| `armv7-unknown-linux-musleabihf` | musl | ARM 32-bit (e.g., Pi 0/1) | Full |

**MANDATE:** Every project SHALL define its target matrix in `cross/targets.toml`.
All targets SHALL be buildable with a single `just cross` command.

---

### 1.4 Rust-Native Development Environment Replacements

> **MANDATE:** All development environment tools SHALL be Rust-native replacements
> wherever possible. This eliminates C toolchain dependencies for development,
> ensures cross-platform consistency, and keeps the entire toolchain in the
> Rust ecosystem (one `rustup` install = everything works).

#### 1.4.1 Why Rust-Native Tools

| Reason | Explanation |
|--------|-------------|
| **No C toolchain needed** | Every Rust tool installs via `cargo install --locked`. No `apt`, `brew`, `yum` for C libraries. |
| **Cross-platform identical** | Same tool, same behavior on Linux, macOS, Windows. No GNU vs BSD grep differences. |
| **Memory safe** | All tools written in safe Rust. No buffer overflows in your development pipeline. |
| **Faster in practice** | ripgrep beats grep by 5-10x on large codebases. fd beats find by 3-5x. |
| **Single upgrade path** | `cargo install --locked <tool>` updates everything. No mixing apt/homebrew/cargo/gem/pip. |
| **Works offline after install** | No runtime dependencies fetched from the internet. |

#### 1.4.2 Replacement Table — Drop-in / Direct Replacements

| Rust Tool | Replaces | Compatibility | Install |
|-----------|----------|---------------|---------|
| **ripgrep** (`rg`) | `grep` / `ag` | Full drop-in for common use. Some GNU grep flags missing. | `cargo install --locked ripgrep` |
| **fd** (`fd`) | `find` | Full drop-in. Simpler syntax. Respects `.gitignore` by default. | `cargo install --locked fd-find` |
| **bat** (`bat`) | `cat` / `less` | Full drop-in. Syntax highlighting, git integration, paging. | `cargo install --locked bat` |
| **sd** (`sd`) | `sed` | Full drop-in for common regex replace. Not 1:1 with sed flags. | `cargo install --locked sd` |
| **delta** (`delta`) | `diff` | Full drop-in for git diff. Works as `diff` replacement with `--paging=never`. | `cargo install --locked git-delta` |
| **eza** (`eza`) | `ls` | Full drop-in (fork of exa). Uses `eza` not `exa` binary name. | `cargo install --locked eza` |
| **dust** (`dust`) | `du` | Full drop-in. More intuitive tree display. | `cargo install --locked dust` |
| **procs** (`procs`) | `ps` | Full drop-in. Colorized, tree view, Docker-aware. | `cargo install --locked procs` |
| **bottom** (`btm`) | `top` / `htop` | Full drop-in. TUI with graphs, sorting, filtering. | `cargo install --locked bottom` |
| **zoxide** (`z`) | `cd` | Full drop-in. Smart directory jumping with `z` command. | `cargo install --locked zoxide` |
| **hyperfine** (`hyperfine`) | `time` | Full drop-in. Statistical benchmarking, warm-up, comparison. | `cargo install --locked hyperfine` |
| **tokei** (`tokei`) | `cloc` | Full drop-in. Counts code, comments, blanks per language. | `cargo install --locked tokei` |
| **ouch** (`ouch`) | `tar` / `zip` / `gzip` | Full drop-in for compress/decompress. Detects format from extension. | `cargo install --locked ouch` |
| **xh** (`xh`) | `curl` / `httpie` | Full drop-in for HTTP requests. Simpler syntax than curl. | `cargo install --locked xh` |
| **dog** (`dog`) | `dig` | Partial drop-in. Basic DNS lookups work. Advanced query flags differ. | `cargo install --locked dog` |
| **gping** (`gping`) | `ping` | Partial drop-in. Graph output. ICMP ping on Linux, TCP ping on macOS/Win. | `cargo install --locked gping` |
| **bandwhich** (`bandwhich`) | `nethogs` / `iftop` | Drop-in for network utilization. TUI, per-process bandwidth. | `cargo install --locked bandwhich` |
| **coreutils** (uutils) | GNU coreutils | **Partial** — actively developed, most tools work. Test edge cases. | `cargo install --locked coreutils` |

#### 1.4.3 Shell & Terminal Replacements

| Rust Tool | Replaces | Compatibility | Install |
|-----------|----------|---------------|---------|
| **nushell** (`nu`) | `bash` / `zsh` | Full drop-in (structured data shell). Different paradigm — invest in learning it. | `cargo install --locked nu` |
| **starship** (`starship`) | shell prompts (oh-my-zsh, bash-git-prompt) | Full drop-in. Works with any shell. Fast, minimal, customizable. | `cargo install --locked starship` |
| **zellij** (`zellij`) | `tmux` / `screen` | Full drop-in. Built-in layout system, mouse support, session management. | `cargo install --locked zellij` |
| **alacritty** (`alacritty`) | xterm, gnome-terminal, konsole | Full drop-in. GPU-accelerated. Note: requires `cmake`, `freetype`, `fontconfig` system packages. | `cargo install --locked alacritty` |
| **helix** (`hx`) | `vim` / `neovim` | Full drop-in. Built-in LSP, tree-sitter, file picker. No plugin system (by design). | `cargo install --locked helix` |
| **just** (`just`) | `make` | Full drop-in (command runner). Simpler syntax, no Makefile quirks. | `cargo install --locked just` |
| **jj** (`jj`) | `git` full replacement | Change-oriented VCS, 100% git-compatible. Automatic rebase, undo, no staging area. | `cargo install --locked jujutsu` |
| **gg** (`gg`) | `gitui` / git TUI | TUI for jj — interactive log, diff, and operation browser. | `cargo install --locked gg` |

#### 1.4.4 Essential Short List

If you're setting up a new machine and only install a few tools, start here:

```
ripgrep   → grep     (the single biggest quality-of-life improvement)
fd        → find     (faster, simpler, git-aware)
bat       → cat      (syntax highlighting is worth it alone)
eza       → ls       (color, icons, permissions readable)
zoxide    → cd       (never type a full path again)
bottom    → htop     (better graphs, mouse support)
delta     → diff     (git diff becomes beautiful)
starship  → prompt   (fast, informative, works in any shell)
helix     → vim      (LSP built-in, no plugin config)
just      → make     (no Makefile syntax, no tabs vs spaces)
jj        → git      (auto-rebase, undo, safer workflow)
sd        → sed      (simple find-and-replace, regex consistent)
```

#### 1.4.5 Caveats and Compatibility Notes

- **uutils/coreutils**: Actively developed, most tools complete. `ls`, `cp`, `mv`, `rm`, `cat`,
  `echo`, `mkdir`, `touch`, `chmod`, `ln`, `sort`, `uniq`, `wc`, `head`, `tail`, `cut`, `tr` are
  all stable. Some edge cases differ from GNU (e.g., sort locale handling). Install and test
  thoroughly before replacing system coreutils. Recommended path: install via `cargo install --locked
  coreutils`, then prepend `~/.cargo/bin` to PATH before `/bin` or `/usr/bin`.
- **dog**: Low maintenance (last release 2022). Basic DNS lookups (A, AAAA, MX, TXT) work fine.
  For advanced DNS debugging (zone transfers, DNSSEC validation), keep `dig` installed.
- **gping**: Infrequent updates but stable. Linux supports ICMP ping (requires `CAP_NET_RAW` or
  `sudo`). macOS and Windows use TCP ping by default (connect to a port, measure latency).
- **alacritty**: Requires system-level graphics libraries (`cmake`, `freetype`, `fontconfig`) that
  cannot be installed via cargo. On Linux: `apt install cmake libfreetype6-dev libfontconfig1-dev`.
  On macOS: `brew install cmake freetype fontconfig`.
- **These tools are development environment, not project dependencies.** They live in your home
  directory (`~/.cargo/bin`), not in the project. They are NOT listed in `Cargo.toml`.
  They are NOT part of the CI pipeline. They are for developer productivity only.

### 1.5 Hermetic Development Environment

> **MANDATE:** Every project SHALL define its development environment in `flake.nix`.
> **MANDATE:** Every project SHALL pin its Rust toolchain in `rust-toolchain.toml`.
> **MANDATE:** `flake.lock` SHALL be committed to version control.

#### 1.5.1 Nix Flake Entry Point (`flake.nix`)

```nix
{
  description = "project — hermetic dev environment";

  inputs = {
    nixpkgs.url       = "github:NixOS/nixpkgs/nixos-unstable";
    fenix.url         = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
    crane.url         = "github:ipetkov/crane";
    crane.inputs.nixpkgs.follows = "nixpkgs";
    flake-utils.url   = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, fenix, crane, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ fenix.overlays.default ];
        };
        rustToolchain = pkgs.fenix.fromToolchainFile {
          file = ./rust-toolchain.toml;
          sha256 = "0000000000000000000000000000000000000000000000000000";
        };
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            rustToolchain
            just
            zig
            asciidoctor
            pandoc
            vale
          ];
        };
      });
}
```

#### 1.5.2 `rust-toolchain.toml` — Exact Rust Pinning

```toml
[toolchain]
channel = "1.85.0"
components = ["clippy", "rustfmt", "rust-src", "llvm-tools-preview"]
targets = [
    "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-gnu",
    "x86_64-unknown-linux-musl",
    "aarch64-unknown-linux-musl",
    "x86_64-pc-windows-gnu",
    "x86_64-pc-windows-msvc",
    "x86_64-unknown-freebsd14",
    "x86_64-apple-darwin",
    "aarch64-apple-darwin",
]
```

**RATIONALE:** `rust-toolchain.toml` is the single source of truth for Rust version. Every tool that reads it (rustup, fenix, crane) agrees on the exact version. No more "latest stable" drift.

#### 1.5.3 `flake.lock` as Environment Merkle Root

`flake.lock` is the cryptographic hash of EVERY transitive dependency in the environment:

| Lock | What It Pins | Update Command |
|------|-------------|----------------|
| `flake.lock` | nixpkgs revision, fenix revision, crane revision | `nix flake update` |
| `Cargo.lock` | Rust crate dependency tree | `cargo update` |
| `rust-toolchain.toml` | Rust compiler + component versions | Manual edit |

**MANDATE:** `flake.lock` SHALL be committed and reviewed like any source file.
**MANDATE:** CI SHALL fail if `nix flake check` reports any issue.

#### 1.5.4 Environment Integrity (`nix flake check`)

```bash
# Verify the entire environment is consistent
nix flake check

# Enter the hermetic development shell
nix develop .

# Build the project inside the sandbox
nix build .
```

**MANDATE:** CI SHALL run `nix flake check` on every commit.
**MANDATE:** CI SHALL NOT install anything outside the Nix sandbox.

#### 1.5.5 Cross-Compilation Targets

All targets are built from a **single Linux Nix host** using `pkgsCross`:

| Target Triple | Nix Attribute | Requirement |
|---------------|--------------|-------------|
| `x86_64-unknown-linux-gnu` | `pkgs.pkgsCross.gnu64` | None (default) |
| `aarch64-unknown-linux-gnu` | `pkgs.pkgsCross.aarch64-multiplatform` | None |
| `x86_64-unknown-linux-musl` | `pkgs.pkgsCross.musl64` | None |
| `aarch64-unknown-linux-musl` | `pkgs.pkgsCross.aarch64-multiplatform-musl` | None |
| `x86_64-pc-windows-gnu` | `pkgs.pkgsCross.mingwW64` | None |
| `x86_64-pc-windows-msvc` | `pkgs.pkgsCross.x86_64-windows` | Windows SDK |
| `x86_64-unknown-freebsd14` | `pkgs.pkgsCross.x86_64-freebsd` | None |
| `x86_64-apple-darwin` | `pkgs.pkgsCross.x86_64-darwin` | macOS host or remote builder |
| `aarch64-apple-darwin` | `pkgs.pkgsCross.aarch64-darwin` | macOS host or remote builder |

**FreeBSD strategy:** Cross-compiled FROM Linux TO FreeBSD via `pkgsCross.x86_64-freebsd`. No native Nix on FreeBSD is required. FreeBSD developers use a Linux CI runner or bhyve VM, documented as a remote-build pattern.

#### 1.5.6 Hermetic Build Guarantee

What the Nix sandbox PROVES at the mathematical level:

| Property | Guarantee | Mechanism |
|----------|-----------|-----------|
| System deps repeatable | ✅ Content-addressed store | `/nix/store` — identical hash = identical bits |
| rustc version stable | ✅ Exact pinned version | `rust-toolchain.toml` + fenix + flake.lock |
| Cargo build hermetic | ✅ No network, no `/proc`, no `/usr`, fixed env | Nix build sandbox |
| All transitive deps pinned | ✅ Complete merkle tree | `flake.lock` = hash of ALL inputs |
| Bit-for-bit reproducibility | ✅ Same lock → same binary | Deterministic builds by default |
| build.rs environment fixed | ✅ Nix sets fixed env vars | `build.rs` cannot read host state |
| Rollback | ✅ `nix profile rollback` | All past envs remain in store |

**MANDATE:** Before accepting any non-hermetic build step, prove that Nix sandbox cannot express it. If Nix CAN express it, the Nix expression is mandatory.

---

## Part 2: Repository Structure

### 2.1 Standard Directory Layout

```
project/
├── .cargo/
│   ├── config.toml                   # strict compiler flags, zig linker config
│   └── credentials.toml              # template only (gitignored with contents)
├── .jj/                               # Jujutsu repo data (auto-created by `jj git init`)
│   └── config.toml                    # jj user configuration (see Part 10)
├── .github/
│   ├── CODEOWNERS                    # every file owned by a team
│   └── workflows/                    # CI pipeline definitions
│       ├── ci.yml                    # main CI: lint, test, proof, build
│       ├── docs.yml                  # documentation build + lint
│       └── release.yml               # release pipeline
├── proofs/                           # Kani proof harnesses (separate crate)
│   ├── Cargo.toml                    # depends on project crate + kani
│   ├── src/
│   │   ├── lib.rs                    # re-exports all harness modules
│   │   ├── parser_proofs.rs          # proof harnesses for parsers
│   │   ├── state_machine_proofs.rs   # proof harnesses for state machines
│   │   ├── ecs_proofs.rs             # proof harnesses for ECS operations
│   │   └── math_proofs.rs            # proof harnesses for math/simulation
│   └── tests/                        # integration-level Kani proofs
├── cross/                            # cross-compilation configuration
│   ├── targets.toml                  # target triple definitions
│   └── Dockerfile.build              # (optional) CI build container
├── xtask/                            # build automation in Rust
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs                   # clap dispatch
│       ├── tasks/
│       │   ├── mod.rs
│       │   ├── check.rs              # full pipeline
│       │   ├── lint.rs               # clippy + fmt + nostd check
│       │   ├── test.rs               # cargo test
│       │   ├── proof.rs              # Kani verification
│       │   ├── fuzz.rs               # cargo-fuzz invocation
│       │   ├── docs.rs               # cargo doc + AsciiDoc build
│       │   ├── release.rs            # full check + readme gen + publish prep
│       │   ├── audit.rs              # cargo-audit + cargo-deny
│       │   ├── cross.rs              # cargo-zigbuild cross-compile
│       │   └── nostd.rs              # no_std compliance check
│       └── utils/
│           ├── mod.rs
│           └── shell.rs              # command execution with error handling
├── schema/                           # ASN.1 schema definitions
│   ├── common/
│   │   ├── primitives.asn1           # all constrained primitive types
│   │   ├── identifiers.asn1          # OID and identifier registrations
│   │   └── timestamps.asn1           # time-related type definitions
│   └── project.asn1                  # project-specific schema (rename per-project)
├── src/
│   ├── lib.rs                        # crate root
│   ├── main.rs                       # binary entry point (if applicable)
│   ├── ecs/                          # ECS world definitions
│   │   ├── mod.rs
│   │   ├── components.rs             # component type definitions
│   │   ├── systems.rs                # system function definitions
│   │   └── resources.rs              # shared resources
│   ├── data/                         # data-oriented design core
│   │   ├── mod.rs
│   │   ├── layouts.rs                # SoA type definitions
│   │   ├── state_machine.rs          # data-driven state machine tables
│   │   └── serialization.rs          # ASN.1/DER encode/decode
│   ├── domain/                       # domain model
│   │   ├── mod.rs
│   │   ├── types.rs                  # domain-specific ASN.1-derived types
│   │   └── error.rs                  # domain error definitions
│   └── api/                          # public API surface
│       ├── mod.rs
│       ├── config.rs                 # configuration types
│       └── lib.rs                    # top-level re-exports
├── tests/
│   ├── integration/                  # integration tests
│   ├── conformance/                  # ASN.1/DER conformance tests
│   │   ├── valid/                    # DER bytes that MUST parse
│   │   ├── invalid/                  # DER bytes that MUST reject
│   │   └── vectors/                  # known-good test vectors
│   └── proptest/                     # property-based tests
│       ├── config_proptests.rs
│       ├── serialization_proptests.rs
│       └── state_machine_proptests.rs
├── fuzz/                             # fuzz targets (cargo-fuzz)
│   ├── Cargo.toml
│   └── fuzz_targets/
│       ├── der_parser.rs             # fuzz DER deserialization
│       └── config_parser.rs          # fuzz config deserialization
├── docs/
│   ├── antora.yml                    # Antora component descriptor
│   ├── .vale.ini                     # Vale prose lint configuration
│   ├── asciidoc-lint.yml             # structural lint rules for AsciiDoc
│   ├── modules/ROOT/
│   │   ├── nav.adoc                  # navigation definition
│   │   ├── pages/
│   │   │   ├── index.adoc            # entry point / overview
│   │   │   ├── installation.adoc     # installation guide
│   │   │   ├── configuration.adoc    # configuration reference
│   │   │   ├── api.adoc              # API documentation
│   │   │   ├── architecture.adoc     # architecture decision records
│   │   │   └── development.adoc      # developer guide
│   │   ├── partials/                 # reusable content fragments
│   │   └── assets/images/            # diagrams and screenshots
│   └── vale/styles/
│       ├── Project/                  # project-specific Vale rules
│       │   ├── Terms.yml
│       │   ├── Headings.yml
│       │   └── Abbreviations.yml
│       └── config/vocabularies/
│           ├── accept.txt            # approved technical terms
│           └── reject.txt            # forbidden terms
├── scripts/                          # Nushell scripts only
│   ├── dev-setup.nu                  # install all tools
│   ├── check-deps.nu                 # verify all tools present
│   ├── release.nu                    # release workflow
│   └── ci-helper.nu                  # CI utility functions
├── Cargo.toml
├── Cargo.lock                        # MANDATE: ALWAYS committed
├── justfile                          # human interface to all tasks
├── .gitattributes                    # strict line ending rules
├── .gitignore                        # includes generated README.md
├── README.adoc                       # source of truth (never README.md)
├── CONTRIBUTING.adoc                 # contribution guidelines
├── CHANGELOG.adoc                    # changelog
├── SECURITY.adoc                     # security policy
├── SUPPORT.adoc                      # support information
└── STANDARDS.md                      # THIS FILE — the standard itself
```

### 2.2 .gitignore

```gitignore
# ─────────────────────────────────────────
# GENERATED FILES: never manually edited
# ─────────────────────────────────────────

# README.md is generated from README.adoc at release time for crates.io.
# It is never committed, never manually edited.
README.md

# ─────────────────────────────────────────
# BUILD ARTIFACTS
# ─────────────────────────────────────────

/target/
**/*.rs.bk

# ─────────────────────────────────────────
# IDE / EDITOR
# ─────────────────────────────────────────

.helix/

# ─────────────────────────────────────────
# FUZZ CORPUS (regenerated)
# ─────────────────────────────────────────

fuzz/corpus/

# ─────────────────────────────────────────
# OS FILES
# ─────────────────────────────────────────

.DS_Store
Thumbs.db
```

### 2.3 .gitattributes

```gitattributes
# Strict file handling rules. Enforced by git, not convention.

# ─────────────────────────────────────────
# DEFAULT: All files use LF. Never CRLF.
# ─────────────────────────────────────────
*               text=auto eol=lf

# ─────────────────────────────────────────
# SOURCE CODE: Always LF, always text
# ─────────────────────────────────────────
*.rs            text eol=lf
*.toml          text eol=lf
*.yaml          text eol=lf
*.yml           text eol=lf
*.json          text eol=lf
*.adoc          text eol=lf
*.md            text eol=lf
*.nu            text eol=lf
*.sh            text eol=lf
*.just          text eol=lf
justfile        text eol=lf
Makefile        text eol=lf
*.asn1          text eol=lf

# ─────────────────────────────────────────
# BINARY: Never diff, never convert
# ─────────────────────────────────────────
*.png           binary
*.jpg           binary
*.jpeg          binary
*.gif           binary
*.ico           binary
*.pdf           binary
*.zip           binary
*.tar           binary
*.gz            binary
*.zst           binary
*.der           binary

# ─────────────────────────────────────────
# DIFF DRIVERS: Semantic diff for structured files
# ─────────────────────────────────────────
*.rs            diff=rust
*.toml          diff=toml
*.yaml          diff=yaml

# ─────────────────────────────────────────
# EXPORT IGNORE: Not in release archives
# ─────────────────────────────────────────
.gitattributes  export-ignore
.gitignore      export-ignore
scripts/        export-ignore
xtask/          export-ignore
proofs/         export-ignore
fuzz/           export-ignore
cross/          export-ignore
```

### 2.4 .cargo/config.toml

```toml
[build]
# MANDATE: Always use all CPU cores.
jobs = 0

[target.x86_64-unknown-linux-gnu]
# Default development target. Uses system linker (not Zig).
# Cross-compilation targets use Zig linker (see cross/targets.toml).
rustflags = [
    # Treat all warnings as errors.
    "-Dwarnings",
    # Forbid unsafe code at the compiler level.
    # Primary enforcement is Cargo.toml [lints.rust] unsafe_code = "forbid".
    # This is the second layer.
    "-F", "unsafe_code",
]

[target.x86_64-unknown-linux-musl]
# Fully static binary via Zig linker.
linker = "zig"
rustflags = [
    "-Dwarnings",
    "-F", "unsafe_code",
    "-C", "target-feature=+crt-static",
]

[target.aarch64-unknown-linux-musl]
linker = "zig"
rustflags = [
    "-Dwarnings",
    "-F", "unsafe_code",
    "-C", "target-feature=+crt-static",
]

[target.x86_64-pc-windows-gnu]
linker = "zig"
rustflags = [
    "-Dwarnings",
    "-F", "unsafe_code",
]

[target.wasm32-wasi]
rustflags = [
    "-Dwarnings",
    "-F", "unsafe_code",
]

[alias]
# Called via: cargo xtask <task>
xtask        = "run --package xtask --"
strict       = "clippy --all-targets --all-features -- -Dwarnings"
full-check   = "test --all-targets --all-features"

[net]
offline = false                     # set true in CI after fetch

[registries.crates-io]
protocol = "sparse"                 # faster, more reliable than git

[env]
# MANDATE: Always show term colors in CI
CARGO_TERM_COLOR = "always"
```

---

## Part 3: Rust Configuration

### 3.1 Cargo.toml — Mandatory Template

```toml
[package]
name          = "project-name"
version       = "0.1.0"
edition       = "2021"                      # MANDATE: 2021 until Kani fully supports 2024
rust-version  = "1.85.0"                    # MANDATE: MSRV never omitted
authors       = ["Name <email@example.com>"]
description   = "One sentence description."
license       = "MIT OR Apache-2.0"
repository    = "https://github.com/org/project"
documentation = "https://docs.rs/project-name"
homepage      = "https://project.example.com"

# README.adoc is the source of truth.
# README.md is generated at release time for crates.io.
readme        = "README.md"

keywords      = ["keyword1", "keyword2"]
categories    = ["category1", "category2"]
exclude       = [
    "docs/",
    "scripts/",
    "tests/",
    "proofs/",
    "fuzz/",
    "cross/",
    "xtask/",
]

# MANDATE: publish = false until explicitly ready.
# Prevents accidental crate publication.
publish = false

[lib]
name = "project_name"

# ─────────────────────────────────────────
# FEATURES
# std is default. no_std is opt-in for embedded.
# ─────────────────────────────────────────
[features]
default = ["std"]
std     = []                          # standard library (default)
no_std  = []                          # embedded / no_std mode
alloc   = []                          # alloc without full std (for no_std + alloc)

[dependencies]
# ─────────────────────────────────────────
# MANDATE: All dependencies use semver-compatible versions.
# MANDATE: Every dependency justified in a comment.
# ─────────────────────────────────────────

# ECS architecture (see Part 4)
hecs = "0.11"                         # minimal ECS, ~2000 LOC, no macros

# ASN.1/DER serialization
rasn = { version = "0.14", features = ["derive"], optional = true }
# DER is deterministic, provably unambiguous encoding.

# Error handling
thiserror = { version = "2", optional = true }  # std feature only

# Replacements for standard patterns (lazy, once, etc.)
# NOTE: std::sync::OnceLock is available since Rust 1.70, prefer that.
# NOTE: std::cell::LazyCell is available since Rust 1.80, prefer that.

[dev-dependencies]
# ─────────────────────────────────────────
# MANDATE: Property-based testing for every project
# ─────────────────────────────────────────
proptest = "1.5"

# Test utilities
tempfile = "3"

# Kani proofs are in proofs/ crate, not here.

[profile.dev]
overflow-checks  = true               # catch integer overflow in development
debug-assertions = true
debug            = true

[profile.release]
# MANDATE: overflow checks in release too — proof relies on defined behavior.
overflow-checks  = true
debug-assertions = true               # MANDATE: keep assertions for Kani proof coverage
strip            = "debuginfo"        # strip debug info but keep panic info
opt-level        = "z"                # optimize for size by default
lto              = true               # link-time optimization
codegen-units    = 1                  # single codegen unit for best optimization
panic            = "abort"            # abort on panic (smaller binary, no unwind tables)

[profile.test]
overflow-checks  = true
debug-assertions = true

[profile.bench]
overflow-checks  = false              # benchmarks disable overflow checks for performance
debug-assertions = false
opt-level        = 3                  # optimize for speed in benchmarks

# ─────────────────────────────────────────
# LINTS: Single source of truth.
# Declared here only. Never in lib.rs or any module.
# Cannot be accidentally overridden at module level.
# ─────────────────────────────────────────

[lints.rust]
# Forbid unsafe code entirely.
# Remove only if FFI is genuinely required.
# Document WHY if removed — governance approval required.
unsafe_code                   = "forbid"

# Documentation: all public items documented.
missing_docs                  = "warn"

# Missing Debug impl = cannot assert type contents in tests.
missing_debug_implementations = "warn"

# Items visible outside current crate but not exported = likely bug.
unreachable_pub               = "warn"

# Every returned value MUST be explicitly handled or
# explicitly discarded with `let _ = ...`.
# Every discard is a visible, reviewable, conscious decision.
unused_results                = "warn"
unused_must_use               = "warn"

# Private items are not documented — this is fine.
# But public items MUST be documented (see missing_docs).
private_doc_tests             = "allow"

# Dead code is only a warning during development.
# CI blocks dead code unless explicitly justified.
dead_code                     = "warn"

[lints.clippy]
# Strictest lint levels.
all      = "warn"
pedantic = "warn"
nursery  = "warn"
cargo    = "warn"

# No silent panics — every unwrap/expect/panic is visible.
unwrap_used      = "warn"
expect_used      = "warn"
panic            = "warn"

# No unfinished code — CI MUST NOT pass with todos.
todo             = "warn"
unimplemented    = "warn"

# No unchecked indexing — use .get() or prove bounds with Kani.
indexing_slicing = "warn"

# No unchecked arithmetic.
arithmetic_side_effects = "warn"

# Forward-compatible public API design.
# All public types must use explicit constructors.
# Struct literal syntax on public types is forbidden.
# This enforces validation at construction time.
exhaustive_structs = "warn"
exhaustive_enums   = "warn"

# Additional strict clippy rules.
missing_const_for_fn      = "warn"    # functions that can be const
missing_errors_doc        = "warn"    # functions that return Result need error docs
missing_panics_doc        = "warn"    # functions that can panic need panics docs
must_use_candidate        = "warn"    # pure functions should be #[must_use]
mut_mut                   = "warn"    # &mut &mut is usually wrong
needless_pass_by_value    = "warn"    # large types should be &T, not T
semicolon_if_nothing_returned = "warn"
same_name_method          = "warn"
significant_drop_tightening = "warn"

# ─────────────────────────────────────────
# DENY: These are hard errors, not warnings.
# ─────────────────────────────────────────
[lints.rust.deny]
const_err                   = true
illegal_floating_point_literal_pattern = true
improper_ctypes             = true
invalid_macro_export_arguments = true
nonsensical_open_options    = true
pointer_structural_match    = true
private_bounds              = true
unconditional_recursion     = true

[lints.clippy.deny]
cargo_common_metadata       = true
multiple_unsafe_ops_per_scope = true
panic_in_result_fn          = true
print_stderr                = true
print_stdout                = true    # use logging (tracing/log) instead
unnecessary_self_imports    = true
unused_async                = true
wildcard_dependencies       = true
```

### 3.2 src/lib.rs — Crate Root Template

```rust
//! # Project Name
//!
//! One paragraph description of what this crate does.
//!
//! ## Feature Flags
//!
//! - `std` (default): Standard library support.
//! - `no_std`: Disable std for embedded targets. Requires `alloc` for heap.
//! - `alloc`: Heap allocation without full std (used with `no_std`).
//!
//! ## Proof Status
//!
//! This crate follows the [PROVED]/[TESTED]/[LINTED]/[FFI_AUDITED] annotation
//! system defined in STANDARDS.md §0.3.3. All public functions are annotated
//! with their proof tier.

// MANDATE: std is the default. cfg-gate for no_std.
#![cfg_attr(feature = "no_std", no_std)]
#![cfg_attr(
    all(feature = "no_std", feature = "alloc"),
    extern crate alloc
)]

// All lints are declared in Cargo.toml [lints].
// No lint attributes here — Cargo.toml is the single source of truth.

// Module declarations — organized by architectural layer.
pub mod data;           // Data-oriented design types
pub mod domain;         // Domain model
pub mod ecs;            // ECS components, systems, resources
pub mod api;            // Public API surface
pub mod error;          // Error types

// Conditional modules.
#[cfg(feature = "std")]
pub mod io;             // I/O operations (std only)
```

### 3.3 src/error.rs — Error Taxonomy Template

```rust
//! Error taxonomy for the project.
//!
//! [PROVED] Kani harness in proofs/harnesses/error_proofs.rs
//!
//! Error taxonomy rules:
//! 1. Every error variant is a struct with named fields — no stringly-typed errors.
//! 2. Every error includes the source location (file, line) of where it was created.
//! 3. Every error is `#[non_exhaustive]` to allow adding variants without breaking API.
//! 4. Every error implements `std::error::Error` with `source()` chain.

use std::fmt;

/// The top-level error type for this crate.
///
/// [PROVED] All variants are constructable without panic.
/// [PROVED] All Display implementations do not panic.
#[non_exhaustive]
#[derive(Debug)]
pub enum Error {
    /// A parsing error from ASN.1/DER deserialization.
    Parse(ParseError),

    /// A configuration validation error.
    Config(ConfigError),

    /// An ECS operation error (entity not found, component missing, etc.).
    Ecs(EcsError),

    /// An I/O error (std only).
    #[cfg(feature = "std")]
    Io(std::io::Error),

    /// An internal invariant violation — this is a BUG.
    /// Includes the invariant description and source location.
    Invariant(InvariantViolation),
}

/// An invariant violation — indicates a bug in the code.
///
/// [PROVED] Kani harness proves this is never constructed when invariants hold.
#[derive(Debug)]
pub struct InvariantViolation {
    pub message: &'static str,
    pub file: &'static str,
    pub line: u32,
}

impl fmt::Display for InvariantViolation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Invariant violation: {} at {}:{}",
            self.message, self.file, self.line
        )
    }
}

impl std::error::Error for InvariantViolation {}

/// Create an invariant violation at the current call site.
///
/// [PROVED] This macro itself does not panic.
/// Usage: `invariant_violation!("entity_id should be in bounds")`
#[macro_export]
macro_rules! invariant_violation {
    ($msg:expr) => {
        $crate::error::InvariantViolation {
            message: $msg,
            file: file!(),
            line: line!(),
        }
    };
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Parse(e) => write!(f, "Parse error: {e}"),
            Error::Config(e) => write!(f, "Config error: {e}"),
            Error::Ecs(e) => write!(f, "ECS error: {e}"),
            #[cfg(feature = "std")]
            Error::Io(e) => write!(f, "I/O error: {e}"),
            Error::Invariant(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Error::Invariant(e) => Some(e),
            _ => None,
        }
    }
}

// Conversion from internal error types.
// Each conversion is a type-safe mapping — no string wrapping.
```

---

## Part 4: Data-Oriented Design & ECS Standard

### 4.1 ECS Architecture (Entity-Component-System)

**MANDATE** for all stateful applications: architecture MUST follow the ECS pattern
using the `hecs` crate (or a custom equivalent).

#### 4.1.1 Why ECS

| Concern | OOP | ECS |
|---------|-----|-----|
| Data layout | AoS — scattered in memory | SoA — dense, contiguous |
| Cache efficiency | Poor (touches all fields) | Excellent (touches only needed fields) |
| Polymorphism | Virtual dispatch (vtable) | Static dispatch (generics) |
| Adding behavior | Modify class (violates OCP) | Add system (no existing code change) |
| Serialization | Graph of objects | Flat arrays of components |
| Formal proof | Hard (dynamic dispatch, hidden state) | Easy (flat data, pure systems) |
| Concurrency | Shared mutable state | Systems operate on disjoint component sets |

#### 4.1.2 Component Definitions

```rust
/// [PROVED] All components are POD (plain old data) — no Drop, no panics.
use hecs::Component;

/// Position in 3D space.
/// [PROVED] Arithmetic does not overflow for expected game coordinates (-1e6 to 1e6).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Position(pub [f32; 3]);

impl Component for Position {}

/// Velocity vector.
/// [PROVED] Bound: magnitude does not exceed 1e6 units/s.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Velocity(pub [f32; 3]);

impl Component for Velocity {}

/// Health value.
/// [PROVED] Invariant: 0 <= health <= max_health.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Health {
    pub current: u32,
    pub maximum: u32,
}

impl Component for Health {}

/// Player display name.
/// [PROVED] Size bound: 1..=64 UTF-8 bytes (enforced at construction).
#[derive(Clone, Debug, PartialEq)]
pub struct DisplayName(pub String);

impl Component for DisplayName {}

/// A tag component — no data, just presence.
/// Entities with this component are marked as "active" in the simulation.
#[derive(Clone, Copy, Debug)]
pub struct Active;

impl Component for Active {}
```

#### 4.1.3 System Definitions

```rust
/// [PROVED] All systems are pure: World in, World out. No side effects.
/// [PROVED] No system panics on any valid World state.

/// Updates entity positions based on velocity.
///
/// [PROVED] Kani harness in proofs/harnesses/ecs_proofs.rs
/// - Asserts: position changes by exactly velocity * dt
/// - Asserts: no entity is removed or added
/// - Asserts: no overflow for bounded velocity and dt
pub fn physics_system(world: &mut hecs::World, dt: f32) {
    // MANDATE: Query only the components needed — no waste.
    let mut query = world.query::<(&mut Position, &Velocity)>();
    for (_entity, (pos, vel)) in query.iter() {
        pos.0[0] += vel.0[0] * dt;
        pos.0[1] += vel.0[1] * dt;
        pos.0[2] += vel.0[2] * dt;
    }
}

/// Removes entities with health <= 0.
///
/// [PROVED] Kani harness proves:
/// - Entities with health > 0 are never removed
/// - Entities with health == 0 are always removed
pub fn death_system(world: &mut hecs::World) {
    let mut query = world.query::<&Health>();
    let mut to_despawn = Vec::new();
    for (entity, health) in query.iter() {
        if health.current == 0 {
            to_despawn.push(entity);
        }
    }
    for entity in to_despawn {
        let _ = world.despawn(entity);  // discard is conscious here — entity may already be gone
    }
}
```

#### 4.1.4 World Initialization Pattern

```rust
/// Constructs the initial ECS world.
///
/// [PROVED] All entities are created with ALL required components.
/// [PROVED] No entity is created without Position + Health.
pub fn initialize_world(player_count: u32) -> hecs::World {
    let mut world = hecs::World::new();

    for i in 0..player_count {
        world.spawn((
            Position([0.0, 0.0, 0.0]),
            Velocity([0.0, 0.0, 0.0]),
            Health { current: 100, maximum: 100 },
            DisplayName(format!("Player {i}")),
            Active,
        ));
    }

    world
}
```

### 4.2 Struct-of-Arrays (SoA) for Non-ECS Data

For data that doesn't fit ECS (e.g., configuration, lookup tables, external data
sources), use explicit SoA types:

```rust
/// [PROVED] All arrays have equal length (invariant enforced at construction).
/// [PROVED] Indexing any array by position index is always in bounds.

pub struct SimulationState {
    // Active objects — dense, contiguous, hot path
    pub positions: Vec<[f32; 3]>,
    pub velocities: Vec<[f32; 3]>,
    pub healths: Vec<u32>,

    // Passive metadata — sparse, cold path
    pub names: Vec<String>,
    pub descriptors: Vec<Vec<u8>>,  // ASN.1 DER encoded metadata
}

impl SimulationState {
    /// [PROVED] Returns None if index is out of bounds for any array.
    pub fn get_active(&self, idx: usize) -> Option<ActiveObject<'_>> {
        Some(ActiveObject {
            position: *self.positions.get(idx)?,
            velocity: *self.velocities.get(idx)?,
            health: *self.healths.get(idx)?,
        })
    }

    /// [PROVED] Panics if arrays have different lengths at any point.
    pub fn assert_invariants(&self) {
        assert_eq!(self.positions.len(), self.velocities.len());
        assert_eq!(self.velocities.len(), self.healths.len());
        assert_eq!(self.healths.len(), self.names.len());
    }
}
```

### 4.3 Hot/Cold Splitting Decision Matrix

```rust
/// FORBIDDEN: Monolithic struct with mixed-frequency fields.
#[derive(Debug)]
pub struct Player {
    // HOT
    pub position: [f32; 3],       // accessed every frame
    pub velocity: [f32; 3],       // accessed every frame
    pub health: u32,               // accessed every frame
    pub stamina: u32,              // accessed every frame
    // COLD
    pub display_name: String,      // accessed on UI hover only
    pub guild_name: String,        // accessed once on login
    pub inventory: Vec<Item>,      // accessed on inventory open
    pub quest_log: Vec<Quest>,     // accessed on quest journal open
}

/// MANDATE: Split by access frequency.
pub struct PlayerHot {
    pub positions: Vec<[f32; 3]>,
    pub velocities: Vec<[f32; 3]>,
    pub healths: Vec<u32>,
    pub staminas: Vec<u32>,
}

pub struct PlayerCold {
    pub display_names: Vec<String>,
    pub guild_names: Vec<String>,
    pub inventories: Vec<Vec<Item>>,
    pub quest_logs: Vec<Vec<Quest>>,
}
```

**RATIONALE:** 80% of CPU time is spent on 20% of the data (hot path). By keeping hot
data in dense arrays, you maximize cache utilization. Cold data can be loaded lazily
or stored off-heap without affecting frame time.

---

## Part 5: ASN.1 + DER — Strict Data Parsing

### 5.1 Foundational Principles

```
MANDATE:
  - ALL data structures MUST have an ASN.1 schema
  - ALL encoding MUST use DER (Distinguished Encoding Rules)
  - ALL parsers MUST reject ANY deviation from schema
  - ZERO tolerance for "best effort" parsing
  - ZERO tolerance for silent defaults on missing data
  - ZERO tolerance for lenient mode — there is no lenient mode
```

**RATIONALE:** DER produces **exactly one valid byte sequence** per value. This means:
- Signatures over DER bytes are deterministic (same value = same bytes = same signature)
- Parsers cannot disagree on the meaning of a valid input
- Canonicalization is unnecessary — DER IS the canonical form
- Testing is exhaustive (finite encoding space for bounded types)

### 5.2 Why DER Over Other Encoding Rules

| Encoding Rule | Deterministic? | Ambiguity? | Status |
|---------------|---------------|------------|--------|
| BER | No | Multiple encodings per value | FORBIDDEN |
| CER | Partially | Length ambiguity | NOT STRICT ENOUGH |
| **DER** | **Yes** | **Exactly one** | **MANDATED** |
| PER | No | Alignment-dependent decoding | AVOID |
| XER/JER | No | Whitespace/attribute flexibility | FORBIDDEN |
| GSER | No | Human-readable ambiguity | FORBIDDEN |

### 5.3 Schema Module Structure

```
schema/
├── common/
│   ├── primitives.asn1          # All constrained primitive types
│   ├── identifiers.asn1         # OID registrations
│   └── timestamps.asn1          # Time type definitions
├── domain/
│   └── project.asn1             # Project-specific types
└── manifest.asn1                # Top-level container schema
```

**MANDATE:** Every `.asn1` file MUST use `EXPLICIT TAGS`.
**FORBIDDEN:** `AUTOMATIC TAGS` (generates implicit tags — dangerous).
**FORBIDDEN:** `IMPLICIT TAGS` (loses type information).
**FORBIDDEN:** `EXPORTS ALL` (no wildcard exports).
**FORBIDDEN:** Unconstrained primitive types (EVERY type MUST have constraints).

### 5.4 Type Definition Rules

**ALL primitives MUST be constrained:**

```asn1
-- FORBIDDEN: No constraints
BadHostname ::= UTF8String              -- What length? What charset?
BadPort     ::= INTEGER                 -- What range? Negative?
BadPayload  ::= OCTET STRING            -- How many bytes? Any limit?

-- MANDATE: Every primitive has constraints
Hostname    ::= IA5String (SIZE (1..253))
PortNumber  ::= INTEGER (1..65535)
SHA256Hash  ::= OCTET STRING (SIZE (32))
TimeoutMs   ::= INTEGER (100..300000)
RetryCount  ::= INTEGER (0..10)
```

**FORBIDDEN:** `DEFAULT` values in SEQUENCE (obscures whether sender set it or not).
**FORBIDDEN:** Extensibility markers (`...`) without documented approval.
**MANDATE:** Every CHOICE alternative MUST have unique context tags.
**MANDATE:** Every SEQUENCE field MUST document WHY it is OPTIONAL (not just that it is).

### 5.5 DER Enforcement Checklist

Every DER encoder and decoder MUST enforce:

```
LENGTH ENCODING
  ✓ Short form (single byte) for lengths 0-127
  ✓ Long form for lengths >= 128
  ✗ Indefinite length (0x80)                   REJECT
  ✗ Unnecessary long form (e.g., 81 01 for len 1) REJECT
  ✗ Padded length                              REJECT

INTEGER ENCODING
  ✓ Minimum number of bytes in two's complement
  ✗ Leading 0x00 bytes (except to avoid sign bit) REJECT
  ✗ Leading 0xFF bytes (except for negative)     REJECT

BOOLEAN ENCODING
  ✓ FALSE = 0x01 0x01 0x00 (tag, length, value)
  ✓ TRUE  = 0x01 0x01 0xFF
  ✗ TRUE as any non-0xFF value                   REJECT
  (BER allows TRUE = any non-zero byte;
   DER mandates exactly 0xFF)

BIT STRING ENCODING
  ✓ Unused bits byte always present
  ✓ Unused bits MUST be zero
  ✗ Constructed form for bit string             REJECT
  ✗ Non-zero unused bits                        REJECT

STRING ENCODING (all string types)
  ✓ Primitive form only
  ✗ Constructed form for strings                REJECT

SET ENCODING
  ✓ Components ordered by tag value (ascending)
  ✗ Out-of-order components                     REJECT

TRAILING DATA
  ✗ Any bytes after valid DER structure         REJECT
  (Critical security property — prevents framing attacks)
```

### 5.6 Three-Phase Validation Pipeline

```
PHASE 1: DER STRUCTURAL VALIDATION
  |  Parse raw bytes according to DER rules
  |  Check all length fields, tag encodings, nesting depth
  |  REJECT trailing bytes, indefinite lengths, non-minimal encodings
  |  RESULT: Structural DER tree OR REJECT(E00x)

PHASE 2: SCHEMA CONFORMANCE
  |  Match structure against ASN.1 schema
  |  Verify required fields present, unknown fields absent
  |  Verify type constraints (INTEGER ranges, string lengths, enum values)
  |  RESULT: Schema-conformant structure OR REJECT(E01x-E03x)

PHASE 3: SEMANTIC VALIDATION
  |  Cross-field constraint checking
  |  Business logic validation (e.g., port >= 1024 requires privilege flag)
  |  Digest/signature verification (if applicable)
  |  RESULT: Fully validated value OR REJECT(E04x)
```

### 5.7 Complete Schema Example

```asn1
ORG-Project-Config-v1
    { 1 2 840 113549 1 9 1 }

DEFINITIONS EXPLICIT TAGS ::= BEGIN

EXPORTS
    ServiceManifest,
    NetworkConfig,
    DatabaseConfig,
    SecurityConfig
    ;

-- ============================================
-- CONSTRAINED PRIMITIVES
-- ============================================

ConfigVersion ::= INTEGER (1..1)                -- Only v1 exists
Hostname      ::= IA5String (SIZE (1..253))
PortNumber    ::= INTEGER (1..65535)
TimeoutMs     ::= INTEGER (100..300000)
RetryCount    ::= INTEGER (0..10)
SHA256Digest  ::= OCTET STRING (SIZE (32))

-- ============================================
-- ENUMERATIONS (NO extensibility)
-- ============================================

Protocol ::= ENUMERATED { tcp (0), tls (1) }
TLSVersion ::= ENUMERATED { tls-1-2 (2), tls-1-3 (3) }
LogLevel ::= ENUMERATED { debug (0), info (1), warning (2), error (3), fatal (4) }

-- ============================================
-- COMPOUND TYPES
-- ============================================

NetworkConfig ::= SEQUENCE {
    version      ConfigVersion,
    hostname     Hostname,
    port         PortNumber,
    protocol     Protocol,
    timeout      TimeoutMs,
    retries      RetryCount,
    tls-config   [0] EXPLICIT TLSConfiguration OPTIONAL
    -- tls-config: required when protocol = tls, forbidden when protocol = tcp
    -- (semantic constraint enforced in Phase 3 validation)
}

TLSConfiguration ::= SEQUENCE {
    min-version        TLSVersion,
    verify-peer        BOOLEAN,
    pinned-cert-hash   [0] EXPLICIT SHA256Digest OPTIONAL,
    allow-resumption   BOOLEAN,
    max-version        [1] EXPLICIT TLSVersion OPTIONAL
}

ServiceManifest ::= SEQUENCE {
    version        ConfigVersion,
    service-name   IA5String (SIZE (1..63)),
    config-digest  SHA256Digest,
    network        NetworkConfig,
    created-at     GeneralizedTime,
    schema-oid     OBJECT IDENTIFIER
}

END
```

### 5.8 Error Taxonomy for Parsing

```
E001  UNEXPECTED_EOF          Input ended mid-structure
E002  INVALID_LENGTH          Length field malformed
E003  INDEFINITE_LENGTH       BER indefinite form detected
E004  TRAILING_DATA           Extra bytes after valid structure
E005  DEPTH_EXCEEDED          Nesting depth > 32
E006  SIZE_EXCEEDED           Input > 16MB

E010  UNEXPECTED_TAG          Wrong tag for expected type
E011  UNKNOWN_TAG             Unrecognized tag value
E012  WRONG_CONSTRUCTED_BIT   Primitive/constructed mismatch

E020  NON_MINIMAL_INTEGER     Leading zero/0xFF bytes
E021  INVALID_BOOLEAN         TRUE not encoded as 0xFF
E022  INVALID_BIT_STRING      Unused bits not zero
E023  INVALID_UTF8            Invalid UTF-8 sequence
E024  INVALID_IA5             Non-ASCII in IA5String
E025  INVALID_OID             Malformed OID encoding
E026  INVALID_TIME            Malformed time value
E027  SET_ORDER_VIOLATED      SET components out of order

E030  VALUE_OUT_OF_RANGE      INTEGER outside range constraint
E031  SIZE_OUT_OF_RANGE       String/collection wrong size
E032  INVALID_ENUM            Undefined enumeration value
E033  MISSING_REQUIRED_FIELD  SEQUENCE missing mandatory field
E034  UNKNOWN_FIELD           SEQUENCE has extra field

E040  CROSS_FIELD_CONSTRAINT  Combined constraint violation
E041  SEMANTIC_RANGE          Value valid per schema, invalid semantically
E042  VERSION_UNSUPPORTED     Version field outside supported window
```

**MANDATE:** Every error MUST include:
- Error code (from the taxonomy above)
- Byte offset where error was detected
- Schema path to the error location (e.g., `ServiceManifest.network.port`)
- Expected value/type
- Actual value/type found

---

## Part 6: Formal Verification Pipeline (SPARK-Level)

### 6.1 The Proof Pyramid (Previously introduced in §0.3.2)

This section provides implementation details for each layer.

### 6.2 Kani Integration

#### 6.2.1 Proofs Crate Setup

**proofs/Cargo.toml:**

```toml
[package]
name    = "proofs"
version = "0.1.0"
edition = "2021"
publish = false

[dependencies]
project_name = { path = ".." }
kani         = { version = "0.55", features = ["concrete"] }

# Cannot use std for proofs when the target is no_std.
# Proofs crate always uses std for harness infrastructure.
```

**proofs/src/lib.rs:**

```rust
//! Kani proof harnesses for project_name.
//!
//! Each module contains proof harnesses for a specific domain.
//! Every proof harness is a function annotated with #[kani::proof]
//! that Kani model-checks for:
//! - No panics (unwrap, expect, index, assert, panic)
//! - No arithmetic overflow
//! - No bounds errors
//! - Custom invariants via kani::assert

pub mod parser_proofs;
pub mod ecs_proofs;
pub mod state_machine_proofs;
pub mod math_proofs;
```

#### 6.2.2 Proof Harness Patterns

**Pattern 1: Unwrap-Safety Proof**

```rust
/// [PROVED] ConfigParser::parse never panics on any valid DER input.
#[kani::proof]
pub fn config_parser_never_panics() {
    // Kani symbolically generates ALL possible valid DER byte sequences
    // that conform to the NetworkConfig schema.
    let bytes: [u8; 128] = kani::any();  // symbolic input up to 128 bytes
    let len: usize = kani::any();
    kani::assume(len <= bytes.len());

    let result = ConfigParser::parse(&bytes[..len]);

    // The parser MUST return Ok or Err — never panic.
    // Kani verifies this for ALL symbolic inputs within bounds.
    // If the parser panics on ANY input, this proof FAILS.
}
```

**Pattern 2: Invariant Proof**

```rust
/// [PROVED] Health component invariant: current <= maximum always.
#[kani::proof]
pub fn health_invariant() {
    let current: u32 = kani::any();
    let maximum: u32 = kani::any();
    kani::assume(current <= maximum);  // only valid health values

    let health = Health { current, maximum };

    // After construction, the invariant holds by type construction.
    // But what about modification? Prove that death_system preserves it.
    let mut world = hecs::World::new();
    let entity = world.spawn((health,));
    death_system(&mut world);

    // After death_system:
    // - If entity still exists, its health invariant holds.
    // - If entity was despawned, that's correct behavior (health == 0).
    let query = world.query::<&Health>();
    for (_e, h) in query.iter() {
        kani::assert(h.current <= h.maximum,
            "health invariant preserved");
    }
}
```

**Pattern 3: Bounded Loop Proof**

```rust
/// [PROVED] Physics system processes exactly N entities for bounded N.
#[kani::proof]
#[kani::unwind(100)]  // Kani needs loop bound hint
pub fn physics_system_bounded() {
    let mut world = hecs::World::new();
    let count: u32 = kani::any();
    kani::assume(count > 0);
    kani::assume(count <= 100);  // bounded for proof

    for i in 0..count {
        world.spawn((
            Position([0.0, 0.0, 0.0]),
            Velocity([1.0, 0.0, 0.0]),
        ));
    }

    physics_system(&mut world, 1.0 / 60.0);

    // Every entity's position changed by exactly velocity * dt
    let query = world.query::<(&Position, &Velocity)>();
    for (_e, (pos, vel)) in query.iter() {
        kani::assert(pos.0[0] == vel.0[0] / 60.0,
            "physics invariant");
    }
}
```

#### 6.2.3 Coding for Proved Correctness

Code must be written in a style amenable to Kani model-checking:

```
MANDATE (for proved code):
  - Loop bounds MUST be statically known or symbolic-bounded
  - No recursion without proven termination
  - No trait objects (dyn Trait) — dynamic dispatch blocks proof
  - No interior mutability (RefCell, Mutex) in proved paths
  - No raw pointer dereference
  - All indexing MUST be provably in-bounds
  - All arithmetic MUST be provably overflow-free

SHOULD (for proved code):
  - Use bounded integer types (u8, u16, u32) where possible
  - Use .get() and explicit bounds checks instead of [] where
    bounds cannot be statically proved
  - Factor out pure functions from side-effectful code
  - Keep functions small (Kani verification time scales super-linearly)
```

#### 6.2.4 Kani CI Integration

```yaml
# In CI workflow:
- name: Run Kani proofs
  run: |
    cd proofs
    cargo kani \
      --enable-unstable \
      --restrict-vtable  \
      --default-unwind 100 \
      --output-format terse
  timeout-minutes: 60
```

### 6.3 Property-Based Testing (proptest)

For code that Kani cannot prove (FFI, syscalls, unbounded algorithms, external services):

```rust
/// [TESTED] Config round-trip property: parse(serialize(c)) == c for all valid configs.
proptest! {
    #[test]
    fn config_roundtrip(config: NetworkConfig) {
        let bytes = config.serialize_to_der();
        let parsed = NetworkConfig::parse_from_der(&bytes).unwrap();
        assert_eq!(config, parsed);
    }

    #[test]
    fn hostname_valid_chars(hostname: String) {
        prop_assume!(hostname.len() >= 1 && hostname.len() <= 253);
        prop_assume!(hostname.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '.'));
        let config = NetworkConfig {
            hostname: Hostname::new(&hostname).unwrap(),
            ..Default::default()
        };
        let bytes = config.serialize_to_der();
        let parsed = NetworkConfig::parse_from_der(&bytes).unwrap();
        assert_eq!(config, parsed);
    }
}
```

**MANDATE:** Every `parse` function MUST have a round-trip property test.
**MANDATE:** Every `serialize` function MUST have a corpus of known-good DER vectors.
**MANDATE:** 10,000+ random test cases per property in CI.

### 6.4 Fuzzing

For I/O boundaries, parsing, and deserialization:

```rust
// fuzz/fuzz_targets/der_parser.rs
#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    // Fuzz the DER parser with arbitrary byte sequences.
    // The parser MUST NOT panic on ANY input — valid or invalid.
    let _ = NetworkConfig::parse_from_der(data);
});
```

**MANDATE:** Every function that accepts `&[u8]` from external sources MUST have a fuzz target.
**MANDATE:** CI runs each fuzz target for minimum 5 minutes.

---

## Part 7: Cross-Compilation

### 7.1 Primary Method — Nix Flakes

```bash
# Build for current platform
nix build .

# Build for specific target
nix build .#x86_64-unknown-linux-musl
nix build .#aarch64-unknown-linux-musl
nix build .#x86_64-pc-windows-gnu

# Build all targets
nix build .#all
```

### 7.2 Fallback — Zig via nixpkgs

Zig linker remains available in the Nix dev shell via `pkgs.zig`. For ad-hoc cross-compilation outside Nix:

```bash
# Only for development iteration, NOT for CI
cargo zigbuild --target x86_64-unknown-linux-musl --release
```

**MANDATE:** CI SHALL build ALL targets via `nix build` inside the Nix sandbox.
**MANDATE:** `cargo-zigbuild` is FORBIDDEN in CI.
**SHOULD:** Use `nix build` for local cross-compilation. `cargo zigbuild` is acceptable for quick iteration.

### 7.3 cross/targets.toml (Optional)

If a `cross/targets.toml` exists, its targets MUST match a subset of the Nix build matrix. It is purely a development convenience for `cargo zigbuild` iteration.

**RATIONALE:** Nix provides the same "build once, run anywhere" property as zigbuild, but with stronger guarantees: content-addressed dependencies, exact toolchain pinning, and full sandbox isolation. Zig is still available for its linker capabilities when needed.

---

## Part 8: Build System

### 8.1 justfile — Human Interface

```just
# justfile — human interface to all project tasks.
# All complex logic lives in xtask (Rust).
# justfile = thin wrapper for discoverability and tab-completion.

# ─────────────────────────────────────────
# HELP
# ─────────────────────────────────────────

# Show available recipes.
default:
    @just --list --unsorted

# ─────────────────────────────────────────
# DEVELOPMENT
# ─────────────────────────────────────────

# Run complete check pipeline (lint + test + proof + docs + audit)
check:
    cargo xtask check

# Run lint only (clippy + fmt + no_std check)
lint:
    cargo xtask lint

# Run tests only
test:
    cargo xtask test

# Run tests with output shown
test-verbose:
    cargo test --all-targets --all-features -- --nocapture

# Run a single test by name
test-one NAME:
    cargo test --all-targets --all-features -- {{NAME}} --nocapture

# ─────────────────────────────────────────
# FORMAL VERIFICATION
# ─────────────────────────────────────────

# Run all Kani proofs
proof:
    cargo xtask proof

# Run property tests (proptest) with high iteration count
proptest:
    PROPTEST_CASES=100000 cargo test proptest -- --nocapture

# Run fuzz targets (5 min each)
fuzz:
    cargo xtask fuzz

# ─────────────────────────────────────────
# CODE QUALITY
# ─────────────────────────────────────────

# Format all code
fmt:
    cargo fmt --all

# Format check without modifying
fmt-check:
    cargo fmt --all --check

# Run clippy strict
clippy:
    cargo clippy --all-targets --all-features -- -Dwarnings

# ─────────────────────────────────────────
# DOCUMENTATION
# ─────────────────────────────────────────

# Build all documentation
docs:
    cargo xtask docs

# Build and open Rust API docs
docs-open:
    cargo doc --all-features --no-deps --open

# Build AsciiDoc documentation
docs-adoc:
    asciidoctor --failure-level=WARN docs/modules/ROOT/pages/index.adoc

# ─────────────────────────────────────────
# SECURITY
# ─────────────────────────────────────────

# Run security audit
audit:
    cargo xtask audit

# Check for outdated dependencies
outdated:
    cargo outdated --exit-code 1

# ─────────────────────────────────────────
# CROSS-COMPILATION
# ─────────────────────────────────────────

# Cross-compile for all configured targets
cross:
    cargo xtask cross

# Cross-compile for a single target
cross-one TARGET:
    cargo xtask cross --target {{TARGET}}

# ─────────────────────────────────────────
# VERSION CONTROL (jj with git backend)
# ─────────────────────────────────────────

# Show repository status
status:
    jj status

# Show log with graph
log:
    jj log

# Show diff
diff:
    jj diff

# Undo last operation
undo:
    jj undo

# Create new change (branch)
new BRANCH:
    jj new --insert-after {{BRANCH}}

# Describe current change (commit message)
describe MSG:
    jj describe -m {{MSG}}

# Push to GitHub
push:
    jj git push

# ─────────────────────────────────────────
# RELEASE
# ─────────────────────────────────────────

# Prepare release (full check + README generation + version bump)
release VERSION:
    cargo xtask release --version {{VERSION}}

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

# CI check (equivalent to full pipeline)
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
    rm -rf build/
```

### 8.2 xtask — Rust Automation Core

#### xtask/src/main.rs

```rust
//! xtask: project build automation
//!
//! All build tasks defined here.
//! Called via: cargo xtask <task>
//! Or via: just <recipe> (which calls cargo xtask)

use anyhow::Result;
use clap::{Parser, Subcommand};

mod tasks;
mod utils;

#[derive(Parser)]
#[command(name = "xtask")]
#[command(about = "Project build automation")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Run all checks (lint + test + proof + docs + audit)
    Check,
    /// Run clippy with strict settings
    Lint,
    /// Run all tests
    Test,
    /// Run Kani proofs
    Proof,
    /// Run fuzz targets
    Fuzz,
    /// Build documentation
    Docs,
    /// Run security audit
    Audit,
    /// Prepare release
    Release {
        #[arg(long)]
        version: String,
        #[arg(long, default_value = "false")]
        dry_run: bool,
    },
    /// Cross-compile for all targets
    Cross {
        #[arg(long)]
        target: Option<String>,
    },
    /// Verify no_std compliance
    NoStd,
    /// Check MSRV compliance
    Msrv,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Check               => tasks::check::run(),
        Command::Lint                => tasks::lint::run(),
        Command::Test                => tasks::test::run(),
        Command::Proof               => tasks::proof::run(),
        Command::Fuzz                => tasks::fuzz::run(),
        Command::Docs                => tasks::docs::run(),
        Command::Audit               => tasks::audit::run(),
        Command::Release { version, dry_run } => tasks::release::run(&version, dry_run),
        Command::Cross { target }    => tasks::cross::run(target.as_deref()),
        Command::NoStd               => tasks::nostd::run(),
        Command::Msrv                => tasks::msrv::run(),
    }
}
```

#### xtask/src/tasks/proof.rs

```rust
//! Proof task: runs Kani verification.
//!
//! MANDATE: All Kani proofs must pass before merge.
//! Kani verifies: no panics, no overflow, no bounds errors, invariants.

use anyhow::Result;
use crate::utils::shell::run_command;

pub fn run() -> Result<()> {
    println!("Running Kani verification...");
    println!("This will take 30-60 minutes for a full proof run.");
    println!("(Use --target to limit to specific proof harness for faster iteration)");

    run_command(
        "cargo",
        &[
            "kani",
            "--enable-unstable",
            "--restrict-vtable",
            "--default-unwind", "100",
            "--output-format", "terse",
        ],
        "Kani proof verification failed. See Kani output above for details.",
    )?;

    println!("All Kani proofs passed.");
    Ok(())
}
```

#### xtask/src/tasks/release.rs

```rust
//! Release task.
//!
//! Runs full check pipeline, generates README.md from README.adoc,
//! and prepares release artifacts.

use anyhow::Result;
use crate::utils::shell::run_command;

pub fn run(version: &str, dry_run: bool) -> Result<()> {
    if dry_run {
        println!("DRY RUN: Release would be prepared with version {version}");
        println!("  Phase 1: Full check pipeline");
        println!("  Phase 2: README.adoc -> README.md conversion");
        println!("  Phase 3: Version bump");
        println!("  Phase 4: Tag and sign");
        return Ok(());
    }

    // Phase 1: Full check must pass before release.
    println!("Phase 1: Running full check pipeline...");
    super::check::run()?;

    // Phase 2: Convert README.adoc to README.md for crates.io.
    println!("Phase 2: Generating README.md from README.adoc...");
    convert_readme()?;

    // Phase 3: Cross-compile for all targets.
    println!("Phase 3: Cross-compiling for all targets...");
    super::cross::run(None)?;

    println!("Release {version} prepared.");
    println!("Next steps:");
    println!("  1. Review CHANGELOG.adoc");
    println!("  2. Commit: git add -A && git commit -m 'release: {version}'");
    println!("  3. Tag:   git tag -s v{version} -m 'v{version}'");
    println!("  4. Publish: cargo publish");
    Ok(())
}

fn convert_readme() -> Result<()> {
    // Step 1: AsciiDoc -> DocBook via asciidoctor.
    run_command(
        "asciidoctor",
        &[
            "--backend=docbook",
            "--out-file=README.xml",
            "README.adoc",
        ],
        "asciidoctor failed: could not convert README.adoc to DocBook.",
    )?;

    // Step 2: DocBook -> Markdown via pandoc.
    run_command(
        "pandoc",
        &[
            "--from=docbook",
            "--to=gfm",
            "--output=README.md",
            "README.xml",
        ],
        "pandoc failed: could not convert README.xml to README.md.",
    )?;

    // Step 3: Remove intermediate DocBook file.
    run_command("rm", &["README.xml"],
        "Failed to remove intermediate README.xml.")?;

    println!("README.md generated from README.adoc.");
    Ok(())
}
```

### 8.3 xtask/src/utils/shell.rs

```rust
//! Shell utilities for xtask.
//! Strict command execution: any failure = hard error.
//! No silent failures. No ignored exit codes.

use anyhow::{bail, Context, Result};
use std::process::Command;

/// [PROVED] Run a command, fail hard on any error.
/// Panics only if the system is out of memory (cannot spawn process).
pub fn run_command(
    program: &str,
    args: &[&str],
    error_message: &str,
) -> Result<()> {
    let status = Command::new(program)
        .args(args)
        .status()
        .with_context(|| {
            format!(
                "Failed to execute: {} {}",
                program,
                args.join(" ")
            )
        })?;

    if !status.success() {
        bail!(
            "{}\nCommand: {} {}\nExit code: {}",
            error_message,
            program,
            args.join(" "),
            status.code().unwrap_or(-1)
        );
    }

    Ok(())
}

/// [PROVED] Run command and capture output.
/// Fails if command fails OR if output is not valid UTF-8.
pub fn run_command_output(
    program: &str,
    args: &[&str],
) -> Result<String> {
    let output = Command::new(program)
        .args(args)
        .output()
        .with_context(|| {
            format!(
                "Failed to execute: {} {}",
                program,
                args.join(" ")
            )
        })?;

    if !output.status.success() {
        bail!(
            "Command failed: {} {}\nStderr: {}",
            program,
            args.join(" "),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    String::from_utf8(output.stdout)
        .context("Command output was not valid UTF-8")
}
```

---

## Part 9: AsciiDoc Documentation Standard

### 9.1 Principles

```
MANDATE:
  - ALL documentation MUST be written in AsciiDoc (.adoc)
  - ALL builds MUST fail on ANY warning (--failure-level=WARN)
  - ALL cross-references MUST be validated at build time
  - ALL prose MUST pass Vale linting at warning level
  - ZERO tolerance for ambiguous structure
  - ZERO tolerance for inconsistent terminology
  - ZERO tolerance for documentation that cannot build
```

### 9.2 Repository Structure

```
docs/
├── antora.yml                    # Antora component descriptor
├── .vale.ini                     # Vale prose lint config
├── asciidoc-lint.yml             # Structural lint rules
├── modules/ROOT/
│   ├── nav.adoc                  # Navigation definition
│   ├── pages/                    # All content pages
│   │   ├── index.adoc
│   │   ├── installation.adoc
│   │   ├── configuration.adoc
│   │   ├── development.adoc
│   │   └── reference/
│   │       ├── api.adoc
│   │       ├── cli.adoc
│   │       └── configuration.adoc
│   ├── partials/                 # Reusable fragments
│   │   ├── prerequisites-common.adoc
│   │   ├── warning-production.adoc
│   │   └── support-contact.adoc
│   └── assets/images/
│       └── architecture-diagram.png
└── vale/styles/                  # Vale configuration
    ├── Project/
    │   ├── Terms.yml
    │   ├── Headings.yml
    │   ├── Abbreviations.yml
    │   └── Punctuation.yml
    └── config/vocabularies/
        ├── accept.txt            # Approved technical terms
        └── reject.txt            # Forbidden terms
```

### 9.3 File Naming Rules

```
CORRECT:   deployment-procedure.adoc
FORBIDDEN: Deployment_Procedure.adoc
FORBIDDEN: deploymentProcedure.adoc
FORBIDDEN: deployment procedure.adoc
FORBIDDEN: deployment-procedure.txt

CORRECT:   installation/
FORBIDDEN: inst/
FORBIDDEN: Installation/
FORBIDDEN: installations/

CORRECT:   deployment-flow-diagram.png
FORBIDDEN: diagram1.png
FORBIDDEN: DeploymentFlow.png
```

### 9.4 Mandatory Document Header

```asciidoc
// RULE: Every .adoc page file MUST have this exact header structure.
// RULE: No exceptions. No omissions.
// RULE: Order is mandatory.

= Page Title in Title Case
Author Name <author@organization.com>
v{revnumber}, {revdate}
:description: One sentence description of this page.
:keywords: keyword1, keyword2, keyword3
:page-status: draft
:page-reviewed-by:
:page-reviewed-date:
```

### 9.5 Section ID Naming

```asciidoc
// FORBIDDEN: Relying on auto-generated ID
== Deployment Procedure
// Auto-generated: _deployment_procedure — breaks when title changes

// CORRECT: Explicit stable ID
[#deployment-procedure]
== Deployment Procedure
// ID is explicit, stable, rename-proof
// xref:deployment-procedure[] always works
```

**MANDATE:** Every section MUST have an explicit ID.
**MANDATE:** IDs use lowercase with hyphens.

### 9.6 Content Rules

```
MANDATE: One sentence per line in source (improves diffs).
MANDATE: Maximum 80 characters per line (not enforced on URLs).
MANDATE: ALL code blocks MUST declare their language.
MANDATE: Input and output in SEPARATE blocks.
MANDATE: Callouts for explanation, NOT inline comments.
MANDATE: ALL tables MUST have column specs, headers, and titles.
MANDATE: ALL cross-references use explicit IDs, never auto-generated.
MANDATE: ALL external links have descriptive text, never bare URLs.
MANDATE: ALL repeated values are AsciiDoc attributes, never hardcoded.

FORBIDDEN: "Click here" as link text.
FORBIDDEN: "Note that" in prose (use NOTE admonition).
FORBIDDEN: Future tense ("will be") — use present tense.
FORBIDDEN: Condescending language ("simply", "just", "obviously", "of course").
FORBIDDEN: Admonitions without titles.
FORBIDDEN: Skipped heading levels.
```

### 9.7 Vale Prose Lint Configuration

**docs/.vale.ini:**

```ini
StylesPath = vale/styles
MinAlertLevel = warning
Vocab = Project

[*.adoc]
BasedOnStyles = Vale, write-good

Project.Terms = YES
Project.Headings = YES
Project.Abbreviations = YES
Project.Punctuation = YES

Vale.Avoid = YES
Vale.Spelling = YES
Vale.Terms = YES

write-good.Passive = YES
write-good.TooWordy = YES
write-good.Weasel = YES
write-good.ThereIs = YES
```

### 9.8 README Generation Pipeline

```
README.adoc (source of truth)
    │
    ▼  asciidoctor --backend=docbook
README.xml (intermediate DocBook)
    │
    ▼  pandoc --from=docbook --to=gfm
README.md (generated for crates.io, in .gitignore)
```

**MANDATE:** Only `README.adoc` is edited manually.
**MANDATE:** `README.md` is in `.gitignore` and is NEVER committed.
**MANDATE:** README generation happens ONLY at release time (see xtask release).

---

## Part 10: Version Control

### 10.1 Guiding Philosophy

This standard uses a **dual VCS approach**:

| Layer | Tool | Role | Status |
|-------|------|------|--------|
| **Philosophical ideal** | **Pijul** | Patch-theory VCS. Formally grounded merge model — patches are first-class mathematical objects that commute, meaning merge conflicts are eliminated at the theoretical level. | Aspirational target. Adopt when pijul reaches production maturity (>= 1.0.0, stable SSH, proven ecosystem). |
| **Practical implementation** | **Jujutsu (`jj`)** | Change-oriented VCS built on git storage. 100% git-compatible — interoperates with GitHub/GitLab without migration. | Day-to-day tool. Used now. |
| **Fallback** | **`git`** | VCS of last resort for edge cases `jj` does not handle. | GitHub/GitLab protocol, submodules, `git am`. |

**RATIONALE:** Pijul's patch algebra (based on category theory pushouts) is the only VCS model that matches this standard's correctness requirements — it mathematically guarantees that two independent sets of patches always produce the same result regardless of application order. However, pijul is not yet production-ready (beta software, single-maintainer, chronic SSH issues, no ecosystem). `jj` provides ~80% of the philosophical benefit (change-oriented design, automatic rebase, first-class undo, conflict recording) with 100% git compatibility, making it the pragmatic choice until pijul matures.

### 10.2 Implementation: Jujutsu (`jj`)

#### 10.2.1 Installation

```bash
cargo install --locked jujutsu
```

#### 10.2.2 Initialize in Existing Git Repo

```bash
cd project/
jj git init --colocate    # creates .jj/ alongside .git/
```

The `--colocate` flag keeps the `.git` directory intact so `git` commands and GitHub integration continue to work. Every `jj` operation creates real git commits — your CI, code review, and deployment pipelines see nothing different.

#### 10.2.3 Recommended Repository Configuration (~/.jj/config.toml)

```toml
[user]
name = "Full Name"
email = "email@example.com"

[ui]
default-description = "wip"       # default change description
editor = "hx"                      # helix as default editor
diff-editor = "hx"                 # editor for conflict resolution

[git]
# Push to the remote whose bookmark matches the current branch
auto-local-branch = true
# Rebase onto target when pushing (safe by default)
rebase = true
# Push the current change even if it has conflicts
push-conflict = false               # MANDATE: resolve conflicts before push

[colors]
# Use delta-like colors for diffs
diff-header = "bold cyan"
diff-file-header = "bold yellow"
diff-context = "dim white"
diff-added = "bold green"
diff-removed = "bold red"

[templates]
# Compact one-line log format
log = """
change_id shortest " " commit_id.shortest " " bookmarks " " description " " empty
"""
```

#### 10.2.4 Key Workflow Mapping

| Intent | Git Command | jj Command | Notes |
|--------|-------------|------------|-------|
| Start new work | `git checkout -b feat` | `jj new feat` | Creates a new change on top of `@` |
| See status | `git status` | `jj status` | Also shows working-copy parent, conflicts |
| See log | `git log --graph` | `jj log` | Shows graph, change IDs, bookmarks by default |
| Stage files | `git add` | _(none)_ | Everything auto-snapshotted |
| Commit | `git commit -m "msg"` | `jj describe -m "msg"` | Describes the current change |
| Create a commit | `git commit` | `jj new` | After describing, create next change |
| Undo | `git reset` / reflog | `jj undo` | Full atomic operation undo |
| Amend | `git commit --amend` | `jj describe` (keeps re-running) | Idempotent — describe as many times as needed |
| Rebase | `git rebase main` | `jj rebase -d main` | All descendants auto-rebase |
| Squash | `git rebase -i` | `jj squash` | Squash current change into parent |
| Split | _(interactive rebase)_ | `jj split` | Interactive file-level split |
| Abandon | `git branch -D` | `jj abandon` | Marks as abandoned (history preserved) |
| Checkout old state | `git checkout HASH` | `jj edit HASH` | Working copy becomes that commit |
| Push | `git push` | `jj git push` | Pushes real git commits |
| Pull | `git pull --rebase` | `jj git fetch` then `jj rebase -d @-` | jj auto-rebases |
| Stash | `git stash` | `jj edit @-` | Just switch to another change — no stash needed |
| Cherry-pick | `git cherry-pick HASH` | `jj new HASH` | Creates child of the target change |
| Resolve conflicts | edit conflicted files | `jj resolve` | Conflicts are stored in commits — never blocking |

#### 10.2.5 How jj Aligns With This Standard

| Standard Principle | jj Enables |
|-------------------|------------|
| **§0.1 Minimalism** | No staging area. No stash. Fewer concepts to hold in your head. |
| **§0.2 Data-oriented** | Operation log is append-only data. Undo is just adding more data. |
| **§0.3 Formal verification** | Change IDs are permanent — no rewriting identity. `jj undo` eliminates the fear that leads to workarounds. |
| **§0.4 Tooling investment** | One Rust binary replaces `git` and most `git rebase -i` pain. |
| **§1.4 Rust-native** | Written in Rust. Installs via `cargo install --locked`. |
| **§6.2.3 Proved correctness** | Automatic rebase, first-class conflicts, full undo stack — fewer manual operations means fewer errors. |

#### 10.2.6 Known Gaps vs Git

| Gap | Workaround |
|-----|------------|
| Git submodules unsupported | Use `git submodule` commands for these rare cases |
| No `prepare-commit-msg` hooks | jj's model doesn't need them (no commit message on `jj new` — only on `jj describe`) |
| No `jj gh submit` yet | Use `gh` CLI or GitHub web UI to create PRs |
| No email workflow | Use `git format-patch` / `git am` for kernel-style workflows |

### 10.3 Philosophical Ideal: Pijul

#### 10.3.1 Why Pijul Is the Long-Term Target

Pijul is based on **patch theory** — a formal mathematical model rooted in category theory (pushouts). This gives it properties no snapshot-based VCS can match:

| Property | Git / jj | Pijul |
|----------|----------|-------|
| **Merge correctness** | Heuristic (3-way merge) — produces wrong results in edge cases | **Mathematically guaranteed** — the patch algebra always produces the unique correct merged state |
| **Commutation** | Not supported — patches depend on order | **Patches commute** — independent patches produce the same result regardless of application order |
| **Conflict representation** | Blocked until resolved, stored in merge commit | **First-class** — conflicts are recorded in the patch DAG, resolvable at any time |
| **Partial clone** | Worktrees / sparse checkout | **Native** — clone a subset of patches or paths |
| **Cherry-pick identity** | Creates a new commit (new hash) | **Preserves identity** — same patch, new context |

#### 10.3.2 Migration Path From jj → Pijul

When pijul reaches production maturity (assessed annually):

1. Export jj/git history as patches: `jj git export` or `git format-patch`
2. Import into pijul: `pijul clone` / `pijul apply` replay
3. Verify both repos produce identical working trees for all tagged releases
4. Update CI: replace `actions/checkout@v4` with pijul's native checkout
5. Update hosting: migrate from GitHub to nest.pijul.com or self-hosted
6. Update STANDARDS.md Part 10 to remove jj fallback

Until then, all development uses `jj`.

### 10.4 Branch Protection & Collaboration Rules

```
MANDATE:
  - main channel (git: main branch): protected
  - Requires PR with 2 approvals
  - Dismiss stale reviews on new commits
  - Require code owner reviews
  - Require linear history (no merge commits)
  - Require signed commits
  - No force pushes
  - No deletions
  - Required conversation resolution
```

Note: These rules are enforced at the **hosting platform** (GitHub), not the VCS. Since jj pushes real git commits, all existing GitHub protections apply unchanged.

---

## Part 11: Nushell Configuration & Scripts

### 11.1 ~/.config/nushell/config.nu

```nushell
$env.config = {
    error_style: "fancy"

    shell_integration: {
        osc2:   true
        osc7:   true
        osc133: true
    }

    history: {
        max_size:             100_000
        sync_on_each_command: true
        file_format:          "sqlite"
        isolation:            true
    }

    completions: {
        case_sensitive: true
        quick:          false
        partial:        false
        algorithm:      "fuzzy"
    }

    table: {
        mode:       "rounded"
        index_mode: "always"
        trim: {
            methodology:             "wrapping"
            wrapping_try_keep_words: true
        }
    }
}

# ─────────────────────────────────────────
# RUST-NATIVE UTILITY REPLACEMENTS
# ─────────────────────────────────────────

alias ls   = eza --long --git --icons --group-directories-first
alias ll   = eza --long --git --icons --all --group-directories-first
alias lt   = eza --tree --git --icons --level=3
alias cat  = bat --style=full
alias find = fd
alias grep = rg
alias du   = dust
alias ps   = procs
alias top  = btm
alias sed  = sd
alias cd   = z
alias git  = jj                    # jj as primary VCS (git-compatible)
alias diff = delta
alias curl = xh
alias dig  = dog
alias ping = gping
alias tar  = ouch

# ─────────────────────────────────────────
# ADDITIONAL RUST-NATIVE UTILITIES
# ─────────────────────────────────────────

alias gui = jj log                  # jj log with graph (TUI-like); or `gg` for dedicated TUI
alias net = bandwhich               # Network utilization TUI (per-process bandwidth)

# ─────────────────────────────────────────
# PROJECT-SPECIFIC ALIASES
# ─────────────────────────────────────────

alias c   = cargo
alias cxt = cargo xtask
alias j   = just

# ─────────────────────────────────────────
# ENVIRONMENT
# ─────────────────────────────────────────

$env.RUSTFLAGS         = "-Dwarnings"
$env.CARGO_TERM_COLOR  = "always"
$env.LANG              = "en_US.UTF-8"
$env.LC_ALL            = "en_US.UTF-8"
$env.EDITOR            = "hx"
$env.VISUAL            = "hx"
$env.PROPTEST_CASES    = "100000"  # High property test count

# ─────────────────────────────────────────
# STARSHIP PROMPT
# ─────────────────────────────────────────
# Initialize starship prompt (run once to create init file):
#   mkdir ~/.cache/starship
#   starship init nu | save -f ~/.cache/starship/init.nu
if ($"($env.HOME)/.cache/starship/init.nu" | path exists) {
    source $"($env.HOME)/.cache/starship/init.nu"
}
```

### 11.2 scripts/check-deps.nu (Replaced by Nix)

`scripts/check-deps.nu` is replaced by `nix flake check`, which verifies the full
environment integrity at the Nix level. A thin shim remains for backwards compatibility:

```nushell
#!/usr/bin/env nu
# check-deps.nu
# Thin wrapper around nix flake check.
# The canonical deps check is: nix flake check

def main [] {
    print "Checking development environment via Nix..."
    let result = (^nix flake check o+e>| complete)
    if $result.exit_code != 0 {
        error make {msg: $"Environment check failed: ($result.stderr)"}
    }
    print $"(ansi green)All environment checks passed.(ansi reset)"
}
```

### 11.3 scripts/dev-setup.nu (Replaced by Nix)

`scripts/dev-setup.nu` is replaced by `nix develop .`, which provides a
hermetic development shell. A thin shim remains for backwards compatibility:

```nushell
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
```

---

### 11.4 Optional Development Environment Configuration

The following configuration files live in the developer's home directory
(`~/.config/`), not in the project repository. They are part of the
development environment standard, not the project standard.

**MANDATE:** These configurations are NOT checked into any project repository.
They are templates that every developer SHOULD install on their local machine.

#### 11.4.1 starship Prompt (~/.config/starship.toml)

```toml
# starship.toml — cross-shell prompt
# Minimal, informative, fast.
# Works with nushell, bash, zsh, fish.

# Don't show until runtime exceeds threshold
command_timeout = 1000
scan_for_worktrees = false

[character]
success_symbol = "[❯](bold green)"
error_symbol   = "[❯](bold red)"

[git_branch]
format = " on [$symbol$branch(:$remote_branch)]($style)"
style = "bold purple"

[git_status]
conflicted = "🏳"
ahead      = "⇡\\({count}\\)"
behind     = "⇣\\({count}\\)"
diverged   = "⇕\\({count}\\)"
stashed    = "📦"
modified   = "!{count}"
staged     = "+{count}"
renamed    = "📝{count}"
deleted    = "✖{count}"
format      = "[\\($all_status$ahead_behind\\)]($style) "

[rust]
format = "via [$symbol($version )]($style)"

[cmd_duration]
format = "took [$duration]($style)"
show_milliseconds = true

# Minimal prompt line — just what you need
format = """
[](#9A348E)\\
$directory\\
$git_branch\\
$git_status\\
$rust\\
$cmd_duration\\
$character"""
```

**Installation:**

```bash
# In Nushell:
mkdir ~/.cache/starship
starship init nu | save -f ~/.cache/starship/init.nu
# Then add to ~/.config/nushell/config.nu:
#   source ~/.cache/starship/init.nu

# In bash:
# Add to ~/.bashrc: eval "$(starship init bash)"

# In zsh:
# Add to ~/.zshrc: eval "$(starship init zsh)"
```

#### 11.4.2 Helix Editor (~/.config/helix/config.toml)

```toml
# helix config.toml — modal editor
# Built-in LSP, tree-sitter, minimal configuration needed.

[editor]
line-number = "relative"         # relative line numbers for easy motion
mouse = false                     # keyboard-centric editing
true-color = true
completion-trigger-len = 1        # trigger completions after 1 character
auto-info = true                  # show info boxes
auto-completion = true
idle-timeout = 250                # ms before LSP request

[editor.cursor-shape]
insert = "bar"
normal = "block"
select = "underline"

[editor.statusline]
mode = true                       # show insert/normal/select
selections = true                 # show selection count
position = true                   # show line:column
file-encoding = true              # show UTF-8 etc.

[editor.lsp]
display-messages = true           # show LSP messages in status line
enable = true                     # enable LSP by default

[editor.whitespace]
render = true                     # show whitespace chars
characters = {
    space = "·"
    tab = "→"
    newline = "⏎"
}
```

**Helix language configuration (~/.config/helix/languages.toml):**

```toml
# Pin LSP servers per language
[language-server.rust-analyzer]
command = "rust-analyzer"

[language-server.taplo]            # for TOML files
command = "taplo"

[[language]]
name = "rust"
language-servers = ["rust-analyzer"]

[[language]]
name = "toml"
language-servers = ["taplo"]

[[language]]
name = "nushell"
language-servers = ["nu-lsp"]
```

#### 11.4.3 Zellij Terminal Multiplexer (~/.config/zellij/config.kdl)

```kdl
// zellij config.kdl — terminal multiplexer
// Built-in layout system, mouse support, session management.

keybinds {
    normal {
        // unbind some defaults to avoid conflicts with helix
        bind "Ctrl p" { SwitchToMode "Tmux"; }
        bind "Ctrl b" { SwitchToMode "Locked"; }
    }
}

plugins {
    tab-bar path="zellij:tab-bar"
    status-bar path="zellij:status-bar"
    strider path="zellij:strider"
    compact-bar path="zellij:compact-bar"
}

theme {
    bg  "#1a1b26"
    fg  "#c0caf5"
    red "#f7768e"
    green "#9ece6a"
    blue "#7aa2f7"
    yellow "#e0af68"
    magenta "#bb9af7"
    cyan "#7dcfff"
    orange "#ff9e64"
}

simplified_ui true
```

#### 11.4.4 Alacritty Terminal (~/.config/alacritty/alacritty.toml)

```toml
[env]
TERM = "xterm-256color"

[font]
size = 11

[font.normal]
family = "Iosevka Term"

[window]
opacity = 0.95
padding = { x = 4, y = 4 }

[colors]
[colors.primary]
background = "#1a1b26"
foreground = "#c0caf5"

[colors.cursor]
text = "#1a1b26"
cursor = "#c0caf5"

[colors.selection]
text = "#1a1b26"
background = "#c0caf5"

[colors.normal]
black   = "#15161e"
red     = "#f7768e"
green   = "#9ece6a"
yellow  = "#e0af68"
blue    = "#7aa2f7"
magenta = "#bb9af7"
cyan    = "#7dcfff"
white   = "#a9b1d6"
```

---

### 11.5 Nushell Scripting Standards

> **MANDATE:** Every `.nu` file in the project SHALL conform to the rules in this
> section. CI SHALL enforce these rules via `nu-lint` (see §11.5.11).

**RATIONALE:** Nushell is the organization's shell standard. Scripts are code —
they deserve the same rigor as Rust code. Consistent style, type safety, and
security practices prevent bugs at parse time instead of at 3 AM in production.

#### 11.5.1 Naming Conventions

```
MANDATE:
  Commands:           kebab-case     fetch-user, build-project
  Sub-commands:       kebab-case     "db migrate", "config validate"
  Variables/params:   snake_case     $user_id, $db_conn
  Environment vars:   SCREAMING_SNAKE_CASE   $env.APP_VERSION
  Flags:              kebab-case     --output-dir, --dry-run
  Constants:          SCREAMING_SNAKE_CASE   const API_VERSION = '1.0'
  Files/modules:      kebab-case     utils.nu, db-migrate.nu

FORBIDDEN:
  camelCase in commands or variables    fetchUser, $userId
  snake_case in commands                fetch_user
  PascalCase in anything                FetchUser, $UserId
  Abbreviations where full words exist  $usr_nm → $user_name, qry → query
```

```nu
# CORRECT
def fetch-user [user_id: int, --all-caps] {
    let display_name = $user_id | get-name
    $'User: ($display_name)'
}

# INCORRECT
def fetchUser [userId: int, --all_caps] {
    let displayName = $userId | get-name     # camelCase variable
    $'User: ($displayName)'
}
```

#### 11.5.2 Formatting Rules

**Defaults:**

```
MANDATE:
  - One space before and after pipe `|`
  - No consecutive spaces (except inside strings)
  - Omit commas between list items
  - No trailing whitespace on any line
  - No space before `|params|` in closures: {|x| ...} NOT { |x| ...}
  - One space after `:` in records: {x: 1} NOT {x:1}

FORBIDDEN:
  - More than one consecutive space
  - Commas in list literals
  - Trailing spaces
  - Space before closure pipe: { |x| ...}
```

```nu
# CORRECT
[1 2 3 4] | reduce {|elt acc| $elt + $acc }
{x: 1, y: 2}
[[status]; [UP] [UP]] | all {|el| $el.status == UP }

# INCORRECT
[1, 2, 3, 4] |  reduce {|elt, acc| $elt + $acc }   # commas + double space
{ x: 1, y: 2}                                          # space before x
[[status]; [UP] [UP]] | all { |el| $el.status == UP }  # space before |el|
```

**Multi-line Format (use when pipeline >80 chars or contains nested records/lists):**

```
MANDATE:
  - Each pipeline step on its own line
  - Each record key-value pair on its own line
  - Each list item on its own line
  - Opening `{` / `[` / `(` on same line as preceding expression
  - Closing `}` / `]` / `)` on its own line
  - 4-space indentation for continuation lines
```

```nu
# CORRECT — multi-line pipeline
let result = $data
    | where size > 1mb
    | sort-by name
    | select name path size
    | first 10

# CORRECT — multi-line record
let config = {
    host:    'localhost'
    port:    8080
    tls:     true
    timeout: 30_000
}
```

#### 11.5.3 String Format Priority

```
MANDATE string format selection order (use FIRST matching rule):
  ┌──────────────────────────────────────────────────────────────┐
  │ Priority │ Format               │ Example                   │
  ├──────────┼──────────────────────┼───────────────────────────┤
  │ 1 (best) │ Bare word in arrays  │ [foo bar baz]             │
  │ 2        │ Single-quoted        │ 'hello world'             │
  │ 3        │ Single-quoted interp │ $'val: ($x)'              │
  │ 4        │ Double-quoted        │ "tab: \t newline: \n"     │
  │ 5        │ Double-quoted interp │ $"val: ($x)"              │
  │ 6        │ Raw string           │ r#'\d+\.\d+#'             │
  └──────────────────────────────────────────────────────────────┘

FORBIDDEN:
  - Double quotes when single quotes suffice: "hello" → 'hello'
  - Double-quoted interpolation when single-quoted works
  - String interpolation with no variables: $"hello" → 'hello'
```

#### 11.5.4 Type Annotations

```
MANDATE:
  - ALL exported commands MUST have type annotations on ALL parameters
  - ALL exported commands MUST declare I/O signature: ]: input_type -> output_type
  - ALL constants MUST be typed via declaration: const FOO: string = 'bar'
  - ALL public commands MUST have a documented return type

SHOULD:
  - Private commands SHOULD have type annotations (catches parse-time errors)
  - Complex types SHOULD use proper syntax (see below)
```

```nu
# CORRECT — full type annotations + I/O signature
def process-item [
    id: int             # Record ID to process
    --verbose (-v)      # Show detailed output
    --output: string    # Output file path
]: int -> record<id: int, status: string> {
    #       ^ input    ^ output type
    {id: $id, status: 'ok'}
}

# Complex type syntax reference:
#   record<name: string, age: int>
#   list<string>
#   table<name: string, count: int>
#   record<metadata: record<version: string>>
#   optional: field?: string

# INCORRECT — no types
def process [id, --verbose] {
    # parse-time: no way to catch misuse
}
```

#### 11.5.5 Pipeline & Functional Style

```
MANDATE:
  - Pipelines over imperative loops in ALL cases
  - `reduce` over `mut` accumulator patterns
  - `each` over `for` for list transformations
  - `where` over manual filtering with `if`
  - `enumerate` over manual index counters

FORBIDDEN:
  - `mut` for accumulation when pipeline alternative exists
  - `for` as the final expression in a command (returns null)
  - `echo` for returning values (use implicit return)
```

```nu
# BAD — imperative accumulation
mut total = 0
for item in $items {
    $total += $item.price
}

# GOOD — functional pipeline
$items | get price | math sum

# BAD — mut + for to build a list
mut result = []
for f in (ls) {
    if ($f.size > 1mb) {
        $result = ($result | append $f.name)
    }
}

# GOOD — filter pipeline
ls | where size > 1mb | get name

# BAD — echo for return
def greet [name: string] {
    echo $'Hello, ($name)!'
}

# GOOD — implicit return
def greet [name: string] {
    $'Hello, ($name)!'
}

# BAD — for as final expression (returns null)
def squares []: nothing -> list<int> {
    for x in [1 2 3 4] {
        $x ** 2
    }  # returns null!
}

# GOOD — each returns the list
def squares []: nothing -> list<int> {
    [1 2 3 4] | each {|x| $x ** 2 }
}
```

#### 11.5.6 Module & Export Patterns

```
MANDATE:
  - ONLY necessary definitions are `export`-ed
  - `export def main` when command name matches module filename
  - `export-env` for environment setup blocks
  - `source`/`use` paths MUST be `const` (parse-time constant), NOT `let`

SHOULD:
  - Private helper commands left un-exported (intentionally private)
  - Submodules use `export module` to preserve namespace
  - Re-exports use `export use` to flatten namespace

FORBIDDEN:
  - `source`/`use` with dynamic (runtime) paths — will error
  - Wildcard re-exports that pull in unexpected names
```

```nu
# my-module.nu — CORRECT module pattern
export def main [] {                # main = module name
    do-setup
    do-work
}

def do-setup [] {                   # private — not exported
    print 'setup complete'
}

export def do-work [] {             # public — exported
    # ...
}

# INCORRECT — dynamic source path
let path = './utils.nu'
source $path                        # Error! Not parse-time constant

# CORRECT — const path
const PATH = './utils.nu'
source $PATH
```

**Export reference:**

| Export Type            | Keyword              | Example                                    |
|------------------------|----------------------|--------------------------------------------|
| Commands               | `export def`         | `export def build [] { ... }`              |
| Env commands           | `export def --env`   | `export def --env setup [] { ... }`        |
| Aliases                | `export alias`       | `export alias ll = eza -l`                |
| Constants              | `export const`       | `export const version = '1.0.0'`          |
| Externals              | `export extern`      | `export extern "git push" [...]`           |
| Submodules             | `export module`      | `export module utils.nu`                   |
| Re-exports             | `export use`         | `export use utils.nu *`                    |
| Env setup              | `export-env`         | `export-env { $env.FOO = 'bar' }`          |

#### 11.5.7 Error Handling

```
MANDATE:
  - Fallible operations MUST be wrapped in `try`/`catch`
  - External commands whose exit code matters MUST use `complete`
  - Custom errors MUST include `label` with `span` when source metadata exists
  - `catch` blocks MUST include meaningful error context (never empty)

SHOULD:
  - Use `default` for optional/fallback values instead of manual null checks
  - Capture `$in` with `let` when used multiple times (streaming caveat)

FORBIDDEN:
  - Bare `error make {msg: '...'}` without `label` when span is available
  - Empty `catch {|| }` blocks
  - Ignoring external command exit codes via bare `^cmd` when result matters
```

```nu
# CORRECT — complete for external command
let result = (^cargo build o+e>| complete)
if $result.exit_code != 0 {
    error make {
        msg: $'Build failed: ($result.stderr)'
        label: {
            text: 'Build error'
            span: (metadata $result).span
        }
    }
}

# CORRECT — try/catch with context
try {
    open $config_path
} catch {|err|
    error make {
        msg: $'Failed to open config at ($config_path): ($err)'
        label: {text: 'Config error'; span: (metadata $config_path).span}
    }
}

# CORRECT — default for null safety
let name = $input | default 'anonymous'
# NOT: let name = if $input == null { 'anonymous' } else { $input }

# CORRECT — optional field access with ?
let version = $record.version? | default '0.0.0'
# NOT: let version = $record.version   (panics if missing)
```

#### 11.5.8 Security Practices

```
CRITICAL — FORBIDDEN:
  - `nu -c $variable` with untrusted input (code injection)
  - `source $variable`/`use $variable` with runtime paths
  - `^sh -c`, `^bash -c`, `^cmd.exe /C` with interpolated user input
  - `run-external` with user-controlled command names
  - Hardcoded secrets/tokens/credentials in source code

HIGH — MANDATE:
  - User-provided paths validated with `path expand` + prefix check
  - No raw `open $user_input` without path traversal guard
  - `..` sequences in user paths detected and rejected
  - `rm` operations validate target path (not `/`, not `$nu.home-path`)
  - Glob patterns from user input validated (no unintended expansion)
  - `--depth` limits on `glob` to prevent DoS on large trees
  - Temp files created with `^mktemp`, not predictable paths
  - Temp files cleaned up in `try`/`catch` or equivalent
  - Credentials scoped with `with-env`, not set on `$env` directly
  - Secrets read from files/stdin, not passed as command-line arguments
  - External commands prefixed with `^` when name conflicts with builtins
```

```nu
# CORRECT — safe external command call
^find . -name '*.rs'          # explicit external via ^ prefix
^grep -r 'pattern' src/       # unambiguous external

# INCORRECT — builtin shadows external
find . -name '*.rs'           # Calls Nushell's find, NOT Unix find!
grep -r 'pattern' src/        # Calls Nushell's grep, NOT Unix grep!

# CORRECT — scoped credentials
with-env {DB_PASS: (open --raw /secrets/db_pass)} {
    ^my-app --connect $env.DB_PASS
}

# INCORRECT — credential on CLI (visible in ps)
^my-app --connect (open --raw /secrets/db_pass)
```

**Nushell builtins vs external commands reference:**

| Ambiguous Name | Nushell Builtin | Unix External (`^`) |
|----------------|-----------------|---------------------|
| `find`         | String search   | File search         |
| `sort`         | Table sort      | Line sort           |
| `date`         | Date commands   | Date (if installed) |
| `open`         | File reader     | (rare)              |
| `source`       | Module loader   | (rare)              |

#### 11.5.9 Anti-Patterns Reference

The following 23 anti-patterns are FORBIDDEN:

```
 1. echo for return values         → Use implicit return (last expression)
 2. for as final expression        → Use each (returns list)
 3. mut accumulator + for          → Use pipeline (reduce, math sum, where)
 4. Dynamic source/use paths       → Use const, never let
 5. Bash-style redirection (>)     → Use save / save --append
 6. String-parsing external output → Use structured commands (ls, http get)
 7. Missing type annotations       → Always annotate params + I/O signature
 8. Space before |params|          → {|x| ...} NOT { |x| ...}
 9. env changes in regular def     → Use def --env to propagate
10. Unnecessary string interp      → Use simplest format (see §11.5.3)
11. each when par-each works       → Use par-each for I/O/CPU-bound work
12. Missing command docs           → Always add # doc comments + @example
13. Manual null checks             → Use default 'fallback'
14. Manual structured data parse   → Use from json / open (native parser)
15. If-else chains for branching   → Use match for multi-branch
16. Missing --stdin in shebang     → Use #!/usr/bin/env -S nu --stdin
17. Forgetting export in modules   → Use export def for public API
18. Confusing pipeline vs params   → Use $in for pipeline input signature
19. each on single records         → Use items {|key, val| ...}
20. Missing field access without ? → Use $rec.field? for optional fields
21. Not prefixing externals with ^ → Use ^cmd when builtin shadows
22. Ignoring external exit codes   → Use complete for fallible externals
23. Length checks for emptiness    → Use is-empty / is-not-empty
```

#### 11.5.10 Performance Patterns

```
MANDATE in CI scripts and hot paths:
  - Use `par-each` for I/O-bound work (file reads, HTTP requests, network)
  - Use `par-each` for CPU-bound work (data processing, transforms)
  - Use `each` ONLY when order must be preserved or list is very small
  - Expensive results cached in `let` bindings, never recomputed
  - `--depth` limits on `glob` to avoid scanning huge directory trees

SHOULD:
  - `each --flatten` for streaming nested results
  - `lines` + pipeline for line-by-line processing of large files
  - Built-in commands preferred over external for small data (<1000 items)
  - External tools (`^rg`, `^jq`, `^awk`) for large-scale operations
  - `first N` / `take while` to limit processing early

FORBIDDEN:
  - Loading entire large files into memory when streaming suffices
  - Unbounded `glob` without `--depth`
```

```nu
# BAD — sequential file processing (slow)
ls **/*.json | each {|f| open $f.name | get version }

# GOOD — parallel file processing
ls **/*.json | par-each {|f| open $f.name | get version }

# BAD — recompute expensive result
if (ls | length) > 100 {
    print $'Many files: (ls | length)'   # ls called twice!
}

# GOOD — bind once
let files = (ls)
if ($files | length) > 100 {
    print $'Many files: ($files | length)'
}
```

#### 11.5.11 Linting & Formatting

```
MANDATE:
  - ALL `.nu` files SHALL pass `nu-lint` in CI
  - CI SHALL fail on any `nu-lint` error
  - Project root SHALL contain a `.nu-lint.toml` configuration

SHOULD:
  - `nu-lint` integrated into pre-commit hooks
  - `topiary` (tree-sitter formatter) used for automated formatting
```

**Sample `.nu-lint.toml`:**

```toml
max_pipeline_length = 80
pipeline_placement = "start"
explicit_optional_access = true

[groups]
security     = "error"
type-safety  = "error"
performance  = "warning"
naming       = "error"
formatting   = "error"
documentation = "warning"
idioms       = "error"
effects      = "error"

[rules]
kebab_case_commands          = "error"
snake_case_variables         = "error"
screaming_snake_constants    = "error"
missing_output_type          = "error"
add_type_hints_arguments     = "error"
add_doc_comment_exported_fn  = "warning"
unchecked_cell_path_index    = "error"
inconsistent_pipe_spacing    = "error"
for_instead_of_each          = "warning"
mut_instead_of_reduce        = "warning"
hat_external_commands        = "error"
dynamic_script_import        = "error"
```

**CI integration:**

```yaml
# In CI workflow:
- name: Lint Nushell scripts
  run: |
    nu-lint check scripts/ src/  # exit code != 0 → CI fails
```

#### 11.5.12 Testing Nushell Code

```
MANDATE:
  - ALL exported commands in shared modules SHALL have tests
  - Tests SHALL be placed in a `tests/` subdirectory relative to the module
  - Test files SHALL be named `<module>.test.nu`

SHOULD:
  - Use `nupm test` when working within a nupm-managed project
  - Use `assert` commands from the standard library
  - Provide `@example` attributes on non-trivial commands (used as doc-tests)
```

```nu
# my-module.nu
# Adds two numbers together.
# @example 'Add 2 and 3' { add 2 3 }  # returns 5
export def add [a: int, b: int]: nothing -> int {
    $a + $b
}

# tests/my-module.test.nu
use ../my-module.nu *

#[test]
def test_add [] {
    let result = add 2 3
    assert equal $result 5
}

#[test]
def test_add_negative [] {
    let result = add (-1) 1
    assert equal $result 0
}
```

---

## Part 12: Error Handling & Proof Taxonomy

### 12.1 Error Type Principles

```
MANDATE:
  - Every error variant is a STRUCT with named fields (no stringly-typed errors)
  - Every error includes source location (file, line)
  - Every error is #[non_exhaustive] (allows adding variants without breaking API)
  - Every error implements std::error::Error with source() chain
  - No Error::Other(String) catch-all variants
  - No anyhow::Error in library code (only in xtask/binaries)
  - No unwrap() in library code (unless Kani-proved impossible)
```

### 12.2 Proof Tier Annotations

Every public function MUST be annotated with one of:

```rust
/// [PROVED] — Kani harness exists and passes in CI.
/// Use for: core logic, parsing, state machines, data transformations.
/// Worst-case CI time: 30-60 min.

/// [TESTED] — Proptest with 10,000+ random cases per property.
/// Use for: functions Kani cannot handle (FFI, syscalls, unbounded algorithms).
/// Coverage: algebraic properties, round-trips, idempotence.

/// [LINTED] — Standard clippy + rustc warnings as errors.
/// Use for: top-level orchestration, main function, glue code.
/// This is the minimum bar for ALL code.

/// [FFI_AUDITED] — Unsafe code reviewed by 2 engineers.
/// Use for: FFI boundaries, inline assembly, raw pointer manipulation.
/// Audit MUST be documented with SAFETY comments on every unsafe block.
```

### 12.3 Invariant Violation Protocol

When an invariant is detected at runtime:

```rust
/// An invariant violation — indicates a BUG, not a recoverable error.
/// [PROVED] Kani proves this is never constructed when invariants hold.
#[derive(Debug)]
pub struct InvariantViolation {
    pub message: &'static str,
    pub file: &'static str,
    pub line: u32,
}

impl std::error::Error for InvariantViolation {}

impl fmt::Display for InvariantViolation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Invariant violation: {} at {}:{}",
            self.message, self.file, self.line)
    }
}
```

**MANDATE:** Invariant violations SHALL be logged at ERROR level and terminate the
operation. They are NOT recoverable errors — they are bugs.
**MANDATE:** Invariant violations MUST include file and line number for debugging.

---

## Part 13: Project Type Adaptation Guide

### 13.1 How To Trim the Framework

Not every section applies to every project type. Use this table to decide what
to keep, adapt, or remove.

| Section | CLI | TUI | GUI | Game | Web/WASM | LLM/AI | Library |
|---------|-----|-----|-----|------|----------|--------|---------|
| Part 0: Philosophy | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Part 1: Stack Decision | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Part 2: Repository | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Part 3: Rust Cfg | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Part 4: DOD/ECS | ECS opt | ECS opt | ECS ✓ | ECS ✓ | limited | data-pipeline | remove |
| Part 5: ASN.1/DER | config | config | config | save-fmt | config | model-data | ✓ |
| Part 6: Proof | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Part 7: Cross-compile | ✓ | ✓ | ✓ | ✓ | WASM only | server only | lib only |
| Part 8: Build | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Part 9: Docs | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Part 10: Git | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Part 11: Nushell | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Part 12: Errors | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

### 13.2 Adaptation Notes by Type

**CLI Application:**
- ECS: optional (for stateful CLIs with complex state)
- ASN.1/DER: for configuration files
- Cross-compilation: full matrix (Linux, Windows, macOS, WASM)
- Proof: focus on argument parsing, state machine logic

**TUI Application:**
- ECS: recommended for complex TUI state management (tabs, panes, input modes)
- ASN.1/DER: for configuration
- Dedicated note: use `ratatui` for rendering, but keep rendering logic SEPARATE from data logic

**GUI Application:**
- ECS: highly recommended for widget state, layout, event handling
- ASN.1/DER: for configuration and save files
- Dedicated note: GUI frameworks (egui, iced, gtk4-rs) may have their own paradigms.
  Wrap them behind DOD abstractions — never let GUI framework dictate data design.

**Game:**
- ECS: MANDATE (games are the canonical ECS use case)
- ASN.1/DER: for save files, replay data, game configuration
- Cross-compilation: full matrix + console targets if applicable
- Proof: focus on physics, state machines, network protocol parsing

**Web/WASM:**
- Cross-compilation: WASM targets only (wasm32-wasi, wasm32-unknown-unknown)
- ASN.1/DER: for server-client protocol, configuration
- ECS: optional (for complex frontend state)
- Dedicated note: WASM targets cannot use std::thread or std::net.
  Gate platform-specific code behind #[cfg(target_arch = "wasm32")].

**LLM/AI:**
- ECS: replace with data pipeline patterns (token → tensor → prediction)
- ASN.1/DER: for model configuration, tokenizer data, prompt templates
- Cross-compilation: server targets + GPU targets (if applicable)
- Proof: focus on tokenizer correctness, tensor bounds, memory safety
- Dedicated note: Use `candle` or `burn` for tensor operations.
  Keep data processing in safe Rust, push compute to GPU libraries.

**Library Crate:**
- ECS: remove (libraries should not mandate architecture)
- ASN.1/DER: keep for data format crates
- Cross-compilation: test all targets but only publish for host triple
- Proof: full Kani coverage on ALL public API

---

## Appendices

### Appendix A: Commitment Record

By adopting this standard, you commit to:

1. **Code correctness** — every line is either proved correct or audited
2. **Data orientation** — data structures define behavior, not the other way around
3. **Minimalism** — ship less code, verify it more thoroughly
4. **Portability** — build once, run on any target
5. **Documentation** — everything is documented, every document is linted, every build is validated
6. **Verification** — proof is not optional; it is the definition of done

### Appendix B: Quick Reference — The 12 Non-Negotiable Rules

```
┌──────────────────────────────────────────────────────────────────────┐
│                     THE 12 COMMANDMENTS                               │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  DATA & DESIGN                                                       │
│  1. Data structures first, algorithms second                          │
│  2. SoA over AoS in hot paths                                         │
│  3. Hot/cold split every struct with mixed-frequency fields           │
│  4. State machines are DATA (tables), not code (match arms)           │
│                                                                       │
│  SERIALIZATION                                                        │
│  5. DER ONLY. Never BER, CER, XER, or JER                             │
│  6. ALL primitives MUST have constraints                              │
│  7. NO silent defaults, NO extensibility markers without approval      │
│                                                                       │
│  VERIFICATION                                                         │
│  8. Every public fn has a proof tier annotation                       │
│  9. Kani on everything possible, proptest on the rest                 │
│  10. Build fails on ANY warning (lint, doc, proof, audit)             │
│                                                                       │
│  INFRASTRUCTURE                                                       │
│  11. just + xtask for all build tasks (never Makefile)                │
│  12. README.adoc is source of truth. README.md is generated.          │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

### Appendix C: Toolchain Source

| Tool | Source |
|------|--------|
| rustup | https://rustup.rs |
| cargo-zigbuild | https://github.com/rust-cross/cargo-zigbuild |
| Zig | https://ziglang.org/download |
| Kani | https://github.com/model-checking/kani |
| just | https://github.com/casey/just |
| jj | https://github.com/jj-vcs/jj |
| pijul | https://nest.pijul.com/pijul/pijul |
| Nushell | https://www.nushell.sh |
| nu-lint | https://crates.io/crates/nu-lint |
| topiary (tree-sitter formatter) | https://github.com/tweag/topiary |
| Asciidoctor | https://asciidoctor.org |
| Vale | https://vale.sh |
| proptest | https://github.com/proptest-rs/proptest |
| cargo-fuzz | https://github.com/rust-fuzz/cargo-fuzz |
| helix | https://helix-editor.com |
| hecs | https://github.com/Ralith/hecs |
| rasn | https://github.com/XAMPPRocky/rasn |
| ripgrep | https://github.com/BurntSushi/ripgrep |
| fd | https://github.com/sharkdp/fd |
| bat | https://github.com/sharkdp/bat |
| eza | https://github.com/eza-community/eza |
| delta | https://github.com/dandavison/delta |
| sd | https://github.com/chmln/sd |
| dust | https://github.com/bootandy/dust |
| bottom | https://github.com/ClementTsang/bottom |
| procs | https://github.com/dalance/procs |
| xh | https://github.com/ducaale/xh |
| zoxide | https://github.com/ajeetdsouza/zoxide |
| hyperfine | https://github.com/sharkdp/hyperfine |
| tokei | https://github.com/XAMPPRocky/tokei |
| ouch | https://github.com/ouch-org/ouch |
| starship | https://starship.rs |
| zellij | https://zellij.dev |
| alacritty | https://alacritty.org |
| gg | https://github.com/gutmet/gg |
| bandwhich | https://github.com/imsnif/bandwhich |
| gping | https://github.com/orf/gping |
| dog | https://github.com/ogham/dog |
| coreutils (uutils) | https://github.com/uutils/coreutils |
| nixpkgs | https://github.com/NixOS/nixpkgs |
| fenix (Rust overlay) | https://github.com/nix-community/fenix |
| crane (Rust builder) | https://github.com/ipetkov/crane |
| cachix (binary cache) | https://cachix.org |
| nix (package manager) | https://nixos.org/download |

---

> **End of STANDARDS.md v1.0.0**
>
> This document is a living standard. It will be updated as tools evolve,
> as we learn from project experience, and as the Rust verification
> ecosystem matures. Every project is expected to evaluate new versions
> and migrate within 6 months of release.
>
> The standard is not a cage — it is a foundation. Within its rules,
> there is enormous freedom. Build well.
