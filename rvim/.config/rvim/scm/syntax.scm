;; 1:1 Steel port of: nvim/.config/nvim/lua/syntax.lua
;; Equivalence:
;; - Uses built-in Treesitter when a parser is already bundled; never downloads parsers.
;; - Guards via `buffer_policy.allows?` and wraps `ts-language-add`/`ts-start` in `with-handler`.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/treesitter")
(require "buffer_policy")

(nvim_create_autocmd
  "FileType"
  (hash
    "callback"
    (lambda (args)
      (define buf (hash-ref args "buf"))
      (when (allows? buf)
        (define ft (bo-get buf "filetype"))
        (define lang (ts-get-lang ft))
        (when lang
          (with-handler
            (lambda (_err) #f)
            (when (ts-language-add lang)
              (ts-start buf lang))))))))
