// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System.Text.Json;

namespace RfpApp;

public static class SharePointFileContent
{
    public static byte[] Decode(byte[] content)
    {
        ArgumentNullException.ThrowIfNull(content);

        if (content.Length >= 2 && content[0] == (byte)'"' && content[^1] == (byte)'"')
        {
            return JsonSerializer.Deserialize<byte[]>(content)
                ?? throw new JsonException("The SharePoint file content response was empty.");
        }

        return content;
    }
}
