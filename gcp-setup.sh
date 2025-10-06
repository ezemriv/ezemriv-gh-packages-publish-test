#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# GAR publish setup (run once per project)
# -----------------------------------------------------------------------------
# Usage:
#   # Run either for dev or pro env:
#   #   ./setup-gcp-predeploy.sh -e dev
#   #   ./setup-gcp-predeploy.sh -e pro
# -----------------------------------------------------------------------------
# Requires these env vars set in sourced config-*.env file:
#   PROJECT_ID           e.g. "tradelab023"
#   PROJECT_NUMBER       e.g. "566607668180"
#   GAR_LOCATION         e.g. "europe-southwest1"
#   REPOSITORY           e.g. "tradelab-pypi"
#   CI_SA                e.g. "tradelab-pypi-publisher"
# -----------------------------------------------------------------------------

set -euo pipefail

ENV="dev"
while getopts ":e:" opt; do
  case "$opt" in
    e) ENV="$OPTARG" ;;
    *) echo "usage: $0 [-e dev|pro]"; exit 2 ;;
  case esac
done

ENV_FILE="config-${ENV}.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "env file not found: $ENV_FILE"; exit 1
fi

echo "Loading $ENV_FILE"
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# require config sourced first
if [[ -z "${CI_SA:-}" ]]; then
  echo "Config not loaded. Retry."
  exit 1
fi

CI_SA_EMAIL="${CI_SA}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Project: $PROJECT_ID"
echo "Repo   : $REPOSITORY ($GAR_LOCATION)"
echo "SA     : $CI_SA_EMAIL"
gcloud config set project "$PROJECT_ID" >/dev/null

echo "1) Enable Artifact Registry API"
gcloud services enable artifactregistry.googleapis.com

echo "2) Ensure GAR Python repo"
if gcloud artifacts repositories describe "$REPOSITORY" --location="$GAR_LOCATION" >/dev/null 2>&1; then
  echo "   Repo exists"
else
  gcloud artifacts repositories create "$REPOSITORY" \
    --repository-format=python \
    --location="$GAR_LOCATION" \
    --description="TradeLab Private Python packages"
fi

echo "3) Ensure publisher service account"
if gcloud iam service-accounts describe "$CI_SA_EMAIL" >/dev/null 2>&1; then
  echo "   SA exists"
else
  gcloud iam service-accounts create "$CI_SA" \
    --display-name="TradeLab Python Packages Publisher"
fi

echo "4) Grant minimal publish rights (writer on repo)"
gcloud artifacts repositories add-iam-policy-binding "$REPOSITORY" \
  --location="$GAR_LOCATION" \
  --member="serviceAccount:${CI_SA_EMAIL}" \
  --role="roles/artifactregistry.writer"

echo "5) Allow GitHub Actions to impersonate the SA via WIF pool 'github-pool'"
# Broad binding to the pool. Tighten later per repo if desired.
gcloud iam service-accounts add-iam-policy-binding "$CI_SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/*"

echo "Done."
echo "Upload URL : https://${GAR_LOCATION}-python.pkg.dev/${PROJECT_ID}/${REPOSITORY}/"
echo "Simple index: https://${GAR_LOCATION}-python.pkg.dev/${PROJECT_ID}/${REPOSITORY}/simple/"
