# FaySHA

A native macOS file checksum app in a thin, rounded 520 × 72 floating bar. It stays above Finder and follows you across desktops. Drag the bar's background to reposition it.

## Run

Requires macOS 13 or later. Building requires Swift 6 or later from Xcode or its command line tools.

```sh
bash scripts/build-app.sh
open dist/FaySHA.app
```

You can move `dist/FaySHA.app` into Applications. The local build is ad-hoc signed; distributing it to other Macs requires Developer ID signing and notarization.

## Use

- Drop one or several files anywhere on the bar, or click **+** (⌘O).
- Select SHA-256, SHA-384, SHA-512, SHA-1, or MD5. The app remembers your selection and recalculates the current files when you change it.
- Click the copy icon or press ⌘C to copy the digest (selected text takes priority); a brief checkmark confirms the copy while keeping the checksum visible. Multiple files copy as `digest  filename`, one per line. Click **⌄** to view and select full results in a temporary popover. Result actions appear after calculation finishes.
- The bar previews the checksum inline. Large files are read in 1 MiB chunks on a background task, with a thin progress line along the bottom and a stop icon for cancellation in the same position as the copy control. The progress line hides when hashing finishes.
- Dropping new files cancels the previous calculation. Folders are rejected with an explanation.
- Closing the bar quits the app. You can also use ⌘Q.

SHA-1 and MD5 are supplied for compatibility with existing checksum lists. Prefer SHA-256 or stronger for security-sensitive use. A checksum alone does not prove who supplied a file. Hash files after any copying or downloading has completed.

## Development

```sh
swift build
swift test
```

`Sources/ChecksumCore` streams file contents through CryptoKit. `Sources/FaySHA` contains the AppKit window and drag-and-drop UI. No network access or third-party dependencies are needed.

## License

MIT — see [LICENSE](LICENSE).

## GitHub publication

GitHub Actions runs tests and packages a universal app for Apple silicon and Intel Macs.
Version tags create draft releases for review. `VERSION` sets the app version.

To build the release archive locally:

```sh
bash scripts/package-release.sh
```

The ZIP archive and its SHA-256 checksum appear in `dist/`.

## Signing configuration

The build script uses ad-hoc signing and contains no Apple team ID or Developer ID identity. Keep personal Apple signing settings in environment variables or an ignored `*.local.xcconfig` file. Certificates, private keys, provisioning profiles, local environment files, and build output are ignored. Use placeholders in any shared configuration examples.
