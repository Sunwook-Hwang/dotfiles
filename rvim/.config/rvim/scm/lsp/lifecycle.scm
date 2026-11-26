;; 1:1 Steel port of: nvim/.config/nvim/lua/lsp/lifecycle.lua
;; Equivalence:
;; - `lsp-restart-client!`: detaches all buffers, stops old client, starts replacement,
;;   and reattaches eligible buffers.
;; - `<leader>ls` restarts attached clients or re-enables enabled configs for filetype.
;; - Detaches clients on `User NopackBufferRestricted`; detects first-time file creation
;;   on `BufWritePre`/`BufWritePost` to restart `ty` and emit `User NopackFilesCreated`.

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/keymap")
(require-builtin rvim/uv)
(require "rvim/lsp")
(require "rvim/notify")
(require "rvim/schedule")
(require "buffer_policy")
(require "state")

(provide lsp-restart-client!)

(define (lsp-restart-client! client)
  (if ((hash-ref client "is_stopped") client)
      #f
      (let ([bufs (hash-keys->list (hash-ref client "attached_buffers"))]
            [cfg (hash-ref client "config")])
        (for-each (lambda (b) (lsp-buf-detach-client! b (hash-ref client "id"))) bufs)
        ((hash-ref client "stop") client #t)
        (define id (lsp-start! cfg (hash "attach" #f)))
        (when id
          (for-each (lambda (b) (when (allows? b) (lsp-buf-attach-client! b id))) bufs))
        id)))

(keymap-set
  "n" "<leader>ls"
  (guard
    (lambda ()
      (define clients (lsp-get-clients (hash "bufnr" 0)))
      (for-each lsp-restart-client! clients)
      (when (null? clients)
        (define names
          (map (lambda (c) (hash-ref c "name"))
               (lsp-get-configs (hash "enabled" #t "filetype" (bo-get 0 "filetype")))))
        (if (null? names)
            (notify "No enabled LSP for this filetype" (log-level 'warn))
            (lsp-enable! names)))))
  (hash "desc" "Restart current buffer LSP clients"))

(nvim_create_autocmd
  "User"
  (hash "group" (nvim_create_augroup "nopack-lsp-lifecycle" (hash "clear" #t))
        "pattern" "NopackBufferRestricted"
        "callback" (lambda (args)
                     (define buf (hash-ref (hash-ref args "data") "buf"))
                     (for-each (lambda (c) (lsp-buf-detach-client! buf (hash-ref c "id")))
                               (lsp-get-clients (hash "bufnr" buf))))))

;; First-write tracking for :edit of non-existent files.
(define *writes* (box (hash)))
(define *pending-files* (box (hash)))
(define *pending-clients* (box (hash)))
(define *scheduled* (box #f))
(define *new-file-group* (nvim_create_augroup "nopack-new-file" (hash "clear" #t)))

(nvim_create_autocmd
  "BufWritePre"
  (hash "group" *new-file-group*
        "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (set-box! *writes* (hash-remove (unbox *writes*) buf))
          (when (is-source? buf)
            (define match-path (hash-ref args "match"))
            (unless (uv-fs-stat match-path)
              (set-box! *writes*
                        (hash-insert (unbox *writes*) buf
                                     (hash "file" match-path
                                           "clients" (if (equal? (bo-get buf "filetype") "python")
                                                         (lsp-get-clients (hash "bufnr" buf "name" "ty"))
                                                         '())))))))))

(nvim_create_autocmd
  "BufWipeout"
  (hash "group" *new-file-group*
        "callback" (lambda (args) (set-box! *writes* (hash-remove (unbox *writes*) (hash-ref args "buf"))))))

(nvim_create_autocmd
  "BufWritePost"
  (hash "group" *new-file-group*
        "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (define write (hash-try-get (unbox *writes*) buf))
          (set-box! *writes* (hash-remove (unbox *writes*) buf))
          (define file (and write (equal? (hash-ref write "file") (hash-ref args "match"))
                            (uv-fs-realpath (hash-ref write "file"))))
          (when file
            (set-box! *pending-files* (hash-insert (unbox *pending-files*) file #t))
            (for-each
              (lambda (c) (set-box! *pending-clients* (hash-insert (unbox *pending-clients*) (hash-ref c "id") c)))
              (hash-ref write "clients"))
            (unless (unbox *scheduled*)
              (set-box! *scheduled* #t)
              (schedule
                (lambda ()
                  (define files (unbox *pending-files*))
                  (define clients (unbox *pending-clients*))
                  (set-box! *pending-files* (hash))
                  (set-box! *pending-clients* (hash))
                  (set-box! *scheduled* #f)
                  (for-each (lambda (id) (lsp-restart-client! (hash-ref clients id)))
                            (hash-keys->list clients))
                  (nvim_exec_autocmds
                    "User"
                    (hash "pattern" "NopackFilesCreated" "data" (hash "files" files) "modeline" #f)))))))))
