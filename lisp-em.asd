(asdf:defsystem #:lisp-em
  :description "A bounded Common Lisp client for the Emacs server socket protocol"
  :author      "Lambda Symbolics OÜ"
  :license     "ISC"
  :version     "0.1.0"
  :depends-on  (#:uiop #:sb-bsd-sockets #:cl-base64 #:argo)
  :serial      t
  :components  ((:file "src/package")
                (:file "src/protocol")
                (:file "src/transport")
                (:file "src/json"))
  :in-order-to ((asdf:test-op (asdf:test-op #:lisp-em/tests))))

(asdf:defsystem #:lisp-em/tests
  :description "Protocol, resource ownership and local socket checks for lisp-em"
  :depends-on  (#:lisp-em #:trivial-gray-streams #:sb-posix)
  :serial      t
  :components  ((:file "tests/tests"))
  :perform     (asdf:test-op (operation component)
                 (declare (ignore operation component))
                 (uiop:symbol-call '#:lisp-em-tests '#:run-tests)))
