#!/usr/bin/env python3
"""
Validate DEV two-account identity configuration in manifest files.
Uses YAML parsing to validate exact paths (not grep).
"""

import sys
import os

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not available. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def get_nested(obj, *keys):
    """Safely get nested dict value."""
    for key in keys:
        if isinstance(obj, dict):
            obj = obj.get(key)
        else:
            return None
    return obj


def validate_kafka_sso(kafka_path):
    """Validate kafka.yaml MDS SSO configuration."""
    errors = []

    try:
        with open(kafka_path, 'r') as f:
            kafka = yaml.safe_load(f)
    except Exception as e:
        return [f"Cannot parse {kafka_path}: {e}"]

    if not kafka or kafka.get('kind') != 'Kafka':
        return [f"{kafka_path} is not a valid Kafka CR"]

    # Check: provider.sso.clientCredentials.secretRef == oauth-mds-sso
    sso_secret = get_nested(kafka, 'spec', 'services', 'mds', 'provider', 'sso',
                            'clientCredentials', 'secretRef')
    if sso_secret != 'oauth-mds-sso':
        errors.append(f"kafka.yaml provider.sso.clientCredentials.secretRef={sso_secret}, expected oauth-mds-sso")
    else:
        print("✓ kafka.yaml uses oauth-mds-sso for provider.sso")

    # Check: SSO configurations match VM
    configs = get_nested(kafka, 'spec', 'services', 'mds', 'provider', 'sso', 'configurations')
    if configs:
        sub_claim = configs.get('subClaimName')
        if sub_claim != 'sub':
            errors.append(f"kafka.yaml SSO subClaimName={sub_claim}, expected sub")
        else:
            print("✓ kafka.yaml SSO has subClaimName: sub")

        groups_claim = configs.get('groupsClaimName')
        if groups_claim != 'dahDev_groups':
            errors.append(f"kafka.yaml SSO groupsClaimName={groups_claim}, expected dahDev_groups")
        else:
            print("✓ kafka.yaml SSO has groupsClaimName: dahDev_groups")

        groups_scope = configs.get('groupsClaimScope')
        if groups_scope != '11547.DAH(Dev)':
            errors.append(f"kafka.yaml SSO groupsClaimScope={groups_scope}, expected 11547.DAH(Dev)")
        else:
            print("✓ kafka.yaml SSO has groupsClaimScope: 11547.DAH(Dev)")

        refresh = configs.get('refreshToken')
        if refresh is not True:
            errors.append(f"kafka.yaml SSO refreshToken={refresh}, expected true")
        else:
            print("✓ kafka.yaml SSO has refreshToken: true")

    return errors


def validate_controlcenter_deps(cc_path):
    """Validate controlcenter.yaml OAuth dependencies."""
    errors = []

    try:
        with open(cc_path, 'r') as f:
            cc = yaml.safe_load(f)
    except Exception as e:
        return [f"Cannot parse {cc_path}: {e}"]

    if not cc or cc.get('kind') != 'ControlCenter':
        return [f"{cc_path} is not a valid ControlCenter CR"]

    deps = get_nested(cc, 'spec', 'dependencies') or {}

    # Kafka dependency
    kafka_secret = get_nested(deps, 'kafka', 'authentication', 'jaasConfig', 'secretRef')
    if kafka_secret != 'oauth-controlcenter':
        errors.append(f"controlcenter.yaml Kafka dep uses {kafka_secret}, expected oauth-controlcenter")
    else:
        print("✓ controlcenter.yaml Kafka dependency uses oauth-controlcenter")

    # MDS dependency (authentication.oauth.secretRef)
    mds_secret = get_nested(deps, 'mds', 'authentication', 'oauth', 'secretRef')
    if mds_secret != 'oauth-controlcenter':
        errors.append(f"controlcenter.yaml MDS dep uses {mds_secret}, expected oauth-controlcenter")
    else:
        print("✓ controlcenter.yaml MDS dependency uses oauth-controlcenter")

    # Schema Registry dependency
    sr_secret = get_nested(deps, 'schemaRegistry', 'authentication', 'oauth', 'secretRef')
    if sr_secret != 'oauth-controlcenter':
        errors.append(f"controlcenter.yaml SR dep uses {sr_secret}, expected oauth-controlcenter")
    else:
        print("✓ controlcenter.yaml Schema Registry dependency uses oauth-controlcenter")

    # Connect dependencies (all must use oauth-controlcenter)
    connects = deps.get('connect', [])
    if isinstance(connects, list):
        for i, conn in enumerate(connects):
            conn_secret = get_nested(conn, 'authentication', 'oauth', 'secretRef')
            conn_name = conn.get('name', f'[{i}]')
            if conn_secret != 'oauth-controlcenter':
                errors.append(f"controlcenter.yaml Connect[{conn_name}] uses {conn_secret}, expected oauth-controlcenter")
            else:
                print(f"✓ controlcenter.yaml Connect[{conn_name}] uses oauth-controlcenter")

    # MDS SSO protocol
    sso_protocol = get_nested(deps, 'mds', 'ssoProtocol')
    if sso_protocol != 'oidc':
        errors.append(f"controlcenter.yaml MDS ssoProtocol={sso_protocol}, expected oidc")
    else:
        print("✓ controlcenter.yaml MDS ssoProtocol: oidc")

    # No basic-auth on MDS
    basic_auth = get_nested(deps, 'mds', 'authentication', 'basic')
    if basic_auth is not None:
        errors.append("controlcenter.yaml has basic-auth on MDS (not allowed)")
    else:
        print("✓ No MDS basic-auth configuration in controlcenter.yaml")

    return errors


def validate_rolebindings(rb_path):
    """Validate rolebindings.yaml controlcenter-systemadmin."""
    errors = []
    found = False

    try:
        with open(rb_path, 'r') as f:
            docs = yaml.safe_load_all(f)
            for doc in docs:
                if doc and doc.get('kind') == 'ConfluentRolebinding' and \
                   doc.get('metadata', {}).get('name') == 'controlcenter-systemadmin':
                    found = True

                    principal_type = get_nested(doc, 'spec', 'principal', 'type')
                    if principal_type != 'user':
                        errors.append(f"controlcenter-systemadmin principal.type={principal_type}, expected user")

                    principal_name = get_nested(doc, 'spec', 'principal', 'name')
                    if principal_name != '0oa1ov6h5mwmQTCKI358':
                        errors.append(f"controlcenter-systemadmin principal.name={principal_name}, expected 0oa1ov6h5mwmQTCKI358")
                    else:
                        print("✓ rolebindings.yaml controlcenter-systemadmin uses 0oa1ov6h5mwmQTCKI358")

                    role = get_nested(doc, 'spec', 'role')
                    if role != 'SystemAdmin':
                        errors.append(f"controlcenter-systemadmin role={role}, expected SystemAdmin")

                    break
    except Exception as e:
        return [f"Cannot parse {rb_path}: {e}"]

    if not found:
        errors.append(f"controlcenter-systemadmin ConfluentRolebinding not found in {rb_path}")

    return errors


def main():
    if len(sys.argv) < 2:
        print("Usage: validate_dev_two_account_manifest.py <env_dir>", file=sys.stderr)
        sys.exit(1)

    env_dir = sys.argv[1]
    kafka_path = os.path.join(env_dir, 'kafka.yaml')
    cc_path = os.path.join(env_dir, 'controlcenter.yaml')
    rb_path = os.path.join(env_dir, 'rbac', 'rolebindings.yaml')

    all_errors = []

    if not os.path.isfile(kafka_path):
        print(f"ERROR: {kafka_path} not found", file=sys.stderr)
        sys.exit(1)
    all_errors.extend(validate_kafka_sso(kafka_path))

    if not os.path.isfile(cc_path):
        print(f"ERROR: {cc_path} not found", file=sys.stderr)
        sys.exit(1)
    all_errors.extend(validate_controlcenter_deps(cc_path))

    if not os.path.isfile(rb_path):
        print(f"ERROR: {rb_path} not found", file=sys.stderr)
        sys.exit(1)
    all_errors.extend(validate_rolebindings(rb_path))

    if all_errors:
        print("\nERRORS:")
        for error in all_errors:
            print(f"  - {error}", file=sys.stderr)
        print("FATAL: DEV two-account identity checks failed", file=sys.stderr)
        sys.exit(1)
    else:
        print("\n✅ DEV two-account identity manifest validation passed")
        sys.exit(0)


if __name__ == '__main__':
    main()
