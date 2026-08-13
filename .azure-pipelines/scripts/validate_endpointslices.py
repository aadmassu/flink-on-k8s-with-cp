#!/usr/bin/env python3
"""Count ready addresses across every Kubernetes EndpointSlice on stdin."""

import json
import sys


def count_ready_addresses(document: dict) -> int:
    total = 0
    for slice_item in document.get("items", []):
        for endpoint in slice_item.get("endpoints", []):
            # EndpointSlice API compatibility rule: an omitted ready condition
            # is interpreted as ready; only an explicit false is excluded.
            if endpoint.get("conditions", {}).get("ready") is not False:
                total += len(endpoint.get("addresses", []))
    return total


def main() -> int:
    try:
        document = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError) as exc:
        print(f"EndpointSlice JSON is invalid: {exc}", file=sys.stderr)
        return 2

    print(count_ready_addresses(document))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
