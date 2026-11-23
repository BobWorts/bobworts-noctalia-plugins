# Media Extra

A compact now-playing widget for the Noctalia bar. It follows any MPRIS player and shows album artwork, scrolling track information and playback controls. It works on any compositor supported by Noctalia.

## Plugin

| Field | Value |
| --- | --- |
| ID | `bobworts/media-extra` |
| Entries | Bar widget: `bar` |

## Requirements

- Noctalia v5.5.0 or newer.
- A player that exposes MPRIS. Some players need a bridge (for example `mpv-mpris` for mpv, `cmus-mpris` for cmus, `mpDris2` for MPD).
- The `noctalia` command in `PATH` for the playback buttons.

## Usage

Enable **Media Extra** in Settings → Plugins, then add the `bar` widget to a bar.

When media is playing, the widget shows the artwork, the track text and the playback buttons. Hovering over the text shows the full track information in a tooltip.

| Input | Action |
| --- | --- |
| Left click / artwork / text | Open or focus the current player |
| Right click | Play / pause |
| Middle click | Switch to the next player |
| Scroll up / down | Next / previous track |

The right click, middle click and scroll actions are native Noctalia widget actions and can be changed in the widget action editor.

When no player is running, the widget shows an app icon or a glyph, or hides itself. English and Russian translations are included.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `layout` | `select` | `art_text_controls` | Presets for artwork, text and controls, or a custom mix |
| `show_artwork` | `bool` | `true` | Show artwork in a custom layout |
| `show_text` | `bool` | `true` | Show text in a custom layout |
| `show_controls` | `bool` | `true` | Show buttons in a custom layout |
| `text_format` | `select` | `artist_title` | Artist – title, title – artist, title, artist, album – title, custom |
| `text_template` | `string` | `{artist} - {title}` | Custom template tokens: `{title}`, `{artist}`, `{artists}`, `{album}`, `{player}`, `{position}`, `{length}` |
| `text_width` | `int` | `140` | Text width on a horizontal bar, 100–320 px |
| `art_size` | `int` | `20` | Artwork size, 8–28 px |
| `art_shape` | `select` | `rounded` | Rounded, circle or square |
| `art_gap` | `int` | `6` | Gap after the artwork, 0–24 px |
| `placeholder` | `select` | `none` | Placeholder while artwork is missing: none, app icon or glyph |
| `placeholder_glyph` | `glyph` | `music` | Placeholder glyph |
| `idle_mode` | `select` | `app_icon` | What to show with no player: app icon, glyph or hidden |
| `idle_glyph` | `glyph` | `music` | Idle glyph |
| `text_scroll` | `select` | `always` | Always, on hover or never |
| `scroll_speed` | `int` | `8` | Scrolling speed in text columns per second |
| `font_size` | `int` | `13` | Track text size, 10–20 px |
| `marquee_gap` | `int` | `3` | Blank columns between repetitions |
| `progress_style` | `select` | `none` | None or a thin progress bar |
| `progress_thickness` | `int` | `2` | Progress bar thickness, 1–4 px |
| `controls_style` | `select` | `all` | All buttons, play/pause only, previous/next only or none |
| `button_size` | `int` | `22` | Button size, 16–28 px |
| `icon_size` | `int` | `16` | Glyph size inside buttons, 10–20 px |
| `vertical_text_width` | `int` | `28` | Text width on a vertical bar, 16–80 px |
| `hide_when_no_media` | `bool` | `false` | Hide the widget when nothing is playing |
| `hide_when_idle` | `bool` | `false` | Hide the widget while paused or stopped |

## Notes

- Artwork comes from the MPRIS metadata. Local paths, `file://` URLs and `http(s)` URLs are supported. Images are cached in the plugin data directory and two alternating files are used so a partially written image is never shown.
- The widget follows Noctalia's player selection, player preferences and MPRIS blacklist.
- Position and progress come directly from `noctalia.mediaPlayer()`.
- Left click tries MPRIS `Raise` through `busctl` or `gdbus`, then falls back to launching the player's desktop entry.
- The plugin can be controlled over IPC: `noctalia msg plugin bobworts/media-extra:bar focused <command>`, where command is `dump`, `refresh`, `toggle`, `next`, `previous`, `next-player`, `previous-player` or `open`.

## License

Apache-2.0 © 2026 BobWorts
