# Docs Assets

This directory holds the source screenshots used by the documentation website. They're real
captures from the iOS 17 Simulator running the `CandleKitDemo` app, taken to document the chart's
guides and drawing tools with real, on-device rendering rather than mockups.

The copies actually referenced by the built site live under
`website/static/img/screenshots/` — this directory is the source of truth those copies are made
from. If you retake a screenshot, replace the file here and re-copy it into
`website/static/img/screenshots/` with the same filename.

## Media (GIFs and larger screenshots)

`docs-assets/media/` holds Simulator recordings converted to GIF (`demo-tour`, `replay`, `comparison`, `session-shading`, `chart-options`) and 480px-wide screenshots of the newer features. Copies for the website live in `website/static/img/media/` (same filenames). GIFs were captured with Simulator's File → Record Screen and converted with `ffmpeg` (10 fps, 300–360px wide, 96-colour palette) to keep each under about 1.2 MB.
