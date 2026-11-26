;; 1:1 Steel port of: nvim/.config/nvim/lua/navigation.lua
;; Equivalence:
;; - <leader>e toggles editable file explorer (calls `explorer` module when ported in P2).
;; - Registers `focus-editor` and `select-buffer` on shared state for tree/buffer pickers.

(require-builtin rvim/api)
(require "rvim/keymap")
(require "rvim/cmd")
(require "buffer_policy")
(require "state")

(keymap-set
  "n"
  "<leader>e"
  (lambda ()
    (define is-explorer? (state-get 'explorer-is-buffer?))
    (define close-explorer (state-get 'explorer-close))
    (define open-explorer (state-get 'explorer-open))
    (when (and (function? is-explorer?) (function? close-explorer) (function? open-explorer))
      (define closed #f)
      (for-each
        (lambda (win)
          (unless closed
            (define buf (nvim_win_get_buf win))
            (when (is-explorer? buf)
              (nvim_win_call win close-explorer)
              (set! closed #t))))
        (nvim_tabpage_list_wins 0))
      (unless closed
        (define file (if (is-source? 0) (nvim_buf_get_name 0) ""))
        (open-explorer (state-call 'project-root) #t file))))
  (hash "silent" #t "nowait" #t "desc" "Toggle editable file explorer"))

(define (focus-editor)
  (unless (is-editor? 0)
    (define found #f)
    (for-each
      (lambda (win)
        (when (and (not found) (is-editor? win))
          (nvim_set_current_win win)
          (set! found #t)))
      (nvim_tabpage_list_wins 0))
    (unless found
      (cmd "botright vnew"))))

(define (select-buffer buf)
  (focus-editor)
  (nvim_set_current_buf buf))

(state-set! 'focus-editor focus-editor)
(state-set! 'select-buffer select-buffer)
