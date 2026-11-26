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
(require-builtin rvim/uv)
(require "state")

(when (= (fn-call "has" "nvim-0.12") 0)
  (error! "This nopack config requires Neovim/rvim 0.12 or newer"))

(define config-root
  (or (fs-dirname (uv-fs-realpath (or (env-get "RVIM_INIT_FILE")
                                      (string-append (fn-call "stdpath" "config") "/init.scm"))))
      (fn-call "stdpath" "config")))

(opt-prepend "runtimepath" config-root)
(state-set! 'config-root config-root)

;; P0–P3: complete 1:1 Steel port of FLASH Neovim configuration
(require "options")
(require "bigfile")
(require "keymaps")
(require "theme")
(require "statusline")
(require "indent")
(require "explorer")
(require "completion")
(require "navigation")
(require "buffers")
(require "project")
(require "jobs")
(require "pickers")
(require "search")
(require "editing")
(require "terminal")
(require "session")
(require "dashboard")
(require "git")
(require "project_watch")
(require "format")
(require "tags")
(require "lsp/init")
(require "outline")
(require "diagnostics")
(require "syntax")
(require "context")
(require "breadcrumbs")
(require "whichkey")
(require "peerpad/config")
