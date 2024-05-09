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

inoremap hh <esc>

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
