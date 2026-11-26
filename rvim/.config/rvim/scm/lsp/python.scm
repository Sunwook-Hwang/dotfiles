;; 1:1 Steel port of: nvim/.config/nvim/lua/lsp/python.lua
;; Equivalence:
;; - `<leader>lv`: selects the current project's Python LSP environment (`.venv`, `venv`,
;;   `VIRTUAL_ENV`, `CONDA_PREFIX`, `PATH`, async `conda env list --json`, manual input,
;;   or Automatic).
;; - Updates `pyright-langserver` via `workspace/didChangeConfiguration` and restarts `ty`
;;   via `lsp-restart-client!`; exports `lsp-python-before-init`.

(require "rvim/api")
(require "rvim/opt")
(require "rvim/keymap")
(require "rvim/fn")
(require "rvim/fs")
(require "rvim/ui")
(require "rvim/json")
(require "rvim/lsp")
(require "rvim/notify")
(require "buffer_policy")
(require "jobs")
(require "lsp/lifecycle")
(require "state")

(provide lsp-python-before-init)

(define *python-paths* (box (hash)))
(define *python-selection* (box #f))

(define (cancel-python-selection! (buf #f))
  (define sel (unbox *python-selection*))
  (when (and sel (or (not buf) (= (hash-ref sel "buf") buf)))
    (set-box! *python-selection* #f)
    (cancel-command! "conda-envs")
    (define p (unbox (hash-ref sel "picker")))
    (when (and p (equal? (state-get 'active-picker) p))
      ((hash-ref p "close")))))

(define *policy-group* (nvim_create_augroup "nopack-lsp-policy" (hash "clear" #t)))
(nvim_create_autocmd
  "User" (hash "group" *policy-group* "pattern" "NopackBufferRestricted"
               "callback" (lambda (args) (cancel-python-selection! (hash-ref (hash-ref args "data") "buf")))))
(nvim_create_autocmd
  '("BufUnload" "BufFilePost" "FileType")
  (hash "group" *policy-group* "callback" (lambda (args) (cancel-python-selection! (hash-ref args "buf")))))
(nvim_create_autocmd
  "User" (hash "group" *policy-group* "pattern" "NopackCancel"
               "callback" (lambda (_args) (cancel-python-selection!))))
(nvim_create_autocmd
  "VimLeavePre" (hash "group" *policy-group* "callback" (lambda (_args) (cancel-python-selection!))))

(define (apply-python-path settings name path)
  (define base (or settings (hash)))
  (if (equal? name "ty")
      (let* ([ty (or (hash-try-get base "ty") (hash))]
             [cfg (or (hash-try-get ty "configuration") (hash))]
             [env0 (or (hash-try-get cfg "environment") (hash))]
             [env1 (if path (hash-insert env0 "python" path) (hash-remove env0 "python"))])
        (hash-insert base "ty" (hash-insert ty "configuration" (hash-insert cfg "environment" env1))))
      (let* ([py (or (hash-try-get base "python") (hash))]
             [py1 (if path (hash-insert py "pythonPath" path) (hash-remove py "pythonPath"))])
        (hash-insert base "python" py1))))

(keymap-set
  "n" "<leader>lv"
  (lambda ()
    (when (allows? 0)
      (if (not (equal? (bo-get 0 "filetype") "python"))
          (notify "Open a Python file to select its environment")
          (let ([buf (nvim_get_current_buf)]
                [root-res (state-call 'project-root)])
            (define root (if (pair? root-res) (car root-res) root-res))
            (cancel-python-selection!)
            (define sel (hash "buf" buf "picker" (box #f)))
            (set-box! *python-selection* sel)
            (define (active?) (and (equal? (unbox *python-selection*) sel) (allows? buf)))
            (define choices (box '()))
            (define seen (box (hash)))
            (define (add! label path)
              (when (and path (not (equal? path ""))
                         (not (hash-contains? (unbox seen) path))
                         (= (fn-call "executable" path) 1))
                (set-box! seen (hash-insert (unbox seen) path #t))
                (set-box! choices (append (unbox choices) (list (hash "label" (string-append label ": " path) "path" path))))))
            (add! "Selected" (hash-try-get (unbox *python-paths*) root))
            (add! "Project .venv" (string-append root "/.venv/bin/python"))
            (add! "Project venv" (string-append root "/venv/bin/python"))
            (when (env-get "VIRTUAL_ENV")
              (add! "Active venv" (string-append (env-get "VIRTUAL_ENV") "/bin/python")))
            (when (env-get "CONDA_PREFIX")
              (add! "Active Conda" (string-append (env-get "CONDA_PREFIX") "/bin/python")))
            (add! "PATH python" (fn-call "exepath" "python"))
            (add! "PATH python3" (fn-call "exepath" "python3"))
            (set-box! choices
                      (append (unbox choices)
                              (list (hash "label" "Enter Python path..." "manual" #t)
                                    (hash "label" "Automatic (project settings / inherited PATH)"))))
            (define (select-path! path)
              (when (active?)
                (set-box! *python-selection* #f)
                (define changed? (not (equal? (hash-try-get (unbox *python-paths*) root) path)))
                (set-box! *python-paths*
                          (if path
                              (hash-insert (unbox *python-paths*) root path)
                              (hash-remove (unbox *python-paths*) root)))
                (define attached (box #f))
                (define restarting (box #f))
                (for-each
                  (lambda (client)
                    (define cname (hash-ref client "name"))
                    (define rdir (hash-try-get (hash-ref client "config") "root_dir"))
                    (when (and (or (equal? cname "ty") (equal? cname "pyright-langserver"))
                               rdir
                               (equal? (car (state-call 'find-project rdir)) root))
                      (set-box! attached #t)
                      (when changed?
                        (if (equal? cname "ty")
                            (when (lsp-restart-client! client) (set-box! restarting #t))
                            (let ([updated (apply-python-path (hash-try-get client "settings") cname path)])
                              (lsp-client-set-settings! client updated)
                              ((hash-ref client "notify") client "workspace/didChangeConfiguration"
                               (hash "settings" updated)))))))
                  (lsp-get-clients))
                (notify (string-append
                          "Python: " (or path "automatic")
                          (cond [(unbox restarting) " (restarting ty)"]
                                [(unbox attached) ""]
                                [else " (applies when Python LSP attaches)"])))))
            (define (choose! item)
              (when (and item (active?))
                (if (not (hash-try-get item "manual"))
                    (select-path! (hash-try-get item "path"))
                    (ui-input
                      (hash "prompt" "Python executable or venv directory: " "completion" "file")
                      (lambda (raw)
                        (when (and (active?) raw (not (equal? raw "")))
                          (define p0 (fs-normalize raw))
                          (define p1 (if (starts-with? p0 "/") p0 (fs-normalize (string-append root "/" p0))))
                          (define p2 (if (= (fn-call "isdirectory" p1) 1) (string-append p1 "/bin/python") p1))
                          (if (not (= (fn-call "executable" p2) 1))
                              (notify (string-append "Python executable not found: " p2) (log-level 'warn))
                              (select-path! p2))))))))
            (define (build-items)
              (map (lambda (c) (hash "label" (hash-ref c "label") "action" (lambda () (choose! c))))
                   (unbox choices)))
            (define picker
              (state-call
                'open-picker
                (string-append "Python environment: " (fn-call "fnamemodify" root ":t"))
                (hash "items" (build-items)
                      "cancel" (lambda () (cancel-command! "conda-envs"))
                      "on_cancel" (lambda () (when (equal? (unbox *python-selection*) sel)
                                               (set-box! *python-selection* #f))))))
            (set-box! (hash-ref sel "picker") picker)
            (define conda0 (fn-call "exepath" "conda"))
            (define conda
              (if (and (equal? conda0 "") (env-get "CONDA_EXE") (= (fn-call "executable" (env-get "CONDA_EXE")) 1))
                  (env-get "CONDA_EXE")
                  conda0))
            (unless (equal? conda "")
              (run-command!
                "conda-envs"
                (list conda "env" "list" "--json")
                (hash "cwd" root "quiet" #t)
                (lambda (output _lim)
                  (when (and (not (unbox (hash-ref picker "closed"))) (active?))
                    (define decoded (with-handler (lambda (_e) #f) (json-decode output)))
                    (define envs (and (hash? decoded) (hash-try-get decoded "envs")))
                    (when (list? envs)
                      (for-each
                        (lambda (env)
                          (when (string? env)
                            (define p (fs-normalize env))
                            (add! (string-append "Conda " (fs-basename p)) (string-append p "/bin/python"))))
                        envs)
                      ((hash-ref picker "set_items") (build-items)))))))))))
  (hash "desc" "Select Python environment for this project"))

(define (lsp-python-before-init _params config)
  (define rdir (hash-try-get config "root_dir"))
  (define proj (and rdir (car (state-call 'find-project rdir))))
  (define path (and proj (hash-try-get (unbox *python-paths*) proj)))
  (apply-python-path (hash-try-get config "settings") (hash-ref config "name") path))
