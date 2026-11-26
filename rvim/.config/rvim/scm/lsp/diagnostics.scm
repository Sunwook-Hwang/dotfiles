;; 1:1 Steel port of: nvim/.config/nvim/lua/lsp/diagnostics.lua
;; Equivalence:
;; - Drops stale versioned `textDocument/publishDiagnostics` reports older than `buf_versions`.
;; - Tracks hidden-buffer pull-diagnostic catch-up on 0.12 and backports workspace
;;   diagnostic refresh to open document-pull buffers.

(require-builtin rvim/api)
(require "rvim/fn")
(require "rvim/lsp")
(require "buffer_policy")
(require "state")

(provide lsp-diagnostic-handlers)

(define *pending* (box (hash)))
(define *has-refresh* (lsp-diagnostic-has-refresh?))

(when *has-refresh*
  (define group (nvim_create_augroup "flash-lsp-diagnostics" (hash "clear" #t)))
  (nvim_create_autocmd
    "LspNotify"
    (hash "group" group
          "callback"
          (lambda (args)
            (define buf (hash-ref args "buf"))
            (define data (hash-ref args "data"))
            (when (and (equal? (hash-ref data "method") "textDocument/didChange") (allows? buf))
              (define client (lsp-get-client-by-id (hash-ref data "client_id")))
              (when (and client
                         ((hash-ref client "supports_method") client "textDocument/diagnostic" buf)
                         (null? (fn-call "win_findbuf" buf)))
                (define cur (or (hash-try-get (unbox *pending*) buf) (hash)))
                (set-box! *pending*
                          (hash-insert (unbox *pending*) buf (hash-insert cur (hash-ref client "id") #t))))))))
  (nvim_create_autocmd
    "BufWinEnter"
    (hash "group" group
          "callback"
          (lambda (args)
            (define buf (hash-ref args "buf"))
            (define clients (hash-try-get (unbox *pending*) buf))
            (set-box! *pending* (hash-remove (unbox *pending*) buf))
            (when (and clients (allows? buf))
              (for-each
                (lambda (id)
                  (define client (lsp-get-client-by-id id))
                  (when (and client
                             (not ((hash-ref client "is_stopped") client))
                             (hash-try-get (hash-ref client "attached_buffers") buf))
                    (lsp-diagnostic-refresh! buf id)))
                (hash-keys->list clients))))))
  (nvim_create_autocmd
    '("BufUnload" "BufWipeout" "LspDetach")
    (hash "group" group
          "callback"
          (lambda (args)
            (define buf (hash-ref args "buf"))
            (if (not (equal? (hash-ref args "event") "LspDetach"))
                (set-box! *pending* (hash-remove (unbox *pending*) buf))
                (let ([cur (hash-try-get (unbox *pending*) buf)])
                  (when cur
                    (set-box! *pending*
                              (hash-insert (unbox *pending*) buf
                                           (hash-remove cur (hash-ref (hash-ref args "data") "client_id")))))))))))

(define (on-diagnostic err result ctx)
  (lsp-diagnostic-on-diagnostic err result ctx)
  (when result
    (define buf (hash-ref ctx "bufnr"))
    (define cur (hash-try-get (unbox *pending*) buf))
    (when cur
      (set-box! *pending* (hash-insert (unbox *pending*) buf (hash-remove cur (hash-ref ctx "client_id")))))))

(define (on-publish-diagnostics err result ctx)
  (define ver (and result (hash-try-get result "version")))
  (define stale?
    (and ver
         (let* ([buf (fn-call "bufnr" (lsp-uri-to-fname (hash-ref result "uri")))]
                [cur-ver (lsp-buf-version buf)])
           (and cur-ver (< ver cur-ver)))))
  (unless stale?
    (lsp-diagnostic-on-publish err result ctx)))

(define lsp-diagnostic-handlers
  (let ([base (hash "textDocument/diagnostic" on-diagnostic
                    "textDocument/publishDiagnostics" on-publish-diagnostics)])
    (if *has-refresh*
        (hash-insert
          base
          "workspace/diagnostic/refresh"
          (lambda (err result ctx)
            (define resp (lsp-diagnostic-on-refresh err result ctx))
            (define client (lsp-get-client-by-id (hash-ref ctx "client_id")))
            (when (and (not err) client
                       (not ((hash-ref client "is_stopped") client))
                       ((hash-ref client "supports_method") client "workspace/diagnostic"))
              (for-each
                (lambda (buf)
                  (when (and (allows? buf)
                             ((hash-ref client "supports_method") client "textDocument/diagnostic" buf))
                    (lsp-diagnostic-refresh! buf (hash-ref client "id"))))
                (hash-keys->list (hash-ref client "attached_buffers"))))
            resp))
        base)))
