# Craft selections and Pi video workflow

This policy owner imports both modules through `homeManagerModules.default`/`ai`.
Native packages remain **artcraft-nix** outputs. Shared CLI/MCP/model/skill packaging
remains **pi-nix**. No global overlay, compiler/font follows, app repackaging or
thirteen new flakes are added. Inject exact producer outputs:

```nix
badwater.ai.artcraft.packages = builtins.removeAttrs
  inputs.artcraft-nix.packages.${pkgs.stdenv.hostPlatform.system} [ "default" ];
```

No ArtCraft input exists in this policy flake; injection avoids an invented follows
and consumer/producer package identity drift. Consumers must keep producer pins and
non-free opt-in intact. New ArtCraft selections are default-off, including ArtCraft's
non-free/source-available frontend. Packaging licenses do not grant cache publication
or redistribution permission.

## General module (`badwater.ai.artcraft`)

`enable` selects installation independently of Pi. Applications:
`artcraft`, `cadcraft`, `deckcraft`, `designcraft`, `effectcraft`, `filmcraft`,
`gridcraft`, `lightcraft`, `pdfcraft`, `photocraft`, `soundcraft`, `vectorcraft`,
`wordcraft`. Each `applications.<name>.enable` defaults false. `applications.all`
is convenience defaults only; explicit false wins:

```nix
badwater.ai.artcraft = {
  enable = true;
  applications.all = true;
  applications.artcraft.enable = false;
};
```

`mcp.enable` is optional, independent of installation. It defaults to verified
selected companions; `mcp.applications` narrows that set. ArtCraft has no verified
companion MCP and explicit registration fails. Twelve native interfaces have
initialize/list/meaningful-operation proof; no GUI bridge/credentials are needed
for those operations. See artcraft-nix's capability matrix for scoped format claims.
The launcher uses private per-application HOME/XDG/output state and no network/live
GUI/config/auth. Raw roots are read-only; native writes belong to per-app derived
state. Startup/list does not invoke analysis/models/edit/export. Native informational
banners and the one exact healthy LightCraft load report are retained in
`startup.log`; other diagnostics are not suppressed.

## Workflow (`badwater.ai.pi.videoEditing`)

```nix
badwater.ai.pi.enable = true;
badwater.ai.pi.videoEditing.enable = true;
```

Minimal dependencies: FilmCraft, SoundCraft, CPU Whisper tiny.en + MIT model card,
FFmpeg/FFprobe, SQLite/Python MCP/NumPy, the configured CLI and packaged Pi skill.
No unrelated/non-free application is an implicit dependency. Explicit exclusions
of required Film/Sound cause clear assertions rather than silently overriding false.
The workflow requires Pi and a supported Linux package path; disabled paths must
remain safe on other platforms. Defaults:

| Option | Default |
|---|---|
| `readRoots` | `~/Videos/Raw` (explicit absolute home path at evaluation) |
| `writeRoot` | `~/Videos/BadwaterAI/Projects` |
| `concurrency` | 1 (1..4) |
| `timeoutSeconds` | 1200 (30..7200) |
| `maxAutomaticRepairAttempts` | 2 (0..3) |
| `mcp.enable` | true |
| `mcp.exposure` | `codemode` |

When enabled, Home Manager activation creates the configured `readRoots` and
`writeRoot`. New leaf directories are private (0700); existing directories, modes
and contents are preserved. Dry-run/disabled workflows create nothing. Each new
project is saved under `writeRoot/<project-name>/` with its local index, jobs,
frames, native revisions and exports. The CLI and builtin MCP share that setting.
Changing `writeRoot` does not move or delete existing projects/caches. Projects
from the earlier XDG default remain there; start a new test project after activation
or explicitly select the old root to reopen one. Never move an `.fcproj` alone:
it can reference derived audio by absolute path.

The CLI is also usable with MCP disabled. Pi's builtin exposure schema is used;
exposure does **not** defer server startup. Default settings add `+codemode` when
needed, but explicit `defaultTools` must already permit it or evaluation fails.
Additional MCP names are unique after builtin '-'/'_' normalization. Identical
Pi package name/output pairs deduplicate; conflicting same-name outputs fail.
The builtin Graphify/web-search identities cannot be replaced by additions.

The video wrapper also routes selected verified apps through `native_catalog`/`native_batch`, without enabling extra direct servers or GUI bridges. ArtCraft remains install-only. Native film plans can add effects/graphics/captions/transitions; Pi's packaged active-model tool and budgeted full-recording visual sweep support context-based planning. The default sweep is every15 seconds with240 total frame attachments per asset; sharing and budget increases require user permission. Other consumers still default to FilmCraft/SoundCraft only; Heavy's explicit all-app selection is consumer-owned.

For commands, plans, models/cache budgets, supported/unsupported editorial scope,
consent, security/QC, native acceptance and exact opt-in model validation, see
`pi-nix/docs/video-editing.md` in the sibling producer. Core MCP/discovery owns
`/mcp`, `codemode`, `tool_search`; the video package declares skills only.

## One additive MCP owner and disable behavior

`badwater.ai.pi.mcpServers` is the minimal mergeable additional-server interface.
Only existing `home.activation.badwaterPiMcp` writes MCP JSON, through
`pi-mcp-merge.py`; never run manual `pi mcp add` or introduce another activation.
It runs for Pi-on and cleanup transitions including Pi-off. Managed ownership is
recorded separately in `~/.pi/agent/badwater-mcp-owned.json`.

Unrelated servers/top-level fields and managed optional metadata remain unchanged.
Only explicitly owned disabled entries are removed. An unmanaged same-name
collision is refused, not overwritten. Exact known legacy Graphify/web-search
command/argument pairs may be adopted; altered user entries remain user-owned.
Nix-store file symlinks may migrate to writable regular0644 JSON; other symlinks,
hardlinks, malformed/non-object schemas fail without following credential files.
Crash ordering records the old/new ownership union before replacing MCP JSON,
then prunes ownership, retaining recovery authority after a mid-write interruption.

Disable only removes owned declarations/package links; it never deletes raw media,
projects, caches, auth, settings resources or applications selected elsewhere.
Synthetic merger tests cover unrelated opaque fields, ownership update/removal,
unmanaged conflict, exact legacy adoption, corrupt JSON/links and inert sibling-auth
preservation. `checks.<system>.pi-mcp-merge` makes these mandatory; native activation
and platform/merge evaluation matrices are additional acceptance, not substitutes.
No live auth is inspected and no activation is authorized by these tests.

## Reproducible policy acceptance

`tests/craft-module-matrix.nix` accepts an `inputs` set (nixpkgs, home-manager,
sops-nix, pi-nix, graphify-nix, artcraft-nix), `system` and optional case. Evaluate
with the selected consumer dependencies and unpublished producer overrides. It
contains13 exact-output individual cases,17 positive combinations and9 assertion
negatives, including omitted/default exposure, package identity conflicts and
normalized/server-builtin collisions. ARM/Darwin are evaluation-only; disabled/
individual paths are safe, Darwin native video/MCP fails with a Linux assertion.

`tests/activation_mcp_gate.py` executes only the generated sole-owner MCP snippets
from the matrix inside a private namespace: Graphify/web-search/video/only-new/
Pi-off transitions, generated video directory creation (dry-run, idempotence,
custom quoted paths, existing mode/data preservation and MCP-off), unrelated opaque
JSON, regular0644 permissions, actual Nix
store-symlink migration, untouched synthetic auth/settings/keybindings/user data.
It expects `/harness/module-contexts.json`, `/harness/paths.json`; bind them and
store read-only with a fresh `/fixture` and cleared synthetic HOME. No full
activation or live secret inspection is performed. Pure merger tests also force
a mid-replacement interruption and verify recovery authority; directory fsync
makes the ownership/replacement ordering durable. Run the mandatory Nix check.
