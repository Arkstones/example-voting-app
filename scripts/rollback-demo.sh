#!/usr/bin/env bash
# scripts/rollback-demo.sh - ship a bad release on purpose, then roll it back.
#
# The bad release changes one setting: the worker is told to use a database
# host that does not exist ("db-typo"). Nothing crashes and both pages still
# load, so it looks fine - but new votes stop being counted. That is the kind
# of mistake that gets past a quick check, which is why rollback matters.
#
# Because votes wait in the Redis queue, none are lost: after the rollback the
# worker reconnects to the real database and saves the votes that piled up.
#
# Usage: ./scripts/rollback-demo.sh
# Needs kubectl and helm pointed at the cluster (./terraform/up.sh does that)
# and the app already deployed by the pipeline.

set -euo pipefail

NS=uga-vote
RELEASE=uga-vote
CHART="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helm/uga-vote"

pause() { echo; read -rp ">>> $1 (press Enter)" _; echo; }

votes_in_db() {
    kubectl exec -n "$NS" db-0 -- \
        psql -U postgres -tAc "SELECT COUNT(*) FROM votes" 2>/dev/null | tr -d '[:space:]'
}

votes_in_queue() {
    kubectl exec -n "$NS" deploy/redis -- redis-cli llen votes 2>/dev/null | tr -d '[:space:]'
}

vote_url=$(kubectl get svc vote -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
result_url=$(kubectl get svc result -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "== 1. the current, working release =="
helm history "$RELEASE" -n "$NS" --max 5
good_revision=$(helm history "$RELEASE" -n "$NS" --max 1 -o json | sed -E 's/.*"revision":([0-9]+).*/\1/')
echo
echo "Vote page:   http://$vote_url"
echo "Result page: http://$result_url"
echo "Votes saved in Postgres: $(votes_in_db)"

pause "Ship the bad release (worker pointed at a database that doesn't exist)"

echo "== 2. shipping the bad release =="
# --reuse-values keeps the image tag and password of the current release,
# and changes only this one setting
helm upgrade "$RELEASE" "$CHART" -n "$NS" --reuse-values \
    --set worker.dbHost=db-typo --wait --timeout 5m
kubectl rollout status deployment/worker -n "$NS" --timeout=3m
echo
kubectl get pods -n "$NS"
echo
echo "Every pod is Running - Kubernetes can't tell anything is wrong."

pause "Now cast a few votes on http://$vote_url, then check the result page"

echo "== 3. what's actually happening =="
echo "Worker log (it can't find its database):"
kubectl logs -n "$NS" deploy/worker --tail=5 || true
echo
echo "Votes saved in Postgres:     $(votes_in_db)   <- not going up"
echo "Votes waiting in Redis queue: $(votes_in_queue)   <- piling up"

pause "Roll back to revision $good_revision"

echo "== 4. helm rollback =="
helm rollback "$RELEASE" "$good_revision" -n "$NS" --wait --timeout 5m
kubectl rollout status deployment/worker -n "$NS" --timeout=3m
echo
helm history "$RELEASE" -n "$NS" --max 5

echo
echo "Giving the worker a few seconds to catch up ..."
sleep 10
echo "Votes saved in Postgres:     $(votes_in_db)   <- the queued votes are saved"
echo "Votes waiting in Redis queue: $(votes_in_queue)"
echo
echo "Rolled back to revision $good_revision. No votes were lost, they waited in Redis."
