;; 1:1 Steel port of: nvim/.config/nvim/lua/search.lua
;; Equivalence:
;; - File pickers (`<leader>f`, `<leader>sn`, `<leader>sr`) using external `fzf` when
;;   available or falling back to native `open-picker`, with bounded (8-wide) async
;;   `uv-fs-stat`/`uv-fs-access` checks for `v:oldfiles`.
;; - Editor metadata pickers: `<leader>sc` (commands), `<leader>sh` (help), `<leader>sp`
;;   (live-preview colorschemes with cancel restore), `<leader>sk` (keymaps).
;; - Live grep (`<leader>st`, `<leader>s/`) and word/selection grep (`<leader>t`) using
;;   `rg --vimgrep` with `grep` fallback and job cancellation on each keystroke.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/uv")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "jobs")
(require "fzf_picker")
(require "state")

(define (file-items files root)
  (define prefix (and root (string-append root "/")))
  (define plen (if prefix (string-length prefix) 0))
  (filter-map
    (lambda (file)
      (if (equal? file "")
          #f
          (hash "filename" file
                "lnum" 1
                "label" (if (and prefix
                                 (>= (string-length file) plen)
                                 (equal? (substring file 0 plen) prefix))
                            (substring file plen (string-length file))
                            (fn-call "fnamemodify" file ":~:.")))))
    files))

(define (cancel-search!)
  (cancel-command! "search"))

(define (open-file-picker title root (cancel #f))
  (define exe (fn-call "exepath" "fzf"))
  (if (not (equal? exe ""))
      (fzf-picker-open title root exe cancel)
      (state-call 'open-picker title (hash "cancel" cancel))))

(define (recent-files! picker)
  (define paths (or (v-get "oldfiles") '()))
  (define total (length paths))
  (define closed-box (hash-ref picker "closed"))
  (if (= total 0)
      ((hash-ref picker "set_files") '())
      (let ([results (box (hash))]
            [index (box 0)]
            [completed (box 0)])
        (define (check-next!)
          (when (and (not (unbox closed-box)) (< (unbox index) total))
            (define pos (unbox index))
            (set-box! index (+ pos 1))
            (define path (list-ref paths pos))
            (define (finish! ok)
              (set-box! results (hash-insert (unbox results) pos (and ok path)))
              (set-box! completed (+ (unbox completed) 1))
              (unless (unbox closed-box)
                (if (= (unbox completed) total)
                    (schedule
                      (lambda ()
                        (unless (unbox closed-box)
                          (define readable
                            (let loop ([i 0] [acc '()])
                              (if (>= i total)
                                  (reverse acc)
                                  (let ([v (hash-try-get (unbox results) i)])
                                    (loop (+ i 1) (if v (cons v acc) acc))))))
                          ((hash-ref picker "set_files") readable))))
                    (check-next!))))
            (uv-fs-stat
              path
              (lambda (_err stat)
                (unless (unbox closed-box)
                  (if (or (not stat) (not (equal? (hash-try-get stat "type") "file")))
                      (finish! #f)
                      (uv-fs-access path "R" (lambda (_e ok) (finish! ok)))))))))
        (let loop ([i 0])
          (when (< i (min 8 total))
            (check-next!)
            (loop (+ i 1)))))))

(define (file-picker! title root command)
  (define picker (open-file-picker title root cancel-search!))
  (run-command!
    "search"
    command
    (hash "cwd" root
          "partial" #t
          "failed" (lambda () ((hash-ref picker "set_files") '())))
    (lambda (output limited)
      (define raw (state-call 'records output "\x00" limited))
      (define files
        (map (lambda (f)
               (if (and (> (string-length f) 0) (equal? (substring f 0 1) "/"))
                   f
                   (string-append root "/" f)))
             raw))
      ((hash-ref picker "set_files") files root)))
  picker)

(define (find-files! root title)
  (define ignored (or (state-get 'ignored-dirs) '()))
  (define prune-expr
    (let loop ([xs ignored] [first? #t] [acc '()])
      (if (null? xs)
          (reverse acc)
          (let ([part (if first? (list "-name" (car xs)) (list "-o" "-name" (car xs)))])
            (loop (cdr xs) #f (append (reverse part) acc))))))
  (define command
    (append (list "find" root "-type" "d" "(") prune-expr (list ")" "-prune" "-o" "-type" "f" "-print0")))
  (file-picker! title root command))

(state-set! 'file-items file-items)
(state-set! 'recent-files recent-files!)
(state-set! 'file-picker file-picker!)
(state-set! 'find-files find-files!)

(keymap-set "n" "<leader>f"
            (lambda () (find-files! (state-call 'project-root) "Find files"))
            (hash "desc" "Find files: fuzzy picker"))
(keymap-set "n" "<leader>sn"
            (lambda () (find-files! (fn-call "stdpath" "config") "Neovim files"))
            (hash "desc" "Find config files"))
(keymap-set "n" "<leader>sr"
            (lambda () (recent-files! (open-file-picker "Recent files" (fn-call "getcwd"))))
            (hash "desc" "Recent files"))

;; =========================================
;; ======= SEARCH: EDITOR METADATA =======
;; =========================================

(define (command-picker title kind action (opts (hash)))
  (define items
    (map (lambda (name) (hash "label" name "action" (lambda () (action name))))
         (fn-call "getcompletion" "" kind)))
  (state-call 'open-picker title (hash-insert opts "items" items)))

(keymap-set "n" "<leader>sc"
            (lambda ()
              (command-picker "Commands" "command"
                              (lambda (name) (nvim_feedkeys (string-append ":" name " ") "n" #t))))
            (hash "desc" "Search commands"))

(keymap-set "n" "<leader>sh"
            (lambda ()
              (command-picker "Help" "help"
                              (lambda (name) (cmd (string-append "help " (fn-call "fnameescape" name))))))
            (hash "desc" "Search help"))

(keymap-set
  "n"
  "<leader>sp"
  (lambda ()
    (define original (or (g-get "colors_name") "default"))
    (define background (go-get "background"))
    (define (apply-cs name)
      (go-set "background" background)
      (cmd (string-append "colorscheme " name)))
    (command-picker
      "Colorschemes" "color" apply-cs
      (hash "highlight" (lambda (item) (when item (apply-cs (hash-ref item "label"))))
            "on_cancel" (lambda () (apply-cs original) (go-set "background" background)))))
  (hash "desc" "Preview and choose colorscheme"))

(keymap-set
  "n"
  "<leader>sk"
  (lambda ()
    (define leader (nvim_replace_termcodes "<leader>" #t #f #t))
    (define llen (string-length leader))
    (define items
      (apply append
             (map
               (lambda (mode)
                 (apply append
                        (map
                          (lambda (pair)
                            (define scope (car pair))
                            (map
                              (lambda (k)
                                (define lhs (hash-ref k "lhsraw"))
                                (define label
                                  (if (and (>= (string-length lhs) llen)
                                           (equal? (substring lhs 0 llen) leader))
                                      (string-append "<leader>" (fn-call "keytrans" (substring lhs llen (string-length lhs))))
                                      (fn-call "keytrans" lhs)))
                                (hash "label"
                                      (string-append mode " " scope " " label "  "
                                                     (or (hash-try-get k "desc")
                                                         (hash-try-get k "rhs")
                                                         "Steel callback"))))
                              (cdr pair)))
                          (list (cons "[global]" (nvim_get_keymap mode))
                                (cons "[buffer]" (nvim_buf_get_keymap 0 mode))))))
               '("n" "i" "x" "t"))))
    (state-call 'open-picker "Keymaps" (hash "items" items)))
  (hash "desc" "Search keymaps"))

;; =========================================
;; ======= SEARCH: TEXT / LIVE GREP ======
;; =========================================

(define (run-grep! text paths root fixed callback)
  (define use-rg (= (fn-call "executable" "rg") 1))
  (define multiline (string-contains? text "\n"))
  (if (and multiline (not use-rg))
      (begin
        (notify "Multiline selection search requires ripgrep (rg)" (log-level 'warn))
        (callback '()))
      (let* ([base
              (if use-rg
                  (let* ([flags (append (if multiline '("--multiline") '())
                                        (if fixed '("--fixed-strings") '()))])
                    (append '("rg") flags
                            (list "--vimgrep" "--hidden" "--smart-case"
                                  "--max-columns" "300" "--max-columns-preview"
                                  "--max-filesize" "2M"
                                  "--glob" "!.git/**" "--glob" "!node_modules/**" "--glob" "!__pycache__/**"
                                  "--" text)))
                  (let ([has-upper (string/find text "%u")])
                    (append (list "grep" "-r" "-n" "-H" "-I" (if fixed "-F" "-E")
                                  "--exclude-dir=.git" "--exclude-dir=node_modules" "--exclude-dir=__pycache__")
                            (if has-upper '() '("-i"))
                            (list "-e" text "--"))))]
             [argv (append base paths)]
             [prefix (string-append root "/")]
             [plen (string-length prefix)])
        (run-command!
          "search"
          argv
          (hash "cwd" root "partial" #t "no_match" #t "failed" (lambda () (callback '())))
          (lambda (output limited)
            (define lines (state-call 'records output "\n" limited 10000))
            (define pat (if use-rg "^(.-):(%d+):(%d+):(.*)$"
                                   "^(.-):(%d+):(.*)$"))
            (define items
              (filter-map
                (lambda (line)
                  (define m (string/match line pat))
                  (if (or (not m) (not (vector? m)) (< (vector-length m) (if use-rg 4 3)))
                      #f
                      (let* ([filename (vector-ref m 0)]
                             [lnum-str (vector-ref m 1)]
                             [col-str (if use-rg (vector-ref m 2) "1")]
                             [content (if use-rg (vector-ref m 3) (vector-ref m 2))]
                             [short-c (substring content 0 (min 200 (string-length content)))]
                             [label
                              (if (and (>= (string-length filename) plen)
                                       (equal? (substring filename 0 plen) prefix))
                                  (string-append (substring filename plen (string-length filename))
                                                 ":" lnum-str " " short-c)
                                  (substring line 0 (min 300 (string-length line))))])
                        (hash "filename" filename
                              "lnum" (string->number lnum-str)
                              "col" (string->number col-str)
                              "text" (substring content 0 (min 300 (string-length content)))
                              "label" label))))
                lines))
            (callback items))))))

(define (text-picker! open-only (word #f))
  (define root (state-call 'project-root))
  (define paths
    (if open-only
        (filter-map
          (lambda (buf)
            (define name (nvim_buf_get_name buf))
            (and (is-source? buf) (not (equal? name "")) name))
          (state-call 'buffers))
        (list root)))
  (define (update! text picker (generation #f))
    (cancel-search!)
    (define (publish! items)
      (when (and (not (unbox (hash-ref picker "closed")))
                 (or (not generation) (= generation (unbox (hash-ref picker "generation")))))
        ((hash-ref picker "set_items") items)))
    (if (or (equal? text "") (null? paths))
        (publish! '())
        (run-grep! text paths root (not (not word)) publish!)))
  (define title
    (cond
      [word (string-append "Word: " (vector-ref (string/gsub word "%c" " ") 0))]
      [open-only "Grep open files"]
      [else "Live grep"]))
  (define picker
    (state-call 'open-picker title
                (hash "cancel" cancel-search!
                      "live" (if word #f update!))))
  (when word
    (update! word picker)))

(keymap-set "n" "<leader>st" (lambda () (text-picker! #f))
            (hash "desc" "Live grep: update while typing"))
(keymap-set "n" "<leader>t" (lambda () (text-picker! #f (fn-call "expand" "<cword>")))
            (hash "desc" "Find cursor word, then refine matches"))
(keymap-set
  "x"
  "<leader>t"
  (lambda ()
    (define text
      (string-join (fn-call "getregion" (fn-call "getpos" "v") (fn-call "getpos" ".")
                            (hash "type" (fn-call "mode")))
                   "\n"))
    (unless (equal? text "")
      (cmd (string-append "normal! " (nvim_replace_termcodes "<Esc>" #t #f #t)))
      (text-picker! #f text)))
  (hash "desc" "Find selection, then refine matches"))
(keymap-set "n" "<leader>s/" (lambda () (text-picker! #t))
            (hash "desc" "Live grep in open files"))
