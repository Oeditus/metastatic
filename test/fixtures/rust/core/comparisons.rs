// Comparisons and boolean logic - M2.1 Core Layer

fn comparisons(a: i32, b: i32) -> bool {
    let eq = a == b;
    let ne = a != b;
    let gt = a > b;
    let ge = a >= b;
    let lt = a < b;
    let le = a <= b;
    eq && ne && gt && ge && lt && le
}

fn booleans(flag: bool) -> bool {
    let not_flag = !flag;
    let and_flag = flag && true;
    let or_flag = flag || false;
    not_flag && and_flag || or_flag
}
