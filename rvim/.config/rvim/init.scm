;; ============================================================================
;;                   ________    ___   _____ __  __
;;                  / ____/ /   /   | / ___// / / /
;;                 / /_  / /   / /| | \__ \/ /_/ /
;;                / __/ / /___/ ___ |___/ / __  /
;;               /_/   /_____/_/  |_/____/_/ /_/
;;
;;                NO-PACK / SPEED MODE (Steel / rvim)
;;                Native rvim. Zero third-party plugins.
;; ============================================================================
;; 1:1 Steel port of: nvim/.config/nvim/init.lua
;; Equivalence:
;; - Preserves exact initialization order of P0 and P1 modules.
;; - Resolves config root and prepends to runtimepath before loading modules.
;; - P2/P3 modules are commented placeholders for the follow-up PRs.

(require "rvim/fn")
(require "rvim/opt")
(require "rvim/fs")
(require "rvim/uv")

(when (= (fn-call "has" "nvim-0.12") 0)
  (error! "This nopack config requires Neovim/rvim 0.12 or newer"))

(require "state")

(define config-root
  (or (fs-dirname (uv-fs-realpath (or (env-get "RVIM_INIT_FILE")
                                      (string-append (fn-call "stdpath" "config") "/init.scm"))))
      (fn-call "stdpath" "config")))

(opt-prepend "runtimepath" config-root)
(state-set! 'config-root config-root)

;; P0: core policy, options, large-file guards, keymaps, theme, indent, navigation, syntax, diagnostics
(require "options")
(require "bigfile")
(require "keymaps")
(require "theme")
(require "statusline")
(require "indent")
;; (require "explorer")       ;; P2
;; (require "completion")     ;; P3
(require "navigation")
(require "buffers")
(require "project")
;; (require "jobs")           ;; P2
;; (require "pickers")        ;; P2
;; (require "search")         ;; P2
(require "editing")
(require "terminal")
(require "session")
(require "dashboard")
;; (require "git")            ;; P2
;; (require "project_watch")  ;; P3
;; (require "format")         ;; P2
;; (require "tags")           ;; P2
;; (require "lsp")            ;; P3
;; (require "outline")        ;; P2
(require "diagnostics")
(require "syntax")
;; (require "context")        ;; P2
(require "breadcrumbs")
(require "whichkey")
;; (require "peerpad/config") ;; P3
