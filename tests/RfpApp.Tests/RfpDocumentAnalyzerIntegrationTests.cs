// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using Azure.AI.ContentUnderstanding;
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
        string? endpoint = Environment.GetEnvironmentVariable("CONTENT_UNDERSTANDING_ENDPOINT");
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            Assert.Skip("Set CONTENT_UNDERSTANDING_ENDPOINT to run the live integration test.");
        }

        var client = new ContentUnderstandingClient(
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
        Assert.Equal(
            [
                "Azure AI",
                "Data Platform",
                "Identity & Security",
                "Integration & Automation",
                "Observability & Operations",
            ],
            result.RequiredCapabilities);
        Assert.Equal(
            [
                "AI Specialist",
                "Data Platform Engineer",
                "Security Architect",
                "Integration Architect",
                "Cloud Operations Specialist",
            ],
            result.RecommendedSmes);
    }
}
