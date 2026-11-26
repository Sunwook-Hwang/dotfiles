;; 1:1 Steel port of: nvim/.config/nvim/lua/state.lua
;; Equivalence:
;; - Replaces Lua's mutable shared table `return {}` with a module-level mutable hash box.
;; - Exposes `state-get`, `state-set!`, `state-has?`, and `state-update!` for cross-module hooks.

(provide state-get state-set! state-has? state-update! state-call)

(define *state* (box (hash)))

(define (state-get key (default #f))
  (define m (unbox *state*))
  (if (hash-contains? m key)
      (hash-ref m key)
      default))

(define (state-set! key val)
  (set-box! *state* (hash-insert (unbox *state*) key val))
  val)

(define (state-has? key)
  (hash-contains? (unbox *state*) key))

(define (state-update! key proc (default #f))
  (define cur (or (state-get key) default))
  (state-set! key (proc cur)))

(define (state-call key . args)
  (define fn (state-get key))
  (when (function? fn)
    (apply fn args)))
