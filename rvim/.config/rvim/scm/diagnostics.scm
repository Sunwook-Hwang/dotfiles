;; 1:1 Steel port of: nvim/.config/nvim/lua/diagnostics.lua
;; Equivalence:
;; - Exact keymaps: <leader>ld, <leader>lD, <leader>sd, [d, ]d, <leader>lt.
;; - Preserves `buffer_policy.guard` on buffer-scoped actions and `state-call 'location-picker`.

(require "rvim/diagnostic")
(require "buffer_policy")
(require "state")


(map-key "n" "<leader>ld" (guard diagnostic-open-float) "Line diagnostics")

(map-key "n" "<leader>lD"
         (guard (lambda ()
                  (state-call 'location-picker
                              "Buffer diagnostics"
                              (diagnostic/toqflist (diagnostic/get 0)))))
         "Select buffer diagnostic")

(map-key "n" "<leader>sd"
         (lambda ()
           (state-call 'location-picker
                       "Diagnostics"
                       (diagnostic/toqflist (diagnostic/get))))
         "Select diagnostic")

(map-key "n" "[d"
         (guard (lambda () (diagnostic-jump (hash "count" -1))))
         "Previous diagnostic")

(map-key "n" "]d"
         (guard (lambda () (diagnostic-jump (hash "count" 1))))
         "Next diagnostic")

(map-key "n" "<leader>lt"
         (lambda () (diagnostic/enable (not (diagnostic/is-enabled?))))
         "Toggle diagnostics")
