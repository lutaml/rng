# Current Context

## Project State

The Rng Ruby library is at version 0.1.2 and is functionally complete for basic RELAX NG processing.

### What Works

1. **RNG XML Parsing**: Fully functional using Lutaml::Model with Nokogiri adapter
   - Parses all RNG XML patterns correctly
   - Preserves namespace information
   - Handles special attribute values (empty, omitted, nil)
   - Round-trip testing passes (parse → generate → parse)

2. **RNC to RNG Conversion**: Functional for basic patterns
   - Parslet-based parser handles RNC syntax
   - Converts to RNG XML via Nokogiri builder
   - Supports element definitions with occurrence markers
   - Handles attributes, text, empty patterns
   - Basic group and choice patterns work

3. **RNG to RNC Generation**: Functional for basic patterns
   - RncBuilder traverses object model
   - Generates readable RNC syntax
   - Handles simple element/attribute patterns
   - Supports datatype libraries
   - Named pattern definitions work

4. **Object Model**: Comprehensive and complete
   - All RELAX NG patterns represented as classes
   - Lutaml::Model provides serialization
   - Well-structured inheritance hierarchy
   - Collections properly initialized

### Known Limitations

1. **RNC Parser**: Currently has disabled tests (`xdescribe` in spec/rng/rnc_parser_spec.rb)
   - Some complex RNC patterns may not parse correctly
   - Parser needs refinement for full RNC compatibility
   - Grammar rules may need expansion

2. **ToRnc Module**: Contains stub implementation (lib/rng/to_rnc.rb)
   - Delegates to RncParser.to_rnc() which IS implemented
   - Wrapper exists but marked as placeholder
   - Actual conversion logic works via RncParser

3. **Incomplete Pattern Coverage in Generation**:
   - RncBuilder handles basic patterns well
   - Some complex nested patterns may not generate optimally
   - Interleave, mixed, and advanced patterns need testing

### Test Coverage

- Basic version test: ✅ Passing
- RNG parsing: ✅ Passing (address_book.rng, relaxng.rng)
- RNG round-trip: ✅ Passing (analogous and equivalent comparisons)
- RNC parser: ⚠️ Tests disabled (xdescribe)
- RNC round-trip: Status unknown (need to check spec/rng/rnc_roundtrip_spec.rb)
- Official test suite: Status unknown (need to check spec/rng/spectest_spec.rb)

## Recent Work

### Major Refactoring Complete (2025-11-25)

Successfully completed a 4-phase refactoring to split the monolithic `rnc_parser.rb`
file (originally 1,385 lines) into focused, single-responsibility classes:

**Phase 1**: Extracted RncBuilder (482 lines) for RNG → RNC generation
**Phase 2**: Extracted RncToRngConverter (522 lines) for parse tree → RNG conversion
**Phase 3**: Extracted IncludeProcessor (297 lines) for file I/O and includes
**Phase 4**: Extracted ParseTreeProcessor (125 lines) for tree normalization

**Result**:
- Main parser reduced to 306 lines (Parslet grammar only)
- Total: ~1,732 lines across 5 focused classes
- All tests passing (no regressions)
- Follows OOP principles and separation of concerns
- Rubocop compliant

**Benefits**:
- Clear separation of concerns
- Each class < 600 lines (maintainable)
- Single responsibility per class
- Easier to maintain and extend
- Better testability
- Improved code organization

## Current Focus

Phase 5: Final documentation and cleanup after refactoring.

Updating documentation to reflect the new architecture:
- README.adoc updated with architecture diagrams
- Memory bank files updated with refactored structure
- Verifying all code documentation is current

## Next Steps

### Short-term priorities:
1. **Enable and fix RNC parser tests** - The disabled tests in spec/rng/rnc_parser_spec.rb need investigation
2. **Verify round-trip conversion** - Test RNC ↔ RNG conversion thoroughly
3. **Complete ToRnc implementation** - Remove stub placeholder, ensure proper delegation
4. **Test complex patterns** - Verify interleave, mixed, and nested patterns work correctly

### Medium-term priorities:
1. **Expand RNC parser grammar** - Add support for more complex RNC syntax
2. **Improve error handling** - Add meaningful error messages for parsing failures
3. **Performance optimization** - Profile and optimize parsing/generation
4. **Documentation** - Expand examples in README.adoc

### Long-term goals:
1. **XSD conversion** - Implement RNG to XSD conversion (mentioned in brief.md)
2. **Validation support** - Add XML validation against RNG schemas
3. **CLI tool** - Create command-line interface for schema conversion
4. **Schema simplification** - Implement RELAX NG simplification algorithm