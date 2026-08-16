#!/usr/bin/env python3
"""Fail fast when the DEV CFK migration plan would exhaust namespace quota."""

import argparse
import json
import re
from decimal import Decimal
from pathlib import Path


BINARY = {
    "Ki": 1024,
    "Mi": 1024**2,
    "Gi": 1024**3,
    "Ti": 1024**4,
}


def bytes_quantity(value: str) -> int:
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([KMGT]i)?", value or "0")
    if not match:
        raise ValueError(f"unsupported binary quantity: {value!r}")
    return int(Decimal(match.group(1)) * BINARY.get(match.group(2), 1))


def cpu_millis(value: str) -> int:
    if not value:
        return 0
    return int(Decimal(value[:-1])) if value.endswith("m") else int(Decimal(value) * 1000)


def pod_quota_resources(pod):
    totals = {"requests.cpu": 0, "limits.cpu": 0, "requests.memory": 0, "limits.memory": 0}
    app = {key: 0 for key in totals}
    init_max = {key: 0 for key in totals}

    for container in pod.get("spec", {}).get("containers", []):
        resources = container.get("resources", {})
        app["requests.cpu"] += cpu_millis(resources.get("requests", {}).get("cpu", "0"))
        app["limits.cpu"] += cpu_millis(resources.get("limits", {}).get("cpu", "0"))
        app["requests.memory"] += bytes_quantity(resources.get("requests", {}).get("memory", "0"))
        app["limits.memory"] += bytes_quantity(resources.get("limits", {}).get("memory", "0"))

    for container in pod.get("spec", {}).get("initContainers", []):
        resources = container.get("resources", {})
        init_max["requests.cpu"] = max(init_max["requests.cpu"], cpu_millis(resources.get("requests", {}).get("cpu", "0")))
        init_max["limits.cpu"] = max(init_max["limits.cpu"], cpu_millis(resources.get("limits", {}).get("cpu", "0")))
        init_max["requests.memory"] = max(init_max["requests.memory"], bytes_quantity(resources.get("requests", {}).get("memory", "0")))
        init_max["limits.memory"] = max(init_max["limits.memory"], bytes_quantity(resources.get("limits", {}).get("memory", "0")))

    for key in totals:
        totals[key] = max(app[key], init_max[key])
    return totals


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quota", required=True)
    parser.add_argument("--pods", required=True)
    parser.add_argument("--pvcs", required=True)
    args = parser.parse_args()

    quota = json.loads(Path(args.quota).read_text())
    pods = json.loads(Path(args.pods).read_text())
    pvcs = json.loads(Path(args.pvcs).read_text())
    hard = quota["status"]["hard"]
    used = quota["status"]["used"]

    # Desired DEV CFK footprint from the manifests in this package.
    gib = 1024**3
    planned = {
        "requests.cpu": 9850,
        "limits.cpu": 21125,
        "requests.memory": 23500 * 1024**2,
        "limits.memory": 45 * gib,
        "requests.storage": 1175 * gib,
    }
    reserve = {
        "requests.cpu": 2000,
        "limits.cpu": 6000,
        "requests.memory": 8 * gib,
        "limits.memory": 16 * gib,
        "requests.storage": 50 * gib,
    }

    current_cfk = {key: 0 for key in planned}
    for pod in pods.get("items", []):
        labels = pod.get("metadata", {}).get("labels", {})
        if labels.get("app.kubernetes.io/part-of") == "confluent-platform":
            values = pod_quota_resources(pod)
            for key, value in values.items():
                current_cfk[key] += value

    pvc_pattern = re.compile(
        r"^(data[0-9]+-(?:kafka|kraftcontroller|controlcenter)-[0-9]+|prometheus-data-controlcenter-[0-9]+)$"
    )
    for pvc in pvcs.get("items", []):
        if pvc_pattern.fullmatch(pvc.get("metadata", {}).get("name", "")):
            current_cfk["requests.storage"] += bytes_quantity(
                pvc.get("spec", {}).get("resources", {}).get("requests", {}).get("storage", "0")
            )

    hard_values = {
        "requests.cpu": cpu_millis(hard["requests.cpu"]),
        "limits.cpu": cpu_millis(hard["limits.cpu"]),
        "requests.memory": bytes_quantity(hard["requests.memory"]),
        "limits.memory": bytes_quantity(hard["limits.memory"]),
        "requests.storage": bytes_quantity(hard["requests.storage"]),
    }
    used_values = {
        "requests.cpu": cpu_millis(used.get("requests.cpu", "0")),
        "limits.cpu": cpu_millis(used.get("limits.cpu", "0")),
        "requests.memory": bytes_quantity(used.get("requests.memory", "0")),
        "limits.memory": bytes_quantity(used.get("limits.memory", "0")),
        "requests.storage": bytes_quantity(used.get("requests.storage", "0")),
    }

    failures = []
    print(f"{'RESOURCE':<20} {'HARD':>12} {'PROJECTED':>12} {'RESERVE':>12} {'HEADROOM':>12}")
    for key in planned:
        projected = used_values[key] - current_cfk[key] + planned[key]
        headroom = hard_values[key] - projected
        divisor = 1000 if key.endswith("cpu") else gib
        suffix = " cores" if key.endswith("cpu") else " Gi"
        print(
            f"{key:<20} {hard_values[key]/divisor:>11.2f}{suffix} "
            f"{projected/divisor:>11.2f}{suffix} {reserve[key]/divisor:>11.2f}{suffix} "
            f"{headroom/divisor:>11.2f}{suffix}"
        )
        if projected + reserve[key] > hard_values[key]:
            failures.append(key)

    if failures:
        raise SystemExit("FATAL: quota reserve would be violated for: " + ", ".join(failures))
    print("OK: DEV CFK migration footprint fits quota while preserving the Flink/operations reserve.")


if __name__ == "__main__":
    main()
