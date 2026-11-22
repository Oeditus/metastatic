#!/usr/bin/env node
/**
 * JavaScript/TypeScript AST Parser for Metastatic
 * 
 * Parses JS/TS source code using @babel/parser and outputs AST as JSON.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

function requirePkg(name) {
  try {
    return require(name);
  } catch (err) {
    const candidates = [
      process.env.NODE_PATH,
      path.join(os.homedir(), '.local', 'share', 'mise', 'installs', 'node', 'latest', 'lib', 'node_modules'),
      path.resolve(__dirname, 'node_modules')
    ].filter(Boolean);

    for (const entry of candidates) {
      for (const dir of entry.split(path.delimiter)) {
        if (!dir) continue;
        try {
          return require(path.join(dir, name));
        } catch (_) {}
      }
    }
    throw err;
  }
}

const parser = requirePkg('@babel/parser');

/**
 * Plugin sets.
 *
 * `typescript` and `flow` are mutually exclusive in Babel, and `typescript`
 * also makes `yield`/`await`/`<T>` reserved in ways plain JavaScript does not
 * expect. Parsing every JavaScript file with the TypeScript plugin therefore
 * rejected valid JS (e.g. `yield` used as an identifier in sloppy mode).
 *
 * The dialect is chosen by the caller (the Elixir adapter passes
 * `--dialect=typescript` for the TypeScript adapter); the default is plain
 * JavaScript with JSX.
 */
const JS_PLUGINS = [
  "jsx",
  "classProperties",
  "classPrivateProperties",
  "classPrivateMethods",
  "decorators-legacy",
  "asyncGenerators",
  "exportDefaultFrom",
  "topLevelAwait",
  "importMeta",
  "objectRestSpread",
  "optionalCatchBinding",
  "optionalChaining",
  "nullishCoalescingOperator",
  "numericSeparator",
  "logicalAssignment",
  "bigInt",
  "dynamicImport",
  "classStaticBlock",
  "importAssertions"
];

const TS_PLUGINS = [
  "typescript",
  "jsx",
  "classProperties",
  "classPrivateProperties",
  "classPrivateMethods",
  "decorators-legacy",
  "asyncGenerators",
  "exportDefaultFrom",
  "topLevelAwait",
  "importMeta",
  "classStaticBlock"
];

function pluginsFor(dialect) {
  return dialect === "typescript" ? TS_PLUGINS : JS_PLUGINS;
}

function parseOptions(dialect) {
  return {
    sourceType: "module",
    allowImportExportEverywhere: true,
    allowReturnOutsideFunction: true,
    allowSuperOutsideMethod: true,
    allowUndeclaredExports: true,
    allowAwaitOutsideFunction: true,
    attachments: false,
    errorRecovery: true,
    ranges: false,
    tokens: false,
    plugins: pluginsFor(dialect)
  };
}

// Bare expressions (`1 + 2`) are not programs, but every other adapter
// accepts them, so a failed program parse is retried as an expression and
// wrapped in a Program/ExpressionStatement so the shape stays uniform.
function parseExpressionAsProgram(source, dialect) {
  const expr = parser.parseExpression(source, parseOptions(dialect));

  return {
    type: "File",
    program: {
      type: "Program",
      sourceType: "module",
      interpreter: null,
      directives: [],
      body: [{ type: "ExpressionStatement", expression: expr }]
    }
  };
}

function parseSource(source, dialect) {
  try {
    let ast;

    try {
      ast = parser.parse(source, parseOptions(dialect));
    } catch (programErr) {
      try {
        ast = parseExpressionAsProgram(source, dialect);
      } catch (_) {
        throw programErr;
      }
    }

    // `errorRecovery` makes Babel return a partial tree instead of throwing,
    // but the recovered nodes are meaningless: `interface I { a: number }`
    // parses as JavaScript into three unrelated statements. A partial parse is
    // reported as a failure so the caller never abstracts garbage.
    if (Array.isArray(ast.errors) && ast.errors.length > 0) {
      const first = ast.errors[0];
      return {
        ok: false,
        error: {
          type: first.name || 'SyntaxError',
          msg: first.message,
          lineno: first.loc ? first.loc.line : null,
          col: first.loc ? first.loc.column : null
        }
      };
    }

    return {
      ok: true,
      ast: ast
    };
  } catch (err) {
    return {
      ok: false,
      error: {
        type: err.name || 'SyntaxError',
        msg: err.message,
        lineno: err.loc ? err.loc.line : null,
        col: err.loc ? err.loc.column : null
      }
    };
  }
}

// `--dialect=typescript` (or `--dialect=javascript`) selects the plugin set.
// Anything else is ignored so an older caller keeps working.
function dialectFromArgv(argv) {
  for (const arg of argv) {
    const match = /^--dialect=(.+)$/.exec(arg);
    if (match) return match[1] === 'typescript' ? 'typescript' : 'javascript';
  }
  return 'javascript';
}

function main() {
  const dialect = dialectFromArgv(process.argv.slice(2));
  const pathArg = process.argv.slice(2).find((arg) => !arg.startsWith('--'));

  let source = '';
  if (pathArg && fs.existsSync(pathArg)) {
    source = fs.readFileSync(pathArg, 'utf-8');
  } else {
    source = fs.readFileSync(0, 'utf-8');
  }

  const result = parseSource(source, dialect);
  process.stdout.write(JSON.stringify(result));
}

main();
