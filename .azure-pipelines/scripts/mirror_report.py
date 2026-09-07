#!/usr/bin/env python3
"""Turn `kafka-mirrors --describe --pedantic` output into a status table.

Usage:
  mirror_report.py --describe-dir DIR [--report FILE] [--require-zero-lag t1,t2]
                   [--link NAME] [--env ENV] [--extra FILE ...]

DIR holds one <topic>.txt per mirror topic (raw describe output). The script
prints a Markdown table, writes it (plus any --extra files) to --report, and
exits 2 when a topic listed in --require-zero-lag has lag > 0, is not ACTIVE,
or has no describe output at all. Parsing is token based ("Key: value" pairs)
so minor format drift between CP versions does not break it.

Python 3.6+, standard library only.
"""
import argparse
import datetime
import pathlib
import re

PAIR_RE = re.compile(r"([A-Za-z][A-Za-z0-9_]*):\s*([^\t\n]*?)(?=\s+[A-Za-z][A-Za-z0-9_]*:|\s*$)")


def parse_describe(text):
    """Return (topic_info, [partition_info]) dicts of lowercase keys."""
    topic = {}
    partitions = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.lower().startswith(("error", "exception", "warn")):
            continue
        pairs = {k.lower(): v.strip() for k, v in PAIR_RE.findall(stripped)}
        if not pairs:
            continue
        if "partition" in pairs and "topic" not in pairs:
            partitions.append(pairs)
        elif "topic" in pairs or "mirrortopic" in pairs:
            topic.update(pairs)
    return topic, partitions


def to_int(value):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def summarise(name, text):
    topic, partitions = parse_describe(text)
    state = topic.get("state") or topic.get("mirrorstate") or "UNKNOWN"
    lags = [to_int(p.get("lag")) for p in partitions]
    lags = [l for l in lags if l is not None]
    fetch_ages = [to_int(p.get("timesincelastfetchms")) for p in partitions]
    fetch_ages = [f for f in fetch_ages if f is not None]
    errors = sorted({p.get("mirrortopicerror") or p.get("error") for p in partitions
                     if (p.get("mirrortopicerror") or p.get("error")) not in (None, "", "NO_ERROR", "NONE")})
    if topic.get("mirrortopicerror") not in (None, "", "NO_ERROR", "NONE"):
        errors.append(topic.get("mirrortopicerror"))
    return {
        "topic": name,
        "state": state,
        "link": topic.get("linkname", ""),
        "partitions": len(partitions),
        "lag_total": sum(lags) if lags else None,
        "lag_max": max(lags) if lags else None,
        "fetch_age_max_ms": max(fetch_ages) if fetch_ages else None,
        "state_time": topic.get("statetime", ""),
        "errors": "; ".join(e for e in errors if e),
        "raw_ok": bool(topic or partitions),
    }


def fmt(v):
    return "-" if v is None or v == "" else str(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--describe-dir", required=True)
    ap.add_argument("--report")
    ap.add_argument("--require-zero-lag", default="")
    ap.add_argument("--link", default="")
    ap.add_argument("--env", default="")
    ap.add_argument("--extra", nargs="*", default=[])
    args = ap.parse_args()

    ddir = pathlib.Path(args.describe_dir)
    rows = []
    for path in sorted(ddir.glob("*.txt")):
        rows.append(summarise(path.stem, path.read_text(encoding="utf-8", errors="replace")))

    header = "| Mirror topic | State | Partitions | Lag total | Lag max | Last fetch age (ms) | State time | Errors |"
    sep = "|---|---|---|---|---|---|---|---|"
    lines = [header, sep]
    for r in rows:
        lines.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (
            r["topic"], r["state"], fmt(r["partitions"]), fmt(r["lag_total"]), fmt(r["lag_max"]),
            fmt(r["fetch_age_max_ms"]), fmt(r["state_time"]), fmt(r["errors"] or "")))
    table = "\n".join(lines)

    active = sum(1 for r in rows if r["state"] == "ACTIVE")
    stopped = sum(1 for r in rows if r["state"] in ("STOPPED", "PENDING_STOPPED"))
    failed = [r["topic"] for r in rows if r["state"] in ("FAILED", "LINK_FAILED", "SOURCE_UNAVAILABLE") or not r["raw_ok"]]
    lagging = [r["topic"] for r in rows if (r["lag_total"] or 0) > 0]
    summary = [
        "Mirror topics: %d | ACTIVE: %d | STOPPED/PENDING_STOPPED: %d | problem: %d | lagging: %d"
        % (len(rows), active, stopped, len(failed), len(lagging)),
    ]
    if failed:
        summary.append("Problem topics: " + ", ".join(failed))
    if lagging:
        summary.append("Lagging topics: " + ", ".join(lagging))

    print(table)
    print()
    print("\n".join(summary))

    if args.report:
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        doc = ["# Mirror topic status — %s" % (args.env or "env"), "",
               "Link: `%s`  " % args.link, "Generated: %s" % now, "", table, "", "\n".join(summary), ""]
        for extra in args.extra:
            p = pathlib.Path(extra)
            if p.exists():
                doc += ["", "## %s" % p.stem.replace("_", " "), "", "```", p.read_text(encoding="utf-8", errors="replace").rstrip(), "```", ""]
        pathlib.Path(args.report).write_text("\n".join(doc), encoding="utf-8")
        print("report written: %s" % args.report)

    required = [t for t in args.require_zero_lag.split(",") if t.strip()]
    if required:
        by_name = {r["topic"]: r for r in rows}
        blockers = []
        for t in required:
            r = by_name.get(t)
            if r is None or not r["raw_ok"]:
                blockers.append("%s: no describe output" % t)
            elif r["state"] != "ACTIVE":
                blockers.append("%s: state %s (need ACTIVE)" % (t, r["state"]))
            elif r["lag_total"] is None:
                blockers.append("%s: lag not reported" % t)
            elif r["lag_total"] > 0:
                blockers.append("%s: lag %d" % (t, r["lag_total"]))
        if blockers:
            print()
            print("PROMOTE BLOCKED:")
            for b in blockers:
                print("  - " + b)
            return 2
        print()
        print("PROMOTE PRE-CHECK PASSED for: " + ", ".join(required))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
