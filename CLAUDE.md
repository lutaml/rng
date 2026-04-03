# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RNG is a Ruby gem for parsing, manipulating, and converting RELAX NG schemas (both RNG XML and RNC compact syntax). It uses Lutaml::Model for the object model, Parslet for RNC parsing, and Nokogiri for XML processing.

## Commands

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rspec

# Run a specific test file
bundle exec rspec spec/rng/rnc_parser_spec.rb

# Run a specific test by line number
bundle exec rspec spec/rng/rnc_parser_spec.rb:42

# Run the official test suite (Jing-Trang compacttest.xml)
bundle exec rspec spec/rng/compacttest_spec.rb

# Run linter with auto-fix
bundle exec rubocop -A

# Run default task (tests + rubocop)
bundle exec rake
```

### CLI Commands

```bash
# Validate a schema
rng validate schema.rng

# Validate an XML document against a schema
rng validate schema.rng document.xml

# Convert between RNG and RNC formats
rng convert schema.rng -o schema.rnc
rng convert schema.rnc -o schema.rng

# Parse and display schema structure
rng parse schema.rng

# Show schema information
rng info --statistics schema.rng
```

## Architecture

The library has two parsing paths and one generation path:

### RNG XML Parsing
`Rng.parse()` → `Grammar.from_xml()` → Lutaml::Model with Nokogiri adapter

All RNG model classes inherit from `Lutaml::Model::Serializable` and define XML mappings via the `xml do` block.

### RNC Compact Parsing
`Rng.parse_rnc()` → `RncParser.parse()` → `ParseTreeProcessor.normalize()` → `RncToRngConverter.convert()` → `Grammar.from_xml()`

The RNC parser is a Parslet-based PEG parser in `lib/rng/rnc_parser.rb`. Key supporting classes:
- `ParseTreeProcessor` (`lib/rng/parse_tree_processor.rb`) - Normalizes parse trees into consistent grammar structures
- `RncToRngConverter` (`lib/rng/rnc_to_rng_converter.rb`) - Converts parse trees to RNG XML using Nokogiri builder
- `IncludeProcessor` (`lib/rng/include_processor.rb`) - Handles file I/O and include directive resolution

### RNG to RNC Generation
`Rng.to_rnc()` → `ToRnc.convert()` → `RncParser.to_rnc()` → `RncBuilder.build()`

`RncBuilder` (`lib/rng/rnc_builder.rb`) traverses the object model and generates RNC text.

## Key Dependencies

- **lutaml-model** - Object model and XML serialization
- **nokogiri** - XML parsing and building
- **parslet** - RNC compact syntax parser
- **canon** - XML comparison matchers for tests (`be_xml_equivalent_with`)

## Object Model Structure

The object model mirrors RELAX NG concepts:
- `Grammar` - Root container (can have start, define, element, include)
- `Start` - Entry point definition
- `Define` - Named pattern definitions
- `Element` / `Attribute` - XML structures
- Pattern classes: `Choice`, `Group`, `Interleave`, `Mixed`, `Optional`, `ZeroOrMore`, `OneOrMore`, `Text`, `Empty`, `Value`, `Data`, `List`
- Reference classes: `Ref`, `ParentRef`, `ExternalRef`
- Name classes: `Name`, `AnyName`, `NsName`, `Except`
- `Div` - Documentation and grouping container

## Design Decisions

- **Foreign elements/attributes are NOT supported**: The RELAX NG spec allows elements and attributes from non-RNG namespaces as annotations. This library does not preserve or round-trip them. They are silently dropped during XML parsing and not stored in the object model. Tests containing foreign elements/attributes are skipped with an explicit message. Do not add `foreign_elements` or `foreign_attributes` attributes to model classes.

## External Href Resolution

The library supports resolving external references via `Rng.parse(rng_xml, location: path, resolve_external: true)`:

- **`<include href="uri"/>`** at grammar level - merges definitions from external grammar
- **`<externalRef href="uri"/>`** at pattern level - replaces ref with content from external grammar's start pattern

### Setting Up Test Fixtures from Jing-Trang

The spectest_spec.rb has 22 pending tests that require external resources from Jing-Trang's test suite. To enable these tests:

1. Ensure Jing-Trang is checked out at `~/src/external/jing-trang`

2. Extract test fixtures:
   ```bash
   bundle exec rake fixtures:extract_spectest
   # or
   ruby scripts/extract_spectest_resources.rb
   ```

   This creates `spec/fixtures/spectest_external/` with 20 test cases, each in its own `case_N/` subdirectory.

3. Note: Each spectest.xml test case has isolated resources (virtual file system). The Jing-Trang framework runs each test with its own set of resources. To fully enable these tests, spectest_spec.rb would need to be updated to copy resources for each test case before running.

## Important Notes

- The Nokogiri adapter must be configured at load time: `Lutaml::Model::Config.configure { |c| c.xml_adapter = Lutaml::Model::Xml::NokogiriAdapter }`
- Ruby 3.0.0+ required
- The `RNG_VERBOSE=1` environment variable enables parser warnings
- The official test suite (`spec/rng/compacttest_spec.rb`) uses Jing-Trang's `compacttest.xml` with 87 test cases

## Documentation Site

The gem has a Jekyll-based documentation site in `docs/`:
- `docs/index.adoc` - Home page
- `docs/getting-started/` - Installation and quick start
- `docs/guides/` - Parsing, conversion, validation guides
- `docs/reference/` - API and CLI reference
- `docs/understanding/` - Architecture and format comparison

Build docs locally: `cd docs && bundle exec jekyll serve`
