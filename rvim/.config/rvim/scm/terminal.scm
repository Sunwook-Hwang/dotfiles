;; 1:1 Steel port of: nvim/.config/nvim/lua/terminal.lua
;; Equivalence:
;; - `<C-t>` toggles persistent bottom split shell; `<leader>TT` restarts in editor `:pwd`.
;; - `<C-\>\` and `<C-\><C-\>` toggle fullscreen tab zoom in n/i/t/x modes.
;; - Keeps exited PTY buffer cleanup deferred to `on_exit` callback.

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/fn")
(require "rvim/cmd")
(require "rvim/schedule")
(require "state")

(define *terminal* (box #f))
(define *terminal-zoom* (box #f))

(define (restore-terminal-zoom!)
  (define zoom (unbox *terminal-zoom*))
  (when zoom
    (set-box! *terminal-zoom* #f)
    (define focus (hash-ref zoom "focus"))
    (define source (hash-ref zoom "source"))
    (define zwin (hash-ref zoom "win"))
    (define target (if (nvim_win_is_valid focus) focus source))
    (when (nvim_win_is_valid target)
      (nvim_set_current_win target)
      (when (nvim_win_is_valid zwin)
        (nvim_win_close zwin #t)))))

(define (terminal-running? buf)
  (define job (bo-get buf "channel"))
  (if (or (not (number? job)) (<= job 0))
      #f
      (with-handler
        (lambda (_err) #f)
        (define status (fn-call "jobwait" (vector job) 0))
        (= (vector-ref status 0) -1))))

(define (toggle-terminal (restart #f))
  (restore-terminal-zoom!)
  (when restart
    (state-call 'focus-editor))
  (define cwd (fn-call "getcwd"))
  (define reuse-win #f)
  (define cur-term (unbox *terminal*))
  (when (and cur-term
             (nvim_buf_is_valid cur-term)
             (equal? (bo-get cur-term "buftype") "terminal")
             (or restart (not (terminal-running? cur-term))))
    (define win (fn-call "bufwinid" cur-term))
    (when (not (= win -1))
      (define placeholder (nvim_create_buf #f #f))
      (bo-set placeholder "bufhidden" "hide")
      (nvim_win_set_buf win placeholder)
      (set! reuse-win win))
    (define old cur-term)
    (set-box! *terminal* #f)
    (if (terminal-running? old)
        (fn-call "jobstop" (bo-get old "channel"))
        (nvim_buf_delete old (hash "force" #t))))
  (define active (unbox *terminal*))
  (if (and active (nvim_buf_is_valid active))
      (let ((win (fn-call "bufwinid" active)))
        (if (not (= win -1))
            (begin
              (cmd "stopinsert")
              (nvim_win_call win (lambda () (cmd (if (> (fn-call "winnr" "$") 1) "hide" "enew")))))
            (begin
              (cmd (string-append "botright sbuffer " (number->string active)))
              (cmd "startinsert"))))
      (begin
        (if reuse-win
            (nvim_set_current_win reuse-win)
            (cmd "botright new"))
        (define buf (nvim_get_current_buf))
        (set-box! *terminal* buf)
        (bo-set buf "bufhidden" "hide")
        (bo-set buf "buflisted" #f)
        (fn-call "jobstart"
                 (opt-get "shell")
                 (hash "term" #t
                       "cwd" cwd
                       "on_exit"
                       (lambda _args
                         (schedule
                           (lambda ()
                             (when (and (not (equal? (unbox *terminal*) buf))
                                        (nvim_buf_is_valid buf))
                               (nvim_buf_delete buf (hash "force" #t))))))))
        (cmd "startinsert"))))

(define (toggle-terminal-zoom)
  (cmd "stopinsert")
  (define zoom (unbox *terminal-zoom*))
  (if (and zoom (nvim_win_is_valid (hash-ref zoom "win")))
      (restore-terminal-zoom!)
      (let ((focus (nvim_get_current_win))
            (cur (unbox *terminal*)))
        (when (or (not cur)
                  (not (nvim_buf_is_valid cur))
                  (not (terminal-running? cur))
                  (= (fn-call "bufwinid" cur) -1))
          (toggle-terminal #f))
        (define source (fn-call "bufwinid" (unbox *terminal*)))
        (when (not (= source -1))
          (nvim_set_current_win source)
          (cmd "tab split")
          (set-box! *terminal-zoom*
                    (hash "source" source "focus" focus "win" (nvim_get_current_win))))))
  (when (equal? (bo-get 0 "buftype") "terminal")
    (cmd "startinsert")))

(define zoom-key "<Plug>(flash-terminal-zoom)")
(keymap-set "n" zoom-key toggle-terminal-zoom (hash "silent" #t))
(for-each
  (lambda (keys)
    (map-key "n" keys toggle-terminal-zoom "Toggle terminal fullscreen")
    (map-key (vector "i" "t") keys (string-append "<C-\\><C-n>" zoom-key) "Toggle terminal fullscreen")
    (map-key "x" keys (string-append "<Esc>" zoom-key) "Toggle terminal fullscreen"))
  (list "<C-\\>\\" "<C-\\><C-\\>"))

(map-key (vector "n" "t") "<C-t>" (lambda () (toggle-terminal #f)) "Toggle bottom terminal")
(map-key "n" "<leader>TT" (lambda () (toggle-terminal #t)) "Restart terminal in editor directory")
