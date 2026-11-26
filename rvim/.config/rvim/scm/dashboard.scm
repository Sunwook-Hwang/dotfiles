;; 1:1 Steel port of: nvim/.config/nvim/lua/dashboard.lua
;; Equivalence:
;; - Native fullscreen floating dashboard with the exact 26-line Braille header,
;;   `SnacksDashboardHeader`/`Desc`/`Key` highlight links, and hidden `NopackDashboardCursor`.
;; - Saves and restores `showtabline`, `laststatus`, and `guicursor`; redirects `:edit` out
;;   of the float; redraws on resize; auto-opens on `VimEnter` for an empty initial buffer.
;; - Entry `c` ("Config") opens `stdpath("config")/init.scm` instead of `init.lua`.

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/schedule")
(require "buffer_policy")
(require "state")

(define *dashboard-header*
  '(""
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡀⠀⠀⠀⠀⠀⡀⢀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠼⠤⠤⠤⠤⠤⣧⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡸⢸⠀⠀⠀⠀⠀⠀⡟⠀⣾⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠃⢸⠘⢏⠉⠉⠉⡽⡇⠀⢹⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠃⠀⢸⢠⠘⡆⠀⡸⠁⡇⡀⢸⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡰⠃⠀⡖⡞⣚⣆⣹⣼⣁⣀⢳⠓⠚⢹⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡴⠁⠀⠀⡇⣧⠀⢀⡜⢳⡀⠀⢸⠀⠀⠀⢣⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠜⠁⠀⠀⠀⡇⡟⢲⡞⠒⠒⢳⣺⢸⠀⠀⠀⠈⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡠⠋⠀⠀⠀⠀⠀⡇⡷⠃⡇⠀⠀⠀⢹⣸⠀⠀⠀⠀⠘⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⠁⠀⠀⠀⠀⠀⣠⢿⢓⣒⣓⣀⣀⣀⡞⠛⡖⠒⠢⠀⠀⡟⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⠁⠀⠀⠀⠀⠀⣠⠞⢹⢸⢸⠀⠀⠀⠀⠀⡇⠀⠘⢦⢰⠀⠀⡇⠘⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⢀⡤⠊⠁⠀⠀⠀⠀⠀⣠⠞⠁⠀⢸⢸⠘⠒⠲⠒⠒⠒⡇⠀⠀⠀⠳⡄⠀⡇⠀⠈⢆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⢀⣠⠴⠊⠁⠀⠀⠀⠀⠀⢀⡤⡎⠁⠀⠀⠀⢸⢸⠀⠀⢀⠀⠀⠀⡇⠀⠀⠀⢀⠈⢦⡗⠀⠀⠈⢣⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡗⠒⡁⠀⠀⠀⠀⠀⠀⠀"
    "⠈⠁⠀⠀⠀⠀⠀⠀⢀⡠⠖⠁⠀⡇⠀⠀⠀⠀⠚⣾⠒⣒⠚⣢⠀⢰⠓⠒⠒⠒⠺⠀⠀⣟⢆⠀⠀⠀⡟⣄⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣑⡞⣹⡄⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⢀⣀⡤⠚⠁⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⣿⢰⠀⠀⠀⠀⢸⢰⠀⠀⠀⠀⡇⠀⡇⠀⠙⠢⣄⡇⠈⠣⡀⠀⠀⠀⠀⣀⡴⣋⢼⡏⠠⢻⠘⢄⠀⠀⠀⠀⠀"
    "⢀⠤⠔⠊⠉⠀⡇⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⣿⠘⠒⠒⢲⠒⢺⢸⠀⠀⠀⠀⡇⠀⡇⠀⠀⠀⠀⡏⠑⠒⢺⠓⠲⠶⡟⠓⠉⡇⢸⣇⣠⢸⠀⠀⡗⠦⣀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⣿⠀⠀⠀⢸⠀⢸⢸⠀⠀⠀⠀⡅⠀⣇⣀⣀⣀⠀⡇⠀⠠⢼⠤⠤⣤⣧⣤⣤⣧⣼⣧⣼⢸⠤⠤⠇⣀⣈⣉⡁"
    "⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⢀⣀⣿⠀⠤⠤⠼⠔⢺⢸⠀⠀⠀⠀⣏⣀⠧⡤⡤⣖⢒⣷⣚⡻⠭⠯⠭⠗⠒⠓⠒⠛⢻⣏⣹⢸⠉⠉⠁⠀⠐⠒⠂"
    "⠀⠀⠀⠀⠀⠀⡇⠀⠀⣀⡀⠤⠤⡗⠒⠈⠉⠁⠀⢸⠀⠀⠀⣀⣠⣼⢸⠀⠀⠀⠀⣇⠦⠽⠚⠒⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⡟⢻⢸⣀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⢀⣀⠤⠔⡗⠉⠁⠀⠀⠀⠀⡇⠀⠀⠀⢀⡠⣼⠖⡘⢍⠰⡡⢺⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⢀⠁⠀⠸⠇⠸⠼⠀⠈⠆⠢⠄⠀⠀"
    "⠐⠉⠁⠀⠀⠀⡇⠀⠀⠀⠀⠀⢀⣧⠤⠖⠋⢽⣠⢃⠞⣈⡶⠜⠒⢹⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⠔⡠⠌⢁⡐⠒⢒⡠⠀⢓⡈⠄⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⡇⠀⢀⡠⠔⠚⡍⠰⠎⣠⠒⣢⡥⢾⠋⠁⠀⠀⠀⢸⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠈⠉⢦⡀⠀⣀⠧⠚⠉⠒⠒⠒⠃⢀⣴⠗⠋⠁⡇⢸⠀⠐⠂⠢⠤⢼⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⢣⠈⠉⠉⠉⠉⠻⣉⡶⠖⠋⠀⠀⠀⠀⡇⢸⠀⠸⡉⠏⢐⣾⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⣖⠒⠒⠠⡀⠀⠀⡇⢸⠀⠀⡱⠈⠁⣼⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"))

(define *dashboard-namespace* (nvim_create_namespace "nopack-dashboard"))
(define *selection-namespace* (nvim_create_namespace "nopack-dashboard-selection"))

(define (dashboard-highlights!)
  (for-each
    (lambda (pair)
      (nvim_set_hl 0 (string-append "SnacksDashboard" (car pair)) (hash "link" (cdr pair))))
    '(("Header" . "Title") ("Desc" . "String") ("Key" . "Number")))
  (define selected (nvim_get_hl 0 (hash "name" "CursorLine" "link" #f)))
  (define normal (nvim_get_hl 0 (hash "name" "Normal" "link" #f)))
  (define background
    (or (hash-try-get selected "bg")
        (hash-try-get normal "bg")
        (if (equal? (go-get "background") "light") #xffffff #x000000)))
  (nvim_set_hl 0 "NopackDashboardCursor" (hash "fg" background "bg" background "blend" 100)))

(dashboard-highlights!)
(nvim_create_autocmd
  "ColorScheme"
  (hash "group" (nvim_create_augroup "nopack-dashboard-colors" (hash "clear" #t))
        "callback" (lambda (_args) (dashboard-highlights!))))

(define *dashboard-win* (box #f))

(define (open-dashboard)
  (define existing (unbox *dashboard-win*))
  (if (and existing (nvim_win_is_valid existing))
      (nvim_set_current_win existing)
      (let* ([source (nvim_get_current_win)]
             [source-buf (nvim_win_get_buf source)]
             [chrome (hash "showtabline" (go-get "showtabline")
                           "laststatus" (go-get "laststatus")
                           "guicursor" (go-get "guicursor"))])
        (go-set "showtabline" 0)
        (go-set "laststatus" 0)
        (define buf (nvim_create_buf #f #t))
        (bo-set buf "bufhidden" "wipe")
        (bo-set buf "filetype" "nopack_dashboard")
        (define win
          (nvim_open_win
            buf #t
            (hash "relative" "win"
                  "win" source
                  "row" 0
                  "col" 0
                  "width" (nvim_win_get_width source)
                  "height" (nvim_win_get_height source)
                  "style" "minimal"
                  "border" "none")))
        (set-box! *dashboard-win* win)
        (wo-local-set win "winhighlight" "Normal:Normal,NormalFloat:Normal,EndOfBuffer:EndOfBuffer")
        (wo-local-set win "wrap" #f)
        (wo-local-set win "scrolloff" 0)
        (define prev-cursor (hash-ref chrome "guicursor"))
        (go-set "guicursor"
                (string-append (if (equal? prev-cursor "") "" (string-append prev-cursor ","))
                               "n-v:block-NopackDashboardCursor-blinkon0"))
        (define group (nvim_create_augroup "nopack-dashboard-window" (hash "clear" #t)))
        (define closed (box #f))

        (define (source-is-empty?)
          (and (nvim_win_is_valid source)
               (= (nvim_win_get_buf source) source-buf)
               (= (length (fn-call "getbufinfo" (hash "buflisted" 1))) 1)
               (equal? (nvim_buf_get_name source-buf) "")
               (not (bo-get source-buf "modified"))
               (= (nvim_buf_line_count source-buf) 1)
               (equal? (car (nvim_buf_get_lines source-buf 0 1 #f)) "")))

        (define (close!)
          (unless (unbox closed)
            (set-box! closed #t)
            (nvim_del_augroup_by_id group)
            (set-box! *dashboard-win* #f)
            (define focused (= (nvim_get_current_win) win))
            (when (nvim_win_is_valid win)
              (nvim_win_close win #t))
            (for-each (lambda (opt) (go-set opt (hash-ref chrome opt)))
                      '("showtabline" "laststatus" "guicursor"))
            (when (and focused (nvim_win_is_valid source))
              (nvim_set_current_win source))))

        (keymap-set "n" "<Esc>" close! (hash "buf" buf "nowait" #t "desc" "Close dashboard"))

        (nvim_create_autocmd
          "QuitPre"
          (hash "group" group
                "buf" buf
                "callback"
                (lambda (_args)
                  (when (and (= (nvim_get_current_win) win) (source-is-empty?))
                    (schedule
                      (lambda ()
                        (when (and (not (nvim_win_is_valid win)) (source-is-empty?))
                          (cmd "quit"))))))))

        (nvim_create_autocmd
          "WinClosed"
          (hash "group" group
                "pattern" (list (number->string win) (number->string source))
                "callback" (lambda (_args) (close!))))

        (nvim_create_autocmd
          "WinLeave"
          (hash "group" group
                "buf" buf
                "callback" (lambda (_args)
                             (go-set "guicursor" (hash-ref chrome "guicursor"))
                             (schedule close!))))

        ;; A direct :edit belongs in the editor, never in the dashboard's float.
        (nvim_create_autocmd
          "BufEnter"
          (hash "group" group
                "callback"
                (lambda (args)
                  (define target-buf (hash-ref args "buf"))
                  (when (and (= (nvim_get_current_win) win) (not (= target-buf buf)))
                    (schedule
                      (lambda ()
                        (when (and (nvim_win_is_valid win)
                                   (= (nvim_win_get_buf win) target-buf))
                          (close!)
                          (when (and (nvim_win_is_valid source) (nvim_buf_is_valid target-buf))
                            (nvim_win_set_buf source target-buf)))))))))

        (define entries
          (list
            (list "f" "Find file"
                  (lambda () (state-call 'find-files (state-call 'project-root) "Find files")))
            (list "r" "Recent files"
                  (lambda () (state-call 'recent-files (state-call 'open-picker "Recent files" (hash)))))
            (list "l" "Restore last session" (lambda () (state-call 'restore-last-session)))
            (list "p" "Select session" (lambda () (state-call 'select-session)))
            (list "n" "New file" (lambda () (cmd "enew") (cmd "startinsert")))
            (list "c" "Config"
                  (lambda ()
                    (cmd (string-append
                           "edit "
                           (fn-call "fnameescape"
                                    (string-append (fn-call "stdpath" "config") "/init.scm"))))))
            (list "q" "Quit" (lambda () (cmd "qa")))))

        (define *button-rows* (box (hash)))
        (define *rendered-size* (box (cons #f #f)))

        (define (render!)
          (define width (nvim_win_get_width win))
          (define height (nvim_win_get_height win))
          (set-box! *rendered-size* (cons width height))
          (define content-height (+ (length *dashboard-header*) 2 (* (length entries) 2) 1))
          (define top-pad (max 0 (floor (/ (- height content-height) 2))))
          (define lines (box (build-list top-pad (lambda (_i) ""))))
          (define (push-line! s)
            (set-box! lines (append (unbox lines) (list s))))
          (define header-start (length (unbox lines)))
          (define header-width
            (foldl (lambda (line acc) (max acc (fn-call "strdisplaywidth" line))) 0 *dashboard-header*))
          (define header-left (max 0 (floor (/ (- width header-width) 2))))
          (define header-pad (make-string header-left #\space))
          (for-each (lambda (line) (push-line! (string-append header-pad line))) *dashboard-header*)
          (push-line! "")
          (push-line! "")
          (define rows-map (box (hash)))
          (for-each
            (lambda (entry)
              (define key (car entry))
              (define desc (cadr entry))
              (define button-width (min 60 width))
              (define gap (max 1 (- button-width
                                    (fn-call "strdisplaywidth" desc)
                                    (fn-call "strdisplaywidth" key))))
              (define text (string-append desc (make-string gap #\space) key))
              (define left (max 0 (floor (/ (- width (fn-call "strdisplaywidth" text)) 2))))
              (push-line! (string-append (make-string left #\space) text))
              (define row (length (unbox lines)))
              (set-box! rows-map
                        (hash-insert (unbox rows-map) key
                                     (hash "row" row
                                           "left" left
                                           "key_col" (- (+ left (string-length text)) (string-length key)))))
              (push-line! ""))
            entries)
          (set-box! *button-rows* (unbox rows-map))
          (define footer "https://sunwook-hwang.github.io")
          (define footer-left (max 0 (floor (/ (- width (fn-call "strdisplaywidth" footer)) 2))))
          (push-line! (string-append (make-string footer-left #\space) footer))
          (define all-lines (unbox lines))
          (bo-set buf "modifiable" #t)
          (nvim_buf_clear_namespace buf *dashboard-namespace* 0 -1)
          (nvim_buf_set_lines buf 0 -1 #f all-lines)
          (bo-set buf "modifiable" #f)
          (let loop ([i 1])
            (when (<= i (length *dashboard-header*))
              (nvim_buf_set_extmark
                buf *dashboard-namespace* (+ header-start i -1) 0
                (hash "end_row" (+ header-start i)
                      "end_col" 0
                      "hl_group" "SnacksDashboardHeader"
                      "priority" 4096))
              (loop (+ i 1))))
          (for-each
            (lambda (entry)
              (define button (hash-ref (unbox *button-rows*) (car entry)))
              (define r (hash-ref button "row"))
              (define l (hash-ref button "left"))
              (define kc (hash-ref button "key_col"))
              (nvim_buf_set_extmark
                buf *dashboard-namespace* (- r 1) l
                (hash "end_row" (- r 1) "end_col" kc "hl_group" "SnacksDashboardDesc" "priority" 4096))
              (nvim_buf_set_extmark
                buf *dashboard-namespace* (- r 1) kc
                (hash "end_row" r "end_col" 0 "hl_group" "SnacksDashboardKey" "priority" 4096)))
            entries)
          (nvim_buf_set_extmark
            buf *dashboard-namespace* (- (length all-lines) 1) 0
            (hash "end_row" (length all-lines)
                  "end_col" 0
                  "hl_group" "SnacksDashboardHeader"
                  "priority" 4096))
          (when (<= content-height height)
            (nvim_win_call win (lambda () (fn-call "winrestview" (hash "topline" 1))))))

        (render!)

        (define (activate! entry)
          (when (= (nvim_get_current_buf) buf)
            (close!)
            (when (nvim_win_is_valid source)
              (nvim_set_current_win source))
            (state-call 'focus-editor)
            ((caddr entry))))

        (for-each
          (lambda (entry)
            (keymap-set
              "n" (car entry)
              (lambda () (activate! entry))
              (hash "buf" buf "nowait" #t "silent" #t "desc" (cadr entry))))
          entries)

        (define *selected-button* (box #f))

        (define (selection-index)
          (define row (vector-ref (nvim_win_get_cursor win) 0))
          (let loop ([xs entries] [i 1] [best 1] [best-dist 1000000])
            (if (null? xs)
                best
                (let* ([candidate (hash-ref (hash-ref (unbox *button-rows*) (caar xs)) "row")]
                       [dist (abs (- candidate row))])
                  (if (< dist best-dist)
                      (loop (cdr xs) (+ i 1) i dist)
                      (loop (cdr xs) (+ i 1) best best-dist))))))

        (define (select-entry! index)
          (define n (length entries))
          (define wrapped (+ (modulo (+ (- index 1) n) n) 1))
          (define entry (list-ref entries (- wrapped 1)))
          (define button (hash-ref (unbox *button-rows*) (car entry)))
          (unless (equal? (unbox *selected-button*) button)
            (nvim_buf_set_extmark
              buf *selection-namespace* (- (hash-ref button "row") 1) (hash-ref button "left")
              (hash "id" 1
                    "end_col" (+ (hash-ref button "key_col") 1)
                    "hl_group" "CursorLine"
                    "priority" 90))
            (set-box! *selected-button* button))
          (define cursor (nvim_win_get_cursor win))
          (define target-row (hash-ref button "row"))
          (define target-col (- (hash-ref button "key_col") 1))
          (when (or (not (= (vector-ref cursor 0) target-row))
                    (not (= (vector-ref cursor 1) target-col)))
            ;; Keep the hidden cursor on padding so non-blending UIs do not obscure text.
            (nvim_win_set_cursor win (vector target-row target-col))))

        (for-each
          (lambda (pair)
            (define key (car pair))
            (define delta (cdr pair))
            (keymap-set
              "n" key
              (lambda () (select-entry! (+ (selection-index) delta)))
              (hash "buf" buf
                    "nowait" #t
                    "silent" #t
                    "desc" (if (> delta 0) "Next dashboard item" "Previous dashboard item"))))
          '(("j" . 1) ("<Down>" . 1) ("k" . -1) ("<Up>" . -1)))

        (keymap-set
          "n" "<CR>"
          (lambda () (activate! (list-ref entries (- (selection-index) 1))))
          (hash "buf" buf "nowait" #t "silent" #t "desc" "Open dashboard item"))

        (nvim_create_autocmd
          "CursorMoved"
          (hash "buf" buf
                "callback" (lambda (_args)
                             (when (= (nvim_get_current_buf) buf)
                               (select-entry! (selection-index))))))

        (nvim_create_autocmd
          '("VimResized" "WinResized")
          (hash "group" group
                "callback"
                (lambda (_args)
                  (when (and (not (unbox closed)) (nvim_win_is_valid source))
                    (define selected (selection-index))
                    (define width (nvim_win_get_width source))
                    (define height (nvim_win_get_height source))
                    (unless (equal? (unbox *rendered-size*) (cons width height))
                      (when (or (not (= (nvim_win_get_width win) width))
                                (not (= (nvim_win_get_height win) height)))
                        (nvim_win_set_config win (hash "width" width "height" height)))
                      (render!)
                      (select-entry! selected))))))

        (select-entry! 1))))

(keymap-set "n" "<leader>A" open-dashboard (hash "desc" "Open dashboard"))

(nvim_create_autocmd
  "VimEnter"
  (hash "callback"
        (lambda (_args)
          (when (and (= (fn-call "argc") 0)
                     (equal? (nvim_buf_get_name 0) "")
                     (is-source? 0)
                     (= (nvim_buf_line_count 0) 1)
                     (equal? (car (nvim_buf_get_lines 0 0 1 #f)) ""))
            (open-dashboard)))))
