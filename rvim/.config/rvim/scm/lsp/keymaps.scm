;; 1:1 Steel port of: nvim/.config/nvim/lua/lsp/keymaps.lua
;; Equivalence:
;; - Buffer-local LSP keymaps installed on `on_attach`: `gr`, `gD`, `K`, `<leader>lr`,
;;   `<leader>la` (normal+visual), plus picker-backed `gR`, `gi`, `gt` via `location-picker`.
;; - Clears `bo.tagfunc` so native tag commands continue reading ctags; detaches if
;;   buffer policy disallows the buffer.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/lsp")
(require "rvim/schedule")
(require "buffer_policy")
(require "state")

(provide lsp-on-attach)

(define (lsp-on-attach client buf)
  (if (not (allows? buf))
      (schedule
        (lambda ()
          (when (lsp-buf-is-attached? buf (hash-ref client "id"))
            (lsp-buf-detach-client! buf (hash-ref client "id")))))
      (begin
        (bo-set buf "tagfunc" "")
        (for-each
          (lambda (pair)
            (define key (car pair))
            (define method (cdr pair))
            (keymap-set
              "n" key
              (guard-buffer
                (lambda ()
                  (define win (nvim_get_current_win))
                  (define ctx (source-context buf))
                  (define opts
                    (hash "on_list"
                          (lambda (lst)
                            (when (and (allows? buf)
                                       (source-unchanged? ctx)
                                       (= (nvim_get_current_win) win)
                                       (= (nvim_get_current_buf) buf))
                              (state-call 'location-picker method (hash-ref lst "items"))))))
                  (if (equal? method "references")
                      (lsp-buf-references #f opts)
                      (lsp-buf-call method opts))))
              (hash "buf" buf "desc" (string-append "Select LSP " method))))
          '(("gR" . "references") ("gi" . "implementation") ("gt" . "type_definition")))
        (for-each
          (lambda (pair)
            (keymap-set
              "n" (car pair)
              (guard-buffer (lambda () (lsp-buf-call (cdr pair))))
              (hash "buf" buf "desc" (string-append "LSP: " (cdr pair)))))
          '(("gr" . "references") ("gD" . "declaration") ("K" . "hover") ("<leader>lr" . "rename")))
        (keymap-set
          '("n" "x") "<leader>la"
          (guard-buffer (lambda () (lsp-buf-call "code_action")))
          (hash "buf" buf "desc" "Code action")))))
