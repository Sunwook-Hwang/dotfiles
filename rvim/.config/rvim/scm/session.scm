;; 1:1 Steel port of: nvim/.config/nvim/lua/session.lua
;; Equivalence:
;; - Shares `~/.local/state/nvim/sessions/` with Pack/FLASH.
;; - Excludes auxiliary/tree buffers around `:mksession!`, restores on failure,
;;   exposes `<leader>pr`, `<leader>pl`, `<leader>pd`, `<leader>pS`, `<leader>r`,
;;   and hooks `VimLeavePre` (+ `SessionWritePre`/`SessionWritePost` on 0.13+).

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/fn")
(require "rvim/cmd")
(require "rvim/notify")
(require-builtin rvim/uv)
(require "rvim/ui")
(require "rvim/string")
(require "buffer_policy")
(require "state")

(define session-dir
  (string-append (or (env-get "XDG_STATE_HOME") (fn-call "expand" "~/.local/state"))
                 "/nvim/sessions/"))
(fn-call "mkdir" session-dir "p")

(define *save-session* (box #t))
(define *excluded* (box #f))

(define (is-tree? buf)
  (define name (nvim_buf_get_name buf))
  (or (equal? (bo-get buf "filetype") "flash-explorer")
      (not (not (string/match name "^flash://")))
      (and (not (equal? name "")) (= (fn-call "isdirectory" name) 1))))

(define (session-path)
  (define cwd (fn-call "getcwd"))
  (define encoded (vector-ref (string/gsub cwd "[\\/:]+" "%%") 0))
  (string-append session-dir encoded ".vim"))

(define (list-session-files)
  (define entries (or (uv-fs-scandir session-dir) (list)))
  (define with-mtime
    (filter-map
      (lambda (ent)
        (define name (hash-ref ent "name"))
        (if (ends-with? name ".vim")
            (let* ((full (string-append session-dir name))
                   (st (uv-fs-stat full)))
              (if (and st (equal? (hash-try-get st "type") "file"))
                  (cons full (hash-ref (hash-ref st "mtime") "sec"))
                  #f))
            #f))
      entries))
  (map car (sort with-mtime (lambda (a b) (> (cdr a) (cdr b))))))

(define (exclude-auxiliary-buffers!)
  (unless (unbox *excluded*)
    (define saved (hash))
    (for-each
      (lambda (buf)
        (when (or (not (is-source? buf)) (is-tree? buf))
          (define bt (bo-get buf "buftype"))
          (set! saved (hash-insert saved buf (hash "listed" (bo-get buf "buflisted") "buftype" bt)))
          (bo-set buf "buflisted" #f)
          (when (or (equal? bt "acwrite") (equal? bt ""))
            (bo-set buf "buftype" "nofile"))))
      (nvim_list_bufs))
    (set-box! *excluded* saved)))

(define (restore-auxiliary-buffers!)
  (define saved (unbox *excluded*))
  (when saved
    (for-each
      (lambda (buf)
        (when (nvim_buf_is_valid buf)
          (define opts (hash-ref saved buf))
          (bo-set buf "buftype" (hash-ref opts "buftype"))
          (bo-set buf "buflisted" (hash-ref opts "listed"))))
      (hash-keys->list saved))
    (set-box! *excluded* #f)))

(define (write-session!)
  (when (unbox *save-session*)
    (define has-file
      (any (lambda (buf)
             (and (is-source? buf)
                  (not (is-tree? buf))
                  (not (equal? (nvim_buf_get_name buf) ""))))
           (nvim_list_bufs)))
    (when has-file
      (state-call 'restore-window-zooms)
      (exclude-auxiliary-buffers!)
      (with-handler
        (lambda (err)
          (restore-auxiliary-buffers!)
          (notify (to-string err) (log-level 'error)))
        (cmd (string-append "mksession! " (fn-call "fnameescape" (session-path))))
        (restore-auxiliary-buffers!)))))

(when (= (fn-call "has" "nvim-0.13") 1)
  (nvim_create_autocmd "SessionWritePre"
                       (hash "callback" (lambda (_a)
                                          (state-call 'restore-window-zooms)
                                          (exclude-auxiliary-buffers!))))
  (nvim_create_autocmd "SessionWritePost"
                       (hash "callback" (lambda (_a) (restore-auxiliary-buffers!)))))

(define (restore-session! path)
  (if (and path (= (fn-call "filereadable" path) 1))
      (begin
        (state-call 'restore-window-zooms)
        (state-call 'focus-editor)
        (define loading (g-get "SessionLoad"))
        (define previous (v-get "this_session"))
        (define saved-scrolloff (go-get "scrolloff"))
        (define saved-sidescrolloff (go-get "sidescrolloff"))
        (define saved-shortmess (opt-get "shortmess"))
        (define saved-lazy (opt-get "lazyredraw"))
        (opt-set "lazyredraw" #t)
        (define failed #f)
        (with-handler
          (lambda (err) (set! failed err))
          (cmd (string-append "source " (fn-call "fnameescape" path))))
        (opt-set "lazyredraw" saved-lazy)
        (for-each
          (lambda (buf)
            (when (and (is-tree? buf) (not (bo-get buf "modified")))
              (nvim_buf_delete buf (hash "force" #f))))
          (nvim_list_bufs))
        (when failed
          (g-set "SessionLoad" loading)
          (v-set "this_session" previous)
          (go-set "scrolloff" saved-scrolloff)
          (go-set "sidescrolloff" saved-sidescrolloff)
          (go-set "shortmess" saved-shortmess)
          (notify (string-append "Session restore failed: " (to-string failed)) (log-level 'error))))
      (notify "No saved session")))

(define (select-session)
  (define paths (list-session-files))
  (ui-select
    paths
    (hash "prompt" "Sessions:"
          "format_item"
          (lambda (p)
            (define trimmed (substring p (string-length session-dir) (- (string-length p) 4)))
            (define dir0 (vector-ref (string/gsub trimmed "%%" "/") 0))
            (define dir (if (= (fn-call "has" "win32") 1)
                            (vector-ref (string/gsub dir0 "^(%w)/" "%1:/") 0)
                            dir0))
            (fn-call "fnamemodify" dir ":p:~")))
    restore-session!))

(define (restore-last-session)
  (define paths (list-session-files))
  (restore-session! (if (null? paths) #f (car paths))))

(state-set! 'select-session select-session)
(state-set! 'restore-last-session restore-last-session)

(define map-key (state-get 'map))
(map-key "n" "<leader>pr" (lambda () (restore-session! (session-path))) "Restore directory session")
(map-key "n" "<leader>pl" restore-last-session "Restore last session")
(map-key "n" "<leader>pd" (lambda () (set-box! *save-session* #f)) "Stop saving session")
(map-key "n" "<leader>pS" select-session "Select session")
(map-key "n" "<leader>r" select-session "Select session")

(nvim_create_autocmd "VimLeavePre" (hash "callback" (lambda (_a) (write-session!))))
