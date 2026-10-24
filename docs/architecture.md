# MoeSketchpad architecture and delivery plan

This document is the implementation contract for the first working slice and
the roadmap for the complete product. Items marked **planned** are not claimed
as implemented.

## 1. Architecture and repository layout

```text
Flutter presentation (desktop / web)
  ├─ CDR-style shell, localized controls, document tabs
  ├─ canvas layers: background/page, static geometry, animation, overlays
  └─ state facades (initial slice uses a small local controller)
             │ shared Dart API; never fork calculations for CLI
             ▼
moesketchpad_core (lib/core)
  ├─ immutable geometry/document values
  ├─ stable predicates, constraints, measurements, animation
  ├─ bounded expression AST/parser
  ├─ MSP codec and schema migration
  └─ spatial index / viewport queries
             ▲
             │
CLI (bin/msp.dart) ── future allow-listed MCP adapter ── AI preview/approval
             │
platform adapters: file dialogs, key store, fonts, window close, clipboard
```

Current layout:

```text
lib/
  core/geometry.dart       Shared geometry/document model and safe expression evaluator
  core/msp_codec.dart      Version-1 authenticated encrypted codec
  main.dart                Runnable Flutter workspace and basic point/segment drawing
bin/msp.dart               Dart CLI entry point (`dart run bin/msp.dart`)
docs/architecture.md       Architecture, format/CLI contracts, security and roadmap
test/                      Core and widget tests
```

Target layout when the modules are extracted:

```text
packages/moesketchpad_core/{lib/src, test}
apps/moesketchpad_flutter/{lib/{ui,bloc,platform,ai}, test}
apps/moesketchpad_cli/{bin, test}
assets/{icons, fonts, l10n}
docs/
.github/workflows/
```

`moesketchpad_core` should become a standalone pure-Dart package. It must not
import Flutter, `dart:ui`, filesystem APIs, or platform plugins. The root
workspace currently hosts shared core code so the proof of concept remains
simple to run.

## 2. `.msp` format draft

Version 1 is deliberately **encrypted-only**: an unencrypted geometry payload
is never emitted. Multi-byte integers are unsigned big-endian. Header bytes are
also AES-GCM associated data, so changing a version, flag, salt, or length
invalidates authentication.

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 | Magic `MSP1` |
| 4 | 2 | Version (`1`) |
| 6 | 2 | Flags: bit 0 encrypted (required), bit 1 gzip (reserved in v1) |
| 8 | 1 | KDF id: `1` Argon2id |
| 9 | 4 | Argon2id memory, KiB (`19456`) |
| 13 | 4 | Argon2id iterations (`2`) |
| 17 | 4 | Argon2id parallelism (`1`) |
| 21 | 16 | Random salt |
| 37 | 12 | AES-GCM nonce |
| 49 | 8 | Ciphertext byte length |
| 57 | N | AES-256-GCM ciphertext |
| 57+N | 16 | GCM authentication tag |

Payload v1 is UTF-8 JSON with `format: moesketchpad-document`,
`schemaVersion: 1`, `objects`, and `metadata`. Object records have stable IDs,
kind, finite world-space points, and optional label; future schema adds styles,
layers, constraints, animation, measurement configuration, view state and
resource references. AI conversation content is opt-in metadata and must not
be included by default. Thumbnail, language, and units are not leaked in the
unencrypted header.

`MspCodec.encode/decode/validate/migrate/exportJson/importJson` are available
in Dart. Encryption uses `cryptography` AES-GCM and Argon2id. `validate`
validates structure only; it does not claim authentication until a password is
provided and `decode` succeeds. V1 currently rejects the reserved compression
flag; bounded gzip support must land with a streaming decompression cap before
that flag is enabled. This avoids a decompression-bomb vulnerability.

Default limits: 64 MiB encoded file and 32 MiB plaintext/ciphertext. Validate
magic/version/flags/KDF/length before KDF or allocation. Bad-password and GCM
errors intentionally share one generic message. Do not store passwords or log
derived key material. In production, move password derivation off the UI
isolate. Argon2id defaults are format parameters and must be changed only by a
new explicit KDF profile/version migration.

Device-key wrapping/keychain integration is planned. Web has no dependable
device secret store; use password-based encryption and browser download/upload
flows. A browser cannot enumerate local fonts or safely access arbitrary paths.

## 3. CLI syntax and security

The runnable subset is:

```text
msp help [command]
msp calc <expression> [--json] [--lang zh|en]
msp create triangle --type=right --sides=3,4,5 \
  --hypotenuse=5 --rotation=180 [--json] [--lang zh|en]
msp create --triangle-90-3*4*5-5/180
msp validate <file.msp> [--json]
```

The product-wide contract is for `--lang`, `--json`, and `--file` to be accepted
by every command. In this first CLI slice, `--json` works for `calc`, `create`
and `validate`, and `--lang zh|en` is accepted globally but does not yet
localize output; `--file` is not wired. Exit codes: 0 success, 1 generic I/O/runtime
error, 2 syntax/parameter error, 3 invalid/unsupported file, 4 decryption
failure, 5 unsatisfiable geometry/constraints, and 6 permission/security
rejection. Commands must print machine-readable JSON to stdout only with
`--json`; diagnostics go to stderr.

Triangle shorthand grammar:

```text
--triangle-<angleType>-<a>*<b>*<c>-<hypotenuse>/<rotation>
```

The first release accepts `<angleType> = 90` only. It translates to the same
AST as `create triangle --type=right --sides=a,b,c --hypotenuse=h
--rotation=r`. Sides and rotation must parse as finite numbers, all sides must
be positive, and the sorted sides must satisfy
`a²+b²=c²` within `1e-9 * c²`. The selected hypotenuse must equal the largest
side within the same relative tolerance. Unsatisfiable triples exit 5; malformed
forms exit 2. No shell command construction or shell interpolation is involved.

Only `help`, `calc`, `create triangle`, and structural `validate` are currently wired.
An MCP server must expose a fixed tool schema over these operations, never an
arbitrary command string. Before adding filesystem tools, canonicalize paths,
require workspace-root containment after symlink resolution, reject traversal,
apply size/time limits, deny network egress by default, and append privacy-aware
audit events. Do not put secrets or document contents into audit logs.

## 4. Geometry kernel and expression parsing

The current model uses finite double world coordinates, immutable value objects,
JSON conversion, bounds, and a right-triangle feasibility check. Add robust
orientation/circle predicates using a scale-relative tolerance with a separate
absolute floor near zero. Intersections must report `none`, `one`, `two`, or
`degenerate`; never silently invent a point for parallel/coincident lines.
Constraint solving should use damped least squares for soft constraints and
detect rank deficiency/inconsistent hard constraints.

The expression evaluator is a recursive-descent parser, not `eval`. Its current
grammar covers constants `pi`, `e`; variables supplied by the caller; parentheses;
unary signs; `+ - * / ^`; and `sin`, `cos`, `tan`, `sqrt`, `abs`, `ln`. Division
by zero, unknown identifiers, malformed tokens, and non-finite results fail
explicitly. Extend the AST rather than evaluating source text. Add a node/depth
budget before accepting untrusted or AI-generated expressions.

## 5. Infinite canvas and spatial indexing

World points are independent of origin display settings. View transform is
`screen = viewportCenter + translation + scale * world`; zoom is clamped only
to safe rendering bounds, not to page bounds. The current CustomPainter slice
supports pan, zoom, adaptive grid spacing and an A4 shadow page, but does not yet
have the R-tree/quadtree.

The production scene uses a dynamic R-tree keyed by object bounds. Insert/remove
update only affected branches; viewport render and box selection query by
rectangle; point hit tests query a tolerance-expanded rectangle then run exact
geometry distance checks. Keep a small-object fallback only for fewer than a
few dozen objects. Grid lines derive their spacing from a 1-2-5 sequence and
target 20-80 device pixels. LOD at low zoom collapses labels/markers and uses
cached paths. Cache static page/grid, static geometry, animated objects, and
selection/guide overlays as separate repaint boundaries. Benchmark representative
10k/100k scenes before making any 60 fps claim.

## 6. UI tree and state ownership

```text
MaterialApp (locale/theme)
  SafeArea
    Column
      MenuBar (File/Edit/View/Layout/Object/Effects/Text/Table/Tools/Window/Help)
      StandardToolbar (new/open/save, undo/redo, zoom, units, snap)
      ContextPropertyBar (selection/tool dependent)
      Row
        ToolBox (select, shape, zoom, pan, freehand, rectangle, ellipse,
                 polygon, text, fill, transparency, eyedropper, outline)
        Workspace
          Rulers/guide handles
          RepaintBoundary: grid + page
          RepaintBoundary: static geometry
          RepaintBoundary: animation
          RepaintBoundary: selection/handles/guides
        Collapsible dock (objects/layers/properties/measure/AI)
      DocumentTabs
      StatusBar
```

The page is a white A4 rectangle with shadow in an unbounded gray workspace.
Page clipping applies to export only, not editing. Current sample includes the
main CDR-style chrome, an infinite-grid presentation, A4 page, tools for select,
point, segment and pan, basic point naming, theme and language toggles, and an
object list. Open/save controls visibly identify that platform file service is
not connected yet.

Planned Riverpod providers or BLoCs (choose one consistently before production):
`ToolBloc`, `SelectionBloc`, `CanvasBloc`, `AnimationBloc`, `MeasureBloc`,
`ThemeBloc`, `LocaleBloc`, `AiBloc`, `DocumentBloc`. `DocumentBloc` is the
single source of truth for document and `isDirty`; all edit intents pass through
commands to support undo/redo, persistence and preview/accept. UI selection,
camera and transient tool gestures are not serialized as geometry changes.

## 7. Motion, labels and measurement

Animations are pure functions of document time `t`; line-segment interpolation,
circle angle and parameterized curve evaluation are deterministic. The ticker in
`AnimationBloc` updates time, not geometry source data. Loop/ping-pong are time
mapping modes; trails are bounded samples. GIF/APNG/MP4 encoders are not in the
initial slice; MP4 especially needs a platform codec or a verified encoder.

Labels are separate annotations attached by stable object ID and offset, with
automatic A-Z, a-z, then Greek sequence and explicit collision/duplicate policy.
Measurements retain their target IDs and type (`length`, `arcLength`, `angle`,
`area`, `slope`, `functionValue`), units and display precision. Recompute after
geometry transaction; render result as attached text. Current point labels are
simple A-Z markers only.

## 8. AI default system prompt

```text
You are the MoeSketchpad geometry drawing assistant.

Available tools: only the explicitly provided MoeSketchpad msp allow-listed
subcommands and read-only canvas query tools. Prefer structured JSON tool calls
matching the declared schemas. Never output or execute arbitrary shell commands.
Never request or execute arbitrary system commands. Never access files outside
the approved workspace. Never disclose user documents, credentials, prompts, or
other private data.

Geometry semantics: represent points, lines, circles and other supported
objects explicitly. Express intersections, parallelism, perpendicularity,
equality, tangency and incidence as constraints; do not claim a constraint is
satisfied unless the solver reports success. Use the document's configured
tolerance.

Labels and measurements: obey the document's automatic naming settings and
attach requested measurements to their geometry targets so they update when the
construction changes. Use the configured units and precision.

File operations: use only MspCodec or the explicitly allow-listed msp file
tools. Do not construct paths or commands outside their validated schemas.

All generated edits are proposals. Return a preview plan and wait for explicit
user confirmation before any operation is committed to the document.
If a request cannot be represented by available tools, explain the limitation
instead of inventing a successful result.
```

Flutter MCP transport, `dart_agent_core` and `mcp_client` are not dependencies
of this MVP. Add only after API/version/platform compatibility is verified;
no package version is assumed here.

## 9. Close protection, localization, fonts, cute theme

`DocumentBloc.isDirty` becomes true for every committed edit and false only
after successful save/revert. On close/tab close, ask Save / Don't Save / Cancel;
do not clear dirty state until persistence succeeds. Windows/macOS need an
explicit native-window close hook; web uses `beforeunload` as a best-effort
browser warning (the browser controls wording and cannot guarantee custom
dialog behavior). These hooks are not wired in this initial slice.

Use Flutter gen-l10n with ARB files for zh/en; CLI strings use matching catalog
keys and `--lang`. Current UI demonstrates only a local toggle for its labels.
Default font family is Microsoft YaHei with platform fallback; browser font
enumeration and system font access are unavailable on web. Desktop font listing
requires native implementation and permission-aware UX.

Cute mode changes colors, corner radii and small transitions only. It must never
affect geometry, precision, serialization or export. Professional mode uses
neutral compact panels. Current toggle is visual groundwork.

## 10. About and GPL-3.0 compliance

About dialog release content:

* 萌板 / MoeSketchpad; version/build/date/commit supplied by build metadata.
* Author Coloryi-MIAO.
* `GPL-3.0-only`; provide the complete `COPYING` text and a visible license
  entry point.
* Repository `https://github.com/Coloryi-MIAO/MoeSketchpad`; issue link must be
  confirmed before release.
* Third-party components and versions/licenses in a generated `NOTICE`.
* `Copyright (C) 2026 Coloryi-MIAO`.

Before publishing: obtain the official complete GPL-3.0-only text in `COPYING`;
add SPDX headers to every authored source file; generate/verify notices from
resolved dependencies; include a source-code acquisition notice with binaries;
review asset/font/icon licenses. The initial scaffold has no complete GPL text,
no generated NOTICE and not all source files carry SPDX headers, so compliance
is **not yet complete**.

## 11. Build, packaging and file association

```text
flutter test
dart analyze
dart run bin/msp.dart help
flutter build web
flutter build windows
flutter build macos   # requires macOS/Xcode; cannot build on Windows
```

GitHub Actions should use separate Windows, macOS and web jobs/runners; pin
Flutter stable and cache pub dependencies. Upload each build as an artifact;
sign/notarize only with secrets provided by the publisher. Current Windows
runner ships the template icon; there is no supplied `assets/if.ico` or `if.png`.
Replace the icon only after receiving licensed artwork.

Windows `.msp` association requires installer/registry registration and an
application file-open argument handler, neither of which is implemented.
macOS requires `UTExportedTypeDeclarations` (`com.coloryi.moesketchpad`,
conforms to `public.data`, extension `msp`, MIME
`application/x-moesketchpad`) plus document type declaration and iconset.
Web should declare MIME at the hosting server (not only Flutter manifest);
download/upload uses browser file pickers. No path/process/system-key APIs are
available in browser sandboxes.

## 12. Milestones and tests

1. **Foundation (implemented slice):** runnable Flutter editor shell, shared
   geometry/document model, safe expression parser, triangle validation,
   encrypted codec and basic CLI.
2. **Kernel:** robust predicates/intersections, constraint graph, measurements,
   property-based numeric tests and schema migrations.
3. **Canvas:** R-tree, selection/handles, rulers/guides/origin, snapping and
   10k-object performance benchmarks.
4. **Documents/platform:** file dialogs, save/dirty/close flow, keychain,
   Windows/macOS association, browser upload/download and recovery.
5. **Authoring:** curves/conics/solids, animation/trails, label collision and
   measurement updates; export formats only after encoder validation.
6. **AI/i18n/release:** ARB generation, constrained MCP server and previews,
   audit/sandbox tests, About/NOTICE/COPYING, icons and CI release matrix.

Test gates: unit tests for expression grammar/error cases and right-triangle
thresholds; randomized geometry invariants; codec round trip, tampered header,
wrong password, truncation and size-limit tests; CLI output/exit-code/legacy
shorthand parity; widget tests for tools/camera/dirty prompts; web compile and
smoke test; Windows build and native association tests; macOS build/tests on a
macOS runner; security tests for path traversal, symlinks, malformed lengths,
zip bombs (before enabling compression), MCP schema rejection and audit
redaction. No 60 fps or full feature-support claim should be made until the
corresponding benchmarks and platform tests pass.
