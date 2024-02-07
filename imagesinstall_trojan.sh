#!/bin/bash
RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

IP=`curl -sL -4 ip.sb`
CONFIG_FILE="/etc/trojan-go/config.json"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

function checkSystem()
{
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi
}

apt install -y dnsutils curl wget && clear

function getData()
{
    echo " "
    echo " 本脚本为trojan一键脚本，运行之前请确认如下条件已经具备："
    echo -e "  ${RED}1. 一个伪装域名${PLAIN}"
    echo -e "  ${RED}2. 伪装域名DNS解析指向当前服务器ip（${IP}）${PLAIN}"
    echo " "
    read -p " 确认满足按y，按其他退出脚本：" answer
    if [ "${answer}" != "y" ] && [ "${answer}" != "Y" ]; then
        exit 0
    fi

    echo ""
    while true
    do
        read -p " 请输入伪装域名：" DOMAIN
        if [ -z "${DOMAIN}" ]; then
            echo " 域名输入错误，请重新输入！"
        else
            break
        fi
    done
    DOMAIN=${DOMAIN,,}
    colorEcho $BLUE " 伪装域名(host)： $DOMAIN"

    echo ""
    resolve=$(dig +short "${DOMAIN}")
    if [[ "${resolve}" != "${IP}" ]]; then
            echo " ${DOMAIN} 解析结果：${resolve}"
            echo -e " ${RED}域名未解析到当前服务器IP(${IP})!${PLAIN}"
            exit 1
        fi


    echo ""
    read -p " 请设置trojan密码（不输入则随机生成）:" PASSWORD
    [ -z "$PASSWORD" ] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    colorEcho $BLUE " 密码： " $PASSWORD

    echo ""
    read -p " 请输入trojan端口[100-65535的一个数字，默认443]：" PORT
    [ -z "${PORT}" ] && PORT=443
    if [ "${PORT:0:1}" = "0" ]; then
        echo -e " ${RED}端口不能以0开头${PLAIN}"
        exit 1
    fi
    colorEcho $BLUE " trojan端口： " $PORT
}


function getCert (){
    # 创建Trojan-go目录
    sudo mkdir -p /etc/trojan-go
    
    apt-get install -y socat openssl
    curl -sL https://get.acme.sh | sh -s email=hijk.pw@protonmail.ch
    source ~/.bashrc
    ~/.acme.sh/acme.sh  --upgrade  --auto-upgrade
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh   --issue -d ${DOMAIN} --keylength ec-256  --standalone

    ~/.acme.sh/acme.sh  --install-cert -d ${DOMAIN} --ecc \
                --key-file       /etc/trojan-go/trojan.key  \
                --fullchain-file /etc/trojan-go/trojan.crt
}


function install () 
{
    # 安装依赖
    apt-get install -y nginx

    # 创建Trojan-go目录
    sudo mkdir -p /etc/trojan-go

    # 生成并修改Trojan-go配置文件
    sudo cat > ${CONFIG_FILE}<<EOF
    {
        "run_type": "server",
        "local_addr": "0.0.0.0",
        "local_port": ${PORT},
        "remote_addr": "127.0.0.1",
        "remote_port": 80,
        "password": [
            "${PASSWORD}"
        ],
        "ssl": {
            "cert": "/etc/trojan-go/trojan.crt",
            "key": "/etc/trojan-go/trojan.key",
            "sni": "${DOMAIN}"
        }
    }
EOF

    # 安装docker
    curl -fsSL https://get.docker.com |sudo bash

    # 生成docker配置文件
    cat > /etc/docker/daemon.json << EOF
    {
        "registry-mirrors": ["https://ub816mdv.mirror.aliyuncs.com"],
        "log-driver": "json-file",
        "log-opts": {
        "max-size": "100m"
        },
        "exec-opts": ["native.cgroupdriver=systemd"]
    }
EOF

    ## 重启docker服务
    systemctl  daemon-reload && systemctl restart docker

    # 启动nginx服务，将nginx及docker服务加入开机自启
    systemctl start nginx && systemctl enable  nginx && systemctl enable docker

    # docker 启动Trojan服务
    docker run -d --network host --name trojan-go --restart=always -v /etc/trojan-go:/etc/trojan-go teddysun/trojan-go

    # 开启bbr加速
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p

    # 关闭防火墙
    ufw disable
}

function showInfo () {
    status=$(docker ps |grep trojan-go |awk '{print $8}')
    echo ============================================
    echo -e " ${BLUE}trojan运行状态：${PLAIN}${status}"
    echo ""
    echo -e " ${BLUE}trojan配置文件：${PLAIN}${RED}$CONFIG_FILE${PLAIN}"
    echo -e " ${BLUE}trojan配置信息：${PLAIN}               "
    echo -e "   ${BLUE}IP/address：${PLAIN} ${RED}$IP${PLAIN}"
    echo -e "   ${BLUE}域名/SNI/peer名称:${PLAIN}  ${RED}${DOMAIN}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${PORT}${PLAIN}"
    echo -e "   ${BLUE}密码(password)：${PLAIN}${RED}${PASSWORD}${PLAIN}"
    echo  
    echo ============================================
}

# 执行脚本
checkSystem
getData
getCert
install
showInfo
