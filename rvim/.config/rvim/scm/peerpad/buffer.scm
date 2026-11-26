;; 1:1 Steel port of: nvim/.config/nvim/lua/peerpad/buffer.lua
;; Equivalence:
;; - Isolated buffer/window predicates for peerpad (`peerpad-is-source?`,
;;   `peerpad-allows?`, `peerpad-is-editor?`, `peerpad-focus-editor!`).

(require "rvim/api")
(require "rvim/opt")
(require "rvim/cmd")

(provide peerpad-is-source? peerpad-allows? peerpad-is-editor? peerpad-focus-editor!)

(define (peerpad-is-source? buf)
  (and (nvim_buf_is_valid buf)
       (equal? (bo-get buf "buftype") "")
       (not (equal? (bo-get buf "filetype") "netrw"))))

(define (peerpad-allows? buf)
  (and (nvim_buf_is_loaded buf) (peerpad-is-source? buf)))

(define (peerpad-is-editor? win0)
  (define win (if (= win0 0) (nvim_get_current_win) win0))
  (and (nvim_win_is_valid win)
       (peerpad-is-source? (nvim_win_get_buf win))
       (equal? (hash-try-get (nvim_win_get_config win) "relative") "")
       (not (wo-get win "previewwindow"))))

(define (peerpad-focus-editor!)
  (unless (peerpad-is-editor? (nvim_get_current_win))
    (let loop ([ws (nvim_tabpage_list_wins 0)])
      (cond
        [(null? ws) (cmd "botright vnew")]
        [(peerpad-is-editor? (car ws)) (nvim_set_current_win (car ws))]
        [else (loop (cdr ws))]))))
