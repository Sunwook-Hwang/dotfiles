;; 1:1 Steel port of: nvim/.config/nvim/lua/indent.lua
;; Equivalence:
;; - Sets `list` and `listchars` with identical glyphs (`┊ `, `┊   `, `.`, `>`, `<`).
;; - Updates `leadmultispace` on FileType/BufWinEnter/OptionSet/NopackBufferRestricted.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/fn")
(require "buffer_policy")

(opt-set "list" #t)
(opt-set "listchars"
         (hash "tab" "┊ "
               "lead" " "
               "leadmultispace" "┊   "
               "trail" "."
               "extends" ">"
               "precedes" "<"))

(define (repeat-spaces n)
  (if (<= n 0)
      ""
      (apply string-append (map (lambda (_) " ") (range 0 n)))))

(define (update-indent-guides . _args)
  (if (not (allows? 0))
      (opt-local-remove "listchars" "leadmultispace")
      (let ((width (fn-call "shiftwidth")))
        (opt-local-append "listchars"
                          (hash "leadmultispace"
                                (string-append "┊" (repeat-spaces (- width 1))))))))

(define indent-group (nvim_create_augroup "nopack-indent-guides" (hash "clear" #t)))

(nvim_create_autocmd
  (vector "FileType" "BufWinEnter")
  (hash "group" indent-group
        "callback" update-indent-guides))

(nvim_create_autocmd
  "OptionSet"
  (hash "group" indent-group
        "pattern" (vector "shiftwidth" "tabstop" "vartabstop")
        "callback" update-indent-guides))

(nvim_create_autocmd
  "User"
  (hash "group" indent-group
        "pattern" "NopackBufferRestricted"
        "callback"
        (lambda (args)
          (define buf (hash-ref (hash-ref args "data") "buf"))
          (for-each
            (lambda (win)
              (nvim_win_call win update-indent-guides))
            (fn-call "win_findbuf" buf)))))
