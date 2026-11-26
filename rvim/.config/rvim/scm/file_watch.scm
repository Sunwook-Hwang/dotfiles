;; 1:1 Steel port of: nvim/.config/nvim/lua/file_watch.lua
;; Equivalence:
;; - Watches parent directories of loaded source buffers via `uv-new-fs-event` so atomic
;;   saves trigger debounced (100ms) `:checktime <buf>` when `autoread` is enabled.
;; - Exports `file-watch-setup!` to register `BufReadPost`/`BufNewFile`/`BufFilePost`/
;;   `BufWritePost` attach hooks and `BufUnload`/`BufFilePre`/`BufWipeout` detach hooks.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/fs")
(require "rvim/uv")
(require "rvim/schedule")
(require "buffer_policy")

(provide file-watch-setup!)

(define *directories* (box (hash)))
(define *buffer-dirs* (box (hash)))

(define (detach! buf)
  (define dir (hash-try-get (unbox *buffer-dirs*) buf))
  (when dir
    (define watch (hash-try-get (unbox *directories*) dir))
    (set-box! *buffer-dirs* (hash-remove (unbox *buffer-dirs*) buf))
    (when watch
      (set-box! (hash-ref watch "files") (hash-remove (unbox (hash-ref watch "files")) buf))
      (when (null? (hash-keys->list (unbox (hash-ref watch "files"))))
        ((hash-ref (hash-ref watch "handle") "close") (hash-ref watch "handle"))
        (set-box! *directories* (hash-remove (unbox *directories*) dir))))))

(define (attach! buf)
  (define raw (nvim_buf_get_name buf))
  (unless (or (not (is-source? buf))
              (equal? raw "")
              (not (equal? (fn-call "matchstr" raw "^[A-Za-z][A-Za-z0-9+.-]*://") "")))
    (define path (or (uv-fs-realpath raw) raw))
    (define dir (fs-dirname path))
    (define name (fs-basename path))
    (define cur-dir (hash-try-get (unbox *buffer-dirs*) buf))
    (define existing-watch (and cur-dir (hash-try-get (unbox *directories*) cur-dir)))
    (unless (and (equal? cur-dir dir)
                 existing-watch
                 (equal? (hash-try-get (unbox (hash-ref existing-watch "files")) buf) name))
      (detach! buf)
      (define watch
        (or (hash-try-get (unbox *directories*) dir)
            (let ([handle (uv-new-fs-event)])
              (if (not handle)
                  #f
                  (let ([w (hash "handle" handle "files" (box (hash)) "pending" (box (hash)))])
                    (define started
                      ((hash-ref handle "start")
                       handle dir (hash)
                       (lambda (err filename _events)
                         (unless err
                           (for-each
                             (lambda (target)
                               (define bname (hash-ref (unbox (hash-ref w "files")) target))
                               (when (and (or (not filename) (equal? filename bname))
                                          (not (hash-contains? (unbox (hash-ref w "pending")) target)))
                                 (set-box! (hash-ref w "pending")
                                           (hash-insert (unbox (hash-ref w "pending")) target #t))
                                 (defer-fn
                                   (lambda ()
                                     (set-box! (hash-ref w "pending")
                                               (hash-remove (unbox (hash-ref w "pending")) target))
                                     (when (and (equal? (hash-try-get (unbox (hash-ref w "files")) target) bname)
                                                (not (bo-get target "modified")))
                                       (define ar (bo-get target "autoread"))
                                       (when (or ar (and (equal? ar 'unset) (go-get "autoread")))
                                         (cmd (string-append "checktime " (number->string target))))))
                                   100)))
                             (hash-keys->list (unbox (hash-ref w "files"))))))))
                    (if started
                        (begin
                          (set-box! *directories* (hash-insert (unbox *directories*) dir w))
                          w)
                        (begin
                          ((hash-ref handle "close") handle)
                          #f)))))))
      (when watch
        (set-box! *buffer-dirs* (hash-insert (unbox *buffer-dirs*) buf dir))
        (set-box! (hash-ref watch "files") (hash-insert (unbox (hash-ref watch "files")) buf name))))))

(define (file-watch-setup! group)
  (nvim_create_autocmd
    '("BufReadPost" "BufNewFile" "BufFilePost" "BufWritePost")
    (hash "group" group "callback" (lambda (args) (attach! (hash-ref args "buf")))))
  (nvim_create_autocmd
    '("BufUnload" "BufFilePre" "BufWipeout")
    (hash "group" group "callback" (lambda (args) (detach! (hash-ref args "buf"))))))
