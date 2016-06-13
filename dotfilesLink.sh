#! /bin/bash
PWD=`pwd`
ln -s $PWD/.vimrc ~/.vimrc
ln -s $PWD/.zshrc ~/.zshrc
ln -s $PWD/.vim ~/.vim
ln -s $PWD/.tmux.conf ~/.tmux.conf
ln -s $PWD/.psqlrc /home/postgres/.psqlrc
echo $PWD
