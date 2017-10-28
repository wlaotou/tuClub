#!/bin/bash
#Check Root
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

#Read var
read -p "Please Enter Panel Doamin (default:xn--h5qz41fzgdxxl.com): " domain
domain=${domain:=xn--h5qz41fzgdxxl.com}
read -p "Please Enter Panel Mukey (default:lhie1):" mukey
mukey=${mukey:=lhie1}
read -p "Please Enter Pnael NodeID (example:1):" nodeid 


#Update And Install Requirement
apt-get update && apt-get upgrade -y 
apt-get install -y lrzsz rpl tar zip unzip mosh vim wget curl git python-pip screen supervisor grub2 ntpdate
apt-get install -y autoconf automake make libev-dev libtool autoconf-archive gnu-standards autoconf-doc build-essential 

#Set Time
ntpdate 0.debian.pool.ntp.org

#Upgrade Kernel And Turn BBR
get_latest_version() {
    latest_version=$(wget -qO- http://kernel.ubuntu.com/~kernel-ppa/mainline/ | awk -F'\"v' '/v[4-9]./{print $2}' | cut -d/ -f1 | grep -v -  | sort -V | tail -1)
    [ -z ${latest_version} ] && return 1
    if [[ `getconf WORD_BIT` == "32" && `getconf LONG_BIT` == "64" ]]; then
        deb_name=$(wget -qO- http://kernel.ubuntu.com/~kernel-ppa/mainline/v${latest_version}/ | grep "linux-image" | grep "generic" | awk -F'\">' '/amd64.deb/{print $2}' | cut -d'<' -f1 | head -1)
        deb_kernel_url="http://kernel.ubuntu.com/~kernel-ppa/mainline/v${latest_version}/${deb_name}"
        deb_kernel_name="linux-image-${latest_version}-amd64.deb"
    else
        deb_name=$(wget -qO- http://kernel.ubuntu.com/~kernel-ppa/mainline/v${latest_version}/ | grep "linux-image" | grep "generic" | awk -F'\">' '/i386.deb/{print $2}' | cut -d'<' -f1 | head -1)
        deb_kernel_url="http://kernel.ubuntu.com/~kernel-ppa/mainline/v${latest_version}/${deb_name}"
        deb_kernel_name="linux-image-${latest_version}-i386.deb"
    fi
    [ ! -z ${deb_name} ] && return 0 || return 1
}

install_config() {
        /usr/sbin/update-grub
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
}

install_BBR(){
         get_latest_version
        wget -c -t3 -T60 -O ${deb_kernel_name} ${deb_kernel_url}
        dpkg -i ${deb_kernel_name}
        rm -fv ${deb_kernel_name}
        install_config
}

install_BBR

#Install Libsodium From Source Code
mkdir /root/tmp && cd /root/tmp
wget https://download.libsodium.org/libsodium/releases/libsodium-1.0.15.tar.gz
tar xzvf *.tar.gz
cd libsodium*
./configure
make -j8 && make install
echo /usr/local/lib > /etc/ld.so.conf.d/usr_local_lib.conf
ldconfig

#Install And Setting Up SSR-Backend
git clone -b manyuser https://github.com/glzjin/shadowsocks.git "/root/shadowsocks"
cd /root/shadowsocks
pip install --upgrade pip
pip install cymysql
cp apiconfig.py userapiconfig.py
cp config.json user-config.json
rpl "WEBAPI_URL = 'https://zhaoj.in'" "WEBAPI_URL = 'https://${domain}'" ./userapiconfig.py
rpl "WEBAPI_TOKEN = 'glzjin'" "WEBAPI_TOKEN = '${mukey}'" ./userapiconfig.py
rpl "NODE_ID = 1" "NODE_ID = ${nodeid}" ./userapiconfig.py
rpl "MU_SUFFIX = 'zhaoj.in'" "MU_SUFFIX = 'bing.com'" ./userapiconfig.py
rpl "SPEEDTEST = 6" "SPEEDTEST = 0" ./userapiconfig.py
rpl "\"fast_open\": false" "\"fast_open\": true" ./user-config.json

#Make Supervisor Work
echo "[program:ssr]
command=python /root/shadowsocks/server.py 
autorestart=true
autostart=true
user=root" > /etc/supervisor/conf.d/ssr.conf && /etc/init.d/supervisor restart && supervisorctl restart ssr

#VPS Speed Up Settings
echo "net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1" > /etc/sysctl.conf && echo "* soft nofile 51200
* hard nofile 51200" >>  /etc/security/limits.conf && ulimit -n 51200 

#Clean Tmp files
rm -rf /root/tmp


#Set Up Swap 
touch /swapfile
dd if=/dev/zero of=/swapfile bs=128M count=4
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
cp /etc/fstab /etc/fstab.bak
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo "vm.swappiness = 10" » /etc/sysctl.conf

exit
