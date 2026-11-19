;; Function calls and Erlang interop - M2.1 Core Layer

(defun calls ()
  (list (erlang:abs -5)
        (io_lib:format "~p" (list 1 2))
        (lists:map (lambda (x) (* x 2)) (list 1 2 3))))

(defun nested ()
  (+ (* 1 2) (- 3 4)))
