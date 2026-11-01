# Local media helpers

The application is native Swift/SwiftUI. Installed FFmpeg/FFprobe, yt-dlp and rclone are local executables, not services. The bundled ASR adapter is reused from Frank's existing DUB skill package (`runtime/x/scripts/transcribe_source.py`, version 1.3.5); original SHA-256: f41ff480247f1be47366b4a883964eb2f3e17ed085aa4b866cd6f13dc1d0722b. It invokes the existing local MLX Whisper/faster-whisper model with Hugging Face offline mode. No model, credentials or production media are included in Git.

The approved DUB artwork is resolved from its exact Drive ID or a hash-verified existing asset, then copied into application-owned storage. The app does not need the Codex process, ChatGPT, GitHub or Xcode Cloud to run. Existing local Python/model paths are operational dependencies configurable in settings.

The development target runs outside App Sandbox because its authorized workflow invokes existing user-installed tools and accesses existing archive/media paths and the existing rclone configuration. It retains macOS permissions and user authorization checks; it does not grant new cloud access. This local build is not a public distribution/notarization claim.
