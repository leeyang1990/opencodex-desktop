# App icon

`AppIcon-Source.png` is an original asset created for this macOS client. It is
not derived from the upstream OpenCodex logo or from a provider's brand mark.

The mark represents three provider routes converging into one local route. The
source must remain a 1024 × 1024 RGBA PNG with transparent rounded corners and
macOS-safe outer padding. The build and release scripts reject an opaque source
so packaged apps cannot regress to a full-bleed square icon.

The build script generates all required `.icns` sizes from this source.

Product screenshots used by the repository README live in `screenshots/`:

- `overview.png` — service and provider overview.
- `accounts.png` — account pool and rotation strategy.
- `models.png` — model catalog and visibility controls.
