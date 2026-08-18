class Calculator {
  constructor(initial) {
    this.value = initial;
  }
  add(amount) {
    this.value += amount;
    return this.value;
  }
}
