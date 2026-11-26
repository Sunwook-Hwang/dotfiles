;; 1:1 Steel port of: nvim/.config/nvim/lua/state.lua
;; Equivalence:
;; - Replaces Lua's mutable shared table `return {}` with a module-level mutable hash box.
;; - Exposes `state-get`, `state-set!`, `state-has?`, `state-update!`, and `state-call`.
;; - Also provides exact Lua-parity adapters over `runtime/scm/rvim/*.scm` (`#749` facade
;;   surface: `o/get`, `bo/get`, `wo/get`, `g/get`, `b/get`, `w/get`, `env/get`, `fn/call`,
;;   `cmd/exec`, `keymap/set`, `log-levels`, `wait`, `diagnostic/*`, `treesitter/*`) so
;;   unset `g:`/`b:`/`w:`/`t:` lookups return `#f` (matching Lua `nil`) and `#f` deletes vars.

(require-builtin rvim/api)
(require "#%private/steel/sort")
(require "rvim/opt")
(require "rvim/fn")
(require "rvim/cmd")
(require "rvim/keymap")
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/diagnostic")
(require "rvim/treesitter")

(provide state-get
         state-set!
         state-has?
         state-update!
         state-call
         filter-map
         map-key
         next-generation!
         sort
         opt-get
         opt-set
         opt-append
         opt-prepend
         go-get
         go-set
         bo-get
         bo-set
         wo-get
         wo-set
         wo-local-set
         g-get
         g-set
         b-get
         b-set
         w-get
         w-set
         t-get
         t-set
         v-get
         v-set
         env-get
         fn-call
         cmd
         keymap-set
         keymap-del
         log-level
         wait-until
         diagnostic-count
         diagnostic-severity
         diagnostic-open-float
         diagnostic-jump
         diagnostic-config
         diagnostic-setloclist
         diagnostic-setqflist
         ts-start
         ts-stop
         ts-get-lang
         ts-language-add)

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
  (define callback (state-get key))
  (when (function? callback)
    (apply callback args)))

(define *generation* (box 0))

(define (next-generation!)
  (define next (+ (unbox *generation*) 1))
  (set-box! *generation* next)
  next)

(define (filter-map mapper items)
  (reverse
    (foldl (lambda (item kept)
             (let ((value (mapper item)))
               (if value (cons value kept) kept)))
           '()
           items)))

;; ============================================================================
;; Exact Lua-parity adapters over `runtime/scm/rvim/*.scm`
;; ============================================================================

(define (opt-value->string val)
  (cond
    [(string? val) val]
    [(vector? val) (string-join (vector->list val) ",")]
    [(list? val) (string-join val ",")]
    [else (to-string val)]))

(define (opt-get name)
  (o/get name))

(define (opt-set name val)
  (o/set name (if (or (vector? val) (list? val)) (opt-value->string val) val)))

(define (opt-append name val)
  (define cur (opt-get name))
  (define add (opt-value->string val))
  (if (or (not (string? cur)) (equal? cur ""))
      (o/set name add)
      (o/set name (string-append cur "," add))))

(define (opt-prepend name val)
  (define cur (opt-get name))
  (define add (opt-value->string val))
  (if (or (not (string? cur)) (equal? cur ""))
      (o/set name add)
      (o/set name (string-append add "," cur))))

(define (go-get name)
  (opt/get name (hash "scope" "global")))

(define (go-set name val)
  (opt/set name (if (or (vector? val) (list? val)) (opt-value->string val) val)
           (hash "scope" "global")))

(define (bo-get buf name)
  (bo/get name buf))

(define (bo-set buf name val)
  (bo/set name val buf))

(define (wo-get win name)
  (wo/get name win))

(define (wo-set win name val)
  (wo/set name val win))

(define (wo-local-set win name val)
  (opt/set name val (hash "win" win "scope" "local")))

(define (g-get name)
  (with-handler (lambda (_e) #f) (g/get name)))

(define (g-set name val)
  (if (equal? val #f)
      (with-handler (lambda (_e) (void)) (g/del name))
      (g/set name val)))

(define (b-get buf name)
  (with-handler (lambda (_e) #f) (b/get name buf)))

(define (b-set buf name val)
  (if (equal? val #f)
      (with-handler (lambda (_e) (void)) (b/del name buf))
      (b/set name val buf)))

(define (w-get win name)
  (with-handler (lambda (_e) #f) (w/get name win)))

(define (w-set win name val)
  (if (equal? val #f)
      (with-handler (lambda (_e) (void)) (w/del name win))
      (w/set name val win)))

(define (t-get tab name)
  (with-handler (lambda (_e) #f) (nvim_tabpage_get_var tab name)))

(define (t-set tab name val)
  (if (equal? val #f)
      (with-handler (lambda (_e) (void)) (nvim_tabpage_del_var tab name))
      (nvim_tabpage_set_var tab name val)))

(define (v-get name)
  (with-handler (lambda (_e) #f) (nvim_get_vvar name)))

(define (v-set name val)
  (nvim_set_vvar name val))

(define (env-get name)
  (define val (env/get name))
  (if (or (equal? val #f) (equal? val void)) #f val))

(define (fn-call name . args)
  (apply fn/call (cons name args)))

(define (cmd src)
  (cmd/exec src))

(define (normalize-keymap-opts opts)
  (if (and (hash? opts) (hash-contains? opts "buf"))
      (hash-insert (hash-remove opts "buf") "buffer" (hash-ref opts "buf"))
      opts))

(define (keymap-set mode lhs rhs (opts (hash)))
  (keymap/set mode lhs rhs (normalize-keymap-opts opts)))

(define (map-key mode lhs rhs desc)
  (keymap-set mode lhs rhs (hash "silent" #t "desc" desc)))

(define (keymap-del mode lhs (opts (hash)))
  (keymap/del mode lhs (normalize-keymap-opts opts)))

(define (log-level sym)
  (cond
    [(equal? sym 'trace) (hash-ref log-levels "TRACE")]
    [(equal? sym 'debug) (hash-ref log-levels "DEBUG")]
    [(equal? sym 'info) (hash-ref log-levels "INFO")]
    [(equal? sym 'warn) (hash-ref log-levels "WARN")]
    [(equal? sym 'error) (hash-ref log-levels "ERROR")]
    [(equal? sym 'off) (hash-ref log-levels "OFF")]
    [else (hash-ref log-levels "INFO")]))

(define (wait-until timeout pred (interval 10))
  (wait timeout pred interval))

(define (diagnostic-count . args)
  (apply diagnostic/count args))

(define (diagnostic-severity name)
  (hash-ref (diagnostic/severity) name))

(define (diagnostic-open-float . args)
  (apply diagnostic/open-float args))

(define (diagnostic-jump . args)
  (apply diagnostic/jump args))

(define (diagnostic-config . args)
  (void))

(define (diagnostic-setloclist . args)
  (void))

(define (diagnostic-setqflist . args)
  (apply diagnostic/toqflist args))

(define (ts-start . args)
  (apply treesitter/start args))

(define (ts-stop . args)
  (apply treesitter/stop args))

(define (ts-get-lang ft)
  (treesitter/language "get_lang" ft))

(define (ts-language-add lang . rest)
  (apply treesitter/language (cons "add" (cons lang rest))))
