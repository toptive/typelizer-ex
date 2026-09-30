# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Typelizer.Serializer`: a serializer DSL (`attributes`, `attribute` with `type:`,
  `nullable:` and `value:`, `has_one`, `has_many`) that builds `serialize/2` and
  `serialize_many/2` at compile time. Types are inferred from Ecto schemas, including
  `Ecto.Enum` literal unions and embeds. Keys are camelCase by default
  (`key_transform:`), dates become ISO-8601 strings and decimals strings (or numbers
  with `decimal_type: :number`). Mistakes are compile errors with a hint.
- User guides for the public API: getting started, serializers, route helpers,
  Inertia page props and configuration.
