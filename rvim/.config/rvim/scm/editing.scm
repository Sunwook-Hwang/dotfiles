;; 1:1 Steel port of: nvim/.config/nvim/lua/editing.lua
;; Equivalence:
;; - Switches input method back to English on `InsertLeave` (`im-select` on macOS, `ibus` on Linux).
;; - `<leader>u`: replays undo tree in a scratch buffer (`wundo!`/`rundo`) and previews unified diffs
;;   via `text-diff`; applies only on Enter after verifying buffer `changedtick`.
;; - `<leader>TH`: cursor-word highlight on `CursorHold`, cleared on movement/mode/restriction.
;; - `<leader>Ti`/`Tr`/`Tl`/`z`: indent guides, relative numbers, LSP status, and Zen mode toggles.
;; - `<leader>TS`: 8-frame native `<C-d>`/`<C-u>` smooth scroll with `on-key` cancellation.

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/notify")
(require "rvim/schedule")
(require-builtin rvim/system)
(require "rvim/diff")
(require "buffer_policy")
(require "breadcrumbs")
(require "state")

;; Return to English when leaving Insert mode.
(define *english-input-command*
  (cond
    [(and (= (fn-call "has" "macunix") 1) (= (fn-call "executable" "im-select") 1))
     (list (fn-call "exepath" "im-select") "com.apple.keylayout.ABC")]
    [(and (= (fn-call "has" "linux") 1) (= (fn-call "executable" "ibus") 1))
     (list (fn-call "exepath" "ibus") "engine" "xkb:us::eng")]
    [else #f]))

(when *english-input-command*
  (nvim_create_autocmd
    "InsertLeave"
    (hash "group" (nvim_create_augroup "nopack-input-method" (hash "clear" #t))
          "callback" (lambda (_args) (system-run *english-input-command*)))))

;; =========================================
;; ========== UNDO / WHITESPACE ==========
;; =========================================

(define (pad-right s width)
  (define len (string-length s))
  (if (>= len width)
      s
      (string-append s (make-string (- width len) #\space))))

(define (collect-undo-entries branch)
  (apply append
         (map (lambda (entry)
                (define alt (hash-try-get entry "alt"))
                (cons entry (if alt (collect-undo-entries alt) '())))
              branch)))

(define (undo-picker)
  (state-call 'focus-editor)
  (define source (nvim_get_current_buf))
  (cond
    [(or (not (is-source? source)) (not (bo-get source "modifiable")))
     (notify "Undo history is available for editable file buffers" (log-level 'warn))]
    [(< (go-get "columns") 44)
     (notify "Undo preview requires at least 44 terminal columns" (log-level 'warn))]
    [else
     (define tree (fn-call "undotree"))
     (define raw-entries (collect-undo-entries (or (hash-try-get tree "entries") '())))
     (if (null? raw-entries)
         (notify "No undo history for this buffer yet" (log-level 'info))
         (let* ([sorted (sort raw-entries (lambda (a b) (> (hash-ref a "seq") (hash-ref b "seq"))))]
                [entries (append sorted (list (hash "seq" 0)))]
                [tick (nvim_buf_get_changedtick source)]
                [lines (nvim_buf_get_lines source 0 -1 #f)]
                [path (fn-call "tempname")]
                [replay (nvim_create_buf #f #t)]
                [seq-cur (hash-try-get tree "seq_cur")])
           (define (cleanup)
             (when (nvim_buf_is_valid replay)
               (nvim_buf_delete replay (hash "force" #t))))
           (define items
             (map (lambda (entry)
                    (define seq (hash-ref entry "seq"))
                    (define stamp
                      (if (= seq 0)
                          "Initial state"
                          (fn-call "strftime" "%m-%d %H:%M:%S" (hash-ref entry "time"))))
                    (hash "seq" seq
                          "label" (string-append
                                    "#" (pad-right (number->string seq) 5) " "
                                    stamp
                                    (if (hash-try-get entry "save") " [saved]" "")
                                    (if (equal? seq seq-cur) " [current]" ""))
                          "action"
                          (lambda ()
                            (if (or (not (nvim_buf_is_valid source))
                                    (not (= (nvim_buf_get_changedtick source) tick)))
                                (notify "Buffer changed while browsing undo history; reopen the list"
                                        (log-level 'warn))
                                (begin
                                  (nvim_set_current_buf source)
                                  (cmd (string-append "undo " (number->string seq))))))))
                  entries))
           (define escaped (fn-call "fnameescape" path))
           (with-handler
             (lambda (err)
               (fn-call "delete" path)
               (cleanup)
               (define active (state-get 'active-picker))
               (when active
                 ((hash-ref active "close")))
               (notify (string-append "Unable to preview undo history: " (to-string err))
                       (log-level 'error)))
             (cmd (string-append "silent wundo! " escaped))
             (bo-set replay "undolevels" 1000)
             (nvim_buf_set_lines replay 0 -1 #f lines)
             (nvim_buf_call replay (lambda () (cmd (string-append "silent rundo " escaped))))
             (state-call
               'open-picker
               "Undo · Enter: apply · Esc: cancel"
               (hash "items" items
                     "cancel" cleanup
                     "preview"
                     (lambda (item buf win)
                       (define seq (hash-ref item "seq"))
                       (define before (box '()))
                       (define after (box '()))
                       (nvim_buf_call
                         replay
                         (lambda ()
                           (cmd (string-append "noautocmd silent undo " (number->string seq)))
                           (set-box! after (nvim_buf_get_lines replay 0 -1 #f))
                           (when (> seq 0)
                             (cmd "noautocmd silent undo"))
                           (set-box! before (nvim_buf_get_lines replay 0 -1 #f))))
                       (define diff
                         (text-diff
                           (string-append (string-join (unbox before) "\n") "\n")
                           (string-append (string-join (unbox after) "\n") "\n")
                           (hash "result_type" "unified"
                                 "ctxlen" 4
                                 "ignore_cr_at_eol" #t
                                 "ignore_whitespace_change_at_eol" #t
                                 "indent_heuristic" #t)))
                       (bo-set buf "modifiable" #t)
                       (nvim_buf_set_lines
                         buf 0 -1 #f
                         (if (equal? diff "")
                             '("No changes")
                             (filter (lambda (s) (not (equal? s ""))) (split-many diff "\n"))))
                       (bo-set buf "syntax" "diff")
                       (bo-set buf "modifiable" #f)
                       (nvim_win_set_cursor win (vector 1 0))
                       (nvim_win_set_config
                         win
                         (hash "title" (string-append "Change #" (number->string seq) " · Ctrl-f/b: scroll"))))))
             (fn-call "delete" path))))]))

(keymap-set "n" "<leader>u" undo-picker (hash "desc" "Preview undo states (Enter to apply)"))

;; <leader>TH: show other occurrences only while resting on a word.
(define *cursor-word-enabled* (box #f))

(define (clear-cursor-word! win)
  (when (nvim_win_is_valid win)
    (define id (w-get win "cursor_word_match"))
    (when id
      (with-handler (lambda (_e) #f) (fn-call "matchdelete" id win))
      (w-set win "cursor_word_match" #f))))

(define (highlight-cursor-word!)
  (when (unbox *cursor-word-enabled*)
    (define win (nvim_get_current_win))
    (define buf (nvim_get_current_buf))
    (when (and (allows? buf) (equal? (fn-call "mode") "n"))
      (define word (fn-call "expand" "<cword>"))
      (define pat (string-append "\\%" (number->string (fn-call "col" ".")) "c\\k"))
      (unless (or (equal? word "")
                  (equal? (fn-call "matchstr" (nvim_get_current_line) pat) ""))
        (clear-cursor-word! win)
        (w-set win "cursor_word_match"
               (fn-call "matchadd" "CursorWord"
                        (string-append "\\C\\V\\<" (fn-call "escape" word "\\") "\\>")
                        -1))))))

(cmd "highlight default link CursorWord Visual")
(define *cursor-word-group* (nvim_create_augroup "nopack-cursor-word" (hash "clear" #t)))

(nvim_create_autocmd
  "User"
  (hash "group" *cursor-word-group*
        "pattern" "NopackBufferRestricted"
        "callback" (lambda (args)
                     (for-each clear-cursor-word!
                               (fn-call "win_findbuf" (hash-ref (hash-ref args "data") "buf"))))))

(nvim_create_autocmd
  "ColorScheme"
  (hash "group" *cursor-word-group*
        "callback" (lambda (_args) (cmd "highlight default link CursorWord Visual"))))

(nvim_create_autocmd
  "CursorHold"
  (hash "group" *cursor-word-group*
        "callback" (lambda (_args) (highlight-cursor-word!))))

(nvim_create_autocmd
  '("CursorMoved" "InsertEnter" "ModeChanged" "WinLeave" "BufLeave" "TextChanged")
  (hash "group" *cursor-word-group*
        "callback" (lambda (_args)
                     (when (unbox *cursor-word-enabled*)
                       (clear-cursor-word! (nvim_get_current_win))))))

(keymap-set
  "n"
  "<leader>TH"
  (lambda ()
    (set-box! *cursor-word-enabled* (not (unbox *cursor-word-enabled*)))
    (if (unbox *cursor-word-enabled*)
        (highlight-cursor-word!)
        (for-each clear-cursor-word! (nvim_list_wins))))
  (hash "desc" "Toggle cursor word highlight"))

;; <leader>Ti / Tr / Tl / z toggles.
(keymap-set "n" "<leader>Ti" "<Cmd>set list!<CR>"
            (hash "desc" "Toggle indent guides / whitespace markers"))
(keymap-set "n" "<leader>Tr" (lambda () (state-call 'toggle-relative-numbers))
            (hash "desc" "Toggle relative line numbers globally"))
(keymap-set
  "n"
  "<leader>Tl"
  (lambda ()
    (state-set! 'language-status-visible (not (state-get 'language-status-visible #t)))
    (cmd "redrawstatus"))
  (hash "desc" "Toggle LSP / formatter status"))

(keymap-set
  "n"
  "<leader>z"
  (lambda ()
    (define visible
      (and (= (go-get "showtabline") 0)
           (not (breadcrumbs-enabled?))
           (not (state-get 'language-status-visible #t))))
    (go-set "showtabline" (if visible 2 0))
    (state-set! 'language-status-visible visible)
    (breadcrumbs-set-enabled! visible)
    (cmd "redrawstatus")
    (notify (string-append "Zen mode: " (if visible "OFF" "ON"))))
  (hash "desc" "Toggle Zen mode (tabline / breadcrumbs / LSP status)"))

;; <leader>TS: animate native Ctrl-d/u views, including wrapped lines and folds.
(define *smooth-enabled* (box #f))
(define *smooth-animation* (box #f))
(define *smooth-keys-ns* (nvim_create_namespace "nopack-smooth-scroll"))

(define (stop-smooth! finish)
  (define st (unbox *smooth-animation*))
  (when st
    (set-box! *smooth-animation* #f)
    (on-key #f *smooth-keys-ns*)
    (when (and finish
               (= (nvim_get_current_win) (hash-ref st "win"))
               (= (nvim_get_current_buf) (hash-ref st "buf"))
               (= (nvim_buf_get_changedtick (hash-ref st "buf")) (hash-ref st "tick"))
               (or (not (unbox (hash-ref st "view")))
                   (equal? (unbox (hash-ref st "view")) (fn-call "winsaveview"))))
      (fn-call "winrestview" (hash-ref st "target")))))

(define (smooth-scroll! key)
  (stop-smooth! #t)
  (define count (or (v-get "count") 0))
  (define keycode (nvim_replace_termcodes key #t #f #t))
  (define keys (string-append (if (> count 0) (number->string count) "") keycode))
  (define win (nvim_get_current_win))
  (define buf (nvim_get_current_buf))
  (if (or (not (unbox *smooth-enabled*))
          (not (equal? (hash-try-get (nvim_win_get_config win) "relative") ""))
          (wo-get win "diff")
          (wo-get win "scrollbind")
          (wo-get win "cursorbind")
          (not (allows? buf))
          (not (equal? (fn-call "reg_executing") ""))
          (not (equal? (fn-call "reg_recording") "")))
      (cmd (string-append "normal! " keys))
      (let ([first (fn-call "winsaveview")])
        (cmd (string-append "normal! " keys))
        (define target (fn-call "winsaveview"))
        (define amount (wo-get win "scroll"))
        (unless (equal? first target)
          (define steps (min 8 amount))
          (define frames
            (let loop ([step 1] [acc '()])
              (if (>= step steps)
                  (reverse (cons target acc))
                  (begin
                    (fn-call "winrestview" first)
                    (cmd (string-append "normal! "
                                        (number->string (floor (/ (* amount step) steps)))
                                        keycode))
                    (loop (+ step 1) (cons (fn-call "winsaveview") acc))))))
          (wo-local-set win "scroll" amount)
          (fn-call "winrestview" first)
          (define st
            (hash "win" win
                  "buf" buf
                  "tick" (nvim_buf_get_changedtick buf)
                  "target" target
                  "view" (box #f)))
          (define width (nvim_win_get_width win))
          (define height (nvim_win_get_height win))
          (set-box! *smooth-animation* st)
          (define step-box (box 0))
          (define (advance)
            (when (equal? (unbox *smooth-animation*) st)
              (if (or (not (= (nvim_get_current_win) win))
                      (not (= (nvim_get_current_buf) buf))
                      (not (= (nvim_buf_get_changedtick buf) (hash-ref st "tick")))
                      (not (equal? (fn-call "mode") "n"))
                      (not (= (nvim_win_get_width win) width))
                      (not (= (nvim_win_get_height win) height))
                      (and (unbox (hash-ref st "view"))
                           (not (equal? (unbox (hash-ref st "view")) (fn-call "winsaveview")))))
                  (stop-smooth! #f)
                  (begin
                    (set-box! step-box (+ (unbox step-box) 1))
                    (define cur-step (unbox step-box))
                    (fn-call "winrestview" (list-ref frames (- cur-step 1)))
                    (cmd "redraw")
                    (set-box! (hash-ref st "view") (fn-call "winsaveview"))
                    (if (< cur-step steps)
                        (defer-fn advance 16)
                        (stop-smooth! #f))))))
          (on-key (lambda (_k) (stop-smooth! #t)) *smooth-keys-ns*)
          (advance)))))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackBufferRestricted"
        "callback" (lambda (args)
                     (define st (unbox *smooth-animation*))
                     (when (and st (= (hash-ref st "buf") (hash-ref (hash-ref args "data") "buf")))
                       (stop-smooth! #f)))))

(keymap-set "n" "<C-d>" (lambda () (smooth-scroll! "<C-d>")) (hash "desc" "Scroll down half a page"))
(keymap-set "n" "<C-u>" (lambda () (smooth-scroll! "<C-u>")) (hash "desc" "Scroll up half a page"))
(keymap-set
  "n"
  "<leader>TS"
  (lambda ()
    (stop-smooth! #t)
    (set-box! *smooth-enabled* (not (unbox *smooth-enabled*)))
    (notify (string-append "Smooth scroll " (if (unbox *smooth-enabled*) "enabled" "disabled"))))
  (hash "desc" "Toggle smooth scroll"))

(nvim_create_autocmd
  '("BufLeave" "WinLeave" "ModeChanged" "VimResized")
  (hash "group" (nvim_create_augroup "nopack-smooth-scroll" (hash "clear" #t))
        "callback" (lambda (_args) (stop-smooth! #f))))
