#!/usr/bin/env python3
"""Compare a rendered ClusterLink/SchemaExporter CR with what the API server stored.

CFK 3.2 v1beta1 admission drops schema-mismatched sub-blocks silently
(runbook LESSONS_LEARNED A-series, memory: v1beta1 silent-strip). This script
walks every leaf in the rendered spec and reports leaves that are missing or
different in the live object. Exit 1 when anything was dropped.

Paths are handled as key tuples, not dotted strings, because cluster link
config keys themselves contain dots (consumer.offset.sync.enable).

Usage: verify_clusterlink_admission.py --rendered FILE --live FILE
Python 3.6+, PyYAML only.
"""
import argparse

import yaml


def leaves(node, prefix=()):
    if isinstance(node, dict):
        for k, v in node.items():
            for item in leaves(v, prefix + (k,)):
                yield item
    elif isinstance(node, list):
        for i, v in enumerate(node):
            for item in leaves(v, prefix + (i,)):
                yield item
    else:
        yield prefix, node


def lookup(node, path):
    cur = node
    for part in path:
        if isinstance(cur, list) and isinstance(part, int):
            if part >= len(cur):
                return None, False
            cur = cur[part]
        elif isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None, False
    return cur, True


def show(path):
    out = "spec"
    for part in path:
        out += "[%d]" % part if isinstance(part, int) else "." + str(part)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rendered", required=True)
    ap.add_argument("--live", required=True)
    args = ap.parse_args()

    with open(args.rendered, encoding="utf-8") as fh:
        rendered = yaml.safe_load(fh)
    with open(args.live, encoding="utf-8") as fh:
        live = yaml.safe_load(fh)
    r_spec = rendered.get("spec", {})
    l_spec = live.get("spec", {})

    compared = 0
    dropped, changed = [], []
    for path, value in leaves(r_spec):
        compared += 1
        live_value, present = lookup(l_spec, path)
        if not present:
            dropped.append(show(path))
        elif str(live_value) != str(value):
            changed.append("%s: rendered=%r live=%r" % (show(path), value, live_value))

    print("admission check: %d leaf field(s) compared" % compared)
    if dropped:
        print("DROPPED at admission (silent strip):")
        for d in dropped:
            print("  - " + d)
    if changed:
        print("CHANGED at admission (defaulting or normalisation):")
        for c in changed:
            print("  - " + c)
    if dropped:
        return 1
    print("PASS: every rendered spec field is present in the stored object")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
