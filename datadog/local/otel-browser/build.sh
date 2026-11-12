#!/bin/sh
# Builds otel-browser.js, the OpenTelemetry Browser SDK as one script for the shopper
# (shopper.yaml loads it into every shop page; up.sh makes the ConfigMap). The built file is
# committed, so up.sh needs no Node. Rerun after changing entry.js or a version in package.json.
set -eu
cd "$(dirname "$0")"
npm ci --no-audit --no-fund
npx esbuild entry.js --bundle --format=iife --target=es2020 --minify --legal-comments=none \
  --outfile=otel-browser.js
ls -l otel-browser.js
