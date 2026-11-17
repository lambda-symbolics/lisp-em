;;;; -- Development Checks --

(require :asdf)

(let* ((root  (uiop:pathname-directory-pathname *load-truename*))
       (setup (merge-pathnames ".qlot/setup.lisp" root)))
  (when (probe-file setup)
    (load setup))
  (asdf:load-asd (merge-pathnames "lisp-em.asd" root))
  (asdf:test-system :lisp-em)
  (asdf:load-system :cheque)
  (let ((findings
          (uiop:symbol-call '#:cheque '#:source-check-run
                            (uiop:symbol-call '#:cheque '#:project-read root)
                            :paths '("lisp-em.asd" "check.lisp" "src/package.lisp"
                                     "src/protocol.lisp" "src/transport.lisp"
                                     "tests/tests.lisp" "README.md")
                            :parinfer-library
                            (uiop:symbol-call '#:cheque '#:source-parinfer-library-ensure))))
    (uiop:symbol-call '#:cheque '#:source-check-report findings *standard-output*)
    (when findings
      (uiop:quit 1))))
