#!/usr/bin/env sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

"$script_dir/authorize-connections.sh"
"$script_dir/createlocalsettings.sh"
