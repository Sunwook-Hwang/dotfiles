;; 1:1 Steel port of: nvim/.config/nvim/lua/options.lua
;; Equivalence:
;; - Applies all 45+ default editor options, shared persistent undo dir, OSC52 SSH/herdr
;;   detection, tool resolution (`resolve-tool`, `resolve-candidate`), batched
;;   `check-external-files`, and utility-window line-number preservation (`toggle-relative-numbers`).
;; - Preserves `g:mapleader` default `" "` without overriding pre-set values.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/fn")
(require "rvim/cmd")
(require "rvim/schedule")
(require "rvim/hl")
(require "rvim/string")
(require "buffer_policy")
(require "state")

(nvim_create_augroup "nvim.progress" (hash "clear" #t))

(when (and (not (g-get "loaded_python3_provider"))
           (not (g-get "python3_host_prog")))
  (g-set "loaded_python3_provider" 0))

(define vimruntime (env-get "VIMRUNTIME"))
(when vimruntime
  (define runtime-paths
    (filter (lambda (p) (or (equal? p vimruntime) (string/match p "/lib[^/]*/nvim$")))
            (nvim_list_runtime_paths)))
  (opt-set "packpath" (list->vector (if (null? runtime-paths) (list vimruntime) runtime-paths))))

(state-set! 'highlight-yank hl-on-yank)
(define native-file-watch (= (fn-call "has" "nvim-0.13") 1))

;; Data & persistent undo directories
(define data-dir (fn-call "stdpath" "data"))
(define nopack-data (string-append data-dir "/nopack"))
(define legacy-data (string-append data-dir "/offline"))
(when (and (= (fn-call "isdirectory" legacy-data) 1)
           (= (fn-call "isdirectory" nopack-data) 0))
  (when (not (= (fn-call "rename" legacy-data nopack-data) 0))
    (set! nopack-data legacy-data)))
(state-set! 'nopack-data nopack-data)

(define undo-dir
  (string-append (or (env-get "XDG_STATE_HOME") (fn-call "expand" "~/.local/state"))
                 "/nvim/undo"))
(fn-call "mkdir" undo-dir "p")

(define use-osc52
  (or (not (not (env-get "SSH_CONNECTION")))
      (not (not (env-get "SSH_TTY")))
      (equal? (env-get "HERDR_ENV") "1")))
(state-set! 'use-osc52 use-osc52)

;; Resolve external CLI tools via PATH first, then existing Mason bin.
(define (resolve-tool name)
  (define path (fn-call "exepath" name))
  (if (not (equal? path ""))
      path
      (let ((installed (string-append (fn-call "stdpath" "data") "/mason/bin/" name)))
        (if (= (fn-call "executable" installed) 1) installed ""))))

(define (resolve-candidate candidates)
  (define (loop rest)
    (if (null? rest)
        #f
        (let* ((cand (car rest))
               (path (resolve-tool (car cand))))
          (if (not (equal? path ""))
              (cons cand path)
              (loop (cdr rest))))))
  (loop candidates))

(state-set! 'resolve-tool resolve-tool)
(state-set! 'resolve-candidate resolve-candidate)

(define default-options
  (hash
    "autoread" #t
    "backup" #f
    "clipboard" (if use-osc52 "" "unnamedplus")
    "lazyredraw" #f
    "cmdheight" 1
    "completeopt" (vector "menu" "menuone" "noselect" "popup" "fuzzy")
    "autocompletedelay" 150
    "complete" (vector "." "w" "b" "t")
    "pumborder" "rounded"
    "winborder" "rounded"
    "conceallevel" 0
    "fileencoding" "utf-8"
    "foldmethod" "manual"
    "foldexpr" ""
    "guifont" "RobotoMono Nerd Font Mono,monospace:h17"
    "hidden" #t
    "hlsearch" #t
    "ignorecase" #t
    "mouse" "a"
    "pumheight" 10
    "showmode" #t
    "showtabline" 2
    "smartcase" #t
    "smartindent" #f
    "splitbelow" #t
    "splitright" #t
    "swapfile" #f
    "termguicolors" #t
    "title" #t
    "undodir" undo-dir
    "undofile" #t
    "updatetime" 250
    "writebackup" #f
    "expandtab" #t
    "shiftwidth" 4
    "tabstop" 4
    "cursorline" #t
    "cursorlineopt" "line,number"
    "cursorcolumn" #f
    "number" #t
    "relativenumber" #f
    "numberwidth" 2
    "signcolumn" "yes"
    "wrap" #t
    "spell" #f
    "spelllang" "en"
    "background" "dark"
    "scrolloff" 5
    "sidescrolloff" 8
    "ttyfast" #t
    "sessionoptions" "buffers,curdir,tabpages,winsize"))

(opt-append "shortmess" "c")
(for-each (lambda (k) (opt-set k (hash-ref default-options k)))
          (hash-keys->list default-options))

;; Batched external file change checks
(define *file-check-pending* (box #f))
(define *file-check-all* (box #f))
(define *file-check-bufs* (box (hash)))

(define (check-external-files (buf #f))
  (define proceed
    (cond
      ((not buf) (set-box! *file-check-all* #t) #t)
      ((is-source? buf)
       (set-box! *file-check-bufs* (hash-insert (unbox *file-check-bufs*) buf #t))
       #t)
      (else #f)))
  (when (and proceed (not (unbox *file-check-pending*)))
    (set-box! *file-check-pending* #t)
    (schedule
      (lambda ()
        (set-box! *file-check-pending* #f)
        (define all (unbox *file-check-all*))
        (define bufs (unbox *file-check-bufs*))
        (set-box! *file-check-all* #f)
        (set-box! *file-check-bufs* (hash))
        (define mode (hash-ref (nvim_get_mode) "mode"))
        (when (and (equal? (fn-call "getcmdwintype") "")
                   (not (string/match mode "^[ct]")))
          (if all
              (cmd "checktime")
              (for-each
                (lambda (target)
                  (when (and (nvim_buf_is_loaded target) (is-source? target))
                    (cmd (string-append "checktime " (number->string target)))))
                (hash-keys->list bufs))))))))

(state-set! 'check-external-files check-external-files)

(define file-changes (nvim_create_augroup "nopack-file-changes" (hash "clear" #t)))
(nvim_create_autocmd
  (vector "BufEnter" "WinEnter" "FocusGained" "ShellCmdPost" "TermLeave" "TermClose")
  (hash "group" file-changes
        "callback"
        (lambda (args)
          (unless (is-picker-event? args)
            (define ev (hash-ref args "event"))
            (if (or (equal? ev "BufEnter") (equal? ev "WinEnter"))
                (unless native-file-watch
                  (check-external-files (hash-ref args "buf")))
                (check-external-files))))))

(cmd "filetype plugin indent on")
(cmd "syntax enable")
(opt-append "whichwrap" "<,>,[,],h,l")
(opt-append "iskeyword" "-")
(opt-set "path" (vector "." ""))
(opt-set "wildmenu" #t)
(opt-set "wildmode" "longest:full,full")
(opt-append "wildignore" (vector "*/.git/*" "*/node_modules/*" "*/__pycache__/*"))

;; Window-local line number preservation across utility windows
(define numbering-options (list "number" "relativenumber" "statuscolumn"))
(define *source-numbering* (box (hash)))
(define numbering-group (nvim_create_augroup "nopack-line-numbers" (hash "clear" #t)))
(define *relative-numbers* (box (hash-ref default-options "relativenumber")))
(define *relative-override* (box #f))
(define *has-relative-override* (box #f))

(define (toggle-relative-numbers)
  (define enabled (not (unbox *relative-numbers*)))
  (set-box! *relative-numbers* enabled)
  (set-box! *relative-override* enabled)
  (set-box! *has-relative-override* #t)
  (go-set "relativenumber" enabled)
  (for-each
    (lambda (win)
      (when (is-editor? win)
        (wo-local-set win "relativenumber" enabled)))
    (nvim_list_wins)))

(state-set! 'toggle-relative-numbers toggle-relative-numbers)

(nvim_create_autocmd
  "BufWinLeave"
  (hash "group" numbering-group
        "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (when (and (is-source? buf) (not (w-get 0 "nopack_numbering_utility")))
            (define saved
              (foldl (lambda (name acc) (hash-insert acc name (wo-get 0 name)))
                     (hash)
                     numbering-options))
            (define win (nvim_get_current_win))
            (define existing (or (hash-try-get (unbox *source-numbering*) win) (hash)))
            (set-box! *source-numbering*
                      (hash-insert (unbox *source-numbering*)
                                   win
                                   (hash-insert existing buf saved)))))))

(nvim_create_autocmd
  (vector "WinClosed" "BufWipeout")
  (hash "group" numbering-group
        "callback"
        (lambda (args)
          (if (equal? (hash-ref args "event") "WinClosed")
              (set-box! *source-numbering*
                        (hash-remove (unbox *source-numbering*)
                                     (string->number (hash-ref args "match"))))
              (let ((buf (hash-ref args "buf")))
                (set-box! *source-numbering*
                          (foldl
                            (lambda (win acc)
                              (hash-insert acc win (hash-remove (hash-ref acc win) buf)))
                            (unbox *source-numbering*)
                            (hash-keys->list (unbox *source-numbering*)))))))))

(define (update-window-numbering win)
  (when (nvim_win_is_valid win)
    (define buf (nvim_win_get_buf win))
    (if (is-source? buf)
        (begin
          (when (w-get win "nopack_numbering_utility")
            (define win-saved (or (hash-try-get (unbox *source-numbering*) win) (hash)))
            (define saved (or (hash-try-get win-saved buf) (hash)))
            (for-each
              (lambda (name)
                (define val (if (hash-contains? saved name) (hash-ref saved name) (go-get name)))
                (wo-local-set win name val))
              numbering-options)
            (w-set win "nopack_numbering_utility" #f))
          (when (unbox *has-relative-override*)
            (wo-local-set win "relativenumber" (unbox *relative-override*))))
        (w-set win "nopack_numbering_utility" #t))
    (when (equal? (bo-get buf "filetype") "flash-explorer")
      (wo-local-set win "number" #f)
      (wo-local-set win "relativenumber" #f)
      (unless (equal? (wo-get win "statuscolumn") "%s ")
        (wo-local-set win "statuscolumn" "%s ")))))

(nvim_create_autocmd
  (vector "WinEnter" "BufEnter" "BufWinEnter" "FileType" "VimEnter" "SessionLoadPost")
  (hash "group" numbering-group
        "callback"
        (lambda (args)
          (define ev (hash-ref args "event"))
          (cond
            ((equal? ev "FileType")
             (define buf (hash-ref args "buf"))
             (schedule (lambda () (for-each update-window-numbering (fn-call "win_findbuf" buf)))))
            ((or (equal? ev "VimEnter") (equal? ev "SessionLoadPost"))
             (for-each update-window-numbering (nvim_list_wins)))
            (else
             (update-window-numbering (nvim_get_current_win)))))))

(unless (g-get "mapleader")
  (g-set "mapleader" " "))
