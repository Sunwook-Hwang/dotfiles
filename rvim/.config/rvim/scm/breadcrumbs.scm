;; 1:1 Steel port of: nvim/.config/nvim/lua/breadcrumbs.lua
;; Equivalence:
;; - Renders cached LSP symbol hierarchy in statusline with clickable `@v:steel.NopackContextJump@`.
;; - `<leader>Tb` toggles breadcrumbs and redraws statusline identically.

(require-builtin rvim/api)
(require-builtin rvim/steel)
(require "rvim/keymap")
(require "rvim/fn")
(require "rvim/cmd")
(require "rvim/notify")
(require "rvim/string")
(require "buffer_policy")
(require "breadcrumb_symbols")
(require "state")

(provide breadcrumbs-enabled? breadcrumbs-set-enabled! breadcrumbs-status)

(define (escape-stl-name s)
  (vector-ref (string/gsub (vector-ref (string/gsub s "[%c]" " ") 0) "%%" "%%%%") 0))

(define (breadcrumbs-enabled?)
  (breadcrumb-symbols-enabled?))

(define (breadcrumbs-status win)
  (define buf (nvim_win_get_buf win))
  (define syms (breadcrumb-symbols-get buf win (nvim_win_get_cursor win)))
  (apply string-append
         (map (lambda (sym)
                (define line (+ (hash-ref (hash-ref (hash-ref sym "selection") "start") "line") 1))
                (define name (escape-stl-name (hash-ref sym "name")))
                (string-append " > %" (number->string line) "@v:steel.NopackContextJump@" name "%X"))
              syms)))

(define (nopack-context-jump line _clicks button _mods)
  (when (equal? button "l")
    (define win (hash-ref (fn-call "getmousepos") "winid"))
    (when (and (is-editor? win) (allows? (nvim_win_get_buf win)))
      (nvim_set_current_win win)
      (cmd "normal! m'")
      (nvim_win_set_cursor win (vector (min line (nvim_buf_line_count 0)) 0))
      (cmd "normal! zvzz"))))

(state-set! 'NopackContextJump nopack-context-jump)
(steel-export! 'NopackContextJump nopack-context-jump)

(define (breadcrumbs-set-enabled! val)
  (unless (equal? (breadcrumb-symbols-enabled?) val)
    (breadcrumb-symbols-set-enabled! val)
    (for-each breadcrumb-symbols-clear! (vector->list (nvim_list_bufs)))
    (when val
      (for-each
        (lambda (win)
          (when (is-editor? win)
            (breadcrumb-symbols-refresh! (nvim_win_get_buf win))))
        (vector->list (nvim_tabpage_list_wins 0))))
    (cmd "redrawstatus")))

(keymap-set
  "n"
  "<leader>Tb"
  (lambda ()
    (breadcrumbs-set-enabled! (not (breadcrumb-symbols-enabled?)))
    (notify (string-append "Statusline context: " (if (breadcrumb-symbols-enabled?) "on" "off"))))
  (hash "desc" "Toggle breadcrumbs"))
