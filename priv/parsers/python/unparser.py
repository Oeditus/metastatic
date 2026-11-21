#!/usr/bin/env python3
"""
Python AST Unparser for Metastatic

Converts AST JSON back to Python source code.
Uses ast.unparse() for Python 3.9+, with fallback for older versions.
"""

import ast
import base64
import json
import sys
from typing import Any, Dict


# Tags written by `parser.py` for values that JSON cannot represent.
_BYTES_TAG = '__bytes__'
_REPR_TAG = '__python_repr__'

# Fields that carry position information. `ast.unparse` walks `_fields` only,
# so these are dropped when rebuilding; but they are also *required* by
# `ast.fix_missing_locations` when the tree is compiled, which is why every
# node gets a position below.
_POSITION_FIELDS = ['lineno', 'col_offset', 'end_lineno', 'end_col_offset']


def _decode_repr(text: str) -> Any:
    """Turn a `repr()` string back into the Python value it describes."""
    if text == 'Ellipsis':
        return Ellipsis
    if text.endswith('j') and '+j' not in text:
        try:
            return complex(text)
        except ValueError:
            return text
    return text


def dict_to_ast(data: Any) -> Any:
    """
    Convert JSON dictionary back to Python AST node.
    
    Args:
        data: Dictionary representation of AST or primitive value
        
    Returns:
        AST node or primitive value
    """
    if isinstance(data, dict) and '_type' in data:
        node_type = data['_type']
        
        # Get the AST node class
        node_class = getattr(ast, node_type, None)
        if node_class is None:
            raise ValueError(f"Unknown AST node type: {node_type}")
        
        # Prepare fields
        fields = {}
        for key, value in data.items():
            if key.startswith('_') or key in _POSITION_FIELDS:
                continue
            
            if isinstance(value, list):
                fields[key] = [dict_to_ast(item) for item in value]
            else:
                fields[key] = dict_to_ast(value)
        
        # Create the node
        return node_class(**fields)
    elif isinstance(data, dict) and _BYTES_TAG in data:
        return base64.b64decode(data[_BYTES_TAG])
    elif isinstance(data, dict) and _REPR_TAG in data:
        return _decode_repr(data[_REPR_TAG])
    elif isinstance(data, list):
        return [dict_to_ast(item) for item in data]
    else:
        # Primitive value
        return data


def _assign_positions(tree: Any) -> None:
    """
    Give every node a position.

    `ast.unparse` is position-independent, but `ast.fix_missing_locations`
    (and therefore `compile`) is not: it raises
    `'Assign' object has no attribute 'lineno'` for any node built without
    one. Nodes rebuilt from MetaAST lose their positions because they are
    not part of `_fields`, so the whole tree is stamped with a synthetic
    position here.
    """
    for node in ast.walk(tree):
        for field in _POSITION_FIELDS:
            if not hasattr(node, field):
                setattr(node, field, 1 if 'lineno' in field else 0)


def unparse_ast(ast_dict: Dict[str, Any]) -> str:
    """
    Convert AST dictionary to Python source code.
    
    Args:
        ast_dict: Dictionary representation of Python AST
        
    Returns:
        Python source code as string
    """
    try:
        # Convert dict back to AST
        tree = dict_to_ast(ast_dict)
        _assign_positions(tree)
        
        # Use ast.unparse if available (Python 3.9+)
        if hasattr(ast, 'unparse'):
            source = ast.unparse(tree)
        else:
            # Fallback for older Python - use astor or basic repr
            try:
                import astor
                source = astor.to_source(tree)
            except ImportError:
                # Last resort - compile and decompile (lossy)
                source = compile(tree, '<string>', 'exec').__repr__()
        
        return source
    except Exception as e:
        raise ValueError(f"Failed to unparse AST: {e}")


def main():
    """Main entry point - read AST JSON from stdin or file, output source to stdout."""
    import os
    if len(sys.argv) > 1 and os.path.exists(sys.argv[1]):
        with open(sys.argv[1], 'r', encoding='utf-8') as f:
            data = json.load(f)
    else:
        data = json.loads(sys.stdin.read())
    
    if not isinstance(data, dict) or '_type' not in data:
        print(json.dumps({
            'ok': False,
            'error': {
                'type': 'ValueError',
                'msg': 'Invalid AST format'
            }
        }))
        return
    
    try:
        source = unparse_ast(data)
        print(json.dumps({
            'ok': True,
            'source': source
        }))
    except Exception as e:
        print(json.dumps({
            'ok': False,
            'error': {
                'type': type(e).__name__,
                'msg': str(e)
            }
        }))


if __name__ == '__main__':
    main()
