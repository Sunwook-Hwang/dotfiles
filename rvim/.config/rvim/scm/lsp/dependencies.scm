;; 1:1 Steel port of: nvim/.config/nvim/lua/lsp/dependencies.lua
;; Equivalence:
;; - Coalesces `textDocument/didChange` notifications for `ty` and requests pull
;;   `textDocument/diagnostic` for dependent visible buffers; hidden buffers catch up
;;   on `BufWinEnter` / `TabEnter`.

(require "rvim/api")
(require "rvim/lsp")
(require "rvim/schedule")
(require "buffer_policy")

(define *states* (box (hash)))

(define (refresh-buf! client st buf)
  (define seen (unbox (hash-ref st "seen")))
  (define ver (unbox (hash-ref st "version")))
  (unless (or (equal? (hash-try-get seen buf) ver)
              (not (hash-try-get (hash-ref client "attached_buffers") buf))
              (not (allows? buf))
              (not ((hash-ref client "supports_method") client "textDocument/diagnostic" buf)))
    (set-box! (hash-ref st "seen") (hash-insert seen buf ver))
    ((hash-ref client "request")
     client "textDocument/diagnostic"
     (hash "identifier" "ty" "textDocument" (hash "uri" (lsp-uri-from-bufnr buf)))
     #f buf)))

(define (refresh-visible! client st)
  (for-each (lambda (w) (refresh-buf! client st (nvim_win_get_buf w)))
            (nvim_tabpage_list_wins 0)))

(define *group* (nvim_create_augroup "flash-lsp-dependencies" (hash "clear" #t)))

(nvim_create_autocmd
  "LspNotify"
  (hash "group" *group*
        "callback"
        (lambda (args)
          (define data (hash-ref args "data"))
          (when (equal? (hash-ref data "method") "textDocument/didChange")
            (define client (lsp-get-client-by-id (hash-ref data "client_id")))
            (when (and client (equal? (hash-ref client "name") "ty"))
              (define cid (hash-ref client "id"))
              (define st
                (or (hash-try-get (unbox *states*) cid)
                    (let ([fresh (hash "version" (box 0) "seen" (box (hash)) "scheduled" (box #f))])
                      (set-box! *states* (hash-insert (unbox *states*) cid fresh))
                      fresh)))
              (define ver (+ (unbox (hash-ref st "version")) 1))
              (set-box! (hash-ref st "version") ver)
              (set-box! (hash-ref st "seen") (hash-insert (unbox (hash-ref st "seen")) (hash-ref args "buf") ver))
              (unless (unbox (hash-ref st "scheduled"))
                (set-box! (hash-ref st "scheduled") #t)
                (schedule
                  (lambda ()
                    (set-box! (hash-ref st "scheduled") #f)
                    (when (and (equal? (hash-try-get (unbox *states*) cid) st)
                               (not ((hash-ref client "is_stopped") client)))
                      (refresh-visible! client st))))))))))

(nvim_create_autocmd
  "BufWinEnter"
  (hash "group" *group*
        "callback" (lambda (args)
                     (define buf (hash-ref args "buf"))
                     (for-each
                       (lambda (client)
                         (define st (hash-try-get (unbox *states*) (hash-ref client "id")))
                         (when st (refresh-buf! client st buf)))
                       (lsp-get-clients (hash "bufnr" buf "name" "ty"))))))

(nvim_create_autocmd
  "TabEnter"
  (hash "group" *group*
        "callback" (lambda (_args)
                     (for-each
                       (lambda (id)
                         (define client (lsp-get-client-by-id id))
                         (when (and client (not ((hash-ref client "is_stopped") client)))
                           (refresh-visible! client (hash-ref (unbox *states*) id))))
                       (hash-keys->list (unbox *states*))))))

(nvim_create_autocmd
  "LspDetach"
  (hash "group" *group*
        "callback" (lambda (args)
                     (define id (hash-ref (hash-ref args "data") "client_id"))
                     (define buf (hash-ref args "buf"))
                     (define st (hash-try-get (unbox *states*) id))
                     (when st
                       (set-box! (hash-ref st "seen") (hash-remove (unbox (hash-ref st "seen")) buf))
                       (define client (lsp-get-client-by-id id))
                       (define attached (if client (hash-keys->list (hash-ref client "attached_buffers")) '()))
                       (when (null? (filter (lambda (b) (not (= b buf))) attached))
                         (set-box! *states* (hash-remove (unbox *states*) id)))))))
