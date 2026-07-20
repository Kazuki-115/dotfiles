" Silence Vim bells when cursor movement hits a boundary.
set belloff=all

" Enable syntax highlighting and filetype-specific behavior.
syntax on
filetype plugin indent on

" Allow the cursor to move into positions with no actual text.
set virtualedit=all

" Improve readability with line numbers and current-line highlight.
set number
set cursorline

" Use Ctrl-[ as an alternative Escape in Insert mode.
inoremap <C-[> <Esc>

" Keep o/O from staying in Insert mode after opening a new line.
nnoremap o o<Esc>
nnoremap O O<Esc>

" Move with Ctrl-hjkl while staying in Insert mode.
inoremap <C-h> <Left>
inoremap <C-j> <Down>
inoremap <C-k> <Up>
inoremap <C-l> <Right>


" Swap x and X so x behaves like Backspace in Normal/Visual mode.
nnoremap x X
nnoremap X x
xnoremap x X
xnoremap X x
