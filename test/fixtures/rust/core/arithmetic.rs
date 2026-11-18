// Arithmetic operations - M2.1 Core Layer
//
// Every expression here must abstract to the same MetaAST shape as its Python,
// Elixir, JavaScript and Ruby counterparts. Literals only, so no identifier
// scope ambiguity can affect the comparison.

fn arithmetic() {
    let a = 1 + 2;
    let b = 10 - 7;
    let c = 3 * 4;
    let d = 8 / 2;
    let e = 17 % 5;
    let f = -5;
    let g = !true;
    let h = (1 + 2) * 3;
    let i = 1 + 2 - 3;
}
