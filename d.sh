#!/bin/bash

# --- 配置区（用户需修改这里）---
SUBFINDER_DIR="/users/zxx/desktop/bin"  # 修改为你的Subfinder实际路径
ONEFORALL_DIR="/users/zxx/desktop/oneforall"  # 修改为你的OneForAll实际路径
OUTPUT_DIR="/users/zxx/desktop/result"         # 原始结果存储目录
DEFAULT_OUTPUT="final.txt"             # 默认最终输出文件名

# --- 自动赋权逻辑 ---
if [ ! -x "$0" ]; then
    echo "[+] 首次运行，自动添加执行权限..."
    chmod +x "$0"
    exec "$0" "$@"
    exit 0
fi

# --- 参数解析 ---
DOMAIN=""
OUTPUT_FILE="$DEFAULT_OUTPUT"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            if [[ -z "$DOMAIN" ]]; then
                DOMAIN="$1"
                shift
            else
                echo "[-] 未知参数: $1"
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$DOMAIN" ]]; then
    echo "Usage: $0 <domain> [-o 自定义结果文件名.txt]"
    exit 1
fi

# --- 工具检查 ---
check_tool() {
    local tool_path="$1"
    if [ ! -f "$tool_path" ] && ! command -v "$(basename "$tool_path")" &> /dev/null; then
        echo "[-] 未找到工具: $tool_path"
        exit 1
    fi
}

# 检查Subfinder（优先使用自定义路径）
SUBFINDER_BIN="$SUBFINDER_DIR/subfinder"
if [ -f "$SUBFINDER_BIN" ]; then
    echo "[+] 使用自定义Subfinder路径: $SUBFINDER_BIN"
else
    SUBFINDER_BIN="subfinder"  # 回退到系统路径
fi
check_tool "$SUBFINDER_BIN"

check_tool "amass"
if [ ! -d "$ONEFORALL_DIR" ]; then
    echo "[-] OneForAll目录不存在: $ONEFORALL_DIR"
    exit 1
fi

# --- 主流程 ---
mkdir -p "$OUTPUT_DIR"

echo "[1/3] Running Subfinder..."
"$SUBFINDER_BIN" -d "$DOMAIN" -o "$OUTPUT_DIR/subfinder.txt" || {
    echo "[-] Subfinder执行失败！"
    exit 1
}

echo "[2/3] Running Amass..."   
amass enum -d "$DOMAIN" -nocolor -o "$OUTPUT_DIR/amass_raw.txt" || {
    echo "[-] Amass执行失败！"
    exit 1
}

# 过滤Amass输出为纯域名
echo "[+] 过滤Amass结果..."
grep "(FQDN)" "$OUTPUT_DIR/amass_raw.txt" | awk '{print $1}' | sort -u > "$OUTPUT_DIR/amass.txt"

echo "[3/3] Running OneForAll..."
cd "$ONEFORALL_DIR" || exit 1
python3 oneforall.py --target "$DOMAIN" --fmt csv --path "$OUTPUT_DIR" run || {
    echo "[-] OneForAll执行失败！"
    exit 1
}

# 过滤OneForAll CSV输出为纯域名（域名在第6列）
echo "[+] 过滤OneForAll结果..."
CSV_FILE="$OUTPUT_DIR/${DOMAIN}.csv"
if [ -f "$CSV_FILE" ]; then
    awk -F',' 'NR>1 {print $6}' "$CSV_FILE" | sort -u > "$OUTPUT_DIR/oneforall.txt"
else
    echo "[-] 未找到OneForAll输出文件: $CSV_FILE"
    exit 1
fi

# --- 合并去重 ---
echo "[+] 合并结果并去重..."
cat "$OUTPUT_DIR/subfinder.txt" "$OUTPUT_DIR/amass.txt" "$OUTPUT_DIR/oneforall.txt" | sort -u > "$OUTPUT_DIR/$OUTPUT_FILE"

# --- 结果统计 ---
COUNT=$(wc -l < "$OUTPUT_DIR/$OUTPUT_FILE")
echo "[+] 完成！共发现 $COUNT 个子域名. 结果保存在: $OUTPUT_DIR/$OUTPUT_FILE"
