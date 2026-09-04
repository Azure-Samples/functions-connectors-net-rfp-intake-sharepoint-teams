// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using Azure.AI.OpenAI;
using Azure.Connectors.Sdk.SharePointOnline;
using Azure.Connectors.Sdk.Teams;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.Exporter;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.OpenTelemetry;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenTelemetry;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING")))
        {
            services.AddOpenTelemetry()
                .UseFunctionsWorkerDefaults()
                .UseAzureMonitorExporter();
        }

        // One credential for everything. In Azure this resolves to the function app's
        // user-assigned managed identity (AZURE_CLIENT_ID); locally it falls back to the
        // signed-in az/VS/CLI identity via DefaultAzureCredential.
        var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
        {
            ManagedIdentityClientId = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID"),
        });

        // SharePoint Online connector client — used to call the "Get file content" action
        // against the connection's runtime URL (authorized by the MI access policy).
        var sharePointRuntimeUrl = RequireEnv("SHAREPOINTONLINE_CONNECTION_RUNTIME_URL");
        services.AddSingleton(new SharePointOnlineClient(new Uri(sharePointRuntimeUrl), credential));

        // Teams connector client — used to call the "Post card in a chat or channel" action.
        var teamsRuntimeUrl = RequireEnv("TEAMS_CONNECTION_RUNTIME_URL");
        services.AddSingleton(new TeamsClient(new Uri(teamsRuntimeUrl), credential));

        // Azure OpenAI client — used to reason over the RFP text and extract requirements.
        var openAiEndpoint = RequireEnv("AZURE_OPENAI_ENDPOINT");
        services.AddSingleton(new AzureOpenAIClient(new Uri(openAiEndpoint), credential));
    })
    .Build();

host.Run();

static string RequireEnv(string name)
{
    var value = Environment.GetEnvironmentVariable(name);
    if (string.IsNullOrWhiteSpace(value))
    {
        throw new InvalidOperationException(
            $"Required app setting '{name}' is not configured. Set it in local.settings.json (local) or app settings (Azure).");
    }

    return value;
}
