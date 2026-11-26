;; 1:1 Steel port of: nvim/.config/nvim/lua/theme_loader.lua
;; Equivalence:
;; - Loads static JSON highlight snapshots from `<config_root>/themes/data/<variant>.json`
;;   instead of executing 55k lines of Lua data files (`steel-design.md` §9(e)).
;; - Applies `background`, `highlight clear`, `syntax reset`, all `nvim_set_hl` groups,
;;   `terminal_color_0..15`, and `g:colors_name` in the exact same order.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/cmd")
(require "rvim/fs")
(require "rvim/json")
(require "state")

(provide apply-theme)

(define (theme-data-dir)
  (string-append (or (state-get 'config-root) "") "/themes/data/"))

(define (apply-theme variants)
  (define bg (opt-get "background"))
  (define variant-name (or (hash-try-get variants bg)
                           (hash-try-get variants "dark")))
  (define path (string-append (theme-data-dir) variant-name ".json"))
  (define snapshot (json-decode (fs-read-file path)))
  ;; Changing background must not reload the previously selected colorscheme.
  (g-set "colors_name" #f)
  (opt-set "background" (hash-ref snapshot "background"))
  (cmd "highlight clear")
  (when (g-get "syntax_on")
    (cmd "syntax reset"))
  (define highlights (hash-ref snapshot "highlights"))
  (for-each
    (lambda (name)
      (nvim_set_hl 0 name (hash-ref highlights name)))
    (hash-keys->list highlights))
  (define terminal (hash-ref snapshot "terminal"))
  (for-each
    (lambda (i)
      (define key (number->string i))
      (define val (hash-try-get terminal key))
      (when val
        (g-set (string-append "terminal_color_" key) val)))
    (range 0 16))
  (g-set "colors_name" (hash-ref snapshot "name")))
