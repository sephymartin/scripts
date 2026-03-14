#!/bin/bash

set -e  # 遇到错误时退出

echo "🎨 iTerm2 颜色主题管理工具"
echo "========================="
echo

# 检查 iTerm2 是否正在运行
if pgrep -x "iTerm2" > /dev/null; then
    echo "⚠️  请先关闭 iTerm2 再运行此脚本"
    exit 1
fi

# 检查配置文件是否存在
PLIST_FILE="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
if [ ! -f "$PLIST_FILE" ]; then
    echo "❌ 未找到 iTerm2 配置文件: $PLIST_FILE"
    exit 1
fi

echo "📁 创建工作目录..."
WORK_DIR="/tmp/iterm2_theme_removal_$$"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "📋 备份原始配置文件..."
cp "$PLIST_FILE" ./original_com.googlecode.iterm2.plist

echo "🔄 转换配置文件为 XML 格式..."
cp "$PLIST_FILE" ./com.googlecode.iterm2.plist
plutil -convert xml1 com.googlecode.iterm2.plist

echo "🔍 正在检测颜色主题..."

# 提取所有颜色主题名称
THEMES=$(sed -n '/Custom Color Presets/,/<\/dict>/p' com.googlecode.iterm2.plist | \
         grep -E '^\s*<key>[^<]+</key>$' | \
         grep -v "Custom Color Presets\|Ansi\|Alpha\|Blue\|Color\|Green\|Red\|Background\|Bold\|Cursor\|Foreground\|Link\|Selected\|Component\|Space" | \
         sed 's/.*<key>\(.*\)<\/key>.*/\1/')

if [ -z "$THEMES" ]; then
    echo "📭 未发现任何自定义颜色主题"
    rm -rf "$WORK_DIR"
    exit 0
fi

echo "发现的颜色主题："
echo "$THEMES" | nl -w2 -s'. '
THEME_COUNT=$(echo "$THEMES" | wc -l | tr -d ' ')
echo
echo "总共找到 $THEME_COUNT 个颜色主题"
echo

# 提供操作选项
echo "请选择操作："
echo "1. 删除所有颜色主题"
echo "2. 选择性删除特定主题"
echo "3. 仅显示主题列表（不删除）"
echo "4. 退出"
echo
read -p "请输入选择 (1-4): " choice

case $choice in
    1)
        echo "⚠️  即将删除所有 $THEME_COUNT 个颜色主题"
        read -p "确认删除？(y/N): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            echo "🗑️  正在删除所有颜色主题..."
            
            # 创建不包含 Custom Color Presets 的新配置文件
            sed '/Custom Color Presets/,/<\/dict>/c\
        <key>Custom Color Presets</key>\
        <dict>\
        </dict>' com.googlecode.iterm2.plist > com.googlecode.iterm2_cleaned.plist
            
            mv com.googlecode.iterm2_cleaned.plist com.googlecode.iterm2.plist
            
            echo "✅ 已删除所有颜色主题"
        else
            echo "❌ 操作已取消"
            rm -rf "$WORK_DIR"
            exit 0
        fi
        ;;
    2)
        echo "请输入要删除的主题编号（多个编号用空格分隔）："
        read -p "编号: " selected_numbers
        
        if [ -z "$selected_numbers" ]; then
            echo "❌ 未选择任何主题"
            rm -rf "$WORK_DIR"
            exit 0
        fi
        
        echo "🗑️  正在删除选定的主题..."
        
        # 创建临时数组存储要删除的主题名
        themes_array=($THEMES)
        
        for num in $selected_numbers; do
            if [[ $num =~ ^[0-9]+$ ]] && [ $num -ge 1 ] && [ $num -le $THEME_COUNT ]; then
                theme_name="${themes_array[$((num-1))]}"
                echo "  正在删除: $theme_name"
                
                # 删除特定主题的配置块
                # 这里使用 sed 来删除从主题名到对应 </dict> 的整个块
                sed -i.bak "/\s*<key>$theme_name<\/key>/,/^\s*<\/dict>$/d" com.googlecode.iterm2.plist
            else
                echo "  ⚠️  无效编号: $num"
            fi
        done
        
        echo "✅ 已删除选定的主题"
        ;;
    3)
        echo "📄 主题列表已显示，未进行任何删除操作"
        rm -rf "$WORK_DIR"
        exit 0
        ;;
    4|*)
        echo "👋 退出"
        rm -rf "$WORK_DIR"
        exit 0
        ;;
esac

echo
echo "🔄 应用修改..."

# 备份当前配置
backup_file="$HOME/Library/Preferences/com.googlecode.iterm2.plist.backup.$(date +%Y%m%d_%H%M%S)"
cp "$PLIST_FILE" "$backup_file"

# 复制修改后的配置文件
cp com.googlecode.iterm2.plist "$PLIST_FILE"

echo "🧹 清理可能存在的旧配置文件..."
# 移除可能存在的旧配置文件
[ -f "$HOME/Library/Preferences/iTerm2.plist" ] && rm "$HOME/Library/Preferences/iTerm2.plist"
[ -f "$HOME/Library/Preferences/net.sourceforge.iTerm.plist" ] && rm "$HOME/Library/Preferences/net.sourceforge.iTerm.plist"

echo "🔄 重新加载配置..."
cd "$HOME/Library/Preferences/"
defaults read com.googlecode.iterm2 > /dev/null 2>&1 || echo "配置文件可能有问题，请检查"

# 清理工作目录
rm -rf "$WORK_DIR"

echo
echo "✅ 操作完成！"
echo "📁 原始配置文件已备份到: $backup_file"
echo "🚀 请重新启动 iTerm2 并检查颜色主题列表"
echo