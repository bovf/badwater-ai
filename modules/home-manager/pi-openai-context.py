"""Own only reviewed contextWindow fields; never copy credentials into ownership state."""
import json
import os
import sys
import tempfile
from copy import deepcopy
from pathlib import Path

PROVIDERS = {"openai", "openai-codex"}


def read(path, default):
    if path.is_symlink() or (path.exists() and (not path.is_file() or path.stat().st_nlink != 1)):
        raise ValueError("refusing symlink, non-regular or hardlinked configuration")
    return json.loads(path.read_text()) if path.exists() else default


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)  # models.json may already contain user-owned API keys.
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        Path(name).unlink(missing_ok=True)


def positive_int(value):
    return type(value) is int and 0 < value <= 2**53 - 1


def merge(desired, target, manifest):
    for path in (target, manifest):
        if any(parent.is_symlink() for parent in path.parents):
            raise ValueError("configuration parent directories must not be symlinks")
    owner = read(manifest, {"version": 1, "previous": {}})
    if not isinstance(owner, dict) or type(owner.get("version")) is not int or owner["version"] != 1 or not isinstance(owner.get("previous"), dict):
        raise ValueError("unsupported ownership schema; original files preserved")
    if not isinstance(desired, dict) or not desired.keys() <= PROVIDERS:
        raise ValueError("unsupported managed provider declaration")
    for entry in desired.values():
        if not isinstance(entry, dict) or set(entry) != {"modelOverrides"} or not isinstance(entry["modelOverrides"], dict):
            raise ValueError("unsupported managed context declaration")
        for model, fields in entry["modelOverrides"].items():
            if not isinstance(model, str) or not model or not isinstance(fields, dict) or set(fields) != {"contextWindow"} or not positive_int(fields["contextWindow"]):
                raise ValueError("managed context windows must be positive safe integers")
    previous = deepcopy(owner["previous"])
    for provider, entries in previous.items():
        if provider not in PROVIDERS or not isinstance(entries, dict):
            raise ValueError("unsupported ownership provider schema")
        for model, saved in entries.items():
            if not isinstance(model, str) or not model or not isinstance(saved, dict) or type(saved.get("present")) is not bool or set(saved) != ({"present", "value"} if saved["present"] else {"present"}) or (saved["present"] and not positive_int(saved["value"])):
                raise ValueError("unsupported ownership context schema")
    if not desired and not previous:
        return
    current = read(target, {})
    if not isinstance(current, dict) or not isinstance(current.get("providers", {}), dict):
        raise TypeError("unsupported models schema; original files preserved")
    updated = deepcopy(current)
    providers = updated.setdefault("providers", {})
    for provider in previous.keys() | desired.keys():
        entry = providers.setdefault(provider, {})
        if not isinstance(entry, dict) or not isinstance(entry.get("modelOverrides", {}), dict):
            raise TypeError("unsupported provider overrides; original files preserved")
        overrides = entry.setdefault("modelOverrides", {})
        wanted = desired.get(provider, {}).get("modelOverrides", {})
        saved_models = previous.setdefault(provider, {})
        for model in saved_models.keys() | wanted.keys():
            fields = overrides.setdefault(model, {})
            if not isinstance(fields, dict):
                raise TypeError("unsupported model overrides; original files preserved")
            if model in wanted:
                if model not in saved_models:
                    old = fields.get("contextWindow")
                    if "contextWindow" in fields and not positive_int(old):
                        raise ValueError("invalid original context window; original files preserved")
                    saved_models[model] = {"present": True, "value": old} if "contextWindow" in fields else {"present": False}
                fields.update(wanted[model])
            else:
                saved = saved_models[model]
                if saved["present"]:
                    fields["contextWindow"] = saved["value"]
                else:
                    fields.pop("contextWindow", None)
                if not fields:
                    overrides.pop(model)
        if not overrides:
            entry.pop("modelOverrides")
        if not entry:
            providers.pop(provider)
    # Save restoration authority before replacing the target; interrupted writes can be retried.
    pending = {"version": 1, "previous": previous}
    if pending != owner:
        atomic(manifest, pending)
    if updated != current:
        atomic(target, updated)
    next_owner = {"version": 1, "previous": {p: {m: previous[p][m] for m in e["modelOverrides"]} for p, e in desired.items()}}
    if next_owner != pending:
        atomic(manifest, next_owner)


if __name__ == "__main__":
    try:
        merge(json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2]), Path(sys.argv[3]))
    except (ValueError, TypeError, OSError):
        # Parser/errors must never echo opaque configuration or credential values.
        print("badwaterPiOpenaiContext: invalid or unsafe configuration; preserve and repair explicitly", file=sys.stderr)
        raise SystemExit(1)
