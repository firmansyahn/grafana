#!/bin/sh
# Checks each PrometheusRule in this directory and runs its unit tests:
#
#   alerts/test.sh
#
# promtool reads plain rule files, not PrometheusRules, so each one's groups
# are written out as <name>.rules.yaml in a temporary directory first, beside a
# copy of tests/<name>.test.yaml. Needs promtool and mikefarah's yq v4 (tested
# with promtool 3.14 and yq 4.53); set PROMTOOL or YQ for binaries that are not
# on PATH.
set -eu

PROMTOOL=${PROMTOOL:-promtool}
YQ=${YQ:-yq}

cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for rules in *.yaml; do
	name=${rules%.yaml}
	"$YQ" '.spec' "$rules" >"$tmp/$name.rules.yaml"
	"$PROMTOOL" check rules --lint-fatal "$tmp/$name.rules.yaml"
	if [ -f "tests/$name.test.yaml" ]; then
		cp "tests/$name.test.yaml" "$tmp/"
		"$PROMTOOL" test rules "$tmp/$name.test.yaml"
	fi
done
