# Veil

A small native macOS menu bar app that shows your remaining weekly allowance for Codex and Claude Code.

This is a purely personal project. I built it for my own use and am sharing the source as-is, with no promise of support or updates.

![Buffer and deficit views with sample data in light and dark mode](docs/usage.png)

## Run

Requires macOS 27, Swift 6.2 or newer, and existing Codex and Claude Code CLI logins.

```sh
./scripts/run
```

Veil reads your existing CLI logins without refreshing or changing them. It uses private usage APIs and may break if they change.

## License

[MIT](LICENSE). See the [provider artwork credits](Sources/Veil/Resources/Artwork.md) for attribution.

Inspired by [CodexBar](https://github.com/steipete/CodexBar) and [tinybar](https://github.com/ThiloReintjes/tinybar).
