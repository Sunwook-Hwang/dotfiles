;; 1:1 Steel port of: nvim/.config/nvim/lua/peerpad/config.lua
;; Equivalence:
;; - Wraps `peerpad-start` with `buffer_policy` + `modifiable` guard and `g:flash_share_max_peers`
;;   clamp (2..64), then calls `peerpad-setup!` with `keymaps = #t` and `g:flash_share_discovery`.

(require "rvim/opt")
(require "buffer_policy")
(require "peerpad/init")
(require "state")

(define *orig-start* peerpad-start)

(peerpad-set-start!
  (lambda (args)
    (unless (and (allows? 0) (bo-get 0 "modifiable"))
      (error! "Share a normal, editable source buffer"))
    (define raw (g-get "flash_share_max_peers"))
    (define n (or (and (number? raw) raw) (and (string? raw) (string->number raw)) 8))
    (peerpad-set-max-peers! (max 2 (min n 64)))
    (*orig-start* args)))

(peerpad-setup!
  (hash "keymaps" #t
        "discovery" (not (equal? (g-get "flash_share_discovery") #f))))
