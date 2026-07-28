# Activity Weather

Render your repository's recent activity as a **weather report SVG** — sunny when commits pour in, stormy when issues flood, foggy when things go quiet, a rainbow right after a release. Drop it in your README and let the sky tell the story.

<p align="center">
  <img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/showcase-banner.svg" alt="banner style" width="840">
</p>

- **Five styles** — `card`, `forecast`, `banner`, `terminal`, `minimal`
- **Ten conditions** — sunny, partly cloudy, cloudy, rainy, stormy, foggy, snowy, windy, plus **rainbow** (fresh release) and **aurora** (star surge)
- **Animated** — sun rays turn, rain falls, lightning flashes; CSS animations that work inside a README `<img>`, honor `prefers-reduced-motion`, and switch off with `animated: false`
- **Theme-aware** — `auto` mode follows the viewer's light/dark scheme; every repo gets its own seeded scenery
- **Zero config** — works out of the box on the repository running the workflow
- **Self-contained** — a static Crystal binary in a prebuilt image; no runtime dependencies, no external requests from the SVG

## Quick start

```yaml
# .github/workflows/activity-weather.yml
name: Activity Weather

on:
  schedule:
    - cron: "17 0 * * *"
  workflow_dispatch:

# contents to push the SVG; issues + pull-requests because the activity
# fetch reads the issues listing (a `permissions:` block drops everything
# it does not name).
permissions:
  contents: write
  issues: read
  pull-requests: read

concurrency:
  group: activity-weather

jobs:
  weather:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: crystal-actions/activity-weather@v0
```

That's it — the action fetches the last 7 days of activity, reads the weather, writes `ACTIVITY_WEATHER.svg`, and commits it. Then embed it:

```markdown
![Activity Weather](ACTIVITY_WEATHER.svg)
```

> GitHub's image proxy caches aggressively. If the image looks stale after a run, append a cache-busting query to the URL (e.g. `ACTIVITY_WEATHER.svg?v=2`) or link the raw URL.

## Styles

Every image below is generated from a committed config in [`examples/`](examples/) — the YAML shown is the config that produced it.

### `card` *(default)*

The weather-app look: big animated icon, temperature, condition, and a metrics row.

```yaml
# .github/activity-weather.yml
style: card
output: ACTIVITY_WEATHER.svg
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/showcase-card.svg" alt="card style" width="480">

### `forecast`

A condensed "today" panel plus one column per trailing day — mini icon, temperature, and an activity bar in that day's color.

```yaml
style: forecast
forecast:
  days: 7
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/showcase-forecast.svg" alt="forecast style" width="760">

### `banner`

A README hero: layered sky, drifting clouds, condition precipitation, and hill silhouettes seeded from your repository name — every repo gets its own horizon.

```yaml
style: banner
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/showcase-banner.svg" alt="banner style" width="840">

### `terminal`

The `wttr.in` spirit: ASCII art per condition, phosphor-toned monospace readout, blinking prompt. Always dark, like a real terminal.

```yaml
style: terminal
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/showcase-terminal.svg" alt="terminal style" width="464">

### `minimal`

A 28px pill for inline use — next to a title, in a badge row.

```yaml
style: minimal
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/showcase-badge.svg" alt="minimal style" height="28">

## Variants

### Pinned dark mode — [`dark.yml`](examples/variants/dark.yml)

For READMEs that pair light/dark images with `#gh-light-mode-only` / `#gh-dark-mode-only` links.

```yaml
style: banner
theme:
  mode: dark
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/variants/dark-banner.svg" alt="dark banner" width="840">

### Monthly window — [`month.yml`](examples/variants/month.yml)

```yaml
period: 1m
style: forecast
forecast:
  days: 14
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/variants/month-forecast.svg" alt="month forecast" width="760">

### Localized phrases — [`korean.yml`](examples/variants/korean.yml)

One message per condition, with `{repo}` / `{commits}` / `{authors}` / `{issues}` / `{prs}` / `{stars}` placeholders.

```yaml
messages:
  windy: "강풍 — 논의는 많고 머지는 적습니다"
  sunny: "쾌청 — 커밋 {commits}건이 쏟아집니다"
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/variants/korean-card.svg" alt="korean phrases" width="480">

### Mono theme — [`mono.yml`](examples/variants/mono.yml)

The sky desaturates; only the icon accent survives.

```yaml
theme:
  preset: mono
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/variants/mono-card.svg" alt="mono theme" width="480">

### Static — [`static.yml`](examples/variants/static.yml)

No animation: rays do not turn, rain does not fall.

```yaml
animated: false
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/variants/static-card.svg" alt="static" width="480">

### A quiet repository — [`quiet.yml`](examples/variants/quiet.yml)

Silence is weather too: a repo with nothing landing reads as snow, a faint trickle as fog.

```yaml
period: 7d   # nothing else — quiet is detected, not configured
```

<img src="https://raw.githubusercontent.com/crystal-actions/activity-weather/main/examples/variants/quiet-card.svg" alt="quiet repository" width="480">

## How the weather is decided

Activity over the window is scored into points (commits, PRs, issues, releases, stars, active authors — each weighted), then log-scaled into a 0–40° **temperature** so a steady hobby project reads warm and a monorepo saturates instead of breaking the thermometer. **Wind** is churn, **humidity** is backlog pressure (opened vs closed), and the **pressure trend** compares the window against the one before it.

Conditions, first match wins:

| Condition | When |
|---|---|
| 🌌 `aurora` | Stars surging in (≥ 10/day) |
| 🌈 `rainbow` | A release shipped into a busy week |
| ⛈ `stormy` | Issues flooding in faster than they close |
| ❄️ `snowy` | Nothing landed, almost nothing stirred (or the repo is archived) |
| 🌫 `foggy` | A faint trickle of activity |
| 🌧 `rainy` | The backlog swelling — much opened, little closed |
| 💨 `windy` | More discussion than code |
| ☀️ `sunny` | Hot and dry — lots landing, backlog under control |
| ⛅ `partly_cloudy` | Comfortably active |
| ☁️ `cloudy` | The unremarkable middle |

Every threshold is tunable — see `thresholds` below.

## Inputs

| Input | Default | Description |
|---|---|---|
| `config` | `.github/activity-weather.yml` | Config file path (optional — zero config works) |
| `token` | `${{ github.token }}` | GitHub API token |
| `repo` | the current repository | `owner/name` to report on |
| `period` | `7d` | Window: `1d`–`90d`, also `2w`, `1m` |
| `no_commit` | `false` | Generate but don't commit/push |
| `commit_message` | `chore: update activity weather` | Commit message |

## Outputs

| Output | Example | Description |
|---|---|---|
| `condition` | `sunny` | The weather condition |
| `temperature` | `23.5` | Activity temperature, 0–40 |
| `phrase` | `Clear skies — commits are pouring in` | The one-line report |
| `paths` | `ACTIVITY_WEATHER.svg` | Comma-separated written files |
| `width`, `height` | `480`, `240` | Pixel size of the first file |
| `changed` | `true` | Whether a commit was pushed |

## Configuration

All keys are optional. The full shape:

```yaml
# .github/activity-weather.yml
repo: owner/name            # default: the repository running the workflow
period: 7d                  # 1d..90d; also Nw / Nm
style: card                 # card | forecast | banner | terminal | minimal
output: ACTIVITY_WEATHER.svg

# Multiple files per run — mix styles and pinned theme modes:
outputs:
  - path: docs/weather.svg
    style: banner
  - path: docs/weather-dark.svg
    style: banner
    mode: dark              # auto | light | dark
  - path: docs/badge.svg
    style: minimal

animated: true              # false = fully static SVG
title: "Weather in {repo}"  # optional heading override

forecast:
  days: 7                   # 0..14 trailing days in forecast-style renders

metrics:
  stars: true               # false skips the stargazer fetch
  releases: true            # false skips the release fetch (and rainbows)

thresholds:                 # the decision tree's dials (defaults shown)
  sunny_temp: 25.0
  storm_issues_per_day: 3.0
  fog_points_per_day: 1.0
  rain_humidity: 70
  windy_wind: 25
  aurora_stars_per_day: 10.0
  rainbow_min_temp: 15.0

messages:                   # per-condition phrase overrides; placeholders:
  sunny: "쾌청 — 커밋 {commits}건"   # {repo} {commits} {authors} {issues} {prs} {stars}

theme:
  preset: github            # github | midnight | paper | mono
  mode: auto                # auto follows the viewer's color scheme
  # background: "#0d1117"   # page background behind the rounded card
  # text_color: "#ffffff"   # force the ink; default picks per condition
  # dark: { background: "...", text_color: "..." }
  # font_family: "Inter, sans-serif"
```

The condition owns the sky — each condition has its own day/dusk gradient pair — while the theme decides the chrome around it. The `mono` preset trades the skies for a neutral ramp.

## Running locally

```console
$ crystal build src/main.cr -o bin/activity-weather --release
$ GITHUB_TOKEN=$(gh auth token) bin/activity-weather -c examples/showcase.yml
activity-weather v0.1.0
```

Nothing is committed locally unless `--commit` is passed. `just render` runs the published container the way the action would.

## Versioning

Pin the action to a release tag; the log's first line names the build:

```
activity-weather v0.1.0
```

| Ref | Meaning |
|---|---|
| `@v0` | Latest v0 release (moves with releases) |
| `@v0.1.0` | Exactly this release, resolved to its own immutable image |
| `@main` | Latest code, floating image |

## Development

```console
$ just build   # shards install + build
$ just test    # crystal spec
$ just check   # format check + ameba + version check
$ just golden  # re-record renderer golden files
```

The renderer output is deterministic — seeded per repository — so the SVGs are golden-file tested byte for byte.

## License

MIT — see [LICENSE](LICENSE).
