# UAT floating DNS ingress correction

## Decision

GO for committing these files and applying them through the normal pipeline, subject to the Container Platform/DNS team pointing the shared UAT floating CNAME at the active site.

## Root cause

The pipeline derived `apps.uat-p.ocp.fcbint.net` and `apps.uat-s.ocp.fcbint.net`. Those are not the FCB UAT ingress domains. The documented contract is:

- Shared UAT floating domain: `apps.ut.ocp.fcbint.net`
- UAT primary physical domain: `apps.ut-p.ocp.fcbint.net`
- UAT secondary physical domain: `apps.ut-s.ocp.fcbint.net`

## Applied design

Each UAT-P Ingress has two exact host rules: the shared floating name and its `ut-p` name. Each UAT-S Ingress has the same shared floating name and its `ut-s` name. This is applied to Schema Registry, Connect, REST Proxy, Control Center, and Kafka MDS.

Ingress certificates use the site-specific hostname as the common name and contain both the site-specific and shared floating hostname in `dnsNames`. All UAT Keyfactor environment annotations are `Non-Prod-UAT`.

The pipeline now validates exact floating and site-specific host rules instead of constructing an `apps.uat-*` domain. Kafka MDS is included in the same validation.

## FCB routing behavior

The shared floating DNS record is external to these manifests. It must point to the active physical site:

- Normal operation: floating UAT CNAME points to UAT-P.
- Failover: Container Platform/DNS changes it to UAT-S.

Both clusters can retain the shared host rule because they are physically separate. DNS determines which router receives traffic.

## Validation completed

- All YAML files parse successfully.
- All 19 inline Bash pipeline scripts pass `bash -n`.
- UAT-P/UAT-S host rules, ports, ingress class, termination, destination CA and TLS secret references validated.
- UAT ingress certificate CNs, SANs, lifetime, renewal window, RSA key and Keyfactor annotations validated.
- No `apps.uat*` hostname or `Non-Prod-QA` annotation remains under either UAT environment.
- No UAT-P physical hostname exists in UAT-S and no UAT-S physical hostname exists in UAT-P.
- Uploaded DEV reference files remain byte-for-byte unchanged.

## Deployment note

Apply the certificate resources before the Ingress resources. Confirm every Certificate is Ready and its Secret exists, then apply the Ingresses. DNS/CNAME ownership remains with the Container Platform/DNS team.
