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

## Failures

Catch `emacs-client-error`. Read `emacs-client-error-reason`,
`emacs-client-error-message` and `emacs-client-error-cause`. Reasons are
`:unavailable`, `:timeout`, `:elisp-error` and `:protocol`. The cause is the
underlying condition where available. Failed cleanup does not replace the
request's result or primary failure.

## Checks

Install development dependencies with Qlot, then run:

```sh
qlot install
sbcl --noinform --no-userinit --no-sysinit --script check.lisp
```

The check runs the library's tests and cheque. Development dependencies are
listed in `qlfile`; none are part of the runtime ASDF system. For tests alone,
load this checkout's ASD and run `(asdf:test-system :lisp-em)` in an environment
with `trivial-gray-streams` and `sb-posix` available.

Tests cover wire encoding, EOF and chunk assembly, exact and aggregate limits,
a generated billion-character line stopped at limit + 1, borrowed-stream and
owned-socket cleanup transitions, and native fake-server roundtrips/timeouts.
The native socket cases are omitted on unsupported hosts.

ISC licensed. Protocol implementation originally extracted from Autolith's
`src/emacs/server.lisp` at baseline `40270fc8`, with incremental reply limits
and standalone transport ownership tests added here.
