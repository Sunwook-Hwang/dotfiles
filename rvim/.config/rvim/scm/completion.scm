;; 1:1 Steel port of: nvim/.config/nvim/lua/completion.lua
;; Equivalence:
;; - Native Blink replacement: built-in LSP completion (`lsp-completion-get`/`enable`) and
;;   snippets (`snippet-active?`/`snippet-jump!`) with `<C-Space>`, `<CR>`, `<Tab>`, `<S-Tab>`.
;; - Extends LSP completion `triggerCharacters` with identifier chars (`a-zA-Z0-9_`) and
;;   enables `bo.autocomplete` for ctags buffers, honoring `NopackBufferRestricted`.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/fn")
(require "rvim/lsp")
(require "rvim/snippet")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "analysis_backend")

(keymap-set
  "i" "<C-Space>"
  (lambda ()
    (when (allows? 0)
      (if (equal? (analysis-backend-get 0) "lsp")
          (lsp-completion-get)
          (nvim_feedkeys (nvim_replace_termcodes "<C-n>" #t #f #t) "n" #f))))
  (hash "desc" "Complete from LSP or buffer"))

(keymap-set
  "i" "<CR>"
  (lambda ()
    (if (and (= (fn-call "pumvisible") 1)
             (>= (hash-ref (fn-call "complete_info") "selected") 0))
        "<C-y>"
        "<CR>"))
  (hash "expr" #t "desc" "Accept selected completion / newline"))

(for-each
  (lambda (pair)
    (define key (car pair))
    (define dir (cdr pair))
    (keymap-set
      '("i" "s") key
      (lambda ()
        (cond
          [(snippet-active? (hash "direction" dir)) (snippet-jump! dir)]
          [(= (fn-call "pumvisible") 1)
           (nvim_feedkeys (nvim_replace_termcodes (if (= dir 1) "<C-n>" "<C-p>") #t #f #t) "n" #f)]
          [else (nvim_feedkeys (nvim_replace_termcodes key #t #f #t) "n" #f)]))
      (hash "desc" (string-append "Snippet tabstop / completion / " key))))
  '(("<Tab>" . 1) ("<S-Tab>" . -1)))

(define *completion-buffers* (box (hash)))
(define *pending-completion* (box (hash)))

(define (buffer-completion! buf)
  (define eligible (allows? buf))
  (bo-set buf "autocomplete" (and eligible (equal? (analysis-backend-get buf) "ctags")))
  (set-box! *completion-buffers* (hash-insert (unbox *completion-buffers*) buf eligible)))

(define *ident-chars*
  (vector->list (string/gmatch "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_" ".")))

(nvim_create_autocmd
  "LspAttach"
  (hash "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (when (allows? buf)
            (buffer-completion! buf)
            (define client (lsp-get-client-by-id (hash-ref (hash-ref args "data") "client_id")))
            (when (and client ((hash-ref client "supports_method") client "textDocument/completion"))
              (lsp-completion-extend-triggers! client *ident-chars*)
              (lsp-completion-enable! #t (hash-ref client "id") buf (hash "autotrigger" #t))
              (bo-set buf "autocomplete" #f))))))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackBufferRestricted"
        "callback" (lambda (args) (buffer-completion! (hash-ref (hash-ref args "data") "buf")))))

(nvim_create_autocmd
  '("BufEnter" "FileType" "LspDetach")
  (hash "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (unless (or (hash-contains? (unbox *pending-completion*) buf)
                      (and (equal? (hash-ref args "event") "BufEnter")
                           (equal? (hash-try-get (unbox *completion-buffers*) buf) (allows? buf))))
            (set-box! *pending-completion* (hash-insert (unbox *pending-completion*) buf #t))
            (schedule
              (lambda ()
                (set-box! *pending-completion* (hash-remove (unbox *pending-completion*) buf))
                (when (nvim_buf_is_loaded buf)
                  (buffer-completion! buf))))))))

(nvim_create_autocmd
  "BufWipeout"
  (hash "callback" (lambda (args)
                     (define buf (hash-ref args "buf"))
                     (set-box! *completion-buffers* (hash-remove (unbox *completion-buffers*) buf))
                     (set-box! *pending-completion* (hash-remove (unbox *pending-completion*) buf)))))
