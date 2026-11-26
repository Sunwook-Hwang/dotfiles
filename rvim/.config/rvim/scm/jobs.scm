;; 1:1 Steel port of: nvim/.config/nvim/lua/jobs.lua
;; Equivalence:
;; - Shared async command runner for search, Git, tags, and external formatters.
;; - Keyed cancellation (new request with same key cancels previous unless `atomic`).
;; - Default limits: 5s timeout, 2 MiB stdout cap (`partial` allows truncated results).
;; - Provides `:NopackCancel` user command, `VimLeavePre` cleanup, and `User NopackCancel`.

(require "rvim/api")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/system")
(require "state")

(provide stop-timer! cancel-command! run-command!)

(define *running* (box (hash)))

(define (stop-timer! timer)
  (when (and timer (not ((hash-ref timer "is_closing") timer)))
    ((hash-ref timer "stop") timer)
    ((hash-ref timer "close") timer)))

(define (stop-command-timer! task)
  (stop-timer! (unbox (hash-ref task "timer")))
  (set-box! (hash-ref task "timer") #f))

(define (cancel-command! key)
  (define task (hash-try-get (unbox *running*) key))
  (when (and task (not (hash-try-get task "atomic")))
    (set-box! (hash-ref task "cancelled") #t)
    (stop-command-timer! task)
    (set-box! (hash-ref task "chunks") '())
    (define proc (unbox (hash-ref task "process")))
    (when proc
      ((hash-ref proc "kill") proc 9))
    (set-box! *running* (hash-remove (unbox *running*) key))))

(define (cancel-all-commands!)
  (nvim_exec_autocmds "User" (hash "pattern" "NopackCancel" "modeline" #f))
  (for-each cancel-command! (hash-keys->list (unbox *running*))))

(nvim_create_user_command
  "NopackCancel"
  (lambda (_opts)
    (define picker (state-get 'active-picker))
    (when picker
      ((hash-ref picker "close")))
    (cancel-all-commands!))
  (hash))

(nvim_create_autocmd "VimLeavePre" (hash "callback" (lambda (_args) (cancel-all-commands!))))

(define (run-command! key argv opts callback)
  (cancel-command! key)
  (unless (hash-contains? (unbox *running*) key)
    (define limit (or (hash-try-get opts "max_bytes") (* 2 1024 1024)))
    (define task
      (hash "chunks" (box '())
            "bytes" (box 0)
            "errors" (box "")
            "limited" (box #f)
            "cancelled" (box #f)
            "atomic" (hash-try-get opts "atomic")
            "process" (box #f)
            "timer" (box #f)))
    (set-box! *running* (hash-insert (unbox *running*) key task))
    (with-handler
      (lambda (err)
        (set-box! *running* (hash-remove (unbox *running*) key))
        (unless (hash-try-get opts "quiet")
          (notify (string-append key ": " (to-string err)) (log-level 'warn)))
        (define failed (hash-try-get opts "failed"))
        (when failed (failed)))
      (define proc
        (system-run
          argv
          (hash "cwd" (hash-try-get opts "cwd")
                "stdin" (hash-try-get opts "stdin")
                "stdout"
                (lambda (err data)
                  (when err
                    (set-box! (hash-ref task "errors") (to-string err)))
                  (when (and data
                             (not (unbox (hash-ref task "cancelled")))
                             (not (unbox (hash-ref task "limited"))))
                    (define remaining (- limit (unbox (hash-ref task "bytes"))))
                    (define dlen (string-length data))
                    (define take-len (min dlen remaining))
                    (set-box! (hash-ref task "chunks")
                              (cons (substring data 0 take-len) (unbox (hash-ref task "chunks"))))
                    (set-box! (hash-ref task "bytes") (+ (unbox (hash-ref task "bytes")) take-len))
                    (when (> dlen remaining)
                      (set-box! (hash-ref task "limited") #t)
                      (define p (unbox (hash-ref task "process")))
                      (when p ((hash-ref p "kill") p 9)))))
                "stderr"
                (lambda (err data)
                  (define msg (or data (and err (to-string err)) ""))
                  (define combined (string-append (unbox (hash-ref task "errors")) msg))
                  (set-box! (hash-ref task "errors")
                            (substring combined 0 (min 8192 (string-length combined))))))
          (lambda (result)
            (schedule
              (lambda ()
                (stop-command-timer! task)
                (unless (unbox (hash-ref task "cancelled"))
                  (set-box! *running* (hash-remove (unbox *running*) key))
                  (define limited (unbox (hash-ref task "limited")))
                  (define code (hash-ref result "code"))
                  (define errors (unbox (hash-ref task "errors")))
                  (define failure
                    (cond
                      [(and limited (not (hash-try-get opts "partial")))
                       "time/output limit exceeded; result discarded"]
                      [(and (not limited)
                            (not (= code 0))
                            (not (and (hash-try-get opts "no_match") (= code 1))))
                       (if (equal? errors "")
                           (string-append "command failed (" (number->string code) ")")
                           errors)]
                      [else #f]))
                  (if failure
                      (begin
                        (set-box! (hash-ref task "chunks") '())
                        (unless (hash-try-get opts "quiet")
                          (notify (string-append key ": " failure) (log-level 'warn)))
                        (define failed (hash-try-get opts "failed"))
                        (when failed (failed)))
                      (begin
                        (when limited
                          (notify (string-append key ": limit reached; partial results") (log-level 'warn)))
                        (define output (apply string-append (reverse (unbox (hash-ref task "chunks")))))
                        (set-box! (hash-ref task "chunks") '())
                        (callback output limited)))))))))
      (set-box! (hash-ref task "process") proc)
      (unless (hash-try-get task "atomic")
        (set-box! (hash-ref task "timer")
                  (defer-fn
                    (lambda ()
                      (set-box! (hash-ref task "timer") #f)
                      (when (and (equal? (hash-try-get (unbox *running*) key) task)
                                 (not (unbox (hash-ref task "cancelled"))))
                        (set-box! (hash-ref task "limited") #t)
                        ((hash-ref proc "kill") proc 9)))
                    (or (hash-try-get opts "timeout") 5000)))))))

(state-set! 'running *running*)
(state-set! 'stop-timer stop-timer!)
(state-set! 'cancel-command cancel-command!)
(state-set! 'run-command run-command!)
