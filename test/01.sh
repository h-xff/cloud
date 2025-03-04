#!/bin/bash
echo "start"

#Welcome page
cat > /etc/motd <<EOF 
 ################################
 #    Welcome  to  XFCLOUD    #
 ################################
EOF

#selinux
sed -i 's/SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

#firewalld
systemctl stop firewalld
systemctl disable firewalld  >> /dev/null 2>&1

#换源
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
yum makecache
yum -y upgrade
yum install expect -y

#iptables
yum install  iptables-services  -y 
if [ 0  -ne  $? ]; then
	echo -e "\033[31mThe installation source configuration errors\033[0m"
	exit 1
fi
systemctl restart iptables
iptables -F
iptables -X
iptables -Z 
/usr/sbin/iptables-save
systemctl stop iptables
systemctl disable iptables

#hosts
if [[ `ip a |grep -w 100.20 ` != '' ]];then 
    hostnamectl set-hostname controller
elif [[ `ip a |grep -w 192.168.100.30 ` != '' ]];then 
    hostnamectl set-hostname compute
else
    hostnamectl set-hostname controller
fi
sed -i -e "/controller/d" -e "/compute/d" /etc/hosts
echo "192.168.100.20 controller" >> /etc/hosts
echo "192.168.100.30 compute" >> /etc/hosts
#ssh
if [[ ! -s ~/.ssh/id_rsa.pub ]];then
    ssh-keygen  -t rsa -N '' -f ~/.ssh/id_rsa -q -b 2048
fi
name=`hostname`
if [[ $name ==controller ]];then
expect -c "set timeout -1;
               spawn ssh-copy-id  -i /root/.ssh/id_rsacompute;
               expect {
                   *password:* {send -- $HOST_PASS_NODE\r;
                        expect {
                            *denied* {exit 2;}
                            eof}
                    }
                   *(yes/no)* {send -- yes\r;exp_continue;}
                   eof         {exit 1;}
               }
               "
else
expect -c "set timeout -1;
               spawn ssh-copy-id  -i /root/.ssh/id_rsacontroller;
               expect {
                   *password:* {send -- $HOST_PASS\r;
                        expect {
                            *denied* {exit 2;}
                            eof}
                    }
                   *(yes/no)* {send -- yes\r;exp_continue;}
                   eof         {exit 1;}
               }
               "
fi

#chrony
name=`hostname`
yum install -y chrony
if [[ $name == controller ]];then
        sed -i '3,6s/^/#/g' /etc/chrony.conf
        sed -i '7s/^/server controller iburst/g' /etc/chrony.conf
        echo "allow 192.168.100.0/24" >> /etc/chrony.conf
        echo "local stratum 10" >> /etc/chrony.conf
else
        sed -i '3,6s/^/#/g' /etc/chrony.conf
        sed -i '7s/^/server controller iburst/g' /etc/chrony.conf
fi
systemctl restart chronyd
systemctl enable chronyd
