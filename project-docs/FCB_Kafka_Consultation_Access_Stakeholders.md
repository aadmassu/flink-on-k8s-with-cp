# FCB Kafka Consultation — System Access & Stakeholder Requirements

## Deliverable Areas & Required Access + Stakeholders

| **Workstream** | **Deliverable Area** | **System Access Required** | **Key Stakeholders to Involve** | **Purpose/Context** |
|---|---|---|---|---|
| **1. Architecture & Topology** | Environment-specific cluster topology (prod/non-prod/DR) | Current Kafka cluster configs, AWS console (for AZ/region layout), Terraform/IaC repos | Platform Engineering, Cloud Architect, Kafka Admin (Tushar), IT Operations | Understand current state: existing clusters, AZ distribution, multi-region strategy |
| | Availability zone / region distribution | AWS Console, Network diagrams, CMDB | Network Operations, Infrastructure team, Cloud Architect | Validate AZ failover capability, regional redundancy |
| | Cluster strategy (linking, LOB isolation, sprawl prevention) | Kubernetes manifests, ArgoCD, GitLab/GitHub repos, Kafka broker configs | Container Platforms (Rick), Kafka Admin, Enterprise Architecture, Security | Define cluster consolidation strategy, prevent resource sprawl |
| **2. Resiliency & Failure Scenarios** | Broker-failure, AZ-failure, network-partition scenarios | Production cluster access (read-only), Kafka metrics (Dynatrace), disaster recovery plans | Kafka Admin, SRE/Ops team, Risk Management | Validate current RTO/RPO, test failover procedures |
| | Schema Registry outage handling | SR cluster config, SR metrics, application code samples | Schema Registry owner, Development leads, Application teams | Understand SR dependencies, circuit-breaker patterns |
| | Kafka Connect failure scenarios | KC cluster config, connector inventories, task logs | Kafka Connect admin, Integration team | Assess connector resilience, replay strategies |
| | Consumer failure & back-pressure handling | Consumer group metrics, lag monitoring (Dynatrace), application logs | Application Development teams, Platform team | Understand offset management, rebalancing behavior |
| **3. Network Architecture** | Connectivity & private endpoints | Network diagrams, VPN configs, peering setup, security group rules | Network Operations, Security, Cloud Architect, Firewall team | Validate private connectivity, zero-trust access |
| | Network bandwidth requirements | Network flow data, Dynatrace metrics, traffic projections | Network Ops, Cloud Architect, Capacity Planning | Ensure inter-AZ/region bandwidth headroom |
| **4. Sizing Methodology** | Current event volume & growth projections | Broker metrics (Dynatrace), topic throughput dashboards, business forecasts | Kafka Admin, Product/Business Analysts, Finance (for growth planning) | Baseline current state, validate projections |
| | Message size distribution, retention analysis | Broker storage metrics, topic configs, retention policies | Kafka Admin, Data Architects, Compliance/Legal | Understand storage footprint, regulatory holds |
| | Partition strategy & replication factor | Current topic configs, partition/broker mapping, replication factor analysis | Data Architects, Application teams, Kafka Admin | Validate partition count, leadership distribution |
| | Storage & compute sizing per broker | Infrastructure inventory, broker resource allocation (CPU/mem/disk), utilization trends | Kafka Admin, Infrastructure/SRE, Capacity Planning | Right-size broker hardware, plan upgrades |
| **5. Governance & Standards** | Topic ownership, lifecycle, schema governance | CMDB, topic inventory, change management system, GitOps workflows | Enterprise Architecture, Data Governance, Application teams, Security | Define ownership model, intake/deprecation process |
| | Naming & security standards | Current naming conventions, security policies, compliance requirements | Security team, Data Governance, Compliance/Legal | Establish naming conventions, encryption standards |
| | Access control & data classification | IAM/RBAC systems, data classification framework, audit logs | Security, Identity & Access Management, Compliance | Define role-based access, data sensitivity tiers |
| | Schema compatibility & AsyncAPI integration | Development practices, contract repositories, API gateway configs | Development teams, API Platform team, Integration team | Validate contract-driven approach, schema evolution |
| | CI/CD & Infrastructure as Code | GitLab/GitHub repos, CI/CD pipelines, Terraform/Helm workflows, policy-as-code tools | DevOps, Platform Engineering, Development teams | Assess IaC maturity, policy engine capability |
| | Tenant/consumer onboarding automation | Current onboarding process, automation platform (if any), form/workflow tools | Platform Engineering, Developer Experience, Data Governance | Design paved-path automation, reduce manual work |
| | Automated impact analysis for deployments | Dependency mapping tools, cluster topology tools, change-impact simulators | Kafka Admin, Platform team, DevOps | Define pre-deploy validation, blast-radius checks |
| | Exception handling & approval workflows | Change advisory board (CAB) structure, SNOW/ticketing system, approval rules | Change Management, CAB members, Security | Design escalation paths, exception approval SLAs |
| **6. Observability & Metrics** | Dynatrace integration (broker, topic, consumer metrics) | Dynatrace environment access, metric names, custom event APIs | Monitoring/Observability team, Dynatrace admin, Platform team | Define dashboards, SLIs/SLOs for Kafka health |
| | Operational health metrics | Metrics warehouse, BI tool access | Observability team, Analytics, SRE | Define KPIs: broker lag, rebalance time, failure detection |
| | Governance & compliance metrics | Audit logs, data-lineage tools, compliance reporting platform | Compliance/Audit, Data Governance, Security | Track policy violations, schema evolution, access patterns |

---

## Recommended Access Provisioning Checklist

### **System Access to Request**
- [ ] **AWS Console** (production account, read-only; non-prod, admin if possible)
  - EC2, RDS, VPC, Route53, SNS for alerts
  - VPN/bastion access for SSH into brokers (read-only)
- [ ] **Kubernetes Clusters** (dah-kafka, dah-flink, production/non-prod)
  - Read-only RBAC: `oc get` permissions on all namespaces
  - Helm release inspection
- [ ] **Git/GitLab/GitHub** (Kafka operator repos, application repos, policies)
  - Clone access to all relevant projects
- [ ] **Dynatrace** (production and non-prod)
  - Kafka dashboards, custom metrics, event APIs, trace access
  - API token for exporting metric queries
- [ ] **Kafka Cluster Access** (via bastion/VPN)
  - `kafka-topics.sh --describe` (all topics)
  - `kafka-consumer-groups.sh --describe` (consumer group inspection)
  - Broker config read (`bin/kafka-configs.sh --describe`)
- [ ] **Schema Registry** (read access)
  - API access to list subjects, versions, compatibility levels
- [ ] **Kafka Connect** (inventory & task status)
  - REST API read access
- [ ] **CMDB / Inventory System** (asset tracking, capacity data)
- [ ] **Change Management System** (SNOW or equivalent)
  - Read access to CAB structure, approval workflows, change history
- [ ] **Data Classification & Governance Platform** (if exists)
  - Access to existing classification matrix, DQ policies
- [ ] **Network Diagrams & Security Groups** (read-only)
  - Current state documentation, peering configs
- [ ] **JIRA / Ticketing System** (backlog, roadmap, dependencies)

---

## Recommended Kickoff Attendees

### **Core Team (Mandatory)**
1. **Tushar Patle** — Kafka Admin
   - Current cluster inventory, sizing data, operational constraints
2. **Rick Mulder** — Container Platforms / Infrastructure
   - Kubernetes/OpenShift strategy, cert-manager, networking
3. **Enterprise Architecture Lead** (identify stakeholder)
   - Alignment with FCB-wide standards, strategic objectives
4. **Platform Engineering Lead** (identify stakeholder)
   - Current platform maturity, IaC/CI-CD posture, automation appetite

### **Extended Team (By Workstream)**
- **Network Operations / Cloud Architect** — For topology, multi-region, bandwidth sizing
- **Security & Compliance Lead** — For standards, data classification, access control, audit requirements
- **Development/Application Teams Representatives** (2-3) — For workload patterns, failure tolerance, onboarding experience
- **SRE / Operations** — For failure scenarios, RTO/RPO, monitoring gaps
- **Data Governance / Schema Steward** — For ownership model, lifecycle standards
- **IT Change Management / CAB Chair** — For change/governance workflows
- **Dynatrace Admin / Observability Lead** — For metrics, dashboards, alerting strategy
- **Finance / Capacity Planning** (optional) — For growth projections, investment timeline

### **Recommended Meeting Structure**
| **Phase** | **Audience** | **Duration** | **Outcome** |
|---|---|---|---|
| **Kickoff** | Core team + Extended team | 2 hours | Align on scope, schedule workshops, identify information gaps |
| **Deep-dives** (by workstream) | Core + relevant domain experts | 1.5-2 hours each | Gather current-state details, constraints, pain points |
| **Design Workshops** | Core + architecture/security | 2-3 hours each | Co-create architecture decisions, governance policies |
| **Validation** | Technical leads + implementation teams | 1.5 hours each | Vet designs against operational reality |
| **Playbook Review** | Ops, SRE, on-call rotations | 1.5 hours | Test runbooks, RTO/RPO scenarios |

---

## Notes

- **Lead Time**: Request system access 1-2 weeks before kickoff to resolve approval delays
- **Read-Only Access**: Request minimal privileges; escalate only for testing/validation phases
- **Sensitive Data**: Clarify which metrics/logs require data residency compliance (e.g., PII, regulatory holds)
- **Cross-Team Alignment**: Ensure Enterprise Architecture is looped in early to avoid rework on governance decisions
- **Validation Access**: For scenario testing (broker failure, AZ failover), plan a dedicated maintenance window with ops team sign-off
