# AtmanForge

Hey, I'm the creator of AtmanForge. With most text being LLM generated these days I wanted a personal line to start off the read me with. I created this project as I noticed I really only use a few image models when creating assets so I wanted a cheap, fast and convenient way to access the models. And it was a ton of fun to build! All code in Claude Code, Opus 4.5. Hope you find it useful!

**Open source AI image generation app for macOS.**

Generate stunning images with state-of-the-art AI models. Bring your own API keys — no subscription, no backend, complete privacy.

[![Website](https://img.shields.io/badge/Website-atmanforge.com-blue)](https://atmanforge.com)
![macOS](https://img.shields.io/badge/macOS-15.0+-blue?logo=apple)
![License](https://img.shields.io/badge/license-MIT-green)
![Swift](https://img.shields.io/badge/Swift-5-orange?logo=swift)

## Features

- **Multiple AI Models** — Gemini, GPT Image, Qwen, Z-Image, and FLUX.2. Switch between them instantly.
- **Custom Models** — The model list is plain JSON. Add models or tweak parameters yourself, no rebuild required.
- **Bring Your Own Keys** — Use your own API key, encrypted on-device and never sent anywhere but the provider.
- **Reference Images** — Guide AI generation with reference images. Sketch directly on them.
- **Background Removal** — One-click background removal powered by [bria/remove-background](https://replicate.com/bria/remove-background).
- **Project Organization** — Keep generations organized with full metadata and activity history.
- **Privacy First** — Everything runs locally. Your data never touches our servers.

## Requirements

- macOS 15.0 or later
- Xcode 16.0 or later (for building)
- A [Replicate](https://replicate.com) API key — currently the only supported provider for accessing AI models

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/Nixarn/atmanforge.git
cd atmanforge
```

### 2. Open in Xcode

```bash
open AtmanForge.xcodeproj
```

### 3. Build and run

Select your target device and press `⌘R` to build and run.

### 4. Add your API key

1. Open AtmanForge
2. Go to **Settings** (⌘,)
3. Enter your [Replicate API key](https://replicate.com/account/api-tokens)

## Supported Models

AtmanForge currently uses [Replicate](https://replicate.com) as its sole provider to access AI models. You'll need a Replicate API key to use the app.

| Model | Replicate model | Reference images | Notes |
|-------|-----------------|------------------|-------|
| Gemini 2.5 | `google/nano-banana` | up to 6 | |
| Gemini 3.0 Pro | `google/nano-banana-pro` | up to 14 | 1K / 2K / 4K output |
| Gemini 3.1 Flash | `google/nano-banana-2` | up to 14 | 1K / 2K / 4K output; widest aspect range (1:8 → 8:1) |
| GPT Image 1.5 | `openai/gpt-image-1.5` | up to 10 | Quality, background, input fidelity; batches server-side |
| GPT Image 2 | `openai/gpt-image-2` | up to 10 | Quality, background incl. transparent; batches server-side |
| Qwen Image | `qwen/qwen-image` | 1 | |
| Qwen Image 2512 | `qwen/qwen-image-2512` | 1 | |
| Z-Image Turbo | `prunaai/z-image-turbo` | 1 | |
| FLUX.2 Pro | `black-forest-labs/flux-2-pro` | 1 | Prompt strength control |
| FLUX.2 Max | `black-forest-labs/flux-2-max` | 1 | Prompt strength control |
| Remove Background | `bria/remove-background` | — | Background removal, not text-to-image |

Any model can be hidden from the picker under **Settings → Models**.

*More models and providers coming soon!*

## Custom Models

The model list ships as a JSON file (`AtmanForge/Resources/Models.json`) rather than being hardcoded, so you can add
models or change their parameters without touching Swift.

Open **Settings → Custom Models File → Edit File**. That copies the bundled list to:

```
~/Library/Containers/com.turbolynx.AtmanForge/Data/Library/Application Support/AtmanForge/Models.json
```

and opens it in your default editor. Hit **Reload** to pick up your changes. AtmanForge is sandboxed, so that file
lives inside the app's container rather than in your top-level Library — use **Reveal in Finder** to get there instead
of navigating by hand.

Your file is merged over the bundled one **by `id`**: an entry whose `id` matches a bundled model replaces it, and an
entry with a new `id` is appended. Bundled models you don't mention are left alone. If your file fails to parse or
validate, the app falls back to the bundled list and shows the error in Settings. **Revert to Bundled…** deletes your
copy.

### Model fields

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Unique. Also what a saved generation records, so avoid renaming ids you've already used. |
| `displayName` | string | Shown in the model picker |
| `kind` | `"generation"` or `"background-removal"` | Only one background-removal model is used |
| `replicateModelID` | string | e.g. `"owner/model-name"` |
| `aspectRatios` | array of strings | Must be non-empty. From `8:1` down to `1:8` |
| `resolutions` | array of strings | `"512"`, `"1K"`, `"2K"`, `"4K"`. Empty means the model has no resolution control |
| `maxImages` | integer ≥ 1 | Upper bound on the image-count stepper |
| `nativeBatchKey` | string or `null` | Input key for server-side batching. `null` means the app fires N separate predictions, spaced by the delay in Settings |
| `maxReferenceImages` | integer ≥ 0 | `0` disables reference images |
| `referenceKey` | `{ "name": …, "kind": "single" \| "array" }` | Which input key reference images go into |
| `staticInputs` | object | Literal values always sent with the request, e.g. `{ "output_format": "png" }` |
| `parameters` | array | User-facing controls, see below |
| `visibleByDefault` | bool | Omit (or `true`) to show the model in a fresh install's picker. `false` starts it hidden, still switchable under **Settings → Models** |

All fields except `nativeBatchKey`, `referenceKey`, and `visibleByDefault` must be present — arrays and objects may be empty, but not omitted.

Out of the box the picker shows Gemini 3.0 Pro, Gemini 3.1 Flash, and GPT Image 2; the rest ship hidden. Once you
change any toggle in **Settings → Models**, your choice sticks and these defaults no longer apply.

### Parameter controls

Each entry in `parameters` needs `key`, `label`, `control`, and `default`:

```json
{ "key": "quality", "label": "Quality", "control": "picker",
  "options": ["high", "medium", "low"], "default": "medium" }
```

- `picker` — requires non-empty `options`; `default` must be a string listed in `options`
- `slider` — requires `min` and `max` (with `min` < `max`), optional `step`; `default` must be a number in range
- `toggle` — `default` must be `true` or `false`

## Architecture

```
AtmanForge/
├── Models/           # Data models (Project, Canvas, GenerationJob, ModelRegistry)
├── ViewModels/       # App state and business logic
├── Views/            # SwiftUI views
│   ├── Canvas/       # Activity and library views
│   ├── Components/   # Reusable components
│   ├── Inspector/    # Side panel views
│   ├── Settings/     # Settings view
│   └── Sidebar/      # Generation sidebar
├── Resources/        # Models.json — the bundled model list
└── Services/         # API providers and managers
```

## Privacy

AtmanForge is designed with privacy in mind:

- **Local Storage** — All images and project data are stored locally on your Mac
- **Encrypted Keys** — Your API key is encrypted at rest and tied to your machine, never stored in plain text
- **No Telemetry** — We don't collect any usage data or analytics
- **Direct API Calls** — Requests go directly to AI providers, no middleman servers

### How your API key is stored

AtmanForge is sandboxed but signed ad-hoc, with no Apple Developer Team ID. Keychain access depends on a stable
signing identity, so the app stores its key itself instead: encrypted with AES-GCM and written inside its own sandbox
container.

```
~/Library/Containers/com.turbolynx.AtmanForge/Data/Library/Application Support/com.turbolynx.AtmanForge/replicate_api_key
```

The encryption key is derived from your Mac's hardware UUID, so the file is useless if copied to another machine, and
the sandbox container keeps other sandboxed apps out of it. This is not Keychain-grade protection, though: a
non-sandboxed process running under your user account can read the file and re-derive the key, since a hardware UUID
isn't a secret. That's the tradeoff for shipping without a signed developer build. If you'd rather not take it, revoke
the key at [replicate.com](https://replicate.com/account/api-tokens) when you're done.

## Contributing

Contributions are welcome! Feel free to:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Credits

Built with ♥ by [Turbo Lynx Oy](https://github.com/Nixarn)

---

**AtmanForge** — Create with AI, on your terms.
