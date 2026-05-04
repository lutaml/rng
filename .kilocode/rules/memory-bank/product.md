# Product Description

## Purpose

The Rng Ruby library provides comprehensive tools for working with RELAX NG schemas, which are XML schema languages used for validating XML documents. It serves as a bridge between Ruby applications and RELAX NG schema processing, enabling developers to parse, manipulate, generate, and convert RELAX NG schemas programmatically.

## Problems It Solves

1. **Schema Parsing**: Developers need to read and understand existing RELAX NG schemas (both XML and Compact syntax formats) within Ruby applications.

2. **Schema Generation**: Creating RELAX NG schemas by hand is tedious and error-prone. This library allows programmatic schema creation through an intuitive Ruby DSL.

3. **Format Conversion**: RELAX NG has two syntaxes (XML/RNG and Compact/RNC). Converting between them manually is complex. This library automates bidirectional conversion.

4. **Schema Manipulation**: Modifying existing schemas requires understanding the complete RELAX NG structure. This library provides an object model (DOM-like) for easy manipulation.

5. **Integration**: Part of the Lutaml modeling ecosystem, it enables XML schema processing within larger document processing workflows.

## How It Works

### Core Architecture

The library uses an object-oriented model-driven approach:

1. **Model Layer**: Each RELAX NG concept is represented as a Ruby class (Element, Attribute, Grammar, etc.) using Lutaml::Model for serialization
2. **Parsing Layer**: 
   - XML/RNG: Uses Lutaml::Model XML deserialization with Nokogiri
   - Compact/RNC: Uses Parslet parser with custom grammar rules
3. **Generation Layer**: 
   - RNG to RNC: RncBuilder traverses the object model and generates compact syntax
   - RNC to RNG: Parser transforms parse tree to Nokogiri XML builder output

### User Experience Goals

**Simple and Intuitive API**
- Top-level module functions: `Rng.parse()`, `Rng.parse_rnc()`, `Rng.to_rnc()`
- Clear separation between parsing and generation
- Object model mirrors RELAX NG specification concepts

**Comprehensive Coverage**
- All RELAX NG patterns supported (element, attribute, choice, group, etc.)
- All cardinality constraints (optional, zeroOrMore, oneOrMore)
- Named pattern definitions and references
- Namespace support
- Datatype library integration

**Bidirectional Conversion**
- Parse RNG → Object Model → Generate RNC
- Parse RNC → Parse Tree → Generate RNG → Object Model
- Round-trip fidelity (parse → generate → parse should be equivalent)

**Integration with Lutaml Ecosystem**
- Uses lutaml-model for serializable classes
- Consistent patterns with other Lutaml libraries
- Part of broader document/schema modeling toolkit

## Target Users

1. **Ruby Developers**: Working with XML validation and need RELAX NG schema processing
2. **Schema Authors**: Creating or maintaining RELAX NG schemas programmatically
3. **Document Processors**: Converting or transforming RELAX NG schemas
4. **Lutaml Users**: Integrating schema processing into modeling workflows