;; 1:1 Steel port of: nvim/.config/nvim/lua/git.lua
;; Equivalence:
;; - Explorer Git status signs (`XY` / `**` aggregated children) in `flash-explorer` buffers.
;; - Per-buffer statusline Git branch/XY cache (`b:nopack_git_status`), `<leader><CR>`
;;   tracked-file picker, `<leader>sg` log, `<leader>gg` lazygit/status, `<leader>gd`/`gD`
;;   side-by-side index/HEAD diffs, `<leader>gj`/`gk` hunk jump, and `<leader>gb` inline blame.
;; - 200ms debounced gutter signs (`+`/`~`/`-`/`~-`) with bounded histogram+DP mixed-hunk
;;   alignment, `git_index_stamp` inode/mtime cache, and `git_actions.scm` integration.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/fs")
(require "rvim/uv")
(require "rvim/diff")
(require "rvim/notify")
(require "rvim/schedule")
(require "explorer")
(require "buffer_policy")
(require "jobs")
(require "git_actions")
(require "state")

(define *netrw-git-ns* (nvim_create_namespace "nopack-netrw-git"))
(define *netrw-git-timer* (box -1))
(define *netrw-git-updated* (box -1000))
(define *netrw-git-cache* (box (hash)))
(define *netrw-git-drawn* (box (hash)))
(define *netrw-git-snapshots* (box (hash)))

(define (netrw-git-statuses root output)
  (define entries (filter (lambda (s) (not (equal? s ""))) (split-many output "\x00")))
  (define trimmed-root (fn-call "substitute" root "/\\+$" "" ""))
  (define statuses (box (hash)))
  (let loop ([idx 0])
    (when (< idx (length entries))
      (define rec (list-ref entries idx))
      (define xy (if (>= (string-length rec) 2) (substring rec 0 2) ""))
      (define rel (if (>= (string-length rec) 4) (substring rec 3 (string-length rec)) ""))
      (define path0 (fn-call "substitute" (string-append trimmed-root "/" rel) "/\\+$" "" ""))
      (let ploop ([p path0])
        (when (and (not (equal? p root)) (not (equal? p (fs-dirname p))))
          (define prev (hash-try-get (unbox statuses) p))
          (set-box! statuses
                    (hash-insert (unbox statuses) p
                                 (if (and prev (not (equal? prev xy))) "**" xy)))
          (ploop (fs-dirname p))))
      (loop (+ idx (if (or (string-contains? xy "R") (string-contains? xy "C")) 2 1)))))
  (unbox statuses))

(define (draw-netrw-git! win buf top statuses)
  (when (and (nvim_win_is_valid win)
             (= (nvim_win_get_buf win) buf)
             (explorer-is-buffer? buf)
             (equal? (explorer-root buf) top))
    (set-box! *netrw-git-cache* (hash-insert (unbox *netrw-git-cache*) top statuses))
    (define tick (nvim_buf_get_changedtick buf))
    (define drawn (hash-try-get (unbox *netrw-git-drawn*) buf))
    (unless (and drawn
                 (equal? (hash-ref drawn "top") top)
                 (= (hash-ref drawn "tick") tick)
                 (equal? (hash-ref drawn "statuses") statuses))
      (set-box! *netrw-git-drawn*
                (hash-insert (unbox *netrw-git-drawn*) buf
                             (hash "top" top "tick" tick "statuses" statuses)))
      (define existing
        (box (foldl (lambda (m acc) (hash-insert acc (list-ref m 0) m))
                    (hash)
                    (nvim_buf_get_extmarks buf *netrw-git-ns* 0 -1 (hash "details" #t)))))
      (define count (nvim_buf_line_count buf))
      (let loop ([row 1])
        (when (<= row count)
          (define path (explorer-path buf row))
          (define xy (and path (hash-try-get statuses path)))
          (when xy
            (define hl
              (cond
                [(or (string-contains? xy "U") (equal? xy "AA") (equal? xy "DD")) "ErrorMsg"]
                [(equal? xy "**") "Directory"]
                [(string-contains? xy "D") "DiffDelete"]
                [(or (string-contains? xy "A") (string-contains? xy "?")) "DiffAdd"]
                [else "DiffChange"]))
            (define text (string-replace xy " " "."))
            (define prev (hash-try-get (unbox existing) row))
            (set-box! existing (hash-remove (unbox existing) row))
            (when (or (not prev)
                      (not (= (list-ref prev 1) (- row 1)))
                      (not (equal? (hash-try-get (list-ref prev 3) "sign_text") text)))
              (nvim_buf_set_extmark
                buf *netrw-git-ns* (- row 1) 0
                (hash "id" row "sign_text" text "sign_hl_group" hl "priority" 20))))
          (loop (+ row 1))))
      (for-each
        (lambda (id) (nvim_buf_del_extmark buf *netrw-git-ns* id))
        (hash-keys->list (unbox existing))))))

(define (each-tree! callback)
  (for-each
    (lambda (win)
      (define buf (nvim_win_get_buf win))
      (when (explorer-is-buffer? buf)
        (callback win buf (explorer-root buf))))
    (nvim_list_wins)))

(define (redraw-netrw-git! (_args #f))
  (each-tree!
    (lambda (win buf top)
      (draw-netrw-git! win buf top (or (hash-try-get (unbox *netrw-git-cache*) top) (hash))))))

(define (refresh-netrw-git! (_tid #f))
  (set-box! *netrw-git-timer* -1)
  (set-box! *netrw-git-updated* (uv-now))
  (define projects (box (hash)))
  (each-tree!
    (lambda (win buf top)
      (define root (state-call 'find-git-root top))
      (if (or (not root) (= (fn-call "isdirectory" top) 0))
          (draw-netrw-git! win buf top (hash))
          (set-box! projects (hash-insert (unbox projects) root #t)))))
  (for-each
    (lambda (root)
      (define key (string-append "git-tree:" root))
      (if (hash-contains? (unbox (state-get 'running)) key)
          (when (= (unbox *netrw-git-timer*) -1)
            (set-box! *netrw-git-timer* (fn-call "timer_start" 1000 refresh-netrw-git!)))
          (let ()
            (define (draw-project! statuses)
              (each-tree!
                (lambda (win buf top)
                  (when (equal? (state-call 'find-git-root top) root)
                    (draw-netrw-git! win buf top statuses)))))
            (run-command!
              key
              '("git" "--no-optional-locks" "status" "--porcelain=v1" "-z" "--untracked-files=all")
              (hash "cwd" root
                    "quiet" #t
                    "failed" (lambda ()
                               (set-box! *netrw-git-snapshots* (hash-remove (unbox *netrw-git-snapshots*) root))
                               (draw-project! (hash))))
              (lambda (output _lim)
                (define snap (hash-try-get (unbox *netrw-git-snapshots*) root))
                (define next-snap
                  (if (and snap (equal? (hash-ref snap "output") output))
                      snap
                      (let ([s (hash "output" output "statuses" (netrw-git-statuses root output))])
                        (set-box! *netrw-git-snapshots* (hash-insert (unbox *netrw-git-snapshots*) root s))
                        s)))
                (draw-project! (hash-ref next-snap "statuses")))))))
    (hash-keys->list (unbox projects))))

(define (queue-netrw-git! (_args #f))
  (when (= (unbox *netrw-git-timer*) -1)
    (let loop ([wins (nvim_list_wins)])
      (unless (null? wins)
        (if (explorer-is-buffer? (nvim_win_get_buf (car wins)))
            (let ([delay (max 100 (- 1000 (- (uv-now) (unbox *netrw-git-updated*))))])
              (set-box! *netrw-git-timer* (fn-call "timer_start" delay refresh-netrw-git!)))
            (loop (cdr wins)))))))

(define *netrw-git-group* (nvim_create_augroup "nopack-netrw-git" (hash "clear" #t)))
(nvim_create_autocmd
  "BufWipeout"
  (hash "group" *netrw-git-group*
        "callback" (lambda (args) (set-box! *netrw-git-drawn* (hash-remove (unbox *netrw-git-drawn*) (hash-ref args "buf"))))))
(nvim_create_autocmd
  "FileType"
  (hash "group" *netrw-git-group* "pattern" "flash-explorer" "callback" queue-netrw-git!))
(nvim_create_autocmd
  '("BufWinEnter" "BufWritePost" "FileChangedShellPost" "FocusGained" "ShellCmdPost" "TermLeave" "TermClose")
  (hash "group" *netrw-git-group*
        "callback" (lambda (args)
                     (unless (or (and (equal? (hash-ref args "event") "BufWinEnter")
                                      (not (explorer-is-buffer? (hash-ref args "buf"))))
                                 (is-picker-event? args))
                       (queue-netrw-git!)))))
(nvim_create_autocmd
  "TextChanged"
  (hash "group" *netrw-git-group*
        "callback" (lambda (_args)
                     (when (explorer-is-buffer? (nvim_get_current_buf))
                       (redraw-netrw-git!)))))
(nvim_create_autocmd
  "User" (hash "group" *netrw-git-group* "pattern" "NopackExplorerChanged" "callback" redraw-netrw-git!))
(nvim_create_autocmd
  "User" (hash "group" *netrw-git-group* "pattern" "NopackExternalChange" "callback" queue-netrw-git!))

;; =========================================
;; ========== GIT STATUSLINE CACHE =========
;; =========================================

(define *git-status-cache* (box (hash)))
(define *git-status-tasks* (box (hash)))

(define (refresh-git-status! buf force?)
  (when (nvim_buf_is_loaded buf)
    (define key (string-append "git-status:" (number->string buf)))
    (define file (nvim_buf_get_name buf))
    (define root (and (is-source? buf) (not (equal? file "")) (state-call 'find-git-root (fs-dirname file))))
    (define snap (hash-try-get (unbox *git-status-cache*) buf))
    (define pending (hash-try-get (unbox *git-status-tasks*) key))
    (unless (or (and (not force?) snap (equal? (hash-ref snap "file") file) (equal? (hash-ref snap "root") root))
                (and (not force?) pending
                     (hash-contains? (unbox (state-get 'running)) key)
                     (equal? (hash-ref pending "file") file)
                     (equal? (hash-ref pending "root") root)))
      (cancel-command! key)
      (if (or (not root) (= (fn-call "executable" "git") 0))
          (b-set buf "nopack_git_status" #f)
          (let ([cache-box *git-status-cache*])
            (set-box! *git-status-tasks* (hash-insert (unbox *git-status-tasks*) key (hash "file" file "root" root)))
            (run-command!
              key
              (list "git" "--no-optional-locks" "--literal-pathspecs"
                    "status" "--porcelain=v2" "--branch" "--no-ahead-behind" "-z" "--" file)
              (hash "cwd" root "quiet" #t)
              (lambda (output _lim)
                (when (and (nvim_buf_is_loaded buf) (equal? (nvim_buf_get_name buf) file))
                  (define branch (box #f))
                  (define oid (box #f))
                  (define xy (box #f))
                  (for-each
                    (lambda (rec)
                      (cond
                        [(starts-with? rec "# branch.head ")
                         (set-box! branch (substring rec 14 (string-length rec)))]
                        [(starts-with? rec "# branch.oid ")
                         (set-box! oid (substring rec 13 (string-length rec)))]
                        [(starts-with? rec "? ")
                         (set-box! xy "??")]
                        [else
                         (define m (fn-call "matchlist" rec "^[12u] \\(\\S\\+\\) "))
                         (when (and (list? m) (>= (length m) 2) (not (equal? (list-ref m 1) "")))
                           (set-box! xy (list-ref m 1)))]))
                    (filter (lambda (s) (not (equal? s ""))) (split-many output "\x00")))
                  (define bname
                    (if (equal? (unbox branch) "(detached)")
                        (let ([o (or (unbox oid) "")])
                          (string-append "HEAD@" (substring o 0 (min 7 (string-length o)))))
                        (unbox branch)))
                  (define status
                    (if bname
                        (string-append "[" bname (if (unbox xy) (string-append " " (unbox xy)) "") "]")
                        ""))
                  (set-box! cache-box (hash-insert (unbox cache-box) buf (hash "file" file "root" root)))
                  (unless (equal? (b-get buf "nopack_git_status") status)
                    (b-set buf "nopack_git_status" status)
                    (cmd "redrawstatus"))))))))))

(define *git-status-group* (nvim_create_augroup "nopack-git-status" (hash "clear" #t)))
(nvim_create_autocmd
  '("BufEnter" "BufReadPost" "BufWritePost" "FileChangedShellPost" "FocusGained" "ShellCmdPost" "TermLeave" "TermClose")
  (hash "group" *git-status-group*
        "callback"
        (lambda (args)
          (unless (is-picker-event? args)
            (define ev (hash-ref args "event"))
            (define buf (hash-ref args "buf"))
            (cond
              [(or (equal? ev "BufReadPost")
                   (equal? ev "FileChangedShellPost")
                   (and (equal? ev "BufWritePost") (is-source? buf)))
               (set-box! *git-status-cache* (hash-remove (unbox *git-status-cache*) buf))]
              [(not (equal? ev "BufEnter"))
               (set-box! *git-status-cache* (hash))])
            (if (or (equal? ev "TermLeave") (equal? ev "TermClose"))
                (let ([seen (box (hash))])
                  (for-each
                    (lambda (w)
                      (define b (nvim_win_get_buf w))
                      (unless (hash-contains? (unbox seen) b)
                        (set-box! seen (hash-insert (unbox seen) b #t))
                        (refresh-git-status! b #t)))
                    (nvim_tabpage_list_wins 0)))
                (refresh-git-status! buf (not (equal? ev "BufEnter"))))))))

(nvim_create_autocmd
  "User"
  (hash "group" *git-status-group*
        "pattern" '("NopackRefresh" "NopackExternalChange")
        "callback" (lambda (_args)
                     (set-box! *git-status-cache* (hash))
                     (refresh-git-status! (nvim_get_current_buf) #t))))

(nvim_create_autocmd
  "BufWipeout"
  (hash "group" *git-status-group*
        "callback" (lambda (args)
                     (define b (hash-ref args "buf"))
                     (set-box! *git-status-cache* (hash-remove (unbox *git-status-cache*) b))
                     (cancel-command! (string-append "git-status:" (number->string b))))))

;; =========================================
;; ====== GIT COMMANDS / DIFF / LAZYGIT ====
;; =========================================

(define (git-root)
  (define res (state-call 'project-root))
  (define root (if (pair? res) (car res) res))
  (define is-git (and (pair? res) (cdr res)))
  (if is-git
      root
      (begin (notify "Current file is not in a Git project") #f)))

(define (run-git! args callback)
  (define root (git-root))
  (when root
    (run-command! "git" (append '("git" "--no-pager") args) (hash "cwd" root)
                  (lambda (out _lim) (callback out)))))

(define (show-git-output! lines ft (vertical? #f))
  (cmd (if vertical? "rightbelow vnew" "botright new"))
  (bo-set 0 "buftype" "nofile")
  (bo-set 0 "buflisted" #f)
  (bo-set 0 "bufhidden" "wipe")
  (bo-set 0 "swapfile" #f)
  (nvim_buf_set_lines 0 0 -1 #f lines)
  (bo-set 0 "filetype" ft)
  (bo-set 0 "modifiable" #f))

(define *active-git-diff* (box #f))

(define (open-git-diff! source-buf source-win base-lines ft)
  (when (unbox *active-git-diff*)
    ((hash-ref (unbox *active-git-diff*) "close")))
  (when (and (nvim_win_is_valid source-win) (= (nvim_win_get_buf source-win) source-buf))
    (define closed (box #f))
    (nvim_set_current_win source-win)
    (cmd "diffthis")
    (show-git-output! base-lines ft #t)
    (define base-buf (nvim_get_current_buf))
    (define base-win (nvim_get_current_win))
    (cmd "diffthis")
    (define group (nvim_create_augroup "nopack-git-diff-window" (hash "clear" #t)))
    (define (close!)
      (unless (unbox closed)
        (set-box! closed #t)
        (set-box! *active-git-diff* #f)
        (with-handler (lambda (_e) #f) (nvim_del_augroup_by_id group))
        (cond
          [(nvim_win_is_valid source-win)
           (nvim_win_call source-win (lambda () (cmd "diffoff")))
           (when (nvim_win_is_valid base-win) (nvim_win_close base-win #t))
           (nvim_set_current_win source-win)]
          [(and (nvim_win_is_valid base-win) (nvim_buf_is_valid source-buf))
           (nvim_win_call base-win (lambda () (cmd "diffoff")))
           (nvim_win_set_buf base-win source-buf)
           (nvim_set_current_win base-win)])))
    (set-box! *active-git-diff* (hash "close" close!))
    (keymap-set "n" "q" close! (hash "buf" base-buf "nowait" #t "desc" "Close Git diff"))
    (keymap-set "n" "<Esc>" close! (hash "buf" base-buf "nowait" #t "desc" "Close Git diff"))
    (nvim_create_autocmd
      "WinClosed"
      (hash "group" group
            "pattern" (list (number->string source-win) (number->string base-win))
            "callback" (lambda (_args) (schedule close!))))))

(keymap-set "n" "<leader><CR>"
            (lambda ()
              (define root (git-root))
              (when root (state-call 'file-picker "Git files" root '("git" "ls-files" "-z"))))
            (hash "desc" "Git files: fuzzy picker"))

(keymap-set "n" "<leader>sg"
            (lambda ()
              (run-git! '("log" "-50" "--oneline")
                        (lambda (out) (show-git-output! (state-call 'records out "\n") "git"))))
            (hash "desc" "Git commits"))

(keymap-set
  "n" "<leader>gg"
  (lambda ()
    (if (= (fn-call "executable" "lazygit") 1)
        (let* ([root (state-call 'project-root)]
               [root-dir (if (pair? root) (car root) root)]
               [width (max 1 (floor (* (go-get "columns") 0.9)))]
               [height (max 1 (floor (* (go-get "lines") 0.9)))]
               [buf (nvim_create_buf #f #t)])
          (bo-set buf "bufhidden" "wipe")
          (define win
            (nvim_open_win
              buf #t
              (hash "relative" "editor" "width" width "height" height
                    "row" (floor (/ (- (go-get "lines") height) 2))
                    "col" (floor (/ (- (go-get "columns") width) 2))
                    "style" "minimal" "border" "none")))
          (wo-local-set win "winhighlight" "Normal:Normal,NormalNC:Normal")
          (define (close!)
            (when (and (nvim_win_is_valid win) (= (nvim_win_get_buf win) buf))
              (nvim_win_close win #t))
            (when (nvim_buf_is_valid buf)
              (nvim_buf_delete buf (hash "force" #t)))
            (state-call 'check-external-files))
          (define job
            (fn-call "jobstart" '("lazygit")
                     (hash "term" #t "cwd" root-dir "on_exit" (lambda (_j _c _e) (schedule close!)))))
          (if (> job 0)
              (cmd "startinsert")
              (begin (close!) (notify "Could not start lazygit" (log-level 'error)))))
        (run-git! '("status" "--short" "--branch" "--untracked-files=normal")
                  (lambda (out) (show-git-output! (state-call 'records out "\n") "git")))))
  (hash "desc" "Lazygit / Git status"))

(for-each
  (lambda (pair)
    (define key (car pair))
    (define rev (cdr pair))
    (keymap-set
      "n" (string-append "<leader>" key)
      (lambda ()
        (define file (nvim_buf_get_name 0))
        (define buf (nvim_get_current_buf))
        (define win (nvim_get_current_win))
        (if (or (not (allows? buf)) (equal? file ""))
            (notify "Open a tracked file first")
            (let* ([res (state-call 'project-root)]
                   [root (if (pair? res) (car res) res)]
                   [rel (substring file (+ (string-length root) 1) (string-length file))]
                   [ctx (source-context buf)])
              (run-git!
                (list "show" (string-append rev rel))
                (lambda (output)
                  (when (and (allows? buf) (source-unchanged? ctx))
                    (define s1 (if (equal? (bo-get buf "fileformat") "dos")
                                   (string-replace output "\r\n" "\n")
                                   output))
                    (define s2 (if (and (bo-get buf "bomb") (starts-with? s1 "\xef\xbb\xbf"))
                                   (substring s1 3 (string-length s1))
                                   s1))
                    (open-git-diff! buf win (state-call 'records s2 "\n") (hash-ref ctx "filetype"))))))))
      (hash "desc" (string-append "Diff against " rev " (:q to close)"))))
  '(("gd" . ":") ("gD" . "HEAD:")))

;; =========================================
;; ======== GIT: LINE CHANGE SIGNS =======
;; =========================================

(define *git-signs-ns* (nvim_create_namespace "nopack-git-signs"))
(define *git-sign-versions* (box (hash)))
(define *git-sign-timers* (box (hash)))
(define *git-sign-changes* (box (hash)))
(define *git-sign-rendered* (box (hash)))
(define *git-base-cache* (box (hash)))

(state-set! 'git-signs *git-signs-ns*)

(define (git-index-stamp root)
  (define (abs-path p)
    (if (or (starts-with? p "/") (starts-with? p "\\")
            (and (>= (string-length p) 3) (equal? (substring p 1 2) ":")))
        p
        (string-append root "/" p)))
  (define env-idx (env-get "GIT_INDEX_FILE"))
  (define index-path
    (if env-idx
        (abs-path env-idx)
        (let* ([gitdir (string-append root "/.git")]
               [info (uv-fs-stat gitdir)])
          (if (and info (equal? (hash-try-get info "type") "file"))
              (let ([lines (with-handler (lambda (_e) '()) (fn-call "readfile" gitdir "" 1))])
                (if (and (not (null? lines)) (starts-with? (car lines) "gitdir: "))
                    (string-append (abs-path (substring (car lines) 8 (string-length (car lines)))) "/index")
                    #f))
              (string-append gitdir "/index")))))
  (if (not index-path)
      #f
      (let ([info (uv-fs-stat index-path)])
        (if (not info)
            (string-append index-path ":missing")
            (string-join
              (list index-path
                    (number->string (hash-ref info "dev"))
                    (number->string (hash-ref info "ino"))
                    (number->string (hash-ref info "size"))
                    (number->string (hash-ref (hash-ref info "mtime") "sec"))
                    (number->string (hash-ref (hash-ref info "mtime") "nsec"))
                    (number->string (hash-ref (hash-ref info "ctime") "sec"))
                    (number->string (hash-ref (hash-ref info "ctime") "nsec")))
              ":")))))

(define (git-hunk-rows buf)
  (define marks (nvim_buf_get_extmarks buf *git-signs-ns* 0 -1 (hash)))
  (let loop ([xs marks] [prev #f] [acc '()])
    (if (null? xs)
        (reverse acc)
        (let ([r (list-ref (car xs) 1)])
          (if (or (not prev) (> r (+ prev 1)))
              (loop (cdr xs) r (cons r acc))
              (loop (cdr xs) r acc))))))

(define (navigate-git-hunk! next?)
  (define rows (git-hunk-rows (nvim_get_current_buf)))
  (if (null? rows)
      (notify "No Git changes in this buffer")
      (let* ([cur (- (vector-ref (nvim_win_get_cursor 0) 0) 1)]
             [target
              (if next?
                  (or (let loop ([xs rows])
                        (cond [(null? xs) #f]
                              [(> (car xs) cur) (car xs)]
                              [else (loop (cdr xs))]))
                      (car rows))
                  (or (let loop ([xs (reverse rows)])
                        (cond [(null? xs) #f]
                              [(< (car xs) cur) (car xs)]
                              [else (loop (cdr xs))]))
                      (last rows)))])
        (nvim_win_set_cursor 0 (vector (+ target 1) 0))
        (cmd "normal! zv"))))

(keymap-set "n" "<leader>gj" (lambda () (navigate-git-hunk! #t)) (hash "desc" "Next Git hunk"))
(keymap-set "n" "<leader>gk" (lambda () (navigate-git-hunk! #f)) (hash "desc" "Previous Git hunk"))

;; =========================================
;; ============= INLINE BLAME ==============
;; =========================================

(define *inline-blame-enabled* (box #f))
(define *inline-blame-ns* (nvim_create_namespace "nopack-inline-blame"))
(define *inline-blame-timer* (box -1))
(define *inline-blame-version* (box 0))
(define *inline-blame-buf* (box #f))
(define *inline-blame-line* (box #f))

(define (clear-inline-blame! buf)
  (when (nvim_buf_is_valid buf)
    (nvim_buf_clear_namespace buf *inline-blame-ns* 0 -1)))

(define (stop-inline-blame!)
  (set-box! *inline-blame-buf* #f)
  (set-box! *inline-blame-line* #f)
  (unless (= (unbox *inline-blame-timer*) -1)
    (fn-call "timer_stop" (unbox *inline-blame-timer*))
    (set-box! *inline-blame-timer* -1))
  (cancel-command! "git-inline-blame"))

(define (refresh-inline-blame! (_tid #f))
  (set-box! *inline-blame-timer* -1)
  (define buf (nvim_get_current_buf))
  (clear-inline-blame! buf)
  (when (and (unbox *inline-blame-enabled*) (allows? buf) (not (bo-get buf "modified")))
    (define file (nvim_buf_get_name buf))
    (define root (and (not (equal? file "")) (state-call 'find-git-root (fs-dirname file))))
    (when (and root (= (fn-call "executable" "git") 1))
      (define line (vector-ref (nvim_win_get_cursor 0) 0))
      (set-box! *inline-blame-version* (+ (unbox *inline-blame-version*) 1))
      (define ver (unbox *inline-blame-version*))
      (run-command!
        "git-inline-blame"
        (list "git" "--no-pager" "blame" "--porcelain"
              "-L" (string-append (number->string line) "," (number->string line))
              "--" file)
        (hash "cwd" root "quiet" #t)
        (lambda (output _lim)
          (when (and (unbox *inline-blame-enabled*)
                     (= (unbox *inline-blame-version*) ver)
                     (= (nvim_get_current_buf) buf)
                     (not (bo-get buf "modified"))
                     (= (vector-ref (nvim_win_get_cursor 0) 0) line))
            (define commit (fn-call "matchstr" output "^\\x\\+"))
            (define raw-author (fn-call "matchstr" output "\nauthor \\zs[^\n]\\+"))
            (define ts-str (fn-call "matchstr" output "\nauthor-time \\zs\\d\\+"))
            (define raw-summary (fn-call "matchstr" output "\nsummary \\zs[^\n]\\+"))
            (define uncommitted? (not (equal? (fn-call "matchstr" commit "^0\\+$") "")))
            (define author (if uncommitted? "Not committed" (if (equal? raw-author "") "Unknown" raw-author)))
            (define date (if (or uncommitted? (equal? ts-str "")) "" (fn-call "strftime" "%Y-%m-%d" (string->number ts-str))))
            (define summary (if uncommitted? "" raw-summary))
            (define parts (filter (lambda (s) (not (equal? s ""))) (list author date summary)))
            (nvim_buf_set_extmark
              buf *inline-blame-ns* (- line 1) 0
              (hash "virt_text" (list (list (string-append "  " (string-join parts " • ")) "Comment"))
                    "virt_text_pos" "eol"
                    "priority" 10))))))))

(define (queue-inline-blame! (delay 150))
  (stop-inline-blame!)
  (when (and (unbox *inline-blame-enabled*) (allows? 0))
    (set-box! *inline-blame-buf* (nvim_get_current_buf))
    (set-box! *inline-blame-line* (vector-ref (nvim_win_get_cursor 0) 0))
    (set-box! *inline-blame-timer* (fn-call "timer_start" delay refresh-inline-blame!))))

(keymap-set
  "n" "<leader>gb"
  (lambda ()
    (set-box! *inline-blame-enabled* (not (unbox *inline-blame-enabled*)))
    (if (unbox *inline-blame-enabled*)
        (queue-inline-blame! 0)
        (begin
          (stop-inline-blame!)
          (for-each clear-inline-blame! (nvim_list_bufs))))
    (notify (string-append "Inline blame: " (if (unbox *inline-blame-enabled*) "on" "off"))))
  (hash "desc" "Toggle inline blame"))

(define *inline-blame-group* (nvim_create_augroup "nopack-inline-blame" (hash "clear" #t)))
(nvim_create_autocmd
  '("CursorMoved" "BufEnter" "BufWritePost" "BufFilePost" "FocusGained" "ShellCmdPost" "TermLeave" "TermClose")
  (hash "group" *inline-blame-group*
        "callback"
        (lambda (args)
          (unless (or (not (unbox *inline-blame-enabled*)) (is-picker-event? args))
            (unless (and (equal? (hash-ref args "event") "CursorMoved")
                         (equal? (unbox *inline-blame-buf*) (hash-ref args "buf"))
                         (equal? (unbox *inline-blame-line*) (vector-ref (nvim_win_get_cursor 0) 0)))
              (queue-inline-blame!))))))
(nvim_create_autocmd
  "User" (hash "group" *inline-blame-group* "pattern" "NopackExternalChange"
               "callback" (lambda (_args) (when (unbox *inline-blame-enabled*) (queue-inline-blame!)))))
(nvim_create_autocmd
  '("TextChanged" "TextChangedI" "BufLeave")
  (hash "group" *inline-blame-group*
        "callback" (lambda (args)
                     (when (unbox *inline-blame-enabled*)
                       (stop-inline-blame!)
                       (clear-inline-blame! (hash-ref args "buf"))))))

;; =========================================
;; ====== SIGN DIFF COMPUTATION + QUEUE ====
;; =========================================

(define (stop-git-sign-timer! buf)
  (stop-timer! (hash-try-get (unbox *git-sign-timers*) buf))
  (set-box! *git-sign-timers* (hash-remove (unbox *git-sign-timers*) buf)))

(define (cancel-git-sign-work! buf)
  (stop-git-sign-timer! buf)
  (cancel-command! (string-append "git-signs:" (number->string buf))))

(define (compute-git-marks base0 current count dos? bom?)
  (define b1 (if dos? (string-replace base0 "\r\n" "\n") base0))
  (define base (if (and bom? (starts-with? b1 "\xef\xbb\xbf")) (substring b1 3 (string-length b1)) b1))
  (define old (split-many base "\n"))
  (if (> (length old) 20001)
      (hash "marks" '() "hunks" '())
      (let* ([hunks (text-diff base current (hash "result_type" "indices" "algorithm" "histogram"))]
             [total-signs (foldl (lambda (h acc) (+ acc (max 1 (list-ref h 3)))) 0 hunks)])
        (if (> total-signs 2000)
            (hash "marks" '() "hunks" '())
            (let ([marks (box '())])
              (for-each
                (lambda (hunk)
                  (define removed (list-ref hunk 1))
                  (define start (list-ref hunk 2))
                  (define added (list-ref hunk 3))
                  (define changed? (and (> removed 0) (> added 0)))
                  (let loop ([off 0])
                    (when (< off (max 1 added))
                      (define txt
                        (cond
                          [(= added 0) "-"]
                          [(and (> removed added) (= off (- added 1))) "~-"]
                          [changed? "~"]
                          [else "+"]))
                      (define hl
                        (cond
                          [(= added 0) "DiffDelete"]
                          [changed? "DiffChange"]
                          [else "DiffAdd"]))
                      (set-box! marks
                                (cons (list (- (max 1 (min count (+ start off))) 1) txt hl)
                                      (unbox marks)))
                      (loop (+ off 1)))))
                hunks)
              (hash "marks" (reverse (unbox marks)) "hunks" hunks))))))

(define (queue-git-signs! buf)
  (when (allows? buf)
    (define ver (gensym))
    (set-box! *git-sign-versions* (hash-insert (unbox *git-sign-versions*) buf ver))
    (define key (string-append "git-signs:" (number->string buf)))
    (cancel-git-sign-work! buf)
    (define (clear-signs!)
      (when (and (equal? (hash-try-get (unbox *git-sign-versions*) buf) ver) (nvim_buf_is_loaded buf))
        (nvim_buf_clear_namespace buf *git-signs-ns* 0 -1)
        (git-actions-clear! buf)))
    (define timer-box (box #f))
    (define timer
      (defer-fn
        (lambda ()
          (when (equal? (hash-try-get (unbox *git-sign-timers*) buf) (unbox timer-box))
            (set-box! *git-sign-timers* (hash-remove (unbox *git-sign-timers*) buf))
            (when (and (equal? (hash-try-get (unbox *git-sign-versions*) buf) ver) (nvim_buf_is_loaded buf))
              (define file (nvim_buf_get_name buf))
              (define limit (* 256 1024))
              (define line-count (nvim_buf_line_count buf))
              (if (or (not (allows? buf))
                      (equal? file "")
                      (= (fn-call "executable" "git") 0)
                      (> line-count 20000)
                      (> (nvim_buf_get_offset buf line-count) limit))
                  (clear-signs!)
                  (let ([root (state-call 'find-git-root (fs-dirname file))])
                    (if (not root)
                        (clear-signs!)
                        (let* ([tick (nvim_buf_get_changedtick buf)]
                               [stamp (git-index-stamp root)]
                               [rendered (hash-try-get (unbox *git-sign-rendered*) buf)])
                          (unless (and stamp rendered
                                       (= (hash-ref rendered "tick") tick)
                                       (equal? (hash-ref rendered "file") file)
                                       (equal? (hash-ref rendered "index") stamp))
                            (define current
                              (string-append (string-join (nvim_buf_get_lines buf 0 -1 #f) "\n")
                                             (if (bo-get buf "endofline") "\n" "")))
                            (define (current?)
                              (and (equal? (hash-try-get (unbox *git-sign-versions*) buf) ver)
                                   (nvim_buf_is_loaded buf)
                                   (= (nvim_buf_get_changedtick buf) tick)
                                   (equal? (nvim_buf_get_name buf) file)
                                   (allows? buf)
                                   (equal? (git-index-stamp root) stamp)))
                            (define (apply-base! base)
                              (when (current?)
                                (if (or (string-contains? base "\x00") (string-contains? current "\x00"))
                                    (clear-signs!)
                                    (schedule
                                      (lambda ()
                                        (when (current?)
                                          (define res
                                            (compute-git-marks
                                              base current (nvim_buf_line_count buf)
                                              (equal? (bo-get buf "fileformat") "dos")
                                              (bo-get buf "bomb")))
                                          (clear-signs!)
                                          (for-each
                                            (lambda (m)
                                              (nvim_buf_set_extmark
                                                buf *git-signs-ns* (list-ref m 0) 0
                                                (hash "sign_text" (list-ref m 1)
                                                      "sign_hl_group" (list-ref m 2)
                                                      "priority" 5)))
                                            (hash-ref res "marks"))
                                          (set-box! *git-sign-rendered*
                                                    (hash-insert (unbox *git-sign-rendered*) buf
                                                                 (hash "tick" tick "file" file "index" stamp)))
                                          (git-actions-render-deleted! buf base (hash-ref res "hunks"))))))))
                            (define cached (hash-try-get (unbox *git-base-cache*) buf))
                            (if (and stamp cached
                                     (equal? (hash-ref cached "file") file)
                                     (equal? (hash-ref cached "root") root)
                                     (equal? (hash-ref cached "index") stamp))
                                (if (hash-ref cached "base")
                                    (apply-base! (hash-ref cached "base"))
                                    (clear-signs!))
                                (run-command!
                                  key
                                  (list "git" "--no-pager" "show"
                                        (string-append ":./" (substring file (+ (string-length root) 1) (string-length file))))
                                  (hash "cwd" root "max_bytes" limit "quiet" #t
                                        "failed" (lambda ()
                                                   (when (current?)
                                                     (set-box! *git-base-cache*
                                                               (hash-insert (unbox *git-base-cache*) buf
                                                                            (hash "file" file "root" root "base" #f "index" stamp)))
                                                     (clear-signs!))))
                                  (lambda (base _lim)
                                    (when (current?)
                                      (set-box! *git-base-cache*
                                                (hash-insert (unbox *git-base-cache*) buf
                                                             (hash "file" file "root" root "base" base "index" stamp)))
                                      (apply-base! base)))))))))))))
        200))
    (set-box! timer-box timer)
    (set-box! *git-sign-timers* (hash-insert (unbox *git-sign-timers*) buf timer))))

(git-actions-setup!
  (lambda (buf)
    (set-box! *git-status-cache* (hash))
    (set-box! *git-sign-rendered* (hash-remove (unbox *git-sign-rendered*) buf))
    (queue-git-signs! buf)
    (refresh-git-status! buf #t)
    (queue-netrw-git!)))

(define (queue-visible-git-signs! (_args #f))
  (define seen (box (hash)))
  (for-each
    (lambda (w)
      (define b (nvim_win_get_buf w))
      (unless (hash-contains? (unbox seen) b)
        (set-box! seen (hash-insert (unbox seen) b #t))
        (queue-git-signs! b)))
    (nvim_list_wins)))

(define *git-signs-group* (nvim_create_augroup "nopack-git-signs" (hash "clear" #t)))
(nvim_create_autocmd
  '("BufEnter" "BufWritePost" "TextChanged" "TextChangedI" "FocusGained" "ShellCmdPost" "TermLeave" "TermClose")
  (hash "group" *git-signs-group*
        "callback"
        (lambda (args)
          (unless (is-picker-event? args)
            (define ev (hash-ref args "event"))
            (define buf (hash-ref args "buf"))
            (define skip?
              (and (or (equal? ev "TextChanged") (equal? ev "TextChangedI"))
                   (let ([tick (nvim_buf_get_changedtick buf)])
                     (if (equal? (hash-try-get (unbox *git-sign-changes*) buf) tick)
                         #t
                         (begin (set-box! *git-sign-changes* (hash-insert (unbox *git-sign-changes*) buf tick)) #f)))))
            (unless skip?
              (if (or (equal? ev "FocusGained") (equal? ev "ShellCmdPost")
                      (equal? ev "TermLeave") (equal? ev "TermClose"))
                  (queue-visible-git-signs!)
                  (queue-git-signs! buf)))))))

(nvim_create_autocmd
  "User" (hash "group" *git-signs-group* "pattern" "NopackExternalChange" "callback" queue-visible-git-signs!))

(nvim_create_autocmd
  '("BufUnload" "BufWipeout")
  (hash "group" *git-signs-group*
        "callback" (lambda (args)
                     (define b (hash-ref args "buf"))
                     (set-box! *git-sign-changes* (hash-remove (unbox *git-sign-changes*) b))
                     (cancel-git-sign-work! b)
                     (set-box! *git-sign-versions* (hash-remove (unbox *git-sign-versions*) b))
                     (set-box! *git-base-cache* (hash-remove (unbox *git-base-cache*) b))
                     (set-box! *git-sign-rendered* (hash-remove (unbox *git-sign-rendered*) b)))))

(nvim_create_autocmd
  "User"
  (hash "group" *git-signs-group*
        "pattern" "NopackCancel"
        "callback" (lambda (_args)
                     (unless (= (unbox *netrw-git-timer*) -1)
                       (fn-call "timer_stop" (unbox *netrw-git-timer*))
                       (set-box! *netrw-git-timer* -1))
                     (stop-inline-blame!)
                     (set-box! *inline-blame-version* (+ (unbox *inline-blame-version*) 1))
                     (for-each stop-git-sign-timer! (hash-keys->list (unbox *git-sign-timers*)))
                     (set-box! *git-sign-versions* (hash)))))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackBufferRestricted"
        "callback" (lambda (args)
                     (define buf (hash-ref (hash-ref args "data") "buf"))
                     (cancel-git-sign-work! buf)
                     (set-box! *git-sign-versions* (hash-remove (unbox *git-sign-versions*) buf))
                     (set-box! *git-sign-rendered* (hash-remove (unbox *git-sign-rendered*) buf))
                     (when (nvim_buf_is_loaded buf)
                       (nvim_buf_clear_namespace buf *git-signs-ns* 0 -1))
                     (when (equal? (unbox *inline-blame-buf*) buf)
                       (stop-inline-blame!)
                       (set-box! *inline-blame-version* (+ (unbox *inline-blame-version*) 1))
                       (clear-inline-blame! buf)))))
