(defpackage #:lisp-em
  (:documentation "A bounded client for the Emacs local-socket protocol.")
  (:use #:cl)
  (:export #:evaluate
           #:evaluate-json
           #:quote-argument
           #:unquote-argument
           #:emacs-client-error
           #:emacs-client-error-reason
           #:emacs-client-error-message
           #:emacs-client-error-cause))
