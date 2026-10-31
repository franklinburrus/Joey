# Joey

Joey is a native macOS Swift/SwiftUI application for authorized DUB and Taxstone media. It plans full-show coverage or explicit highlights, produces one shared portrait MP4 per clip, performs automatic media checks, and files verified outputs to the existing Joey Drive destinations. It never publishes social posts or sends email.

The current requirements are in [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md). Read [docs/STATUS.md](docs/STATUS.md) for verified progress and remaining operational dependencies, and [docs/OPERATING_GUIDE.md](docs/OPERATING_GUIDE.md) for use.

## Development

Use the existing `Joey.xcodeproj` and its `Joey` scheme. The repository uses Xcode 27.2's `project.xcproj` format. The native UI and Swift package tests compile the same core files in `Joey/Core`. No third-party Swift packages, cloud services or new CI systems were added.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The opt-in real-media test requires `JOEY_REAL_MEDIA_INPUTS` pointing to a local JSON list of authorized source paths, hashes, intervals and matching artwork. Without it, that one test is explicitly skipped. Cloud CI should run generated tests only and never receive production media/models/credentials.

## Runtime

Open the built native app directly. Xcode, Codex, ChatGPT, GitHub and Xcode Cloud are not production operators. FFmpeg, FFprobe, rclone, yt-dlp and an existing local Whisper environment/model are local operational dependencies. Acquisition and Drive filing require connectivity; accepted local files and job history remain accessible offline.

Data lives in `~/Library/Application Support/Joey Native`, outside Drive. Historical Python Joey data and its installed application remain separate and unchanged. Local ad-hoc signing is not notarization or public distribution.
