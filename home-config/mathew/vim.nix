{ pkgs, ... }:
{
  programs.vim = {
    enable = true;
    defaultEditor = true;
    plugins = with pkgs.vimPlugins; [
      vim-wayland-clipboard
    ];

    # nixfmt on :w for Nix files; a nixfmt error leaves the buffer untouched. `:let g:nix_autoformat = 0` disables it.
    extraConfig = ''
      " The Home Manager wrapper starts vim with `-u <this file>`, which skips the built-in defaults
      " (filetype detection, syntax, incsearch, ...): load them explicitly.
      source $VIMRUNTIME/defaults.vim

      " `-` = anonymous stdin; a bare nixfmt call prints a deprecation warning that would end up in the buffer.
      let g:nixfmt = '${pkgs.nixfmt}/bin/nixfmt -'

      function! s:NixFormat() abort
        if !get(g:, 'nix_autoformat', 1)
          return
        endif
        let l:view = winsaveview()
        silent keepjumps execute '%!' . g:nixfmt
        if v:shell_error
          let l:err = getline(1, '$')
          silent undo
          echohl ErrorMsg
          for l:line in l:err
            echom 'nixfmt: ' . l:line
          endfor
          echohl None
        endif
        call winrestview(l:view)
      endfunction

      augroup nix_format
        autocmd!
        autocmd BufWritePre *.nix call s:NixFormat()
        autocmd FileType nix let &l:formatprg = g:nixfmt
      augroup END
    '';
  };
}
