# grafana

Grafana Alloy modules, alerting rules and Grafana dashboards for monitoring Kubernetes clusters, Linux hosts and the databases that run on them. Metrics go to a Prometheus-compatible backend such as Mimir, logs to Loki and traces to Tempo, each under a tenant (`X-Scope-OrgID`) you choose per instance.

```
alloy/modules/   Alloy modules, one file per module, each a set of declare blocks
rules/           alerting rules as Prometheus Operator PrometheusRules, with unit tests
dashboards/      Grafana dashboards for what the modules collect
```

Each module documents its arguments, labels and requirements in the comments at the top of its file and above each `declare`. This README is the index.

## Using a module

Import a module straight from this repository with `import.git`, then instantiate its declares:

```alloy
import.git "host_metrics" {
  repository     = "https://github.com/startechnica/grafana.git"
  revision       = "main"
  path           = "alloy/modules/host_metrics.alloy"
  pull_frequency = "1h"
}

host_metrics.unix "node" {
  tenant_id                    = "my-tenant"
  endpoint_url                 = sys.env("MIMIR_ENDPOINT_URL")
  endpoint_basic_auth_username = sys.env("AUTH_BASIC_USERNAME")
  endpoint_basic_auth_password = sys.env("AUTH_BASIC_PASSWORD")
}
```

With `revision = "main"`, every change merged to `main` reaches your Alloy on its next pull. To roll changes out on your own schedule, set `revision` to a commit SHA and move it forward when you are ready.

The modules are written for and checked against Alloy v1.19.2.

## Modules

**Delivery** says where a declare's output goes. *Built-in* means the declare writes it itself, to the endpoint and credentials you pass. *`forward_to`* means it hands entries to receivers you pass, such as your own `loki.write`. Some declares support both.

### Hosts and containers

| Module | Declares | Collects | Delivery |
|---|---|---|---|
| `host_metrics` | `unix` | Host metrics through the embedded node_exporter | Built-in remote_write or `forward_to` |
| | `kubelet` | The local kubelet's `/metrics`, `/metrics/cadvisor`, `/metrics/probes` and `/metrics/resource` | Built-in remote_write or `forward_to` |
| | `control_plane` | The local kube-controller-manager, kube-scheduler and etcd | Built-in remote_write or `forward_to` |
| | `containers` | CPU, memory, block I/O and pids of every Docker or Podman container, from cgroups through cAdvisor | Built-in remote_write or `forward_to` |
| `host_logs` | `journal`, `files`, `syslog` | The systemd journal, text files under `/var/log`, and syslog received over the network | Built-in loki.write or `forward_to` |
| `container_metrics` | `apps` | Metrics that apps inside Docker or Podman containers expose, from containers that opt in with labels | Built-in remote_write |

### Kubernetes

| Module | Declares | Collects | Delivery |
|---|---|---|---|
| `k8s_metrics` | `kubernetes` | Annotated pods (`prometheus.io/scrape`) and ServiceMonitors in a tenant's namespaces | Built-in remote_write or `forward_to` |
| | `crds` | ServiceMonitors and PodMonitors only | Built-in remote_write or `forward_to` |
| | `annotations` | Annotated pods only | Built-in remote_write or `forward_to` |
| `k8s_pod_logs_file` | `kubernetes` | Pod logs tailed from `/var/log/pods` on the local node | `forward_to` |
| `k8s_pod_logs_api` | `kubernetes` | Pod logs of the local node's pods, streamed through the API server | `forward_to` |
| `k8s_pod_logs` | `kubernetes` | Pod logs through the API server, with fixed health-check drops and redactions | `forward_to` |
| `k8s_podlogs` | `kubernetes` | Logs of the local node's pods that PodLogs resources select, streamed through the API server, limited to a tenant's namespaces | `forward_to` |
| `k8s_events` | `kubernetes` | Kubernetes events as log lines: Warnings, plus node condition changes, by default | `forward_to` |
| `k8s_alerts` | `metrics`, `metrics_scoped`, `logs` | Syncs PrometheusRule CRDs into the Mimir ruler (PromQL) and the Loki ruler (LogQL) | The rulers' APIs |
| `k8s_otel` | `default`, `tenant_route` | An OTLP gateway on ports 4317 and 4318 that adds Kubernetes attributes, and per-tenant routes with service graph and span metrics | OTLP exporters and remote_write |
| `ceph_logs` | `process` | A `loki.process` for Ceph and Rook pod logs, chained after `k8s_podlogs`: drops the lines Ceph's metrics already cover and reads the Ceph and Rook log levels | `forward_to` |
| `openebs_logs` | `log` | A `loki.process` that joins OpenEBS's multi-line log records | `forward_to` |

### Databases

| Module | Declares | Collects | Delivery |
|---|---|---|---|
| `postgres_metrics` | `postgres`, `patroni`, `etcd`, `haproxy`, `pgbouncer` | A PostgreSQL HA stack managed by Patroni, one declare per component | Built-in remote_write or `forward_to` |
| `mongodb_metrics` | `mongodb` | A standalone mongod, replica set member, config server or mongos, one declare per process | Built-in remote_write or `forward_to` |

### Alloy itself

| Module | Declares | Collects | Delivery |
|---|---|---|---|
| `self_monitor` | `default` | Alloy's own metrics, logs and traces | Built-in remote_write, loki.write and OTLP exporter, or per-signal `*_forward_to` |

## Conventions

- **Tenants.** A module stamps the tenant you pass as `tenant_id` on everything it sends, so one Alloy can serve several tenants side by side. The Kubernetes modules are usually instantiated once per tenant, each with that tenant's `namespaces`.
- **Node-local collection.** `host_metrics`, `host_logs`, `k8s_pod_logs_file`, `k8s_pod_logs_api`, `k8s_podlogs`, `postgres_metrics` and `mongodb_metrics` collect only from the node they run on. Run them as a DaemonSet on Kubernetes, or as one container per host under Docker or Podman. Each module's header lists the mounts and flags it needs. The node name comes from `node_name`, else `K8S_NODE_NAME`, which the Grafana Alloy Helm chart sets. Outside Kubernetes, the host and database modules fall back to the hostname.
- **Clustering.** Node-local declares turn clustering off, so every Alloy keeps its own node's data. Cluster-wide work, such as `k8s_metrics` scrapes and `k8s_events` watches, is split across clustered Alloy peers.
- **Shared labels.** `node` is the same on a host's metrics and its logs, so the two join. `cluster_name`, `region` and `zone` come from arguments. `k8s_pod_logs`, `k8s_pod_logs_file`, `k8s_pod_logs_api` and `k8s_podlogs` take `cluster_name` from `K8S_CLUSTER_NAME` when it is not passed.
- **Structured metadata.** `host_logs`, `k8s_pod_logs_file`, `k8s_podlogs` and `k8s_events` keep high-cardinality fields (pid, pod, object name) as Loki structured metadata instead of labels. That needs Loki with `allow_structured_metadata: true` (TSDB index, schema v13).

## Alerting rules

| File | Covers |
|---|---|
| [`rules/postgres-metrics.yaml`](rules/postgres-metrics.yaml) | Patroni, etcd, HAProxy, PgBouncer and PostgreSQL, as `postgres_metrics` collects them |
| [`rules/mongodb-metrics.yaml`](rules/mongodb-metrics.yaml) | MongoDB processes, replica sets and sharding, as `mongodb_metrics` collects them |

Both are Prometheus Operator `PrometheusRule`s. In a namespace that `k8s_alerts.metrics` watches, they are synced into that tenant's Mimir ruler. Without Kubernetes, load the groups with mimirtool:

```sh
yq '{"namespace": .metadata.name, "groups": .spec.groups}' \
  rules/postgres-metrics.yaml > postgres-metrics.rules.yaml
mimirtool rules load postgres-metrics.rules.yaml --address=<mimir> --id=<tenant>
```

Add `--user` and `--key` when Mimir sits behind basic auth. The rules have to land in the tenant the metrics are written to, and the tenant's Alertmanager needs a route that delivers them. The rules select by metric name, not by job, so they also cover the same software scraped some other way. The header of each file explains its labels and thresholds.

## Dashboards

| Dashboard | UID | Shows |
|---|---|---|
| [Host Metrics](dashboards/host-metrics.json) | `host-metrics` | `host_metrics`: CPU, memory, filesystems, network and disk I/O, plus optional container and Kubernetes node service panels |
| [Host Logs](dashboards/host-logs.json) | `host-logs` | `host_logs`: log volume, the noisiest sources, access and privilege events, and the log stream |
| [Patroni](dashboards/patroni.json) | `patroni` | `postgres_metrics.patroni`: members, roles, replication, DCS and maintenance state |
| [MongoDB](dashboards/mongodb.json) | `mongodb` | `mongodb_metrics`: processes, replication, operations, connections, cache, databases and sharding |

Import the JSON through **Dashboards → New → Import** or file provisioning. Each dashboard has a `datasource` variable, so pick your Mimir or Loki data source after importing.

## Development

CI ([`.github/workflows/lint.yaml`](.github/workflows/lint.yaml)) runs on every push to every branch, with pinned tool versions:

| Check | What it runs |
|---|---|
| Alloy modules | `alloy fmt` must leave each module unchanged, then `alloy validate` (Alloy v1.19.2) |
| YAML | `yamllint --strict .`, configured in `.yamllint.yaml` |
| Dashboards | `dashboard-linter lint --strict` on each dashboard; `dashboards/.lint` lists the excluded rules and why |
| Rules | `rules/test.sh`: `promtool check rules` and the unit tests in `rules/tests/` (promtool 3.14, yq 4.53) |

Run `alloy fmt -w <file>` after editing a module. Files are stored with LF line endings (`.gitattributes`).

Anything that imports `main` picks up a merge on its next pull, so keep argument names and label output stable. Mark a breaking change with `!` in the commit title (for example `refactor(k8s)!: ...`) and describe the migration in the pull request.
