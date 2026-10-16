" Optional vim-lsp integration. The standalone .vimrc supplies the native UI/policy.
" Install prabirshrestha/vim-lsp into ~/.vim/pack/vendor/opt/vim-lsp, or set
" g:vim_lsp_path before loading .vimrc. The asyncomplete pair lives beside it.
" No plugin manager or downloads at startup.
if !exists('g:dotfiles_vim_lsp_host') | finish | endif
let s:plugin = expand(get(g:, 'vim_lsp_path', '~/.vim/pack/vendor/opt/vim-lsp'))
if !exists('g:lsp_loaded') && !filereadable(s:plugin . '/plugin/lsp.vim') | finish | endif
let s:host = g:dotfiles_vim_lsp_host
let s:servers = {}
let s:restart = get(s:, 'restart', {})
call timer_stop(get(s:, 'completion_timer', -1))
for request in values(get(s:, 'outline_requests', {})) + values(get(s:, 'navigation', {}))
  if has_key(request, 'cancel') | call request.cancel() | endif
endfor
unlet! s:completion_timer
let s:outline_requests = {}
let s:navigation = {}
let s:diagnostics_visible = get(s:, 'diagnostics_visible', 1)
let s:python_paths = get(s:, 'python_paths', {})

" Keep updates asynchronous without vim-lsp's default one-second change queue.
let g:lsp_use_event_queue = 0
let g:lsp_async_completion = 1
let g:lsp_experimental_workspace_folders = 1
let g:lsp_diagnostics_pull_enabled = 1
let g:lsp_semantic_enabled = 1
let g:lsp_semantic_delay = 150
let g:lsp_diagnostics_virtual_text_enabled = 0
let g:lsp_diagnostics_float_cursor = 0
let g:lsp_diagnostics_echo_cursor = 0
let g:lsp_diagnostics_signs_delay = 0
let g:lsp_diagnostics_highlights_delay = 0
let g:lsp_diagnostics_signs_priority = 30
let g:lsp_diagnostics_signs_error = {'text': 'E'}
let g:lsp_diagnostics_signs_warning = {'text': 'W'}
let g:lsp_diagnostics_signs_information = {'text': 'I'}
let g:lsp_diagnostics_signs_hint = {'text': 'H'}
let g:lsp_document_highlight_enabled = 0
let g:lsp_document_code_action_signs_enabled = 0
let g:lsp_fold_enabled = 0
let g:lsp_signature_help_enabled = 0
let g:lsp_max_buffer_size = 2 * 1024 * 1024
" Re-sourcing .vimrc resets runtimepath, but the plugin's commands remain loaded.
" Keep their autoload files reachable even when plugin/lsp.vim need not run again.
if index(split(&runtimepath, ','), s:plugin) < 0
  execute 'set runtimepath^=' . escape(s:plugin, ' ,\')
endif
if !exists('g:lsp_loaded')
  runtime plugin/lsp.vim
endif

" Load only the completion pair beside vim-lsp; leave unrelated plugins excluded.
let s:completion_plugins = map(['asyncomplete.vim', 'asyncomplete-lsp.vim'],
      \ 'fnamemodify(s:plugin, ":h") . "/" . v:val')
let s:has_completion = filereadable(s:completion_plugins[0] . '/plugin/asyncomplete.vim')
      \ && filereadable(s:completion_plugins[1] . '/plugin/asyncomplete-lsp.vim')
if s:has_completion
  let g:asyncomplete_enable_for_all = 0
  let g:asyncomplete_auto_completeopt = 0
  " Vim 9 supports TextChangedP; no polling fallback is needed.
  let g:asyncomplete_change_manager = ['asyncomplete#utils#_on_change#textchangedp#init']
  for plugin in s:completion_plugins
    if index(split(&runtimepath, ','), plugin) < 0
      execute 'set runtimepath^=' . escape(plugin, ' ,\')
    endif
    execute 'source ' . fnameescape(plugin . '/plugin/' . fnamemodify(plugin, ':t'))
  endfor
endif

function! s:Command(command, info) abort
  return s:host.allows(bufnr('%')) && expand('%:p') !=# '' ? a:command : []
endfunction
function! s:Root(info) abort
  return lsp#utils#path_to_uri(s:host.root(bufnr('%')).root)
endfunction
function! s:Tool(name) abort
  let path = s:host.tool(a:name)
  if path !=# '' | return path | endif
  let data = empty($XDG_DATA_HOME) ? expand('~/.local/share') : $XDG_DATA_HOME
  let path = data . '/nvim-pack/mason/bin/' . a:name . (has('win32') ? '.cmd' : '')
  return executable(path) ? path : ''
endfunction
function! s:PythonSettings(info) abort
  let uri = lsp#get_server_root_uri(a:info.name)
  let root = uri ==# '' ? s:host.root(bufnr('%')).root : lsp#utils#uri_to_path(uri)
  let python = get(s:python_paths, root, '')
  for env in [$VIRTUAL_ENV, $CONDA_PREFIX, root . '/.venv', root . '/venv']
    if python !=# '' | break | endif
    if env ==# '' | continue | endif
    let candidate = env . (has('win32') ? '/Scripts/python.exe' : '/bin/python')
    if executable(candidate) | let python = candidate | break | endif
  endfor
  if python ==# '' | let python = exepath('python3') | endif
  return a:info.name ==# 'ty' ? {'ty': {'configuration': {'environment': {'python': python}}}}
        \ : {'python': {'pythonPath': python}}
endfunction
function! s:PythonAdd(selection, label, path) abort
  if a:path ==# '' || !executable(a:path) || index(a:selection.paths, a:path) >= 0 | return | endif
  call add(a:selection.paths, a:path)
  call add(a:selection.items, {'label': a:label . ': ' . a:path,
        \ 'action': function('<SID>PythonSelect', [a:selection, a:path, 0])})
endfunction
function! s:PythonSelect(selection, path, manual) abort
  if !s:host.allows(a:selection.buf) || !bufloaded(a:selection.buf)
        \ || getbufvar(a:selection.buf, '&filetype') !=# 'python'
        \ || s:host.root(a:selection.buf).root !=# a:selection.root | return | endif
  let path = a:path
  if a:manual
    let path = expand(input('Python executable or venv directory: ', '', 'file'))
    if path ==# '' | return | endif
    if path !~# '^/' && path !~# '^\a:[/\\]' | let path = a:selection.root . '/' . path | endif
    let path = simplify(path)
    if isdirectory(path) | let path .= has('win32') ? '/Scripts/python.exe' : '/bin/python' | endif
    if !executable(path) | echohl WarningMsg | echom 'Python executable not found: ' . path | echohl None | return | endif
  endif
  if get(s:python_paths, a:selection.root, '') !=# path
    if path ==# ''
      if has_key(s:python_paths, a:selection.root) | call remove(s:python_paths, a:selection.root) | endif
    else
      let s:python_paths[a:selection.root] = path
    endif
    call s:Restart()
  endif
  echom 'Python: ' . (path ==# '' ? 'automatic' : path)
endfunction
function! s:PythonConda(selection, output, limited) abort
  if a:limited || empty(popup_getpos(a:selection.picker)) | return | endif
  try
    let result = json_decode(a:output)
  catch
    return
  endtry
  if type(result) != v:t_dict || type(get(result, 'envs', 0)) != v:t_list | return | endif
  for env in result.envs
    if type(env) == v:t_string
      call s:PythonAdd(a:selection, 'Conda ' . fnamemodify(env, ':t'), env . (has('win32') ? '/Scripts/python.exe' : '/bin/python'))
    endif
  endfor
  call s:host.picker_items(a:selection.picker, a:selection.items)
endfunction
function! s:PythonEnvironment() abort
  if !s:host.allows(bufnr('%')) | return | endif
  if &filetype !=# 'python' | echom 'Open a Python file to select its environment' | return | endif
  let selection = {'buf': bufnr('%'), 'root': s:host.root(bufnr('%')).root, 'items': [], 'paths': []}
  call s:PythonAdd(selection, 'Selected', get(s:python_paths, selection.root, ''))
  let suffix = has('win32') ? '/Scripts/python.exe' : '/bin/python'
  for [label, env] in [['Project .venv', selection.root . '/.venv'], ['Project venv', selection.root . '/venv'],
        \ ['Active venv', $VIRTUAL_ENV], ['Active Conda', $CONDA_PREFIX]]
    if env !=# '' | call s:PythonAdd(selection, label, env . suffix) | endif
  endfor
  call s:PythonAdd(selection, 'PATH python', exepath('python'))
  call s:PythonAdd(selection, 'PATH python3', exepath('python3'))
  call add(selection.items, {'label': 'Enter Python path...', 'action': function('<SID>PythonSelect', [selection, '', 1])})
  call add(selection.items, {'label': 'Automatic (project settings / inherited PATH)', 'action': function('<SID>PythonSelect', [selection, '', 0])})
  let selection.picker = s:host.picker('Python environment: ' . fnamemodify(selection.root, ':t'),
        \ {'items': selection.items, 'cancel': function(s:host.cancel, ['vim-lsp-conda'])})
  let conda = exepath('conda')
  if conda ==# '' && executable($CONDA_EXE) | let conda = $CONDA_EXE | endif
  if selection.picker > 0 && conda !=# ''
    call s:host.run('vim-lsp-conda', [conda, 'env', 'list', '--json'], {'cwd': selection.root, 'quiet': 1},
          \ function('<SID>PythonConda', [selection]))
  endif
endfunction
function! s:Register() abort
  " Prefer the first installed server, checking PATH then existing Mason tools.
  let definitions = [
        \ [['clangd'], ['c','cpp','objc','objcpp','cuda']],
        \ [['mlir-lsp-server'], ['mlir']], [['starpls','server'], ['bzl']],
        \ [['buf','lsp','serve'], ['proto']], [['bash-language-server','start'], ['sh']],
        \ [[['neocmakelsp','stdio'], ['cmake-language-server']], ['cmake']],
        \ [['yaml-language-server','--stdio'], ['yaml']], [['texlab'], ['tex','plaintex']],
        \ [['rust-analyzer'], ['rust']], [['verible-verilog-ls'], ['verilog','systemverilog']],
        \ [[['ty','server'], ['pyright-langserver','--stdio']], ['python']],
        \ [['lua-language-server'], ['lua']],
        \ [['typescript-language-server','--stdio'], ['javascript','javascriptreact','typescript','typescriptreact']],
        \ [['vscode-html-language-server','--stdio'], ['html']],
        \ [['vscode-css-language-server','--stdio'], ['css','scss','less']],
        \ [['svelteserver','--stdio'], ['svelte']], [['graphql-lsp','server','-m','stream'], ['graphql']],
        \ [['prisma-language-server'], ['prisma']],
        \ ]
  for [commands, filetypes] in definitions
    for command in type(commands[0]) == v:t_list ? commands : [commands]
      let path = s:Tool(command[0])
      if path ==# '' | continue | endif
      let info = {'name': command[0], 'allowlist': filetypes,
            \ 'cmd': function('<SID>Command', [[path] + command[1:]]), 'root_uri': function('<SID>Root')}
      if index(filetypes, 'python') >= 0
        let info.workspace_config = function('<SID>PythonSettings')
      elseif command[0] ==# 'typescript-language-server'
        let tsserver = s:Tool('tsserver')
        if tsserver !=# '' | let info.initialization_options = {'tsserver': {'fallbackPath': tsserver}} | endif
      elseif command[0] ==# 'lua-language-server'
        let info.workspace_config = {'Lua': {'diagnostics': {'globals': ['vim']}, 'completion': {'callSnippet': 'Replace'}}}
      endif
      let s:servers[info.name] = info
      let info.capabilities = lsp#default_get_supported_capabilities(info)
      let info.capabilities.textDocument.publishDiagnostics.tagSupport = {'valueSet': [1]}
      " vim-lsp handles diagnostic refresh requests, but omits this capability.
      let info.capabilities.workspace.diagnostics = {'refreshSupport': v:true}
      " vim-lsp's delta splice retains the old array when an edit starts at zero.
      " Advertise full tokens only; do not mutate server capabilities or token IDs.
      let info.capabilities.textDocument.semanticTokens.requests.full = v:true
      if index(lsp#get_server_names(), info.name) < 0
        call lsp#register_server(deepcopy(info))
      endif
      break
    endfor
  endfor
endfunction
function! s:Names(buf) abort
  let ft = getbufvar(a:buf, '&filetype')
  let selected = getbufvar(a:buf, 'nopack_lsp_backend', {})
  if get(selected, 'filetype', -1) !=# ft
    let names = filter(keys(s:servers), 'index(s:servers[v:val].allowlist, ft) >= 0')
    let selected = {'filetype': ft, 'names': names}
    call setbufvar(a:buf, 'nopack_lsp_backend', selected)
  endif
  return selected.names
endfunction
function! s:Owns(buf) abort
  return !empty(s:Names(a:buf))
endfunction
function! s:Run(command) abort
  if s:host.allows(bufnr('%')) && s:Owns(bufnr('%')) | execute a:command | endif
endfunction
function! s:Definition() abort
  call s:Navigate('definition', 0)
endfunction
function! s:CancelNavigation(buf) abort
  if has_key(s:navigation, a:buf)
    let request = remove(s:navigation, a:buf)
    if has_key(request, 'cancel') | call request.cancel() | endif
  endif
endfunction
function! s:LocationsReady(request, data) abort
  let buf = a:request.context.buf
  if get(s:navigation, buf, {}) isnot a:request | return | endif
  call remove(s:navigation, buf)
  if !s:host.unchanged(a:request.context) || win_getid() != a:request.win
        \ || bufnr('%') != buf || getcurpos()[1:2] != a:request.cursor | return | endif
  let response = get(a:data, 'response', {})
  if has_key(response, 'error') | return | endif
  let result = get(response, 'result', v:null)
  let location = type(result) == v:t_list ? (len(result) == 1 ? result[0] : {}) : (type(result) == v:t_dict ? result : {})
  let uri = get(location, 'targetUri', get(location, 'uri', ''))
  if !a:request.list && lsp#utils#is_file_uri(uri)
    " A direct jump needs no preview text or end-position conversion.
    let range = get(location, 'targetSelectionRange', get(location, 'range', {}))
    let items = [{'filename': lsp#utils#uri_to_path(uri), 'position': range.start}]
  else
    let items = lsp#utils#location#_lsp_to_vim_list(result)
  endif
  if empty(items) | echo 'No locations found' | return | endif
  call settagstack(a:request.win, {'items': [{'tagname': expand('<cword>'), 'from': [buf, line('.'), col('.'), 0]}]}, 't')
  if len(items) == 1 && !a:request.list
    let item = items[0]
    let target = bufadd(item.filename)
    normal! m'
    " Reuse an editor in this tab, excluding previews and utility windows.
    if target != buf
      for win in win_findbuf(target)
        if s:host.editor(win) | call win_gotoid(win) | break | endif
      endfor
    endif
    call setbufvar(target, '&buflisted', 1)
    if target != bufnr('%')
      if &modified && !&hidden
        execute (&splitbelow ? 'rightbelow ' : 'leftabove ') . 'sbuffer ' . target
      else
        execute 'buffer ' . target
      endif
    endif
    let [row, col] = lsp#utils#position#lsp_to_vim(target, item.position)
    call cursor(row, col)
    normal! zvzz
  else
    for item in items | let item.label = fnamemodify(item.filename, ':~:.') . ':' . item.lnum . ' ' . item.text | endfor
    call s:host.picker('LSP locations', {'items': items})
  endif
endfunction
function! s:Navigate(method, list) abort
  let buf = bufnr('%')
  if !s:host.allows(buf) | return | endif
  let pending = get(s:navigation, buf, {})
  if !empty(pending) && pending.method ==# a:method && pending.list == a:list && pending.win == win_getid()
        \ && pending.cursor == getcurpos()[1:2] && s:host.unchanged(pending.context) | return | endif
  call s:CancelNavigation(buf)
  let capability = 'lsp#capabilities#has_' . (a:method ==# 'typeDefinition' ? 'type_definition' : a:method) . '_provider'
  let names = filter(copy(s:Names(buf)), 'lsp#get_server_status(v:val) ==# "running" && call(function(capability), [v:val])')
  if empty(names) | echo 'LSP is not ready for this operation' | return | endif
  let request = {'context': s:host.context(buf), 'win': win_getid(), 'cursor': getcurpos()[1:2], 'method': a:method, 'list': a:list}
  let params = {'textDocument': lsp#get_text_document_identifier(), 'position': lsp#get_position()}
  if a:method ==# 'references' | let params.context = {'includeDeclaration': v:true} | endif
  let s:navigation[buf] = request
  let request.cancel = lsp#callbag#pipe(lsp#request(names[0], {'method': 'textDocument/' . a:method, 'bufnr': buf, 'params': params}),
        \ lsp#callbag#subscribe({'next': function('<SID>LocationsReady', [request])}))
endfunction
function! s:FormatName(buf) abort
  return join(filter(copy(s:Names(a:buf)), 'lsp#get_server_status(v:val) ==# "running" && lsp#capabilities#has_document_formatting_provider(v:val)'), ',')
endfunction
function! s:Format() abort
  let name = s:FormatName(bufnr('%'))
  if name ==# '' | return 0 | endif
  call lsp#send_request(split(name, ',')[0], {'method': 'textDocument/formatting', 'bufnr': bufnr('%'),
        \ 'params': {'textDocument': lsp#get_text_document_identifier(), 'options': {'tabSize': shiftwidth(), 'insertSpaces': &expandtab ? v:true : v:false}},
        \ 'on_notification': function('<SID>FormatReady', [s:host.context(bufnr('%'))])})
  return 1
endfunction
function! s:FormatReady(context, data) abort
  let response = get(a:data, 'response', {})
  if s:host.allows(a:context.buf) && s:host.unchanged(a:context) && getbufvar(a:context.buf, '&modifiable')
        \ && !has_key(response, 'error') && type(get(response, 'result', v:null)) == v:t_list
    call lsp#utils#text_edit#apply_text_edits(lsp#utils#path_to_uri(a:context.file), response.result)
  endif
endfunction
function! s:Status(...) abort
  if !s:Owns(bufnr('%')) | unlet! b:nopack_lsp_status b:nopack_diagnostic_status | return | endif
  let previous = [get(b:, 'nopack_lsp_status', ''), get(b:, 'nopack_diagnostic_status', '')]
  let names = s:Names(bufnr('%'))
  let active = filter(copy(names), 'lsp#get_server_status(v:val) ==# "running"')
  let b:nopack_lsp_status = '[LSP: ' . join(empty(active) ? names : active, ',') . (empty(active) ? ' ...' : '') . ']'
  let counts = lsp#get_buffer_diagnostics_counts()
  let b:nopack_diagnostic_status = ''
  for [kind, letter] in [['error','E'], ['warning','W'], ['hint','H']]
    let amount = get(counts, kind, 0)
    if amount > 0
      let group = letter ==# 'H' ? 'NopackStatus' : 'VimLspStatus' . letter
      let b:nopack_diagnostic_status .= '%#' . group . '#' . letter . ': ' . amount . '%#NopackStatus# '
    endif
  endfor
  let servers = map(copy(names), '[v:val, lsp#get_server_status(v:val)]')
  if get(b:, 'nopack_lsp_tool_servers', []) !=# servers
    let b:nopack_lsp_tool_servers = servers
    call s:host.tool_status(bufnr('%'))
  endif
  if a:0 && a:1 && previous !=# [b:nopack_lsp_status, b:nopack_diagnostic_status] | redrawstatus | endif
endfunction
function! s:Highlights() abort
  highlight! link VimLspUnused Comment
  let background = synIDattr(synIDtrans(hlID('NopackStatus')), 'bg#', 'gui')
  if background ==# '' | let background = 'NONE' | endif
  let status = synIDtrans(hlID('StatusLine'))
  let terminal_background = synIDattr(status, synIDattr(status, 'reverse', 'cterm') ==# '1' ? 'fg' : 'bg', 'cterm')
  if terminal_background ==# '' | let terminal_background = 'NONE' | endif
  for [letter, kind, color, terminal] in [['E','Error','#ff0000',9], ['W','Warning','#ffd700',220], ['H','Hint','#00bfff',12], ['I','Information','#00d7ff',14]]
    execute 'highlight VimLsp' . letter . ' gui=bold cterm=bold guifg=' . color . ' guibg=NONE ctermfg=' . terminal . ' ctermbg=NONE'
    execute 'highlight! link Lsp' . kind . 'Text VimLsp' . letter
    execute 'highlight Lsp' . kind . 'Highlight gui=undercurl cterm=underline guifg=NONE guibg=NONE guisp=' . color . ' ctermfg=NONE ctermbg=NONE'
    if letter ==# 'E' || letter ==# 'W'
      execute 'highlight VimLspStatus' . letter . ' gui=bold cterm=bold guifg=' . color . ' guibg=' . background
            \ . ' ctermfg=' . terminal . ' ctermbg=' . terminal_background
    endif
  endfor
endfunction
function! s:Unused() abort
  let buf = bufnr('%')
  if !s:Owns(buf) | return | endif
  let diagnostics = []
  if s:diagnostics_visible && s:host.allows(buf)
    for response in values(lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_server_for_uri(lsp#get_text_document_identifier().uri))
      call extend(diagnostics, filter(copy(get(response.params, 'diagnostics', [])), 'index(get(v:val, "tags", []), 1) >= 0'))
    endfor
  endif
  let snapshot = [expand('%:p'), &filetype, b:changedtick, diagnostics]
  if get(b:, 'nopack_unused_snapshot', []) ==# snapshot | return | endif
  let b:nopack_unused_snapshot = snapshot
  if empty(prop_type_get('VimLspUnused', {'bufnr': buf}))
    call prop_type_add('VimLspUnused', {'bufnr': buf, 'highlight': 'VimLspUnused', 'priority': 5, 'combine': 0})
  else
    call prop_remove({'bufnr': buf, 'type': 'VimLspUnused', 'all': 1}, 1, line('$'))
  endif
  for diagnostic in diagnostics
    let [first, col] = lsp#utils#position#lsp_to_vim(buf, diagnostic.range.start)
    let [last, endcol] = lsp#utils#position#lsp_to_vim(buf, diagnostic.range.end)
    if first > 0 && last <= line('$') && (last > first || endcol > col)
      call prop_add(first, col, {'bufnr': buf, 'type': 'VimLspUnused', 'end_lnum': last, 'end_col': endcol})
    endif
  endfor
endfunction
function! s:CompletionBuffer() abort
  if !s:has_completion | return | endif
  let enabled = s:host.allows(bufnr('%')) && s:Owns(bufnr('%'))
  if enabled != get(b:, 'asyncomplete_enable', 0)
    if enabled | call asyncomplete#enable_for_buffer()
    else | call asyncomplete#disable_for_buffer() | endif
  endif
endfunction
function! s:Buffer() abort
  call s:CompletionBuffer()
  if !s:Owns(bufnr('%'))
    if !empty(prop_type_get('VimLspUnused', {'bufnr': bufnr('%')}))
      call prop_remove({'type': 'VimLspUnused', 'all': 1}, 1, line('$'))
    endif
    unlet! b:nopack_unused_snapshot
    if exists('b:nopack_lsp_mapped')
      for key in b:nopack_lsp_mapped
        let mapping = maparg(key, 'n', 0, 1)
        if get(mapping, 'sid', 0) == str2nr(matchstr(expand('<SID>'), '\d\+'))
          execute 'silent! nunmap <buffer> ' . key
        endif
      endfor
      if &l:omnifunc ==# 'lsp#complete' | setlocal omnifunc= | endif
      if get(maparg('<leader>la', 'x', 0, 1), 'sid', 0) == str2nr(matchstr(expand('<SID>'), '\d\+'))
        silent! xunmap <buffer> <leader>la
      endif
      unlet b:nopack_lsp_mapped
    endif
    unlet! b:nopack_lsp_status b:nopack_diagnostic_status
    return
  endif
  if !s:host.allows(bufnr('%')) | return | endif
  setlocal omnifunc=lsp#complete
  if exists('+autocomplete') | setlocal noautocomplete | endif
  if !exists('b:nopack_lsp_mapped')
    let b:nopack_lsp_mapped = []
    for [key, command] in [['K','LspHover'],
        \ ['<leader>lr','LspRename'], ['<leader>la','LspCodeAction'],
        \ ['[d','LspPreviousDiagnostic'], [']d','LspNextDiagnostic']]
      execute 'nnoremap <silent><buffer> ' . key . ' <Cmd>call <SID>Run(' . string(command) . ')<CR>'
      call add(b:nopack_lsp_mapped, key)
    endfor
    for [key, method, list] in [['gr','references',0], ['gR','references',1], ['gD','declaration',0], ['gi','implementation',1], ['gt','typeDefinition',1]]
      execute 'nnoremap <silent><buffer> ' . key . ' <Cmd>call <SID>Navigate(' . string(method) . ',' . list . ')<CR>'
      call add(b:nopack_lsp_mapped, key)
    endfor
    xnoremap <silent><buffer> <leader>la :<C-u>call <SID>Run("'<,'>LspCodeAction")<CR>
  endif
  call s:Status()
  call s:Unused()
endfunction
function! s:SyncInsert() abort
  call s:CompletionBuffer()
  " Cached completion candidates must not stop document changes reaching the server.
  if s:host.allows(bufnr('%')) && s:Owns(bufnr('%'))
    call lsp#ensure_flush_all(bufnr('%'), s:Names(bufnr('%')))
  endif
endfunction
function! s:Start(name) abort
  call lsp#register_server(deepcopy(s:servers[a:name]))
  for buf in getbufinfo({'bufloaded': 1})
    if s:host.allows(buf.bufnr) && index(s:Names(buf.bufnr), a:name) >= 0
      call setbufvar(buf.bufnr, 'lsp_semantic_previous_result_id', '')
      call lsp#ensure_flush_all(buf.bufnr, [a:name])
    endif
  endfor
  if s:host.allows(bufnr('%')) && s:Owns(bufnr('%')) | call lsp#activate() | endif
endfunction
function! s:Restart() abort
  if !s:host.allows(bufnr('%')) | return | endif
  let names = s:Names(bufnr('%'))
  if empty(names) | echom 'No configured LSP for this filetype' | return | endif
  for name in names
    if has_key(s:restart, name) | continue | endif
    " Initialization can fail while the server process is still alive.
    if index(['running','starting','failed'], lsp#get_server_status(name)) >= 0
      let s:restart[name] = 1
      call lsp#stop_server(name)
    else
      call s:Start(name)
    endif
  endfor
endfunction
function! s:Exited() abort
  for name in keys(copy(s:restart))
    if index(['exited','not running'], lsp#get_server_status(name)) >= 0
      call remove(s:restart, name)
      call s:Start(name)
    endif
  endfor
  call s:Status(1)
endfunction
function! s:DiagnosticItems(all) abort
  let items = []
  let grouped = lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_uri_and_server()
  for [uri, servers] in items(grouped)
    let file = lsp#utils#uri_to_path(uri)
    if !a:all && file !=# expand('%:p') | continue | endif
    for response in values(servers)
      for diagnostic in get(response.params, 'diagnostics', [])
        let severity = get(diagnostic, 'severity', 1)
        let letter = ['E','W','I','H'][max([0, min([3, severity - 1])])]
        let row = diagnostic.range.start.line + 1
        call add(items, {'filename': file, 'lnum': row,
              \ 'col': lsp#utils#position#lsp_to_vim(file, diagnostic.range.start)[1],
              \ 'severity': severity, 'text': diagnostic.message,
              \ 'label': letter . ' ' . fnamemodify(file, ':~:.') . ':' . row . ' ' . substitute(diagnostic.message, '\n', ' ', 'g')})
      endfor
    endfor
  endfor
  return sort(items, {a,b -> a.severity == b.severity ? a.filename ==# b.filename ? a.lnum - b.lnum : a.filename ># b.filename ? 1 : -1 : a.severity - b.severity})
endfunction
function! s:DiagnosticPaint(state, item) abort
  let id = a:state.id
  if id == 0 || empty(popup_getpos(id)) | return | endif
  let buf = winbufnr(id)
  for letter in ['E','W','I','H']
    if empty(prop_type_get('VimLsp' . letter, {'bufnr': buf}))
      call prop_type_add('VimLsp' . letter, {'bufnr': buf, 'highlight': 'VimLsp' . letter})
    endif
  endfor
  call prop_remove({'bufnr': buf, 'types': ['VimLspE','VimLspW','VimLspI','VimLspH'], 'all': 1}, 1, len(getbufline(buf, 1, '$')))
  let row = 3
  for text in getbufline(buf, 3, '$')
    if text =~# '^[EWIH] '
      call prop_add(row, 1, {'bufnr': buf, 'type': 'VimLsp' . text[0], 'length': 1})
    endif
    let row += 1
  endfor
endfunction
function! s:Diagnostics(all) abort
  let state = {'id': 0}
  let state.id = s:host.picker('Diagnostics', {'items': s:DiagnosticItems(a:all),
        \ 'highlight': function('<SID>DiagnosticPaint', [state])})
  call s:DiagnosticPaint(state, {})
endfunction
function! s:LineDiagnostic() abort
  let diagnostics = filter(s:DiagnosticItems(0), 'v:val.lnum == line(".")')
  if empty(diagnostics) | return | endif
  let lines = split(join(map(diagnostics, 'v:val.text'), "\n\n"), "\n", 1)
  call popup_create(lines, {'pos': 'botleft', 'line': 'cursor-1',
        \ 'col': 'cursor', 'border': [1], 'padding': [0,1,0,1], 'maxwidth': &columns * 4 / 5,
        \ 'moved': 'any', 'mapping': 0, 'filter': 'popup_filter_menu'})
endfunction
function! s:ToggleDiagnostics() abort
  let s:diagnostics_visible = !s:diagnostics_visible
  for buf in getbufinfo({'bufloaded': 1})
    if s:diagnostics_visible | call lsp#enable_diagnostics_for_buffer(buf.bufnr)
    else | call lsp#disable_diagnostics_for_buffer(buf.bufnr) | endif
  endfor
endfunction
function! s:Symbols(symbols, file, depth, items) abort
  let kinds = ['file','module','namespace','package','class','method','property','field','constructor','enum','interface','function','variable','constant','string','number','boolean','array','object','key','null','enum member','struct','event','operator','type parameter']
  for symbol in a:symbols
    let range = get(symbol, 'selectionRange', get(symbol, 'range', get(get(symbol, 'location', {}), 'range', {})))
    if empty(range) | continue | endif
    let kind = get(kinds, get(symbol, 'kind', 1) - 1, 'symbol')
    let label = toupper(strpart(kind, 0, 1)) . strpart(kind, 1)
    call add(a:items, {'label': repeat('  ', a:depth) . label . ' ' . symbol.name,
          \ 'filename': a:file, 'lnum': range.start.line + 1, 'kind': kind,
          \ 'name_col': a:depth * 2 + strlen(label) + 2, 'name_length': strlen(symbol.name)})
    call s:Symbols(get(symbol, 'children', []), a:file, a:depth + 1, a:items)
  endfor
endfunction
function! s:SymbolsReady(request, response) abort
  let context = a:request.context
  if get(s:outline_requests, context.buf, {}) isnot a:request | return | endif
  call remove(s:outline_requests, context.buf)
  if !s:host.unchanged(context) || win_id2win(a:request.win) == 0 || winbufnr(a:request.win) != context.buf
        \ || (a:request.open && win_getid() != a:request.win) | return | endif
  let sidebar = get(t:, 'nopack_outline_win', 0)
  if !a:request.open && (win_id2win(sidebar) == 0 || get(getbufvar(winbufnr(sidebar), 'nopack_outline', {}), 'source', -1) != context.buf) | return | endif
  let response = get(a:response, 'response', {})
  if has_key(response, 'error') | return | endif
  let items = []
  let symbols = get(response, 'result', [])
  call s:Symbols(type(symbols) == v:t_list ? symbols : [], context.file, 0, items)
  call sort(items, {a,b -> a.lnum - b.lnum})
  call s:host.outline(context.buf, a:request.win, items, 1)
endfunction
function! s:Outline(buf, win, open) abort
  if !s:host.allows(a:buf) | return | endif
  let pending = get(s:outline_requests, a:buf, {})
  if !empty(pending) && pending.win == a:win && s:host.unchanged(pending.context)
        \ && (!a:open || pending.open) | return | endif
  call s:CancelOutline(a:buf)
  let names = filter(copy(s:Names(a:buf)), 'lsp#capabilities#has_document_symbol_provider(v:val)')
  if empty(names) | return | endif
  let request = {'method': 'textDocument/documentSymbol', 'bufnr': a:buf,
        \ 'params': {'textDocument': lsp#get_text_document_identifier(a:buf)}}
  let pending = {'context': s:host.context(a:buf), 'win': a:win, 'open': a:open}
  let s:outline_requests[a:buf] = pending
  let pending.cancel = lsp#callbag#pipe(lsp#request(names[0], request),
        \ lsp#callbag#subscribe({'next': function('<SID>SymbolsReady', [pending])}))
endfunction
function! s:RefreshOutline() abort
  let sidebar = get(t:, 'nopack_outline_win', 0)
  if win_id2win(sidebar) == 0 | return | endif
  let outline = getbufvar(winbufnr(sidebar), 'nopack_outline', {})
  if !empty(outline) && get(outline, 'live', 0) && s:Owns(outline.source) && !s:host.unchanged(outline.context)
    call s:Outline(outline.source, outline.target, 0)
  endif
endfunction
function! s:CancelOutline(buf) abort
  if has_key(s:outline_requests, a:buf)
    let request = remove(s:outline_requests, a:buf)
    if has_key(request, 'cancel') | call request.cancel() | endif
  endif
endfunction
function! s:FileSaved() abort
  if !s:host.allows(bufnr('%')) | return | endif
  for name in s:Names(bufnr('%'))
    if lsp#get_server_status(name) !=# 'running' | continue | endif
    call lsp#callbag#pipe(lsp#notification(name, {'method': 'workspace/didChangeWatchedFiles',
          \ 'params': {'changes': [{'uri': lsp#utils#get_buffer_uri(), 'type': get(b:, 'nopack_lsp_file_existed', 1) ? 2 : 1}]}}),
          \ lsp#callbag#subscribe())
  endfor
endfunction

call extend(s:host.adapter, {'owns': function('<SID>Owns'), 'definition': function('<SID>Definition'),
      \ 'outline': function('<SID>Outline'), 'format': function('<SID>Format'), 'format_name': function('<SID>FormatName')})
call extend(s:host.labels, {'lv': 'Select Python environment', 'ls': 'Restart LSP', 'li': 'LSP status', 'lr': 'Rename symbol',
      \ 'la': 'Code action', 'ld': 'Line diagnostic', 'lD': 'Buffer diagnostics',
      \ 'sd': 'Workspace diagnostics', 'lt': 'Toggle diagnostics'})
call s:Highlights()
call s:Register()
if s:has_completion
  " Also attach completion when this module is reloaded into an existing LSP session.
  doautocmd <nomodeline> asyncomplete_lsp User lsp_server_init
endif
augroup DotfilesVimLsp
  autocmd!
  autocmd User lsp_buffer_enabled call <SID>Buffer()
  autocmd User lsp_server_init,lsp_diagnostics_updated call <SID>Status(1)
  autocmd User lsp_diagnostics_updated call <SID>Unused()
  autocmd User lsp_server_exit call <SID>Exited()
  autocmd FileType,BufEnter * call <SID>Buffer()
  autocmd TextChangedI * call <SID>SyncInsert()
  autocmd TextChanged,BufWritePost * call <SID>RefreshOutline()
  autocmd BufWritePre * let b:nopack_lsp_file_existed = filereadable(expand('%:p'))
  autocmd BufWritePost,FileChangedShellPost * call <SID>FileSaved()
  autocmd BufUnload,BufWipeout * call <SID>CancelOutline(str2nr(expand('<abuf>')))
  autocmd BufUnload,BufWipeout * call <SID>CancelNavigation(str2nr(expand('<abuf>')))
  autocmd ColorScheme * call <SID>Highlights()
augroup END
command! LspRestart call <SID>Restart()
nnoremap <silent> <leader>ls <Cmd>LspRestart<CR>
nnoremap <silent> <leader>lv <Cmd>call <SID>PythonEnvironment()<CR>
nnoremap <silent> <leader>li <Cmd>LspStatus<CR>
nnoremap <silent> <leader>ld <Cmd>call <SID>LineDiagnostic()<CR>
nnoremap <silent> <leader>lD <Cmd>call <SID>Diagnostics(0)<CR>
nnoremap <silent> <leader>sd <Cmd>call <SID>Diagnostics(1)<CR>
nnoremap <silent> <leader>lt <Cmd>call <SID>ToggleDiagnostics()<CR>
call s:Buffer()
