;; 1:1 Steel port of: nvim/.config/nvim/lua/lsp/refresh.lua
;; Equivalence:
;; - Wraps LSP client `request`/`cancel_request` for diagnostic, semanticTokens, completion,
;;   and rename methods so stale responses are dropped and transient `ContentModified` /
;;   `ServerCancelled` failures retry with exponential backoff (50ms..1000ms).
;; - Cleans up retry timers on `LspRequest` cancel and `LspDetach`.

(require "rvim/api")
(require "rvim/lsp")
(require "rvim/schedule")
(require "buffer_policy")
(require "jobs")

(provide lsp-refresh-attach!)

(define *clients* (box (hash)))
(define *tracked-methods*
  (hash "textDocument/diagnostic" "diagnostic"
        "textDocument/semanticTokens/full" "tokens"
        "textDocument/semanticTokens/full/delta" "tokens"
        "textDocument/semanticTokens/range" "range"
        "textDocument/completion" "completion"
        "textDocument/prepareRename" "prepare-rename"
        "textDocument/rename" "rename"))

(define (stop-retry! st)
  (when st
    (define retrying (unbox (hash-ref st "retrying")))
    (when retrying
      (set-box! retrying (hash-remove (unbox retrying) (unbox (hash-ref st "original_id")))))
    (stop-timer! (unbox (hash-ref st "timer")))
    (set-box! (hash-ref st "timer") #f)))

(define (lsp-refresh-attach! client)
  (define native-request (hash-ref client "request"))
  (define native-cancel (hash-ref client "cancel_request"))
  (define retrying (box (hash)))
  (define (send-request self method params handler buf)
    (define target-buf (if (or (equal? buf 0) (equal? buf (nvim_get_current_buf))) #f buf))
    (native-request self method params handler target-buf))
  (define (wrapped-cancel self id)
    (define st (hash-try-get (unbox retrying) id))
    (define actual-id
      (if st
          (begin
            (set-box! (hash-ref st "cancelled") #t)
            (stop-retry! st)
            (unbox (hash-ref st "id")))
          id))
    (native-cancel self actual-id))
  (define (wrapped-request self method params handler buf0)
    (define kind (hash-try-get *tracked-methods* method))
    (if (not kind)
        (send-request self method params handler buf0)
        (let* ([buf (if (or (not buf0) (= buf0 0)) (nvim_get_current_buf) buf0)]
               [cid (hash-ref self "id")]
               [buffers (or (hash-try-get (unbox *clients*) cid)
                            (let ([b (box (hash))])
                              (set-box! *clients* (hash-insert (unbox *clients*) cid b))
                              b))]
               [requests (or (hash-try-get (unbox buffers) buf)
                             (let ([r (box (hash))])
                               (set-box! buffers (hash-insert (unbox buffers) buf r))
                               r))]
               [key (string-append kind ":" (or (hash-try-get params "identifier") ""))]
               [prev (hash-try-get (unbox requests) key)])
          (when (and prev (unbox (hash-ref prev "retrying")))
            (wrapped-cancel self (unbox (hash-ref prev "original_id"))))
          (stop-retry! prev)
          (define ver (lsp-buf-version buf))
          (define st
            (hash "version" ver
                  "delay" (box (and prev (equal? (hash-ref prev "version") ver) (unbox (hash-ref prev "delay"))))
                  "cancelled" (box #f)
                  "retrying" (box #f)
                  "original_id" (box #f)
                  "id" (box #f)
                  "timer" (box #f)))
          (set-box! requests (hash-insert (unbox requests) key st))
          (define effective-handler (or handler (lsp-client-handler self method)))
          (define (current? ctx)
            (and (equal? (hash-try-get (unbox buffers) buf) requests)
                 (equal? (hash-try-get (unbox requests) key) st)
                 (not (unbox (hash-ref st "cancelled")))
                 (not ((hash-ref self "is_stopped") self))
                 (hash-try-get (hash-ref self "attached_buffers") buf)
                 (allows? buf)
                 (equal? (hash-ref (hash-ref params "textDocument") "uri") (lsp-uri-from-bufnr buf))
                 (equal? (hash-try-get ctx "version") (lsp-buf-version buf))))
          (define (on-response err result ctx)
            (if (not (current? ctx))
                (stop-retry! st)
                (let* ([code (and err (hash-try-get err "code"))]
                       [data (and err (hash-try-get err "data"))]
                       [retry?
                        (and (or (equal? kind "diagnostic") (equal? kind "tokens"))
                             err
                             (or (equal? code -32801)
                                 (and (equal? code -32802)
                                      (or (not (hash? data))
                                          (not (equal? (hash-try-get data "retriggerRequest") #f))))))])
                  (if (not retry?)
                      (begin
                        (stop-retry! st)
                        (set-box! requests (hash-remove (unbox requests) key))
                        (define ctx2 (hash-insert ctx "request_id"
                                                  (or (unbox (hash-ref st "original_id")) (hash-try-get ctx "request_id"))))
                        (effective-handler err result ctx2))
                      (begin
                        (unless (unbox (hash-ref st "original_id"))
                          (set-box! (hash-ref st "original_id") (hash-try-get ctx "request_id")))
                        (set-box! (hash-ref st "retrying") retrying)
                        (set-box! retrying (hash-insert (unbox retrying) (unbox (hash-ref st "original_id")) st))
                        (define delay (min (* (or (unbox (hash-ref st "delay")) 25) 2) 1000))
                        (set-box! (hash-ref st "delay") delay)
                        (set-box! (hash-ref st "timer")
                                  (defer-fn
                                    (lambda ()
                                      (set-box! (hash-ref st "timer") #f)
                                      (if (and (current? ctx)
                                               (or (not (equal? kind "tokens"))
                                                   (lsp-semantic-tokens-enabled? (hash "bufnr" buf "client_id" cid))))
                                          (let ([res (send-request self method params on-response buf)])
                                            (set-box! (hash-ref st "id") (cdr res))
                                            (unless (car res)
                                              (stop-retry! st)
                                              (set-box! requests (hash-remove (unbox requests) key))
                                              (effective-handler #f #f ctx)))
                                          (stop-retry! st)))
                                    delay)))))))
          (define res (send-request self method params on-response buf))
          (set-box! (hash-ref st "id") (cdr res))
          res)))
  (lsp-client-wrap-requests! client wrapped-request wrapped-cancel))

(define *group* (nvim_create_augroup "flash-lsp-refresh" (hash "clear" #t)))
(nvim_create_autocmd
  "LspRequest"
  (hash "group" *group*
        "callback"
        (lambda (args)
          (define data (hash-ref args "data"))
          (when (equal? (hash-try-get (hash-ref data "request") "type") "cancel")
            (define buffers (hash-try-get (unbox *clients*) (hash-ref data "client_id")))
            (define reqs (and buffers (hash-try-get (unbox buffers) (hash-ref args "buf"))))
            (when reqs
              (for-each
                (lambda (k)
                  (define st (hash-ref (unbox reqs) k))
                  (when (equal? (unbox (hash-ref st "id")) (hash-ref data "request_id"))
                    (stop-retry! st)
                    (set-box! reqs (hash-remove (unbox reqs) k))))
                (hash-keys->list (unbox reqs))))))))

(nvim_create_autocmd
  "LspDetach"
  (hash "group" *group*
        "callback"
        (lambda (args)
          (define id (hash-ref (hash-ref args "data") "client_id"))
          (define buffers (hash-try-get (unbox *clients*) id))
          (when buffers
            (define reqs (hash-try-get (unbox buffers) (hash-ref args "buf")))
            (when reqs
              (for-each (lambda (k) (stop-retry! (hash-ref (unbox reqs) k)))
                        (hash-keys->list (unbox reqs))))
            (set-box! buffers (hash-remove (unbox buffers) (hash-ref args "buf")))
            (when (null? (hash-keys->list (unbox buffers)))
              (set-box! *clients* (hash-remove (unbox *clients*) id)))))))
