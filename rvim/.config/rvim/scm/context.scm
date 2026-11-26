;; 1:1 Steel port of: nvim/.config/nvim/lua/context.lua
;; Equivalence:
;; - `<leader>Ts`: indentation-based sticky scroll overlay (up to 8 context lines + separator)
;;   with companion gutter line-number float; no parser or LSP required.
;; - Scans at most 1,000 lines / 256 KiB above viewport; respects wrapped lines, closed folds,
;;   horizontal `leftcol`, `list`/`listchars`, and `User NopackBufferRestricted`.

(require-builtin rvim/api)
(require-builtin rvim/util)
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "state")

(define *enabled* (box #f))
(define *queued* (box #f))
(define *popup* (box #f))
(define *numbers* (box #f))
(define *cache* (box #f))
(define *rendered-config* (box #f))
(define *numbers-config* (box #f))
(define *number-hl* (nvim_create_namespace "nopack-sticky-numbers"))

(define *python-blocks*
  (hash "def" #t "class" #t "if" #t "elif" #t "else" #t "for" #t "while" #t
        "try" #t "except" #t "finally" #t "with" #t "match" #t "case" #t))

(define (close-sticky!)
  (define wins (list (unbox *popup*) (unbox *numbers*)))
  (set-box! *popup* #f)
  (set-box! *numbers* #f)
  (set-box! *numbers-config* #f)
  (set-box! *rendered-config* #f)
  (for-each
    (lambda (w)
      (when (and w (nvim_win_is_valid w))
        (nvim_win_close w #t)))
    wins))

(define (make-header-reader buf top bottom)
  (define first (max 1 (- top 1000)))
  (define last (min (nvim_buf_line_count buf) (+ bottom 20)))
  (if (> (- (nvim_buf_get_offset buf last) (nvim_buf_get_offset buf (- first 1))) (* 256 1024))
      (lambda (_t) (values '() #f))
      (let ([lines (nvim_buf_get_lines buf (- first 1) last #f)]
            [python? (equal? (bo-get buf "filetype") "python")]
            [indents (box (hash))])
        (define (indent-at line)
          (define cached (hash-try-get (unbox indents) line))
          (if cached
              cached
              (let ([v (fn-call "indent" line)])
                (set-box! indents (hash-insert (unbox indents) line v))
                v)))
        (define (raw-at line)
          (list-ref lines (- line first)))
        (define (text-at line)
          (define s (or (string/match (raw-at line) "^%s*(.-)%s*$") ""))
          (if (or (equal? s "")
                  (string/match s "^#")
                  (string/match s "^//")
                  (string/match s "^/%*")
                  (string/match s "^%*"))
              #f
              s))
        (lambda (cur-top)
          (define base
            (let loop ([b cur-top])
              (if (> b last)
                  b
                  (let ([t (text-at b)])
                    (if (and t (not (and (string/match t "^%)")
                                         (string/match t "[:{]$"))))
                        b
                        (loop (+ b 1)))))))
          (if (> base last)
              (values '() #f)
              (let ([start-line (- cur-top 1)]
                    [min-line (max first (- cur-top 1000))])
                (let loop ([line start-line] [ind (indent-at base)] [res '()] [func #f])
                  (if (or (< line min-line) (= ind 0))
                      (values res func)
                      (let ([t (text-at line)])
                        (if (not t)
                            (loop (- line 1) ind res func)
                            (let ([level (indent-at line)])
                              (if (>= level ind)
                                  (loop (- line 1) ind res func)
                                  (let* ([stripped (vector-ref (string/gsub t "^async%s+" "") 0)]
                                         [kw (or (string/match stripped "^([%a_]+)") "")]
                                         [starts-close (not (not (string/match t "^[%)%]%}]")))]
                                         [only-punct (not (not (string/match t "^[{%[(;]+$")))])
                                    (if (and (not starts-close)
                                             (not only-punct)
                                             (or (not python?) (hash-contains? *python-blocks* kw)))
                                        (let* ([entry (hash "text" (raw-at line) "lnum" line)]
                                               [new-func
                                                (or func
                                                    (and (or (equal? kw "def")
                                                             (equal? kw "function")
                                                             (not (not (string/match t "^local%s+function%s"))))
                                                         entry))])
                                          (loop (- line 1) level (cons entry res) new-func))
                                        (loop (- line 1) ind res func)))))))))))))))

(define (update-sticky!)
  (define win (nvim_get_current_win))
  (define buf (nvim_win_get_buf win))
  (if (or (not (unbox *enabled*))
          (not (is-editor? win))
          (not (allows? buf))
          (not (equal? (fn-call "getcmdwintype") "")))
      (close-sticky!)
      (let* ([view (fn-call "winsaveview")]
             [cursor (nvim_win_get_cursor win)]
             [screen-top (list-ref (fn-call "win_screenpos" win) 0)]
             [row (- (hash-ref (fn-call "screenpos" win (vector-ref cursor 0) (+ (vector-ref cursor 1) 1)) "row")
                     screen-top)]
             [limit (min 8 (floor (/ (nvim_win_get_height win) 3)) (- row 1))])
        (if (< limit 1)
            (close-sticky!)
            (let* ([total (nvim_buf_line_count buf)]
                   [topline (hash-ref view "topline")]
                   [targets
                    (let loop ([h 1] [line topline] [acc '()])
                      (if (> h (+ limit 1))
                          (reverse acc)
                          (let ([adv
                                 (let inner ([ln line])
                                   (if (>= ln total)
                                       ln
                                       (let ([next-ln (+ (max ln (fn-call "foldclosedend" ln)) 1)])
                                         (if (> next-ln total)
                                             ln
                                             (let ([next-row (hash-ref (fn-call "screenpos" win next-ln 1) "row")])
                                               (if (or (= next-row 0) (> next-row (+ screen-top h)))
                                                   ln
                                                   (inner next-ln)))))))])
                            (loop (+ h 1) adv (cons adv acc)))))]
                   [key (list win buf (nvim_buf_get_changedtick buf) topline
                              (bo-get buf "tabstop") (bo-get buf "vartabstop") (bo-get buf "filetype") targets)])
              (unless (and (unbox *cache*) (equal? (hash-ref (unbox *cache*) "key") key))
                (define headers (make-header-reader buf topline (last targets)))
                (define top-header (headers topline))
                (define lines0 (list-ref top-header 0))
                (define func0 (list-ref top-header 1))
                (define sticky-header
                  (let loop ([iter 0] [ls lines0] [active-function func0] [cnt (min (length lines0) limit)])
                    (if (or (>= iter limit) (= cnt 0))
                        (values ls active-function cnt)
                        (let* ([header (headers (list-ref targets cnt))]
                               [covered (car header)]
                               [enclosing (cadr header)])
                          (cond
                            [(and enclosing active-function
                                  (not (= (hash-ref enclosing "lnum") (hash-ref active-function "lnum")))
                                  (>= (hash-ref enclosing "lnum") topline))
                             (define boundary (- (hash-ref (fn-call "screenpos" win (hash-ref enclosing "lnum") 1) "row")
                                                 screen-top))
                             (values ls active-function (max 0 (min cnt (- boundary 1))))]
                            [(< (length covered) cnt)
                             (values ls active-function cnt)]
                            [else
                             (define next-cnt (min (length covered) limit))
                             (if (= next-cnt cnt)
                                 (values covered enclosing cnt)
                                 (loop (+ iter 1) covered enclosing next-cnt))])))))
                (define lines (list-ref sticky-header 0))
                (define func (list-ref sticky-header 1))
                (define count (list-ref sticky-header 2))
                (define raw-scopes (drop lines (- (length lines) count)))
                (define scopes1
                  (if (and (> count 0) (not (member (car lines) raw-scopes)))
                      (cons (car lines) (cdr raw-scopes))
                      raw-scopes))
                (define scopes2
                  (if (and (> count 0) func (not (member func scopes1)))
                      (if (= count 1)
                          (list func)
                          (cons (car scopes1) (cons func (cddr scopes1))))
                      scopes1))
                (set-box! *cache* (hash "key" key "scopes" scopes2)))
              (define scopes (hash-ref (unbox *cache*) "scopes"))
              (if (null? scopes)
                  (close-sticky!)
                  (let* ([gutter (hash-ref (car (fn-call "getwininfo" win)) "textoff")]
                         [width (- (nvim_win_get_width win) gutter)])
                    (if (< width 1)
                        (close-sticky!)
                        (let* ([show-num (or (wo-get win "number") (wo-get win "relativenumber"))]
                               [lines (append (map (lambda (e) (hash-ref e "text")) scopes)
                                              (list (make-string width #\─)))]
                               [labels (append
                                         (map (lambda (e)
                                                (define lbl (if show-num (number->string (hash-ref e "lnum")) ""))
                                                (string-append (make-string (max 0 (- gutter (string-length lbl) 1)) #\space)
                                                               lbl " "))
                                              scopes)
                                         (list (make-string gutter #\─)))]
                               [cfg (hash "relative" "win" "win" win "row" 0 "col" gutter
                                          "width" width "height" (length lines)
                                          "focusable" #f "style" "minimal" "border" "none" "zindex" 20)])
                          (cond
                            [(or (not (unbox *popup*)) (not (nvim_win_is_valid (unbox *popup*))))
                             (define scratch (nvim_create_buf #f #t))
                             (bo-set scratch "bufhidden" "wipe")
                             (define p (nvim_open_win scratch #f cfg))
                             (set-box! *popup* p)
                             (wo-local-set p "winhighlight" "Normal:Pmenu,EndOfBuffer:Pmenu")
                             (wo-local-set p "wrap" #f)]
                            [(not (equal? (unbox *rendered-config*) cfg))
                             (nvim_win_set_config (unbox *popup*) cfg)])
                          (set-box! *rendered-config* cfg)
                          (define p (unbox *popup*))
                          (define scratch (nvim_win_get_buf p))
                          (bo-set scratch "tabstop" (bo-get buf "tabstop"))
                          (bo-set scratch "vartabstop" (bo-get buf "vartabstop"))
                          (for-each
                            (lambda (opt)
                              (unless (equal? (wo-get p opt) (wo-get win opt))
                                (wo-local-set p opt (wo-get win opt))))
                            '("list" "listchars"))
                          (define syn (let ([s (bo-get buf "syntax")]) (if (equal? s "") (bo-get buf "filetype") s)))
                          (unless (equal? (bo-get scratch "syntax") syn)
                            (bo-set scratch "syntax" syn))
                          (unless (equal? (nvim_buf_get_lines scratch 0 -1 #f) lines)
                            (bo-set scratch "modifiable" #t)
                            (nvim_buf_set_lines scratch 0 -1 #f lines)
                            (bo-set scratch "modifiable" #f))
                          (define leftcol (hash-ref view "leftcol"))
                          (unless (= (hash-ref (car (fn-call "getwininfo" p)) "leftcol") leftcol)
                            (wo-local-set p "virtualedit" "all")
                            (win-call
                              p
                              (lambda ()
                                (cmd (string-append "normal! " (number->string (+ leftcol 1)) "|"))
                                (fn-call "winrestview" (hash "topline" 1 "leftcol" leftcol)))))
                          (if (> gutter 0)
                              (let ([layout (hash-insert (hash-insert cfg "col" 0) "width" gutter)])
                                (cond
                                  [(or (not (unbox *numbers*)) (not (nvim_win_is_valid (unbox *numbers*))))
                                   (define nb (nvim_create_buf #f #t))
                                   (bo-set nb "bufhidden" "wipe")
                                   (define nw (nvim_open_win nb #f layout))
                                   (set-box! *numbers* nw)
                                   (wo-local-set nw "winhighlight" "Normal:Pmenu,EndOfBuffer:Pmenu,LineNr:LineNr")]
                                  [(not (equal? (unbox *numbers-config*) layout))
                                   (nvim_win_set_config (unbox *numbers*) layout)])
                                (set-box! *numbers-config* layout)
                                (define nb (nvim_win_get_buf (unbox *numbers*)))
                                (unless (equal? (nvim_buf_get_lines nb 0 -1 #f) labels)
                                  (bo-set nb "modifiable" #t)
                                  (nvim_buf_set_lines nb 0 -1 #f labels)
                                  (bo-set nb "modifiable" #f)
                                  (nvim_buf_clear_namespace nb *number-hl* 0 -1)
                                  (let loop ([r 0])
                                    (when (< r (- (length labels) 1))
                                      (nvim_buf_set_extmark
                                        nb *number-hl* r 0
                                        (hash "end_col" (string-length (list-ref labels r))
                                              "hl_group" "LineNr"))
                                      (loop (+ r 1))))))
                              (when (unbox *numbers*)
                                (when (nvim_win_is_valid (unbox *numbers*))
                                  (nvim_win_close (unbox *numbers*) #t))
                                (set-box! *numbers* #f)
                                (set-box! *numbers-config* #f))))))))))))

(define (queue-sticky! (_args #f))
  (when (and (unbox *enabled*) (not (unbox *queued*)))
    (set-box! *queued* #t)
    (schedule
      (lambda ()
        (set-box! *queued* #f)
        (update-sticky!)))))

(define *sticky-group* (nvim_create_augroup "nopack-sticky-scroll" (hash "clear" #t)))

(nvim_create_autocmd
  "User"
  (hash "group" *sticky-group*
        "pattern" "NopackBufferRestricted"
        "callback" (lambda (args)
                     (define c (unbox *cache*))
                     (when (and c (= (list-ref (hash-ref c "key") 1) (hash-ref (hash-ref args "data") "buf")))
                       (close-sticky!)
                       (set-box! *cache* #f)))))

(nvim_create_autocmd
  '("VimEnter" "BufEnter" "WinEnter" "WinScrolled" "VimResized"
    "CursorMoved" "CursorMovedI" "TextChanged" "TextChangedI" "InsertLeave" "FileType")
  (hash "group" *sticky-group* "callback" queue-sticky!))

(nvim_create_autocmd
  "OptionSet"
  (hash "group" *sticky-group*
        "pattern" '("number" "relativenumber" "numberwidth" "signcolumn" "foldcolumn" "statuscolumn"
                    "list" "listchars" "tabstop" "vartabstop" "shiftwidth" "wrap" "previewwindow")
        "callback" (lambda (_args)
                     (when (equal? (hash-try-get (nvim_win_get_config 0) "relative") "")
                       (queue-sticky!)))))

(nvim_create_autocmd
  '("BufLeave" "WinLeave" "TabLeave")
  (hash "group" *sticky-group* "callback" (lambda (_args) (close-sticky!))))

(nvim_create_autocmd
  "WinClosed"
  (hash "group" *sticky-group*
        "callback" (lambda (args)
                     (define c (unbox *cache*))
                     (when (and c (= (string->number (hash-ref args "match")) (list-ref (hash-ref c "key") 0)))
                       (close-sticky!)
                       (set-box! *cache* #f)))))

(keymap-set
  "n"
  "<leader>Ts"
  (lambda ()
    (set-box! *enabled* (not (unbox *enabled*)))
    (if (unbox *enabled*) (queue-sticky!) (close-sticky!)))
  (hash "desc" "Toggle sticky scroll"))
