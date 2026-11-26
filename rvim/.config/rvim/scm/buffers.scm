;; 1:1 Steel port of: nvim/.config/nvim/lua/buffers.lua
;; Equivalence:
;; - Native Barbar replacement: shared display order (`*buffer-order*`) for tabline,
;;   `<S-l>`/`<S-h>`/`]b`/`[b` cycling, `<A-1..9>` direct jump, `<leader>bj`/`bk` reorder,
;;   `<leader>bD`/`bL` sort, and `<leader>be`/`bm`/`bh`/`bl` side-closing.
;; - Preserves splits when closing buffers (`delete-buffer`), merging duplicate editor panes
;;   only when a single listed buffer remains.
;; - Shows a 750ms floating buffer list when cycling in Zen mode (tabline/breadcrumbs/LSP hidden).

(require-builtin rvim/api)
(require-builtin rvim/util)
(require-builtin rvim/steel)
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "breadcrumbs")
(require "state")

(define *buffer-order* (box '()))
(define *tabline-cache* (box #f))

(define (buffer-highlights!)
  (define sel0 (nvim_get_hl 0 (hash "name" "TabLineSel" "link" #f)))
  (define colors-name (or (g-get "colors_name") ""))
  (define is-ayu (not (not (string/match colors-name "^ayu"))))
  (define buffer-highlights
    (cond
      [is-ayu
       (define normal (nvim_get_hl 0 (hash "name" "Normal" "link" #f)))
       ;; Prevent TabLine's reverse attribute from combining with these colors.
       (values (hash "bg" (hash-try-get normal "fg")
                     "fg" (hash-try-get normal "bg")
                     "bold" #t
                     "nocombine" #t
                     "cterm" (hash "nocombine" #t))
               (hash "bg" (hash-try-get normal "bg")
                     "fg" (hash-try-get normal "fg")
                     "nocombine" #t
                     "cterm" (hash "nocombine" #t))
               (hash "link" "NopackBufferInactive"))]
      [(and (not (hash-try-get sel0 "bg")) (not (hash-try-get sel0 "reverse")))
       (define normal (nvim_get_hl 0 (hash "name" "Normal" "link" #f)))
       (define accent (nvim_get_hl 0 (hash "name" "Special" "link" #f)))
       (define tab (nvim_get_hl 0 (hash "name" "TabLine" "link" #f)))
       (values (hash "bg" (or (hash-try-get accent "fg") (hash-try-get normal "fg"))
                     "fg" (hash-try-get normal "bg")
                     "bold" #t)
               (hash "bg" (or (hash-try-get tab "bg") (hash-try-get normal "bg"))
                     "fg" (or (hash-try-get tab "fg") (hash-try-get normal "fg")))
               (hash "link" "NopackBufferInactive"))]
      [else
       (values sel0 (hash "link" "TabLine") (hash "link" "TabLineFill"))]))
  (define selected (list-ref buffer-highlights 0))
  (define inactive (list-ref buffer-highlights 1))
  (define fill (list-ref buffer-highlights 2))
  (nvim_set_hl 0 "NopackBufferCurrent" selected)
  (nvim_set_hl 0 "NopackBufferInactive" inactive)
  (nvim_set_hl 0 "NopackBufferFill" fill))

(buffer-highlights!)
(nvim_create_autocmd "ColorScheme" (hash "callback" (lambda (_args) (buffer-highlights!))))

(define (listed-tab-buffer? buf)
  (and (nvim_buf_is_valid buf)
       (bo-get buf "buflisted")
       (or (is-source? buf) (equal? (bo-get buf "buftype") "terminal"))))

(define (buffers)
  (define kept (filter listed-tab-buffer? (unbox *buffer-order*)))
  (define seen
    (foldl (lambda (b acc) (hash-insert acc b #t)) (hash) kept))
  (define added
    (filter (lambda (b) (and (not (hash-contains? seen b)) (listed-tab-buffer? b)))
            (vector->list (nvim_list_bufs))))
  (define result (append kept added))
  (set-box! *buffer-order* result)
  result)

(state-set! 'buffers buffers)

(define (buffer-index buf (items #f))
  (define list-items (or items (buffers)))
  (let loop ([xs list-items] [i 1])
    (cond
      [(null? xs) 1]
      [(= (car xs) buf) i]
      [else (loop (cdr xs) (+ i 1))])))

(define (nopack-tabline-click buf _clicks button _mods)
  (when (and (equal? button "l") (nvim_buf_is_valid buf))
    (state-call 'select-buffer buf)))

(define (nopack-tabline)
  (define cached (unbox *tabline-cache*))
  (if cached
      cached
      (let* ([cur (nvim_get_current_buf)]
             [items
              (let loop ([xs (buffers)] [i 1] [acc '()])
                (if (null? xs)
                    (reverse acc)
                    (let* ([b (car xs)]
                           [raw (fn-call "fnamemodify" (nvim_buf_get_name b) ":t")]
                           [name (if (equal? raw "") "[No Name]" raw)]
                           [hl (if (= b cur) "%#NopackBufferCurrent#" "%#NopackBufferInactive#")]
                           [mod (if (bo-get b "modified") " + " " ")]
                           [part (string-append
                                   hl "%" (number->string b) "@v:steel.NopackTablineClick@ "
                                   (number->string i) ":" (vector-ref (string/gsub name "%%" "%%%%") 0) mod "%T")])
                      (loop (cdr xs) (+ i 1) (cons part acc)))))]
             [rendered (string-append (apply string-append items) "%#NopackBufferFill#")])
        (set-box! *tabline-cache* rendered)
        rendered)))

(state-set! 'NopackTablineClick nopack-tabline-click)
(steel-export! 'NopackTablineClick nopack-tabline-click)
(state-set! 'NopackTabline nopack-tabline)
(steel-export! 'NopackTabline nopack-tabline)
(opt-set "tabline" "%!v:steel.NopackTabline()")

(keymap-set
  "n"
  "<leader>Tt"
  (lambda ()
    (go-set "showtabline" (if (= (go-get "showtabline") 0) 2 0)))
  (hash "desc" "Toggle tabline"))

(define (invalidate-tabline! _args)
  (set-box! *tabline-cache* #f))

(define *tabline-events*
  (let ([base '("BufAdd" "BufDelete" "BufEnter" "BufFilePost" "FileType" "TermOpen")])
    (if (= (fn-call "has" "nvim-0.13") 0)
        (append base '("BufModifiedSet"))
        base)))

(nvim_create_autocmd *tabline-events* (hash "callback" invalidate-tabline!))
(nvim_create_autocmd
  "OptionSet"
  (hash "pattern" '("buflisted" "buftype" "modified")
        "callback" invalidate-tabline!))

;; =========================================
;; ======= BUFFER PICKER / KEYMAPS =======
;; =========================================

(define *cycle-win* (box #f))
(define *cycle-generation* (box 0))
(define *cycle-namespace* (nvim_create_namespace "nopack-buffer-cycle"))

(define (close-cycle-list!)
  (set-box! *cycle-generation* (+ (unbox *cycle-generation*) 1))
  (define w (unbox *cycle-win*))
  (when (and w (nvim_win_is_valid w))
    (nvim_win_close w #t))
  (set-box! *cycle-win* #f))

(nvim_create_autocmd
  '("BufLeave" "WinLeave" "InsertEnter" "VimResized")
  (hash "callback" (lambda (_args) (close-cycle-list!))))

(nvim_create_autocmd
  "OptionSet"
  (hash "pattern" "showtabline"
        "callback" (lambda (_args) (close-cycle-list!))))

(define (list-slice xs start count)
  (let loop ([ys (drop xs (- start 1))] [n count] [acc '()])
    (if (or (<= n 0) (null? ys))
        (reverse acc)
        (loop (cdr ys) (- n 1) (cons (car ys) acc)))))

(define (select-cycle-buffer! buf items)
  (define previous (nvim_get_current_buf))
  (state-call 'select-buffer buf)
  (unless (or (= buf previous)
              (not (= (go-get "showtabline") 0))
              (state-get 'language-status-visible #t)
              (breadcrumbs-enabled?)
              (not (equal? (fn-call "reg_recording") ""))
              (not (equal? (fn-call "reg_executing") "")))
    (define height (min 5 (length items) (- (go-get "lines") (go-get "cmdheight") 4)))
    (define width (min 60 (- (go-get "columns") 4)))
    (when (and (>= height 1) (>= width 1))
      (define index (buffer-index buf items))
      (define first (max 1 (min (- index (floor (/ height 2))) (+ (- (length items) height) 1))))
      (define window-items (list-slice items first height))
      (define lines
        (let loop ([xs window-items] [i first] [acc '()])
          (if (null? xs)
              (reverse acc)
              (let* ([b (car xs)]
                     [name (fn-call "fnamemodify" (nvim_buf_get_name b) ":t")]
                     [line (string-append
                             (if (= i index) "> " "  ")
                             (number->string i) ": "
                             (if (equal? name "") "[No Name]" name)
                             (if (bo-get b "modified") " +" ""))])
                (loop (cdr xs) (+ i 1) (cons line acc))))))
      (define list-buf (nvim_create_buf #f #t))
      (bo-set list-buf "bufhidden" "wipe")
      (nvim_buf_set_lines list-buf 0 -1 #f lines)
      (nvim_buf_set_extmark
        list-buf *cycle-namespace* (- index first) 0
        (hash "line_hl_group" "NopackBufferCurrent"))
      (set-box! *cycle-win*
                (nvim_open_win
                  list-buf #f
                  (hash "relative" "editor"
                        "row" 1
                        "col" (floor (/ (- (go-get "columns") width) 2))
                        "width" width
                        "height" height
                        "style" "minimal"
                        "border" "rounded"
                        "focusable" #f
                        "noautocmd" #t)))
      (define generation (unbox *cycle-generation*))
      (defer-fn
        (lambda ()
          (when (= (unbox *cycle-generation*) generation)
            (close-cycle-list!)))
        750))))

(define (pick-buffer)
  (define items
    (map (lambda (b)
           (define name (nvim_buf_get_name b))
           (hash "bufnr" b
                 "filename" (if (equal? name "") #f name)
                 "label" (string-append
                           (number->string b) ": "
                           (if (equal? name "") "[No Name]" (fn-call "fnamemodify" name ":~:.")))))
         (buffers)))
  (state-call 'open-picker "Buffers" (hash "items" items)))

(for-each
  (lambda (pair)
    (define key (car pair))
    (define direction (cdr pair))
    (keymap-set
      "n"
      key
      (lambda ()
        (state-call 'focus-editor)
        (define items (buffers))
        (define count (length items))
        (when (> count 0)
          (define index (buffer-index (nvim_get_current_buf) items))
          (define delta (if (equal? direction "bnext") 1 -1))
          (define next-idx (modulo (+ (- index 1) delta count) count))
          (select-cycle-buffer! (list-ref items next-idx) items)))
      (hash "desc" (if (equal? direction "bnext") "Next buffer" "Previous buffer"))))
  '(("<S-l>" . "bnext") ("<S-h>" . "bprevious") ("]b" . "bnext") ("[b" . "bprevious")))

(define (move-list-item xs from-idx to-idx)
  (define item (list-ref xs (- from-idx 1)))
  (define without
    (append (take xs (- from-idx 1)) (drop xs from-idx)))
  (append (take without (- to-idx 1)) (list item) (drop without (- to-idx 1))))

(for-each
  (lambda (pair)
    (define key (car pair))
    (define delta (cdr pair))
    (keymap-set
      "n"
      (string-append "<leader>" key)
      (lambda ()
        (state-call 'focus-editor)
        (define cur (nvim_get_current_buf))
        (define items (buffers))
        (define index (buffer-index cur items))
        (when (and (<= index (length items)) (= (list-ref items (- index 1)) cur))
          (define target (max 1 (min (length items) (+ index delta))))
          (set-box! *buffer-order* (move-list-item items index target))
          (set-box! *tabline-cache* #f)
          (cmd "redrawtabline")))
      (hash "desc" "Move buffer in displayed order")))
  '(("bj" . -1) ("bk" . 1)))

(for-each
  (lambda (pair)
    (define key (car pair))
    (define field (cdr pair))
    (keymap-set
      "n"
      (string-append "<leader>" key)
      (lambda ()
        (define items (buffers))
        (define (sort-key b)
          (if (equal? field "directory")
              (fn-call "fnamemodify" (nvim_buf_get_name b) ":h")
              (bo-get b "filetype")))
        (set-box! *buffer-order*
                  (sort items
                        (lambda (a b)
                          (define la (sort-key a))
                          (define lb (sort-key b))
                          (if (equal? la lb) (< a b) (string<? la lb)))))
        (set-box! *tabline-cache* #f)
        (cmd "redrawtabline"))
      (hash "desc" (string-append "Order buffers by " field))))
  '(("bD" . "directory") ("bL" . "language")))

(define (delete-buffer buf force (replacement #f))
  (define listed (bo-get buf "buflisted"))
  (define repl-box (box replacement))
  ;; Wiping a displayed buffer closes its splits. Replace it in-place first.
  (for-each
    (lambda (win)
      (when (and (nvim_win_is_valid win)
                 (equal? (hash-try-get (nvim_win_get_config win) "relative") ""))
        (unless (unbox repl-box)
          (define candidate
            (let loop ([xs (buffers)])
              (cond
                [(null? xs) #f]
                [(not (= (car xs) buf)) (car xs)]
                [else (loop (cdr xs))])))
          (set-box! repl-box (or candidate (nvim_create_buf #t #f))))
        (win-call
          win
          (lambda ()
            (cmd (string-append "buffer" (if force "! " " ") (number->string (unbox repl-box))))))))
    (fn-call "win_findbuf" buf))
  ;; Leaving the last window can already wipe a buffer with bufhidden=wipe.
  (when (nvim_buf_is_valid buf)
    (nvim_buf_delete buf (hash "force" force)))
  (define remaining (buffers))
  (when (and listed (= (length remaining) 1))
    (define only (car remaining))
    (define keep
      (box (if (and (= (nvim_get_current_buf) only) (is-editor? 0))
               (nvim_get_current_win)
               #f)))
    (for-each
      (lambda (win)
        (when (and (= (nvim_win_get_buf win) only) (is-editor? win))
          (if (not (unbox keep))
              (set-box! keep win)
              (when (not (= win (unbox keep)))
                (nvim_win_close win #f)))))
      (vector->list (nvim_tabpage_list_wins 0)))))

(state-set! 'delete-buffer delete-buffer)

(define (close-current-buffer force)
  (define is-terminal (equal? (bo-get 0 "buftype") "terminal"))
  (if (and (bo-get 0 "modified") (not is-terminal) (not force))
      (notify "Unsaved changes: save the buffer before closing")
      (delete-buffer (nvim_get_current_buf) (or force is-terminal))))

(keymap-set "n" "<leader>c" (lambda () (close-current-buffer #t))
            (hash "desc" "Force wipe current buffer (original binding)"))
(keymap-set "n" "<leader>bw" (lambda () (close-current-buffer #f))
            (hash "desc" "Wipe buffer (protect unsaved files)"))
(keymap-set "n" "<leader>bp" pick-buffer (hash "desc" "Pick buffer"))
(keymap-set "n" "<leader>sb" pick-buffer (hash "desc" "Search buffers"))
(keymap-set "n" "<leader>bb" pick-buffer (hash "desc" "Search buffers"))

(for-each
  (lambda (i)
    (keymap-set
      "n"
      (string-append "<A-" (number->string i) ">")
      (lambda ()
        (define items (buffers))
        (define count (length items))
        (define idx (if (= i 9) count i))
        (when (and (> count 0) (<= idx count))
          (select-cycle-buffer! (list-ref items (- idx 1)) items)))
      (hash "desc" (string-append "Go to buffer " (number->string i)))))
  '(1 2 3 4 5 6 7 8 9))

(for-each
  (lambda (pair)
    (define key (car pair))
    (define side (cdr pair))
    (keymap-set
      "n"
      (string-append "<leader>" key)
      (lambda ()
        (state-call 'focus-editor)
        (define current (nvim_get_current_buf))
        (define items (buffers))
        (define index (buffer-index current items))
        (let loop ([xs items] [pos 1])
          (unless (null? xs)
            (define b (car xs))
            (when (and (not (= b current))
                       (or (equal? side "all")
                           (and (equal? side "left") (< pos index))
                           (and (equal? side "right") (> pos index))))
              (define is-terminal (equal? (bo-get b "buftype") "terminal"))
              (when (or is-terminal (not (bo-get b "modified")))
                (delete-buffer b is-terminal current)))
            (loop (cdr xs) (+ pos 1)))))
      (hash "desc" (string-append "Close " side " buffers (keep modified)"))))
  '(("be" . "all") ("bm" . "all") ("bh" . "left") ("bl" . "right")))
