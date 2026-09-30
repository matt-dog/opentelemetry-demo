#!/usr/bin/env bash
# Put the OTel Demo to sleep (default) or delete it.
#
#   down.sh            scale nodes to 0. Cluster, config and public IP stay;
#                      up.sh wakes it in a few minutes.
#   down.sh --delete   delete the cluster. up.sh rebuilds from scratch
#                      (new public IP, 5 to 8 minutes plus pod startup).
set -euo pipefail
. "$(dirname "$0")/common.sh"

require_bins gcloud
load_env

cluster_exists || { log "$CLUSTER does not exist, nothing to do"; exit 0; }

case "${1:-}" in
  --delete)
    read -r -p "Delete cluster $CLUSTER in $GCP_PROJECT? This cannot be undone. [y/N] " ok
    [ "$ok" = "y" ] || die "aborted"
    log "Deleting $CLUSTER (about 5 minutes)"
    gc delete "$CLUSTER" --quiet
    log "Deleted."
    ;;
  "")
    if [ "$(current_nodes)" = "0" ]; then
      log "$CLUSTER is already asleep"
    else
      log "Sleeping $CLUSTER: scaling $NODE_POOL to 0 nodes"
      gc resize "$CLUSTER" --node-pool "$NODE_POOL" --num-nodes 0 --quiet
      log "Asleep. Wake with: $DIR/up.sh"
    fi
    ;;
  *) die "usage: down.sh [--delete]" ;;
esac
