// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using RfpApp;
using Xunit;

namespace RfpApp.Tests;

public class RfpAnalysisParserTests
{
    [Fact]
    public void Parse_ExtractsCustomerCapabilitiesAndSmes()
    {
        const string content = """
            REQUEST FOR PROPOSAL
            Customer: Contoso Ltd.

            3. SCOPE & REQUIRED CAPABILITIES
            3.1 Azure AI
            - Natural-language support assistant.
            3.2 Data Platform
            - Scalable lakehouse and analytics.
            3.3 Identity & Security
            - Single sign-on and conditional access.

            4. NON-FUNCTIONAL REQUIREMENTS
            4.1 Availability
            """;

        RfpAnalysis result = RfpAnalysisParser.Parse(content);

        Assert.Equal("Contoso Ltd.", result.Customer);
        Assert.Equal(["Azure AI", "Data Platform", "Identity & Security"], result.RequiredCapabilities);
        Assert.Equal(
            ["AI Specialist", "Data Platform Engineer", "Security Architect"],
            result.RecommendedSmes);
    }

    [Fact]
    public void Parse_HandlesMarkdownLayoutOutput()
    {
        const string content = """
            # Request for proposal
            Organization - Fabrikam, Inc.

            ## 2. Required Capabilities
            ### 2.1 Integration & Automation
            Event-driven integration is required.
            ### 2.2 Observability & Operations
            Monitoring and runbooks are required.

            ## 3. Deliverables
            """;

        RfpAnalysis result = RfpAnalysisParser.Parse(content);

        Assert.Equal("Fabrikam, Inc.", result.Customer);
        Assert.Equal(
            ["Integration & Automation", "Observability & Operations"],
            result.RequiredCapabilities);
        Assert.Equal(
            ["Integration Architect", "Cloud Operations Specialist"],
            result.RecommendedSmes);
    }

    [Fact]
    public void Parse_HandlesContentUnderstandingHtmlTables()
    {
        const string content = """
            # Request for proposal

            <table>
            <tr>
            <td>Customer:</td>
            <td>Contoso Ltd.</td>
            </tr>
            </table>

            ## 3. Scope & Required Capabilities
            ### 3.1 Azure AI
            ### 3.2 Data Platform
            ## 4. Deliverables
            """;

        RfpAnalysis result = RfpAnalysisParser.Parse(content);

        Assert.Equal("Contoso Ltd.", result.Customer);
        Assert.Equal(["Azure AI", "Data Platform"], result.RequiredCapabilities);
        Assert.Equal(["AI Specialist", "Data Platform Engineer"], result.RecommendedSmes);
    }

    [Fact]
    public void Parse_HandlesLabelAndValueOnSeparateOcrLines()
    {
        const string content = """
            Customer :
            Contoso Ltd.
            3. REQUIRED CAPABILITIES
            3.1 Azure AI
            4. DELIVERABLES
            """;

        RfpAnalysis result = RfpAnalysisParser.Parse(content);

        Assert.Equal("Contoso Ltd.", result.Customer);
        Assert.Equal(["Azure AI"], result.RequiredCapabilities);
    }

    [Fact]
    public void Parse_DoesNotUseSectionHeadingForBlankCustomer()
    {
        const string content = """
            Customer:

            3. REQUIRED CAPABILITIES
            3.1 Azure AI
            """;

        RfpAnalysis result = RfpAnalysisParser.Parse(content);

        Assert.Equal("Unknown customer", result.Customer);
        Assert.Equal(["Azure AI"], result.RequiredCapabilities);
    }

    [Fact]
    public void Parse_StopsBlankCustomerAtNextField()
    {
        const string content = """
            Customer:
            Date: September 16, 2026
            Organization: Fabrikam, Inc.

            3. REQUIRED CAPABILITIES
            3.1 Data Platform
            """;

        RfpAnalysis result = RfpAnalysisParser.Parse(content);

        Assert.Equal("Fabrikam, Inc.", result.Customer);
    }

    [Fact]
    public void Parse_IgnoresRequiredCapabilitiesInProse()
    {
        const string content = """
            Customer: Contoso Ltd.
            The following are required capabilities for this engagement.

            3. REQUIRED CAPABILITIES
            3.1 Integration & Automation
            4. DELIVERABLES
            """;

        RfpAnalysis result = RfpAnalysisParser.Parse(content);

        Assert.Equal(["Integration & Automation"], result.RequiredCapabilities);
    }

    [Fact]
    public void Parse_ReturnsSafeDefaultsForEmptyContent()
    {
        RfpAnalysis result = RfpAnalysisParser.Parse(null);

        Assert.Equal("Unknown customer", result.Customer);
        Assert.Empty(result.RequiredCapabilities);
        Assert.Empty(result.RecommendedSmes);
    }
}
