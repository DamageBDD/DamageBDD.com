#!/usr/bin/env python3
"""Validate the article pack against a website tree without exporting Org.

Run from any directory. With --baseline, missing local Org links are resolved
against a separate reference tree, allowing checks before applying the patch.
No network access, subprocesses or writes are performed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


def check(root: Path, baseline: Path | None) -> dict:
    errors: list[str] = []
    stats = {"articles": 0, "local_links": 0, "includes": 0,
             "metadata_checks": 0, "source_links": 0, "coverage_areas": 0}
    manifest = json.loads((root / "editorial/article-manifest.json").read_text(encoding="utf-8"))
    coverage = json.loads((root / "editorial/feature-coverage-2026-10-10.json").read_text(encoding="utf-8"))
    required = {"TITLE", "DESCRIPTION", "DATE", "LAST_MODIFIED", "CONTENT_CLASS",
                "IMPLEMENTATION_STATUS", "VALIDATION_STATUS", "VALIDATION_SCOPE",
                "EVIDENCE_DATE", "EVIDENCE_URL", "LANGUAGE"}
    articles = manifest["articles"]
    slugs = {a["slug"] for a in articles}
    titles: set[str] = set()
    if len(slugs) != len(articles):
        errors.append("Duplicate article slug")
    if len(articles) != manifest["article_count"]:
        errors.append("Article count differs from manifest")

    def resolve(origin: Path, target: str) -> bool:
        target = target.split("::", 1)[0]
        path = (origin.parent / target).resolve()
        try:
            relative = path.relative_to(root)
        except ValueError:
            errors.append(f"Reference escapes website tree: {origin}: {target}")
            return False
        return path.is_file() or (baseline is not None and (baseline / relative).is_file())

    for a in articles:
        p = root / "org/articles" / (a["slug"] + ".org")
        if not p.is_file():
            errors.append(f"Missing article: {a['slug']}")
            continue
        text = p.read_text(encoding="utf-8")
        stats["articles"] += 1
        if hashlib.sha256(p.read_bytes()).hexdigest() != a["sha256"]:
            errors.append(f"Content differs from reviewed manifest: {p.name}; update the manifest after reviewing edits")
        meta: dict[str, list[str]] = {}
        for key, value in re.findall(r"^#\+([A-Z_]+):\s*(.*)$", text, re.M):
            meta.setdefault(key, []).append(value)
        for key in required:
            stats["metadata_checks"] += 1
            if not meta.get(key) or not all(v.strip() for v in meta[key]):
                errors.append(f"Missing/empty {key}: {p.name}")
        if "CAPABILITY_ID" in meta or "VERIFIED_RELEASE" in meta:
            errors.append(f"Evaluation article must not imply a new validated capability/release: {p.name}")
        if meta.get("VALIDATION_STATUS") != ["documentation_review_only"]:
            errors.append(f"Unexpected validation status: {p.name}")
        title = meta.get("TITLE", [""])[0]
        if title in titles:
            errors.append(f"Duplicate title: {title}")
        titles.add(title)
        if title != a["title"]:
            errors.append(f"Title differs from manifest: {p.name}")
        for date_key in ("DATE", "LAST_MODIFIED", "EVIDENCE_DATE"):
            if meta.get(date_key) != [manifest["review_date"]]:
                errors.append(f"Unexpected review date {date_key}: {p.name}")
        if meta.get("EVIDENCE_URL") != a["source_urls"]:
            errors.append(f"Evidence URLs differ from manifest: {p.name}")
        for source in meta.get("EVIDENCE_URL", []):
            stats["source_links"] += 1
            if not source.startswith("https://") or any(ch.isspace() for ch in source):
                errors.append(f"Malformed evidence URL: {p.name}: {source}")
        if re.search(r"\{\{|%7b%7b|sandbox:|/mnt/data/|", text, re.I):
            errors.append(f"Unexpanded/internal marker in article: {p.name}")
        if re.search(r"\bERM\b", text):
            errors.append(f"Use lowercase erm: {p.name}")
        for line in text.splitlines():
            if line.rstrip() != line:
                errors.append(f"Trailing whitespace: {p.name}")
                break
        starts = re.findall(r"^#\+BEGIN_(\w+)", text, re.M | re.I)
        ends = re.findall(r"^#\+END_(\w+)", text, re.M | re.I)
        if starts != ends:
            errors.append(f"Unbalanced Org blocks: {p.name}")
        for target in re.findall(r'\[\[file:([^\]\n]+)\]', text):
            stats["local_links"] += 1
            if not resolve(p, target):
                errors.append(f"Unresolved local link: {p.name}: {target}")
        for target in re.findall(r'^#\+INCLUDE:\s*"([^"]+)"', text, re.M):
            stats["includes"] += 1
            if not resolve(p, target):
                errors.append(f"Unresolved include: {p.name}: {target}")

    hub = (root / "org/articles/solutions_evidence_first.org").read_text(encoding="utf-8")
    for slug in slugs - {"solutions_evidence_first"}:
        if f"[[file:{slug}.org]" not in hub:
            errors.append(f"Collection missing article: {slug}")
    index = (root / "org/articles/index.org").read_text(encoding="utf-8")
    if "[[file:solutions_evidence_first.org]" not in index:
        errors.append("Article index does not link the collection; merge the index insertion after using additions-only")
    if index.count('#+INCLUDE: "index.inc"') != 1:
        errors.append("Article index must preserve one generated index.inc include")
    for item in coverage["features"]:
        stats["coverage_areas"] += 1
        if not item["boundary"] or not item["evidence"]:
            errors.append(f"Coverage item lacks evidence boundary: {item['id']}")
        for slug in item["article_slugs"]:
            if slug not in slugs:
                errors.append(f"Coverage item refers to unknown article: {item['id']}: {slug}")
    if stats["coverage_areas"] != coverage["feature_area_count"]:
        errors.append("Coverage count differs from declared count")
    return {"result": "FAIL" if errors else "PASS", "checks": stats,
            "errors": errors,
            "not_tested": ["Native Emacs/Org export and ERT", "External-link availability",
                           "Complete current repository", "Application execution and integrations",
                           "Deployment and generated discovery correctness"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--baseline", type=Path, help="Optional reference website tree for missing local links")
    args = parser.parse_args()
    try:
        result = check(args.root.resolve(), args.baseline.resolve() if args.baseline else None)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"Article validation could not complete: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2))
    return 0 if result["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
