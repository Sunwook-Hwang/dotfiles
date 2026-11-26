;; 1:1 Steel port of: nvim/.config/nvim/lua/format.lua
;; Equivalence:
;; - Native Conform replacement: resolves external formatters per filetype (stylua,
;;   clang-format, ruff/black, prettier, buildifier, shfmt, cmake-format, latexindent,
;;   rustfmt, verible-verilog-format) or falls back to sequential LSP `textDocument/formatting`.
;; - Applies external diffs minimally via `text-diff` (`indices`) + `undojoin`; discards
;;   stale results if the buffer changes during async execution.
;; - Exposes `v:steel.NopackFormatStatus` and `<leader>lf` keymap.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/notify")
(require "rvim/diff")
(require "rvim/lsp")
(require "rvim/string")
(require "buffer_policy")
(require "jobs")
(require "state")

(define *format-status-cache* (box (hash)))
(define *format-versions* (box (hash)))

(define (cancel-format! buf)
  (define version (hash-try-get (unbox *format-versions*) buf))
  (set-box! *format-versions* (hash-remove (unbox *format-versions*) buf))
  (cancel-command! (string-append "format:" (number->string buf)))
  (when version
    (define req (unbox (hash-ref version "request")))
    (when (and req (hash-try-get req "id"))
      ((hash-ref (hash-ref req "client") "cancel_request")
       (hash-ref req "client")
       (hash-ref req "id")))))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackCancel"
        "callback" (lambda (_args)
                     (for-each cancel-format! (hash-keys->list (unbox *format-versions*))))))

(define *prettier* '(("prettier" "--stdin-filepath" "%")))

(define *formatters*
  (hash "lua" '(("stylua" "--stdin-filepath" "%" "-"))
        "c" '(("clang-format" "--assume-filename=%"))
        "cpp" '(("clang-format" "--assume-filename=%"))
        "cuda" '(("clang-format" "--assume-filename=%"))
        "python" '(("ruff" "format" "--stdin-filename" "%" "-")
                   ("black" "--quiet" "--stdin-filename" "%" "-"))
        "javascript" *prettier*
        "javascriptreact" *prettier*
        "typescript" *prettier*
        "typescriptreact" *prettier*
        "html" *prettier*
        "css" *prettier*
        "scss" *prettier*
        "less" *prettier*
        "json" *prettier*
        "jsonc" *prettier*
        "yaml" *prettier*
        "markdown" *prettier*
        "markdown.mdx" *prettier*
        "graphql" *prettier*
        "vue" *prettier*
        "handlebars" *prettier*
        "bzl" '(("buildifier" "-path" "%" "-"))
        "proto" '(("clang-format" "--assume-filename=%"))
        "sh" '(("shfmt" "-filename" "%"))
        "cmake" '(("cmake-format" "-"))
        "tex" '(("latexindent" "-"))
        "plaintex" '(("latexindent" "-"))
        "rust" '(("rustfmt" "--emit=stdout" "--edition=2021"))
        "verilog" '(("verible-verilog-format" "--stdin_name" "%" "-"))
        "systemverilog" '(("verible-verilog-format" "--stdin_name" "%" "-"))))

(define *format-status-group* (nvim_create_augroup "nopack-format-status" (hash "clear" #t)))

(nvim_create_autocmd
  '("FileType" "BufFilePost" "BufWritePost" "BufWipeout")
  (hash "group" *format-status-group*
        "callback" (lambda (args)
                     (set-box! *format-status-cache*
                               (hash-remove (unbox *format-status-cache*) (hash-ref args "buf"))))))

(define (invalidate-format-status!)
  (set-box! *format-status-cache* (hash)))

(nvim_create_autocmd
  '("FocusGained" "ShellCmdPost" "TermLeave" "TermClose")
  (hash "group" *format-status-group*
        "callback" (lambda (args)
                     (unless (is-picker-event? args)
                       (invalidate-format-status!)))))

(nvim_create_autocmd
  "User"
  (hash "group" *format-status-group*
        "pattern" "NopackRefresh"
        "callback" (lambda (_args) (invalidate-format-status!))))

(define (nopack-format-status)
  (if (not (state-get 'language-status-visible #t))
      ""
      (let* ([win (nvim_get_current_win)]
             [buf (nvim_win_get_buf win)])
        (cond
          [(not (is-source? buf)) ""]
          [(or (not (bo-get buf "modifiable")) (not (allows? buf))) "[FORMAT X]"]
          [else
           (define ft (bo-get buf "filetype"))
           (define key (list ft (or (env-get "PATH") "") (fn-call "getcwd" win)))
           (define cached (hash-try-get (unbox *format-status-cache*) buf))
           (define entry
             (if (and cached (equal? (hash-ref cached "key") key))
                 cached
                 (let* ([resolved (state-call 'resolve-candidate (or (hash-try-get *formatters* ft) '()))]
                        [cand (and resolved (car resolved))]
                        [fresh (hash "key" key "formatter" (and cand (car cand)))])
                   (set-box! *format-status-cache* (hash-insert (unbox *format-status-cache*) buf fresh))
                   fresh)))
           (if (hash-try-get entry "formatter")
               (string-append "[FORMAT: " (hash-ref entry "formatter") "]")
               (let* ([status-entry (state-call 'status-clients buf)]
                      [clients (if status-entry (hash-ref (unbox status-entry) "clients") '())]
                      [names-set
                       (foldl
                         (lambda (c acc)
                           (if ((hash-ref c "supports_method") c "textDocument/formatting" buf)
                               (hash-insert acc (car (lua-gsub (hash-ref c "name") "[%c]" " ")) #t)
                               acc))
                         (hash)
                         clients)]
                      [sorted (fn-call "sort" (hash-keys->list names-set))])
                 (if (> (length sorted) 0)
                     (string-append "[FORMAT: " (string-join sorted ", ") "]")
                     "[FORMAT X]")))]))))

(state-set! 'NopackFormatStatus nopack-format-status)

(define (list-slice-1based xs start end)
  (if (> start end)
      '()
      (take (drop xs (- start 1)) (+ (- end start) 1))))

(keymap-set
  "n"
  "<leader>lf"
  (lambda ()
    (cond
      [(or (not (is-source? 0)) (not (bo-get 0 "modifiable")))
       (notify "Open an editable file before formatting")]
      [(not (allows? (nvim_get_current_buf)))
       (notify "Formatting skipped: large-file protection is active")]
      [else
       (define buf (nvim_get_current_buf))
       (define ctx (box (source-context buf)))
       (define file (hash-ref (unbox ctx) "file"))
       (define filetype (hash-ref (unbox ctx) "filetype"))
       (cancel-format! buf)
       (define version (hash "request" (box #f)))
       (set-box! *format-versions* (hash-insert (unbox *format-versions*) buf version))
       (define (current?)
         (cond
           [(or (not (equal? (hash-try-get (unbox *format-versions*) buf) version))
                (not (allows? buf)))
            #f]
           [(or (not (bo-get buf "modifiable")) (not (source-unchanged? (unbox ctx))))
            (notify "Buffer changed during formatting; result discarded")
            #f]
           [else #t]))
       (define root (state-call 'project-root))
       (define candidates (hash-try-get *formatters* filetype))
       (define resolved (state-call 'resolve-candidate (or candidates '())))
       (define candidate (and resolved (car resolved)))
       (define executable (and resolved (cdr resolved)))
       (if (not candidate)
           (begin
             (when candidates
               (notify "Formatter missing; trying LSP"))
             (define clients (lsp-get-clients (hash "bufnr" buf "method" "textDocument/formatting")))
             (if (null? clients)
                 (notify "No formatting provider for this buffer")
                 (let ([params (lsp-make-formatting-params)])
                   (define (format-next! idx)
                     (when (and (< idx (length clients)) (current?))
                       (define client (list-ref clients idx))
                       (define req (hash "client" client "id" #f))
                       (set-box! (hash-ref version "request") req)
                       (define res
                         ((hash-ref client "request")
                          client
                          "textDocument/formatting"
                          params
                          (lambda (err edits)
                            (set-box! (hash-ref version "request") #f)
                            (when (current?)
                              (if err
                                  (notify (string-append "LSP formatting: " (hash-ref err "message"))
                                          (log-level 'warn))
                                  (begin
                                    (when edits
                                      (lsp-apply-text-edits edits buf (hash-ref client "offset_encoding")))
                                    (set-box! ctx (hash-insert (unbox ctx) "tick" (nvim_buf_get_changedtick buf)))
                                    (format-next! (+ idx 1))))))
                          buf))
                       (set-box! (hash-ref version "request") (hash-insert req "id" (cdr res)))))
                   (format-next! 0))))
           (let* ([original-eol (bo-get buf "endofline")]
                  [input (string-append (string-join (nvim_buf_get_lines buf 0 -1 #f) "\n")
                                        (if original-eol "\n" ""))]
                  [command (cons executable
                                 (map (lambda (arg) (string-replace arg "%" file)) (cdr candidate)))])
             (run-command!
               (string-append "format:" (number->string buf))
               command
               (hash "stdin" input "cwd" root)
               (lambda (content _limited)
                 (when (and (current?) (not (equal? content input)))
                   (define edits (text-diff input content (hash "result_type" "indices")))
                   (define lines (state-call 'records content "\n"))
                   (define n (length edits))
                   (let loop ([i (- n 1)])
                     (when (>= i 0)
                       (define e (list-ref edits i))
                       (define old-start (list-ref e 0))
                       (define old-count (list-ref e 1))
                       (define new-start (list-ref e 2))
                       (define new-count (list-ref e 3))
                       (define start (if (= old-count 0) old-start (- old-start 1)))
                       (when (< i (- n 1))
                         (nvim_buf_call buf (lambda () (cmd "undojoin"))))
                       (nvim_buf_set_lines
                         buf start (+ start old-count) #f
                         (list-slice-1based lines new-start (+ new-start new-count -1)))
                       (loop (- i 1))))
                   (bo-set buf "endofline" original-eol))))))]))
  (hash "desc" "Format asynchronously with installed tool or LSP"))

(nvim_create_autocmd
  '("BufUnload" "BufWipeout")
  (hash "callback" (lambda (args) (cancel-format! (hash-ref args "buf")))))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackBufferRestricted"
        "callback" (lambda (args) (cancel-format! (hash-ref (hash-ref args "data") "buf")))))
