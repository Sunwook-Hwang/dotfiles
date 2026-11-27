;; 1:1 Steel port of: nvim/.config/nvim/lua/peerpad/core.lua
;; Equivalence:
;; - Authenticated TCP single-buffer collaboration with line-delimited JSON frames,
;;   OT rebase/undo/redo (`peerpad/operation.scm`), peer cursor extmarks (`LiveSharePeer1..6`),
;;   and NFS-safe exclusive sidecar discovery (`.<name>.flash-share`) with `.git/info/exclude`.
;; - Exports `peerpad-core-set-config!`, `peerpad-core-start`, `peerpad-core-join`,
;;   `peerpad-core-discover`, `peerpad-core-stop`, and `peerpad-core-status`.

(require-builtin rvim/api)
(require-builtin rvim/util)
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/cmd")
(require "rvim/fn")
(require "rvim/fs")
(require-builtin rvim/uv)
(require "rvim/json")
(require-builtin rvim/system)
(require "rvim/notify")
(require "rvim/schedule")
(require "rvim/string")
(require "peerpad/operation")
(require "peerpad/buffer")
(require "state")

(provide peerpad-core-set-config!
         peerpad-core-start
         peerpad-core-join
         peerpad-core-discover
         peerpad-core-stop
         peerpad-core-status)

(define *config* (box (hash "discovery" #t "max_peers" 8 "keymaps" #f)))
(define *server* (box #f))
(define *client* (box #f))
(define *group* (nvim_create_augroup "peerpad-transport" (hash "clear" #t)))
(define *limit* (* 1024 1024))
(define *cursor-ns* (nvim_create_namespace "peerpad-cursors"))

(define (peerpad-core-set-config! cfg)
  (set-box! *config* cfg))

(let loop ([links '("DiagnosticVirtualTextInfo" "DiagnosticVirtualTextHint" "DiagnosticVirtualTextWarn"
                    "DiagnosticVirtualTextOk" "DiagnosticVirtualTextError" "Visual")]
           [i 1])
  (unless (null? links)
    (nvim_set_hl 0 (string-append "LiveSharePeer" (number->string i))
                 (hash "link" (car links) "default" #t))
    (loop (cdr links) (+ i 1))))

(define (pp-notify msg (level #f))
  (notify (string-append "Peerpad: " msg) (or level (log-level 'info))))

(define (close-handle! h)
  (when (and h (not (uv-is-closing h)))
    (uv-close h)))

(define (printable val (len 64))
  (define s (vector-ref (string/gsub (to-string val) "[%c]" "?") 0))
  (substring s 0 (min len (string-length s))))

(define (sidecar-path path)
  (fs-joinpath (fs-dirname path) (string-append "." (fs-basename path) ".flash-share")))

(define (random-sha256 n)
  (fn-call "sha256" (uv-random n)))

;; JSON arrays decode to vectors; the protocol code works on lists, as the Lua tables did.
(define (decode-json text)
  (let convert ([v (json-decode text)])
    (cond
      [(vector? v) (map convert (vector->list v))]
      [(hash? v) (foldl (lambda (k acc) (hash-insert acc k (convert (hash-ref v k)))) (hash) (hash-keys->list v))]
      [else v])))

;; Sync uv calls return luv's `nil, message, name` as a list instead of raising.
(define (checked result)
  (cond
    [(list? result) (error! (cadr result))]
    [(not result) (error! "Filesystem operation failed")]
    [else result]))

(define (disk-content path)
  (define st (uv-fs-stat path))
  (cond
    [(and (hash? st) (> (hash-ref st "size") (* 2 *limit*))) #f]
    [(= (fn-call "filereadable" path) 0) 'missing]
    [else (string-join (vector->list (fn-call "readfile" path "b")) "\n")]))

(define (document-valid! text)
  (unless (and (<= (string-length text) *limit*) (ends-with? text "\n"))
    (error! "Invalid shared document")))

(define (make-channel socket receive disconnected)
  (define input-box (box ""))
  (define closed-box (box #f))
  (define timer-box (box #f))
  (define id-box (box #f))
  (define label-box (box #f))
  (define cursor-box (box #f))
  (define conn-box (box #f))

  (define (settle!)
    (close-handle! (unbox timer-box))
    (set-box! timer-box #f))

  (define (stop! (reason #f))
    (unless (unbox closed-box)
      (set-box! closed-box #t)
      (settle!)
      (close-handle! socket)
      (when disconnected (disconnected reason))))

  (define (deadline! ms reason)
    (settle!)
    (define t (uv-new-timer))
    (set-box! timer-box t)
    (uv-timer-start t ms 0 (lambda () (schedule (lambda () (stop! reason))))))

  (define (send! msg)
    (unless (unbox closed-box)
      (define frame (string-append (json-encode msg) "\n"))
      (if (> (+ (uv-tcp-get-write-queue-size socket) (string-length frame)) (* 4 *limit*))
          (stop! "Connection cannot keep up; local text was retained")
          (with-handler
            (lambda (err) (stop! (error-text err)))
            (checked (uv-tcp-write
              socket frame
              (lambda args
                (define werr (and (not (null? args)) (not (equal? (car args) void)) (car args)))
                (schedule (lambda () (when werr (stop! (to-string werr))))))))))))

  (define (read!)
    (with-handler
      (lambda (err) (stop! (error-text err)))
      (checked (uv-tcp-read-start
        socket
        (lambda args
          (define err (and (not (null? args)) (not (equal? (car args) void)) (car args)))
          (define data (and (>= (length args) 2) (cadr args)))
          (schedule
            (lambda ()
              (unless (unbox closed-box)
                (if (or err (not data))
                    (stop! (or (and err (error-text err)) "Connection closed by peer"))
                    (begin
                      (set-box! input-box (string-append (unbox input-box) data))
                      (let loop ()
                        (unless (unbox closed-box)
                          (define buf-str (unbox input-box))
                          (define match (string/find buf-str "\n" 1 #t))
                          (define nl (and match (- (vector-ref match 0) 1)))
                          (cond
                            [(not nl)
                             (when (> (string/byte-len buf-str) (* 2 *limit*))
                               (stop! "Frame is too large"))]
                            [(> (+ nl 1) (* 2 *limit*))
                             (stop! "Frame is too large")]
                            [else
                             (define frame (string/sub buf-str 1 nl))
                             (set-box! input-box (string/sub buf-str (+ nl 2)))
                             (with-handler
                               (lambda (e) (stop! (error-text e)))
                               (define parsed (decode-json frame))
                               (unless (hash? parsed) (error! "Invalid message"))
                               (receive (unbox conn-box) parsed))
                             (loop)])))))))))))))

  (define conn
    (hash "socket" socket "closed" closed-box "id" id-box "label" label-box "cursor" cursor-box
          "stop" stop! "deadline" deadline! "settle" settle! "send" send! "read" read!))
  (set-box! conn-box conn)
  conn)

(define (read-sidecar file)
  (define st (uv-fs-lstat file))
  (if (or (not (hash? st)) (not (equal? (hash-ref st "type") "file")) (> (hash-ref st "size") 4096))
      #f
      (let ([fd (with-handler (lambda (_e) #f) (uv-fs-open file "r" 0))])
        (if (not (integer? fd))
            #f
            (let* ([opened (uv-fs-fstat fd)]
                   [data (and (hash? opened)
                              (= (hash-ref opened "ino") (hash-ref st "ino"))
                              (= (hash-ref opened "dev") (hash-ref st "dev"))
                              (uv-fs-read fd 4096 0))])
              (uv-fs-close fd)
              (define info (with-handler (lambda (_e) #f) (decode-json (or data ""))))
              (if (and (hash? info)
                       (equal? (hash-try-get info "protocol") 1)
                       (string? (hash-try-get info "token"))
                       (string/match (hash-ref info "token")
                                     (string-append "^" (string/rep "%x" 64) "$"))
                       (number? (hash-try-get info "port"))
                       (>= (hash-ref info "port") 1)
                       (<= (hash-ref info "port") 65535)
                       (list? (hash-try-get info "hosts"))
                       (<= (length (hash-ref info "hosts")) 32)
                       (let hloop ([hs (hash-ref info "hosts")])
                         (cond [(null? hs) #t]
                               [(and (string? (car hs)) (<= (string-length (car hs)) 255)
                                     (string/match (car hs) "^[%w%.:%-_]+$"))
                                (hloop (cdr hs))]
                               [else #f])))
                  (hash-insert
                    (hash-insert
                      (hash-insert info "uid" (hash-ref st "uid"))
                      "user" (printable (hash-try-get info "user")))
                    "host" (printable (hash-try-get info "host")))
                  #f))))))

(define (stale-sidecar? info)
  (and (equal? (hash-ref info "host") (uv-os-gethostname))
       (number? (hash-try-get info "pid"))
       (let ([res (uv-kill (hash-ref info "pid") 0)])
         (and (list? res) (string-contains? (cadr res) "ESRCH")))))

(define (advertised-hosts bind)
  (if (and (not (equal? bind "0.0.0.0")) (not (equal? bind "::")))
      (list bind)
      (let ([hosts (box (list (uv-os-gethostname)))])
        (for-each
          (lambda (addrs)
            (for-each
              (lambda (addr)
                (when (and (not (hash-try-get addr "internal"))
                           (or (equal? (hash-try-get addr "family") "inet")
                               (and (equal? bind "::")
                                    (equal? (hash-try-get addr "family") "inet6")
                                    (not (string/find (hash-ref addr "ip") "^fe80")))))
                  (set-box! hosts (append (unbox hosts) (list (hash-ref addr "ip"))))))
              addrs))
          (hash-values->list (uv-interface-addresses)))
        (unbox hosts))))

(define (exclude-sidecar! file temp)
  (define dir (fs-dirname file))
  (unless (null? (fs-find ".git" (hash "path" dir "upward" #t)))
    (unless (= (fn-call "executable" "git") 1)
      (error! "Git is required to exclude the session token"))
    (define (git-sync args)
      (system-wait
        (system-run (append (list "git" "-C" dir) args) (hash "text" #t "timeout" 2000))))
    (define res (git-sync '("rev-parse" "--git-path" "info/exclude")))
    (unless (= (hash-ref res "code") 0)
      (error! "Cannot locate Git's local exclude file"))
    (define raw-path (trim (hash-ref res "stdout")))
    (define excl-path (if (starts-with? raw-path "/") raw-path (fs-joinpath dir raw-path)))
    (define lines (if (= (fn-call "filereadable" excl-path) 1) (vector->list (fn-call "readfile" excl-path)) '()))
    (define missing (filter (lambda (p) (not (member p lines))) '(".*.flash-share" ".*.flash-share.*")))
    (unless (null? missing)
      (fn-call "mkdir" (fs-dirname excl-path) "p")
      (unless (= (fn-call "writefile" (cons "" missing) excl-path "a") 0)
        (error! "Cannot exclude session tokens")))
    (for-each
      (lambda (cand)
        (unless (= (hash-ref (git-sync (list "check-ignore" "-q" "--" cand)) "code") 0)
          (error! "Session file is tracked or not safely ignored")))
      (list file temp))))

(define (publish-sidecar! owner bind)
  (define st (uv-fs-stat (hash-ref owner "path")))
  (unless (hash? st) (error! "Save the source file before sharing"))
  (define perm (modulo (hash-ref st "mode") 512))
  (define grp-read? (not (= (bitwise-and perm 16) 0)))
  (define mode (+ 384 (if grp-read? 32 0) (if (not (= (bitwise-and perm 2) 0)) 4 0)))
  (define file (sidecar-path (hash-ref owner "path")))
  (define existing (read-sidecar file))
  (if (and existing (not (and (stale-sidecar? existing) (= (hash-ref existing "uid") (uv-getuid)))))
      (values #f (string-append (hash-ref existing "user") "@" (hash-ref existing "host")
                                " is already sharing this file; use :PeerpadJoin"))
      (begin
        (when existing (uv-fs-unlink file))
        (define temp (string-append file "." (substring (random-sha256 16) 0 16)))
        (exclude-sidecar! file temp)
        (define info
          (json-encode
            (hash "protocol" 1
                  "port" (unbox (hash-ref owner "port"))
                  "token" (hash-ref owner "token")
                  "hosts" (advertised-hosts bind)
                  "host" (uv-os-gethostname)
                  "user" (hash-ref (uv-os-get-passwd) "username")
                  "pid" (uv-os-getpid))))
        (define fd (checked (uv-fs-open-result temp "wx" 384)))
        (define write-err (box #f))
        (with-handler
          (lambda (e) (set-box! write-err (error-text e)))
          (when (and grp-read? (not (= (hash-ref st "gid") (uv-getgid))))
            (when (list? (uv-fs-fchown fd (uv-getuid) (hash-ref st "gid")))
              (pp-notify "Cannot give the share file the source's group; group members cannot join" (log-level 'warn))))
          (checked (uv-fs-fchmod fd mode))
          (unless (equal? (uv-fs-write fd info 0) (string-length info))
            (error! "Incomplete session file write")))
        (uv-fs-close fd)
        (define link-res (and (not (unbox write-err)) (uv-fs-link temp file)))
        (define linked?
          (and (not (unbox write-err))
               (or (eq? link-res #t)
                   (let ([lst (uv-fs-lstat temp)]) (and (hash? lst) (= (hash-try-get lst "nlink") 2))))))
        (uv-fs-unlink temp)
        (cond
          [(and (not linked?) (read-sidecar file))
           (values #f "Another session advertised this file; use :PeerpadJoin")]
          [(not linked?)
           (error! (string-append "Cannot create " file ": " (or (unbox write-err) (and (list? link-res) (cadr link-res)) "link failed")))]
          [else
           (set-box! (hash-ref owner "sidecar") file)
           (values #t #f)]))))

(define (unpublish-sidecar! owner)
  (define sc (unbox (hash-ref owner "sidecar")))
  (define info (and sc (read-sidecar sc)))
  (when (and info (equal? (hash-ref info "token") (hash-ref owner "token")))
    (uv-fs-unlink sc)))

(define (send-next! session)
  (when (and (unbox (hash-ref session "connected")) (not (unbox (hash-ref session "sent"))))
    (define q (unbox (hash-ref session "queue")))
    (if (not (null? q))
        (begin
          (set-box! (hash-ref session "sent") #t)
          ((hash-ref (unbox (hash-ref session "connection")) "send")
           (hash "type" "edit" "revision" (unbox (hash-ref session "revision")) "operation" (car q))))
        (let ([win (nvim_get_current_win)]
              [buf (unbox (hash-ref session "buf"))])
          (when (and (unbox (hash-ref session "cursor_moved")) buf (= (nvim_win_get_buf win) buf))
            (set-box! (hash-ref session "cursor_moved") #f)
            (define cur (nvim_win_get_cursor win))
            (define off (+ (nvim_buf_get_offset buf (- (vector-ref cur 0) 1)) (vector-ref cur 1)))
            (unless (equal? off (unbox (hash-ref session "reported_cursor")))
              (set-box! (hash-ref session "reported_cursor") off)
              ((hash-ref (unbox (hash-ref session "connection")) "send")
               (hash "type" "cursor" "revision" (unbox (hash-ref session "revision")) "offset" off))))))))

(define (schedule-send! session)
  (when (and (unbox (hash-ref session "connected")) (not (unbox (hash-ref session "send_scheduled"))))
    (set-box! (hash-ref session "send_scheduled") #t)
    (schedule (lambda ()
                (set-box! (hash-ref session "send_scheduled") #f)
                (send-next! session)))))

(define (show-peer! session id label offset0)
  (define offset
    (foldl (lambda (pending acc) (op-move acc pending)) offset0 (unbox (hash-ref session "queue"))))
  (define text (unbox (hash-ref session "text")))
  (define buf (unbox (hash-ref session "buf")))
  (define peer-position (op-position text (min offset (- (string-length text) 1))))
  (define row (list-ref peer-position 0))
  (define col (list-ref peer-position 1))
  (define line (car (vector->list (nvim_buf_get_lines buf row (+ row 1) #t))))
  (define peers (unbox (hash-ref session "peers")))
  (define prev (hash-try-get peers id))
  (define hl (string-append "LiveSharePeer" (number->string (+ (modulo (- id 1) 6) 1))))
  (define opts
    (hash "hl_group" hl
          "virt_text" (list (list (string-append " " label " ") hl))
          "virt_text_pos" "eol"))
  (define opts2 (if (and prev (hash-try-get prev "mark")) (hash-insert opts "id" (hash-ref prev "mark")) opts))
  (define opts3 (if (< col (string-length line)) (hash-insert opts2 "end_col" (+ col 1)) opts2))
  (define mark (nvim_buf_set_extmark buf *cursor-ns* row col opts3))
  (set-box! (hash-ref session "peers")
            (hash-insert peers id (hash "label" label "mark" mark))))

(define (trim-history! hist-box bytes-box)
  (let loop ()
    (define h (unbox hist-box))
    (when (or (> (length h) 1000) (> (unbox bytes-box) (* 4 *limit*)))
      (set-box! bytes-box (- (unbox bytes-box) (op-size (car h))))
      (set-box! hist-box (cdr h))
      (loop))))

(define (rebase-history! hist-box bytes-box remote0)
  (define rev (reverse (unbox hist-box)))
  (let loop ([xs rev] [rem remote0] [acc '()])
    (if (null? xs)
        (begin
          (set-box! hist-box acc)
          (trim-history! hist-box bytes-box))
        (let* ([old-op (car xs)]
               [old-sz (op-size old-op)])
          (define transformed (op-transform rem old-op))
          (define next-rem (list-ref transformed 0))
          (define next-op (list-ref transformed 1))
          (set-box! bytes-box (+ (unbox bytes-box) (- (op-size next-op) old-sz)))
          (loop (cdr xs) next-rem (cons next-op acc))))))

(define (push-history! hist-box bytes-box operation)
  (set-box! hist-box (append (unbox hist-box) (list operation)))
  (set-box! bytes-box (+ (unbox bytes-box) (op-size operation)))
  (trim-history! hist-box bytes-box))

(define (patch-buffer! session operation)
  (define before (unbox (hash-ref session "text")))
  (define after (op-apply before operation))
  (document-valid! after)
  (unless (equal? before after)
    (define edits
      (op-difference (substring before 0 (- (string-length before) 1))
                     (substring after 0 (- (string-length after) 1))))
    (define first (list-ref edits 0))
    (define removed (list-ref edits 1))
    (define inserted (list-ref edits 2))
    (define buf (unbox (hash-ref session "buf")))
    (define positions
      (map (lambda (w)
             (define cur (nvim_win_get_cursor w))
             (define off (+ (nvim_buf_get_offset buf (- (vector-ref cur 0) 1)) (vector-ref cur 1)))
             (cons w (op-move off operation)))
           (vector->list (fn-call "win_findbuf" buf))))
    (set-box! (hash-ref session "applying") #t)
    (define start-position (op-position before first))
    (define row (list-ref start-position 0))
    (define col (list-ref start-position 1))
    (define end-position (op-position before (+ first removed)))
    (define end-row (list-ref end-position 0))
    (define end-col (list-ref end-position 1))
    (define err-box (box #f))
    (with-handler
      (lambda (e) (set-box! err-box e))
      (nvim_buf_set_text buf row col end-row end-col (split-many inserted "\n")))
    (set-box! (hash-ref session "applying") #f)
    (when (unbox err-box) (error! (to-string (unbox err-box))))
    (set-box! (hash-ref session "text") after)
    (for-each
      (lambda (pair)
        (define cursor-position (op-position after (min (cdr pair) (- (string-length after) 1))))
        (define nr (list-ref cursor-position 0))
        (define nc (list-ref cursor-position 1))
        (nvim_win_set_cursor (car pair) (vector (+ nr 1) nc)))
      positions)))

(define (record-op! session operation (kind #f))
  (define inv (op-inverse (unbox (hash-ref session "text")) operation))
  (cond
    [(equal? kind "undo") (push-history! (hash-ref session "redo") (hash-ref session "redo_bytes") inv)]
    [(equal? kind "redo") (push-history! (hash-ref session "undo") (hash-ref session "undo_bytes") inv)]
    [else
     (push-history! (hash-ref session "undo") (hash-ref session "undo_bytes") inv)
     (set-box! (hash-ref session "redo") '())
     (set-box! (hash-ref session "redo_bytes") 0)])
  (when (unbox (hash-ref session "connected"))
    (set-box! (hash-ref session "queue") (append (unbox (hash-ref session "queue")) (list operation)))
    (set-box! (hash-ref session "queue_bytes") (+ (unbox (hash-ref session "queue_bytes")) (op-size operation)))
    (when (or (> (length (unbox (hash-ref session "queue"))) 1000)
              (> (unbox (hash-ref session "queue_bytes")) (* 4 *limit*)))
      (schedule
        (lambda ()
          ((hash-ref (unbox (hash-ref session "connection")) "stop")
           "Too many unacknowledged edits; local text was retained"))))))

(define (undo-shared! session redo?)
  (define hbox (hash-ref session (if redo? "redo" "undo")))
  (define bbox (hash-ref session (if redo? "redo_bytes" "undo_bytes")))
  (let loop ([rem (max 1 (or (v-get "count1") 1))])
    (when (and (> rem 0) (not (null? (unbox hbox))))
      (define rev (reverse (unbox hbox)))
      (define operation (car rev))
      (set-box! hbox (reverse (cdr rev)))
      (set-box! bbox (- (unbox bbox) (op-size operation)))
      (define ok?
        (with-handler
          (lambda (_e) #f)
          (define after (op-apply (unbox (hash-ref session "text")) operation))
          (document-valid! after)
          #t))
      (if (not ok?)
          (pp-notify "That change can no longer be undone" (log-level 'warn))
          (begin
            (record-op! session operation (if redo? "redo" "undo"))
            (patch-buffer! session operation)
            (loop (- rem 1))))))
  (send-next! session))

(define (write-shared! session)
  (define owner (unbox *server*))
  (cond
    [(or (not owner) (not (equal? (unbox (hash-ref owner "session")) session)))
     (pp-notify "Only the session owner saves the source file" (log-level 'warn))]
    [(or (not (unbox (hash-ref session "connected")))
         (not (null? (unbox (hash-ref session "queue"))))
         (not (equal? (unbox (hash-ref session "text")) (unbox (hash-ref owner "text")))))
     (pp-notify "Wait for pending edits to synchronize before saving" (log-level 'warn))]
    [(let ([src (hash-ref owner "source")])
       (or (not (nvim_buf_is_loaded src))
           (not (peerpad-is-source? src))
           (not (bo-get src "modifiable"))
           (not (= (nvim_buf_get_changedtick src) (unbox (hash-ref owner "source_tick"))))
           (not (equal? (nvim_buf_get_name src) (hash-ref owner "path")))
           (not (equal? (disk-content (hash-ref owner "path")) (unbox (hash-ref owner "disk"))))))
     (pp-notify "Source file changed outside this session; save was refused" (log-level 'error))]
    [else
     (define src (hash-ref owner "source"))
     (define otext (unbox (hash-ref owner "text")))
     (nvim_buf_set_lines src 0 -1 #f (split-many (substring otext 0 (- (string-length otext) 1)) "\n"))
     (set-box! (hash-ref owner "source_tick") (nvim_buf_get_changedtick src))
     (define err-box (box #f))
     (with-handler
       (lambda (e) (set-box! err-box (error-text e)))
       (buf-call src (lambda () (cmd "write"))))
     (set-box! (hash-ref owner "source_tick") (nvim_buf_get_changedtick src))
     (set-box! (hash-ref owner "disk") (disk-content (hash-ref owner "path")))
     (cond
       [(unbox err-box) (pp-notify (unbox err-box) (log-level 'error))]
       [(not (equal? (string-append (string-join (vector->list (nvim_buf_get_lines src 0 -1 #f)) "\n") "\n") otext))
        (pp-notify "A source write hook changed the file; stop sharing before continuing" (log-level 'error))
        (peerpad-core-stop)]
       [else
        (bo-set (unbox (hash-ref session "buf")) "modified" #f)
        (pp-notify (string-append "Saved " (hash-ref owner "path")))])]))

(define (create-shared-buffer! session msg)
  (define buf (nvim_create_buf #t #f))
  (define text (hash-ref msg "text"))
  (define file (hash-ref msg "file"))
  (set-box! (hash-ref session "buf") buf)
  (set-box! (hash-ref session "text") text)
  (set-box! (hash-ref session "file") file)
  (define name (string-append "peerpad://" (hash-ref msg "session") "/"
                              (number->string (unbox (hash-ref session "id"))) "/"
                              (fs-basename file)))
  (nvim_buf_set_name buf name)
  (bo-set buf "buftype" "acwrite")
  (bo-set buf "bufhidden" "hide")
  (bo-set buf "swapfile" #f)
  (bo-set buf "undofile" #f)
  (bo-set buf "undolevels" -1)
  (bo-set buf "modeline" #f)
  (nvim_buf_set_lines buf 0 -1 #f (split-many (substring text 0 (- (string-length text) 1)) "\n"))
  (bo-set buf "filetype" (hash-ref msg "filetype"))
  (bo-set buf "modified" #f)
  (b-set buf "live_shared" #t)
  (nvim_create_autocmd
    '("BufWriteCmd" "FileWriteCmd" "FileAppendCmd")
    (hash "group" *group* "buf" buf
          "callback"
          (lambda (args)
            (cond
              [(not (unbox (hash-ref session "connected")))
               (pp-notify "Disconnected snapshot: copy its text into a normal buffer to save" (log-level 'warn))]
              [(and (equal? (hash-ref args "event") "BufWriteCmd") (equal? (nvim_buf_get_name buf) name))
               (write-shared! session)]
              [else
               (pp-notify "Shared buffers cannot write another path; copy text into a normal buffer first" (log-level 'warn))]))))
  (nvim_create_autocmd
    '("CursorMoved" "CursorMovedI")
    (hash "group" *group* "buf" buf
          "callback" (lambda (_args)
                       (set-box! (hash-ref session "cursor_moved") #t)
                       (schedule-send! session))))
  (keymap-set "n" "u" (lambda () (undo-shared! session #f)) (hash "buf" buf "desc" "Undo my shared edit"))
  (keymap-set "n" "<C-r>" (lambda () (undo-shared! session #t)) (hash "buf" buf "desc" "Redo my shared edit"))
  (nvim_buf_attach
    buf #f
    (hash "on_bytes"
          (lambda (_ev _b _tick row col start _or _oc removed added-rows added-col)
            (cond
              [(unbox (hash-ref session "disabled")) #t]
              [(unbox (hash-ref session "applying")) #f]
              [else
               (define count (nvim_buf_line_count buf))
               (define finish (+ row added-rows))
               (define lines0 (vector->list (nvim_buf_get_lines buf row (min (+ finish 1) count) #t)))
               (define lines1
                 (if (< finish count)
                     (let* ([rev (reverse lines0)]
                            [end-col (if (= added-rows 0) (+ col added-col) added-col)])
                       (reverse (cons (substring (car rev) 0 end-col) (cdr rev))))
                     (append lines0 '(""))))
               (define lines2 (cons (substring (car lines1) col (string-length (car lines1))) (cdr lines1)))
               (define inserted (string-join lines2 "\n"))
               (define cur-text (unbox (hash-ref session "text")))
               (define operation (op-splice (string-length cur-text) start removed inserted))
               (define after
                 (with-handler
                   (lambda (_e) #f)
                   (define a (op-apply cur-text operation))
                   (document-valid! a)
                   (when (= (+ start removed) (string-length cur-text))
                     (unless (equal? a (string-append (substring cur-text 0 start) inserted))
                       (error! "sentinel mismatch")))
                   a))
               (if (not after)
                   (begin
                     (set-box! (hash-ref session "disabled") #t)
                     (schedule
                       (lambda ()
                         (when (nvim_buf_is_valid buf)
                           (keymap-del "n" "u" (hash "buf" buf))
                           (keymap-del "n" "<C-r>" (hash "buf" buf))
                           (bo-set buf "undolevels" (go-get "undolevels")))
                         (define reason "Unsupported edit; buffer retained, sharing stopped")
                         (define conn (unbox (hash-ref session "connection")))
                         (if (unbox (hash-ref conn "closed"))
                             (pp-notify reason (log-level 'warn))
                             ((hash-ref conn "stop") reason))))
                     #f)
                   (begin
                     (unless (equal? after cur-text)
                       (record-op! session operation)
                       (set-box! (hash-ref session "text") after)
                       (schedule-send! session))
                     #f))]))
          "on_detach"
          (lambda (_ev _b)
            (schedule (lambda () (when (equal? (unbox *client*) session) (peerpad-core-stop)))))))
  (define target (hash-ref session "target"))
  (define twin (hash-ref target "win"))
  (define tbuf (hash-ref target "buf"))
  (if (and (nvim_win_is_valid twin)
           (= (nvim_win_get_buf twin) tbuf)
           (= (nvim_buf_get_changedtick tbuf) (hash-ref target "tick"))
           (equal? (nvim_buf_get_name tbuf) (hash-ref target "name")))
      (nvim_win_set_buf twin buf)
      (pp-notify (string-append "Original window changed; shared buffer is available with :buffer " (number->string buf)))))

(define (finish-buffer! session)
  (define buf (unbox (hash-ref session "buf")))
  (define source (hash-ref (hash-ref session "target") "buf"))
  (if (or (not buf) (not (nvim_buf_is_valid buf)))
      ""
      (begin
        (b-set buf "live_shared" #f)
        (nvim_buf_clear_namespace buf *cursor-ns* 0 -1)
        (if (and (nvim_buf_is_loaded source)
                 (peerpad-is-source? source)
                 (equal? (nvim_buf_get_name source) (unbox (hash-ref session "file")))
                 (null? (unbox (hash-ref session "queue")))
                 (equal? (vector->list (nvim_buf_get_lines buf 0 -1 #f)) (vector->list (nvim_buf_get_lines source 0 -1 #f))))
            (begin
              (for-each
                (lambda (w)
                  (win-call
                    w
                    (lambda ()
                      (define view (fn-call "winsaveview"))
                      (nvim_win_set_buf w source)
                      (fn-call "winrestview" view))))
                (vector->list (fn-call "win_findbuf" buf)))
              (nvim_buf_delete buf (hash "force" #t))
              "; returned to source buffer")
            (let ([name (nvim_buf_get_name buf)])
              (nvim_buf_set_name buf (string-append (fs-dirname name) "/[disconnected] "
                                                    (fs-basename (unbox (hash-ref session "file")))))
              "; disconnected snapshot retained")))))

(define (connect! hosts port token (owner #f))
  (when (unbox *client*) (error! "Already sharing; use :PeerpadStop first"))
  (when (and (not owner) (not (peerpad-is-editor? 0)))
    (peerpad-focus-editor!))
  (define cur-buf (nvim_get_current_buf))
  (define session
    (hash "queue" (box '()) "queue_bytes" (box 0)
          "undo" (box '()) "undo_bytes" (box 0)
          "redo" (box '()) "redo_bytes" (box 0)
          "peers" (box (hash))
          "connected" (box #f) "sent" (box #f) "send_scheduled" (box #f)
          "cursor_moved" (box #f) "reported_cursor" (box #f)
          "applying" (box #f) "disabled" (box #f) "refused" (box #f) "silent" (box #f)
          "id" (box #f) "revision" (box 0) "buf" (box #f) "text" (box "") "file" (box "")
          "attempt" (box 0) "connection" (box #f)
          "target" (if owner
                       (hash-ref owner "target")
                       (hash "win" (nvim_get_current_win) "buf" cur-buf
                             "tick" (nvim_buf_get_changedtick cur-buf)
                             "name" (nvim_buf_get_name cur-buf)))))
  (set-box! *client* session)
  (when owner (set-box! (hash-ref owner "session") session))

  (define (receive! _conn msg)
    (define mtype (hash-try-get msg "type"))
    (cond
      [(equal? mtype "welcome")
       (when (unbox (hash-ref session "connected")) (error! "Repeated welcome"))
       (document-valid! (hash-ref msg "text"))
       (op-valid-text! (hash-ref msg "text"))
       ((hash-ref (unbox (hash-ref session "connection")) "settle"))
       (set-box! (hash-ref session "id") (hash-ref msg "id"))
       (set-box! (hash-ref session "revision") (hash-ref msg "revision"))
       (set-box! (hash-ref session "connected") #t)
       (create-shared-buffer! session msg)
       (for-each
         (lambda (p) (show-peer! session (hash-ref p "id") (printable (hash-ref p "label") 128) (hash-ref p "offset")))
         (or (and (list? (hash-try-get msg "cursors")) (hash-ref msg "cursors")) '()))
       (set-box! (hash-ref session "cursor_moved") #t)
       (send-next! session)
       (pp-notify "Connected. u/Ctrl+r undo only your edits; :PeerpadStop disconnects")]
      [(equal? mtype "edit")
       (unless (and (unbox (hash-ref session "connected"))
                    (= (hash-ref msg "revision") (+ (unbox (hash-ref session "revision")) 1)))
         (error! "Revision mismatch"))
       (when (unbox (hash-ref session "reported_cursor"))
         (set-box! (hash-ref session "reported_cursor")
                   (op-move (unbox (hash-ref session "reported_cursor")) (hash-ref msg "operation"))))
       (if (= (hash-ref msg "id") (unbox (hash-ref session "id")))
           (let ([q (unbox (hash-ref session "queue"))])
             (unless (and (unbox (hash-ref session "sent")) (not (null? q)))
               (error! "Unexpected acknowledgement"))
             (set-box! (hash-ref session "queue_bytes") (- (unbox (hash-ref session "queue_bytes")) (op-size (car q))))
             (set-box! (hash-ref session "queue") (cdr q))
             (set-box! (hash-ref session "sent") #f))
           (let loop ([qs (unbox (hash-ref session "queue"))] [rem (hash-ref msg "operation")] [acc '()])
             (if (null? qs)
                 (begin
                   (set-box! (hash-ref session "queue") (reverse acc))
                   (patch-buffer! session rem)
                   (rebase-history! (hash-ref session "undo") (hash-ref session "undo_bytes") rem)
                   (rebase-history! (hash-ref session "redo") (hash-ref session "redo_bytes") rem))
                 (let ([p (car qs)])
                   (define transformed (op-transform rem p))
                   (define nrem (list-ref transformed 0))
                   (define np (list-ref transformed 1))
                   (set-box! (hash-ref session "queue_bytes")
                             (+ (unbox (hash-ref session "queue_bytes")) (- (op-size np) (op-size p))))
                   (loop (cdr qs) nrem (cons np acc))))))
       (set-box! (hash-ref session "revision") (hash-ref msg "revision"))
       (send-next! session)]
      [(equal? mtype "cursor")
       (unless (and (unbox (hash-ref session "connected"))
                    (= (hash-ref msg "revision") (unbox (hash-ref session "revision"))))
         (error! "Revision mismatch"))
       (show-peer! session (hash-ref msg "id") (printable (hash-ref msg "label") 128) (hash-ref msg "offset"))]
      [(equal? mtype "refused")
       (set-box! (hash-ref session "refused") #t)
       (error! (printable (hash-ref msg "reason") 128))]
      [(equal? mtype "leave")
       (define p (hash-try-get (unbox (hash-ref session "peers")) (hash-ref msg "id")))
       (when (and p (hash-try-get p "mark") (nvim_buf_is_valid (unbox (hash-ref session "buf"))))
         (nvim_buf_del_extmark (unbox (hash-ref session "buf")) *cursor-ns* (hash-ref p "mark")))
       (set-box! (hash-ref session "peers") (hash-remove (unbox (hash-ref session "peers")) (hash-ref msg "id")))]
      [else (error! "Unknown server message")]))

  (define (attempt! idx)
    (define host (list-ref hosts idx))
    (define sock (uv-new-tcp))
    (define conn
      (make-channel
        sock receive!
        (lambda (reason)
          (if (and (not (unbox (hash-ref session "id")))
                   (not (unbox (hash-ref session "refused")))
                   (equal? (unbox *client*) session)
                   (< (+ idx 1) (length hosts)))
              (attempt! (+ idx 1))
              (begin
                (set-box! (hash-ref session "connected") #f)
                (when (equal? (unbox *client*) session) (set-box! *client* #f))
                (define outcome (finish-buffer! session))
                (unless (unbox (hash-ref session "silent"))
                  (pp-notify (string-append (or reason "Disconnected") outcome)
                             (if reason (log-level 'warn) (log-level 'info)))))))))
    (set-box! (hash-ref session "attempt") idx)
    (set-box! (hash-ref session "connection") conn)
    ((hash-ref conn "deadline") 5000 (string-append "Cannot reach " host ":" (number->string port)))
    (uv-getaddrinfo
      host #f (hash "socktype" "stream")
      (lambda (err addrs)
        (schedule
          (lambda ()
            (unless (unbox (hash-ref conn "closed"))
              (if (or err (not addrs) (null? addrs))
                  ((hash-ref conn "stop") (or (and err (error-text err)) (string-append "Cannot resolve " host)))
                  (uv-tcp-connect
                    sock (hash-ref (car addrs) "addr") port
                    (lambda args
                      (define cerr (and (not (null? args)) (not (equal? (car args) void)) (car args)))
                      (schedule
                        (lambda ()
                          (unless (unbox (hash-ref conn "closed"))
                            (if cerr
                                ((hash-ref conn "stop") (to-string cerr))
                                (begin
                                  ((hash-ref conn "read"))
                                  ((hash-ref conn "send")
                                   (hash "type" "hello" "token" token "protocol" 2
                                         "user" (hash-ref (uv-os-get-passwd) "username")))))))))))))))))

  (attempt! 0))

(define (peerpad-core-start (args '()))
  (when (or (unbox *server*) (unbox *client*))
    (error! "Already sharing; use :PeerpadStop first"))
  (define source (nvim_get_current_buf))
  (unless (and (peerpad-allows? source) (bo-get source "modifiable"))
    (error! "Share a normal, editable source buffer"))
  (unless (equal? (go-get "encoding") "utf-8")
    (error! "UTF-8 is required"))
  (define path (nvim_buf_get_name source))
  (when (equal? path "") (error! "Save/name the source file before sharing"))
  (define text (string-append (string-join (vector->list (nvim_buf_get_lines source 0 -1 #f)) "\n") "\n"))
  (document-valid! text)
  (op-valid-text! text)
  (define port (if (>= (length args) 1) (string->number (list-ref args 0)) 0))
  (unless (and port (>= port 0) (<= port 65535) (= port (floor port)))
    (error! "Invalid port"))
  (when (> (length args) 2) (error! "Usage: Peerpad [port] [bind-address]"))
  (define address (if (= (length args) 2) (list-ref args 1) "0.0.0.0"))
  (define hosts (advertised-hosts address))
  (define dcontent (disk-content path))
  (when (equal? dcontent #f) (error! "Source file on disk exceeds 2 MiB"))
  (define listener (uv-new-tcp))
  (define owner
    (hash "text" (box text) "revision" (box 0)
          "history" (box (hash)) "history_floor" (box 0) "history_bytes" (box 0)
          "peers" (box '()) "next_id" (box 0)
          "token" (random-sha256 32)
          "target" (hash "win" (nvim_get_current_win) "buf" source
                         "tick" (nvim_buf_get_changedtick source) "name" path)
          "source" source "source_tick" (box (nvim_buf_get_changedtick source))
          "path" path "filetype" (bo-get source "filetype") "disk" (box dcontent)
          "capacity" (max 2 (min (hash-ref (unbox *config*) "max_peers") 64))
          "ip" (if (>= (length hosts) 2) (list-ref hosts 1) (car hosts))
          "listener" listener "port" (box 0) "sidecar" (box #f) "session" (box #f)))
  (with-handler
    (lambda (e) (close-handle! listener) (error! (error-text e)))
    (checked (uv-tcp-bind listener address port)))
  (set-box! *server* owner)
  (with-handler
    (lambda (e) (peerpad-core-stop) (error! (error-text e)))
    (checked (uv-tcp-listen
      listener 8
      (lambda args
        (define aerr (and (not (null? args)) (not (equal? (car args) void)) (car args)))
        (schedule
          (lambda ()
            (when (and (equal? (unbox *server*) owner) (not aerr))
              (define sock (uv-new-tcp))
              (uv-tcp-accept listener sock)
             (define full? (>= (length (unbox (hash-ref owner "peers"))) (hash-ref owner "capacity")))
             (define peer-box (box #f))
             (define peer
               (make-channel
                 sock
                 (lambda (conn msg)
                   (cond
                     [(not (unbox (hash-ref conn "id")))
                      (unless (and (equal? (hash-try-get msg "type") "hello")
                                   (equal? (hash-try-get msg "protocol") 2)
                                   (equal? (hash-try-get msg "token") (hash-ref owner "token")))
                        (error! "Authentication failed or incompatible peerpad protocol"))
                      ((hash-ref conn "settle"))
                      (define nid (+ (unbox (hash-ref owner "next_id")) 1))
                      (set-box! (hash-ref owner "next_id") nid)
                      (set-box! (hash-ref conn "id") nid)
                      (define pinfo (uv-tcp-getpeername sock))
                      (define ip0 (or (and (hash? pinfo) (hash-try-get pinfo "ip")) "?"))
                      (define ip (if (or (string/find ip0 "^127%.") (equal? ip0 "::1") (string/find ip0 "^::ffff:127%."))
                                     (hash-ref owner "ip") ip0))
                      (define lbl0 (string-append (printable (or (hash-try-get msg "user") "?")) "@" ip))
                      (define dup?
                        (let loop ([ps (unbox (hash-ref owner "peers"))])
                          (cond [(null? ps) #f]
                                [(equal? (unbox (hash-ref (car ps) "label")) lbl0) #t]
                                [else (loop (cdr ps))])))
                      (set-box! (hash-ref conn "label")
                                (if dup? (string-append lbl0 " #" (number->string nid)) lbl0))
                      (define cursors
                        (filter-map
                          (lambda (m)
                            (and (unbox (hash-ref m "cursor"))
                                 (hash "id" (unbox (hash-ref m "id"))
                                       "label" (unbox (hash-ref m "label"))
                                       "offset" (unbox (hash-ref m "cursor")))))
                          (unbox (hash-ref owner "peers"))))
                      ((hash-ref conn "send")
                       (hash "type" "welcome" "id" nid "revision" (unbox (hash-ref owner "revision"))
                             "text" (unbox (hash-ref owner "text")) "file" (hash-ref owner "path")
                             "filetype" (hash-ref owner "filetype")
                             "session" (substring (hash-ref owner "token") 0 16)
                             "cursors" cursors))]
                     [(equal? (hash-try-get msg "type") "cursor")
                      (define rev (hash-try-get msg "revision"))
                      (define off0 (hash-try-get msg "offset"))
                      (unless (and (number? rev) (number? off0) (>= off0 0)) (error! "Invalid cursor"))
                      (define cur-rev (unbox (hash-ref owner "revision")))
                      (when (and (>= rev (unbox (hash-ref owner "history_floor"))) (<= rev cur-rev))
                        (define off
                          (let loop ([i (+ rev 1)] [o off0])
                            (if (> i cur-rev)
                                o
                                (loop (+ i 1) (op-move o (hash-ref (hash-ref (unbox (hash-ref owner "history")) i) "operation"))))))
                        (set-box! (hash-ref conn "cursor") off)
                        (for-each
                          (lambda (m)
                            (when (and (unbox (hash-ref m "id")) (not (equal? m conn)))
                              ((hash-ref m "send")
                               (hash "type" "cursor" "id" (unbox (hash-ref conn "id"))
                                     "label" (unbox (hash-ref conn "label"))
                                     "revision" cur-rev "offset" off))))
                          (unbox (hash-ref owner "peers"))))]
                     [(equal? (hash-try-get msg "type") "edit")
                      (define rev (hash-try-get msg "revision"))
                      (define cur-rev (unbox (hash-ref owner "revision")))
                      (unless (and (number? rev) (>= rev (unbox (hash-ref owner "history_floor"))) (<= rev cur-rev))
                        (error! "Client is too far behind; reconnect"))
                      (define len
                        (if (= rev cur-rev)
                            (string-length (unbox (hash-ref owner "text")))
                            (hash-ref (hash-ref (unbox (hash-ref owner "history")) (+ rev 1)) "length")))
                      (define op0 (hash-ref msg "operation"))
                      (op-validate! op0 len)
                      (define rebased
                        (let loop ([i (+ rev 1)] [o op0])
                          (if (> i cur-rev)
                              o
                              (let* ([entry (hash-ref (unbox (hash-ref owner "history")) i)]
                                     [transformed (op-transform (hash-ref entry "operation") o)])
                                (loop (+ i 1) (cadr transformed))))))
                      (define prev-text (unbox (hash-ref owner "text")))
                      (define after (op-apply prev-text rebased))
                      (document-valid! after)
                      (define nrev (+ cur-rev 1))
                      (set-box! (hash-ref owner "revision") nrev)
                      (set-box! (hash-ref owner "history")
                                (hash-insert (unbox (hash-ref owner "history")) nrev
                                             (hash "operation" rebased "length" (string-length prev-text))))
                      (set-box! (hash-ref owner "history_bytes") (+ (unbox (hash-ref owner "history_bytes")) (op-size rebased)))
                      (let tloop ()
                        (when (or (> (- nrev (unbox (hash-ref owner "history_floor"))) 1024)
                                  (> (unbox (hash-ref owner "history_bytes")) (* 4 *limit*)))
                          (define nf (+ (unbox (hash-ref owner "history_floor")) 1))
                          (set-box! (hash-ref owner "history_floor") nf)
                          (define drop-op (hash-ref (hash-ref (unbox (hash-ref owner "history")) nf) "operation"))
                          (set-box! (hash-ref owner "history_bytes") (- (unbox (hash-ref owner "history_bytes")) (op-size drop-op)))
                          (set-box! (hash-ref owner "history") (hash-remove (unbox (hash-ref owner "history")) nf))
                          (tloop)))
                      (set-box! (hash-ref owner "text") after)
                      (for-each
                        (lambda (m)
                          (when (unbox (hash-ref m "cursor"))
                            (set-box! (hash-ref m "cursor") (op-move (unbox (hash-ref m "cursor")) rebased)))
                          (when (unbox (hash-ref m "id"))
                            ((hash-ref m "send")
                             (hash "type" "edit" "id" (unbox (hash-ref conn "id"))
                                   "revision" nrev "operation" rebased))))
                        (unbox (hash-ref owner "peers")))]
                     [else (error! "Unknown client message")]))
                 (lambda (_r)
                   (define p (unbox peer-box))
                   (set-box! (hash-ref owner "peers")
                             (filter (lambda (m) (not (equal? m p))) (unbox (hash-ref owner "peers"))))
                   (when (and p (unbox (hash-ref p "id")))
                     (for-each
                       (lambda (m)
                         (when (unbox (hash-ref m "id"))
                           ((hash-ref m "send") (hash "type" "leave" "id" (unbox (hash-ref p "id"))))))
                       (unbox (hash-ref owner "peers")))))))
             (set-box! peer-box peer)
             (if full?
                 (begin
                   ((hash-ref peer "send")
                    (hash "type" "refused"
                          "reason" (string-append "Session is full (" (number->string (hash-ref owner "capacity")) " participants)")))
                   (uv-tcp-shutdown sock (lambda _args (schedule (lambda () ((hash-ref peer "stop")))))))
                 (begin
                   (set-box! (hash-ref owner "peers") (cons peer (unbox (hash-ref owner "peers"))))
                   ((hash-ref peer "deadline") 10000 "Authentication timed out")
                   ((hash-ref peer "read")))))))))))
  (define bound-port (hash-ref (uv-tcp-getsockname listener) "port"))
  (set-box! (hash-ref owner "port") bound-port)
  (define publication
    (with-handler
      (lambda (e)
        (pp-notify (string-append "Automatic discovery unavailable: " (error-text e) "; manual joining still works")
                   (log-level 'warn))
        #f)
      (publish-sidecar! owner address)))
  (when (and publication (not (list-ref publication 0)))
    (peerpad-core-stop)
    (error! (list-ref publication 1)))
  (define connect-host (cond [(equal? address "0.0.0.0") "127.0.0.1"] [(equal? address "::") "::1"] [else address]))
  (connect! (list connect-host) bound-port (hash-ref owner "token") owner)
  (pp-notify
    (string-append "Port " (number->string bound-port)
                   (if (unbox (hash-ref owner "sidecar"))
                       ". Others opening this file are offered to join. Manual: "
                       ". Manual: ")
                   ":PeerpadJoin <host> " (number->string bound-port) " " (hash-ref owner "token"))))

(define (peerpad-core-discover buf ask?)
  (unless (and ask? (or (not (= (nvim_get_current_buf) buf)) (not (peerpad-is-editor? 0))))
    (define path (nvim_buf_get_name buf))
    (define file (sidecar-path path))
    (define info (read-sidecar file))
    (cond
      [(not info)
       (unless ask? (error! "No live share for this file; use :PeerpadJoin <host> <port> <token>"))]
      [(and (unbox *server*) (equal? (hash-ref (unbox *server*) "token") (hash-ref info "token")))
       #f]
      [(stale-sidecar? info)
       (when (= (hash-ref info "uid") (uv-getuid)) (uv-fs-unlink file))
       (pp-notify (string-append "Ignored a stale share from " (hash-ref info "user") "@" (hash-ref info "host")
                                 " (its Neovim exited)")
                  (log-level 'warn))]
      [(unbox *client*)
       (pp-notify (string-append (hash-ref info "user") "@" (hash-ref info "host")
                                 " is sharing this file; :PeerpadStop, then :PeerpadJoin")
                  (log-level 'warn))]
      [(and ask? (not (= (fn-call "confirm"
                                  (string-append (hash-ref info "user") "@" (hash-ref info "host")
                                                 " is live-sharing " (fs-basename path) ". Join?")
                                  "&Join\n&Not now" 2)
                         1)))
       #f]
      [else
       (define hosts
         (if (equal? (hash-ref info "host") (uv-os-gethostname))
             (cons "127.0.0.1" (hash-ref info "hosts"))
             (let ([own (box (hash "localhost" #t))])
               (for-each (lambda (iface)
                           (for-each (lambda (a) (set-box! own (hash-insert (unbox own) (hash-ref a "ip") #t)))
                                     (cdr iface)))
                         (uv-interface-addresses))
               (filter (lambda (h) (and (not (hash-contains? (unbox own) h)) (not (string/find h "^127%."))))
                       (hash-ref info "hosts")))))
       (when (null? hosts)
         (error! (string-append (hash-ref info "user") "@" (hash-ref info "host") " advertises no reachable address")))
       (connect! hosts (hash-ref info "port") (hash-ref info "token"))])))

(define (peerpad-core-join (args '()))
  (if (null? args)
      (peerpad-core-discover (nvim_get_current_buf) #f)
      (begin
        (unless (= (length args) 3) (error! "Usage: PeerpadJoin [<host> <port> <token>]"))
        (define port (string->number (list-ref args 1)))
        (unless (and port (> port 0) (<= port 65535) (= port (floor port))) (error! "Invalid port"))
        (connect! (list (list-ref args 0)) port (list-ref args 2)))))

(define (stop-internal! silent?)
  (define owner (unbox *server*))
  (define session (unbox *client*))
  (set-box! *server* #f)
  (set-box! *client* #f)
  (when session
    (set-box! (hash-ref session "silent") silent?)
    ((hash-ref (unbox (hash-ref session "connection")) "stop")))
  (when owner
    (unpublish-sidecar! owner)
    (close-handle! (hash-ref owner "listener"))
    (for-each (lambda (p) ((hash-ref p "stop"))) (unbox (hash-ref owner "peers"))))
  (when (and owner (unbox (hash-ref owner "session")) (not (equal? (unbox (hash-ref owner "session")) session)))
    (define os (unbox (hash-ref owner "session")))
    (set-box! (hash-ref os "silent") silent?)
    ((hash-ref (unbox (hash-ref os "connection")) "stop")))
  (when (and owner (not session) (not silent?))
    (pp-notify "Sharing stopped")))

(define (peerpad-core-stop (_args '()))
  (stop-internal! #f))

(define (peerpad-core-status (_args '()))
  (define session (unbox *client*))
  (if (not session)
      (pp-notify (if (unbox *server*) "Server running; local client disconnected" "Not sharing"))
      (let* ([header (string-append (if (unbox *server*) "Owner" "Guest")
                                    ", revision " (number->string (unbox (hash-ref session "revision")))
                                    ", pending edits " (number->string (length (unbox (hash-ref session "queue")))))]
             [peers (unbox (hash-ref session "peers"))]
             [peer-lines
              (map (lambda (id)
                     (define p (hash-ref peers id))
                     (define pos (nvim_buf_get_extmark_by_id (unbox (hash-ref session "buf")) *cursor-ns* (hash-ref p "mark") (hash)))
                     (string-append "  " (hash-ref p "label")
                                    " at line " (number->string (+ (vector-ref pos 0) 1))
                                    ", column " (number->string (+ (vector-ref pos 1) 1))))
                   (hash-keys->list peers))])
        (pp-notify (string-join (cons header peer-lines) "\n")))))

(nvim_create_autocmd
  "VimLeavePre"
  (hash "group" *group* "callback" (lambda (_args) (stop-internal! #t))))
