;; 1:1 Steel port of: nvim/.config/nvim/lua/lsp/servers.lua
;; Equivalence:
;; - Adds `.v`/`.vh` (verilog) and `.sv`/`.svh` (systemverilog) filetype mappings.
;; - Declares the 21 language server definitions (clangd, mlir-lsp-server, starpls, buf,
;;   bash-language-server, neocmakelsp/cmake-language-server, yaml, texlab, rust-analyzer,
;;   verible-verilog-ls, pyright/ty, lua-language-server, typescript, html, css, tailwind,
;;   svelte, graphql, emmet, prisma, eslint).

(require "rvim/filetype")
(require "state")

(provide *lsp-servers*)

(filetype-add! (hash "extension" (hash "v" "verilog" "vh" "verilog" "sv" "systemverilog" "svh" "systemverilog")))

(define *tsserver* (or (state-call 'resolve-tool "tsserver") ""))

(define *lsp-servers*
  (list
    (hash "cmd" '("clangd") "ft" '("c" "cpp" "objc" "objcpp" "cuda"))
    (hash "cmd" '("mlir-lsp-server") "ft" '("mlir"))
    (hash "cmd" '("starpls" "server") "ft" '("bzl"))
    (hash "cmd" '("buf" "lsp" "serve") "ft" '("proto"))
    (hash "cmd" '("bash-language-server" "start") "ft" '("sh"))
    (hash "alternatives" '(("neocmakelsp" "stdio") ("cmake-language-server")) "ft" '("cmake"))
    (hash "cmd" '("yaml-language-server" "--stdio") "ft" '("yaml"))
    (hash "cmd" '("texlab") "ft" '("tex" "plaintex"))
    (hash "cmd" '("rust-analyzer") "ft" '("rust"))
    (hash "cmd" '("verible-verilog-ls") "ft" '("verilog" "systemverilog"))
    (hash "alternatives" '(("pyright-langserver" "--stdio") ("ty" "server")) "ft" '("python"))
    (hash "cmd" '("lua-language-server")
          "ft" '("lua")
          "settings" (hash "Lua" (hash "diagnostics" (hash "globals" '("vim"))
                                       "completion" (hash "callSnippet" "Replace"))))
    (hash "cmd" '("typescript-language-server" "--stdio")
          "init_options" (if (equal? *tsserver* "") #f (hash "tsserver" (hash "fallbackPath" *tsserver*)))
          "ft" '("javascript" "javascriptreact" "typescript" "typescriptreact"))
    (hash "cmd" '("vscode-html-language-server" "--stdio") "ft" '("html"))
    (hash "cmd" '("vscode-css-language-server" "--stdio") "ft" '("css" "scss" "less"))
    (hash "cmd" '("tailwindcss-language-server" "--stdio")
          "markers" '("tailwind.config.js" "tailwind.config.cjs" "tailwind.config.mjs" "tailwind.config.ts")
          "dependency" "tailwindcss"
          "ft" '("html" "css" "javascriptreact" "typescriptreact" "svelte"))
    (hash "cmd" '("svelteserver" "--stdio") "ft" '("svelte"))
    (hash "cmd" '("graphql-lsp" "server" "-m" "stream") "ft" '("graphql"))
    (hash "cmd" '("emmet-ls" "--stdio")
          "ft" '("html" "css" "javascriptreact" "typescriptreact")
          "markers" '(".emmet.json" "emmet.json"))
    (hash "cmd" '("prisma-language-server" "--stdio") "ft" '("prisma"))
    (hash "cmd" '("vscode-eslint-language-server" "--stdio")
          "markers" '("eslint.config.js" "eslint.config.mjs" "eslint.config.cjs" "eslint.config.ts"
                      ".eslintrc" ".eslintrc.json" ".eslintrc.js" ".eslintrc.cjs" ".eslintrc.yml" ".eslintrc.yaml")
          "dependency" "eslint"
          "ft" '("javascript" "javascriptreact" "typescript" "typescriptreact"))))
