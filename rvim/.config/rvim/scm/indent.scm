;; 1:1 Steel port of: nvim/.config/nvim/lua/indent.lua
;; Equivalence:
;; - Sets `list` and `listchars` with identical glyphs (`┊ `, `┊   `, `.`, `>`, `<`).
;; - Updates `leadmultispace` on FileType/BufWinEnter/OptionSet/NopackBufferRestricted.

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/fn")
(require "buffer_policy")
(require "state")

(opt-set "list" #t)
(opt-set "listchars" "extends:>,lead: ,leadmultispace:┊   ,precedes:<,tab:┊ ,trail:.")

(define (listchars-with-indent current guide)
  (define entries
    (foldl (lambda (entry result)
             (let* ((parts (split-many entry ":"))
                    (key (trim (car parts))))
               (if (null? (cdr parts))
                   (hash-remove result key)
                   (hash-insert result key (cadr parts)))))
           (hash)
           (split-many current ",")))
  (define updated
    (if guide
        (hash-insert entries "leadmultispace" guide)
        (hash-remove entries "leadmultispace")))
  (string-join
    (map (lambda (key) (string-append key ":" (hash-ref updated key)))
         (vector->list (fn-call "sort" (hash-keys->list updated))))
    ","))

(define (update-indent-guides . _args)
  (define guide
    (and (allows? 0)
         (string-append "┊" (make-string (max 0 (- (fn-call "shiftwidth") 1)) #\space))))
  (opt/set "listchars" (listchars-with-indent (o/get "listchars") guide)
           (hash "scope" "local")))

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
            (vector->list (fn-call "win_findbuf" buf))))))
