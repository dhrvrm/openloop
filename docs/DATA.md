# Local Storage, Compression, and Encryption

All user information stays on the Mac. There is no server copy, cloud index,
account database, or telemetry stream.

## What is stored

The local vault contains five information resolutions:

### Raw capture

The exact text or audio originally supplied by the user. It is immutable during
its retention period so later processing remains auditable.

### Clarified intent

A proposed classification, desired outcome, and smallest next action. The raw
capture remains available, and user corrections become new revisions.

### Clarification correction

An append-only local review event containing the capture identity, review time,
previous proposal when present, and corrected proposal. The current proposal is
updated for fast display, while correction history preserves how the meaning
changed. Corrections are encrypted with the rest of the vault and never alter
the immutable raw capture.

### Focus state

The active intention, start time, elapsed-time state, relevant local references,
and current status.

### Return packet

A compact interruption snapshot containing the exact next action, recently
completed work, blocker, references, and capture time.

### Durable memory

An atomic fact, decision, commitment, preference, question, correction, or
learned personal pattern with evidence, time, confidence, and supersession.

## Storage capacity

At 16 kHz mono 16-bit PCM, audio consumes about 115 MB per hour. Opus at 24–32
kbit/s consumes approximately 10.8–14.4 MB per hour.

For eight hours a day across 22 workdays:

| Representation | Approximate monthly size |
| --- | ---: |
| Raw PCM | 20.3 GB |
| Opus at 24 kbit/s | 1.9 GB |
| Opus at 32 kbit/s | 2.5 GB |

Voice activity detection reduces retained audio further. Typed captures,
transcripts, structured state, embeddings, and local indexes are normally much
smaller than continuous audio. Local model files may occupy several gigabytes.

There is no artificial product quota. A configurable storage governor protects
free disk space and reports exactly what each category consumes.

Recommended defaults:

- typed captures, return packets, and durable memories: keep until deleted;
- compressed audio: seven-day rolling retention;
- complete transcripts: 30-day retention;
- evidence excerpts referenced by durable memory: keep with that memory;
- model caches and search indexes: disposable and rebuildable;
- stop capture visibly before the disk becomes critically low.

## Semantic compression

Compression must reduce retrieval effort without erasing why something is known.
Use semantic delta compression:

1. preserve new evidence;
2. extract candidate atomic claims;
3. compare them with active memories;
4. attach corroborating evidence to equivalent memories;
5. create a revision when information changes;
6. preserve contradictions when no resolution is supported;
7. mark a memory superseded only with replacement evidence;
8. generate readable summaries from atomic memory on demand.

Never summarize summaries repeatedly. Raw evidence may expire according to the
user's retention setting, but the application must expose when a memory no longer
has retained primary evidence.

Compression quality is measured through:

- evidence coverage;
- contradiction preservation;
- current-state accuracy;
- retrieval success;
- reconstruction fidelity;
- useful memories per stored megabyte.

## Local encryption

1. Generate a random vault root key on the Mac.
2. Store the root key in macOS Keychain for provisioned builds. Rapidly changing
   local ad-hoc builds migrate the same key once to an owner-only, file-protected
   Application Support file so unstable code-hash ACLs do not block launch.
3. Derive separate database, audio, export, and diagnostic keys using HKDF.
4. Encrypt bulk objects using authenticated encryption such as AES-GCM or
   ChaCha20-Poly1305.
5. Use a unique nonce for each encrypted object.
6. Authenticate object identifier, schema version, and content type as associated
   data.
7. Rotate wrapped data keys without rewriting every object immediately.

Keychain stores small secrets, not the complete database. Search indexes remain
inside the encrypted local vault. Exports are encrypted unless the user
explicitly selects plaintext.

References:

- https://developer.apple.com/documentation/security/keychain-services
- https://developer.apple.com/documentation/cryptokit

## Deletion and recovery

- Deleting evidence removes selected raw capture and transcript revisions.
- Deleting a memory removes its claim, return references, and search entries.
- Resetting the vault destroys the root key and removes encrypted files.
- The user may create an encrypted local backup file.
- No remote recovery exists; losing both the vault key and backup intentionally
  makes the data unrecoverable.
