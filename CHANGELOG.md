# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.1.0

### Added

- Initial release: render repository activity as a weather report SVG.
- Five visual styles: `card`, `forecast`, `banner`, `terminal`, `minimal`.
- Ten weather conditions: sunny, partly_cloudy, cloudy, rainy, stormy, foggy,
  snowy, windy, plus `rainbow` (fresh release) and `aurora` (star surge).
- CSS-animated scenes (sun rays, drifting clouds, rain, snow, lightning),
  with `animated: false` for static output and a `prefers-reduced-motion` guard.
- Light/dark/auto theme modes with `github`, `midnight`, `paper`, `mono` presets.
- Zero-config operation on GitHub Actions; optional `.github/activity-weather.yml`.
