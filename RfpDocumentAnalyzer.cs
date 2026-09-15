// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System.Text.RegularExpressions;
using Azure;
using Azure.AI.DocumentIntelligence;

namespace RfpApp;

public sealed class RfpDocumentAnalyzer
{
    private const string LayoutModelId = "prebuilt-layout";
    private readonly DocumentIntelligenceClient _client;

    public RfpDocumentAnalyzer(DocumentIntelligenceClient client)
    {
        _client = client;
    }

    public async Task<RfpAnalysis> AnalyzeAsync(byte[] document, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(document);

        Operation<AnalyzeResult> operation = await _client.AnalyzeDocumentAsync(
            WaitUntil.Completed,
            LayoutModelId,
            BinaryData.FromBytes(document),
            cancellationToken);

        return RfpAnalysisParser.Parse(operation.Value.Content);
    }
}

public static partial class RfpAnalysisParser
{
    private static readonly (string[] Keywords, string Sme)[] SmeRules =
    [
        (["artificial intelligence", "azure ai", "machine learning", "copilot", "semantic search"], "AI Specialist"),
        (["data", "analytics", "lakehouse", "business intelligence"], "Data Platform Engineer"),
        (["identity", "security", "compliance", "zero trust"], "Security Architect"),
        (["integration", "automation", "event-driven", "api"], "Integration Architect"),
        (["observability", "operations", "monitoring", "reliability"], "Cloud Operations Specialist"),
        (["application", "app modernization", "serverless"], "Application Architect"),
    ];

    public static RfpAnalysis Parse(string? content)
    {
        if (string.IsNullOrWhiteSpace(content))
        {
            return new RfpAnalysis { Customer = "Unknown customer" };
        }

        string[] lines = content
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Split('\n', StringSplitOptions.TrimEntries);

        string customer = ExtractCustomer(lines);
        List<string> capabilities = ExtractCapabilities(lines);
        List<string> smes = RecommendSmes(capabilities);

        return new RfpAnalysis
        {
            Customer = customer,
            RequiredCapabilities = capabilities,
            RecommendedSmes = smes,
        };
    }

    private static string ExtractCustomer(IReadOnlyList<string> lines)
    {
        for (int index = 0; index < lines.Count; index++)
        {
            Match match = CustomerLineRegex().Match(lines[index]);
            if (match.Success)
            {
                string value = CleanValue(match.Groups["value"].Value);
                if (!string.IsNullOrWhiteSpace(value))
                {
                    return value;
                }

                for (int nextIndex = index + 1; nextIndex < lines.Count; nextIndex++)
                {
                    value = CleanValue(lines[nextIndex]);
                    if (!string.IsNullOrWhiteSpace(value))
                    {
                        return value;
                    }
                }
            }
        }

        return "Unknown customer";
    }

    private static List<string> ExtractCapabilities(IReadOnlyList<string> lines)
    {
        int sectionStart = -1;
        int sectionNumber = -1;

        for (int index = 0; index < lines.Count; index++)
        {
            if (!lines[index].Contains("REQUIRED CAPABILITIES", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            sectionStart = index;
            Match heading = MajorSectionRegex().Match(lines[index]);
            if (heading.Success)
            {
                _ = int.TryParse(heading.Groups["number"].Value, out sectionNumber);
            }

            break;
        }

        if (sectionStart < 0)
        {
            return [];
        }

        var capabilities = new List<string>();
        for (int index = sectionStart + 1; index < lines.Count; index++)
        {
            string line = lines[index];
            Match majorSection = MajorSectionRegex().Match(line);
            if (majorSection.Success &&
                int.TryParse(majorSection.Groups["number"].Value, out int currentSection) &&
                (sectionNumber < 0 || currentSection > sectionNumber))
            {
                break;
            }

            Match capability = CapabilityHeadingRegex().Match(line);
            if (capability.Success)
            {
                string name = CleanValue(capability.Groups["value"].Value);
                if (!string.IsNullOrWhiteSpace(name))
                {
                    capabilities.Add(name);
                }
            }
        }

        return capabilities.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    private static List<string> RecommendSmes(IEnumerable<string> capabilities)
    {
        string searchable = string.Join(' ', capabilities);
        var smes = new List<string>();

        foreach ((string[] keywords, string sme) in SmeRules)
        {
            if (keywords.Any(keyword => searchable.Contains(keyword, StringComparison.OrdinalIgnoreCase)))
            {
                smes.Add(sme);
            }
        }

        return smes;
    }

    private static string CleanValue(string value)
    {
        return value
            .Trim()
            .Trim('#', '*', '_', '-', ':')
            .Trim();
    }

    [GeneratedRegex(
        @"^\s*(?:#{1,6}\s*)?(?:customer|client|organization)\s*[:\-]\s*(?<value>.*?)\s*$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex CustomerLineRegex();

    [GeneratedRegex(
        @"^\s*(?:#{1,6}\s*)?(?<number>\d+)\.\s+(?<value>.+?)\s*$",
        RegexOptions.CultureInvariant)]
    private static partial Regex MajorSectionRegex();

    [GeneratedRegex(
        @"^\s*(?:#{1,6}\s*)?\d+\.\d+(?:\.\d+)?[.)]?\s+(?<value>[^:]+?)\s*:?\s*$",
        RegexOptions.CultureInvariant)]
    private static partial Regex CapabilityHeadingRegex();
}
