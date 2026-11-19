#!/usr/bin/env bash
# Builds the shop's frontend from this repo's src/frontend (the OpenTelemetry Browser SDK,
# open-telemetry/opentelemetry-demo#4329) with Cloud Build, on native linux/amd64, and pushes it
# to Artifact Registry. A local build under amd64 emulation (Rancher Desktop on Apple silicon)
# segfaults in `next build` (exit 139), so the build runs in Google Cloud.
#
#   datadog/local/frontend-build.sh [tag]     # prints the image; pass it to up.sh as FRONTEND_IMAGE
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PROJECT="${GCP_PROJECT:-dd-dev-otelpmdev}"
REGION="${GCP_REGION:-us-east1}"
TAG="${1:-$(git -C "$ROOT" rev-parse --short HEAD)}"
IMAGE="$REGION-docker.pkg.dev/$PROJECT/otel-demo/frontend:$TAG"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/src"
rsync -a --exclude node_modules --exclude .next "$ROOT/src/frontend" "$stage/src/"
cat >"$stage/cloudbuild.yaml" <<EOF
steps:
  - name: gcr.io/cloud-builders/docker
    args: [build, -f, src/frontend/Dockerfile, -t, "$IMAGE", .]
images: ["$IMAGE"]
options: {machineType: E2_HIGHCPU_8}
timeout: 1800s
EOF
gcloud builds submit "$stage" --project "$PROJECT" --region "$REGION" --config "$stage/cloudbuild.yaml" >&2
echo "$IMAGE"
