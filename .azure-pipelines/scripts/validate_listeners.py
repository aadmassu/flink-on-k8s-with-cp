#!/usr/bin/env python3
"""Validate the hybrid-auth contract in one CFK environment directory."""

import argparse
from pathlib import Path
import sys

import yaml


MANAGED_COMPONENTS = (
    "schemaregistry.yaml",
    "connect.yaml",
    "kafkarest.yaml",
    "controlcenter.yaml",
)


def load_yaml(path: Path) -> dict:
    if not path.is_file():
        raise ValueError(f"required manifest is missing: {path}")
    try:
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise ValueError(f"cannot parse {path}: {exc}") from exc
    if not isinstance(document, dict):
        raise ValueError(f"manifest is not a YAML object: {path}")
    return document


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def validate_environment(env_dir: Path) -> list[str]:
    errors: list[str] = []
    kafka = load_yaml(env_dir / "kafka.yaml")
    spec = kafka.get("spec", {})
    listeners = spec.get("listeners", {})

    internal = listeners.get("internal", {})
    require(
        internal.get("authentication", {}).get("type") == "plain",
        "Kafka internal listener must use PLAIN authentication",
        errors,
    )
    require(
        internal.get("tls", {}).get("enabled") is True,
        "Kafka internal listener must enable TLS",
        errors,
    )

    external = listeners.get("external", {})
    require(
        external.get("authentication", {}).get("type") == "oauth",
        "Kafka external listener must use OAuth authentication",
        errors,
    )
    require(
        external.get("tls", {}).get("enabled") is True,
        "Kafka external listener must enable TLS",
        errors,
    )

    reporter = spec.get("metricReporter", {})
    reporter_endpoint = str(reporter.get("bootstrapEndpoint", ""))
    require(
        reporter_endpoint.endswith(":9071"),
        f"Kafka metrics reporter must use port 9071, got {reporter_endpoint!r}",
        errors,
    )
    require(
        reporter.get("authentication", {}).get("type") == "plain",
        "Kafka metrics reporter must use PLAIN authentication",
        errors,
    )

    for filename in MANAGED_COMPONENTS:
        component = load_yaml(env_dir / filename)
        kafka_dependency = component.get("spec", {}).get("dependencies", {}).get("kafka", {})
        endpoint = str(kafka_dependency.get("bootstrapEndpoint", ""))
        auth_type = kafka_dependency.get("authentication", {}).get("type")
        require(
            endpoint.endswith(":9092"),
            f"{filename} Kafka dependency must use port 9092, got {endpoint!r}",
            errors,
        )
        require(
            auth_type == "oauth",
            f"{filename} Kafka dependency must use OAuth, got {auth_type!r}",
            errors,
        )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("env_dir", type=Path)
    args = parser.parse_args()
    try:
        errors = validate_environment(args.env_dir)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Hybrid listener contract valid: {args.env_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
