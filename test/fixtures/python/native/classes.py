# Simple class
class MyClass:
    def __init__(self, value):
        self.value = value
    
    def method(self):
        return self.value * 2

# Class with inheritance
class Child(Parent):
    pass

# Class with multiple bases
class Multi(Base1, Base2):
    attribute = 42
