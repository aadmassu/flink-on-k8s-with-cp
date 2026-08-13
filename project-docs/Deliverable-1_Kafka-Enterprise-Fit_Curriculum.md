# Deliverable 1: Foundational Alignment — Kafka & Confluent
## Curriculum Outline: "Where Kafka Fits in Enterprise Architecture"
**Duration:** 16 hours (recorded, vendor-neutral education module)  
**Audience:** Architecture, Engineering, Operations, Business stakeholders  
**Purpose:** Establish shared baseline understanding of event streaming, Kafka capabilities, and enterprise applicability

---

## MODULE 1: FOUNDATIONS OF EVENT STREAMING (2.5 hours)

### 1.1 Messaging Paradigms in Enterprise Architecture (45 min)
**What's In Scope:**
- Request-response (synchronous) vs. publish-subscribe (asynchronous) patterns
- Point-to-point messaging (queues) vs. broadcast messaging (topics)
- Event vs. command vs. fact semantics
- Decoupling producers from consumers: temporal, technological, organizational

**What's Out of Scope:**
- HTTP APIs, webhooks, gRPC (separate architectural patterns)
- Real-time data warehousing / analytical pipelines

**Questions for Phoutty:**
- Does FCB currently distinguish between event-driven and request-response architecture in their standards?
- Are there existing architectural patterns (SOA, microservices, ESB) we should reference?

---

### 1.2 Event Streaming Fundamentals (60 min)
**What's In Scope:**
- Events: immutable facts, timestamps, schema
- Topics: event categories, partitions for scalability and ordering guarantees
- Producers: sources of events (applications, sensors, data platforms)
- Consumers: subscribers, consumer groups, offset management
- Brokers: storage, replication, availability
- Schemas: contract between producer and consumer, schema evolution

**Hands-On Visualization:**
- Event flow diagram: multi-producer → topic → multi-consumer
- Partition leadership & replica assignment
- Consumer group rebalancing scenario

**What's Out of Scope:**
- Detailed Kafka protocol/codec internals
- JVM tuning, memory management
- Kafka security implementation (separate workstream)

**Questions for Phoutty:**
- Should we include examples from FCB's business domains (payments, compliance, customer data)?
- Are there existing event taxonomies or data dictionaries we should align with?

---

### 1.3 Kafka vs. Traditional Alternatives (45 min)
**What's In Scope:**
- **Traditional Message Queues (JMS, MQ Series, RabbitMQ):**
  - Point-to-point primary use case
  - Message consumption destructive by default
  - Not optimized for replayability or multi-consumer patterns
  
- **Enterprise Service Bus (Mulesoft, TIBCO, custom integrations):**
  - Centralized routing and transformation
  - Message format translation
  - Orchestration and compensation logic
  - Coupling at integration layer
  
- **Batch Data Movement (Informatica, scripts, scheduled ETL):**
  - High latency (hours/days)
  - Fixed schedule, not reactive
  - Not suitable for real-time analytics or decision-making
  
- **Kafka's Differentiators:**
  - Append-only log for audit trail & replay
  - Multiple independent consumers, each at own pace
  - Topic retention enables time-travel
  - Scalable partition model (not a bottleneck)

**Visual Comparison:**
- Side-by-side latency, throughput, use-case fit table
- Integration architecture: ESB-centric vs. event-stream-centric

**What's Out of Scope:**
- Product-by-product feature comparison (RabbitMQ vs. Kafka vs. AWS SQS)
- Cost analysis or TCO models (deferred to commercial evaluation)

**Questions for Phoutty:**
- Should we include a diagram of FCB's current integration footprint (MS, TIBCO) and how Kafka would fit?
- Are there pain points with existing systems (JMS, MQ Series) that should be highlighted?

---

## MODULE 2: KAFKA ECOSYSTEM & ENTERPRISE CAPABILITIES (3.5 hours)

### 2.1 Schema Registry & Data Contracts (45 min)
**What's In Scope:**
- Schema as contract: producer commits to shape; consumer enforces compatibility
- Schema evolution: backwards, forwards, full compatibility
- Multi-version management: Schema Registry as source of truth
- Schema-driven code generation (Avro, Protobuf, JSON Schema)
- AsyncAPI: machine-readable contracts for Kafka topics

**Real-World Example:**
- Payment event schema evolution: add optional field without breaking consumers
- Versioning strategy for regulated data (compliance, audit trail)

**What's Out of Scope:**
- Schema Registry administration / operations (moved to governance workstream)
- Deep dive into Avro vs. Protobuf syntax

**Questions for Phoutty:**
- Does FCB have a data lineage or data catalog platform already (e.g., Apache Atlas, Collibra, Informatica)?
- Are schema contracts part of FCB's governance model today?

---

### 2.2 Kafka Connect & Streaming Data Integration (45 min)
**What's In Scope:**
- Kafka Connect architecture: source connectors (DB → Kafka), sink connectors (Kafka → DB/API/warehouse)
- Built-in connectors (JDBC, S3, Elastic, MongoDB, etc.)
- Custom connector development
- Scaling & task distribution
- Failure & recovery semantics (exactly-once, at-least-once)
- Comparison to ETL: lower latency, higher frequency, reactive

**Use Case Example:**
- CDC (Change Data Capture) from operational DB → Kafka topic
- Kafka topic → Data warehouse (real-time copy)
- Event stream → external SaaS (analytics, compliance audit)

**What's Out of Scope:**
- Connector-specific configuration deep dives
- Custom connector development workshop

**Questions for Phoutty:**
- What are FCB's current data integration patterns? Are they batch-heavy, real-time, hybrid?
- Are there system-of-record sources (operational DBs, core banking systems) that need to stream events?
- Are there compliance/audit requirements driving change-data-capture needs?

---

### 2.3 Stream Processing Frameworks (Flink, ksqlDB, Kafka Streams) (45 min)
**What's In Scope:**
- Stateless transformations (filter, map, enrich) on event streams
- Stateful operations (aggregate, join, windowing) on multiple streams
- Scalability: partition parallelism, horizontal scaling
- Failure recovery & exactly-once semantics
- When to pick Kafka Streams (embedded, Java/Scala) vs. Flink (distributed, polyglot) vs. ksqlDB (SQL)
- Real-time analytics, anomaly detection, complex event processing

**Example Workflows:**
- Real-time fraud detection: join payment stream with historical patterns
- Customer 360: merge customer data from multiple sources, update in real-time
- Operational alerting: detect SLA violations or service degradation from event stream

**What's Out of Scope:**
- Detailed operator semantics, state backend storage
- Flink/ksqlDB operator deployments (moved to infrastructure workstream)

**Questions for Phoutty:**
- What are FCB's current real-time analytics & alerting gaps?
- Are there business use cases (compliance monitoring, fraud prevention, customer insights) that could benefit from stream processing?
- Do they use any stream processing frameworks today (Spark Streaming, custom solutions)?

---

### 2.4 Stream Governance: Policy, Lineage, Observability (45 min)
**What's In Scope:**
- Topic governance: ownership, lifecycle (creation → deprecation), SLA enforcement
- Metadata management: topic classification, data sensitivity levels, PII tagging
- Access control: who can produce/consume, audit trail
- Data quality & observability: latency, completeness, drift monitoring
- Regulatory alignment: GDPR, PCI, HIPAA data handling in streaming context
- Integration with CMDB, data catalog, policy engines

**Policy Examples:**
- Sensitive data (PII, financial) must be encrypted, limited consumer access, short retention
- Critical topics (payment streams) require min replication factor 3, SLA monitoring
- New topics require schema approval before production deployment

**What's Out of Scope:**
- Hands-on governance platform configuration
- Deep security implementation (separate workstream)

**Questions for Phoutty:**
- Does FCB have a data governance office or data steward role?
- What are FCB's current data classification & compliance requirements?
- How are data lineage and impact analysis tracked today?

---

## MODULE 3: KAFKA IN FINANCIAL SERVICES (2 hours)

### 3.1 Regulated Environment Compliance (45 min)
**What's In Scope:**
- Financial services compliance drivers: regulations (SOX, GLBA, CFTC, AML), internal audit, risk management
- Immutable audit trail: Kafka append-only log, compliance with regulatory hold requirements
- Data residency & encryption: at-rest, in-transit, key management
- Consumer access patterns: application identity, fine-grained permissions
- Monitoring & alerting: regulatory event detection, anomaly flagging
- Disaster recovery & business continuity: multi-site replication, RTO/RPO targets

**Financial Services Use Cases:**
- Payment event streaming with regulatory audit trail
- Real-time sanctions screening (AML/OFAC)
- Trade event reconstruction (CFTC reconstruction rule)
- Customer data synchronization (PCI compliance)

**What's Out of Scope:**
- Detailed compliance program design (handled by Risk/Compliance)
- Specific regulatory interpretations

**Questions for Phoutty:**
- What are FCB's top 3 regulatory drivers for streaming architecture?
- Are there existing compliance frameworks (audit trails, retention policies, access logs) that must be preserved?
- What are current blockers to event-driven architecture adoption due to compliance?

---

### 3.2 Reference Adoption Patterns in Financial Services (45 min)
**What's In Scope:**
- **Tier 1 Banks:** Multi-region event platform, 1000s of topics, cross-division consolidation
- **Regional Banks:** Core systems integration (payments, lending, deposits), real-time risk analytics
- **Fintech:** Customer engagement event streaming, fraud detection, compliance monitoring
- **Common Success Pattern:** Greenfield stream processor (low-risk, measurable ROI) → Core system CDC → Cross-enterprise event backbone

**Anti-Patterns to Avoid:**
- "Kafka as database": misuse as primary data store without proper retention strategy
- "Kafka as queue": under-utilizing topic replayability and multi-consumer capability
- "Data lake dump": streaming everything without governance or classification
- "Centralized ESB replacement": over-coupling producers/consumers through orchestration

**What's Out of Scope:**
- Customer case study details (confidentiality)
- Competitive product positioning

**Questions for Phoutty:**
- Where does FCB see themselves on the adoption journey (greenfield vs. core system integration vs. enterprise backbone)?
- What are the biggest organizational/cultural blockers to event-driven architecture?
- Are there peer institutions whose architectures FCB should learn from?

---

## MODULE 4: ENTERPRISE ARCHITECTURE ALIGNMENT (2 hours)

### 4.1 Event Streaming Principles & Architecture Decision Framework (60 min)
**What's In Scope:**
- When to use event streaming vs. APIs, batch, RPC
- Bounded contexts and team ownership (Domain-Driven Design lens)
- Coupling & decoupling tradeoffs: loose coupling vs. observability/debugging complexity
- Topic design patterns: domain event topics, integration topics, data stream topics
- Producer/consumer contract: who owns what, versioning agreements
- Event naming and taxonomy alignment with FCB business domains

**Architecture Principles:**
- *Immutability:* Events are facts, not mutable commands
- *Asynchonicity:* Producers should not wait for consumers
- *Observability:* Event stream is audit trail; must be queryable
- *Autonomy:* Consumer pace independent of producer

**Decision Framework Questions:**
- Is this a broadcast (one producer, many consumers) or point-to-point (1:1) interaction?
- Do consumers need to reply or just update their local state?
- Is event ordering per-partition sufficient, or do we need global ordering?
- What's the retention requirement (audit trail, compliance, replayability)?

**What's Out of Scope:**
- Deep architectural refactoring of FCB systems (handled in workstream 3)
- Organizational structure / team ownership mapping (handled in workstream 4)

**Questions for Phoutty:**
- Does FCB have an enterprise architecture framework (TOGAF, custom)? Should we align with it?
- Are there architectural principles or anti-patterns FCB wants to enforce on streaming?
- How does FCB currently make architecture decisions? Board? Committees?

---

### 4.2 Building an Event-Driven Enterprise: Roadmap Fundamentals (60 min)
**What's In Scope:**
- Maturity model: Event streaming readiness assessment (people, process, technology)
- Phased approach: proof of concept → pilot → production backbone
- Critical success factors: sponsorship, skill building, tooling, governance
- ROI drivers: time-to-market, real-time insights, operational efficiency
- Cultural shift: from request-response to event-reactive mindset

**Roadmap Considerations:**
- Skills gap: Java/Scala developers know Kafka; Python/Go/Node engineers may not
- Organizational readiness: siloed teams → cross-functional event producers/consumers
- Technology debt: legacy systems must emit/consume events; bridge technologies
- Governance maturity: centralized policy engine, self-service onboarding, audit automation

**What's Out of Scope:**
- FCB's specific roadmap planning (handled in workstream 3)
- Multi-year investment planning and resource allocation

**Questions for Phoutty:**
- What's FCB's appetite for organizational change alongside technical implementation?
- Are there specific business outcomes (faster time-to-market, risk reduction, cost savings) driving the engagement?
- What's the expected timeline for transitioning from current systems (MS, TIBCO) to Kafka backbone?

---

## DELIVERY FORMAT & INTERACTION MODEL

### Video Modules
- 8 videos, ~2 hours each
- Recorded (allows async consumption by busy stakeholders)
- Slides + whiteboard diagrams + screen recordings + real-world examples
- Vendor-neutral; no Confluent-specific features mentioned until workstream 3 (if applicable)

### Interactive Components
- **Pre-Module Questionnaires:** Stakeholders pre-test knowledge; helps calibrate depth
- **Knowledge Checks:** Post-module quizzes to ensure comprehension
- **Glossary & Reference:** One-pager on terms (topic, partition, consumer group, etc.)
- **Discussion Forums:** Async Q&A; facilitator (Ayu) responds within 48h

### Optional Live Sessions (if Phoutty approves)
- 2-hour live Q&A kickoff (intro to modules, set expectations)
- 1.5-hour live office hours halfway through (address questions, clarify concepts)
- 2-hour wrap-up discussion (applicability to FCB, transition to workstream 2)

---

## SCOPE DECISIONS FOR PHOUTTY

### **APPROVE / INCLUDE:**
- [ ] Event streaming fundamentals (module 1)
- [ ] Kafka vs. queues, ESB, batch (module 1.3)
- [ ] Schema Registry & data contracts (module 2.1)
- [ ] Kafka Connect basics (module 2.2)
- [ ] Stream processing overview: Flink/ksqlDB/Kafka Streams (module 2.3)
- [ ] Stream governance & observability (module 2.4)
- [ ] Compliance in financial services (module 3.1)
- [ ] Reference patterns: bank adoption journeys (module 3.2)
- [ ] Architecture alignment & principles (module 4.1)
- [ ] Maturity model & roadmap thinking (module 4.2)

### **DEFER / OUT OF SCOPE:**
- [ ] Kafka security & encryption implementation (→ workstream 5)
- [ ] Hands-on Kafka installation & configuration (→ workstream 3)
- [ ] FCB's specific cluster topology design (→ workstream 3)
- [ ] Governance policy codification (→ workstream 4)
- [ ] Sizing & capacity planning (→ workstream 3)
- [ ] Detailed cost/TCO analysis (→ commercial discussion)
- [ ] Hands-on labs / interactive sandbox (too time-intensive for 16 hours)

### **QUESTIONS FOR PHOUTTY:**
1. **Target Audience Depth:** Should we aim for business stakeholders (executive summary level) or technical deep-dive? Propose: **mix**—foundation-level for all, technical examples for engineering.
2. **Financial Services Focus:** How much of the 16 hours should focus on regulated compliance vs. general architecture? Propose: **30%** (module 3 + weave compliance into other modules).
3. **Current System Context:** Should we reference FCB's existing MuleSoft/TIBCO integrations, or keep purely vendor-neutral? Propose: **vendor-neutral in module 1-4; explicit FCB context in workstream 2 discovery**.
4. **Interactive vs. Recorded:** Pure recorded videos or include live Q&A/workshops? Propose: **recorded core modules + optional live Q&A + async forums**.
5. **Success Metric:** How will FCB measure whether the module was effective? Propose: **post-module quiz (70%+ pass rate) + stakeholder confidence survey + downstream engagement in workstream 2**.

