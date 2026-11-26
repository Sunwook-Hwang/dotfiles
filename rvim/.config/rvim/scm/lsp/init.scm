;; 1:1 Steel port of: nvim/.config/nvim/lua/lsp/init.lua
;; Equivalence:
;; - Resolves installed language server binaries from `*lsp-servers*`, registers filetype
;;   providers with `analysis_backend.scm`, configures each server via `lsp-config!`,
;;   and enables it via `lsp-enable!`.
;; - Enforces project marker / `package.json` dependency checks for auxiliary servers and
;;   nested `pyrightconfig.json`/`pyproject.toml` root discovery for `pyright-langserver`.

(require-builtin rvim/api)
(require "rvim/fs")
(require "rvim/json")
(require "rvim/lsp")
(require "buffer_policy")
(require "analysis_backend")
(require "state")
(require "lsp/servers")
(require "lsp/python")
(require "lsp/keymaps")
(require "lsp/diagnostics")
(require "lsp/refresh")
(require "lsp/lifecycle")
(require "lsp/dependencies")

(define (project-uses-server? server dir)
  (define markers (hash-try-get server "markers"))
  (define dep (hash-try-get server "dependency"))
  (cond
    [(or (not markers) (fs-root dir markers)) #t]
    [(not dep) #f]
    [else
     (let loop ([paths (fs-find "package.json" (hash "path" dir "upward" #t "type" "file" "limit" 1000))])
       (if (null? paths)
           #f
           (let* ([raw (with-handler (lambda (_e) "") (fs-read-file (car paths)))]
                  [snippet (substring raw 0 (min 65536 (string-length raw)))]
                  [pkg (with-handler (lambda (_e) #f) (json-decode snippet))])
             (if (and (hash? pkg)
                      (or (let dloop ([fields '("dependencies" "devDependencies" "peerDependencies")])
                            (cond
                              [(null? fields) #f]
                              [(and (hash? (hash-try-get pkg (car fields)))
                                    (hash-contains? (hash-ref pkg (car fields)) dep))
                               #t]
                              [else (dloop (cdr fields))]))
                          (and (equal? dep "eslint") (hash-try-get pkg "eslintConfig"))))
                 #t
                 (loop (cdr paths))))))]))

(for-each
  (lambda (server)
    (define cands (or (hash-try-get server "alternatives") (list (hash-ref server "cmd"))))
    (define resolved (state-call 'resolve-candidate cands))
    (when resolved
      (define spec (car resolved))
      (define executable (cdr resolved))
      (analysis-backend-register!
        (hash-ref server "ft")
        (lambda (buf)
          (define file (nvim_buf_get_name buf))
          (or (not (hash-try-get server "markers"))
              (and (not (equal? file "")) (project-uses-server? server (fs-dirname file))))))
      (define name (car spec))
      (define is-python (or (equal? name "ty") (equal? name "pyright-langserver")))
      (define command (cons executable (cdr spec)))
      (lsp-config!
        name
        (hash "cmd" command
              "handlers" lsp-diagnostic-handlers
              "filetypes" (hash-ref server "ft")
              "settings" (or (hash-try-get server "settings") (and is-python (hash)))
              "init_options" (hash-try-get server "init_options")
              "before_init" (and is-python lsp-python-before-init)
              "on_init" lsp-refresh-attach!
              "on_attach" lsp-on-attach
              "root_dir"
              (lambda (buf on-dir)
                (when (allows? buf)
                  (define file (nvim_buf_get_name buf))
                  (when (and (not (equal? file "")) (project-uses-server? server (fs-dirname file)))
                    (define dir (fs-dirname file))
                    (define root0 (car (state-call 'find-project dir)))
                    (define root
                      (if (equal? name "pyright-langserver")
                          (let ([found (fs-find '("pyrightconfig.json" "pyproject.toml")
                                                (hash "path" dir "upward" #t "stop" (fs-dirname root0)
                                                      "type" "file" "limit" 1))])
                            (if (null? found) root0 (fs-dirname (car found))))
                          root0))
                    (on-dir root))))))
      (lsp-enable! name)))
  *lsp-servers*)
