# openstack一键部署allinone
推荐系统CentOS7.9最小安装纯净版,单网卡！
默认安装Train版本
指定安装可以自己修改脚本中的版本VERSION="train"
运行环境是需要脚本文件有可执行权限
```shell
chmod +x ./allinone.sh
./allinone.sh
```
脚本运行后会提示登录密码和控制台地址
```sh
========== OpenStack 登录信息 ==========
控制台地址: http://xx.xx.xx.xx/dashboard
域      名: Default
管理员账号: admin
管理员密码: 1YZXlKpY82ZYk3Yf
演示用户  : demo
密码      : Lyj8awvPa530r3VP
数据库信息:
   Root密码: dkZDCnbbiURH04Wb
   Keystone: qfi6w57WZvmOzWC6
   Glance  : q85x4RJfcqPAZ2Ng
   Nova    : DNLYrm7pIVxNNCRJ
   Neutron : 4cp7bP7O12oPNdmP
网络配置:
   物理网络: provider
   网卡接口: eth0
   VLAN范围: 100-200
=======================================
注意: 为了安全，请修改所有默认密码!
信息记录在/root/logininfo.txt
```

# 环境变量，可以自己修改或者运行默认的安装程序
```shell
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
```
