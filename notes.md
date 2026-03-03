Project Overview
This is a GitOps-based deployment system for running Confluent Platform + Apache Flink on Kubernetes, managed by Argo CD across 4 environments (dev, qa, stg, prd) in AWS US East 2.

Two Main Directories
gitops-config/ — "The entry point"
This is where Argo CD starts. It contains ApplicationSet manifests organized by region and environment:


gitops-config/
└── aws-us-east-2/
    ├── dev/
    ├── qa/
    ├── stg/
    └── prd/
Each environment has 5 ApplicationSets — one per component:ß

cert-manager-application-set.yaml
confluent-operator-application-set.yaml
confluent-flink-operator-application-set.yaml
confluent-flink-application-set.yaml
confluent-platform-application-set.yaml
These ApplicationSets tell Argo CD what to deploy — Helm-based operators reference values.yaml files in apps/ via the `$values/` multi-source pattern, while manifest-based components reference manifests/ directories directly.

apps/ — "The actual deployments"
This is what gets deployed. Each component has per-environment configs:

Component	What it is	Config style
argocd/	Argo CD itself (self-managed)	Helm values
cert-manager/	TLS certificate automation	Helm values
confluent-operator/	CFK operator for Kafka platform CRDs	Helm values
confluent-flink-operator/	Flink Kubernetes operator	Helm values
confluent-flink/	Confluent Manager for Flink (CMF)	Raw manifests
confluent-platform/	The full Kafka platform	Raw manifests (Kafka, KRaft, Connect, Schema Registry, ksqlDB, Control Center)
The Flow

gitops-config/aws-us-east-2/dev/  ──ApplicationSets──►  Argo CD Applications
                                                              │
                                                    ┌─────────┴─────────┐
                                                    │                   │
                                        Helm chart + values.yaml    Git path + manifests/
                                         (operators, cert-manager)   (Confluent Platform, Flink manager)
ApplicationSets in gitops-config/ generate Argo CD Application resources
Helm-based operators use $values/ multi-source to reference apps/<component>/<env>/values.yaml
Manifest-based components point directly to apps/<component>/<env>/manifests/
Supporting Files
scripts/ — deploy-dev.sh and destroy-dev.sh for bootstrapping
.github/workflows/ — GitHub Actions CI/CD (deploy-operators.yaml, full-deploy.yaml)
.azure-pipelines/ — Azure DevOps equivalents
CHEATSHEET.md — kubectl/helm/oc command reference
hosts.yaml / secrets.yaml — environment and secrets config
In short: gitops-config/ is the "what goes where" layer (region/env routing), and apps/ is the "what actually gets deployed" layer (charts, values, manifests). Together they give you a fully GitOps-driven, multi-environment Confluent + Flink stack.