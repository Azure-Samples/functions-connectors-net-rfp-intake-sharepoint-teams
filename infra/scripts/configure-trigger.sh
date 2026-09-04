#!/usr/bin/env sh

set -eu

target=
callback_base_url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --target)
            [ "$#" -ge 2 ] || { echo "--target requires a value." >&2; exit 2; }
            target=$2
            shift 2
            ;;
        --callback-base-url)
            [ "$#" -ge 2 ] || { echo "--callback-base-url requires a value." >&2; exit 2; }
            callback_base_url=$2
            shift 2
            ;;
        *)
            echo "Usage: $0 --target local|azure [--callback-base-url URL]" >&2
            exit 2
            ;;
    esac
done

case "$target" in
    local|azure) ;;
    *) echo "--target must be 'local' or 'azure'." >&2; exit 2 ;;
esac

if ! az extension show --name connector-namespace --query name -o tsv >/dev/null 2>&1; then
    echo "The 'connector-namespace' Azure CLI extension is required." >&2
    exit 1
fi

outputs=$(azd env get-values --output json)
resource_group_name=$(printf '%s' "$outputs" | jq -r '.resourceGroupName // empty')
connector_namespace_name=$(printf '%s' "$outputs" | jq -r '.connectorNamespaceName // empty')
sharepoint_connection_name=$(printf '%s' "$outputs" | jq -r '.sharepointConnectionName // empty')
function_app_name=$(printf '%s' "$outputs" | jq -r '.functionAppName // empty')
subscription_id=$(printf '%s' "$outputs" | jq -r '.AZURE_SUBSCRIPTION_ID // empty')
sharepoint_site_url=$(printf '%s' "$outputs" | jq -r '.sharepointSiteUrl // empty')
sharepoint_library_name=$(printf '%s' "$outputs" | jq -r '.sharepointLibraryName // empty')
sharepoint_folder_path=$(printf '%s' "$outputs" | jq -r '.sharepointFolderPath // empty')

if [ -z "$resource_group_name" ] || [ -z "$connector_namespace_name" ] ||
   [ -z "$sharepoint_connection_name" ] || [ -z "$sharepoint_site_url" ] ||
   [ -z "$sharepoint_library_name" ]; then
    echo "Required azd outputs are missing. Run 'azd provision' first." >&2
    exit 1
fi

function_name=OnNewFile
trigger_name="${sharepoint_connection_name}-onnewfile"
host_keys_file=
notification_file=

cleanup() {
    for file in "$host_keys_file" "$notification_file"; do
        [ -n "$file" ] || continue
        attempt=1
        while [ "$attempt" -le 5 ] && [ -e "$file" ]; do
            rm -f -- "$file" 2>/dev/null || true
            [ ! -e "$file" ] && break
            sleep 1
            attempt=$((attempt + 1))
        done
        if [ -e "$file" ]; then
            printf "Warning: Could not delete temporary callback file: %s\n" "$file" >&2
        fi
    done
}
trap cleanup EXIT HUP INT TERM

if [ "$target" = local ]; then
    if [ -z "$callback_base_url" ]; then
        echo "--callback-base-url is required for a local target." >&2
        exit 2
    fi

    callback_base=${callback_base_url%/}
    case "$callback_base" in
        https://*) ;;
        *) echo "--callback-base-url must be a public HTTPS URL." >&2; exit 2 ;;
    esac

    host_blob_name=$(az storage blob list \
        --container-name azure-webjobs-secrets \
        --connection-string UseDevelopmentStorage=true \
        --query 'sort_by([], &properties.lastModified)[-1].name' -o tsv)

    if [ -z "$host_blob_name" ]; then
        echo "Could not find local Function host keys in Azurite. Start Azurite and run 'func start --enableAuth' first." >&2
        exit 1
    fi

    host_keys_file=$(mktemp "${TMPDIR:-/tmp}/connector-host-keys.XXXXXX.json")
    az storage blob download \
        --container-name azure-webjobs-secrets \
        --name "$host_blob_name" \
        --connection-string UseDevelopmentStorage=true \
        --file "$host_keys_file" --no-progress --overwrite -o none

    connector_extension_key=$(jq -r \
        '.systemKeys[]? | select(.name == "connector_extension") | (.value // .val // empty)' \
        "$host_keys_file" | head -n 1)
    if [ -z "$connector_extension_key" ]; then
        echo "The local connector_extension system key was not found. Ensure the Connector extension loaded successfully." >&2
        exit 1
    fi

    encoded_key=$(jq -nr --arg value "$connector_extension_key" '$value|@uri')
    callback_url="$callback_base/runtime/webhooks/connector?functionName=$function_name&code=$encoded_key"
    metadata="{destinationType:functionApp,functionName:$function_name,recurrenceFrequency:Minute,recurrenceInterval:'5'}"
    target_label=Local
else
    if [ -z "$function_app_name" ] || [ -z "$subscription_id" ]; then
        echo "Function App deployment outputs are missing. Run 'azd deploy' first." >&2
        exit 1
    fi

    connector_extension_key=$(az functionapp keys list \
        -g "$resource_group_name" -n "$function_app_name" \
        --query systemKeys.connector_extension -o tsv)
    if [ -z "$connector_extension_key" ]; then
        printf "Could not fetch the connector_extension system key from '%s'.\n" "$function_app_name" >&2
        exit 1
    fi

    encoded_key=$(jq -nr --arg value "$connector_extension_key" '$value|@uri')
    callback_url="https://$function_app_name.azurewebsites.net/runtime/webhooks/connector?functionName=$function_name&code=$encoded_key"
    metadata="{destinationType:functionApp,functionAppName:$function_app_name,functionAppResourceGroup:$resource_group_name,functionAppSubscriptionId:$subscription_id,functionName:$function_name,recurrenceFrequency:Minute,recurrenceInterval:'5'}"
    target_label=Azure
fi

trigger_parameters="[{name:dataset,value:'$sharepoint_site_url'},{name:table,value:'$sharepoint_library_name'}"
if [ -n "$sharepoint_folder_path" ]; then
    trigger_parameters="$trigger_parameters,{name:folderPath,value:'$sharepoint_folder_path'}"
fi
trigger_parameters="$trigger_parameters]"

notification_file=$(mktemp "${TMPDIR:-/tmp}/connector-notification-details.XXXXXX.json")
jq -cn --arg callbackUrl "$callback_url" '{callbackUrl: $callbackUrl}' >"$notification_file"

az connector-namespace trigger delete \
    -g "$resource_group_name" --namespace "$connector_namespace_name" \
    -n "$trigger_name" --yes >/dev/null 2>&1 || true

az connector-namespace trigger create \
    -g "$resource_group_name" --namespace "$connector_namespace_name" \
    -n "$trigger_name" \
    --connection-details "{connectionName:$sharepoint_connection_name,connectorName:sharepointonline}" \
    --operation-name GetOnNewFileItems \
    --parameters "$trigger_parameters" \
    --notification-details "@$notification_file" \
    --description "When a file is created (properties only) - $target_label" \
    --metadata "$metadata" \
    --state Enabled \
    -o none

printf "SharePoint trigger now targets %s.\n" "$target_label"
if [ "$target" = local ]; then
    printf "Callback: %s/runtime/webhooks/connector?functionName=%s&code=<redacted>\n" \
        "$callback_base" "$function_name"
fi
