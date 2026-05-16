# Complete Rewrite Plan: dwm-win32 → STANDARDS.md Compliance

> **Status:** Approved  
> **Target:** Full compliance with STANDARDS.md v1.0.0  
> **Project Type:** GUI Application (window manager)  
> **Current State:** C codebase (Win32 API + Lua scripting)  
> **Target State:** Rust codebase (ECS architecture, data-oriented design, formal verification)  

---

## Decision Log

| Question | Decision | Rationale |
|----------|----------|-----------|
| Lua scripting (Phase 3/E) | **Drop entirely** | STANDARDS §0.1.1: minimal, single-purpose code. Config moves to ASN.1/DER + TOML frontend. |
| Multi-monitor support | **Yes, first-class** | Current code assumes single monitor (global `sx,sy,sw,sh`). Target: per-monitor ECS archetypes with full `EnumDisplayMonitors` integration. |
| Configuration format | **Dual: TOML → DER** | Human-editable TOML (`~/.config/dwm/config.toml`) validated against ASN.1 schema → compiled to canonical DER for runtime parsing. Kani-proved DER decoder. |
| Win32 batch optimizations | **Yes, include** | `BeginDeferWindowPos`/`DeferWindowPos`/`EndDeferWindowPos` for atomic screen updates. Evaluate Win11 `IDeskModWrapper` Snap integration. |

---

## Phase 0: Foundation & Infrastructure

### 0.1 Repository Structure Rewrite

Adopt STANDARDS.md Part 2 directory layout, replacing the flat C structure:

```
dwm-win32/
├── .cargo/
│   └── config.toml              # strict compiler flags, Zig linker
├── .gitoxide/
│   └── config                   # strict mode, git:// forbidden
├── .github/workflows/
│   ├── ci.yml                   # lint → test → proof → fuzz → build → docs → audit
│   ├── docs.yml                 # AsciiDoc build + Vale lint
│   └── release.yml              # release pipeline
├── proofs/                      # Kani proof harnesses (separate crate)
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── window_proofs.rs     # window management invariants
│       ├── layout_proofs.rs     # tiling algorithm correctness (all 7 layouts)
│       ├── state_machine_proofs.rs  # window lifecycle exhaustiveness
│       └── config_proofs.rs     # DER parser safety
├── cross/
│   └── targets.toml             # cross-compilation target definitions
├── xtask/                       # Rust build automation (never Makefile)
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs              # clap dispatch
│       └── tasks/
│           ├── mod.rs
│           ├── check.rs         # full pipeline
│           ├── lint.rs          # clippy + fmt + no_std
│           ├── test.rs
│           ├── proof.rs         # Kani verification
│           ├── fuzz.rs
│           ├── docs.rs          # AsciiDoc + cargo doc
│           ├── release.rs       # full check + README gen + publish prep
│           ├── audit.rs         # cargo-audit + cargo-deny
│           └── cross.rs         # cargo-zigbuild cross-compile
├── schema/
│   ├── common/
│   │   ├── primitives.asn1      # constrained primitive types
│   │   └── identifiers.asn1     # OID registrations
│   └── dwm-win32.asn1           # window manager config schema
├── src/
│   ├── lib.rs                   # crate root + module declarations
│   ├── main.rs                  # WinMain entry point
│   ├── ecs/                     # ECS world definition
│   │   ├── mod.rs
│   │   ├── components.rs        # Window, Tag, Monitor components
│   │   ├── systems.rs           # layout, focus, manage systems
│   │   └── resources.rs         # shared resources (config, display info)
│   ├── data/                    # data-oriented design core
│   │   ├── mod.rs
│   │   ├── layouts.rs           # SoA types for hot paths
│   │   ├── state_machine.rs     # data-driven state tables
│   │   └── serialization.rs     # TOML frontend + DER encode/decode
│   ├── domain/                  # domain model
│   │   ├── mod.rs
│   │   ├── types.rs             # domain types (WindowId, Tag, Layout, etc.)
│   │   └── error.rs             # STANDARDS-compliant error taxonomy
│   └── win32/                   # Win32 FFI (ONLY module with unsafe_code)
│       ├── mod.rs
│       ├── window.rs            # safe window management wrappers
│       ├── display.rs           # safe display/monitor wrappers
│       ├── hook.rs              # ShellHook + WinEventHook
│       ├── input.rs             # keyboard/mouse event wrappers
│       └── batch.rs             # BeginDeferWindowPos batch operations
├── tests/
│   ├── integration/
│   ├── conformance/
│   │   ├── valid/               # DER bytes that MUST parse
│   │   ├── invalid/             # DER bytes that MUST reject
│   │   └── vectors/             # known-good test vectors
│   └── proptest/                 # property-based tests
│       ├── config_proptests.rs
│       ├── layout_proptests.rs
│       └── state_machine_proptests.rs
├── fuzz/
│   ├── Cargo.toml
│   └── fuzz_targets/
│       ├── der_parser.rs        # fuzz DER deserialization
│       └── event_processor.rs   # fuzz event sequences
├── docs/
│   ├── antora.yml               # Antora component descriptor
│   ├── .vale.ini                # Vale prose lint configuration
│   ├── modules/ROOT/
│   │   ├── nav.adoc
│   │   └── pages/
│   │       ├── index.adoc
│   │       ├── installation.adoc
│   │       ├── configuration.adoc
│   │       ├── api.adoc
│   │       ├── architecture.adoc
│   │       └── development.adoc
│   └── vale/styles/Project/
│       ├── Terms.yml
│       ├── Headings.yml
│       └── Abbreviations.yml
├── scripts/                     # Nushell scripts only
│   ├── dev-setup.nu
│   ├── check-deps.nu
│   └── ci-helper.nu
├── Cargo.toml
├── Cargo.lock                   # ALWAYS committed
├── justfile                     # human interface to all tasks
├── .gitattributes               # strict line ending rules
├── .gitignore                   # STANDARDS template (includes README.md)
├── README.adoc                  # source of truth (never README.md)
├── CHANGELOG.adoc
├── CONTRIBUTING.adoc
├── SECURITY.adoc
├── SUPPORT.adoc
├── STANDARDS.md                 # the standard itself (already exists)
└── PLAN.md                      # THIS FILE
```

### 0.2 Configuration Files

**.cargo/config.toml** (STANDARDS §2.4):
```toml
[build]
jobs = 0

[target.x86_64-pc-windows-msvc]
rustflags = ["-Dwarnings", "-F", "unsafe_code"]

[target.x86_64-pc-windows-gnu]
linker = "zig"
rustflags = ["-Dwarnings", "-F", "unsafe_code"]

[alias]
xtask      = "run --package xtask --"
strict     = "clippy --all-targets --all-features -- -Dwarnings"
full-check = "test --all-targets --all-features"

[net]
protocol = "sparse"

[env]
CARGO_TERM_COLOR = "always"
```

**.gitattributes** (STANDARDS §2.3):
```
*               text=auto eol=lf
*.rs            text eol=lf
*.toml          text eol=lf
*.asn1          text eol=lf
*.adoc          text eol=lf
*.nu            text eol=lf
justfile        text eol=lf
*.png           binary
*.der           binary
```

**.gitignore** (STANDARDS §2.2): Generated README.md, /target/, `*.rs.bk`, fuzz corpus, IDE files.

---

## Phase 1: Core Domain Types & Win32 FFI

### 1.1 Domain Type System

All types in `src/domain/types.rs` with Kani-provable invariants:

```rust
/// Window identifier — wraps HWND as isize to avoid raw pointer in Send types.
/// [LINTED] Value is only valid when obtained from Win32 enumeration callbacks.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct WindowId(pub isize);

/// Tag identifier (0..=8, fits in tag bitmask).
/// [PROVED] Constructor rejects values > 8.
/// [PROVED] Conversion to bit position does not overflow u32.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Tag(u8);

/// Layout algorithm selector.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Layout {
    Tile,
    Monocle,
    Floating,
    BStack,
    Grid,
    GaplessGrid,
    Spiral,
    Dwindle,
}

/// Window state flags.
/// [LINTED] Bitflag operations are safe and well-defined.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WindowFlags(u8);

impl WindowFlags {
    pub const FLOATING: Self    = Self(0x01);
    pub const MINIMIZED: Self   = Self(0x02);
    pub const CLOAKED: Self     = Self(0x04);
    pub const BORDER: Self      = Self(0x08);
    pub const IGNORE: Self      = Self(0x10);

    /// [PROVED] Returns true if no flags set.
    pub fn is_empty(self) -> bool { self.0 == 0 }
}
```

**Error taxonomy** (`src/domain/error.rs`, STANDARDS §12.1):
- Every variant is a struct with named fields (no stringly-typed errors)
- Every error includes source location (file, line)
- `#[non_exhaustive]` — allows adding variants without breaking API
- Implements `std::error::Error` with `source()` chain
- `InvariantViolation` — special variant for detected bugs (includes message + file + line)

### 1.2 Win32 FFI Wrappers

**GOVERNANCE APPROVAL REQUIRED:** `unsafe_code` is set to `forbid` in `Cargo.toml`. The `win32/` module gets `#![allow(unsafe_code)]` — the ONLY such exception in the entire project. Every `unsafe` block is annotated with `// SAFETY:`.

Module structure:

| Module | Purpose | Key safe API |
|--------|---------|-------------|
| `win32::window` | Window management | `set_position`, `set_visibility`, `set_border`, `get_title`, `get_class` |
| `win32::display` | Display/monitor info | `enumerate_monitors`, `work_area`, `is_cloaked` |
| `win32::hook` | Shell/event hooks | `register_shell_hook`, `register_win_event_hook`, event callback routing |
| `win32::input` | Input handling | `register_hotkey`, `unregister_hotkey`, `translate_modifiers` |
| `win32::batch` | DeferWindowPos batching | `BatchUpdater` — RAII wrapper for Begin/EndDeferWindowPos |

Example pattern — every unsafe block wrapped in a safe function:

```rust
/// [FFI_AUDITED] SAFETY: hwnd validated by caller (must be from WindowId).
/// - GetWindowTextW: buffer size fixed at 1024 WCHAR, validated for null termination.
/// - Return value: heap-allocated Rust String from UTF-16.
pub fn get_window_title(hwnd: isize) -> Option<String> {
    let hwnd = hwnd as HWND;
    // SAFETY: hwnd is a valid window handle from our client tracking.
    // Buffer is stack-allocated (1024 WCHAR), GetWindowTextW bounded.
    unsafe {
        let mut buf: [u16; 1024] = [0; 1024];
        let len = GetWindowTextW(hwnd, buf.as_mut_ptr(), buf.len() as i32);
        if len == 0 { return None; }
        Some(String::from_utf16_lossy(&buf[..len as usize]))
    }
}
```

---

## Phase 2: Data-Oriented Core

### 2.1 ECS Architecture

STANDARDS §4 mandates ECS for all stateful applications using the `hecs` crate.

**Components** (`src/ecs/components.rs`):

| Component | Field | Invariant |
|-----------|-------|-----------|
| `WinHandle` | `isize` | Obtained from Win32 enumeration; no invalid handles after init |
| `Position` | `x, y: i32` | Within virtual screen bounds |
| `Size` | `w, h: i32` | > 0 for visible windows |
| `Tags` | `u32` | Bitmask ⊆ TAGMASK |
| `Flags` | `WindowFlags` | Valid subset of flag constants |
| `MonitorId` | `usize` | Index into `DisplayInfo.monitors` |
| `ParentId` | `Option<isize>` | Parent HWND for child windows |
| `Title` | `String` | Max 1024 UTF-16 code units |
| `ClassName` | `String` | Max 256 UTF-16 code units |
| `ProcessName` | `String` | `MAX_PATH` bounded |

**Resources** (`src/ecs/resources.rs`):

```rust
/// [PROVED] Monitors vector is non-empty (at least 1 display).
pub struct DisplayInfo {
    pub monitors: Vec<MonitorInfo>,
}

pub struct MonitorInfo {
    pub id: usize,
    pub rect: Rect<i32>,         // full display rect
    pub work_area: Rect<i32>,    // excluding taskbar
    pub is_primary: bool,
    pub name: String,            // device name
}

/// [LINTED] Configuration loaded at startup, validated by DER parser.
pub struct DwmConfig {
    pub font_name: String,
    pub font_size: u32,
    pub border_px: u32,
    pub show_bar: bool,
    pub top_bar: bool,
    pub master_factor: f32,      // 0.05..=0.95
    pub color_scheme: ColorScheme,
    pub rules: Vec<WindowRule>,
    pub key_bindings: Vec<KeyBinding>,
}
```

**Per-monitor ECS archetype** — each monitor is an entity with:
```rust
world.spawn((
    MonitorId(0),
    MonitorTagSet(1, 1),        // tagset[seltags]
    LayoutSlot(Layout::Tile),    // lt[sellt]
    DisplayRect(...),
    WorkArea(...),
));
```

Windows are assigned to a monitor via `MonitorId` component. Systems query by monitor.

### 2.2 SoA Layout for Hot Paths

STANDARDS §4.2: hot paths use SoA for cache efficiency.

The layout calculation loop iterates all visible windows per monitor — this is THE hot path:

```rust
/// [PROVED] All arrays have equal length at construction.
/// [PROVED] Indexing by position index is always in bounds.
pub struct PerMonitorLayout {
    // HOT: every layout pass
    pub positions: Vec<[i32; 2]>,
    pub sizes: Vec<[i32; 2]>,
    pub tags: Vec<u32>,
    pub flags: Vec<WindowFlags>,
    // COLD: infrequent access
    pub handles: Vec<isize>,
    pub titles: Vec<String>,
}

impl PerMonitorLayout {
    /// [PROVED] Returns Some only if idx is valid for all arrays.
    pub fn get_hot(&self, idx: usize) -> Option<WindowHotData> { ... }

    /// [PROVED] Panics if arrays have unequal lengths — catches desync bugs.
    pub fn assert_invariants(&self) {
        assert_eq!(self.positions.len(), self.sizes.len());
        assert_eq!(self.sizes.len(), self.tags.len());
        assert_eq!(self.tags.len(), self.flags.len());
    }
}
```

### 2.3 Data-Driven State Machine

STANDARDS §0.2.5: state machines as data tables, not control flow.

Window lifecycle:
```
States: Created → Managed → Visible → Hidden → Destroyed
         (transient)     ↓            ↑
                       Focused → Unfocused
```

```rust
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub enum WindowState { Created, Managed, Visible, Hidden, Focused, Destroyed }

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub enum WindowEvent {
    ShellCreated, ShellDestroyed, ShellActivated,
    TagApplied, TagRemoved, FocusChanged,
    Minimized, Restored, Cloaked, Uncloaked,
}

pub struct Transition {
    pub next: WindowState,
    pub action: Option<ActionId>,
}

/// [PROVED] Kani proves every (state, event) pair is explicitly defined.
/// [PROVED] No silent defaults — every None is intentional.
pub static WINDOW_TABLE: &[[Option<Transition>; 10]; 6] = &[
    // Created
    [Some(Transition { next: Managed,   action: Some(Action::ApplyRules) }),
     None, // ShellDestroyed
     None, // ShellActivated
     ...],
    // Managed
    ...
];
```

---

## Phase 3: Core Functionality

### 3.1 System Pipeline

Replace the monolithic 1675-line `WndProc` with cleanly separated ECS systems:

```
Win32 Message Pump (main.rs)
    │ GetMessage / DispatchMessage
    ▼
┌──────────────────────┐
│  Event Ingest System  │  ShellHook/WinEventHook → EventQueue resource
│  (runs on message)    │
└──────┬───────────────┘
       ▼ raw Win32 events
┌──────────────────────┐
│  Event Process System │  matches events → ECS commands
│  (data-driven SM)     │  (spawn, despawn, add/remove components)
└──────┬───────────────┘
       ▼
┌──────────────────────┐
│  Tag/Filter System    │  updates window visibility based on active tags
└──────┬───────────────┘
       ▼
┌──────────────────────┐
│  Layout System        │  runs per-monitor: tile/monocle/bstack/grid/etc.
│  (SoA hot path)       │  produces Vec<WindowPosition> for batch update
└──────┬───────────────┘
       ▼
┌──────────────────────┐
│  Batch Update System  │  BeginDeferWindowPos + DeferWindowPos + EndDeferWindowPos
│  (win32::batch)       │
└──────┬───────────────┘
       ▼
┌──────────────────────┐
│  Focus/Z-Order System │  manages focus history stack, active window
└──────┬───────────────┘
       ▼
┌──────────────────────┐
│  Bar UI System        │  draws tag bar, layout symbol, status text, clock
│  (per-monitor)        │
└──────────────────────┘
```

### 3.2 Layout Algorithms

Seven layout systems, each a pure `fn(world: &mut hecs::World, monitor: Entity)`:

| System | Source | Notes |
|--------|--------|-------|
| `tile_system` | `tile()` in dwm-win32.c | Master + stack vertical split |
| `monocle_system` | `monocle()` | All windows maximized |
| `bstack_system` | `bstack.c` | Bottom stack |
| `grid_system` | `grid.c` | Equal grid |
| `gaplessgrid_system` | `gaplessgrid.c` | Smart grid |
| `spiral_system` | `fibonacci(0)` | Fibonacci spiral |
| `dwindle_system` | `fibonacci(1)` | Fibonacci dwindle |

Each annotated `[PROVED]` with Kani harness:
- Asserts: all windows placed within work area
- Asserts: no overlapping for tiled layouts
- Asserts: total tiled area ≤ monitor work area
- Asserts: master window gets `mfact` portion

### 3.3 Multi-Monitor Architecture

Replace flat `sx,sy,sw,sh` globals with:

```rust
// src/win32/display.rs
/// [FFI_AUDITED] SAFETY: EnumDisplayMonitors callback validates all parameters.
pub fn query_display_info() -> Result<Vec<MonitorInfo>> {
    // EnumDisplayMonitors for per-monitor info
    // EnumDisplaySettings for per-monitor resolution/position
    // SystemParametersInfo(SPI_GETWORKAREA) for primary work area
    // MonitorFromWindow for window→monitor mapping
}

// src/ecs/systems.rs
/// Assigns windows to monitors based on their center point.
pub fn monitor_assignment_system(world: &mut hecs::World) {
    let display = world.get::<DisplayInfo>(display_entity);
    for (_, (handle, pos, size, monitor)) in world.query::<(&WinHandle, &Position, &Size, &mut MonitorId)>() {
        let cx = pos.x + size.w / 2;
        let cy = pos.y + size.h / 2;
        *monitor = MonitorId(find_monitor_for_point(&display, cx, cy));
    }
}
```

Layout and tags are per-monitor. Each monitor has its own:
- Active tag set (`tagset[seltags]`)
- Layout algorithm (`lt[sellt]`)
- Focus history
- Bar window

### 3.4 Batch Window Updates

```rust
// src/win32/batch.rs
/// [FFI_AUDITED] SAFETY: handles validated by WindowId tracking. All values bounded.
pub struct BatchUpdater {
    hdc: HDWP,
    count: u32,
}

impl BatchUpdater {
    pub fn new(initial_capacity: u32) -> Option<Self> {
        // SAFETY: BeginDeferWindowPos with positive count.
        let hdc = unsafe { BeginDeferWindowPos(initial_capacity as i32) };
        if hdc.is_null() { return None; }
        Some(Self { hdc, count: 0 })
    }

    /// [PROVED] Panics if capacity exceeded (caller must size correctly).
    pub fn defer_position(&mut self, window: WindowId, x: i32, y: i32, w: i32, h: i32) {
        // SAFETY: hwnd validated by WindowId. x,y,w,h validated by layout system.
        unsafe {
            DeferWindowPos(self.hdc, window.0 as HWND, HWND_TOP, x, y, w, h,
                SWP_NOACTIVATE | SWP_NOZORDER);
        }
        self.count += 1;
    }

    /// Commits all batched positions atomically.
    pub fn commit(self) {
        // SAFETY: All handles and positions validated before commit.
        unsafe { EndDeferWindowPos(self.hdc); }
    }
}
```

---

## Phase 4: Configuration Pipeline

### 4.1 TOML Frontend (Human Editable)

Config file at `~/.config/dwm/config.toml`:

```toml
[appearance]
font = "Fira Code"
font_size = 20
border_px = 0
theme = { norm_border = "#444444", norm_bg = "#222222", norm_fg = "#bbbbbb",
          sel_border = "#775500", sel_bg = "#775500", sel_fg = "#eeeeee" }

[layout]
master_factor = 0.55
show_bar = true
top_bar = true
default_layout = "Tile"

[rules]
floating = ["MultitaskingViewFrame", "MSCTFIME UI", "TaskManagerWindow"]
ignore_border = ["CASCADIA_HOSTING_WINDOW_CLASS"]
tag_1 = ["EXCEL"]

[keys]
mod = "Alt"
"Mod+Return" = "spawn wt.exe"
"Mod+j" = "focus_stack +1"
"Mod+k" = "focus_stack -1"
"Mod+Control+l" = "toggle_log"
```

### 4.2 DER Compiler (Runtime Format)

At startup:
1. Read `~/.config/dwm/config.toml` (if exists)
2. Parse via `toml` crate
3. Validate against ASN.1 schema constraints
4. Encode to DER via `rasn`
5. System then reads only DER at runtime

**Three-phase validation** (STANDARDS §5.6):
- Phase 1 (DER structural): length fields, tag encodings, nesting ≤ 32, size ≤ 16MB
- Phase 2 (Schema): type constraints, range checks, enum values
- Phase 3 (Semantic): cross-field constraints (e.g., TLS config only when protocol=tls)

```rust
/// [PROVED] Kani: no panic on any valid DER input.
/// [PROVED] Kani: no panic on any invalid DER input (returns ConfigError).
/// [TESTED] Round-trip: toml → der → config → der matches.
pub fn load_config() -> Result<DwmConfig, ConfigError> {
    let toml_path = get_config_path();
    let toml_str = std::fs::read_to_string(toml_path)
        .context("Failed to read config.toml")?;
    let validated = validate_toml_against_asn1(&toml_str)?;
    let der = encode_to_der(&validated)?;
    let config = parse_der_config(&der)?;
    Ok(config)
}
```

---

## Phase 5: Verification

### 5.1 Proof Pyramid Implementation

| Layer | Tool | CI Time | Scope |
|-------|------|---------|-------|
| Kani model checking | `cargo kani` | 30-60 min | All core logic: layout, state machine, config parser, window invariants |
| Property-based testing | `proptest` | 10-30 min | Round-trips, algebraic properties, config edge cases |
| Fuzzing | `cargo-fuzz` | 5 min/target | Config parser, event sequences |
| Static analysis | `clippy` + `rustc` | Every build | STANDARDS lint config |
| Type system | Rust compiler | Every build | Memory safety, thread safety |

### 5.2 Key Proof Harnesses

```rust
// proofs/src/layout_proofs.rs

/// [PROVED] No two tiled windows overlap for tile layout.
#[kani::proof]
#[kani::unwind(20)]
pub fn tile_no_overlap() {
    let count: u32 = kani::any();
    kani::assume(count > 0 && count <= 10);
    let mut state = PerMonitorLayout::new();
    for i in 0..count {
        state.add_window([0, 0], [100, 100], 1 << (i % 9), WindowFlags::empty());
    }
    tile_algorithm(&mut state, &Rect { x: 0, y: 0, w: 1920, h: 1080 }, 0.55);
    // Verify: no two windows share the same pixel
    for i in 0..state.positions.len() {
        for j in (i+1)..state.positions.len() {
            let a = Rect::new(state.positions[i], state.sizes[i]);
            let b = Rect::new(state.positions[j], state.sizes[j]);
            kani::assert(!a.overlaps(&b), "windows do not overlap");
        }
    }
}

/// [PROVED] All windows placed within screen bounds.
#[kani::proof]
pub fn all_windows_in_bounds() { ... }

/// [PROVED] State machine has no unhandled transitions.
#[kani::proof]
pub fn state_machine_exhaustive() {
    for state in 0..6 {
        for event in 0..10 {
            let s: WindowState = std::mem::transmute(state);
            let e: WindowEvent = std::mem::transmute(event);
            let result = WINDOW_TABLE[s as usize][e as usize];
            kani::assert(result.is_some(), "every transition defined");
        }
    }
}
```

### 5.3 Proof Tier Annotations

Every `pub fn` must have exactly one of these in its doc comment:

- `/// [PROVED]` — Kani harness exists and passes in CI
- `/// [TESTED]` — Proptest with ≥10,000 random cases per property
- `/// [LINTED]` — Minimum bar: clippy + rustc warnings as errors
- `/// [FFI_AUDITED]` — Unsafe code reviewed with SAFETY comments

CI enforces presence via custom xtask check.

---

## Phase 6: Documentation

### 6.1 AsciiDoc Migration

- `README.md` → `README.adoc` (source of truth, STANDARDS §9.8)
- `docs/api.md` → `docs/modules/ROOT/pages/api.adoc`
- New pages: index, installation, configuration, architecture, development
- Vale prose linting at warning level (STANDARDS §9.7)
- Build failure on any AsciiDoc warning

### 6.2 CI Pipeline

```yaml
# .github/workflows/ci.yml
jobs:
  lint:
    - cargo fmt --all --check
    - cargo clippy --all-targets --all-features -- -Dwarnings
    - cargo xtask proof-tier-check
  test:
    - cargo test --all-targets --all-features
    - PROPTEST_CASES=100000 cargo test proptest
  proof:
    - cd proofs && cargo kani --enable-unstable --default-unwind 100
  fuzz:
    - cargo xtask fuzz --duration 300
  build:
    - cargo zigbuild --target x86_64-pc-windows-msvc --release
    - cargo zigbuild --target x86_64-pc-windows-gnu --release
  docs:
    - asciidoctor --failure-level=WARN docs/modules/ROOT/pages/index.adoc
    - vale docs/
    - cargo doc --all-features --no-deps
  audit:
    - cargo audit
    - cargo deny check
```

---

## Migration Schedule

| Phase | Duration | Key Deliverables |
|-------|----------|-----------------|
| **0:** Scaffold | 2-3 days | Cargo workspace, justfile, xtask, .config files, directory layout |
| **1:** Domain + FFI | 5-7 days | Domain types, Win32 wrappers, error taxonomy, ASN.1 schema |
| **2:** ECS + SoA | 7-10 days | All components, per-monitor archetypes, SoA layout core, state machine |
| **3:** Functionality | 10-14 days | Full system pipeline, 7 layouts, batch DeferWindowPos, multi-monitor bar |
| **4:** Config | 3-5 days | TOML parser, DER compiler, three-phase validation, migration from config.h |
| **5:** Verification | 10-14 days | All Kani proofs, proptest suites, fuzz targets, CI integration |
| **6:** Documentation | 3-5 days | All AsciiDoc pages, Vale lint, README.adoc, CHANGELOG, CONTRIBUTING |

**Total estimated effort: 40-58 days (single developer)**

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Win32 FFI unsafety | Unsafe code exception needed | ONLY `win32/` module exempted; every unsafe block has SAFETY comment; all functions wrap unsafe in safe API |
| Kani cannot prove Win32 syscalls | Proof gap at FFI boundary | Prove up to the boundary; proptest + fuzz for FFI paths; `[FFI_AUDITED]` with 2-engineer review |
| Layout algorithm proof complexity | Kani timeout on symbolic N | Bound N ≤ 10 for proof; unbounded tested via proptest |
| Multi-monitor edge cases | Windows moved between monitors lose state | ECS `MonitorId` component; re-query display on `WM_DISPLAYCHANGE` |
| TOML→DER dual config confusion | User edits DER instead of TOML | Clear documentation; only TOML paths documented; DER is implementation detail |
| Performance regression from ECS overhead | Layout tick slower than linked-list C | SoA hot path ensures cache-efficient iteration; batch DeferWindowPos minimizes syscalls |
