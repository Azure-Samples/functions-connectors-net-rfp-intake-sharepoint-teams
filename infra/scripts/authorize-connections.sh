#!/usr/bin/env sh

set -eu

non_interactive=false
if [ "${1:-}" = "--non-interactive" ]; then
    non_interactive=true
elif [ "$#" -gt 0 ]; then
    echo "Usage: $0 [--non-interactive]" >&2
    exit 2
fi

if ! az extension show --name connector-namespace --query name -o tsv >/dev/null 2>&1; then
    echo "The 'connector-namespace' Azure CLI extension is required." >&2
    exit 1
fi

outputs=$(azd env get-values --output json)
resource_group_name=$(printf '%s' "$outputs" | jq -r '.resourceGroupName // empty')
connector_namespace_name=$(printf '%s' "$outputs" | jq -r '.connectorNamespaceName // empty')
sharepoint_connection_name=$(printf '%s' "$outputs" | jq -r '.sharepointConnectionName // empty')
teams_connection_name=$(printf '%s' "$outputs" | jq -r '.teamsConnectionName // empty')

if [ -z "$resource_group_name" ] || [ -z "$connector_namespace_name" ] ||
   [ -z "$sharepoint_connection_name" ] || [ -z "$teams_connection_name" ]; then
    echo "Required azd outputs are missing. Run 'azd provision' first." >&2
    exit 1
fi

open_url() {
    url=$1
    if command -v open >/dev/null 2>&1; then
        open "$url" >/dev/null 2>&1
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1
    else
        return 1
    fi
}

authorize_connection() {
    connection_name=$1
    friendly_hint=$2

    printf "\nAuthorizing connection '%s'...\n" "$connection_name"
    current_status=$(az connector-namespace connection show \
        -g "$resource_group_name" --namespace "$connector_namespace_name" \
        -n "$connection_name" --query properties.overallStatus -o tsv 2>/dev/null || true)

    if [ "$current_status" = "Connected" ]; then
        printf "Connection '%s' is already authorized.\n" "$connection_name"
        return
    fi

    consent_link=
    attempt=1
    while [ "$attempt" -le 5 ]; do
        consent_link=$(az connector-namespace connection list-consent-links \
            -g "$resource_group_name" --namespace "$connector_namespace_name" \
            --connection-name "$connection_name" \
            --parameters "[{parameterName:token,redirectUrl:'https://portal.azure.com'}]" \
            --query 'value[0].link' -o tsv 2>/dev/null || true)

        if [ -z "$consent_link" ]; then
            consent_link=$(az connector-namespace connection list-consent-links \
                -g "$resource_group_name" --namespace "$connector_namespace_name" \
                --connection-name "$connection_name" \
                --parameters "[{parameterName:token,redirectUrl:'https://portal.azure.com'}]" \
                --query link -o tsv 2>/dev/null || true)
        fi

        [ -n "$consent_link" ] && break
        if [ "$attempt" -lt 5 ]; then
            printf "Consent-link attempt %s failed. Retrying in 5 seconds...\n" "$attempt"
            sleep 5
        fi
        attempt=$((attempt + 1))
    done

    if [ -z "$consent_link" ]; then
        printf "Failed to create a consent link for '%s'.\n" "$connection_name" >&2
        exit 1
    fi

    printf "Consent URL: %s\n%s\n" "$consent_link" "$friendly_hint"
    if [ "$non_interactive" = false ] && ! open_url "$consent_link"; then
        echo "Unable to open a browser automatically. Paste the consent URL into your browser."
    fi

    deadline=$(( $(date +%s) + 300 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        sleep 3
        current_status=$(az connector-namespace connection show \
            -g "$resource_group_name" --namespace "$connector_namespace_name" \
            -n "$connection_name" --query properties.overallStatus -o tsv 2>/dev/null || true)
        [ "$current_status" = "Connected" ] && break
    done

    if [ "$current_status" != "Connected" ]; then
        printf "Timed out waiting for '%s' to reach Connected status.\n" "$connection_name" >&2
        exit 1
    fi

    printf "Connection '%s' is authorized.\n" "$connection_name"
}

authorize_connection "$sharepoint_connection_name" \
    "Sign in with an account that can access the SharePoint site."
authorize_connection "$teams_connection_name" \
    "Sign in with an account that can post to the target Teams channel."
