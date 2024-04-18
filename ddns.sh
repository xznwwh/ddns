#!/bin/bash

# Cloudflare 相关信息
API_KEY="290c08cf3650560676362c9cdb3a965fbc4c5"  # Cloudflare API 密钥
EMAIL="xznwwh@foxmail.com"    # Cloudflare 账户邮箱
ZONE_ID="9fbdb949b815326bfcccf846cc57c897"  # Cloudflare 区域 ID
DOMAIN="uiii.eu.org"  # 主域名
SUBDOMAIN="ddns"  # 子域名名称
TTL="60"  # 默认 TTL 为一分钟
UPDATE_COUNT=3  # 要更新的最快IP数量及二级域名数量
NUMBER=20      #随机IP数量
PORT=""  # 端口号
DATACENTER="HKG"  # 数据中心

# 文件读取输出相关信息
AsnIata="https://raw.githubusercontent.com/xznwwh/cmliu-ACL4SSR/main/addressescsv.csv"       # 输入文件路径
AsnIata_IPS="ips.txt"      # 输出满足条件的IP地址和端口的文件路径
Shuf_IP="ip.txt"           # 输出随机抽取的IP地址的文件路径
Speed_IPS="speed_ips.txt"  # 速度最快的IP临时文件

LOG_FILE="logDNS.txt"  # 日志文件路径

# 记录日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')

    # 只有日志级别为 INFO 时才记录日志
    if [[ "$level" == "INFO" ]]; then
        echo "$timestamp - [$level] $message"
        echo "$timestamp - [$level] $message" >> "$LOG_FILE"
    fi
}

log "INFO" "开始执行随机IP测速"

# 使用 awk 命令提取满足条件的 IP 地址和端口，并输出到文件
#awk -F',' '$5 == "'"$DATACENTER"'" && $2 == "'"$PORT"'" {print $1 " " $2}' "$AsnIata" > "$AsnIata_IPS"
#awk -F',' '$5 == "'"$DATACENTER"'" && $2 == "'"$PORT"'" && !seen[$1,$2]++ {print $1 " " $2}' "$AsnIata" > "$AsnIata_IPS"
#awk -F',' '$4 == "'"$DATACENTER"'" && $2 == "'"$PORT"'" {print $1 " " $2}' "$AsnIata" > "$AsnIata_IPS"
#awk -F',' '$4 == "'"$DATACENTER"'" && $2 == "'"$PORT"'" && !seen[$1,$2]++ {print $1 " " $2}' "$AsnIata" > "$AsnIata_IPS"
awk -F',' '$4 == "'"$DATACENTER"'" && $2 == "'"$PORT"'" && !seen[$1,$2]++ && !ip_seen[$1]++ {print $1 " " $2}' "$AsnIata" > "$AsnIata_IPS"


log "INFO" "开始整理 $DATACENTER 满足条件的IP地址和端口"

# 随机抽取 20 个端口为 2096 的 IP 地址，并保存到 ip.txt 文件中
shuf "$AsnIata_IPS" | head -n $NUMBER > "$Shuf_IP"
log "INFO" "开始随机抽取 $NUMBER 个端口为 $PORT 的IP地址"

echo "随机抽取 20 个端口为 $PORT 的 IP 地址完成，请查看 $Shuf_IP 文件。"

# 使用 iptest 进行测试，并生成新的 ip.csv 文件
./iptest -test=speed.mingri.icu -file="$Shuf_IP" -outfile=ip.csv -max=10 -speedtest=1 -tls=true -url=speed.mingri.icu/50M.7z

# 选择速度最快的 IP 地址，并将其写入临时输出文件
#sort -t',' -k8,8nr "ip.csv" | awk -F',' '!seen[$1]++' | head -n "$UPDATE_COUNT" | awk -F',' '{print $1}' > "$Speed_IPS"
sort -t',' -k11,11nr "ip.csv" | awk -F',' '!seen[$1]++' | head -n "$UPDATE_COUNT" | awk -F',' '{print $1}' > "$Speed_IPS"

log "INFO" "执行整理随机IP测速完毕"

log "INFO" "开始执行 DDNS 更新 IP 到 $SUBDOMAIN 子域名"

# 删除特定子域名相关的 A 记录
delete_existing_records() {
    log "INFO" "正在删除 $SUBDOMAIN 的现有 DNS 记录"

    existing_records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$SUBDOMAIN.$DOMAIN" \
        -H "X-Auth-Email: $EMAIL" \
        -H "X-Auth-Key: $API_KEY" \
        -H "Content-Type: application/json" | jq -r '.result[].id')

    # 删除每个特定子域名相关的 A 记录
    for record_id in $existing_records; do
        curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
             -H "X-Auth-Email: $EMAIL" \
             -H "X-Auth-Key: $API_KEY" \
             -H "Content-Type: application/json" > /dev/null
    done

    log "INFO" "已删除 $SUBDOMAIN 的现有 DNS 记录"
}

# 添加新的 A 记录
add_new_records() {
    log "INFO" "正在添加新的 DNS 记录到 $SUBDOMAIN 子域名"

    # 提取端口为 2096 且数据中心为 HKG 的 IP 地址，并选择前三个 IP
    local ip_array=($(head -n $UPDATE_COUNT "$Speed_IPS"))

    # 添加每个 IP 地址为新的 A 记录
    for ip in "${ip_array[@]}"; do
        log "INFO" "开始 $SUBDOMAIN 子域名更新,已添加IP地址 $ip 为新的DNS记录成功"
        curl -s -X POST "https://raw.githubusercontent.com/cmliu/WorkerVless2sub/main/addressescsv.csv" \
             -H "X-Auth-Email: $EMAIL" \
             -H "X-Auth-Key: $API_KEY" \
             -H "Content-Type: application/json" \
             --data '{"type":"A","name":"'"$SUBDOMAIN.$DOMAIN"'","content":"'"$ip"'","ttl":'$TTL',"proxied":false}' > /dev/null
    done

    log "INFO" "执行 $SUBDOMAIN.$DOMAIN 更新完毕"
}

# 主程序逻辑
main() {
    delete_existing_records  # 删除特定子域名相关的 A 记录
    add_new_records  # 添加新的 A 记录
}

# 运行主程序
main
