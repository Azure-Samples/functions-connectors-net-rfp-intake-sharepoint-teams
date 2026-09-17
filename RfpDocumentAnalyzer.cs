// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System.Text.RegularExpressions;
using Azure;
using Azure.AI.ContentUnderstanding;

namespace RfpApp;

public sealed class RfpDocumentAnalyzer
{
    private const string LayoutAnalyzerId = "prebuilt-layout";
    private readonly ContentUnderstandingClient _client;

    public RfpDocumentAnalyzer(ContentUnderstandingClient client)
    {
        _client = client;
    }

    public async Task<RfpAnalysis> AnalyzeAsync(byte[] document, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(document);

        Operation<AnalysisResult> operation = await _client.AnalyzeBinaryAsync(
            WaitUntil.Completed,
            LayoutAnalyzerId,
            BinaryData.FromBytes(document),
            cancellationToken: cancellationToken);

        string? markdown = operation.Value.Contents?.FirstOrDefault()?.Markdown;
        return RfpAnalysisParser.Parse(markdown);
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

        string[] lines = NormalizeContent(content)
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
                    string nextLine = lines[nextIndex];
                    if (IsFieldOrSectionBoundary(nextLine))
                    {
                        break;
                    }

                    value = CleanValue(nextLine);
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
            Match heading = MajorSectionRegex().Match(lines[index]);
            if (!heading.Success ||
                !heading.Groups["value"].Value.Contains(
                    "REQUIRED CAPABILITIES",
                    StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            sectionStart = index;
            _ = int.TryParse(heading.Groups["number"].Value, out sectionNumber);

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

    private static bool IsFieldOrSectionBoundary(string line)
    {
        return CustomerLineRegex().IsMatch(line) ||
            MajorSectionRegex().IsMatch(line) ||
            FieldLineRegex().IsMatch(line);
    }

    private static string CleanValue(string value)
    {
        return value
            .Trim()
            .Trim('#', '*', '_', '-', ':')
            .Trim();
    }

    private static string NormalizeContent(string content)
    {
        string normalized = HtmlTableRowRegex().Replace(
            content,
            static match =>
            {
                string label = CleanHtmlCell(match.Groups["label"].Value);
                string value = CleanHtmlCell(match.Groups["value"].Value);
                return $"{label} {value}";
            });

        return HtmlTableTagRegex().Replace(normalized, "\n");
    }

    private static string CleanHtmlCell(string value)
    {
        return System.Net.WebUtility.HtmlDecode(HtmlTagRegex().Replace(value, string.Empty)).Trim();
    }

    [GeneratedRegex(
        @"^\s*(?:#{1,6}\s*)?(?:customer|client|organization)\s*[:\-]\s*(?<value>.*?)\s*$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex CustomerLineRegex();

    [GeneratedRegex(
        @"^\s*(?:#{1,6}\s*)?[A-Za-z][A-Za-z0-9 &/()_-]*\s*:\s*.*$",
        RegexOptions.CultureInvariant)]
    private static partial Regex FieldLineRegex();

    [GeneratedRegex(
        @"^\s*(?:#{1,6}\s*)?(?<number>\d+)\.\s+(?<value>.+?)\s*$",
        RegexOptions.CultureInvariant)]
    private static partial Regex MajorSectionRegex();

    [GeneratedRegex(
        @"^\s*(?:#{1,6}\s*)?\d+\.\d+(?:\.\d+)?[.)]?\s+(?<value>[^:]+?)\s*:?\s*$",
        RegexOptions.CultureInvariant)]
    private static partial Regex CapabilityHeadingRegex();

    [GeneratedRegex(
        @"<tr\b[^>]*>\s*<t[dh]\b[^>]*>(?<label>.*?)</t[dh]>\s*<t[dh]\b[^>]*>(?<value>.*?)</t[dh]>\s*</tr>",
        RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.CultureInvariant)]
    private static partial Regex HtmlTableRowRegex();

    [GeneratedRegex(
        @"</?(?:table|thead|tbody|tfoot|tr|td|th)\b[^>]*>",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex HtmlTableTagRegex();

    [GeneratedRegex(
        @"<[^>]+>",
        RegexOptions.CultureInvariant)]
    private static partial Regex HtmlTagRegex();
}
