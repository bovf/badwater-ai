"""Run with python3 tests/test_graphify_skill.py; no Nix activation or secrets."""

from pathlib import Path
import re
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / "modules/home-manager/ai.nix").read_text()
block = re.search(r'```bash\n(    PYTHON=.*?)    ```', source, re.S).group(1)
assert '${graphifyPkg}/bin/graphify-python' in block

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    scan = root / "scan with spaces"
    scan.mkdir()
    # Deliberately nonexistent: initialization must not run Python or installers.
    wrapper = "/nix/store/test-graphify/bin/graphify-python"
    script = block.replace("${graphifyPkg}/bin/graphify-python", wrapper).replace(
        "INPUT_PATH", str(scan)
    )
    for _ in range(2):
        subprocess.run(["bash", "-eu", "-c", script], cwd=root, check=True)
        assert (root / "graphify-out/.graphify_python").read_text() == wrapper + "\n"
        assert (root / "graphify-out/.graphify_root").read_text() == str(scan) + "\n"
    invalid = subprocess.run(
        ["bash", "-c", script.replace(str(scan), str(root / "missing"))],
        cwd=root,
        capture_output=True,
    )
    assert invalid.returncode != 0
    assert (root / "graphify-out/.graphify_root").read_text() == str(scan) + "\n"

print("Graphify skill sidecars preserve the Nix wrapper and scan path; rerun is safe.")
