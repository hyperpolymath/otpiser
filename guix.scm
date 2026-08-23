;; SPDX-License-Identifier: MPL-2.0
;; Guix development environment.
;; Usage: guix shell -D -f guix.scm

(use-modules (guix packages)
             (guix build-system gnu)
             (guix licenses)
             (gnu packages base)
             (gnu packages bash)
)

(package
  (name "otpiser")
  (version "0.1.0")
  (source #f)
  (build-system gnu-build-system)
  (inputs (list coreutils bash ))
  (synopsis "otpiser")
  (description "otpiser — part of the hyperpolymath ecosystem.")
  (home-page "https://github.com/hyperpolymath/otpiser")
  (license ((@@ (guix licenses) license) "MPL-2.0" "https://github.com/hyperpolymath/palimpsest-license")))
