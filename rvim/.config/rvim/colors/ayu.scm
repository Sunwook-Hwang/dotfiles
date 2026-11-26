;; Modified for FLASH: native entry point for exported Ayu definitions.
;; Source and Apache-2.0 license: see lua/themes/README.md.
;; 1:1 Steel port of nvim/.config/nvim/colors/ayu.lua
(require "rvim/opt")
(require "theme_loader")
(require "state")
(define style (or (g-get "ayucolor") "dark"))
(define snapshot (if (equal? style "dark") "ayu" (string-append "ayu-" style)))
(apply-theme (hash "dark" snapshot "light" snapshot))
