;; 1:1 Steel port of: nvim/.config/nvim/lua/pickers.lua
;; Equivalence:
;; - Shared native Telescope replacement: 3-pane floating picker (query / results / preview)
;;   with 120ms debounced `matchfuzzy` or live-search callback, 64 KiB chunked async file
;;   preview (`read-preview`), quickfix export (`<C-q>`), and diagnostic severity sorting.
;; - Connects `ui-select-set!` and `location-picker` to the shared picker UI.
;; - Registers `'records`, `'read-preview`, `'open-picker`, and `'location-picker` on `state`.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/uv")
(require "rvim/ui")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "jobs")
(require "state")

(define *diagnostic-types*
  (hash "E" (hash "rank" 1 "name" "Error" "source" "NopackStatusError")
        "W" (hash "rank" 2 "name" "Warn" "source" "NopackStatusWarn")
        "I" (hash "rank" 3 "name" "Info" "source" "DiagnosticInfo")
        "N" (hash "rank" 4 "name" "Hint" "source" "DiagnosticHint")))

(define (diagnostic-highlights!)
  (for-each
    (lambda (k)
      (define kind (hash-ref *diagnostic-types* k))
      (define hl (nvim_get_hl 0 (hash "name" (hash-ref kind "source") "link" #f)))
      (nvim_set_hl
        0 (string-append "NopackPicker" (hash-ref kind "name"))
        (hash "fg" (hash-try-get hl "fg") "ctermfg" (hash-try-get hl "ctermfg") "bold" #t)))
    '("E" "W" "I" "N")))

(diagnostic-highlights!)
(nvim_create_autocmd
  "ColorScheme"
  (hash "group" (nvim_create_augroup "nopack-picker-highlights" (hash "clear" #t))
        "callback" (lambda (_args) (diagnostic-highlights!))))

(define (sort-diagnostics items)
  (if (and (not (null? items))
           (hash-try-get (car items) "type")
           (hash-contains? *diagnostic-types* (hash-ref (car items) "type")))
      (sort items
            (lambda (a b)
              (define ra (hash-ref (hash-ref *diagnostic-types* (hash-ref a "type")) "rank"))
              (define rb (hash-ref (hash-ref *diagnostic-types* (hash-ref b "type")) "rank"))
              (if (= ra rb) (< (hash-ref a "order") (hash-ref b "order")) (< ra rb))))
      items))

(define (records output separator (limited #f) (maximum #f))
  (define slen (string-length separator))
  (define olen (string-length output))
  (let loop ([offset 0] [count 0] [acc '()])
    (if (and maximum (>= count maximum))
        (reverse acc)
        (let ([idx (string-index-of output separator offset)])
          (if (not idx)
              (if (and (not limited) (< offset olen))
                  (reverse (cons (substring output offset olen) acc))
                  (reverse acc))
              (loop (+ idx slen) (+ count 1) (cons (substring output offset idx) acc)))))))

(state-set! 'records records)

(define (show-results! items title)
  (fn-call "setqflist" '() " " (hash "title" title "items" items))
  (if (null? items)
      (notify (string-append "No results: " title))
      (begin
        (state-call 'focus-editor)
        (cmd "botright copen")
        (bo-set 0 "buflisted" #f)
        (wo-local-set 0 "wrap" #f))))

(define (read-preview! file first count current? done (max-bytes #f))
  (uv-fs-open
    file "r" 438
    (lambda (err fd)
      (schedule
        (lambda ()
          (if (or err (not fd))
              (when (current?) (done #f))
              (let ([offset-box (box 0)]
                    [row-box (box 1)]
                    [prefix-box (box "")]
                    [lines-box (box '())]
                    [last-row (+ first count -1)])
                (define (finish! res)
                  (uv-fs-close fd)
                  (when (current?) (done res)))
                (define (read-next!)
                  (if (not (current?))
                      (finish! #f)
                      (uv-fs-read
                        fd 65536 (unbox offset-box)
                        (lambda (failure data)
                          (schedule
                            (lambda ()
                              (cond
                                [(or (not (current?)) failure (and data (string-contains? data "\x00")))
                                 (finish! #f)]
                                [(or (not data) (equal? data ""))
                                 (when (and (>= (unbox row-box) first) (not (equal? (unbox prefix-box) "")))
                                   (set-box! lines-box (cons (unbox prefix-box) (unbox lines-box))))
                                 (finish! (reverse (unbox lines-box)))]
                                [else
                                 (define dlen (string-length data))
                                 (set-box! offset-box (+ (unbox offset-box) dlen))
                                 (define done-early
                                   (let loop ([start 0])
                                     (if (>= start dlen)
                                         #f
                                         (let* ([nl (string-index-of data "\n" start)]
                                                [end-pos (or nl dlen)]
                                                [row (unbox row-box)]
                                                [pref (unbox prefix-box)])
                                           (when (and (>= row first) (< (string-length pref) 500))
                                             (define take-end (min end-pos (+ start (- 500 (string-length pref)))))
                                             (set-box! prefix-box (string-append pref (substring data start take-end))))
                                           (if (not nl)
                                               #f
                                               (begin
                                                 (when (>= row first)
                                                   (define cleaned (trim-end-matches (unbox prefix-box) "\r"))
                                                   (set-box! lines-box (cons cleaned (unbox lines-box))))
                                                 (set-box! row-box (+ row 1))
                                                 (set-box! prefix-box "")
                                                 (if (> (+ row 1) last-row)
                                                     #t
                                                     (loop (+ nl 1)))))))))
                                 (cond
                                   [done-early (finish! (reverse (unbox lines-box)))]
                                   [(and max-bytes (>= (unbox offset-box) max-bytes))
                                    (when (and (>= (unbox row-box) first) (not (equal? (unbox prefix-box) "")))
                                      (set-box! lines-box (cons (unbox prefix-box) (unbox lines-box))))
                                    (finish! (reverse (unbox lines-box)))]
                                   [else (read-next!)])])))))))
                (read-next!))))))))

(state-set! 'read-preview read-preview!)

(define (open-picker title (opts (hash)))
  (define prev (state-get 'active-picker))
  (when prev ((hash-ref prev "close")))
  (define origin (nvim_get_current_win))
  (state-call 'focus-editor)
  (define target (nvim_get_current_win))
  (define cols (go-get "columns"))
  (define lines-opt (go-get "lines"))
  (define w0 (max 24 (min (- cols 4) 120)))
  (define h0 (max 4 (min (- lines-opt 8) 22)))
  (define scale (min 1.8 (/ (max 1 (- cols 4)) w0) (/ (max 1 (- lines-opt 8)) h0)))
  (define width (max 1 (floor (+ (* w0 scale) 0.5))))
  (define height (max 1 (floor (+ (* h0 scale) 0.5))))
  (define preview-context (min 8 (- height 1)))
  (define row (max 0 (floor (/ (- lines-opt height 4) 2))))
  (define col (max 0 (floor (/ (- cols width) 2))))
  (define list-width (if (or (>= width 70) (hash-try-get opts "preview")) (floor (* width 0.48)) width))

  (define items-box (box '()))
  (define matches-box (box '()))
  (define index-box (box 1))
  (define gen-box (box 0))
  (define closed-box (box #f))
  (define windows-box (box '()))
  (define buffers-box (box '()))

  (define (pane role r c w h enter)
    (define b (nvim_create_buf #f #t))
    (b-set b "nopack_picker_role" role)
    (bo-set b "bufhidden" "wipe")
    (define w-id
      (nvim_open_win
        b enter
        (hash "relative" "editor" "row" r "col" c "width" w "height" h
              "style" "minimal" "border" "rounded"
              "title" (if (equal? role "query") title role))))
    (wo-local-set w-id "wrap" #f)
    (set-box! windows-box (append (unbox windows-box) (list w-id)))
    (set-box! buffers-box (append (unbox buffers-box) (list b)))
    (cons b w-id))

  (define list-pair (pane "results" (+ row 3) col list-width height #f))
  (define list-buf (car list-pair))
  (define list-win (cdr list-pair))
  (define preview-buf #f)
  (define preview-win #f)
  (when (< list-width width)
    (define pp (pane "preview" (+ row 3) (+ col list-width 2) (- width list-width 2) height #f))
    (set! preview-buf (car pp))
    (set! preview-win (cdr pp))
    (unless (hash-try-get opts "preview")
      (b-set preview-buf "nopack_preview_first" 1)
      (wo-local-set preview-win "number" #t)
      (wo-local-set preview-win "signcolumn" "yes:1")
      (wo-local-set preview-win "statuscolumn" "%s%{v:lnum + b:nopack_preview_first - 1}  ")))
  (define query-buf (car (pane "query" row col width 1 #t)))
  (wo-local-set list-win "cursorline" #t)
  (wo-local-set list-win "cursorlineopt" "line")
  (wo-local-set list-win "winhighlight" "CursorLine:NopackPickerSelection,CursorLineNr:NopackPickerSelection")
  (define group (nvim_create_augroup "nopack-picker" (hash "clear" #t)))

  (define (fill! buf ls)
    (when (nvim_buf_is_valid buf)
      (bo-set buf "modifiable" #t)
      (nvim_buf_set_lines buf 0 -1 #f (if (null? ls) '("No matches") ls))
      (bo-set buf "modifiable" #f)))

  (define preview-ns (nvim_create_namespace "nopack-picker-preview"))
  (define preview-gen (box 0))

  (define (preview! item)
    (set-box! preview-gen (+ (unbox preview-gen) 1))
    (define ver (unbox preview-gen))
    (when preview-buf
      (define custom-preview (hash-try-get opts "preview"))
      (if custom-preview
          (when item (custom-preview item preview-buf preview-win))
          (begin
            (nvim_buf_clear_namespace preview-buf preview-ns 0 -1)
            (fill! preview-buf '(""))
            (if (not item)
                (bo-set preview-buf "syntax" "")
                (let ()
                  (define (display! ls first (ft #f))
                    (unless (or (unbox closed-box) (not (= ver (unbox preview-gen))))
                      (define target-line (max 1 (or (hash-try-get item "lnum") 1)))
                      (define chunk
                        (map (lambda (s) (substring s 0 (min 500 (string-length s))))
                             (take ls (min (length ls) height))))
                      (fill! preview-buf chunk)
                      (b-set preview-buf "nopack_preview_first" first)
                      (define sel (- target-line first))
                      (when (and (>= sel 0) (< sel (length chunk)))
                        (define c (min (max 0 (- (or (hash-try-get item "col") 1) 1))
                                       (string-length (list-ref chunk sel))))
                        (nvim_win_set_cursor preview-win (vector (+ sel 1) c))
                        (nvim_buf_set_extmark
                          preview-buf preview-ns sel 0
                          (hash "sign_text" ">" "sign_hl_group" "Search"
                                "number_hl_group" "CursorLineNr" "line_hl_group" "CursorLine")))
                      (define syn
                        (or ft
                            (fn-call "filetype_match"
                                     (hash "filename" (hash-try-get item "filename") "buf" preview-buf))
                            ""))
                      (unless (equal? (bo-get preview-buf "syntax") syn)
                        (bo-set preview-buf "syntax" syn))))
                  (define fname (hash-try-get item "filename"))
                  (define bnr (or (hash-try-get item "bufnr") (and fname (fn-call "bufnr" fname)) -1))
                  (cond
                    [(and (> bnr 0) (nvim_buf_is_loaded bnr))
                     (define first (max 0 (- (or (hash-try-get item "lnum") 1) preview-context 1)))
                     (define ls (nvim_buf_get_lines bnr first (+ first height) #f))
                     (define ft (bo-get bnr "filetype"))
                     (display! ls (+ first 1) (if (equal? ft "") #f ft))]
                    [fname
                     (define lnum (or (hash-try-get item "lnum") 1))
                     (define first (max 1 (- lnum preview-context)))
                     (read-preview!
                       fname first height
                       (lambda () (and (not (unbox closed-box)) (= ver (unbox preview-gen))))
                       (lambda (ls)
                         (if (not ls)
                             (begin (bo-set preview-buf "syntax" "") (fill! preview-buf '("No text preview")))
                             (display! ls first)))
                       (if (= lnum 1) 65536 #f))]
                    [(hash-try-get item "text")
                     (bo-set preview-buf "syntax" "")
                     (fill! preview-buf (split-many (hash-ref item "text") "\n"))])))))))

  (define selected-box (box #f))
  (define list-ns (nvim_create_namespace "nopack-picker-list"))

  (define (select-item!)
    (define ms (unbox matches-box))
    (define idx (max 1 (min (unbox index-box) (max 1 (length ms)))))
    (set-box! index-box idx)
    (nvim_win_set_cursor list-win (vector idx 0))
    (define item (and (<= idx (length ms)) (list-ref ms (- idx 1))))
    (define changed (not (equal? (unbox selected-box) item)))
    (when (or (not (hash-try-get opts "preview")) changed)
      (preview! item))
    (when (and (hash-try-get opts "highlight") changed)
      ((hash-ref opts "highlight") item))
    (set-box! selected-box item))

  (define (draw!)
    (unless (unbox closed-box)
      (define ms (unbox matches-box))
      (fill! list-buf
             (map (lambda (it)
                    (car (lua-gsub (hash-ref it "label") "[%c]" " ")))
                  ms))
      (nvim_buf_clear_namespace list-buf list-ns 0 -1)
      (let loop ([xs ms] [i 0])
        (unless (null? xs)
          (define t (hash-try-get (car xs) "type"))
          (define kind (and t (hash-try-get *diagnostic-types* t)))
          (when kind
            (nvim_buf_set_extmark
              list-buf list-ns i 0
              (hash "end_col" 1 "hl_group" (string-append "NopackPicker" (hash-ref kind "name")))))
          (loop (cdr xs) (+ i 1))))
      (select-item!)))

  (define (filter-items!)
    (define query
      (if (hash-try-get opts "live")
          ""
          (let ([ls (nvim_buf_get_lines query-buf 0 1 #f)])
            (if (null? ls) "" (car ls)))))
    (define items (unbox items-box))
    (define matched
      (if (equal? query "")
          (take items (min 200 (length items)))
          (sort-diagnostics (fn-call "matchfuzzy" items query (hash "key" "label" "limit" 200)))))
    (set-box! matches-box matched)
    (set-box! index-box 1)
    (draw!))

  (define (set-items! items)
    (unless (unbox closed-box)
      (set-box! items-box items)
      (set-box! selected-box #f)
      (filter-items!)))

  (define (set-files! files (root #f))
    (unless (unbox closed-box)
      (set-items! (state-call 'file-items files root))))

  (define input-timer (box #f))
  (define (cancel-input!)
    (stop-timer! (unbox input-timer))
    (set-box! input-timer #f))

  (define state-box (box #f))
  (define (close! (accepted #f))
    (unless (unbox closed-box)
      (set-box! closed-box #t)
      (cancel-input!)
      (when (hash-try-get opts "cancel")
        ((hash-ref opts "cancel")))
      (cmd "stopinsert")
      (nvim_del_augroup_by_id group)
      (for-each (lambda (w) (when (nvim_win_is_valid w) (nvim_win_close w #t)))
                (unbox windows-box))
      (when (nvim_win_is_valid origin)
        (nvim_set_current_win origin))
      (when (equal? (state-get 'active-picker) (unbox state-box))
        (state-set! 'active-picker #f))
      (when (and (not accepted) (hash-try-get opts "on_cancel"))
        ((hash-ref opts "on_cancel")))))

  (define (accept!)
    (when (= (nvim_get_current_win) list-win)
      (set-box! index-box (vector-ref (nvim_win_get_cursor list-win) 0)))
    (define ms (unbox matches-box))
    (define idx (unbox index-box))
    (when (and (>= idx 1) (<= idx (length ms)))
      (define item (list-ref ms (- idx 1)))
      (close! #t)
      (if (is-editor? target)
          (nvim_set_current_win target)
          (state-call 'focus-editor))
      (if (hash-try-get item "action")
          ((hash-ref item "action"))
          (begin
            (cond
              [(and (hash-try-get item "bufnr") (nvim_buf_is_valid (hash-ref item "bufnr")))
               (nvim_set_current_buf (hash-ref item "bufnr"))]
              [(hash-try-get item "filename")
               (cmd (string-append "edit " (fn-call "fnameescape" (hash-ref item "filename"))))])
            (when (hash-try-get item "lnum")
              (define ln (min (hash-ref item "lnum") (nvim_buf_line_count 0)))
              (nvim_win_set_cursor 0 (vector (max 1 ln) (max 0 (- (or (hash-try-get item "col") 1) 1))))
              (cmd "normal! zz"))))))

  (define (move! delta)
    (define n (length (unbox matches-box)))
    (when (> n 0)
      (set-box! index-box (+ (modulo (+ (- (unbox index-box) 1) delta n) n) 1))
      (select-item!)))

  (for-each
    (lambda (buf)
      (for-each
        (lambda (k) (keymap-set '("n" "i") k (lambda () (close!)) (hash "buf" buf "nowait" #t)))
        '("<Esc>" "<C-c>"))
      (when (and (hash-try-get opts "preview") preview-win)
        (for-each
          (lambda (k)
            (keymap-set
              '("n" "i") k
              (lambda ()
                (nvim_win_call
                  preview-win
                  (lambda ()
                    (cmd (string-append "normal! "
                                        (nvim_replace_termcodes (if (equal? k "<C-f>") "<C-d>" "<C-u>") #t #f #t))))))
              (hash "buf" buf "desc" "Scroll undo preview")))
          '("<C-f>" "<C-b>")))
      (keymap-set '("n" "i") "<CR>" accept! (hash "buf" buf))
      (for-each (lambda (k) (keymap-set '("n" "i") k (lambda () (move! 1)) (hash "buf" buf)))
                '("<C-n>" "<Down>" "<Tab>"))
      (for-each (lambda (k) (keymap-set '("n" "i") k (lambda () (move! -1)) (hash "buf" buf)))
                '("<C-p>" "<Up>" "<S-Tab>"))
      (keymap-set '("n" "i") "<C-q>"
                  (lambda ()
                    (define ms (unbox matches-box))
                    (close! #t)
                    (show-results! ms title))
                  (hash "buf" buf "desc" "Send matches to quickfix")))
    (unbox buffers-box))

  (define st
    (hash "closed" closed-box
          "generation" gen-box
          "close" close!
          "set_items" set-items!
          "set_files" set-files!))
  (set-box! state-box st)

  (nvim_create_autocmd
    '("TextChangedI" "TextChanged")
    (hash "group" group
          "buf" query-buf
          "callback"
          (lambda (_args)
            (set-box! gen-box (+ (unbox gen-box) 1))
            (define gen (unbox gen-box))
            (cancel-input!)
            (when (hash-try-get opts "live")
              (when (hash-try-get opts "cancel") ((hash-ref opts "cancel")))
              (set-box! items-box '())
              (set-box! matches-box '())
              (set-box! index-box 1)
              (draw!))
            (set-box! input-timer
                      (defer-fn
                        (lambda ()
                          (when (and (not (unbox closed-box)) (= gen (unbox gen-box)))
                            (set-box! input-timer #f)
                            (if (hash-try-get opts "live")
                                (let ([ls (nvim_buf_get_lines query-buf 0 1 #f)])
                                  ((hash-ref opts "live") (if (null? ls) "" (car ls)) st gen))
                                (filter-items!))))
                        120)))))

  (nvim_create_autocmd
    "WinClosed"
    (hash "group" group
          "pattern" (map number->string (unbox windows-box))
          "callback" (lambda (_args) (close!))))

  (state-set! 'active-picker st)
  (set-items! (or (hash-try-get opts "items") '()))
  (cmd "startinsert")
  st)

(state-set! 'open-picker open-picker)

;; Connect ui-select and location lists to the shared picker.
(ui-select-set!
  (lambda (items opts callback)
    (define o (or opts (hash)))
    (define fmt (hash-try-get o "format_item"))
    (define choices
      (let loop ([xs items] [i 1] [acc '()])
        (if (null? xs)
            (reverse acc)
            (let ([it (car xs)])
              (loop (cdr xs) (+ i 1)
                    (cons (hash "label" (if fmt (fmt it) (to-string it))
                                "action" (lambda () (callback it i)))
                          acc))))))
    (open-picker (or (hash-try-get o "prompt") "Select")
                 (hash "items" choices
                       "on_cancel" (lambda () (callback #f #f))))))

(define (location-picker title locations)
  (define root (state-call 'project-root))
  (define prefix (string-append root "/"))
  (define plen (string-length prefix))
  (define items
    (let loop ([xs locations] [order 1] [acc '()])
      (if (null? xs)
          (reverse acc)
          (let* ([it (car xs)]
                 [bnr (hash-try-get it "bufnr")]
                 [fname (or (hash-try-get it "filename") (and bnr (nvim_buf_get_name bnr)) "")]
                 [rel (if (and (>= (string-length fname) plen) (equal? (substring fname 0 plen) prefix))
                          (substring fname plen (string-length fname))
                          fname)]
                 [t (hash-try-get it "type")]
                 [kind (and t (hash-try-get *diagnostic-types* t))]
                 [badge (if kind (string-append (substring (hash-ref kind "name") 0 1) " ") "")]
                 [lbl (string-append badge rel ":" (number->string (or (hash-try-get it "lnum") 1))
                                     " " (or (hash-try-get it "text") ""))])
            (loop (cdr xs) (+ order 1)
                  (cons (hash "filename" fname "bufnr" bnr
                              "lnum" (hash-try-get it "lnum") "col" (hash-try-get it "col")
                              "text" (hash-try-get it "text") "type" t "order" order "label" lbl)
                        acc))))))
  (open-picker title (hash "items" (sort-diagnostics items))))

(state-set! 'location-picker location-picker)
