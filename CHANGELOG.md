# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- M2.2s Structural/Organizational Layer - New meta-model layer for cross-language structural constructs
  - `container` type for modules/classes/namespaces with visibility-aware member tracking
  - `function_def` type for function/method definitions with guards, visibility, and pattern parameters
  - `attribute_access` type for field/property access on objects
  - `augmented_assignment` type for compound assignment operators (+=, -=, etc.)
  - `property` type for property declarations with getters/setters
- Full support for M2.2s types across all analysis modules:
  - Duplication fingerprinting (Type I/II clone detection)
  - Cyclomatic complexity analysis
  - Cognitive complexity analysis
  - Nesting depth tracking
  - Halstead metrics (operators/operands)
  - Function metrics (statements, returns)
  - Lines of code (LoC) counting
- Comprehensive test coverage: 143 new tests for structural types (1,149 total tests passing)
- Helper functions: `container_name/1`, `function_name/1`, `function_visibility/1`, `has_state?/1`

### Documentation
- Added `STRUCTURAL_LAYER_RESEARCH.md` - Theory and cross-language analysis of structural constructs
- Added `STRUCTURAL_LAYER_DESIGN.md` - Implementation design decisions and rationale
- Updated `README.md` with M2.2s layer description
- Enhanced `@typedoc` for all structural types with M1 instances and examples

## [0.1.0] - 2026-01-21

MVP

## Notes

This project follows a rigorous theoretical foundation based on:
- OMG Meta Object Facility (MOF) Specification
- Eclipse Modeling Framework (EMF)
- Formal meta-modeling theory

See `THEORETICAL_FOUNDATIONS.md` for the complete formal treatment with proofs.
