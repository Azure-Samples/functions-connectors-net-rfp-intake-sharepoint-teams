# Automated RFP Intake with SharePoint, Azure OpenAI, and Teams

> A customer submits an RFP document to a shared SharePoint library. An Azure Function picks it
> up, an AI model extracts the requirements, and a summary card is posted to a Microsoft Teams
> channel so the right people can respond.

This .NET sample shows how to implement the scenario above using the
[Azure Functions Connector extension](https://github.com/Azure/azure-functions-connector-extension)
and the [Azure Connectors .NET SDK](https://github.com/Azure/Connectors-NET-SDK). It uses two
connections, SharePoint Online and Microsoft Teams, created in an
[Azure Connector Namespace](https://learn.microsoft.com/azure/connector-namespace/connector-namespace-overview),
and leverages the function app's managed identity for authentication.

## End-to-end flow

```mermaid
flowchart LR
    A["📄 Customer uploads an RFP<br/>to the SharePoint RFP library"]
    A -->|"Trigger: When a file is created (properties only)"| B

    subgraph FA["Function App"]
      B["OnNewFile function"]
    end

    subgraph CN["Connector Namespace"]
      direction TB
      SP["sharepointonline connection"]
      TM["teams connection"]
    end

    B -->|"Action: Get file content<br/>GetFileContentAsync(site, fileId) → byte[]"| SP
    SP -->|"RFP text"| B
    B -->|"prompt with RFP text"| C["Azure OpenAI (GPT-4o)<br/>chat completion → JSON"]
    C -->|"{ customer, requiredCapabilities[], recommendedSMEs[] }"| B
    B -->|"Action: Post card in a chat or channel<br/>PostCardToConversationAsync — non-deprecated"| TM
    TM --> E["💬 Teams channel — Adaptive Card<br/>New RFP received · Blue Cloud Inc.<br/>Capabilities: Azure AI, Data Platform, Identity<br/>Recommended SMEs: AI Specialist, Security Architect"]
```

### Architecture

```mermaid
flowchart LR
    sp@{ icon: "mdi:microsoft-sharepoint", form: "square", label: "SharePoint RFP library", pos: "b" }

    subgraph FA["🟦 Azure Function App"]
        func@{ icon: "mdi:lightning-bolt", form: "square", label: "OnNewFile function", pos: "b" }
    end

    subgraph NS["🟩 Connector Namespace"]
        spconn@{ icon: "mdi:transit-connection-variant", form: "square", label: "SharePoint connection", pos: "b" }
        tmconn@{ icon: "mdi:transit-connection-variant", form: "square", label: "Teams connection", pos: "b" }
    end

    oai@{ icon: "mdi:robot-happy", form: "square", label: "Azure OpenAI (GPT-4o)", pos: "b" }
    teams@{ icon: "mdi:microsoft-teams", form: "square", label: "Teams channel", pos: "b" }

    sp --> spconn
    spconn --> func
    func --> oai
    func --> tmconn
    tmconn --> teams
```

## Prerequisites

- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI (`az`)](https://learn.microsoft.com/cli/azure/install-azure-cli) ≥ 2.75.0
- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local?tabs=macos%2Cisolated-process%2Cnode-v4%2Cpython-v2%2Chttp-trigger%2Ccontainer-apps&pivots=programming-language-csharp#install-the-azure-functions-core-tools)
- [.NET 10 SDK](https://dotnet.microsoft.com/download)
- [`connector-namespace` Azure CLI extension](https://github.com/Azure/Connectors/tree/main/public-preview/connector-namespace-cli)
- [Visual Studio Code](https://code.visualstudio.com/)
- A SharePoint site + document library to receive RFPs.
- A Microsoft Teams **team** and **public channel** to post to. Posting to **private channels is not supported**. The Teams **Workflows** app must be allowed in the [Teams admin center](https://admin.teams.microsoft.com/policies/manage-apps) (required by the card-posting action). See the [Microsoft Teams connector documentation](https://learn.microsoft.com/connectors/teams/?tabs=text1%2Cdotnet) for details.

## Provision resources
1. Clone the repo:
    ```pwsh
    git clone https://github.com/Azure-Samples/functions-connectors-net-rfp-intake-sharepoint-teams.git
    ```

2. Open a terminal and log in to Azure:

    ```pwsh
    azd auth login
    az login
    ```

3. Inside the root directory, create an `azd` environment. This becomes the resource group name:

    ```pwsh
    azd env new rfp-demo
    ```

4. Provision resoures:

    ```pwsh
    azd provision
    ```

    You get prompted for these values:

    | Prompt | Example value | Explanation |
    |---|---|---|
    | Azure Subscription| `00000000-0000-0000-0000-000000000000`| Resources will be provisioned in this subscription. |
    | Location | `East US 2` | The region where resources will be deployed in. |
    | `SHAREPOINT_SITE_URL` | `https://contoso.sharepoint.com/sites/RFPs` | URL of the SharePoint site containing the document library to monitor. |
    | `SHAREPOINT_LIBRARY_NAME` | `Documents` | Name of the SharePoint document library containing the RFP files. This is not a folder name. |
    | `TEAMS_TEAM_ID` | `00000000-0000-0000-0000-000000000000` | Microsoft 365 group ID of the Teams team that receives the summary card. |
    | `TEAMS_CHANNEL_ID` | `19:example-channel-id@thread.tacv2` | ID of the channel within that team that receives the summary card. |

After provisioning, `authorize-connections.ps1` opens a browser to authenticate the SharePoint and
Teams connections. For each authorization page, select **I have verified this request and trust the
source**, then select **Allow access**. Connections that are already authenticated are skipped.

## Test locally

### Run the app locally

1. Enter the required values in `local.settings.json`. The SharePoint and Teams connection runtime
   URLs are available on their connection pages in the Connector Namespace portal.

   > **Note:** Leave `AZURE_CLIENT_ID` empty when running locally. This is referring to the managed identity client ID of the Function App and is only used when the app is running in Azure.

   To find your Teams team ID, list the teams you have joined:

   ```pwsh
   az rest --method get \
     --url "https://graph.microsoft.com/v1.0/me/joinedTeams" \
     --query "value[].{name:displayName,teamId:id}" -o table
   ```

   Then use the team ID to list its channels:

   ```pwsh
   az rest --method get \
     --url "https://graph.microsoft.com/v1.0/teams/<team-id>/channels" \
     --query "value[].{name:displayName,channelId:id}" -o table
   ```

2. Start Azurite in a separate terminal:

   ```pwsh
   azurite --silent --location ~/.azurite/connectors-sample
   ```

3. Start the app with authentication enabled:

   ```pwsh
   func start --enableAuth
   ```

   > **Note:** Always use `--enableAuth` when exposing your app through a dev tunnel. Without it,
   > your function endpoint is completely unauthenticated on the public internet.

4. In VS Code, open the integrated terminal (**Control+Shift+\`** or
   **Ctrl+Shift+\`**). Open the **Ports** view in the Panel region, then select
   **Forward a Port**.
5. Enter port `7071`. Port forwarding starts, and the **Ports** view displays a
   **Forwarded Address**, such as `https://<id>-7071.uks1.devtunnels.ms`. If you haven't previously signed in to GitHub from VS Code, complete the sign-in prompt.
6. Right-click port `7071`, then select **Port Visibility → Public**. Public ports don't require
   sign-in. Select **Continue** in the confirmation dialog.
7. Copy the **Forwarded Address**, then create the SharePoint trigger and point it to your local
   Function host:

   ```pwsh
   ./infra/scripts/configure-trigger.ps1 `
     -Target Local `
     -CallbackBaseUrl "https://<id>-7071.uks1.devtunnels.ms"
   ```

   The trigger polls the configured SharePoint library every five minutes and sends new-file
   notifications through the public dev tunnel. Rerun this command whenever the forwarded address
   changes.

## Upload file

1. Upload `sample-data/bluecloud-rfp.txt` to the monitored SharePoint library.
2. The function runs within the trigger's polling interval (~5 min).
3. A **"New RFP received"** Adaptive Card appears in your Teams channel:

   ```
   📄 New RFP received
   Customer:      Blue Cloud Inc.
   Source file:   bluecloud-rfp.txt

   Required capabilities
   - Azure AI
   - Data Platform
   - Identity

   Recommended SMEs
   - AI Specialist
   - Security Architect
   ```

    This sample assumes **text-style RFPs** (`.txt` / `.md`). Binary formats (PDF, DOCX) would need a
    document-extraction step (e.g. Azure AI Document Intelligence) before the Azure OpenAI call, which is **not** included in the sample.

## Deploy Function App to Azure

1. Deploy the Function App:

    ```pwsh
    azd deploy
    ```

2. Upload a newly named file to the monitored SharePoint library.

### What happens in the process

| # | Stage | How |
|---|-------|-----|
| 1 | **RFP arrives** | A file is uploaded to the monitored SharePoint document library. |
| 2 | **Trigger** | The Connector Namespace polls the SharePoint **"When a file is created"** trigger (`GetOnNewFileItems`) and calls the function's callback (`OnNewFile`). The trigger returns **properties** only, so the content needs to be fetched separately. |
| 3 | **Fetch content** | The function calls the SharePoint **"Get file content"** action (`SharePointOnlineClient.GetFileContentAsync`) using the file identifier from the trigger payload. |
| 4 | **Extract requirements** | The RFP text is sent to **Azure OpenAI** (GPT-4o), which returns structured JSON: `customer`, `requiredCapabilities`, `recommendedSMEs`. |
| 5 | **Notify** | The function builds an Adaptive Card and posts it to a Teams channel with the **"Post card in a chat or channel"** action (`TeamsClient.PostCardToConversationAsync`). |

## Clean up

```pwsh
azd down --purge
```

## How auth works (no secrets)

| Component | Role |
|---|---|
| **Function-app user-assigned MI** | Calls the SharePoint + Teams connection runtime URLs and Azure OpenAI. Granted an access policy on each connection and `Cognitive Services OpenAI User` on the OpenAI account. |
| **Connector Namespace system MI** | Polls the SharePoint trigger and delivers callbacks. |
| **Callback authorization** | The connector `connector_extension` system key on the callback URL (default). This sample does **not** use App Service built-in auth. |

## Deployment scripts

The scripts in `infra/scripts` complete setup that cannot be handled entirely by the Bicep
deployment:

| Script | What it does | Why it is needed |
|---|---|---|
| `authorize-connections.ps1` | Opens the OAuth consent flow for the SharePoint and Teams connections, then waits for each connection to become authenticated. Connections that are already authenticated are skipped. | Bicep creates the connections, but a user must grant consent before they can access SharePoint or Teams. `azd provision` runs this script through the `postprovision` hook. |
| `configure-trigger.ps1` | Creates the SharePoint new-file trigger and points it to either a local dev tunnel (`-Target Local`) or the deployed Function App (`-Target Azure`). It retrieves the appropriate `connector_extension` system key and adds it to the callback URL. | The callback URL and `connector_extension` system key are not available until the function is running locally or deployed to Azure, so the authenticated callback must be configured afterward. Changing between those targets requires the trigger to be deleted and recreated. |
| `postdeploy.ps1` | Runs `configure-trigger.ps1 -Target Azure`, then checks the SharePoint and Teams connection authorization. | `azd deploy` uses this script through the `postdeploy` hook to replace any local callback with the deployed Function App callback and leave the Azure workflow ready to use. |

## Project layout

```
connectors-integrated-demo/
├── Program.cs               # DI: SharePoint + Teams SDK clients, Azure OpenAI client (managed identity)
├── RfpFunctions.cs          # OnNewFile: trigger → get content → OpenAI → post Teams card
├── host.json
├── azure.yaml               # azd config + post-provision and post-deploy hooks
├── rfpApp.csproj
├── local.settings.json.sample
├── Architecture.md          # deep-dive platform architecture (connectors × functions)
├── sample-data/
│   └── bluecloud-rfp.txt    # Text-style sample RFP to upload for testing
└── infra/
    ├── main.bicep           # Function app, storage, App Insights, namespace, OpenAI, app settings
    ├── connectorNamespace.bicep  # SharePoint + Teams connections + MI access policies
    ├── openai.bicep         # Azure OpenAI account + GPT-4o deployment + role assignment
    ├── main.parameters.json
    └── scripts/
        ├── authorize-connections.ps1 # OAuth-authorizes both connections
        ├── configure-trigger.ps1     # Points the trigger to local or Azure
        └── postdeploy.ps1            # Restores the Azure callback after deployment
```

## Troubleshooting

If the summary card is not posted to the specified Teams channel, check the following:

- In the Connector Namespace portal, verify that the SharePoint trigger's callback URL points to
  the intended local dev tunnel or deployed Function App and includes the correct
  `connector_extension` access key.
- For local testing, verify that port `7071` is forwarded and the dev tunnel visibility is
  **Public**.
- Ensure Azurite is running before starting the function locally and configuring the trigger.
- Leave `AZURE_CLIENT_ID` empty in `local.settings.json` for local development. The Function App's
  managed identity client ID is only needed when running in Azure.

## Resources

- [Azure Functions Connector extension](https://github.com/Azure/azure-functions-connector-extension) — the trigger binding used here.
- [Azure Connectors .NET SDK](https://github.com/Azure/Connectors-NET-SDK) — typed clients for SharePoint, Teams, and other connectors.
