" Standalone nopack config: Vim 9.0+ with +timers/+cryptv, no third-party plugins/downloads.
" Try: vim -Nu /path/to/.vimrc
" Only bundled runtime plugins (netrw, matchit, etc.) are loaded.

if v:version < 900
  echoerr 'This vimrc requires Vim 9.0 or newer'
  finish
endif
if !has('timers') || !has('job') || !has('channel') || !has('popupwin') || !exists('*sha256')
  echoerr 'This vimrc requires Vim +timers, +job, +channel, +popupwin and +cryptv support'
  finish
endif

set nocompatible
" Servers may use LANG=C; decode UI characters as UTF-8 before reading them.
set encoding=utf-8
scriptencoding utf-8

let s:save_cpo = &cpoptions
set cpoptions&vim
let s:vimrc_path = resolve(expand('<sfile>:p'))

let &runtimepath = $VIMRUNTIME
let &packpath = $VIMRUNTIME

" =========================================
" ============== CORE OPTIONS =============
" =========================================
let s:nopack_data = exists('$VIM_NOPACK_DATA') && $VIM_NOPACK_DATA !=# ''
      \ ? expand($VIM_NOPACK_DATA) : expand('~/.vim/nopack')
" Preserve the former custom data path and existing sessions/undo files.
if empty($VIM_NOPACK_DATA) && !empty($VIM_OFFLINE_DATA)
  let s:nopack_data = expand($VIM_OFFLINE_DATA)
elseif empty($VIM_NOPACK_DATA) && isdirectory(expand('~/.vim/offline')) && !isdirectory(s:nopack_data)
  if rename(expand('~/.vim/offline'), s:nopack_data) != 0
    let s:nopack_data = expand('~/.vim/offline')
  endif
endif
set nobackup
" Editing defaults that Neovim supplies even without an init.lua.
set autoindent autoread
set backspace=indent,eol,start
set incsearch nojoinspaces nostartofline smarttab
set nrformats-=octal
set formatoptions+=j
set sidescroll=1
set ttimeout ttimeoutlen=50
set history=10000
" Keep Vim's registers authoritative; mirror yanks to the desktop or SSH client.
let s:ssh = !empty($SSH_TTY) || !empty($SSH_CONNECTION)
let s:desktop_clipboard = !s:ssh && has('clipboard') && (has('mac') || has('win32') || !empty($DISPLAY))
set clipboard=
set nolazyredraw
set cmdheight=1
set completeopt=menuone,noselect
set complete=.,w,b,t
set conceallevel=0
set fileencoding=utf-8
set foldmethod=manual
set foldexpr=
set guifont=monospace:h17
set hidden
set hlsearch
set ignorecase
set tagcase=match
set mouse=a
set pumheight=10
set showmode
set showtabline=2
set smartcase
set nosmartindent
set splitbelow
set splitright
set noswapfile
if exists('+termguicolors')
  set termguicolors
endif
" Terminal Vim uses these mode sequences instead of Neovim's 'guicursor'.
if has('cursorshape') && !has('gui_running') && &term !=# 'dumb'
  let &t_SI = "\e[6 q" " Insert: steady bar
  let &t_SR = "\e[4 q" " Replace: steady underline
  let &t_EI = "\e[2 q" " Normal: steady block
endif
set title
if exists('+undodir') && exists('+undofile')
  call mkdir(s:nopack_data . '/undo', 'p')
  let &undodir = s:nopack_data . '/undo'
  set undofile
endif
set updatetime=250
set nowritebackup
set expandtab
set shiftwidth=4
set tabstop=4
set cursorline
if exists("+cursorlineopt")
  set cursorlineopt=line,number
endif
set cursorcolumn
set number
set norelativenumber
set numberwidth=2
if exists('+signcolumn')
  set signcolumn=yes
endif
set wrap
set nospell
set spelllang=en
set background=dark
set scrolloff=5
set synmaxcol=300
set sidescrolloff=8
set ttyfast
let &sessionoptions = 'buffers,curdir,folds,help,tabpages,winsize,winpos'
      \ . (has('terminal') ? ',terminal' : '')
set shortmess+=c
set whichwrap+=<,>,[,],h,l
set iskeyword+=-
let &path = '.,'
set wildmenu
set wildmode=longest:full,full
set wildignore+=*/.git/*,*/node_modules/*,*/__pycache__/*

" Shared buffer policy: source operations survive large-file protection.
function! s:IsSource(buf) abort
  return bufexists(a:buf) && getbufvar(a:buf, '&buftype') ==# ''
        \ && getbufvar(a:buf, '&filetype') !=# 'netrw'
endfunction
function! s:IsEditorWindow(winid) abort
  return win_id2win(a:winid) > 0 && s:IsSource(winbufnr(a:winid))
        \ && !getwinvar(a:winid, '&previewwindow')
endfunction
function! s:BufferAllows(buf) abort
  return bufloaded(a:buf) && s:IsSource(a:buf) && !getbufvar(a:buf, 'nopack_large_file', 0)
endfunction
" Results belong to one loaded source identity, not just its buffer number.
function! s:SourceContext(buf) abort
  return {'buf': a:buf, 'file': fnamemodify(bufname(a:buf), ':p'),
        \ 'filetype': getbufvar(a:buf, '&filetype'), 'tick': getbufvar(a:buf, 'changedtick', -1)}
endfunction
function! s:SourceUnchanged(context) abort
  let buf = a:context.buf
  return bufloaded(buf) && s:IsSource(buf)
        \ && fnamemodify(bufname(buf), ':p') ==# a:context.file
        \ && getbufvar(buf, '&filetype') ==# a:context.filetype
        \ && getbufvar(buf, 'changedtick', -1) == a:context.tick
endfunction

function! s:BufferByteSize(buf, limit) abort
  if a:buf == bufnr('%')
    return line2byte(line('$') + 1) - 1
  endif
  let size = 0
  let first = 1
  while size <= a:limit
    let lines = getbufline(a:buf, first, first + 127)
    if empty(lines) | break | endif
    let size += strlen(join(lines, "\n")) + 1
    let first += len(lines)
  endwhile
  return size
endfunction

function! s:RestrictBuffer(buf) abort
  if getbufvar(a:buf, 'nopack_large_file', 0) | return | endif
  call setbufvar(a:buf, 'nopack_large_file', 1)
  let s:restricted_buf = a:buf
  try
    doautocmd <nomodeline> User NopackBufferRestricted
  finally
    unlet s:restricted_buf
  endtry
endfunction

" Restore only affected windows; do not rewrite window options during redraw.
function! s:ShowLineNumbers(winid) abort
  let buf = winbufnr(a:winid)
  if buf > 0 && (s:IsSource(buf) || getbufvar(buf, '&filetype') ==# 'netrw')
    if !getwinvar(a:winid, '&number')
      call setwinvar(a:winid, '&number', 1)
    endif
    if getwinvar(a:winid, '&relativenumber')
      call setwinvar(a:winid, '&relativenumber', 0)
    endif
  endif
endfunction

function! s:RestoreBufferNumbers(buf, timer) abort
  for winid in win_findbuf(a:buf)
    call s:ShowLineNumbers(winid)
  endfor
endfunction

function! s:RestoreAllNumbers() abort
  for info in getwininfo()
    call s:ShowLineNumbers(info.winid)
  endfor
endfunction

augroup NopackLineNumbers
  autocmd!
  autocmd BufWinEnter,WinEnter * call <SID>ShowLineNumbers(win_getid())
  autocmd FileType * call timer_start(0, function('<SID>RestoreBufferNumbers', [str2nr(expand('<abuf>'))]))
  autocmd VimEnter * call <SID>RestoreAllNumbers()
  if exists('##SessionLoadPost')
    autocmd SessionLoadPost * call <SID>RestoreAllNumbers()
  endif
augroup END

" =========================================
" ================ LEADER =================
" =========================================
let mapleader = ' '

" =========================================
" ============== KEYMAPS: BASE ============
" =========================================
inoremap <silent> jk <Esc>
inoremap <C-u> <C-g>u<C-u>
inoremap <C-w> <C-g>u<C-w>
nnoremap <silent> <Esc> :nohlsearch<CR>
nnoremap <silent> + <C-a>
nnoremap <silent> - <C-x>
if has('terminal')
  tnoremap <Esc><Esc> <C-W>N
endif

inoremap <silent> , ,<C-g>u
inoremap <silent> . .<C-g>u
inoremap <silent> ; ;<C-g>u
inoremap <silent> < <<C-g>u

inoremap <silent> <A-Up> <C-\><C-N><C-w>k
inoremap <silent> <A-Down> <C-\><C-N><C-w>j
inoremap <silent> <A-Left> <C-\><C-N><C-w>h
inoremap <silent> <A-Right> <C-\><C-N><C-w>l

inoremap <silent> <A-j> <Esc>:move .+1<CR>==gi
inoremap <silent> <A-k> <Esc>:move .-2<CR>==gi
nnoremap <silent> <A-j> :move .+1<CR>==
nnoremap <silent> <A-k> :move .-2<CR>==
xnoremap <silent> <A-j> :move '>+1<CR>gv-gv
xnoremap <silent> <A-k> :move '<-2<CR>gv-gv

inoremap <silent> <C-s> <Esc>:write<CR>
nnoremap <silent> <C-s> :write<CR>

nnoremap <silent> <C-h> <C-w>h
nnoremap <silent> <C-j> <C-w>j
nnoremap <silent> <C-k> <C-w>k
nnoremap <silent> <C-l> <C-w>l
if has('terminal')
  tnoremap <silent> <C-h> <C-W>N<C-w>h
  tnoremap <silent> <C-j> <C-W>N<C-w>j
  tnoremap <silent> <C-k> <C-W>N<C-w>k
  tnoremap <silent> <C-l> <C-W>N<C-w>l
endif

nnoremap <silent> <S-Up> :resize -5<CR>
nnoremap <silent> <S-Down> :resize +5<CR>
nnoremap <silent> <S-Left> :vertical resize -5<CR>
nnoremap <silent> <S-Right> :vertical resize +5<CR>
if has('terminal')
  tnoremap <silent> <S-Up> <C-W>:resize -5<CR>
  tnoremap <silent> <S-Down> <C-W>:resize +5<CR>
  tnoremap <silent> <S-Left> <C-W>:vertical resize -5<CR>
  tnoremap <silent> <S-Right> <C-W>:vertical resize +5<CR>
endif

nnoremap <silent> x "_x
nnoremap Y y$
nnoremap & :&&<CR>
" Vim exposes the active recording register, but not Neovim's reg_recorded().
let s:last_recorded = ''
function! s:MacroKey(key) abort
  if a:key ==# 'q'
    if !empty(reg_recording()) | let s:last_recorded = tolower(reg_recording()) | endif
    return 'q'
  endif
  if empty(s:last_recorded) | return "\<Esc>" | endif
  return mode() ==# 'V' ? ':normal! @' . s:last_recorded . "\<CR>" : '@' . s:last_recorded
endfunction
nnoremap <expr> q <SID>MacroKey('q')
nnoremap <expr> Q <SID>MacroKey('Q')
xnoremap <silent><expr> Q <SID>MacroKey('Q')
xnoremap <silent><expr> @ mode() ==# 'V' ? ':normal! @' . getcharstr() . '<CR>' : '@'
" Native Visual P preserves the yank and the selection boundary, including EOL.
xnoremap <silent> p P
xnoremap <silent> P P
nnoremap <silent> n nzzzv
nnoremap <silent> N Nzzzv
nnoremap <silent> <leader>w :windo diffthis<CR>
nnoremap <silent> <leader>a ggVG

" Keep Neovim's list navigation, including numeric counts, on native Ex commands.
for [s:key, s:command, s:count_command] in [
      \ ['[q', 'cprevious', 'cprevious'], [']q', 'cnext', 'cnext'],
      \ ['[Q', 'crewind', 'crewind'], [']Q', 'clast', 'clast'],
      \ ['[<C-q>', 'cpfile', 'cpfile'], [']<C-q>', 'cnfile', 'cnfile'],
      \ ['[l', 'lprevious', 'lprevious'], [']l', 'lnext', 'lnext'],
      \ ['[L', 'lrewind', 'lrewind'], [']L', 'llast', 'llast'],
      \ ['[<C-l>', 'lpfile', 'lpfile'], [']<C-l>', 'lnfile', 'lnfile'],
      \ ['[a', 'previous', 'previous'], [']a', 'next', 'next'],
      \ ['[A', 'rewind', 'argument'], [']A', 'last', 'argument'],
      \ ['[t', 'tprevious', 'tprevious'], [']t', 'tnext', 'tnext'],
      \ ['[T', 'trewind', 'trewind'], [']T', 'tlast', 'trewind'],
      \ ['[<C-t>', 'ptprevious', 'ptprevious'], [']<C-t>', 'ptnext', 'ptnext'],
      \ ['[B', 'brewind', 'buffer'], [']B', 'blast', 'buffer']]
  execute 'nnoremap <silent> ' . s:key . ' :<C-u>execute v:count ? v:count . "' . s:count_command . '" : "' . s:command . '"<CR>'
endfor
unlet s:key s:command s:count_command

function! s:VisualText() abort
  " Yank into the unnamed register's backing register, leaving register 0 intact.
  if exists('*getreginfo')
    let reg = getreginfo('"').points_to
  else
    " Early 8.2 cannot report the alias; choose a register with identical data.
    let reg = '0'
    for name in split('0123456789abcdefghijklmnopqrstuvwxyz-' . (has('clipboard') ? '*+' : ''), '\zs')
      if getreg(name, 1, 1) ==# getreg('"', 1, 1) && getregtype(name) ==# getregtype('"')
        let reg = name
        break
      endif
    endfor
  endif
  let saved = getreg(reg, 1, 1)
  let regtype = getregtype(reg)
  silent execute 'normal! gv"' . reg . 'y'
  let text = getreg(reg)
  call setreg(reg, saved, regtype)
  return text
endfunction

function! s:VisualSubstitute(range) abort
  let pattern = substitute(escape(s:VisualText(), '\/'), "\n", '\\n', 'g')
  call feedkeys(':' . a:range . 's/\V' . pattern . '/', 'ni')
endfunction

function! s:VisualSearch(forward, count) abort
  let start = getpos("'<")
  let text = s:VisualText()
  if visualmode() ==# 'V' | let text = substitute(text, "\n$", '', '') | endif
  if empty(text) | return | endif
  let @/ = '\V' . substitute(escape(text, '\'), "\n", '\\n', 'g')
  call histadd('/', @/)
  let v:searchforward = a:forward
  call setpos('.', start)
  execute 'normal! ' . a:count . 'n'
endfunction
xnoremap <silent> * :<C-u>call <SID>VisualSearch(1, v:count1)<CR>
xnoremap <silent> # :<C-u>call <SID>VisualSearch(0, v:count1)<CR>

nnoremap <leader>Sa :%s/\<<C-r><C-w>\>/
nnoremap <leader>Sf :.,$s/\<<C-r><C-w>\>/
xnoremap <leader>Sa :<C-u>call <SID>VisualSubstitute('%')<CR>
xnoremap <leader>Sf :<C-u>call <SID>VisualSubstitute('.,$')<CR>

xnoremap <silent> < <gv
xnoremap <silent> > >gv

" =========================================
" ========== NATIVE COMMENTING ============
" =========================================
" Match Neovim's linewise gc operator using the filetype's commentstring.
" g@ provides counts, motions, Visual selections, and native dot-repeat.
function! s:CommentParts() abort
  let split = stridx(&l:commentstring, '%s')
  if split < 0
    call s:Warn('Set commentstring for this filetype before commenting')
    return []
  endif
  return [strpart(&l:commentstring, 0, split), strpart(&l:commentstring, split + 2)]
endfunction

function! s:CommentPattern(parts) abort
  " Escape delimiters literally, including /* */, <!-- -->, and backslashes.
  return '\C^\(\s*\)\V' . escape(a:parts[0], '\')
        \ . '\m\(.*\)\V' . escape(a:parts[1], '\') . '\m\(\s*\)$'
endfunction

function! s:CommentOperator(...) abort
  if a:0 == 0
    let &operatorfunc = s:sid . 'CommentOperator'
    return 'g@'
  endif
  let first = line("'[")
  let last = line("']")
  if first > last || (first == last && col("'[") > col("']"))
    return
  endif
  let parts = s:CommentParts()
  if empty(parts)
    return
  endif
  let trimmed = [trim(parts[0]), trim(parts[1])]
  let pattern = s:CommentPattern(trimmed)
  let lines = getline(first, last)
  let indent = ''
  let width = -1
  let commented = 1
  " Ignore blank lines when deciding whether to comment or uncomment.
  for text in lines
    if text =~# '^\s*$'
      continue
    endif
    let prefix = matchstr(text, '^\s*')
    if width < 0 || strlen(prefix) < width
      let indent = prefix
      let width = strlen(prefix)
    endif
    let commented = commented && text =~# pattern
  endfor
  let result = []
  let exact = s:CommentPattern(parts)
  for text in lines
    if commented
      let matched = matchlist(text, exact)
      if empty(matched)
        let matched = matchlist(text, pattern)
      endif
      if !empty(matched)
        " Removing an empty comment must not leave indentation/trailing spaces.
        let text = matched[2] =~# '^\s*$' ? matched[2] : matched[1] . matched[2] . matched[3]
      endif
    elseif text =~# '^\s*$'
      let text = indent . trimmed[0] . trimmed[1]
    else
      let text = indent . parts[0] . strpart(text, strlen(indent)) . parts[1]
    endif
    call add(result, text)
  endfor
  " One change for undo; preserve registers, marks, and the window view.
  if result !=# lines
    lockmarks call setline(first, result)
  endif
endfunction

function! s:CommentTextObject() abort
  let parts = s:CommentParts()
  if empty(parts)
    return
  endif
  let pattern = s:CommentPattern([trim(parts[0]), trim(parts[1])])
  if getline('.') !~# pattern
    return
  endif
  let first = line('.')
  let last = first
  while first > 1 && getline(first - 1) =~# pattern
    let first -= 1
  endwhile
  while last < line('$') && getline(last + 1) =~# pattern
    let last += 1
  endwhile
  execute 'normal! ' . first . 'GV' . last . 'G'
endfunction

" Keep a script prefix for callbacks and popup-local commands.
let s:sid = matchstr(string(function('s:CommentOperator')), '<SNR>\d\+_')
nnoremap <silent><expr> gc <SID>CommentOperator()
xnoremap <silent><expr> gc <SID>CommentOperator()
nnoremap <silent><expr> gcc <SID>CommentOperator() . '_'
onoremap <silent> gc :<C-u>call <SID>CommentTextObject()<CR>

function! s:BlankLines(above, ...) abort
  if !a:0
    let &operatorfunc = s:sid . (a:above ? 'BlankAbove' : 'BlankBelow')
    return 'g@l'
  endif
  call append(line('.') - a:above, repeat([''], v:count1))
endfunction
function! s:BlankAbove(type) abort
  call s:BlankLines(1, a:type)
endfunction
function! s:BlankBelow(type) abort
  call s:BlankLines(0, a:type)
endfunction
nnoremap <silent><expr> [<Space> <SID>BlankLines(1)
nnoremap <silent><expr> ]<Space> <SID>BlankLines(0)

function! s:ClearYankHighlight(winid, matchids, timer) abort
  if win_id2tabwin(a:winid)[0] > 0
    for id in a:matchids
      call win_execute(a:winid, 'silent! call matchdelete(' . id . ')')
    endfor
  endif
endfunction

function! s:HighlightYank() abort
  if get(v:event, 'operator', '') !=# 'y'
    return
  endif
  let first = getpos("'[")[1]
  let last = getpos("']")[1]
  if first <= 0 || last < first
    return
  endif
  let positions = map(range(first, min([last, first + 199])), '[v:val]')
  let ids = []
  for offset in range(0, len(positions) - 1, 8)
    let id = matchaddpos('IncSearch', positions[offset : min([offset + 7, len(positions) - 1])], 10)
    if id > 0
      call add(ids, id)
    endif
  endfor
  if !empty(ids)
    call timer_start(160, function('<SID>ClearYankHighlight', [win_getid(), ids]))
  endif
endfunction

function! s:CopyYank() abort
  if &clipboard !=# '' || get(v:event, 'operator', '') !=# 'y' || index(['', '+', '*'], get(v:event, 'regname', '')) < 0
    return
  endif
  let contents = get(v:event, 'regcontents', [])
  if s:desktop_clipboard
    try
      call setreg('+', contents, get(v:event, 'regtype', 'v'))
    catch
      call s:Warn('System clipboard unavailable; text remains in Vim: ' . v:exception)
    endtry
    return
  endif
  if !executable('base64')
    return
  endif
  let payload = join(contents, "\n")
  if get(v:event, 'regtype', '') ==# 'V'
    let payload .= "\n"
  endif
  if strlen(payload) > 100000
    call s:Warn('OSC52 yank skipped: selection exceeds 100 KB')
    return
  endif
  let encoded = substitute(system('base64', payload), '\_s', '', 'g')
  let sequence = "\e]52;c;" . encoded . "\x07"
  if exists('$TMUX') && !empty($TMUX)
    let sequence = "\ePtmux;\e" . sequence . "\e\\"
  elseif exists('$STY') && !empty($STY)
    let sequence = "\eP" . sequence . "\e\\"
  endif
  if filewritable('/dev/tty') == 1
    silent! call writefile([sequence], '/dev/tty', 'b')
  endif
endfunction

augroup NopackYank
  autocmd!
  if exists('##TextYankPost')
    autocmd TextYankPost * call <SID>HighlightYank()
    autocmd TextYankPost * call <SID>CopyYank()
  endif
augroup END

" Built-in display, completion, and file browsing.
filetype plugin indent on
syntax enable
packadd matchit
" Use the preferred theme when available, otherwise fall back to a bundled theme.
if !empty(globpath(&runtimepath, 'colors/retrobox.vim'))
  colorscheme retrobox
else
  colorscheme desert
endif

" Space Th: idle-only word highlighting; disabled until explicitly toggled.
let s:cursor_word_enabled = 0
highlight default link CursorWord Visual
function! s:ClearCursorWord(winid) abort
  let id = getwinvar(a:winid, 'cursor_word_match', 0)
  if id > 0
    silent! call matchdelete(id, a:winid)
    call setwinvar(a:winid, 'cursor_word_match', 0)
  endif
endfunction
function! s:HighlightCursorWord() abort
  if !s:cursor_word_enabled || !s:BufferAllows(bufnr('%')) || mode() !=# 'n'
    return
  endif
  let word = expand('<cword>')
  if empty(word) || empty(matchstr(getline('.'), '\%' . col('.') . 'c\k'))
    return
  endif
  call s:ClearCursorWord(win_getid())
  let w:cursor_word_match = matchadd('CursorWord', '\C\V\<' . escape(word, '\') . '\>', -1)
endfunction
function! s:ToggleCursorWord() abort
  let s:cursor_word_enabled = !s:cursor_word_enabled
  if s:cursor_word_enabled
    call s:HighlightCursorWord()
  else
    for info in getwininfo()
      call s:ClearCursorWord(info.winid)
    endfor
  endif
endfunction
nnoremap <silent> <leader>Th :call <SID>ToggleCursorWord()<CR>
augroup NopackCursorWord
  autocmd!
  autocmd ColorScheme * highlight default link CursorWord Visual
  autocmd CursorHold * call <SID>HighlightCursorWord()
  autocmd CursorMoved,InsertEnter,ModeChanged,WinLeave,BufLeave,TextChanged * if s:cursor_word_enabled | call <SID>ClearCursorWord(win_getid()) | endif
augroup END
set laststatus=2
set statusline=%!NopackStatusline()
set list
let s:base_listchars = 'tab:┊ ,trail:·,extends:>,precedes:<'
let &listchars = s:base_listchars
let s:has_indent_guides = 1
function! s:UpdateIndentGuides() abort
  let markers = s:base_listchars
  if s:has_indent_guides && s:BufferAllows(bufnr('%'))
    let markers .= ',leadmultispace:┊' . repeat(' ', shiftwidth() - 1)
  endif
  let &l:listchars = markers
endfunction
call s:UpdateIndentGuides()
augroup NopackIndentGuides
  autocmd!
  autocmd FileType,BufWinEnter * call <SID>UpdateIndentGuides()
  autocmd OptionSet shiftwidth,tabstop,vartabstop call <SID>UpdateIndentGuides()
augroup END

augroup NopackFiletypes
  autocmd!
  autocmd FileType * setlocal indentkeys-=0# cinkeys-=0#
  autocmd FileType python setlocal nosmartindent
  autocmd BufRead,BufNewFile *.cu,*.cuh setfiletype cuda
  autocmd BufRead,BufNewFile *.bzl,BUILD,BUILD.bazel,WORKSPACE,WORKSPACE.bazel,MODULE.bazel setfiletype bzl
  autocmd BufRead,BufNewFile *.mlir setfiletype mlir
  autocmd BufRead,BufNewFile *.mdx setfiletype markdown.mdx
  " Prefer Verilog over the V language for .v files.
  autocmd BufRead,BufNewFile *.v,*.vh setlocal filetype=verilog
  autocmd BufRead,BufNewFile *.sv,*.svh setlocal filetype=systemverilog
augroup END

function! s:Pair(open, close) abort
  if !s:BufferAllows(bufnr('%')) | return a:open | endif
  let next = strpart(getline('.'), col('.') - 1, 1)
  let previous = strpart(getline('.'), col('.') - 2, 1)
  if a:open ==# a:close && (previous =~# '\k\|\\' || next =~# '\k')
    return a:open
  endif
  if next ==# a:close && a:open ==# a:close
    return "\<Right>"
  endif
  return next ==# '' || next =~# '\s\|[]})]' ? a:open . a:close . "\<Left>" : a:open
endfunction
function! s:PairClose(char) abort
  if !s:BufferAllows(bufnr('%')) | return a:char | endif
  return strpart(getline('.'), col('.') - 1, 1) ==# a:char ? "\<Right>" : a:char
endfunction
function! s:PairBackspace() abort
  if !s:BufferAllows(bufnr('%')) | return "\<BS>" | endif
  let pair = strpart(getline('.'), col('.') - 2, 2)
  return index(['()', '[]', '{}', '""', "''", '``'], pair) >= 0 ? "\<BS>\<Del>" : "\<BS>"
endfunction
inoremap <expr> ( <SID>Pair('(', ')')
inoremap <expr> [ <SID>Pair('[', ']')
inoremap <expr> { <SID>Pair('{', '}')
inoremap <expr> ) <SID>PairClose(')')
inoremap <expr> ] <SID>PairClose(']')
inoremap <expr> } <SID>PairClose('}')
inoremap <expr> " <SID>Pair('"', '"')
inoremap <expr> ' <SID>Pair("'", "'")
inoremap <expr> ` <SID>Pair('`', '`')
inoremap <expr> <BS> <SID>PairBackspace()

let g:netrw_banner = 0
let g:netrw_liststyle = 3
let g:netrw_winsize = 25
let g:netrw_browse_split = 4
let g:netrw_keepdir = 1
let g:netrw_home = s:nopack_data
let g:netrw_bufsettings = 'noma nomod nu nobl nowrap ro nornu'
" Recent netrw uses <unique> when assigning Ctrl-H/L.  Declare alternate
" targets before netrw loads so our window-navigation mappings can coexist.
nmap <silent> <Plug>NopackNetrwHide <Plug>NetrwHideEdit
nmap <silent> <Plug>NopackNetrwRefresh <Plug>NetrwRefresh

function! s:CompletionEnter() abort
  return pumvisible() && complete_info().selected >= 0 ? "\<C-Y>" : "\<CR>"
endfunction

inoremap <expr> <C-Space> <SID>BufferAllows(bufnr("%")) ? "\<C-N>" : ""
inoremap <expr> <CR> <SID>CompletionEnter()
inoremap <expr> <Tab> pumvisible() ? "\<C-N>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-P>" : "\<S-Tab>"

" Native completion combines buffer words and the project ctags index.
function! s:BufferCompletion() abort
  let &l:autocomplete = s:BufferAllows(bufnr('%'))
endfunction
if exists('+autocomplete')
  if exists('+autocompletedelay')
    set autocompletedelay=150
  endif
  augroup NopackCompletion
    autocmd!
    autocmd BufEnter,FileType * call <SID>BufferCompletion()
  augroup END
else
  " Older Vim lacks 'autocomplete': request native keyword completion after a pause.
  let s:completion_timer = -1
  function! s:CancelCompletion() abort
    if s:completion_timer != -1
      call timer_stop(s:completion_timer)
      let s:completion_timer = -1
    endif
  endfunction

  function! s:AutoComplete(buf, tick, position, timer) abort
    let s:completion_timer = -1
    if !s:BufferAllows(a:buf) || mode() !=# 'i' || bufnr('%') != a:buf || b:changedtick != a:tick
          \ || getcurpos() != a:position || pumvisible()
      return
    endif
    call feedkeys("\<C-N>", 'n')
  endfunction

  function! s:QueueCompletion() abort
    call s:CancelCompletion()
    if !s:BufferAllows(bufnr('%')) || pumvisible()
      return
    endif
    if strpart(getline('.'), 0, col('.') - 1) =~# '\k\{2,}$'
      let s:completion_timer = timer_start(150, function('<SID>AutoComplete', [bufnr('%'), b:changedtick, getcurpos()]))
    endif
  endfunction

  augroup NopackCompletion
    autocmd!
    autocmd TextChangedI * call <SID>QueueCompletion()
    autocmd InsertLeave,CompleteDone * call <SID>CancelCompletion()
  augroup END
endif

function! s:TabWindows() abort
  let info = gettabinfo(tabpagenr())
  return empty(info) ? [] : info[0].windows
endfunction

function! s:OpenExplorer(root, width, relative) abort
  let saved_error = v:errmsg
  let saved_lazyredraw = &lazyredraw
  set lazyredraw
  let existing = map(getbufinfo(), 'v:val.bufnr')
  try
    execute 'silent topleft vertical ' . a:width . 'new'
    execute 'silent Explore ' . fnameescape(a:root)
    if a:relative !=# '' && &filetype ==# 'netrw'
      call s:RevealTreeFile(a:relative)
    endif
  finally
    " Only discard empty hidden buffers created by this netrw operation.
    " Existing unnamed buffers (including user drafts) must remain untouched.
    for info in getbufinfo()
      if index(existing, info.bufnr) < 0 && info.name ==# '' && info.loaded
            \ && !info.changed && empty(win_findbuf(info.bufnr))
            \ && s:IsSource(info.bufnr)
            \ && getbufline(info.bufnr, 1, '$') ==# ['']
        execute 'bwipeout ' . info.bufnr
      endif
    endfor
    " netrw catches this empty scratch-buffer error but leaves v:errmsg set.
    if v:errmsg =~# '^E749:'
      let v:errmsg = saved_error
    endif
    call s:RedrawNetrwGit()
    let &lazyredraw = saved_lazyredraw
  endtry
endfunction

function! s:NetrwAction(action) abort
  let saved_lazyredraw = &lazyredraw
  set lazyredraw
  try
    execute "normal \<Plug>" . a:action
  finally
    call s:RedrawNetrwGit()
    let &lazyredraw = saved_lazyredraw
  endtry
endfunction

function! s:NetrwRoot(win) abort
  let buf = winbufnr(a:win)
  return getwinvar(a:win, 'netrw_treetop', getbufvar(buf, 'netrw_curdir', ''))
endfunction

function! s:NetrwRefresh() abort
  let root = substitute(get(w:, 'netrw_treetop', get(b:, 'netrw_curdir', getcwd())), '/$', '', '')
  let expanded = sort(filter(keys(get(w:, 'netrw_treedict', {})), 'isdirectory(v:val)'), {a, b -> strlen(a) - strlen(b)})
  let view = winsaveview()
  let saved = &lazyredraw
  let saved_error = v:errmsg
  set lazyredraw
  try
    " Vim 9.0 netrw refresh drops directory suffixes in cached child lists.
    " Re-read through its normal browser, then reopen only expanded branches.
    unlet! w:netrw_treedict
    call netrw#LocalBrowseCheck(root . '/')
    for directory in expanded
      if stridx(directory, root . '/') == 0
        call s:RevealTreeFile(strpart(directory, strlen(root) + 1) . '/')
      endif
    endfor
    call winrestview(view)
    call s:RedrawNetrwGit()
    call s:QueueNetrwGit()
    doautocmd <nomodeline> User NopackFilesChanged
  finally
    " netrw catches an empty scratch-buffer deletion but retains v:errmsg.
    if v:errmsg =~# '^E749:' | let v:errmsg = saved_error | endif
    let &lazyredraw = saved
  endtry
endfunction

function! s:NetrwSetRoot(path) abort
  let path = empty(a:path) ? s:NetrwCursorPaths()[1] : a:path
  call netrw#SetTreetop(1, substitute(path, '/\+$', '', '') . '/')
  call s:QueueNetrwGit()
endfunction

function! s:NetrwCursorPaths() abort
  let parent = b:netrw_curdir
  let directory = parent
  if get(w:, 'netrw_liststyle', 0) == 3 && exists('w:netrw_treetop')
    let path = netrw#Call('NetrwTreePath', w:netrw_treetop)
    if !empty(path)
      let path = substitute(path, '/\+$', '', '')
      if getline('.') =~# '/$'
        let directory = path
        let parent = fnamemodify(path, ':h')
      elseif !isdirectory(path) || getline('.') =~# '\t -->'
        let parent = fnamemodify(path, ':h')
        let directory = parent
      else
        let parent = path
        let directory = path
      endif
    endif
  endif
  return [parent, directory]
endfunction

function! s:NetrwCursorPath() abort
  let parent = s:NetrwCursorPaths()[0]
  let word = netrw#Call('NetrwGetWord')
  if empty(word) || index(['./', '../'], word) >= 0 | return '' | endif
  let path = parent . '/' . substitute(word, '/$', '', '')
  let paths = getftype(path) ==# '' ? [] : [path]
  if word !~# '/$'
    let display = split(getline('.'), "\t")[0]
    for suffix in ['*@', '@', '*']
      if strpart(display, strlen(display) - strlen(word . suffix)) ==# word . suffix
        if getftype(path . suffix) !=# '' | call add(paths, path . suffix) | endif
        break
      endif
    endfor
  endif
  if len(paths) > 1
    throw 'Ambiguous netrw filename; use the terminal: ' . join(paths, ', ')
  endif
  return get(paths, 0, '')
endfunction

function! s:NetrwSelected(first, last) abort
  let marked = netrw#Expose('netrwmarkfilelist')
  let paths = type(marked) == v:t_list ? copy(marked) : []
  let saved = getcurpos()
  try
    if empty(paths)
      for row in range(a:first, a:last)
        call cursor(row, 1)
        let path = s:NetrwCursorPath()
        if !empty(path) | call add(paths, path) | endif
      endfor
    endif
  finally
    call setpos('.', saved)
  endtry
  return uniq(sort(filter(paths, 'getftype(v:val) !=# ""')))
endfunction

function! s:NetrwRemove(first, last) abort
  let paths = s:NetrwSelected(a:first, a:last)
  if empty(paths) || confirm('Delete ' . join(paths, ', ') . '?', "&Yes\n&No", 2) != 1 | return | endif
  for path in paths
    if delete(path, getftype(path) ==# 'dir' ? 'rf' : '') != 0
      call s:Warn('Delete failed: ' . path)
    endif
  endfor
  call netrw#Call('NetrwUnMarkFile', 1)
  call s:NetrwRefresh()
endfunction

function! s:NetrwRename(first, last) abort
  for old in s:NetrwSelected(a:first, a:last)
    let new = input('Move to: ', old, 'file')
    if empty(new) | break | endif
    if old !=# new && (getftype(new) ==# '' || confirm('Overwrite ' . new . '?', "&Yes\n&No", 2) == 1)
      if rename(old, new) != 0 | call s:Warn('Rename failed: ' . old) | endif
    endif
  endfor
  call netrw#Call('NetrwUnMarkFile', 1)
  call s:NetrwRefresh()
endfunction

function! s:NetrwCreate(directory) abort
  let root = s:NetrwCursorPaths()[1]
  let name = input(a:directory ? 'New directory: ' : 'New file: ', root . '/', 'file')
  if empty(name) | return | endif
  if a:directory
    call mkdir(name, 'p')
    call s:NetrwRefresh()
  else
    call s:FocusEditor()
    if &filetype ==# 'netrw' | botright vnew | endif
    execute 'edit ' . fnameescape(name)
  endif
endfunction

function! s:NetrwMark() abort
  let path = s:NetrwCursorPath()
  if empty(path) | return | endif
  let saved_style = w:netrw_liststyle
  let saved_directory = b:netrw_curdir
  let b:netrw_curdir = fnamemodify(path, ':h')
  let w:netrw_liststyle = 0
  try
    call netrw#Call('NetrwMarkFile', 1, fnamemodify(path, ':t'))
  finally
    let w:netrw_liststyle = saved_style
    let b:netrw_curdir = saved_directory
  endtry
endfunction

function! s:NetrwTarget() abort
  let target = s:NetrwCursorPaths()[1]
  let saved = g:netrw_fastbrowse
  try
    let g:netrw_fastbrowse = 2
    call netrw#MakeTgt(target)
  finally
    let g:netrw_fastbrowse = saved
  endtry
endfunction

function! s:NetrwTransferred(win, buf, files, output, limited) abort
  if win_id2win(a:win) > 0 && winbufnr(a:win) == a:buf && getbufvar(a:buf, '&filetype') ==# 'netrw'
    let marked = netrw#Expose('netrwmarkfilelist')
    call s:NetrwInWindow(a:win, type(marked) == v:t_list && marked ==# a:files)
  endif
endfunction

function! s:NetrwTransfer(command) abort
  if has_key(s:running, 'netrw-transfer')
    call s:Warn('A file copy or move is already running')
    return
  endif
  let files = netrw#Expose('netrwmarkfilelist')
  let target = netrw#Expose('netrwmftgt')
  if type(files) != v:t_list || empty(files) || type(target) != v:t_string || !isdirectory(target)
    call s:Warn('Mark files with mf and set the target directory with mt')
    return
  endif
  call s:RunCommand('netrw-transfer', [a:command] + (a:command ==# 'cp' ? ['-R'] : []) + files + [target],
        \ {'timeout': 120000}, function('<SID>NetrwTransferred', [win_getid(), bufnr('%'), copy(files)]))
endfunction

function! s:SidebarWidth() abort
  if exists('w:nopack_sidebar') && w:nopack_sidebar.buf != bufnr('%')
    let &l:winfixwidth = w:nopack_sidebar.value
    unlet w:nopack_sidebar
  endif
  if &filetype ==# 'netrw'
    if !exists('w:nopack_sidebar')
      let w:nopack_sidebar = {'buf': bufnr('%'), 'value': &l:winfixwidth}
    endif
    setlocal winfixwidth conceallevel=2 concealcursor=nvic
  endif
endfunction

function! s:NetrwHelpFilter(id, key) abort
  let previous = getwinvar(a:id, 'nopack_help_key', '')
  call setwinvar(a:id, 'nopack_help_key', a:key)
  if index(['q', "\<Esc>", "\<C-c>"], a:key) >= 0 || (previous ==# 'g' && a:key ==# '?')
    call popup_close(a:id)
  elseif a:key ==# 'g' && previous ==# 'g'
    call win_execute(a:id, 'normal! gg')
  else
    let motions = {'j': 'j', 'k': 'k', 'G': 'G', "\<Down>": 'j', "\<Up>": 'k',
          \ "\<C-d>": "\<C-d>", "\<C-u>": "\<C-u>", "\<C-f>": "\<C-f>", "\<C-b>": "\<C-b>"}
    if has_key(motions, a:key)
      call win_execute(a:id, 'normal! ' . motions[a:key])
    endif
  endif
  return 1
endfunction

function! s:NetrwHelp() abort
  let lines = [
        \ 'netrw file explorer · Nopack Vim', '',
        \ 'Navigation / Opening',
        \ '  j / k             Move down / up',
        \ '  gg / G            First / last line',
        \ '  Enter / l         Expand or collapse directory / open file',
        \ '  h / -             Collapse branch / go to parent directory',
        \ '  gn / :Ntree PATH  Use cursor directory / chosen path as root',
        \ '  o / v / t         Open in horizontal split / vertical split / tab',
        \ '  p                 Preview file',
        \ '  Ctrl-h/j/k/l      Move between windows',
        \ '  Space e           Toggle file explorer', '',
        \ 'Display / Refresh',
        \ '  Space nr          Refresh tree',
        \ '  gh                Toggle hidden files',
        \ '  Space nh          Edit file hiding patterns',
        \ '  s / r             Change sort order / reverse sorting', '',
        \ 'File Operations',
        \ '  % / d             New file in editor / new directory',
        \ '  R / D             Rename / delete (D also accepts a selection)',
        \ '  mf / mu           Toggle file mark / unmark all files',
        \ '  mt                Set cursor directory as copy/move target',
        \ '  mc / mm           Copy / move marked files to target', '',
        \ 'g? / q / Esc: Close help · j/k, Ctrl-d/u, gg/G: Scroll']
  call popup_create(lines, {'title': ' netrw help ', 'pos': 'center',
        \ 'maxwidth': max([1, min([78, &columns - 4])]), 'maxheight': max([1, &lines - 6]),
        \ 'border': [1], 'padding': [0, 1, 0, 1], 'wrap': 1, 'mapping': 0, 'zindex': 250,
        \ 'filter': function('<SID>NetrwHelpFilter')})
endfunction

function! s:NetrwSetup() abort
  let w:netrw_liststyle = 3
  command! -buffer -nargs=? -complete=dir Ntree call <SID>NetrwSetRoot(<q-args>)
  nnoremap <silent><buffer> gn :Ntree<CR>
  nnoremap <silent><buffer> g? :call <SID>NetrwHelp()<CR>
  nnoremap <silent><buffer> <Plug>NetrwRefresh :call <SID>NetrwRefresh()<CR>
  nnoremap <silent><buffer> % :call <SID>NetrwCreate(0)<CR>
  nnoremap <silent><buffer> d :call <SID>NetrwCreate(1)<CR>
  nnoremap <silent><buffer> D :call <SID>NetrwRemove(line('.'), line('.'))<CR>
  xnoremap <silent><buffer> D :<C-u>call <SID>NetrwRemove(line("'<"), line("'>"))<CR>
  nnoremap <silent><buffer> R :call <SID>NetrwRename(line('.'), line('.'))<CR>
  nnoremap <silent><buffer> mf :call <SID>NetrwMark()<CR>
  nnoremap <silent><buffer> mt :call <SID>NetrwTarget()<CR>
  nnoremap <silent><buffer> mc :call <SID>NetrwTransfer('cp')<CR>
  nnoremap <silent><buffer> mm :call <SID>NetrwTransfer('mv')<CR>
  setlocal number norelativenumber nowrap
  " netrw's wide-list cleanup unmaps these when any global RHS contains the
  " same character; temporary identities keep that cleanup error-free.
  nnoremap <buffer> w w
  nnoremap <buffer> b b
  nnoremap <silent><buffer> <leader>nh :call <SID>NetrwAction('NetrwHideEdit')<CR>
  nnoremap <silent><buffer> <leader>nr :call <SID>NetrwRefresh()<CR>
  nnoremap <silent><buffer> <C-h> <C-w>h
  nnoremap <silent><buffer> <C-j> <C-w>j
  nnoremap <silent><buffer> <C-k> <C-w>k
  nnoremap <silent><buffer> <C-l> <C-w>l
  nnoremap <silent><buffer> <CR> :call <SID>NetrwAction('NetrwLocalBrowseCheck')<CR>
  nnoremap <silent><buffer> l :call <SID>NetrwAction('NetrwLocalBrowseCheck')<CR>
  nnoremap <silent><buffer> h :call <SID>NetrwAction('NetrwTreeSqueeze')<CR>
endfunction

augroup NopackNetrw
  autocmd!
  autocmd FileType netrw call <SID>NetrwSetup()
  autocmd BufWinEnter,WinEnter * call <SID>SidebarWidth()
  autocmd BufWipeout * if has_key(s:tree_reveal, expand('<abuf>')) | call remove(s:tree_reveal, expand('<abuf>')) | endif
  autocmd Syntax netrw syntax match Conceal /[|│]/ contained containedin=netrwTreeBar conceal cchar=┊
  autocmd BufWritePre * let b:nopack_new_write = getftype(expand('%:p')) ==# ''
  autocmd BufWritePost * if get(b:, 'nopack_new_write', 0) | call timer_start(0, function('<SID>NetrwNewFile', [expand('%:p')])) | let b:nopack_new_write = 0 | endif
augroup END

function! s:NetrwNewFile(path, timer) abort
  for info in getwininfo()
    if getbufvar(info.bufnr, '&filetype') ==# 'netrw'
      let root = substitute(s:NetrwRoot(info.winid), '/$', '', '')
      if stridx(a:path, root . '/') == 0
        call s:NetrwInWindow(info.winid, 0)
      endif
    endif
  endfor
endfunction

function! s:NetrwInWindow(win, unmark) abort
  " netrw uses :redir internally; win_execute() would nest output capture (E930).
  let origin = win_getid()
  let saved = &lazyredraw
  set lazyredraw
  try
    noautocmd call win_gotoid(a:win)
    if a:unmark | call netrw#Call('NetrwUnMarkFile', 1) | endif
    call s:NetrwRefresh()
  finally
    noautocmd call win_gotoid(origin)
    let &lazyredraw = saved
  endtry
endfunction

let s:tree_reveal = {}
function! s:RevealTreeFile(relative) abort
  let key = string(bufnr('%'))
  let root = s:NetrwRoot(win_getid())
  let cached = get(s:tree_reveal, key, {})
  if !empty(cached) && cached.relative ==# a:relative && cached.tick == b:changedtick && cached.root ==# root
    if line('.') != cached.row
      call cursor(cached.row, 1)
      normal! zz
    endif
    return
  endif
  let lines = getline(1, '$')
  let tree_bar = '| '
  for text in lines
    if stridx(text, '│ ') == 0 | let tree_bar = '│ ' | break | endif
    if stridx(text, '| ') == 0 | break | endif
  endfor
  let parts = filter(split(a:relative, '/', 1), 'v:val !=# ""')
  let parent_line = 1
  let depth = 1
  for name in parts
    let directory = depth < len(parts) || a:relative =~# '/$'
    let prefix = repeat(tree_bar, depth)
    let label = prefix . name . (directory ? '/' : '')
    let found = 0
    for row in range(parent_line + 1, len(lines))
      if depth > 1 && strpart(lines[row - 1], 0, strlen(prefix)) !=# prefix
        break
      endif
      if lines[row - 1] ==# label
        let found = row
        break
      endif
    endfor
    if found == 0
      return
    endif
    call cursor(found, 1)
    if directory
      let child_prefix = repeat(tree_bar, depth + 1)
      if found >= len(lines) || strpart(lines[found], 0, len(child_prefix)) !=# child_prefix
        let saved_error = v:errmsg
        call s:NetrwAction('NetrwLocalBrowseCheck')
        let lines = getline(1, '$')
        if v:errmsg =~# '^E749:'
          let v:errmsg = saved_error
        endif
      endif
    endif
    let parent_line = found
    let depth += 1
  endfor
  let s:tree_reveal[key] = {'relative': a:relative, 'tick': b:changedtick, 'root': root, 'row': parent_line}
  normal! zz
endfunction

let s:project_roots = {}
let s:project_markers = ['CMakeLists.txt', 'compile_commands.json', 'Makefile', 'package.json', 'pyproject.toml', 'ty.toml', 'pyrightconfig.json', 'Cargo.toml', 'WORKSPACE', 'WORKSPACE.bazel', 'MODULE.bazel', 'buf.yaml', 'verible.filelist']

function! s:ProjectRoot(...) abort
  let buf = a:0 ? a:1 : bufnr('%')
  let dir = ''
  if !a:0 && getbufvar(buf, '&filetype') ==# 'netrw'
    let dir = get(w:, 'netrw_treetop', getbufvar(buf, 'netrw_curdir', ''))
  elseif s:IsSource(buf) && bufname(buf) !=# ''
    let dir = fnamemodify(bufname(buf), ':p:h')
  endif
  if dir ==# '' && !a:0
    for winid in s:TabWindows()
      let candidate = winbufnr(winid)
      if s:IsEditorWindow(winid) && bufname(candidate) !=# ''
        let dir = fnamemodify(bufname(candidate), ':p:h')
        break
      endif
    endfor
  endif
  return s:FindProject(dir ==# '' ? getcwd() : dir)
endfunction

function! s:FindProject(dir) abort
  let dir = fnamemodify(a:dir, ':p')
  let dir = substitute(dir, '/\+$', '', '')
  if dir ==# ''
    let dir = '/'
  endif
  if has_key(s:project_roots, dir)
    return s:project_roots[dir]
  endif
  let fallback = dir
  let library = matchstr(dir . '/', '^.\{-}/\%(site\|dist\)-packages/[^/]*')
  let library = substitute(library, '/$', '', '')
  let stop = empty(library) ? '' : fnamemodify(library, ':h')
  let marker = ''
  let git = 0
  while dir !=# stop
    if getftype(dir . '/.git') !=# ''
      let git = 1
      break
    endif
    if empty(library) && filereadable(dir . '/os.py') && filereadable(dir . '/importlib/__init__.py')
      let library = dir
      break
    endif
    if empty(marker)
      for name in s:project_markers
        if filereadable(dir . '/' . name)
          let marker = dir
          break
        endif
      endfor
    endif
    let parent = fnamemodify(dir, ':h')
    if parent ==# dir | break | endif
    let dir = parent
  endwhile
  let root = git ? dir : !empty(library) ? library : !empty(marker) ? marker : fallback
  let result = {'root': root, 'git': git, 'recognized': git || !empty(library) || !empty(marker)}
  let s:project_roots[fallback] = result
  return result
endfunction

function! s:ToggleExplorer() abort
  let windows = s:TabWindows()
  for winid in windows
    if getbufvar(winbufnr(winid), '&filetype') ==# 'netrw'
      if len(windows) > 1
        call win_execute(winid, 'close')
      else
        let tree = winid
        botright vnew
        call win_execute(tree, 'vertical resize ' . max([20, &columns / 4]) . ' | setlocal winfixwidth')
        let g:netrw_chgwin = winnr()
      endif
      return
    endif
  endfor

  let file = s:IsSource(bufnr('%')) ? expand('%:p') : ''
  let root = s:ProjectRoot().root
  let width = max([20, min([40, &columns / 4])])
  let relative = file !=# '' && stridx(file, root . '/') == 0 ? strpart(file, len(root) + 1) : ''
  call s:OpenExplorer(root, width, relative)
endfunction

nnoremap <silent><nowait> <leader>e :call <SID>ToggleExplorer()<CR>

let s:syncing_project = 0
function! s:SyncProjectContext() abort
  if s:syncing_project || !s:IsEditorWindow(win_getid()) || expand('%:p') ==# ''
    return
  endif
  let project = s:ProjectRoot()
  if !project.recognized
    return
  endif
  let file = expand('%:p')
  let origin = win_getid()
  let s:syncing_project = 1
  try
    if getcwd() !=# project.root
      execute 'lcd ' . fnameescape(project.root)
    endif
    for winid in s:TabWindows()
      if getbufvar(winbufnr(winid), '&filetype') ==# 'netrw'
        " Revealing a file is not a user window switch: avoid duplicate jobs.
        noautocmd call win_gotoid(winid)
        if substitute(s:NetrwRoot(winid), '/$', '', '') !=# project.root
          call s:NetrwSetRoot(project.root)
        endif
        if stridx(file, project.root . '/') == 0
          call s:RevealTreeFile(strpart(file, len(project.root) + 1))
        endif
      endif
    endfor
  finally
    noautocmd call win_gotoid(origin)
    let s:syncing_project = 0
  endtry
endfunction

augroup NopackProjectContext
  autocmd!
  autocmd BufEnter * call <SID>SyncProjectContext()
  autocmd BufFilePost,FocusGained,ShellCmdPost,DirChanged * let s:project_roots = {}
  autocmd User NopackFilesChanged let s:project_roots = {}
  autocmd BufLeave * if &buftype ==# 'terminal' | let s:project_roots = {} | endif
  execute 'autocmd BufWritePost ' . join(s:project_markers + ['.git', 'os.py', '__init__.py'], ',') . ' let s:project_roots = {}'
augroup END

" =========================================
" ============== BUFFER LIST ==============
" =========================================
let s:buffer_order = []

function! s:IsEditorBuffer(buf) abort
  return bufexists(a:buf) && buflisted(a:buf)
        \ && (s:IsSource(a:buf) || getbufvar(a:buf, '&buftype') ==# 'terminal')
endfunction

function! s:Buffers() abort
  let seen = {}
  let kept = []
  for buf in s:buffer_order
    if s:IsEditorBuffer(buf)
      call add(kept, buf)
      let seen[string(buf)] = 1
    endif
  endfor
  let s:buffer_order = kept
  for info in getbufinfo({'buflisted': 1})
    if !has_key(seen, string(info.bufnr)) && s:IsEditorBuffer(info.bufnr)
      call add(s:buffer_order, info.bufnr)
      let seen[string(info.bufnr)] = 1
    endif
  endfor
  return copy(s:buffer_order)
endfunction

function! s:BufferIndex(buf, ...) abort
  let index = 0
  for candidate in (a:0 ? a:1 : s:Buffers())
    if candidate == a:buf
      return index
    endif
    let index += 1
  endfor
  return 0
endfunction

function! s:FocusEditor() abort
  if s:IsEditorWindow(win_getid()) | return | endif
  let target = get(get(b:, 'nopack_outline', {}), 'target', 0)
  if s:IsEditorWindow(target)
    call win_gotoid(target)
    return
  endif
  for winid in s:TabWindows()
    if s:IsEditorWindow(winid)
      call win_gotoid(winid)
      return
    endif
  endfor
  let buffers = filter(s:Buffers(), 's:IsSource(v:val)')
  if empty(buffers)
    botright vnew
  else
    execute 'botright sbuffer ' . buffers[0]
  endif
endfunction

function! s:SelectBuffer(buf) abort
  if !s:IsEditorBuffer(a:buf)
    return
  endif
  call s:FocusEditor()
  execute 'buffer ' . a:buf
endfunction

function! NopackTabline() abort
  if !empty(s:tabline_cache) | return s:tabline_cache | endif
  let items = []
  let index = 1
  for buf in s:Buffers()
    let name = fnamemodify(bufname(buf), ':t')
    if name ==# ''
      let name = '[No Name]'
    endif
    let highlight = buf == bufnr('%') ? '%#TabLineSel#' : '%#TabLine#'
    let modified = getbufvar(buf, '&modified') ? ' + ' : ' '
    call add(items, highlight . ' ' . index . ':' . substitute(name, '%', '%%', 'g') . modified)
    let index += 1
  endfor
  let s:tabline_cache = join(items, '') . '%#TabLineFill#'
  return s:tabline_cache
endfunction

let s:tabline_cache = ''
function! s:TablineModified() abort
  if get(b:, 'nopack_tab_modified', -1) != &modified
    let b:nopack_tab_modified = &modified
    let s:tabline_cache = ''
  endif
endfunction
set tabline=%!NopackTabline()
augroup NopackTabline
  autocmd!
  autocmd BufAdd,BufDelete,BufEnter,BufFilePost,FileType * let s:tabline_cache = ''
  autocmd OptionSet buflisted,buftype let s:tabline_cache = ''
  autocmd TextChanged,TextChangedI,BufWritePost * call <SID>TablineModified()
augroup END

function! s:PickBuffer() abort
  let items = []
  for buf in s:Buffers()
    let name = bufname(buf)
    call add(items, {
          \ 'bufnr': buf,
          \ 'filename': name ==# '' ? '' : fnamemodify(name, ':p'),
          \ 'label': buf . ': ' . (name ==# '' ? '[No Name]' : fnamemodify(name, ':~:.')),
          \ })
  endfor
  call s:OpenPicker('Buffers', {'items': items})
endfunction

function! s:CycleBuffer(delta) abort
  call s:FocusEditor()
  let items = s:Buffers()
  if empty(items)
    return
  endif
  let index = s:BufferIndex(bufnr('%'), items)
  call s:SelectBuffer(items[(index + a:delta + len(items)) % len(items)])
endfunction

function! s:MoveBuffer(delta) abort
  call s:FocusEditor()
  let items = s:Buffers()
  if empty(s:buffer_order)
    return
  endif
  let index = s:BufferIndex(bufnr('%'), items)
  if items[index] != bufnr('%') | return | endif
  let target = max([0, min([len(s:buffer_order) - 1, index + a:delta])])
  let buf = remove(s:buffer_order, index)
  call insert(s:buffer_order, buf, target)
  let s:tabline_cache = ''
  redrawtabline
endfunction

function! s:CompareBuffersByDirectory(left, right) abort
  let lvalue = fnamemodify(bufname(a:left), ':h')
  let rvalue = fnamemodify(bufname(a:right), ':h')
  return lvalue ==# rvalue ? a:left - a:right : (lvalue <# rvalue ? -1 : 1)
endfunction

function! s:CompareBuffersByLanguage(left, right) abort
  let lvalue = getbufvar(a:left, '&filetype')
  let rvalue = getbufvar(a:right, '&filetype')
  return lvalue ==# rvalue ? a:left - a:right : (lvalue <# rvalue ? -1 : 1)
endfunction

function! s:SortBuffers(kind) abort
  call s:Buffers()
  if a:kind ==# 'directory'
    call sort(s:buffer_order, function('<SID>CompareBuffersByDirectory'))
  else
    call sort(s:buffer_order, function('<SID>CompareBuffersByLanguage'))
  endif
  let s:tabline_cache = ''
  redrawtabline
endfunction

" Keep edit windows alive: switch every view of the target before wiping it.
function! s:WipeBuffer(buf, force) abort
  let terminal = getbufvar(a:buf, '&buftype') ==# 'terminal'
  if !terminal && !s:IsEditorBuffer(a:buf)
    return
  endif
  if getbufvar(a:buf, '&modified') && !terminal && !a:force
    call s:Warn('Unsaved changes: save the buffer before closing')
    return
  endif
  let candidates = filter(s:Buffers(), 'v:val != a:buf')
  let replacement = empty(candidates) ? -1 : candidates[0]
  " win_findbuf() excludes popup windows; close terminal popups explicitly.
  if exists('*popup_list')
    for popup in popup_list()
      if winbufnr(popup) == a:buf
        call popup_close(popup)
      endif
    endfor
  endif
  let origin = win_getid()
  try
    for winid in win_findbuf(a:buf)
      if win_gotoid(winid)
        " Use a real window switch: netrw's BufEnter handler uses :redir,
        " which cannot run inside win_execute()'s output capture.
        if replacement > 0
          execute 'buffer' . (a:force || terminal ? '!' : '') . ' ' . replacement
        else
          " Vim needs one edit buffer when the last file is closed.
          execute 'enew' . (a:force || terminal ? '!' : '')
          let replacement = bufnr('%')
        endif
      endif
    endfor
  finally
    call win_gotoid(origin)
  endtry
  execute 'bwipeout' . (a:force || terminal ? '!' : '') . ' ' . a:buf
  redrawtabline
endfunction

function! s:CloseCurrentBuffer(force) abort
  if &l:buftype !=# 'terminal' | call s:FocusEditor() | endif
  call s:WipeBuffer(bufnr('%'), a:force)
endfunction

function! s:SelectBufferNumber(number) abort
  let items = s:Buffers()
  let index = a:number == 9 ? len(items) - 1 : a:number - 1
  if index >= 0 && index < len(items)
    call s:SelectBuffer(items[index])
  endif
endfunction

function! s:CloseOtherBuffers(side) abort
  call s:FocusEditor()
  let current = bufnr('%')
  let items = s:Buffers()
  let current_index = s:BufferIndex(current, items)
  let index = 0
  for buf in items
    if buf != current && (a:side ==# 'all' || (a:side ==# 'left' && index < current_index) || (a:side ==# 'right' && index > current_index))
      let terminal = getbufvar(buf, '&buftype') ==# 'terminal'
      if terminal || !getbufvar(buf, '&modified')
        call s:WipeBuffer(buf, terminal)
      endif
    endif
    let index += 1
  endfor
endfunction

nnoremap <silent> <S-l> :call <SID>CycleBuffer(1)<CR>
nnoremap <silent> <S-h> :call <SID>CycleBuffer(-1)<CR>
nnoremap <silent> ]b :call <SID>CycleBuffer(1)<CR>
nnoremap <silent> [b :call <SID>CycleBuffer(-1)<CR>
nnoremap <silent> <leader>bj :call <SID>MoveBuffer(-1)<CR>
nnoremap <silent> <leader>bk :call <SID>MoveBuffer(1)<CR>
nnoremap <silent> <leader>bD :call <SID>SortBuffers('directory')<CR>
nnoremap <silent> <leader>bL :call <SID>SortBuffers('language')<CR>
nnoremap <silent> <leader>c :call <SID>CloseCurrentBuffer(1)<CR>
nnoremap <silent> <leader>bw :call <SID>CloseCurrentBuffer(0)<CR>
nnoremap <silent> <leader>bp :call <SID>PickBuffer()<CR>
nnoremap <silent> <leader>sb :call <SID>PickBuffer()<CR>
nnoremap <silent> <leader>be :call <SID>CloseOtherBuffers('all')<CR>
nnoremap <silent> <leader>bm :call <SID>CloseOtherBuffers('all')<CR>
nnoremap <silent> <leader>bh :call <SID>CloseOtherBuffers('left')<CR>
nnoremap <silent> <leader>bl :call <SID>CloseOtherBuffers('right')<CR>
for s:number in range(1, 9)
  execute 'nnoremap <silent> <A-' . s:number . '> :call <SID>SelectBufferNumber(' . s:number . ')<CR>'
endfor
unlet s:number

" =========================================
" ============ ASYNC COMMANDS =============
" =========================================
let s:running = {}
let s:task_sequence = 0

function! s:Warn(message) abort
  echohl WarningMsg
  echomsg a:message
  echohl None
endfunction

function! s:Info(message) abort
  echomsg a:message
endfunction

function! s:TaskCleanup(opts) abort
  for path in get(a:opts, 'cleanup', []) | call delete(path) | endfor
endfunction

function! s:CancelTask(key) abort
  if !has_key(s:running, a:key)
    return
  endif
  let task = remove(s:running, a:key)
  let task.cancelled = 1
  if get(task, 'timer', -1) != -1
    call timer_stop(task.timer)
  endif
  if has_key(task, 'job') && job_status(task.job) ==# 'run'
    call job_stop(task.job, 'kill')
  endif
  call s:TaskCleanup(task.opts)
endfunction

function! s:CancelCommands() abort
  silent doautocmd <nomodeline> User NopackCancel
  for key in keys(copy(s:running))
    call s:CancelTask(key)
  endfor
endfunction

function! s:JobOutput(key, channel, message) abort
  if !has_key(s:running, a:key) || s:running[a:key].job isnot ch_getjob(a:channel)
    return
  endif
  let task = s:running[a:key]
  if task.cancelled || task.limited
    return
  endif
  let remaining = task.limit - task.bytes
  if remaining <= 0
    let task.limited = 1
  else
    let chunk = strpart(a:message, 0, remaining)
    call add(task.chunks, chunk)
    let task.bytes += strlen(chunk)
    if strlen(a:message) > remaining
      let task.limited = 1
    endif
  endif
  if task.limited && job_status(task.job) ==# 'run'
    call job_stop(task.job, 'kill')
  endif
endfunction

function! s:JobError(key, channel, message) abort
  if has_key(s:running, a:key) && s:running[a:key].job is ch_getjob(a:channel)
    let task = s:running[a:key]
    let task.errors = strpart(task.errors . a:message, 0, 8192)
  endif
endfunction

function! s:JobTimedOut(key, sequence, timer) abort
  if !has_key(s:running, a:key) || s:running[a:key].sequence != a:sequence
    return
  endif
  let task = s:running[a:key]
  let task.limited = 1
  if job_status(task.job) ==# 'run'
    call job_stop(task.job, 'kill')
  endif
endfunction

function! s:JobClosed(key, channel) abort
  if has_key(s:running, a:key) && s:running[a:key].job is ch_getjob(a:channel)
    let s:running[a:key].closed = 1
    call s:JobFinished(a:key)
  endif
endfunction

function! s:JobExited(key, job, code) abort
  if has_key(s:running, a:key) && s:running[a:key].job is a:job
    let s:running[a:key].exitcode = a:code
    call s:JobFinished(a:key)
  endif
endfunction

function! s:JobFinished(key) abort
  if !has_key(s:running, a:key) || !get(s:running[a:key], 'closed', 0) || !has_key(s:running[a:key], 'exitcode')
    return
  endif
  let task = remove(s:running, a:key)
  if get(task, 'timer', -1) != -1
    call timer_stop(task.timer)
  endif
  if task.cancelled
    return
  endif
  call s:TaskCleanup(task.opts)
  let code = task.exitcode
  if task.limited && !get(task.opts, 'partial', 0)
    if !get(task.opts, 'quiet', 0)
      call s:Warn(a:key . ': time/output limit exceeded; result discarded')
    endif
    if has_key(task.opts, 'failed')
      call call(task.opts.failed, [])
    endif
    return
  endif
  if !task.limited && code != 0 && !(get(task.opts, 'no_match', 0) && code == 1)
    if !get(task.opts, 'quiet', 0)
      call s:Warn(a:key . ': ' . (task.errors !=# '' ? task.errors : 'command failed (' . code . ')'))
    endif
    if has_key(task.opts, 'failed')
      call call(task.opts.failed, [])
    endif
    return
  endif
  if task.limited && !get(task.opts, 'quiet', 0)
    call s:Warn(a:key . ': limit reached; partial results')
  endif
  call call(task.Callback, [join(task.chunks, ''), task.limited])
endfunction

function! s:RunCommand(key, argv, opts, Callback) abort
  if !exists('*job_start')
    call s:Warn(a:key . ': this Vim build has no +job support')
    if has_key(a:opts, 'failed')
      call call(a:opts.failed, [])
    endif
    return
  endif
  call s:CancelTask(a:key)
  let s:task_sequence += 1
  let task = {
        \ 'sequence': s:task_sequence,
        \ 'chunks': [],
        \ 'bytes': 0,
        \ 'errors': '',
        \ 'limited': 0,
        \ 'cancelled': 0,
        \ 'limit': get(a:opts, 'max_bytes', 2 * 1024 * 1024),
        \ 'opts': a:opts,
        \ 'Callback': a:Callback,
        \ 'timer': -1,
        \ }
  let options = {
        \ 'out_io': 'pipe',
        \ 'err_io': 'pipe',
        \ 'out_mode': 'raw',
        \ 'err_mode': 'raw',
        \ 'out_cb': function('<SID>JobOutput', [a:key]),
        \ 'err_cb': function('<SID>JobError', [a:key]),
        \ 'close_cb': function('<SID>JobClosed', [a:key]),
        \ 'exit_cb': function('<SID>JobExited', [a:key]),
        \ 'stoponexit': 'kill',
        \ }
  let options.in_io = has_key(a:opts, 'stdin') ? 'pipe' : 'null'
  if has_key(a:opts, 'cwd')
    let options.cwd = a:opts.cwd
  endif
  let s:running[a:key] = task
  let job = job_start(a:argv, options)
  let task.job = job
  if job_status(job) ==# 'fail'
    call remove(s:running, a:key)
    call s:TaskCleanup(a:opts)
    if !get(a:opts, 'quiet', 0)
      call s:Warn(a:key . ': unable to start ' . get(a:argv, 0, 'command'))
    endif
    if has_key(a:opts, 'failed')
      call call(a:opts.failed, [])
    endif
    return
  endif
  let task.timer = timer_start(get(a:opts, 'timeout', 5000), function('<SID>JobTimedOut', [a:key, task.sequence]))
  if has_key(a:opts, 'stdin')
    let channel = job_getchannel(job)
    call ch_sendraw(channel, a:opts.stdin)
    call ch_close_in(channel)
  endif
endfunction

function! s:OutputLines(output, limited, ...) abort
  let maximum = a:0 ? a:1 : 0
  let lines = split(a:output, "\n", 1)
  if !empty(lines) && (a:limited || a:output =~# "\n$")
    call remove(lines, -1)
  endif
  if maximum > 0 && len(lines) > maximum
    return lines[0 : maximum - 1]
  endif
  return lines
endfunction

command! NopackCancel call <SID>CloseActivePicker() | call <SID>CancelCommands()

augroup NopackCommands
  autocmd!
  autocmd VimLeavePre * call <SID>CancelCommands()
augroup END

" =========================================
" ============== NATIVE PICKER =============
" =========================================
let s:pickers = {}
let s:active_picker = 0

function! s:CloseActivePicker() abort
  if s:active_picker > 0
    call s:PickerClose(s:active_picker, 0)
  endif
endfunction

function! s:PickerMatches(items, query) abort
  if a:query ==# ''
    return len(a:items) > 200 ? a:items[0:199] : copy(a:items)
  endif
  if exists('*matchfuzzy')
    return matchfuzzy(a:items, a:query, {'key': 'label', 'limit': 200})
  endif
  let query = tolower(a:query)
  return filter(copy(a:items), 'stridx(tolower(get(v:val, "label", "")), query) >= 0')[0:199]
endfunction

function! s:PickerPreview(state, item) abort
  if get(a:state, 'preview', 0) <= 0 | return | endif
  if empty(a:item)
    call popup_settext(a:state.preview, ['No matches'])
    call popup_setoptions(a:state.preview, {'firstline': 1, 'title': ' Preview '})
    return
  endif
  if has_key(a:state.opts, 'preview')
    call call(a:state.opts.preview, [a:state, a:item])
    return
  endif
  let height = a:state.height
  let line = max([1, get(a:item, 'lnum', 1)])
  let first = max([1, line - 8])
  let lines = []
  let buf = get(a:item, 'bufnr', -1)
  let filename = get(a:item, 'filename', '')
  if buf > 0 && bufloaded(buf)
    let source = getbufline(buf, first, first + height - 1)
  elseif filename !=# '' && filereadable(filename) && (getfsize(filename) < 0 || getfsize(filename) <= 2 * 1024 * 1024) && first <= 10000
    try
      let all = readfile(filename, '', min([10000, first + height - 1]))
      let source = first <= len(all) ? all[first - 1 : first + height - 2] : []
    catch
      let source = []
    endtry
  elseif has_key(a:item, 'text')
    let source = split(a:item.text, "\n", 1)
    let first = 1
  else
    let source = ['No text preview']
    let first = 1
  endif
  let number = first
  for text in source
    call add(lines, number . '  ' . strpart(text, 0, 500))
    let number += 1
  endfor
  if empty(lines)
    let lines = ['No text preview']
  endif
  if !empty(popup_getpos(a:state.preview))
    call popup_settext(a:state.preview, lines)
  endif
endfunction

function! s:PickerDraw(id) abort
  let key = string(a:id)
  if !has_key(s:pickers, key) || empty(popup_getpos(a:id))
    return
  endif
  let state = s:pickers[key]
  let match_count = len(state.matches)
  let state.index = match_count == 0 ? 0 : max([0, min([state.index, match_count - 1])])
  let pending = get(state, 'pending', 0) ? '  [searching]' : ''
  let lines = ['> ' . state.query . pending, repeat('-', min([state.list_width - 2, 60]))]
  if match_count == 0
    call add(lines, 'No matches')
    let state.draw_start = 0
    let cursor_line = 3
    let item = {}
  else
    let start = max([0, state.index - (state.height - 1) / 2])
    let start = min([start, max([0, match_count - state.height])])
    let finish = min([match_count - 1, start + state.height - 1])
    for index in range(start, finish)
      call add(lines, substitute(get(state.matches[index], 'label', ''), '[[:cntrl:]]', ' ', 'g'))
    endfor
    let state.draw_start = start
    let cursor_line = 3 + state.index - start
    let item = state.matches[state.index]
  endif
  if get(state, 'drawn_lines', []) !=# lines
    call popup_settext(a:id, lines)
    let state.drawn_lines = lines
  endif
  call win_execute(a:id, 'call cursor(' . cursor_line . ', 1)')
  call s:PickerPreview(state, item)
  if has_key(state.opts, 'highlight') && !empty(item)
    silent! call call(state.opts.highlight, [item])
  endif
endfunction

function! s:PickerFilterItems(id) abort
  let key = string(a:id)
  if !has_key(s:pickers, key)
    return
  endif
  let state = s:pickers[key]
  let state.matches = s:PickerMatches(state.items, state.query)
  let state.index = 0
  call s:PickerDraw(a:id)
endfunction

function! s:PickerSetItems(id, items) abort
  let key = string(a:id)
  if !has_key(s:pickers, key)
    return
  endif
  let state = s:pickers[key]
  let state.items = a:items
  let state.pending = 0
  let state.matches = s:PickerMatches(state.items, state.query)
  let state.index = 0
  call s:PickerDraw(a:id)
endfunction

function! s:PickerLiveTimer(id, generation, timer) abort
  let key = string(a:id)
  if !has_key(s:pickers, key) || s:pickers[key].generation != a:generation
    return
  endif
  let state = s:pickers[key]
  let state.timer = -1
  call call(state.opts.live, [state.query, a:id, a:generation])
endfunction

function! s:PickerQueryChanged(id) abort
  let key = string(a:id)
  if !has_key(s:pickers, key)
    return
  endif
  let state = s:pickers[key]
  let state.generation += 1
  if get(state, 'timer', -1) != -1
    call timer_stop(state.timer)
  endif
  if has_key(state.opts, 'live')
    if has_key(state.opts, 'cancel')
      silent! call call(state.opts.cancel, [])
    endif
    let state.pending = 1
    let state.matches = []
    let state.index = 0
    call s:PickerDraw(a:id)
    let state.timer = timer_start(120, function('<SID>PickerLiveTimer', [a:id, state.generation]))
  else
    call s:PickerFilterItems(a:id)
  endif
endfunction

function! s:PickerMove(id, delta) abort
  let key = string(a:id)
  if !has_key(s:pickers, key) || empty(s:pickers[key].matches)
    return
  endif
  let state = s:pickers[key]
  let state.index = (state.index + a:delta + len(state.matches)) % len(state.matches)
  call s:PickerDraw(a:id)
endfunction

function! s:PickerClosed(id, result) abort
  let key = string(a:id)
  if !has_key(s:pickers, key)
    return
  endif
  let state = remove(s:pickers, key)
  if get(state, 'timer', -1) != -1
    call timer_stop(state.timer)
  endif
  if get(state, 'preview', 0) > 0 && !empty(popup_getpos(state.preview))
    call popup_close(state.preview)
  endif
  if has_key(state.opts, 'cancel')
    silent! call call(state.opts.cancel, [])
  endif
  if !get(state, 'accepted', 0) && has_key(state.opts, 'on_cancel')
    silent! call call(state.opts.on_cancel, [])
  endif
  if win_id2win(state.origin) > 0
    call win_gotoid(state.origin)
  endif
  if s:active_picker == a:id
    let s:active_picker = 0
  endif
endfunction

function! s:PickerClose(id, accepted) abort
  let key = string(a:id)
  if !has_key(s:pickers, key)
    return
  endif
  let s:pickers[key].accepted = a:accepted
  if !empty(popup_getpos(a:id))
    call popup_close(a:id)
  else
    call s:PickerClosed(a:id, 0)
  endif
endfunction

function! s:PickerAccept(id) abort
  let key = string(a:id)
  if !has_key(s:pickers, key)
    return
  endif
  let state = s:pickers[key]
  if empty(state.matches)
    return
  endif
  let item = state.matches[state.index]
  let target = state.target
  call s:PickerClose(a:id, 1)
  if s:IsEditorWindow(target)
    call win_gotoid(target)
  else
    call s:FocusEditor()
  endif
  if has_key(item, 'action')
    call call(item.action, [])
    return
  endif
  let buf = get(item, 'bufnr', -1)
  if buf > 0 && bufexists(buf)
    execute 'buffer ' . buf
  elseif get(item, 'filename', '') !=# ''
    execute 'edit ' . fnameescape(item.filename)
  endif
  if has_key(item, 'lnum')
    call cursor(min([max([1, item.lnum]), line('$')]), max([1, get(item, 'col', 1)]))
    normal! zz
  endif
endfunction

function! s:QuickfixItems(items) abort
  let result = []
  for item in a:items
    if has_key(item, 'filename') || has_key(item, 'bufnr')
      let entry = {}
      for name in ['filename', 'bufnr', 'lnum', 'col', 'text', 'type']
        if has_key(item, name) && item[name] !=# ''
          let entry[name] = item[name]
        endif
      endfor
      call add(result, entry)
    endif
  endfor
  return result
endfunction

function! s:ShowResults(items, title) abort
  let items = s:QuickfixItems(a:items)
  if empty(items)
    call s:Info('No results: ' . a:title)
    return
  endif
  call setqflist([], ' ', {'title': a:title, 'items': items})
  call s:FocusEditor()
  botright copen
  setlocal nobuflisted nowrap
endfunction

function! s:PickerSendQuickfix(id) abort
  let key = string(a:id)
  if !has_key(s:pickers, key)
    return
  endif
  let items = copy(s:pickers[key].matches)
  let title = s:pickers[key].title
  call s:PickerClose(a:id, 1)
  call s:ShowResults(items, title)
endfunction

function! s:PickerFilter(id, key) abort
  if a:key ==# "\<Esc>" || a:key ==# "\<C-C>"
    call s:PickerClose(a:id, 0)
  elseif a:key ==# "\<CR>"
    call s:PickerAccept(a:id)
  elseif index(["\<C-N>", "\<Down>", "\<Tab>"], a:key) >= 0
    call s:PickerMove(a:id, 1)
  elseif index(["\<C-P>", "\<Up>", "\<S-Tab>"], a:key) >= 0
    call s:PickerMove(a:id, -1)
  elseif index(["\<C-F>", "\<C-B>"], a:key) >= 0 && has_key(s:pickers[string(a:id)].opts, 'preview')
    let preview = s:pickers[string(a:id)].preview
    if preview > 0
      let delta = s:pickers[string(a:id)].height / 2 * (a:key ==# "\<C-F>" ? 1 : -1)
      let first = max([1, popup_getpos(preview).firstline + delta])
      call popup_setoptions(preview, {'firstline': min([first, len(getbufline(winbufnr(preview), 1, '$'))])})
    endif
  elseif a:key ==# "\<C-Q>"
    call s:PickerSendQuickfix(a:id)
  elseif index(["\<BS>", "\<C-H>", "\<Del>"], a:key) >= 0
    let state = s:pickers[string(a:id)]
    let state.query = strcharpart(state.query, 0, max([0, strchars(state.query) - 1]))
    call s:PickerQueryChanged(a:id)
  elseif a:key ==# "\<C-U>"
    let s:pickers[string(a:id)].query = ''
    call s:PickerQueryChanged(a:id)
  elseif strchars(a:key) == 1 && char2nr(a:key) >= 32
    let s:pickers[string(a:id)].query .= a:key
    call s:PickerQueryChanged(a:id)
  endif
  return 1
endfunction

function! s:OpenPicker(title, opts) abort
  if !exists('*popup_create')
    call s:Warn('This picker requires Vim +popupwin support')
    return 0
  endif
  call s:CloseActivePicker()
  let origin = win_getid()
  call s:FocusEditor()
  let target = win_getid()
  let width = max([24, min([&columns - 4, 120])])
  let height = max([4, min([&lines - 8, 22])])
  let list_width = width >= 70 || has_key(a:opts, 'preview') ? width * 48 / 100 : width
  let row = max([1, (&lines - height - 4) / 2])
  let col = max([1, (&columns - width) / 2])
  let state = {
        \ 'title': a:title,
        \ 'opts': a:opts,
        \ 'origin': origin,
        \ 'target': target,
        \ 'items': [],
        \ 'matches': [],
        \ 'query': '',
        \ 'index': 0,
        \ 'generation': 0,
        \ 'timer': -1,
        \ 'pending': 0,
        \ 'accepted': 0,
        \ 'height': height,
        \ 'list_width': list_width,
        \ 'preview': 0,
        \ }
  if list_width < width
    let state.preview = popup_create([''], {
          \ 'title': ' Preview ',
          \ 'pos': 'topleft',
          \ 'line': row,
          \ 'col': col + list_width + 2,
          \ 'minwidth': width - list_width - 2,
          \ 'maxwidth': width - list_width - 2,
          \ 'minheight': height + 2,
          \ 'maxheight': height + 2,
          \ 'border': [1, 1, 1, 1],
          \ 'padding': [0, 1, 0, 1],
          \ 'wrap': 0,
          \ 'zindex': 199,
          \ })
    " A window-local match follows preview text updates and disappears on close.
    let word = get(a:opts, 'preview_word', '')
    if word !=# ''
      let pattern = '\C\<\V' . escape(word, '\') . '\m\>'
      call win_execute(state.preview, 'call matchadd(''Search'', ' . string(pattern) . ')')
    endif
  endif
  let id = popup_create(['> ', '--', 'No matches'], {
        \ 'title': ' ' . a:title . ' ',
        \ 'pos': 'topleft',
        \ 'line': row,
        \ 'col': col,
        \ 'minwidth': list_width,
        \ 'maxwidth': list_width,
        \ 'minheight': height + 2,
        \ 'maxheight': height + 2,
        \ 'border': [1, 1, 1, 1],
        \ 'padding': [0, 1, 0, 1],
        \ 'mapping': 0,
        \ 'filter': function('<SID>PickerFilter'),
        \ 'callback': function('<SID>PickerClosed'),
        \ 'cursorline': 1,
        \ 'wrap': 0,
        \ 'zindex': 200,
        \ })
  let state.id = id
  let s:pickers[string(id)] = state
  let s:active_picker = id
  call s:PickerSetItems(id, get(a:opts, 'items', []))
  return id
endfunction

" =========================================
" =========== PICKER INTEGRATIONS =========
" =========================================
function! s:RelativeLabel(filename, root) abort
  let prefix = a:root ==# '/' ? '/' : a:root . '/'
  return a:root !=# '' && stridx(a:filename, prefix) == 0
        \ ? strpart(a:filename, len(prefix)) : fnamemodify(a:filename, ':~:.')
endfunction

function! s:FileItems(files, ...) abort
  let root = a:0 ? a:1 : ''
  let items = []
  for file in a:files
    if file ==# ''
      continue
    endif
    let filename = file[0] ==# '/' ? file : (root ==# '' ? fnamemodify(file, ':p') : root . '/' . file)
    call add(items, {'filename': filename, 'lnum': 1, 'label': s:RelativeLabel(filename, root)})
  endfor
  return items
endfunction

function! s:CancelSearch() abort
  call s:CancelTask('search')
endfunction

function! s:FilePickerFailed(id) abort
  call s:PickerSetItems(a:id, [])
endfunction

function! s:FilePickerFinished(id, root, output, limited) abort
  let files = s:OutputLines(a:output, a:limited, 10000)
  call s:PickerSetItems(a:id, s:FileItems(files, a:root))
endfunction

function! s:FilePicker(title, root, command) abort
  let id = s:OpenPicker(a:title, {'cancel': function('<SID>CancelSearch')})
  if id == 0
    return 0
  endif
  let s:pickers[string(id)].pending = 1
  call s:PickerDraw(id)
  call s:RunCommand('search', a:command, {
        \ 'cwd': a:root,
        \ 'partial': 1,
        \ 'failed': function('<SID>FilePickerFailed', [id]),
        \ }, function('<SID>FilePickerFinished', [id, a:root]))
  return id
endfunction

function! s:FindFiles(root, title) abort
  if !isdirectory(a:root)
    call s:Warn('Directory not found: ' . a:root)
    return
  endif
  call s:FilePicker(a:title, a:root, [
        \ 'find', a:root,
        \ '-type', 'd', '(',
        \ '-name', '.git', '-o',
        \ '-name', 'node_modules', '-o',
        \ '-name', '__pycache__',
        \ ')', '-prune', '-o',
        \ '-type', 'f', '-print',
        \ ])
endfunction

function! s:FindProjectFiles() abort
  let project = s:ProjectRoot()
  call s:FindFiles(project.root, 'Find files')
endfunction

function! s:FindVimFiles() abort
  let root = fnamemodify(s:vimrc_path, ':h')
  call s:FindFiles(root, 'Vim files')
endfunction

function! s:RecentFiles() abort
  let files = filter(map(copy(v:oldfiles), 'fnamemodify(v:val, ":p")'), 'filereadable(v:val)')
  call s:OpenPicker('Recent files', {'items': s:FileItems(files)})
endfunction

nnoremap <silent> <leader>f :call <SID>FindProjectFiles()<CR>
nnoremap <silent> <leader>sn :call <SID>FindVimFiles()<CR>
nnoremap <silent> <leader>sr :call <SID>RecentFiles()<CR>

function! s:FeedCommand(name) abort
  call feedkeys(':' . a:name . ' ', 'n')
endfunction

function! s:OpenHelp(name) abort
  execute 'help ' . fnameescape(a:name)
endfunction

function! s:SetColorscheme(name, background) abort
  " Each preview starts from the user's preference, not the previous theme's setting.
  let &background = a:background
  execute 'colorscheme ' . fnameescape(a:name)
endfunction

function! s:PreviewColorscheme(background, item) abort
  call s:SetColorscheme(a:item.label, a:background)
endfunction

function! s:RestoreColorscheme(name, background) abort
  call s:SetColorscheme(a:name, a:background)
  let &background = a:background
endfunction

function! s:CommandPicker(title, kind, Action) abort
  let items = []
  for name in getcompletion('', a:kind)
    call add(items, {'label': name, 'action': function(a:Action, [name])})
  endfor
  call s:OpenPicker(a:title, {'items': items})
endfunction

function! s:PickCommands() abort
  call s:CommandPicker('Commands', 'command', '<SID>FeedCommand')
endfunction

function! s:PickHelp() abort
  call s:CommandPicker('Help', 'help', '<SID>OpenHelp')
endfunction

function! s:PickColorschemes() abort
  let original = get(g:, 'colors_name', 'default')
  let background = &background
  let items = []
  for name in getcompletion('', 'color')
    call add(items, {'label': name, 'action': function('<SID>SetColorscheme', [name, background])})
  endfor
  call s:OpenPicker('Colorschemes', {
        \ 'items': items,
        \ 'highlight': function('<SID>PreviewColorscheme', [background]),
        \ 'on_cancel': function('<SID>RestoreColorscheme', [original, background]),
        \ })
endfunction

function! s:PickKeymaps() abort
  let items = []
  if exists('*maplist')
    for mapping in maplist()
      let mode = get(mapping, 'mode', '')
      let lhs = get(mapping, 'lhs', '')
      let rhs = get(mapping, 'rhs', '')
      call add(items, {'label': mode . ' ' . lhs . '  ' . (rhs ==# '' ? 'callback' : rhs)})
    endfor
  else
    for line in split(execute('silent map'), "\n")
      call add(items, {'label': line})
    endfor
  endif
  call s:OpenPicker('Keymaps', {'items': items})
endfunction

nnoremap <silent> <leader>sc :call <SID>PickCommands()<CR>
nnoremap <silent> <leader>sh :call <SID>PickHelp()<CR>
nnoremap <silent> <leader>sp :call <SID>PickColorschemes()<CR>
nnoremap <silent> <leader>sk :call <SID>PickKeymaps()<CR>

function! s:SearchFailed(Callback) abort
  call call(a:Callback, [[]])
endfunction

function! s:SearchFinished(use_rg, root, Callback, output, limited) abort
  let items = []
  for line in s:OutputLines(a:output, a:limited, 10000)
    if a:use_rg
      let match = matchlist(line, '^\(.\{-}\):\(\d\+\):\(\d\+\):\(.*\)$')
      if empty(match)
        continue
      endif
      let filename = match[1]
      let lnum = str2nr(match[2])
      let column = str2nr(match[3])
      let content = match[4]
    else
      let match = matchlist(line, '^\(.\{-}\):\(\d\+\):\(.*\)$')
      if empty(match)
        continue
      endif
      let filename = match[1]
      let lnum = str2nr(match[2])
      let column = 1
      let content = match[3]
    endif
    if filename !~# '^/'
      let filename = a:root . '/' . filename
    endif
    let label = s:RelativeLabel(filename, a:root) . ':' . lnum . ' ' . strpart(content, 0, 200)
    call add(items, {
          \ 'filename': filename,
          \ 'lnum': lnum,
          \ 'col': column,
          \ 'text': strpart(content, 0, 300),
          \ 'label': label,
          \ })
  endfor
  call call(a:Callback, [items])
endfunction

function! s:Search(text, paths, root, fixed, Callback) abort
  if a:text ==# ''
    call call(a:Callback, [[]])
    return
  endif
  let use_rg = executable('rg')
  if use_rg
    let argv = [
          \ 'rg', '--vimgrep', a:fixed ? '--case-sensitive' : '--smart-case',
          \ '--max-columns', '300', '--max-columns-preview',
          \ '--max-filesize', '2M',
          \ '--glob', '!.git/**',
          \ '--glob', '!node_modules/**',
          \ '--glob', '!__pycache__/**',
          \ '--', a:text,
          \ ]
    if a:fixed
      call insert(argv, '--fixed-strings', 1)
      call insert(argv, '--word-regexp', 1)
    endif
  else
    let argv = [
          \ 'grep', '-r', '-n', '-H', '-I',
          \ a:fixed ? '-F' : '-E',
          \ '--exclude-dir=.git',
          \ '--exclude-dir=node_modules',
          \ '--exclude-dir=__pycache__',
          \ ]
    if a:fixed
      call add(argv, '-w')
    elseif a:text !~# '\u'
      call add(argv, '-i')
    endif
    call extend(argv, ['-e', a:text, '--'])
  endif
  call extend(argv, a:paths)
  call s:RunCommand('search', argv, {
        \ 'cwd': a:root,
        \ 'partial': 1,
        \ 'no_match': 1,
        \ 'failed': function('<SID>SearchFailed', [a:Callback]),
        \ }, function('<SID>SearchFinished', [use_rg, a:root, a:Callback]))
endfunction

function! s:PickerSearchResults(id, generation, items) abort
  let key = string(a:id)
  if has_key(s:pickers, key) && (a:generation < 0 || s:pickers[key].generation == a:generation)
    call s:PickerSetItems(a:id, a:items)
  endif
endfunction

function! s:UpdateTextPicker(paths, root, fixed, text, id, generation) abort
  call s:CancelSearch()
  if a:text ==# '' || empty(a:paths)
    call s:PickerSearchResults(a:id, a:generation, [])
    return
  endif
  call s:Search(a:text, a:paths, a:root, a:fixed,
        \ function('<SID>PickerSearchResults', [a:id, a:generation]))
endfunction

function! s:TextPicker(open_only, ...) abort
  let project = s:ProjectRoot()
  let root = project.root
  let paths = [root]
  if a:open_only
    let paths = []
    for buf in s:Buffers()
      let name = bufname(buf)
      if s:IsSource(buf) && name !=# ''
        call add(paths, fnamemodify(name, ':p'))
      endif
    endfor
  endif
  let has_word = a:0 > 0
  let word = has_word ? a:1 : ''
  let title = has_word ? 'Word: ' . word : (a:open_only ? 'Grep open files' : 'Live grep')
  let opts = {'cancel': function('<SID>CancelSearch')}
  if has_word
    let opts.preview_word = word
  else
    let opts.live = function('<SID>UpdateTextPicker', [paths, root, 0])
  endif
  let id = s:OpenPicker(title, opts)
  if id > 0 && has_word
    let s:pickers[string(id)].pending = 1
    call s:PickerDraw(id)
    call s:UpdateTextPicker(paths, root, 1, word, id, -1)
  endif
endfunction

function! s:TextPickerWord() abort
  call s:TextPicker(0, expand('<cword>'))
endfunction

nnoremap <silent> <leader>st :call <SID>TextPicker(0)<CR>
nnoremap <silent> <leader>t :call <SID>TextPickerWord()<CR>
nnoremap <silent> <leader>s/ :call <SID>TextPicker(1)<CR>
" =========================================
" ========= CTAGS: DEFINITIONS / OUTLINE ===
" =========================================
let s:tag_projects = {}
let s:ctags_checked = ''
let s:ctags_kind = ''
let s:ctags_command = ''
let s:managed_tags = {}

function! s:CtagsCandidates() abort
  let candidates = []
  if exists('g:nopack_ctags') && g:nopack_ctags !=# ''
    call add(candidates, expand(g:nopack_ctags))
  endif
  for directory in split($PATH, has('win32') ? ';' : ':')
    call add(candidates, directory . (directory =~# '[\\/]$' ? '' : '/') . (has('win32') ? 'ctags.exe' : 'ctags'))
  endfor
  return uniq(candidates)
endfunction

function! s:CtagsAvailable(...) abort
  let candidates = s:CtagsCandidates()
  let checked = string(candidates)
  if checked !=# s:ctags_checked
    let s:ctags_checked = checked
    let s:ctags_kind = ''
    let s:ctags_command = ''
    let fallback = ''
    for command in candidates
      if !executable(command)
        continue
      endif
      let ctags_version = system(shellescape(command) . ' --options=NONE --version')
      let kind = ctags_version =~# 'Universal Ctags' ? 'universal'
            \ : ctags_version =~# 'Exuberant Ctags' ? 'exuberant' : ''
      if kind ==# 'universal'
        let s:ctags_kind = 'universal'
        let s:ctags_command = command
        break
      elseif kind ==# 'exuberant' && fallback ==# ''
        let fallback = command
      endif
    endfor
    if s:ctags_kind ==# '' && fallback !=# ''
      let s:ctags_kind = 'exuberant'
      let s:ctags_command = fallback
    endif
  endif
  if s:ctags_kind ==# '' && !(a:0 && a:1)
    call s:Warn('Universal or Exuberant Ctags is required; check ctags --version or set g:nopack_ctags to its executable')
  endif
  return s:ctags_kind !=# ''
endfunction

function! s:UseTags(buf, path) abort
  let tags = getbufvar(a:buf, '&tags')
  let previous = get(s:managed_tags, string(a:buf), '')
  if previous !=# '' && stridx(tags, previous) == 0
    let tags = strpart(tags, strlen(previous))
  endif
  let prefix = a:path ==# '' ? '' : escape(a:path, ' ,\') . ','
  call setbufvar(a:buf, '&tags', prefix . tags)
  if prefix ==# ''
    if has_key(s:managed_tags, string(a:buf)) | call remove(s:managed_tags, string(a:buf)) | endif
  else
    let s:managed_tags[string(a:buf)] = prefix
  endif
endfunction

function! s:TagsAttach(buf) abort
  if !bufexists(a:buf) | return | endif
  if !s:BufferAllows(a:buf) || bufname(a:buf) ==# ''
    call s:UseTags(a:buf, '')
    return
  endif
  let root = s:ProjectRoot(a:buf).root
  call s:UseTags(a:buf, get(get(s:tag_projects, root, {}), 'path', ''))
endfunction

" A tab-local right sidebar; its scratch buffer is wiped when the window closes.
function! s:OutlineClose() abort
  if winnr('$') == 1
    enew
  else
    close
  endif
endfunction

" Both automatic following and Enter require the same saved source snapshot.
function! s:OutlineValid(outline) abort
  return s:BufferAllows(a:outline.source) && !getbufvar(a:outline.source, '&modified')
        \ && s:SourceUnchanged(a:outline.context) && s:IsEditorWindow(a:outline.target)
        \ && winbufnr(a:outline.target) == a:outline.source
endfunction

function! s:OutlineFollow() abort
  let sidebar = get(t:, 'nopack_outline_win', 0)
  if sidebar == 0 || win_id2win(sidebar) == 0 | return | endif
  let outline = getbufvar(winbufnr(sidebar), 'nopack_outline', {})
  if empty(outline) || !s:OutlineValid(outline) | return | endif
  if win_getid() == sidebar
    let row = line('.')
    if row < 1 || row > len(outline.items) || row == outline.selected_row | return | endif
    let outline.selected_row = row
    call win_execute(outline.target, ['noautocmd call cursor(' . outline.items[row - 1].lnum . ', 1)',
          \ 'noautocmd normal! zvzz'])
  elseif win_getid() == outline.target
    " Ctags has declaration lines, not enclosing ranges. Find the last preceding tag.
    let low = 0
    let high = len(outline.items)
    while low < high
      let middle = (low + high) / 2
      if outline.items[middle].lnum <= line('.')
        let low = middle + 1
      else
        let high = middle
      endif
    endwhile
    if low == 0 | return | endif
    let row = low
    if row != outline.selected_row
      let outline.selected_row = row
      call win_execute(sidebar, ['noautocmd call cursor(' . row . ', 1)', 'noautocmd normal! zz'])
    endif
  endif
endfunction

augroup NopackOutlineFollow
  autocmd!
  autocmd CursorMoved,CursorMovedI,BufEnter * call s:OutlineFollow()
augroup END

function! s:OutlineJump() abort
  let index = line('.') - 1
  let items = b:nopack_outline.items
  if index < 0 || index >= len(items)
    return
  endif
  let item = items[index]
  let target = b:nopack_outline.target
  let source = b:nopack_outline.source
  if !s:OutlineValid(b:nopack_outline)
    call s:Warn('The source or editor changed; save the file and press r to refresh the outline')
    return
  endif
  call win_gotoid(target)
  normal! m'
  execute 'buffer ' . source
  call cursor(min([item.lnum, line('$')]), 1)
  normal! zz
endfunction

function! s:OutlineShow(source, target, items) abort
  execute 'rightbelow vertical ' . max([20, min([40, &columns / 4])]) . 'new'
  call s:OwnUtilityWindow()
  setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile
  setlocal nonumber norelativenumber nowrap winfixwidth nocursorcolumn cursorline
  setlocal nospell nolist signcolumn=no foldcolumn=0
  let b:nopack_outline = {'source': a:source, 'target': a:target, 'items': a:items, 'context': s:SourceContext(a:source), 'selected_row': 1}
  let t:nopack_outline_win = win_getid()
  let title = 'Outline: ' . substitute(fnamemodify(bufname(a:source), ':t'), '[\r\n\t]', ' ', 'g')
  let w:nopack_outline_menu = 'WinBar.' . escape(title, ' .\|')
  execute 'nnoremenu <silent> ' . w:nopack_outline_menu . ' <Nop>'
  let &l:statusline = ' ' . substitute(title, '%', '%%', 'g')
  let labels = map(copy(a:items), 'v:val.label')
  call setline(1, empty(labels) ? ['No symbols in saved file'] : labels)
  for group in ['Function', 'Type', 'Identifier', 'Comment']
    call prop_type_add('NopackOutline' . group, {'bufnr': bufnr('%'), 'highlight': group})
  endfor
  for index in range(len(a:items))
    let item = a:items[index]
    let group = index(['function', 'method', 'constructor'], item.kind) >= 0 ? 'Function'
          \ : index(['class', 'struct', 'interface', 'enum'], item.kind) >= 0 ? 'Type' : 'Identifier'
    call prop_add(index + 1, item.name_col, {'type': 'NopackOutline' . group, 'length': item.name_length})
    call prop_add(index + 1, item.name_col - strlen(item.kind) - 1,
          \ {'type': 'NopackOutlineComment', 'length': strlen(item.kind)})
  endfor
  setlocal nomodifiable
  nnoremap <silent><buffer> <CR> :call <SID>OutlineJump()<CR>
  nnoremap <silent><buffer> q :call <SID>OutlineClose()<CR>
  nnoremap <silent><buffer> <Esc> :call <SID>OutlineClose()<CR>
  nnoremap <silent><buffer> r :call <SID>OutlineRefresh()<CR>
  call cursor(1, 1)
  call win_execute(a:target, 'call <SID>OutlineFollow()')
endfunction

function! s:OutlineRefresh() abort
  let outline = b:nopack_outline
  call s:OutlineClose()
  if win_gotoid(outline.target) && bufnr('%') == outline.source
    call s:CtagsOpen('outline')
  endif
endfunction

function! s:TagsShow(context, win, root, mode, word, position) abort
  let buf = a:context.buf
  if !s:BufferAllows(buf) || !s:SourceUnchanged(a:context) | return | endif
  " A background build must not redirect a window now editing another file.
  if win_getid() != a:win || winbufnr(a:win) != buf
        \ || (a:mode ==# 'definition' && getcurpos()[1:2] != a:position)
    call s:Info('Ctags index ready; reopen definition/outline in the desired file')
    return
  endif
  call s:UseTags(buf, s:tag_projects[a:root].path)
  if a:mode ==# 'definition'
    if empty(taglist('\C^\V' . escape(a:word, '\') . '\m$', expand('%:p')))
      call s:Warn('No definition in saved project files: ' . a:word)
      return
    endif
    " Native tag selection preserves the tag stack and offers duplicate names.
    execute 'tjump ' . fnameescape(a:word)
    return
  endif
  let filename = resolve(expand('%:p'))
  let items = []
  for tag in taglist('.')
    if resolve(fnamemodify(tag.filename, ':p')) !=# filename
      continue
    endif
    let scope = ''
    for kind in ['class', 'struct', 'namespace', 'union', 'enum', 'function', 'scope']
      if has_key(tag, kind)
        let scope = tag[kind]
        break
      endif
    endfor
    let depth = scope ==# '' ? 0 : len(split(scope, '::\|\.'))
    let number = str2nr(get(tag, 'line', '0'))
    if number > 0
      let kind = get(tag, 'kind', 'symbol')
      let kind_label = toupper(strpart(kind, 0, 1)) . strpart(kind, 1)
      call add(items, {'label': repeat('  ', depth) . kind_label . ' ' . tag.name
            \ . (scope ==# '' ? '' : ' (' . scope . ')'), 'filename': filename, 'lnum': number,
            \ 'kind': kind, 'name_col': depth * 2 + strlen(kind_label) + 2, 'name_length': strlen(tag.name)})
    endif
  endfor
  call sort(items, {a, b -> a.lnum - b.lnum})
  call s:OutlineShow(buf, a:win, items)
endfunction

function! s:TagsBuilt(root, files, After, output, limited) abort
  let project = s:tag_projects[a:root]
  " Replace only a complete successful index; errors keep the previous one.
  let temporary = project.path . '.' . getpid() . '.tmp'
  try
    let lines = split(a:output, "\n")
    if !empty(a:files) && filereadable(project.path)
      " Replace all old definitions from saved files, including deleted symbols.
      let old = readfile(project.path)
      call filter(old, 'v:val !~# "^!_TAG_" && index(a:files, get(split(v:val, "\t"), 1, "")) < 0')
      call filter(lines, 'v:val !~# "^!_TAG_"')
      let lines = sort(old + lines)
    endif
    call writefile(lines, temporary)
    if rename(temporary, project.path) != 0
      throw 'Unable to replace ctags cache'
    endif
    if empty(a:files)
      let project.ready = 1
    endif
  catch
    call s:TagsFailed(a:root)
    call s:Warn('Unable to save ctags cache: ' . v:exception)
    return
  finally
    call delete(temporary)
  endtry
  for info in getbufinfo({'bufloaded': 1})
    call s:TagsAttach(info.bufnr)
  endfor
  let project.busy = 0
  call s:TagsDrain(a:root)
endfunction

function! s:TagsCommand() abort
  " Both produce extended Vim tags; Exuberant uses older option names/values.
  let format = s:ctags_kind ==# 'exuberant'
        \ ? ['--format=2', '--extra=-q', '--tag-relative=no']
        \ : ['--output-format=e-ctags', '--extras=-q', '--tag-relative=never']
  return [s:ctags_command, '--options=NONE'] + format
        \ + ['--fields=+nK', '--sort=yes', '--links=no',
        \ '--langmap=C++:+.ipp.cu.cuh,Python:+.pyi', '-f', '-']
endfunction

function! s:TagsRun(root, files, After, command, opts) abort
  let s:tag_projects[a:root].active_files = a:files
  let opts = extend(copy(a:opts), {'failed': function('<SID>TagsFailed', [a:root])})
  call s:RunCommand('ctags:' . a:root, a:command, opts,
        \ function('<SID>TagsBuilt', [a:root, a:files, a:After]))
endfunction

function! s:TagsGitFiles(root, After, output, limited) abort
  let files = []
  " Git supplies tracked + untracked source files, respecting .gitignore.
  for file in split(a:output, "\n")
    if file =~# '^"'
      try
        let file = json_decode(file)
      catch
        call s:Warn('Ctags skipped an unrepresentable filename: ' . file)
        continue
      endtry
    endif
    if file !~# '[\r\n]' && filereadable(a:root . '/' . file)
      call add(files, a:root . '/' . file)
    endif
  endfor
  if empty(files)
    call s:TagsBuilt(a:root, [], a:After, '', 0)
    return
  endif
  call s:TagsRun(a:root, [], a:After, s:TagsCommand() + ['-L', '-'],
        \ {'cwd': a:root, 'stdin': join(uniq(sort(files)), "\n") . "\n", 'timeout': 120000,
        \ 'max_bytes': 64 * 1024 * 1024})
endfunction

function! s:TagsBuild(root, After, ...) abort
  let project = s:tag_projects[a:root]
  if project.timer != -1
    call timer_stop(project.timer)
    let project.timer = -1
  endif
  if type(a:After) == v:t_func | call add(project.callbacks, a:After) | endif
  if a:0
    for file in a:1 | let project.pending[file] = 1 | endfor
  elseif !project.busy || !project.building_full
    let project.full = 1
  endif
  call s:TagsDrain(a:root)
endfunction

function! s:TagsFailed(root) abort
  let project = s:tag_projects[a:root]
  let project.busy = 0
  let project.full = 1
  let project.callbacks = []
  for info in getbufinfo({'bufloaded': 1})
    if s:IsSource(info.bufnr) && s:ProjectRoot(info.bufnr).root ==# a:root
      call setbufvar(info.bufnr, 'nopack_tags_requested', 0)
    endif
  endfor
endfunction

function! s:TagsDrain(root) abort
  let project = s:tag_projects[a:root]
  if project.busy | return | endif
  let full = project.full
  let files = sort(keys(project.pending))
  if !full && empty(files)
    let callbacks = project.callbacks
    let project.callbacks = []
    for Callback in callbacks | call call(Callback, []) | endfor
    return
  endif
  let project.pending = {}
  let project.full = 0
  let project.busy = 1
  let project.building_full = full
  if !full
    call s:TagsRun(a:root, files, 0, s:TagsCommand() + ['-L', '-'],
          \ {'cwd': a:root, 'stdin': join(files, "\n") . "\n", 'timeout': 30000, 'max_bytes': 16 * 1024 * 1024})
  elseif getftype(a:root . '/.git') !=# ''
    " Disable Git's non-ASCII quoting. Unrepresentable newline names are skipped.
    call s:RunCommand('ctags:' . a:root,
          \ ['git', '-c', 'core.quotepath=false', 'ls-files', '--cached', '--others', '--exclude-standard'],
          \ {'cwd': a:root, 'timeout': 30000, 'max_bytes': 16 * 1024 * 1024,
          \ 'failed': function('<SID>TagsFailed', [a:root])}, function('<SID>TagsGitFiles', [a:root, 0]))
  else
    call s:TagsRun(a:root, [], 0, s:TagsCommand() + [
          \ '--exclude=.git', '--exclude=.venv', '--exclude=venv', '--exclude=node_modules',
          \ '--exclude=__pycache__', '--exclude=build', '--exclude=build-*',
          \ '--exclude=cmake-build-*', '--exclude=dist', '-R', a:root],
          \ {'cwd': a:root, 'timeout': 120000, 'max_bytes': 64 * 1024 * 1024})
  endif
endfunction

function! s:CtagsOpen(mode) abort
  if a:mode ==# 'outline'
    for winid in s:TabWindows()
      if !empty(getbufvar(winbufnr(winid), 'nopack_outline', {}))
        let origin = win_getid()
        call win_gotoid(winid)
        call s:OutlineClose()
        call win_gotoid(origin)
        return
      endif
    endfor
  endif
  call s:FocusEditor()
  if !s:BufferAllows(bufnr('%')) || expand('%:p') ==# '' || !s:CtagsAvailable()
    return
  endif
  let root = s:ProjectRoot().root
  let word = expand('<cword>')
  if a:mode ==# 'definition' && word ==# ''
    return
  endif
  if &modified
    call s:Info('Ctags uses saved files; save changes to update definitions and line numbers')
  endif
  if !has_key(s:tag_projects, root)
    call mkdir(s:nopack_data . '/tags', 'p')
    let s:tag_projects[root] = {'path': s:nopack_data . '/tags/' . sha256(root), 'ready': 0, 'timer': -1, 'pending': {}, 'callbacks': [], 'full': 0, 'busy': 0, 'building_full': 0}
  endif
  let After = function('<SID>TagsShow', [s:SourceContext(bufnr('%')), win_getid(), root, a:mode, word, getcurpos()[1:2]])
  if a:mode ==# 'refresh'
    call s:TagsBuild(root, 0)
  elseif a:mode ==# 'outline' || a:mode ==# 'completion'
    call s:TagsBuild(root, a:mode ==# 'outline' ? After : 0, [resolve(expand('%:p'))])
  elseif s:tag_projects[root].ready
    call s:TagsBuild(root, After, [])
  else
    call s:Info('Building project ctags index…')
    call s:TagsBuild(root, After)
  endif
endfunction

function! s:TagsRefresh(root, timer) abort
  if !has_key(s:tag_projects, a:root) || s:tag_projects[a:root].timer != a:timer | return | endif
  let s:tag_projects[a:root].timer = -1
  call s:TagsBuild(a:root, 0, [])
endfunction

function! s:TagsSaved(buf) abort
  if !s:BufferAllows(a:buf) || bufname(a:buf) ==# ''
    return
  endif
  let root = s:ProjectRoot(a:buf).root
  if !has_key(s:tag_projects, root)
    return
  endif
  let project = s:tag_projects[root]
  let project.pending[resolve(fnamemodify(bufname(a:buf), ':p'))] = 1
  if project.timer != -1
    call timer_stop(project.timer)
  endif
  let project.timer = timer_start(750, function('<SID>TagsRefresh', [root]))
endfunction

function! s:TagsCompletion() abort
  " Index the current file on first editing use, never on individual keystrokes.
  if !s:BufferAllows(bufnr('%')) || empty(&filetype) || expand('%:p') ==# ''
    return
  endif
  if !get(b:, 'nopack_tags_requested', 0) && s:CtagsAvailable(1)
    let b:nopack_tags_requested = 1
    call s:CtagsOpen('completion')
  endif
  call s:TagsAttach(bufnr('%'))
endfunction

function! s:CancelTags() abort
  for project in values(s:tag_projects)
    if project.timer != -1
      call timer_stop(project.timer)
      let project.timer = -1
    endif
    let project.busy = 0
    let project.full = 1
    let project.callbacks = []
  endfor
  for info in getbufinfo()
    call setbufvar(info.bufnr, 'nopack_tags_requested', 0)
  endfor
endfunction

function! s:CtagsClearAll() abort
  for [root, project] in items(s:tag_projects)
    if project.timer != -1
      call timer_stop(project.timer)
    endif
    call s:CancelTask('ctags:' . root)
  endfor
  let s:tag_projects = {}
  call delete(s:nopack_data . '/tags', 'rf')
  for info in getbufinfo()
    call setbufvar(info.bufnr, 'nopack_tags_requested', 0)
    call s:TagsAttach(info.bufnr)
  endfor
  call s:Info('Cleared all managed ctags caches')
endfunction

nnoremap <silent> gd :call <SID>CtagsOpen('definition')<CR>
" Ctrl-t already toggles the terminal; use g Ctrl-t to pop the tag stack.
nnoremap <silent> g<C-t> :pop<CR>
nnoremap <silent> <leader>o :call <SID>CtagsOpen('outline')<CR>
command! CtagsUpdate call <SID>CtagsOpen('refresh')
command! CtagsClearAll call <SID>CtagsClearAll()
augroup NopackCtags
  autocmd!
  autocmd FocusGained,ShellCmdPost * let s:ctags_checked = ''
  autocmd BufLeave * if &buftype ==# 'terminal' | let s:ctags_checked = '' | endif
  autocmd User NopackCancel call <SID>CancelTags()
  autocmd InsertEnter * call <SID>TagsCompletion()
  autocmd BufEnter * call <SID>TagsAttach(str2nr(expand('<abuf>')))
  autocmd BufFilePost,FileType * call setbufvar(str2nr(expand('<abuf>')), 'nopack_tags_requested', 0) | call <SID>TagsAttach(str2nr(expand('<abuf>')))
  autocmd BufWipeout * if has_key(s:managed_tags, expand('<abuf>')) | call remove(s:managed_tags, expand('<abuf>')) | endif
  autocmd BufWritePost * call <SID>TagsSaved(str2nr(expand('<abuf>')))
augroup END

" =========================================
" =========== UNDO STATE PREVIEW ===========
" =========================================
function! s:UndoEntries(entries, result) abort
  for entry in a:entries
    call add(a:result, entry)
    if has_key(entry, 'alt')
      call s:UndoEntries(entry.alt, a:result)
    endif
  endfor
endfunction

function! s:UndoApply(context, seq) abort
  if !s:SourceUnchanged(a:context) || !getbufvar(a:context.buf, '&modifiable')
    call s:Warn('Buffer changed while browsing undo history; reopen the list')
    return
  endif
  execute 'buffer ' . a:context.buf
  execute 'undo ' . a:seq
endfunction

function! s:UndoCleanup(context) abort
  if has_key(a:context, 'replay')
    call popup_close(a:context.replay)
  endif
endfunction

function! s:UndoDiff(before, after) abort
  if exists('*diff')
    return split(diff(a:before, a:after, {'output': 'unified', 'context': 4, 'iwhiteeol': 1, 'indent-heuristic': 1}), "\n")
  endif
  " Vim 9.0 predates diff(); use the system diff without changing editor windows.
  let old = tempname()
  let new = tempname()
  try
    " Match Snacks' end-of-line whitespace handling on older Vim too.
    call writefile(map(copy(a:before), {_, line -> substitute(line, '\s\+$', '', '')}), old)
    call writefile(map(copy(a:after), {_, line -> substitute(line, '\s\+$', '', '')}), new)
    let command = executable('diff') ? 'diff -U4' : 'git --no-pager diff --no-index --no-ext-diff --no-color --unified=4 --'
    let result = systemlist(command . ' ' . shellescape(old) . ' ' . shellescape(new))
    if v:shell_error > 1
      throw 'Cannot generate undo diff: ' . join(result, ' ')
    endif
    let first = match(result, '^@@')
    return first < 0 ? [] : result[first:]
  finally
    call delete(old)
    call delete(new)
  endtry
endfunction

function! s:UndoPreview(context, state, item) abort
  let replay = a:context.replay
  call win_execute(replay, 'noautocmd silent undo ' . a:item.seq)
  let after = getbufline(winbufnr(replay), 1, '$')
  if a:item.seq > 0
    call win_execute(replay, 'noautocmd silent undo')
  endif
  let before = getbufline(winbufnr(replay), 1, '$')
  let changes = s:UndoDiff(before, after)
  call popup_settext(a:state.preview, empty(changes) ? ['No changes'] : changes)
  call setbufvar(winbufnr(a:state.preview), '&syntax', 'diff')
  call popup_setoptions(a:state.preview, {'firstline': 1,
        \ 'title': ' Change #' . a:item.seq . ' · Ctrl-f/b: scroll '})
endfunction

function! s:UndoPicker() abort
  call s:FocusEditor()
  if !s:IsSource(bufnr('%')) || !&modifiable
    call s:Warn('Undo history is available for editable file buffers')
    return
  endif
  if !exists('*popup_create') || &columns < 44
    call s:Warn('Undo preview requires +popupwin and at least 44 terminal columns')
    return
  endif
  let tree = undotree()
  let entries = []
  call s:UndoEntries(tree.entries, entries)
  if empty(entries)
    call s:Warn('No undo history for this buffer yet')
    return
  endif
  call sort(entries, {a, b -> b.seq - a.seq})
  let context = extend(s:SourceContext(bufnr('%')), {'lines': getline(1, '$'),
        \ 'path': tempname()})
  let items = []
  for entry in entries + [{'seq': 0, 'time': 0}]
    let label = printf('#%-5d %s%s%s', entry.seq,
          \ entry.seq == 0 ? 'Initial state' : strftime('%m-%d %H:%M:%S', entry.time),
          \ has_key(entry, 'save') ? ' [saved]' : '',
          \ entry.seq == tree.seq_cur ? ' [current]' : '')
    call add(items, {'label': label, 'seq': entry.seq,
          \ 'action': function('<SID>UndoApply', [context, entry.seq])})
  endfor
  try
    " The temporary undo file is removed as soon as the preview has loaded it.
    execute 'silent wundo! ' . fnameescape(context.path)
    let context.replay = popup_create(context.lines, {'hidden': 1})
    call win_execute(context.replay, 'setlocal modifiable noundofile undolevels=1000')
    call win_execute(context.replay, 'silent rundo ' . fnameescape(context.path))
    call s:OpenPicker('Undo · Enter: apply · Esc: cancel', {
          \ 'items': items, 'preview': function('<SID>UndoPreview', [context]),
          \ 'cancel': function('<SID>UndoCleanup', [context])})
  catch
    call s:CloseActivePicker()
    call s:UndoCleanup(context)
    call s:Warn('Unable to preview undo history: ' . v:exception)
  finally
    call delete(context.path)
  endtry
endfunction

nnoremap <silent> <leader>u :call <SID>UndoPicker()<CR>
nnoremap <silent> <leader>Ti :set list!<CR>

" =========================================
" ============== TERMINAL =================
" =========================================
let s:terminal_buf = -1

function! s:ToggleTerminal() abort
  if s:terminal_buf > 0 && bufexists(s:terminal_buf)
    let visible = bufwinid(s:terminal_buf)
    if visible > 0
      call win_execute(visible, winnr('$') > 1 ? 'hide' : 'enew')
      return
    endif
    if term_getstatus(s:terminal_buf) !~# 'running'
      execute 'silent! bwipeout! ' . s:terminal_buf
      let s:terminal_buf = -1
    endif
  endif
  execute 'botright ' . max([5, &lines / 3]) . 'split'
  if s:terminal_buf <= 0 || !bufexists(s:terminal_buf)
    " Hiding keeps the shell alive; quitting Vim may stop it without E947.
    let s:terminal_buf = term_start(&shell, {'curwin': 1, 'cwd': s:ProjectRoot().root, 'term_finish': 'close', 'term_kill': 'kill'})
  else
    execute 'buffer ' . s:terminal_buf
  endif
  call s:OwnUtilityWindow()
  setlocal nobuflisted bufhidden=hide nonumber norelativenumber nocursorline nocursorcolumn signcolumn=no
  startinsert
endfunction

if has('terminal')
  nnoremap <silent> <C-t> :call <SID>ToggleTerminal()<CR>
  tnoremap <silent> <C-t> <C-W>:call <SID>ToggleTerminal()<CR>
endif

" =========================================
" ================ SESSIONS ===============
" =========================================
let s:session_dir = s:nopack_data . '/sessions/'
call mkdir(s:session_dir, 'p')
let s:save_session = 1

function! s:SessionPath(...) abort
  let root = a:0 ? a:1 : getcwd()
  return s:session_dir . sha256(root) . '.vim'
endfunction

function! s:WriteSession() abort
  let buffers = s:Buffers()
  if !s:save_session || (argc() == 0 && len(buffers) == 1 && bufname(buffers[0]) ==# '')
    return
  endif
  let root = getcwd()
  let path = s:SessionPath(root)
  execute 'mksession! ' . fnameescape(path)
  call writefile([root], path . '.root')
  call writefile([path], s:session_dir . 'last')
endfunction

function! s:RestoreSession(path) abort
  if a:path !=# '' && filereadable(a:path)
    execute 'source ' . fnameescape(a:path)
  else
    call s:Info('No saved session')
  endif
endfunction

function! s:RestoreDirectorySession() abort
  call s:RestoreSession(s:SessionPath())
endfunction

function! s:RestoreLastSession() abort
  let last = s:session_dir . 'last'
  let paths = filereadable(last) ? readfile(last, '', 1) : []
  call s:RestoreSession(empty(paths) ? '' : paths[0])
endfunction

function! s:DisableSessionSave() abort
  let s:save_session = 0
endfunction

function! s:SessionLabel(path) abort
  let roots = filereadable(a:path . '.root') ? readfile(a:path . '.root', '', 1) : []
  if !empty(roots)
    return roots[0]
  endif
  let directory = ''
  for line in readfile(a:path)
    if line =~# '^lcd '
      return substitute(line, '^lcd ', '', '')
    elseif directory ==# '' && line =~# '^cd '
      let directory = substitute(line, '^cd ', '', '')
    endif
  endfor
  return directory ==# '' ? a:path : directory
endfunction

function! s:PickSession() abort
  let items = []
  for path in glob(s:session_dir . '*.vim', 0, 1)
    call add(items, {
          \ 'label': s:SessionLabel(path),
          \ 'action': function('<SID>RestoreSession', [path]),
          \ })
  endfor
  call s:OpenPicker('Sessions', {'items': items})
endfunction

nnoremap <silent> <leader>pr :call <SID>RestoreDirectorySession()<CR>
nnoremap <silent> <leader>pl :call <SID>RestoreLastSession()<CR>
nnoremap <silent> <leader>pd :call <SID>DisableSessionSave()<CR>
nnoremap <silent> <leader>pS :call <SID>PickSession()<CR>

augroup NopackSessions
  autocmd!
  autocmd VimLeavePre * silent! call <SID>WriteSession()
augroup END

" =========================================
" ================== GIT ===================
" =========================================
" netrw Git signs: XY is index/worktree status; ** aggregates mixed children.
let s:netrw_git_timer = -1
let s:netrw_git_cache = {}


function! s:NetrwGitStatuses(root, output) abort
  let statuses = {}
  let records = split(a:output, '\%x00')
  let index = 0
  while index < len(records)
    let record = records[index]
    let xy = strpart(record, 0, 2)
    let path = substitute(a:root, '/\+$', '', '') . '/' . strpart(record, 3)
    let index += xy =~# '[RC]' ? 2 : 1
    let path = substitute(path, '/\+$', '', '')
    while path !=# a:root && path !=# fnamemodify(path, ':h')
      let statuses[path] = has_key(statuses, path) && statuses[path] !=# xy ? '**' : xy
      let path = fnamemodify(path, ':h')
    endwhile
  endwhile
  return statuses
endfunction

function! s:DrawNetrwGit(win, buf, top, statuses) abort
  if winbufnr(a:win) != a:buf || getbufvar(a:buf, '&filetype') !=# 'netrw' || s:NetrwRoot(a:win) !=# a:top
    return
  endif
  let existing = {}
  for sign in sign_getplaced(a:buf, {'group': 'nopack-netrw-git'})[0].signs
    let existing[sign.id] = sign
  endfor
  let parents = {0: substitute(a:top, '/\+$', '', '')}
  let row = 0
  for line in getbufline(a:buf, 1, '$')
    let row += 1
    let indent = matchstr(line, '^\%([|│] \)\+')
    let depth = strchars(indent) / 2
    if depth == 0 || !has_key(parents, depth - 1)
      continue
    endif
    let name = substitute(strpart(line, strlen(indent)), '\t -->.*$', '', '')
    let path = parents[depth - 1] . '/' . substitute(name, '/$', '', '')
    " netrw appends type markers; preserve literal suffixes on real filenames.
    if path =~# '[@*=|]$' && !has_key(a:statuses, path) && getftype(path) ==# ''
      let path = substitute(path, '[@*=|]$', '', '')
    endif
    let parents[depth] = path
    let xy = get(a:statuses, path, '')
    if xy ==# ''
      continue
    endif
    let sign = 'NopackTreeGit' . char2nr(xy[0]) . '_' . char2nr(xy[1])
    let highlight = xy =~# 'U\|AA\|DD' ? 'ErrorMsg' : xy ==# '**' ? 'Directory'
          \ : xy =~# 'D' ? 'DiffDelete' : xy =~# '[A?]' ? 'DiffAdd' : 'DiffChange'
    if empty(sign_getdefined(sign))
      call sign_define(sign, {'text': substitute(xy, ' ', '.', 'g'), 'texthl': highlight})
    endif
    let previous = has_key(existing, row) ? remove(existing, row) : {}
    if get(previous, 'lnum', 0) != row || get(previous, 'name', '') !=# sign
      if !empty(previous)
        call sign_unplace('nopack-netrw-git', {'buffer': a:buf, 'id': row})
      endif
      call sign_place(row, 'nopack-netrw-git', sign, a:buf, {'lnum': row, 'priority': 20})
    endif
  endfor
  for sign in values(existing)
    call sign_unplace('nopack-netrw-git', {'buffer': a:buf, 'id': sign.id})
  endfor
endfunction

function! s:RedrawNetrwGit() abort
  if !exists('*sign_place')
    return
  endif
  for info in getwininfo()
    if getbufvar(info.bufnr, '&filetype') ==# 'netrw'
      let top = s:NetrwRoot(info.winid)
      call s:DrawNetrwGit(info.winid, info.bufnr, top, get(s:netrw_git_cache, top, {}))
    endif
  endfor
endfunction

function! s:NetrwGitResult(win, buf, top, root, output, limited) abort
  let statuses = s:NetrwGitStatuses(a:root, a:output)
  let s:netrw_git_cache[a:top] = statuses
  call s:DrawNetrwGit(a:win, a:buf, a:top, statuses)
endfunction

function! s:RefreshNetrwGit(timer) abort
  if a:timer != s:netrw_git_timer | return | endif
  let s:netrw_git_timer = -1
  for info in getwininfo()
    if getbufvar(info.bufnr, '&filetype') !=# 'netrw'
      continue
    endif
    let top = s:NetrwRoot(info.winid)
    let project = s:FindProject(top)
    let root = project.git ? project.root : ''
    let key = 'git-tree:' . info.bufnr
    call s:CancelTask(key)
    if root ==# '' || !isdirectory(top)
      let s:netrw_git_cache[top] = {}
      call s:DrawNetrwGit(info.winid, info.bufnr, top, {})
      continue
    endif
    call s:RunCommand(key, ['git', '--no-optional-locks', 'status', '--porcelain=v1', '-z', '--untracked-files=all'], {
          \ 'cwd': root, 'quiet': 1,
          \ 'failed': function('<SID>DrawNetrwGit', [info.winid, info.bufnr, top, {}]),
          \ }, function('<SID>NetrwGitResult', [info.winid, info.bufnr, top, root]))
  endfor
endfunction

function! s:NetrwGitOnEnter() abort
  if &filetype !=# 'netrw' | return | endif
  if has_key(s:netrw_git_cache, s:NetrwRoot(win_getid()))
    call s:RedrawNetrwGit()
  else
    call s:QueueNetrwGit()
  endif
endfunction

function! s:QueueNetrwGit() abort
  let s:netrw_git_cache = {}
  if empty(filter(getwininfo(), 'getbufvar(v:val.bufnr, "&filetype") ==# "netrw"')) | return | endif
  if s:netrw_git_timer != -1
    call timer_stop(s:netrw_git_timer)
  endif
  let s:netrw_git_timer = timer_start(100, function('<SID>RefreshNetrwGit'))
endfunction

function! s:CancelNetrwGit() abort
  call timer_stop(s:netrw_git_timer)
  let s:netrw_git_timer = -1
endfunction

augroup NopackNetrwGit
  autocmd!
  if exists('*sign_place') && exists('*job_start')
    autocmd FileType netrw call <SID>NetrwGitOnEnter()
    autocmd BufWinEnter * call <SID>NetrwGitOnEnter()
    autocmd BufWritePost,FocusGained,ShellCmdPost * call <SID>QueueNetrwGit()
    autocmd BufLeave * if &buftype ==# 'terminal' | call <SID>QueueNetrwGit() | endif
    autocmd TextChanged * if &filetype ==# 'netrw' | call <SID>RedrawNetrwGit() | endif
    autocmd BufWipeout * call <SID>CancelTask('git-tree:' . expand('<abuf>'))
    autocmd User NopackCancel call <SID>CancelNetrwGit()
  endif
augroup END

" Branch and current file index/worktree status; no Git commands during redraw.
function! s:GitStatusResult(buf, file, output, limited) abort
  if !bufloaded(a:buf) || fnamemodify(bufname(a:buf), ':p') !=# a:file
    return
  endif
  let branch = ''
  let oid = ''
  let xy = ''
  for line in split(a:output, "\n")
    if line =~# '^# branch.head '
      let branch = strpart(line, 14)
    elseif line =~# '^# branch.oid '
      let oid = strpart(line, 13)
    elseif line =~# '^[12u] '
      let xy = split(line)[1]
    elseif line =~# '^? '
      let xy = '??'
    endif
  endfor
  if branch ==# '(detached)'
    let branch = 'HEAD@' . strpart(oid, 0, 7)
  endif
  let status = branch ==# '' ? '' : '[' . branch . (xy ==# '' ? '' : ' ' . xy) . ']'
  if getbufvar(a:buf, 'nopack_git_status', '') !=# status
    call setbufvar(a:buf, 'nopack_git_status', status)
    redrawstatus
  endif
endfunction

let s:git_status_sources = {}
function! s:RefreshGitStatus(buf, ...) abort
  if !bufloaded(a:buf)
    return
  endif
  let file = fnamemodify(bufname(a:buf), ':p')
  let project = s:ProjectRoot(a:buf)
  let key = string(a:buf)
  let identity = [file, getbufvar(a:buf, '&filetype'), project.root, project.git, executable('git')]
  if !a:0 && get(s:git_status_sources, key, []) ==# identity | return | endif
  let s:git_status_sources[key] = identity
  call s:CancelTask('git-status:' . a:buf)
  if !s:IsSource(a:buf) || bufname(a:buf) ==# '' || !project.git || !executable('git')
    call setbufvar(a:buf, 'nopack_git_status', '')
    return
  endif
  call s:RunCommand('git-status:' . a:buf,
        \ ['git', '--no-optional-locks', '--literal-pathspecs', 'status', '--porcelain=v2', '--branch', '--no-ahead-behind', '--', file],
        \ {'cwd': project.root, 'quiet': 1, 'failed': function('<SID>ForgetGitStatus', [a:buf])}, function('<SID>GitStatusResult', [a:buf, file]))
endfunction

function! s:ForgetGitStatus(buf) abort
  if has_key(s:git_status_sources, string(a:buf)) | call remove(s:git_status_sources, string(a:buf)) | endif
  call s:CancelTask('git-status:' . a:buf)
endfunction

function! s:RefreshVisibleGitStatus() abort
  let s:git_status_sources = {}
  for buf in uniq(sort(map(getwininfo(), 'v:val.bufnr')))
    call s:RefreshGitStatus(buf)
  endfor
endfunction

augroup NopackGitStatus
  autocmd!
  autocmd BufEnter * call <SID>RefreshGitStatus(str2nr(expand('<abuf>')))
  autocmd BufWritePost,BufFilePost,FileType * call <SID>RefreshGitStatus(str2nr(expand('<abuf>')), 1)
  autocmd FocusGained,ShellCmdPost * call <SID>RefreshVisibleGitStatus()
  autocmd User NopackFilesChanged call <SID>RefreshVisibleGitStatus()
  autocmd BufLeave * if &buftype ==# 'terminal' | call <SID>RefreshVisibleGitStatus() | endif
  autocmd BufUnload,BufWipeout * call <SID>ForgetGitStatus(str2nr(expand('<abuf>')))
  if exists('##TerminalOpen')
    autocmd TerminalOpen * call <SID>RefreshVisibleGitStatus()
  endif
augroup END

function! s:Git(args, Callback, ...) abort
  let project = s:ProjectRoot()
  if !project.git
    call s:Warn('Current file is not in a Git project')
    return 0
  endif
  let opts = a:0 ? copy(a:1) : {}
  let opts.cwd = project.root
  call s:RunCommand(get(opts, 'key', 'git'), ['git', '--no-pager'] + a:args, opts, a:Callback)
  return 1
endfunction

function! s:SetScratchLines(lines) abort
  let lines = empty(a:lines) ? [''] : a:lines
  call setline(1, lines)
  if line('$') > len(lines)
    execute len(lines) + 1 . ',$delete _'
  endif
endfunction

function! s:ShowOutput(lines, filetype, vertical) abort
  execute a:vertical ? 'rightbelow vnew' : 'botright new'
  setlocal buftype=nofile nobuflisted bufhidden=wipe noswapfile
  setlocal modifiable
  call s:SetScratchLines(a:lines)
  let &l:filetype = a:filetype
  setlocal nomodifiable nomodified
endfunction

function! s:GitFiles() abort
  let project = s:ProjectRoot()
  if !project.git
    call s:Warn('Current file is not in a Git project')
    return
  endif
  call s:FilePicker('Git files', project.root, ['git', 'ls-files'])
endfunction

function! s:ShowGitLog(output, limited) abort
  call s:ShowOutput(s:OutputLines(a:output, a:limited), 'git', 0)
endfunction

function! s:ShowGitStatus(output, limited) abort
  call s:ShowOutput(s:OutputLines(a:output, a:limited), 'git', 0)
endfunction

function! s:GitLog() abort
  call s:Git(['log', '-50', '--oneline'], function('<SID>ShowGitLog'))
endfunction

let s:lazygit_popup = 0
function! s:GitTerminalClosed(id, result) abort
  let s:lazygit_popup = 0
  call s:RefreshVisibleGitStatus()
  call s:QueueNetrwGit()
  for info in getwininfo()
    call setbufvar(info.bufnr, 'nopack_git_base', v:null)
    call s:QueueGitSigns(info.bufnr)
  endfor
endfunction

function! s:GitStatus() abort
  if s:lazygit_popup && !empty(popup_getpos(s:lazygit_popup))
    call popup_close(s:lazygit_popup)
    return
  endif
  if executable('lazygit') && has('terminal')
    let buf = term_start(['lazygit'], {'hidden': 1, 'cwd': s:ProjectRoot().root, 'term_finish': 'close'})
    let s:lazygit_popup = popup_create(buf, {'minwidth': &columns * 9 / 10, 'maxwidth': &columns * 9 / 10,
          \ 'minheight': &lines * 9 / 10, 'maxheight': &lines * 9 / 10, 'border': [],
          \ 'callback': function('<SID>GitTerminalClosed')})
    call setbufvar(buf, '&bufhidden', 'wipe')
    return
  endif
  call s:Git(['status', '--short', '--branch', '--untracked-files=normal'], function('<SID>ShowGitStatus'))
endfunction

function! s:RelativePath(file, root) abort
  let prefix = a:root ==# '/' ? '/' : a:root . '/'
  return stridx(a:file, prefix) == 0 ? strpart(a:file, len(prefix)) : a:file
endfunction

function! s:GitDiffResult(context, winid, output, limited) abort
  if !s:BufferAllows(a:context.buf) || !s:SourceUnchanged(a:context)
        \ || !s:IsEditorWindow(a:winid) || winbufnr(a:winid) != a:context.buf | return | endif
  call win_gotoid(a:winid)
  tab split
  let source = win_getid()
  diffthis
  call s:ShowOutput(s:OutputLines(a:output, a:limited), a:context.filetype, 1)
  let t:nopack_diff_base = bufnr('%')
  let t:nopack_diff = 1
  diffthis
  call win_gotoid(source)
endfunction

function! s:DiffCleanup(win, timer) abort
  if win_getid() != a:win || !get(t:, 'nopack_diff', 0) | return | endif
  if winnr('$') == 1
    let base = get(t:, 'nopack_diff_base', -1)
    diffoff
    unlet t:nopack_diff
    if tabpagenr('$') > 1
      tabclose
    endif
    if bufexists(base) | execute 'silent! bwipeout ' . base | endif
  endif
endfunction
augroup NopackDiff
  autocmd!
  " Newer Vim locks the layout during a close-triggered WinEnter (E1312).
  " Finish after that operation unwinds, before the next input/redraw cycle.
  autocmd WinEnter * if get(t:, 'nopack_diff', 0) && winnr('$') == 1 | call timer_start(0, function('<SID>DiffCleanup', [win_getid()])) | endif
augroup END

function! s:GitDiff(revision) abort
  let file = expand('%:p')
  if !s:BufferAllows(bufnr('%')) || file ==# ''
    call s:Warn('Open a tracked file first')
    return
  endif
  let project = s:ProjectRoot()
  if !project.git
    call s:Warn('Current file is not in a Git project')
    return
  endif
  let relative = s:RelativePath(file, project.root)
  let Callback = function('<SID>GitDiffResult', [s:SourceContext(bufnr('%')), win_getid()])
  call s:Git(['show', a:revision . relative], Callback)
endfunction

nnoremap <silent> <leader><CR> :call <SID>GitFiles()<CR>
nnoremap <silent> <leader>sg :call <SID>GitLog()<CR>
nnoremap <silent> <leader>gg :call <SID>GitStatus()<CR>
nnoremap <silent> <leader>gd :call <SID>GitDiff(':')<CR>
nnoremap <silent> <leader>gD :call <SID>GitDiff('HEAD:')<CR>
nnoremap <silent> <leader>gn :call <SID>GitHunk(1)<CR>
nnoremap <silent> <leader>gp :call <SID>GitHunk(-1)<CR>
nnoremap <silent> <leader>gb :call <SID>ToggleBlame()<CR>

function! s:GitHunk(direction) abort
  let signs = sign_getplaced(bufnr('%'), {'group': 'nopack-git-signs'})[0].signs
  let rows = uniq(sort(map(signs, 'v:val.lnum'), 'n'))
  let starts = filter(copy(rows), 'index(rows, v:val - 1) < 0')
  if empty(starts) | call s:Info('No changes in this buffer') | return | endif
  let candidates = filter(copy(starts), 'a:direction > 0 ? v:val > line(".") : v:val < line(".")')
  let target = empty(candidates) ? (a:direction > 0 ? starts[0] : starts[-1]) : (a:direction > 0 ? candidates[0] : candidates[-1])
  normal! m'
  call cursor(target, 1)
  normal! zvzz
endfunction

" Track unstaged line changes against the index with Vim signs.
if exists('*sign_define')
  call sign_define('NopackGitAdd', {'text': '+', 'texthl': 'DiffAdd'})
  call sign_define('NopackGitChange', {'text': '~', 'texthl': 'DiffChange'})
  call sign_define('NopackGitDelete', {'text': '-', 'texthl': 'DiffDelete'})
  call sign_define('NopackGitChangeDelete', {'text': '~-', 'texthl': 'DiffChange'})
endif

let s:git_sign_versions = {}
let s:git_sign_timers = {}
let s:git_sign_changes = {}


function! s:ClearGitSigns(buf) abort
  if exists('*sign_unplace')
    silent! call sign_unplace('nopack-git-signs', {'buffer': a:buf})
  else
    execute 'silent! sign unplace * group=nopack-git-signs buffer=' . a:buf
  endif
endfunction

" Align mixed hunks like the nopack Neovim version; bound quadratic work.
function! s:ChangedLines(old, new, hunk) abort
  let m = a:hunk.from_count
  let n = a:hunk.to_count
  let changed = {}
  if m == 0 || n == 0
    return changed
  endif
  " Bound both matrix cells and character comparisons on Vim's main thread.
  " Complex hunks retain every sign, using coarse changed-line classification.
  if m == n || m * n > 1024
        \ || n * strlen(join(a:old[a:hunk.from_idx : a:hunk.from_idx + m - 1], ''))
        \ + m * strlen(join(a:new[a:hunk.to_idx : a:hunk.to_idx + n - 1], '')) > 32768
    for j in range(n)
      let changed[j] = 1
    endfor
    return changed
  endif
  let costs = [range(n + 1)]
  let steps = [[]]
  for i in range(1, m)
    call add(costs, [i])
    call add(steps, [''])
    for j in range(1, n)
      let left = a:old[a:hunk.from_idx + i - 1]
      let right = a:new[a:hunk.to_idx + j - 1]
      let prefix = 0
      let suffix = 0
      let length = min([strlen(left), strlen(right)])
      while prefix < length && strpart(left, prefix, 1) ==# strpart(right, prefix, 1)
        let prefix += 1
      endwhile
      while suffix < length - prefix && strpart(left, strlen(left) - suffix - 1, 1) ==# strpart(right, strlen(right) - suffix - 1, 1)
        let suffix += 1
      endwhile
      let similarity = (prefix + suffix) * 1.0 / max([1, strlen(left), strlen(right)])
      let pair_cost = left ==# right ? 0.0 : 1.8 - similarity
      if (left =~# '^\s*$') != (right =~# '^\s*$')
        let pair_cost = 1.95
      endif
      let best = costs[i - 1][j - 1] + pair_cost
      let step = 'pair'
      if costs[i][j - 1] + 1 < best
        let best = costs[i][j - 1] + 1
        let step = 'add'
      endif
      if costs[i - 1][j] + 1 < best
        let best = costs[i - 1][j] + 1
        let step = 'delete'
      endif
      call add(costs[i], best)
      call add(steps[i], step)
    endfor
  endfor
  let i = m
  let j = n
  while i > 0 && j > 0
    if steps[i][j] ==# 'pair'
      let changed[j - 1] = 1
      let i -= 1
      let j -= 1
    elseif steps[i][j] ==# 'add'
      let j -= 1
    else
      let i -= 1
    endif
  endwhile
  return changed
endfunction

function! s:PlaceGitHunks(buf, hunks, ...) abort
  if !bufloaded(a:buf)
    return
  endif
  call s:ClearGitSigns(a:buf)
  let line_count = getbufinfo(a:buf)[0].linecount
  let sign_id = 1
  for hunk in a:hunks
    if sign_id > 2000 | break | endif
    let removed = get(hunk, 'from_count', 0)
    let added = get(hunk, 'to_count', 0)
    let start = get(hunk, 'to_idx', 0) + 1
    let changed = a:0 == 2 ? s:ChangedLines(a:1, a:2, hunk) : {}
    if added == 0
      let lnum = max([1, min([line_count, start])])
      call sign_place(sign_id, 'nopack-git-signs', 'NopackGitDelete', a:buf, {'lnum': lnum, 'priority': 5})
      let sign_id += 1
      continue
    endif
    for offset in range(0, min([added - 1, 1999]))
      if sign_id > 2000 | break | endif
      if removed == 0 || (a:0 == 2 && !has_key(changed, offset))
        let name = 'NopackGitAdd'
      elseif removed > added && offset == added - 1
        let name = 'NopackGitChangeDelete'
      else
        let name = 'NopackGitChange'
      endif
      let lnum = max([1, min([line_count, start + offset])])
      call sign_place(sign_id, 'nopack-git-signs', name, a:buf, {'lnum': lnum, 'priority': 5})
      let sign_id += 1
    endfor
  endfor
endfunction

function! s:GitSignsCurrent(buf, revision_id, tick, file) abort
  return s:BufferAllows(a:buf)
        \ && get(s:git_sign_versions, string(a:buf), -1) == a:revision_id
        \ && getbufvar(a:buf, 'changedtick', -1) == a:tick
        \ && fnamemodify(bufname(a:buf), ':p') ==# a:file
endfunction

function! s:ParseUnifiedHunks(output) abort
  let hunks = []
  for line in split(a:output, "\n")
    let match = matchlist(line, '^@@ -\(\d\+\)\%(,\(\d\+\)\)\? +\(\d\+\)\%(,\(\d\+\)\)\? @@')
    if !empty(match)
      call add(hunks, {
            \ 'from_idx': str2nr(match[1]) - 1,
            \ 'from_count': match[2] ==# '' ? 1 : str2nr(match[2]),
            \ 'to_idx': str2nr(match[3]) - 1,
            \ 'to_count': match[4] ==# '' ? 1 : str2nr(match[4]),
            \ })
    endif
  endfor
  return hunks
endfunction

function! s:GitSignsFallbackResult(buf, revision_id, tick, file, output, limited) abort
  if s:GitSignsCurrent(a:buf, a:revision_id, a:tick, a:file)
    call s:PlaceGitHunks(a:buf, s:ParseUnifiedHunks(a:output))
  endif
endfunction

function! s:GitSignsFallback(buf, revision_id, tick, file, base, current) abort
  let old = tempname()
  let new = tempname()
  call writefile(a:base, old)
  call writefile(a:current, new)
  call s:RunCommand('git-signs:' . a:buf,
        \ ['git', '--no-pager', 'diff', '--no-index', '--no-ext-diff', '--no-color', '--unified=0', '--', old, new],
        \ {'cleanup': [old, new], 'no_match': 1, 'max_bytes': 2 * 1024 * 1024, 'quiet': 1},
        \ function('<SID>GitSignsFallbackResult', [a:buf, a:revision_id, a:tick, a:file]))
endfunction

function! s:GitSignsBase(buf, revision_id, tick, file, root, relative, current, output, limited) abort
  if !s:GitSignsCurrent(a:buf, a:revision_id, a:tick, a:file)
    return
  endif
  let base = s:OutputLines(a:output, 0)
  call setbufvar(a:buf, 'nopack_git_base', a:output)
  if exists('*diff')
    let hunks = diff(base, a:current, {'output': 'indices'})
    if type(hunks) == v:t_list
      call s:PlaceGitHunks(a:buf, hunks, base, a:current)
      return
    endif
  endif
  " Vim 9.0 has no diff() API; compare snapshots asynchronously, including unsaved edits.
  call s:GitSignsFallback(a:buf, a:revision_id, a:tick, a:file, base, a:current)
endfunction

function! s:GitSignsFailed(buf, revision_id) abort
  if bufloaded(a:buf) && get(s:git_sign_versions, string(a:buf), -1) == a:revision_id
    call s:ClearGitSigns(a:buf)
  endif
endfunction

function! s:StartGitSigns(buf, revision_id, timer) abort
  if get(s:git_sign_timers, string(a:buf), -1) != a:timer | return | endif
  call remove(s:git_sign_timers, string(a:buf))
  if !bufloaded(a:buf) || get(s:git_sign_versions, string(a:buf), -1) != a:revision_id
    return
  endif
  let file = fnamemodify(bufname(a:buf), ':p')
  let limit = 256 * 1024
  if !s:BufferAllows(a:buf) || file ==# '' || !executable('git')
    call s:ClearGitSigns(a:buf)
    return
  endif
  let project = s:ProjectRoot(a:buf)
  if !project.git || s:BufferByteSize(a:buf, limit) > limit
    call s:ClearGitSigns(a:buf)
    return
  endif
  let relative = s:RelativePath(file, project.root)
  let tick = getbufvar(a:buf, 'changedtick', -1)
  let current = getbufline(a:buf, 1, '$')
  let base = getbufvar(a:buf, 'nopack_git_base', v:null)
  if type(base) == v:t_string
    call s:GitSignsBase(a:buf, a:revision_id, tick, file, project.root, relative, current, base, 0)
    return
  endif
  call s:RunCommand('git-signs:' . a:buf, [
        \ 'git', '--no-pager', 'show', ':./' . relative,
        \ ], {
        \ 'cwd': project.root,
        \ 'max_bytes': limit,
        \ 'quiet': 1,
        \ 'failed': function('<SID>GitSignsFailed', [a:buf, a:revision_id]),
        \ }, function('<SID>GitSignsBase', [
        \   a:buf, a:revision_id, tick, file, project.root, relative, current,
        \ ]))
endfunction

function! s:QueueGitSigns(buf) abort
  if !s:BufferAllows(a:buf) || empty(bufname(a:buf))
    call s:ForgetGitSigns(a:buf)
    if bufloaded(a:buf) | call s:ClearGitSigns(a:buf) | endif
    return
  endif
  let key = string(a:buf)
  let s:git_sign_versions[key] = get(s:git_sign_versions, key, 0) + 1
  let revision_id = s:git_sign_versions[key]
  if has_key(s:git_sign_timers, key)
    call timer_stop(s:git_sign_timers[key])
  endif
  call s:CancelTask('git-signs:' . a:buf)
  let s:git_sign_timers[key] = timer_start(200, function('<SID>StartGitSigns', [a:buf, revision_id]))
endfunction

function! s:GitChanged(buf) abort
  let key = string(a:buf)
  let tick = getbufvar(a:buf, 'changedtick', -1)
  if get(s:git_sign_changes, key, -2) == tick | return | endif
  let s:git_sign_changes[key] = tick
  call s:QueueGitSigns(a:buf)
endfunction

function! s:CancelGitSigns() abort
  for timer in values(s:git_sign_timers)
    call timer_stop(timer)
  endfor
  let s:git_sign_timers = {}
  let s:git_sign_versions = {}
endfunction

function! s:ForgetGitSigns(buf) abort
  let key = string(a:buf)
  if has_key(s:git_sign_changes, key) | call remove(s:git_sign_changes, key) | endif
  if has_key(s:git_sign_timers, key)
    call timer_stop(remove(s:git_sign_timers, key))
  endif
  if has_key(s:git_sign_versions, key)
    call remove(s:git_sign_versions, key)
  endif
  call s:CancelTask('git-signs:' . a:buf)
endfunction

function! s:InvalidateBufferGitSigns(buf) abort
  let key = string(a:buf)
  if has_key(s:git_sign_changes, key) | call remove(s:git_sign_changes, key) | endif
  call setbufvar(a:buf, 'nopack_git_base', v:null)
  call s:GitChanged(a:buf)
endfunction

function! s:RefreshVisibleGitSigns() abort
  for info in getbufinfo({'bufloaded': 1})
    call s:ForgetGitSigns(info.bufnr)
    call setbufvar(info.bufnr, 'nopack_git_base', v:null)
  endfor
  for buf in uniq(sort(map(getwininfo(), 'v:val.bufnr')))
    call s:GitChanged(buf)
  endfor
endfunction

augroup NopackGitSigns
  autocmd!
  autocmd User NopackCancel call <SID>CancelGitSigns()
  if exists('*sign_place') && exists('*job_start')
    autocmd BufEnter * call <SID>GitChanged(str2nr(expand('<abuf>')))
    autocmd BufWritePost,BufFilePost,FileType * call <SID>InvalidateBufferGitSigns(str2nr(expand('<abuf>')))
    autocmd FocusGained,ShellCmdPost * call <SID>RefreshVisibleGitSigns()
    autocmd User NopackFilesChanged call <SID>RefreshVisibleGitSigns()
    autocmd BufLeave * if &buftype ==# 'terminal' | call <SID>RefreshVisibleGitSigns() | endif
    autocmd TextChanged,TextChangedI * call <SID>GitChanged(str2nr(expand('<abuf>')))
    autocmd BufUnload,BufWipeout * call <SID>ForgetGitSigns(str2nr(expand('<abuf>')))
  endif
augroup END

" =========================================
" =============== FORMATTING ==============
" =========================================
let s:formatters = {
      \ 'lua': [['stylua', '--stdin-filepath', '%', '-']],
      \ 'python': [['ruff', 'format', '--stdin-filename', '%', '-'], ['black', '--quiet', '--stdin-filename', '%', '-']],
      \ 'bzl': [['buildifier', '-path', '%', '-']],
      \ 'sh': [['shfmt', '-filename', '%']],
      \ 'cmake': [['cmake-format', '-']],
      \ 'tex': [['latexindent', '-']],
      \ 'plaintex': [['latexindent', '-']],
      \ 'rust': [['rustfmt', '--emit=stdout', '--edition=2021']],
      \ 'verilog': [['verible-verilog-format', '--stdin_name', '%', '-']],
      \ 'systemverilog': [['verible-verilog-format', '--stdin_name', '%', '-']],
      \ }
for s:ft in ['c', 'cpp', 'cuda', 'proto']
  let s:formatters[s:ft] = [['clang-format', '--assume-filename=%']]
endfor
for s:ft in ['javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'html', 'css', 'scss', 'less', 'json', 'jsonc', 'yaml', 'markdown', 'markdown.mdx', 'graphql', 'vue', 'handlebars']
  let s:formatters[s:ft] = [['prettier', '--stdin-filepath', '%']]
endfor
unlet s:ft

function! s:Executable(name) abort
  let found = exepath(a:name)
  if found !=# '' | return found | endif
  let data = empty($XDG_DATA_HOME) ? expand('~/.local/share') : $XDG_DATA_HOME
  let path = data . '/nvim/mason/bin/' . a:name . (has('win32') ? '.cmd' : '')
  return executable(path) ? path : ''
endfunction

function! s:Formatter(ft) abort
  for candidate in get(s:formatters, a:ft, [])
    let path = s:Executable(candidate[0])
    if !empty(path) | return [path] + candidate[1:] | endif
  endfor
  return []
endfunction

function! s:ToolStatus(buf) abort
  if !bufloaded(a:buf) || !s:IsSource(a:buf) | return | endif
  call s:CtagsAvailable(1)
  let formatter = s:Formatter(getbufvar(a:buf, '&filetype'))
  let label = 'X'
  " Strip .cmd/.exe only; Unix executable names may legitimately contain dots.
  if !empty(formatter) | let label = ': ' . substitute(fnamemodify(formatter[0], ':t'), '\.\%(cmd\|exe\)$', '', '') | endif
  call setbufvar(a:buf, 'nopack_format_status', '[FORMAT' . (label ==# 'X' ? ' X' : label) . ']')
endfunction
function! s:RefreshVisibleToolStatus() abort
  for buf in uniq(sort(map(getwininfo(), 'v:val.bufnr')))
    call s:ToolStatus(buf)
  endfor
endfunction
augroup NopackTools
  autocmd!
  autocmd FileType,BufFilePost,BufWritePost * call <SID>ToolStatus(str2nr(expand('<abuf>')))
  autocmd FocusGained,ShellCmdPost * call <SID>RefreshVisibleToolStatus()
  autocmd BufLeave * if &buftype ==# 'terminal' | call <SID>RefreshVisibleToolStatus() | endif
augroup END

function! s:FormatterArguments(command, file) abort
  let result = []
  for argument in a:command
    call add(result, substitute(argument, '%', escape(a:file, '\&'), 'g'))
  endfor
  return result
endfunction

" Apply changed ranges from the bottom, preserving marks outside the edits.
" Older Vim builds use a single range bounded by the unchanged prefix/suffix.
function! s:ApplyFormatInEditor() abort
  call s:ReplaceBufferLines(s:format_in_window.buf, s:format_in_window.content)
endfunction

function! s:ReplaceBufferLines(buf, content) abort
  " A terminal popup cannot switch buffers. Apply through a normal window.
  if exists('*popup_list') && index(popup_list(), win_getid()) >= 0
    let windows = filter(getwininfo(), 'index(popup_list(), v:val.winid) < 0')
    if empty(windows)
      call s:Warn('No editor window available; formatting result discarded')
      return
    endif
    let s:format_in_window = {'buf': a:buf, 'content': a:content}
    try
      call win_execute(windows[0].winid, 'call ' . s:sid . 'ApplyFormatInEditor()')
    finally
      unlet s:format_in_window
    endtry
    return
  endif
  let original_endofline = getbufvar(a:buf, '&endofline')
  let old = getbufline(a:buf, 1, '$')
  let lines = s:OutputLines(a:content, 0)
  if empty(lines)
    let lines = ['']
  endif
  let hunks = exists('*diff') ? diff(old, lines, {'output': 'indices'}) : v:null
  if type(hunks) != v:t_list
    let first = 0
    let last = 0
    while first < min([len(old), len(lines)]) && old[first] ==# lines[first]
      let first += 1
    endwhile
    while last < min([len(old), len(lines)]) - first && old[-last - 1] ==# lines[-last - 1]
      let last += 1
    endwhile
    let hunks = first == len(old) && first == len(lines) ? [] : [{
          \ 'from_idx': first, 'from_count': len(old) - first - last,
          \ 'to_idx': first, 'to_count': len(lines) - first - last}]
  endif
  let origin = bufnr('%')
  let view = winsaveview()
  let hidden = &l:bufhidden
  try
    if origin != a:buf
      let &l:bufhidden = 'hide'
    endif
    " No UI/autocommand side effects when a formatter finishes in a hidden buffer.
    if origin != a:buf
      execute 'noautocmd keepalt keepjumps hide buffer ' . a:buf
    endif
    let edited = 0
    for hunk in reverse(hunks)
      let start = hunk.from_idx
      let common = min([hunk.from_count, hunk.to_count])
      if common > 0
        if edited | undojoin | endif
        call setline(start + 1, lines[hunk.to_idx : hunk.to_idx + common - 1])
        let edited = 1
      endif
      if hunk.to_count > common
        if edited | undojoin | endif
        call append(start + common, lines[hunk.to_idx + common : hunk.to_idx + hunk.to_count - 1])
        let edited = 1
      elseif hunk.from_count > common
        if edited | undojoin | endif
        call deletebufline(a:buf, start + common + 1, start + hunk.from_count)
        let edited = 1
      endif
    endfor
    let &l:endofline = original_endofline
  finally
    if origin != a:buf && bufexists(origin)
      execute 'noautocmd keepalt keepjumps hide buffer ' . origin
    endif
    if bufexists(origin)
      call setbufvar(origin, '&bufhidden', hidden)
    endif
    call winrestview(view)
  endtry
endfunction

function! s:FormatStep(context, root, commands, index, content, limited) abort
  let buf = a:context.buf
  if !s:BufferAllows(buf) || !getbufvar(buf, '&modifiable') || !s:SourceUnchanged(a:context)
    call s:Warn('Buffer changed during formatting; result discarded')
    return
  endif
  if a:index >= len(a:commands)
    call s:ReplaceBufferLines(buf, a:content)
    return
  endif
  let arguments = s:FormatterArguments(a:commands[a:index], a:context.file)
  call s:RunCommand('format:' . buf, arguments, {'stdin': a:content, 'cwd': a:root},
        \ function('<SID>FormatStep', [a:context, a:root, a:commands, a:index + 1]))
endfunction

function! s:FormatBuffer() abort
  if !s:IsSource(bufnr('%')) || !&l:modifiable
    call s:Warn('Open an editable file before formatting')
    return
  endif
  let buf = bufnr('%')
  if !s:BufferAllows(buf)
    call s:Warn('Formatting skipped: large-file protection is active')
    return
  endif
  let command = s:Formatter(&l:filetype)
  if empty(command)
    let names = map(copy(get(s:formatters, &l:filetype, [])), 'v:val[0]')
    call s:Warn(empty(names) ? 'No formatter registered for ' . &filetype : 'Install ' . join(names, ' or ') . ' on PATH (existing Mason tools are also supported)')
    return
  endif
  let commands = [command]
  let input = join(getline(1, '$'), "\n") . (&l:endofline ? "\n" : '')
  call s:FormatStep(s:SourceContext(buf), s:ProjectRoot().root, commands, 0, input, 0)
endfunction

nnoremap <silent> <leader>lf :call <SID>FormatBuffer()<CR>
augroup NopackFormat
  autocmd!
  autocmd BufUnload,BufFilePost,FileType * call <SID>CancelTask('format:' . expand('<abuf>'))
augroup END

" Vim has no bundled LSP client. gd uses ctags; native gD/K remain
" available, while Neovim-only LSP actions and diagnostics are intentionally
" omitted from this plugin-free port.

" Only the detector owns thresholds; listeners inspect changed ranges after textlock.
let s:large_watchers = {}
function! s:MarkLargeFile(path) abort
  " A fresh read must reassess protection, restoring only options we disabled.
  if exists('b:nopack_large_options')
    let saved = remove(b:, 'nopack_large_options')
    for [name, value] in items(saved) | call setbufvar(bufnr('%'), '&' . name, value) | endfor
  endif
  unlet! b:nopack_large_file
  for winid in win_findbuf(bufnr('%'))
    call win_execute(winid, 'call <SID>ReleaseLargeWindow()')
  endfor
  if getfsize(a:path) > 2 * 1024 * 1024 | call s:RestrictBuffer(bufnr('%')) | endif
endfunction
function! s:ReleaseLargeWindow() abort
  if exists('w:nopack_large_window') && (w:nopack_large_window.buf != bufnr('%') || s:BufferAllows(bufnr('%')))
    let saved = remove(w:, 'nopack_large_window')
    for [name, value] in items(saved.options) | call setwinvar(win_getid(), '&' . name, value) | endfor
  endif
endfunction
function! s:InheritLargeWindow() abort
  " :split copies disabled options, so copy their restoration state as well.
  let saved = getwinvar(win_getid(winnr('#')), 'nopack_large_window', {})
  if get(saved, 'buf', -1) == bufnr('%') && get(b:, 'nopack_large_file', 0)
    let w:nopack_large_window = deepcopy(saved)
  endif
endfunction
function! s:ProtectLargeBuffer(buf) abort
  let saved = getbufvar(a:buf, 'nopack_large_options', {})
  for name in ['syntax', 'indentexpr'] + (exists('+autocomplete') ? ['autocomplete'] : [])
    let value = getbufvar(a:buf, '&' . name)
    " FileType can set runtime options after the initial size check.
    if !has_key(saved, name) || (name ==# 'syntax' && value !=# 'OFF') || (name ==# 'indentexpr' && value !=# '')
      let saved[name] = value
    endif
  endfor
  call setbufvar(a:buf, 'nopack_large_options', saved)
  if getbufvar(a:buf, '&syntax') !=# 'OFF' | call setbufvar(a:buf, '&syntax', 'OFF') | endif
  call setbufvar(a:buf, '&indentexpr', '')
  if exists('+autocomplete') | call setbufvar(a:buf, '&autocomplete', 0) | endif
endfunction
function! s:ApplyLargeFileSettings() abort
  if s:BufferAllows(bufnr('%')) || !s:IsSource(bufnr('%')) | return | endif
  call s:ProtectLargeBuffer(bufnr('%'))
  if !exists('w:nopack_large_window')
    let options = {}
    for name in ['foldmethod', 'cursorline', 'cursorcolumn', 'wrap']
      let options[name] = getwinvar(win_getid(), '&' . name)
    endfor
    let w:nopack_large_window = {'buf': bufnr('%'), 'options': options}
  endif
  setlocal foldmethod=manual nocursorline nocursorcolumn nowrap
endfunction
function! s:CheckLargeFile(buf, first, last) abort
  if !s:BufferAllows(a:buf) | return | endif
  let line_count = getbufinfo(a:buf)[0].linecount
  let large = line_count > 50000 || s:BufferByteSize(a:buf, 2 * 1024 * 1024) > 2 * 1024 * 1024
  let first = max([1, min([a:first, line_count])])
  let last = min([a:last, line_count])
  while !large && first <= last
    for text in getbufline(a:buf, first, min([first + 511, last]))
      if strlen(text) > 10000 | let large = 1 | break | endif
    endfor
    let first += 512
  endwhile
  if large | call s:RestrictBuffer(a:buf) | endif
endfunction
function! s:RunLargeCheck(buf, state, timer) abort
  if get(s:large_watchers, a:buf, {}) isnot a:state | return | endif
  let a:state.timer = -1
  let first = a:state.first
  let last = a:state.last
  let a:state.first = 0
  let a:state.last = 0
  call s:CheckLargeFile(a:buf, first, last)
endfunction
function! s:LargeFileChanged(buf, first, last, added, changes) abort
  if !has_key(s:large_watchers, a:buf) || !s:BufferAllows(a:buf) | return | endif
  let state = s:large_watchers[a:buf]
  let state.first = state.first ? min([state.first, a:first]) : a:first
  let state.last = max([state.last + max([0, a:added]), a:last + max([0, a:added])])
  if state.timer == -1
    let state.timer = timer_start(0, function('<SID>RunLargeCheck', [a:buf, state]))
  endif
endfunction
function! s:WatchLargeFile(buf) abort
  if !s:BufferAllows(a:buf) | return | endif
  if !has_key(s:large_watchers, a:buf)
    let s:large_watchers[a:buf] = {'listener': listener_add(function('<SID>LargeFileChanged'), a:buf), 'timer': -1, 'first': 0, 'last': 0}
    call s:CheckLargeFile(a:buf, 1, getbufinfo(a:buf)[0].linecount)
  endif
endfunction
function! s:ForgetLargeFile(buf) abort
  if !has_key(s:large_watchers, a:buf) | return | endif
  let state = remove(s:large_watchers, a:buf)
  call listener_remove(state.listener)
  call timer_stop(state.timer)
endfunction
function! s:RestrictEditing(buf) abort
  call s:ForgetLargeFile(a:buf)
  call s:ProtectLargeBuffer(a:buf)
  for winid in win_findbuf(a:buf)
    call s:ClearCursorWord(winid)
    call win_execute(winid, 'call <SID>ApplyLargeFileSettings() | call <SID>UpdateIndentGuides()')
  endfor
  if !exists('+autocomplete') && a:buf == bufnr('%')
    call s:CancelCompletion()
  endif
  call s:CancelTask('format:' . a:buf)
  if a:buf == bufnr('%')
    call timer_stop(s:scroll_timer)
    let s:scroll_timer = -1
    call timer_stop(s:sticky_timer)
    let s:sticky_timer = -1
    call s:CloseSticky()
    let s:sticky_cache = {}
  endif
endfunction
function! s:RestrictGit(buf) abort
  call s:ForgetGitSigns(a:buf)
  if bufloaded(a:buf) | call s:ClearGitSigns(a:buf) | endif
  if !empty(s:blame_key) && s:blame_key[1] == a:buf
    call s:CloseBlame()
    call s:CancelTask('blame')
    let s:blame_key = []
  endif
endfunction
function! s:RestrictTags(buf) abort
  call s:TagsAttach(a:buf)
  if empty(bufname(a:buf)) | return | endif
  let root = s:ProjectRoot(a:buf).root
  let project = get(s:tag_projects, root, {})
  let file = resolve(fnamemodify(bufname(a:buf), ':p'))
  if !empty(project)
    if has_key(project.pending, file) | call remove(project.pending, file) | endif
    if project.busy && (project.building_full || index(get(project, 'active_files', []), file) >= 0)
      call s:CancelTask('ctags:' . root)
      let project.busy = 0
      let project.full = 0
      let project.callbacks = []
    endif
    if empty(project.pending)
      call timer_stop(project.timer)
      let project.timer = -1
    elseif !project.busy
      call s:TagsDrain(root)
    endif
  endif
  for info in getwininfo()
    if get(getbufvar(info.bufnr, 'nopack_outline', {}), 'source', -1) == a:buf
      call win_execute(info.winid, 'call <SID>OutlineClose()')
    endif
  endfor
endfunction

function! s:OwnUtilityWindow() abort
  let options = {}
  for name in ['number', 'relativenumber', 'cursorline', 'cursorcolumn', 'signcolumn', 'foldcolumn', 'list', 'wrap', 'spell', 'winfixwidth', 'statusline']
    let options[name] = getwinvar(win_getid(), '&' . name)
  endfor
  let w:nopack_utility = {'buf': bufnr('%'), 'options': options}
endfunction

function! s:ReleaseUtilityWindow() abort
  if exists('w:nopack_utility') && w:nopack_utility.buf != bufnr('%')
    let saved = remove(w:, 'nopack_utility')
    if exists('w:nopack_outline_menu')
      execute 'silent! nunmenu ' . w:nopack_outline_menu
      unlet w:nopack_outline_menu
    endif
    for [name, value] in items(saved.options)
      call setwinvar(win_getid(), '&' . name, value)
    endfor
  endif
endfunction

augroup NopackBufferPolicy
  autocmd!
  autocmd User NopackBufferRestricted call <SID>RestrictEditing(s:restricted_buf) | call <SID>RestrictGit(s:restricted_buf) | call <SID>RestrictTags(s:restricted_buf)
augroup END
augroup NopackLargeFiles
  autocmd!
  autocmd WinNew * call <SID>InheritLargeWindow()
  autocmd BufReadPre * call <SID>MarkLargeFile(expand('<afile>:p'))
  autocmd BufReadPost * call <SID>ForgetLargeFile(str2nr(expand('<abuf>'))) | call <SID>WatchLargeFile(str2nr(expand('<abuf>')))
  autocmd BufNewFile,FileType,BufWinEnter * call <SID>WatchLargeFile(str2nr(expand('<abuf>')))
  autocmd TextChanged,TextChangedI * call listener_flush(str2nr(expand('<abuf>')))
  autocmd BufUnload,BufWipeout * call <SID>ForgetLargeFile(str2nr(expand('<abuf>')))
  autocmd BufWinEnter * call <SID>ReleaseUtilityWindow() | call <SID>ReleaseLargeWindow()
  autocmd FileType,BufWinEnter * call <SID>ApplyLargeFileSettings()
augroup END

" Status rendering reads cached tool information; no processes or filesystem scans.
let s:active_window = win_getid()
let s:show_tools = 1
function! s:HighlightColor(group, attr, fallback) abort
  let color = synIDattr(synIDtrans(hlID(a:group)), a:attr, 'gui')
  return empty(color) ? a:fallback : color
endfunction
function! s:StatusHighlights() abort
  let fg = s:HighlightColor('Normal', 'fg#', '#d0d0d0')
  let bg = s:HighlightColor('Normal', 'bg#', '#202020')
  let base = synIDtrans(hlID('StatusLine'))
  let reversed = synIDattr(base, 'reverse') ==# '1'
  let statusfg = s:HighlightColor('StatusLine', reversed ? 'bg#' : 'fg#', fg)
  let statusbg = s:HighlightColor('StatusLine', reversed ? 'fg#' : 'bg#', bg)
  execute 'hi NopackStatus gui=bold cterm=bold guifg=' . statusfg . ' guibg=' . statusbg
  let base = synIDtrans(hlID('StatusLineNC'))
  let reversed = synIDattr(base, 'reverse') ==# '1'
  execute 'hi NopackStatusNC gui=NONE cterm=NONE guifg=' . s:HighlightColor('StatusLineNC', reversed ? 'bg#' : 'fg#', fg)
        \ . ' guibg=' . s:HighlightColor('StatusLineNC', reversed ? 'fg#' : 'bg#', bg)
  for [mode, group, fallback, terminal] in [['N', 'Function', '#80a0d0', 4], ['I', 'String', '#90b060', 2], ['V', 'Statement', '#d0a060', 3]]
    let color = s:HighlightColor(group, 'fg#', fallback)
    if color ==# statusbg || color ==# bg | let color = fallback | endif
    execute 'hi NopackGit' . mode . ' gui=bold cterm=bold guifg=' . bg . ' guibg=' . color . ' ctermfg=0 ctermbg=' . terminal
  endfor
endfunction
function! NopackStatusline() abort
  let target = get(g:, 'statusline_winid', win_getid())
  let buf = winbufnr(target)
  let active = target == s:active_window
  if !active | return '%#NopackStatusNC# %f %=%y ' | endif
  let branch = substitute(getbufvar(buf, 'nopack_git_status', ''), '%', '%%', 'g')
  let mode = mode(1)
  let group = mode =~# '^[iRt]' ? 'I' : mode =~# '^[vV\x16sS]' ? 'V' : 'N'
  let result = empty(branch) ? '%#NopackStatus# ' : '%#NopackGit' . group . '#' . branch . '%#NopackStatus# '
  let result .= '%f %m%r%h %='
  if s:show_tools && s:IsSource(buf)
    let tags = empty(s:ctags_command) ? 'X' : ': ' . (s:ctags_kind ==# 'universal' ? 'Universal' : 'Exuberant')
    let format = s:BufferAllows(buf) && getbufvar(buf, '&modifiable') ? getbufvar(buf, 'nopack_format_status', '[FORMAT X]') : '[FORMAT X]'
    let result .= '[CTAGS' . (tags ==# 'X' ? ' X' : tags) . '] ' . format . ' '
  endif
  return result . '%y | %6l:%-4c | %3p%% '
endfunction
function! s:ToggleTools() abort
  let s:show_tools = !s:show_tools
  redrawstatus
endfunction
nnoremap <silent> <leader>Tl :call <SID>ToggleTools()<CR>
augroup NopackStatusline
  autocmd!
  autocmd ColorScheme * call <SID>StatusHighlights()
  autocmd WinEnter,VimEnter * let s:active_window = win_getid() | redrawstatus
  autocmd ModeChanged * redrawstatus
augroup END
call s:StatusHighlights()

" Vim 9.0 predates virtual text: a noninteractive popup follows the blamed line.
let s:blame_enabled = 0
let s:blame_popup = 0
let s:blame_timer = -1
let s:blame_key = []
function! s:CloseBlame() abort
  call timer_stop(s:blame_timer)
  let s:blame_timer = -1
  if s:blame_popup | call popup_close(s:blame_popup) | let s:blame_popup = 0 | endif
endfunction
function! s:CancelBlame() abort
  call s:CloseBlame()
  call s:CancelTask('blame')
  let s:blame_key = []
endfunction
function! s:BlameResult(key, output, limited) abort
  if !s:BufferAllows(a:key[1]) | return | endif
  if !s:blame_enabled || a:key !=# s:blame_key || bufnr('%') != a:key[1] || b:changedtick != a:key[3] || &modified | return | endif
  let author = matchstr(a:output, '\nauthor \zs[^\n]*')
  let summary = matchstr(a:output, '\nsummary \zs[^\n]*')
  let timestamp = str2nr(matchstr(a:output, '\nauthor-time \zs\d*'))
  if empty(author) | return | endif
  let position = screenpos(win_getid(), line('.'), strlen(getline('.')) + 1)
  if position.row == 0 || position.col + 12 > win_screenpos(0)[1] + winwidth(0) | return | endif
  let s:blame_popup = popup_create('  ' . author . ' · ' . strftime('%Y-%m-%d', timestamp) . ' · ' . summary,
        \ {'line': position.row, 'col': position.col + 1, 'pos': 'topleft', 'wrap': 0,
        \ 'maxwidth': win_screenpos(0)[1] + winwidth(0) - position.col - 1, 'highlight': 'Comment', 'zindex': 10})
endfunction
function! s:BlameStart(key, timer) abort
  if a:timer != s:blame_timer | return | endif
  let s:blame_timer = -1
  if a:key !=# s:blame_key || !s:blame_enabled || !s:BufferAllows(a:key[1]) | return | endif
  let row = a:key[2]
  call s:RunCommand('blame', ['git', '--no-pager', 'blame', '--line-porcelain', '-L', row . ',' . row, '--', expand('%:p')],
        \ {'cwd': s:ProjectRoot().root, 'quiet': 1}, function('<SID>BlameResult', [a:key]))
endfunction
function! s:QueueBlame() abort
  if !s:blame_enabled | return | endif
  let key = [win_getid(), bufnr('%'), line('.'), b:changedtick, winsaveview().leftcol, line('w0'), expand('%:p'), &filetype]
  if key ==# s:blame_key | return | endif
  call s:CloseBlame()
  call s:CancelTask('blame')
  let s:blame_key = key
  if !s:BufferAllows(bufnr('%')) || &modified || !s:ProjectRoot().git | return | endif
  let s:blame_timer = timer_start(150, function('<SID>BlameStart', [key]))
endfunction
function! s:ToggleBlame() abort
  let s:blame_enabled = !s:blame_enabled
  call s:CancelBlame()
  call s:QueueBlame()
  call s:Info('Inline blame: ' . (s:blame_enabled ? 'on' : 'off'))
endfunction
augroup NopackBlame
  autocmd!
  autocmd User NopackCancel call <SID>CancelBlame()
  autocmd CursorMoved,BufEnter,WinEnter,WinScrolled,BufWritePost,BufFilePost,FileType,TextChanged * call <SID>QueueBlame()
  autocmd InsertEnter,BufLeave,WinLeave * call <SID>CancelBlame()
augroup END

" =========================================
" ======== NATIVE STICKY CONTEXT ===========
" =========================================
let s:sticky_enabled = 0
let s:sticky_popup = 0
let s:sticky_numbers = 0
let s:sticky_timer = -1
let s:sticky_cache = {}
function! s:CloseSticky() abort
  for popup in [s:sticky_popup, s:sticky_numbers]
    if popup | call popup_close(popup) | endif
  endfor
  let s:sticky_popup = 0
  let s:sticky_numbers = 0
endfunction

function! s:StickyHeaders(top, first, lines) abort
  let base = a:top
  let last = a:first + len(a:lines) - 1
  while base <= last
    let text = trim(a:lines[base - a:first])
    if text !~# '^\%(#\|//\|/\*\|\*\|$\)' && text !~# '^).*[:{]$' | break | endif
    let base += 1
  endwhile
  if base > last | return [[], {}] | endif
  let level = indent(base)
  let result = []
  let func = {}
  for row in reverse(range(max([a:first, a:top - 1000]), a:top - 1))
    let text = trim(a:lines[row - a:first])
    if text =~# '^\%(#\|//\|/\*\|\*\|$\)' || indent(row) >= level | continue | endif
    let keyword = matchstr(substitute(text, '^async\s\+', '', ''), '^\w\+')
    if text =~# '^[])}]' || text =~# '^[{[(;]\+$' | continue | endif
    if &filetype ==# 'python' && index(['def', 'class', 'if', 'elif', 'else', 'for', 'while', 'try', 'except', 'finally', 'with', 'match', 'case'], keyword) < 0 | continue | endif
    let entry = {'text': a:lines[row - a:first], 'lnum': row}
    call insert(result, entry)
    if empty(func) && (keyword ==# 'def' || keyword ==# 'function' || text =~# '^local\s\+function\s')
      let func = entry
    endif
    let level = indent(row)
    if level == 0 | break | endif
  endfor
  return [result, func]
endfunction

function! s:StickyUpdate(timer) abort
  let s:sticky_timer = -1
  if !s:sticky_enabled || !s:IsEditorWindow(win_getid())
        \ || !s:BufferAllows(bufnr('%')) || getcmdwintype() !=# ''
    call s:CloseSticky()
    return
  endif
  let win = win_getid()
  let view = winsaveview()
  let screen = win_screenpos(0)
  let row = screenpos(win, line('.'), col('.')).row - screen[0]
  let limit = min([8, winheight(0) / 3, row - 1])
  if limit < 1 | call s:CloseSticky() | return | endif
  let targets = []
  let number = view.topline
  for height in range(1, limit + 1)
    while number < line('$')
      let next = max([number, foldclosedend(number)]) + 1
      if next > line('$') | break | endif
      let nextrow = screenpos(win, next, 1).row
      if nextrow == 0 || nextrow > screen[0] + height | break | endif
      let number = next
    endwhile
    call add(targets, number)
  endfor
  let key = [win, bufnr('%'), b:changedtick, view.topline, &tabstop, &vartabstop, &filetype, targets, limit]
  if get(s:sticky_cache, 'key', []) !=# key
    let first = max([1, view.topline - 1000])
    let last = min([line('$'), targets[-1] + 20])
    if line2byte(last + 1) - line2byte(first) > 256 * 1024 | call s:CloseSticky() | return | endif
    let source = getline(first, last)
    let [scopes, func] = s:StickyHeaders(view.topline, first, source)
    let scope_count = min([len(scopes), limit])
    for iteration in range(limit)
      if scope_count == 0 | break | endif
      let [covered, enclosing] = s:StickyHeaders(targets[scope_count], first, source)
      if !empty(enclosing) && !empty(func) && enclosing.lnum != func.lnum && enclosing.lnum >= view.topline
        let scope_count = max([0, min([scope_count, screenpos(win, enclosing.lnum, 1).row - screen[0] - 1])])
        break
      endif
      if len(covered) < scope_count | break | endif
      let scopes = covered
      let func = enclosing
      let next = min([len(scopes), limit])
      if next == scope_count | break | endif
      let scope_count = next
    endfor
    let shown = scope_count ? scopes[-scope_count:] : []
    if scope_count && index(shown, scopes[0]) < 0 | let shown[0] = scopes[0] | endif
    if scope_count && !empty(func) && index(shown, func) < 0 | let shown[min([1, scope_count - 1])] = func | endif
    let s:sticky_cache = {'key': key, 'scopes': shown}
  endif
  if empty(s:sticky_cache.scopes) | call s:CloseSticky() | return | endif
  let gutter = getwininfo(win)[0].textoff
  let width = winwidth(0) - gutter
  if width < 1 | call s:CloseSticky() | return | endif
  let draw_key = [screen, width, gutter, view.leftcol, &syntax, &list, &listchars, &number, &relativenumber]
  if s:sticky_popup && get(s:sticky_cache, 'draw_key', []) ==# draw_key | return | endif
  let lines = map(copy(s:sticky_cache.scopes), 'v:val.text') + [repeat('─', width)]
  let labels = map(copy(s:sticky_cache.scopes), 'printf("%*s ", max([0, gutter - 1]), &number || &relativenumber ? string(v:val.lnum) : "")') + [repeat('─', gutter)]
  let options = {'line': screen[0], 'col': screen[1] + gutter, 'pos': 'topleft', 'wrap': 0,
        \ 'minwidth': width, 'maxwidth': width, 'minheight': len(lines), 'maxheight': len(lines), 'highlight': 'Pmenu', 'zindex': 20}
  if !s:sticky_popup
    let s:sticky_popup = popup_create(lines, options)
  else
    call popup_move(s:sticky_popup, options)
    if getbufline(winbufnr(s:sticky_popup), 1, '$') !=# lines | call popup_settext(s:sticky_popup, lines) | endif
  endif
  let buf = winbufnr(s:sticky_popup)
  let syntax = empty(&syntax) ? &filetype : &syntax
  if getbufvar(buf, '&syntax') !=# syntax | call setbufvar(buf, '&syntax', syntax) | endif
  call setbufvar(buf, '&tabstop', &tabstop)
  call setbufvar(buf, '&vartabstop', &vartabstop)
  call setwinvar(s:sticky_popup, '&list', &list)
  call setwinvar(s:sticky_popup, '&listchars', &listchars)
  call win_execute(s:sticky_popup, 'call winrestview(' . string({'topline': 1, 'leftcol': view.leftcol}) . ')')
  if gutter > 0
    let options.col = screen[1]
    let options.minwidth = gutter
    let options.maxwidth = gutter
    if !s:sticky_numbers
      let s:sticky_numbers = popup_create(labels, options)
    else
      call popup_move(s:sticky_numbers, options)
      if getbufline(winbufnr(s:sticky_numbers), 1, '$') !=# labels | call popup_settext(s:sticky_numbers, labels) | endif
    endif
  elseif s:sticky_numbers
    call popup_close(s:sticky_numbers)
    let s:sticky_numbers = 0
  endif
  let s:sticky_cache.draw_key = draw_key
endfunction

function! s:QueueSticky() abort
  if s:sticky_enabled && s:sticky_timer == -1
    let s:sticky_timer = timer_start(0, function('<SID>StickyUpdate'))
  endif
endfunction
function! s:ToggleSticky() abort
  let s:sticky_enabled = !s:sticky_enabled
  call s:CloseSticky()
  call s:QueueSticky()
endfunction
nnoremap <silent> <leader>Ts :call <SID>ToggleSticky()<CR>
augroup NopackSticky
  autocmd!
  autocmd BufEnter,WinEnter,CursorMoved,CursorMovedI,TextChanged,TextChangedI,WinScrolled,VimResized,FileType * call <SID>QueueSticky()
  autocmd BufLeave,WinLeave,TabLeave * call <SID>CloseSticky()
  autocmd OptionSet number,relativenumber,numberwidth,signcolumn,foldcolumn,list,listchars,tabstop,vartabstop,shiftwidth,wrap,previewwindow call <SID>QueueSticky()
augroup END

" =========================================
" ============== SPACE GUIDE ==============
" =========================================
let s:guide_labels = {
      \ 'A': 'Dashboard', 'f': 'Find files', 'e': 'File tree', 'o': 'Ctags outline', 'u': 'Undo preview',
      \ 't': 'Search word', 'c': 'Force-close buffer', 'a': 'Select all', 'w': 'Compare windows', '<CR>': 'Git files',
      \ 'b': 'Buffers', 'g': 'Git', 's': 'Search', 'S': 'Substitute', 'T': 'Toggles', 'p': 'Sessions', 'l': 'Language tools', 'n': 'File tree',
      \ 'Ts': 'Sticky context', 'TS': 'Smooth paging', 'Ti': 'Indent guides', 'Tl': 'Tool status', 'Th': 'Cursor word highlight',
      \ 'gg': 'Lazygit / Git status', 'gd': 'Diff index', 'gD': 'Diff HEAD', 'gb': 'Inline blame', 'gn': 'Next hunk', 'gp': 'Previous hunk',
      \ 'lf': 'Format buffer', 'nr': 'Refresh tree', 'nh': 'Edit hidden-file patterns',
      \ 'pr': 'Restore directory session', 'pl': 'Restore last session', 'pS': 'Select session', 'pd': 'Stop saving session',
      \ 'st': 'Search project text', 's/': 'Search open files', 'sr': 'Recent files', 'sn': 'Vim configuration',
      \ 'sc': 'Commands', 'sh': 'Help', 'sp': 'Themes', 'sk': 'Keymaps', 'sb': 'Buffers', 'sg': 'Git log',
      \ 'bp': 'Pick buffer', 'bw': 'Close buffer', 'be': 'Close other buffers', 'bm': 'Close other buffers',
      \ 'bh': 'Close buffers to left', 'bl': 'Close buffers to right', 'bj': 'Move buffer left', 'bk': 'Move buffer right',
      \ 'bD': 'Sort by directory', 'bL': 'Sort by language', 'Sa': 'Replace throughout file', 'Sf': 'Replace from cursor',
      \ }
function! s:GuideMappings(prefix) abort
  let result = {}
  let prefix = a:prefix
  for mapping in maplist()
    if mapping.mode !~# 'n\| ' || mapping.abbr | continue | endif
    let lhs = substitute(mapping.lhs, '<Space>', ' ', 'g')
    if stridx(lhs, prefix) != 0 || lhs ==# ' ' | continue | endif
    let rest = strpart(lhs, strlen(prefix))
    let next = rest =~# '^<' ? matchstr(rest, '^<[^>]*>') : strcharpart(rest, 0, 1)
    let key = prefix . next
    let shortcut = strpart(key, 1)
    let result[key] = {'key': key, 'label': shortcut . '  ' . get(s:guide_labels, shortcut, 'More shortcuts')}
  endfor
  return sort(values(result), {a, b -> a.key ==# b.key ? 0 : a.key ># b.key ? 1 : -1})
endfunction
function! s:GuideFilter(id, key) abort
  if a:key ==# "\<CursorHold>" | return 1 | endif
  if index(["\<Esc>", "\<C-C>"], a:key) >= 0 | call popup_close(a:id) | return 1 | endif
  let prefix = getwinvar(a:id, 'nopack_prefix') . a:key
  call popup_close(a:id)
  if !empty(maparg(prefix, 'n'))
    call feedkeys(prefix, 'mi')
  else
    call s:SpaceGuide(prefix)
  endif
  return 1
endfunction
function! s:SpaceGuide(prefix) abort
  let mappings = s:GuideMappings(a:prefix)
  if empty(mappings) | return | endif
  let id = popup_create(map(mappings, 'v:val.label'), {'title': ' Space shortcuts · Esc closes ',
        \ 'line': &lines - 2, 'col': 2, 'pos': 'botleft', 'maxheight': max([4, &lines / 3]),
        \ 'maxwidth': max([20, &columns - 6]), 'border': [1], 'padding': [0, 1, 0, 1],
        \ 'filter': function('<SID>GuideFilter'), 'mapping': 0, 'zindex': 250, 'wrap': 0})
  call setwinvar(id, 'nopack_prefix', a:prefix)
endfunction
nnoremap <silent> <Space> :call <SID>SpaceGuide(' ')<CR>

" =========================================
" ============= SMOOTH SCROLL ==============
" =========================================
let s:smooth_enabled = 0
let s:scroll_timer = -1
function! s:ScrollFrame(win, buf, direction, state, timer) abort
  if !s:BufferAllows(a:buf) || win_getid() != a:win || bufnr('%') != a:buf || mode() !~# '^n'
    call timer_stop(a:timer)
    return
  endif
  let amount = min([a:state.remaining, max([1, a:state.step])])
  let saved = &l:scroll
  execute 'normal! ' . amount . (a:direction > 0 ? "\<C-D>" : "\<C-U>")
  let &l:scroll = saved
  let a:state.remaining -= amount
  if a:state.remaining <= 0 | call timer_stop(a:timer) | let s:scroll_timer = -1 | endif
endfunction
function! s:Scroll(key) abort
  call timer_stop(s:scroll_timer)
  if !s:smooth_enabled || &diff || !s:BufferAllows(bufnr('%')) || reg_executing() !=# '' || reg_recording() !=# ''
    execute 'normal! ' . (v:count ? v:count : '') . a:key
    return
  endif
  let full = index(["\<C-F>", "\<C-B>"], a:key) >= 0
  let amount = full ? max([1, winheight(0) - 2]) * v:count1 : (v:count ? v:count : &scroll)
  let direction = index(["\<C-D>", "\<C-F>"], a:key) >= 0 ? 1 : -1
  let state = {'remaining': amount, 'step': max([1, amount / 6])}
  let s:scroll_timer = timer_start(10, function('<SID>ScrollFrame', [win_getid(), bufnr('%'), direction, state]), {'repeat': -1})
endfunction
function! s:ToggleSmooth() abort
  let s:smooth_enabled = !s:smooth_enabled
  call timer_stop(s:scroll_timer)
  call s:Info('Smooth scroll: ' . (s:smooth_enabled ? 'on' : 'off'))
endfunction
nnoremap <silent> <leader>TS :call <SID>ToggleSmooth()<CR>
nnoremap <silent> <C-D> <Cmd>call <SID>Scroll("\<lt>C-D>")<CR>
nnoremap <silent> <C-U> <Cmd>call <SID>Scroll("\<lt>C-U>")<CR>
nnoremap <silent> <C-F> <Cmd>call <SID>Scroll("\<lt>C-F>")<CR>
nnoremap <silent> <C-B> <Cmd>call <SID>Scroll("\<lt>C-B>")<CR>

let s:dashboard_header = [
      \ '',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡀⠀⠀⠀⠀⠀⡀⢀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠼⠤⠤⠤⠤⠤⣧⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡸⢸⠀⠀⠀⠀⠀⠀⡟⠀⣾⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠃⢸⠘⢏⠉⠉⠉⡽⡇⠀⢹⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠃⠀⢸⢠⠘⡆⠀⡸⠁⡇⡀⢸⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡰⠃⠀⡖⡞⣚⣆⣹⣼⣁⣀⢳⠓⠚⢹⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡴⠁⠀⠀⡇⣧⠀⢀⡜⢳⡀⠀⢸⠀⠀⠀⢣⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠜⠁⠀⠀⠀⡇⡟⢲⡞⠒⠒⢳⣺⢸⠀⠀⠀⠈⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡠⠋⠀⠀⠀⠀⠀⡇⡷⠃⡇⠀⠀⠀⢹⣸⠀⠀⠀⠀⠘⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⠁⠀⠀⠀⠀⠀⣠⢿⢓⣒⣓⣀⣀⣀⡞⠛⡖⠒⠢⠀⠀⡟⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⠁⠀⠀⠀⠀⠀⣠⠞⢹⢸⢸⠀⠀⠀⠀⠀⡇⠀⠘⢦⢰⠀⠀⡇⠘⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⢀⡤⠊⠁⠀⠀⠀⠀⠀⣠⠞⠁⠀⢸⢸⠘⠒⠲⠒⠒⠒⡇⠀⠀⠀⠳⡄⠀⡇⠀⠈⢆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⢀⣠⠴⠊⠁⠀⠀⠀⠀⠀⢀⡤⡎⠁⠀⠀⠀⢸⢸⠀⠀⢀⠀⠀⠀⡇⠀⠀⠀⢀⠈⢦⡗⠀⠀⠈⢣⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡗⠒⡁⠀⠀⠀⠀⠀⠀⠀',
      \ '⠈⠁⠀⠀⠀⠀⠀⠀⢀⡠⠖⠁⠀⡇⠀⠀⠀⠀⠚⣾⠒⣒⠚⣢⠀⢰⠓⠒⠒⠒⠺⠀⠀⣟⢆⠀⠀⠀⡟⣄⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣑⡞⣹⡄⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⢀⣀⡤⠚⠁⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⣿⢰⠀⠀⠀⠀⢸⢰⠀⠀⠀⠀⡇⠀⡇⠀⠙⠢⣄⡇⠈⠣⡀⠀⠀⠀⠀⣀⡴⣋⢼⡏⠠⢻⠘⢄⠀⠀⠀⠀⠀',
      \ '⢀⠤⠔⠊⠉⠀⡇⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⣿⠘⠒⠒⢲⠒⢺⢸⠀⠀⠀⠀⡇⠀⡇⠀⠀⠀⠀⡏⠑⠒⢺⠓⠲⠶⡟⠓⠉⡇⢸⣇⣠⢸⠀⠀⡗⠦⣀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⣿⠀⠀⠀⢸⠀⢸⢸⠀⠀⠀⠀⡅⠀⣇⣀⣀⣀⠀⡇⠀⠠⢼⠤⠤⣤⣧⣤⣤⣧⣼⣧⣼⢸⠤⠤⠇⣀⣈⣉⡁',
      \ '⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⢀⣀⣿⠀⠤⠤⠼⠔⢺⢸⠀⠀⠀⠀⣏⣀⠧⡤⡤⣖⢒⣷⣚⡻⠭⠯⠭⠗⠒⠓⠒⠛⢻⣏⣹⢸⠉⠉⠁⠀⠐⠒⠂',
      \ '⠀⠀⠀⠀⠀⠀⡇⠀⠀⣀⡀⠤⠤⡗⠒⠈⠉⠁⠀⢸⠀⠀⠀⣀⣠⣼⢸⠀⠀⠀⠀⣇⠦⠽⠚⠒⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⡟⢻⢸⣀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⢀⣀⠤⠔⡗⠉⠁⠀⠀⠀⠀⡇⠀⠀⠀⢀⡠⣼⠖⡘⢍⠰⡡⢺⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⢀⠁⠀⠸⠇⠸⠼⠀⠈⠆⠢⠄⠀⠀',
      \ '⠐⠉⠁⠀⠀⠀⡇⠀⠀⠀⠀⠀⢀⣧⠤⠖⠋⢽⣠⢃⠞⣈⡶⠜⠒⢹⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⠔⡠⠌⢁⡐⠒⢒⡠⠀⢓⡈⠄⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⡇⠀⢀⡠⠔⠚⡍⠰⠎⣠⠒⣢⡥⢾⠋⠁⠀⠀⠀⢸⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠈⠉⢦⡀⠀⣀⠧⠚⠉⠒⠒⠒⠃⢀⣴⠗⠋⠁⡇⢸⠀⠐⠂⠢⠤⢼⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⢣⠈⠉⠉⠉⠉⠻⣉⡶⠖⠋⠀⠀⠀⠀⡇⢸⠀⠸⡉⠏⢐⣾⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⣖⠒⠒⠠⡀⠀⠀⡇⢸⠀⠀⡱⠈⠁⣼⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
      \ ]
let s:dashboard = 0
let s:dashboard_items = [['f', 'Find file', ' f'], ['r', 'Recent files', ' sr'], ['l', 'Restore last session', ' pl'], ['p', 'Select session', ' pS'],
      \ ['n', 'New file', ':enew'], ['c', 'Config', ':edit ' . fnameescape(s:vimrc_path)], ['q', 'Quit', ':qa!']]
function! s:DashboardFilter(id, key) abort
  let index = getwinvar(a:id, 'nopack_selection', 0)
  if index(['j', "\<Down>", "\<Tab>"], a:key) >= 0
    let index = (index + 1) % len(s:dashboard_items)
  elseif index(['k', "\<Up>", "\<S-Tab>"], a:key) >= 0
    let index = (index + len(s:dashboard_items) - 1) % len(s:dashboard_items)
  elseif a:key ==# "\<Esc>" || a:key ==# ':'
    call popup_close(a:id)
    if a:key ==# ':' | call feedkeys(':', 'ni') | endif
    return 1
  else
    let keys = map(copy(s:dashboard_items), 'v:val[0]')
    let chosen = a:key ==# "\<CR>" ? index : index(keys, a:key)
    if chosen >= 0
      let action = s:dashboard_items[chosen][2]
      call popup_close(a:id)
      call feedkeys(action . (action[0] ==# ':' ? "\<CR>" : ''), 'mi')
    endif
    return 1
  endif
  call setwinvar(a:id, 'nopack_selection', index)
  call win_execute(a:id, 'call cursor(' . (getwinvar(a:id, 'nopack_menu_start') + index * 2) . ', 1)')
  return 1
endfunction
function! s:DashboardClosed(id, result) abort
  if s:dashboard != a:id | return | endif
  let s:dashboard = 0
  augroup NopackDashboardWindow
    autocmd!
  augroup END
  call popup_close(s:dashboard_chrome.background)
  let &showtabline = s:dashboard_chrome.showtabline
  let &laststatus = s:dashboard_chrome.laststatus
  if has_key(s:dashboard_chrome, 't_ve')
    let &t_ve = s:dashboard_chrome.t_ve
  endif
endfunction
function! s:DashboardCheck() abort
  " Recover after popup_clear() and keep the dashboard with its original editor.
  let position = popup_getpos(s:dashboard)
  if empty(position)
    call s:DashboardClosed(s:dashboard, -1)
  elseif !get(position, 'visible', 0) || win_getid() != s:dashboard_chrome.win
        \ || bufnr('%') != s:dashboard_chrome.buf
    call popup_close(s:dashboard)
  endif
endfunction
function! s:DashboardHighlights() abort
  highlight! link NopackDashboardHeader Title
  highlight! link NopackDashboardDesc String
  highlight! link NopackDashboardKey Number
endfunction
call s:DashboardHighlights()

function! s:DashboardPosition() abort
  if !s:dashboard || empty(popup_getpos(s:dashboard)) | return | endif
  let height = max([1, &lines - &cmdheight])
  if popup_getoptions(s:dashboard).maxheight != height
    let content_height = len(getbufline(winbufnr(s:dashboard), 1, '$'))
    call popup_setoptions(s:dashboard, {'line': max([1, (height - content_height) / 2 + 1]),
          \ 'maxheight': height})
  endif
  let background = popup_getoptions(s:dashboard_chrome.background)
  if background.maxwidth != &columns || background.maxheight != height
    call popup_setoptions(s:dashboard_chrome.background, {'minwidth': &columns, 'maxwidth': &columns,
          \ 'minheight': height, 'maxheight': height})
  endif
endfunction

function! s:Dashboard() abort
  if s:dashboard | call s:DashboardCheck() | endif
  if s:dashboard | return | endif
  let width = max([20, min([100, &columns - 4])])
  let header = &lines >= 45 && width >= 100 ? copy(s:dashboard_header) : ['VIM · NOPACK', 'Native Vim 9.0+ · ctags · no plugins']
  let rows = []
  for text in header
    call add(rows, repeat(' ', max([0, (width - strdisplaywidth(text)) / 2])) . text)
  endfor
  call add(rows, '')
  let first = len(rows) + 1
  let menu_width = min([60, width])
  let menu_left = max([0, (width - menu_width) / 2])
  for item in s:dashboard_items
    let gap = max([1, menu_width - strdisplaywidth(item[1]) - strdisplaywidth(item[0])])
    call add(rows, repeat(' ', menu_left) . item[1] . repeat(' ', gap) . item[0])
    call add(rows, '')
  endfor
  let footer = 'https://sunwook-hwang.github.io'
  call add(rows, repeat(' ', max([0, (width - strlen(footer)) / 2])) . footer)
  let height = max([1, &lines - &cmdheight])
  let s:dashboard = popup_create(rows, {'minwidth': width, 'maxwidth': width, 'maxheight': height,
        \ 'pos': 'topleft', 'line': max([1, (height - len(rows)) / 2 + 1]),
        \ 'highlight': 'Normal', 'cursorline': 1, 'mapping': 0, 'wrap': 0, 'zindex': 180,
        \ 'filter': function('<SID>DashboardFilter'), 'callback': function('<SID>DashboardClosed')})
  let s:dashboard_chrome = {'showtabline': &showtabline, 'laststatus': &laststatus,
        \ 'win': win_getid(), 'buf': bufnr('%')}
  " Cover the editor's text and guides without changing its window-local options.
  let s:dashboard_chrome.background = popup_create([''], {'line': 1, 'col': 1, 'pos': 'topleft',
        \ 'minwidth': &columns, 'maxwidth': &columns, 'minheight': height, 'maxheight': height,
        \ 'highlight': 'Normal', 'zindex': 179, 'mapping': 0, 'scrollbar': 0})
  if !has('gui_running')
    let s:dashboard_chrome.t_ve = &t_ve
    let &t_ve = &t_vi
  endif
  set showtabline=0 laststatus=0
  augroup NopackDashboardWindow
    autocmd!
    autocmd SafeState,WinEnter,BufEnter * call <SID>DashboardCheck()
    autocmd TabLeave * call popup_close(s:dashboard)
    autocmd VimResized * call <SID>DashboardPosition()
  augroup END
  let buf = winbufnr(s:dashboard)
  for name in ['Header', 'Desc', 'Key']
    call prop_type_add('NopackDashboard' . name, {'bufnr': buf, 'highlight': 'NopackDashboard' . name})
  endfor
  for row in range(1, len(header)) + [len(rows)]
    if !empty(rows[row - 1])
      call prop_add(row, 1, {'bufnr': buf, 'type': 'NopackDashboardHeader', 'length': strlen(rows[row - 1])})
    endif
  endfor
  for index in range(len(s:dashboard_items))
    let row = first + index * 2
    let item = s:dashboard_items[index]
    call prop_add(row, menu_left + 1, {'bufnr': buf, 'type': 'NopackDashboardDesc', 'length': strlen(item[1])})
    call prop_add(row, strlen(rows[row - 1]), {'bufnr': buf, 'type': 'NopackDashboardKey', 'length': 1})
  endfor
  call setwinvar(s:dashboard, 'nopack_menu_start', first)
  call setwinvar(s:dashboard, 'nopack_selection', 0)
  call win_execute(s:dashboard, 'call cursor(' . first . ', 1)')
endfunction
function! s:StartupDashboard() abort
  if argc() == 0 && empty(bufname('%')) && !&modified && !has('gui_running') && !has('ttyin') | return | endif
  if argc() == 0 && empty(bufname('%')) && !&modified && line('$') == 1 && getline(1) ==# ''
    call s:Dashboard()
  endif
endfunction
nnoremap <silent> <leader>A :call <SID>Dashboard()<CR>
augroup NopackDashboard
  autocmd!
  autocmd ColorScheme * call <SID>DashboardHighlights()
  autocmd VimEnter * call <SID>StartupDashboard()
augroup END

let &cpoptions = s:save_cpo
unlet s:save_cpo
