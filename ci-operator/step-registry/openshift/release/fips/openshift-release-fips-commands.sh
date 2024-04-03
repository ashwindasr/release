#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

payload_url="${RELEASE_IMAGE_LATEST}"

if [[ "$payload_url" == *"@sha256"* ]]; then
    payload_url=$(echo "$payload_url" | sed 's/@sha256.*/:latest/')
fi

echo "Login to registry"
oc registry login

echo "Testing auth"
oc adm release info "${payload_url}"

./check-payload scan payload -V "${MAJOR_MINOR}" --url "${payload_url}"
