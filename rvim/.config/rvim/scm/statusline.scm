;; 1:1 Steel port of: nvim/.config/nvim/lua/statusline.lua
;; Equivalence:
;; - Computes WCAG contrast ratio for `NopackGitBranch` on `ModeChanged` / `ColorScheme`
;;   and derives `NopackStatusError` / `NopackStatusWarn` from `StatusLine`.
;; - Invalidates native diagnostic counts on `DiagnosticChanged` and `BufWipeout`.
;; - Reads live LSP clients and redraws after `LspAttach` and `LspDetach`.
;; - Caches file context, LSP and formatter text per window; buffer, window, cwd,
;;   LSP, filetype, refresh and focus events clear it, so the text matches Lua.
;; - Exposes statusline components via `v:steel.*` callbacks registered on `state`:
;;   `NopackStatusline`, `NopackGitStatus`, `NopackDiagnosticStatus`, `NopackLspStatus`,
;;   `NopackFileContext`, and `NopackBreadcrumbStatus`.

(require-builtin rvim/api)
(require-builtin rvim/steel)
(require "rvim/opt")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/fs")
(require "rvim/schedule")
(require-builtin rvim/statusline as draw.)
(require "buffer_policy")
(require "breadcrumbs")
(require "state")

(define *git-mode-group* (box #f))

(define (relative-luminance color)
  (define (channel shift)
    (define c (/ (modulo (floor (/ color (expt 256 shift))) 256) 255.0))
    (if (<= c 0.04045)
        (/ c 12.92)
        (expt (/ (+ c 0.055) 1.055) 2.4)))
  (+ (* 0.2126 (channel 2))
     (* 0.7152 (channel 1))
     (* 0.0722 (channel 0))))

(define (contrast-ratio a b)
  (/ (+ (max a b) 0.05) (+ (min a b) 0.05)))

(define (set-git-mode-highlight!)
  (define mode-str (fn-call "mode"))
  (define mode (if (> (string-length mode-str) 0) (substring mode-str 0 1) ""))
  (define group
    (cond
      [(equal? mode "i") "String"]
      [(or (equal? mode "v") (equal? mode "V") (equal? mode "\x16;")) "Constant"]
      [else "Identifier"]))
  (if (equal? (unbox *git-mode-group*) group)
      #f
      (begin
        (set-box! *git-mode-group* group)
        (define normal (nvim_get_hl 0 (hash "name" "Normal" "link" #f)))
        (define accent (nvim_get_hl 0 (hash "name" group "link" #f)))
        (define bg
          (or (if (hash-try-get accent "reverse")
                  (hash-try-get accent "bg")
                  (hash-try-get accent "fg"))
              (hash-try-get normal "fg")
              #x808080))
        (define accent-cterm (hash-try-get accent "cterm"))
        (define ctermbg
          (if (and accent-cterm (hash-try-get accent-cterm "reverse"))
              (hash-try-get accent "ctermbg")
              (hash-try-get accent "ctermfg")))
        (define bg-lum (relative-luminance bg))
        (define normal-bg (or (hash-try-get normal "bg") #x000000))
        (define normal-fg (or (hash-try-get normal "fg") #xffffff))
        (define fg0 normal-bg)
        (define ctermfg0 (or (hash-try-get normal "ctermbg") 0))
        (define preferred-color
          (if (> (contrast-ratio (relative-luminance normal-fg) bg-lum)
                 (contrast-ratio (relative-luminance fg0) bg-lum))
              (values normal-fg (or (hash-try-get normal "ctermfg") 15))
              (values fg0 ctermfg0)))
        (define fg1 (list-ref preferred-color 0))
        (define ctermfg1 (list-ref preferred-color 1))
        (define readable-color
          (if (< (contrast-ratio (relative-luminance fg1) bg-lum) 4.5)
              (if (> bg-lum 0.179)
                  (values #x000000 0)
                  (values #xffffff 15))
              (values fg1 ctermfg1)))
        (define fg (list-ref readable-color 0))
        (define ctermfg (list-ref readable-color 1))
        (nvim_set_hl
          0
          "NopackGitBranch"
          (hash "fg" fg
                "bg" bg
                "ctermfg" ctermfg
                "ctermbg" (or ctermbg (hash-try-get normal "ctermfg") 8)
                "bold" #t
                "reverse" #f
                "nocombine" #t))
        #t)))

(define (set-nopack-status-highlights!)
  (nvim_set_hl 0 "NopackLspMissing" (hash "fg" "#ffffff" "bg" "#af0000" "bold" #t))
  (set-box! *git-mode-group* #f)
  (set-git-mode-highlight!)
  (define active-hl (box (hash)))
  (for-each
    (lambda (suffix)
      (define hl (nvim_get_hl 0 (hash "name" (string-append "StatusLine" suffix) "link" #f)))
      (define bold? (equal? suffix ""))
      (define cterm (hash-try-get hl "cterm"))
      (define hl1 (hash-insert hl "bold" bold?))
      (define hl2
        (if cterm
            (hash-insert hl1 "cterm" (hash-insert cterm "bold" bold?))
            hl1))
      (nvim_set_hl 0 (string-append "StatusLine" suffix) hl2)
      (set-box! active-hl hl2))
    '("NC" ""))
  ;; Diagnostics render only in the active window, so derive them from StatusLine.
  (define base (unbox active-hl))
  (define h1
    (if (hash-try-get base "reverse")
        (if (hash-contains? base "fg")
            (hash-insert base "bg" (hash-ref base "fg"))
            (hash-remove base "bg"))
        base))
  (define cterm1 (hash-try-get h1 "cterm"))
  (define h2
    (if (and cterm1 (hash-try-get cterm1 "reverse"))
        (hash-insert
          (if (hash-contains? h1 "ctermfg")
              (hash-insert h1 "ctermbg" (hash-ref h1 "ctermfg"))
              (hash-remove h1 "ctermbg"))
          "cterm"
          (hash-insert cterm1 "reverse" #f))
        h1))
  (define cterm2 (hash-try-get h2 "cterm"))
  (define h3
    (if cterm2
        (hash-insert h2 "cterm" (hash-insert cterm2 "nocombine" #t))
        h2))
  (define error-hl
    (hash-insert
      (hash-insert
        (hash-insert
          (hash-insert h3 "nocombine" #t)
          "reverse" #f)
        "fg" "#ff0000")
      "ctermfg" 9))
  (nvim_set_hl 0 "NopackStatusError" error-hl)
  (define warn-hl
    (hash-insert (hash-insert error-hl "fg" "#ffd700") "ctermfg" 220))
  (nvim_set_hl 0 "NopackStatusWarn" warn-hl)
  (state-call 'picker-selection-highlight))

(set-nopack-status-highlights!)

(define *status-hl-group* (nvim_create_augroup "nopack-status-highlights" (hash "clear" #t)))
(nvim_create_autocmd
  "ColorScheme"
  (hash "group" *status-hl-group*
        "callback" (lambda (_args) (set-nopack-status-highlights!))))

(nvim_create_autocmd
  "ModeChanged"
  (hash "group" *status-hl-group*
        "callback" (lambda (_args)
                     (when (set-git-mode-highlight!)
                       (cmd "redrawstatus")))))

(state-set! 'language-status-visible #t)

(nvim_create_autocmd
  '("DiagnosticChanged" "BufWipeout")
  (hash "group" (nvim_create_augroup "nopack-diagnostic-status" (hash "clear" #t))
        "callback" (lambda (args)
                     (draw.statusline-invalidate-diagnostics! (hash-ref args "buf")))))

(define (nopack-git-status)
  (draw.statusline-git (or (b-get 0 "nopack_git_status") "") "NopackGitBranch"))

(define (nopack-diagnostic-status)
  (draw.statusline-diagnostics (nvim_get_current_buf) "NopackStatusError" "NopackStatusWarn"))

(define (nopack-lsp-status)
  (define buf (nvim_get_current_buf))
  (if (and (state-get 'language-status-visible #t) (is-source? buf))
      (let ([text (draw.statusline-lsp buf)])
        (cond
          [(not (equal? text "")) text]
          [(and (state-get 'ctags-kind)
                (allows? buf)
                (not (equal? (nvim_buf_get_name buf) ""))
                (equal? (state-call 'analysis-backend-get buf) "ctags"))
           (string-append "[CTAGS: " (state-get 'ctags-kind) "]")]
          [else "%#NopackLspMissing#[LSP X]%*"]))
      ""))

(nvim_create_autocmd
  '("LspAttach" "LspDetach")
  (hash "group" (nvim_create_augroup "nopack-lsp-status" (hash "clear" #t))
        "callback" (lambda (_args) (schedule (lambda () (cmd "redrawstatus"))))))

(define (file-context win)
  (define file (nvim_buf_get_name (nvim_win_get_buf win)))
  (cond
    [(or (equal? file "") (not (breadcrumbs-enabled?)))
     (if (equal? file "") "[No Name]" (fn-call "fnamemodify" file ":t"))]
    [(not (is-editor? win))
     (fn-call "fnamemodify" file ":~:.")]
    [else
     (define res (state-call 'find-project (fs-dirname file)))
     (if (and res (caddr res))
         (or (draw.statusline-relative-path file (car res))
             (fn-call "fnamemodify" file ":~:."))
         (fn-call "fnamemodify" file ":~:."))]))

(define (nopack-file-context)
  (file-context (nvim_get_current_win)))

(define (nopack-breadcrumb-status)
  (breadcrumbs-status (nvim_get_current_win)))

(define *statusline-style*
  (draw.statusline-style "NopackGitBranch" "NopackStatusError" "NopackStatusWarn"))

;; File context, LSP and formatter text change only on these events, not per keystroke.
(define *static-cache* (box (hash)))

(nvim_create_autocmd
  '("BufWinEnter" "BufFilePost" "BufWritePost" "FileType" "DirChanged" "LspAttach" "LspDetach"
    "WinClosed" "FocusGained" "ShellCmdPost" "TermLeave" "TermClose" "User")
  (hash "group" (nvim_create_augroup "nopack-status-cache" (hash "clear" #t))
        "callback" (lambda (args)
                     (set-box! *static-cache* (hash))
                     (when (equal? (hash-ref args "event") "LspDetach")
                       ;; LspDetach fires before the client leaves the buffer.
                       (schedule (lambda () (set-box! *static-cache* (hash))))))))

(nvim_create_autocmd
  "OptionSet"
  (hash "group" "nopack-status-cache"
        "pattern" "buftype,modifiable"
        "callback" (lambda (_args) (set-box! *static-cache* (hash)))))

(define (static-parts win current?)
  (define buf (nvim_win_get_buf win))
  (define key (list buf current? (state-get 'language-status-visible #t)
                    (breadcrumbs-enabled?) (state-get 'ctags-kind)))
  (define cached (hash-try-get (unbox *static-cache*) win))
  (if (and cached (equal? (car cached) key))
      (cdr cached)
      (let* ([formatter (state-get 'NopackFormatStatus)]
             [parts (if current?
                        (list (file-context win) (nopack-lsp-status)
                              (if (function? formatter) (formatter) ""))
                        (list (file-context win) "" ""))])
        (set-box! *static-cache* (hash-insert (unbox *static-cache*) win (cons key parts)))
        parts)))

(define (nopack-statusline)
  (define current (nvim_get_current_win))
  (define raw-win (g-get "statusline_winid"))
  (define win (or (and (number? raw-win) raw-win)
                  (and (string? raw-win) (string->number raw-win))
                  current))
  (define parts (static-parts win (= win current)))
  (if (= win current)
      (draw.statusline-compose #t (nvim_get_current_buf) (car parts) (breadcrumbs-status win)
                               (cadr parts) (caddr parts) *statusline-style*)
      (draw.statusline-compose #f 0 (car parts) "" "" "" *statusline-style*)))

(state-set! 'NopackGitStatus nopack-git-status)
(steel-export! 'NopackGitStatus nopack-git-status)
(state-set! 'NopackDiagnosticStatus nopack-diagnostic-status)
(steel-export! 'NopackDiagnosticStatus nopack-diagnostic-status)
(state-set! 'NopackLspStatus nopack-lsp-status)
(steel-export! 'NopackLspStatus nopack-lsp-status)
(state-set! 'NopackFileContext nopack-file-context)
(steel-export! 'NopackFileContext nopack-file-context)
(state-set! 'NopackBreadcrumbStatus nopack-breadcrumb-status)
(steel-export! 'NopackBreadcrumbStatus nopack-breadcrumb-status)
(state-set! 'NopackStatusline nopack-statusline)
(steel-export! 'NopackStatusline nopack-statusline)

(opt-set "statusline" "%!v:steel.NopackStatusline()")
