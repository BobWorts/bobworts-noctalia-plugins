# BobWorts' Noctalia Plugins

A small collection of plugins for the [Noctalia](https://noctalia.dev) desktop shell.

## Plugins

| Plugin | ID | Entry | Description |
| --- | --- | --- | --- |
| Media Extra | `bobworts/media-extra` | `bar` | Universal MPRIS now-playing widget with configurable layout, album artwork, scrolling text and playback controls. |

## Installation

Add this repository as a plugin source in Noctalia:

```sh
noctalia msg plugins source add bobworts git https://github.com/BobWorts/bobworts-noctalia-plugins.git
```

Then enable the plugin in **Settings → Plugins** and add its `bar` widget to a bar.

## License

Apache-2.0. See [LICENSE](LICENSE). Each plugin keeps its own license file.
