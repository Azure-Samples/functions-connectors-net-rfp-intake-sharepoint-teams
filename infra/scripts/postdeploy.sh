#!/usr/bin/env sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

echo "Configuring the deployed Function App trigger..."
sh "$script_dir/configure-trigger.sh" --target azure

echo "Checking connector authorization..."
sh "$script_dir/authorize-connections.sh"

printf "\nDone. RFP intake is configured end-to-end.\n"
