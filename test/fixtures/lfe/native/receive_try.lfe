;; Constructs with no cross-language analogue - M2.3 Native Layer
;;
;; These are preserved verbatim as :language_specific nodes so that
;; FromMeta can restore them exactly.

(defun receiver ()
  (receive
    ((msg) (handle msg))
    (after 1000 'timeout)))

(defun guarded (x)
  (try
    (risky x)
    (catch
      ((error reason) (list 'error reason))
      (after (cleanup)))))
