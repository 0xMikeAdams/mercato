# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2024-12-30

### Added

#### Core E-commerce Features
- **Product Catalog Management**: Complete product management with support for simple, variable, downloadable, virtual, and subscription products
- **Shopping Cart System**: Anonymous and authenticated carts with real-time updates via Phoenix PubSub
- **Order Management**: Full order lifecycle with status tracking, audit trails, and event broadcasting
- **Customer Management**: Guest checkout support with optional user registration and saved addresses
- **Coupon & Discount System**: Flexible promotion engine with percentage, fixed cart, fixed product, and free shipping discounts
- **Subscription Billing**: Recurring payment support with multiple billing cycles and automated processing
- **Referral System**: Commission tracking with shortlink attribution and analytics

#### Technical Features
- **Real-time Updates**: Phoenix PubSub integration for live cart, order, and inventory updates
- **Extensible Architecture**: Behavior-based plugin system for payment gateways, shipping calculators, and tax engines
- **Database Migrations**: Complete Ecto schema definitions with automated migration generation
- **Phoenix Integration**: Router helpers, controller examples, and LiveView integration patterns
- **Configuration Management**: Flexible store settings with runtime configuration support

#### Developer Experience
- **Comprehensive API**: Clean, ergonomic public APIs following Elixir conventions
- **Documentation**: Complete module and function documentation with examples
- **Testing Suite**: Property-based testing with StreamData and comprehensive unit tests using ExMachina
- **Installation Tools**: `mix mercato.install` task for easy project setup
- **Integration Examples**: Phoenix router, LiveView, and traditional controller examples

#### Extensibility
- **Payment Gateway Behavior**: Pluggable payment processing with dummy implementation included
- **Shipping Calculator Behavior**: Customizable shipping logic with flat rate default
- **Tax Calculator Behavior**: Flexible tax calculation system
- **Event System**: Comprehensive event broadcasting for all state changes

### Technical Details
- **Elixir Version**: Requires Elixir ~> 1.14
- **Dependencies**: Ecto 3.11+, Phoenix PubSub 2.1+, Decimal 2.0+
- **Database**: PostgreSQL support with Ecto migrations
- **Testing**: ExMachina factories and StreamData property-based testing

[Unreleased]: https://github.com/0xMikeAdams/mercato/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/0xMikeAdams/mercato/releases/tag/v0.1.0