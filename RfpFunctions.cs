// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System.Text.Json;
using Azure.Connectors.Sdk.SharePointOnline;
using Azure.Connectors.Sdk.SharePointOnline.Models;
using Azure.Connectors.Sdk.Teams;
using Azure.Connectors.Sdk.Teams.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Extensions.Connector;
using Microsoft.Extensions.Logging;

namespace RfpApp;

/// <summary>
/// End-to-end RFP intake:
///   SharePoint "When a file is created (properties only)" trigger
///     -> SharePoint "Get file content" action (fetch the RFP document)
///       -> Azure Document Intelligence (extract text and layout)
///         -> deterministic RFP routing rules (identify capabilities and SMEs)
///         -> Teams "Post card in a chat or channel" action (notify the team).
/// </summary>
public class RfpFunctions
{
    private readonly ILogger<RfpFunctions> _logger;
    private readonly SharePointOnlineClient _sharePoint;
    private readonly TeamsClient _teams;
    private readonly RfpDocumentAnalyzer _documentAnalyzer;

    public RfpFunctions(
        ILogger<RfpFunctions> logger,
        SharePointOnlineClient sharePoint,
        TeamsClient teams,
        RfpDocumentAnalyzer documentAnalyzer)
    {
        _logger = logger;
        _sharePoint = sharePoint;
        _teams = teams;
        _documentAnalyzer = documentAnalyzer;
    }

    [Function("OnNewFile")]
    public async Task OnNewFile(
        [ConnectorTrigger] SharePointOnlineOnNewFileItemsTriggerPayload payload,
        CancellationToken cancellationToken)
    {
        var items = payload.Body?.Value;
        if (items is null || items.Count == 0)
        {
            _logger.LogInformation("OnNewFile fired with no items.");
            return;
        }

        var siteAddress = RequireEnv("SHAREPOINT_SITE_URL");

        foreach (var item in items)
        {
            var fileIdentifier = GetProperty(item, "{Identifier}", "Identifier", "{FullPath}", "Id");
            var fileName = GetProperty(item, "{FilenameWithExtension}", "{Name}", "Name") ?? "(unknown)";

            if (string.IsNullOrWhiteSpace(fileIdentifier))
            {
                _logger.LogWarning("Skipping '{FileName}': no file identifier in the trigger payload.", fileName);
                continue;
            }

            _logger.LogInformation("New RFP detected: {FileName}", fileName);

            try
            {
                // 1. Fetch the original RFP bytes from SharePoint.
                var document = await GetRfpDocumentAsync(siteAddress, fileIdentifier, cancellationToken);
                if (document.Length == 0)
                {
                    _logger.LogWarning("'{FileName}' was empty; skipping.", fileName);
                    continue;
                }

                // 2. Extract document structure with Document Intelligence and apply routing rules.
                var analysis = await _documentAnalyzer.AnalyzeAsync(document, cancellationToken);

                // 3. Post an Adaptive Card to the Teams channel.
                await PostToTeamsAsync(analysis, fileName, cancellationToken);

                _logger.LogInformation(
                    "Posted RFP summary for customer '{Customer}' ({CapabilityCount} capabilities, {SmeCount} SMEs).",
                    analysis.Customer, analysis.RequiredCapabilities.Count, analysis.RecommendedSmes.Count);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to process RFP '{FileName}'.", fileName);
            }
        }
    }

    private async Task<byte[]> GetRfpDocumentAsync(
        string siteAddress,
        string fileIdentifier,
        CancellationToken cancellationToken)
    {
        // SharePoint Online connector: GetFileContentAsync -> byte[].
        // The connector's "dataset" (site address) parameter is declared x-ms-url-encoding: double,
        // so it must arrive double-encoded. The SDK applies one Uri.EscapeDataString internally, so
        // we pre-encode the site once here to end up double-encoded; the trigger's {Identifier} is
        // already single-encoded and is passed through as-is.
        var encodedSite = Uri.EscapeDataString(siteAddress);
        byte[] content = await _sharePoint.GetFileContentAsync(
            encodedSite,
            fileIdentifier,
            cancellationToken: cancellationToken);
        return SharePointFileContent.Decode(content);
    }

    private async Task PostToTeamsAsync(RfpAnalysis analysis, string fileName, CancellationToken cancellationToken)
    {
        var teamId = RequireEnv("TEAMS_TEAM_ID");
        var channelId = RequireEnv("TEAMS_CHANNEL_ID");
        var postAs = Environment.GetEnvironmentVariable("TEAMS_POST_AS") ?? "Flow bot";
        var postIn = Environment.GetEnvironmentVariable("TEAMS_POST_IN") ?? "Channel";

        var card = BuildAdaptiveCard(analysis, fileName);

        // Dynamic body shape for "Post card in a chat or channel":
        //   { "recipient": { "groupId": <teamId>, "channelId": <channelId> }, "messageBody": <adaptive card> }
        var request = new DynamicPostCardRequest
        {
            AdditionalProperties =
            {
                ["recipient"] = JsonSerializer.SerializeToElement(new { groupId = teamId, channelId = channelId }),
                ["messageBody"] = card,
            },
        };

        await _teams.PostCardToConversationAsync(postAs, postIn, request, cancellationToken);
    }

    private static JsonElement BuildAdaptiveCard(RfpAnalysis analysis, string fileName)
    {
        var capabilities = analysis.RequiredCapabilities.Count > 0
            ? string.Join("\n", analysis.RequiredCapabilities.Select(c => $"- {c}"))
            : "_None identified_";
        var smes = analysis.RecommendedSmes.Count > 0
            ? string.Join("\n", analysis.RecommendedSmes.Select(s => $"- {s}"))
            : "_None identified_";

        var card = new Dictionary<string, object?>
        {
            ["type"] = "AdaptiveCard",
            ["$schema"] = "http://adaptivecards.io/schemas/adaptive-card.json",
            ["version"] = "1.4",
            ["body"] = new object[]
            {
                new { type = "TextBlock", size = "Large", weight = "Bolder", text = "📄 New RFP received" },
                new
                {
                    type = "FactSet",
                    facts = new object[]
                    {
                        new { title = "Customer:", value = analysis.Customer },
                        new { title = "Source file:", value = fileName },
                    },
                },
                new { type = "TextBlock", weight = "Bolder", spacing = "Medium", text = "Required capabilities" },
                new { type = "TextBlock", wrap = true, text = capabilities },
                new { type = "TextBlock", weight = "Bolder", spacing = "Medium", text = "Recommended SMEs" },
                new { type = "TextBlock", wrap = true, text = smes },
            },
        };

        return JsonSerializer.SerializeToElement(card, JsonOptions);
    }

    private static string? GetProperty(Item item, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (item.AdditionalProperties.TryGetValue(key, out var element) &&
                element.ValueKind is not JsonValueKind.Null and not JsonValueKind.Undefined)
            {
                return element.ValueKind == JsonValueKind.String ? element.GetString() : element.ToString();
            }
        }

        return null;
    }

    private static string RequireEnv(string name)
    {
        var value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException($"Required app setting '{name}' is not configured.");
        }

        return value;
    }

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
}

/// <summary>Structured result extracted from an RFP document.</summary>
public class RfpAnalysis
{
    public string Customer { get; set; } = string.Empty;
    public List<string> RequiredCapabilities { get; set; } = new();
    public List<string> RecommendedSmes { get; set; } = new();
}
