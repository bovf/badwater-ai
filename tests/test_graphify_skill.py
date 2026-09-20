"""Test source sidecars, optionally built skill directories passed as arguments.

Run with python3 tests/test_graphify_skill.py [<directory-containing-SKILL.md> ...].
No Nix activation, model calls, installers, or secrets.
"""

from pathlib import Path
import re
import subprocess
import sys
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

# Optional package-boundary regression: use the actual Home Manager file tree,
# not only the Nix string, so upstream resource/layout changes are visible.
for directory in map(Path, sys.argv[1:]):
    skill = (directory / "SKILL.md").read_text()
    frontmatter = re.match(r"\A---\n(.*?)\n---\n", skill, re.S)
    assert frontmatter and "name: graphify" in frontmatter.group(1), directory
    assert skill.index("System context (added by") > frontmatter.end(), directory
    references = set(re.findall(r"references/[A-Za-z0-9_-]+\.md", skill))
    assert references, directory
    for reference in references:
        assert (directory / reference).is_file(), (directory, reference)
    init = re.search(r'```bash\n(PYTHON=.*?)```', skill, re.S).group(1)
    wrapper = re.search(r'^PYTHON="([^"]+/bin/graphify-python)"', init).group(1)
    assert Path(wrapper).is_file(), wrapper
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        scan = root / "scan with spaces"
        scan.mkdir()
        subprocess.run(
            ["bash", "-eu", "-c", init.replace("INPUT_PATH", str(scan))],
            cwd=root, check=True,
        )
        assert (root / "graphify-out/.graphify_python").read_text() == wrapper + "\n"
        assert (root / "graphify-out/.graphify_root").read_text() == str(scan) + "\n"
        subprocess.run(
            [wrapper, "-c", "import graphify; from graphify.extract import extract_nix"],
            cwd=root, check=True,
        )
    print(f"Built Graphify skill frontmatter, {len(references)} references and wrapper passed: {directory}")
