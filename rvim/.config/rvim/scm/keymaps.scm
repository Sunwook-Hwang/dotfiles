;; 1:1 Steel port of: nvim/.config/nvim/lua/keymaps.lua
;; Equivalence:
;; - Exact insert pairs (`()`, `[]`, `{}`, `''`, `""`, `` `` ``) + `<BS>` empty-pair delete.
;; - Exact `*`/`#` in-place literal word search, `jk`, `<Esc>`, `+/-`, `<C-s>`, `<C-w>o` zoom,
;;   `<C-h/j/k/l>`, `<S-Up/Down/Left/Right>`, `x`, `p`/`P` cursor-clamp, `n`/`N`, `<leader>w`,
;;   `<leader>a`, `<leader>Sa`/`<leader>Sf`, `<`/`>`, yank highlight, OSC52 yank hook,
;;   and shared `map` helper.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/fn")
(require "rvim/cmd")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/clipboard")
(require "rvim/string")
(require "buffer_policy")
(require "state")

(keymap-set "i" "jk" "<esc>" (hash "noremap" #t "silent" #t))

;; Native insert pairs
(define insert-pairs
  (hash "(" ")" "[" "]" "{" "}" "'" "'" "\"" "\"" "`" "`"))

(define (trailing-backslashes-odd? text)
  (= (modulo (string-length (or (string/match text "\\+$") "")) 2) 1))

(define (word-char? ch)
  (not (not (string/match ch "[%w_]"))))

(define (pair-mapping key callback desc)
  (define plug (string-append "<Plug>(nopack-pair-" (number->string (char->integer (string-ref key 0))) ")"))
  (keymap-set "i" key (string-append "<Ignore>" plug) (hash "desc" desc))
  (keymap-set "i" plug callback (hash "expr" #t)))

(for-each
  (lambda (opening)
    (define closing (hash-ref insert-pairs opening))
    (pair-mapping
      opening
      (lambda ()
        (if (not (allows? 0))
            opening
            (let* ((line (nvim_get_current_line))
                   (col (vector-ref (nvim_win_get_cursor 0) 1))
                   (before (substring line 0 (min col (string-length line))))
                   (after (if (< col (string-length line))
                              (substring line col (+ col 1))
                              "")))
              (cond
                ((trailing-backslashes-odd? before) opening)
                ((and (equal? opening closing) (equal? after closing)) "<C-g>U<Right>")
                ((or (word-char? after)
                     (and (equal? opening "'")
                          (string/match before "[%w_]$")))
                 opening)
                (else (string-append opening closing "<C-g>U<Left>"))))))
      (string-append "Insert " opening closing " pair"))
    (unless (equal? opening closing)
      (pair-mapping
        closing
        (lambda ()
          (if (allows? 0)
              (let* ((line (nvim_get_current_line))
                     (col (vector-ref (nvim_win_get_cursor 0) 1))
                     (before (substring line 0 (min col (string-length line))))
                     (after (if (< col (string-length line))
                                (substring line col (+ col 1))
                                "")))
                (if (and (equal? after closing) (not (trailing-backslashes-odd? before)))
                    "<C-g>U<Right>"
                    closing))
              closing))
        (string-append "Skip closing " closing))))
  (hash-keys->list insert-pairs))

(pair-mapping
  "<BS>"
  (lambda ()
    (if (allows? 0)
        (let* ((line (nvim_get_current_line))
               (col (vector-ref (nvim_win_get_cursor 0) 1)))
          (if (and (> col 0)
                   (< col (string-length line))
                   (equal? (hash-try-get insert-pairs (substring line (- col 1) col))
                           (substring line col (+ col 1)))
                   (not (trailing-backslashes-odd? (substring line 0 (- col 1)))))
              "<BS><Del>"
              "<BS>"))
        "<BS>"))
  "Delete an empty pair")

;; Clear search highlight
(keymap-set "n" "<ESC>" ":nohl<CR>" (hash "noremap" #t "silent" #t))

;; Literal word search without moving cursor
(define (search-word direction)
  (define word (fn-call "expand" "<cword>"))
  (unless (equal? word "")
    (define pat (string-append "\\V" (fn-call "escape" word "\\")))
    (when (>= (fn-call "match" word "^\\k") 0)
      (set! pat (string-append "\\<" pat)))
    (when (>= (fn-call "match" word "\\k$") 0)
      (set! pat (string-append pat "\\>")))
    (fn-call "setreg" "/" pat)
    (fn-call "histadd" "search" pat)
    (v-set "searchforward" direction)
    (v-set "hlsearch" (if (opt-get "hlsearch") 1 0))))

(keymap-set "n" "*" (lambda () (search-word 1)) (hash "desc" "Search current word forward without moving"))
(keymap-set "n" "#" (lambda () (search-word 0)) (hash "desc" "Search current word backward without moving"))

(keymap-set "n" "+" "<C-a>" (hash "noremap" #t "silent" #t))
(keymap-set "n" "-" "<C-x>" (hash "noremap" #t "silent" #t))
(keymap-set "t" "<Esc><Esc>" "<C-\\><C-n>" (hash "desc" "Exit terminal mode"))

;; Undo break-points
(for-each
  (lambda (pair)
    (keymap-set "i" (car pair) (cdr pair) (hash "noremap" #t "silent" #t)))
  (list (cons "," ",<c-g>u") (cons "." ".<c-g>u") (cons ";" ";<c-g>u") (cons "<" "<<C-g>u")))

;; Insert-mode alt-arrow window navigation
(for-each
  (lambda (pair)
    (keymap-set "i" (car pair) (cdr pair) (hash "noremap" #t "silent" #t)))
  (list (cons "<A-Up>" "<C-\\><C-N><C-w>k")
        (cons "<A-Down>" "<C-\\><C-N><C-w>j")
        (cons "<A-Left>" "<C-\\><C-N><C-w>h")
        (cons "<A-Right>" "<C-\\><C-N><C-w>l")))

;; Save
(keymap-set "i" "<C-s>" "<ESC><cmd>w<CR>" (hash "noremap" #t "silent" #t))
(keymap-set "n" "<C-s>" ":w<CR>" (hash "noremap" #t "silent" #t))

;; Window zoom toggle
(define (invalidate-split-zoom! tab)
  (when (and (nvim_tabpage_is_valid tab) (t-get tab "flash_zoom"))
    (define editors
      (length (filter is-editor? (nvim_tabpage_list_wins tab))))
    (when (> editors 1)
      (t-set tab "flash_zoom" #f))))

(nvim_create_autocmd
  "WinNew"
  (hash "group" (nvim_create_augroup "flash-window-zoom" (hash "clear" #t))
        "callback"
        (lambda (_args)
          (define tab (nvim_get_current_tabpage))
          (when (t-get tab "flash_zoom")
            (schedule (lambda () (invalidate-split-zoom! tab)))))))

(define (restore-window-zoom! tab win)
  (invalidate-split-zoom! tab)
  (define zoom (t-get tab "flash_zoom"))
  (when zoom
    (define source (hash-ref zoom "source"))
    (cond
      ((or (not (is-editor? source)) (not (is-editor? win)))
       (t-set tab "flash_zoom" #f)
       (notify "Original editor window closed; keeping the zoom tab"))
      (else
       (define buf (nvim_win_get_buf win))
       (if (and (wo-get source "winfixbuf") (not (= (nvim_win_get_buf source) buf)))
           (notify "Original window has winfixbuf enabled; unlock it before restoring zoom")
           (let* ((view (nvim_win_call win (lambda () (fn-call "winsaveview"))))
                  (non-float
                    (filter (lambda (w) (equal? (hash-try-get (nvim_win_get_config w) "relative") ""))
                            (nvim_tabpage_list_wins tab))))
             (nvim_win_set_buf source buf)
             (if (= (length non-float) 1)
                 (begin (nvim_set_current_win win) (cmd "tabclose"))
                 (t-set tab "flash_zoom" #f))
             (nvim_set_current_win source)
             (fn-call "winrestview" view)))))))

(define (restore-window-zooms!)
  (for-each
    (lambda (tab)
      (define zoom (t-get tab "flash_zoom"))
      (when zoom
        (restore-window-zoom! tab (hash-ref zoom "win"))))
    (nvim_list_tabpages)))

(state-set! 'restore-window-zooms restore-window-zooms!)

(define (toggle-window-zoom)
  (when (is-editor? 0)
    (define tab (nvim_get_current_tabpage))
    (invalidate-split-zoom! tab)
    (cond
      ((t-get tab "flash_zoom")
       (restore-window-zoom! tab (nvim_get_current_win)))
      ((> (length (nvim_tabpage_list_wins tab)) 1)
       (define source (nvim_get_current_win))
       (cmd "tab split")
       (t-set (nvim_get_current_tabpage)
              "flash_zoom"
              (hash "source" source "win" (nvim_get_current_win)))))))

(keymap-set "n" "<C-w>o" toggle-window-zoom (hash "silent" #t "desc" "Toggle editor window zoom"))
(keymap-set "n" "<C-w><C-o>" toggle-window-zoom (hash "silent" #t "desc" "Toggle editor window zoom"))

;; Window movement & resize
(for-each
  (lambda (dir)
    (keymap-set "n" (string-append "<C-" dir ">") (string-append "<C-w>" dir) (hash "noremap" #t "silent" #t))
    (keymap-set "t" (string-append "<C-" dir ">") (string-append "<C-\\><C-n><C-w>" dir) (hash "silent" #t)))
  (list "h" "j" "k" "l"))

(for-each
  (lambda (pair)
    (define k (car pair))
    (define ex (cdr pair))
    (keymap-set "n" (string-append "<S-" k ">") (string-append ":" ex "<CR>") (hash "noremap" #t "silent" #t))
    (keymap-set "t" (string-append "<S-" k ">") (lambda () (cmd ex)) (hash "silent" #t)))
  (list (cons "Up" "resize -5")
        (cons "Down" "resize +5")
        (cons "Left" "vertical resize -5")
        (cons "Right" "vertical resize +5")))

;; Yank/paste tweaks
(keymap-set "n" "x" "\"_x" (hash "noremap" #t "silent" #t))

(define put-start "<Plug>(nopack-put-start)")
(define *block-put-multiline* (box #f))

(define (put-keys command)
  (set-box! *block-put-multiline* #f)
  (define reg (v-get "register"))
  (when (and (equal? (fn-call "mode") "\x16")
             (equal? (fn-call "getregtype" reg) "v"))
    (define txt (fn-call "getreg" reg))
    (set-box! *block-put-multiline* (string-contains? txt "\n")))
  (string-append command put-start))

(keymap-set
  "n"
  put-start
  (lambda ()
    (define first (nvim_buf_get_mark 0 "["))
    (define row (vector-ref first 0))
    (define col (vector-ref first 1))
    (when (unbox *block-put-multiline*)
      (define line (car (nvim_buf_get_lines 0 (- row 1) row #f)))
      (set! col (max 0 (fn-call "match" line ".$"))))
    (when (and (> row 0)
               (or (unbox *block-put-multiline*)
                   (> (vector-ref (nvim_win_get_cursor 0) 0) row)))
      (nvim_win_set_cursor 0 (vector row col)))
    (set-box! *block-put-multiline* #f)))

(keymap-set "n" "p" (lambda () (put-keys "p")) (hash "expr" #t "silent" #t))
(keymap-set "x" "p" (lambda () (put-keys "P")) (hash "expr" #t "silent" #t))
(keymap-set "x" "P" "P" (hash "noremap" #t "silent" #t))

;; Search centering, diff, select-all, visual indent
(keymap-set "n" "n" "nzzzv" (hash "noremap" #t "silent" #t))
(keymap-set "n" "N" "Nzzzv" (hash "noremap" #t "silent" #t))
(keymap-set "n" "<leader>w" ":windo diffthis<CR>" (hash "noremap" #t "silent" #t "desc" "Diff all windows"))
(keymap-set "n" "<leader>a" "gg<S-v>G" (hash "noremap" #t "silent" #t "desc" "Select entire file"))
(keymap-set "v" "<" "<gv" (hash "noremap" #t "silent" #t))
(keymap-set "v" ">" ">gv" (hash "noremap" #t "silent" #t))

;; Substitute helpers
(for-each
  (lambda (pair)
    (define suffix (car pair))
    (define rng (cdr pair))
    (keymap-set "n" (string-append "<leader>" suffix)
                (string-append ":" rng "s/\\<<C-r><C-w>\\>/")
                (hash "desc" "Substitute word"))
    (keymap-set "x" (string-append "<leader>" suffix)
                (lambda ()
                  (define saved (fn-call "getreginfo" "\""))
                  (define scratch (fn-call "getreginfo" "z"))
                  (cmd "normal! \"zy")
                  (define raw (fn-call "escape" (fn-call "getreg" "z") "\\/"))
                  (define pat (string-replace raw "\n" "\\n"))
                  (fn-call "setreg" "z" scratch)
                  (fn-call "setreg" "\"" saved)
                  (nvim_feedkeys (string-append ":" rng "s/\\V" pat "/") "ni" #t))
                (hash "desc" "Substitute selection")))
  (list (cons "Sa" "%") (cons "Sf" ".,$")))

;; Yank highlight
(nvim_create_autocmd
  "TextYankPost"
  (hash "desc" "Highlight when yanking (copying) text"
        "group" (nvim_create_augroup "kickstart-highlight-yank" (hash "clear" #t))
        "callback" (lambda (_args) (state-call 'highlight-yank))))

;; OSC52 yank hook on SSH/herdr
(when (state-get 'use-osc52)
  (nvim_create_autocmd
    "TextYankPost"
    (hash "group" (nvim_create_augroup "nopack-osc52-yank" (hash "clear" #t))
          "callback"
          (lambda (_args)
            (define ev (v-get "event"))
            (when (and (equal? (hash-try-get ev "operator") "y")
                       (equal? (hash-try-get ev "regname") ""))
              (define lines (hash-ref ev "regcontents"))
              (define out (if (equal? (hash-try-get ev "regtype") "V")
                              (append lines (list ""))
                              lines))
              (define joined (string-join out "\n"))
              (if (> (string-length joined) 100000)
                  (notify "OSC52 yank skipped: selection exceeds 100 KB" (log-level 'warn))
                  (osc52-copy "+" out)))))))

;; Shared map helper
(state-set! 'map
            (lambda (mode lhs rhs desc)
              (keymap-set mode lhs rhs (hash "silent" #t "desc" desc))))
