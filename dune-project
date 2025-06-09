(lang dune 3.17)

(name scheduler)

(generate_opam_files true)

(source
 (github username/reponame))

(authors "Author Name <author@example.com>")

(maintainers "Maintainer Name <maintainer@example.com>")

(license LICENSE)

(documentation https://url/to/documentation)

(package
 (name scheduler)
 (synopsis "Sophisticated email scheduling system with state-based exclusion rules")
 (description "An OCaml-based email scheduling system that manages automated email and SMS campaigns with complex date calculations, state-specific exclusion windows, and support for processing millions of contacts efficiently")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.0))
  (sqlite3 (>= 5.0.0))
  (caqti (>= 2.0.0))
  caqti-driver-sqlite3
  caqti-lwt
  (lwt (>= 5.6.0))
  ptime
  timedesc
  yojson
  logs
  alcotest
  bisect_ppx
  ctypes
  ppxlib
  ocamlgraph
  re
  fmt
  cmdliner)
 (tags
  (email scheduling "business rules" campaigns visualization)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
