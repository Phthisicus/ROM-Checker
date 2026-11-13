# Security Policy

ROM Checker processes user-provided files and can modify a mounted library when an administrator explicitly starts organization or recovery actions. Treat it as a trusted administrative tool and run it only with the storage and network access it needs.

## Reporting a vulnerability

Please do not report exploitable vulnerabilities in a public issue. If GitHub's private vulnerability reporting or Security Advisories feature is available for this repository, use it. Otherwise, contact the repository maintainer privately through GitHub and request a secure reporting channel. Do not include ROM contents, credentials, API tokens, or unredacted user data in a report.

Include, when safe:

- The affected release, image tag or digest, and deployment mode.
- A concise description of impact and the affected component.
- Reproduction details using synthetic files and a disposable environment.
- Any relevant logs after removing passwords, tokens, private hostnames, and personal paths.

Do not test against installations or data that you do not own or have explicit permission to assess. Please allow the maintainer time to investigate before publishing technical details. No response-time or supported-version guarantee is currently defined.

## Deployment notes

- Configure a strong `ROMCHECKER_PASSWORD` and a separate random storage token; keep both server-side.
- Do not expose the internal storage service directly to the Internet or mount the Docker socket or host root.
- If deploying behind a proxy, trust only the exact proxy IP as seen by the application container.
- Protect the persistent application data and configuration, and back up application data, ROM storage, and the library.
- Online lookups may disclose hashes and metadata to their configured services. RomM publishing copies eligible files into the configured shared export library.

See the [security and privacy reference](docs/REFERENCE.md#security-and-privacy) and [reverse-proxy guide](docs/wiki/Reverse-Proxy-and-HTTPS.md) for implementation-specific setup details.
