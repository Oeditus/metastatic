import Config

# Configuration for Metastatic
# Configures the tree-sitter executable used by NL-MetaAST
config :metastatic,
  tree_sitter_bin: System.get_env("TREE_SITTER_BIN") || "tree-sitter"
