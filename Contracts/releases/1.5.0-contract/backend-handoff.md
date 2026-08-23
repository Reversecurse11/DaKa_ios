# BNBU Sports Contract 1.5.0 Candidate Handoff

| Item | Value |
| --- | --- |
| Canonical OpenAPI | `docs/backend-contracts/openapi.yaml` |
| Candidate version | `1.5.0-contract` |
| OpenAPI version | `3.1.0` |
| SHA-256 | `f0b4916cb0abd1ec4057f690763de8d7e6f79ca2b7e666a8cd6f3d8c37c69bed` |
| Source baseline commit | `b014fb01051acc99dd7f15a971efed0c46642e8e` |
| Operations | 123 |
| Schemas | 279 |
| Compatibility vs 1.4 | PASS; 0 unapproved blockers |
| Enabled operations | 106 |
| Intentionally disabled | 17 |
| Not implemented | 0 |

The 17 disabled operations remain real authenticated routes that fail closed. This handoff authorizes neither location collection nor GPS permission requests. It adds original-byte WebM verification, not transcoding. Clients must retain photo evidence as a supported path and surface stable media validation errors.
