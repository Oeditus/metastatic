;; Lambdas, let and comprehensions - M2.2 Extended Layer

(defun lambdas ()
  (list (lambda (x) x)
        (lambda (x y) (+ x y))))

(defun bindings ()
  (let ((x 1)
        (y 2))
    (+ x y)))

(defun comprehension ()
  (lc ((* x 2)) (gen x (list 1 2 3))))
