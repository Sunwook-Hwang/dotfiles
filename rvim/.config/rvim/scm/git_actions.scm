;; 1:1 Steel port of: nvim/.config/nvim/lua/git_actions.lua
;; Equivalence:
;; - Hunk and visual-range staging (`<leader>gs`/`gS`), resetting (`<leader>gr`/`gR`),
;;   session undo-stage (`<leader>gU`), inline hunk preview (`<leader>gv`), deleted-lines
;;   toggle (`<leader>gt`), inner-hunk textobject (`ih`), and full blame float (`<leader>gB`).
;; - Uses histogram `text-diff` with full-context patches (`git apply --cached`) so stale
;;   index contents are rejected rather than misapplied; preserves CRLF, final EOL, and BOM.

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/fs")
(require "rvim/uv")
(require "rvim/diff")
(require "rvim/lsp")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "jobs")
(require "state")

(provide git-actions-clear! git-actions-render-deleted! git-actions-setup!)

(define *preview-ns* (nvim_create_namespace "nopack-git-preview"))
(define *deleted-ns* (nvim_create_namespace "nopack-git-deleted"))
(define *busy* (box (hash)))
(define *history* (box (hash)))
(define *previews* (box (hash)))
(define *deleted* (box (hash)))
(define *show-deleted* (box #f))
(define *limit* (* 256 1024))
(define *refresh-cb* (box (lambda (_buf) #f)))

;; Keep line terminators: patches must preserve both CRLF and missing final newlines.
(define (keep-records text)
  (define lines (vector->list (string/gmatch text "[^\n]*\n")))
  (define tail (string/match text "([^\n]+)$"))
  (if tail (append lines (list tail)) lines))

(define (diff-indices a b)
  (text-diff a b (hash "result_type" "indices" "algorithm" "histogram")))

(define (cursor-hunk hunks row)
  (let loop ([xs hunks])
    (if (null? xs)
        #f
        (let* ([h (car xs)]
               [b (list-ref h 2)]
               [n (list-ref h 3)])
          (if (and (>= row (max 1 b)) (<= row (max 1 (+ b (max 1 n) -1))))
              h
              (loop (cdr xs)))))))

(define (slice-0 lines start count)
  (if (<= count 0) '() (take (drop lines start) (min count (max 0 (- (length lines) start))))))

(define (selected-spans hunks top bottom whole?)
  (filter-map
    (lambda (h)
      (define a (list-ref h 0))
      (define m (list-ref h 1))
      (define b (list-ref h 2))
      (define n (list-ref h 3))
      (define anchor (max 1 b))
      (if (or whole? (and (<= anchor bottom) (>= (max anchor (+ b n -1)) top)))
          (let* ([first (if (or whole? (= n 0)) 0 (max 0 (- top b)))]
                 [last (if (= n 0) 0 (if whole? n (min n (+ (- bottom b) 1))))]
                 [old-first (min first m)]
                 [old-last (if (= last n) m (min last m))])
            (list (+ (if (= m 0) a (- a 1)) old-first)
                  (- old-last old-first)
                  (+ (if (= n 0) b (- b 1)) first)
                  (- last first)))
          #f))
    hunks))

(define (replace-spans base current changes reverse?)
  (define old (keep-records base))
  (define new (keep-records current))
  (define src (if reverse? new old))
  (let loop ([xs changes] [offset 0] [acc '()])
    (if (null? xs)
        (apply string-append (append acc (drop src offset)))
        (let* ([ch (car xs)]
               [a (list-ref ch 0)]
               [m (list-ref ch 1)]
               [b (list-ref ch 2)]
               [n (list-ref ch 3)]
               [start (if reverse? b a)]
               [cnt (if reverse? n m)]
               [repl (if reverse? (slice-0 old a m) (slice-0 new b n))]
               [unchanged (slice-0 src offset (max 0 (- start offset)))])
          (loop (cdr xs) (+ start cnt) (append acc unchanged repl))))))

(define *git-path-escapes*
  (foldl
    (lambda (code acc)
      (hash-insert acc (string (integer->char code)) (string/format "\\%03o" code)))
    (hash "\\" "\\134" "\"" "\\042" "\x7f" "\\177")
    (range 0 32)))

(define (quote-git-path path)
  (string-append "\"" (vector-ref (string/gsub path "[%c\\\"]" *git-path-escapes*) 0) "\""))

(define (build-patch path old new mode exists?)
  (define a (quote-git-path (string-append "a/" path)))
  (define b (quote-git-path (string-append "b/" path)))
  (define header
    (string-append "diff --git " a " " b "\n"
                   (if exists? "" (string-append "new file mode " mode "\n"))))
  (define ctx (+ (max (length (keep-records old)) (length (keep-records new))) 1))
  (string-append
    header "--- " (if exists? a "/dev/null") "\n+++ " b "\n"
    (text-diff old new (hash "algorithm" "histogram" "ctxlen" ctx))))

(define (git-warn text)
  (notify (string-append "Git: " text) (log-level 'warn)))

(define (buffer-text buf base)
  (define sep (if (and (equal? (bo-get buf "fileformat") "dos") (string-contains? base "\r\n")) "\r\n" "\n"))
  (define body (string-join (nvim_buf_get_lines buf 0 -1 #f) sep))
  (define with-eol (if (bo-get buf "endofline") (string-append body sep) body))
  (if (bo-get buf "bomb") (string-append "\xef\xbb\xbf" with-eol) with-eol))

(define (snapshot! callback)
  (define buf (nvim_get_current_buf))
  (if (not (allows? buf))
      #f
      (let* ([ctx (source-context buf)]
             [file (hash-ref ctx "file")]
             [root (and (not (equal? file "")) (state-call 'find-git-root (fs-dirname file)))])
        (cond
          [(or (not root) (= (fn-call "executable" "git") 0))
           (git-warn "Open a file in a Git repository") #f]
          [(hash-contains? (unbox *busy*) root)
           (git-warn "An action is still running in this repository") #f]
          [(> (nvim_buf_get_offset buf (nvim_buf_line_count buf)) *limit*)
           (git-warn "Hunk actions are limited to 256 KiB files") #f]
          [(and (not (equal? (bo-get buf "fileencoding") ""))
                (not (equal? (bo-get buf "fileencoding") "utf-8")))
           (git-warn "Hunk actions require UTF-8 text") #f]
          [else
           (define path (substring file (+ (string-length root) 1) (string-length file)))
           (define writing-box (box #f))
           (define exists-box (box #f))
           (define mode-box (box "100644"))
           (define base-box (box ""))
           (define current-box (box ""))
           (define hunks-box (box '()))
           (define st-box (box #f))
           (define (finish!)
             (when (equal? (hash-try-get (unbox *busy*) root) (unbox st-box))
               (set-box! *busy* (hash-remove (unbox *busy*) root))))
           (define (valid?)
             (and (equal? (hash-try-get (unbox *busy*) root) (unbox st-box))
                  (allows? buf)
                  (source-unchanged? ctx)))
           (define (run! args input done)
             (run-command!
               (string-append "git-action:" root)
               (append '("git" "--no-pager" "--literal-pathspecs") args)
               (hash "cwd" root "stdin" input "max_bytes" *limit*
                     "atomic" (unbox writing-box) "failed" finish!)
               (lambda (out _lim) (done out))))
           (define st
             (hash "buf" buf "context" ctx "root" root "path" path
                   "writing" writing-box "exists" exists-box "mode" mode-box
                   "base" base-box "current" current-box "hunks" hunks-box
                   "finish" finish! "valid" valid? "run" run!))
           (set-box! st-box st)
           (set-box! *busy* (hash-insert (unbox *busy*) root st))
           (run!
             (list "ls-files" "--stage" "-z" "--" path)
             #f
             (lambda (output)
               (if (not (valid?))
                   (finish!)
                   (let* ([m (string/match output "^(%d+) (%x+) (%d)\t")]
                          [matched (and (vector? m) (>= (vector-length m) 3))]
                          [mode (if matched (vector-ref m 0) #f)]
                          [oid (if matched (vector-ref m 1) #f)]
                          [stage (if matched (vector-ref m 2) #f)])
                     (if (and stage (or (not (equal? stage "0"))
                                        (and (not (equal? mode "100644")) (not (equal? mode "100755")))))
                         (begin (git-warn "Resolve index conflicts first; only regular files support hunk actions")
                                (finish!))
                         (let ([ok-file #t])
                           (set-box! exists-box (not (not oid)))
                           (set-box! mode-box (or mode "100644"))
                           (unless oid
                             (define info (uv-fs-lstat file))
                             (cond
                               [(and info (not (equal? (hash-try-get info "type") "file")))
                                (git-warn "Only regular files support hunk actions")
                                (finish!)
                                (set! ok-file #f)]
                               [(and info (not (= (bitwise-and (hash-ref info "mode") 73) 0)))
                                (set-box! mode-box "100755")]))
                           (when ok-file
                             (define (ready! base)
                               (if (not (valid?))
                                   (finish!)
                                   (let ([cur (buffer-text buf base)])
                                     (set-box! base-box base)
                                     (set-box! current-box cur)
                                     (if (or (string-contains? base "\x00") (string-contains? cur "\x00"))
                                         (begin (git-warn "Binary buffers do not support hunk actions") (finish!))
                                         (begin
                                           (set-box! hunks-box (diff-indices base cur))
                                           (callback st))))))
                             (if oid
                                 (run! (list "cat-file" "blob" oid) #f ready!)
                                 (ready! "")))))))))
           st]))))

(define (write-index! st target (undo #f))
  (define entry
    (or undo
        (hash "after" target
              "patch" (build-patch (hash-ref st "path") (unbox (hash-ref st "base"))
                                   target (unbox (hash-ref st "mode")) (unbox (hash-ref st "exists"))))))
  (if (and undo (not (equal? (unbox (hash-ref st "base")) (hash-ref undo "after"))))
      (begin
        (git-warn "Index changed since staging; refusing to overwrite other staged changes")
        ((hash-ref st "finish")))
      (let ([args (append '("apply" "--cached" "--whitespace=nowarn")
                          (if undo '("--reverse") '())
                          '("-"))])
        (set-box! (hash-ref st "writing") #t)
        ((hash-ref st "run")
         args (hash-ref entry "patch")
         (lambda (_out)
           (define key (hash-ref st "buf"))
           (when (and (nvim_buf_is_loaded key)
                      (equal? (nvim_buf_get_name key) (hash-ref (hash-ref st "context") "file")))
             (define stack (or (hash-try-get (unbox *history*) key) '()))
             (define next-stack (if undo (if (null? stack) '() (cdr stack)) (cons entry stack)))
             (set-box! *history* (hash-insert (unbox *history*) key next-stack)))
           ((hash-ref st "finish"))
           ((unbox *refresh-cb*) key)
           (notify (if undo "Git: staging undone" "Git: staged")))))))

(define (visible-lines text fmt)
  (define no-bom (vector-ref (string/gsub text "^\xef\xbb\xbf" "") 0))
  (define norm (if (equal? fmt "dos") (string-replace no-bom "\r\n" "\n") no-bom))
  (define trimmed (if (ends-with? norm "\n") (substring norm 0 (- (string-length norm) 1)) norm))
  (if (equal? trimmed "") '("") (split-many trimmed "\n")))

(define (reset-buffer! st target)
  (define buf (hash-ref st "buf"))
  (if (or (not ((hash-ref st "valid"))) (not (bo-get buf "modifiable")))
      ((hash-ref st "finish"))
      (let* ([old (nvim_buf_get_lines buf 0 -1 #f)]
             [new (visible-lines target (bo-get buf "fileformat"))]
             [edits (diff-indices (string-append (string-join old "\n") "\n")
                                  (string-append (string-join new "\n") "\n"))]
             [n (length edits)])
        (nvim_buf_call
          buf
          (lambda ()
            (let loop ([i (- n 1)])
              (when (>= i 0)
                (when (< i (- n 1)) (cmd "undojoin"))
                (define e (list-ref edits i))
                (define a (list-ref e 0))
                (define m (list-ref e 1))
                (define b (list-ref e 2))
                (define cnt (list-ref e 3))
                (define start (if (= m 0) a (- a 1)))
                (nvim_buf_set_lines buf start (+ start m) #f
                                    (slice-0 new (if (= cnt 0) b (- b 1)) cnt))
                (loop (- i 1))))))
        (bo-set buf "endofline" (ends-with? target "\n"))
        (bo-set buf "bomb" (starts-with? target "\xef\xbb\xbf"))
        ((hash-ref st "finish"))
        ((unbox *refresh-cb*) buf))))

(define (run-hunk-action! kind visual? whole?)
  (define cur (fn-call "line" "."))
  (define-values (top bottom)
    (if visual?
        (let ([v (fn-call "line" "v")])
          (nvim_feedkeys (nvim_replace_termcodes "<Esc>" #t #f #t) "n" #f)
          (values (min cur v) (max cur v)))
        (values cur cur)))
  (snapshot!
    (lambda (st)
      (define hunks (unbox (hash-ref st "hunks")))
      (define changes
        (cond
          [whole? (selected-spans hunks 1 100000000 #t)]
          [visual? (selected-spans hunks top bottom #f)]
          [else
           (define h (cursor-hunk hunks top))
           (if h (selected-spans (list h) 1 100000000 #t) '())]))
      (if (null? changes)
          (begin (git-warn "No unstaged hunk at this position") ((hash-ref st "finish")))
          (let ([target (replace-spans (unbox (hash-ref st "base"))
                                       (unbox (hash-ref st "current"))
                                       changes
                                       (equal? kind "reset"))])
            (if (equal? kind "stage")
                (write-index! st target)
                (reset-buffer! st target)))))))

(define (virtual-lines base-lines hunk)
  (map (lambda (line)
         (list (list (string-append "- " (vector-ref (string/gsub line "[\r\n]+$" "") 0)) "DiffDelete")))
       (slice-0 base-lines (- (list-ref hunk 0) 1) (list-ref hunk 1))))

(define (git-actions-clear! buf)
  (when (hash-contains? (unbox *deleted*) buf)
    (nvim_buf_clear_namespace buf *deleted-ns* 0 -1)
    (set-box! *deleted* (hash-remove (unbox *deleted*) buf))))

(define (git-actions-render-deleted! buf base hunks)
  (git-actions-clear! buf)
  (when (unbox *show-deleted*)
    (define base-lines-box (box #f))
    (for-each
      (lambda (h)
        (when (> (list-ref h 1) 0)
          (unless (unbox base-lines-box)
            (set-box! base-lines-box (keep-records base)))
          (set-box! *deleted* (hash-insert (unbox *deleted*) buf #t))
          (nvim_buf_set_extmark
            buf *deleted-ns* (max 0 (- (list-ref h 2) 1)) 0
            (hash "virt_lines" (virtual-lines (unbox base-lines-box) h)
                  "virt_lines_above" (or (> (list-ref h 3) 0) (= (list-ref h 2) 0))))))
      hunks)))

(define (at-cursor! callback (wait? #f))
  (define row (fn-call "line" "."))
  (define win (nvim_get_current_win))
  (define req
    (snapshot!
      (lambda (st)
        ((hash-ref st "finish"))
        (when (and (= (nvim_get_current_win) win)
                   (= (nvim_get_current_buf) (hash-ref st "buf"))
                   (= (fn-call "line" ".") row))
          (define h (cursor-hunk (unbox (hash-ref st "hunks")) row))
          (if h (callback st h) (git-warn "No unstaged hunk at this position"))))))
  (when (and wait? req)
    (wait-until 5500 (lambda () (not (equal? (hash-try-get (unbox *busy*) (hash-ref req "root")) req))) 10)))

(define (git-actions-setup! on-change)
  (set-box! *refresh-cb* on-change)
  (for-each
    (lambda (spec)
      (define key (list-ref spec 0))
      (define kind (list-ref spec 1))
      (define whole? (list-ref spec 2))
      (keymap-set "n" (string-append "<leader>" key)
                  (lambda () (run-hunk-action! kind #f whole?))
                  (hash "desc" (string-append "Git: " kind (if whole? " buffer" " hunk"))))
      (unless whole?
        (keymap-set "x" (string-append "<leader>" key)
                    (lambda () (run-hunk-action! kind #t #f))
                    (hash "desc" (string-append "Git: " kind " selection")))))
    '(("gs" "stage" #f) ("gr" "reset" #f) ("gS" "stage" #t) ("gR" "reset" #t)))

  (keymap-set
    "n" "<leader>gU"
    (lambda ()
      (snapshot!
        (lambda (st)
          (define stack (or (hash-try-get (unbox *history*) (hash-ref st "buf")) '()))
          (if (null? stack)
              (begin (git-warn "No staging to undo in this session") ((hash-ref st "finish")))
              (write-index! st #f (car stack))))))
    (hash "desc" "Git: Undo stage hunk"))

  (keymap-set
    "n" "<leader>gv"
    (lambda ()
      (at-cursor!
        (lambda (st h)
          (define buf (hash-ref st "buf"))
          (nvim_buf_clear_namespace buf *preview-ns* 0 -1)
          (set-box! *previews* (hash-insert (unbox *previews*) buf #t))
          (nvim_buf_set_extmark
            buf *preview-ns* (max 0 (- (list-ref h 2) 1)) 0
            (hash "virt_lines" (virtual-lines (keep-records (unbox (hash-ref st "base"))) h)
                  "virt_lines_above" (or (> (list-ref h 3) 0) (= (list-ref h 2) 0))))
          (when (> (list-ref h 3) 0)
            (nvim_buf_set_extmark
              buf *preview-ns* (- (list-ref h 2) 1) 0
              (hash "end_row" (+ (- (list-ref h 2) 1) (list-ref h 3))
                    "hl_group" "DiffAdd" "hl_eol" #t))))))
    (hash "desc" "Git: Preview hunk (inline)"))

  (keymap-set
    "n" "<leader>gt"
    (lambda ()
      (set-box! *show-deleted* (not (unbox *show-deleted*)))
      (for-each
        (lambda (buf)
          (when (nvim_buf_is_loaded buf)
            (git-actions-clear! buf)
            (when (and (unbox *show-deleted*) (not (= (fn-call "bufwinid" buf) -1)))
              ((unbox *refresh-cb*) buf))))
        (nvim_list_bufs))
      (notify (string-append "Deleted lines: " (if (unbox *show-deleted*) "on" "off"))))
    (hash "desc" "Git: Toggle deleted"))

  (keymap-set
    '("o" "x") "ih"
    (lambda ()
      (at-cursor!
        (lambda (_st h)
          (define m (fn-call "mode"))
          (when (or (equal? m "v") (equal? m "V") (equal? m "\x16"))
            (cmd (string-append "normal! " (nvim_replace_termcodes "<Esc>" #t #f #t))))
          (define s (max 1 (list-ref h 2)))
          (define e (max 1 (+ (list-ref h 2) (max 1 (list-ref h 3)) -1)))
          (cmd (string-append "normal! " (number->string s) "GV" (number->string e) "G")))
        #t))
    (hash "desc" "Git: inner hunk"))

  (keymap-set
    "n" "<leader>gB"
    (lambda ()
      (define row (fn-call "line" "."))
      (snapshot!
        (lambda (st)
          ((hash-ref st "run")
           (list "blame" "--line-porcelain" "--contents" "-"
                 "-L" (string-append (number->string row) "," (number->string row))
                 "--" (hash-ref st "path"))
           (unbox (hash-ref st "current"))
           (lambda (output)
             (if (not ((hash-ref st "valid")))
                 ((hash-ref st "finish"))
                 (let ([commit (or (string/match output "^(%x+)") "")])
                   (define (display! text)
                     (define ok (and ((hash-ref st "valid"))
                                     (= (nvim_get_current_buf) (hash-ref st "buf"))
                                     (= (fn-call "line" ".") row)))
                     ((hash-ref st "finish"))
                     (when ok
                       (lsp-open-floating-preview
                         (split-many text "\n") "git"
                         (hash "border" "single" "focusable" #t))))
                   (if (or (equal? commit "") (string/match commit "^0+$"))
                       (display! "Not committed yet")
                       ((hash-ref st "run")
                        (list "show" "--format=fuller" "--no-ext-diff" commit "--" (hash-ref st "path"))
                        #f display!)))))))))
    (hash "desc" "Git: Blame (full)"))

  (define group (nvim_create_augroup "nopack-git-actions" (hash "clear" #t)))
  (nvim_create_autocmd
    '("CursorMoved" "InsertEnter" "TextChanged" "TextChangedI" "BufLeave")
    (hash "group" group
          "callback" (lambda (args)
                       (define buf (hash-ref args "buf"))
                       (when (hash-contains? (unbox *previews*) buf)
                         (nvim_buf_clear_namespace buf *preview-ns* 0 -1)
                         (set-box! *previews* (hash-remove (unbox *previews*) buf)))
                       (when (or (equal? (hash-ref args "event") "TextChanged")
                                 (equal? (hash-ref args "event") "TextChangedI"))
                         (git-actions-clear! buf)))))
  (nvim_create_autocmd
    '("BufUnload" "BufFilePost")
    (hash "group" group
          "callback" (lambda (args)
                       (define buf (hash-ref args "buf"))
                       (nvim_buf_clear_namespace buf *preview-ns* 0 -1)
                       (set-box! *history* (hash-remove (unbox *history*) buf))
                       (set-box! *previews* (hash-remove (unbox *previews*) buf))
                       (git-actions-clear! buf))))
  (nvim_create_autocmd
    "User"
    (hash "group" group
          "pattern" '("NopackCancel" "NopackBufferRestricted")
          "callback"
          (lambda (args)
            (define data (hash-try-get args "data"))
            (define target-buf (and data (hash-try-get data "buf")))
            (for-each
              (lambda (root)
                (define st (hash-ref (unbox *busy*) root))
                (when (and (not (unbox (hash-ref st "writing")))
                           (or (not target-buf) (= (hash-ref st "buf") target-buf)))
                  (cancel-command! (string-append "git-action:" root))
                  (set-box! *busy* (hash-remove (unbox *busy*) root))))
              (hash-keys->list (unbox *busy*)))
            (for-each
              (lambda (buf)
                (when (and (nvim_buf_is_loaded buf) (or (not target-buf) (= buf target-buf)))
                  (nvim_buf_clear_namespace buf *preview-ns* 0 -1)
                  (git-actions-clear! buf)
                  (set-box! *previews* (hash-remove (unbox *previews*) buf))))
              (nvim_list_bufs))))))
