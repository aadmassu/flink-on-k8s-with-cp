# Production Ready Flink Kubernetes Operator Configuration

## Installation

You must install the Confluent Platform for Apache Flink Kubernetes operator before you install CMF because CMF uses the operator to manage the Flink clusters.

### Prerequisites

1. **cert-manager** must be installed first. FCB uses upstream cert-manager (not the Red Hat version) with a KeyFactor-backed ClusterIssuer.

```bash
kubectl create -f https://github.com/jetstack/cert-manager/releases/download/v1.19.4/cert-manager.yaml
```

> **Note:** FCB already has cert-manager deployed with their own ClusterIssuer linked to KeyFactor. You do not need to install cert-manager separately.

### Install the Flink Kubernetes Operator

Use the `watchNamespaces` configuration to prepare the Kubernetes namespaces you want to deploy Flink applications to. You can later upgrade the Flink Kubernetes operator to extend the list, by re-running below Helm command again, with the additional namespaces. Note that you need to manually restart the Flink Kubernetes operator after changing the `watchNamespaces` configuration, for example by deleting the operator pod. It will be automatically recreated. You must ensure that the Kubernetes operator watches the Kubernetes namespaces you want to deploy Flink applications to with CMF.

Instead of using Helm, you can also manually prepare a Kubernetes namespace for deploying Flink clusters, by creating the necessary flink service account, role and role binding, as documented in the Flink Kubernetes operator documentation. If you omit the `watchNamespaces` flag, the operator will watch all namespaces, but the necessary flink service account will only by created in the namespace where the operator is installed. Additional namespaces must be setup manually.

### OpenShift-Specific Configuration

On OpenShift, pod security contexts must be nullified so that OpenShift SCCs manage security contexts:

```yaml
podSecurityContext:
  enabled: false

operatorSecurityContext: {}
webhookSecurityContext: {}
```

Or via Helm CLI flags:

```bash
--set podSecurityContext.runAsUser=null --set podSecurityContext.runAsGroup=null
```

### Helm Install Command

```bash
helm upgrade --install cp-flink-kubernetes-operator --version "1.130.2" \
  confluentinc/flink-kubernetes-operator \
  --namespace confluent-operator \
  --set watchNamespaces="{confluent-operator,confluent-dev}"
```

## Specifying Operator Configuration

The operator allows users to specify default configuration that will be shared by the Flink operator itself and the Flink deployments.

These configuration files are mounted externally via ConfigMaps. The Configuration files with default values are shipped in the Helm chart. It is recommended to review and adjust them if needed in the `values.yaml` file before deploying the Operator in production environments.

To append to the default configuration, define the `flink-conf.yaml` key in the `defaultConfiguration` section of the Helm `values.yaml` file:

```yaml
defaultConfiguration:
  create: true
  # Set append to false to replace configuration files
  append: true
  flink-conf.yaml: |+
    # Flink Config Overrides
    kubernetes.operator.metrics.reporter.slf4j.factory.class: org.apache.flink.metrics.slf4j.Slf4jReporterFactory
    kubernetes.operator.metrics.reporter.slf4j.interval: 5 MINUTE

    kubernetes.operator.reconcile.interval: 15 s
    kubernetes.operator.observer.progress-check.interval: 5 s
```

To learn more about metrics and logging configuration please refer to the dedicated docs page.



## Dynamic Operator Configuration

The Kubernetes operator supports dynamic config changes through the operator ConfigMaps. Dynamic operator configuration is enabled by default, and can be disabled by setting `kubernetes.operator.dynamic.config.enabled` to `false`. Time interval for checking dynamic config changes is specified by `kubernetes.operator.dynamic.config.check.interval` of which default value is 5 minutes.

Verify whether dynamic operator configuration updates is enabled via the `deploy/flink-kubernetes-operator` log has:

```
2022-05-28 13:08:29,222 o.a.f.k.o.c.FlinkConfigManager [INFO ] Enabled dynamic config updates, checking config changes every PT5M
```

To change config values dynamically the ConfigMap can be directly edited via `kubectl patch` or `kubectl edit` command. For example to change the reschedule interval you can override `kubernetes.operator.reconcile.interval`.

Verify whether the config value of `kubernetes.operator.reconcile.interval` is updated to 30 seconds via the `deploy/flink-kubernetes-operator` log has:

```
2022-05-28 13:08:30,115 o.a.f.k.o.c.FlinkConfigManager [INFO ] Updating default configuration to {kubernetes.operator.reconcile.interval=PT30S}
```

## Leader Election and High Availability

The operator supports high availability through leader election and standby operator instances. To enable leader election you need to add the following two mandatory operator configuration parameters.

```yaml
kubernetes.operator.leader-election.enabled: true
kubernetes.operator.leader-election.lease-name: flink-operator-lease
```

Lease name must be unique in the current lease namespace. For other more advanced config parameters please refer to the configuration reference.

Once you enabled leader election you can increase the replicas for the operator Deployment using the Helm chart to enable high availability.

If replicas value is greater than 1, you can define `topologySpreadConstraints` via `operatorPod.topologySpreadConstraints`.

## Webhook TLS Configuration

The Flink Operator Helm chart creates a namespace-scoped self-signed cert-manager `Issuer` (`flink-operator-selfsigned-issuer`) and a `Certificate` CR for webhook TLS. This is standard for internal webhook traffic — the API server trusts it via cert-manager's cainjector.

If your security policy requires all certificates to come from an enterprise CA (e.g., KeyFactor), you can override the issuer reference using a Kustomize patch:

```yaml
# patch-certificate-issuer.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: flink-operator-serving-cert
spec:
  issuerRef:
    kind: ClusterIssuer
    name: <your-keyfactor-clusterissuer-name>
```

The chart also supports a custom keystore secret for the webhook:

```yaml
webhook:
  create: true
  keystore:
    useDefaultPassword: false
    passwordSecretRef:
      name: confluent-keystore
      key: password
```

> **Note:** The `confluent-keystore` secret must exist before the operator deploys.

## Snapshot Resource

Enable the `FlinkStateSnapshot` CRD to declaratively trigger savepoints and checkpoints:

```yaml
defaultConfiguration:
  flink-conf.yaml: |+
    kubernetes.operator.snapshot.resource.enabled: true
```

This allows creating `FlinkStateSnapshot` CRs for job upgrades and disaster recovery without using the Flink CLI.

## Console-Only Logging

For Kubernetes deployments, disable file-based logging and use console-only output. This eliminates the need for persistent volumes for log files and lets the container runtime / log aggregator collect logs from stdout.

In the `defaultConfiguration` section, override the operator logging config:

```yaml
defaultConfiguration:
  create: true
  append: false
  log4j-operator.properties: |
    rootLogger.level = INFO
    rootLogger.appenderRef.console.ref = ConsoleAppender

    appender.console.name = ConsoleAppender
    appender.console.type = CONSOLE
    appender.console.layout.type = PatternLayout
    appender.console.layout.pattern = %d{yyyy-MM-dd HH:mm:ss,SSS} %-5p %-60c %x - %m%n
```

> **Note:** Do NOT include `rootLogger.appenderRef.rolling.ref = RollingFileAppender` or the `appender.rolling.*` block. Removing the rolling appender means no log files are created on the container filesystem, and `operatorVolumes` are not needed for logging.

## Example Production Configuration File (`operator-production-ready.yaml`)

This file is used with Helm to customize the Flink Kubernetes Operator deployment for production:

```yaml
replicas: 2

watchNamespaces:
  - confluent-operator
  - confluent-dev

image:
  registry: artifactory.fcbint.net/<docker-repo>
  repository: confluentinc/cp-flink-kubernetes-operator

## OpenShift — let SCCs manage security contexts
podSecurityContext:
  enabled: false
operatorSecurityContext: {}
webhookSecurityContext: {}

## Scheduling
operatorPod:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values:
                    - flink-kubernetes-operator
            topologyKey: "kubernetes.io/hostname"
  tolerations:
    - operator: Exists
      key: node-role.kubernetes.io/xlworker
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9999"

## Resources
resources:
  requests:
    cpu: 1
    memory: "2.5Gi"
  limits:
    cpu: 2
    memory: "2.5Gi"
webhook:
  create: true
  keystore:
    useDefaultPassword: false
    passwordSecretRef:
      name: confluent-keystore
      key: password
  resources:
    requests:
      cpu: 200m
      memory: "0.5Gi"
    limits:
      cpu: 500m
      memory: "0.5Gi"

## RBAC
rbac:
  nodesRule:
    create: false
  operatorRole:
    create: true
    name: "flink-operator"
  operatorRoleBinding:
    create: true
    name: "flink-operator-role-binding"
  jobRole:
    create: true
    name: "flink"
  jobRoleBinding:
    create: true
    name: "flink-role-binding"

## Service accounts
operatorServiceAccount:
  create: true
  name: "flink-operator"
jobServiceAccount:
  create: true
  name: "flink"

## No volumes needed (console-only logging)
operatorVolumes:
  create: false

## Default Flink configuration
defaultConfiguration:
  create: true
  append: false
  flink-conf.yaml: |+
    # Leader Election for HA
    kubernetes.operator.leader-election.enabled: true
    kubernetes.operator.leader-election.lease-name: flink-operator-lease

    # Metrics
    kubernetes.operator.metrics.reporter.prom.factory.class: org.apache.flink.metrics.prometheus.PrometheusReporterFactory
    kubernetes.operator.metrics.reporter.prom.port: 9999

    # Reconciliation
    kubernetes.operator.reconcile.interval: 15 s
    kubernetes.operator.observer.progress-check.interval: 5 s

    # Snapshot resource
    kubernetes.operator.snapshot.resource.enabled: true

    # Default values
    taskmanager.numberOfTaskSlots: 1
    parallelism.default: 1
  log4j-operator.properties: |
    rootLogger.level = INFO
    rootLogger.appenderRef.console.ref = ConsoleAppender

    appender.console.name = ConsoleAppender
    appender.console.type = CONSOLE
    appender.console.layout.type = PatternLayout
    appender.console.layout.pattern = %d{yyyy-MM-dd HH:mm:ss,SSS} %-5p %-60c %x - %m%n
  log4j-console.properties: |+
    # Flink Deployment Logging Overrides
    # rootLogger.level = DEBUG

metrics:
  port: 9999
```

**Explanation of key configuration:**

*   **`replicas: 2`**: Two operator replicas for high availability. One is active (leader), one is standby. Requires leader election to be enabled.
*   **`podAntiAffinity`**: Soft rule (weight 100) to spread operator pods across different nodes. If one node goes down, the other replica survives.
*   **`tolerations`**: Allows scheduling on FCB's dedicated `xlworker` nodes. The `Exists` operator matches the taint regardless of value.
*   **`resources`**: Production-grade resource allocation. Operator container: 1 CPU / 2.5Gi request, 2 CPU / 2.5Gi limit. Webhook container: 200m / 0.5Gi request, 500m / 0.5Gi limit.
*   **`webhook`**: Enables ValidatingWebhookConfiguration and MutatingWebhookConfiguration. Uses a custom keystore secret (`confluent-keystore`) instead of the default password.
*   **`rbac.nodesRule.create: false`**: Not needed — NodePort is not used on OpenShift (Routes are used instead).
*   **`operatorVolumes.create: false`**: No persistent volumes needed since logging is console-only.
*   **`defaultConfiguration.append: false`**: Replaces the default ConfigMap entirely rather than merging. This gives full control over the operator configuration.
*   **`kubernetes.operator.snapshot.resource.enabled: true`**: Enables the `FlinkStateSnapshot` CRD for declarative savepoints and checkpoints.
*   **`metrics`**: Prometheus metrics reporter on port 9999 with pod annotations for scraping.

## Applying the Configuration

To apply the configurations defined in `operator-production-ready.yaml`:

```bash
helm upgrade --install cp-flink-kubernetes-operator \
  confluentinc/flink-kubernetes-operator \
  --version "1.130.2" \
  --namespace confluent-operator \
  --values operator-production-ready.yaml
```

This command will upgrade your existing Helm release, applying the changes specified in your `operator-production-ready.yaml` file. If the release does not exist, it will install it.

> **Note:** In the FCB GitOps setup, this is deployed via ArgoCD ApplicationSets rather than manual Helm commands. The values file is stored in `apps/confluent-flink-operator/<env>/values.yaml` with an OpenShift overlay applied automatically.

## Alerting Strategy for Core Components

To ensure the stability of your Flink environment, you should monitor the health of the core operator and management pods. This section outlines a high-level alerting strategy that can be implemented with any standard Kubernetes monitoring solution.

### Core Components to Monitor

Identify the following deployments or pods in your cluster using the verified labels below.

1.  **Flink Kubernetes Operator**
    *   **Verified Label:** `app.kubernetes.io/name: flink-kubernetes-operator`
2.  **Confluent for Kubernetes Operator**
    *   **Verified Label:** `app.kubernetes.io/name: confluent-operator`
3.  **Confluent Manager for Flink (CMF)**
    *   **Verified Label:** `app.kubernetes.io/name: confluent-manager-for-apache-flink`

### Essential Alerts

Configure your monitoring system to trigger alerts based on the following conditions.

*   **Alert 1: Component Deployment Not Available**
    *   **Condition:** The number of available replicas for any of the core component deployments (identified by the labels above) is zero for more than 1-2 minutes.
    *   **Reasoning:** This is a critical alert. If the deployment has no available pods, the corresponding management or operator functionality is completely down.

*   **Alert 2: Excessive Pod Restarts**
    *   **Condition:** A pod within one of the core component deployments restarts more than a few times (e.g., 3-5 times) within a short period (e.g., 15-30 minutes).
    *   **Reasoning:** This indicates a recurring crash loop that could be caused by configuration errors, resource pressure, or software bugs. While the service might be intermittently available, it is unstable and requires investigation.
