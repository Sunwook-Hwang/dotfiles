;; 1:1 Steel port of: nvim/.config/nvim/lua/statusline.lua
;; Equivalence:
;; - Computes WCAG contrast ratio for `NopackGitBranch` on `ModeChanged` / `ColorScheme`
;;   and derives `NopackStatusError` / `NopackStatusWarn` from `StatusLine`.
;; - Caches per-buffer diagnostics (`DiagnosticChanged`/`BufWipeout`) and LSP clients
;;   (`LspAttach`/`LspDetach`/`BufWipeout`, pruning stopped clients on read).
;; - Exposes statusline components via `v:steel.*` callbacks registered on `state`:
;;   `NopackStatusline`, `NopackGitStatus`, `NopackDiagnosticStatus`, `NopackLspStatus`,
;;   `NopackFileContext`, and `NopackBreadcrumbStatus`.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/fs")
(require "rvim/schedule")
(require "rvim/lsp")
(require "rvim/diagnostic")
(require "rvim/string")
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
      [(or (equal? mode "v") (equal? mode "V") (equal? mode "\x16")) "Constant"]
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
        (define-values (fg1 ctermfg1)
          (if (> (contrast-ratio (relative-luminance normal-fg) bg-lum)
                 (contrast-ratio (relative-luminance fg0) bg-lum))
              (values normal-fg (or (hash-try-get normal "ctermfg") 15))
              (values fg0 ctermfg0)))
        (define-values (fg ctermfg)
          (if (< (contrast-ratio (relative-luminance fg1) bg-lum) 4.5)
              (if (> bg-lum 0.179)
                  (values #x000000 0)
                  (values #xffffff 15))
              (values fg1 ctermfg1)))
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
        (hash-insert base "bg" (hash-try-get base "fg"))
        base))
  (define cterm1 (hash-try-get h1 "cterm"))
  (define h2
    (if (and cterm1 (hash-try-get cterm1 "reverse"))
        (hash-insert
          (hash-insert h1 "ctermbg" (hash-try-get h1 "ctermfg"))
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

(define *diagnostic-counts* (box (hash)))
(define *lsp-status-cache* (box (hash)))

(nvim_create_autocmd
  '("DiagnosticChanged" "BufWipeout")
  (hash "group" (nvim_create_augroup "nopack-diagnostic-status" (hash "clear" #t))
        "callback" (lambda (args)
                     (set-box! *diagnostic-counts*
                               (hash-remove (unbox *diagnostic-counts*) (hash-ref args "buf"))))))

(define (status-clients buf)
  (define existing (hash-try-get (unbox *lsp-status-cache*) buf))
  (define entry
    (or existing
        (let ([fresh (box (hash "clients" (lsp-get-clients (hash "bufnr" buf)) "text" #f))])
          (set-box! *lsp-status-cache* (hash-insert (unbox *lsp-status-cache*) buf fresh))
          fresh)))
  (define data (unbox entry))
  (define clients (hash-ref data "clients"))
  (define alive (filter (lambda (c) (not ((hash-ref c "is_stopped") c))) clients))
  (when (not (= (length alive) (length clients)))
    (set-box! entry (hash "clients" alive "text" #f)))
  entry)

(state-set! 'status-clients status-clients)

(define (escape-percent s)
  (string-replace s "%" "%%"))

(define (strip-controls s)
  (car (lua-gsub s "[%c]" " ")))

(define (nopack-git-status)
  (define status (b-get 0 "nopack_git_status"))
  (if (or (not status) (equal? status ""))
      ""
      (string-append "%#NopackGitBranch# " (escape-percent status) " %*")))

(define (nopack-diagnostic-status)
  (define buf (nvim_get_current_buf))
  (define counts
    (or (hash-try-get (unbox *diagnostic-counts*) buf)
        (let ([c (diagnostic-count buf)])
          (set-box! *diagnostic-counts* (hash-insert (unbox *diagnostic-counts*) buf c))
          c)))
  (define specs
    (list (list (diagnostic-severity "ERROR") "E:" "NopackStatusError")
          (list (diagnostic-severity "WARN") "W:" "NopackStatusWarn")
          (list (diagnostic-severity "HINT") "H:" #f)))
  (define parts
    (filter-map
      (lambda (spec)
        (define count (or (hash-try-get counts (car spec)) 0))
        (if (> count 0)
            (let ([text (string-append (cadr spec) " " (number->string count))]
                  [grp (caddr spec)])
              (if grp
                  (string-append "%#" grp "#" text "%*")
                  text))
            #f))
      specs))
  (string-join parts " "))

(define (nopack-lsp-status)
  (if (not (state-get 'language-status-visible #t))
      ""
      (let ([buf (nvim_get_current_buf)])
        (if (not (is-source? buf))
            ""
            (let* ([entry (status-clients buf)]
                   [data (unbox entry)]
                   [cached (hash-try-get data "text")]
                   [text
                    (if (string? cached)
                        cached
                        (let* ([names-set
                                (foldl (lambda (c acc)
                                         (hash-insert acc (strip-controls (hash-ref c "name")) #t))
                                       (hash)
                                       (hash-ref data "clients"))]
                               [sorted (fn-call "sort" (hash-keys->list names-set))]
                               [rendered
                                (if (> (length sorted) 0)
                                    (string-append "[LSP: " (escape-percent (string-join sorted ", ")) "]")
                                    "")])
                          (set-box! entry (hash-insert data "text" rendered))
                          rendered))])
              (cond
                [(and (equal? text "")
                      (state-get 'ctags-kind)
                      (allows? buf)
                      (not (equal? (nvim_buf_get_name buf) ""))
                      (equal? (state-call 'analysis-backend-get buf) "ctags"))
                 (string-append "[CTAGS: " (state-get 'ctags-kind) "]")]
                [(not (equal? text "")) text]
                [else "%#NopackLspMissing#[LSP X]%*"]))))))

(nvim_create_autocmd
  '("LspAttach" "LspDetach" "BufWipeout")
  (hash "group" (nvim_create_augroup "nopack-lsp-status" (hash "clear" #t))
        "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (set-box! *lsp-status-cache* (hash-remove (unbox *lsp-status-cache*) buf))
          (unless (equal? (hash-ref args "event") "BufWipeout")
            (schedule
              (lambda ()
                (set-box! *lsp-status-cache* (hash-remove (unbox *lsp-status-cache*) buf))
                (cmd "redrawstatus")))))))

(define (nopack-file-context)
  (define win (nvim_get_current_win))
  (define file (nvim_buf_get_name (nvim_win_get_buf win)))
  (cond
    [(or (equal? file "") (not (breadcrumbs-enabled?)))
     (if (equal? file "") "[No Name]" (fn-call "fnamemodify" file ":t"))]
    [(not (is-editor? win))
     (fn-call "fnamemodify" file ":~:.")]
    [else
     (define res (state-call 'find-project (fs-dirname file)))
     (if (and res (caddr res))
         (let* ([root (car res)]
                [trimmed (car (lua-gsub root "/+$" ""))]
                [prefix (string-append trimmed "/")]
                [plen (string-length prefix)])
           (if (and (>= (string-length file) plen)
                    (equal? (substring file 0 plen) prefix))
               (substring file plen (string-length file))
               (fn-call "fnamemodify" file ":~:.")))
         (fn-call "fnamemodify" file ":~:."))]))

(define (nopack-breadcrumb-status)
  (breadcrumbs-status (nvim_get_current_win)))

(define (nopack-statusline)
  (define raw-win (g-get "statusline_winid"))
  (define win (or (and (number? raw-win) raw-win)
                  (and (string? raw-win) (string->number raw-win))
                  (nvim_get_current_win)))
  (if (not (= win (nvim_get_current_win)))
      " %{v:steel.NopackFileContext()} %= %y "
      "%{%v:steel.NopackGitStatus()%} %<%{v:steel.NopackFileContext()}%{%v:steel.NopackBreadcrumbStatus()%} %m%r%h %= %{%v:steel.NopackDiagnosticStatus()%} %{%v:steel.NopackLspStatus()%} %{v:steel.NopackFormatStatus()} %y | %4l:%3c | %3p%% "))

(state-set! 'NopackGitStatus nopack-git-status)
(state-set! 'NopackDiagnosticStatus nopack-diagnostic-status)
(state-set! 'NopackLspStatus nopack-lsp-status)
(state-set! 'NopackFileContext nopack-file-context)
(state-set! 'NopackBreadcrumbStatus nopack-breadcrumb-status)
(state-set! 'NopackStatusline nopack-statusline)

(opt-set "statusline" "%!v:steel.NopackStatusline()")
