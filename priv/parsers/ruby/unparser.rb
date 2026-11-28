#!/usr/bin/env ruby
# frozen_string_literal: true

$VERBOSE = nil

begin
  require 'bundler/setup'
rescue LoadError, StandardError
  # Fall back to global/mise Ruby gems when running outside a bundle context
end

require 'parser/current'
require 'unparser'
require 'json'

module Metastatic
  # Ruby AST unparser that converts JSON AST back to Ruby source code
  class RubyUnparser
    # Unparse JSON AST back to Ruby source code
    #
    # @param ast_json [String] JSON-serialized AST
    # @return [Hash] Result with source code or error
    def self.unparse(ast_json)
      data = JSON.parse(ast_json, symbolize_names: true)
      raw_ast = data.is_a?(Hash) && data.key?(:ast) ? data[:ast] : data
      ast = deserialize_node(raw_ast)
      source = Unparser.unparse(ast)
      
      {
        ok: true,
        source: source
      }
    rescue JSON::ParserError => e
      {
        ok: false,
        error: "JSON parse error: #{e.message}"
      }
    rescue StandardError => e
      {
        ok: false,
        error: "#{e.class}: #{e.message}"
      }
    end

    # Deserialize a JSON structure back to Parser::AST::Node
    #
    # @param data [Hash, nil, Object] Serialized node data
    # @return [Parser::AST::Node, nil, Object] Deserialized AST node
    def self.deserialize_node(data)
      return nil if data.nil?
      
      # Handle primitives (literals)
      return data unless data.is_a?(Hash)
      
      # If it doesn't have a type, it's likely metadata or a literal value
      return data unless data[:type]

      type = data[:type].to_sym
      children = data[:children].map { |child| deserialize_node(child) }

      # JSON has no symbol type, so every Ruby symbol arrives as a string.
      # Unparser distinguishes the two: `s(:sym, "foo")` renders as the
      # *string* `"foo"`, and a string in a name slot raises
      # `TypeError: wrong argument type String (expected Symbol)`.
      # Convert the name slots these node types actually use.
      children = symbolize_children(type, children)
      
      Parser::AST::Node.new(type, children)
    end

    # Node types whose children carry a Symbol name, and the index of that name.
    SYMBOL_CHILD_INDEX = {
      sym: 0,
      lvar: 0,
      ivar: 0,
      cvar: 0,
      gvar: 0,
      lvasgn: 0,
      ivasgn: 0,
      cvasgn: 0,
      gvasgn: 0,
      arg: 0,
      optarg: 0,
      kwarg: 0,
      kwoptarg: 0,
      restarg: 0,
      kwrestarg: 0,
      blockarg: 0,
      def: 0,
      defs: 1,
      send: 1,
      csend: 1,
      const: 1,
      class: 0,
      module: 0,
      alias: 0,
      undef: 0
    }.freeze

    # @param type [Symbol] AST node type
    # @param children [Array] deserialized children
    # @return [Array] children with the name slot converted to a Symbol
    def self.symbolize_children(type, children)
      index = SYMBOL_CHILD_INDEX[type]
      return children unless index

      if children.length > index && children[index].is_a?(String)
        children = children.dup
        children[index] = children[index].to_sym
      end

      children
    end
  end
end

# CLI interface: read JSON from file (if passed) or STDIN, write JSON envelope to STDOUT
if __FILE__ == $PROGRAM_NAME
  if ARGV[0] && File.exist?(ARGV[0])
    ast_json = File.read(ARGV[0])
  else
    ast_json = $stdin.read
  end
  result = Metastatic::RubyUnparser.unparse(ast_json)
  puts JSON.generate(result)
end
