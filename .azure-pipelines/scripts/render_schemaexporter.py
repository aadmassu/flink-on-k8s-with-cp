#!/usr/bin/env python3
"""Render a CFK SchemaExporter CR from an env's cluster-linking folder.

  schemaexporter.yaml   CR template (spec.subjects stub)
  subjects.txt          one subject / pattern per line ("*" = default context)

  --check   static validation only
  --out F   write the rendered CR
  --list    print subjects one per line

Python 3.6+, PyYAML only.
"""
import argparse
import pathlib
import re
import sys

import yaml

PLACEHOLDER = "REPLACE_WITH_"


def read_lines(path):
    if not path.exists():
        return []
    out = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            out.append(line)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--env-dir", required=True)
    ap.add_argument("--out")
    ap.add_argument("--source-sr-url", default="", help="replaces __SOURCE_SR_URL__")
    ap.add_argument("--token-endpoint", default="", help="replaces __SOURCE_OAUTH_TOKEN_ENDPOINT__ on both sides")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    env_dir = pathlib.Path(args.env_dir)
    errors = []
    subjects = read_lines(env_dir / "subjects.txt")
    for s in subjects:
        if PLACEHOLDER in s:
            errors.append("subjects.txt still has a placeholder line: %s" % s)
        if "|" in s or " " in s:
            errors.append("subjects.txt: one subject or pattern per line, no separators: %s" % s)
    if not subjects:
        errors.append("subjects.txt lists no subjects")

    path = env_dir / "schemaexporter.yaml"
    template = None
    if not path.exists():
        errors.append("missing %s" % path)
    else:
        docs = [d for d in yaml.safe_load_all(path.read_text(encoding="utf-8")) if d]
        if len(docs) != 1 or docs[0].get("kind") != "SchemaExporter":
            errors.append("%s must hold exactly one SchemaExporter document" % path)
        else:
            template = docs[0]
            text = path.read_text(encoding="utf-8")
            if PLACEHOLDER in text:
                errors.append("%s still contains a %s placeholder" % (path, PLACEHOLDER))

    if args.list:
        print("\n".join(subjects))
        return 0
    if args.check:
        if errors:
            print("FAIL: schema-linking static validation")
            for e in errors:
                print("  - " + e)
            return 1
        print("PASS: %d subject pattern(s)" % len(subjects))
        return 0
    if errors:
        for e in errors:
            print("ERROR: " + e, file=sys.stderr)
        return 1
    if not args.out:
        print("ERROR: --out is required to render", file=sys.stderr)
        return 1

    spec = template.setdefault("spec", {})
    spec["subjects"] = subjects
    src_rest = spec.get("sourceCluster", {}).get("schemaRegistryRest", {})
    if str(src_rest.get("endpoint", "")).startswith("__") or args.source_sr_url:
        if not args.source_sr_url or args.source_sr_url.startswith(("@", "REPLACE_WITH_")):
            print("ERROR: --source-sr-url must be the resolved source Schema Registry URL", file=sys.stderr)
            return 1
        src_rest["endpoint"] = args.source_sr_url
    for side in ("sourceCluster", "destinationCluster"):
        conf = spec.get(side, {}).get("schemaRegistryRest", {}).get("authentication", {}).get("oauth", {}).get("configuration", {})
        if str(conf.get("tokenEndpointUri", "")).startswith("__") or args.token_endpoint:
            if not args.token_endpoint or args.token_endpoint.startswith("@"):
                print("ERROR: --token-endpoint must be the resolved Okta token URL", file=sys.stderr)
                return 1
            conf["tokenEndpointUri"] = args.token_endpoint
    text = yaml.safe_dump(template, default_flow_style=False, sort_keys=False)
    leftover = re.findall(r"__[A-Z_]+__|REPLACE_WITH_\w+|@vargroup", text)
    if leftover:
        print("ERROR: rendered CR still contains unresolved tokens: %s" % sorted(set(leftover)), file=sys.stderr)
        return 1
    pathlib.Path(args.out).write_text(text, encoding="utf-8")
    print("rendered %s: %d subject pattern(s)" % (args.out, len(subjects)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
