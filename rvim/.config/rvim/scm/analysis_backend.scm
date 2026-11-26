;; 1:1 Steel port of: nvim/.config/nvim/lua/analysis_backend.lua
;; Equivalence:
;; - Tracks registered LSP filetype providers and caches per-buffer analysis backend
;;   decisions ("lsp" vs "ctags") keyed by `(buf, filetype)`.
;; - Updates cache on `LspAttach` and clears on `BufWipeout`.
;; - Exports `analysis-backend-register!` and `analysis-backend-get`, and registers
;;   `'analysis-backend-get` on `state` for `statusline.scm`.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/lsp")
(require "state")

(provide analysis-backend-register! analysis-backend-get)

(define *providers* (box (hash)))
(define *decisions* (box (hash)))

(define (analysis-backend-register! filetypes accepts)
  (for-each
    (lambda (ft)
      (define existing (or (hash-try-get (unbox *providers*) ft) '()))
      (set-box! *providers* (hash-insert (unbox *providers*) ft (append existing (list accepts))))
      (set-box! *decisions*
                (foldl
                  (lambda (buf acc)
                    (define dec (hash-ref (unbox *decisions*) buf))
                    (if (equal? (hash-ref dec "filetype") ft)
                        (hash-remove acc buf)
                        acc))
                  (unbox *decisions*)
                  (hash-keys->list (unbox *decisions*)))))
    filetypes))

(define (analysis-backend-get buf0)
  (define buf (if (= buf0 0) (nvim_get_current_buf) buf0))
  (define ft (bo-get buf "filetype"))
  (define dec (hash-try-get (unbox *decisions*) buf))
  (if (and dec (equal? (hash-ref dec "filetype") ft))
      (hash-ref dec "mode")
      (let* ([ft-providers (or (hash-try-get (unbox *providers*) ft) '())]
             [matched-provider
              (let loop ([xs ft-providers])
                (cond
                  [(null? xs) #f]
                  [((car xs) buf) #t]
                  [else (loop (cdr xs))]))]
             [matched-client
              (if matched-provider
                  #t
                  (let loop ([cs (lsp-get-clients (hash "bufnr" buf))])
                    (if (null? cs)
                        #f
                        (let* ([cfg (hash-try-get (car cs) "config")]
                               [fts (and cfg (hash-try-get cfg "filetypes"))])
                          (if (or (not fts) (member ft fts))
                              #t
                              (loop (cdr cs)))))))]
             [mode (if matched-client "lsp" "ctags")])
        (set-box! *decisions*
                  (hash-insert (unbox *decisions*) buf (hash "filetype" ft "mode" mode)))
        mode)))

(state-set! 'analysis-backend-register analysis-backend-register!)
(state-set! 'analysis-backend-get analysis-backend-get)

(nvim_create_autocmd
  "LspAttach"
  (hash "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (set-box! *decisions*
                    (hash-insert (unbox *decisions*) buf
                                 (hash "filetype" (bo-get buf "filetype") "mode" "lsp"))))))

(nvim_create_autocmd
  "BufWipeout"
  (hash "callback"
        (lambda (args)
          (set-box! *decisions* (hash-remove (unbox *decisions*) (hash-ref args "buf"))))))
