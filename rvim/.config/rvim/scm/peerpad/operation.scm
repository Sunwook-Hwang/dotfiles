;; 1:1 Steel port of: nvim/.config/nvim/lua/peerpad/operation.lua
;; Equivalence:
;; - Operational Transformation (OT) text operations: positive ints retain, negative ints
;;   delete, strings insert; preserves final newline sentinel and UTF-8 character boundaries.
;; - Exports `op-valid-text!`, `op-splice`, `op-validate!`, `op-apply`, `op-size`,
;;   `op-inverse`, `op-transform`, `op-difference`, `op-position`, and `op-move`.

(require "rvim/string")
(require "state")

(provide op-valid-text!
         op-splice
         op-validate!
         op-apply
         op-size
         op-inverse
         op-transform
         op-difference
         op-position
         op-move)

(define (op-valid-text! text)
  (when (string-contains? text "\x00;")
    (error! "Only valid UTF-8 text without NUL is supported")))

(define (append-part op part)
  (cond
    [(or (equal? part 0) (equal? part "")) op]
    [(null? op) (list part)]
    [else
     (define last-part (car op))
     (cond
       [(and (string? last-part) (string? part))
        (cons (string-append last-part part) (cdr op))]
       [(and (number? last-part) (number? part) (> (* last-part part) 0))
        (cons (+ last-part part) (cdr op))]
       [else (cons part op)])]))

(define (op-splice len start0 removed0 inserted0)
  (define splice-parts
    (if (and (= (+ start0 removed0) len) (> len 0))
        (cond
          [(not (equal? inserted0 ""))
           (if (= removed0 0)
               (values (- len 1) 0 (string-append "\n" (substring inserted0 0 (- (string-length inserted0) 1))))
               (values start0 (- removed0 1) (substring inserted0 0 (- (string-length inserted0) 1))))]
          [(and (> removed0 0) (> start0 0))
           (values (- start0 1) removed0 inserted0)]
          [else (values start0 removed0 inserted0)])
        (values start0 removed0 inserted0)))
  (define start (list-ref splice-parts 0))
  (define removed (list-ref splice-parts 1))
  (define inserted (list-ref splice-parts 2))
  (define acc0 '())
  (define acc1 (append-part acc0 start))
  (define acc2 (append-part acc1 inserted))
  (define acc3 (append-part acc2 (- removed)))
  (define acc4 (append-part acc3 (- len start removed)))
  (reverse acc4))

(define (op-validate! op len)
  (unless (and (list? op) (<= (length op) 10000))
    (error! "Invalid text operation"))
  (define consumed (box 0))
  (define inserted (box 0))
  (for-each
    (lambda (part)
      (if (string? part)
          (begin
            (op-valid-text! part)
            (set-box! inserted (+ (unbox inserted) (string-length part))))
          (begin
            (unless (and (number? part) (not (= part 0)) (= part (floor part)))
              (error! "Invalid byte count"))
            (set-box! consumed (+ (unbox consumed) (abs part))))))
    op)
  (unless (and (= (unbox consumed) len) (<= (unbox inserted) (* 1024 1024)))
    (error! "Invalid operation size"))
  (unless (or (= len 0) (and (not (null? op)) (number? (last op)) (> (last op) 0)))
    (error! "Operation must keep the final newline")))

(define (op-apply text op)
  (op-validate! op (string-length text))
  (define pieces (box '()))
  (define pos (box 0))
  (define sz (box 0))
  (for-each
    (lambda (part)
      (if (string? part)
          (begin
            (set-box! pieces (cons part (unbox pieces)))
            (set-box! sz (+ (unbox sz) (string-length part))))
          (begin
            (when (> part 0)
              (set-box! pieces (cons (substring text (unbox pos) (+ (unbox pos) part)) (unbox pieces)))
              (set-box! sz (+ (unbox sz) part)))
            (set-box! pos (+ (unbox pos) (abs part)))))
      (when (> (unbox sz) (* 1024 1024))
        (error! "Shared document exceeds 1 MiB")))
    op)
  (apply string-append (reverse (unbox pieces))))

(define (op-size op)
  (foldl (lambda (part acc) (+ acc (if (string? part) (string-length part) 8))) 0 op))

(define (op-inverse text op)
  (let loop ([xs op] [pos 0] [acc '()])
    (if (null? xs)
        (reverse acc)
        (let ([part (car xs)])
          (cond
            [(string? part) (loop (cdr xs) pos (append-part acc (- (string-length part))))]
            [(> part 0) (loop (cdr xs) (+ pos part) (append-part acc part))]
            [else
             (define del-len (- part))
             (loop (cdr xs) (+ pos del-len) (append-part acc (substring text pos (+ pos del-len))))])))))

(define (op-transform left right)
  (let loop ([ls left] [rs right] [x (and (not (null? left)) (car left))] [y (and (not (null? right)) (car right))]
             [a '()] [b '()])
    (cond
      [(and (not x) (not y)) (values (reverse a) (reverse b))]
      [(string? x)
       (define nls (cdr ls))
       (loop nls rs (and (not (null? nls)) (car nls)) y (append-part a x) (append-part b (string-length x)))]
      [(string? y)
       (define nrs (cdr rs))
       (loop ls nrs x (and (not (null? nrs)) (car nrs)) (append-part a (string-length y)) (append-part b y))]
      [else
       (unless (and x y) (error! "Operation lengths differ"))
       (define len (min (abs x) (abs y)))
       (define na
         (cond [(and (> x 0) (> y 0)) (append-part a len)]
               [(and (< x 0) (> y 0)) (append-part a (- len))]
               [else a]))
       (define nb
         (cond [(and (> x 0) (> y 0)) (append-part b len)]
               [(and (< y 0) (> x 0)) (append-part b (- len))]
               [else b]))
       (define nx (+ x (if (> x 0) (- len) len)))
       (define ny (+ y (if (> y 0) (- len) len)))
       (define left-state
         (if (= nx 0) (let ([t (cdr ls)]) (values t (and (not (null? t)) (car t)))) (values ls nx)))
       (define nls (list-ref left-state 0))
       (define fx (list-ref left-state 1))
       (define right-state
         (if (= ny 0) (let ([t (cdr rs)]) (values t (and (not (null? t)) (car t)))) (values rs ny)))
       (define nrs (list-ref right-state 0))
       (define fy (list-ref right-state 1))
       (loop nls nrs fx fy na nb)])))

(define (op-difference before after)
  (define blen (string-length before))
  (define alen (string-length after))
  (define min-len (min blen alen))
  (define first
    (let loop ([i 0])
      (if (and (< i min-len) (equal? (substring before i (+ i 1)) (substring after i (+ i 1))))
          (loop (+ i 1))
          i)))
  (define changed-end
    (let loop ([oe blen] [ne alen])
      (if (and (> oe first) (> ne first)
               (equal? (substring before (- oe 1) oe) (substring after (- ne 1) ne)))
          (loop (- oe 1) (- ne 1))
          (values oe ne))))
  (define old-end (list-ref changed-end 0))
  (define new-end (list-ref changed-end 1))
  (values first (- old-end first) (substring after first new-end)))

(define (op-position text offset)
  (define prefix (substring text 0 (min offset (string-length text))))
  (define row (vector-ref (string/gsub prefix "\n" "\n") 1))
  (define col (string-length (or (string/match prefix "[^\n]*$") "")))
  (values row col))

(define (op-move offset op)
  (let loop ([xs op] [in-pos 0] [out-pos 0])
    (if (null? xs)
        out-pos
        (let ([part (car xs)])
          (cond
            [(string? part) (loop (cdr xs) in-pos (+ out-pos (string-length part)))]
            [(> part 0)
             (if (< offset (+ in-pos part))
                 (+ out-pos (- offset in-pos))
                 (loop (cdr xs) (+ in-pos part) (+ out-pos part)))]
            [else
             (if (< offset (+ in-pos (- part)))
                 out-pos
                 (loop (cdr xs) (+ in-pos (- part)) out-pos))])))))
