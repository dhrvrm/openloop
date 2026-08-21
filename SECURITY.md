# Security

Please do not report vulnerabilities through public issues.

Email **security@dhruvverma.dev** with:

- the affected version and macOS release;
- reproduction steps and expected impact;
- whether local audio, transcripts, credentials, permissions, or output injection are involved;
- any proof of concept that can be shared safely.

You should receive an acknowledgement within seven days. Do not include real meeting recordings, API keys, Keychain exports, or private workspace data.

## Supported versions

Security fixes target the latest published release. Older development builds may be asked to update before further investigation.

## Security model

OpenLoop is local-first, but local software is not automatically safe. The project treats permission timing, encrypted persistence, explicit network mode, credential storage, evidence provenance, and confirmation before external mutation as security boundaries.
