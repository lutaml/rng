# Architecture

## System Architecture

The Rng library implements a layered architecture for RELAX NG schema processing:

```
┌────────────────────────────────────────────────────────┐
│                   Public API Layer                     │
│  Rng.parse() | Rng.parse_rnc() | Rng.to_rnc()         │
└─────────────┬──────────────────────────┬───────────────┘
              │                          │
              ▼                          ▼
┌─────────────────────────┐  ┌──────────────────────────┐
│   Parsing Layer         │  │   Generation Layer       │
│                         │  │                          │
│  XML/RNG Parser         │  │  RNC Generator           │
│  (Lutaml::Model +       │  │  (RncBuilder)            │
│   Nokogiri)             │  │                          │
│                         │  │  RNG Generator           │
│  Compact/RNC Parser     │  │  (Nokogiri XML Builder)  │
│  (Parslet + Custom      │  │                          │
│   Grammar)              │  │                          │
└─────────────┬───────────┘  └───────────▲──────────────┘
              │                          │
              ▼                          │
┌────────────────────────────────────────┴───────────────┐
│              Object Model Layer                        │
│                                                        │
│  Grammar ─► Start ─► Element ─► Attribute             │
│         └─► Define                                     │
│         └─► Pattern Classes (Choice, Group, etc.)     │
│                                                        │
│  All classes inherit from Lutaml::Model::Serializable │
└────────────────────────────────────────────────────────┘
```

## Source Code Organization

### Core Module (lib/rng.rb)
Entry point providing high-level API:
- Rng.parse(rng) - Parse RNG XML to object model
- Rng.parse_rnc(rnc) - Parse RNC to object model
- Rng.to_rnc(schema) - Convert object model to RNC string

### Model Classes (lib/rng/*.rb)
Each RELAX NG concept is a separate class:

**Primary Classes:**
- grammar.rb - Root schema container, can hold start, define, element, include
- start.rb - Entry point definition in grammar
- define.rb - Named pattern definitions
- element.rb - XML element patterns
- attribute.rb - XML attribute patterns

**Pattern Classes:**
- choice.rb - Alternation between patterns (A | B)
- group.rb - Sequence of patterns (A, B)
- interleave.rb - Patterns that can be interleaved (A & B)
- mixed.rb - Mixed content (text and elements)
- optional.rb - Optional pattern (A?)
- zero_or_more.rb - Zero or more occurrences (A*)
- one_or_more.rb - One or more occurrences (A+)

**Content Classes:**
- text.rb - Text content
- empty.rb - Empty content
- value.rb - Specific value
- data.rb - Datatype constraint
- list.rb - List of values

**Reference Classes:**
- ref.rb - Reference to named pattern
- parent_ref.rb - Reference to parent grammar pattern
- external_ref.rb - Reference to external grammar

**Name Classes:**
- name.rb - Element/attribute name
- any_name.rb - Wildcard for any name
- ns_name.rb - Namespace wildcard

**Other Classes:**
- pattern.rb - Base class for patterns (not actively used)
- not_allowed.rb - Pattern that never matches
- except.rb - Exception pattern for wildcards
- param.rb - Parameter for datatype
- include.rb - Include external grammar

### Parsing Layer

**RNG XML Parsing:**
- Uses Grammar.from_xml() method from Lutaml::Model
- Nokogiri adapter handles XML parsing
- XML namespace: http://relaxng.org/ns/structure/1.0
- All attributes preserve special values: empty, omitted, nil

**RNC Compact Parsing:**
The RNC parser has been refactored into focused, single-responsibility classes:

- **lib/rng/rnc_parser.rb** (~306 lines)
  - Parslet-based parser defining RNC grammar rules
  - Handles lexical analysis and creates parse trees
  - Delegates to other components for processing
  - Key rules: element_def, attribute_def, choice_def, group_def, named_pattern, start_def

- **lib/rng/parse_tree_processor.rb** (~125 lines)
  - Normalizes parse trees into consistent grammar structures
  - Handles three RNC file formats: top-level includes, grammar blocks, and flat grammars
  - Transforms various parse tree formats into standardized Grammar objects

- **lib/rng/rnc_to_rng_converter.rb** (~522 lines)
  - Converts RNC parse trees to RNG XML using Nokogiri XML builder
  - Handles all pattern types and wildcard name classes
  - Processes content items recursively
  - Generates proper XML namespace declarations

- **lib/rng/include_processor.rb** (~297 lines)
  - Manages file I/O and include directive resolution
  - Handles circular include detection
  - Supports grammar merging with override behavior
  - Resolves file paths relative to including file

### Generation Layer

**RNC Generation:**
- **lib/rng/rnc_builder.rb** (~482 lines)
  - Generates RNC text from RNG object model
  - Traverses object model and produces compact syntax
  - Handles simple element patterns, grammar blocks, datatype libraries
  - Private methods: build_element(), build_content(), build_attribute(), build_pattern()

**RNG XML Generation:**
- Currently stub implementation (lib/rng/to_rnc.rb)
- Planned to use Lutaml::Model's to_xml() method
- Should leverage existing XML mappings in model classes

### Wrapper Modules

**ParseRnc (lib/rng/parse_rnc.rb):**
- Wrapper around RncParser.parse()
- Provides stable API if parser implementation changes

**ToRnc (lib/rng/to_rnc.rb):**
- Wrapper around conversion logic
- Currently stub implementation

## Key Technical Decisions

### Model-Driven Architecture

**Decision**: Use Lutaml::Model for all schema classes

**Rationale**:
- Provides automatic XML serialization/deserialization
- Enforces consistent structure across classes
- Enables round-trip testing (parse → generate → parse)
- Integrates with Lutaml ecosystem

**Implementation**:
- Each class inherits from Lutaml::Model::Serializable
- XML mapping defined in xml do blocks
- Attributes map to both elements and attributes
- Collections use collection: true option
- Empty collections initialized with initialize_empty: true

### Two-Parser Approach

**Decision**: Separate parsers for RNG XML and RNC Compact

**Rationale**:
- RNG XML: Leverage Lutaml::Model's XML parsing (Nokogiri)
- RNC Compact: Custom grammar requires specialized parser (Parslet)
- Each format has different complexity and requirements

**Trade-offs**:
- ✅ Clean separation of concerns
- ✅ Optimal tool for each format
- ❌ Two codebases to maintain
- ❌ Conversion requires intermediate format

### Object Model Design

**Decision**: Deep object hierarchy mirroring RELAX NG spec

**Rationale**:
- Direct mapping to RELAX NG concepts
- Easy to understand for users familiar with spec
- Supports all RELAX NG features

**Structure**:
Grammar can contain:
- start: Start (entry point)
- define: array of Define (named patterns)
- element: array of Element (direct elements)
- Element can contain nested elements, attributes, and patterns

### Namespace Handling

**Decision**: Preserve namespace information in ns attribute

**Implementation**:
- All pattern classes have ns attribute
- Special value maps for empty/omitted/nil
- Qualified names split into prefix + local_name

### Datatype Library Support

**Decision**: Store datatype library URI at grammar and pattern level

**Implementation**:
- Grammar-level: datatypeLibrary attribute
- Pattern-level: Each pattern can override with own datatypeLibrary
- Data class: type attribute references datatype (e.g., ID, string)

## Critical Implementation Paths

### RNG Parsing Flow
1. Rng.parse(xml_string)
2. Grammar.from_xml(xml_string)
3. Lutaml::Model deserializes using Nokogiri
4. Returns Grammar object with nested patterns

### RNC Parsing Flow
1. Rng.parse_rnc(rnc_string)
2. ParseRnc.parse(rnc_string)
3. RncParser.parse(rnc_string)
4. Parslet parser generates parse tree
5. RncParser.convert_to_rng(tree)
6. Nokogiri XML builder creates RNG XML
7. Grammar.from_xml(rng_xml)
8. Returns Grammar object

### RNC Generation Flow
1. Rng.to_rnc(schema)
2. ToRnc.convert(schema)
3. RncParser.to_rnc(schema)
4. RncBuilder.new.build(schema)
5. Traverses object model recursively
6. Builds RNC string with proper syntax
7. Returns RNC string

### Round-Trip Testing Pattern
1. Parse original format → Grammar object
2. Generate target format → string
3. Parse target format → Grammar object
4. Compare Grammar objects (analogous/equivalent)

## Design Patterns

### Visitor Pattern (Implicit)
RNC generation uses visitor-like pattern:
- build_pattern() dispatches based on node type
- Each pattern type has specific handling
- Recursive descent through object tree

### Builder Pattern
- RncBuilder constructs RNC strings incrementally
- Nokogiri::XML::Builder constructs XML documents
- Fluent interface for building schemas programmatically

### Composite Pattern
Pattern hierarchy:
- Elements can contain elements (recursive composition)
- Choice/Group/Interleave contain multiple patterns
- Uniform interface for all pattern types

## Testing Strategy

Located in spec/ directory:

- **Unit Tests**: spec/rng_spec.rb - Version check
- **Schema Tests**: spec/rng/schema_spec.rb - RNG parsing and round-trip
- **Parser Tests**: spec/rng/rnc_parser_spec.rb - RNC parser (currently disabled)
- **Round-Trip Tests**: spec/rng/rnc_roundtrip_spec.rb - RNC ↔ RNG conversion
- **Spec Test Suite**: spec/rng/spectest_spec.rb - Official RELAX NG test suite

**Test Fixtures**:
- spec/fixtures/rng/ - RNG XML samples
- spec/fixtures/rnc/ - RNC samples
- test-suite/ - Official RELAX NG test suite

**Custom Matchers** (via canon gem):
- be_xml_equivalent_with() - Structural XML comparison
- be_equivalent_to_xml() - Formatted XML comparison