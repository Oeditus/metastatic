/*
 * Java AST bridge for Metastatic.
 *
 * Parses Java source into a JSON AST using the JDK's own tree API
 * (com.sun.source.tree) and unparses such an AST back to source.
 *
 * No third-party dependency: only a JDK 11+ is required. Run it through the
 * single-file source launcher:
 *
 *     java parser.java parse   /tmp/Source.java
 *     java parser.java unparse /tmp/ast.json
 *
 * Output is always a single JSON object on stdout:
 *
 *     {"ok": true,  "ast": {...}}      (parse)
 *     {"ok": true,  "source": "..."}   (unparse)
 *     {"ok": false, "error": {"type": "...", "msg": "...", "line": 12}}
 *
 * The AST shape is documented in Metastatic.Adapters.Java: every node is an
 * object with a "kind" field naming its Tree.Kind, a "pos" object with source
 * positions, and kind-specific fields. Nodes that have no MetaAST analogue are
 * still serialised faithfully so that FromMeta can round-trip them.
 */

import com.sun.source.tree.*;
import com.sun.source.util.JavacTask;
import com.sun.source.util.SourcePositions;
import com.sun.source.util.TreePath;
import com.sun.source.util.Trees;

import javax.lang.model.element.Modifier;
import javax.tools.Diagnostic;
import javax.tools.DiagnosticCollector;
import javax.tools.JavaCompiler;
import javax.tools.JavaFileObject;
import javax.tools.SimpleJavaFileObject;
import javax.tools.StandardJavaFileManager;
import javax.tools.ToolProvider;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class parser {

    /** Source text of the unit currently being serialised (for positions). */
    private static String currentSource = "";
    private static SourcePositions positions;

    public static void main(String[] argv) {
        if (argv.length < 2) {
            emit(error("ValueError", "usage: parser.java <parse|unparse> <file>", 0));
            return;
        }

        String mode = argv[0];
        Path input = Paths.get(argv[1]);

        try {
            String payload = new String(Files.readAllBytes(input), StandardCharsets.UTF_8);

            if ("parse".equals(mode)) {
                emit(parse(payload));
            } else if ("unparse".equals(mode)) {
                emit(unparse(payload));
            } else {
                emit(error("ValueError", "unknown mode: " + mode, 0));
            }
        } catch (IOException e) {
            emit(error("IOException", e.getMessage(), 0));
        } catch (RuntimeException e) {
            emit(error(e.getClass().getSimpleName(), String.valueOf(e.getMessage()), 0));
        }
    }

    // ----- Parse -----

    private static Map<String, Object> parse(String source) {
        JavaCompiler compiler = ToolProvider.getSystemJavaCompiler();

        if (compiler == null) {
            return error("EnvironmentError",
                    "no system Java compiler available (a JDK is required, not a JRE)", 0);
        }

        DiagnosticCollector<JavaFileObject> diagnostics = new DiagnosticCollector<>();
        StandardJavaFileManager fileManager =
                compiler.getStandardFileManager(diagnostics, Locale.ROOT, StandardCharsets.UTF_8);

        try {
            JavaFileObject unit = new StringSource("Source.java", source);
            JavacTask task = (JavacTask) compiler.getTask(
                    new PrintWriter(new StringWriter()), fileManager, diagnostics, null, null, List.of(unit));

            Iterable<? extends CompilationUnitTree> units = task.parse();
            Diagnostic<? extends JavaFileObject> parseError = firstError(diagnostics);
            if (parseError != null) {
                return error("SyntaxError", parseError.getMessage(Locale.ROOT),
                        (int) parseError.getLineNumber());
            }
            CompilationUnitTree tree = units.iterator().hasNext() ? units.iterator().next() : null;

            if (tree == null) {
                Diagnostic<? extends JavaFileObject> first = firstError(diagnostics);
                return first == null
                        ? error("SyntaxError", "no compilation unit produced", 0)
                        : error("SyntaxError", first.getMessage(Locale.ROOT), (int) first.getLineNumber());
            }

            currentSource = source;
            positions = Trees.instance(task).getSourcePositions();

            Map<String, Object> ok = new LinkedHashMap<>();
            ok.put("ok", true);
            ok.put("ast", serialize(tree, tree));
            return ok;
        } catch (IOException e) {
            return error("IOException", e.getMessage(), 0);
        } catch (RuntimeException e) {
            return error(e.getClass().getSimpleName(), String.valueOf(e.getMessage()), 0);
        } finally {
            try {
                fileManager.close();
            } catch (IOException ignored) {
                // nothing useful to do
            }
        }
    }

    private static Diagnostic<? extends JavaFileObject> firstError(
            DiagnosticCollector<JavaFileObject> diagnostics) {
        for (Diagnostic<? extends JavaFileObject> diagnostic : diagnostics.getDiagnostics()) {
            if (diagnostic.getKind() == Diagnostic.Kind.ERROR) {
                return diagnostic;
            }
        }
        return null;
    }

    /** In-memory source file so no temporary directory is needed. */
    private static final class StringSource extends SimpleJavaFileObject {
        private final String code;

        StringSource(String name, String code) {
            super(URI.create("string:///" + name), Kind.SOURCE);
            this.code = code;
        }

        @Override
        public CharSequence getCharContent(boolean ignoreEncodingErrors) {
            return code;
        }
    }

    // ----- Serialization (M1 -> JSON) -----

    @SuppressWarnings("deprecation")
    private static Map<String, Object> serialize(Tree node, CompilationUnitTree unit) {
        if (node == null) {
            return null;
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", node.getKind().name());

        if (node instanceof CompilationUnitTree) {
            CompilationUnitTree cu = (CompilationUnitTree) node;
            out.put("package", serialize(cu.getPackageName(), unit));
            out.put("imports", serializeAll(cu.getImports(), unit));
            out.put("types", serializeAll(cu.getTypeDecls(), unit));
        } else if (node instanceof ImportTree) {
            ImportTree imp = (ImportTree) node;
            out.put("qualified", serialize(imp.getQualifiedIdentifier(), unit));
            out.put("static", imp.isStatic());
        } else if (node instanceof ClassTree) {
            ClassTree cls = (ClassTree) node;
            out.put("name", cls.getSimpleName().toString());
            out.put("extends", serialize(cls.getExtendsClause(), unit));
            out.put("implements", serializeAll(cls.getImplementsClause(), unit));
            out.put("members", serializeAll(cls.getMembers(), unit));
            out.put("modifiers", modifierNames(cls.getModifiers()));
        } else if (node instanceof MethodTree) {
            MethodTree method = (MethodTree) node;
            out.put("name", method.getName().toString());
            out.put("returnType", serialize(method.getReturnType(), unit));
            out.put("params", serializeAll(method.getParameters(), unit));
            out.put("body", serialize(method.getBody(), unit));
            out.put("throws", serializeAll(method.getThrows(), unit));
            out.put("modifiers", modifierNames(method.getModifiers()));
        } else if (node instanceof VariableTree) {
            VariableTree var = (VariableTree) node;
            out.put("name", var.getName().toString());
            out.put("type", serialize(var.getType(), unit));
            out.put("init", serialize(var.getInitializer(), unit));
            out.put("modifiers", modifierNames(var.getModifiers()));
        } else if (node instanceof BlockTree) {
            out.put("statements", serializeAll(((BlockTree) node).getStatements(), unit));
        } else if (node instanceof ReturnTree) {
            out.put("expr", serialize(((ReturnTree) node).getExpression(), unit));
        } else if (node instanceof ExpressionStatementTree) {
            out.put("expr", serialize(((ExpressionStatementTree) node).getExpression(), unit));
        } else if (node instanceof BinaryTree) {
            BinaryTree bin = (BinaryTree) node;
            out.put("kind", "BINARY");
            out.put("op", bin.getKind().name());
            out.put("left", serialize(bin.getLeftOperand(), unit));
            out.put("right", serialize(bin.getRightOperand(), unit));
        } else if (node instanceof UnaryTree) {
            UnaryTree un = (UnaryTree) node;
            out.put("kind", "UNARY");
            out.put("op", un.getKind().name());
            out.put("expr", serialize(un.getExpression(), unit));
        } else if (node instanceof AssignmentTree) {
            AssignmentTree asg = (AssignmentTree) node;
            out.put("var", serialize(asg.getVariable(), unit));
            out.put("expr", serialize(asg.getExpression(), unit));
        } else if (node instanceof CompoundAssignmentTree) {
            CompoundAssignmentTree asg = (CompoundAssignmentTree) node;
            out.put("op", asg.getKind().name());
            out.put("var", serialize(asg.getVariable(), unit));
            out.put("expr", serialize(asg.getExpression(), unit));
        } else if (node instanceof MethodInvocationTree) {
            MethodInvocationTree call = (MethodInvocationTree) node;
            out.put("select", serialize(call.getMethodSelect(), unit));
            out.put("args", serializeAll(call.getArguments(), unit));
        } else if (node instanceof NewClassTree) {
            NewClassTree created = (NewClassTree) node;
            out.put("identifier", serialize(created.getIdentifier(), unit));
            out.put("args", serializeAll(created.getArguments(), unit));
            out.put("classBody", serialize(created.getClassBody(), unit));
        } else if (node instanceof MemberSelectTree) {
            MemberSelectTree select = (MemberSelectTree) node;
            out.put("expr", serialize(select.getExpression(), unit));
            out.put("name", select.getIdentifier().toString());
        } else if (node instanceof IdentifierTree) {
            out.put("name", ((IdentifierTree) node).getName().toString());
        } else if (node instanceof LiteralTree) {
            Object value = ((LiteralTree) node).getValue();
            out.put("value", value);
            out.put("literalKind", node.getKind().name());
        } else if (node instanceof IfTree) {
            IfTree iff = (IfTree) node;
            out.put("cond", serialize(iff.getCondition(), unit));
            out.put("then", serialize(iff.getThenStatement(), unit));
            out.put("else", serialize(iff.getElseStatement(), unit));
        } else if (node instanceof WhileLoopTree) {
            WhileLoopTree loop = (WhileLoopTree) node;
            out.put("cond", serialize(loop.getCondition(), unit));
            out.put("body", serialize(loop.getStatement(), unit));
        } else if (node instanceof DoWhileLoopTree) {
            DoWhileLoopTree loop = (DoWhileLoopTree) node;
            out.put("cond", serialize(loop.getCondition(), unit));
            out.put("body", serialize(loop.getStatement(), unit));
        } else if (node instanceof ForLoopTree) {
            ForLoopTree loop = (ForLoopTree) node;
            out.put("init", serializeAll(loop.getInitializer(), unit));
            out.put("cond", serialize(loop.getCondition(), unit));
            out.put("update", serializeAll(loop.getUpdate(), unit));
            out.put("body", serialize(loop.getStatement(), unit));
        } else if (node instanceof EnhancedForLoopTree) {
            EnhancedForLoopTree loop = (EnhancedForLoopTree) node;
            out.put("var", serialize(loop.getVariable(), unit));
            out.put("expr", serialize(loop.getExpression(), unit));
            out.put("body", serialize(loop.getStatement(), unit));
        } else if (node instanceof TryTree) {
            TryTree tri = (TryTree) node;
            out.put("block", serialize(tri.getBlock(), unit));
            out.put("catches", serializeAll(tri.getCatches(), unit));
            out.put("finally", serialize(tri.getFinallyBlock(), unit));
            out.put("resources", serializeAll(tri.getResources(), unit));
        } else if (node instanceof CatchTree) {
            CatchTree cat = (CatchTree) node;
            out.put("param", serialize(cat.getParameter(), unit));
            out.put("block", serialize(cat.getBlock(), unit));
        } else if (node instanceof ThrowTree) {
            out.put("expr", serialize(((ThrowTree) node).getExpression(), unit));
        } else if (node instanceof BreakTree) {
            String label = ((BreakTree) node).getLabel() == null
                    ? null : ((BreakTree) node).getLabel().toString();
            out.put("label", label);
        } else if (node instanceof ContinueTree) {
            String label = ((ContinueTree) node).getLabel() == null
                    ? null : ((ContinueTree) node).getLabel().toString();
            out.put("label", label);
        } else if (node instanceof ParenthesizedTree) {
            out.put("expr", serialize(((ParenthesizedTree) node).getExpression(), unit));
        } else if (node instanceof ArrayAccessTree) {
            ArrayAccessTree access = (ArrayAccessTree) node;
            out.put("expr", serialize(access.getExpression(), unit));
            out.put("index", serialize(access.getIndex(), unit));
        } else if (node instanceof NewArrayTree) {
            NewArrayTree arr = (NewArrayTree) node;
            out.put("type", serialize(arr.getType(), unit));
            out.put("initializers", serializeAll(arr.getInitializers(), unit));
            out.put("dimensions", serializeAll(arr.getDimensions(), unit));
        } else if (node instanceof ConditionalExpressionTree) {
            ConditionalExpressionTree cond = (ConditionalExpressionTree) node;
            out.put("cond", serialize(cond.getCondition(), unit));
            out.put("true", serialize(cond.getTrueExpression(), unit));
            out.put("false", serialize(cond.getFalseExpression(), unit));
        } else if (node instanceof TypeCastTree) {
            TypeCastTree cast = (TypeCastTree) node;
            out.put("type", serialize(cast.getType(), unit));
            out.put("expr", serialize(cast.getExpression(), unit));
        } else if (node instanceof InstanceOfTree) {
            InstanceOfTree inst = (InstanceOfTree) node;
            out.put("expr", serialize(inst.getExpression(), unit));
            out.put("type", serialize(inst.getType(), unit));
        } else if (node instanceof PrimitiveTypeTree) {
            out.put("name", ((PrimitiveTypeTree) node).getPrimitiveTypeKind().name());
        } else if (node instanceof ParameterizedTypeTree) {
            ParameterizedTypeTree param = (ParameterizedTypeTree) node;
            out.put("type", serialize(param.getType(), unit));
            out.put("typeArgs", serializeAll(param.getTypeArguments(), unit));
        } else if (node instanceof ArrayTypeTree) {
            out.put("elemType", serialize(((ArrayTypeTree) node).getType(), unit));
        } else if (node instanceof ModifiersTree) {
            out.put("flags", modifierNames((ModifiersTree) node));
        } else if (node instanceof AnnotationTree) {
            AnnotationTree ann = (AnnotationTree) node;
            out.put("annotationType", serialize(ann.getAnnotationType(), unit));
            out.put("args", serializeAll(ann.getArguments(), unit));
        } else if (node instanceof LambdaExpressionTree) {
            LambdaExpressionTree lambda = (LambdaExpressionTree) node;
            out.put("params", serializeAll(lambda.getParameters(), unit));
            out.put("body", serialize(lambda.getBody(), unit));
        } else if (node instanceof MemberReferenceTree) {
            MemberReferenceTree ref = (MemberReferenceTree) node;
            out.put("expr", serialize(ref.getQualifierExpression(), unit));
            out.put("name", ref.getName().toString());
        } else if (node instanceof SwitchTree) {
            SwitchTree sw = (SwitchTree) node;
            out.put("expr", serialize(sw.getExpression(), unit));
            out.put("cases", serializeAll(sw.getCases(), unit));
        } else if (node instanceof CaseTree) {
            CaseTree cs = (CaseTree) node;
            out.put("expr", serialize(cs.getExpression(), unit));
            out.put("statements", serializeAll(cs.getStatements(), unit));
        } else if (node instanceof EmptyStatementTree) {
            // no fields
        } else {
            // Unknown node: keep its kind only. FromMeta reifies it as an
            // opaque language_specific node rather than guessing.
        }

        out.put("pos", position(node, unit));
        return out;
    }

    private static List<Object> serializeAll(List<? extends Tree> nodes, CompilationUnitTree unit) {
        List<Object> out = new ArrayList<>();
        if (nodes == null) {
            return out;
        }
        for (Tree node : nodes) {
            if (node != null) {
                out.add(serialize(node, unit));
            }
        }
        return out;
    }

    private static List<String> modifierNames(ModifiersTree modifiers) {
        List<String> flags = new ArrayList<>();
        if (modifiers == null) {
            return flags;
        }
        for (Modifier modifier : modifiers.getFlags()) {
            flags.add(modifier.name().toLowerCase(Locale.ROOT));
        }
        return flags;
    }

    /**
     * Converts a character offset into a 1-based line/column pair. Doing the
     * conversion here keeps the Elixir side free of source-text bookkeeping.
     */
    private static Map<String, Object> lineCol(long offset) {
        Map<String, Object> out = new LinkedHashMap<>();
        int line = 1;
        int col = 1;

        long limit = Math.min(offset, currentSource.length());
        for (int i = 0; i < limit; i++) {
            if (currentSource.charAt(i) == '\n') {
                line++;
                col = 1;
            } else {
                col++;
            }
        }

        out.put("line", line);
        out.put("col", col);
        return out;
    }

    private static Map<String, Object> position(Tree node, CompilationUnitTree unit) {
        Map<String, Object> pos = new LinkedHashMap<>();
        pos.put("known", false);

        if (positions == null) {
            return pos;
        }

        try {
            long start = positions.getStartPosition(unit, node);
            long end = positions.getEndPosition(unit, node);

            if (start < 0 || end < 0) {
                return pos;
            }

            Map<String, Object> startPos = lineCol(start);
            Map<String, Object> endPos = lineCol(end);

            pos.put("known", true);
            pos.put("line", startPos.get("line"));
            pos.put("col", startPos.get("col"));
            pos.put("end_line", endPos.get("line"));
            pos.put("end_col", endPos.get("col"));
            return pos;
        } catch (RuntimeException e) {
            return pos;
        }
    }

    // ----- Unparse (JSON -> source) -----

    /**
     * The JDK can print a tree only while it is attached to a compilation
     * unit, and rebuilding one from JSON would mean re-implementing javac.
     * Metastatic therefore unparses through `FromMeta` -> `parse` -> this
     * pretty printer, which takes source text and normalises it.
     */
    private static Map<String, Object> unparse(String payload) {
        Map<String, Object> out = new LinkedHashMap<>();

        try {
            Object decoded = Json.parse(payload);

            if (!(decoded instanceof Map)) {
                return error("ValueError", "unparse expects a JSON object", 0);
            }

            @SuppressWarnings("unchecked")
            Map<String, Object> ast = (Map<String, Object>) decoded;

            Object sourceField = ast.get("source");

            if (sourceField instanceof String) {
                out.put("ok", true);
                out.put("source", prettyPrint((String) sourceField));
                return out;
            }

            return error("ValueError",
                    "unparse expects {\"source\": \"...\"} produced by FromMeta reification", 0);
        } catch (RuntimeException e) {
            return error(e.getClass().getSimpleName(), String.valueOf(e.getMessage()), 0);
        }
    }

    /**
     * Normalises whitespace: strips trailing spaces, collapses runs of blank
     * lines and ensures a single trailing newline. Formatting is not preserved
     * across a round trip, so this is the closest honest approximation.
     */
    private static String prettyPrint(String source) {
        String[] lines = source.split("\n", -1);
        StringBuilder sb = new StringBuilder();
        boolean previousBlank = true;

        for (String line : lines) {
            String trimmed = line.replaceAll("\\s+$", "");

            if (trimmed.isEmpty()) {
                if (!previousBlank) {
                    sb.append('\n');
                }
                previousBlank = true;
            } else {
                sb.append(trimmed).append('\n');
                previousBlank = false;
            }
        }

        return sb.toString();
    }

    // ----- Output helpers -----

    private static Map<String, Object> error(String type, String message, int line) {
        Map<String, Object> err = new LinkedHashMap<>();
        err.put("type", type);
        err.put("msg", message == null ? "" : message);
        if (line > 0) {
            err.put("line", line);
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("ok", false);
        out.put("error", err);
        return out;
    }

    private static void emit(Map<String, Object> payload) {
        System.out.println(Json.write(payload));
    }

    // ----- Minimal JSON reader/writer (keeps the bridge dependency-free) -----

    private static final class Json {

        static String write(Object value) {
            StringBuilder sb = new StringBuilder();
            writeValue(sb, value);
            return sb.toString();
        }

        private static void writeValue(StringBuilder sb, Object value) {
            if (value == null) {
                sb.append("null");
            } else if (value instanceof String) {
                writeString(sb, (String) value);
            } else if (value instanceof Boolean) {
                sb.append(value);
            } else if (value instanceof Number) {
                writeNumber(sb, (Number) value);
            } else if (value instanceof Map) {
                sb.append('{');
                boolean first = true;
                for (Map.Entry<?, ?> entry : ((Map<?, ?>) value).entrySet()) {
                    if (!first) {
                        sb.append(',');
                    }
                    first = false;
                    writeString(sb, String.valueOf(entry.getKey()));
                    sb.append(':');
                    writeValue(sb, entry.getValue());
                }
                sb.append('}');
            } else if (value instanceof Iterable) {
                sb.append('[');
                boolean first = true;
                for (Object item : (Iterable<?>) value) {
                    if (!first) {
                        sb.append(',');
                    }
                    first = false;
                    writeValue(sb, item);
                }
                sb.append(']');
            } else {
                writeString(sb, String.valueOf(value));
            }
        }

        private static void writeNumber(StringBuilder sb, Number number) {
            if (number instanceof Double || number instanceof Float) {
                double d = number.doubleValue();
                if (Double.isNaN(d) || Double.isInfinite(d)) {
                    sb.append("null");
                } else {
                    sb.append(d);
                }
            } else {
                sb.append(number);
            }
        }

        private static void writeString(StringBuilder sb, String text) {
            sb.append('"');
            for (int i = 0; i < text.length(); i++) {
                char c = text.charAt(i);
                switch (c) {
                    case '"':
                        sb.append("\\\"");
                        break;
                    case '\\':
                        sb.append("\\\\");
                        break;
                    case '\n':
                        sb.append("\\n");
                        break;
                    case '\r':
                        sb.append("\\r");
                        break;
                    case '\t':
                        sb.append("\\t");
                        break;
                    default:
                        if (c < 0x20) {
                            sb.append(String.format("\\u%04x", (int) c));
                        } else {
                            sb.append(c);
                        }
                }
            }
            sb.append('"');
        }

        static Object parse(String text) {
            Reader reader = new Reader(text);
            Object value = reader.readValue();
            reader.skipWhitespace();
            return value;
        }

        private static final class Reader {
            private final String text;
            private int index;

            Reader(String text) {
                this.text = text;
                this.index = 0;
            }

            Object readValue() {
                skipWhitespace();
                char c = peek();

                switch (c) {
                    case '{':
                        return readObject();
                    case '[':
                        return readArray();
                    case '"':
                        return readString();
                    case 't':
                        expect("true");
                        return Boolean.TRUE;
                    case 'f':
                        expect("false");
                        return Boolean.FALSE;
                    case 'n':
                        expect("null");
                        return null;
                    default:
                        return readNumber();
                }
            }

            private Map<String, Object> readObject() {
                Map<String, Object> map = new LinkedHashMap<>();
                index++; // '{'
                skipWhitespace();

                if (peek() == '}') {
                    index++;
                    return map;
                }

                while (true) {
                    skipWhitespace();
                    String key = readString();
                    skipWhitespace();
                    index++; // ':'
                    map.put(key, readValue());
                    skipWhitespace();

                    char c = peek();
                    index++;

                    if (c == '}') {
                        return map;
                    }
                }
            }

            private List<Object> readArray() {
                List<Object> list = new ArrayList<>();
                index++; // '['
                skipWhitespace();

                if (peek() == ']') {
                    index++;
                    return list;
                }

                while (true) {
                    list.add(readValue());
                    skipWhitespace();
                    char c = peek();
                    index++;

                    if (c == ']') {
                        return list;
                    }
                }
            }

            private String readString() {
                StringBuilder sb = new StringBuilder();
                index++; // opening quote

                while (true) {
                    char c = text.charAt(index++);

                    if (c == '"') {
                        return sb.toString();
                    }

                    if (c == '\\') {
                        char escaped = text.charAt(index++);
                        switch (escaped) {
                            case 'n':
                                sb.append('\n');
                                break;
                            case 'r':
                                sb.append('\r');
                                break;
                            case 't':
                                sb.append('\t');
                                break;
                            case 'b':
                                sb.append('\b');
                                break;
                            case 'f':
                                sb.append('\f');
                                break;
                            case 'u':
                                sb.append((char) Integer.parseInt(text.substring(index, index + 4), 16));
                                index += 4;
                                break;
                            default:
                                sb.append(escaped);
                        }
                    } else {
                        sb.append(c);
                    }
                }
            }

            private Number readNumber() {
                int start = index;

                while (index < text.length() && "-+.eE0123456789".indexOf(text.charAt(index)) >= 0) {
                    index++;
                }

                String literal = text.substring(start, index);

                if (literal.contains(".") || literal.contains("e") || literal.contains("E")) {
                    return Double.parseDouble(literal);
                }

                return Long.parseLong(literal);
            }

            private void expect(String literal) {
                if (!text.startsWith(literal, index)) {
                    throw new IllegalArgumentException("invalid JSON at offset " + index);
                }
                index += literal.length();
            }

            private char peek() {
                if (index >= text.length()) {
                    throw new IllegalArgumentException("unexpected end of JSON input");
                }
                return text.charAt(index);
            }

            private void skipWhitespace() {
                while (index < text.length() && Character.isWhitespace(text.charAt(index))) {
                    index++;
                }
            }
        }
    }
}
