# With statement
with open("file.txt") as f:
    content = f.read()

# Multiple context managers
with open("input.txt") as fin, open("output.txt") as fout:
    fout.write(fin.read())
