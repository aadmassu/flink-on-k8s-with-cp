# Deliverable 2: Current-State Assessment — System Access Provisioning
## Deployment-Agnostic Access Checklist
**Purpose:** Enable comprehensive assessment of FCB's existing streaming & integration landscape (Kafka, MuleSoft, TIBCO) for consolidation analysis  
**Scope:** Inventory, configuration review, metrics, and architectural assessment across infrastructure and application layers

---

## SECTION A: KAFKA ECOSYSTEM ACCESS

### Kafka Cluster Infrastructure & Monitoring
- [ ] **Kafka Cluster SSH Access** (all clusters: read-only or via bastion)
  - Environment: dev, qa, uat, production, disaster recovery (as applicable)
  - Scope: List brokers, read broker configs (`server.properties`), inspect log directories
  - Command-line tools: `kafka-broker-api-versions.sh`, `kafka-configs.sh --describe`, disk usage analysis

- [ ] **Kafka Metrics & Monitoring Platform** (Dynatrace, Prometheus, Splunk, or internal platform)
  - Broker-level: CPU, memory, disk, network I/O
  - Topic-level: message rate (msgs/sec), bytes in/out, partition leadership, replication lag
  - Consumer-level: consumer group lag, rebalancing frequency, offset progression
  - Query examples: peak throughput, storage growth trend, rebalance incident frequency
  - Retention: historical data (30+ days recommended for trend analysis)

- [ ] **Kafka Admin Portal / UI** (if applicable)
  - Topic management interface
  - Consumer group monitoring dashboard
  - Partition leader distribution visualization
  - Broker health/status

- [ ] **Kafka Logs & Event Archives**
  - Broker logs: errors, warnings (last 30 days)
  - Controller logs: leader election history
  - Operational incident records: outages, degradations, failure scenarios

---

### Schema Registry & Data Contracts
- [ ] **Schema Registry API Access**
  - List all subjects and versions
  - Retrieve schema metadata (compatibility mode, usage count)
  - Schema evolution history per subject
  - API endpoint: `GET /subjects`, `GET /subjects/{subject}/versions`

- [ ] **Schema Lineage & Usage Analytics** (if available)
  - Which topics use which schemas
  - Producer/consumer code that references schemas
  - Schema adoption timeline (when introduced, deprecated)

---

### Kafka Connect & Integration Connectors
- [ ] **Kafka Connect REST API** (if deployed)
  - List all connectors, tasks, and their status
  - Connector configuration (source/sink types, scaling, failure modes)
  - Task-level failure logs
  - API endpoint: `GET /connectors`, `GET /connectors/{name}/status`

- [ ] **Kafka Connect Cluster Metrics**
  - Connector scaling/parallelism: number of tasks per connector
  - Failure & retry patterns: failed task restarts, recovery behavior
  - Latency: end-to-end data movement (source → Kafka → sink)

---

### Stream Processing Frameworks (if deployed)
- [ ] **Flink Cluster Access** (if applicable)
  - Job manager UI or REST API
  - Running jobs, job history
  - Task parallelism, resource allocation (CPU, memory)
  - Checkpoint/savepoint logs
  - Performance metrics: processing latency, watermark progression

- [ ] **ksqlDB / Kafka Streams Metrics** (if applicable)
  - Query status and topology
  - State store size and changelog topic usage
  - Query processing latency

---

## SECTION B: MULESOFT ECOSYSTEM ACCESS

### MuleSoft Deployment & Architecture
- [ ] **MuleSoft Instance Type & Deployment Details**
  - Confirmation: CloudHub deployment OR Runtime Fabric (RTF) OR on-premises
  - Version, patch level
  - Number of workers/instances, resource allocation (vCores, memory)
  - Clusters (if RTF): worker distribution, HA setup

- [ ] **MuleSoft Runtime Manager UI** (read-only access)
  - Deployed applications: list, status, version history
  - Application properties: inbound/outbound endpoints, listener ports

- [ ] **MuleSoft Application Code Repository** (Git or internal)
  - Flows, connectors, and data mappings
  - Transformation logic (DataWeave scripts, Java/Groovy code)
  - Connection configurations (database, API, messaging credentials)
  - Dependency versions (MuleSoft connector packs)

- [ ] **MuleSoft Connector Inventory**
  - Which connectors are in use: Database (JDBC), JMS, Email, HTTP, FTP, etc.
  - Custom connectors (if any)
  - Polling intervals, batch sizes, retry logic

---

### MuleSoft Integration Patterns & Flows
- [ ] **Point-to-Point Integrations** (read-only)
  - Application flow diagrams or documentation
  - Producer/consumer systems (source → MuleSoft → target)
  - Transformation/enrichment logic
  - Error handling and dead-letter patterns

- [ ] **Hub-and-Spoke Orchestration** (if applicable)
  - Central MuleSoft orchestration flows
  - Sub-flow invocations and compensation logic
  - Routing rules and conditional logic

- [ ] **API Management** (if MuleSoft API Manager used)
  - API contracts and versioning
  - Rate limiting, throttling policies
  - API usage analytics

---

### MuleSoft Monitoring & Observability
- [ ] **MuleSoft Observability Platform** (Anypoint Monitoring or APM tool)
  - Application metrics: throughput, latency, error rate
  - Flow/component execution timeline
  - Message volume per integration (daily, peak)
  - Failure incidents and troubleshooting logs

- [ ] **MuleSoft Logs**
  - Application logs (errors, warnings, info level)
  - Integration execution logs (last 30 days)
  - Incident history: failed deployments, connector failures, message processing errors

---

### MuleSoft Performance & Scaling
- [ ] **Load Profile Analysis**
  - Average message rate (msgs/sec) per application
  - Peak throughput and spike patterns
  - Message size distribution
  - Processing latency: end-to-end, per-component

- [ ] **Resource Utilization** (CloudHub or RTF)
  - CPU/memory consumption trends
  - Connector library memory footprint
  - Database connection pool status
  - Scaling history: auto-scaling triggers, manual scale-ups

---

## SECTION C: TIBCO ECOSYSTEM ACCESS

### TIBCO Deployment & Architecture
- [ ] **TIBCO Instance Details**
  - TIBCO product suite in use: EMS (Enterprise Message Service), ActiveMatrix, BW (BusinessWorks), etc.
  - Version, patch level
  - Deployment model: on-premises, virtual machines, containers
  - Hardware: servers, storage, network topology

- [ ] **TIBCO EMS (if used)** or **TIBCO Messaging Broker**
  - Broker configuration: queues, topics, destinations
  - Queue depth, retention policies
  - Replication/HA setup (if applicable)
  - Broker logs and alert history

- [ ] **TIBCO BusinessWorks** (if used)
  - Process design: flows, service calls, transformations
  - Repository access: process definitions, libraries, shared modules
  - Activity profiles: JDBC, HTTP, messaging, file operations
  - Condition evaluation and routing logic

- [ ] **TIBCO Plug-in Inventory**
  - Adapters: database, JMS, SOAP, REST, file systems, custom
  - Data transformation: XSLT, custom functions
  - Error handling and retry policies

---

### TIBCO Integration Patterns & Flows
- [ ] **Message-Driven Processes**
  - EMS queue/topic subscribers: which processes consume which destinations
  - Message correlation and state management
  - Asynchronous request-reply patterns

- [ ] **Orchestration & Complex Event Processing**
  - Multi-step workflows across systems
  - Event correlation and aggregation
  - Time-window processing and windowed aggregations

- [ ] **Adapter Configurations**
  - Database adapters: query definitions, polling intervals, batch sizes, transaction handling
  - File adapters: polling directories, file formats (CSV, XML, fixed-width), transformation
  - Web service adapters: WSDL contracts, message mapping

---

### TIBCO Monitoring & Observability
- [ ] **TIBCO Admin Console / Management UI** (read-only)
  - Process instances: running, suspended, completed
  - Activity logs and tracing
  - Error logs and failure reasons

- [ ] **TIBCO Metrics & Performance Data**
  - Message throughput per queue/topic (msgs/sec)
  - Process execution time and latency percentiles
  - EMS queue depth and message aging
  - Failed process instances and error rate

- [ ] **TIBCO Logs**
  - Engine logs: process executions, activity details
  - Adapter logs: connection errors, transformation failures
  - Connector logs: message delivery status (last 30 days)

---

### TIBCO Performance & Scaling
- [ ] **Load Profile Analysis**
  - Message rate per queue/topic
  - Concurrency: number of parallel process instances
  - Batch sizes and throughput limits (QOS configurations)
  - Message size distribution

- [ ] **Resource Utilization**
  - Server CPU/memory per engine instance
  - EMS broker persistence (disk I/O)
  - Database connection pool utilization
  - Network bandwidth for inter-broker replication (if applicable)

- [ ] **Scaling & Clustering**
  - TIBCO cluster configuration (if HA deployed)
  - Load balancing and failover behavior
  - Growth trend: increased message volume requiring scale-ups

---

## SECTION D: ENTERPRISE INFRASTRUCTURE & CROSS-CUTTING STACKS

### Network & Connectivity
- [ ] **Network Topology Diagrams**
  - Current layout: on-premises, cloud, hybrid
  - Network zones: DMZ, internal, database tier
  - Firewall rules and ingress/egress policies for integration systems
  - VPN, bastion, or jump-host access

- [ ] **Network Bandwidth & Capacity**
  - Bandwidth allocation to Kafka, MuleSoft, TIBCO clusters
  - Inter-system connectivity: latency, packet loss (if measurable)
  - Network bottleneck analysis: any saturation incidents

- [ ] **DNS & Service Discovery**
  - Hostnames for Kafka brokers, MuleSoft runtimes, TIBCO engines
  - Load balancer configuration (round-robin, sticky sessions, health checks)

---

### Identity & Access Management (IAM) / RBAC
- [ ] **IAM System** (Active Directory, Okta, custom)
  - User roles and groups accessing MuleSoft, TIBCO, Kafka
  - Application service accounts (credentials management)
  - Audit trail: access grants and revocations

- [ ] **Kafka Authorization Model**
  - ACLs or RBAC: who can produce/consume which topics
  - Access control gaps: overly permissive, missing controls
  - Audit logs: failed auth attempts

- [ ] **MuleSoft Authorization**
  - Application ownership: who develops/deploys which flows
  - Connector credential management: how secrets are stored/rotated
  - API Management access controls (if applicable)

- [ ] **TIBCO Authorization**
  - Process/adapter ownership and developer roles
  - EMS broker queue access controls
  - Audit trail for admin operations

---

### Secrets & Credentials Management
- [ ] **Current Secrets Vault / Management System**
  - Tool: CyberArk, HashiCorp Vault, cloud-native KMS, file-based, or hardcoded
  - Scope: database credentials, API keys, SSL certificates, encryption keys
  - Rotation policy: manual or automated
  - Compliance: encryption, audit trail, access logs

- [ ] **MuleSoft Credential Handling**
  - Secure properties files, vaults, or MuleSoft Secrets Manager
  - Database connection passwords, API credentials
  - Connector configurations: encrypted or plaintext

- [ ] **TIBCO Credential Handling**
  - EMS broker authentication credentials
  - Database adapter credentials
  - SSL certificates for secure connections

- [ ] **Kafka Broker & Client Credentials**
  - SASL/SSL configuration (if enforced)
  - Keystore/truststore locations
  - Certificate rotation process

---

### Database Connectivity & Data Sources
- [ ] **Connected Databases & Data Sources**
  - Type: SQL Server, Oracle, PostgreSQL, MySQL, etc.
  - Instance inventory: dev, test, production
  - Access credentials (read from IAM system above)
  - Schema information: tables involved in Kafka, MuleSoft, TIBCO integrations

- [ ] **Data Movement Patterns**
  - Which databases are producers to Kafka/MuleSoft/TIBCO (CDC, scheduled queries)
  - Which are consumers (sink integrations)
  - ETL/ELT frequency: batch, real-time, scheduled
  - Data volume per integration (rows/sec, GB/day)

- [ ] **Database Monitoring**
  - Query performance metrics (if applicable to integrations)
  - Replication lag (for CDC scenarios)
  - Connection pool utilization

---

### Observability & Monitoring Platform
- [ ] **Enterprise Monitoring & Alerting System**
  - Tool: Dynatrace, New Relic, Splunk, Datadog, Prometheus, or custom
  - Kafka metrics: already captured above
  - MuleSoft metrics: throughput, latency, error rate
  - TIBCO metrics: message rate, process latency, queue depth
  - TIBCO EMS: broker memory, queue persistence performance
  - Cross-system dashboards (if exist)

- [ ] **Logging & Log Aggregation**
  - Centralized log platform: Splunk, ELK, Datadog, Grafana Loki, etc.
  - Log sources: Kafka broker logs, MuleSoft app logs, TIBCO engine logs, connector logs
  - Retention: 30+ days recommended for trend analysis
  - Query capability: grep, aggregate, build custom searches

- [ ] **Alerting & Incident Management**
  - Alert rules: latency thresholds, error rate spikes, queue depth warnings
  - Incident history: last 12 months (outages, degradations, failures)
  - Root cause analysis: logs and metrics correlated for past incidents

---

### Deployment & CI/CD Automation
- [ ] **MuleSoft Deployment Pipeline**
  - Git repository: branching strategy, CI/CD tool (Jenkins, GitLab CI, Azure DevOps, etc.)
  - Deployment frequency: how often do MuleSoft apps update
  - Deployment process: approval gates, rollback procedures
  - Deployment failures: incident logs

- [ ] **TIBCO Deployment Pipeline**
  - Process/adapter code repository
  - CI/CD workflow: build, test, deploy stages
  - Deployment frequency and process
  - Rollback capability and incident history

- [ ] **Kafka Administration & GitOps** (if applicable)
  - Topic/schema management: manual, Terraform, helm, or custom GitOps
  - Cluster configuration: version upgrades, broker scaling, storage expansion
  - Change approval process (CAB, SNOW)

---

### Documentation & Architecture Artifacts
- [ ] **Integration Architecture Documentation**
  - System integration diagrams (MuleSoft, TIBCO, Kafka ecosystems)
  - Data flow maps: sources, systems, sinks
  - Dependency graphs: which applications depend on which integration systems

- [ ] **Business Process Documentation**
  - Process ownership: which business unit owns which integration
  - Use cases and business outcomes
  - SLAs: availability, latency, compliance requirements

- [ ] **Operational Runbooks**
  - Playbooks for common incidents (MuleSoft app failure, TIBCO queue depth spike, Kafka rebalance)
  - Escalation paths and on-call procedures
  - Troubleshooting guides per system

- [ ] **Known Issues & Technical Debt Log**
  - Current blockers: scaling limits, performance issues, operational pain points
  - Deferred refactoring: coupling, complexity, maintainability concerns
  - Vendor product gaps or workarounds

---

### Compliance, Audit & Governance
- [ ] **Data Classification & Sensitivity Labels**
  - How FCB classifies data: public, internal, confidential, restricted
  - PII tagging, financial data sensitivity levels
  - Regulatory holds or retention requirements

- [ ] **Compliance & Audit Trail**
  - Who accessed/modified data in MuleSoft, TIBCO, Kafka (IAM logs)
  - Data lineage: which systems touched the data
  - Audit logs (last 12+ months recommended)

- [ ] **Change Management Process**
  - SNOW (ServiceNow) or ticketing system for changes
  - Change Advisory Board (CAB) approval gates
  - Change impact assessment: who is affected by integration changes
  - Change history: last 90 days for pattern analysis

---

## SECTION E: OPTIONAL / ADVANCED ACCESS (if timeline permits)

- [ ] **Direct Code Review Access** (MuleSoft & TIBCO application repos)
  - Identifies code smells: synchronous orchestration instead of async, overly complex mappings
  - Reveals hidden dependencies and temporal coupling

- [ ] **Load Testing / Performance Lab Access** (with explicit approval)
  - Permission to run non-destructive load testing against integration systems
  - Enables baseline measurement of Kafka alternatives vs. current throughput

- [ ] **Disaster Recovery Runbook & Testing Records**
  - RTO/RPO definitions for Kafka, MuleSoft, TIBCO
  - DR drill results: actual recovery times achieved
  - Failover procedure documentation

---

## SUMMARY: ACCESS REQUEST GROUPS

### **Tier 1 — Essential (High Priority)**
```
Kafka: Cluster SSH, Metrics, Logs, Broker Admin
MuleSoft: Runtime Manager UI, Git repos, Monitoring, Logs
TIBCO: Admin Console, Logs, Metrics, Configuration access
Enterprise: Network diagrams, Database list, IAM system, Secrets vault info, Monitoring platform
```

### **Tier 2 — Important (Medium Priority)**
```
Kafka: Schema Registry, Kafka Connect, Stream Processing (if deployed)
MuleSoft: Code deep-dive, Connector inventory, API Manager (if used)
TIBCO: Engine metrics, Queue/topic details, Business process documentation
Enterprise: Change management system (SNOW), Compliance audit logs, Performance baselines
```

### **Tier 3 — Nice-to-Have (Lower Priority, Optional)**
```
Direct cluster load testing, DR runbook access, Architecture governance board minutes
```

---

## QUESTIONS FOR FCB STAKEHOLDERS

1. **On-Premises vs. Cloud:** Is MuleSoft deployed on-premises, CloudHub, or Runtime Fabric? (Determines network access strategy)
2. **Database Scope:** Which operational databases are integrated with MuleSoft/TIBCO? (Scopes data movement analysis)
3. **Compliance Requirements:** Are there audit/governance restrictions on external vendor access to integration configs? (May require proxy access via FCB staff)
4. **Incident Access:** Can we review the last 12 months of integration incidents (MuleSoft failures, TIBCO bottlenecks, Kafka issues)?
5. **Consolidation Drivers:** What are FCB's pain points today? (Scaling limits, operational overhead, feature gaps, cost)
6. **Target Timeline:** Is this a greenfield replacement or gradual migration of existing integrations? (Informs assessment focus)

