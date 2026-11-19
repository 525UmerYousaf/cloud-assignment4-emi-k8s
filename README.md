# Loan EMI Calculator on Kubernetes (Minikube) with a MongoDB replica set

Cloud Computing (DS-584), Assignment 4 — Muhammad Umer Yousaf (MSCSF26M018)

A loan EMI calculator (Node.js/Express, jQuery, Bootstrap) that stores every calculation in a
3-member MongoDB replica set. Everything runs on a single-node Minikube cluster in the
namespace `emi`; traffic enters only through the NGINX Ingress at `http://emi.local/`.

```
host ──► Ingress (NGINX, emi.local) ──► Service emi-web (ClusterIP) ──► emi-web pods (Deployment, 1-5, HPA)
                                                                         │ MONGO_URL
                                                                         ▼
                                          StatefulSet mongo (rs0): mongo-0 PRIMARY · mongo-1 · mongo-2, one PVC each
```

## Repository layout

| Path | Contents |
|---|---|
| `app/` | Express server (`server.js`, `app.js`, `emi.js`), UI (`public/`), `Dockerfile`, `.dockerignore`, tests |
| `k8s/` | Namespace, MongoDB headless Service + StatefulSet, `mongo-init` Job, ConfigMap, web Deployment + Service, Ingress |
| `k8s/autoscale/` | HorizontalPodAutoscaler (applied separately for Milestone 04) |
| `scripts/` | Cluster setup, image builds, demos for Milestones 2-3, load tests, profilers, parsing, graphs |
| `results/` | Raw outputs of every experiment (`m2/`, `m3/`, `fixed/`, `autoscale/`, `graphs/`) |

## API

| Method and path | Description |
|---|---|
| `POST /api/emi` | Body `{principal, rate, months}` (JSON or form-encoded). Validates (positive numbers, whole months), computes EMI, total payment and total interest, saves to MongoDB, returns them with `servedBy` (pod name from `HOSTNAME`), `podIp` and `version`. `400` on invalid input. |
| `GET /api/history` | Last 10 calculations, newest first. |
| `GET /health` | `200` only when MongoDB answers a ping; `503` otherwise. Used by the readiness and liveness probes. |
| `GET /api/info` | Pod name, pod IP and app version (shown in the page title/footer). |

Every calculation is stored in `emidb.calculations` with `principal, rate, months, emi, servedBy, createdAt`.
The connection string comes only from the `MONGO_URL` environment variable.

`EMI = P·r·(1+r)^n / ((1+r)^n − 1)`, with `r = annual rate / 12 / 100`. Example: P = 500000, 12 %, 24 months → **EMI 23,536.74**, total 564,881.67, interest 64,881.67.

## Prerequisites

Docker (Colima or Docker Desktop), `minikube`, `kubectl`, `git`, `python3` with `matplotlib` (for the graphs). Tested with Minikube v1.39 (docker driver) and Kubernetes v1.37.

## Bring the whole system up on a fresh Minikube cluster

```bash
# 1. Cluster: 4 CPUs / 6 GB, addons ingress + metrics-server
./scripts/setup-cluster.sh
#    (equivalent manual commands)
#    minikube start -p emi --driver=docker --cpus=4 --memory=6144 && minikube profile emi
#    minikube addons enable ingress && minikube addons enable metrics-server

# 2. Application image, built on the host and loaded into the cluster
./scripts/build-image.sh 1.0
#    (equivalent)  docker build -t emi-web:1.0 app/ && minikube image load emi-web:1.0

# 3. Everything else
kubectl apply -f k8s/
#    or ./scripts/deploy.sh, which also waits for MongoDB, the mongo-init Job and the web pods

# 4. Reach it from the host through the Ingress
#    macOS / Windows (docker driver): keep this running in its own terminal
minikube tunnel
#    and map the name once:  echo "127.0.0.1 emi.local" | sudo tee -a /etc/hosts
#    Linux: use the address from `minikube ip` instead of 127.0.0.1 (no tunnel needed)
open http://emi.local
```

Check:

```bash
kubectl get all,pvc,configmap,ingress -n emi -o wide
./scripts/rs-status.sh          # one PRIMARY, two SECONDARY
./scripts/count-docs.sh         # number of stored calculations
```

## Milestones

| Milestone | Commands | Output |
|---|---|---|
| 1. App, tested locally with one MongoDB container | `./scripts/local-test.sh up` → `http://localhost:8080`, then `./scripts/local-test.sh down` | screenshot |
| 2. Deploy on Minikube | `./scripts/deploy.sh`, `kubectl port-forward svc/emi-web 8080:80 -n emi`, `./scripts/m2-evidence.sh`, `./scripts/persistence-test.sh` | `results/m2/` |
| 3. Ingress, load balancing, self-healing, rolling update | `./scripts/spread.sh 30 3r`, `./scripts/scale-demo.sh`, `./scripts/selfheal-web.sh`, `./scripts/failover.sh`, `./scripts/build-image.sh 1.1 && ./scripts/rollout-demo.sh` | `results/m3/` |
| 4. Load tests, profiling, autoscaling | `./scripts/build-loadgen.sh`, `./scripts/run-fixed.sh` (15 runs), `./scripts/run-autoscale.sh` (10 min), `python3 scripts/plot_results.py` | `results/fixed/`, `results/autoscale/`, `results/graphs/` |

### Load-test design

* httperf (compiled from source, `scripts/loadgen/Dockerfile`) runs as a Kubernetes Job and sends
  every request to `http://emi.local/` — `emi.local` resolves to the NGINX Ingress controller, so each
  request takes the same Ingress → Service → pod path as a browser on the host. Running the
  generator inside the cluster avoids the macOS port-forwarding relay of the docker driver, which in
  earlier experiments (Assignment 2) stalled under load and invalidated the measurements.
* Each request is `POST /api/emi` with random valid inputs (1000 random request templates, httperf's
  maximum), so every request writes to MongoDB.
* Fixed replicas: 1, 2, 3 replicas × 10, 25, 50, 100, 200 req/s × 60 s. The HPA is removed during
  these runs so it cannot change the replica count.
* Profiling: `scripts/pod-top.sh` (`kubectl top pods -n emi` every 15 s, plus the node) and
  `scripts/host-cpu.sh` (host CPU every second; `iostat` on macOS, `/proc/stat` on Linux).
* Autoscaling: HPA `autoscaling/v2`, 1–5 replicas, 50 % CPU, scale-down stabilisation 60 s (default
  300 s is longer than the 3-minute cool-down). Load: 2 min at 10, 5 min at 100, 3 min at 10 req/s;
  the HPA is recorded every 15 s (`results/autoscale/hpa.csv` and the raw `hpa_raw.log`).

### Design notes

* **Readiness = MongoDB reachable.** `/health` pings with `primaryPreferred`, so a short PRIMARY
  election does not take every web pod out of the Service at once; writes wait up to 15 s
  (`serverSelectionTimeoutMS`) for the new PRIMARY and are retried once by the driver.
* **Zero-downtime updates.** `maxUnavailable: 0`, readiness probes, a 10 s `preStop` delay so the
  Ingress stops routing to a pod before it shuts down, graceful `SIGTERM` handling, and an HTTP
  keep-alive timeout longer than NGINX's.
* **MongoDB on a laptop.** `--wiredTigerCacheSizeGB 0.25` stops three members from each claiming half
  of the node's RAM; the headless Service publishes not-ready addresses so members can find each
  other while the set is being formed.
* **Image.** `node:22-alpine`, production dependencies only (`npm ci --omit=dev`), runs as the
  unprivileged `node` user, code owned by root.

## Tests

```bash
cd app && npm install && npm test     # EMI maths, validation, every endpoint (stand-in database)
```

## Clean up

```bash
./scripts/teardown.sh            # remove workloads, keep MongoDB data (PVCs), stop Minikube
./scripts/teardown.sh --data     # also delete the PVCs
./scripts/teardown.sh --cluster  # delete the whole Minikube profile
```
