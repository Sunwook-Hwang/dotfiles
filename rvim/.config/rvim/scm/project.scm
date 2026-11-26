;; 1:1 Steel port of: nvim/.config/nvim/lua/project.lua
;; Equivalence:
;; - Exact project marker list (CMakeLists.txt, Cargo.toml, pyproject.toml, etc.),
;;   ignored_dirs list, Git + Python site-packages/stdlib boundary detection, and `:NopackRefresh`.
;; - Aligns editor window `:lcd` on `BufEnter` and invalidates root caches on project events.

(require-builtin rvim/api)
(require "rvim/fn")
(require "rvim/cmd")
(require "rvim/fs")
(require-builtin rvim/uv)
(require "rvim/string")
(require "buffer_policy")
(require "state")

(define markers
  (list "CMakeLists.txt" "compile_commands.json" "Makefile" "package.json"
        "pyproject.toml" "ty.toml" "pyrightconfig.json" "Cargo.toml"
        "WORKSPACE" "WORKSPACE.bazel" "MODULE.bazel" "buf.yaml" "verible.filelist"))

(state-set! 'ignored-dirs
            (list ".git" "node_modules" "__pycache__" ".venv" "venv"
                  "build" "build-*" "cmake-build-*" "dist"))

(define *git-roots* (box (hash)))
(define *project-roots* (box (hash)))

(define (find-git-root dir)
  (define cached (hash-try-get (unbox *git-roots*) dir))
  (if cached
      cached
      (let* ((path (string-append (vector-ref (string/gsub dir "/+$" "") 0) "/"))
             (pkg-match (or (string/match path "^(.-/site%-packages/)(.*)$")
                            (string/match path "^(.-/dist%-packages/)(.*)$")))
             (packages (and (vector? pkg-match) (vector-ref pkg-match 0)))
             (relative (and (vector? pkg-match) (vector-ref pkg-match 1)))
             (git-root #f)
             (lib-root (and packages
                            (vector-ref (string/gsub (string-append packages (or (string/match relative "^[^/]+") "")) "/+$" "") 0))))
        (define (walk current)
          (when (and current (not (equal? current "")))
            (cond
              ((uv-fs-stat (string-append current "/.git"))
               (set! git-root current))
              ((and (not lib-root)
                    (= (fn-call "filereadable" (string-append current "/os.py")) 1)
                    (= (fn-call "filereadable" (string-append current "/importlib/__init__.py")) 1))
               (set! lib-root current))
              (else
               (define parent (fs-dirname current))
               (unless (or (not parent) (equal? parent current))
                 (walk parent))))))
        (walk dir)
        (define res (vector git-root lib-root))
        (set-box! *git-roots* (hash-insert (unbox *git-roots*) dir res))
        res)))

(define (find-project dir)
  (define cached (hash-try-get (unbox *project-roots*) dir))
  (if cached
      cached
      (let* ((pair (find-git-root dir))
             (git-root (vector-ref pair 0))
             (lib-root (vector-ref pair 1))
             (res
               (cond
                 (git-root (vector git-root #t #t))
                 (lib-root (vector lib-root #f #t))
                 (else
                  (define found (fs-find markers (hash "path" dir "upward" #t "type" "file" "limit" 1)))
                  (define marker (and (not (null? found)) (car found)))
                  (vector (if marker (fs-dirname marker) dir) #f (not (not marker)))))))
        (set-box! *project-roots* (hash-insert (unbox *project-roots*) dir res))
        res)))

(define (project-root)
  (define current (nvim_get_current_buf))
  (define is-exp? (state-get 'explorer-is-buffer?))
  (define exp-root (state-get 'explorer-root))
  (define dir
    (cond
      ((and (function? is-exp?) (is-exp? current) (function? exp-root))
       (exp-root current))
      ((and (is-source? 0) (not (equal? (nvim_buf_get_name 0) "")))
       (fn-call "expand" "%:p:h"))
      (else
       (define found #f)
       (for-each
         (lambda (win)
           (unless found
             (define buf (nvim_win_get_buf win))
             (define name (nvim_buf_get_name buf))
             (when (and (is-editor? win) (not (equal? name "")))
               (set! found (fn-call "fnamemodify" name ":h")))))
         (nvim_tabpage_list_wins 0))
       (or found (fn-call "getcwd")))))
  (find-project dir))

(state-set! 'find-git-root find-git-root)
(state-set! 'find-project find-project)
(state-set! 'project-root (lambda () (vector-ref (project-root) 0)))
(state-set! 'project-info project-root)

(define proj-group (nvim_create_augroup "nopack-project-context" (hash "clear" #t)))

(nvim_create_autocmd
  "BufEnter"
  (hash "group" proj-group
        "callback"
        (lambda (_args)
          (when (and (is-editor? 0) (not (equal? (nvim_buf_get_name 0) "")))
            (define info (project-root))
            (define root (vector-ref info 0))
            (define recognized (vector-ref info 2))
            (when (and recognized (not (equal? (fn-call "getcwd") root)))
              (cmd (string-append "lcd " (fn-call "fnameescape" root))))))))

(define (invalidate-project-roots! . _args)
  (set-box! *git-roots* (hash))
  (set-box! *project-roots* (hash)))

(nvim_create_autocmd
  (vector "BufFilePost" "FocusGained" "ShellCmdPost" "TermLeave" "TermClose")
  (hash "group" proj-group
        "callback"
        (lambda (args)
          (unless (is-picker-event? args)
            (invalidate-project-roots!)))))

(nvim_create_autocmd
  "BufWritePost"
  (hash "group" proj-group
        "pattern" (list->vector (append markers (list ".git" "os.py" "__init__.py")))
        "callback" invalidate-project-roots!))

(nvim_create_autocmd
  "User"
  (hash "group" proj-group
        "pattern" (vector "NopackRefresh" "NopackExplorerChanged" "NopackExternalChange")
        "callback" invalidate-project-roots!))

(nvim_create_user_command
  "NopackRefresh"
  (lambda (_args)
    (nvim_exec_autocmds "User" (hash "pattern" "NopackRefresh" "modeline" #f))
    (nvim_exec_autocmds "BufEnter" (hash "group" "nopack-project-context" "buf" 0 "modeline" #f))
    (cmd "redrawstatus"))
  (hash "desc" "Refresh project roots and formatter availability"))
