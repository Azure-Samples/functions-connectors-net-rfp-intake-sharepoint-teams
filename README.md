# Automated RFP Intake with SharePoint, Document Intelligence, and Teams

> A customer submits an RFP document to a shared SharePoint library. An Azure
> Function picks it up, Azure Document Intelligence extracts its text and
> layout, deterministic routing rules identify the required capabilities, and a
> summary card is posted to a Microsoft Teams channel.

This .NET sample shows how to implement the scenario above using the
[Azure Functions Connector extension](https://github.com/Azure/azure-functions-connector-extension)
and the
[Azure Connectors .NET SDK](https://github.com/Azure/Connectors-NET-SDK). It
uses two connections, SharePoint Online and Microsoft Teams, created in an
[Azure Connector Namespace](https://learn.microsoft.com/azure/connector-namespace/connector-namespace-overview),
and leverages the function app's managed identity for authentication.

## End-to-end flow

```mermaid
flowchart LR
    A["📄 RFP uploaded to SharePoint"]
    A -->|"Trigger: When a file is created (properties only)"| B

    subgraph FA["Function App"]
      B["OnNewFile function"]
    end

    subgraph CN["Connector Namespace"]
      direction TB
      SP["sharepointonline connection"]
      TM["teams connection"]
    end

    B -->|"Get file content"| SP
    SP -->|"RFP bytes"| B
    B -->|"Analyze document"| C["Azure Document Intelligence<br/>prebuilt-layout"]
    C -->|"Extracted text and layout"| B
    B -->|"Apply capability and SME routing rules"| B
    B -->|"Post Adaptive Card"| TM
    TM --> E["💬 Teams channel<br/>New RFP card"]
```

### Architecture

![Architecture diagram](docs/images/architecture.svg)

## Prerequisites

- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI (`az`)](https://learn.microsoft.com/cli/azure/install-azure-cli) ≥
  2.75.0
- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local?tabs=macos%2Cisolated-process%2Cnode-v4%2Cpython-v2%2Chttp-trigger%2Ccontainer-apps&pivots=programming-language-csharp#install-the-azure-functions-core-tools)
- [.NET 10 SDK](https://dotnet.microsoft.com/download)
- [`jq`](https://jqlang.org/download/) (macOS and Linux only)
- [`connector-namespace` Azure CLI extension](https://github.com/Azure/Connectors/tree/main/public-preview/connector-namespace-cli)
- [Visual Studio Code](https://code.visualstudio.com/)
- A SharePoint site + document library to receive RFPs.
- RFPs with a `Customer`, `Client`, or `Organization` field and a numbered
  `Required Capabilities` section. The included sample demonstrates the
  expected structure.
- A Microsoft Teams **team** and **public channel** to post to. Posting to
  **private channels is not supported**. The Teams **Workflows** app must be
  allowed in the
  [Teams admin center](https://admin.teams.microsoft.com/policies/manage-apps)
  (required by the card-posting action). See the
  [Microsoft Teams connector documentation](https://learn.microsoft.com/connectors/teams/?tabs=text1%2Cdotnet)
  for details.

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

3. Inside the root directory, create an `azd` environment. This becomes the
   resource group name:

   ```pwsh
   azd env new rfp-demo
   ```

4. Provision resoures:

   ```pwsh
   azd provision
   ```

   You get prompted for these values:

   - **Azure Subscription** (`00000000-0000-0000-0000-000000000000`):
     subscription where the resources will be provisioned.
   - **Location** (`East US 2`): Azure region where resources will be
     deployed.
   - **`SHAREPOINT_SITE_URL`**
     (`https://contoso.sharepoint.com/sites/RFPs`): SharePoint site that
     contains the document library to monitor.
   - **`SHAREPOINT_LIBRARY_NAME`** (`Documents`): SharePoint document
     library that contains the RFP files. This is not a folder name.
   - **`TEAMS_TEAM_ID`** (`00000000-0000-0000-0000-000000000000`):
     Microsoft 365 group ID of the team that receives the summary card.
   - **`TEAMS_CHANNEL_ID`** (`19:example-channel-id@thread.tacv2`):
     channel ID within the team that receives the summary card.

After provisioning, the platform-specific `authorize-connections` script opens a
browser to authenticate the SharePoint and Teams connections. For each
authorization page, select **I have verified this request and trust the
source**, then select **Allow access**. Connections that are already
authenticated are skipped.

## Test locally

### Run the app locally

1. Enter the required values in `local.settings.json`. The SharePoint and Teams
   connection runtime URLs are available on their connection pages in the
   Connector Namespace portal.

   > **Note:** Leave `AZURE_CLIENT_ID` empty when running locally. This is
   > referring to the managed identity client ID of the Function App and is only
   > used when the app is running in Azure.

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

   > **Note:** Always use `--enableAuth` when exposing your app through a dev
   > tunnel. Without it, your function endpoint is completely unauthenticated on
   > the public internet.

4. In VS Code, open the integrated terminal (**Control+Shift+\`** or
   **Ctrl+Shift+\`**). Open the **Ports** view in the Panel region, then select
   **Forward a Port**.
5. Enter port `7071`. Port forwarding starts, and the **Ports** view displays a
   **Forwarded Address**, such as `https://<id>-7071.uks1.devtunnels.ms`. If you
   haven't previously signed in to GitHub from VS Code, complete the sign-in
   prompt.
6. Right-click port `7071`, then select **Port Visibility → Public**. Public
   ports don't require sign-in. Select **Continue** in the confirmation dialog.
7. Copy the **Forwarded Address**, then create the SharePoint trigger and point
   it to your local Function host:

   On macOS or Linux:

   ```sh
   sh ./infra/scripts/configure-trigger.sh \
     --target local \
     --callback-base-url "https://<id>-7071.uks1.devtunnels.ms"
   ```

   On Windows:

   ```powershell
   pwsh ./infra/scripts/configure-trigger.ps1 `
     -Target Local `
     -CallbackBaseUrl "https://<id>-7071.uks1.devtunnels.ms"
   ```

   The trigger polls the configured SharePoint library every five minutes and
   sends new-file notifications through the public dev tunnel. Rerun this
   command whenever the forwarded address changes.

## Upload file

1. Upload `sample-data/contoso-rfp.pdf` to the monitored SharePoint library.
2. The function runs within the trigger's polling interval (~5 min).
3. A **"New RFP received"** Adaptive Card appears in your Teams channel:

   ```text
   📄 New RFP received
   Customer:      Contoso Ltd.
   Source file:   contoso-rfp.pdf

   Required capabilities
   - Azure AI
   - Data Platform
   - Identity & Security
   - Integration & Automation
   - Observability & Operations

   Recommended SMEs
   - AI Specialist
   - Data Platform Engineer
   - Security Architect
   - Integration Architect
   - Cloud Operations Specialist
   ```

   The `prebuilt-layout` model supports PDF, image, Microsoft Office, and HTML
   documents. Document Intelligence performs OCR and layout extraction; the
   application then uses explicit, testable rules to parse the customer and
   numbered capability headings and map them to SME roles. No generative model
   is used.

### Run automated tests

Run the deterministic parser tests:

```pwsh
dotnet test tests/RfpApp.Tests/RfpApp.Tests.csproj --filter "Category!=Integration"
```

To verify the included PDF against a live Document Intelligence account, sign
in with `az login`, grant your identity the `Cognitive Services User` role, and
run:

```pwsh
$env:DOCUMENT_INTELLIGENCE_ENDPOINT = "https://<resource>.cognitiveservices.azure.com/"
dotnet test tests/RfpApp.Tests/RfpApp.Tests.csproj --filter "Category=Integration"
```

## Deploy Function App to Azure

1. Deploy the Function App:

   ```pwsh
   azd deploy
   ```

2. Upload a newly named file to the monitored SharePoint library.

### What happens in the process

1. **RFP arrives.** A file is uploaded to the monitored SharePoint document
   library.
2. **Trigger.** The Connector Namespace polls the SharePoint **"When a file
   is created"** trigger (`GetOnNewFileItems`) and calls the function's
   `OnNewFile` callback. The trigger returns properties only, so the content
   must be fetched separately.
3. **Fetch content.** The function calls the SharePoint **"Get file content"**
   action (`SharePointOnlineClient.GetFileContentAsync`) with the file
   identifier from the trigger payload.
4. **Extract the document.** The original file bytes are sent to Azure Document
   Intelligence's `prebuilt-layout` model, which returns OCR text and document
   structure.
5. **Route the RFP.** The function parses the customer and numbered headings in
   the `Required Capabilities` section, then maps recognized capability terms
   to SME roles with deterministic routing rules.
6. **Notify.** The function builds an Adaptive Card and posts it to a Teams
   channel with the **"Post card in a chat or channel"** action
   (`TeamsClient.PostCardToConversationAsync`).

## Clean up

```pwsh
azd down --purge
```

## How auth works (no secrets)

- **Function-app user-assigned managed identity:** Calls the SharePoint and
  Teams connection runtime URLs and Azure Document Intelligence. It has an
  access policy on each connection and the `Cognitive Services User` role on
  the Document Intelligence account.
- **Connector Namespace system managed identity:** Polls the SharePoint
  trigger and delivers callbacks.
- **Callback authorization:** Uses the `connector_extension` system key on the
  callback URL. This sample does not use App Service built-in authentication.

## Deployment scripts

The scripts in `infra/scripts` complete setup that cannot be handled entirely by
the Bicep deployment:

- **`authorize-connections.ps1` / `.sh`:** Opens the OAuth consent flow and
  waits for the SharePoint and Teams connections to become authenticated.
  Connections that are already authenticated are skipped. This script is
  needed because Bicep creates the connections, but a user must grant consent.
  `azd provision` runs the platform-specific script through the
  `postprovision` hook.
- **`configure-trigger.ps1` / `.sh`:** Creates the SharePoint new-file trigger
  and points it to a local dev tunnel or the deployed Function App. It adds the
  `connector_extension` system key to the callback URL. This script runs after
  the function is available because the callback URL and key are not known
  earlier. Changing targets requires the trigger to be deleted and recreated.
- **`postdeploy.ps1` / `.sh`:** Configures the trigger for Azure and checks
  both connection authorizations. `azd deploy` runs the platform-specific
  script through the `postdeploy` hook, replacing any local callback with the
  deployed Function App callback.

## Project layout

```text
functions-connectors-net-rfp-intake-sharepoint-teams/
├── .vscode/
│   ├── extensions.json
│   ├── launch.json
│   ├── settings.json
│   └── tasks.json
├── Program.cs
├── RfpDocumentAnalyzer.cs
├── RfpFunctions.cs
├── azure.yaml
├── docs/
│   └── images/
│       └── architecture.svg
├── host.json
├── local.settings.json
├── rfpApp.csproj
├── sample-data/
│   └── contoso-rfp.pdf
├── tests/
│   └── RfpApp.Tests/
│       ├── RfpAnalysisParserTests.cs
│       └── RfpApp.Tests.csproj
└── infra/
    ├── abbreviations.json
    ├── bicepconfig.json
    ├── connectorNamespace.bicep
    ├── main.bicep
    ├── main.json
    ├── main.parameters.json
    ├── documentIntelligence.bicep
    └── scripts/
        ├── authorize-connections.ps1
        ├── authorize-connections.sh
        ├── configure-trigger.ps1
        ├── configure-trigger.sh
        ├── postdeploy.ps1
        └── postdeploy.sh
```

## Troubleshooting

If the summary card is not posted to the specified Teams channel, check the
following:

- In the Connector Namespace portal, verify that the SharePoint trigger's
  callback URL points to the intended local dev tunnel or deployed Function App
  and includes the correct `connector_extension` access key.
- For local testing, verify that port `7071` is forwarded and the dev tunnel
  visibility is **Public**.
- Ensure Azurite is running before starting the function locally and configuring
  the trigger.
- Leave `AZURE_CLIENT_ID` empty in `local.settings.json` for local development.
  The Function App's managed identity client ID is only needed when running in
  Azure.
- Confirm the uploaded file is in a
  [format supported by the `prebuilt-layout` model](https://learn.microsoft.com/azure/ai-services/document-intelligence/prebuilt/layout?view=doc-intel-4.0.0#input-requirements).
- Confirm the RFP contains a numbered `Required Capabilities` section. The
  deterministic parser intentionally returns empty capability and SME lists
  rather than inventing requirements that are not present.

## Resources

- [Azure Functions Connector extension](https://github.com/Azure/azure-functions-connector-extension)
  — the trigger binding used here.
- [Azure Connectors .NET SDK](https://github.com/Azure/Connectors-NET-SDK) —
  typed clients for SharePoint, Teams, and other connectors.
- [Azure Document Intelligence layout model](https://learn.microsoft.com/azure/ai-services/document-intelligence/prebuilt/layout?view=doc-intel-4.0.0)
  — OCR and layout extraction used by this sample.
