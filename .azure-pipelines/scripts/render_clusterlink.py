#!/usr/bin/env python3
"""Render a CFK ClusterLink CR from an env's cluster-linking folder.

Inputs (all under --env-dir):
  clusterlink.yaml      CR template; __SOURCE_CLUSTER_ID__ token, empty list stubs
  topics.txt            one mirror per line: "<source>" or "<source>=<mirror>"
  promote-topics.txt    mirror names that must carry state PROMOTE
  consumer-groups.txt   "name|patternType|filterType"
  acls.txt              "resourceType|name|patternType|principal|host|operation|permissionType"

Modes:
  --out FILE                write the rendered CR (default action)
  --list-mirrors            print mirror-topic names, one per line
  --list-sources            print source-topic names, one per line
  --list-groups             print consumer-group names, one per line
  --check                   static validation only (exit 1 on any problem)
  --failover-topics a,b     set state FAILOVER on those mirrors (emergency path)

Python 3.6+, PyYAML only.
"""
import argparse
import pathlib
import re
import sys

import yaml


def dump_yaml(data):
    """safe_dump preserving key order; PyYAML < 5.1 (RHEL python3.6) has no sort_keys."""
    try:
        return yaml.safe_dump(data, default_flow_style=False, sort_keys=False)
    except TypeError:
        class OrderedDumper(yaml.SafeDumper):
            pass
        OrderedDumper.add_representer(
            dict, lambda d, v: d.represent_mapping("tag:yaml.org,2002:map", list(v.items())))
        return yaml.dump(data, Dumper=OrderedDumper, default_flow_style=False)

TOPIC_RE = re.compile(r"^[A-Za-z0-9._-]{1,249}$")
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


def parse_topics(env_dir, errors):
    """Return list of (source, mirror)."""
    result = []
    seen = set()
    for line in read_lines(env_dir / "topics.txt"):
        if PLACEHOLDER in line:
            errors.append("topics.txt still has a placeholder line: %s" % line)
            continue
        if "=" in line:
            source, mirror = (p.strip() for p in line.split("=", 1))
        else:
            source = mirror = line
        for name in (source, mirror):
            if not TOPIC_RE.match(name):
                errors.append("topics.txt: invalid topic name %r" % name)
        if mirror in seen:
            errors.append("topics.txt: mirror topic listed twice: %s" % mirror)
        seen.add(mirror)
        result.append((source, mirror))
    return result


def parse_groups(env_dir, errors):
    filters = []
    for line in read_lines(env_dir / "consumer-groups.txt"):
        if PLACEHOLDER in line:
            errors.append("consumer-groups.txt still has a placeholder line: %s" % line)
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) == 1:
            # bare group name = exact match, included
            parts = [parts[0], "LITERAL", "INCLUDE"]
        if len(parts) != 3:
            errors.append("consumer-groups.txt: expected name|patternType|filterType (or a bare name), got %d field(s): %s" % (len(parts), line))
            continue
        name, pattern, ftype = parts
        if pattern not in ("LITERAL", "PREFIXED"):
            errors.append("consumer-groups.txt: patternType must be LITERAL|PREFIXED: %s" % line)
        if ftype not in ("INCLUDE", "EXCLUDE"):
            errors.append("consumer-groups.txt: filterType must be INCLUDE|EXCLUDE: %s" % line)
        filters.append({"name": name, "patternType": pattern, "filterType": ftype})
    return filters


ACL_RESOURCE = ("any", "cluster", "group", "topic", "transactionId", "delegationToken")
ACL_PATTERN = ("any", "literal", "prefixed", "match")
ACL_OPS = ("ANY", "READ", "WRITE", "CREATE", "DELETE", "ALTER", "DESCRIBE",
           "CLUSTER_ACTION", "IDEMPOTENT_WRITE", "DESCRIBE_CONFIGS", "ALTER_CONFIGS")
ACL_PERM = ("any", "allow", "deny")


def parse_acls(env_dir, errors):
    filters = []
    for line in read_lines(env_dir / "acls.txt"):
        if PLACEHOLDER in line:
            errors.append("acls.txt still has a placeholder line: %s" % line)
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) != 7:
            errors.append("acls.txt: expected 7 fields, got %d: %s" % (len(parts), line))
            continue
        rtype, name, pattern, principal, host, op, perm = parts
        if rtype not in ACL_RESOURCE:
            errors.append("acls.txt: resourceType %r not in %s" % (rtype, ACL_RESOURCE))
        if pattern not in ACL_PATTERN:
            errors.append("acls.txt: patternType %r not in %s" % (pattern, ACL_PATTERN))
        if op not in ACL_OPS:
            errors.append("acls.txt: operation %r not in %s" % (op, ACL_OPS))
        if perm not in ACL_PERM:
            errors.append("acls.txt: permissionType %r not in %s" % (perm, ACL_PERM))
        filters.append({
            "accessFilter": {
                "principal": principal, "host": host,
                "operation": op, "permissionType": perm,
            },
            "resourceFilter": {"resourceType": rtype, "name": name, "patternType": pattern},
        })
    return filters


def parse_promote(env_dir, mirrors, errors):
    names = []
    for line in read_lines(env_dir / "promote-topics.txt"):
        if PLACEHOLDER in line:
            errors.append("promote-topics.txt still has a placeholder line: %s" % line)
            continue
        if line not in mirrors:
            errors.append("promote-topics.txt: %s is not a mirror topic in topics.txt" % line)
        names.append(line)
    return names


def load_template(env_dir, errors):
    path = env_dir / "clusterlink.yaml"
    if not path.exists():
        errors.append("missing %s" % path)
        return None
    docs = list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
    docs = [d for d in docs if d]
    if len(docs) != 1 or docs[0].get("kind") != "ClusterLink":
        errors.append("%s must hold exactly one ClusterLink document" % path)
        return None
    return docs[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--env-dir", required=True)
    ap.add_argument("--out")
    ap.add_argument("--source-cluster-id", default="")
    ap.add_argument("--source-bootstrap", default="", help="replaces __SOURCE_BOOTSTRAP__")
    ap.add_argument("--token-endpoint", default="", help="replaces __SOURCE_OAUTH_TOKEN_ENDPOINT__")
    ap.add_argument("--failover-topics", default="")
    ap.add_argument("--list-mirrors", action="store_true")
    ap.add_argument("--list-sources", action="store_true")
    ap.add_argument("--list-groups", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    env_dir = pathlib.Path(args.env_dir)
    errors = []
    topics = parse_topics(env_dir, errors)
    mirrors = [m for _, m in topics]
    groups = parse_groups(env_dir, errors)
    acls = parse_acls(env_dir, errors)
    promote = parse_promote(env_dir, mirrors, errors)
    template = load_template(env_dir, errors)

    if args.list_mirrors:
        print("\n".join(mirrors))
        return 0
    if args.list_sources:
        print("\n".join(s for s, _ in topics))
        return 0
    if args.list_groups:
        print("\n".join(g["name"] for g in groups if g["filterType"] == "INCLUDE"))
        return 0

    if not topics:
        errors.append("topics.txt lists no topics; a link with no mirror topics is not provisioned")

    failover = [t for t in args.failover_topics.split(",") if t.strip()]
    for t in failover:
        if t not in mirrors:
            errors.append("--failover-topics: %s is not a mirror topic in topics.txt" % t)

    if args.check:
        if errors:
            print("FAIL: cluster-linking static validation")
            for e in errors:
                print("  - " + e)
            return 1
        print("PASS: %d mirror topic(s), %d promote, %d group filter(s), %d acl filter(s)"
              % (len(topics), len(promote), len(groups), len(acls)))
        return 0

    if errors:
        for e in errors:
            print("ERROR: " + e, file=sys.stderr)
        return 1
    if not args.out:
        print("ERROR: --out is required to render", file=sys.stderr)
        return 1
    if not args.source_cluster_id or args.source_cluster_id.startswith("@"):
        print("ERROR: --source-cluster-id must be the resolved source Kafka cluster id", file=sys.stderr)
        return 1

    spec = template.setdefault("spec", {})
    src = spec.setdefault("sourceKafkaCluster", {})
    src["clusterID"] = args.source_cluster_id
    if str(src.get("bootstrapEndpoint", "")).startswith("__") or args.source_bootstrap:
        if not args.source_bootstrap or args.source_bootstrap.startswith(("@", "REPLACE_WITH_")):
            print("ERROR: --source-bootstrap must be the resolved host:port list", file=sys.stderr)
            return 1
        src["bootstrapEndpoint"] = args.source_bootstrap
    oauth = src.get("authentication", {}).get("oauthSettings", {})
    if str(oauth.get("tokenEndpointUri", "")).startswith("__") or args.token_endpoint:
        if not args.token_endpoint or args.token_endpoint.startswith("@"):
            print("ERROR: --token-endpoint must be the resolved Okta token URL", file=sys.stderr)
            return 1
        oauth["tokenEndpointUri"] = args.token_endpoint

    mirror_list = []
    for source, mirror in topics:
        item = {"name": mirror}
        if source != mirror:
            item["sourceTopicName"] = source
        if mirror in failover:
            item["state"] = "FAILOVER"
        elif mirror in promote:
            item["state"] = "PROMOTE"
        else:
            item["state"] = "ACTIVE"
        mirror_list.append(item)
    spec["mirrorTopics"] = mirror_list

    configs = spec.setdefault("configs", {})
    if groups:
        spec["consumerGroupFilters"] = groups
        configs["consumer.offset.sync.enable"] = "true"
    else:
        spec.pop("consumerGroupFilters", None)
        configs["consumer.offset.sync.enable"] = "false"
    if acls:
        spec["aclFilters"] = acls
        configs["acl.sync.enable"] = "true"
    else:
        spec.pop("aclFilters", None)
        configs["acl.sync.enable"] = "false"
    # CFK stores configs as strings; normalise anything the template wrote as bool/int.
    for k, v in list(configs.items()):
        if isinstance(v, bool):
            configs[k] = "true" if v else "false"
        elif not isinstance(v, str):
            configs[k] = str(v)

    text = dump_yaml(template)
    leftover = re.findall(r"__[A-Z_]+__|REPLACE_WITH_\w+|@vargroup|@discover", text)
    if leftover:
        print("ERROR: rendered CR still contains unresolved tokens: %s" % sorted(set(leftover)), file=sys.stderr)
        return 1
    pathlib.Path(args.out).write_text(text, encoding="utf-8")
    print("rendered %s: %d mirror topic(s) [%d PROMOTE, %d FAILOVER], offset sync %s, acl sync %s"
          % (args.out, len(mirror_list), len(promote), len(failover),
             configs["consumer.offset.sync.enable"], configs["acl.sync.enable"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
