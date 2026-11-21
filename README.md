# lisp-em

A Common Lisp client for Emacs's `server.el` local-socket protocol, extracted
from Autolith. Requires SBCL. Native transport uses AF_UNIX on Linux and macOS;
on unsupported hosts, evaluation signals `emacs-client-error` with reason
`:unavailable`. Protocol and quoting functions load on those hosts.

## Evaluation

```lisp
(asdf:load-system :lisp-em)
(lisp-em:evaluate #P"/run/user/1000/emacs/server" "(+ 20 22)")
;; => "42"
```

`evaluate` accepts a socket pathname or string, an Emacs Lisp form string,
and these keyword arguments:

- `:timeout`, default 10 seconds: SBCL's per-blocking-I/O timeout, not an
  overall deadline or a connection-establishment deadline.
- `:maximum-reply`, default 8388608: all received wire characters, including
  framing, ignored metadata and newlines. Exactly that many characters are
  accepted; the first excess character signals before it is retained.

Each evaluation opens and owns a fresh socket, then closes it on every exit.
The private frame reader borrows its stream and never closes it. Retained
reply storage is O(`maximum-reply`); an unterminated line cannot bypass the
limit. The result is Emacs's printed value, with protocol quoting removed,
print chunks joined and the final newline added by Emacs removed once.
Unknown metadata frames are ignored and count toward the limit.

Use `quote-argument` and `unquote-argument` for the protocol's ampersand
encoding. These are wire encoders, not Emacs Lisp string escaping functions.
Choose the server and authorize the code before calling `evaluate`.

## JSON values and string arguments

Call `evaluate-json` with a socket, an Emacs Lisp body and optional `:arguments`
list of strings. In the body, refer to the strings as `a0`, `a1`, and so on.
The strings are bound as UTF-8 data rather than inserted as Lisp source.

```lisp
(lisp-em:evaluate-json socket "(vector a0 (length a0))"
                       :arguments (list "λ"))
;; => #("λ" 1)
```

The body must return a value accepted by Emacs's `json-serialize`: a plist,
vector, string, number, `t`, `:false` or `:null`. The result is decoded with Argo:
objects become EQUAL hash tables, arrays vectors, true `t`, false the marker
from `argo:json-false`, and null `nil`. Accept or reject value shapes in the
caller. `:timeout` and `:maximum-reply` have the same meaning as in `evaluate`.
Unreadable printed strings, base64, UTF-8 and JSON signal `emacs-client-error`
with reason `:protocol`; inspect its cause for the decoding failure.

## Failures

Catch `emacs-client-error`. Read `emacs-client-error-reason`,
`emacs-client-error-message` and `emacs-client-error-cause`. Reasons are
`:unavailable`, `:timeout`, `:elisp-error` and `:protocol`. The cause is the
underlying condition where available. Failed cleanup does not replace the
request's result or primary failure.

## Checks

Install Quicklisp and Qlot, then run:

```sh
./script/bootstrap
./script/check
```

The check runs the library's tests and cheque. Development tools are listed in
`checks/qlfile` and installed in the user cache. For tests alone, load this
checkout's ASD and run `(asdf:test-system :lisp-em)` in an environment with
`trivial-gray-streams` and `sb-posix` available.

Tests cover wire encoding, EOF and chunk assembly, exact and aggregate limits,
a generated billion-character line stopped at limit + 1, borrowed-stream and
owned-socket cleanup transitions, native fake-server roundtrips/timeouts, and
UTF-8 JSON values and malformed replies. Argument binding is exercised in real
Emacs when an executable is available. Native socket cases are omitted on
unsupported hosts.

ISC licensed. Protocol implementation originally extracted from Autolith's
`src/emacs/server.lisp` at baseline `40270fc8`, with incremental reply limits
and standalone transport ownership tests added here.
