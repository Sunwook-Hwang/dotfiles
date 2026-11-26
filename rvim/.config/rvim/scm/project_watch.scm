;; 1:1 Steel port of: nvim/.config/nvim/lua/project_watch.lua
;; Equivalence:
;; - Watches active project roots on screen (recursive on macOS/Windows; breadth-first
;;   up to 4,096 dirs + `.git` on Linux) using `uv-new-fs-event`.
;; - Filters ignored dirs and `.git/*.lock`/`.git/objects/*`, coalesces events with a
;;   150ms debounce, and emits `User NopackExternalChange` with `{files = ...}`.

(require "rvim/api")
(require "rvim/fn")
(require "rvim/fs")
(require "rvim/uv")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "explorer")
(require "state")

(define *recursive* (= (fn-call "has" "linux") 0))
(define *max-directories* 4096)
(define *watches* (box (hash)))
(define *created* (box (hash)))
(define *flush-pending* (box #f))
(define *sync-pending* (box #f))

(define (ignored-name? name)
  (let loop ([xs (or (state-get 'ignored-dirs) '())])
    (cond
      [(null? xs) #f]
      [(lua-match name
                  (string-append "^" (car (lua-gsub (car (lua-gsub (car xs) "[%(%)%.%%%+%-%*%?%[%]%^%$]" "%%%0")) "%%%*" ".*")) "$"))
       #t]
      [else (loop (cdr xs))])))

(define (flush!)
  (set-box! *flush-pending* #f)
  (define files (unbox *created*))
  (set-box! *created* (hash))
  (nvim_exec_autocmds "User" (hash "pattern" "NopackExternalChange" "modeline" #f "data" (hash "files" files))))

(define (start-watch! watch root dir flags)
  (define handle (uv-new-fs-event))
  (if (not handle)
      #f
      (let ([prefix (if (equal? dir root)
                        ""
                        (string-append (substring dir (+ (string-length root) 1) (string-length dir)) "/"))])
        (define started
          ((hash-ref handle "start")
           handle dir flags
           (lambda (err filename events)
             (unless err
               (on-changed! watch root (and filename (string-append prefix filename)) events)))))
        (if (not started)
            (begin ((hash-ref handle "close") handle) #f)
            (begin
              (set-box! (hash-ref watch "handles") (hash-insert (unbox (hash-ref watch "handles")) dir handle))
              (set-box! (hash-ref watch "count") (+ (unbox (hash-ref watch "count")) 1))
              #t)))))

(define (watch-directory! watch root dir)
  (let loop ([queue (list dir)])
    (unless (or (null? queue) (>= (unbox (hash-ref watch "count")) *max-directories*))
      (define cur (car queue))
      (define rest (cdr queue))
      (if (and (not (hash-contains? (unbox (hash-ref watch "handles")) cur))
               (start-watch! watch root cur (hash)))
          (let ([sub-dirs
                 (filter-map
                   (lambda (entry)
                     (define name (car entry))
                     (define kind (cdr entry))
                     (and (equal? kind "directory") (not (ignored-name? name))
                          (string-append cur "/" name)))
                   (uv-fs-scandir cur))])
            (loop (append rest sub-dirs)))
          (loop rest)))))

(define (on-changed! watch root relative events)
  (define ignore? #f)
  (when relative
    (if (starts-with? relative ".git/")
        (let ([git-rel (substring relative 5 (string-length relative))])
          (when (or (ends-with? git-rel ".lock") (starts-with? git-rel "objects/"))
            (set! ignore? #t)))
        (begin
          (for-each (lambda (part) (when (ignored-name? part) (set! ignore? #t)))
                    (split-many relative "/"))
          (when (and (not ignore?) events (hash-try-get events "rename"))
            (define path (string-append root "/" relative))
            (set-box! *created* (hash-insert (unbox *created*) path #t))
            (unless *recursive*
              (define h (hash-try-get (unbox (hash-ref watch "handles")) path))
              (define st (uv-fs-stat path))
              (cond
                [(and h (not st))
                 ((hash-ref h "close") h)
                 (set-box! (hash-ref watch "handles") (hash-remove (unbox (hash-ref watch "handles")) path))
                 (set-box! (hash-ref watch "count") (- (unbox (hash-ref watch "count")) 1))]
                [(and st (equal? (hash-try-get st "type") "directory"))
                 (watch-directory! watch root path)]))))))
  (when (and (not ignore?) (not (unbox *flush-pending*)))
    (set-box! *flush-pending* #t)
    (defer-fn flush! 150)))

(define (watch-root! root tree?)
  (define watch (hash "handles" (box (hash)) "count" (box 0)))
  (set-box! *watches* (hash-insert (unbox *watches*) root watch))
  (cond
    [(not tree?) (start-watch! watch root root (hash))]
    [*recursive* (start-watch! watch root root (hash "recursive" #t))]
    [else
     (watch-directory! watch root root)
     (define git-st (uv-fs-stat (string-append root "/.git")))
     (when (and git-st (equal? (hash-try-get git-st "type") "directory"))
       (start-watch! watch root (string-append root "/.git") (hash)))]))

(define (sync-watches!)
  (set-box! *sync-pending* #f)
  (define wanted (box (hash)))
  (for-each
    (lambda (win)
      (define buf (nvim_win_get_buf win))
      (cond
        [(explorer-is-buffer? buf)
         (define top (explorer-root buf))
         (unless (equal? top "")
           (define root (state-call 'find-git-root top))
           (set-box! wanted (hash-insert (unbox wanted) (or root top) (not (not root)))))]
        [(and (is-source? buf) (not (equal? (nvim_buf_get_name buf) "")))
         (define root (state-call 'find-git-root (fs-dirname (nvim_buf_get_name buf))))
         (when root
           (set-box! wanted (hash-insert (unbox wanted) root #t)))]))
    (nvim_list_wins))
  (for-each
    (lambda (root)
      (unless (hash-contains? (unbox wanted) root)
        (define w (hash-ref (unbox *watches*) root))
        (for-each (lambda (d)
                    (define h (hash-ref (unbox (hash-ref w "handles")) d))
                    ((hash-ref h "close") h))
                  (hash-keys->list (unbox (hash-ref w "handles"))))
        (set-box! *watches* (hash-remove (unbox *watches*) root))))
    (hash-keys->list (unbox *watches*)))
  (for-each
    (lambda (root)
      (unless (hash-contains? (unbox *watches*) root)
        (watch-root! root (hash-ref (unbox wanted) root))))
    (hash-keys->list (unbox wanted))))

(nvim_create_autocmd
  '("BufWinEnter" "WinClosed" "FileType")
  (hash "group" (nvim_create_augroup "nopack-project-watch" (hash "clear" #t))
        "callback" (lambda (_args)
                     (unless (unbox *sync-pending*)
                       (set-box! *sync-pending* #t)
                       (schedule sync-watches!)))))
