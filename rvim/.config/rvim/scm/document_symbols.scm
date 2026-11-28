;; 1:1 Steel port of: nvim/.config/nvim/lua/document_symbols.lua
;; Equivalence:
;; - Shared `textDocument/documentSymbol` RPC cache and listener fan-out used by
;;   both `outline.scm` and `breadcrumb_symbols.scm`.
;; - Shares one in-flight RPC and its successful result per buffer version, retries once on `ContentModified`,
;;   and only cancels the RPC when the last waiting consumer unsubscribes.
;; - Clears cache on `BufUnload`, `BufFilePost`, `FileType`, `LspDetach`, and
;;   `User NopackBufferRestricted`.

(require-builtin rvim/api)
(require "rvim/lsp")
(require "rvim/schedule")
(require "buffer_policy")
(require "state")

(provide doc-symbols-client
         doc-symbols-before?
         doc-symbols-contains?
         doc-symbols-position
         doc-symbols-clear!
         doc-symbols-request!)

(define *states* (box (hash)))
(define *method* "textDocument/documentSymbol")

(define (doc-symbols-client buf)
  (foldl
    (lambda (client best)
      (if (or (not best) (< (hash-ref client "id") (hash-ref best "id")))
          client
          best))
    #f
    (lsp-get-clients (hash "bufnr" buf "method" *method*))))

(define (doc-symbols-before? a b)
  (define la (hash-ref a "line"))
  (define lb (hash-ref b "line"))
  (or (< la lb) (and (= la lb) (< (hash-ref a "character") (hash-ref b "character")))))

(define (doc-symbols-contains? range pos)
  (and (not (doc-symbols-before? pos (hash-ref range "start")))
       (doc-symbols-before? pos (hash-ref range "end"))))

(define (doc-symbols-position buf cursor encoding)
  (define row (vector-ref cursor 0))
  (define col (vector-ref cursor 1))
  (define lines (vector->list (nvim_buf_get_lines buf (- row 1) row #f)))
  (define line (if (null? lines) "" (car lines)))
  (hash "line" (- row 1)
        "character" (lsp-str-utfindex line (or encoding "utf-16") col #f)))

(define (deliver! listener err result st)
  (schedule
    (lambda ()
      (when (unbox (hash-ref listener "active"))
        (set-box! (hash-ref listener "active") #f)
        ((hash-ref listener "callback") err (or result '()) (hash-ref st "context"))))))

(define (finish! st err result)
  (set-box! (hash-ref st "completed") #t)
  (set-box! (hash-ref st "request") #f)
  (set-box! (hash-ref st "result") result)
  (define buf (hash-ref (hash-ref st "context") "buf"))
  (when (and err (eq? (hash-try-get (unbox *states*) buf) st))
    (set-box! *states* (hash-remove (unbox *states*) buf)))
  (for-each (lambda (listener) (deliver! listener err result st))
            (unbox (hash-ref st "listeners")))
  (set-box! (hash-ref st "listeners") '()))

(define (doc-symbols-clear! buf)
  (define st (hash-try-get (unbox *states*) buf))
  (set-box! *states* (hash-remove (unbox *states*) buf))
  (when (and st (not (unbox (hash-ref st "completed"))))
    (set-box! (hash-ref st "cancelled") #t)
    (define req (unbox (hash-ref st "request")))
    (when req
      ((hash-ref (hash-ref st "client") "cancel_request") (hash-ref st "client") req))
    (finish! st (hash "code" -32800 "message" "Symbol request cancelled") #f)))

(define (doc-symbols-request! buf client callback (force #f))
  (define prev (hash-try-get (unbox *states*) buf))
  (define st
    (if (and prev
             (or (not (equal? (hash-ref prev "client") client))
                 (not (source-unchanged? (hash-ref prev "context")))
                 (and force (unbox (hash-ref prev "completed")))))
        (begin (doc-symbols-clear! buf) #f)
        prev))
  (define state
    (cond
      [(not st)
       (define fresh
         (hash "client" client
               "context" (source-context buf)
               "listeners" (box '())
               "completed" (box #f)
               "cancelled" (box #f)
               "started" (box #f)
               "retried" (box #f)
               "attempt" (box 0)
               "request" (box #f)
               "result" (box #f)))
       (set-box! *states* (hash-insert (unbox *states*) buf fresh))
       fresh]
      [(and force (not (unbox (hash-ref st "completed"))))
       (define req (unbox (hash-ref st "request")))
       (when req
         ((hash-ref client "cancel_request") client req))
       (set-box! (hash-ref st "attempt") (+ (unbox (hash-ref st "attempt")) 1))
       (set-box! (hash-ref st "request") #f)
       (set-box! (hash-ref st "started") #f)
       (set-box! (hash-ref st "retried") #f)
       st]
      [else st]))
  (define listener (hash "active" (box #t) "callback" callback))
  (if (unbox (hash-ref state "completed"))
      (deliver! listener #f (unbox (hash-ref state "result")) state)
      (set-box! (hash-ref state "listeners") (cons listener (unbox (hash-ref state "listeners")))))
  (define (send!)
    (unless (unbox (hash-ref state "cancelled"))
      (if (or (not (allows? buf)) (not (source-unchanged? (hash-ref state "context"))))
          (finish! state (hash "code" -32801 "message" "Source buffer changed") #f)
          (let ([answered (box #f)]
                [attempt (+ (unbox (hash-ref state "attempt")) 1)])
            (set-box! (hash-ref state "attempt") attempt)
            (define req-res
              ((hash-ref client "request")
               client
               *method*
               (hash "textDocument" (hash "uri" (lsp-uri-from-bufnr buf)))
               (lambda (err result)
                 (set-box! answered #t)
                 (unless (or (unbox (hash-ref state "cancelled"))
                             (not (= (unbox (hash-ref state "attempt")) attempt)))
                   (set-box! (hash-ref state "request") #f)
                   (if (and err
                            (equal? (hash-try-get err "code") -32801)
                            (not (unbox (hash-ref state "retried")))
                            (allows? buf)
                            (source-unchanged? (hash-ref state "context")))
                       (begin
                         (set-box! (hash-ref state "retried") #t)
                         (schedule
                           (lambda ()
                             (when (= (unbox (hash-ref state "attempt")) attempt)
                               (send!)))))
                       (finish! state err result)))
                 void)
               buf))
            (define ok (car req-res))
            (define id (cdr req-res))
            (cond
              [(not ok)
               (finish! state (hash "code" -32603 "message" "Symbol request could not be sent") #f)]
              [(not (unbox answered))
               (set-box! (hash-ref state "request") id)])))))
  (unless (unbox (hash-ref state "started"))
    (set-box! (hash-ref state "started") #t)
    (send!))
  (lambda ()
    (set-box! (hash-ref listener "active") #f)
    (set-box! (hash-ref state "listeners")
              (filter (lambda (l) (not (equal? l listener))) (unbox (hash-ref state "listeners"))))
    (when (and (equal? (hash-try-get (unbox *states*) buf) state)
               (not (unbox (hash-ref state "completed")))
               (null? (unbox (hash-ref state "listeners"))))
      (doc-symbols-clear! buf))))

(nvim_create_autocmd
  '("BufUnload" "BufFilePost" "FileType")
  (hash "callback" (lambda (args) (doc-symbols-clear! (hash-ref args "buf")))))

(nvim_create_autocmd
  "LspDetach"
  (hash "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (define st (hash-try-get (unbox *states*) buf))
          (when (and st (= (hash-ref (hash-ref st "client") "id")
                           (hash-ref (hash-ref args "data") "client_id")))
            (doc-symbols-clear! buf)))))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackBufferRestricted"
        "callback" (lambda (args) (doc-symbols-clear! (hash-ref (hash-ref args "data") "buf")))))
