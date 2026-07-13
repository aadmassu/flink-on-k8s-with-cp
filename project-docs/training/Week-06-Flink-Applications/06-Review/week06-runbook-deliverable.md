# Week 6 — Runbook Deliverable Template — Personal Master Runbook (final)

Submit at end of week as `deliverables/<you>/personal-master-runbook.md`.

This is the bootcamp's final artifact. 10 pages, structured around the Friday capstone diagram.

## Structure — one page per layer

### Page 1: Kafka Topic (source + sink)

- **What breaks**: broker unavailable, ACL denies produce/consume, retention wraps around before consumer catches up
- **How to detect**: broker health metrics, `kafka-consumer-groups` lag, producer/consumer client logs
- **How to fix**: broker restart (Week 4), ACL update via ConfluentRolebinding (Week 4 Tue), retention config change (Week 5 or Kafka admin work)

### Page 2: Kafka Client / Source Operator

- **What breaks**: OAuth token expired, deserializer mismatch, backpressure
- **How to detect**: source operator log with `Bearer` / `Invalid Token`; `numLateRecords` metric; UI backpressure indicator
- **How to fix**: OAuth token refresh (automatic), rolebinding update for new client-ID (Week 4 Tue), sink parallelism increase

### Page 3: Flink Operators (Map / KeyBy / Window / Aggregate / Sink)

- **What breaks**: exception in user code, key skew, state grew unboundedly
- **How to detect**: TM logs with the operator's class name; UI shows one instance at 100% CPU; disk usage climbing on one TM
- **How to fix**: hotfix in code + savepoint upgrade (Week 6 Fri), better key distribution, state TTL (Week 6 Wed)

### Page 4: Checkpoint Coordinator

- **What breaks**: checkpoint decline (operator timeout), S3 write failure, alignment blocked
- **How to detect**: Checkpoints tab in UI shows failures; JM log has `Checkpoint N declined`
- **How to fix**: increase checkpoint timeout, resolve S3 access issue, switch to unaligned checkpoints if latency critical

### Page 5: JobManager

- **What breaks**: HA lease can't be acquired, JM crash + no standby, config error
- **How to detect**: `status.jobStatus.state` stuck; JM Pod restarts; operator log
- **How to fix**: fix HA ConfigMap RBAC, restart JM Pod, fix CR config

### Page 6: TaskManagers

- **What breaks**: OOM, disk full (RocksDB), lost from JM (network)
- **How to detect**: TM Pod restarts, OOM in Pod events, disk usage metric
- **How to fix**: increase memory / disk, tune RocksDB, network policy check

### Page 7: Flink Kubernetes Operator

- **What breaks**: reconcile loop stuck, RBAC insufficient, CR schema error
- **How to detect**: operator log has repeated errors on one CR
- **How to fix**: adjust operator RBAC (Container Platforms), fix CR YAML

### Page 8: Kubernetes

- **What breaks**: Pod stuck Pending, NetworkPolicy blocking, quota exhausted
- **How to detect**: `oc describe pod` shows events with the reason
- **How to fix**: capacity ticket (Container Platforms), NetworkPolicy update, ResourceQuota increase (Container Platforms)

### Page 9: PKI / TLS / OAuth

- **What breaks**: cert expired, trust bundle missing CA, OAuth token subject not in rolebindings
- **How to detect**: `bad_certificate` in operator TLS handshake, `Invalid Token : User Identity not found` in MDS log
- **How to fix**: cert-manager reissue (or manual), rolebinding fix (Week 4 Tue), OAuth client refresh

### Page 10: NetApp S3 + Artifactory

- **What breaks**: S3 endpoint unreachable, bucket policy revoked, JAR 404
- **How to detect**: checkpoint failures pile up, JAR download log lines in JM
- **How to fix**: FCB storage team ticket, Artifactory release process

---

## Personal notes section

Anywhere your 6 weeks of on-hands experience diverges from this template — record it. This is *your* runbook, informed by what you've seen at FCB. Update it every time you learn something new on-call.
