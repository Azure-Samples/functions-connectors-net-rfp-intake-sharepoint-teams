// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using Azure.AI.DocumentIntelligence;
using Azure.Identity;
using RfpApp;
using Xunit;

namespace RfpApp.Tests;

public class RfpDocumentAnalyzerIntegrationTests
{
    [Fact]
    [Trait("Category", "Integration")]
    public async Task AnalyzeAsync_ExtractsTheSamplePdf()
    {
        string? endpoint = Environment.GetEnvironmentVariable("DOCUMENT_INTELLIGENCE_ENDPOINT");
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            Assert.Skip("Set DOCUMENT_INTELLIGENCE_ENDPOINT to run the live integration test.");
        }

        var client = new DocumentIntelligenceClient(
            new Uri(endpoint),
            new DefaultAzureCredential());
        var analyzer = new RfpDocumentAnalyzer(client);
        byte[] document = await File.ReadAllBytesAsync(
            Path.Combine(AppContext.BaseDirectory, "sample-data", "contoso-rfp.pdf"),
            TestContext.Current.CancellationToken);

        RfpAnalysis result = await analyzer.AnalyzeAsync(
            document,
            TestContext.Current.CancellationToken);

        Assert.Equal("Contoso Ltd.", result.Customer);
        Assert.Contains("Azure AI", result.RequiredCapabilities);
        Assert.Contains("Data Platform", result.RequiredCapabilities);
        Assert.Contains("Identity & Security", result.RequiredCapabilities);
        Assert.Contains("AI Specialist", result.RecommendedSmes);
        Assert.Contains("Security Architect", result.RecommendedSmes);
    }
}
