# Screenshot MCP policy

```nix
badwater.ai.pi = {
  enable = true;
  screenshot.enable = true; # default false, Linux only
  # screenshot.package = pkgs.badwater-screenshot;
};
```

Enabling appends the explicit skill package through the existing Pi package
owner and installs only its thin `cliPackage` in PATH, avoiding manifest-root
collisions. The package must expose that passthru. Existing package order,
provider/models and unrelated MCP/auth state are preserved.

The sole `badwaterPiMcp` owner declares local stdio `badwater-screenshot` with
`args = ["mcp"]` and codemode exposure. Server initialization/tool listing is
passive; package selection is not permission to inspect targets, capture pixels,
change focus/clipboard, share images or publish docs. No independent activation,
auth owner, background desktop service or WM configuration change is added.
Unsupported platform/missing package/Pi/codemode dependencies fail closed.

The operator authorizes specific targets and data. Headless web/code is preferred
for unfocused/new web windows. GUI IDs/output/regions are explicit. KDE focus is
opt-in with normal finally restoration; Niri window capture requires a separate
clipboard-effect opt-in. Nothing reads/restores private clipboard bytes.
Original artifacts/receipts remain private; image content is returned only via
an explicit sharing call, not capture itself. These are tool/workflow guardrails,
not OS isolation or proof that arbitrary model output is correct.

[Producer modes, backend limits and tests](https://github.com/bovf/pi-nix/blob/main/docs/screenshot.md).
