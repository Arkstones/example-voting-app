# Architecture

GitHub renders these diagrams directly (they are written in Mermaid).

## 1. The running system

```mermaid
flowchart LR
    user(["Voter's browser"])

    subgraph aws["AWS eu-north-1 · default VPC"]
        lbv["Load balancer<br/>vote :80"]
        lbr["Load balancer<br/>result :80"]

        subgraph eks["EKS cluster Uga-vote-cluster · 2 × c7i-flex.large"]
            subgraph ns["namespace uga-vote · Pod Security: restricted"]
                vote["vote<br/>Python/Flask · 2 pods<br/>:8080"]
                redis[("redis<br/>queue")]
                worker["worker<br/>.NET 10"]
                db[("db<br/>PostgreSQL 17<br/>StatefulSet")]
                result["result<br/>Node.js 24<br/>:8080"]
            end
        end

        ebs[("EBS gp3 volume<br/>encrypted")]
    end

    user -- "cast a vote" --> lbv --> vote
    vote -- "RPUSH votes" --> redis
    redis -- "LPOP votes" --> worker
    worker -- "INSERT / UPDATE" --> db
    db --- ebs
    result -- "SELECT counts" --> db
    lbr --> result
    user -- "watch totals" --> lbr
```

- **vote** and **result** are the only public parts, each behind its own AWS load balancer.
- **Redis** decouples voting from saving. If the worker or database is down, votes wait in the queue instead of being lost (the rollback demo shows this).
- **Postgres** keeps its data on an EBS disk, so votes survive the pod restarting or moving.
- Every pod runs as a non-root user, with no Linux capabilities and no privilege escalation. The three app services also have read-only root filesystems.

## 2. From a push to a running release

```mermaid
flowchart LR
    dev(["git push / merge<br/>to main"]) --> gha

    subgraph gha["GitHub Actions · .github/workflows/ci.yml"]
        direction LR
        tests["test-vote · pytest<br/>test-result · node --test<br/>build-worker · dotnet<br/>lint-chart · helm lint"]
        e2e["e2e<br/>whole app in<br/>Docker Compose"]
        img["images × 3<br/>build → Trivy scan<br/>→ push"]
        deploy["deploy<br/>helm upgrade --install<br/>+ smoke test"]
        tests --> e2e --> img --> deploy
    end

    img -- "tag = commit SHA" --> ghcr[("ghcr.io/arkstones/<br/>uga-vote/*")]
    deploy -- "github-deployer<br/>(namespace-only access)" --> eks["EKS<br/>namespace uga-vote"]
    ghcr -- "nodes pull images" --> eks
```

- Pull requests run everything except pushing images and deploying.
- Trivy fails the run on fixable CRITICAL or HIGH vulnerabilities.
- The deploy job is skipped (not failed) when the cluster has been destroyed to save money.

## 3. What creates what

```mermaid
flowchart TB
    tfci["terraform/ci-user<br/>(applied once, kept)"] --> iamuser["IAM user<br/>github-deployer"]
    tf["terraform/<br/>(up.sh / down.sh)"] --> cluster["EKS cluster, node group,<br/>add-ons, access entries,<br/>EBS CSI role"]
    setup["k8s/cluster-setup.yaml<br/>(applied by up.sh)"] --> nsc["namespace uga-vote<br/>+ gp3 StorageClass"]
    helm["helm/uga-vote<br/>(deployed by CI)"] --> app["vote, result, worker,<br/>redis, db, Secret,<br/>load balancers, EBS disk"]
```
