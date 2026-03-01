# Contributing to Launchyard

Thanks for your interest in contributing! Here's how to get started.

## Getting Started

1. Fork the repo and clone your fork
2. Create a branch for your work: `git checkout -b feature/your-feature`
3. Make your changes
4. Test thoroughly on macOS 14+
5. Submit a pull request

## Guidelines

### Code

- **Swift & SwiftUI only** — No UIKit, no Objective-C unless absolutely necessary
- **Follow existing patterns** — Match the code style and architecture already in the project (MVVM, services layer)
- **No third-party dependencies** — Keep it lean. If you need something, build it or justify the dependency in your PR
- **Target macOS 14+** — Don't use APIs unavailable on Sonoma

### Pull Requests

- Keep PRs focused — one feature or fix per PR
- Write a clear description of what changed and why
- Include screenshots for UI changes
- Make sure it builds with no warnings

### Issues

- Check existing issues before opening a new one
- Bug reports: include macOS version, steps to reproduce, and expected vs actual behavior
- Feature requests: describe the use case, not just the solution

### What We're Looking For

- Bug fixes
- UI/UX improvements
- Support for additional launchd keys in the editor
- Better log viewing (live tail, filtering)
- Accessibility improvements
- Performance improvements

### What We'll Probably Decline

- Adding third-party dependencies without strong justification
- Major architecture changes without prior discussion
- Features that require elevated privileges (sudo) without a clear security model

## Code of Conduct

Be kind. Be constructive. We're all here to make a useful tool.
