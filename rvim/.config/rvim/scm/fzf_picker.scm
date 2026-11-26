;; 1:1 Steel port of: nvim/.config/nvim/lua/fzf_picker.lua
;; Equivalence:
;; - Runs external `fzf` in an unlisted terminal float with optional side-by-side preview
;;   driven by `TermRequest` OSC 51 (`\x1b]51;flash-fzf:<index>`) notifications.
;; - Uses NUL-delimited `--read0`/`--print0` temp files and clears `FZF_DEFAULT_OPTS` so
;;   user shell config cannot break the picker protocol.
;; - Restores editor focus on accept, cleans up PTY/windows/temp files on close.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/fs")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "state")

(provide fzf-picker-open)

(define (fzf-picker-open title root executable cancel)
  (define prev (state-get 'active-picker))
  (when prev ((hash-ref prev "close")))
  (define origin (nvim_get_current_win))
  (state-call 'focus-editor)
  (define target (nvim_get_current_win))
  (define closed (box #f))
  (define input (fn-call "tempname"))
  (define output (fn-call "tempname"))
  (define buf (nvim_create_buf #f #t))
  (b-set buf "nopack_picker_role" "fzf")
  (bo-set buf "bufhidden" "hide")
  (define width (max 1 (floor (* (go-get "columns") 0.9))))
  (define height (max 1 (floor (* (- (go-get "lines") 4) 0.9))))
  (define left-width (if (>= width 70) (floor (/ (- width 2) 2)) width))
  (define row (max 0 (floor (/ (- (go-get "lines") height 2) 2))))
  (define col (max 0 (floor (/ (- (go-get "columns") width 2) 2))))
  (define win
    (nvim_open_win
      buf #t
      (hash "relative" "editor" "style" "minimal" "border" "rounded"
            "title" title "width" left-width "height" height "row" row "col" col)))
  (define preview-buf #f)
  (define preview-win #f)
  (when (< left-width width)
    (set! preview-buf (nvim_create_buf #f #t))
    (b-set preview-buf "nopack_picker_role" "preview")
    (bo-set preview-buf "bufhidden" "wipe")
    (set! preview-win
          (nvim_open_win
            preview-buf #f
            (hash "relative" "editor" "style" "minimal" "border" "rounded"
                  "title" "preview" "width" (- width left-width 2) "height" height
                  "row" row "col" (+ col left-width 2) "focusable" #f)))
    (wo-set preview-win "number" #t)
    (wo-set preview-win "wrap" #f))
  (define job-box (box #f))
  (define req-box (box #f))
  (define gen-box (box 0))
  (define sel-box (box #f))
  (define state-box (box #f))

  (define (close! (accepted #f))
    (unless (unbox closed)
      (set-box! closed #t)
      (when (unbox req-box)
        (nvim_del_autocmd (unbox req-box))
        (set-box! req-box #f))
      (when cancel (cancel))
      (define j (unbox job-box))
      (when (and j (> j 0))
        (fn-call "jobstop" j))
      (when (nvim_win_is_valid win)
        (when (= (nvim_get_current_win) win)
          (cmd "stopinsert"))
        (nvim_win_close win #t))
      (when (and (not (unbox job-box)) (nvim_buf_is_valid buf))
        (nvim_buf_delete buf (hash "force" #t)))
      (when (and preview-win (nvim_win_is_valid preview-win))
        (nvim_win_close preview-win #t))
      (when (and preview-buf (nvim_buf_is_valid preview-buf))
        (nvim_buf_delete preview-buf (hash "force" #t)))
      (fn-call "delete" input)
      (fn-call "delete" output)
      (define focus (if (and (equal? accepted #t) (is-editor? target)) target origin))
      (when (nvim_win_is_valid focus)
        (nvim_set_current_win focus))
      (when (equal? (state-get 'active-picker) (unbox state-box))
        (state-set! 'active-picker #f))))

  (nvim_create_autocmd
    "WinClosed"
    (hash "pattern" (if preview-win
                        (list (number->string win) (number->string preview-win))
                        (number->string win))
          "once" #t
          "callback" (lambda (_args) (close!))))

  (nvim_buf_set_lines buf 0 -1 #f '("Collecting files..."))
  (bo-set buf "modified" #f)
  (bo-set buf "modifiable" #f)
  (keymap-set "n" "<Esc>" (lambda () (close!)) (hash "buf" buf "silent" #t))
  (keymap-set "n" "<C-c>" (lambda () (close!)) (hash "buf" buf "silent" #t))

  (define (set-files! files (_root #f))
    (unless (unbox closed)
      (if (null? files)
          (begin
            (close!)
            (notify (string-append "No results: " title)))
          (let* ([prefix (string-append (vector-ref (string/gsub root "/+$" "") 0) "/")]
                 [plen (string-length prefix)]
                 [labels-and-lookup
                  (foldl
                    (lambda (filename acc)
                      (define label
                        (if (and (>= (string-length filename) plen)
                                 (equal? (substring filename 0 plen) prefix))
                            (substring filename plen (string-length filename))
                            filename))
                      (cons (cons label (car acc))
                            (hash-insert (cdr acc) label filename)))
                    (cons '() (hash))
                    files)]
                 [labels (reverse (car labels-and-lookup))]
                 [lookup (cdr labels-and-lookup)])
            (with-handler
              (lambda (err)
                (close!)
                (notify (string-append "Could not prepare fzf input: " (to-string err)) (log-level 'error)))
              (fs-write-file input (string-append (string-join labels "\x00") "\x00"))
              (nvim_set_current_win win)
              (when preview-buf
                (set-box! req-box
                          (nvim_create_autocmd
                            "TermRequest"
                            (hash "buf" buf
                                  "callback"
                                  (lambda (ev)
                                    (define seq (hash-ref (hash-ref ev "data") "sequence"))
                                    (define cap (string/match seq "^\x1b%]51;flash%-fzf:(%-?%d+)$"))
                                    (when cap
                                      (define idx (+ (string->number cap) 1))
                                      (unless (or (unbox closed) (equal? idx (unbox sel-box)))
                                        (set-box! sel-box idx)
                                        (set-box! gen-box (+ (unbox gen-box) 1))
                                        (if (or (< idx 1) (> idx (length files)))
                                            (begin
                                              (bo-set preview-buf "syntax" "")
                                              (bo-set preview-buf "modifiable" #t)
                                              (nvim_buf_set_lines preview-buf 0 -1 #f '("No matches"))
                                              (bo-set preview-buf "modifiable" #f))
                                            (let ([ver (unbox gen-box)]
                                                  [filename (list-ref files (- idx 1))])
                                              (state-call
                                                'read-preview
                                                filename 1 height
                                                (lambda () (and (not (unbox closed))
                                                                (= (unbox gen-box) ver)
                                                                (nvim_buf_is_valid preview-buf)))
                                                (lambda (lines)
                                                  (bo-set preview-buf "modifiable" #t)
                                                  (nvim_buf_set_lines preview-buf 0 -1 #f (or lines '("No text preview")))
                                                  (bo-set preview-buf "modifiable" #f)
                                                  (define syn
                                                    (if lines
                                                        (or (fn-call "filetype_match"
                                                                     (hash "filename" filename "buf" preview-buf))
                                                            "")
                                                        ""))
                                                  (unless (equal? (bo-get preview-buf "syntax") syn)
                                                    (bo-set preview-buf "syntax" syn)))
                                                65536))))))))))
              (define base-cmd
                (list "sh" "-c" "input=$1 output=$2; shift 2; exec \"$@\" < \"$input\" > \"$output\""
                      "flash-fzf" input output executable
                      "--read0" "--print0" "--no-multi" "--layout=reverse" "--bind=change:first"))
              (define full-cmd
                (if preview-buf
                    (append base-cmd
                            (list "--preview-window=0"
                                  "--preview" "printf '\\033]51;flash-fzf:%s\\007' {n} > /dev/tty"
                                  "--bind" "zero:preview(printf '\\033]51;flash-fzf:-1\\007' > /dev/tty)"))
                    base-cmd))
              (define j
                (fn-call
                  "jobstart"
                  full-cmd
                  (hash "term" #t
                        "cwd" root
                        "env" (hash "FZF_DEFAULT_OPTS" "" "FZF_DEFAULT_OPTS_FILE" "" "SHELL" "sh")
                        "on_exit"
                        (lambda (_id code _ev)
                          (schedule
                            (lambda ()
                              (set-box! job-box #f)
                              (if (unbox closed)
                                  (when (nvim_buf_is_valid buf)
                                    (nvim_buf_delete buf (hash "force" #t)))
                                  (let* ([raw (with-handler (lambda (_e) "") (fs-read-file output))]
                                         [trimmed (vector-ref (string/gsub raw "%z$" "") 0)]
                                         [filename (and (= code 0) (hash-try-get lookup trimmed))])
                                    (close! (not (not filename)))
                                    (cond
                                      [filename
                                       (unless (is-editor? target) (state-call 'focus-editor))
                                       (cmd (string-append "edit " (fn-call "fnameescape" filename)))]
                                      [(and (not (= code 0)) (not (= code 1)) (not (= code 130)))
                                       (notify (string-append "fzf exited with code " (number->string code))
                                               (log-level 'error))])))))))))
              (if (<= j 0)
                  (begin
                    (set-box! job-box #f)
                    (close!)
                    (notify "Could not start fzf" (log-level 'error)))
                  (begin
                    (set-box! job-box j)
                    (cmd "startinsert"))))))))

  (define st (hash "closed" closed "close" close! "set_files" set-files!))
  (set-box! state-box st)
  (state-set! 'active-picker st)
  st)
