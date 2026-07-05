# Cure: Syntax Approach

A first-principles syntax design for a BEAM-targeting language whose semantic
backbone is MetaAST. Every MetaAST node type maps to a natural surface
construct. Cure's differentiators -- dependent types, first-class FSMs, and
BEAM process integration -- are preserved and given clean syntax.

## 1. Design Principles

**Expression-oriented.** Every construct produces a value. There are no
statements, only expressions. The last expression in a block is its value.

**Indentation-structured.** Block nesting follows visual layout. No closing
delimiters (`end`, `}`) are required; indentation alone determines scope.
This eliminates an entire class of syntactic noise while keeping the grammar
unambiguous.

**Uniform function syntax.** A single keyword `fn` introduces both named
and anonymous functions. The presence or absence of a name is the only
difference.

**Exported by default.** All definitions are public unless marked
`local`. This matches BEAM's module-as-unit-of-encapsulation model
and reduces annotation noise.

**Minimal keywords.** Under 40 reserved words. No synonyms
(`match` exists; `case`/`switch`/`cond` do not).

**MetaAST-native.** Every M2.1 Core, M2.2 Extended, and M2.2s Structural
node has exactly one syntactic representation. The syntax IS the MetaAST,
made human-readable.

## 2. Indentation Rules

Blocks are opened by certain syntactic positions: after `=` in a function
definition, after the scrutinee in `match`, after `if`/`elif`/`else`,
after comprehension heads, etc.

1. The indentation level of a block is set by its first line.
2. Subsequent lines at the same level continue the block.
3. A line at a lesser level closes all blocks above it.
4. A line at a greater level is a continuation of the previous expression.
5. Blank lines do not affect indentation.
6. Spaces only (2 or 4); tabs are a lexer error.

For compactness, `match` and `if` also have inline forms using `{` `}` and
`then`/`else` keywords respectively (see Sections 8 and 9).

## 3. Lexical Elements

### 3.1 Comments

```cure
# single-line comment
```

No block comments. Prefix each line with `#`.

### 3.2 Identifiers

- Values and functions: `snake_case`
- Types, modules, constructors: `PascalCase`
- Unused bindings: `_` prefix (`_unused`, plain `_` for wildcard)
- Module attributes/decorators: `@name`

### 3.3 Keywords

```
mod fn let type rec proto impl fsm local use as
match if elif else then for do
in try catch finally throw return yield
spawn send receive after
when where and or not
true false nil
extern
```

### 3.4 Operators

```
Arithmetic     +  -  *  /  %
Comparison     ==  !=  <  >  <=  >=
Boolean        and  or  not
Bitwise        band  bor  bnot  bxor  bsl  bsr
String         <>
Range          ..  ..=
Pipe           |>
Cons           |  (inside [ ])
Access         .
Assignment     =  +=  -=  *=  /=
Type arrow     ->
Type annotate  :
Sum separator  |  (in type definitions)
```

## 4. Literals

MetaAST node: **literal**

```cure
42                 # integer
0xFF               # integer (hex)
0b1010             # integer (binary)
3.14               # float
1.0e-3             # float (scientific)
"hello"            # string
true               # boolean
false              # boolean
nil                # null
:ok                # symbol (atom)
:error             # symbol (atom)
~r/[a-z]+/i        # regex
'c'                # char
<<0xFF, 0x00>>     # bytes (binary)
```

## 5. Collections

### 5.1 List -- MetaAST: list

```cure
[]                 # empty
[1, 2, 3]          # literal list
[head | tail]      # cons (pattern and expression)
```

### 5.2 Tuple -- MetaAST: tuple

```cure
%[]                # unit (empty tuple)
%[1, 2]            # 2-tuple
%[a, b, c]         # 3-tuple
%[x]               # 1-tuple (unambiguous thanks to sigil)
```

Tuples always use the `%[...]` sigil. Parentheses `(expr)` are
purely for grouping and never produce tuples.

### 5.3 Map -- MetaAST: map + pair

```cure
%{}                           # empty map
%{name: "Alice", age: 30}    # atom keys (shorthand)
%{:name => "Alice"}           # atom keys (explicit)
%{"key" => value}             # string keys
%{k => v}                     # variable keys
```

Maps always use the `%{...}` sigil. The `key: value` shorthand
desugars to `:key => value`. Bare `{...}` (without `%`) is reserved
for record construction, record update, refinement types, and
inline match blocks.

### 5.4 Record construction

```cure
Person{name: "Alice", age: 30}
person with {age: 31}          # functional update
```

### 5.5 Range -- MetaAST: range

```cure
1..10              # exclusive upper bound (1 to 9)
1..=10             # inclusive (1 to 10)
0..n               # variable bound
```

## 6. Type System

### 6.1 Primitive types

```
Int  Float  String  Bool  Atom  Binary  Unit  Pid  Ref
```

### 6.2 Composite types

```cure
List(T)            # linked list
Map(K, V)          # key-value map
Set(T)             # unordered set
%[A, B]            # 2-tuple
%[A, B, C]         # 3-tuple
```

### 6.3 Function types

```cure
Int -> String                  # unary
(Int, Int) -> Bool             # binary
(List(T), T -> Bool) -> List(T)  # higher-order
```

### 6.4 ADTs (sum types) -- MetaAST: container[enum]

```cure
type Option(T) = Some(T) | None
type Result(T, E) = Ok(T) | Error(E)
type Color = Red | Green | Blue
type Tree(T) = Leaf(T) | Branch(Tree(T), Tree(T))
```

### 6.5 Records -- MetaAST: container[struct]

```cure
rec Person
  name: String
  age: Int
  email: String
```

Record types are referenced by name. Fields are accessed with `.`:
`person.name`. Type parameters are supported: `rec Pair(A, B)`.

### 6.6 Refinement types

```cure
type Nat = {x: Int | x >= 0}
type Pos = {x: Int | x > 0}
type Percentage = {p: Float | 0.0 <= p and p <= 1.0}
type NonEmpty(T) = {xs: List(T) | length(xs) > 0}
```

Constraints inside `{ | }` are verified at compile time via SMT.

### 6.7 Dependent types

Return types and preconditions that depend on values:

```cure
fn safe_head(v: Vector(T, n)) -> T when n > 0
fn replicate(n: Nat, x: T) -> Vector(T, n)
fn safe_divide(a: Int, b: {x: Int | x != 0}) -> Int
```

`when` clauses express preconditions checked by the type system.

### 6.8 Type constraints

```cure
fn sort(xs: List(T)) -> List(T) where Ord(T)
fn debug(x: T) -> Unit where Show(T)
fn transform(f: A -> B, c: F(A)) -> F(B) where Functor(F)
```

`where` clauses require protocol membership. Multiple constraints are
comma-separated: `where Show(T), Ord(T)`.

### 6.9 Type aliases

```cure
type Name = String
type Pair(A, B) = %[A, B]
type Handler(T) = T -> Result(Unit, Error)
```

## 7. Variables, Assignment, Access

### 7.1 Variables -- MetaAST: variable

```cure
x
name
_ignored        # unused (no warning)
_               # wildcard (cannot be referenced)
```

### 7.2 Let bindings -- MetaAST: assignment

```cure
let x = 42
let x: Int = 42            # with type annotation
let name = "Alice"
```

### 7.3 Rebinding

```cure
x = x + 1                  # shadows previous binding
```

On the BEAM this compiles to a new variable, not mutation.

### 7.4 Augmented assignment -- MetaAST: augmented_assignment

```cure
x += 1                     # sugar for x = x + 1
count -= delta
total *= factor
```

### 7.5 Destructuring -- MetaAST: inline_match

```cure
let %[a, b] = split(data)
let [head | rest] = items
let Ok(value) = parse(input)        # will raise on Error
let Person{name: n, age: a} = user
```

### 7.6 Attribute access -- MetaAST: attribute_access

```cure
person.name
config.timeout
module.function
```

There is no safe-navigation operator. Nil access is a runtime
error. Use explicit `match` or `Option` wrapping instead.

### 7.7 String interpolation -- MetaAST: string_interpolation

```cure
"Hello, #{name}! You are #{age} years old."
"Result: #{compute(x) + 1}"
```

## 8. Functions

### 8.1 Named functions -- MetaAST: function_def + param

```cure
# single-expression body (exported by default)
fn add(x: Int, y: Int) -> Int = x + y

# multi-line body (last expression is return value)
fn process(data: List(Int)) -> Int =
  let filtered = filter(data, fn(x) -> x > 0)
  let total = fold(filtered, 0, fn(acc, x) -> acc + x)
  total

# private (not exported)
local fn validate(name: String) -> Bool = length(name) > 0
```

### 8.2 Multi-clause functions with guards

Clauses share a signature. Each clause starts with `|` and
pattern-matches the parameters:

```cure
fn factorial(n: Nat) -> Nat
  | 0 -> 1
  | n -> n * factorial(n - 1)

fn fibonacci(n: Nat) -> Nat
  | 0 -> 0
  | 1 -> 1
  | n -> fibonacci(n - 1) + fibonacci(n - 2)

fn classify(x: Int) -> String
  | x when x > 0  -> "positive"
  | x when x < 0  -> "negative"
  | _              -> "zero"
```

A simpler two-clause form keeps separate `fn` heads (matches current
Cure style and MetaAST `function_def` with `clauses:` metadata):

```cure
fn abs(x: Int) -> Int when x >= 0 = x
fn abs(x: Int) -> Int = -x
```

### 8.3 Default parameters

```cure
fn greet(name: String, greeting: String = "Hello") -> String =
  "#{greeting}, #{name}!"
```

MetaAST `param` node with `default:` metadata.

### 8.4 Variadic and keyword parameters

```cure
fn log(msg: String, *tags: String) -> Unit = ...       # variadic
fn connect(host: String, **opts: Any) -> Conn = ...     # keyword variadic
```

Maps to MetaAST `param` with `kind: :variadic` / `kind: :keyword_variadic`.

### 8.5 Lambdas -- MetaAST: lambda

```cure
fn(x) -> x * 2
fn(x, y) -> x + y
fn() -> 42

# multi-line
fn(item) ->
  let processed = transform(item)
  validate(processed)
```

Lambdas are first-class values; parameter types are inferred from context.

### 8.6 Pipe -- MetaAST: pipe

```cure
data
  |> transform
  |> filter(fn(x) -> x > 0)
  |> fold(0, fn(acc, x) -> acc + x)
```

`a |> f` desugars to `f(a)`. With extra arguments: `a |> f(b)` becomes
`f(a, b)` (first-argument insertion).

## 9. Pattern Matching

### 9.1 Match expression -- MetaAST: pattern_match + match_arm

```cure
match result
  Ok(value)  -> handle(value)
  Error(msg) -> report(msg)

match list
  []       -> "empty"
  [h | _]  -> "head: #{h}"

match point
  %[0, 0]  -> "origin"
  %[x, 0]  -> "on x-axis"
  %[0, y]  -> "on y-axis"
  %[x, y]  -> "(#{x}, #{y})"
```

### 9.2 Inline match

```cure
let r = match x { 0 -> "zero", _ -> "other" }
```

Braces `{` `}` and commas allow single-line matching.

### 9.3 Pattern types

```cure
42                  # literal
x                   # variable binding
_                   # wildcard
%[a, b]             # tuple
[h | t]             # list cons
[a, b, c]           # exact list
Ok(value)           # constructor
Person{name: n}     # record (partial field match)
%{key: v}           # map
x when x > 0        # guarded pattern
```

### 9.4 Guards in match arms

```cure
match n
  x when x > 100 -> "large"
  x when x > 10  -> "medium"
  _               -> "small"
```

Guards may use: comparison operators, `and`, `or`, `not`,
arithmetic, and calls to pure guard-safe functions.

### 9.5 If-let for refutable patterns

```cure
if let Some(x) = lookup(key)
  use(x)
else
  handle_missing()
```

## 10. Control Flow

### 10.1 Conditional -- MetaAST: conditional

```cure
# inline (ternary)
if x > 0 then x else -x

# multi-line
if score > 90
  "excellent"
elif score > 70
  "good"
else
  "average"
```

Every `if` is an expression and produces a value.

### 10.2 Early return -- MetaAST: early_return

```cure
return value
```

Optional in expression-oriented code; the last expression in a
block is implicitly the return value. Useful for early exits inside
guards or validation logic.

### 10.3 Throw -- MetaAST: throw

```cure
throw Error("something went wrong")
```

### 10.4 Block -- MetaAST: block

A sequence of expressions at the same indentation level. The value
of a block is its last expression:

```cure
fn example() -> Int =
  let a = compute()       # first expression
  let b = transform(a)    # second expression
  a + b                   # block value
```

## 11. Iteration

Cure has no imperative loop keywords. All iteration is expressed
through:

1. **Comprehensions** (Section 12) for transforming and filtering
   collections declaratively.
2. **Recursion** for general iteration. The BEAM optimizes tail
   calls, so recursive loops compile to constant-stack iterations.
3. **Folds and higher-order functions** (`fold`, `map`, `filter`,
   `each`, etc.) from the standard library.

MetaAST `loop` nodes (while, for_each, do_while, infinite) exist
for cross-language analysis of imperative code (Python, Ruby, etc.)
but have no surface syntax in Cure. When Metastatic analyzes Cure
source, iteration constructs produce `comprehension`, `collection_op`,
or `function_call` (recursive) MetaAST nodes instead.

Example -- processing a queue with recursion:

```cure
fn drain(q: Queue(T)) -> Unit =
  if queue_empty(q) then %[]
  else
    let %[item, rest] = dequeue(q)
    process(item)
    drain(rest)
```

## 12. Comprehensions

### 12.1 List comprehension -- MetaAST: comprehension + generator + filter

```cure
[x * 2 for x <- list]
[x * 2 for x <- list, x > 0]
[%[k, v] for k <- keys, v <- values, k != "skip"]
```

Grammar: `[ body for pattern <- collection, ...guards ]`

Generators (`pattern <- collection`) map to MetaAST `generator` nodes.
Guard expressions map to MetaAST `filter` nodes.

### 12.2 Map comprehension

```cure
%{k: v * 2 for k, v <- original_map}
```

### 12.3 Yield -- MetaAST: yield

```cure
fn fibonacci() -> Stream(Int) =
  local fn step(a: Int, b: Int) -> Stream(Int) =
    yield a
    step(b, a + b)
  step(0, 1)
```

`yield expr` produces a value into a lazy stream. The recursive
call after yield resumes when the next value is pulled. Compiles
to a BEAM process: each generator is a spawned process that sends
values on demand. The consumer pulls via message passing.

## 13. Collection Operations -- MetaAST: collection_op

Higher-order collection operations are plain function calls, but
the compiler recognizes them for optimization:

```cure
list |> map(fn(x) -> x * 2)       # collection_op[map]
list |> filter(fn(x) -> x > 0)    # collection_op[filter]
list |> fold(0, fn(a, x) -> a + x) # collection_op[reduce]
```

No special syntax; the MetaAST `collection_op` node is
distinguished at the semantic level.

## 14. Module System

### 14.1 Module -- MetaAST: container[module]

```cure
mod MyApp.Users
  fn create(name: String) -> User = ...         # exported
  fn find(id: Int) -> Option(User) = ...        # exported
  local fn validate(name: String) -> Bool = ...  # private
```

Everything is exported by default. Mark definitions with `local`
to keep them module-private.

### 14.2 Imports -- MetaAST: import

```cure
use Std.List                     # import all public items
use Std.List.{map, filter, fold} # import specific items
use Std.Io as IO                 # aliased import
use Std.{Result, Option}         # multiple from parent
```

The `use` keyword unifies all dependency-loading. The MetaAST
`import_type` metadata is set by the compiler based on context.

### 14.3 Module attributes -- MetaAST: property

```cure
mod Config
  @version "2.0.0"
  @author "Cure Team"
  @behaviour GenServer
```

`@name value` at module scope defines a compile-time property.

### 14.4 Decorators -- MetaAST: decorator

```cure
@deprecated("Use new_fn/1 instead")
fn old_fn(x: Int) -> Int = x

@doc("Computes the factorial of n")
fn factorial(n: Nat) -> Nat = ...

@inline
local fn helper(x: Int) -> Int = x + 1
```

`@name` or `@name(args)` before a definition attaches metadata.

### 14.5 Foreign function interface

```cure
@extern(:io, :format, 2)
fn print_raw(format: String, args: List(Any)) -> Unit

@extern(:erlang, :spawn, 1)
fn spawn_raw(func: fn() -> Any) -> Pid

@extern(:maps, :get, 2)
fn map_get(key: Any, map: Map(K, V)) -> V
```

`@extern(module, function, arity)` binds a Cure function signature
to an Erlang MFA. Replaces Cure 1's `curify` keyword.

## 15. Protocols and Implementations

### 15.1 Protocol definition -- MetaAST: container[protocol]

```cure
proto Show(T)
  fn show(x: T) -> String

proto Ord(T)
  fn compare(a: T, b: T) -> Ordering

proto Functor(F)
  fn fmap(f: A -> B, fa: F(A)) -> F(B)
```

### 15.2 Protocol implementation -- MetaAST: impl as container[trait]

```cure
impl Show for Int
  fn show(x: Int) -> String = int_to_string(x)

impl Show for Person
  fn show(p: Person) -> String =
    "Person(#{p.name}, #{p.age})"

impl Ord for Int
  fn compare(a: Int, b: Int) -> Ordering =
    if a < b then Lt
    elif a > b then Gt
    else Eq
```

### 15.3 Constrained implementations

```cure
impl Show for List(T) where Show(T)
  fn show(xs: List(T)) -> String =
    let inner = join(map(xs, fn(x) -> show(x)), ", ")
    "[#{inner}]"
```

### 15.4 Behaviours -- MetaAST: container[interface]

```cure
proto GenServer(State, Msg)
  fn init(args: Any) -> %[Atom, State]
  fn handle_call(msg: Msg, from: Pid, state: State) -> %[Atom, Any, State]
  fn handle_cast(msg: Msg, state: State) -> %[Atom, State]
```

Behaviours are protocols with OTP semantics. The compiler generates
the necessary BEAM callbacks.

## 16. Error Handling

### 16.1 Try-catch-finally -- MetaAST: exception_handling

```cure
try
  risky_operation()
catch
  e: IOError    -> handle_io(e)
  e: ParseError -> handle_parse(e)
  _             -> handle_unknown()
finally
  cleanup()
```

`try` is an expression; its value is the value of the try-block or
the matching catch arm. `finally` always runs but does not affect
the return value.

### 16.2 Result-based error handling (idiomatic)

```cure
fn safe_divide(a: Int, b: Int) -> Result(Int, String) =
  if b == 0 then Error("division by zero")
  else Ok(a / b)

let result = safe_divide(10, x)
  |> map_ok(fn(v) -> v * 2)
  |> and_then(fn(v) -> safe_sqrt(v))

match result
  Ok(v)    -> println("Success: #{v}")
  Error(e) -> println("Error: #{e}")
```

## 17. Concurrency

### 17.1 Spawn -- MetaAST: async_operation[async]

```cure
let pid = spawn fn() -> worker_loop()
```

### 17.2 Send

```cure
send pid, %[:message, data]
```

### 17.3 Receive -- MetaAST: async_operation[await]

```cure
receive
  %[:response, value] -> use(value)
  %[:error, reason]   -> handle(reason)
after 5000
  timeout_handler()
```

`receive` is an expression. `after` specifies a timeout in
milliseconds.

### 17.4 Process monitoring

```cure
let ref = monitor(pid)
receive
  %[:DOWN, ^ref, :process, _pid, reason] -> handle_down(reason)
```

## 18. Finite State Machines

Cure's signature feature. FSMs are first-class constructs verified at
compile time via SMT solver (Z3 or CVC5). The compiler automatically
proves reachability, deadlock freedom, guard exhaustiveness, and
user-declared invariants.

### 18.1 FSM definition

```cure
rec TrafficPayload
  cycles: Int
  emergencies: Int

fsm TrafficLight with TrafficPayload{cycles: 0, emergencies: 0}
  Red    --timer-->     Green
  Green  --timer-->     Yellow
  Yellow --timer-->     Red
  *      --emergency--> Red
```

- First state listed (`Red`) is the initial state.
- `*` is a wildcard: the transition applies from any state.
- Transitions: `Source --event--> Target`.
- The payload record tracks data across transitions.

### 18.2 Guarded transitions

Guards on transitions constrain when a transition may fire.
The compiler encodes guards as SMT assertions and verifies
exhaustiveness (no event is silently dropped).

```cure
fsm Counter with CounterPayload{value: 0}
  Counting --increment when value < 100-->  Counting
  Counting --increment when value >= 100--> Saturated
  Saturated --reset--> Counting
```

For the `increment` event in state `Counting`, the two guards
`value < 100` and `value >= 100` are checked for:
- **Exhaustiveness**: their disjunction is a tautology (no gap).
- **Non-overlap** (optional warning): their conjunction is unsat.

### 18.3 Terminal states and invariants

```cure
fsm Connection with ConnPayload{retries: 0, buffer_size: 0}
  @terminal Closed
  @terminal Failed

  @invariant retries >= 0 and retries <= 5
  @invariant buffer_size >= 0

  Idle       --connect-->                   Connecting
  Connecting --ack-->                       Connected
  Connecting --timeout when retries < 5-->  Connecting
  Connecting --timeout when retries >= 5--> Failed
  Connected  --data-->                      Connected
  Connected  --disconnect-->                Closing
  Closing    --ack-->                       Closed
  *          --fatal_error-->               Failed
```

### 18.4 Transition actions (payload updates)

Transitions can update payload fields. These updates participate
in invariant proofs:

```cure
fsm Counter with CounterPayload{value: 0, overflows: 0}
  @invariant value >= 0

  Counting --increment when value < 100
    do value = value + 1
    --> Counting
  Counting --increment when value >= 100
    do value = 0, overflows = overflows + 1
    --> Saturated
  Saturated --reset
    do value = 0
    --> Counting
```

The `do field = expr, ...` clause specifies payload updates per
transition. The SMT encoding includes these when verifying invariants.

### 18.5 SMT verification

**Automatic checks** (no annotation needed -- compiler always runs these):

- **Reachability**: every declared state is reachable from the
  initial state. Unreachable states are a compile error.
- **Deadlock freedom**: every non-`@terminal` state has at least
  one outgoing transition. A silent sink is a compile error.
- **Guard exhaustiveness**: for each (state, event) pair with
  guarded transitions, the disjunction of all guards is a tautology
  over the payload type. A gap is a compile error.
- **Guard satisfiability**: each individual guard is satisfiable
  (not `false`). Dead guards produce a warning.

**User-declared properties** (checked via SMT):

```cure
fsm Lift with LiftPayload{floor: 0, moving: false}
  @terminal OutOfService

  @invariant floor >= 0 and floor <= 20
  @verify reachable(OutOfService)
  @verify safe(floor <= 20)       # holds in all reachable states

  Idle   --call(target) when target != floor--> Moving
  Idle   --call(target) when target == floor--> Idle
  Moving --arrived-->                           Idle
  *      --shutdown-->                          OutOfService
```

- `@invariant expr` -- must hold for the payload in every reachable
  state. The solver checks that every transition preserves it:
  `inv(pre) and guard(pre) => inv(post(pre))`.
- `@verify reachable(State)` -- the given state is reachable from
  the initial state (existential reachability).
- `@verify safe(expr)` -- the expression holds in all reachable
  states (safety property, proved via full inductive invariant:
  base case on initial state + inductive step over all transitions).

### 18.6 SMT encoding summary

The FSM compiles to an SMT theory as follows:
- **States**: finite enum sort `S = {S1, S2, ...}`
- **Events**: finite enum sort `E = {E1, E2, ...}`
- **Payload**: product of SMT sorts matching the record fields
- **Transition relation**: `T(s, e, guard, action, s')` as
  quantifier-free first-order formulas
- **Reachability**: transitive closure of `T` from initial state
- **Invariant preservation**:
  `forall s, e: inv(payload) and guard(payload) => inv(action(payload))`
- **Deadlock freedom**:
  `forall s not in Terminal: exists e, s': T(s, e, true, _, s')`
- **Guard exhaustiveness per (s, e)**:
  `guard_1(p) or guard_2(p) or ... or guard_n(p)` is valid

### 18.7 FSM runtime operations

```cure
use Std.Fsm.{fsm_spawn, fsm_cast, fsm_state, fsm_advertise}

let pid = fsm_spawn(:TrafficLight, TrafficPayload{cycles: 0, emergencies: 0})
fsm_advertise(pid, :traffic)
fsm_cast(:traffic, %[:timer, []])
let state = fsm_state(:traffic)    # => :Green
```

## 19. Type Annotations

### 19.1 Standalone annotation -- MetaAST: type_annotation

```cure
let x: Int = compute()
let config: Map(String, Int) = load_config()
```

Type annotations on `let` bindings are optional; the compiler infers
types. Annotations serve as documentation and checked assertions.

## 20. MetaAST Coverage Matrix

Below, every MetaAST node type and its Cure surface syntax.

### M2.1 Core Layer

```
literal              -> 42, 3.14, "s", true, nil, :atom, ~r//, 'c', <<>>
variable             -> x, name, _
list                 -> [1, 2, 3], [h | t]
map                  -> %{k: v}, %{k => v}
pair                 -> k: v (inside map/record), %[a, b] (as 2-tuple)
tuple                -> %[], %[a, b], %[a, b, c]
binary_op            -> x + y, a == b, p and q, a band b, 1..10, s <> t
unary_op             -> -x, not p, bnot x
function_call        -> f(x), M.f(x), x.method(y)
conditional          -> if c then a else b / if...elif...else multi-line
early_return         -> return expr
throw                -> throw expr
block                -> indented expression sequence
assignment           -> let x = expr / x = expr (rebind)
inline_match         -> let Ok(v) = expr / if let Some(x) = expr
range                -> 1..10, 1..=10
string_interpolation -> "hello #{name}"
```

### M2.2 Extended Layer

```
loop[*]              -> no surface syntax (MetaAST-only, cross-language)
                        Cure iteration uses comprehensions, recursion, fold
lambda               -> fn(x) -> expr / fn(x, y) -> expr
collection_op        -> list |> map(f) / filter(f) / fold(init, f)
pattern_match        -> match expr <arms>
match_arm            -> pattern -> expr / pattern when guard -> expr
exception_handling   -> try <block> catch <arms> finally <block>
async_operation      -> spawn fn() -> expr / receive <arms> after ms <block>
yield                -> yield expr
comprehension        -> [expr for pat <- gen, guard]
generator            -> pat <- collection (inside comprehension)
filter               -> guard expression (inside comprehension)
pipe                 -> expr |> f |> g
```

### M2.2s Structural Layer

```
container[module]    -> mod Name <body>
container[struct]    -> rec Name <fields>
container[protocol]  -> proto Name(T) <signatures>
container[interface] -> proto Name(S, M) <callbacks>  (behaviour)
container[enum]      -> type Name = A | B | C
function_def         -> fn name(...) / local fn name(...) for private
param                -> name: Type / name: Type = default / *rest / **kw
attribute_access     -> obj.field
augmented_assignment -> x += 1, x -= 1
property             -> @name value (module attribute)
import               -> use Path.{items}
type_annotation      -> let x: Type = expr
decorator            -> @name / @name(args) before definition
```

### Not directly in surface syntax

```
container[class]     -> not included (use mod + proto for BEAM idioms)
container[namespace] -> mod serves this role
container[trait]     -> impl blocks serve this role
language_specific    -> escape hatch via @extern / @native annotations
```

## 21. Complete Example

```cure
mod MyApp.Math
  use Std.{Result, Option}
  use Std.List.{map, fold}
  use Std.Io.{println}

  @doc("Sum type for classification")
  type Sign = Positive | Negative | Zero

  rec Stats
    mean: Float
    count: Int
    sum: Int

  # exported (default)
  fn add(x: Int, y: Int) -> Int = x + y

  # multi-clause with pattern matching
  fn factorial(n: Nat) -> Nat
    | 0 -> 1
    | n -> n * factorial(n - 1)

  # guards
  fn classify(x: Int) -> Sign
    | x when x > 0 -> Positive
    | x when x < 0 -> Negative
    | _             -> Zero

  # dependent type: non-empty list guarantee
  fn safe_head(xs: NonEmpty(T)) -> T =
    let [h | _] = xs
    h

  # private helper
  local fn sum_positive(data: List(Int)) -> Int =
    [x for x <- data, x > 0]
      |> fold(0, fn(a, x) -> a + x)

  # comprehension + pipe
  fn process(data: List(Int)) -> Stats =
    let positive = [x for x <- data, x > 0]
    let total = sum_positive(data)
    let n = length(positive)
    Stats{mean: total / n, count: n, sum: total}

  # error handling
  fn safe_divide(a: Int, b: Int) -> Result(Int, String) =
    if b == 0 then Error("division by zero")
    else Ok(a / b)

  # lambda and higher-order
  fn double_all(xs: List(Int)) -> List(Int) =
    map(xs, fn(x) -> x * 2)

  fn main() -> Unit =
    let data = [1, -2, 3, -4, 5]
    let stats = process(data)
    println("Sum: #{stats.sum}, Count: #{stats.count}")
    let result = safe_divide(stats.sum, stats.count)
    match result
      Ok(v)    -> println("Mean: #{v}")
      Error(e) -> println("Error: #{e}")
```

## 22. Resolved Design Decisions

The following questions were considered during design and are now
settled:

1. **Blocks**: Indentation-structured. No `do...end` delimiters.
2. **Tuples**: `%[a, b]` sigil syntax. Parentheses are purely
   for grouping. 1-tuples (`%[x]`) are unambiguous.
3. **Maps**: `%{k: v}` and `%{k => v}` sigil syntax. Bare `{}`
   is reserved for records, refinement types, and inline match.
4. **FSM transition actions**: `do field = expr` with indented
   multiline bodies. Part of the transition block.
5. **Yield**: Process-based generators. Each generator spawns a
   BEAM process; values are pulled via message passing.
6. **Multi-clause functions**: Both forms coexist. Grouped form
   (`| pattern -> body` under a shared signature) and separate
   `fn` heads (`fn name(...) when guard = ...`) are both valid.
7. **Safe navigation**: Not supported. Nil access is a runtime
   error. Use explicit `match` or `Option` types.
8. **FSM verification**: Full inductive proof strategy for
   `@verify safe(...)` properties. Base case on the initial
   state, inductive step over all transitions.
