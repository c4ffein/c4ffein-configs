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

" ctrl-^jkl to move during edit: <C-^> works with Alacritty with my custom remap in alacritty.toml
inoremap <C-^> <up>
inoremap <C-j> <left>
inoremap <C-k> <down>
inoremap <C-l> <right>
" ctrl-^jkl actually also works in other modes: <C-^> works with Alacritty with my custom remap in alacritty.toml
noremap <C-^> <up>
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

" TODO : Check security
" au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
]])

-- TODO V is not visual line but visual on the word?

vim.cmd('colorscheme c4ffein')

vim.g.editorconfig = false

require('file-finder').setup()
require('file-finder-from-content').setup()
