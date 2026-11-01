# Provider artwork

`OpenAI.svg` and `Claude.svg` are unmodified template marks from [CodexBar](https://github.com/steipete/CodexBar/tree/897bff31731bb4b21b105f6e8bf4c32a8a8bf095/Sources/CodexBar/Resources): `ProviderIcon-codex.svg` and `ProviderIcon-claude.svg`. The upstream MIT notice is bundled in `CodexBar-LICENSE.txt`. The marks identify the respective products and remain the property of OpenAI and Anthropic.

SHA-256:

- `OpenAI.svg`: `5c999792f6d26c9d14a197aa6e6c20f5af3def433473f7b66bd0d8c8a41cd8cf`
- `Claude.svg`: `497a88a780831512317b6dd061285e2ec2608abf09a94a5f24ee9019a4d3ef8b`

The panel uses native blue for Codex and Anthropic's [documented primary accent](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/brand-guidelines/SKILL.md), `#D97757`, for Claude. Blue is a UI accent, not a claim about OpenAI's brand palette. Menu-bar marks remain adaptive monochrome. Both assets load once through AppKit's SVG decoder; SwiftUI's named-image loader does not resolve these loose SVG resources.
