# Technology Stack

## Core Technologies

### Ruby
- **Version**: 3.0.0+
- **Purpose**: Primary programming language
- **Current Version**: 0.1.2

### Primary Dependencies

#### Lutaml::Model
- **Purpose**: Foundation for serializable model classes
- **Usage**: All RNG model classes inherit from Lutaml::Model::Serializable
- **Features Used**:
  - XML serialization/deserialization
  - Automatic attribute mapping
  - Collection handling with initialize_empty
  - Value mapping for special attributes (empty, omitted, nil)
  - Ordered XML elements (ordered: true)
  - Namespace support
- **Version**: ~> 0.7 (recommended in brief)

#### Nokogiri
- **Purpose**: XML parsing and generation
- **Usage**:
  - XML document parsing (via Lutaml::Model adapter)
  - XML building (Nokogiri::XML::Builder) for RNC → RNG conversion
- **Features Used**:
  - XML parsing with namespaces
  - XML building with builder pattern
  - UTF-8 encoding support

#### Parslet
- **Purpose**: Parser creation for RNC (RELAX NG Compact syntax)
- **Usage**: RncParser inherits from Parslet::Parser
- **Features Used**:
  - PEG (Parsing Expression Grammar) rules
  - Pattern matching and repetition
  - Parse tree generation
  - Recursive parsing

## Development Dependencies

### Testing
- **RSpec**: Testing framework
  - Unit tests for classes
  - Integration tests for parsing/generation
  - Round-trip tests for format conversion

- **Canon**: XML comparison matchers
  - be_xml_equivalent_with() - Structural comparison
  - be_equivalent_to_xml() - Formatted comparison

### Code Quality
- **Rubocop**: Ruby linter and formatter
  - rubocop-performance: Performance-focused cops
  - rubocop-rake: Rake-specific rules
  - rubocop-rspec: RSpec-specific rules

### Build Tools
- **Rake**: Task automation
- **Bundler**: Dependency management

## Architecture Patterns

### Object-Oriented Design
- **Inheritance**: All model classes inherit from Lutaml::Model::Serializable or base pattern class
- **Composition**: Complex patterns composed of simpler patterns
- **Polymorphism**: Uniform interface for all pattern types

### Parser Patterns
- **PEG Grammar**: Parslet uses Parsing Expression Grammar for RNC
- **Recursive Descent**: Both parsers use recursive pattern matching
- **Builder Pattern**: Nokogiri::XML::Builder for XML generation

### Data Flow
```
RNG XML ──► Nokogiri/Lutaml ──► Grammar Object ──► RncBuilder ──► RNC String
                                       ▲                   │
                                       │                   ▼
RNC String ──► Parslet Parser ──► Parse Tree ──► Nokogiri Builder ──► RNG XML
```

## Development Setup

### Installation
```bash
gem install rng
# or in Gemfile
gem 'rng'
```

### Local Development
```bash
git clone https://github.com/lutaml/rng.git
cd rng
bundle install
```

### Running Tests
```bash
bundle exec rspec
```

### Running Linter
```bash
bundle exec rubocop
bundle exec rubocop -A  # Auto-correct
```

## Technical Constraints

### Ruby Version
- Requires Ruby 3.0.0 or higher
- Uses modern Ruby features

### XML Namespace
- All RNG XML uses namespace: http://relaxng.org/ns/structure/1.0
- Must be preserved in round-trip conversions

### Attribute Value Mapping
- Special values handled: empty, omitted, nil
- Preserved during serialization/deserialization
- Critical for accurate schema representation

### Datatype Libraries
- Default: XML Schema datatypes (http://www.w3.org/2001/XMLSchema-datatypes)
- Configurable at grammar and pattern levels
- Must be preserved in conversions

## File Organization

### Library Structure
```
lib/
├── rng.rb                    # Main entry point
└── rng/
    ├── version.rb            # Version constant
    ├── grammar.rb            # Root container
    ├── parse_rnc.rb          # RNC parser wrapper
    ├── to_rnc.rb             # RNC generator wrapper
    ├── rnc_parser.rb         # Parslet parser + RncBuilder
    ├── pattern.rb            # Base pattern class
    ├── element.rb            # Element patterns
    ├── attribute.rb          # Attribute patterns
    ├── start.rb              # Start definitions
    ├── define.rb             # Named patterns
    ├── choice.rb             # Choice patterns
    ├── group.rb              # Group patterns
    ├── interleave.rb         # Interleave patterns
    ├── optional.rb           # Optional patterns
    ├── zero_or_more.rb       # Zero or more patterns
    ├── one_or_more.rb        # One or more patterns
    ├── mixed.rb              # Mixed content
    ├── text.rb               # Text content
    ├── empty.rb              # Empty content
    ├── value.rb              # Value patterns
    ├── data.rb               # Data patterns
    ├── list.rb               # List patterns
    ├── ref.rb                # References
    ├── parent_ref.rb         # Parent references
    ├── external_ref.rb       # External references
    ├── name.rb               # Name classes
    ├── any_name.rb           # Any name wildcards
    ├── ns_name.rb            # Namespace wildcards
    ├── except.rb             # Exception patterns
    ├── param.rb              # Parameters
    ├── not_allowed.rb        # Not allowed patterns
    └── include.rb            # Include directives
```

### Test Structure
```
spec/
├── spec_helper.rb
├── rng_spec.rb               # Basic version test
└── rng/
    ├── schema_spec.rb        # RNG parsing tests
    ├── rnc_parser_spec.rb    # RNC parser tests (disabled)
    ├── rnc_roundtrip_spec.rb # Conversion tests
    └── spectest_spec.rb      # Official test suite
```

### Fixtures
```
spec/fixtures/
├── rng/
│   ├── address_book.rng
│   ├── relaxng.rng
│   └── testSuite.rng
├── rnc/
│   ├── address_book.rnc
│   └── complex_example.rnc
└── spectest.xml
```

## Integration Points

### Lutaml Ecosystem
- Part of the Lutaml suite of modeling tools
- Shares common patterns with other Lutaml libraries
- Uses lutaml-model for serialization

### XML Processing
- Standard XML namespace handling
- Compatible with XML schema tools
- Supports RELAX NG validation workflows

### Ruby Applications
- Can be integrated into Rails applications
- Suitable for CLI tools
- Useful for API schema validation