# DEV CFK migration resource budget

This package is sized against namespace `dah-flink-dev` ResourceQuota
`compute-resources` captured on 2026-08-15.

## Persistent storage

| Workload | Replicas/PVCs | Capacity each | Total |
|---|---:|---:|---:|
| Kafka brokers | 3 | 300 Gi | 900 Gi |
| KRaft controllers | 3 | 25 Gi | 75 Gi |
| Control Center state | 1 | 100 Gi | 100 Gi |
| Control Center Prometheus | 1 | 100 Gi | 100 Gi |
| **CFK total** | 8 | | **1,175 Gi** |
| Namespace quota | | | 1,272 Gi |
| **Remaining quota** | | | **97 Gi** |

All persistent claims use the dedicated `kafka` StorageClass
(`csi.vsphere.vmware.com`, `Immediate`, `Retain`, expansion enabled).
The Prometheus claim is pre-created because the installed CFK 3.2 CRD does
not expose a nested StorageClass field and the cluster has no default class.

## CFK compute requests and limits

| Workload | Replicas | CPU request each | CPU limit each | Memory request each | Memory limit each |
|---|---:|---:|---:|---:|---:|
| Kafka | 3 | 1.25 | 2.5 | 3 Gi | 6 Gi |
| KRaft | 3 | 1 | 2 | 2 Gi | 3 Gi |
| Schema Registry | 2 | 0.25 | 0.75 | 768 Mi | 1.5 Gi |
| Connect | 2 | 0.375 | 0.75 | 1 Gi | 2 Gi |
| REST Proxy | 1 | 0.125 | 0.375 | 512 Mi | 1 Gi |
| Control Center | 1 | 1.25 | 2.5 | 3 Gi | 6 Gi |
| Prometheus | 1 | 0.375 | 1.25 | 1 Gi | 3 Gi |
| Alertmanager | 1 | 0.1 | 0.5 | 512 Mi | 1 Gi |
| **CFK total** | | **9.85** | **21.125** | **23.5 Gi** | **45 Gi** |

The pipeline dynamically subtracts currently deployed CFK pods/PVCs from
ResourceQuota usage, adds this desired footprint, and refuses deployment unless
at least 2 requested CPU cores, 6 CPU limit cores, 8 Gi requested memory,
16 Gi limit memory, and 50 Gi storage remain for Flink and operations.
