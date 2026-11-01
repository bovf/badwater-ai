# GitLab: install first, authorize separately

```nix
badwater.ai.pi = {
  enable = true;
  gitlab = {
    enable = true; # default false
    host = "gitlab.example.com"; # explicit DNS host, no URL/path/credentials
    mcp.connect = false; # disabled native MCP entry, not an automatic connection
    # package = pkgs.badwater-gitlab;
  };
};
```

Enabling appends the skill package without reordering existing Pi packages and
installs its exact managed GLab command. Only the CLI package enters PATH; the
skill package is linked separately, avoiding root `package.json` collisions.
No auth/config writer, secret variable,
extra MCP extension or global Git/GLab host setting is added. Disabled policy
is lazy and does not force the package. Pi, a valid hostname and the package
are required. Heavy/Spy selection belongs to the consumer; other homes stay off.

The sole existing `badwaterPiMcp` owner writes `badwater-gitlab` at
`https://<host>/api/v4/mcp`, with `enabled = false` by default, hidden server
exposure and17 exact read-tool overrides using codemode. No wildcard enables
future tools; writes, unknown tools, artifacts, general API/GraphQL and Duo
execution are not in the preset. Availability still depends on GitLab version
and instance policy. Per-tool codemode overrides use the existing dependency
assertion even when their server is hidden. Exposure is not a project ACL.

The human enables/signs in through Pi's `/mcp`. Managed switches reapply the
configured `mcp.connect` value; use an explicitly trusted project Enable override
for project-local persistence, or explicitly set this option true after approval.
Keep personal project overrides out of commits. Pi stores MCP OAuth privately;
GLab CLI login/keyring authorization is independent and manual on each machine.
No token/header/OAuth secret belongs in Nix, Git or chat. Existing private auth
and modes survive same-endpoint merges; endpoint changes with private auth fail
for explicit reconciliation rather than forwarding credentials.

Tests cover16 module cases per supported platform, native Pi zero-request
startup for a disabled entry, exact read exposure and hidden writes/unknowns,
plus26 merger cases. These use local/inert fixtures, not real GitLab/OAuth.
