# BNBU Sports Contract 2.0.2 Release Handoff

| Item | Value |
| --- | --- |
| Canonical OpenAPI | `docs/backend-contracts/openapi.yaml` |
| Contract version | `2.0.2-contract` |
| Release state | `published` |
| OpenAPI version | `3.1.0` |
| SHA-256 | `853e7f5efadb10dcbbe0f446c4c60962ce2fd864360a156343b5740d0c1761a4` |
| Source baseline commit | `bec7aac06f53e71cef5e969359a032a8f054be79` |
| Operations | 126 |
| Schemas | 288 |
| Compatibility vs 2.0.1-contract | PASS; 0 unapproved blockers |
| Enabled operations | 109 |
| Intentionally disabled | 17 |
| Not implemented | 0 |

The 17 disabled operations remain real authenticated routes that fail closed. This handoff authorizes neither location collection nor GPS permission requests. It adds original-byte WebM verification, not transcoding. Clients must retain photo evidence as a supported path and surface stable media validation errors. Updated clients use `GET /api/v1/exemption-application-details` for lossless exemption subtype and organization fields; QR join still completes email verification before the restricted session becomes active.
