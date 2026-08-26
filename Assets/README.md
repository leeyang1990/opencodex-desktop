# App icon

`AppIcon-Source.png` is an original asset created for this macOS client. It is
not derived from the upstream OpenCodex logo or from a provider's brand mark.

The mark represents three provider routes converging into one local route. The
source must remain a fully opaque 1024 × 1024 square PNG whose background fills
every edge. macOS applies the platform's continuous rounded-corner mask when it
displays the icon. The build and release scripts reject transparent sources so
packaged apps cannot regress to a double-masked icon with a visible white halo.

The build script generates all required `.icns` sizes from this source.

Product screenshots used by the repository README live in `screenshots/`:

- `overview.png` — service and provider overview.
- `accounts.png` — account pool and rotation strategy.
- `models.png` — model catalog and visibility controls.
