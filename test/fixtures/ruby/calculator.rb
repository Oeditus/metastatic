class Calculator
  attr_reader :value

  def initialize(initial = 0)
    @value = initial
  end

  def add(x)
    @value += x
    self
  end

  def multiply(x)
    @value *= x
    self
  end

  def result
    @value
  end
end
