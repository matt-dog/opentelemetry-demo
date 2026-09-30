# Shared settings and helpers for up.sh, down.sh and status.sh. Sourced, not run.

CLUSTER="otel-demo"          # the GKE cluster
DD_CLUSTER_NAME="otel-demo-gke"   # k8s.cluster.name in Datadog; set in both values files
DD_ENV="otel-demo-gke"            # env tag; set in both values files
NAMESPACE="otel-demo"
NODE_POOL="default-pool"
NUM_NODES=2
MACHINE_TYPE="e2-standard-4"
DEMO_CHART_VERSION="0.42.1"
COLLECTOR_CHART_VERSION="0.173.1"
KSM_CHART_VERSION="8.6.0"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require_bins() {
  local b
  for b in "$@"; do command -v "$b" >/dev/null || die "$b is not installed"; done
}

load_env() {
  [ -f "$DIR/.env" ] || die "No $DIR/.env. Copy .env.example to .env and fill it in."
  set -a
  # shellcheck disable=SC1091
  . "$DIR/.env"
  set +a
  : "${GCP_PROJECT:?GCP_PROJECT is required in .env}"
  : "${GKE_ZONE:?GKE_ZONE is required in .env}"
  : "${DD_SITE:?DD_SITE is required in .env}"
  : "${DD_API_KEY:?DD_API_KEY is required in .env}"
}

# Resolve an op:// reference to the real key. Only up.sh needs the key itself.
resolve_api_key() {
  case "$DD_API_KEY" in
    op://*)
      require_bins op
      DD_API_KEY="$(op read "$DD_API_KEY")" || die "op could not read DD_API_KEY. Is 1Password unlocked?"
      ;;
  esac
  # A wrong site/key pairing fails silently as "no data", so check it up front.
  local res
  res="$(curl -s "https://api.${DD_SITE}/api/v1/validate" -H "DD-API-KEY: ${DD_API_KEY}")"
  [ "$res" = '{"valid":true}' ] || die "DD_API_KEY is not valid on ${DD_SITE}: $res"
}

gc() { gcloud container clusters "$@" --project "$GCP_PROJECT" --zone "$GKE_ZONE"; }

cluster_exists() { gc describe "$CLUSTER" --format='value(name)' >/dev/null 2>&1; }

# Target size of the node pool's instance group. The cluster's currentNodeCount
# lags a resize (it still read 1 after a finished resize to 0), which would make
# up.sh skip the wake.
current_nodes() {
  local mig n
  mig="$(gcloud container node-pools describe "$NODE_POOL" --cluster "$CLUSTER" \
    --project "$GCP_PROJECT" --zone "$GKE_ZONE" --format='value(instanceGroupUrls[0])' 2>/dev/null)"
  [ -n "$mig" ] || { echo 0; return; }
  n="$(gcloud compute instance-groups managed describe "${mig##*/}" \
    --project "$GCP_PROJECT" --zone "$GKE_ZONE" --format='value(targetSize)' 2>/dev/null)"
  echo "${n:-0}"
}

use_cluster() {
  gc get-credentials "$CLUSTER" >/dev/null 2>&1 || die "could not get credentials for $CLUSTER"
}
