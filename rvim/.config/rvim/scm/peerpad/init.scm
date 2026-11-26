;; 1:1 Steel port of: nvim/.config/nvim/lua/peerpad/init.lua
;; Equivalence:
;; - Registers `:Peerpad`, `:PeerpadJoin`, `:PeerpadStop`, `:PeerpadStatus` commands,
;;   optional `<leader>Ps`/`Pj`/`Pq`/`Pi` keymaps, and `BufReadPost` sidecar discovery
;;   (`.<name>.flash-share`) via `uv-fs-lstat`.

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/fn")
(require "rvim/fs")
(require-builtin rvim/uv)
(require "rvim/notify")
(require "rvim/schedule")
(require "peerpad/buffer")
(require "peerpad/core")
(require "state")

(provide peerpad-config peerpad-set-max-peers! peerpad-start peerpad-set-start! peerpad-setup!)

(define *config* (box (hash "discovery" #t "max_peers" 8 "keymaps" #f)))
(define *registered* (box (hash)))
(define *start-fn* (box (lambda (args) (peerpad-core-start (or args '())))))

(define *shortcuts*
  '(("<leader>Ps" "Peerpad" "Peerpad: start sharing")
    ("<leader>Pj" "PeerpadJoin" "Peerpad: join current file")
    ("<leader>Pq" "PeerpadStop" "Peerpad: disconnect")
    ("<leader>Pi" "PeerpadStatus" "Peerpad: session information")))

(define (peerpad-config)
  (unbox *config*))

(define (peerpad-set-max-peers! n)
  (set-box! *config* (hash-insert (unbox *config*) "max_peers" n))
  (peerpad-core-set-config! (unbox *config*)))

(define (peerpad-start (args '()))
  ((unbox *start-fn*) args))

(define (peerpad-set-start! callback)
  (set-box! *start-fn* callback))

(define (peerpad-setup! (opts (hash)))
  (when (= (fn-call "has" "nvim-0.12") 0)
    (error! "peerpad.nvim requires Neovim 0.12 or newer"))
  (define cfg
    (foldl (lambda (k acc) (hash-insert acc k (hash-ref opts k)))
           (unbox *config*)
           (hash-keys->list opts)))
  (define max-peers (hash-ref cfg "max_peers"))
  (unless (and (number? max-peers) (>= max-peers 2) (<= max-peers 64) (= max-peers (floor max-peers)))
    (error! "max_peers must be an integer between 2 and 64"))
  (set-box! *config* cfg)
  (peerpad-core-set-config! cfg)
  (for-each
    (lambda (pair)
      (define command (car pair))
      (define action-name (cadr pair))
      (define handler (caddr pair))
      (nvim_create_user_command
        command
        (lambda (args)
          (with-handler
            (lambda (err) (notify (to-string err) (log-level 'error)))
            (handler (or (hash-try-get args "fargs") '()))))
        (hash "nargs" "*" "force" #t "desc" (string-append "Peerpad: " action-name))))
    (list (list "Peerpad" "start" (lambda (a) (peerpad-start a)))
          (list "PeerpadJoin" "join" (lambda (a) (peerpad-core-join a)))
          (list "PeerpadStop" "stop" (lambda (a) (peerpad-core-stop a)))
          (list "PeerpadStatus" "status" (lambda (a) (peerpad-core-status a)))))
  (for-each
    (lambda (lhs)
      (when (equal? (fn-call "maparg" lhs "n") (hash-ref (unbox *registered*) lhs))
        (keymap-del "n" lhs)))
    (hash-keys->list (unbox *registered*)))
  (set-box! *registered* (hash))
  (when (hash-ref cfg "keymaps")
    (for-each
      (lambda (spec)
        (define lhs (list-ref spec 0))
        (define command (list-ref spec 1))
        (define desc (list-ref spec 2))
        (when (equal? (fn-call "maparg" lhs "n") "")
          (define rhs (string-append "<Cmd>" command "<CR>"))
          (keymap-set "n" lhs rhs (hash "silent" #t "desc" desc))
          (define mapped-lhs (hash-ref (fn-call "maparg" lhs "n" #f #t) "lhs"))
          (set-box! *registered* (hash-insert (unbox *registered*) mapped-lhs rhs))))
      *shortcuts*))
  (nvim_create_autocmd
    "BufReadPost"
    (hash "group" (nvim_create_augroup "peerpad-discovery" (hash "clear" #t))
          "callback"
          (lambda (args)
            (define buf (hash-ref args "buf"))
            (define path (nvim_buf_get_name buf))
            (when (and (hash-ref (unbox *config*) "discovery")
                       (equal? (bo-get buf "buftype") "")
                       (not (equal? path "")))
              (define sidecar (fs-joinpath (fs-dirname path) (string-append "." (fs-basename path) ".flash-share")))
              (uv-fs-lstat
                sidecar
                (lambda (err st)
                  (schedule
                    (lambda ()
                      (when (and (or (not err) (equal? err (void)))
                                 (hash? st)
                                 (hash-ref (unbox *config*) "discovery")
                                 (= (nvim_get_current_buf) buf)
                                 (equal? (nvim_buf_get_name buf) path)
                                 (peerpad-is-editor? 0))
                        (with-handler
                          (lambda (e) (notify (to-string e) (log-level 'error)))
                          (peerpad-core-discover buf #t))))))))))))
