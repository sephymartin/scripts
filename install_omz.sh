#!/bin/bash
set -e

sudo apt update && sudo apt install zsh -y 

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    echo "Oh My Zsh installed successfully."

    echo "setting up Oh My Zsh mirror..."
    git -C $ZSH remote set-url origin https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git
    git -C $ZSH pull
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
sed -i'.bak' 's/^ZSH_THEME=.*$/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
echo "Theme set to powerlevel10k, reloading zsh configuration..."
source ~/.zshrc