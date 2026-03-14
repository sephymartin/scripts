#!/usr/bin/env bash
#
# BBR 拥塞控制算法安装/启用脚本
# 支持 BBR/BBRv2/BBRv3 检测和启用
#
if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' "请使用 bash 运行此脚本。" >&2
    printf '%s\n' "示例：" >&2
    printf '%s\n' "  curl -fsSL https://raw.githubusercontent.com/sephymartin/scripts/main/enable_bbr.sh | bash -s -- -a" >&2
    printf '%s\n' "  bash enable_bbr.sh -a" >&2
    exit 1
fi

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本需要 root 权限运行，请使用 sudo 或切换到 root 用户"
    fi
}

# 获取内核版本
get_kernel_version() {
    local version=$(uname -r | cut -d'-' -f1)
    local major=$(echo "$version" | cut -d'.' -f1)
    local minor=$(echo "$version" | cut -d'.' -f2)
    echo "$major.$minor"
}

# 检查内核是否支持 BBR
check_bbr_support() {
    local kernel_version=$(get_kernel_version)
    local major=$(echo "$kernel_version" | cut -d'.' -f1)
    local minor=$(echo "$kernel_version" | cut -d'.' -f2)
    
    # BBR 需要 4.9+ 内核
    if [[ $major -gt 4 ]] || [[ $major -eq 4 && $minor -ge 9 ]]; then
        return 0
    else
        return 1
    fi
}

# 获取可用的拥塞控制算法
get_available_cc() {
    if [[ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
        cat /proc/sys/net/ipv4/tcp_available_congestion_control
    else
        echo "unknown"
    fi
}

# 获取当前使用的拥塞控制算法
get_current_cc() {
    sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown"
}

# 获取当前队列调度算法
get_current_qdisc() {
    sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown"
}

# 检查 BBR 模块是否已加载
check_bbr_module() {
    if lsmod | grep -q "tcp_bbr"; then
        return 0
    fi
    return 1
}

# 显示当前状态
show_status() {
    echo ""
    info "========== 当前系统状态 =========="
    echo "内核版本: $(uname -r)"
    echo "可用拥塞控制算法: $(get_available_cc)"
    echo "当前拥塞控制算法: $(get_current_cc)"
    echo "当前队列调度算法: $(get_current_qdisc)"
    
    if check_bbr_module; then
        echo "BBR 模块状态: ${GREEN}已加载${NC}"
    else
        echo "BBR 模块状态: ${YELLOW}未加载${NC}"
    fi
    
    # 检查是否已启用 BBR
    local current_cc=$(get_current_cc)
    if [[ "$current_cc" == "bbr" ]] || [[ "$current_cc" == "bbr2" ]] || [[ "$current_cc" == "bbr3" ]]; then
        echo -e "BBR 状态: ${GREEN}已启用 ($current_cc)${NC}"
    else
        echo -e "BBR 状态: ${YELLOW}未启用${NC}"
    fi
    echo "=================================="
    echo ""
}

# 检测最佳可用的 BBR 版本
detect_best_bbr() {
    local available=$(get_available_cc)
    
    if echo "$available" | grep -q "bbr3"; then
        echo "bbr3"
    elif echo "$available" | grep -q "bbr2"; then
        echo "bbr2"
    elif echo "$available" | grep -q "bbr"; then
        echo "bbr"
    else
        echo "none"
    fi
}

# 启用 BBR
enable_bbr() {
    local bbr_version=${1:-"bbr"}
    local sysctl_conf="/etc/sysctl.conf"
    local sysctl_bbr="/etc/sysctl.d/99-bbr.conf"
    
    info "正在启用 $bbr_version..."
    
    # 尝试加载 BBR 模块
    if ! check_bbr_module; then
        modprobe tcp_bbr 2>/dev/null || true
    fi
    
    # 创建单独的 sysctl 配置文件
    cat > "$sysctl_bbr" << EOF
# BBR 拥塞控制配置
# 由 enable-bbr.sh 脚本生成

# 使用 fq 队列调度算法（BBR 推荐）
net.core.default_qdisc=fq

# 启用 BBR 拥塞控制算法
net.ipv4.tcp_congestion_control=$bbr_version
EOF
    
    # 移除旧配置（如果存在于 sysctl.conf 中）
    if [[ -f "$sysctl_conf" ]]; then
        sed -i '/net.core.default_qdisc/d' "$sysctl_conf" 2>/dev/null || true
        sed -i '/net.ipv4.tcp_congestion_control/d' "$sysctl_conf" 2>/dev/null || true
    fi
    
    # 应用配置
    sysctl -p "$sysctl_bbr" >/dev/null 2>&1
    
    # 验证是否成功
    local current_cc=$(get_current_cc)
    local current_qdisc=$(get_current_qdisc)
    
    if [[ "$current_cc" == "$bbr_version" ]] && [[ "$current_qdisc" == "fq" ]]; then
        success "$bbr_version 已成功启用！"
        return 0
    else
        error "启用 $bbr_version 失败，请检查系统配置"
    fi
}

# 显示 XanMod 内核安装说明
show_xanmod_info() {
    echo ""
    info "========== XanMod 内核安装说明 =========="
    echo "XanMod 内核提供最新的 BBR 版本（包括 BBRv3）"
    echo ""
    echo "Debian/Ubuntu 安装命令："
    echo "  wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg"
    echo "  echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list"
    echo "  apt update && apt install linux-xanmod-x64v3"
    echo ""
    echo "安装后需要重启系统"
    echo "=========================================="
    echo ""
}

# 主菜单
show_menu() {
    echo ""
    echo "========== BBR 管理菜单 =========="
    echo "1. 查看当前状态"
    echo "2. 启用 BBR（自动选择最佳版本）"
    echo "3. 启用 BBR（标准版）"
    echo "4. 启用 BBRv2（如果可用）"
    echo "5. 启用 BBRv3（如果可用）"
    echo "6. 查看 XanMod 内核安装说明"
    echo "0. 退出"
    echo "=================================="
    echo ""
}

# 交互模式
interactive_mode() {
    while true; do
        show_menu
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1)
                show_status
                ;;
            2)
                local best_bbr=$(detect_best_bbr)
                if [[ "$best_bbr" == "none" ]]; then
                    error "当前内核不支持 BBR，请升级内核到 4.9+"
                fi
                enable_bbr "$best_bbr"
                show_status
                ;;
            3)
                if ! echo "$(get_available_cc)" | grep -q "bbr"; then
                    error "当前内核不支持 BBR"
                fi
                enable_bbr "bbr"
                show_status
                ;;
            4)
                if ! echo "$(get_available_cc)" | grep -q "bbr2"; then
                    error "当前内核不支持 BBRv2，请考虑安装 XanMod 内核"
                fi
                enable_bbr "bbr2"
                show_status
                ;;
            5)
                if ! echo "$(get_available_cc)" | grep -q "bbr3"; then
                    error "当前内核不支持 BBRv3，请考虑安装 XanMod 内核"
                fi
                enable_bbr "bbr3"
                show_status
                ;;
            6)
                show_xanmod_info
                ;;
            0)
                info "退出"
                exit 0
                ;;
            *)
                warn "无效选择，请重试"
                ;;
        esac
    done
}

# 自动模式（无交互）
auto_mode() {
    info "自动模式：检测并启用最佳 BBR 版本"
    
    # 检查内核支持
    if ! check_bbr_support; then
        error "当前内核版本 $(uname -r) 不支持 BBR（需要 4.9+）"
    fi
    
    # 检查是否已启用
    local current_cc=$(get_current_cc)
    if [[ "$current_cc" == "bbr" ]] || [[ "$current_cc" == "bbr2" ]] || [[ "$current_cc" == "bbr3" ]]; then
        success "BBR 已启用 ($current_cc)，无需重复操作"
        show_status
        exit 0
    fi
    
    # 检测并启用最佳版本
    local best_bbr=$(detect_best_bbr)
    if [[ "$best_bbr" == "none" ]]; then
        error "当前内核不支持 BBR"
    fi
    
    enable_bbr "$best_bbr"
    show_status
}

# 显示帮助
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -a, --auto      自动模式（无交互，自动启用最佳 BBR 版本）"
    echo "  -s, --status    仅显示当前状态"
    echo "  -h, --help      显示此帮助信息"
    echo ""
    echo "不带参数运行将进入交互式菜单"
}

# 主函数
main() {
    check_root
    
    case "${1:-}" in
        -a|--auto)
            auto_mode
            ;;
        -s|--status)
            show_status
            ;;
        -h|--help)
            show_help
            ;;
        "")
            show_status
            interactive_mode
            ;;
        *)
            error "未知选项: $1，使用 -h 查看帮助"
            ;;
    esac
}

main "$@"
