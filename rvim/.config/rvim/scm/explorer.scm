;; 1:1 Steel port of: nvim/.config/nvim/lua/explorer.lua
;; Equivalence:
;; - Native editable directory buffers (`flash://<root>`, `filetype=flash-explorer`,
;;   `buftype=acwrite`) with concealed `/<id> ` row IDs preserving identity across `yy`/`p`.
;; - Transactional `:w` (`plan` -> `.flash-XXXXXX` staging -> atomic `uv-fs-rename` ->
;;   rollback on failure) for create, rename, copy, and delete operations; preserves
;;   open buffer names and split layouts.
;; - Provides `explorer-is-buffer?`, `explorer-root`, `explorer-path`, `explorer-open`,
;;   `explorer-close`, `explorer-refresh`, plus `'sidebar-width` and `'fix-sidebar-width` on `state`.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/fs")
(require "rvim/uv")
(require "rvim/ui")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "jobs")
(require "state")

(provide explorer-is-buffer?
         explorer-root
         explorer-path
         explorer-open
         explorer-close
         explorer-refresh)

(define (sidebar-width)
  (max 20 (min 40 (floor (* (go-get "columns") 0.25)))))

(define (fix-sidebar-width! win)
  (define saved (or (w-get win "nopack_sidebar_width") (hash "value" (wo-get win "winfixwidth"))))
  (w-set win "nopack_sidebar_width" (hash-insert saved "buf" (nvim_win_get_buf win)))
  (wo-local-set win "winfixwidth" #t))

(state-set! 'sidebar-width sidebar-width)
(state-set! 'fix-sidebar-width fix-sidebar-width!)

(nvim_create_autocmd
  "BufWinEnter"
  (hash "group" (nvim_create_augroup "nopack-sidebar-width" (hash "clear" #t))
        "callback" (lambda (args)
                     (define saved (w-get 0 "nopack_sidebar_width"))
                     (when (and saved (not (= (hash-ref saved "buf") (hash-ref args "buf"))))
                       (wo-local-set 0 "winfixwidth" (hash-ref saved "value"))
                       (w-set 0 "nopack_sidebar_width" #f)))))

(g-set "loaded_netrwPlugin" 1)
(g-set "loaded_nvim_dir_plugin" 1)

(define *states* (box (hash)))
(define *entries* (box (hash)))
(define *ids* (box (hash)))
(define *next-id* (box 0))
(define *filters* (box (hash "hidden" #t "show_ignored" #t)))
(define *copied-ids* (box (hash)))
(define *group* (nvim_create_augroup "flash-directory" (hash "clear" #t)))
(define *saving* (box #f))
(define *locks* (box #f))
(define *tree-ns* (nvim_create_namespace "flash-directory-tree"))
(define *window-options* (box (hash)))
(define *ui-options* '("conceallevel" "concealcursor" "wrap" "winbar" "foldenable" "spell" "cursorcolumn" "list"))

(define (close-help! buf)
  (define st (hash-try-get (unbox *states*) buf))
  (define help (and st (unbox (hash-ref st "help"))))
  (when help
    (set-box! (hash-ref st "help") #f)
    (define hwin (hash-ref help "win"))
    (when (and (nvim_win_is_valid hwin) (= (nvim_win_get_buf hwin) (hash-ref help "buf")))
      (define focused (= (nvim_get_current_win) hwin))
      (nvim_win_close hwin #t)
      (when (and focused (nvim_win_is_valid (hash-ref help "owner")))
        (nvim_set_current_win (hash-ref help "owner"))))))

(define (restore-window! win saved)
  (when saved
    (for-each (lambda (opt) (wo-local-set win opt (hash-ref saved opt)))
              (hash-keys->list saved))))

(define (focus-editor-restoring!)
  (define origin (nvim_get_current_win))
  (define prev (foldl (lambda (w acc) (hash-insert acc w #t)) (hash) (nvim_tabpage_list_wins 0)))
  (state-call 'focus-editor)
  (define win (nvim_get_current_win))
  (unless (hash-contains? prev win)
    (restore-window! win (hash-try-get (unbox *window-options*) origin))))

(define (encode-name name)
  (define s1 (vector-ref (string/gsub name "%%" "%%25") 0))
  (define lead (or (string/match s1 "^ +") ""))
  (define s2
    (if (> (string-length lead) 0)
        (string-append (apply string-append (build-list (string-length lead) (lambda (_i) "%20")))
                       (substring s1 (string-length lead) (string-length s1)))
        s1))
  (define s3 (string-replace s2 "\n" "%0A"))
  (define s4 (string-replace s3 "\r" "%0D"))
  (string-replace s4 "\t" "%09"))

(define (decode-name name)
  (let loop ([pos 1] [acc '()])
    (define found (string/find name "%%(%x%x)" pos))
    (if (not found)
        (apply string-append (reverse (cons (substring name (- pos 1) (string-length name)) acc)))
        (let ([s (vector-ref found 0)]
              [e (vector-ref found 1)]
              [hex (vector-ref found 2)])
          (loop (+ e 1)
                (cons (string (integer->char (string->number hex 16)))
                      (cons (substring name (- pos 1) (- s 1)) acc)))))))

(define (stat-key st)
  (and st
       (string-append (hash-ref st "type") ":"
                      (number->string (hash-ref st "dev")) ":"
                      (number->string (hash-ref st "ino")))))

(define (within? path dir)
  (or (equal? path dir) (starts-with? path (string-append dir "/"))))

(define (buffer-path buf parents-box)
  (define st (hash-try-get (unbox *states*) buf))
  (if st
      (unbox (hash-ref st "root"))
      (let ([name (nvim_buf_get_name buf)])
        (if (and (not (equal? name "")) (equal? (bo-get buf "buftype") ""))
            (let* ([dir (fs-dirname name)]
                   [cached (hash-try-get (unbox parents-box) dir)]
                   [parent
                    (if (not (equal? cached #f))
                        cached
                        (let loop ([anc dir] [suffix ""])
                          (define resolved (uv-fs-realpath anc))
                          (cond
                            [resolved
                             (define p (string-append resolved suffix))
                             (set-box! parents-box (hash-insert (unbox parents-box) dir p))
                             p]
                            [(equal? (fs-dirname anc) anc)
                             (set-box! parents-box (hash-insert (unbox parents-box) dir 'none))
                             'none]
                            [else
                             (loop (fs-dirname anc)
                                   (string-append "/" (fs-basename anc) suffix))])))])
              (if (string? parent)
                  (fs-joinpath parent (fs-basename name))
                  name))
            name))))

(define (remove-recursive! path)
  (define st (uv-fs-lstat path))
  (unless st (error! (string-append "Filesystem operation failed: " path)))
  (if (equal? (hash-ref st "type") "directory")
      (begin
        (uv-fs-chmod path (bitwise-ior (modulo (hash-ref st "mode") 4096) 448))
        (for-each
          (lambda (entry) (remove-recursive! (fs-joinpath path (car entry))))
          (uv-fs-scandir path))
        (uv-fs-rmdir path))
      (uv-fs-unlink path)))

(define (copy-recursive! src dst (defer-mode? #f))
  (define st (uv-fs-lstat src))
  (unless st (error! (string-append "Filesystem operation failed: " src)))
  (define t (hash-ref st "type"))
  (cond
    [(equal? t "directory")
     (define mode (modulo (hash-ref st "mode") 4096))
     (uv-fs-mkdir dst (bitwise-ior mode 448))
     (for-each
       (lambda (entry) (copy-recursive! (fs-joinpath src (car entry)) (fs-joinpath dst (car entry))))
       (uv-fs-scandir src))
     (unless defer-mode?
       (uv-fs-chmod dst mode))
     mode]
    [(equal? t "link")
     (uv-fs-symlink (uv-fs-readlink src) dst)
     #f]
    [(equal? t "file")
     (uv-fs-copyfile src dst 1)
     #f]
    [else (error! (string-append "Cannot copy special file: " src))]))

(define (explorer-is-buffer? buf)
  (equal? (bo-get buf "filetype") "flash-explorer"))

(define (explorer-root buf)
  (define st (hash-try-get (unbox *states*) buf))
  (if st (unbox (hash-ref st "root")) ""))

(define (tree-rows buf)
  (define st (hash-ref (unbox *states*) buf))
  (define tick (nvim_buf_get_changedtick buf))
  (if (equal? (unbox (hash-ref st "tick")) tick)
      (values (unbox (hash-ref st "rows")) (unbox (hash-ref st "row_error")))
      (let ([lines (nvim_buf_get_lines buf 0 -1 #f)]
            [rows (box (hash))]
            [paths (box (hash))]
            [parents (box (hash 0 (unbox (hash-ref st "root"))))]
            [failure (box #f)])
        (let loop ([xs lines] [idx 1])
          (when (and (not (null? xs)) (not (unbox failure)))
            (define line (car xs))
            (unless (equal? line "")
              (define m (string/match line "^/(%d+) (.*)$"))
              (define has-id (and (vector? m) (>= (vector-length m) 2)))
              (define id (and has-id (string->number (vector-ref m 0))))
              (define label (if has-id (vector-ref m 1) line))
              (define sp-pair (string/match label "^( *)(.*)$"))
              (define spaces (if (vector? sp-pair) (vector-ref sp-pair 0) ""))
              (define raw-name (if (vector? sp-pair) (vector-ref sp-pair 1) label))
              (define sp-len (string-length spaces))
              (define depth (floor (/ sp-len 2)))
              (define dir? (ends-with? raw-name "/"))
              (define name (decode-name (if dir? (substring raw-name 0 (- (string-length raw-name) 1)) raw-name)))
              (define parent-dir (hash-try-get (unbox parents) depth))
              (cond
                [(or (not (= (modulo sp-len 2) 0)) (not parent-dir))
                 (set-box! failure
                           (string-append "Invalid tree indentation at row " (number->string idx)
                                          "; collapse folders before deleting their row"))]
                [(or (equal? name "")
                     (starts-with? name "/")
                     (string/find name "[\\%z]")
                     (string-contains? name "//")
                     (let cloop ([parts (vector->list (string/gmatch name "[^/]+"))])
                       (cond [(null? parts) #f]
                             [(or (equal? (car parts) ".") (equal? (car parts) "..")) #t]
                             [else (cloop (cdr parts))])))
                 (set-box! failure (string-append "Use a relative path without '.' or '..': " label))]
                [else
                 (define target (fs-joinpath parent-dir name))
                 (set-box! rows (hash-insert (unbox rows) idx
                                             (hash "id" id "target" target "directory" dir? "depth" depth)))
                 (set-box! paths (hash-insert (unbox paths) target idx))
                 (set-box! parents
                           (foldl (lambda (lvl acc) (if (> lvl depth) (hash-remove acc lvl) acc))
                                  (unbox parents)
                                  (hash-keys->list (unbox parents))))
                 (when dir?
                   (set-box! parents (hash-insert (unbox parents) (+ depth 1) target)))]))
            (loop (cdr xs) (+ idx 1))))
        (set-box! (hash-ref st "tick") tick)
        (set-box! (hash-ref st "rows") (unbox rows))
        (set-box! (hash-ref st "path_rows") (unbox paths))
        (set-box! (hash-ref st "row_error") (unbox failure))
        (values (unbox rows) (unbox failure)))))

(define (explorer-path buf index)
  (if (not (hash-contains? (unbox *states*) buf))
      #f
      (let-values ([(rows _err) (tree-rows buf)])
        (define r (hash-try-get rows index))
        (and r (hash-ref r "target")))))

(define (draw-tree! buf first last)
  (define finish (if (= last (nvim_buf_line_count buf)) -1 last))
  (nvim_buf_clear_namespace buf *tree-ns* first finish)
  (define-values (rows _err) (tree-rows buf))
  (define st (hash-ref (unbox *states*) buf))
  (define ignored (unbox (hash-ref st "ignored")))
  (let loop ([xs (nvim_buf_get_lines buf first last #f)] [off 0])
    (unless (null? xs)
      (define line (car xs))
      (define label (or (string/match line "^/%d+ (.*)$") line))
      (define prefix (string-length (or (string/match line "^/%d+ ") "")))
      (define spaces (or (string/match label "^ *") ""))
      (define sp-len (string-length spaces))
      (define depth (floor (/ sp-len 2)))
      (define idx (+ first off))
      (when (> depth 0)
        (nvim_buf_set_extmark
          buf *tree-ns* idx prefix
          (hash "virt_text" (list (list (apply string-append (build-list depth (lambda (_i) "│ "))) "NonText"))
                "virt_text_pos" "overlay" "right_gravity" #f)))
      (define row (hash-try-get rows (+ idx 1)))
      (define dot? (and (< sp-len (string-length label)) (equal? (substring label sp-len (+ sp-len 1)) ".")))
      (when (or dot? (and row (hash-try-get ignored (hash-ref row "target"))))
        (nvim_buf_set_extmark
          buf *tree-ns* idx (+ prefix sp-len)
          (hash "end_col" (string-length line) "hl_group" "Comment" "priority" 100)))
      (loop (cdr xs) (+ off 1)))))

(define (select-file! buf)
  (define st (hash-ref (unbox *states*) buf))
  (define reveal (unbox (hash-ref st "reveal")))
  (unless (or (not reveal) (unbox (hash-ref st "filtering")) (bo-get buf "modified"))
    (define wins (fn-call "win_findbuf" buf))
    (unless (null? wins)
      (tree-rows buf)
      (define idx (hash-try-get (unbox (hash-ref st "path_rows")) reveal))
      (when idx
        (define line (car (nvim_buf_get_lines buf (- idx 1) idx #f)))
        (define col (string-length (or (string/match line "^/%d+ *") "")))
        (for-each
          (lambda (w)
            (define cur (nvim_win_get_cursor w))
            (unless (and (= (vector-ref cur 0) idx) (= (vector-ref cur 1) col))
              (nvim_win_set_cursor w (vector idx col))))
          wins))
      (set-box! (hash-ref st "reveal") #f))))

(define (render-explorer! buf)
  (define st (hash-ref (unbox *states*) buf))
  (unless (unbox (hash-ref st "filtering"))
    (define tick (nvim_buf_get_changedtick buf))
    (define lines-box (box '()))
    (define orig-box (box (hash)))
    (define unchecked-box (box '()))
    (define (visit! dir depth git-paths?)
      (define children-map (unbox (hash-ref st "children")))
      (define listing
        (or (hash-try-get children-map dir)
            (let* ([raw (uv-fs-scandir dir)]
                   [items
                    (filter-map
                      (lambda (pair)
                        (define name (car pair))
                        (if (or (unbox (hash-ref st "hidden")) (not (starts-with? name ".")))
                            (let* ([path (fs-joinpath dir name)]
                                   [lstat (uv-fs-lstat path)]
                                   [t (hash-ref lstat "type")]
                                   [is-dir (or (equal? t "directory")
                                               (and (equal? t "link") (= (fn-call "isdirectory" path) 1)))])
                              (hash "name" name "path" path "key" (stat-key lstat)
                                    "size" (hash-ref lstat "size")
                                    "mtime" (hash-ref (hash-ref lstat "mtime") "sec")
                                    "directory" is-dir "symlink" (equal? t "link")))
                            #f))
                      raw)]
                   [sort-key (unbox (hash-ref st "sort"))]
                   [rev? (unbox (hash-ref st "reverse"))]
                   [sorted
                    (sort items
                          (lambda (a b)
                            (if (not (equal? (hash-ref a "directory") (hash-ref b "directory")))
                                (hash-ref a "directory")
                                (let* ([av0 (hash-ref a sort-key)]
                                       [bv0 (hash-ref b sort-key)]
                                       [av (if (equal? av0 bv0) (hash-ref a "name") av0)]
                                       [bv (if (equal? av0 bv0) (hash-ref b "name") bv0)])
                                  (if (string? av)
                                      (if rev? (string>? av bv) (string<? av bv))
                                      (if rev? (> av bv) (< av bv)))))))])
              (set-box! (hash-ref st "children") (hash-insert children-map dir sorted))
              sorted)))
      (for-each
        (lambda (entry)
          (define path (hash-ref entry "path"))
          (define ignored-map (unbox (hash-ref st "ignored")))
          (when (or (unbox (hash-ref st "show_ignored")) (not (hash-try-get ignored-map path)))
            (when (and git-paths? (not (hash-contains? ignored-map path)))
              (set-box! unchecked-box (cons path (unbox unchecked-box))))
            (define id
              (or (hash-try-get (unbox *ids*) path)
                  (let ([nid (+ (unbox *next-id*) 1)])
                    (set-box! *next-id* nid)
                    (set-box! *ids* (hash-insert (unbox *ids*) path nid))
                    nid)))
            (define with-id (hash-insert entry "id" id))
            (set-box! *entries* (hash-insert (unbox *entries*) id with-id))
            (set-box! orig-box (hash-insert (unbox orig-box) id with-id))
            (set-box! (hash-ref st "known") (hash-insert (unbox (hash-ref st "known")) id #t))
            (set-box! lines-box
                      (cons (string-append "/" (number->string id) " "
                                           (make-string (* depth 2) #\space)
                                           (encode-name (hash-ref entry "name"))
                                           (if (hash-ref entry "directory") "/" ""))
                            (unbox lines-box)))
            (when (and (hash-ref entry "directory")
                       (hash-try-get (unbox (hash-ref st "expanded")) path))
              (visit! path (+ depth 1) (and git-paths? (not (hash-ref entry "symlink")))))))
        listing))
    (visit! (unbox (hash-ref st "root")) 0 #t)
    (define unchecked (reverse (unbox unchecked-box)))
    (define deferred #f)
    (unless (null? unchecked)
      (define git-root (state-call 'find-git-root (unbox (hash-ref st "root"))))
      (if (and git-root (= (fn-call "executable" "git") 1))
          (begin
            (unless (unbox (hash-ref st "show_ignored"))
              (set-box! (hash-ref st "filtering") #t)
              (set! deferred #t))
            (define (finish! output)
              (when (equal? (hash-try-get (unbox *states*) buf) st)
                (set-box! (hash-ref st "filtering") #f)
                (if (not output)
                    (set-box! (hash-ref st "show_ignored") #t)
                    (begin
                      (for-each (lambda (p) (set-box! (hash-ref st "ignored")
                                                      (hash-insert (unbox (hash-ref st "ignored")) p #f)))
                                unchecked)
                      (for-each (lambda (p)
                                  (unless (equal? p "")
                                    (set-box! (hash-ref st "ignored")
                                              (hash-insert (unbox (hash-ref st "ignored")) p #t))))
                                (split-many output "\x00"))))
                (when (= (nvim_buf_get_changedtick buf) tick)
                  (if (unbox (hash-ref st "show_ignored"))
                      (draw-tree! buf 0 (nvim_buf_line_count buf))
                      (render-explorer! buf)))))
            (run-command!
              (string-append "explorer-ignore:" (number->string buf))
              '("git" "check-ignore" "-z" "--stdin")
              (hash "cwd" git-root
                    "stdin" (string-append (string-join unchecked "\x00") "\x00")
                    "no_match" #t
                    "failed" (lambda () (finish! #f)))
              (lambda (out _lim) (finish! out))))
          (set-box! (hash-ref st "show_ignored") #t)))
    (unless deferred
      (set-box! (hash-ref st "originals") (unbox orig-box))
      (define lines (let ([ls (reverse (unbox lines-box))]) (if (null? ls) '("") ls)))
      (define changed? (not (equal? lines (nvim_buf_get_lines buf 0 -1 #f))))
      (when changed?
        (define ul (bo-get buf "undolevels"))
        (define mod (bo-get buf "modifiable"))
        (bo-set buf "modifiable" #t)
        (bo-set buf "undolevels" -1)
        (set-box! (hash-ref st "rendering") #t)
        (nvim_buf_set_lines buf 0 -1 #f lines)
        (set-box! (hash-ref st "rendering") #f)
        (bo-set buf "undolevels" ul)
        (bo-set buf "modifiable" mod))
      (bo-set buf "modified" #f)
      (when changed?
        (draw-tree! buf 0 (length lines))
        (nvim_exec_autocmds "User" (hash "pattern" "NopackExplorerChanged" "modeline" #f)))
      (select-file! buf))))

(define (refresh-explorer! buf (files #f))
  (define st (hash-ref (unbox *states*) buf))
  (if files
      (let ([changed (box #f)])
        (for-each
          (lambda (path)
            (define dir (fs-dirname path))
            (when (hash-contains? (unbox (hash-ref st "children")) dir)
              (set-box! (hash-ref st "children") (hash-remove (unbox (hash-ref st "children")) dir))
              (set-box! changed #t))
            (set-box! (hash-ref st "ignored") (hash-remove (unbox (hash-ref st "ignored")) path)))
          (hash-keys->list files))
        (when (unbox changed) (render-explorer! buf)))
      (begin
        (set-box! (hash-ref st "children") (hash))
        (set-box! (hash-ref st "ignored") (hash))
        (render-explorer! buf))))

(define (reveal-file! buf file)
  (define st (hash-ref (unbox *states*) buf))
  (if (or (equal? file "") (bo-get buf "modified"))
      #f
      (let* ([parent0 (uv-fs-realpath (fs-dirname file))]
             [full (if parent0 (fs-joinpath parent0 (fs-basename file)) file)]
             [root (unbox (hash-ref st "root"))]
             [prefix (string-append (vector-ref (string/gsub root "/+$" "") 0) "/")])
        (if (not (starts-with? full prefix))
            #f
            (begin
              (set-box! (hash-ref st "reveal") full)
              (let loop ([p parent0] [expanded? #f])
                (if (or (not p) (equal? p root))
                    expanded?
                    (let ([was (hash-try-get (unbox (hash-ref st "expanded")) p)])
                      (unless was
                        (set-box! (hash-ref st "expanded")
                                  (hash-insert (unbox (hash-ref st "expanded")) p #t)))
                      (loop (fs-dirname p) (or expanded? (not was)))))))))))

(define (plan-operations buf)
  (define st (hash-ref (unbox *states*) buf))
  (define-values (parsed failure) (tree-rows buf))
  (when failure (error! failure))
  (define targets (box (hash)))
  (define rows (box '()))
  (define origs (unbox (hash-ref st "originals")))
  (define line-count (nvim_buf_line_count buf))
  (let loop ([idx 1])
    (when (<= idx line-count)
      (define pr (hash-try-get parsed idx))
      (when pr
        (define id (hash-try-get pr "id"))
        (define src (and id (or (hash-try-get origs id) (hash-try-get (unbox *entries*) id))))
        (when (and id (not src)) (error! (string-append "Unknown file ID: " (number->string id))))
        (when (and src (not (equal? (hash-ref src "directory") (hash-ref pr "directory"))))
          (error! "Keep the directory '/' marker"))
        (define target (hash-ref pr "target"))
        (when (hash-contains? (unbox targets) target)
          (error! (string-append "Duplicate name; rename pasted entries before :w: " target)))
        (set-box! targets (hash-insert (unbox targets) target #t))
        (set-box! rows (cons (hash-insert pr "source" src) (unbox rows))))
      (loop (+ idx 1))))
  (define row-list (reverse (unbox rows)))
  (define retained
    (box (foldl (lambda (r acc)
                  (define src (hash-try-get r "source"))
                  (if (and src (equal? (hash-ref src "path") (hash-ref r "target")))
                      (hash-insert acc (hash-ref r "id") #t)
                      acc))
                (hash)
                row-list)))
  (define ops (box '()))
  (for-each
    (lambda (r)
      (define src (hash-try-get r "source"))
      (if src
          (unless (equal? (hash-ref src "path") (hash-ref r "target"))
            (define id (hash-ref r "id"))
            (define kind (if (and (hash-contains? origs id) (not (hash-contains? (unbox retained) id)))
                             "rename" "copy"))
            (set-box! retained (hash-insert (unbox retained) id #t))
            (set-box! ops (cons (hash-insert r "kind" kind) (unbox ops))))
          (set-box! ops (cons (hash-insert r "kind" "create") (unbox ops)))))
    row-list)
  (for-each
    (lambda (id)
      (unless (hash-contains? (unbox retained) id)
        (set-box! ops (cons (hash "kind" "delete" "source" (hash-ref origs id)) (unbox ops)))))
    (hash-keys->list origs))
  (define raw-ops (reverse (unbox ops)))
  (define source-dirs
    (foldl (lambda (op acc)
             (define src (hash-try-get op "source"))
             (if (and src (hash-ref src "directory")) (hash-insert acc (hash-ref src "path") op) acc))
           (hash) raw-ops))
  (define target-dirs
    (foldl (lambda (op acc)
             (if (and (hash-try-get op "directory") (hash-try-get op "target"))
                 (hash-insert acc (hash-ref op "target") op)
                 acc))
           (hash) raw-ops))
  (define (find-ancestor path dirs)
    (let loop ([cur path] [p (fs-dirname path)])
      (cond
        [(equal? p cur) #f]
        [(hash-contains? dirs p) (hash-ref dirs p)]
        [else (loop p (fs-dirname p))])))
  (define filtered
    (filter-map
      (lambda (op)
        (define src (hash-try-get op "source"))
        (define tgt (hash-try-get op "target"))
        (define kind (hash-ref op "kind"))
        (define parent (and src (find-ancestor (hash-ref src "path") source-dirs)))
        (define covered?
          (and parent
               (or (and (equal? (hash-ref parent "kind") "delete") (equal? kind "delete"))
                   (and (equal? (hash-ref parent "kind") kind)
                        (or (equal? kind "rename") (equal? kind "copy"))
                        (equal? tgt
                                (string-append
                                  (hash-ref parent "target")
                                  (substring (hash-ref src "path")
                                             (string-length (hash-ref (hash-ref parent "source") "path"))
                                             (string-length (hash-ref src "path")))))))))
        (define tgt-parent (and tgt (find-ancestor tgt target-dirs)))
        (define mov-parent (and tgt (find-ancestor tgt source-dirs)))
        (when (or (and parent (not covered?))
                  (and tgt-parent (not (equal? (hash-ref tgt-parent "kind") "create")) (not covered?))
                  (and mov-parent (not (equal? (hash-ref mov-parent "kind") "copy")) (not covered?)))
          (error! "Save folder changes separately from edits inside it"))
        (and (not covered?) op))
      raw-ops))
  (define root (unbox (hash-ref st "root")))
  (define dirs-seen (box (hash)))
  (define additions (box '()))
  (for-each
    (lambda (op)
      (define tgt (hash-try-get op "target"))
      (when tgt
        (let loop ([p (fs-dirname tgt)])
          (unless (or (equal? p root) (hash-contains? (unbox dirs-seen) p))
            (define pst (uv-fs-stat p))
            (cond
              [pst
               (unless (equal? (hash-ref pst "type") "directory")
                 (error! (string-append "Parent is not a folder: " p)))
               (set-box! dirs-seen (hash-insert (unbox dirs-seen) p #t))]
              [(and (hash-contains? (unbox targets) p) (not (hash-contains? target-dirs p)))
               (error! (string-append "Parent is planned as a file: " p))]
              [else
               (set-box! dirs-seen (hash-insert (unbox dirs-seen) p #t))
               (unless (hash-contains? target-dirs p)
                 (set-box! additions (cons (hash "kind" "create" "directory" #t "target" p) (unbox additions))))
               (loop (fs-dirname p))])))))
    filtered)
  (define sorted-ops
    (sort (append filtered (unbox additions))
          (lambda (a b)
            (define ap (or (hash-try-get a "target") (hash-ref (hash-ref a "source") "path")))
            (define bp (or (hash-try-get b "target") (hash-ref (hash-ref b "source") "path")))
            (if (= (string-length ap) (string-length bp))
                (string<? ap bp)
                (< (string-length ap) (string-length bp))))))
  (if (null? sorted-ops)
      (values '() '())
      (let* ([parents-box (box (hash))]
             [buffers
              (map (lambda (loaded)
                     (hash "id" loaded
                           "name" (box (buffer-path loaded parents-box))
                           "modified" (box (bo-get loaded "modified"))
                           "directory" (hash-contains? (unbox *states*) loaded)))
                   (nvim_list_bufs))])
        (for-each
          (lambda (op)
            (define src (hash-try-get op "source"))
            (define tgt (hash-try-get op "target"))
            (define kind (hash-ref op "kind"))
            (when (and src (not (equal? (stat-key (uv-fs-lstat (hash-ref src "path"))) (hash-ref src "key"))))
              (error! (string-append "File changed externally; refresh before editing: " (hash-ref src "path"))))
            (when tgt
              (for-each (lambda (b)
                          (when (within? (unbox (hash-ref b "name")) tgt)
                            (error! (string-append "Destination already has an open buffer: " tgt))))
                        buffers)
              (when (uv-fs-lstat tgt)
                (error! (string-append "Destination already exists: " tgt))))
            (when (and src tgt (starts-with? tgt (string-append (hash-ref src "path") "/")))
              (error! "Cannot copy a directory inside itself"))
            (when (or (equal? kind "delete") (equal? kind "rename"))
              (for-each (lambda (b)
                          (define bname (unbox (hash-ref b "name")))
                          (when (and (unbox (hash-ref b "modified"))
                                     (or (equal? kind "delete") (hash-ref b "directory"))
                                     (within? bname (hash-ref src "path")))
                            (error! (string-append "Save or discard modified buffer first: " bname))))
                        buffers)))
          sorted-ops)
        (values sorted-ops buffers))))

(define (summarize-ops ops)
  (string-join
    (map (lambda (op)
           (define src (hash-try-get op "source"))
           (define tgt (hash-try-get op "target"))
           (string-append (hash-ref op "kind") " "
                          (if src (hash-ref src "path") "")
                          (if tgt (string-append " -> " tgt) "")))
         ops)
    "\n"))

(define (commit-explorer! buf (confirmed? #f))
  (define-values (ops buffers) (plan-operations buf))
  (cond
    [(null? ops)
     (bo-set buf "modified" #f)
     #t]
    [(and (not confirmed?)
          (not (= (fn-call "confirm" (summarize-ops ops) "&Apply\n&Cancel" 2) 1)))
     #f]
    [else
     (for-each
       (lambda (op)
         (define kind (hash-ref op "kind"))
         (when (or (equal? kind "rename") (equal? kind "copy"))
           (define spath (hash-ref (hash-ref op "source") "path"))
           (for-each
             (lambda (b)
               (define bname (unbox (hash-ref b "name")))
               (when (and (unbox (hash-ref b "modified")) (not (hash-ref b "directory")) (within? bname spath))
                 (nvim_buf_call (hash-ref b "id") (lambda () (cmd "silent write")))
                 (set-box! (hash-ref b "modified") #f)))
             buffers)))
       ops)
     (define stages (box '()))
     (define err-box (box #f))
     (with-handler
       (lambda (e) (set-box! err-box (to-string e)))
       (for-each
         (lambda (op)
           (define src (hash-try-get op "source"))
           (define tgt (hash-try-get op "target"))
           (define kind (hash-ref op "kind"))
           (define parent
             (let loop ([p (fs-dirname (or tgt (hash-ref src "path")))])
               (if (uv-fs-stat p) p (loop (fs-dirname p)))))
           (define stage-dir (uv-fs-mkdtemp (string-append parent "/.flash-XXXXXX")))
           (define item-path (fs-joinpath stage-dir "item"))
           (define mode #f)
           (cond
             [(equal? kind "copy")
              (set! mode (copy-recursive! (hash-ref src "path") item-path #t))]
             [(equal? kind "create")
              (if (hash-try-get op "directory")
                  (uv-fs-mkdir item-path 493)
                  (let ([fd (uv-fs-open item-path "wx" 420)]) (uv-fs-close fd)))])
           (set-box! stages
                     (append (unbox stages)
                             (list (hash "op" op "stage" stage-dir "item" item-path "mode" mode
                                         "moved" (box #f) "installed" (box #f) "rollback_ok" (box #t))))))
         ops)
       (for-each
         (lambda (s)
           (define op (hash-ref s "op"))
           (define kind (hash-ref op "kind"))
           (when (or (equal? kind "rename") (equal? kind "delete"))
             (uv-fs-rename (hash-ref (hash-ref op "source") "path") (hash-ref s "item"))
             (set-box! (hash-ref s "moved") #t)))
         (unbox stages))
       (for-each
         (lambda (s)
           (define tgt (hash-try-get (hash-ref s "op") "target"))
           (when tgt
             (when (uv-fs-lstat tgt) (error! (string-append "Destination appeared during save: " tgt)))
             (uv-fs-rename (hash-ref s "item") tgt)
             (set-box! (hash-ref s "installed") #t)))
         (unbox stages)))
     (when (unbox err-box)
       (define recovery (box '()))
       (for-each
         (lambda (s)
           (define op (hash-ref s "op"))
           (define ok #t)
           (when (unbox (hash-ref s "installed"))
             (set! ok (with-handler (lambda (_e) #f) (uv-fs-rename (hash-ref op "target") (hash-ref s "item")) #t)))
           (when (and ok (unbox (hash-ref s "moved")))
             (define sp (hash-ref (hash-ref op "source") "path"))
             (set! ok (and (not (uv-fs-lstat sp))
                           (with-handler (lambda (_e) #f) (uv-fs-rename (hash-ref s "item") sp) #t))))
           (set-box! (hash-ref s "rollback_ok") ok)
           (unless ok (set-box! recovery (cons (hash-ref s "stage") (unbox recovery)))))
         (reverse (unbox stages)))
       (for-each
         (lambda (s)
           (when (unbox (hash-ref s "rollback_ok"))
             (with-handler
               (lambda (_e) (set-box! recovery (cons (hash-ref s "stage") (unbox recovery))))
               (remove-recursive! (hash-ref s "stage")))))
         (unbox stages))
       (error! (string-append (unbox err-box)
                              (if (null? (unbox recovery))
                                  ""
                                  (string-append "\nRecover files from: " (string-join (unbox recovery) "\n"))))))
     (for-each
       (lambda (s)
         (define op (hash-ref s "op"))
         (when (hash-ref s "mode")
           (with-handler
             (lambda (e) (notify (string-append "Copied, but could not restore directory permissions: " (to-string e))
                                 (log-level 'warn)))
             (uv-fs-chmod (hash-ref op "target") (hash-ref s "mode"))))
         (when (equal? (hash-ref op "kind") "rename")
           (define sp (hash-ref (hash-ref op "source") "path"))
           (define tgt (hash-ref op "target"))
           (for-each
             (lambda (b)
               (define bname (unbox (hash-ref b "name")))
               (when (within? bname sp)
                 (define dest (string-append tgt (substring bname (string-length sp) (string-length bname))))
                 (define loaded (hash-ref b "id"))
                 (define dir-st (hash-try-get (unbox *states*) loaded))
                 (when dir-st
                   (set-box! (hash-ref dir-st "root") dest)
                   (for-each (lambda (w) (wo-local-set w "winbar" (vector-ref (string/gsub dest "%%" "%%%%") 0)))
                             (fn-call "win_findbuf" loaded)))
                 (nvim_buf_set_name loaded (string-append (if dir-st "flash://" "") dest))
                 (set-box! (hash-ref b "name") dest)))
             buffers)
           (for-each
             (lambda (p)
               (when (or (equal? p sp) (and (hash-ref (hash-ref op "source") "directory") (within? p sp)))
                 (define id (hash-ref (unbox *ids*) p))
                 (define dest (string-append tgt (substring p (string-length sp) (string-length p))))
                 (set-box! *ids* (hash-insert (hash-remove (unbox *ids*) p) dest id))
                 (define e (hash-ref (unbox *entries*) id))
                 (set-box! *entries*
                           (hash-insert (unbox *entries*) id
                                        (hash-insert (hash-insert e "path" dest) "name" (fs-basename dest))))))
             (hash-keys->list (unbox *ids*)))))
       (unbox stages))
     (for-each
       (lambda (sbuf)
         (define st (hash-ref (unbox *states*) sbuf))
         (for-each
           (lambda (s)
             (define op (hash-ref s "op"))
             (when (and (equal? (hash-ref op "kind") "rename") (hash-ref (hash-ref op "source") "directory"))
               (define sp (hash-ref (hash-ref op "source") "path"))
               (define tgt (hash-ref op "target"))
               (define exp (unbox (hash-ref st "expanded")))
               (set-box! (hash-ref st "expanded")
                         (foldl (lambda (p acc)
                                  (if (within? p sp)
                                      (hash-insert (hash-remove acc p)
                                                   (string-append tgt (substring p (string-length sp) (string-length p)))
                                                   (hash-ref exp p))
                                      acc))
                                exp (hash-keys->list exp)))))
           (unbox stages))
         (set-box! (hash-ref st "children") (hash)))
       (hash-keys->list (unbox *states*)))
     (define deleted (box (hash)))
     (for-each
       (lambda (b)
         (for-each
           (lambda (s)
             (define op (hash-ref s "op"))
             (when (and (equal? (hash-ref op "kind") "delete")
                        (within? (unbox (hash-ref b "name")) (hash-ref (hash-ref op "source") "path")))
               (set-box! deleted (hash-insert (unbox deleted) (hash-ref b "id") #t))))
           (unbox stages)))
       buffers)
     (unless (null? (hash-keys->list (unbox deleted)))
       (define repl
         (box (let loop ([xs (state-call 'buffers)])
                (cond [(null? xs) #f]
                      [(and (not (hash-contains? (unbox deleted) (car xs))) (is-source? (car xs))) (car xs)]
                      [else (loop (cdr xs))]))))
       (for-each
         (lambda (cand)
           (when (nvim_buf_is_valid cand)
             (if (bo-get cand "modified")
                 (notify (string-append "Deleted file has unsaved buffer; kept: " (nvim_buf_get_name cand))
                         (log-level 'warn))
                 (begin
                   (when (and (not (unbox repl)) (not (null? (fn-call "win_findbuf" cand))))
                     (set-box! repl (nvim_create_buf #t #f)))
                   (state-call 'delete-buffer cand #f (unbox repl))))))
         (hash-keys->list (unbox deleted))))
     (for-each
       (lambda (s)
         (with-handler
           (lambda (e) (notify (string-append "Could not remove staging directory: " (hash-ref s "stage") "\n" (to-string e))
                               (log-level 'warn)))
           (remove-recursive! (hash-ref s "stage"))))
       (unbox stages))
     (when (and (hash-contains? (unbox *states*) buf) (nvim_buf_is_valid buf))
       (refresh-explorer! buf))
     (when (nvim_buf_is_valid buf)
       (nvim_exec_autocmds "BufWritePost" (hash "buf" buf "modeline" #f)))
     #t]))

(define (save-explorer! buf (callback #f) (confirmed? #f))
  (define st (hash-ref (unbox *states*) buf))
  (cond
    [(unbox (hash-ref st "filtering")) (notify "Git ignore filtering in progress" (log-level 'info))]
    [(unbox *saving*) (notify "A directory save is already running" (log-level 'warn))]
    [else
     (set-box! *saving* buf)
     (define locks (box (hash)))
     (for-each
       (lambda (cand)
         (set-box! locks (hash-insert (unbox locks) cand (bo-get cand "modifiable")))
         (bo-set cand "modifiable" #f))
       (hash-keys->list (unbox *states*)))
     (set-box! *locks* locks)
     (define result-box (box #f))
     (define err-box (box #f))
     (with-handler
       (lambda (e) (set-box! err-box (to-string e)))
       (set-box! result-box (commit-explorer! buf confirmed?)))
     (set-box! *saving* #f)
     (for-each
       (lambda (cand)
         (when (nvim_buf_is_valid cand)
           (bo-set cand "modifiable" (hash-ref (unbox locks) cand))))
       (hash-keys->list (unbox locks)))
     (set-box! *locks* #f)
     (for-each
       (lambda (cand)
         (when (and (not (bo-get cand "modified")) (null? (fn-call "win_findbuf" cand)))
           (nvim_buf_delete cand (hash "force" #t))))
       (hash-keys->list (unbox *states*)))
     (when (unbox err-box)
       (schedule (lambda () (notify (unbox err-box) (log-level 'error)))))
     (when (and callback (nvim_buf_is_valid buf))
       (callback (and (not (unbox err-box)) (unbox result-box))))]))

(define (clean-explorer! buf action)
  (define st (hash-ref (unbox *states*) buf))
  (cond
    [(unbox (hash-ref st "filtering")) (notify "Git ignore filtering in progress" (log-level 'info))]
    [(unbox *saving*) (notify "Directory save in progress" (log-level 'warn))]
    [(not (bo-get buf "modified")) (action #f #f)]
    [else
     (define win (nvim_get_current_win))
     (define plan-err (box #f))
     (define ops-box (box '()))
     (with-handler
       (lambda (e) (set-box! plan-err (to-string e)))
       (define-values (ops _b) (plan-operations buf))
       (set-box! ops-box ops))
     (define choice
       (if (not (unbox plan-err))
           (fn-call "confirm" (string-append "Unsaved directory edits\n" (summarize-ops (unbox ops-box)))
                    "&Save\n&Discard\n&Cancel" 3)
           (let ([c (fn-call "confirm" (string-append "Unsaved directory edits\n" (unbox plan-err))
                             "&Discard\n&Cancel" 2)])
             (if (> c 0) (+ c 1) 0))))
     (cond
       [(= choice 1)
        (save-explorer!
          buf
          (lambda (saved?)
            (when (and saved? (nvim_win_is_valid win) (= (nvim_win_get_buf win) buf))
              (if (= (nvim_get_current_win) win)
                  (action #t #f)
                  (nvim_win_call win (lambda () (action #t #f))))))
          #t)]
       [(= choice 2)
        (refresh-explorer! buf)
        (action #t #t)])]))

(define (notify-filter! key)
  (notify (string-append (if (equal? key "hidden") "Hidden files" "Git ignored files")
                         ": " (if (hash-ref (unbox *filters*) key) "ON" "OFF"))))

(define (toggle-filter! buf key)
  (clean-explorer!
    buf
    (lambda (_r _d)
      (define st (hash-ref (unbox *states*) buf))
      (define next-val (not (unbox (hash-ref st key))))
      (set-box! (hash-ref st key) next-val)
      (set-box! *filters* (hash-insert (unbox *filters*) key next-val))
      (if (equal? key "hidden") (refresh-explorer! buf) (render-explorer! buf))
      (notify-filter! key))))

(for-each
  (lambda (pair)
    (keymap-set
      "n" (string-append "<leader>" (car pair))
      (lambda ()
        (define found
          (let loop ([ws (nvim_tabpage_list_wins 0)])
            (cond
              [(null? ws) #f]
              [(hash-contains? (unbox *states*) (nvim_win_get_buf (car ws))) (car ws)]
              [else (loop (cdr ws))])))
        (if found
            (nvim_win_call found (lambda () (toggle-filter! (nvim_win_get_buf found) (cdr pair))))
            (begin
              (set-box! *filters*
                        (hash-insert (unbox *filters*) (cdr pair) (not (hash-ref (unbox *filters*) (cdr pair)))))
              (notify-filter! (cdr pair)))))
      (hash "desc" (if (equal? (cdr pair) "hidden")
                       "Toggle hidden files in Explorer"
                       "Toggle Git ignored files in Explorer"))))
  '(("Tg" . "show_ignored") ("Th" . "hidden")))

(define (style-window! win)
  (define buf (nvim_win_get_buf win))
  (cond
    [(hash-contains? (unbox *states*) buf)
     (unless (hash-contains? (unbox *window-options*) win)
       (define saved
         (foldl (lambda (opt acc) (hash-insert acc opt (wo-get win opt))) (hash) *ui-options*))
       (set-box! *window-options* (hash-insert (unbox *window-options*) win saved)))
     (wo-local-set win "conceallevel" 3)
     (wo-local-set win "concealcursor" "nvic")
     (wo-local-set win "wrap" #f)
     (wo-local-set win "foldenable" #f)
     (wo-local-set win "spell" #f)
     (wo-local-set win "cursorcolumn" #f)
     (wo-local-set win "list" #f)
     (wo-local-set win "winbar" (vector-ref (string/gsub (unbox (hash-ref (hash-ref (unbox *states*) buf) "root")) "%%" "%%%%") 0))
     (define cursor (nvim_win_get_cursor win))
     (define ls (nvim_buf_get_lines buf (- (vector-ref cursor 0) 1) (vector-ref cursor 0) #f))
     (define line (if (null? ls) "" (car ls)))
     (define pref (or (string/match line "^/%d+ *") ""))
     (when (and (not (equal? pref "")) (< (vector-ref cursor 1) (string-length pref)))
       (nvim_win_set_cursor win (vector (vector-ref cursor 0) (string-length pref))))]
    [(hash-contains? (unbox *window-options*) win)
     (restore-window! win (hash-ref (unbox *window-options*) win))
     (set-box! *window-options* (hash-remove (unbox *window-options*) win))]))

(nvim_create_autocmd
  '("BufWinEnter" "WinEnter")
  (hash "group" *group* "callback" (lambda (_args) (style-window! (nvim_get_current_win)))))

(nvim_create_autocmd
  "WinClosed"
  (hash "group" *group*
        "callback" (lambda (args)
                     (define closed (string->number (hash-ref args "match")))
                     (set-box! *window-options* (hash-remove (unbox *window-options*) closed))
                     (for-each
                       (lambda (b)
                         (define st (hash-ref (unbox *states*) b))
                         (define h (unbox (hash-ref st "help")))
                         (cond
                           [(and h (= (hash-ref h "owner") closed)) (close-help! b)]
                           [(and h (= (hash-ref h "win") closed)) (set-box! (hash-ref st "help") #f)]))
                       (hash-keys->list (unbox *states*))))))

(define (explorer-close)
  (clean-explorer!
    (nvim_get_current_buf)
    (lambda (_r _d)
      (define win (nvim_get_current_win))
      (focus-editor-restoring!)
      (nvim_win_close win #f))))

(define (explorer-open root0 (sidebar? #f) (file #f))
  (define root (or (uv-fs-realpath root0) (fs-normalize root0)))
  (unless (= (fn-call "isdirectory" root) 1)
    (error! (string-append "Not a directory: " root)))
  (define prev (nvim_get_current_buf))
  (define origin (nvim_get_current_win))
  (define saved
    (or (hash-try-get (unbox *window-options*) origin)
        (foldl (lambda (opt acc) (hash-insert acc opt (wo-get origin opt))) (hash) *ui-options*)))
  (if (and (hash-contains? (unbox *states*) prev) (bo-get prev "modified"))
      (clean-explorer! prev (lambda (_r _d) (explorer-open root sidebar? file)))
      (let* ([existing
              (let loop ([bs (hash-keys->list (unbox *states*))])
                (cond
                  [(null? bs) #f]
                  [(equal? (unbox (hash-ref (hash-ref (unbox *states*) (car bs)) "root")) root) (car bs)]
                  [else (loop (cdr bs))]))]
             [buf (or existing (nvim_create_buf #f #f))])
        (unless existing
          (define st
            (hash "root" (box root)
                  "originals" (box (hash))
                  "known" (box (hash))
                  "children" (box (hash))
                  "expanded" (box (hash))
                  "hidden" (box (hash-ref (unbox *filters*) "hidden"))
                  "show_ignored" (box (hash-ref (unbox *filters*) "show_ignored"))
                  "ignored" (box (hash))
                  "sort" (box "name")
                  "reverse" (box #f)
                  "filtering" (box #f)
                  "rendering" (box #f)
                  "reveal" (box #f)
                  "help" (box #f)
                  "tick" (box #f)
                  "rows" (box (hash))
                  "path_rows" (box (hash))
                  "row_error" (box #f)
                  "redraw" (box #f)))
          (set-box! *states* (hash-insert (unbox *states*) buf st))
          (nvim_buf_set_name buf (string-append "flash://" root))
          (bo-set buf "buftype" "acwrite")
          (bo-set buf "bufhidden" "hide")
          (bo-set buf "swapfile" #f)
          (bo-set buf "undofile" #f)
          (bo-set buf "filetype" "flash-explorer")
          (nvim_buf_call
            buf
            (lambda ()
              (cmd "syntax match FlashDirectoryId /^\\/\\d\\+ / conceal")
              (cmd "syntax match FlashDirectoryFolder /.*\\/$/ contains=FlashDirectoryId")
              (cmd "highlight default link FlashDirectoryFolder Directory")))
          (define (bmap key fn desc)
            (keymap-set "n" key fn (hash "buf" buf "silent" #t "desc" desc)))
          (for-each
            (lambda (pair)
              (keymap-set
                "n" (car pair)
                (lambda ()
                  (define pref (or (string/match (fn-call "getline" ".") "^/%d+ *") ""))
                  (string-append "0" (if (> (string-length pref) 0)
                                         (string-append (number->string (string-length pref)) "l")
                                         "")
                                 (cdr pair)))
                (hash "buf" buf "expr" #t "desc" "Edit filename without its ID")))
            '(("0" . "") ("^" . "") ("<Home>" . "") ("I" . "i") ("cc" . "C") ("S" . "C")))
          (for-each
            (lambda (key)
              (bmap key
                    (lambda ()
                      (define idx (fn-call "line" "."))
                      (define-values (rows _e) (tree-rows buf))
                      (define row (hash-try-get rows idx))
                      (define reg (v-get "register"))
                      (define cnt (v-get "count1"))
                      (if (not (starts-with? (fn-call "getregtype" reg) "V"))
                          (cmd (string-append "normal! \"" reg (number->string cnt) key))
                          (let* ([contents (fn-call "getreg" reg 1 #t)]
                                 [first (if (null? contents) "" (car contents))]
                                 [lbl (or (string/match first "^/%d+ (.*)$") first)]
                                 [depth (floor (/ (string-length (or (string/match lbl "^ *") "")) 2))]
                                 [delta (- (if row (hash-ref row "depth") 0) depth)])
                            (when (and (equal? key "p") row (hash-ref row "directory"))
                              (let loop ([i idx])
                                (define nxt (hash-try-get rows (+ i 1)))
                                (if (and nxt (> (hash-ref nxt "depth") (hash-ref row "depth")))
                                    (loop (+ i 1))
                                    (begin (set! idx i) (nvim_win_set_cursor 0 (vector i 0))))))
                            (cmd (string-append "normal! \"" reg (number->string cnt) key))
                            (unless (= delta 0)
                              (define start (if (equal? key "p") idx (- idx 1)))
                              (define pasted (nvim_buf_get_lines buf start (+ start (* (length contents) cnt)) #f))
                              (define adjusted
                                (map (lambda (line)
                                       (define pm (string/match line "^(/%d+ )(.*)$"))
                                       (define p (if (vector? pm) (vector-ref pm 0) ""))
                                       (define rest (if (vector? pm) (vector-ref pm 1) line))
                                       (define im (string/match rest "^( *)(.*)$"))
                                       (define ind (if (vector? im) (vector-ref im 0) ""))
                                       (define nm (if (vector? im) (vector-ref im 1) rest))
                                       (string-append p (make-string (max 0 (+ (string-length ind) (* delta 2))) #\space) nm))
                                     pasted))
                              (cmd "undojoin")
                              (nvim_buf_set_lines buf start (+ start (length adjusted)) #f adjusted)))))
                    "Paste entries at current tree depth"))
            '("p" "P"))
          (for-each
            (lambda (key)
              (keymap-set
                "n" key
                (lambda ()
                  (unless (or (unbox (hash-ref st "filtering")) (not (bo-get buf "modifiable")))
                    (define idx (fn-call "line" "."))
                    (define-values (rows _e) (tree-rows buf))
                    (define row (hash-try-get rows idx))
                    (define depth (if row (hash-ref row "depth") 0))
                    (when (and (equal? key "o") row (hash-ref row "directory"))
                      (set! depth (+ depth 1))
                      (define collapsed? (not (hash-try-get (unbox (hash-ref st "expanded")) (hash-ref row "target"))))
                      (set-box! (hash-ref st "expanded")
                                (hash-insert (unbox (hash-ref st "expanded")) (hash-ref row "target") #t))
                      (when (and collapsed? (hash-try-get row "id") (not (bo-get buf "modified")))
                        (render-explorer! buf)))
                    (define ins-idx (- idx (if (equal? key "O") 1 0)))
                    (nvim_buf_set_lines buf ins-idx ins-idx #f (list (make-string (* depth 2) #\space)))
                    (nvim_win_set_cursor 0 (vector (+ ins-idx 1) (* depth 2)))
                    (cmd "startinsert!")))
                (hash "buf" buf "desc" "Create entry (o on a folder creates a child)")))
            '("o" "O"))
          (keymap-set
            "i" "<BS>"
            (lambda ()
              (define pref (or (string/match (fn-call "getline" ".") "^/%d+ *") ""))
              (if (and (not (equal? pref "")) (<= (fn-call "col" ".") (+ (string-length pref) 1))) "" "<BS>"))
            (hash "buf" buf "expr" #t))
          (define (open-entry! (command #f))
            (define line (fn-call "getline" "."))
            (define path0 (explorer-path buf (fn-call "line" ".")))
            (define m (string/match line "^/(%d+) "))
            (define id (and m (string->number m)))
            (define orig-path (and id (hash-try-get (unbox *entries*) id) (hash-ref (hash-ref (unbox *entries*) id) "path")))
            (when path0
              (clean-explorer!
                buf
                (lambda (_r discarded?)
                  (define path (if discarded? orig-path path0))
                  (when path
                    (if (not (uv-fs-lstat path))
                        (notify (string-append "Entry does not exist; save directory edits first: " path) (log-level 'warn))
                        (begin
                          (when command
                            (define s (hash-try-get (unbox *window-options*) (nvim_get_current_win)))
                            (cmd command)
                            (restore-window! (nvim_get_current_win) s))
                          (if (= (fn-call "isdirectory" path) 1)
                              (if (and (not command) id (hash-ref (hash-ref (unbox *entries*) id) "directory"))
                                  (begin
                                    (set-box! (hash-ref st "expanded")
                                              (hash-insert (unbox (hash-ref st "expanded")) path
                                                           (not (hash-try-get (unbox (hash-ref st "expanded")) path))))
                                    (render-explorer! buf))
                                  (explorer-open path))
                              (begin
                                (focus-editor-restoring!)
                                (cmd (string-append "edit " (fn-call "fnameescape" path))))))))))))
          (for-each (lambda (k) (bmap k (lambda () (open-entry!)) "Open file / expand or collapse folder"))
                    '("<CR>" "za"))
          (bmap "zc"
                (lambda ()
                  (clean-explorer!
                    buf
                    (lambda (_r _d)
                      (define-values (rows _e) (tree-rows buf))
                      (define row (hash-try-get rows (fn-call "line" ".")))
                      (when row
                        (define tgt (hash-ref row "target"))
                        (define p (if (hash-try-get (unbox (hash-ref st "expanded")) tgt) tgt (fs-dirname tgt)))
                        (unless (equal? p (unbox (hash-ref st "root")))
                          (set-box! (hash-ref st "expanded") (hash-remove (unbox (hash-ref st "expanded")) p))
                          (render-explorer! buf)
                          (define-values (rows2 _e2) (tree-rows buf))
                          (for-each
                            (lambda (i)
                              (when (equal? (hash-ref (hash-ref rows2 i) "target") p)
                                (nvim_win_set_cursor 0 (vector i 0))))
                            (hash-keys->list rows2)))))))
                "Collapse folder / parent")
          (for-each
            (lambda (pair) (bmap (car pair) (lambda () (open-entry! (cdr pair))) "Open in split / tab"))
            '(("<localleader>v" . "belowright vnew") ("<localleader>s" . "belowright new") ("<localleader>t" . "tabnew")))
          (bmap "-" (lambda () (explorer-open (fs-dirname (unbox (hash-ref st "root"))))) "Parent directory")
          (bmap "<localleader>w" (lambda () (explorer-open (fn-call "getcwd"))) "Working directory")
          (bmap "gr" (lambda () (clean-explorer! buf (lambda (refreshed? _d) (unless refreshed? (refresh-explorer! buf))))) "Refresh directory")
          (bmap "g." (lambda () (toggle-filter! buf "hidden")) "Toggle hidden files")
          (bmap "<localleader>i" (lambda () (toggle-filter! buf "show_ignored")) "Toggle Git ignored files")
          (for-each
            (lambda (pair)
              (bmap (car pair)
                    (lambda () (cmd (string-append (cdr pair) " " (fn-call "fnameescape" (unbox (hash-ref st "root"))))))
                    "Change working directory"))
            '(("<localleader>d" . "cd") ("<localleader>D" . "tcd")))
          (bmap "gx" (lambda () (define p (explorer-path buf (fn-call "line" "."))) (when p (ui-open p))) "Open externally")
          (bmap "<C-c>" explorer-close "Close explorer")
          (bmap "gs"
                (lambda ()
                  (clean-explorer!
                    buf
                    (lambda (_r _d)
                      (ui-select '("name" "size" "mtime") (hash "prompt" "Sort by")
                                 (lambda (col _i)
                                   (when col
                                     (ui-select '("ascending" "descending") (hash "prompt" "Sort order")
                                                (lambda (ord _j)
                                                  (when (and ord (hash-contains? (unbox *states*) buf) (not (bo-get buf "modified")))
                                                    (set-box! (hash-ref st "sort") col)
                                                    (set-box! (hash-ref st "reverse") (equal? ord "descending"))
                                                    (refresh-explorer! buf))))))))))
                "Choose sort order")
          (bmap "<localleader>p"
                (lambda ()
                  (define pwin
                    (let loop ([ws (nvim_tabpage_list_wins 0)])
                      (cond [(null? ws) #f]
                            [(wo-get (car ws) "previewwindow") (car ws)]
                            [else (loop (cdr ws))])))
                  (if pwin
                      (nvim_win_close pwin #f)
                      (let ([p (explorer-path buf (fn-call "line" "."))])
                        (when (and p (= (fn-call "filereadable" p) 1))
                          (define s (hash-try-get (unbox *window-options*) (nvim_get_current_win)))
                          (cmd (string-append "pedit " (fn-call "fnameescape" p)))
                          (for-each (lambda (w) (when (wo-get w "previewwindow") (restore-window! w s)))
                                    (nvim_tabpage_list_wins 0))))))
                "Toggle preview")
          (bmap "g?"
                (lambda ()
                  (if (unbox (hash-ref st "help"))
                      (close-help! buf)
                      (let* ([owner (nvim_get_current_win)]
                             [hbuf (nvim_create_buf #f #t)]
                             [ll (or (g-get "maplocalleader") "\\")]
                             [raw-items
                              '(("Navigation")
                                ("Enter / za" . "Open file or expand/collapse folder")
                                ("zc" . "Collapse folder or its parent")
                                ("- / Local w" . "Root parent / working directory")
                                ("Local v / Local s" . "Open in vertical / horizontal split")
                                ("Local t" . "Open in a new tab")
                                ("Local p" . "Toggle file preview")
                                ("Ctrl-c" . "Close explorer, return to editor")
                                ()
                                ("File operations  (apply with :w)")
                                ("yy / p" . "Copy entry; rename pasted row")
                                ("i / a" . "Edit name here / after the cursor")
                                ("I / A" . "Edit at filename start / end")
                                ("cc" . "Replace the entire filename")
                                ("o / O" . "Create entry below / above")
                                ("name / name/" . "Create a file / folder")
                                ("test/main.py" . "Create missing folders and the file")
                                ("dd" . "Delete entry; collapse folder first")
                                (":w" . "Review and confirm file operations")
                                ()
                                ("View")
                                ("gr" . "Refresh directory contents")
                                ("g. / Local i" . "Toggle hidden / Git ignored files")
                                ("gs" . "Choose sort order")
                                ("Local d / Local D" . "Set global / tab working directory")
                                ("gx" . "Open in an external application")
                                ()
                                ("g?" . "Toggle guide from the tree or guide")
                                ("q / Esc" . "Close while focused in the guide"))]
                             [lines
                              (map (lambda (it)
                                     (cond
                                       [(null? it) ""]
                                       [(string? (cdr it))
                                        (define ll-esc (vector-ref (string/gsub ll "%%" "%%%%") 0))
                                        (define k (vector-ref (string/gsub (car it) "Local ([%a])" (string-append ll-esc "%1")) 0))
                                        (string-append "  " k (make-string (max 2 (- 18 (string-length k))) #\space) (cdr it))]
                                       [else (string-append "  " (car it))]))
                                   raw-items)]
                             [w (min (- (go-get "columns") 4)
                                     (foldl (lambda (l acc) (max acc (+ (fn-call "strdisplaywidth" l) 2))) 20 lines))]
                             [h (min (length lines) (- (go-get "lines") 4))])
                        (nvim_buf_set_lines hbuf 0 -1 #f lines)
                        (bo-set hbuf "modifiable" #f)
                        (bo-set hbuf "bufhidden" "wipe")
                        (define hwin
                          (nvim_open_win
                            hbuf #t
                            (hash "relative" "editor" "style" "minimal" "border" "single"
                                  "title" " FLASH Explorer " "title_pos" "center"
                                  "width" w "height" h
                                  "row" (floor (/ (- (go-get "lines") h) 2))
                                  "col" (floor (/ (- (go-get "columns") w) 2)))))
                        (wo-set hwin "wrap" #t)
                        (wo-set hwin "winfixbuf" #t)
                        (set-box! (hash-ref st "help") (hash "win" hwin "buf" hbuf "owner" owner))
                        (for-each (lambda (k) (keymap-set "n" k (lambda () (close-help! buf)) (hash "buf" hbuf)))
                                  '("g?" "q" "<Esc>" "<C-c>")))))
                "Directory help")
          (nvim_create_autocmd
            "BufWriteCmd"
            (hash "group" *group* "buf" buf "callback" (lambda (_args) (save-explorer! buf))))
          (nvim_buf_attach
            buf #f
            (hash "on_lines"
                  (lambda (_ev changed _tick first old-last last)
                    (define s (hash-try-get (unbox *states*) changed))
                    (when (and s (not (unbox (hash-ref s "rendering"))))
                      (define pending (unbox (hash-ref s "redraw")))
                      (if pending
                          (set-box! (hash-ref s "redraw")
                                    (cons (min (car pending) first)
                                          (max (+ (cdr pending) (- last old-last)) (+ last 1))))
                          (begin
                            (set-box! (hash-ref s "redraw") (cons first (+ last 1)))
                            (schedule
                              (lambda ()
                                (when (equal? (hash-try-get (unbox *states*) changed) s)
                                  (define rng (unbox (hash-ref s "redraw")))
                                  (set-box! (hash-ref s "redraw") #f)
                                  (define cnt (nvim_buf_line_count changed))
                                  (draw-tree! changed (min (car rng) (- cnt 1)) (min (cdr rng) cnt)))))))))))
          (nvim_create_autocmd
            "TextYankPost"
            (hash "group" *group* "buf" buf
                  "callback" (lambda (_args)
                               (define ev (v-get "event"))
                               (for-each
                                 (lambda (line)
                                   (define m (string/match line "^/(%d+) "))
                                   (when m
                                     (define id (string->number m))
                                     (when (hash-contains? (unbox *entries*) id)
                                       (set-box! *copied-ids* (hash-insert (unbox *copied-ids*) id #t)))))
                                 (or (and ev (hash-try-get ev "regcontents")) '())))))
          (nvim_create_autocmd
            '("CursorMoved" "CursorMovedI")
            (hash "group" *group* "buf" buf
                  "callback" (lambda (_args)
                               (define pref (or (string/match (fn-call "getline" ".") "^/%d+ *") ""))
                               (define cur (nvim_win_get_cursor 0))
                               (when (and (not (equal? pref "")) (< (vector-ref cur 1) (string-length pref)))
                                 (nvim_win_set_cursor 0 (vector (vector-ref cur 0) (string-length pref))))))))
        (when file (reveal-file! buf file))
        (unless (bo-get buf "modified") (refresh-explorer! buf))
        (when (and (unbox *saving*) (unbox *locks*) (not (hash-contains? (unbox (unbox *locks*)) buf)))
          (set-box! (unbox *locks*) (hash-insert (unbox (unbox *locks*)) buf (bo-get buf "modifiable")))
          (bo-set buf "modifiable" #f))
        (if sidebar?
            (let ([w (nvim_open_win buf #t (hash "split" "left" "win" -1 "width" (sidebar-width)))])
              (set-box! *window-options* (hash-insert (unbox *window-options*) w saved))
              (fix-sidebar-width! w))
            (nvim_set_current_buf buf))
        (style-window! (nvim_get_current_win))
        (select-file! buf))))

(define (explorer-refresh buf (files #f))
  (when (and (not (unbox *saving*))
             (hash-contains? (unbox *states*) buf)
             (not (bo-get buf "modified")))
    (refresh-explorer! buf files)))

(nvim_create_autocmd
  '("BufEnter" "WinEnter")
  (hash "group" *group*
        "callback" (lambda (args)
                     (unless (or (g-get "SessionLoad") (not (is-editor? 0)))
                       (define file (nvim_buf_get_name (hash-ref args "buf")))
                       (for-each
                         (lambda (w)
                           (define b (nvim_win_get_buf w))
                           (when (hash-contains? (unbox *states*) b)
                             (if (reveal-file! b file)
                                 (render-explorer! b)
                                 (select-file! b))))
                         (nvim_tabpage_list_wins 0))))))

(nvim_create_autocmd
  "BufWipeout"
  (hash "group" *group*
        "callback" (lambda (args)
                     (define b (hash-ref args "buf"))
                     (define st (hash-try-get (unbox *states*) b))
                     (close-help! b)
                     (set-box! *states* (hash-remove (unbox *states*) b))
                     (when st
                       (cancel-command! (string-append "explorer-ignore:" (number->string b)))
                       (for-each
                         (lambda (id)
                           (define retained
                             (or (hash-contains? (unbox *copied-ids*) id)
                                 (let loop ([bs (hash-keys->list (unbox *states*))])
                                   (cond
                                     [(null? bs) #f]
                                     [(hash-contains? (unbox (hash-ref (hash-ref (unbox *states*) (car bs)) "known")) id) #t]
                                     [else (loop (cdr bs))]))))
                           (when (and (not retained) (hash-contains? (unbox *entries*) id))
                             (define p (hash-ref (hash-ref (unbox *entries*) id) "path"))
                             (set-box! *entries* (hash-remove (unbox *entries*) id))
                             (when (equal? (hash-try-get (unbox *ids*) p) id)
                               (set-box! *ids* (hash-remove (unbox *ids*) p)))))
                         (hash-keys->list (unbox (hash-ref st "known"))))))))

(nvim_create_autocmd
  "User"
  (hash "group" *group* "pattern" "NopackCancel"
        "callback" (lambda (_args)
                     (for-each
                       (lambda (b)
                         (define st (hash-ref (unbox *states*) b))
                         (when (unbox (hash-ref st "filtering"))
                           (set-box! (hash-ref st "filtering") #f)
                           (set-box! (hash-ref st "show_ignored") #t)))
                       (hash-keys->list (unbox *states*))))))

(nvim_create_autocmd
  "BufHidden"
  (hash "group" *group*
        "callback" (lambda (args)
                     (define b (hash-ref args "buf"))
                     (when (hash-contains? (unbox *states*) b)
                       (close-help! b)
                       (schedule
                         (lambda ()
                           (when (and (not (unbox *saving*))
                                      (hash-contains? (unbox *states*) b)
                                      (not (bo-get b "modified"))
                                      (null? (fn-call "win_findbuf" b)))
                             (nvim_buf_delete b (hash "force" #t)))))))))

(nvim_create_autocmd
  '("BufWritePost" "FileChangedShellPost")
  (hash "group" *group*
        "pattern" '(".gitignore" "*/.git/info/exclude")
        "callback" (lambda (args)
                     (define root (state-call 'find-git-root (fs-dirname (nvim_buf_get_name (hash-ref args "buf")))))
                     (when root
                       (for-each
                         (lambda (b)
                           (define st (hash-ref (unbox *states*) b))
                           (when (equal? (state-call 'find-git-root (unbox (hash-ref st "root"))) root)
                             (cancel-command! (string-append "explorer-ignore:" (number->string b)))
                             (set-box! (hash-ref st "filtering") #f)
                             (set-box! (hash-ref st "ignored") (hash))
                             (when (and (not (unbox *saving*)) (not (bo-get b "modified")))
                               (render-explorer! b))))
                         (hash-keys->list (unbox *states*)))))))

(nvim_create_autocmd
  "BufEnter"
  (hash "group" *group*
        "callback" (lambda (args)
                     (define b (hash-ref args "buf"))
                     (unless (hash-contains? (unbox *states*) b)
                       (define name (nvim_buf_get_name b))
                       (when (and (equal? (bo-get b "buftype") "")
                                  (not (equal? name ""))
                                  (= (fn-call "isdirectory" name) 1))
                         (bo-set b "buflisted" #f)
                         (bo-set b "buftype" "nofile")
                         (unless (g-get "SessionLoad")
                           (explorer-open name)
                           (schedule
                             (lambda ()
                               (when (and (nvim_buf_is_valid b) (null? (fn-call "win_findbuf" b)))
                                 (nvim_buf_delete b (hash "force" #t)))))))))))

(nvim_create_autocmd
  "User"
  (hash "group" *group*
        "pattern" '("NopackFilesCreated" "NopackExternalChange")
        "callback" (lambda (args)
                     (define data (hash-try-get args "data"))
                     (define files (and data (hash-try-get data "files")))
                     (for-each (lambda (b) (explorer-refresh b files))
                               (hash-keys->list (unbox *states*))))))
