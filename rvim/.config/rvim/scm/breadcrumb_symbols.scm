;; 1:1 Steel port of: nvim/.config/nvim/lua/breadcrumb_symbols.lua
;; Equivalence:
;; - Caches normalized LSP document symbols per buffer keyed by `(client, changedtick)`.
;; - Uses binary search + `prefix_end` pruning for O(log N) cursor hierarchy lookup.
;; - Delegates LSP `documentSymbol` requests via the shared document-symbol hooks.

(require-builtin rvim/api)
(require-builtin rvim/breadcrumbs as draw.)
(require "rvim/fn")
(require "rvim/cmd")
(require "rvim/schedule")
(require "document_symbols")
(require "buffer_policy")
(require "state")

(provide breadcrumb-symbols-enabled?
         breadcrumb-symbols-set-enabled!
         breadcrumb-symbols-clear!
         breadcrumb-symbols-refresh!
         breadcrumb-symbols-render)

(define *enabled* (box #t))
(define *states* (box (hash)))
(define *queued* (box (hash)))

(define (breadcrumb-symbols-enabled?) (unbox *enabled*))
(define (breadcrumb-symbols-set-enabled! v) (set-box! *enabled* v))

(define (breadcrumb-symbols-clear! buf)
  (define st (hash-try-get (unbox *states*) buf))
  (set-box! *states* (hash-remove (unbox *states*) buf))
  (set-box! *queued* (hash-remove (unbox *queued*) buf))
  (when (and st (hash-try-get st "cancel"))
    ((hash-ref st "cancel"))))

(define (breadcrumb-symbols-refresh! buf)
  (define has-editor-win (findf is-editor? (vector->list (fn-call "win_findbuf" buf))))
  (if (or (not (unbox *enabled*)) (not (allows? buf)) (not has-editor-win))
      (breadcrumb-symbols-clear! buf)
      (let ([client (doc-symbols-client buf)])
          (if (not client)
              (breadcrumb-symbols-clear! buf)
              (let ((prev (hash-try-get (unbox *states*) buf))
                    (tick (nvim_buf_get_changedtick buf)))
                (unless (and prev
                             (equal? (hash-ref prev "client") client)
                             (= (hash-ref prev "tick") tick)
                             (or (hash-try-get prev "cancel") (hash-try-get prev "ready")))
                  (breadcrumb-symbols-clear! buf)
                  (define st-box
                    (box (hash "client" client
                               "symbols" (if (and prev
                                                  (equal? (hash-ref prev "client") client)
                                                  (= (hash-ref prev "tick") tick))
                                             (hash-ref prev "symbols")
                                             #f)
                               "tick" tick
                               "ready" #f
                               "cancel" #f)))
                  (set-box! *states* (hash-insert (unbox *states*) buf st-box))
                  (define cancel
                    (doc-symbols-request!
                      buf
                      client
                      (lambda (err symbols ctx)
                        (when (eq? (hash-try-get (unbox *states*) buf) st-box)
                          (set-box! st-box (hash-insert (unbox st-box) "cancel" #f))
                          (cond
                            ((or (not (unbox *enabled*)) (not (allows? buf)))
                             (breadcrumb-symbols-clear! buf))
                            ((and (not err) (source-unchanged? ctx))
                             (set-box! st-box
                                       (hash-insert
                                         (hash-insert (unbox st-box) "symbols" (draw.breadcrumb-index symbols (nvim_buf_get_name buf)))
                                         "ready"
                                         #t))
                             (cmd "redrawstatus")))))))
                  (set-box! st-box (hash-insert (unbox st-box) "cancel" cancel))))))))

(define (breadcrumb-symbols-render buf win cursor)
  (define entry (hash-try-get (unbox *states*) buf))
  (if (and entry (unbox *enabled*) (allows? buf) (is-editor? win))
      (let* ([state (unbox entry)]
             [index (hash-ref state "symbols")])
        (if (and index (= (hash-ref state "tick") (nvim_buf_get_changedtick buf)))
            (draw.breadcrumb-render
              index buf (vector-ref cursor 0) (vector-ref cursor 1)
              (or (hash-try-get (hash-ref state "client") "offset_encoding") "utf-16")
              "v:steel.NopackContextJump")
            ""))
      ""))

(define group (nvim_create_augroup "NopackBreadcrumbSymbols" (hash "clear" #t)))

(nvim_create_autocmd
  (vector "BufEnter" "BufWinEnter" "BufFilePost" "FileType" "TextChanged"
          "InsertLeave" "BufWritePost" "FileChangedShellPost" "LspAttach" "LspDetach")
  (hash "group" group
        "callback"
        (lambda (args)
          (define ev (hash-ref args "event"))
          (define buf (hash-ref args "buf"))
          (when (or (equal? ev "BufFilePost") (equal? ev "FileType"))
            (breadcrumb-symbols-clear! buf))
          (when (or (hash-try-get (unbox *states*) buf)
                    (and (unbox *enabled*) (allows? buf)))
            (unless (hash-try-get (unbox *queued*) buf)
              (define token (box #t))
              (set-box! *queued* (hash-insert (unbox *queued*) buf token))
              (schedule
                (lambda ()
                  (when (eq? (hash-try-get (unbox *queued*) buf) token)
                    (set-box! *queued* (hash-remove (unbox *queued*) buf))
                    (breadcrumb-symbols-refresh! buf)))))))))

(nvim_create_autocmd
  "BufUnload"
  (hash "group" group
        "callback" (lambda (args) (breadcrumb-symbols-clear! (hash-ref args "buf")))))

(nvim_create_autocmd
  "User"
  (hash "group" group
        "pattern" "NopackBufferRestricted"
        "callback" (lambda (args) (breadcrumb-symbols-clear! (hash-ref (hash-ref args "data") "buf")))))
