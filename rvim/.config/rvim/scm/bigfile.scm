;; 1:1 Steel port of: nvim/.config/nvim/lua/bigfile.lua
;; Equivalence:
;; - Identical thresholds: > 2 MiB, > 50,000 lines, or > 10,000 bytes in a single line.
;; - Merges `on_lines` ranges outside textlock via `schedule`, scans in 512-line batches.
;; - Saves and restores `syntax`, `indentexpr`, `autocomplete` and per-window
;;   `foldmethod`, `cursorcolumn`, `cursorline` on `BufReadPre` / `BufWipeout`.

(require-builtin rvim/api)
(require "rvim/opt")
(require "rvim/fn")
(require-builtin rvim/uv)
(require "rvim/treesitter")
(require "rvim/schedule")
(require "rvim/string")
(require "buffer_policy")
(require "state")

(define MAX_BYTES (* 2 1024 1024))
(define MAX_LINES 50000)
(define MAX_LINE_BYTES 10000)
(define BATCH_SIZE 512)

(define *watched-buffers* (box (hash)))
(define *protected-options* (box (hash)))

(define (protect-large-file! buf)
  (when (nvim_buf_is_loaded buf)
    (define saved (or (hash-try-get (unbox *protected-options*) buf)
                      (let ((entry (hash "syntax" (bo-get buf "syntax")
                                         "indentexpr" (bo-get buf "indentexpr")
                                         "autocomplete" (bo-get buf "autocomplete")
                                         "windows" (box (hash)))))
                        (set-box! *protected-options*
                                  (hash-insert (unbox *protected-options*) buf entry))
                        entry)))
    (restrict! buf)
    (unless (equal? (bo-get buf "syntax") "OFF")
      (bo-set buf "syntax" "OFF"))
    (bo-set buf "indentexpr" "")
    (bo-set buf "autocomplete" #f)
    (define win-map (hash-ref saved "windows"))
    (for-each
      (lambda (win)
        (unless (hash-try-get (unbox win-map) win)
          (set-box! win-map
                    (hash-insert (unbox win-map)
                                 win
                                 (hash "foldmethod" (wo-get win "foldmethod")
                                       "cursorcolumn" (wo-get win "cursorcolumn")
                                       "cursorline" (wo-get win "cursorline")))))
        (wo-local-set win "foldmethod" "manual")
        (wo-local-set win "cursorcolumn" #f)
        (wo-local-set win "cursorline" #f))
      (vector->list (fn-call "win_findbuf" buf)))))

(nvim_create_autocmd
  "User"
  (hash "pattern" "NopackBufferRestricted"
        "callback"
        (lambda (args)
          (define buf (hash-ref (hash-ref args "data") "buf"))
          (when (nvim_buf_is_loaded buf)
            (with-handler (lambda (_err) #f) (ts-stop buf))))))

(define (has-overlong-line? buf first last)
  (buf/has-overlong-line? buf first last MAX_LINE_BYTES))

(define (check-large-file! buf first last)
  (when (and (not (b-get buf "nopack_large_file"))
             (nvim_buf_is_loaded buf))
    (define count (nvim_buf_line_count buf))
    (define large
      (or (> count MAX_LINES)
          (> (nvim_buf_get_offset buf count) MAX_BYTES)
          (let ((f (max 0 (min first count)))
                (l (max 0 (min last count))))
            (has-overlong-line? buf f l))))
    (when large
      (protect-large-file! buf))))

(define (queue-large-file-check! buf first last added)
  (define st-box (hash-try-get (unbox *watched-buffers*) buf))
  (when (and st-box (not (b-get buf "nopack_large_file")))
    (define st (unbox st-box))
    (define prev-first (hash-try-get st "first"))
    (define prev-last (hash-try-get st "last"))
    (define next-first (if prev-first (min prev-first first) first))
    (define shifted (if prev-last (+ prev-last (max 0 (or added 0))) last))
    (define next-last (max shifted last))
    (define was-pending (hash-ref st "pending"))
    (define generation (hash-ref st "generation"))
    (set-box! st-box (hash "first" next-first "last" next-last "pending" #t "generation" generation))
    (unless was-pending
      (schedule
        (lambda ()
          (define current (hash-try-get (unbox *watched-buffers*) buf))
          (when (and current (equal? (hash-ref (unbox current) "generation") generation))
            (define cur (unbox current))
            (define start (hash-ref cur "first"))
            (define finish (hash-ref cur "last"))
            (set-box! current (hash "first" #f "last" #f "pending" #f "generation" generation))
            (when (nvim_buf_is_loaded buf)
              (check-large-file! buf start finish))))))))

(nvim_create_autocmd
  "BufReadPre"
  (hash "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (define saved (hash-try-get (unbox *protected-options*) buf))
          (when saved
            (for-each (lambda (name) (bo-set buf name (hash-ref saved name)))
                      (list "syntax" "indentexpr" "autocomplete"))
            (define win-map (unbox (hash-ref saved "windows")))
            (for-each
              (lambda (win)
                (when (and (nvim_win_is_valid win) (= (nvim_win_get_buf win) buf))
                  (define opts (hash-ref win-map win))
                  (for-each (lambda (name) (wo-local-set win name (hash-ref opts name)))
                            (hash-keys->list opts))))
              (hash-keys->list win-map))
            (set-box! *protected-options* (hash-remove (unbox *protected-options*) buf)))
          (b-set buf "nopack_large_file" #f)
          (define st (uv-fs-stat (nvim_buf_get_name buf)))
          (when (and (hash? st) (> (hash-ref st "size") MAX_BYTES))
            (restrict! buf)))))

(nvim_create_autocmd
  (vector "BufReadPost" "BufNewFile" "FileType" "BufWinEnter")
  (hash "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (when (is-source? buf)
            (if (b-get buf "nopack_large_file")
                (protect-large-file! buf)
                (unless (hash-try-get (unbox *watched-buffers*) buf)
                  (define st-box (box (hash "first" #f "last" #f "pending" #f "generation" (next-generation!))))
                  (set-box! *watched-buffers* (hash-insert (unbox *watched-buffers*) buf st-box))
                  (define attached
                    (nvim_buf_attach
                      buf
                      #f
                      (hash
                        "on_lines"
                        (lambda (_ev changed-buf _tick first old-last new-last _old-bytes)
                          (queue-large-file-check! changed-buf first new-last (- new-last old-last)))
                        "on_reload"
                        (lambda (_ev reloaded-buf)
                          (queue-large-file-check! reloaded-buf 0 1000000000 0))
                        "on_detach"
                        (lambda (_ev detached-buf)
                          (set-box! *watched-buffers*
                                    (hash-remove (unbox *watched-buffers*) detached-buf))))))
                  (if attached
                      (check-large-file! buf 0 1000000000)
                      (set-box! *watched-buffers*
                                (hash-remove (unbox *watched-buffers*) buf)))))))))

(nvim_create_autocmd
  "BufWipeout"
  (hash "callback"
        (lambda (args)
          (define buf (hash-ref args "buf"))
          (set-box! *protected-options* (hash-remove (unbox *protected-options*) buf)))))
