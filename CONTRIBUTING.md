# Contributing to Mercato

Thank you for your interest in contributing to Mercato! This document provides guidelines and information for contributors.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. Please be respectful and constructive in all interactions.

## How to Contribute

### Reporting Issues

- Use the GitHub issue tracker to report bugs or request features
- Search existing issues before creating a new one
- Provide clear, detailed descriptions with steps to reproduce
- Include relevant system information (Elixir/OTP versions, etc.)

### Submitting Changes

1. **Fork the repository** and create a feature branch
2. **Write tests** for your changes
3. **Ensure all tests pass**: `mix test`
4. **Follow code style**: Run `mix format` and `mix credo` (if available)
5. **Update documentation** for any API changes
6. **Submit a pull request** with a clear description

### Development Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/0xMikeAdams/mercato.git
   cd mercato
   ```

2. **Install dependencies**:
   ```bash
   mix deps.get
   ```

3. **Set up the database** (for testing):
   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

4. **Run tests**:
   ```bash
   mix test
   ```

### Code Style Guidelines

- Follow standard Elixir formatting: `mix format`
- Use descriptive variable and function names
- Write clear, concise documentation
- Include `@doc` for all public functions
- Include `@moduledoc` for all modules
- Use pattern matching and pipe operators idiomatically

### Testing Guidelines

- Write tests for all new functionality
- Include both unit tests and integration tests
- Use property-based testing for complex logic
- Maintain good test coverage
- Test both success and error cases

### Documentation

- Update README.md for user-facing changes
- Add examples for new features
- Update CHANGELOG.md following [Keep a Changelog](https://keepachangelog.com/) format
- Include inline documentation with examples

## Project Structure

```
mercato/
├── lib/mercato/           # Main library code
│   ├── catalog/          # Product catalog functionality
│   ├── cart/             # Shopping cart functionality
│   ├── orders/           # Order management
│   ├── customers/        # Customer management
│   ├── coupons/          # Discount system
│   ├── subscriptions/    # Recurring billing
│   ├── referrals/        # Referral system
│   └── behaviours/       # Extensible behaviors
├── test/                 # Test files
├── priv/repo/migrations/ # Database migrations
└── examples/             # Integration examples
```

## Areas for Contribution

### High Priority
- Additional payment gateway implementations
- More shipping calculator options
- Tax calculation improvements
- Performance optimizations
- Documentation improvements

### Medium Priority
- Additional product types
- Enhanced reporting features
- API improvements
- Integration examples
- Localization support

### Low Priority
- Admin interface components
- Additional test coverage
- Code quality improvements

## Release Process

1. Update version in `mix.exs`
2. Update `CHANGELOG.md` with new features and fixes
3. Ensure all tests pass
4. Create a pull request for review
5. After merge, maintainers will tag and release

## Getting Help

- Check existing documentation and examples
- Search through existing issues
- Ask questions in GitHub Discussions
- Join the Elixir community forums

## Recognition

Contributors will be recognized in:
- CHANGELOG.md for significant contributions
- GitHub contributors list
- Release notes for major features

Thank you for helping make Mercato better!