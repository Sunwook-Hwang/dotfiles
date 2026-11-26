;; 1:1 Steel port of: nvim/.config/nvim/lua/theme.lua
;; Equivalence:
;; - Sets default colorscheme `ayu`.
;; - Computes `NopackPickerSelection` contrast highlight identically using RGB channels
;;   and Rec.601 luminance (`(r*299 + g*587 + b*114) / 1000`), +/-48 channel shift when
;;   `PmenuSel` distance < 32.

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/cmd")
(require "state")

(cmd "colorscheme ayu")

(define (channel-r c) (modulo (quotient c #x10000) #x100))
(define (channel-g c) (modulo (quotient c #x100) #x100))
(define (channel-b c) (modulo c #x100))
(define (clamp-byte v) (max 0 (min 255 v)))

(define (picker-selection-highlight)
  (define normal-float (nvim_get_hl 0 (hash "name" "NormalFloat" "link" #f)))
  (define normal (if (hash-try-get normal-float "bg")
                     normal-float
                     (nvim_get_hl 0 (hash "name" "Normal" "link" #f))))
  (define selected (nvim_get_hl 0 (hash "name" "PmenuSel" "link" #f)))
  (define background
    (or (hash-try-get normal "bg")
        (if (equal? (opt-get "background") "dark") #x000000 #xffffff)))
  (define selected-bg (hash-try-get selected "bg"))
  (define red (channel-r background))
  (define green (channel-g background))
  (define blue (channel-b background))
  (define use-selected
    (and selected-bg
         (>= (max (abs (- red (channel-r selected-bg)))
                  (abs (- green (channel-g selected-bg)))
                  (abs (- blue (channel-b selected-bg))))
             32)))
  (if use-selected
      (nvim_set_hl 0 "NopackPickerSelection" selected)
      (let* ((lum (/ (+ (* red 299) (* green 587) (* blue 114)) 1000))
             (offset (if (< lum 128) 48 -48))
             (gr (clamp-byte (+ red offset)))
             (gg (clamp-byte (+ green offset)))
             (gb (clamp-byte (+ blue offset)))
             (gen (+ (* gr #x10000) (* gg #x100) gb))
             (gen-lum (/ (+ (* gr 299) (* gg 587) (* gb 114)) 1000)))
        (nvim_set_hl 0 "NopackPickerSelection"
                     (hash "fg" (if (< gen-lum 128) #xffffff #x000000)
                           "bg" gen
                           "bold" #t)))))

(state-set! 'picker-selection-highlight picker-selection-highlight)
