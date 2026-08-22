# Local MCP connections

OpenLoop reads optional MCP server configuration from:

`~/Library/Application Support/OpenLoop/MCP/servers.json`

The exact application-support folder follows the app's existing data directory.
The file is local and is not uploaded by OpenLoop.

```json
{
  "servers": [
    {
      "id": "filesystem",
      "command": "npx",
      "arguments": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/Projects"],
      "environment": {},
      "workingDirectory": null,
      "protocolMode": "legacy",
      "enabled": true
    }
  ]
}
```

Use `legacy` for servers that negotiate a 2025 MCP version with
`initialize`. Use `modern` only for servers that implement the stateless
2026-07-28 request metadata protocol.

Discovered tools start at **Observe**. A write cannot run until the user grants
**Act**, and write or destructive tools still require confirmation for each
action. Server environment values are passed only to that child process and are
not copied into OpenLoop's action history.
