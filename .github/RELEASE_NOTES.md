Native macOS file checksums in a floating bar.

- Supports SHA-256, SHA-384, SHA-512, SHA-1, and MD5.
- Accepts multiple files, with progress and cancellation.
- Requires macOS 13 or later. The universal app supports Apple silicon and Intel.

Download the ZIP archive, extract it, and move FaySHA.app into Applications.
Use the attached `.sha256` file to check the archive with `shasum -a 256 -c`.

This build uses ad-hoc signing. It has no Developer ID signature or Apple notarization.
macOS Gatekeeper can block the downloaded app. Build from source if your system blocks it.
