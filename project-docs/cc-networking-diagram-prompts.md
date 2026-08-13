# Confluent Cloud Networking — AI Image-Generation Prompts

Untracked working file (gitignored via `project-docs/*`). Holds the 6 AI image-generation prompts for the Confluent Cloud networking diagram series, each reviewed for technical accuracy against the official Confluent Cloud documentation at https://docs.confluent.io/cloud/current/networking/overview.html.

Style follows the Wk2 Wed/Thu visual pattern (see `feedback_ai_image_prompt_style` memory): 16:9 landscape, AWS/Azure/GCP architecture-icon style, branded vendor logos, color-coded trust zones, numbered step strip at bottom, green design-target banner, optional grey Note line.

Each prompt is reviewed for:

- No absolute language ("never", "always", "PROHIBITED", "cannot")
- Distinguishing endpoint-based vs routing-based vs ENI-based mechanisms
- Including DNS as a first-class element (most-missed implementation step)
- Including hybrid reach (Direct Connect / ExpressRoute / Cloud Interconnect / VPN)
- Latency claims softened to match doc wording ("milliseconds to seconds, depending on cluster type")
- IP overlap support matched to the doc's comparison table (not the narrative text where they sometimes disagree)
- Explicit "do NOT render" guardrails against image-gen tool context bleed

Citation policy: anywhere a claim could be challenged in a customer review, the prompt cites or paraphrases the relevant doc section so the reviewer can trace it back.

---

## Diagram 1 — Public vs Private Connectivity Decision

**Filename**: `CC-Networking-1-Public-vs-Private-Decision.png`

```
Create a horizontal architecture diagram titled "1 — Confluent Cloud Networking: Public vs Private Connectivity" with the subtitle "The first fork: choose at cluster provisioning time. Switching networking type later requires creating a new cluster and migrating via cluster linking — not an in-place flip".

Style: AWS/Azure/GCP architecture-icon style with branded vendor logos throughout (AWS orange, Azure blue, GCP red/blue/yellow/green, Confluent red). 16:9 landscape canvas.

Top section — a DECISION DIAMOND in the center labelled "Provisioning-time choice: public or private endpoint?", with two arrows branching left and right.

LEFT path — PINK/CORAL ZONE "Public Connectivity":
  - "Public Internet" tile with a globe icon
  - "Customer App / Producer / Consumer" tile (generic blue with Kafka-client icon) on the customer side, connecting OUT over the public internet to the Confluent Cloud public endpoint
  - Confluent Cloud tile (Confluent red) labelled "Public endpoint: pkc-xxxxx.<region>.<cloud>.confluent.cloud"
    - Annotation: "DNS resolves to Confluent-managed public IPs that change over time — do NOT allowlist by IP. Use hostname-based egress rules."
  - Small green badge: "TLS 1.2+ enforced. Auth required via API keys / OAuth / mTLS."
  - Small badge (neutral, not red): "Cloud edge networking provides network-level protections and traffic filtering."
  - Trade-off callout below:
    "Pros: minimal networking setup; reachable from anywhere a client has internet egress."
    "Cons: surface area is the internet; many regulated organizations require private connectivity for PCI / HIPAA / internal data-classification policy; native Kafka clients have limited forward-proxy support."

RIGHT path — multi-zone "Private Connectivity":
  - Three vendor sub-zones stacked, each rendered with its own cloud-provider color and brand logo. Each lists distinct mechanism CATEGORIES:
    - AWS sub-zone (AWS orange):
      • "Endpoint-based: AWS PrivateLink (inbound + outbound)"
      • "Routing-based: VPC Peering, Transit Gateway"
      • "ENI-based: Private Network Interface (PNI)"
      • "Hybrid reach: AWS Direct Connect (DX) into customer VPC, then any of the above into CC"
    - Azure sub-zone (Azure blue):
      • "Endpoint-based: Azure Private Link"
      • "Routing-based: VNet Peering"
      • "Hybrid reach: Azure ExpressRoute into customer VNet, then any of the above into CC"
    - GCP sub-zone (GCP multi-color):
      • "Endpoint-based: Private Service Connect (PSC)"
      • "Routing-based: VPC Peering"
      • "Hybrid reach: Cloud Interconnect into customer VPC, then PSC or peering into CC"
  - "Customer VPC / VNet" tile (Azure/AWS blue) showing — depending on the mechanism chosen above — either:
      (a) a "Private Connectivity Attachment" (Private Endpoint object for PrivateLink/Private Link/PSC; route table entries for peering/TGW; ENI for PNI)
      (b) a small "Private DNS Zone" tile annotated "DNS resolution is the most-missed step — clients must resolve CC hostnames to the private path, not to public IPs. Configure Private DNS Zones / Route 53 private hosted zones / Cloud DNS private zones with VNet/VPC links."
  - Confluent Cloud Tenant tile (Confluent red) labelled "Private path — not publicly routable. Reachable only via approved private connectivity (PrivateLink / PSC / peering / TGW / PNI), optionally extended from on-prem via Direct Connect / ExpressRoute / Cloud Interconnect / VPN."
  - Green badge: "TLS 1.2+ still enforced; auth via API keys / OAuth / mTLS unchanged. Private connectivity is about TRANSPORT path, not encryption or authentication."
  - Trade-off callout below:
    "Pros: no public internet exposure; satisfies most regulated-workload policies when combined with message-level encryption (e.g. CSFLE); audit-defensible network path."
    "Cons: customer manages DNS, peered/linked networks, route tables, security groups, and per-VPC connectivity. On-prem reaches CC via private hybrid links (Direct Connect / ExpressRoute / Cloud Interconnect / VPN) into a customer-owned VPC/VNet first, then through the chosen private connectivity mechanism. No proxy required for PrivateLink/PSC/PNI; proxy IS required when on-prem reaches CC via VPC peering (per Confluent docs)."

Bottom of canvas — 6 numbered explanation circles (small filled blue circles with white numbers). This strip is the ENTIRE bottom row.
1. The networking type (public or private) is chosen at cluster provisioning time. A cluster cannot be flipped between the two later — switching requires creating a new cluster of the desired type and migrating workloads via cluster linking.
2. Public vs private determines only the network PATH, not whether encryption or authentication are used. Both options enforce TLS 1.2+ end-to-end and require explicit authentication (API key, OAuth, or mTLS).
3. Ports vary by service and cluster type. Common patterns: Kafka listeners on TCP 9092 (native) or 443 (REST), all HTTPS-based services (Schema Registry, Confluent REST API, CLI, Metrics API, Confluent Cloud Console) on TCP 443. Verify against the per-cluster network documentation.
4. Public-endpoint IPs are Confluent-managed and change over time. Allowlisting Confluent Cloud by IP is unsupported — use hostname-based egress rules or move to private connectivity for stable network identity.
5. Public connectivity is generally discouraged for PCI / HIPAA / regulated workloads by most organizational security policies. Confluent's documentation prohibits PCI cardholder data on public connectivity unless message-level encryption (e.g. CSFLE Client-Side Field Level Encryption) is in use AND the cluster is private. Check your organization's compliance posture.
6. Native Kafka clients have limited support for HTTP forward proxies and generally require direct TCP connectivity. If your network requires an explicit forward proxy for egress, prefer the Confluent Cloud REST API (HTTPS) for produce operations.

Bottom GREEN BANNER with checkmark: "Design target: pick public for unregulated dev / sandbox / experiments where speed matters. Pick private for any workload that crosses a compliance line (PCI, HIPAA, internal corporate data classification). The choice is locked for the cluster's lifetime — migration is via cluster linking to a new cluster, not an in-place flip."

Bottom GREY note line: "Serverless services (Flink, Schema Registry, managed connectors) inherit the networking model of the Dedicated Kafka cluster they serve. Choosing public vs private at cluster provisioning time ripples to those services automatically — no separate decision."

REMINDER for the rendering tool: do NOT add any 'Production path / Mirror path' comparison band, no JFrog/Twistlock/ROSA/docker-pull content. This is a single decision diagram with two trade-off panels (public on the left, private on the right) and one numbered step strip at the bottom.
```

**Review notes for Diagram 1**: covered in detail in the user feedback exchange — 20 corrections applied (absolute language softened, "Private Endpoint" generalized to "Private Connectivity Attachment", AWS options split by mechanism category, ExpressRoute / Cloud Interconnect / Direct Connect added, DNS added, PCI language reframed from "PROHIBITED" to "discouraged by organizational policy", on-prem reachability corrected to allow private hybrid links).

---

## Diagram 2 — VPC / VNet Peering with Confluent Cloud

**Filename**: `CC-Networking-2-VPC-VNet-Peering.png`

```
Create a horizontal architecture diagram titled "2 — VPC / VNet Peering with Confluent Cloud" with the subtitle "Direct bidirectional layer-3 peering between customer cloud network and the Confluent Cloud tenant network — point-to-point, non-transitive, IP CIDRs must not overlap".

Style: AWS/Azure/GCP architecture-icon style with branded vendor logos throughout (AWS orange, Azure blue, GCP multi-color, Confluent red). 16:9 landscape canvas. Color-coded zones from left to right: dark grey "On-Premise" (small box with annotation), Azure-blue / AWS-blue / GCP-blue "Customer VPC / VNet" (rendered large), and Confluent-red "Confluent Cloud Tenant Network".

LEFT — On-Premise (dark grey, small box):
  - "On-Prem Data Center" tile with corporate building icon
  - Annotation below: "On-prem cannot reach CC via peering alone (peering is non-transitive). Practical pattern: extend on-prem into the customer VPC/VNet via Direct Connect / ExpressRoute / Cloud Interconnect / VPN, then add a proxy in the customer VPC/VNet to forward Kafka traffic to CC — peering with CC requires a proxy on the customer side when serving on-prem clients (per Confluent docs)."
  - Dashed arrow into the customer VPC/VNet labelled "Direct Connect / ExpressRoute / Cloud Interconnect / VPN"

MIDDLE — Customer VPC/VNet (Azure-blue / AWS-blue zone, rendered LARGE):
  - Outer rectangle "Customer VPC / VNet — 10.10.0.0/16"
  - Three small chips at the top of this zone (one per cloud): "AWS VPC Peering", "Azure VNet Peering", "GCP VPC Peering" — annotation "same architectural pattern, three vendor names"
  - "Customer App / Producer / Consumer" tile inside the VPC (generic blue with Kafka-client icon)
  - Optional "Proxy VM" tile in the VPC (rendered only if on-prem reach is part of the design) — labelled "Required for on-prem-to-CC traffic over peering"
  - "Private DNS / Route 53 private hosted zone / Cloud DNS private zone" tile inside the VPC — annotation "must be configured to resolve CC hostnames to the private IPs in the CC Network. Without this, clients resolve to public IPs and bypass the peering silently."
  - SOLID bidirectional arrow from the Customer App → out to the Confluent Cloud tenant on the right, labelled "Direct L3 routing — both directions"
  - Red callout badge: "IP address ranges must NOT overlap between customer VPC/VNet and CC Network — peering won't activate if they do (per the doc comparison table)"

RIGHT — Confluent Cloud Tenant Network (Confluent red):
  - "Confluent Cloud Network" outer rounded rectangle labelled "Single tenant, regional, spread across 3 zones"
  - Inside: three tiles stacked
    - "Dedicated Kafka Cluster" (Confluent red) — annotation "VPC/VNet peering supported on Dedicated only. Enterprise, Freight, Basic, and Standard cluster types do NOT support peering — see Diagram 3 (PrivateLink) or Diagram 5 (PNI) for those."
    - "Managed Connectors / ksqlDB" (Confluent red) — annotation "Managed connectors running in this CC Network can only reach resources in the directly-peered VPC. Other VPCs in your organization need their own separate peering or a Transit Gateway pattern (Diagram 4)."
    - "Flink + Schema Registry" (Confluent red with small badge) — annotation "AWS supports Flink and Schema Registry over peering; Azure and GCP support varies — verify against the per-cloud support matrix"

CROSS-CUTTING — peering connection rendered as a thick double-headed arrow between the two VPCs, with a label box on the arrow itself: "VPC/VNet Peering Connection — non-transitive; only the two directly-peered networks see each other"

Bottom of canvas — 6 numbered explanation circles (small filled blue circles with white numbers). This strip is the ENTIRE bottom row.
1. Peering is bidirectional and non-transitive. The customer VPC reaches CC; CC managed connectors can reach back into the peered VPC. Neither side can use the other as a transit hop to reach a third network.
2. IP address ranges must not overlap. Plan CIDR allocations BEFORE provisioning the CC Network. Once provisioned, the CC Network's CIDR cannot be changed.
3. Managed connectors running in the CC Network can only reach resources in the directly-peered VPC. To reach a different customer VPC, set up a separate peering, or move to Transit Gateway (Diagram 4) for hub-and-spoke reach.
4. Latency over peering ranges from milliseconds to seconds depending on cluster type (per the doc comparison table). Same-region traffic stays inside the cloud provider's regional backbone. Inter-AZ traffic incurs the cloud provider's standard inter-AZ data transfer charge.
5. Peering is supported only with Dedicated cluster types on AWS, Azure, and GCP. Enterprise, Freight, Basic, and Standard cluster types do NOT support peering — use PrivateLink/PSC (Diagram 3) or PNI (Diagram 5) for those.
6. DNS resolution is the customer's responsibility. Each peered VPC must be configured to resolve CC hostnames to the private IPs in the CC Network. Misconfigured DNS is the most common reason peering 'works' at the network layer but clients still resolve to public IPs and bypass the peering.

Bottom GREEN BANNER with checkmark: "Design target: VPC/VNet Peering when you have one or two VPCs in the same region as your Dedicated CC cluster, non-overlapping CIDRs, and no on-prem connectivity requirement. Otherwise reach for PrivateLink, Transit Gateway, or PNI."

Bottom GREY note line: "Confluent Cloud supports a one-way migration path from VPC Peering to AWS Transit Gateway (Diagram 4) as organizations outgrow the simpler pattern. No migration path back from Transit Gateway to peering."

REMINDER for the rendering tool: do NOT add any 'Production path / Mirror path' band, no JFrog/Twistlock/ROSA/docker-pull content. Single architectural pattern, three vendor names.
```

**Review notes for Diagram 2**: fixed the "on-prem can't connect DIRECTLY" wording (now correctly describes on-prem path: hybrid link → customer VPC → proxy → peering → CC, per the doc). Latency claim softened from "single-digit ms" to "milliseconds to seconds, depending on cluster type" (doc wording). DNS added as a first-class tile. CIDR overlap claim now cites the doc comparison table explicitly.

---

## Diagram 3 — PrivateLink Family (AWS PrivateLink / Azure Private Link / GCP Private Service Connect)

**Filename**: `CC-Networking-3-PrivateLink-Family.png`

```
Create a horizontal architecture diagram titled "3 — PrivateLink Family: AWS PrivateLink / Azure Private Link / GCP Private Service Connect" with the subtitle "Endpoint-based private connectivity — customer creates a Private Endpoint in their VPC/VNet that forwards traffic over the cloud provider's backbone to Confluent Cloud. INBOUND pattern shown here (customer → CC); a separate Outbound pattern exists for CC managed connectors reaching customer private resources".

Style: AWS/Azure/GCP architecture-icon style with branded vendor logos throughout (AWS orange, Azure blue, GCP multi-color, Confluent red). 16:9 landscape canvas. Color-coded zones from left to right: dark grey "On-Premise" (small), Azure-blue / AWS-blue / GCP-blue "Customer VPC / VNet" (rendered LARGE), light cyan narrow band "Cloud Provider Backbone", and Confluent-red "Confluent Cloud Tenant".

LEFT — On-Premise (dark grey, small box):
  - "On-Prem Data Center" tile
  - Dashed arrow into the customer VPC/VNet labelled "Direct Connect / ExpressRoute / Cloud Interconnect / VPN"
  - Annotation: "On-prem reaches CC via hybrid link into the customer VPC/VNet, then through the Private Endpoint — no proxy required on the PrivateLink path (per Confluent docs)."

MIDDLE — Customer VPC/VNet (rendered LARGE, most of the wiring lives here):
  - Outer rectangle "Customer VPC / VNet — 10.10.0.0/16"
  - Three subnets shown inside:
    - "Workload Subnet 10.10.1.0/24" containing a "Customer App / Producer / Consumer" tile (generic blue with Kafka-client icon)
    - "Private Endpoint Subnet 10.10.2.0/28" containing a "Private Endpoint / Interface Endpoint / PSC Endpoint" tile (Azure cyan / AWS orange / GCP blue with the respective Private Link icon) labelled "CC Private Endpoint — 10.10.2.x"
    - "Private DNS Zone" tile floating in the VNet zone (Azure cyan / Route 53 / Cloud DNS icon) labelled "privatelink.<region>.<cloud>.confluent.cloud" with a small A-record table showing 3 rows mapping Kafka bootstrap, Schema Registry, and Flink REST hostnames to the Private Endpoint IP
  - Dotted line labelled "VNet Link / Route 53 association / Cloud DNS peering" from the Private DNS Zone to the outer VPC/VNet rectangle, with annotation "links the Private DNS Zone to this VPC/VNet so all subnets resolve CC hostnames to the PE IP. This is the most-missed implementation step."
  - A "Network Security Group / Security Group / VPC Firewall Rule" shield wrapping the Private Endpoint, with annotation "allowlist: Workload Subnet → Private Endpoint on TCP/9092 (Kafka native) or 443 (Kafka REST + SR + Flink REST), depending on service"
  - DASHED arrow from the Customer App → Private DNS Zone labelled "1. DNS lookup: CC hostname → PE IP"
  - SOLID arrow from the Customer App → Private Endpoint labelled "2. Kafka/HTTPS connection to resolved PE IP"

CYAN BAND — Cloud Provider Backbone:
  - Centered tile "AWS PrivateLink / Azure Private Link / GCP Private Service Connect" with the three vendor logos in a row
  - Dashed bidirectional line from Private Endpoint → Confluent Cloud Private Link Service
  - Label above the dashed line: "Traffic carried over the cloud provider's backbone — does not traverse the public internet"

RIGHT — Confluent Cloud Tenant (Confluent red):
  - "Private Link Service / VPC Endpoint Service / PSC Service Attachment" tile on the left edge (Confluent red + cloud-provider cyan badge) labelled "CC-side endpoint accepting customer PE connections"
  - Inside: three stacked tiles
    - "Kafka Cluster" (Confluent red) annotated "Cluster support varies by cloud — Dedicated + Enterprise on AWS and Azure, Dedicated on GCP. Verify against the per-cloud support matrix."
    - "Schema Registry" (Confluent red) annotated "served via the same PE on AWS and Azure"
    - "Flink Compute Pool" (Confluent red with Flink squirrel logo) annotated "served via the same PE on AWS and Azure"

CROSS-CUTTING annotations (small badges placed near the middle):
  - "Direction: UNIDIRECTIONAL (inbound) — customer dials CC. The reverse pattern (Outbound PrivateLink, CC dials customer DB) is a SEPARATE design — customer publishes a Private Link Service, CC has a Private Endpoint. Don't conflate the two."
  - "IP overlap: SUPPORTED — customer VPC/VNet CIDR and CC Network CIDR can overlap. The PE has its own IP in the customer subnet, so no routed path between the two networks exists."

Bottom of canvas — 7 numbered explanation circles (small filled blue circles with white numbers). This strip is the ENTIRE bottom row.
1. The customer creates a Private Endpoint (PE) in their VPC/VNet. The PE gets an IP from the customer's own subnet — not from Confluent Cloud's network. This is why IP overlap between customer and CC CIDRs is supported.
2. The customer creates a Private DNS Zone (privatelink.<region>.<cloud>.confluent.cloud) and links it to their VPC/VNet. Without this DNS step, clients resolve CC hostnames to public IPs and bypass the PE silently. This is the most-missed implementation step.
3. DNS resolution flow: client → Private DNS Zone → returns the PE IP from the customer subnet → client connects to the PE → PE forwards over the cloud provider backbone.
4. The PE forwards traffic over the cloud provider's backbone (AWS PrivateLink / Azure Private Link / GCP PSC infrastructure) to the Confluent Cloud Private Link Service. The customer does not see CC's actual network topology.
5. NSG/Security Group/VPC Firewall Rule on the PE allowlists which subnets in the customer VPC can reach it. OAuth2/TLS 1.2+ still enforced end-to-end — Private Link is a transport private path, not a replacement for authentication.
6. Cluster support varies by cloud. AWS PrivateLink works with Dedicated and Enterprise (serverless) clusters. Azure Private Link works with Dedicated and Enterprise. GCP PSC works with Dedicated. Verify against the per-cloud support matrix in the Confluent docs before designing.
7. Cost shape: medium — hourly endpoint fee + per-GB data processing charge on both produce and consume traffic. Higher than peering, lower than Transit Gateway. Latency ranges from milliseconds to seconds depending on cluster type (per doc comparison table).

Bottom GREEN BANNER with checkmark: "Design target: PrivateLink family when you need many customer VPCs to reach a single CC tenant, when IP overlap is unavoidable, when strict data-exfiltration protection is required, or when service-level granularity matters more than network-level isolation. The simplest pattern that scales."

Bottom GREY note line: "Outbound PrivateLink (CC managed connector dials INTO customer's private database) is a separate, less-known pattern — Customer publishes a Private Link Service, CC has a Private Endpoint. Don't conflate with the Inbound PrivateLink pattern shown here, where Customer has the PE."

REMINDER for the rendering tool: do NOT add any 'Production path / Mirror path' band, no JFrog/Twistlock/ROSA/docker-pull content. Single architectural pattern, three vendor names.
```

**Review notes for Diagram 3**: clarified that this is INBOUND PrivateLink (vs Outbound which is a separate design). Latency softened from "single-digit ms" to "milliseconds to seconds". On-prem reachability explicitly described as hybrid-link + PE (no proxy required for PrivateLink). DNS already first-class in the original — retained and clarified as "most-missed step". Per-cloud cluster support matrix referenced rather than hardcoded.

---

## Diagram 4 — AWS Transit Gateway with Confluent Cloud

**Filename**: `CC-Networking-4-Transit-Gateway-AWS.png`

```
Create a horizontal architecture diagram titled "4 — AWS Transit Gateway with Confluent Cloud" with the subtitle "Hub-and-spoke transit hub for multi-VPC and hybrid topologies — transitive routing, on-prem reachable via Direct Connect, AWS-only".

Style: AWS architecture-icon style with branded vendor logos throughout (AWS orange dominant, Confluent red). 16:9 landscape canvas. Color-coded zones: dark grey "On-Premise Data Center", AWS-orange "AWS Account / Region", and Confluent-red "Confluent Cloud Tenant".

LEFT — On-Premise (dark grey zone):
  - "On-Prem Data Center" tile with corporate building icon
  - "Customer Router" tile
  - Arrow labelled "AWS Direct Connect (DX) — preferred — or AWS Site-to-Site VPN" going right into the AWS zone, terminating at a "Direct Connect Gateway" tile

MIDDLE — AWS Account / Region (AWS orange zone, rendered LARGE — the hub-and-spoke is the point of this diagram):
  - Center of the zone: a large "AWS Transit Gateway (TGW)" tile (AWS orange with TGW icon) labelled "the hub"
  - Around the TGW, four spokes radiating outward (wheel layout):
    - SPOKE 1 (top-left): "VPC A — 10.1.0.0/16" with Workload A inside
    - SPOKE 2 (top-right): "VPC B — 10.2.0.0/16" with Workload B inside
    - SPOKE 3 (bottom-left): "VPC C — 10.3.0.0/16" with Workload C inside
    - SPOKE 4 (bottom-right): "Direct Connect Gateway" tile (AWS orange) feeding from the on-prem connection
  - Each spoke connects to the TGW with a labelled arrow "TGW attachment"
  - "Private DNS / Route 53 private hosted zone" tile somewhere in the AWS zone, annotated "shared across attached VPCs via Route 53 association — resolves CC hostnames to the CC Network IP range routed through TGW"
  - Annotation badge near TGW: "TGW attachment to Confluent Cloud requires opening an AWS support ticket on Confluent's side — initial setup has lead time (per Confluent docs)"

RIGHT — Confluent Cloud Tenant (Confluent red):
  - "Confluent Cloud Network" outer rounded rectangle
  - Inside: stacked tiles
    - "Dedicated Kafka Cluster" (Confluent red) annotated "Transit Gateway supported on Dedicated only. Enterprise/Freight/Basic/Standard cluster types do NOT support TGW — use PrivateLink (Diagram 3) for those."
    - "Managed Connectors / ksqlDB"
    - "Flink + Schema Registry" annotated "AWS supports Flink and Schema Registry over TGW"
  - A thick double-headed arrow from the TGW → Confluent Cloud, labelled "TGW attachment on the Confluent side (Confluent provisions; customer initiates via support request)"

CROSS-CUTTING annotations (small badges placed mid-canvas):
  - "Transitive routing: VPC A ↔ TGW ↔ VPC B ↔ TGW ↔ on-prem ↔ TGW ↔ Confluent Cloud — all reachable through one hub"
  - "Direction: bidirectional. CC managed connectors can reach resources in ANY attached VPC or on-prem (via DX), not just one peered VPC."
  - "IP overlap: NOT supported on standard TGW attachments per the Confluent docs comparison table. Confluent's descriptive text suggests TGW the technology can handle overlapping CIDRs with advanced routing — verify with your Confluent SE before assuming overlap will work in your specific design."

Bottom of canvas — 6 numbered explanation circles (small filled blue circles with white numbers). This strip is the ENTIRE bottom row.
1. The Transit Gateway is a regional hub that owns the routing table. Attach customer VPCs, attach a Direct Connect Gateway for on-prem, and attach Confluent Cloud's TGW on the Confluent side — every spoke can reach every other spoke through the hub.
2. Transitive routing is the defining feature. With VPC peering you would need N*(N-1)/2 peering links between N VPCs; with TGW you need N attachments. Operationally simpler at scale.
3. On-premises reachability comes for free once Direct Connect (or Site-to-Site VPN) is attached to the same TGW. This is the canonical pattern when your data center needs to reach Confluent Cloud through a hub.
4. Cluster support: Dedicated clusters only. Enterprise, Freight, Basic, and Standard do not support Transit Gateway — use PrivateLink (Diagram 3) for those cluster types.
5. Cost shape: highest of the AWS private options. TGW charges an hourly attachment fee per attached VPC plus a per-GB data processing charge for traffic that crosses the gateway, on both produce and consume sides. Budget accordingly when volume is large. Latency ranges from milliseconds to seconds depending on cluster type.
6. Migration path: Confluent Cloud supports a one-way migration from VPC Peering (Diagram 2) to Transit Gateway as your organization grows. Plan to move when you cross approximately 3-4 VPCs needing CC access, or when on-prem connectivity becomes a requirement.

Bottom GREEN BANNER with checkmark: "Design target: AWS Transit Gateway when you have 3+ VPCs needing Confluent Cloud access, when on-prem connectivity is part of the requirement, or when transitive routing simplifies an existing hub-and-spoke design."

Bottom GREY note line: "Azure analogue: Azure Virtual WAN with a hub VNet — Confluent Cloud does NOT have a direct Virtual WAN integration; use Private Link (Diagram 3) for Azure hub-and-spoke. GCP analogue: Cloud VPN in a hub-and-spoke topology with PSC into CC."

REMINDER for the rendering tool: do NOT add any 'Production path / Mirror path' band, no JFrog/Twistlock/ROSA/docker-pull content. Single architectural pattern, AWS-specific.
```

**Review notes for Diagram 4**: latency softened to doc wording. CIDR overlap claim made nuanced (the doc's comparison table says "not supported" but the narrative text says TGW can handle overlap — diagram now flags the ambiguity and tells the reader to verify with Confluent SE rather than asserting one way). DNS added as an inset tile. TGW provisioning lead time called out per the doc.

---

## Diagram 5 — AWS Private Network Interface (PNI) for Confluent Cloud

**Filename**: `CC-Networking-5-Private-Network-Interface-AWS.png`

```
Create a horizontal architecture diagram titled "5 — AWS Private Network Interface (PNI) for Confluent Cloud" with the subtitle "ENI-style attachment of Confluent Cloud brokers directly into the customer VPC — high throughput, low cost when same-AZ aligned, customer-managed security groups, AWS-only".

Style: AWS architecture-icon style with branded vendor logos throughout (AWS orange dominant, Confluent red, ENI icon). 16:9 landscape canvas. Color-coded zones: AWS-orange "Customer AWS VPC" (rendered LARGE — most of the diagram lives here), Confluent-red narrow band on the right "Confluent Cloud Control Plane".

LEFT — Customer AWS VPC (AWS-orange zone, rendered LARGE):
  - Outer rectangle "Customer VPC — 10.10.0.0/16"
  - Inside, three Availability Zone columns labelled "AZ-1", "AZ-2", "AZ-3"
  - In each AZ:
    - "Workload Subnet" containing a "Customer App / Producer / Consumer" tile aligned to that AZ
    - "PNI Subnet" containing an "ENI — Confluent Cloud Broker N" tile (AWS orange ENI icon with Confluent red badge) — three ENIs total, one per AZ
    - Annotation: "ENI lives in the customer subnet but represents a CC broker. Looks like a normal AWS network interface to your security tools — same VPC flow logs, same security group enforcement, same audit posture."
  - Solid arrows from each Workload App → its same-AZ ENI labelled "Kafka traffic — same-AZ produce/consume is $0 (no inter-AZ data transfer cost). Inter-AZ produce/consume incurs the standard AWS inter-AZ rate."
  - A "Customer Security Group" shield wrapping all three ENIs, with annotation "customer-managed security group — same policies, same tooling, same audit posture as native AWS resources. Granular interface-level management."
  - "Private DNS / Route 53 private hosted zone" tile inside the VPC, annotated "resolves CC hostnames to the ENI IPs in the customer subnet. Same DNS-as-most-missed-step concern as PrivateLink — without this, clients bypass the ENIs."

RIGHT — Confluent Cloud Control Plane (Confluent red, narrow band):
  - "Confluent Cloud Control Plane" tile (Confluent red) connecting to each of the three ENIs via a dashed line labelled "CC manages broker lifecycle through control plane only — data path stays in customer VPC"
  - Annotation: "Data plane never leaves the customer VPC. CC reaches in via the ENIs for management traffic; you reach broker-side via Kafka protocol through the ENIs."

CROSS-CUTTING annotations (small badges placed in the middle):
  - "Cluster support: Enterprise clusters and Freight clusters (PNI on these shapes supports ingress connectivity to Kafka only — per Confluent docs footnote). Dedicated also supports PNI as a higher-throughput alternative to peering, labelled 'PNI Dedicated'. Flink and Schema Registry attach via the same PNI on Enterprise and Dedicated."
  - "Direction: bidirectional for management. Data-plane direction depends on cluster type (Freight/Enterprise ingress-only for Kafka, Dedicated bidirectional). Verify against the per-cluster support matrix in the Confluent docs."
  - "Hub-and-spoke: PNI enables hub-and-spoke architectures similar to TGW (Diagram 4) — multiple customer VPCs reach the ENIs via VPC peering or Transit Gateway within the customer's AWS account."
  - "IP overlap: SUPPORTED — ENIs use IPs from the customer subnet, no routed path between customer VPC and CC network."

Bottom of canvas — 7 numbered explanation circles (small filled blue circles with white numbers). This strip is the ENTIRE bottom row.
1. Confluent Cloud provisions one Elastic Network Interface (ENI) per broker, in your VPC, in your subnets, across your Availability Zones. The brokers themselves run on Confluent's account, but their network face lives in yours.
2. Same-AZ produce/consume is $0 — no inter-AZ data transfer charge — when the client and the ENI are aligned in the same AZ. This is the cost-optimal pattern for high-throughput Kafka workloads on AWS.
3. Security is customer-managed: same VPC security groups, same VPC flow logs, same audit posture as if the brokers were running on EC2 in your account. No bespoke 'Confluent network' admin model to learn.
4. PNI is the direct-attach equivalent of PrivateLink but with no per-GB data processing fee — and with the throughput characteristics of an ENI (limited only by the instance type, not by a managed service layer in between).
5. Cluster support: Enterprise clusters and Freight clusters support PNI with Kafka ingress only (per Confluent docs footnote). Dedicated supports PNI as a higher-throughput alternative to peering. Latency ranges from milliseconds to seconds depending on cluster type.
6. Hybrid reach: if the VPC where the ENIs land is already attached to a Transit Gateway with Direct Connect, on-prem can reach the ENIs through that existing TGW topology — no new Confluent-side networking needed.
7. DNS resolution still required. Configure a Private DNS Zone or Route 53 private hosted zone to resolve CC hostnames to the ENI IPs in the customer subnet. Same most-missed-implementation-step concern as the other private connectivity patterns.

Bottom GREEN BANNER with checkmark: "Design target: AWS PNI for the highest-throughput, lowest-cost private connectivity on AWS — especially when produce and consume can be aligned in the same AZ as the broker ENIs. PNI changes the cost shape of high-throughput Kafka workloads on Confluent Cloud."

Bottom GREY note line: "PNI is AWS-only today. Azure and GCP do not have a directly-equivalent pattern — closest analogues are Azure Private Link (Diagram 3) and GCP Private Service Connect (Diagram 3 again — same architectural pattern under a third vendor name)."

REMINDER for the rendering tool: do NOT add any 'Production path / Mirror path' band, no JFrog/Twistlock/ROSA/docker-pull content. Single architectural pattern, AWS-specific.
```

**Review notes for Diagram 5**: clarified that PNI on Freight/Enterprise is ingress-only for Kafka (per doc footnote). Latency softened. DNS added explicitly as a step. Hub-and-spoke note retained but clarified that it uses customer-side VPC peering or TGW, not CC-provided routing.

---

## Diagram 6 — The Confluent Cloud Network Abstraction

**Filename**: `CC-Networking-6-CC-Network-Abstraction.png`

```
Create a horizontal architecture diagram titled "6 — The Confluent Cloud Network Abstraction" with the subtitle "A CC Network is the single-tenant networking container — it holds Dedicated clusters and serverless services, lives in one environment and one region, spans three zones, and idle networks are garbage-collected after 60 days".

Style: AWS/Azure/GCP architecture-icon style with branded vendor logos throughout (AWS orange, Azure blue, GCP multi-color, Confluent red). 16:9 landscape canvas. Color-coded zones: AWS-orange/Azure-blue/GCP-multi outer "Cloud Provider Region (one of AWS / Azure / GCP)", Confluent-red inner "Confluent Cloud Environment", and the centerpiece — a thick-bordered "Confluent Cloud Network" rounded rectangle.

CENTER — Confluent Cloud Network (the centerpiece, thick rounded rectangle, Confluent red):
  - At the top, three AZ badges in a row: "AZ-1", "AZ-2", "AZ-3" — annotation "spread across 3 zones for HA. AWS and GCP support customer zone selection; Azure does not (per Confluent docs)."
  - Inside the rectangle, content split into TWO ROWS:
    - TOP ROW — "Hosted in this CC Network" (the resources the network was designed to hold):
      - "Dedicated Kafka Cluster A" tile (Confluent red) — annotation "cluster cannot be moved to a different network after provisioning. Migration between networks requires creating a new cluster and cluster-linking from the old one."
      - "Dedicated Kafka Cluster B" tile (Confluent red) — annotation "multiple Dedicated clusters can share one CC Network"
      - "Managed Connectors" tile (Confluent red)
      - "ksqlDB Cluster" tile (Confluent red)
    - BOTTOM ROW — "Optionally attached" (rendered in lighter ink to indicate conditional attachment):
      - "Apache Flink Compute Pool" tile (Confluent red with Flink squirrel) — annotation "attaches under specific conditions per the per-cloud per-cluster support matrix in the Confluent docs"
      - "Schema Registry" tile (Confluent red) — same annotation

LEFT — Environment context (Confluent red zone wrapping the CC Network):
  - "Confluent Cloud Environment" outer label — annotation "a CC Network belongs to exactly ONE environment; you cannot move a network across environments"

RIGHT — Lifecycle states (vertical stack of three small tiles outside the CC Network rectangle):
  - "PROVISIONED" green tile — "Has at least one Dedicated cluster / connector / ksqlDB cluster attached"
  - "IDLE" yellow tile — "No physical resources attached; warning shows in Console with countdown to deletion"
  - "DELETED" red tile — "Auto-deleted after 60 days idle; email reminders sent before deletion"
  - Arrows from PROVISIONED → IDLE → DELETED labelled with the lifecycle transition. A reverse arrow from IDLE → PROVISIONED labelled "attach a resource to reset the idle timer."

BOTTOM-LEFT of the canvas — RBAC roles allowed to provision/delete networks (small inset, NOT part of the main numbered strip):
  - "NetworkAdmin" badge — "all environments in the organization"
  - "OrganizationAdmin" badge — "all environments in the organization"
  - "EnvironmentAdmin" badge — "assigned environments only"

CROSS-CUTTING annotations placed in the white space around the CC Network rectangle:
  - "Private connectivity options that attach to a CC Network: AWS PrivateLink, VPC Peering, Transit Gateway, PNI · Azure Private Link, VNet Peering · GCP PSC, VPC Peering. Refer to Diagrams 2-5 for the specific architectural pattern of each."
  - "Created and deleted via Confluent Cloud Console, CC Network REST API, or `confluent network` CLI commands."

Bottom of canvas — 6 numbered explanation circles (small filled blue circles with white numbers). This strip is the ENTIRE bottom row.
1. A Confluent Cloud Network is the single-tenant container that holds Dedicated Kafka clusters, ksqlDB, managed connectors, and (under specific conditions) Flink and Schema Registry. It is the abstraction that private connectivity (peering / PrivateLink / TGW / PNI) attaches to.
2. A network is cloud-provider-specific (AWS, Azure, or GCP), regional (one region per network), and spread across three Availability Zones for high availability. AWS and GCP support customer zone selection at provisioning time; Azure does not.
3. A network belongs to exactly ONE Confluent Cloud Environment. You cannot move a network between environments. A cluster cannot be moved between networks — migration requires creating a new cluster and cluster-linking from the old one. Plan the topology before provisioning.
4. RBAC: NetworkAdmin and OrganizationAdmin can create and delete networks anywhere in the organization. EnvironmentAdmin is scoped to their assigned environments only.
5. A network is 'idle' when no physical resources are attached (no Dedicated cluster, no ksqlDB cluster, no managed connector). The Console flags idle networks with a warning icon; hover to see the countdown to deletion. The REST API and `confluent network` CLI also expose the idle state.
6. Idle networks are auto-deleted after 60 days. Email reminders are sent before deletion. To preserve an idle network, attach a resource to it. Otherwise expect to recreate the network when you next need it.

Bottom GREEN BANNER with checkmark: "Design target: treat the CC Network as the long-lived networking primitive — provision once per environment per region, attach clusters / connectors / ksqlDB as workloads materialize, and let idle ones garbage-collect themselves after 60 days. Do not create speculative networks 'just in case' — the GC clock will clean them up."

Bottom GREY note line: "Check idle state via the Console (Network management tab → For dedicated clusters → State column), the CC REST API, or `confluent network list`. Catch the warning before the email reminders arrive — recreating a network has lead time."

REMINDER for the rendering tool: do NOT add any 'Production path / Mirror path' band, no JFrog/Twistlock/ROSA/docker-pull content. This is the abstraction/lifecycle diagram, not a connectivity-pattern diagram.
```

**Review notes for Diagram 6**: clarified the cluster-migration path (cluster-linking, not in-place move). Zone selection AWS/GCP-only call-out preserved (already accurate per doc). RBAC roles preserved (already accurate per doc). Idle/deletion lifecycle wording tightened.

---

## What to verify before rendering

For all six diagrams, check against the doc one more time:

1. **Per-cloud per-cluster support matrix** — the doc has explicit support tables for AWS, Azure, GCP (the AWS one is fully shown; Azure and GCP are referenced as "see the per-cloud support matrix"). Anywhere I wrote "see the per-cloud support matrix in the Confluent docs", the actual rendered diagram should ideally cite the specific row.
2. **Latency wording** — the doc says "milliseconds to seconds, depending on cluster type" for ALL options including peering and PNI. This is unusually wide. If you want to assert tighter latency (e.g. single-digit ms for same-region peering), get that confirmed with a Confluent SE first.
3. **TGW + IP overlap** — the comparison table says "Not supported"; the narrative says "can handle overlapping CIDR blocks". The diagram now flags this ambiguity. Resolve with Confluent SE before asserting one way.
4. **PNI cluster-type direction footnote** — the doc says "PNI connectivity for Freight and Enterprise clusters only support ingress connectivity to Kafka". Make sure the rendered diagram puts this footnote in lighter ink so it doesn't dominate the visual.
