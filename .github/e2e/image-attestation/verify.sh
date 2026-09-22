#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
: "${IMAGE:?}" "${DIGEST:?}" "${IMAGE_TAG:?}" "${ATTEST_RESULT:?}" "${REPORTS:?}"

actual="$(docker buildx imagetools inspect "$IMAGE@$DIGEST" --format '{{json .Manifest}}' | jq -er '.digest')"
[[ "$actual" == "$DIGEST" ]]
if [[ "$NEGATIVE" == true ]]; then
  [[ "$ATTEST_RESULT" == failure ]]
  if failure="$(docker buildx imagetools inspect "$IMAGE_TAG" --raw 2>&1)"; then
    echo '::error::Negative case published a release tag'
    exit 1
  fi
  # Authentication/network failures do not establish that the tag is absent.
  grep -Eqi 'manifest unknown|not found|404' <<< "$failure"
  echo 'PASS: incomplete SBOM evidence blocked release-tag publication' | tee -a "$GITHUB_STEP_SUMMARY"
  exit 0
fi
[[ "$ATTEST_RESULT" == success ]]
actual="$(docker buildx imagetools inspect "$IMAGE_TAG" --format '{{json .Manifest}}' | jq -er '.digest')"
[[ "$actual" == "$DIGEST" ]]
policy=(--repo "$GITHUB_REPOSITORY" --source-ref "$GITHUB_REF" --source-digest "$GITHUB_SHA"
  --signer-workflow "$GITHUB_REPOSITORY/.github/workflows/attest-image.yml" --signer-digest "$GITHUB_SHA"
  --bundle-from-oci)

while IFS= read -r digest; do
  gh attestation verify "oci://$IMAGE@$digest" "${policy[@]}" --predicate-type https://slsa.dev/provenance/v1
done < <(jq -r '[.digest] + [.platforms[].digest] | unique[]' "$REPORTS/image.json")

while IFS=$'\t' read -r platform digest; do
  key="${platform//\//-}"
  gh attestation verify "oci://$IMAGE@$digest" "${policy[@]}" \
    --predicate-type https://spdx.dev/Document/v2.3 --format json > "$RUNNER_TEMP/verified-sbom.json"
  jq -e --slurpfile expected "$REPORTS/$key.spdx.json" \
    'any(.[]; .verificationResult.statement.predicate == $expected[0])' "$RUNNER_TEMP/verified-sbom.json" >/dev/null
  # Run the verified child: Docker's classic store cannot cache both architectures
  # under the same multi-platform index digest.
  if [[ "$FIXTURE" == go ]]; then
    actual="$(docker run --rm --platform "$platform" --network none --cap-drop=ALL \
      --security-opt=no-new-privileges "$IMAGE@$digest")"
    [[ "$actual" == "hello from $platform" ]]
  else
    docker run --rm --platform "$platform" --network none --cap-drop=ALL \
      --security-opt=no-new-privileges "$IMAGE@$digest" go version
    docker run --rm --platform "$platform" --network none --cap-drop=ALL \
      --security-opt=no-new-privileges "$IMAGE@$digest" golangci-lint --version
  fi
  echo "PASS: $platform SBOM, signatures, digest and runtime" | tee -a "$GITHUB_STEP_SUMMARY"
done < <(jq -r '.platforms[] | [.platform, .digest] | @tsv' "$REPORTS/image.json")
echo "PASS: release tag $IMAGE_TAG preserves $DIGEST" | tee -a "$GITHUB_STEP_SUMMARY"
