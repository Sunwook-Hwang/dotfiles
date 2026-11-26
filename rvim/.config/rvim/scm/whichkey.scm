;; 1:1 Steel port of: nvim/.config/nvim/lua/whichkey.lua
;; Equivalence:
;; - Normal-mode leader key guide: inspects global + buffer-local `n` keymaps,
;;   renders 1..3 column floating window with screen-cell truncation (`strdisplaywidth`),
;;   replays matched shortcut with count + register, cancels on Esc/Ctrl-c/leave.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/fn")
(require "rvim/cmd")
(require "rvim/notify")
(require "rvim/string")

(define leader (fn-call "nvim_replace_termcodes" "<leader>" #t #t #t))

(define groups
  (hash "s" "Search"
        "S" "Substitute"
        "b" "Buffer"
        "T" "Toggle"
        "l" "LSP & Diagnostic"
        "g" "Git"
        "p" "Project"
        "n" "File tree"
        "P" "Peerpad"))

(define *active* (box #f))

(define (collect-mappings buf)
  (define acc (hash))
  (for-each
    (lambda (lst)
      (for-each
        (lambda (item)
          (define lhs (hash-ref item "lhsraw"))
          (when (and (> (string-length lhs) (string-length leader))
                     (equal? (substring lhs 0 (string-length leader)) leader))
            (set! acc (hash-insert acc lhs item))))
        lst))
    (list (nvim_get_keymap "n") (nvim_buf_get_keymap buf "n")))
  acc)

(define (pad-spaces n)
  (if (<= n 0) "" (apply string-append (map (lambda (_) " ") (range 0 n)))))

(define (truncate-cells text limit)
  (if (<= (fn-call "strdisplaywidth" text) limit)
      text
      (let loop ((s (fn-call "strcharpart" text 0 (max 0 (- limit 1)))))
        (if (and (> (fn-call "strchars" s) 0)
                 (> (fn-call "strdisplaywidth" s) (- limit 1)))
            (loop (fn-call "strcharpart" s 0 (- (fn-call "strchars" s) 1)))
            (string-append s "…")))))

(define (guide)
  (define source-win (nvim_get_current_win))
  (define source-buf (nvim_get_current_buf))
  (define count (v-get "count"))
  (define register (v-get "register"))
  (define prefix leader)
  (define popup #f)
  (define cancelled #f)

  (define (close-popup!)
    (define w popup)
    (set! popup #f)
    (when (and w (nvim_win_is_valid w))
      (nvim_win_close w #t)))

  (define (choices items)
    (define next-keys (hash))
    (define plen (string-length prefix))
    (for-each
      (lambda (lhs)
        (when (and (> (string-length lhs) plen)
                   (equal? (substring lhs 0 plen) prefix))
          (define item (hash-ref items lhs))
          (define rest (fn-call "keytrans" (substring lhs plen (string-length lhs))))
          (define key (or (string/match rest "^<[^>]+>")
                          (fn-call "strcharpart" rest 0 1)))
          (cond
            ((equal? rest key)
             (set! next-keys (hash-insert next-keys key (or (hash-try-get item "desc") (hash-ref item "lhs")))))
            ((not (hash-contains? next-keys key))
             (define gkey (string-append (substring prefix (string-length leader) plen) key))
             (set! next-keys (hash-insert next-keys key (string-append "+ " (or (hash-try-get groups gkey) key))))))))
      (hash-keys->list items))
    (map (lambda (k) (string-append k "  " (hash-ref next-keys k)))
         (fn-call "sort" (hash-keys->list next-keys))))

  (define (draw! (entries #f))
    (define ents (or entries (choices (collect-mappings source-buf))))
    (define cols-opt (opt-get "columns"))
    (define lines-opt (opt-get "lines"))
    (define width (max 1 (min 120 (- cols-opt 4))))
    (define columns (max 1 (min 3 (quotient width 32))))
    (define cell (quotient width columns))
    (define rows (max 1 (quotient (+ (length ents) (- columns 1)) columns)))
    (define height (min rows (max 1 (- lines-opt 6))))
    (define vec (list->vector ents))
    (define lines
      (map (lambda (r)
             (apply string-append
                    (map (lambda (c)
                           (define idx (+ (* c rows) r))
                           (define raw (if (< idx (vector-length vec)) (vector-ref vec idx) ""))
                           (define txt (truncate-cells raw (max 1 (- cell 2))))
                           (string-append txt (pad-spaces (- cell (fn-call "strdisplaywidth" txt)))))
                         (range 0 columns))))
           (range 0 height)))
    (define cfg
      (hash "relative" "editor"
            "row" (max 0 (- lines-opt height (opt-get "cmdheight") 3))
            "col" (max 0 (quotient (- cols-opt width) 2))
            "width" width
            "height" height
            "style" "minimal"
            "border" "rounded"
            "focusable" #f
            "zindex" 80
            "title" (string-append " <leader>"
                                   (fn-call "keytrans" (substring prefix (string-length leader) (string-length prefix)))
                                   " · Esc: cancel ")))
    (if (or (not popup) (not (nvim_win_is_valid popup)))
        (let ((b (nvim_create_buf #f #t)))
          (bo-set b "bufhidden" "wipe")
          (set! popup (nvim_open_win b #f cfg)))
        (nvim_win_set_config popup cfg))
    (define b (nvim_win_get_buf popup))
    (bo-set b "modifiable" #t)
    (nvim_buf_set_lines b 0 -1 #f lines)
    (bo-set b "modifiable" #f)
    (cmd "redraw"))

  (set-box! *active*
            (hash "draw" draw!
                  "cancel"
                  (lambda ()
                    (set! cancelled #t)
                    (close-popup!)
                    (nvim_feedkeys (fn-call "nvim_replace_termcodes" "<Esc>" #t #t #t) "ni" #f))))

  (with-handler
    (lambda (err)
      (set-box! *active* #f)
      (close-popup!)
      (notify (to-string err) (log-level 'error)))
    (let loop ()
      (unless cancelled
        (define items (collect-mappings source-buf))
        (cond
          ((hash-contains? items prefix)
           (close-popup!)
           (define lead
             (string-append
               (if (not (equal? register "\"")) (string-append "\"" register) "")
               (if (> count 0) (number->string count) "")))
           (nvim_feedkeys (string-append lead prefix) "mi" #f))
          (else
           (define ents (choices items))
           (unless (null? ents)
             (when (equal? (fn-call "getcharstr" 1) "")
               (draw! ents))
             (define key (with-handler (lambda (_e) #f)
                                       (fn-call "getcharstr" -1 (hash "cursor" "keep"))))
             (define esc (fn-call "nvim_replace_termcodes" "<Esc>" #t #t #t))
             (when (and key
                        (not (equal? key esc))
                        (not (equal? key "\x03"))
                        (not cancelled)
                        (= (nvim_get_current_win) source-win)
                        (= (nvim_get_current_buf) source-buf))
               (set! prefix (string-append prefix key))
               (loop))))))))
  (set-box! *active* #f)
  (close-popup!))

(keymap-set "n" "<leader>" guide (hash "nowait" #t "silent" #t "desc" "Leader key guide"))

(define group (nvim_create_augroup "nopack-leader-guide" (hash "clear" #t)))
(nvim_create_autocmd
  (vector "BufLeave" "WinLeave" "TabLeave")
  (hash "group" group
        "callback" (lambda (_args)
                     (define a (unbox *active*))
                     (when a ((hash-ref a "cancel"))))))
(nvim_create_autocmd
  "VimResized"
  (hash "group" group
        "callback" (lambda (_args)
                     (define a (unbox *active*))
                     (when a ((hash-ref a "draw"))))))
