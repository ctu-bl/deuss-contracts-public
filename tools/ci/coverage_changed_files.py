import argparse
import re
import subprocess
import sys
from pathlib import Path


COMMENT_RE = re.compile(r"//.*?$|/\*.*?\*/", re.MULTILINE | re.DOTALL)
STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
TOP_LEVEL_TYPE_RE = re.compile(r"\b(contract|interface|library)\s+[A-Za-z_][A-Za-z0-9_]*")
EXECUTABLE_MEMBER_RE = re.compile(
    r"\b(function|constructor|fallback|receive|modifier)\b[^;{]*\{",
    re.MULTILINE | re.DOTALL,
)


def parse_lcov(path):
    coverage = {}
    current = None
    lf = lh = 0
    with open(path) as fh:
        for raw in fh:
            line = raw.strip()
            if line.startswith("SF:"):
                current = line[3:]
                lf = lh = 0
            elif line.startswith("LF:"):
                lf = int(line[3:])
            elif line.startswith("LH:"):
                lh = int(line[3:])
            elif line == "end_of_record" and current is not None:
                coverage[current] = (lf, lh)
                current = None
                lf = lh = 0
    return coverage


def changed_sol_files(base):
    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=AM", f"{base}...HEAD", "--", "src/"],
        check=True, capture_output=True, text=True,
    )
    return [p for p in result.stdout.splitlines() if p.endswith(".sol")]


def lookup(cov, rel):
    if rel in cov:
        return cov[rel]
    return cov.get(str(Path(rel).resolve()))


def is_declaration_only_source(path):
    text = Path(path).read_text()
    source = COMMENT_RE.sub("", text)
    source = STRING_RE.sub("", source)
    declarations = TOP_LEVEL_TYPE_RE.findall(source)
    if declarations and all(kind == "interface" for kind in declarations):
        return True
    return not EXECUTABLE_MEMBER_RE.search(source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lcov", default="lcov.info")
    parser.add_argument("--base", required=True, help="Git ref to diff against (A...HEAD)")
    parser.add_argument("--threshold", type=float, default=90.0)
    args = parser.parse_args()

    files = changed_sol_files(args.base)
    if not files:
        print(f"No changed Solidity files in src/ vs {args.base}; gate passes.")
        return 0

    cov = parse_lcov(args.lcov)
    failures = []
    print(f"Changed Solidity source files ({len(files)}), threshold {args.threshold}%:")
    for rel in files:
        entry = lookup(cov, rel)
        if entry is None:
            if is_declaration_only_source(rel):
                print(f"  {rel}: declaration-only source; no executable coverage data OK")
                continue
            print(f"  {rel}: no coverage data (treated as 0%) FAIL")
            failures.append((rel, 0.0))
            continue
        lf, lh = entry
        pct = (lh / lf * 100.0) if lf else 100.0
        status = "OK" if pct >= args.threshold else "FAIL"
        print(f"  {rel}: {pct:.2f}% ({lh}/{lf}) {status}")
        if pct < args.threshold:
            failures.append((rel, pct))

    if failures:
        print(f"\n{len(failures)} file(s) below {args.threshold}% line coverage:")
        for rel, pct in failures:
            print(f"  - {rel}: {pct:.2f}%")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
