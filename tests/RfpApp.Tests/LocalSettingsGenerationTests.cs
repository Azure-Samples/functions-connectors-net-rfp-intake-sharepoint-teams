// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System.Diagnostics;
using System.Text.Json;
using Xunit;

namespace RfpApp.Tests;

public class LocalSettingsGenerationTests
{
    [Fact]
    public async Task Generate_WritesPollSettingsWithoutAzureIdentitySelectors()
    {
        using var fixture = new SettingsFixture();

        var result = await fixture.RunAsync();

        Assert.Equal(0, result.ExitCode);
        using var settings = JsonDocument.Parse(File.ReadAllText(fixture.SettingsPath));
        var values = settings.RootElement.GetProperty("Values");
        Assert.Equal(fixture.Outputs["connectorNamespacePollingEndpoint"],
            values.GetProperty("ConnectorNamespace__pollingEndpoint").GetString());
        Assert.Equal(fixture.Outputs["sharepointPollTriggerConfigName"],
            values.GetProperty("OnNewFilePollTriggerConfigName").GetString());
        Assert.Equal("", values.GetProperty("AZURE_CLIENT_ID").GetString());
        Assert.False(values.TryGetProperty("ConnectorNamespace__credential", out _));
        Assert.False(values.TryGetProperty("ConnectorNamespace__clientId", out _));
    }

    [Theory]
    [InlineData("connectorNamespacePollingEndpoint")]
    [InlineData("sharepointPollTriggerConfigName")]
    public async Task Generate_RejectsMissingPollOutput(string missingOutput)
    {
        using var fixture = new SettingsFixture();
        fixture.Outputs.Remove(missingOutput);

        var result = await fixture.RunAsync();

        Assert.NotEqual(0, result.ExitCode);
        Assert.Contains("Required azd outputs are missing", result.Output);
        Assert.False(File.Exists(fixture.SettingsPath));
    }

    [Fact]
    public async Task Generate_PreservesExistingSettingsUnlessForced()
    {
        using var fixture = new SettingsFixture();
        const string existing = """{"IsEncrypted":false,"Values":{"CUSTOM":"keep"}}""";
        File.WriteAllText(fixture.SettingsPath, existing);

        var preserved = await fixture.RunAsync();

        Assert.Equal(0, preserved.ExitCode);
        Assert.Equal(existing, File.ReadAllText(fixture.SettingsPath));

        var replaced = await fixture.RunAsync(force: true);

        Assert.Equal(0, replaced.ExitCode);
        using var settings = JsonDocument.Parse(File.ReadAllText(fixture.SettingsPath));
        Assert.Equal(fixture.Outputs["sharepointPollTriggerConfigName"],
            settings.RootElement.GetProperty("Values").GetProperty("OnNewFilePollTriggerConfigName").GetString());
    }

    private sealed class SettingsFixture : IDisposable
    {
        private readonly string _directory = Path.Combine(Path.GetTempPath(), $"rfp-settings-{Guid.NewGuid():N}");
        private readonly string _scriptPath;
        private readonly string _binPath;

        public Dictionary<string, string> Outputs { get; } = new()
        {
            ["sharepointConnectionRuntimeUrl"] = "https://example.test/sharepoint",
            ["sharepointSiteUrl"] = "https://example.test/sites/rfp",
            ["teamsConnectionRuntimeUrl"] = "https://example.test/teams",
            ["TEAMS_TEAM_ID"] = "test-team",
            ["TEAMS_CHANNEL_ID"] = "test-channel",
            ["contentUnderstandingEndpoint"] = "https://example.test/content",
            ["connectorNamespacePollingEndpoint"] = "https://example.test",
            ["sharepointPollTriggerConfigName"] = "sharepoint-onnewfilepoll"
        };

        public string SettingsPath => Path.Combine(_directory, "local.settings.json");

        public SettingsFixture()
        {
            var root = new DirectoryInfo(AppContext.BaseDirectory);
            while (root is not null && !File.Exists(Path.Combine(root.FullName, "rfpApp.csproj")))
            {
                root = root.Parent;
            }

            if (root is null)
            {
                throw new DirectoryNotFoundException("Could not locate the sample project.");
            }

            var scriptDirectory = Directory.CreateDirectory(Path.Combine(_directory, "infra", "scripts"));
            string scriptName = OperatingSystem.IsWindows() ? "createlocalsettings.ps1" : "createlocalsettings.sh";
            _scriptPath = Path.Combine(scriptDirectory.FullName, scriptName);
            File.Copy(Path.Combine(root.FullName, "infra", "scripts", scriptName), _scriptPath);
            _binPath = Directory.CreateDirectory(Path.Combine(_directory, "bin")).FullName;
        }

        public async Task<(int ExitCode, string Output)> RunAsync(bool force = false)
        {
            string json = JsonSerializer.Serialize(Outputs);
            string stubPath = Path.Combine(_binPath, OperatingSystem.IsWindows() ? "azd.cmd" : "azd");
            File.WriteAllText(stubPath, OperatingSystem.IsWindows()
                ? $"@echo off\r\necho {json}\r\n"
                : $"#!/bin/sh\nprintf '%s\\n' '{json}'\n");
            if (!OperatingSystem.IsWindows())
            {
                File.SetUnixFileMode(stubPath, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            }

            var startInfo = new ProcessStartInfo(OperatingSystem.IsWindows() ? "powershell.exe" : "/bin/sh")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };
            if (OperatingSystem.IsWindows())
            {
                foreach (string argument in new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File" })
                {
                    startInfo.ArgumentList.Add(argument);
                }
            }

            startInfo.ArgumentList.Add(_scriptPath);
            if (force)
            {
                startInfo.ArgumentList.Add(OperatingSystem.IsWindows() ? "-Force" : "--force");
            }

            startInfo.Environment["PATH"] = $"{_binPath}{Path.PathSeparator}{Environment.GetEnvironmentVariable("PATH")}";
            using var process = Process.Start(startInfo)
                ?? throw new InvalidOperationException("Could not start the local settings generator.");
            Task<string> stdout = process.StandardOutput.ReadToEndAsync();
            Task<string> stderr = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();
            return (process.ExitCode, await stdout + await stderr);
        }

        public void Dispose() => Directory.Delete(_directory, recursive: true);
    }
}
