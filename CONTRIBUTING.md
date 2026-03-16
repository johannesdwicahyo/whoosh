# Contributing to Whoosh

Thank you for your interest in contributing!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/whoosh.git`
3. Install dependencies: `bundle install`
4. Run tests: `bundle exec rspec`
5. Create a branch: `git checkout -b my-feature`

## Development

```bash
bundle exec rspec              # Run all tests
bundle exec rspec spec/whoosh/ # Run unit tests only
bundle exec rspec spec/integration/ # Run integration tests
bundle exec ruby benchmarks/simple_json.rb # Run benchmarks
```

## Pull Requests

- Write tests for new features (TDD preferred)
- Ensure all tests pass: `bundle exec rspec`
- Follow existing code style
- Keep commits focused and well-described
- Update CHANGELOG.md

## Reporting Issues

Open an issue at https://github.com/johannesdwicahyo/whoosh/issues with:
- Ruby version (`ruby -v`)
- Whoosh version
- Steps to reproduce
- Expected vs actual behavior

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
