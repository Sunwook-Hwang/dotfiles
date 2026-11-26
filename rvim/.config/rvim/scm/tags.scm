;; 1:1 Steel port of: nvim/.config/nvim/lua/tags.lua
;; Equivalence:
;; - Universal / Exuberant Ctags probing, per-project incremental/full tag indexing
;;   with atomic temp-file swap (`uv-fs-rename`), `bo.tags` attachment, and 750ms save
;;   debounce.
;; - `gd` dispatches to LSP (`textDocument/definition`, with `ContentModified` retry and
;;   exact-name filtering) or Ctags (`tjump`) per `analysis_backend.scm` without silent
;;   backend switching on RPC failure.
;; - Provides `g<C-t>`, `:CtagsUpdate`, `:CtagsClearAll`, and `NopackCancel`/`NopackBufferRestricted` hooks.

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/fs")
(require "rvim/uv")
(require "rvim/lsp")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "analysis_backend")
(require "jobs")
(require "state")

(define *tag-projects* (box (hash)))
(define *definition-requests* (box (hash)))
(define *managed-tags* (box (hash)))
(define *ctags-checked* (box #f))
(define *ctags-kind* (box #f))
(define *ctags-command* (box #f))
(define *ctags-probe* (box #f))
(define *tag-work-seq* (box 0))
(define *cancel-generation* (box 0))

(define (finish-tag-waiters! waiters succeeded output (cancelled #f))
  (for-each
    (lambda (waiter)
      (define cb (if succeeded (hash-try-get waiter "after") (hash-try-get waiter "failed")))
      (when cb
        (with-handler
          (lambda (err) (notify (to-string err) (log-level 'warn)))
          (cb output cancelled))))
    waiters))

(define (cancel-tag-build! root project)
  (set-box! (hash-ref project "generation") (+ (unbox (hash-ref project "generation")) 1))
  (cancel-command! (string-append "ctags:" root))
  (define active (unbox (hash-ref project "active")))
  (define waiters
    (if active
        (begin
          (for-each (lambda (f) (set-box! (hash-ref project "pending")
                                          (hash-insert (unbox (hash-ref project "pending")) f #t)))
                    (hash-keys->list (hash-ref active "files")))
          (append (unbox (hash-ref project "waiters")) (hash-ref active "waiters")))
        (unbox (hash-ref project "waiters"))))
  (set-box! (hash-ref project "active") #f)
  (set-box! (hash-ref project "save_version") #f)
  (set-box! (hash-ref project "waiters") '())
  (set-box! (hash-ref project "full") #f)
  (set-box! (hash-ref project "quiet") #t)
  (finish-tag-waiters! waiters #f #f #t))

(state-set! 'tag-projects *tag-projects*)
(state-set! 'definition-requests *definition-requests*)
(state-set! 'finish-tag-waiters finish-tag-waiters!)
(state-set! 'cancel-tag-build cancel-tag-build!)

(define (ctags-candidates)
  (define seen (box (hash)))
  (define res (box '()))
  (define (add! path)
    (when (and path (not (equal? path "")) (not (hash-contains? (unbox seen) path)))
      (set-box! seen (hash-insert (unbox seen) path #t))
      (set-box! res (cons path (unbox res)))))
  (add! (g-get "nopack_ctags"))
  (define exe (if (= (fn-call "has" "win32") 1) "ctags.exe" "ctags"))
  (define sep (if (= (fn-call "has" "win32") 1) ";" ":"))
  (for-each
    (lambda (dir)
      (unless (equal? dir "")
        (add! (fs-joinpath dir exe))))
    (split-many (or (env-get "PATH") "") sep))
  (reverse (unbox res)))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackCancel"
        "callback"
        (lambda (_args)
          (set-box! *cancel-generation* (+ (unbox *cancel-generation*) 1))
          (when (unbox *ctags-probe*)
            (set-box! *ctags-probe* #f)
            (set-box! *ctags-checked* #f))
          (for-each
            (lambda (root) (cancel-tag-build! root (hash-ref (unbox *tag-projects*) root)))
            (hash-keys->list (unbox *tag-projects*)))
          (for-each
            (lambda (buf) ((hash-ref (hash-ref (unbox *definition-requests*) buf) "cancel")))
            (hash-keys->list (unbox *definition-requests*))))))

(define (ctags-available! quiet callback)
  (define candidates (ctags-candidates))
  (define checked (string-join candidates "\x00;"))
  (define (answer! avail)
    (when (and (not avail) (not quiet))
      (notify "Universal or Exuberant Ctags required; check ctags --version or g:nopack_ctags"
              (log-level 'warn)))
    (callback avail))
  (when (and (unbox *ctags-probe*) (not (hash-contains? (unbox (state-get 'running)) "ctags-probe")))
    (set-box! *ctags-probe* #f)
    (set-box! *ctags-checked* #f))
  (define active-probe (unbox *ctags-probe*))
  (cond
    [(and active-probe (equal? (hash-ref active-probe "key") checked))
     (set-box! (hash-ref active-probe "waiters")
               (append (unbox (hash-ref active-probe "waiters")) (list answer!)))]
    [(and (equal? (unbox *ctags-checked*) checked) (not active-probe))
     (answer! (not (not (unbox *ctags-kind*))))]
    [else
     (define probe (hash "key" checked "waiters" (box (list answer!))))
     (set-box! *ctags-probe* probe)
     (set-box! *ctags-checked* checked)
     (set-box! *ctags-kind* #f)
     (set-box! *ctags-command* #f)
     (state-set! 'ctags-kind #f)
     (define idx-box (box 0))
     (define fallback-box (box #f))
     (define (finish!)
       (when (equal? (unbox *ctags-probe*) probe)
         (set-box! *ctags-probe* #f)
         (when (and (not (unbox *ctags-kind*)) (unbox fallback-box))
           (set-box! *ctags-kind* "exuberant")
           (set-box! *ctags-command* (unbox fallback-box)))
         (define k (unbox *ctags-kind*))
         (state-set! 'ctags-kind
                     (cond [(equal? k "universal") "Universal"]
                           [(equal? k "exuberant") "Exuberant"]
                           [else #f]))
         (cmd "redrawstatus")
         (for-each (lambda (w) (w (not (not k)))) (unbox (hash-ref probe "waiters")))))
     (define (next-candidate!)
       (when (equal? (unbox *ctags-probe*) probe)
         (define cmd-path
           (let loop ([i (unbox idx-box)])
             (if (>= i (length candidates))
                 (begin (set-box! idx-box i) #f)
                 (let ([c (list-ref candidates i)])
                   (if (= (fn-call "executable" c) 1)
                       (begin (set-box! idx-box (+ i 1)) c)
                       (loop (+ i 1)))))))
         (if (not cmd-path)
             (finish!)
             (run-command!
               "ctags-probe"
               (list cmd-path "--options=NONE" "--version")
               (hash "quiet" #t "timeout" 2000 "max_bytes" 65536 "failed" next-candidate!)
               (lambda (version _lim)
                 (when (equal? (unbox *ctags-probe*) probe)
                   (cond
                     [(string-contains? version "Universal Ctags")
                      (set-box! *ctags-kind* "universal")
                      (set-box! *ctags-command* cmd-path)
                      (finish!)]
                     [else
                      (when (and (string-contains? version "Exuberant Ctags") (not (unbox fallback-box)))
                        (set-box! fallback-box cmd-path))
                      (next-candidate!)])))))))
     (next-candidate!)]))

(define (tag-context buf)
  (if (or (not (nvim_buf_is_valid buf)) (not (allows? buf)))
      #f
      (let ([raw (nvim_buf_get_name buf)])
        (if (equal? raw "")
            #f
            (let* ([file (or (uv-fs-realpath raw) raw)]
                   [proj (state-call 'find-project (fs-dirname file))])
              (cons (car proj) file))))))

(state-set! 'tag-context tag-context)

(define (tag-project root)
  (define existing (hash-try-get (unbox *tag-projects*) root))
  (if existing
      existing
      (let ([tags-dir (string-append (state-get 'nopack-data) "/tags")])
        (fn-call "mkdir" tags-dir "p")
        (define proj
          (hash "path" (string-append tags-dir "/" (fn-call "sha256" root))
                "pending" (box (hash))
                "waiters" (box '())
                "quiet" (box #t)
                "full" (box #f)
                "ready" (box #f)
                "active" (box #f)
                "save_version" (box #f)
                "generation" (box 0)))
        (set-box! *tag-projects* (hash-insert (unbox *tag-projects*) root proj))
        proj)))

(define (attach-tags! buf)
  (define tags (bo-get buf "tags"))
  (define prev (hash-try-get (unbox *managed-tags*) buf))
  (when (or prev (not (null? (hash-keys->list (unbox *tag-projects*)))))
    (define stripped
      (if (and prev (starts-with? tags prev))
          (substring tags (string-length prev) (string-length tags))
          tags))
    (define ctx (tag-context buf))
    (define proj (and ctx (hash-try-get (unbox *tag-projects*) (car ctx))))
    (define prefix (and proj (string-append (fn-call "escape" (hash-ref proj "path") " ,\\") ",")))
    (define updated (string-append (or prefix "") stripped))
    (unless (equal? (bo-get buf "tags") updated)
      (bo-set buf "tags" updated))
    (set-box! *managed-tags*
              (if prefix
                  (hash-insert (unbox *managed-tags*) buf prefix)
                  (hash-remove (unbox *managed-tags*) buf)))))

(define (tag-command)
  (append
    (list (unbox *ctags-command*) "--options=NONE")
    (if (equal? (unbox *ctags-kind*) "exuberant")
        '("--format=2" "--extra=-q" "--tag-relative=no")
        '("--output-format=e-ctags" "--extras=-q" "--tag-relative=never"))
    '("--fields=+nK" "--sort=yes" "--links=no"
      "--langmap=C++:+.ipp.cu.cuh,Python:+.pyi" "-f" "-")))

(define *tag-unescapes* (hash "t" "\t" "r" "\r" "n" "\n" "\\" "\\"))

(define (tag-filename line)
  (define raw (string/match line "^[^\t]+\t([^\t]+)"))
  (if (not raw)
      ""
      (vector-ref (string/gsub raw "\\(.)" *tag-unescapes*) 0)))

(state-set! 'tag-filename tag-filename)

(define (run-tag-build! root full? changed after failed quiet)
  (define project (tag-project root))
  (set-box! (hash-ref project "generation") (+ (unbox (hash-ref project "generation")) 1))
  (define gen (unbox (hash-ref project "generation")))
  (cancel-command! (string-append "ctags:" root))
  (ctags-available!
    quiet
    (lambda (available)
      (when (and (equal? (hash-try-get (unbox *tag-projects*) root) project)
                 (= (unbox (hash-ref project "generation")) gen))
        (if (not available)
            (failed)
            (let ()
              (define (save! output)
                (set-box! *tag-work-seq* (+ (unbox *tag-work-seq*) 1))
                (define tmp
                  (string-append (hash-ref project "path") "."
                                 (number->string (fn-call "getpid")) "."
                                 (number->string (unbox *tag-work-seq*)) ".tmp"))
                (define work
                  (uv-new-work
                    "merge-tags"
                    (lambda (ok err)
                      (schedule
                        (lambda ()
                          (if (or (not (equal? (hash-try-get (unbox *tag-projects*) root) project))
                                  (not (= (unbox (hash-ref project "generation")) gen)))
                              (fn-call "delete" tmp)
                              (let ([err-box (box (if ok #f (to-string err)))])
                                (unless (unbox err-box)
                                  (with-handler
                                    (lambda (e) (set-box! err-box (to-string e)))
                                    (uv-fs-rename tmp (hash-ref project "path"))))
                                (fn-call "delete" tmp)
                                (if (unbox err-box)
                                    (begin (notify (unbox err-box) (log-level 'warn)) (failed))
                                    (begin
                                      (when full? (set-box! (hash-ref project "ready") #t))
                                      (for-each attach-tags! (nvim_list_bufs))
                                      (after output))))))))))
                (uv-work-queue work output (hash-ref project "path") tmp changed full?))
              (define (run! argv stdin)
                (run-command!
                  (string-append "ctags:" root)
                  argv
                  (hash "cwd" root
                        "stdin" stdin
                        "timeout" (if full? 120000 10000)
                        "max_bytes" (* (if full? 64 16) 1024 1024)
                        "failed" failed)
                  (lambda (out _lim) (save! out))))
              (cond
                [(not full?)
                 (define sorted (sort changed string<?))
                 (run! (append (tag-command) '("-L" "-"))
                       (string-append (string-join sorted "\n") "\n"))]
                [(uv-fs-stat (string-append root "/.git"))
                 (run-command!
                   (string-append "ctags:" root)
                   '("git" "ls-files" "-z" "--cached" "--others" "--exclude-standard")
                   (hash "cwd" root "timeout" 30000 "max_bytes" (* 16 1024 1024) "failed" failed)
                   (lambda (output _lim)
                     (define seen (box (hash)))
                     (define sources
                       (filter-map
                         (lambda (f)
                           (define path (string-append root "/" f))
                           (if (or (string/find f "[\r\n]")
                                   (hash-contains? (unbox seen) path)
                                   (not (= (fn-call "filereadable" path) 1)))
                               #f
                               (begin
                                 (set-box! seen (hash-insert (unbox seen) path #t))
                                 path)))
                         (state-call 'records output "\x00;")))
                     (if (null? sources)
                         (save! "")
                         (run! (append (tag-command) '("-L" "-"))
                               (string-append (string-join sources "\n") "\n")))))]
                [else
                 (define excludes
                   (map (lambda (d) (string-append "--exclude=" d))
                        (or (state-get 'ignored-dirs) '())))
                 (run! (append (tag-command) excludes (list "-R" root)) #f)])))))))

(define (build-tags! root full? (files #f) (after #f) (failed #f) (quiet #f))
  (define project (tag-project root))
  (for-each
    (lambda (f) (set-box! (hash-ref project "pending")
                          (hash-insert (unbox (hash-ref project "pending")) f #t)))
    (or files '()))
  (set-box! (hash-ref project "full") (or (unbox (hash-ref project "full")) full?))
  (set-box! (hash-ref project "quiet") (and (unbox (hash-ref project "quiet")) (equal? quiet #t)))
  (when (or after failed)
    (set-box! (hash-ref project "waiters")
              (append (unbox (hash-ref project "waiters"))
                      (list (hash "after" after "failed" failed)))))
  (unless (or (unbox (hash-ref project "active"))
              (and (not (unbox (hash-ref project "full")))
                   (null? (hash-keys->list (unbox (hash-ref project "pending"))))))
    (define batch
      (hash "files" (unbox (hash-ref project "pending"))
            "full" (unbox (hash-ref project "full"))
            "waiters" (unbox (hash-ref project "waiters"))
            "quiet" (unbox (hash-ref project "quiet"))))
    (set-box! (hash-ref project "pending") (hash))
    (set-box! (hash-ref project "waiters") '())
    (set-box! (hash-ref project "full") #f)
    (set-box! (hash-ref project "quiet") #t)
    (set-box! (hash-ref project "active") batch)
    (define (finish! ok (output #f))
      (when (and (equal? (hash-try-get (unbox *tag-projects*) root) project)
                 (equal? (unbox (hash-ref project "active")) batch))
        (set-box! (hash-ref project "active") #f)
        (define queued? (or (unbox (hash-ref project "full"))
                            (not (null? (hash-keys->list (unbox (hash-ref project "pending")))))))
        (unless ok
          (for-each (lambda (f) (set-box! (hash-ref project "pending")
                                          (hash-insert (unbox (hash-ref project "pending")) f #t)))
                    (hash-keys->list (hash-ref batch "files"))))
        (define gen (unbox (hash-ref project "generation")))
        (finish-tag-waiters! (hash-ref batch "waiters") ok output)
        (when (and queued?
                   (equal? (hash-try-get (unbox *tag-projects*) root) project)
                   (= (unbox (hash-ref project "generation")) gen))
          (build-tags! root #f #f #f #f #t))))
    (run-tag-build!
      root (hash-ref batch "full") (hash-keys->list (hash-ref batch "files"))
      (lambda (out) (finish! #t out))
      (lambda () (finish! #f))
      (hash-ref batch "quiet"))))

(state-set! 'build-tags build-tags!)

(define (still-at? buf win ctx pos)
  (and (allows? buf)
       (nvim_win_is_valid win)
       (= (nvim_get_current_win) win)
       (= (nvim_win_get_buf win) buf)
       (source-unchanged? ctx)
       (equal? (nvim_win_get_cursor win) pos)))

(define (request-tags! (after #f))
  (state-call 'focus-editor)
  (define buf (nvim_get_current_buf))
  (define win (nvim_get_current_win))
  (define ctx (tag-context buf))
  (when (and ctx (not (string/find (cdr ctx) "[\r\n]")))
    (define src-ctx (source-context buf))
    (define pos (nvim_win_get_cursor win))
    (build-tags!
      (car ctx) #t (list (cdr ctx))
      (and after
           (lambda (_out _cancelled)
             (if (still-at? buf win src-ctx pos)
                 (nvim_win_call win after)
                 (notify "Ctags index ready; repeat navigation in the desired file")))))))

(define (ctags-definition!)
  (define ctx (tag-context (nvim_get_current_buf)))
  (define word (fn-call "expand" "<cword>"))
  (when (and ctx (not (equal? word "")))
    (when (bo-get 0 "modified")
      (notify "Ctags uses saved files; save edits to update definitions"))
    (define (jump!)
      (attach-tags! (nvim_get_current_buf))
      (define tags
        (fn-call "taglist"
                 (string-append "\\C^\\V" (fn-call "escape" word "\\") "\\m$")
                 (fn-call "expand" "%:p")))
      (if (null? tags)
          (notify (string-append "No definition in saved project files: " word))
          (cmd (string-append "tjump " (fn-call "fnameescape" word)))))
    (if (unbox (hash-ref (tag-project (car ctx)) "ready"))
        (jump!)
        (request-tags! jump!))))

(keymap-set "n" "g<C-t>" "<Cmd>pop<CR>" (hash "desc" "Return from ctags definition"))
(nvim_create_user_command "CtagsUpdate" (lambda (_opts) (request-tags!)) (hash))
(nvim_create_user_command
  "CtagsClearAll"
  (lambda (_opts)
    (for-each (lambda (r) (cancel-tag-build! r (hash-ref (unbox *tag-projects*) r)))
              (hash-keys->list (unbox *tag-projects*)))
    (set-box! *tag-projects* (hash))
    (fn-call "delete" (string-append (state-get 'nopack-data) "/tags") "rf")
    (for-each
      (lambda (b)
        (b-set b "nopack_tags_requested" #f)
        (attach-tags! b))
      (nvim_list_bufs))
    (notify "Cleared all managed ctags caches"))
  (hash))

(nvim_create_autocmd
  '("BufEnter" "BufFilePost" "FileType")
  (hash "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (unless (equal? (hash-ref args "event") "BufEnter")
            (b-set buf "nopack_tags_requested" #f))
          (attach-tags! buf)
          (when (and (allows? buf)
                     (not (equal? (bo-get buf "filetype") ""))
                     (equal? (analysis-backend-get buf) "ctags"))
            (ctags-available! #t (lambda (_avail) #f))))))

(nvim_create_autocmd
  "BufWipeout"
  (hash "callback" (lambda (args) (set-box! *managed-tags* (hash-remove (unbox *managed-tags*) (hash-ref args "buf"))))))

(define (ensure-tag-completion! buf)
  (unless (or (b-get buf "nopack_tags_requested")
              (not (allows? buf))
              (equal? (bo-get buf "filetype") "")
              (not (equal? (analysis-backend-get buf) "ctags")))
    (define ctx (tag-context buf))
    (when (and ctx (not (string/find (cdr ctx) "[\r\n]")))
      (b-set buf "nopack_tags_requested" #t)
      (build-tags!
        (car ctx) #f (list (cdr ctx)) #f
        (lambda (_o _c) (when (nvim_buf_is_valid buf) (b-set buf "nopack_tags_requested" #f)))
        #t))))

(nvim_create_autocmd
  "InsertEnter"
  (hash "callback"
        (lambda (args)
          (define gen (unbox *cancel-generation*))
          (define buf (hash-ref args "buf"))
          (schedule
            (lambda ()
              (when (and (= gen (unbox *cancel-generation*)) (nvim_buf_is_valid buf))
                (ensure-tag-completion! buf)))))))

(nvim_create_autocmd
  "BufWritePost"
  (hash "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (when (and (allows? buf) (equal? (analysis-backend-get buf) "ctags"))
            (define ctx (tag-context buf))
            (define root (and ctx (car ctx)))
            (define file (and ctx (cdr ctx)))
            (define project (and root (hash-try-get (unbox *tag-projects*) root)))
            (when (and project (not (string/find file "[\r\n]")))
              (set-box! (hash-ref project "pending")
                        (hash-insert (unbox (hash-ref project "pending")) file #t))
              (define ver (gensym))
              (set-box! (hash-ref project "save_version") ver)
              (defer-fn
                (lambda ()
                  (when (and (equal? (hash-try-get (unbox *tag-projects*) root) project)
                             (equal? (unbox (hash-ref project "save_version")) ver))
                    (build-tags! root #f #f #f #f #t)))
                750))))))

(define (exact-definitions locations word)
  (define files (box (hash)))
  (for-each
    (lambda (item)
      (define loc (hash-ref item "location"))
      (define uri (or (hash-try-get loc "uri") (hash-try-get loc "targetUri")))
      (define rng (or (hash-try-get loc "targetSelectionRange") (hash-try-get loc "range")))
      (when (and uri rng)
        (define fname (lsp-uri-to-fname uri))
        (define entry (or (hash-try-get (unbox files) fname)
                          (hash "last" (box 0) "targets" (box '()))))
        (set-box! (hash-ref entry "last") (max (unbox (hash-ref entry "last")) (+ (hash-ref (hash-ref rng "start") "line") 1)))
        (set-box! (hash-ref entry "targets") (cons (cons item rng) (unbox (hash-ref entry "targets"))))
        (set-box! files (hash-insert (unbox files) fname entry))))
    locations)
  (define matched (box (hash)))
  (for-each
    (lambda (fname)
      (define entry (hash-ref (unbox files) fname))
      (define buf (fn-call "bufnr" fname))
      (define loaded (and (> buf 0) (nvim_buf_is_loaded buf)))
      (define disk-lines
        (and (not loaded) (= (fn-call "filereadable" fname) 1)
             (fn-call "readfile" fname "" (unbox (hash-ref entry "last")))))
      (for-each
        (lambda (pair)
          (define item (car pair))
          (define rng (cdr pair))
          (define row (hash-ref (hash-ref rng "start") "line"))
          (define line
            (if loaded
                (let ([ls (nvim_buf_get_lines buf row (+ row 1) #f)]) (and (not (null? ls)) (car ls)))
                (and disk-lines (< row (length disk-lines)) (list-ref disk-lines row))))
          (when line
            (with-handler
              (lambda (_e) #f)
              (define first (lsp-str-byteindex line (hash-ref item "encoding") (hash-ref (hash-ref rng "start") "character") #f))
              (define last (lsp-str-byteindex line (hash-ref item "encoding") (hash-ref (hash-ref rng "end") "character") #f))
              (define name (substring line first last))
              (when (and (equal? name word) (string/match name "^[_%a][_%w]*$"))
                (set-box! matched (hash-insert (unbox matched) item #t))))))
        (unbox (hash-ref entry "targets"))))
    (hash-keys->list (unbox files)))
  (filter (lambda (it) (hash-contains? (unbox matched) it)) locations))

(keymap-set
  "n"
  "gd"
  (lambda ()
    (state-call 'focus-editor)
    (define buf (nvim_get_current_buf))
    (define win (nvim_get_current_win))
    (when (allows? buf)
      (define source-word (fn-call "expand" "<cword>"))
      (define position (nvim_win_get_cursor win))
      (define ctx (source-context buf))
      (define prev (hash-try-get (unbox *definition-requests*) buf))
      (define reuse?
        (and prev
             (= (hash-ref prev "win") win)
             (equal? (hash-ref prev "position") position)
             (source-unchanged? (hash-ref prev "context"))))
      (unless reuse?
        (when prev ((hash-ref prev "cancel")))
        (if (equal? (analysis-backend-get buf) "ctags")
            (ctags-definition!)
            (let ([clients (lsp-get-clients (hash "bufnr" buf "method" "textDocument/definition"))])
              (if (null? clients)
                  (notify "LSP definition provider is not connected or does not support definitions"
                          (log-level 'warn))
                  (let ([client-ids (foldl (lambda (c acc) (hash-insert acc (hash-ref c "id") #t)) (hash) clients)]
                        [done-box (box #f)]
                        [cancel-box (box #f)]
                        [retried-box (box #f)])
                    (define (stop! (completed #f))
                      (unless (unbox done-box)
                        (set-box! done-box #t)
                        (set-box! *definition-requests* (hash-remove (unbox *definition-requests*) buf))
                        (when (and (not completed) (unbox cancel-box))
                          ((unbox cancel-box)))))
                    (define req (hash "win" win "position" position "context" ctx "clients" client-ids "cancel" stop!))
                    (set-box! *definition-requests* (hash-insert (unbox *definition-requests*) buf req))
                    (define (send!)
                      (unless (unbox done-box)
                        (if (not (still-at? buf win ctx position))
                            (stop! #t)
                            (set-box!
                              cancel-box
                              (lsp-buf-request-all
                                buf "textDocument/definition"
                                (lambda (client) (lsp-make-position-params win (hash-try-get client "offset_encoding")))
                                (lambda (results)
                                  (unless (unbox done-box)
                                    (if (not (still-at? buf win ctx position))
                                        (stop! #t)
                                        (let ([locs (box '())]
                                              [errs (box '())]
                                              [cm-box (box #f)])
                                          (for-each
                                            (lambda (id)
                                              (define resp (hash-ref results id))
                                              (define client (lsp-get-client-by-id id))
                                              (define err (hash-try-get resp "err"))
                                              (define res (hash-try-get resp "result"))
                                              (cond
                                                [err
                                                 (when (equal? (hash-try-get err "code") -32801)
                                                   (set-box! cm-box #t))
                                                 (set-box! errs
                                                           (cons (string-append
                                                                   (if client (hash-ref client "name") (to-string id))
                                                                   ": " (hash-ref err "message"))
                                                                 (unbox errs)))]
                                                [(and client res)
                                                 (define xs (if (list? res) res (list res)))
                                                 (for-each
                                                   (lambda (loc)
                                                     (set-box! locs
                                                               (cons (hash "location" loc
                                                                           "encoding" (hash-try-get client "offset_encoding"))
                                                                     (unbox locs))))
                                                   xs)]))
                                            (hash-keys->list results))
                                          (define found (reverse (unbox locs)))
                                          (define errors (reverse (unbox errs)))
                                          (if (and (null? found) (unbox cm-box) (not (unbox retried-box)))
                                              (begin (set-box! retried-box #t) (schedule send!))
                                              (begin
                                                (stop! #t)
                                                (cond
                                                  [(and (null? found) (not (null? errors)))
                                                   (notify (string-append "LSP definition failed: " (string-join errors "; "))
                                                           (log-level 'warn))]
                                                  [else
                                                   (define filtered
                                                     (if (and (> (length found) 1) (not (equal? source-word "")))
                                                         (let ([ex (exact-definitions found source-word)])
                                                           (if (null? ex) found ex))
                                                         found))
                                                   (cond
                                                     [(null? filtered)
                                                      (notify (string-append "No LSP definition found: " source-word))]
                                                     [(= (length filtered) 1)
                                                      (lsp-show-document (hash-ref (car filtered) "location")
                                                                         (hash-ref (car filtered) "encoding")
                                                                         (hash "focus" #t))]
                                                     [else
                                                      (define items
                                                        (map (lambda (it)
                                                               (define ch (car (lsp-locations-to-items
                                                                                 (list (hash-ref it "location"))
                                                                                 (hash-ref it "encoding"))))
                                                               (hash-insert
                                                                 (hash-insert ch "label"
                                                                              (string-append (hash-ref ch "filename") ":"
                                                                                             (number->string (hash-ref ch "lnum"))))
                                                                 "action"
                                                                 (lambda ()
                                                                   (lsp-show-document (hash-ref it "location")
                                                                                      (hash-ref it "encoding")
                                                                                      (hash "focus" #t)))))
                                                             filtered))
                                                      (state-call 'open-picker "Definitions:" (hash "items" items))])]))))))))))))
                    (send!))))))))
  (hash "desc" "Go to definition: LSP or ctags"))

(nvim_create_autocmd
  "LspDetach"
  (hash "callback" (lambda (args)
                     (define req (hash-try-get (unbox *definition-requests*) (hash-ref args "buf")))
                     (when (and req (hash-contains? (hash-ref req "clients") (hash-ref (hash-ref args "data") "client_id")))
                       ((hash-ref req "cancel"))))))

(nvim_create_autocmd
  '("BufUnload" "BufFilePost" "FileType")
  (hash "callback" (lambda (args)
                     (define req (hash-try-get (unbox *definition-requests*) (hash-ref args "buf")))
                     (when req ((hash-ref req "cancel"))))))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackBufferRestricted"
        "callback"
        (lambda (args)
          (define buf (hash-ref (hash-ref args "data") "buf"))
          (attach-tags! buf)
          (define req (hash-try-get (unbox *definition-requests*) buf))
          (when req ((hash-ref req "cancel")))
          (define raw (nvim_buf_get_name buf))
          (define file (or (uv-fs-realpath raw) raw))
          (define root (and (not (equal? file "")) (car (state-call 'find-project (fs-dirname file)))))
          (define proj (and root (hash-try-get (unbox *tag-projects*) root)))
          (when proj
            (define active (unbox (hash-ref proj "active")))
            (when (or (hash-contains? (unbox (hash-ref proj "pending")) file)
                      (and active (hash-contains? (hash-ref active "files") file)))
              (cancel-tag-build! root proj)
              (set-box! (hash-ref proj "pending") (hash-remove (unbox (hash-ref proj "pending")) file))
              (unless (null? (hash-keys->list (unbox (hash-ref proj "pending"))))
                (build-tags! root #f)))))))
