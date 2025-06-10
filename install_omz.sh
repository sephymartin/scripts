#!/bin/bash
set -e

sudo apt update && sudo apt install git zsh tmux vim -y 

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "installing Oh My Zsh..."
    git clone https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git
    cd ohmyzsh/tools
    REMOTE=https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git sh install.sh
    rm -rf "./ohmyzsh"
else
    echo "Oh my zsh already installed"
fi

P10K_PATH="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ ! -d "$P10K_PATH" ]; then
    echo "installing Powerlevel10k theme..."
    git clone --depth=1 https://gitee.com/romkatv/powerlevel10k.git "$P10K_PATH"
else
    echo "Powerlevel10k theme already installed"
fi

# Change theme to powerlevel10k
echo "Setting powerlevel10k theme..."
sed -i'.bak' 's/^ZSH_THEME=.*$/ZSH_THEME="powerlevel10k\/powerlevel10k"/' $HOME/.zshrc
echo "Theme set to powerlevel10k, reloading zsh configuration..."