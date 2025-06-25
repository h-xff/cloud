#!/bin/bash
#===============================================================================
#  脚本名称: allinone.sh
#  脚本用途: 一键部署 OpenStack Train（单节点）
#  适用系统: 纯净版 CentOS 7.9，单网卡，联网
#  作    者: xfcloud
#  联系方式: xfcloud1@126.com
#  创建时间: 2025-06-14
#  最后更新: 2025-06-14
#  版权声明: 本脚本仅供学习和内部使用，禁止商业盗用，转载请注明出处。
#===============================================================================
# 修改主机名
hostnamectl set-hostname openstack

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
# 进度动画
SPINNER=('⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷')
# 显示旋转动画
spin() {
    while true; do
        for i in "${SPINNER[@]}"; do
            echo -ne "\r$1 ${CYAN}$i${NC} 正在工作..."
            sleep 0.1
        done
    done
}

# ----------------------------
# 自动获取本机网络信息
# ----------------------------
# 获取默认路由网卡名称
INTERFACE_NAME=$(ip route show default | awk '/default/ {print $5}')
# 获取本机IP地址
HOST_IP=$(ip addr show $INTERFACE_NAME | grep "inet " | awk '{print $2}' | cut -d/ -f1)
# 设置主机名
HOST_NAME=openstack

# ----------------------------
# 生成随机密码函数
# ----------------------------
generate_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

# ----------------------------
# 密码环境变量（自动生成）
# ----------------------------
DB_PASS=$(generate_password)                  # 数据库root密码
RABBIT_USER="openstack"                      # RabbitMQ用户名
RABBIT_PASS=$(generate_password)             # RabbitMQ密码
ADMIN_PASS=$(generate_password)              # OpenStack管理员密码
DEMO_PASS=$(generate_password)               # 演示用户密码
METADATA_SECRET=$(generate_password)         # 元数据密钥

# ----------------------------
# 组件密码（自动生成）
# ----------------------------
KEYSTONE_DBPASS=$(generate_password)
GLANCE_DBPASS=$(generate_password)
GLANCE_PASS=$(generate_password)
PLACEMENT_DBPASS=$(generate_password)
PLACEMENT_PASS=$(generate_password)
NOVA_DBPASS=$(generate_password)
NOVA_PASS=$(generate_password)
NEUTRON_DBPASS=$(generate_password)
NEUTRON_PASS=$(generate_password)

# ----------------------------
# 常规配置
# ----------------------------
DOMAIN_NAME="Default"                        # 域名
Physical_NAME="provider"                     # 物理网络名称
VERSION="train"                             # OpenStack版本
YUM_REPO="https://mirrors.aliyun.com/centos/7/cloud/x86_64/openstack-$VERSION/"  # 镜像源
minvlan=100                                  # VLAN最小值
maxvlan=200                                  # VLAN最大值

# ----------------------------
# 显示基础配置
# ----------------------------
echo -e "\033[1;36m[ 自动检测系统配置 ]\033[0m"
echo "主机名: $HOST_NAME"
echo "本机IP: $HOST_IP"
echo "网卡接口: $INTERFACE_NAME"
echo "OpenStack版本: $VERSION"
echo "物理网络: $Physical_NAME"
echo "VLAN范围: $minvlan-$maxvlan"

echo -e "\n\033[1;36m[ 随机密码已生成 ]\033[0m"
echo "数据库root密码: $DB_PASS"
echo "管理员密码: $ADMIN_PASS"
echo "元数据密钥: $METADATA_SECRET"
echo "所有组件密码均已自动生成安全密码"

# 添加hosts映射
hostnamectl set-hostname $HOST_NAME
echo "$HOST_IP $HOST_NAME" >> /etc/hosts

# 增强版yum安装检查函数（完美融合旋转动画）
yum_install_check() {
    local max_retries=3
    local retry_count=0
    local packages="$1"
    local log_file=$(mktemp)
    
    # 创建临时文件记录需要安装的包
    local package_file="/tmp/packages_$$.lst"
    echo "$packages" | tr ' ' '\n' > "$package_file"
    
    # 记录总包数
    local total_packages=$(wc -l < "$package_file")
    
    # 开始安装
    while [ $retry_count -lt $max_retries ]; do
        ((retry_count++))
        
        # 显示重试信息
        if [ $retry_count -gt 1 ]; then
            echo -e "${YELLOW}重试安装 [$retry_count/$max_retries]${NC}"
        else
            echo -e "${BLUE}开始安装包...${NC}"
        fi
        
        # 初始化未安装列表
        local missing_packages=""
        
        # 显示安装进度
        echo -e "${BLUE}安装包列表:${NC} $packages"
        
        # 执行yum安装并显示旋转动画
        echo -ne "\r${CYAN}${SPINNER[0]}${NC} ${BLUE}正在安装 $packages${NC} 正在工作..."
        
        # 启动旋转动画
        spin "安装 $packages" &
        local spin_pid=$!
        
        # 执行实际的yum安装
        yum install -y $packages > "$log_file" 2>&1
        local yum_status=$?
        
        # 停止旋转动画
        kill $spin_pid 2>/dev/null
        wait $spin_pid 2>/dev/null
        
        # 清除旋转动画行
        echo -ne "\r\033[K"
        
        # 显示安装结果
        if [ $yum_status -eq 0 ]; then
            echo -e "${GREEN}✓ 安装完成${NC}"
        else
            echo -e "${RED}✗ 安装失败${NC}"
        fi
        
        # 检查哪些包没有安装成功
        while IFS= read -r pkg; do
            # 优化的包存在检查
            if rpm -qa | grep -q "^$pkg" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ 已安装: $pkg${NC}"
            elif rpm -qa | grep -q "$pkg" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ 已安装: $pkg${NC}"
            elif yum list installed | grep -q "^$pkg" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ 已安装: $pkg${NC}"
            elif yum list installed | grep -q "$pkg" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ 已安装: $pkg${NC}"
            else
                echo -e "${RED}✗ 未安装: $pkg${NC}"
                missing_packages+="$pkg "
            fi
        done < "$package_file"
        
        # 如果全部安装成功则退出
        if [ -z "$missing_packages" ]; then
            echo -e "${GREEN}✓ 所有包安装成功: $packages${NC}"
            rm -f "$package_file" "$log_file"
            return 0
        fi
        
        # 更新包列表为仅未安装的包
        packages="$missing_packages"
        echo "$packages" | tr ' ' '\n' > "$package_file"
        
        # 等待重试
        if [ $retry_count -lt $max_retries ]; then
            echo -e "${YELLOW}✗ 未安装包: $(echo $missing_packages | xargs)${NC}"
            for i in {5..1}; do
                printf "\r${YELLOW}等待重试... [${i}秒]${NC}"
                sleep 1
            done
            printf "\n\n"
        fi
    done
    
    # 最终失败处理
    echo -e "${RED}=================================================${NC}"
    echo -e "${RED}错误: 以下包未能安装: $packages${NC}"
    
    # 检查安装状态
    echo -e "\n${BLUE}安装状态报告:${NC}"
    while IFS= read -r pkg; do
        if (rpm -q "$pkg" >/dev/null 2>&1 || yum list installed "$pkg" >/dev/null 2>&1); then
            echo -e "${GREEN}✓ 已安装: $pkg${NC}"
        else
            echo -e "${RED}✗ 未安装: $pkg${NC}"
        fi
    done < "$package_file"
    
    # 显示错误摘要
    echo -e "\n${YELLOW}错误摘要:${NC}"
    grep -iE 'error|fail|critical|warning|invalid|not found|no match|conflict' "$log_file" | sort | uniq
    
    # 系统状态
    echo -e "\n${YELLOW}系统状态检查:${NC}"
    echo "磁盘空间: $(df -h / | awk 'NR==2{print $4}')"
    echo "可用内存: $(free -m | awk '/Mem/ {print $4}')MB"
    echo "YUM缓存: $(du -sh /var/cache/yum 2>/dev/null || echo '空')"
    
    echo -e "${RED}=================================================${NC}"
    echo -e "${RED}完整日志: $log_file${NC}"
    echo -e "${YELLOW}请尝试手动安装: yum install -y $packages\n${NC}"
    
    rm -f "$package_file"
    exit 1
}

echo -e "\n\033[1;33m>>> 1. 配置系统环境\033[0m"
# 禁用SELinux
sed -i 's/SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

# 关闭防火墙
systemctl stop firewalld
systemctl disable firewalld

# 优化SSH配置
sed -i -e 's/#UseDNS yes/UseDNS no/g' -e 's/GSSAPIAuthentication yes/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
systemctl restart sshd

# 配置Yum源
echo -e "\n\033[1;33m>>> 2. 配置Yum源\033[0m"
# 检查并替换Yum源
setup_yum_repos() {
    echo -e "${YELLOW}▶ 检查Yum源配置...${NC}"
    
    # 检查基础源是否是阿里云
    if ! grep -q "mirrors.aliyun.com" /etc/yum.repos.d/CentOS-Base.repo 2>/dev/null; then
        echo -e "  ${CYAN}▸ 替换基础源为阿里云镜像${NC}"
        curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo || {
            echo -e "${RED}▓▓ 错误: 基础源替换失败 ▓▓${NC}"
            return 1
        }
    else
        echo -e "  ${GREEN}✓ 阿里云基础源已存在，跳过${NC}"
        REPO_CHANGED=0
    fi
    
    # 检查OpenStack源是否存在
    if [ ! -f /etc/yum.repos.d/openstack-$VERSION.repo ]; then
        echo -e "  ${CYAN}▸ 添加OpenStack $VERSION 源${NC}"
        REPO_CHANGED=1
        sudo tee /etc/yum.repos.d/openstack-$VERSION.repo <<EOF
[openstack-$VERSION]
name=$VERSION
baseurl=$YUM_REPO
enable=1
gpgcheck=0

[train-extras]
name=CentOS-train-extras
baseurl=https://mirrors.aliyun.com/centos/7/extras/x86_64/
enable=1
gpgcheck=0

[Virt]
name=CentOS-\$releasever - Base
baseurl=http://mirrors.aliyun.com/centos/7/virt/x86_64/kvm-common/
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF
    else
        echo -e "  ${GREEN}✓ OpenStack $VERSION 源已存在，跳过${NC}"
    fi
    
    # 只有在源被修改时才清理缓存
    if [[ $REPO_CHANGED -eq 1 ]]; then
        echo -e "${YELLOW}▶ 检测到源配置变更，正在清理并重建Yum缓存...${NC}"
        spin "Yum缓存操作" &
        SPIN_PID=$!
        disown
        
        yum clean all >/dev/null 2>&1
        yum makecache >/dev/null 2>&1
        
        kill $SPIN_PID >/dev/null 2>&1
        echo -ne "\r\033[K"
        echo -e "  ${GREEN}✓ Yum缓存重建完成${NC}"
        
        # 系统升级
        echo -e "${YELLOW}▶ 执行系统更新...${NC}"
        spin "系统升级" &
        SPIN_PID=$!
        disown
        
        yum -y upgrade >/dev/null 2>&1
        
        kill $SPIN_PID >/dev/null 2>&1
        echo -ne "\r\033[K"
        echo -e "  ${GREEN}✓ 系统升级完成${NC}"
    else
        echo -e "  ${GREEN}✓ 未检测到源配置变更，跳过缓存清理${NC}"
    fi
    
    echo
}
setup_yum_repos

# 配置NTP
echo -e "\n\033[1;33m>>> 3. 配置时间同步\033[0m"
yum_install_check chrony
sed -i '3,6s/^/#/g' /etc/chrony.conf
sed -i '7s/^/server ntp.aliyun.com iburst/g' /etc/chrony.conf
systemctl restart chronyd
systemctl enable chronyd

# 安装基础工具
echo -e "\n\033[1;33m>>> 4. 安装基础工具\033[0m"
yum_install_check "expect lsof net-tools vim bash-completion"

# 安装OpenStack客户端
echo -e "\n\033[1;33m>>> 5. 安装OpenStack客户端\033[0m"
yum_install_check "python-openstackclient openstack-selinux openstack-utils"

# 安装数据库
echo -e "\n\033[1;33m>>> 6. 安装MariaDB数据库\033[0m"
yum_install_check "mariadb mariadb-server MySQL-python"

# 配置数据库
openstack-config --set /etc/my.cnf.d/openstack.cnf mysqld bind-address 0.0.0.0
openstack-config --set /etc/my.cnf.d/openstack.cnf mysqld default-storage-engine innodb
openstack-config --set /etc/my.cnf.d/openstack.cnf mysqld innodb_file_per_table on
openstack-config --set /etc/my.cnf.d/openstack.cnf mysqld max_connections 4096
openstack-config --set /etc/my.cnf.d/openstack.cnf mysqld collation-server utf8_general_ci
openstack-config --set /etc/my.cnf.d/openstack.cnf mysqld character-set-server utf8

# 优化服务限制
crudini --set /usr/lib/systemd/system/mariadb.service Service LimitNOFILE 10000
crudini --set /usr/lib/systemd/system/mariadb.service Service LimitNPROC 10000
systemctl daemon-reload
systemctl enable mariadb.service
systemctl start mariadb.service

# 安全初始化数据库
expect <<EOF
spawn mysql_secure_installation
expect "Enter current password for root (enter for none):"
send "\r"
expect "Set root password?"
send "y\r"
expect "New password:"
send "$DB_PASS\r"
expect "Re-enter new password:"
send "$DB_PASS\r"
expect "Remove anonymous users?"
send "y\r"
expect "Disallow root login remotely?"
send "n\r"
expect "Remove test database and access to it?"
send "y\r"
expect "Reload privilege tables now?"
send "y\r"
expect eof
EOF

# 安装Memcached
echo -e "\n\033[1;33m>>> 7. 安装Memcached\033[0m"
yum_install_check "memcached python-memcached"
sed -i 's/OPTIONS=".*"/OPTIONS="-l 0.0.0.0,::1"/g' /etc/sysconfig/memcached
systemctl enable memcached.service
systemctl restart memcached.service

# 安装消息队列
echo -e "\n\033[1;33m>>> 8. 安装RabbitMQ\033[0m"
yum_install_check "rabbitmq-server"
systemctl start rabbitmq-server.service
sleep 10
systemctl enable rabbitmq-server.service

rabbitmqctl -n rabbit@$HOST_NAME add_user $RABBIT_USER $RABBIT_PASS
rabbitmqctl -n rabbit@$HOST_NAME set_permissions $RABBIT_USER ".*" ".*" ".*"
rabbitmqctl -n rabbit@$HOST_NAME set_permissions -p "/" $RABBIT_USER ".*" ".*" ".*"
rabbitmqctl -n rabbit@$HOST_NAME set_user_tags $RABBIT_USER administrator

# 安装Keystone
echo -e "\n\033[1;33m>>> 9. 安装Keystone身份服务\033[0m"
yum_install_check "openstack-keystone httpd mod_wsgi"

# 配置Keystone数据库
mysql -uroot -p$DB_PASS -e "CREATE DATABASE keystone;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';"

# 配置Keystone
openstack-config --set /etc/keystone/keystone.conf database connection "mysql+pymysql://keystone:$KEYSTONE_DBPASS@$HOST_IP/keystone"
openstack-config --set /etc/keystone/keystone.conf token provider fernet

# 初始化数据库
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

# 引导服务
keystone-manage bootstrap --bootstrap-password $ADMIN_PASS \
  --bootstrap-admin-url http://$HOST_IP:5000/v3/ \
  --bootstrap-internal-url http://$HOST_IP:5000/v3/ \
  --bootstrap-public-url http://$HOST_IP:5000/v3/ \
  --bootstrap-region-id RegionOne

# 配置Apache
sed -i "s/#ServerName www.example.com:80/ServerName $HOST_NAME/g" /etc/httpd/conf/httpd.conf
ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
systemctl enable httpd.service
systemctl restart httpd.service

# 创建OpenStack环境脚本
mkdir -p /etc/xfcloud-openstack
cat > /etc/xfcloud-openstack/admin-openrc <<EOF
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=$DOMAIN_NAME
export OS_PROJECT_DOMAIN_NAME=$DOMAIN_NAME
export OS_AUTH_URL=http://$HOST_IP:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

source /etc/xfcloud-openstack/admin-openrc

# 创建域、项目和用户
openstack domain create --description "Default Domain" $DOMAIN_NAME
openstack project create --domain $DOMAIN_NAME --description "Service Project" service
openstack project create --domain $DOMAIN_NAME --description "Demo Project" demo
openstack user create --domain $DOMAIN_NAME --password $DEMO_PASS demo
openstack role create user
openstack role add --project demo --user demo user

echo -e "\n\033[1;32mKeystone安装完成! 测试Token:\033[0m"
openstack token issue

# 安装Glance
echo -e "\n\033[1;33m>>> 10. 安装Glance镜像服务\033[0m"
yum_install_check "openstack-glance"

# 配置Glance数据库
mysql -uroot -p$DB_PASS -e "CREATE DATABASE glance;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';"

# 创建Glance用户
openstack user create --domain $DOMAIN_NAME --password $GLANCE_PASS glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://$HOST_IP:9292
openstack endpoint create --region RegionOne image internal http://$HOST_IP:9292
openstack endpoint create --region RegionOne image admin http://$HOST_IP:9292

# 配置Glance
openstack-config --set /etc/glance/glance-api.conf database connection "mysql+pymysql://glance:$GLANCE_DBPASS@$HOST_IP/glance"
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken www_authenticate_uri http://$HOST_IP:5000
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_url http://$HOST_IP:5000
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers $HOST_IP:11211
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name $DOMAIN_NAME
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name $DOMAIN_NAME
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken project_name service
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken username glance
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken password $GLANCE_PASS
openstack-config --set /etc/glance/glance-api.conf paste_deploy flavor keystone
openstack-config --set /etc/glance/glance-api.conf glance_store stores file,http
openstack-config --set /etc/glance/glance-api.conf glance_store default_store file
openstack-config --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/

# 初始化数据库
su -s /bin/sh -c "glance-manage db_sync" glance

# 启动服务
systemctl enable openstack-glance-api.service openstack-glance-registry.service
systemctl restart openstack-glance-api.service openstack-glance-registry.service

echo -e "\033[1;32mGlance安装完成! 测试服务状态:\033[0m"
openstack image list

# 安装Placement
echo -e "\n\033[1;33m>>> 11. 安装Placement放置服务\033[0m"
yum_install_check "openstack-placement-api"

# 配置Placement数据库
mysql -uroot -p$DB_PASS -e "CREATE DATABASE placement;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PLACEMENT_DBPASS';"

# 创建Placement用户
openstack user create --domain $DOMAIN_NAME --password $PLACEMENT_PASS placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public http://$HOST_IP:8778
openstack endpoint create --region RegionOne placement internal http://$HOST_IP:8778
openstack endpoint create --region RegionOne placement admin http://$HOST_IP:8778

# 配置Placement
openstack-config --set /etc/placement/placement.conf placement_database connection "mysql+pymysql://placement:$PLACEMENT_DBPASS@$HOST_IP/placement"
openstack-config --set /etc/placement/placement.conf api auth_strategy keystone
openstack-config --set /etc/placement/placement.conf keystone_authtoken auth_url http://$HOST_IP:5000/v3
openstack-config --set /etc/placement/placement.conf keystone_authtoken memcached_servers $HOST_IP:11211
openstack-config --set /etc/placement/placement.conf keystone_authtoken auth_type password
openstack-config --set /etc/placement/placement.conf keystone_authtoken project_domain_name $DOMAIN_NAME
openstack-config --set /etc/placement/placement.conf keystone_authtoken user_domain_name $DOMAIN_NAME
openstack-config --set /etc/placement/placement.conf keystone_authtoken project_name service
openstack-config --set /etc/placement/placement.conf keystone_authtoken username placement
openstack-config --set /etc/placement/placement.conf keystone_authtoken password $PLACEMENT_PASS

# 初始化数据库
su -s /bin/sh -c "placement-manage db sync" placement

# 配置Apache
cat >> /etc/httpd/conf.d/00-placement-api.conf <<EOF
<Directory /usr/bin>
   <IfVersion >= 2.4>
      Require all granted
   </IfVersion>
   <IfVersion < 2.4>
      Order allow,deny
      Allow from all
   </IfVersion>
</Directory>
EOF

# 重启Apache
systemctl restart httpd

echo -e "\033[1;32mPlacement安装完成! 测试服务状态:\033[0m"
placement-status upgrade check

# 安装Nova
echo -e "\n\033[1;33m>>> 12. 安装Nova计算服务\033[0m"
yum_install_check "openstack-nova-api openstack-nova-conductor openstack-nova-novncproxy openstack-nova-scheduler openstack-nova-compute"

# 配置Nova数据库
mysql -uroot -p$DB_PASS -e "CREATE DATABASE nova_api;"
mysql -uroot -p$DB_PASS -e "CREATE DATABASE nova;"
mysql -uroot -p$DB_PASS -e "CREATE DATABASE nova_cell0;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"

# 创建Nova用户
openstack user create --domain $DOMAIN_NAME --password $NOVA_PASS nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public http://$HOST_IP:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://$HOST_IP:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://$HOST_IP:8774/v2.1

# 配置Nova
openstack-config --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
openstack-config --set /etc/nova/nova.conf DEFAULT my_ip $HOST_IP
openstack-config --set /etc/nova/nova.conf DEFAULT use_neutron true
openstack-config --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
openstack-config --set /etc/nova/nova.conf DEFAULT transport_url rabbit://$RABBIT_USER:$RABBIT_PASS@$HOST_IP
openstack-config --set /etc/nova/nova.conf api_database connection "mysql+pymysql://nova:$NOVA_DBPASS@$HOST_IP/nova_api"
openstack-config --set /etc/nova/nova.conf database connection "mysql+pymysql://nova:$NOVA_DBPASS@$HOST_IP/nova"
openstack-config --set /etc/nova/nova.conf api auth_strategy keystone
openstack-config --set /etc/nova/nova.conf vnc enabled true
openstack-config --set /etc/nova/nova.conf vnc server_listen 0.0.0.0
openstack-config --set /etc/nova/nova.conf vnc server_proxyclient_address $HOST_IP
openstack-config --set /etc/nova/nova.conf vnc novncproxy_base_url http://$HOST_IP:6080/vnc_auto.html
openstack-config --set /etc/nova/nova.conf glance api_servers http://$HOST_IP:9292
openstack-config --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp
openstack-config --set /etc/nova/nova.conf scheduler discover_hosts_in_cells_interval 300
openstack-config --set /etc/nova/nova.conf libvirt virt_type qemu

# 配置Keystone认证
openstack-config --set /etc/nova/nova.conf keystone_authtoken www_authenticate_uri http://$HOST_IP:5000/
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_url http://$HOST_IP:5000/
openstack-config --set /etc/nova/nova.conf keystone_authtoken memcached_servers $HOST_IP:11211
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_type password
openstack-config --set /etc/nova/nova.conf keystone_authtoken project_domain_name $DOMAIN_NAME
openstack-config --set /etc/nova/nova.conf keystone_authtoken user_domain_name $DOMAIN_NAME
openstack-config --set /etc/nova/nova.conf keystone_authtoken project_name service
openstack-config --set /etc/nova/nova.conf keystone_authtoken username nova
openstack-config --set /etc/nova/nova.conf keystone_authtoken password $NOVA_PASS

# 配置Placement连接
openstack-config --set /etc/nova/nova.conf placement region_name RegionOne
openstack-config --set /etc/nova/nova.conf placement project_domain_name $DOMAIN_NAME
openstack-config --set /etc/nova/nova.conf placement project_name service
openstack-config --set /etc/nova/nova.conf placement auth_type password
openstack-config --set /etc/nova/nova.conf placement user_domain_name $DOMAIN_NAME
openstack-config --set /etc/nova/nova.conf placement auth_url http://$HOST_IP:5000/v3
openstack-config --set /etc/nova/nova.conf placement username placement
openstack-config --set /etc/nova/nova.conf placement password $PLACEMENT_PASS

# 初始化数据库
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
nova-manage cell_v2 list_cells

# 启动服务
systemctl enable openstack-nova-api.service openstack-nova-scheduler.service \
  openstack-nova-conductor.service openstack-nova-novncproxy.service libvirtd.service openstack-nova-compute.service
systemctl restart openstack-nova-api.service openstack-nova-scheduler.service \
  openstack-nova-conductor.service openstack-nova-novncproxy.service libvirtd.service openstack-nova-compute.service
  
echo -e "\033[1;32mNova安装完成! 计算节点状态:\033[0m"
openstack compute service list

# 安装Neutron
echo -e "\n\033[1;33m>>> 13. 安装Neutron网络服务\033[0m"
yum_install_check "openstack-neutron openstack-neutron-ml2 openstack-neutron-linuxbridge ebtables ipset"

# 配置Neutron数据库
mysql -uroot -p$DB_PASS -e "CREATE DATABASE neutron;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';"

# 创建Neutron用户
openstack user create --domain $DOMAIN_NAME --password $NEUTRON_PASS neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://$HOST_IP:9696
openstack endpoint create --region RegionOne network internal http://$HOST_IP:9696
openstack endpoint create --region RegionOne network admin http://$HOST_IP:9696

# 配置Neutron
openstack-config --set /etc/neutron/neutron.conf database connection "mysql+pymysql://neutron:$NEUTRON_DBPASS@$HOST_IP/neutron"
openstack-config --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
openstack-config --set /etc/neutron/neutron.conf DEFAULT service_plugins router
openstack-config --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips true
openstack-config --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://$RABBIT_USER:$RABBIT_PASS@$HOST_IP
openstack-config --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
openstack-config --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true

# 配置Keystone认证
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken www_authenticate_uri http://$HOST_IP:5000
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://$HOST_IP:5000
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers $HOST_IP:11211
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name $DOMAIN_NAME
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name $DOMAIN_NAME
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken project_name service
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken username neutron
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken password $NEUTRON_PASS

# 配置Nova连接
openstack-config --set /etc/neutron/neutron.conf nova auth_url http://$HOST_IP:5000
openstack-config --set /etc/neutron/neutron.conf nova auth_type password
openstack-config --set /etc/neutron/neutron.conf nova project_domain_name $DOMAIN_NAME
openstack-config --set /etc/neutron/neutron.conf nova user_domain_name $DOMAIN_NAME
openstack-config --set /etc/neutron/neutron.conf nova region_name RegionOne
openstack-config --set /etc/neutron/neutron.conf nova project_name service
openstack-config --set /etc/neutron/neutron.conf nova username nova
openstack-config --set /etc/neutron/neutron.conf nova password $NOVA_PASS
openstack-config --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp

# 配置ML2插件
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,vlan,vxlan,gre,local
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vxlan
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers linuxbridge,l2population
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks $Physical_NAME
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan network_vlan_ranges $Physical_NAME:$minvlan:$maxvlan
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges $minvlan:$maxvlan
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset true

# 配置Linux Bridge代理
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings $Physical_NAME:$INTERFACE_NAME
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan true
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan local_ip $HOST_IP
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan l2_population true
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup enable_security_group true
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

# 配置网络过滤
modprobe br_netfilter
echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-ip6tables = 1' >> /etc/sysctl.conf
sysctl -p

# 配置L3代理
openstack-config --set /etc/neutron/l3_agent.ini DEFAULT interface_driver linuxbridge

# 配置DHCP代理
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver linuxbridge
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true

# 配置元数据代理
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_host $HOST_IP
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret $METADATA_SECRET

# 在Nova中配置Neutron
openstack-config --set /etc/nova/nova.conf neutron auth_url http://$HOST_IP:5000
openstack-config --set /etc/nova/nova.conf neutron auth_type password
openstack-config --set /etc/nova/nova.conf neutron project_domain_name $DOMAIN_NAME
openstack-config --set /etc/nova/nova.conf neutron user_domain_name $DOMAIN_NAME
openstack-config --set /etc/nova/nova.conf neutron region_name RegionOne
openstack-config --set /etc/nova/nova.conf neutron project_name service
openstack-config --set /etc/nova/nova.conf neutron username neutron
openstack-config --set /etc/nova/nova.conf neutron password $NEUTRON_PASS
openstack-config --set /etc/nova/nova.conf neutron service_metadata_proxy true
openstack-config --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret $METADATA_SECRET

# 初始化数据库
ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

# 重启相关服务
# 重启nova服务
systemctl restart openstack-nova-api.service openstack-nova-comput.service
# 重启netutron服务
systemctl restart neutron-server.service neutron-linuxbridge-agent.service neutron-dhcp-agent.service neutron-metadata-agent neutron-l3-agent
systemctl enable neutron-server.service neutron-linuxbridge-agent.service neutron-dhcp-agent.service neutron-metadata-agent neutron-l3-agent

echo -e "\033[1;32mNeutron安装完成! 网络代理状态:\033[0m"
openstack network agent list

# 安装Dashboard
echo -e "\n\033[1;33m>>> 14. 安装Dashboard控制台\033[0m"
yum_install_check "openstack-dashboard"

# 配置Dashboard
sed -i "s/^OPENSTACK_HOST = \".*\"/OPENSTACK_HOST = \"$HOST_IP\"/" /etc/openstack-dashboard/local_settings
sed -i "s/^ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['*', ]/" /etc/openstack-dashboard/local_settings
sed -i "s/^TIME_ZONE = \".*\"/TIME_ZONE = \"Asia\/Shanghai\"/" /etc/openstack-dashboard/local_settings
sed -i "s/^#SESSION_ENGINE = .*/SESSION_ENGINE = 'django.contrib.sessions.backends.cache'/" /etc/openstack-dashboard/local_settings

sed -i '/^OPENSTACK_HOST/s#127.0.0.1#'$HOST_IP'#' /etc/openstack-dashboard/local_settings
sed -i "/^ALLOWED_HOSTS/s#\[.*\]#['*']#" /etc/openstack-dashboard/local_settings
sed -i '/TIME_ZONE/s#UTC#Asia/Shanghai#' /etc/openstack-dashboard/local_settings
sed -i '/^#SESSION_ENGINE/s/#//' /etc/openstack-dashboard/local_settings
sed -i "/^SESSION_ENGINE/s#'.*'#'django.contrib.sessions.backends.cache'#" /etc/openstack-dashboard/local_settings

# 添加高级配置
cat >> /etc/openstack-dashboard/local_settings <<EOF
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 2,
}

OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "$DOMAIN_NAME"

CACHES = {
    'default': {
         'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
         'LOCATION': '$HOST_IP:11211',
    }
}

WEBROOT = '/dashboard/'
EOF

# 修正WSGI配置
sed  -e '4iWSGIApplicationGroup %{GLOBAL}' /etc/httpd/conf.d/openstack-dashboard.conf 


# 重建配置文件
cd /usr/share/openstack-dashboard && python manage.py make_web_conf --apache > /etc/httpd/conf.d/openstack-dashboard.conf
ln -s /etc/openstack-dashboard /usr/share/openstack-dashboard/openstack_dashboard/conf
cd /root/
sed -i "s:WSGIScriptAlias / :WSGIScriptAlias /dashboard :" /etc/httpd/conf.d/openstack-dashboard.conf
sed -i "s:Alias /static:Alias /dashboard/static:" /etc/httpd/conf.d/openstack-dashboard.conf

# 重启Web服务
systemctl restart httpd.service memcached.service

# 生成登录信息
echo -e "\n\033[1;32m==============================================\033[0m"
echo -e "\033[1;32m      OpenStack Train 安装完成!               \033[0m"
echo -e "\033[1;32m==============================================\033[0m"

# ----------------------------
# 安装完成后服务状态检测
# ----------------------------

echo -e "\n\033[1;36m[ 服务状态检测 ]\033[0m"

check_service() {
    local name=$1
    local service=$2
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✔ $name (${service}) 正常运行${NC}"
    else
        echo -e "${RED}✖ $name (${service}) 未运行${NC}"
    fi
}

check_openstack() {
    local name=$1
    if openstack $2 >/dev/null 2>&1; then
        echo -e "${GREEN}✔ $name 接口正常${NC}"
    else
        echo -e "${RED}✖ $name 接口异常${NC}"
    fi
}

# 系统服务检查
check_service "数据库(MariaDB)" mariadb
check_service "消息队列(RabbitMQ)" rabbitmq-server
check_service "缓存服务(Memcached)" memcached
check_service "Web服务器(Apache)" httpd

# OpenStack服务检查
check_service "镜像服务(Glance)" openstack-glance-api
check_service "计算服务(Nova API)" openstack-nova-api
check_service "调度器(Nova Scheduler)" openstack-nova-scheduler
check_service "网络服务(Neutron)" neutron-server
check_service "网络代理(Linux Bridge)" neutron-linuxbridge-agent
check_service "L3路由服务" neutron-l3-agent
check_service "DHCP服务" neutron-dhcp-agent
check_service "元数据服务" neutron-metadata-agent

# 简单OpenStack命令检测
echo -e "\n\033[1;36m[ OpenStack CLI 接口检测 ]\033[0m"
source /etc/xfcloud-openstack/admin-openrc
check_openstack "Token获取" "token issue"
check_openstack "镜像列表" "image list"
check_openstack "计算服务列表" "compute service list"
check_openstack "网络代理列表" "network agent list"

echo -e "\n${CYAN}✅ 所有服务检测完成，请检查有无失败项。${NC}"


cat > /root/logininfo.txt <<EOF
========== OpenStack 登录信息 ==========
控制台地址: http://$HOST_IP/dashboard
域      名: $DOMAIN_NAME
管理员账号: admin
管理员密码: $ADMIN_PASS
演示用户  : demo
密码      : $DEMO_PASS
数据库信息:
   Root密码: $DB_PASS
   Keystone: $KEYSTONE_DBPASS
   Glance  : $GLANCE_DBPASS
   Nova    : $NOVA_DBPASS
   Neutron : $NEUTRON_DBPASS
网络配置:
   物理网络: $Physical_NAME
   网卡接口: $INTERFACE_NAME
   VLAN范围: $minvlan-$maxvlan
=======================================
注意: 为了安全，请修改所有默认密码!
信息记录在/root/logininfo.txt
EOF

cat /root/logininfo.txt
echo -e "\n\033[1;33m安装日志和登录信息已保存到: /root/logininfo.txt\033[0m"
echo -e "\033[1;32m请确保主机防火墙开放所需端口!\033[0m"

# 写入环境变量
cat > /etc/xfcloud-openstack/openstack.sh <<-EOF
INTERFACE_NAME=$INTERFACE_NAME
HOST_IP=$HOST_IP
HOST_NAME=$HOST_NAME
DB_PASS=$DB_PASS
RABBIT_USER=$RABBIT_USER
RABBIT_PASS=$RABBIT_PASS
ADMIN_PASS=$ADMIN_PASS
DEMO_PASS=$DEMO_PASS
METADATA_SECRET=$METADATA_SECRET
KEYSTONE_DBPASS=$KEYSTONE_DBPASS
GLANCE_DBPASS=$GLANCE_DBPASS
GLANCE_PASS=$GLANCE_PASS
PLACEMENT_DBPASS=$PLACEMENT_DBPASS
PLACEMENT_PASS=$PLACEMENT_PASS
NOVA_DBPASS=$NOVA_DBPASS
NOVA_PASS=$NOVA_PASS
NEUTRON_DBPASS=$NEUTRON_DBPASS
NEUTRON_PASS=$NEUTRON_PASS
DOMAIN_NAME=$DOMAIN_NAME
Physical_NAME=$Physical_NAME
VERSION=$VERSION
YUM_REPO=$YUM_REPO
minvlan=$minvlan
maxvlan=$maxvlan
EOF
