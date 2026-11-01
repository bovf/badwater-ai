# Swarm Home Manager policy and HTTP MCP

This module owns integration policy, not the swarm runtime/package. It does not
activate a home, start a swarm/browser, authenticate Context7, or authorize model,
network, target inspection or deployment operations.

```nix
badwater.ai.pi = {
  enable = true;
  swarm = {
    enable = true; # default false
    # package = pkgs.badwater-swarm;
    maxConcurrent = 6; # 1..6
    maxAgents = 32; # logical admissions, 1..64
    maxRepairCycles = 2; # 0..2
    roleModels = {}; # absent roles inherit the parent's provider/model
    # roleModels."swarm.qa" = "<explicit provider/model>";
    browser.enable = pkgs.stdenv.hostPlatform.isLinux; # default
    # browser.package = pkgs.badwater-swarm-browser;
    context7.enable = true; # defaults to swarm.enable
  };
};
```

The producer `pi-nix` supplies `pkgs.badwater-swarm`,
`pkgs.piPackages.badwater-swarm = { name = "badwater-swarm"; package = pkgs.badwater-swarm; }`,
and `packages.<system>.badwater-swarm`. The package root supplies `package.json`,
`extension.mjs`, `lib.mjs`, `cli.mjs`, `workflows/`, `agents/` and
`skills/swarm/SKILL.md`; the manifest registers the extension, skill and
`pi-subagents.agents`. Actual Pi and pi-subagents come from host outputs, not
private npm copies, global bootstrap, or runtime installers. No additional
passthru metadata is required by this module.

Enabling selects `badwater-swarm` and the producer's existing
`pkgs.piPackages.pi-subagents` through `badwater.ai.pi.packages`. Existing equal
name/output selections deduplicate. Different outputs for the same name fail
closed; reconcile the selection explicitly. If the producer does not expose
pi-subagents, an explicit `packages` selection with that name is required. The
normal stable links `~/.pi/agent/nix-packages/<name>` are used. Disabled homes do
not force the swarm, subagents or browser packages. No global subagent settings,
user agent files or default provider/model are taken over.

Linux browser integration requires the Nix browser package supplying
`bin/swarm-browser`, installed in `home.packages`. Other platforms default to
browser disabled and reject an explicit browser enable. Runtime settings get an
absolute store browser command when enabled, otherwise `null`. This is not
permission to launch Chromium, contact a site, or access a real browser profile.

## Settings precedence

Generated settings include `badwaterSwarm = { maxConcurrent = 6; maxAgents = 32;
maxRepairCycles = 2; roleModels = {}; browserCommand = <absolute path or null>; }`.
The typed `swarm.*` options supply these defaults. Explicit
`extraSettings.badwaterSwarm` is recursively merged **over** them, including
per-role model selections, opaque unrelated keys, and an explicit
`browserCommand` (including null). Other existing `extraSettings`, model/provider,
compaction/context and package selections keep their existing precedence.

Use the typed options for checked bounds. The escape hatch does not silently
reset explicit settings: the runtime must validate effective bounds/paths and
fail closed for invalid overrides. Settings are the existing writable copies
re-applied on Home Manager switch; runtime changes can be overwritten. No new
settings or activation writer is added by swarm.

## Context7 and managed HTTP schema

`swarm.context7.enable` declares exactly:

```nix
badwater.ai.pi.mcpServers.context7 = {
  url = "https://mcp.context7.com/mcp";
  exposure = "codemode";
};
```

It can be disabled independently or enabled without the swarm package, but
requires Pi enabled. Codemode follows the existing additive default; an explicit
`defaultTools` excluding codemode fails the existing dependency assertion rather
than being overwritten. Disable Context7 or select another explicit exposure
with a higher-priority declaration if codemode is intentionally unavailable.
OAuth remains native Pi runtime behavior (`/mcp`), never a module login or stored
secret. Connecting to Context7 is a separate network/auth approval. No live
Context7/OAuth request belongs in policy tests.

Additional `pi.mcpServers` accept one mutually exclusive transport:

- **stdio**: absolute `command`, optional string-list `args`, optional
  `type = "stdio"`. The existing stdio `env` API is unchanged; never put literal
  credentials in Nix-store declarations.
- **streamable HTTP**: `url`, optional `type = "http"` or
  `type = "streamable-http"`. The aliases and omitted type share one HTTP
  identity. `command`, `args`, `env`, `cwd` are forbidden, including null values.
  Managed `headers`, `auth` and `oauth` are forbidden: place private auth only in
  the regular writable runtime JSON, not the public/immutable Nix store.

The managed URL subset is conservative: lowercase `https://` with a DNS-style
ASCII host (or `[::1]`), optional numeric port 1..65535 without leading zeros,
and optional path. Plain HTTP is accepted **only** on exact `localhost`,
`127.0.0.1`, `[::1]` for private loopback fixtures. No URL userinfo, query,
fragment, whitespace, backslash or `@` is accepted. Legacy SSE is not supported;
there is no silent protocol fallback. This restriction applies only to managed
declarations; unrelated opaque user-owned general Pi HTTP entries are preserved,
not revalidated or narrowed. Both Nix assertions and the Python merger validate
the same managed schema. Exposure remains codemode/deferred/direct/hidden.

The existing `badwaterPiMcp` is the **only** Pi MCP activation owner, after
`writeBoundary`, via Home Manager's dry-run-aware `run`. Graphify, web search,
REA, context policy and unrelated opaque servers/settings remain intact. Names
must be unique after Pi's hyphen/underscore normalization. An existing unmanaged
name is adopted only when its transport identity matches: exact stdio
command/args, or exact HTTP URL, ignoring type aliases and exposure. Distinct
URLs (including paths/trailing slashes/ports) are deliberately not equated.
Conflicts fail before writes and diagnostics never print configuration values.

Once a name is owned, deliberate stdio-to-HTTP migration removes stale
command/args/env/cwd/type; HTTP-to-stdio removes url/headers/type (omitted args
restore the empty-args identity). Unrelated metadata and private auth/oauth
metadata are retained unless explicitly removed in writable configuration.
Same-HTTP user headers remain opaque. Inspect/remove stale private auth when
intentionally changing endpoints: retained auth is not authorization to send it
to a different service. Disable removes only owned registrations, not auth.json,
models/settings, user projects/caches or unrelated registrations. The existing
ownership manifest format remains version 1/names only, with crash recovery.
Regular private modes stay private; new MCP/store-symlink migration retains 0644
and new ownership manifests use 0600. Non-store symlinks, hardlinks, invalid JSON
and schemas fail closed.

## Offline checks

No flake input/lock update is needed. The module matrix uses fake package
fixtures and caller-owned pinned nixpkgs/Home Manager paths; it never builds a
home generation. With `$NIXPKGS` and `$HOME_MANAGER` pointing at pinned source
paths (not live settings), from this repo:

```bash
export NIX_CONFIG="${NIX_CONFIG-}"$'\nmax-jobs = 1\ncores = 3'
python3 tests/test_pi_mcp_merge.py
python3 tests/test_pi_openai_context.py
# Repeat evaluation for x86_64-linux, aarch64-linux and aarch64-darwin:
nix eval --impure --json --expr "(import ./tests/swarm-module-matrix.nix {
  inputs = { nixpkgs = builtins.toPath \"$NIXPKGS\";
             home-manager = builtins.toPath \"$HOME_MANAGER\"; };
  system = \"x86_64-linux\";
}).matrix" > /tmp/swarm-native.json
# Realize native generated JSON/helper inputs only:
nix build --impure --no-link --expr "(import ./tests/swarm-module-matrix.nix {
  inputs = { nixpkgs = builtins.toPath \"$NIXPKGS\";
             home-manager = builtins.toPath \"$HOME_MANAGER\"; };
}).sources"
python3 tests/test_swarm_policy.py --resources /tmp/swarm-native.json \
  /tmp/swarm-arm-linux.json /tmp/swarm-darwin.json
```

Both inputs may be source paths (or cached flake inputs). The matrix deliberately
does not add a Home Manager input to this flake.

Execute `tests/swarm_activation_gate.py <native-matrix.json> <store-bash-output>`
only inside a fresh private filesystem **and** network namespace, with cleared
environment, `HOME=/tmp/policy-home`, read-only `/nix/store`, tests and matrix
exposed, and no host sockets/home. It exercises actual generated MCP snippets
with HM's real `run`, including dry-run, enable/disable/Pi-off, conflicts,
private modes, opaque auth preservation and store-symlink migration. It does not
execute the unrelated full activation/settings snippets.

Likewise run core Node 22 on
`tests/test_pi_mcp_http.mjs <pi-output>` inside that isolated namespace with
`PI_OFFLINE=1`, a fresh `/tmp/policy-home` and cwd there. It loads the actual
builtin factories and an inert model runtime with model network disabled;
private loopback initialize/list/synthetic echo cover omitted/http/streamable-http
forms and sole `/mcp` ownership. It never contacts Context7 or provider endpoints,
reads real credentials, launches a browser or makes a model call. Infrastructure
failure blocks the check, rather than switching protocol/execution mode.

These checks do not establish the real swarm/browser package contract,
approval workflow, live model behavior, consumer evaluations or remote OAuth.
Those remain producer/runtime/consumer gates, not evidence inferred from fake
packages or the loopback fixture.
