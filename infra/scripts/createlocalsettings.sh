#!/usr/bin/env sh

set -eu

force=false
if [ "${1:-}" = "--force" ]; then
    force=true
elif [ "$#" -gt 0 ]; then
    echo "Usage: $0 [--force]" >&2
    exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
settings_path="$repo_root/local.settings.json"
temp_path="$settings_path.tmp"

if [ -f "$settings_path" ] && [ "$force" = false ]; then
    printf "%s already exists; leaving it unchanged.\n" "$settings_path"
    exit 0
fi

outputs=$(azd env get-values --output json)
sharepoint_runtime_url=$(printf '%s' "$outputs" | jq -r '.sharepointConnectionRuntimeUrl // empty')
sharepoint_site_url=$(printf '%s' "$outputs" | jq -r '.sharepointSiteUrl // .SHAREPOINT_SITE_URL // empty')
teams_runtime_url=$(printf '%s' "$outputs" | jq -r '.teamsConnectionRuntimeUrl // empty')
teams_team_id=$(printf '%s' "$outputs" | jq -r '.TEAMS_TEAM_ID // empty')
teams_channel_id=$(printf '%s' "$outputs" | jq -r '.TEAMS_CHANNEL_ID // empty')
content_understanding_endpoint=$(printf '%s' "$outputs" | jq -r '.contentUnderstandingEndpoint // empty')

if [ -z "$sharepoint_runtime_url" ] || [ -z "$sharepoint_site_url" ] ||
   [ -z "$teams_runtime_url" ] || [ -z "$teams_team_id" ] ||
   [ -z "$teams_channel_id" ] || [ -z "$content_understanding_endpoint" ]; then
    echo "Required azd outputs are missing. Run 'azd provision' first." >&2
    exit 1
fi

trap 'rm -f "$temp_path"' EXIT

jq -n \
    --arg sharepoint_runtime_url "$sharepoint_runtime_url" \
    --arg sharepoint_site_url "$sharepoint_site_url" \
    --arg teams_runtime_url "$teams_runtime_url" \
    --arg teams_team_id "$teams_team_id" \
    --arg teams_channel_id "$teams_channel_id" \
    --arg content_understanding_endpoint "$content_understanding_endpoint" \
    '
      {
        IsEncrypted: false,
        Values: {
          AzureWebJobsStorage: "UseDevelopmentStorage=true",
          FUNCTIONS_WORKER_RUNTIME: "dotnet-isolated",
          AZURE_CLIENT_ID: "",
          SHAREPOINTONLINE_CONNECTION_RUNTIME_URL: $sharepoint_runtime_url,
          SHAREPOINT_SITE_URL: $sharepoint_site_url,
          TEAMS_CONNECTION_RUNTIME_URL: $teams_runtime_url,
          TEAMS_TEAM_ID: $teams_team_id,
          TEAMS_CHANNEL_ID: $teams_channel_id,
          TEAMS_POST_AS: "Flow bot",
          TEAMS_POST_IN: "Channel",
          CONTENT_UNDERSTANDING_ENDPOINT: $content_understanding_endpoint
        }
      }
    ' > "$temp_path"

mv "$temp_path" "$settings_path"
trap - EXIT

printf "Created %s from azd deployment outputs.\n" "$settings_path"
