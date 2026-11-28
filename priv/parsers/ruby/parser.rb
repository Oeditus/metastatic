#!/usr/bin/env ruby
# frozen_string_literal: true

$VERBOSE = nil

begin
  require 'bundler/setup'
rescue LoadError, StandardError
  # Fall back to global/mise Ruby gems when running outside a bundle context
end

require 'parser/current'
require 'json'

module Metastatic
  # Ruby AST parser that converts Ruby source code to JSON-serializable format
  class RubyParser
    # Parse Ruby source code and return JSON-serializable AST
    #
    # @param source [String] Ruby source code
    # @return [Hash] Serialized AST or error information
    def self.parse(source)
      buffer = Parser::Source::Buffer.new('(string)', source: source)
      parser = Parser::CurrentRuby.new
      ast = parser.parse(buffer)

      if ast.nil?
        {
          ok: false,
          error: 'Parse error: syntax error'
        }
      else
        {
          ok: true,
          ast: serialize_node(ast)
        }
      end
    rescue Parser::SyntaxError => e
      {
        ok: false,
        error: {
          type: 'SyntaxError',
          msg: e.message,
          line: e.diagnostic.location.line,
          column: e.diagnostic.location.column
        }
      }
    rescue StandardError => e
      {
        ok: false,
        error: {
          type: e.class.to_s,
          msg: e.message
        }
      }
    end

    # Serialize a Parser::AST::Node to a JSON-friendly structure
    #
    # @param node [Parser::AST::Node, nil] AST node to serialize
    # @return [Hash, nil] Serialized node structure
    def self.serialize_node(node)
      return nil if node.nil?

      # Handle non-node values (literals)
      unless node.is_a?(Parser::AST::Node)
        return node
      end

      {
        type: node.type.to_s,
        children: node.children.map { |child| serialize_node(child) },
        location: serialize_location(node.location)
      }
    end

    # Serialize location information
    #
    # @param loc [Parser::Source::Map] Location map
    # @return [Hash] Serialized location info
    def self.serialize_location(loc)
      return nil unless loc && loc.expression

      expr = loc.expression
      {
        begin_pos: expr.begin_pos,
        end_pos: expr.end_pos,
        begin_line: expr.line,
        begin_column: expr.column,
        end_line: expr.last_line,
        end_column: expr.last_column
      }
    rescue StandardError
      nil
    end
  end
end

# CLI interface: read from file (if passed) or STDIN, write JSON to STDOUT
if __FILE__ == $PROGRAM_NAME
  if ARGV[0] && File.exist?(ARGV[0])
    source = File.read(ARGV[0])
  else
    source = $stdin.read
  end
  result = Metastatic::RubyParser.parse(source)
  puts JSON.generate(result)
end
