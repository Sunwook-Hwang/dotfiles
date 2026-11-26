;; 1:1 Steel port of: nvim/.config/nvim/lua/breadcrumb_symbols.lua
;; Equivalence:
;; - Caches normalized LSP document symbols per buffer keyed by `(client, changedtick)`.
;; - Uses binary search + `prefix_end` pruning for O(log N) cursor hierarchy lookup.
;; - Delegates LSP `documentSymbol` requests via shared `document-symbols` hooks (P3 bridge).

(require-builtin rvim/api)
(require "rvim/fn")
(require "rvim/cmd")
(require "rvim/schedule")
(require "buffer_policy")
(require "state")

(provide breadcrumb-symbols-enabled?
         breadcrumb-symbols-set-enabled!
         breadcrumb-symbols-clear!
         breadcrumb-symbols-refresh!
         breadcrumb-symbols-get)

(define *enabled* (box #t))
(define *states* (box (hash)))
(define *queued* (box (hash)))

(define (breadcrumb-symbols-enabled?) (unbox *enabled*))
(define (breadcrumb-symbols-set-enabled! v) (set-box! *enabled* v))

(define (pos-before? a b)
  (define al (hash-ref a "line"))
  (define bl (hash-ref b "line"))
  (or (< al bl)
      (and (= al bl) (< (hash-ref a "character") (hash-ref b "character")))))

(define (range-contains? rng pos)
  (and (not (pos-before? pos (hash-ref rng "start")))
       (not (pos-before? (hash-ref rng "end") pos))))

(define (breadcrumb-symbols-clear! buf)
  (define st (hash-try-get (unbox *states*) buf))
  (set-box! *states* (hash-remove (unbox *states*) buf))
  (set-box! *queued* (hash-remove (unbox *queued*) buf))
  (when (and st (hash-try-get st "cancel"))
    ((hash-ref st "cancel"))))

(define (index-ranges nodes)
  (define furthest #f)
  (map (lambda (node)
         (define end-pos (hash-ref (hash-ref node "range") "end"))
         (when (or (not furthest) (pos-before? furthest end-pos))
           (set! furthest end-pos))
         (define children (hash-try-get node "children"))
         (define indexed-children (if children (index-ranges children) #f))
         (hash-insert (if indexed-children
                          (hash-insert node "children" indexed-children)
                          node)
                      "prefix_end"
                      furthest))
       nodes))

(define (breadcrumb-symbols-refresh! buf)
  (define has-editor-win (any is-editor? (fn-call "win_findbuf" buf)))
  (if (or (not (unbox *enabled*)) (not (allows? buf)) (not has-editor-win))
      (breadcrumb-symbols-clear! buf)
      (let ((doc-client (state-get 'document-symbols-client))
            (doc-request (state-get 'document-symbols-request)))
        (when (and (function? doc-client) (function? doc-request))
          (define client (doc-client buf))
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
                                             (list))
                               "tick" tick
                               "ready" #f
                               "cancel" #f)))
                  (set-box! *states* (hash-insert (unbox *states*) buf st-box))
                  (define cancel
                    (doc-request
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
                                         (hash-insert (unbox st-box) "symbols" (index-ranges symbols))
                                         "ready"
                                         #t))
                             (cmd "redrawstatus")))))))
                  (set-box! st-box (hash-insert (unbox st-box) "cancel" cancel)))))))))

(define (breadcrumb-symbols-get buf win cursor)
  (if (or (not (unbox *enabled*)) (not (allows? buf)) (not (is-editor? win)))
      (list)
      (let ((st-box (hash-try-get (unbox *states*) buf)))
        (if (not st-box)
            (list)
            (let ((st (unbox st-box)))
              (if (not (= (hash-ref st "tick") (nvim_buf_get_changedtick buf)))
                  (list)
                  (let* ((doc-pos (state-get 'document-symbols-position))
                         (pos (if (function? doc-pos)
                                  (doc-pos buf cursor (hash-try-get (hash-ref st "client") "offset_encoding"))
                                  (hash "line" (- (vector-ref cursor 0) 1) "character" (vector-ref cursor 1)))))
                    (define (visit nodes)
                      (define (scan rev)
                        (cond
                          ((null? rev) (list))
                          (else
                           (define node (car rev))
                           (cond
                             ((pos-before? pos (hash-ref (hash-ref node "range") "start"))
                              (scan (cdr rev)))
                             ((not (pos-before? pos (hash-ref node "prefix_end")))
                              (list))
                             ((range-contains? (hash-ref node "range") pos)
                              (cons node (let ((ch (hash-try-get node "children")))
                                           (if ch (visit ch) (list)))))
                             (else (scan (cdr rev)))))))
                      (scan (reverse nodes)))
                    (visit (hash-ref st "symbols")))))))))

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
