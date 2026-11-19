;; Conditionals and pattern matching - M2.1 / M2.2

(defun sign (x)
  (if (> x 0)
      'positive
      (if (< x 0) 'negative 'zero)))

(defun classify (x)
  (case x
    ((0) 'zero)
    ((n) (when (> n 0)) 'positive)
    ((_) 'negative)))
