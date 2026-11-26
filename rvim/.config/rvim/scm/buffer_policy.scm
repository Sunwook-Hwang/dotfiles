;; 1:1 Steel port of: nvim/.config/nvim/lua/buffer_policy.lua
;; Equivalence:
;; - Exact 1:1 functions: is-picker-event?, is-source?, allows?, is-editor?,
;;   source-context, source-unchanged?, guard, restrict!.
;; - Preserves buffer variable `nopack_large_file` and User autocmd `NopackBufferRestricted`.

(require "rvim/api")
(require "rvim/opt")

(provide is-picker-event?
         is-source?
         allows?
         is-editor?
         source-context
         source-unchanged?
         guard
         restrict!)

(define (resolve-buf buf)
  (if (or (not buf) (= buf 0))
      (nvim_get_current_buf)
      buf))

(define (resolve-win win)
  (if (or (not win) (= win 0))
      (nvim_get_current_win)
      win))

;; Picker buffer lifecycle events do not signal file changes; global notifications still do.
(define (is-picker-event? args)
  (define ev (hash-try-get args "event"))
  (define buf (hash-try-get args "buf"))
  (and (not (equal? ev "FocusGained"))
       (not (equal? ev "ShellCmdPost"))
       buf
       (nvim_buf_is_valid buf)
       (not (not (b-get buf "nopack_picker_role")))))

(define (is-source? (buf 0))
  (define b (resolve-buf buf))
  (and (nvim_buf_is_valid b)
       (equal? (bo-get b "buftype") "")))

(define (allows? (buf 0))
  (define b (resolve-buf buf))
  (and (nvim_buf_is_loaded b)
       (is-source? b)
       (not (b-get b "nopack_large_file"))))

;; Editing targets are ordinary source windows, including protected large files.
(define (is-editor? (win 0))
  (define w (resolve-win win))
  (and (nvim_win_is_valid w)
       (is-source? (nvim_win_get_buf w))
       (equal? (hash-try-get (nvim_win_get_config w) "relative") "")
       (not (wo-get w "previewwindow"))))

;; Background results must still belong to the source they were requested for.
(define (source-context (buf 0))
  (define b (resolve-buf buf))
  (hash "buf" b
        "file" (nvim_buf_get_name b)
        "filetype" (bo-get b "filetype")
        "tick" (nvim_buf_get_changedtick b)))

(define (source-unchanged? ctx)
  (define b (hash-ref ctx "buf"))
  (and (nvim_buf_is_loaded b)
       (is-source? b)
       (equal? (nvim_buf_get_name b) (hash-ref ctx "file"))
       (equal? (bo-get b "filetype") (hash-ref ctx "filetype"))
       (equal? (nvim_buf_get_changedtick b) (hash-ref ctx "tick"))))

(define (guard callback)
  (lambda args
    (when (allows? 0)
      (apply callback args))))

(define (restrict! buf)
  (unless (b-get buf "nopack_large_file")
    (b-set buf "nopack_large_file" #t)
    (nvim_exec_autocmds
      "User"
      (hash "pattern" "NopackBufferRestricted"
            "data" (hash "buf" buf)
            "modeline" #f))))
