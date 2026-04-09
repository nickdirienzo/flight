# Remote Session Authentication

## Remote Control requires full-scope OAuth tokens

`claude --remote-control` needs the `user:sessions:claude_code` scope to register
sessions with the Anthropic backend (visible in Claude mobile/web app).

Tokens from `claude setup-token` and `CLAUDE_CODE_OAUTH_TOKEN` are **inference-only**
(`user:inference` scope). They work for `claude -p` but NOT for Remote Control.

To get a full-scope token:

```bash
claude auth login
```

This opens a browser OAuth flow granting all scopes:
`org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload`

### Provisioning remote workspaces

1. Run `claude auth login` locally (or on any machine with a browser)
2. Store the resulting token in SSM / secrets manager
3. Have the coder provisioner pull it into `CLAUDE_CODE_OAUTH_TOKEN`
4. Also ensure `~/.claude.json` has `"hasCompletedOnboarding": true` to skip
   the interactive setup wizard (see anthropics/claude-code#4714)

### Potential hook for token sync

Users could provide a hook script that refreshes the token and syncs to a vault before starting a remote session. TBD.

## References

- anthropics/claude-code#4714 — onboarding ignores env tokens
- Claude Code docs: https://code.claude.com/docs/en/remote-control
