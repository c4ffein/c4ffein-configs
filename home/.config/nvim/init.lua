vim.cmd([[
noremap j h
noremap i k
noremap k j
noremap h i

noremap J ^
noremap L $

noremap p P
noremap P p

noremap ; :
noremap : ;

inoremap hh    <esc>
inoremap <C-h> <esc>

" ctrl-ijkl to move during edit: <C-i> works with Alacritty but won't on most legacy terminals
inoremap <C-]> <up>
inoremap <C-j> <left>
inoremap <C-k> <down>
inoremap <C-l> <right>
" ctrl-ijkl actually also works in other modes:  this works with Alacritty but won't on most legacy terminals
noremap <C-]> <up>
noremap <C-j> <left>
noremap <C-k> <down>
noremap <C-l> <right>

vnoremap H I
vnoremap h c

set number relativenumber

syntax enable

" better safe than sorry
set modelines=0
set nomodeline

set ignorecase
set smartcase
set showmatch
set hlsearch
set incsearch
set mouse=a
set tabstop=4
set softtabstop=4
set expandtab
set shiftwidth=4
set autoindent
set wildmode=longest,list
set cc=120
filetype plugin indent on
syntax on
set clipboard=unnamedplus
set ttyfast
]])

vim.g.editorconfig = false
