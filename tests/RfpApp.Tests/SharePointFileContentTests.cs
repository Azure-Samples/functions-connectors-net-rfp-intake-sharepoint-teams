// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System.Text.Json;
using RfpApp;
using Xunit;

namespace RfpApp.Tests;

public class SharePointFileContentTests
{
    [Fact]
    public void Decode_DecodesJsonBase64Response()
    {
        byte[] expected = "%PDF-1.7"u8.ToArray();
        byte[] response = JsonSerializer.SerializeToUtf8Bytes(expected);

        byte[] result = SharePointFileContent.Decode(response);

        Assert.Equal(expected, result);
    }

    [Fact]
    public void Decode_PreservesRawBinaryResponse()
    {
        byte[] response = "%PDF-1.7"u8.ToArray();

        byte[] result = SharePointFileContent.Decode(response);

        Assert.Same(response, result);
    }
}
