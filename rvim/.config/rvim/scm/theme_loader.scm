;; 1:1 Steel port of: nvim/.config/nvim/lua/theme_loader.lua
;; Equivalence:
;; - Loads static JSON highlight snapshots from `<config_root>/themes/data/<variant>.json`
;;   via the Rust bulk loader `rvim/theme` (`apply-theme-json-file`) instead of executing
;;   55k lines of Lua data files or per-group Steel VM round-trips.
;; - Applies `g:colors_name = nil`, `background`, `highlight clear`, `syntax reset`,
;;   all `nvim_set_hl` groups, `terminal_color_0..15`, and `g:colors_name` in exact order.

(require "rvim/fs")
(require-builtin rvim/uv)
(require "rvim/theme")
(require "state")

(provide apply-theme flash-config-root)

(define (flash-config-root)
  (define config-dir (fn-call "stdpath" "config"))
  (define init-path (or (env-get "RVIM_INIT_FILE") (fs-joinpath config-dir "init.scm")))
  (define resolved (uv-fs-realpath init-path))
  (if (string? resolved) (fs-dirname resolved) config-dir))

(define (theme-data-dir)
  (string-append (or (state-get 'config-root) (flash-config-root)) "/themes/data/"))

(define (apply-theme variants)
  (define bg (opt-get "background"))
  (define variant-name (or (hash-try-get variants bg)
                           (hash-try-get variants "dark")))
  (define path (string-append (theme-data-dir) variant-name ".json"))
  (apply-theme-json-file 0 path))
