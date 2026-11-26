;; 1:1 Steel port of: nvim/.config/nvim/lua/outline.lua
;; Equivalence:
;; - `<leader>o`: toggle right-hand code outline sidebar backed by LSP `documentSymbol`
;;   (via `document_symbols.scm`) or Ctags (via `tags.scm` / `analysis_backend.scm`).
;; - Two-way cursor tracking: moving cursor in sidebar previews symbol in editor;
;;   moving cursor in editor highlights enclosing symbol in sidebar.
;; - Refreshes on file switch, save, filetype change, or LSP attach/detach; cancels on
;;   `User NopackCancel` and resets on `BufUnload` / `User NopackBufferRestricted`.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/uv")
(require "rvim/lsp")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "analysis_backend")
(require "document_symbols")
(require "state")

(define *outline-ns* (nvim_create_namespace "nopack-outline-highlights"))

(define (name-highlight kind)
  (define k (string->lower kind))
  (cond
    [(or (equal? k "function") (equal? k "method") (equal? k "constructor")) "Function"]
    [(or (equal? k "class") (equal? k "struct") (equal? k "interface") (equal? k "enum")) "Type"]
    [else "Identifier"]))

(define (follow-source! st)
  (define win (hash-ref st "win"))
  (define buf (hash-ref st "buf"))
  (define source-win (unbox (hash-ref st "source_win")))
  (define source (unbox (hash-ref st "source")))
  (define src-ctx (unbox (hash-ref st "source_context")))
  (when (and (nvim_win_is_valid win)
             (= (nvim_win_get_buf win) buf)
             (is-editor? source-win)
             (= (nvim_win_get_buf source-win) source)
             (allows? source)
             src-ctx
             (source-unchanged? src-ctx))
    (define cursor (nvim_win_get_cursor source-win))
    (define pos-box (box #f))
    (define (get-pos)
      (or (unbox pos-box)
          (let ([p (doc-symbols-position source cursor (unbox (hash-ref st "encoding")))])
            (set-box! pos-box p)
            p)))
    (define selected
      (let loop ([xs (unbox (hash-ref st "items"))] [i 1] [sel #f] [enclosing #f] [nearest #f])
        (if (null? xs)
            sel
            (let* ([item (car xs)]
                   [rng (hash-try-get item "range")]
                   [lnum (hash-try-get item "lnum")])
              (cond
                [rng
                 (if (and (doc-symbols-contains? rng (get-pos))
                          (or (not enclosing)
                              (and (not (doc-symbols-before? (hash-ref rng "start") (hash-ref enclosing "start")))
                                   (not (doc-symbols-before? (hash-ref enclosing "end") (hash-ref rng "end"))))))
                     (loop (cdr xs) (+ i 1) i rng nearest)
                     (loop (cdr xs) (+ i 1) sel enclosing nearest))]
                [(and lnum (<= lnum (vector-ref cursor 0)) (or (not nearest) (> lnum nearest)))
                 (loop (cdr xs) (+ i 1) i enclosing lnum)]
                [else (loop (cdr xs) (+ i 1) sel enclosing nearest)])))))
    (when selected
      (set-box! (hash-ref st "selected_row") selected)
      (unless (= (vector-ref (nvim_win_get_cursor win) 0) selected)
        (nvim_win_set_cursor win (vector selected 0))))))

(define (outline-text! st lines)
  (define buf (hash-ref st "buf"))
  (when (nvim_buf_is_valid buf)
    (bo-set buf "modifiable" #t)
    (nvim_buf_set_lines buf 0 -1 #f lines)
    (bo-set buf "modifiable" #f)
    (nvim_buf_clear_namespace buf *outline-ns* 0 -1)
    (let loop ([items (unbox (hash-ref st "items"))] [i 0])
      (when (and (not (null? items)) (< i (length lines)))
        (define item (car items))
        (when (equal? (hash-ref item "label") (list-ref lines i))
          (for-each
            (lambda (span)
              (nvim_buf_set_extmark
                buf *outline-ns* i (list-ref span 0)
                (hash "end_col" (list-ref span 1) "hl_group" (list-ref span 2))))
            (or (hash-try-get item "highlights") '())))
        (loop (cdr items) (+ i 1))))
    (follow-source! st)))

(define (cancel-outline! st)
  (set-box! (hash-ref st "version") (+ (unbox (hash-ref st "version")) 1))
  (set-box! (hash-ref st "refresh_pending") #f)
  (set-box! (hash-ref st "request_context") #f)
  (define cancel (unbox (hash-ref st "cancel")))
  (when cancel
    (cancel)
    (set-box! (hash-ref st "cancel") #f)))

(state-set! 'cancel-outline cancel-outline!)

(define (reset-outline! st msg)
  (cancel-outline! st)
  (set-box! (hash-ref st "items") '())
  (outline-text! st (list msg)))

(define (set-outline-title! st buf)
  (define name (string-replace (fn-call "fnamemodify" (nvim_buf_get_name buf) ":t") "%" "%%"))
  (wo-local-set (hash-ref st "win") "winbar" (string-append " Outline: " name)))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackCancel"
        "callback" (lambda (_args)
                     (define st (state-get 'outline))
                     (when st (cancel-outline! st)))))

(nvim_create_autocmd
  "BufUnload"
  (hash "callback" (lambda (args)
                     (define st (state-get 'outline))
                     (when (and st (= (unbox (hash-ref st "source")) (hash-ref args "buf")))
                       (reset-outline! st "Source buffer closed")))))

(define (ctags-outline! st)
  (define version (unbox (hash-ref st "version")))
  (define buf (unbox (hash-ref st "source")))
  (set-box! (hash-ref st "source_context")
            (if (bo-get buf "modified") #f (source-context buf)))
  (define ctx (state-call 'tag-context buf))
  (define root (and ctx (car ctx)))
  (define file (and ctx (cdr ctx)))
  (cond
    [(not root)
     (outline-text! st '("Ctags unavailable or file exceeds size limits"))]
    [(or (string-contains? file "\r") (string-contains? file "\n"))
     #f]
    [else
     (define stat (uv-fs-stat file))
     (define stamp
       (and stat
            (string-append (number->string (hash-ref stat "size")) ":"
                           (number->string (hash-ref (hash-ref stat "mtime") "sec")) ":"
                           (number->string (hash-ref (hash-ref stat "mtime") "nsec")))))
     (if (and stamp
              (equal? (unbox (hash-ref st "ctags_file")) file)
              (equal? (unbox (hash-ref st "ctags_stamp")) stamp))
         (begin
           (set-box! (hash-ref st "items") (unbox (hash-ref st "ctags_items")))
           (outline-text! st (unbox (hash-ref st "ctags_lines"))))
         (begin
           (outline-text! st '("Indexing saved file..."))
           (state-call
             'build-tags
             root #f (list file)
             (lambda (output)
               (when (and (equal? (state-get 'outline) st)
                          (= (unbox (hash-ref st "version")) version)
                          (allows? buf))
                 (define items
                   (sort
                     (filter-map
                       (lambda (line)
                         (if (or (starts-with? line "!_TAG_")
                                 (not (equal? (state-call 'tag-filename line) file)))
                             #f
                             (let* ([name (or (lua-match line "^([^\t]+)") "")]
                                    [row-str (or (lua-match line "\tline:(%d+)") "")]
                                    [row (and (not (equal? row-str "")) (string->number row-str))]
                                    [kind0 (or (lua-match line ";\"\t([^\t]+)") "")]
                                    [kind (if (equal? kind0 "") "symbol" kind0)]
                                    [kind-label (string-append (string->upper (substring kind 0 1))
                                                               (substring kind 1 (string-length kind)))]
                                    [scope
                                     (foldl
                                       (lambda (field acc)
                                         (define m (or (lua-match line (string-append "\t" field ":([^\t]+)")) ""))
                                         (if (equal? m "") acc m))
                                       ""
                                       '("class" "struct" "namespace" "union" "enum" "function" "scope"))])
                               (if (not row)
                                   #f
                                   (let* ([depth (if (equal? scope "")
                                                     0
                                                     (length (split-many (string-replace scope "::" ".") ".")))]
                                          [indent-str (make-string (* depth 2) #\space)]
                                          [label (string-append indent-str kind-label " " name
                                                                (if (equal? scope "") "" (string-append " (" scope ")")))])
                                     (hash "lnum" row
                                           "label" label
                                           "highlights"
                                           (list (list (* depth 2) (+ (* depth 2) (string-length kind-label)) "Comment")
                                                 (list (+ (* depth 2) (string-length kind-label) 1)
                                                       (+ (* depth 2) (string-length kind-label) 1 (string-length name))
                                                       (name-highlight kind)))))))))
                       (state-call 'records output "\n"))
                     (lambda (a b) (< (hash-ref a "lnum") (hash-ref b "lnum")))))
                 (set-box! (hash-ref st "items") items)
                 (define lines (if (null? items) '("No symbols in saved file") (map (lambda (it) (hash-ref it "label")) items)))
                 (set-box! (hash-ref st "ctags_file") file)
                 (set-box! (hash-ref st "ctags_stamp") stamp)
                 (set-box! (hash-ref st "ctags_items") items)
                 (set-box! (hash-ref st "ctags_lines") lines)
                 (outline-text! st lines)))
             (lambda (_err cancelled)
               (when (and (equal? (state-get 'outline) st) (= (unbox (hash-ref st "version")) version))
                 (outline-text! st (list (if cancelled "Ctags indexing cancelled" "Ctags indexing failed")
                                         "Press r to retry")))))))]))

(define (refresh-outline! st (force #f))
  (define buf (unbox (hash-ref st "source")))
  (if (not (allows? buf))
      (reset-outline! st "Source buffer unavailable or protected")
      (let* ([mode (analysis-backend-get buf)]
             [client (and (equal? mode "lsp") (doc-symbols-client buf))]
             [req-ctx (unbox (hash-ref st "request_context"))])
        (unless (and req-ctx
                     (= (hash-ref req-ctx "buf") buf)
                     (equal? (unbox (hash-ref st "backend")) mode)
                     (equal? (unbox (hash-ref st "client")) client)
                     (source-unchanged? req-ctx)
                     (not force))
          (cancel-outline! st)
          (define version (unbox (hash-ref st "version")))
          (set-box! (hash-ref st "items") '())
          (set-box! (hash-ref st "source_context") #f)
          (set-box! (hash-ref st "backend") mode)
          (set-box! (hash-ref st "client") client)
          (set-box! (hash-ref st "request_context") (source-context buf))
          (cond
            [(equal? mode "ctags") (ctags-outline! st)]
            [(not client)
             (outline-text! st '("LSP symbol provider is not connected or does not support symbols"
                                 "Press r to retry"))]
            [else
             (outline-text! st '("Loading symbols..."))
             (set-box!
               (hash-ref st "cancel")
               (doc-symbols-request!
                 buf client
                 (lambda (err symbols context)
                   (when (and (equal? (state-get 'outline) st) (= (unbox (hash-ref st "version")) version))
                     (set-box! (hash-ref st "cancel") #f)
                     (when (allows? buf)
                       (cond
                         [(not (source-unchanged? context))
                          (outline-text! st '("File changed; save or press r"))]
                         [err
                          (set-box! (hash-ref st "request_context") #f)
                          (outline-text!
                            st
                            (list (string-append "LSP symbols failed: "
                                                 (car (lua-gsub (hash-ref err "message") "[%c]" " ")))
                                  "Press r to retry"))]
                         [else
                          (define lines-box (box '()))
                          (define items-box (box '()))
                          (define (collect nodes depth)
                            (for-each
                              (lambda (sym)
                                (define loc
                                  (or (hash-try-get sym "location")
                                      (hash "uri" (lsp-uri-from-bufnr buf)
                                            "range" (or (hash-try-get sym "selectionRange")
                                                        (hash-try-get sym "range")))))
                                (define kind (lsp-symbol-kind-name (hash-try-get sym "kind")))
                                (define clean-name (car (lua-gsub (hash-ref sym "name") "[%c]" " ")))
                                (define lbl (string-append (make-string (* depth 2) #\space) kind " " clean-name))
                                (set-box! lines-box (cons lbl (unbox lines-box)))
                                (set-box! items-box
                                          (cons (hash "location" loc
                                                      "range" (or (hash-try-get sym "range") (hash-ref loc "range"))
                                                      "label" lbl
                                                      "highlights"
                                                      (list (list (* depth 2) (+ (* depth 2) (string-length kind)) "Comment")
                                                            (list (+ (* depth 2) (string-length kind) 1)
                                                                  (string-length lbl)
                                                                  (name-highlight kind))))
                                                (unbox items-box)))
                                (when (hash-try-get sym "children")
                                  (collect (hash-ref sym "children") (+ depth 1))))
                              nodes))
                          (collect symbols 0)
                          (define lines (reverse (unbox lines-box)))
                          (define items (reverse (unbox items-box)))
                          (set-box! (hash-ref st "items") items)
                          (set-box! (hash-ref st "encoding") (hash-try-get client "offset_encoding"))
                          (set-box! (hash-ref st "source_context") context)
                          (outline-text! st (if (null? lines) '("No symbols in this file") lines))]))))
                 force))])))))

(keymap-set
  "n"
  "<leader>o"
  (lambda ()
    (define existing (state-get 'outline))
    (if existing
        (nvim_win_close (hash-ref existing "win") #t)
        (begin
          (state-call 'focus-editor)
          (if (or (not (allows? 0)) (equal? (nvim_buf_get_name 0) ""))
              (notify "Open a code file to view its outline")
              (let* ([src-buf (nvim_get_current_buf)]
                     [src-win (nvim_get_current_win)]
                     [obuf (nvim_create_buf #f #t)])
                (bo-set obuf "bufhidden" "wipe")
                (bo-set obuf "filetype" "nopack_outline")
                (define owin
                  (nvim_open_win
                    obuf #t
                    (hash "split" "right" "win" src-win "width" (state-call 'sidebar-width))))
                (define st
                  (hash "buf" obuf
                        "win" owin
                        "source" (box src-buf)
                        "source_win" (box src-win)
                        "version" (box 0)
                        "items" (box '())
                        "encoding" (box "utf-16")
                        "selected_row" (box #f)
                        "source_context" (box #f)
                        "request_context" (box #f)
                        "backend" (box #f)
                        "client" (box #f)
                        "cancel" (box #f)
                        "refresh_pending" (box #f)
                        "ctags_file" (box #f)
                        "ctags_stamp" (box #f)
                        "ctags_items" (box '())
                        "ctags_lines" (box '())))
                (state-set! 'outline st)
                (state-call 'fix-sidebar-width owin)
                (wo-local-set owin "number" #f)
                (wo-local-set owin "relativenumber" #f)
                (wo-local-set owin "signcolumn" "no")
                (wo-local-set owin "wrap" #f)
                (wo-local-set owin "cursorline" #t)
                (wo-local-set owin "cursorlineopt" "line")
                (wo-local-set owin "cursorcolumn" #f)
                (set-outline-title! st src-buf)
                (keymap-set "n" "q" (lambda () (nvim_win_close owin #t)) (hash "buf" obuf "desc" "Close outline"))
                (keymap-set "n" "r" (lambda () (refresh-outline! st #t)) (hash "buf" obuf "desc" "Refresh outline"))
                (nvim_create_autocmd
                  "CursorMoved"
                  (hash "buf" obuf
                        "callback"
                        (lambda (_args)
                          (define s-buf (unbox (hash-ref st "source")))
                          (define s-win (unbox (hash-ref st "source_win")))
                          (define s-ctx (unbox (hash-ref st "source_context")))
                          (when (and (equal? (state-get 'outline) st)
                                     (= (nvim_get_current_win) owin)
                                     (allows? s-buf)
                                     (is-editor? s-win)
                                     (= (nvim_win_get_buf s-win) s-buf)
                                     s-ctx
                                     (source-unchanged? s-ctx))
                            (define row-idx (vector-ref (nvim_win_get_cursor owin) 0))
                            (unless (equal? row-idx (unbox (hash-ref st "selected_row")))
                              (set-box! (hash-ref st "selected_row") row-idx)
                              (define items (unbox (hash-ref st "items")))
                              (when (and (>= row-idx 1) (<= row-idx (length items)))
                                (define item (list-ref items (- row-idx 1)))
                                (define loc (hash-try-get item "location"))
                                (define target-pos
                                  (if loc
                                      (if (= (fn-call "bufnr" (lsp-uri-to-fname (hash-ref loc "uri"))) s-buf)
                                          (let* ([start (hash-ref (hash-ref loc "range") "start")]
                                                 [r (+ (hash-ref start "line") 1)]
                                                 [ls (nvim_buf_get_lines s-buf (- r 1) r #f)]
                                                 [line (if (null? ls) "" (car ls))]
                                                 [c (lsp-str-byteindex line (unbox (hash-ref st "encoding"))
                                                                       (hash-ref start "character") #f)])
                                            (vector (min r (nvim_buf_line_count s-buf)) c))
                                          #f)
                                      (vector (min (hash-ref item "lnum") (nvim_buf_line_count s-buf)) 0)))
                                (when (and target-pos (not (equal? (nvim_win_get_cursor s-win) target-pos)))
                                  (nvim_win_set_cursor s-win target-pos)
                                  (nvim_win_call s-win (lambda () (cmd "normal! zvzz"))))))))))
                (keymap-set
                  "n"
                  "<CR>"
                  (lambda ()
                    (define s-ctx (unbox (hash-ref st "source_context")))
                    (if (or (not s-ctx) (not (source-unchanged? s-ctx)))
                        (notify "Outline is out of date; save the file or press r to refresh")
                        (let* ([row-idx (vector-ref (nvim_win_get_cursor owin) 0)]
                               [items (unbox (hash-ref st "items"))])
                          (when (and (>= row-idx 1) (<= row-idx (length items)))
                            (define item (list-ref items (- row-idx 1)))
                            (define s-buf (unbox (hash-ref st "source")))
                            (define s-win (unbox (hash-ref st "source_win")))
                            (if (is-editor? s-win)
                                (nvim_set_current_win s-win)
                                (state-call 'focus-editor))
                            (cond
                              [(hash-try-get item "location")
                               (lsp-show-document (hash-ref item "location")
                                                  (unbox (hash-ref st "encoding"))
                                                  (hash "focus" #t))]
                              [(nvim_buf_is_valid s-buf)
                               (cmd "normal! m'")
                               (nvim_win_set_buf 0 s-buf)
                               (nvim_win_set_cursor 0 (vector (min (hash-ref item "lnum") (nvim_buf_line_count s-buf)) 0))])
                            (cmd "normal! zvzz")))))
                  (hash "buf" obuf "desc" "Jump to symbol"))
                (nvim_create_autocmd
                  "WinClosed"
                  (hash "pattern" (number->string owin)
                        "once" #t
                        "callback" (lambda (_args)
                                     (cancel-outline! st)
                                     (when (equal? (state-get 'outline) st)
                                       (state-set! 'outline #f)))))
                (refresh-outline! st))))))
  (hash "desc" "Toggle code outline"))

(nvim_create_autocmd
  '("CursorMoved" "CursorMovedI" "BufEnter" "WinEnter")
  (hash "callback" (lambda (args)
                     (define st (state-get 'outline))
                     (when (and st (= (hash-ref args "buf") (unbox (hash-ref st "source"))) (is-editor? 0))
                       (set-box! (hash-ref st "source_win") (nvim_get_current_win))
                       (follow-source! st)))))

(nvim_create_autocmd
  '("BufEnter" "BufWritePost" "BufFilePost" "FileType" "LspAttach" "LspDetach")
  (hash "callback"
        (lambda (args)
          (define st (state-get 'outline))
          (when st
            (define owin (hash-ref st "win"))
            (define obuf (hash-ref st "buf"))
            (define ev (hash-ref args "event"))
            (define abuf (hash-ref args "buf"))
            (cond
              [(not (= (nvim_win_get_buf owin) obuf))
               (cancel-outline! st)
               (state-set! 'outline #f)]
              [(and (= abuf (unbox (hash-ref st "source")))
                    (or (equal? ev "BufFilePost") (equal? ev "FileType")))
               (cancel-outline! st)
               (set-box! (hash-ref st "items") '())
               (set-outline-title! st abuf)
               (if (not (allows? abuf))
                   (outline-text! st '("Source buffer unavailable"))
                   (refresh-outline! st))]
              [(and (is-source? abuf) (= (nvim_win_get_tabpage owin) (nvim_get_current_tabpage)))
               (define proceed #t)
               (when (equal? ev "BufEnter")
                 (if (not (is-editor? 0))
                     (set! proceed #f)
                     (let ([same? (= (unbox (hash-ref st "source")) abuf)])
                       (set-box! (hash-ref st "source") abuf)
                       (set-box! (hash-ref st "source_win") (nvim_get_current_win))
                       (if same?
                           (set! proceed #f)
                           (begin
                             (cancel-outline! st)
                             (set-box! (hash-ref st "items") '())
                             (set-box! (hash-ref st "source_context") #f)
                             (set-box! (hash-ref st "selected_row") #f)
                             (set-outline-title! st abuf))))))
               (when (and proceed (= abuf (unbox (hash-ref st "source"))) (not (unbox (hash-ref st "refresh_pending"))))
                 (define token (gensym))
                 (set-box! (hash-ref st "refresh_pending") token)
                 (schedule
                   (lambda ()
                     (when (equal? (unbox (hash-ref st "refresh_pending")) token)
                       (set-box! (hash-ref st "refresh_pending") #f)
                       (when (equal? (state-get 'outline) st)
                         (refresh-outline! st))))))])))))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackBufferRestricted"
        "callback" (lambda (args)
                     (define st (state-get 'outline))
                     (when (and st (= (unbox (hash-ref st "source")) (hash-ref (hash-ref args "data") "buf")))
                       (reset-outline! st "Large-file protection is active")))))
