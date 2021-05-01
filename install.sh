#!/usr/bin/env bash
# 检测区
# -------------------------------------------------------------
# 检查系统
checkSystem() {
	if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
		centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')

		if [[ -z "${centosVersion}" ]] && grep </etc/centos-release "release 8"; then
			centosVersion=8
		fi
		release="centos"
		installType='yum -y install'
		# removeType='yum -y remove'
		upgrade="yum update -y --skip-broken"

	elif grep </etc/issue -q -i "debian" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "debian" && [[ -f "/proc/version" ]]; then
		if grep </etc/issue -i "8"; then
			debianVersion=8
		fi
		release="debian"
		installType='apt -y install'
		upgrade="apt update -y"
		# removeType='apt -y autoremove'

	elif grep </etc/issue -q -i "ubuntu" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "ubuntu" && [[ -f "/proc/version" ]]; then
		release="ubuntu"
		installType='apt-get -y install'
		upgrade="apt-get update -y"
		# removeType='apt-get --purge remove'
	fi

	if [[ -z ${release} ]]; then
		echo "本脚本不支持此系统，请将下方日志反馈给开发者"
		cat /etc/issue
		cat /proc/version
		exit 0
	fi
}

# 初始化全局变量
initVar() {
	installType='yum -y install'
	removeType='yum -y remove'
	upgrade="yum -y update"
	echoType='echo -e'

	# 域名
	domain=

	# CDN节点的address
	add=

	# 安装总进度
	totalProgress=1

	# 1.xray-core安装
	# 2.v2ray-core 安装
	# 3.v2ray-core[xtls] 安装
	coreInstallType=

	# 核心安装path
	# coreInstallPath=

	# v2ctl Path
	ctlPath=
	# 1.全部安装
	# 2.个性化安装
	# v2rayAgentInstallType=

	# 当前的个性化安装方式 01234
	currentInstallProtocolType=

	# 选择的个性化安装方式
	selectCustomInstallType=

	# v2ray-core、xray-core配置文件的路径
	configPath=

	# 配置文件的path
	currentPath=

	# 配置文件的host
	currentHost=

	# 安装时选择的core类型
	selectCoreType=

	# 默认core版本
	v2rayCoreVersion=

	# 随机路径
	customPath=

	# centos version
	centosVersion=

	# UUID
	currentUUID=

	# pingIPv6 pingIPv4
	# pingIPv4=
	pingIPv6=

	# 集成更新证书逻辑不再使用单独的脚本--RenewTLS
	renewTLS=$1
}

# 检测安装方式
readInstallType() {
	coreInstallType=
	configPath=

	# 1.检测安装目录
	if [[ -d "/etc/v2ray-agent" ]]; then
		# 检测安装方式 v2ray-core
		if [[ -d "/etc/v2ray-agent/v2ray" && -f "/etc/v2ray-agent/v2ray/v2ray" && -f "/etc/v2ray-agent/v2ray/v2ctl" ]]; then
			if [[ -d "/etc/v2ray-agent/v2ray/conf" && -f "/etc/v2ray-agent/v2ray/conf/02_VLESS_TCP_inbounds.json" ]]; then
				configPath=/etc/v2ray-agent/v2ray/conf/

				if ! grep </etc/v2ray-agent/v2ray/conf/02_VLESS_TCP_inbounds.json -q xtls; then
					# 不带XTLS的v2ray-core
					coreInstallType=2
					# coreInstallPath=/etc/v2ray-agent/v2ray/v2ray
					ctlPath=/etc/v2ray-agent/v2ray/v2ctl
				elif grep </etc/v2ray-agent/v2ray/conf/02_VLESS_TCP_inbounds.json -q xtls; then
					# 带XTLS的v2ray-core
					# coreInstallPath=/etc/v2ray-agent/v2ray/v2ray
					ctlPath=/etc/v2ray-agent/v2ray/v2ctl
					coreInstallType=3
				fi
			fi
		fi

		if [[ -d "/etc/v2ray-agent/xray" && -f "/etc/v2ray-agent/xray/xray" ]]; then
			# 这里检测xray-core
			if [[ -d "/etc/v2ray-agent/xray/conf" && -f "/etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json" ]]; then
				# xray-core
				configPath=/etc/v2ray-agent/xray/conf/
				# coreInstallPath=/etc/v2ray-agent/xray/xray
				ctlPath=/etc/v2ray-agent/xray/xray
				coreInstallType=1
			fi
		fi
	fi
}

# 读取协议类型
readInstallProtocolType() {
	currentInstallProtocolType=

	while read -r row; do
		if echo ${row} | grep -q VLESS_TCP_inbounds; then
			currentInstallProtocolType=${currentInstallProtocolType}'0'
		fi
		if echo ${row} | grep -q VLESS_WS_inbounds; then
			currentInstallProtocolType=${currentInstallProtocolType}'1'
		fi
		if echo ${row} | grep -q VMess_TCP_inbounds; then
			currentInstallProtocolType=${currentInstallProtocolType}'2'
		fi
		if echo ${row} | grep -q VMess_WS_inbounds; then
			currentInstallProtocolType=${currentInstallProtocolType}'3'
		fi
		if echo ${row} | grep -q VLESS_gRPC_inbounds; then
			currentInstallProtocolType=${currentInstallProtocolType}'5'
		fi

	done < <(ls ${configPath} | grep inbounds.json | awk -F "[.]" '{print $1}')

	if [[ -f "/etc/v2ray-agent/trojan/trojan-go" ]] && [[ -f "/etc/v2ray-agent/trojan/config_full.json" ]]; then
		currentInstallProtocolType=${currentInstallProtocolType}'4'
	fi
}

# 检查文件目录以及path路径
readConfigHostPathUUID() {
	currentPath=
	currentUUID=
	currentHost=
	currentPort=
	currentAdd=
	# 读取path
	if [[ -n "${configPath}" ]]; then
		local path
		path=$(jq .inbounds[0].settings.fallbacks[].path ${configPath}02_VLESS_TCP_inbounds.json | awk -F "[\"][/]" '{print $2}' | awk -F "[\"]" '{print $1}' | tail -n +2 | head -n 1)
		# local path=$(cat ${configPath}02_VLESS_TCP_inbounds.json | jq .inbounds[0].settings.fallbacks | jq -c '.[].path' | awk -F "[\"][/]" '{print $2}' | awk -F "[\"]" '{print $1}' | tail -n +2 | head -n 1)
		# jq .inbounds[0].settings.fallbacks.[].path ${configPath}02_VLESS_TCP_inbounds.json| awk -F "[\"][/]" '{print $2}' | awk -F "[\"]" '{print $1}' | tail -n +2 | head -n 1

		if [[ -n "${path}" ]]; then
			if [[ "${path:0-3}" == "vws" && ${#path} -gt 6 ]]; then
				currentPath=$(echo "${path}" | awk -F "[v][w][s]" '{print $1}')
			elif [[ "${path:0-2}" == "ws" ]]; then
				currentPath=$(echo "${path}" | awk -F "[w][s]" '{print $1}')
			elif [[ "${path:0-2}" == "tcp" ]]; then
				currentPath=$(echo "${path}" | awk -F "[t][c][p]" '{print $1}')
			fi
		fi
	fi
	if [[ "${coreInstallType}" == "1" ]]; then
		currentHost=$(jq .inbounds[0].streamSettings.xtlsSettings.certificates[0].certificateFile ${configPath}02_VLESS_TCP_inbounds.json | awk -F '[t][l][s][/]' '{print $2}' | awk -F '["]' '{print $1}' | awk -F '[.][c][r][t]' '{print $1}')
		currentUUID=$(jq .inbounds[0].settings.clients[0].id ${configPath}02_VLESS_TCP_inbounds.json | awk -F '["]' '{print $2}')
		currentAdd=$(jq .inbounds[0].settings.clients[0].add ${configPath}02_VLESS_TCP_inbounds.json | awk -F '["]' '{print $2}')
		currentPort=$(jq .inbounds[0].port ${configPath}02_VLESS_TCP_inbounds.json)

	elif [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]]; then
		if [[ "${coreInstallType}" == "3" ]]; then
			currentHost=$(jq .inbounds[0].streamSettings.xtlsSettings.certificates[0].certificateFile ${configPath}02_VLESS_TCP_inbounds.json | awk -F '[t][l][s][/]' '{print $2}' | awk -F '["]' '{print $1}' | awk -F '[.][c][r][t]' '{print $1}')
		else
			currentHost=$(jq .inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile ${configPath}02_VLESS_TCP_inbounds.json | awk -F '[t][l][s][/]' '{print $2}' | awk -F '["]' '{print $1}' | awk -F '[.][c][r][t]' '{print $1}')
		fi
		currentAdd=$(jq .inbounds[0].settings.clients[0].add ${configPath}02_VLESS_TCP_inbounds.json | awk -F '["]' '{print $2}')
		currentUUID=$(jq .inbounds[0].settings.clients[0].id ${configPath}02_VLESS_TCP_inbounds.json | awk -F '["]' '{print $2}')
		currentPort=$(jq .inbounds[0].port ${configPath}02_VLESS_TCP_inbounds.json)
	fi
}

# 状态展示
showInstallStatus() {
	if [[ -n "${coreInstallType}" ]]; then
		if [[ "${coreInstallType}" == 1 ]]; then
			if [[ -n $(pgrep -f xray/xray) ]]; then
				echoContent yellow "\n核心：Xray-core[运行中]"
			else
				echoContent yellow "\n核心：Xray-core[未运行]"
			fi

		elif [[ "${coreInstallType}" == 2 || "${coreInstallType}" == 3 ]]; then
			if [[ -n $(pgrep -f v2ray/v2ray) ]]; then
				echoContent yellow "\n核心：v2ray-core[运行中]"
			else
				echoContent yellow "\n核心：v2ray-core[未运行]"
			fi
		fi
		# 读取协议类型
		readInstallProtocolType

		if [[ -n ${currentInstallProtocolType} ]]; then
			echoContent yellow "已安装协议：\c"
		fi
		if echo ${currentInstallProtocolType} | grep -q 0; then
			if [[ "${coreInstallType}" == 2 ]]; then
				echoContent yellow "VLESS+TCP[TLS] \c"
			else
				echoContent yellow "VLESS+TCP[TLS/XTLS] \c"
			fi
		fi

		if echo ${currentInstallProtocolType} | grep -q 1; then
			echoContent yellow "VLESS+WS[TLS] \c"
		fi

		if echo ${currentInstallProtocolType} | grep -q 2; then
			echoContent yellow "VMess+TCP[TLS] \c"
		fi

		if echo ${currentInstallProtocolType} | grep -q 3; then
			echoContent yellow "VMess+WS[TLS] \c"
		fi

		if echo ${currentInstallProtocolType} | grep -q 4; then
			echoContent yellow "Trojan+TCP/WS[TLS]\c"
		fi

		if echo ${currentInstallProtocolType} | grep -q 5; then
			echoContent yellow "VLESS+gRPC[TLS] \c"
		fi
	fi
}

# 清理旧残留
cleanUp() {
	if [[ "$1" == "v2rayClean" ]]; then
		rm -rf "$(find /etc/v2ray-agent/v2ray/* | grep -E '(config_full.json|conf)')"
		handleV2Ray stop >/dev/null 2>&1
		rm -f /etc/systemd/system/v2ray.service
	elif [[ "$1" == "xrayClean" ]]; then
		rm -rf "$(find /etc/v2ray-agent/xray/* | grep -E '(config_full.json|conf)')"
		handleXray stop >/dev/null 2>&1
		rm -f /etc/systemd/system/xray.service

	elif [[ "$1" == "v2rayDel" ]]; then
		rm -rf /etc/v2ray-agent/v2ray/*

	elif [[ "$1" == "xrayDel" ]]; then
		rm -rf /etc/v2ray-agent/xray/*
	fi
}

initVar $1
checkSystem
readInstallType
readInstallProtocolType
readConfigHostPathUUID

# -------------------------------------------------------------

echoContent() {
	case $1 in
	# 红色
	"red")
		# shellcheck disable=SC2154
		${echoType} "\033[31m${printN}$2 \033[0m"
		;;
		# 天蓝色
	"skyBlue")
		${echoType} "\033[1;36m${printN}$2 \033[0m"
		;;
		# 绿色
	"green")
		${echoType} "\033[32m${printN}$2 \033[0m"
		;;
		# 白色
	"white")
		${echoType} "\033[37m${printN}$2 \033[0m"
		;;
	"magenta")
		${echoType} "\033[31m${printN}$2 \033[0m"
		;;
		# 黄色
	"yellow")
		${echoType} "\033[33m${printN}$2 \033[0m"
		;;
	esac
}

# 初始化安装目录
mkdirTools() {
	mkdir -p /etc/v2ray-agent/tls
	mkdir -p /etc/v2ray-agent/mtg
	mkdir -p /etc/v2ray-agent/subscribe
	mkdir -p /etc/v2ray-agent/subscribe_tmp
	mkdir -p /etc/v2ray-agent/v2ray/conf
	mkdir -p /etc/v2ray-agent/xray/conf
	mkdir -p /etc/v2ray-agent/trojan
	mkdir -p /etc/systemd/system/
	mkdir -p /tmp/v2ray-agent-tls/
}

# 安装工具包
installTools() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 安装工具"
	if [[ "${release}" == "centos" ]]; then
		echoContent green " ---> 检查安装jq、nginx epel源、yum-utils、semanage"
		# jq epel源
		if [[ -z $(command -v jq) ]]; then
			rpm -ivh http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm >/dev/null 2>&1
		fi

		nginxEpel=""
		if rpm -qa | grep -q nginx; then
			local nginxVersion
			nginxVersion=$(rpm -qa | grep -v grep | grep nginx | head -1 | awk -F '[-]' '{print $2}')
			if [[ $(echo "${nginxVersion}" | awk -F '[.]' '{print $1}') -le 1 ]] && [[ $(echo "${nginxVersion}" | awk -F '[.]' '{print $2}') -le 17 ]]; then
				rpm -qa | grep -v grep | grep nginx | xargs rpm -e >/dev/null 2>&1
			fi
		fi

		if [[ "${centosVersion}" == "6" ]]; then
			nginxEpel="http://nginx.org/packages/centos/6/x86_64/RPMS/nginx-1.18.0-1.el6.ngx.x86_64.rpm"
			rpm -ivh ${nginxEpel} >/etc/v2ray-agent/error.log 2>&1
		elif [[ "${centosVersion}" == "7" ]]; then
			nginxEpel="http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm"
			policyCoreUtils="policycoreutils-python.x86_64"
			rpm -ivh ${nginxEpel} >/etc/v2ray-agent/error.log 2>&1
		elif [[ "${centosVersion}" == "8" ]]; then
			nginxEpel="http://nginx.org/packages/centos/8/x86_64/RPMS/nginx-1.18.0-1.el8.ngx.x86_64.rpm"
			policyCoreUtils="policycoreutils-python-utils-2.9-9.el8.noarch"
		fi

		# yum-utils
		if [[ "${centosVersion}" == "8" ]]; then
			upgrade="yum update -y --skip-broken --nobest"
			installType="yum -y install --nobest"
			${installType} yum-utils >/etc/v2ray-agent/error.log 2>&1
		else
			${installType} yum-utils >/etc/v2ray-agent/error.log 2>&1
		fi

	fi
	# 修复ubuntu个别系统问题
	if [[ "${release}" == "ubuntu" ]]; then
		dpkg --configure -a
	fi

	if [[ -n $(pgrep -f "apt") ]]; then
		pgrep -f apt | xargs kill -9
	fi

	echoContent green " ---> 检查、安装更新【新机器会很慢，耐心等待】"

	${upgrade} >/dev/null
	if [[ "${release}" == "centos" ]]; then
		rm -rf /var/run/yum.pid
	fi
	#	[[ -z `find /usr/bin /usr/sbin |grep -v grep|grep -w curl` ]]

	if ! find /usr/bin /usr/sbin | grep -q -w wget; then
		echoContent green " ---> 安装wget"
		${installType} wget >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w curl; then
		echoContent green " ---> 安装curl"
		${installType} curl >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w unzip; then
		echoContent green " ---> 安装unzip"
		${installType} unzip >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w socat; then
		echoContent green " ---> 安装socat"
		${installType} socat >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w tar; then
		echoContent green " ---> 安装tar"
		${installType} tar >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w cron; then
		echoContent green " ---> 安装crontabs"
		if [[ "${release}" == "ubuntu" ]] || [[ "${release}" == "debian" ]]; then
			${installType} cron >/dev/null 2>&1
		else
			${installType} crontabs >/dev/null 2>&1
		fi
	fi
	if ! find /usr/bin /usr/sbin | grep -q -w jq; then
		echoContent green " ---> 安装jq"
		${installType} jq >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w binutils; then
		echoContent green " ---> 安装binutils"
		${installType} binutils >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w ping6; then
		echoContent green " ---> 安装ping6"
		${installType} inetutils-ping >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w qrencode; then
		echoContent green " ---> 安装qrencode"
		${installType} qrencode >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w nginx; then
		echoContent green " ---> 安装nginx"
		if [[ "${centosVersion}" == "8" ]]; then
			rpm -ivh ${nginxEpel} >/etc/v2ray-agent/error.log 2>&1
		else
			${installType} nginx >/dev/null 2>&1
		fi

		if [[ -n "${centosVersion}" ]]; then
			systemctl daemon-reload
			systemctl enable nginx
		fi
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w semanage; then
		echoContent green " ---> 安装semanage"
		${installType} bash-completion >/dev/null 2>&1
		if [[ -n "${policyCoreUtils}" ]]; then
			${installType} ${policyCoreUtils} >/dev/null 2>&1
		fi
		if [[ -n $(which semanage) ]]; then
			semanage port -a -t http_port_t -p tcp 31300

		fi
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w sudo; then
		echoContent green " ---> 安装sudo"
		${installType} sudo >/dev/null 2>&1
	fi
	# todo 关闭防火墙

	if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
		echoContent green " ---> 安装acme.sh"
		curl -s https://get.acme.sh | sh >/etc/v2ray-agent/tls/acme.log
		if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
			echoContent red "  acme安装失败--->"
			echoContent yellow "错误排查："
			echoContent red "  1.获取Github文件失败，请等待Gitub恢复后尝试，恢复进度可查看 [https://www.githubstatus.com/]"
			echoContent red "  2.acme.sh脚本出现bug，可查看[https://github.com/acmesh-official/acme.sh] issues"
			exit 0
		fi
	fi
}

# 初始化Nginx申请证书配置
initTLSNginxConfig() {
	handleNginx stop
	echoContent skyBlue "\n进度  $1/${totalProgress} : 初始化Nginx申请证书配置"
	if [[ -n "${currentHost}" ]]; then
		echo
		read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDomainStatus
		if [[ "${historyDomainStatus}" == "y" ]]; then
			domain=${currentHost}
			echoContent yellow "\n ---> 域名：${domain}"
		else
			echo
			echoContent yellow "请输入要配置的域名 例：www.v2ray-agent.com --->"
			read -r -p "域名:" domain
		fi
	else
		echo
		echoContent yellow "请输入要配置的域名 例：www.v2ray-agent.com --->"
		read -r -p "域名:" domain
	fi

	if [[ -z ${domain} ]]; then
		echoContent red "  域名不可为空--->"
		initTLSNginxConfig
	else
		# 修改配置
		echoContent green "\n ---> 配置Nginx"
		touch /etc/nginx/conf.d/alone.conf
		echo "server {listen 80;listen [::]:80;server_name ${domain};root /usr/share/nginx/html;location ~ /.well-known {allow all;}location /test {return 200 'fjkvymb6len';}}" >/etc/nginx/conf.d/alone.conf
		# 启动nginx
		handleNginx start
		echoContent yellow "\n检查IP是否设置为当前VPS"
		checkIP
		# 测试nginx
		echoContent yellow "\n检查Nginx是否正常访问"
		sleep 0.5
		domainResult=$(curl -s "${domain}/test" | grep fjkvymb6len)
		if [[ -n ${domainResult} ]]; then
			handleNginx stop
			echoContent green "\n ---> Nginx配置成功"
		else
			echoContent red " ---> 无法正常访问服务器，请检测域名是否正确、域名的DNS解析以及防火墙设置是否正确--->"
			exit 0
		fi
	fi
}

# 修改nginx重定向配置
updateRedirectNginxConf() {

	cat <<EOF >/etc/nginx/conf.d/alone.conf
    server {
        listen 80;
        listen [::]:80;
        server_name ${domain};
        # shellcheck disable=SC2154
        return 301 https://${domain}$request_uri;
    }
EOF

	if [[ "${debianVersion}" == "8" ]]; then
		cat <<EOF >>/etc/nginx/conf.d/alone.conf
        server {
        listen 31300;
        server_name ${domain};
        root /usr/share/nginx/html;
        location /s/ {
        	add_header Content-Type text/plain;
        	alias /etc/v2ray-agent/subscribe/;
        }
        # location / {
        #   add_header Strict-Transport-Security "max-age=63072000" always;
        # }
#       location ~ /.well-known {allow all;}
#       location /test {return 200 'fjkvymb6len';}
    }
EOF
	else
		cat <<EOF >>/etc/nginx/conf.d/alone.conf
        server {
            listen 31300;
            server_name ${domain};
            root /usr/share/nginx/html;
            location /s/ {
            	add_header Content-Type text/plain;
        		alias /etc/v2ray-agent/subscribe/;
        	}
            location / {
                add_header Strict-Transport-Security "max-age=63072000" always;
            }
    #       location ~ /.well-known {allow all;}
    #       location /test {return 200 'fjkvymb6len';}
        }
EOF
	fi

}

# 检查ip
checkIP() {
	echoContent skyBlue " ---> 检查ipv4中"
	local pingIP=$(curl -s -H 'accept:application/dns-json' 'https://cloudflare-dns.com/dns-query?name='${domain}'&type=A' | jq -r ".Answer|.[]|select(.type==1)|.data")

	if [[ -z "${pingIP}" ]]; then
		echoContent skyBlue " ---> 检查ipv6中"
		pingIP=$(curl -s -H 'accept:application/dns-json' 'https://cloudflare-dns.com/dns-query?name='${domain}'&type=AAAA' | jq -r ".Answer|.[]|select(.type==28)|.data")
		pingIPv6=${pingIP}
	fi

	if [[ -n "${pingIP}" ]]; then
		echo
		read -r -p "当前域名的IP为 [${pingIP}]，是否正确[y/n]？" domainStatus
		if [[ "${domainStatus}" == "y" ]]; then
			echoContent green "\n ---> IP确认完成"
		else
			echoContent red "\n ---> 1.检查Cloudflare DNS解析是否正常"
			echoContent red " ---> 2.检查Cloudflare DNS云朵是否为灰色\n"
			exit 0
		fi
	else
		read -r -p "IP查询失败，是否重试[y/n]？" retryStatus
		if [[ "${retryStatus}" == "y" ]]; then
			checkIP
		else
			exit 0
		fi
	fi
}
# 安装TLS
installTLS() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 申请TLS证书\n"
	local tlsDomain=${domain}
	# 安装tls
	if [[ -f "/etc/v2ray-agent/tls/${tlsDomain}.crt" && -f "/etc/v2ray-agent/tls/${tlsDomain}.key" ]] || [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]]; then
		# 存在证书
		echoContent green " ---> 检测到证书"
		checkTLStatus "${tlsDomain}"
		if [[ "${tlsStatus}" == "已过期" ]]; then
			rm -rf $HOME/.acme.sh/${tlsDomain}_ecc/*
			rm -rf /etc/v2ray-agent/tls/${tlsDomain}*
			installTLS "$1"
		else
			echoContent green " ---> 证书有效"

			if ! ls /etc/v2ray-agent/tls/ | grep -q "${tlsDomain}.crt" || ! ls /etc/v2ray-agent/tls/ | grep -q "${tlsDomain}.key"; then
				sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/v2ray-agent/tls/${tlsDomain}.crt" --keypath "/etc/v2ray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
			else
				echoContent yellow " ---> 如未过期请选择[n]\n"
				read -r -p "是否重新安装？[y/n]:" reInstallStatus
				if [[ "${reInstallStatus}" == "y" ]]; then
					rm -rf /etc/v2ray-agent/tls/*
					installTLS "$1"
				fi
			fi
		fi
	elif [[ -d "$HOME/.acme.sh" ]] && [[ ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" || ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" ]]; then
		echoContent green " ---> 安装TLS证书"
		if [[ -n "${pingIPv6}" ]]; then
			sudo "$HOME/.acme.sh/acme.sh" --issue -d "${tlsDomain}" --standalone -k ec-256 --listen-v6 >/dev/null
		else
			sudo "$HOME/.acme.sh/acme.sh" --issue -d "${tlsDomain}" --standalone -k ec-256 >/dev/null
		fi

		sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/v2ray-agent/tls/${tlsDomain}.crt" --keypath "/etc/v2ray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
		if [[ -z $(cat "/etc/v2ray-agent/tls/${tlsDomain}.crt") ]]; then
			echoContent red " ---> TLS安装失败，请检查acme日志"
			exit 0
		elif [[ -z $(cat "/etc/v2ray-agent/tls/${tlsDomain}.key") ]]; then
			echoContent red " ---> TLS安装失败，请检查acme日志"
			exit 0
		fi
		echoContent green " ---> TLS生成成功"
	else
		echoContent yellow " ---> 未安装acme.sh"
		exit 0
	fi
}
# 配置伪装博客
initNginxConfig() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Nginx"

	cat <<EOF >/etc/nginx/conf.d/alone.conf
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    root /usr/share/nginx/html;
    location ~ /.well-known {allow all;}
    location /test {return 200 'fjkvymb6len';}
}
EOF
}

# 自定义/随机路径
randomPathFunction() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 生成随机路径"

	if [[ -n "${currentPath}" ]]; then
		echo
		read -r -p "读取到上次安装记录，是否使用上次安装时的path路径 ？[y/n]:" historyPathStatus
		echo
	fi

	if [[ "${historyPathStatus}" == "y" ]]; then
		customPath=${currentPath}
		echoContent green " ---> 使用成功\n"
	else
		echoContent yellow "请输入自定义路径[例: alone]，不需要斜杠，[回车]随机路径"
		read -r -p '路径:' customPath

		if [[ -z "${customPath}" ]]; then
			customPath=$(head -n 50 /dev/urandom | sed 's/[^a-z]//g' | strings -n 4 | tr 'A-Z' 'a-z' | head -1)
			currentPath=${customPath:0:4}
		fi
	fi
	echoContent yellow "path：${customPath}"
	echoContent skyBlue "\n----------------------------"
}
# Nginx伪装博客
nginxBlog() {
	echoContent skyBlue "\n进度 $1/${totalProgress} : 添加伪装站点"
	if [[ -d "/usr/share/nginx/html" && -f "/usr/share/nginx/html/check" ]]; then
		echo
		read -r -p "检测到安装伪装站点，是否需要重新安装[y/n]：" nginxBlogInstallStatus
		if [[ "${nginxBlogInstallStatus}" == "y" ]]; then
			rm -rf /usr/share/nginx/html
			wget -q -P /usr/share/nginx https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html1.zip >/dev/null
			unzip -o /usr/share/nginx/html1.zip -d /usr/share/nginx/html >/dev/null
			rm -f /usr/share/nginx/html.zip*
			echoContent green " ---> 添加伪装站点成功"
		fi
	else
		rm -rf /usr/share/nginx/html
		wget -q -P /usr/share/nginx https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html1.zip >/dev/null
		unzip -o /usr/share/nginx/html1.zip -d /usr/share/nginx/html >/dev/null
		rm -f /usr/share/nginx/html1.zip*
		echoContent green " ---> 添加伪装站点成功"
	fi

}
# 操作Nginx
handleNginx() {

	if [[ -z $(pgrep -f "nginx") ]] && [[ "$1" == "start" ]]; then
		nginx
		sleep 0.5
		if ! ps -ef | grep -v grep | grep -q nginx; then
			echoContent red " ---> Nginx启动失败"
			echoContent red " ---> 请手动尝试安装nginx后，再次执行脚本"
			exit 0
		fi
	elif [[ "$1" == "stop" ]] && [[ -n $(pgrep -f "nginx") ]]; then
		nginx -s stop >/dev/null 2>&1
		sleep 0.5
		if [[ -n $(pgrep -f "nginx") ]]; then
			pgrep -f "nginx" | xargs kill -9
		fi
	fi
}

# 定时任务更新tls证书
installCronTLS() {
	echoContent skyBlue "\n进度 $1/${totalProgress} : 添加定时维护证书"
	crontab -l >/etc/v2ray-agent/backup_crontab.cron
	sed '/v2ray-agent/d;/acme.sh/d' /etc/v2ray-agent/backup_crontab.cron >/etc/v2ray-agent/backup_crontab.cron
	echo "30 1 * * * /bin/bash /etc/v2ray-agent/install.sh RenewTLS" >>/etc/v2ray-agent/backup_crontab.cron
	crontab /etc/v2ray-agent/backup_crontab.cron
	echoContent green "\n ---> 添加定时维护证书成功"
}

# 更新证书
renewalTLS() {
	echoContent skyBlue "\n进度  1/1 : 更新证书"

	if [[ -d "$HOME/.acme.sh/${currentHost}_ecc" ]] && [[ -f "$HOME/.acme.sh/${currentHost}_ecc/${currentHost}.key" ]] && [[ -f "$HOME/.acme.sh/${currentHost}_ecc/${currentHost}.cer" ]]; then
		modifyTime=$(stat $HOME/.acme.sh/${currentHost}_ecc/${currentHost}.cer | sed -n '7,6p' | awk '{print $2" "$3" "$4" "$5}')

		modifyTime=$(date +%s -d "${modifyTime}")
		currentTime=$(date +%s)
		stampDiff=$(expr ${currentTime} - ${modifyTime})
		days=$(expr ${stampDiff} / 86400)
		remainingDays=$(expr 90 - ${days})
		tlsStatus=${remainingDays}
		if [[ ${remainingDays} -le 0 ]]; then
			tlsStatus="已过期"
		fi
		echoContent skyBlue " ---> 证书生成日期:$(date -d @"${modifyTime}" +"%F %H:%M:%S")"
		echoContent skyBlue " ---> 证书生成天数:${days}"
		echoContent skyBlue " ---> 证书剩余天数:"${tlsStatus}

		if [[ ${remainingDays} -le 1 ]]; then
			echoContent yellow " ---> 重新生成证书"
			handleNginx stop
			sudo "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh"
			sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${currentHost}" --fullchainpath /etc/v2ray-agent/tls/"${currentHost}.crt" --keypath /etc/v2ray-agent/tls/"${currentHost}.key" --ecc | sudo tee -a /etc/v2ray-agent/tls/acme.log
			handleNginx start

			reloadCore

		else
			echoContent green " ---> 证书有效"
		fi
	else
		echoContent red " ---> 未安装"
	fi
}
# 查看TLS证书的状态
checkTLStatus() {

	if [[ -n "$1" ]]; then
		if [[ -d "$HOME/.acme.sh/$1_ecc" ]] && [[ -f "$HOME/.acme.sh/$1_ecc/$1.key" ]] && [[ -f "$HOME/.acme.sh/$1_ecc/$1.cer" ]]; then
			modifyTime=$(stat $HOME/.acme.sh/$1_ecc/$1.key | sed -n '7,6p' | awk '{print $2" "$3" "$4" "$5}')

			modifyTime=$(date +%s -d "${modifyTime}")
			currentTime=$(date +%s)
			stampDiff=$(expr ${currentTime} - ${modifyTime})
			days=$(expr ${stampDiff} / 86400)
			remainingDays=$(expr 90 - ${days})
			tlsStatus=${remainingDays}
			if [[ ${remainingDays} -le 0 ]]; then
				tlsStatus="已过期"
			fi
			echoContent skyBlue " ---> 证书生成日期:$(date -d "@${modifyTime}" +"%F %H:%M:%S")"
			echoContent skyBlue " ---> 证书生成天数:${days}"
			echoContent skyBlue " ---> 证书剩余天数:${tlsStatus}"
		fi
	fi
}

# 安装xray
installXray() {
	readInstallType
	echoContent skyBlue "\n进度  $1/${totalProgress} : 安装Xray"

	if [[ "${coreInstallType}" != "1" ]]; then
		version=$(curl -s https://github.com/XTLS/Xray-core/releases | grep /XTLS/Xray-core/releases/tag/ | grep "Xray-core v" | head -1 | awk '{print $3}' | awk -F "[<]" '{print $1}')

		echoContent green " ---> Xray-core版本:${version}"
		if wget --help | grep -q show-progress; then
			wget -c -q --show-progress -P /etc/v2ray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/Xray-linux-64.zip"
		else
			wget -c -P /etc/v2ray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/Xray-linux-64.zip" >/dev/null 2>&1
		fi

		unzip -o /etc/v2ray-agent/xray/Xray-linux-64.zip -d /etc/v2ray-agent/xray >/dev/null
		rm -rf /etc/v2ray-agent/xray/Xray-linux-64.zip
		chmod 655 /etc/v2ray-agent/xray/xray
	else
		echoContent green " ---> Xray-core版本:$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)"
		read -r -p "是否更新、升级？[y/n]:" reInstallXrayStatus
		if [[ "${reInstallXrayStatus}" == "y" ]]; then
			rm -f /etc/v2ray-agent/xray/xray
			installXray "$1"
		fi
	fi
}

# xray版本管理
xrayVersionManageMenu() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : Xray版本管理"
	if [[ ! -d "/etc/v2ray-agent/xray/" ]]; then
		echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
		menu
		exit 0
	fi
	echoContent red "\n=============================================================="
	echoContent yellow "1.升级"
	echoContent yellow "2.回退"
	echoContent yellow "3.关闭Xray-core"
	echoContent yellow "4.打开Xray-core"
	echoContent yellow "5.重启Xray-core"
	echoContent red "=============================================================="
	read -r -p "请选择：" selectXrayType
	if [[ "${selectXrayType}" == "1" ]]; then
		updateXray
	elif [[ "${selectXrayType}" == "2" ]]; then
		echoContent yellow "\n1.由于Xray-core频繁更新，只可以回退最近的两个版本"
		echoContent yellow "2.不保证回退后一定可以正常使用"
		echoContent yellow "3.如果回退的版本不支持当前的config，则会无法连接，谨慎操作"
		echoContent skyBlue "------------------------Version-------------------------------"
		curl -s https://github.com/XTLS/Xray-core/releases | grep /XTLS/Xray-core/releases/tag/ | grep "Xray-core v" | head -5 | awk -F "[X][r][a][y][-][c][o][r][e][ ]" '{print $2}' | awk -F "[<]" '{print $1}' | tail -n 5 | awk '{print ""NR""":"$0}'
		echoContent skyBlue "--------------------------------------------------------------"
		read -r -p "请输入要回退的版本：" selectXrayVersionType
		version=$(curl -s https://github.com/XTLS/Xray-core/releases | grep /XTLS/Xray-core/releases/tag/ | grep "Xray-core v" | head -5 | awk -F "[X][r][a][y][-][c][o][r][e][ ]" '{print $2}' | awk -F "[<]" '{print $1}' | tail -n 5 | awk '{print ""NR""":"$0}' | grep "${selectXrayVersionType}:" | awk -F "[:]" '{print $2}')
		if [[ -n "${version}" ]]; then
			updateXray "${version}"
		else
			echoContent red "\n ---> 输入有误，请重新输入"
			xrayVersionManageMenu 1
		fi
	elif [[ "${selectXrayType}" == "3" ]]; then
		handleXray stop
	elif [[ "${selectXrayType}" == "4" ]]; then
		handleXray start
	elif [[ "${selectXrayType}" == "5" ]]; then
		reloadCore
	fi

}
# 更新Xray
updateXray() {
	readInstallType
	if [[ -z "${coreInstallType}" ]]; then
		if [[ -n "$1" ]]; then
			version=$1
		else
			version=$(curl -s https://github.com/XTLS/Xray-core/releases | grep /XTLS/Xray-core/releases/tag/ | grep "Xray-core v" | head -1 | awk '{print $3}' | awk -F "[<]" '{print $1}')
		fi

		echoContent green " ---> Xray-core版本:${version}"

		if wget --help | grep -q show-progress; then
			wget -c -q --show-progress -P /etc/v2ray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/Xray-linux-64.zip"
		else
			wget -c -P /etc/v2ray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/Xray-linux-64.zip" >/dev/null 2>&1
		fi

		unzip -o /etc/v2ray-agent/xray/Xray-linux-64.zip -d /etc/v2ray-agent/xray >/dev/null
		rm -rf /etc/v2ray-agent/xray/Xray-linux-64.zip
		chmod 655 /etc/v2ray-agent/xray/xray
		handleXray stop
		handleXray start
	else
		echoContent green " ---> 当前Xray-core版本:$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)"

		if [[ -n "$1" ]]; then
			version=$1
		else
			version=$(curl -s https://github.com/XTLS/Xray-core/releases | grep /XTLS/Xray-core/releases/tag/ | grep "Xray-core v" | head -1 | awk '{print $3}' | awk -F "[<]" '{print $1}')
		fi

		if [[ -n "$1" ]]; then
			read -r -p "回退版本为${version}，是否继续？[y/n]:" rollbackXrayStatus
			if [[ "${rollbackXrayStatus}" == "y" ]]; then
				echoContent green " ---> 当前Xray-core版本:$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)"

				handleXray stop
				rm -f /etc/v2ray-agent/xray/xray
				updateXray "${version}"
			else
				echoContent green " ---> 放弃回退版本"
			fi
		elif [[ "${version}" == "v$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)" ]]; then
			read -r -p "当前版本与最新版相同，是否重新安装？[y/n]:" reInstallXrayStatus
			if [[ "${reInstallXrayStatus}" == "y" ]]; then
				handleXray stop
				rm -f /etc/v2ray-agent/xray/xray
				rm -f /etc/v2ray-agent/xray/xray
				updateXray
			else
				echoContent green " ---> 放弃重新安装"
			fi
		else
			read -r -p "最新版本为：${version}，是否更新？[y/n]：" installXrayStatus
			if [[ "${installXrayStatus}" == "y" ]]; then
				rm -f /etc/v2ray-agent/xray/xray
				updateXray
			else
				echoContent green " ---> 放弃更新"
			fi

		fi
	fi
}

# 验证整个服务是否可用
checkGFWStatue() {
	readInstallType
	echoContent skyBlue "\n进度 $1/${totalProgress} : 验证服务启动状态"
	if [[ "${coreInstallType}" == "1" ]] && [[ -n $(pgrep -f xray/xray) ]]; then
		echoContent green " ---> 服务启动成功"
	elif [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]] && [[ -n $(pgrep -f v2ray/v2ray) ]]; then
		echoContent green " ---> 服务启动成功"
	else
		echoContent red " ---> 服务启动失败，请检查终端是否有日志打印"
		exit 0
	fi

}

# Xray开机自启
installXrayService() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Xray开机自启"
	if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
		rm -rf /etc/systemd/system/xray.service
		touch /etc/systemd/system/xray.service
		execStart='/etc/v2ray-agent/xray/xray run -confdir /etc/v2ray-agent/xray/conf'
		cat <<EOF >/etc/systemd/system/xray.service
[Unit]
Description=Xray - A unified platform for anti-censorship
# Documentation=https://v2ray.com https://guide.v2fly.org
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=yes
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23


[Install]
WantedBy=multi-user.target
EOF
		systemctl daemon-reload
		systemctl enable xray.service
		echoContent green " ---> 配置Xray开机自启成功"
	fi
}

# 操作xray
handleXray() {
	if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && ls /etc/systemd/system/ | grep -q xray.service; then
		if [[ -z $(pgrep -f "xray/xray") ]] && [[ "$1" == "start" ]]; then
			systemctl start xray.service
		elif [[ -n $(pgrep -f "xray/xray") ]] && [[ "$1" == "stop" ]]; then
			systemctl stop xray.service
		fi
	fi

	sleep 0.8

	if [[ "$1" == "start" ]]; then
		if [[ -n $(pgrep -f "xray/xray") ]]; then
			echoContent green " ---> Xray启动成功"
		else
			echoContent red "xray启动失败"
			echoContent red "执行 [ps -ef|grep xray] 查看日志"
			exit 0
		fi
	elif [[ "$1" == "stop" ]]; then
		if [[ -z $(pgrep -f "xray/xray") ]]; then
			echoContent green " ---> Xray关闭成功"
		else
			echoContent red "xray关闭失败"
			echoContent red "请手动执行【ps -ef|grep -v grep|grep xray|awk '{print \$2}'|xargs kill -9】"
			exit 0
		fi
	fi
}

# 初始化Xray 配置文件
initXrayConfig() {
	echoContent skyBlue "\n进度 $2/${totalProgress} : 初始化Xray配置"
	echo
	read -r -p "是否自定义UUID ？[y/n]:" customUUIDStatus
	echo

	if [[ "${customUUIDStatus}" == "y" ]]; then
		read -r -p "请输入合法的UUID:" currentCustomUUID
		if [[ -n "${currentCustomUUID}" ]]; then
			uuid=${currentCustomUUID}
		fi
	fi

	if [[ -n "${currentUUID}" && -z "${uuid}" ]]; then
		echo
		read -r -p "读取到上次安装记录，是否使用上次安装时的UUID ？[y/n]:" historyUUIDStatus
		if [[ "${historyUUIDStatus}" == "y" ]]; then
			uuid=${currentUUID}
		else
			uuid=$(/etc/v2ray-agent/xray/xray uuid)
		fi
	elif [[ -z "${uuid}" ]]; then
		uuid=$(/etc/v2ray-agent/xray/xray uuid)
	fi

	if [[ -z "${uuid}" ]]; then
		echoContent red "\n ---> uuid读取错误，重新生成"
		uuid=$(/etc/v2ray-agent/xray/xray uuid)
	fi

	echoContent green "\n ---> 使用成功"

	rm -rf /etc/v2ray-agent/xray/conf/*

	# log
	cat <<EOF >/etc/v2ray-agent/xray/conf/00_log.json
{
  "log": {
    "error": "/etc/v2ray-agent/xray/error.log",
    "loglevel": "warning"
  }
}
EOF

	# outbounds
	if [[ -n "${pingIPv6}" ]]; then
		cat <<EOF >/etc/v2ray-agent/xray/conf/10_ipv6_outbounds.json
{
    "outbounds": [
        {
          "protocol": "freedom",
          "settings": {},
          "tag": "direct"
        }
    ]
}
EOF

	else
		cat <<EOF >/etc/v2ray-agent/xray/conf/10_ipv4_outbounds.json
{
    "outbounds": [
        {
          "protocol": "freedom",
          "settings": {
            "domainStrategy": "UseIPv4"
          },
          "tag": "IPv4-out"
        }
    ]
}
EOF
	fi

	# 取消BT
	#	cat <<EOF >/etc/v2ray-agent/xray/conf/10_bt_outbounds.json
	#{
	#    "outbounds": [
	#        {
	#          "protocol": "blackhole",
	#          "settings": {},
	#          "tag": "blocked"
	#        }
	#    ]
	#}
	#EOF

	# dns
	cat <<EOF >/etc/v2ray-agent/xray/conf/11_dns.json
{
    "dns": {
        "servers": [
          "localhost"
        ]
  }
}
EOF
	# VLESS_TCP_TLS/XTLS
	# 回落nginx
	local fallbacksList='{"dest":31300,"xver":0}'

	if echo "${selectCustomInstallType}" | grep -q 4 || [[ "$1" == "all" ]]; then
		# 回落trojan-go
		fallbacksList='{"dest":31296,"xver":0}'
	fi

	# VLESS_WS_TLS
	if echo "${selectCustomInstallType}" | grep -q 1 || [[ "$1" == "all" ]]; then
		fallbacksList=${fallbacksList}',{"path":"/'${customPath}'ws","dest":31297,"xver":1}'
		cat <<EOF >/etc/v2ray-agent/xray/conf/03_VLESS_WS_inbounds.json
{
"inbounds":[
    {
  "port": 31297,
  "listen": "127.0.0.1",
  "protocol": "vless",
  "tag":"VLESSWS",
  "settings": {
    "clients": [
      {
        "id": "${uuid}",
        "email": "${domain}_vless_ws"
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "security": "none",
    "wsSettings": {
      "acceptProxyProtocol": true,
      "path": "/${customPath}ws"
    }
  }
}
]
}
EOF
	fi

	# VMess_TCP
	if [[ -n $(echo ${selectCustomInstallType} | grep 2) || "$1" == "all" ]]; then
		fallbacksList=${fallbacksList}',{"path":"/'${customPath}'tcp","dest":31298,"xver":1}'
		cat <<EOF >/etc/v2ray-agent/xray/conf/04_VMess_TCP_inbounds.json
{
"inbounds":[
{
  "port": 31298,
  "listen": "127.0.0.1",
  "protocol": "vmess",
  "tag":"VMessTCP",
  "settings": {
    "clients": [
      {
        "id": "${uuid}",
        "alterId": 1,
        "email": "${domain}_vmess_tcp"
      }
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "none",
    "tcpSettings": {
      "acceptProxyProtocol": true,
      "header": {
        "type": "http",
        "request": {
          "path": [
            "/${customPath}tcp"
          ]
        }
      }
    }
  }
}
]
}
EOF
	fi

	# VMess_WS
	if echo "${selectCustomInstallType}" | grep -q 3 || [[ "$1" == "all" ]]; then
		fallbacksList=${fallbacksList}',{"path":"/'${customPath}'vws","dest":31299,"xver":1}'
		cat <<EOF >/etc/v2ray-agent/xray/conf/05_VMess_WS_inbounds.json
{
"inbounds":[
{
  "port": 31299,
  "protocol": "vmess",
  "tag":"VMessWS",
  "settings": {
    "clients": [
      {
        "id": "${uuid}",
        "alterId": 1,
        "add": "${add}",
        "email": "${domain}_vmess_ws"
      }
    ]
  },
  "streamSettings": {
    "network": "ws",
    "security": "none",
    "wsSettings": {
      "acceptProxyProtocol": true,
      "path": "/${customPath}vws"
    }
  }
}
]
}
EOF
	fi

	if echo "${selectCustomInstallType}" | grep -q 5 || [[ "$1" == "all" ]]; then
		fallbacksList=${fallbacksList}',{"alpn":"h2","dest":31301,"xver":0}'
		cat <<EOF >/etc/v2ray-agent/xray/conf/06_VLESS_gRPC_inbounds.json
{
    "inbounds":[
    {
        "port": 31301,
        "listen": "127.0.0.1",
        "protocol": "vless",
        "tag":"VLESSGRPC",
        "settings": {
            "clients": [
                {
                    "id": "${uuid}",
                    "add": "${add}",
                    "email": "${domain}_vless_grpc"
                }
            ],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "grpc",
            "grpcSettings": {
                "serviceName": "${customPath}grpc"
            }
        }
    }
]
}
EOF
	fi

	# VLESS_TCP
	cat <<EOF >/etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json
{
"inbounds":[
{
  "port": 443,
  "protocol": "vless",
  "tag":"VLESSTCP",
  "settings": {
    "clients": [
     {
        "id": "${uuid}",
        "add":"${add}",
        "flow":"xtls-rprx-direct",
        "email": "${domain}_VLESS_XTLS/TLS-direct_TCP"
      }
    ],
    "decryption": "none",
    "fallbacks": [
        ${fallbacksList}
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "xtls",
    "xtlsSettings": {
      "minVersion": "1.2",
      "alpn": [
        "http/1.1",
        "h2"
      ],
      "certificates": [
        {
          "certificateFile": "/etc/v2ray-agent/tls/${domain}.crt",
          "keyFile": "/etc/v2ray-agent/tls/${domain}.key",
          "ocspStapling": 3600,
          "usage":"encipherment"
        }
      ]
    }
  }
}
]
}
EOF
}

# 通用
defaultBase64Code() {
	local type=$1
	local ps=$2
	local id=$3
	local hostPort=$4
	local host=
	local port=
	if echo "${hostPort}" | grep -q ":"; then
		host=$(echo "${hostPort}" | awk -F "[:]" '{print $1}')
		port=$(echo "${hostPort}" | awk -F "[:]" '{print $2}')
	else
		host=${hostPort}
		port=443
	fi

	local path=$5
	local add=$6

	local subAccount=${currentHost}_$(echo "${id//\"/}_currentHost" | md5sum | awk '{print $1}')
	if [[ "${type}" == "vlesstcp" ]]; then
		local VLESSID
		VLESSID=${id//\"/}
		local VLESSEmail
		VLESSEmail=$(echo "${ps}" | awk -F "[\"]" '{print $2}')

		if [[ "${coreInstallType}" == "1" ]]; then
			echoContent yellow " ---> 通用格式(VLESS+TCP+TLS/xtls-rprx-direct)"
			echoContent green "    vless://${VLESSID}@${host}:${port}?encryption=none&security=xtls&type=tcp&host=${host}&headerType=none&flow=xtls-rprx-direct#${VLESSEmail}\n"

			echoContent yellow " ---> 格式化明文(VLESS+TCP+TLS/xtls-rprx-direct)"
			echoContent green "协议类型：VLESS，地址：${host}，端口：${port}，用户ID：${VLESSID}，安全：xtls，传输方式：tcp，flow：xtls-rprx-direct，账户名:${VLESSEmail}\n"
			cat <<EOF >>"/etc/v2ray-agent/subscribe_tmp/${subAccount}"
vless://${VLESSID}@${host}:${port}?encryption=none&security=xtls&type=tcp&host=${host}&headerType=none&flow=xtls-rprx-direct#${VLESSEmail}
EOF
			echoContent yellow " ---> 二维码 VLESS(VLESS+TCP+TLS/xtls-rprx-direct)"
			echoContent green "https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${VLESSID}%40${host}%3A${port}%3F${encryption}%3Dnone%26security%3Dxtls%26type%3Dtcp%26${host}%3D${host}%26headerType%3Dnone%26flow%3Dxtls-rprx-direct%23${VLESSEmail}\n"
                 fi
	fi
}

# 账号
showAccounts() {
	readInstallType
	readConfigHostPathUUID
	readInstallProtocolType
	echoContent skyBlue "\n进度 $1/${totalProgress} : 账号"
	local show
	# VLESS TCP
	if [[ -n "${configPath}" ]]; then
		show=1
		if echo "${currentInstallProtocolType}" | grep -q 0 || [[ -z "${currentInstallProtocolType}" ]]; then
			echoContent skyBlue "===================== VLESS TCP TLS/XTLS-direct/XTLS-splice ======================\n"
			# cat ${configPath}02_VLESS_TCP_inbounds.json | jq .inbounds[0].settings.clients | jq -c '.[]'
			jq .inbounds[0].settings.clients ${configPath}02_VLESS_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
				defaultBase64Code vlesstcp $(echo "${user}" | jq .email) $(echo "${user}" | jq .id) "${currentHost}:${currentPort}" ${currentHost}
			done
		fi
	fi
	
	if [[ -z ${show} ]]; then
		echoContent red " ---> 未安装"
	fi
}

# 更新伪装站
updateNginxBlog() {
	echoContent skyBlue "\n进度 $1/${totalProgress} : 更换伪装站点"
	echoContent red "=============================================================="
	echoContent yellow "# 如需自定义，请手动复制模版文件到 /usr/share/nginx/html \n"
	echoContent yellow "1.数据统计模版"
	echoContent yellow "2.下雪动画用户注册登录模版"
	echoContent yellow "3.物流大数据服务平台模版"
	echoContent yellow "4.植物花卉模版"
	echoContent yellow "5.解锁加密的音乐文件模版[https://github.com/ix64/unlock-music]"
	echoContent yellow "6.mikutap[https://github.com/HFIProgramming/mikutap]"
	echoContent red "=============================================================="
	read -r -p "请选择：" selectInstallNginxBlogType

	if [[ "${selectInstallNginxBlogType}" =~ ^[1-6]$ ]]; then
		rm -rf /usr/share/nginx/html

		if wget --help | grep -q show-progress; then
			wget -c -q --show-progress -P /usr/share/nginx "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${selectInstallNginxBlogType}.zip" >/dev/null
		else
			wget -c -P /usr/share/nginx "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${selectInstallNginxBlogType}.zip" >/dev/null
		fi

		unzip -o "/usr/share/nginx/html${selectInstallNginxBlogType}.zip" -d /usr/share/nginx/html >/dev/null
		rm -f "/usr/share/nginx/html${selectInstallNginxBlogType}.zip*"
		echoContent green " ---> 更换伪站成功"
	else
		echoContent red " ---> 选择错误，请重新选择"
		updateNginxBlog
	fi
}

# 卸载脚本
unInstall() {
	read -r -p "是否确认卸载安装内容？[y/n]:" unInstallStatus
	if [[ "${unInstallStatus}" != "y" ]]; then
		echoContent green " ---> 放弃卸载"
		menu
		exit 0
	fi

	handleNginx stop
	if [[ -z $(pgrep -f "nginx") ]]; then
		echoContent green " ---> 停止Nginx成功"
	fi

	handleV2Ray stop
	handleTrojanGo stop
	#	handleMTG stop

	rm -rf /etc/systemd/system/v2ray.service
	echoContent green " ---> 删除V2Ray开机自启完成"

	#	rm -rf /etc/systemd/system/mtg.service
	#	echoContent green " ---> 删除MTG开机自启完成"

	rm -rf /etc/systemd/system/trojan-go.service
	echoContent green " ---> 删除Trojan-Go开机自启完成"
	rm -rf /tmp/v2ray-agent-tls/*
	if [[ -d "/etc/v2ray-agent/tls" ]] && [[ -n $(find /etc/v2ray-agent/tls/ -name "*.key") ]] && [[ -n $(find /etc/v2ray-agent/tls/ -name "*.crt") ]]; then
		mv /etc/v2ray-agent/tls /tmp/v2ray-agent-tls
		if [[ -n $(find /tmp/v2ray-agent-tls -name '*.key') ]]; then
			echoContent yellow " ---> 备份证书成功，请注意留存。[/tmp/v2ray-agent-tls]"
		fi
	fi

	rm -rf /etc/v2ray-agent
	rm -rf /etc/nginx/conf.d/alone.conf
	rm -rf /usr/bin/vasma
	rm -rf /usr/sbin/vasma
	echoContent green " ---> 卸载快捷方式完成"
	echoContent green " ---> 卸载v2ray-agent脚本完成"
}

# 自定义uuid
customUUID() {
	read -r -p "是否自定义UUID ？[y/n]:" customUUIDStatus
	echo
	if [[ "${customUUIDStatus}" == "y" ]]; then
		read -r -p "请输入合法的UUID:" currentCustomUUID
		echo
		if [[ -z "${currentCustomUUID}" ]]; then
			echoContent red " ---> UUID不可为空"
		else
			local repeat=
			jq '.inbounds[0].settings.clients[].id' ${configPath}02_VLESS_TCP_inbounds.json | awk -F "[\"]" '{print $2}' | while read -r line; do
				if [[ "${line}" == "${currentCustomUUID}" ]]; then
					echo repeat >/tmp/v2ray-agent
				fi
			done
			if [[ -f "/tmp/v2ray-agent" && -n $(cat /tmp/v2ray-agent) ]]; then
				echoContent red " ---> UUID不可重复"
				rm /tmp/v2ray-agent
				exit 0
			fi
		fi
	fi
}

# 自定义email
customUserEmail() {
	read -r -p "是否自定义email ？[y/n]:" customEmailStatus
	echo
	if [[ "${customEmailStatus}" == "y" ]]; then
		read -r -p "请输入合法的email:" currentCustomEmail
		echo
		if [[ -z "${currentCustomEmail}" ]]; then
			echoContent red " ---> email不可为空"
		else
			local repeat=
			jq '.inbounds[0].settings.clients[].email' ${configPath}02_VLESS_TCP_inbounds.json | awk -F "[\"]" '{print $2}' | while read -r line; do
				if [[ "${line}" == "${currentCustomEmail}" ]]; then
					echo repeat >/tmp/v2ray-agent
				fi
			done
			if [[ -f "/tmp/v2ray-agent" && -n $(cat /tmp/v2ray-agent) ]]; then
				echoContent red " ---> email不可重复"
				rm /tmp/v2ray-agent
				exit 0
			fi
		fi
	fi
}

# 查看、检查日志
checkLog() {
	if [[ -z ${configPath} ]]; then
		echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
	fi
	local logStatus=false
	if [[ -n $(cat ${configPath}00_log.json | grep access) ]]; then
		logStatus=true
	fi

	echoContent skyBlue "\n功能 $1/${totalProgress} : 查看日志"
	echoContent red "\n=============================================================="
	echoContent yellow "# 建议仅调试时打开access日志\n"

	if [[ "${logStatus}" == "false" ]]; then
		echoContent yellow "1.打开access日志"
	else
		echoContent yellow "1.关闭access日志"
	fi

	echoContent yellow "2.监听access日志"
	echoContent yellow "3.监听error日志"
	echoContent yellow "4.清空日志"
	echoContent red "=============================================================="

	read -r -p "请选择：" selectAccessLogType
	local configPathLog=${configPath//conf\//}

	case ${selectAccessLogType} in
	1)
		if [[ "${logStatus}" == "false" ]]; then
			cat <<EOF >${configPath}00_log.json
{
  "log": {
  	"access":"${configPathLog}access.log",
    "error": "${configPathLog}error.log",
    "loglevel": "warning"
  }
}
EOF
		elif [[ "${logStatus}" == "true" ]]; then
			cat <<EOF >${configPath}00_log.json
{
  "log": {
    "error": "${configPathLog}error.log",
    "loglevel": "warning"
  }
}
EOF
		fi
		reloadCore
		checkLog 1
		;;
	2)
		tail -f ${configPathLog}access.log
		;;
	3)
		tail -f ${configPathLog}error.log
		;;
	4)
		echo >${configPathLog}access.log
		echo >${configPathLog}error.log
		;;
	esac
}

# 脚本快捷方式
aliasInstall() {

	if [[ -f "$HOME/install.sh" ]] && [[ -d "/etc/v2ray-agent" ]] && grep <$HOME/install.sh -q "作者：mack-a"; then
		mv "$HOME/install.sh" /etc/v2ray-agent/install.sh
		if [[ -d "/usr/bin/" ]] && [[ ! -f "/usr/bin/vasma" ]]; then
			ln -s /etc/v2ray-agent/install.sh /usr/bin/vasma
			chmod 700 /usr/bin/vasma
			rm -rf "$HOME/install.sh"
		elif [[ -d "/usr/sbin" ]] && [[ ! -f "/usr/sbin/vasma" ]]; then
			ln -s /etc/v2ray-agent/install.sh /usr/sbin/vasma
			chmod 700 /usr/sbin/vasma
			rm -rf "$HOME/install.sh"
		fi
		echoContent green "快捷方式创建成功，可执行[vasma]重新打开脚本"
	fi
}

# 检查ipv6、ipv4
checkIPv6() {
	pingIPv6=$(ping6 -c 1 www.google.com | sed '2{s/[^(]*(//;s/).*//;q;}' | tail -n +2)
	if [[ -z "${pingIPv6}" ]]; then
		echoContent red " ---> 不支持ipv6"
		exit 0
	fi
}

# Xray-core个性化安装
customXrayInstall() {
	echoContent skyBlue "\n========================个性化安装============================"
	echoContent yellow "VLESS前置，默认安装0，如果只需要安装0，则只选择0即可"
	echoContent yellow "0.VLESS+TLS/XTLS+TCP"
	read -r -p "请选择[多选]，[例如:123]:" selectCustomInstallType
	echoContent skyBlue "--------------------------------------------------------------"
	if [[ -z ${selectCustomInstallType} ]]; then
		echoContent red " ---> 不可为空"
		customXrayInstall
	elif [[ "${selectCustomInstallType}" =~ ^[0-5]+$ ]]; then
		cleanUp v2rayClean
		totalProgress=17
		installTools 1
		# 申请tls
		initTLSNginxConfig 2
		installTLS 3
		handleNginx stop
		initNginxConfig 4
		# 随机path
		if echo "${selectCustomInstallType}" | grep -q 1 || echo "${selectCustomInstallType}" | grep -q 3 || echo "${selectCustomInstallType}" | grep -q 4 || echo "${selectCustomInstallType}" | grep -q 5; then
			randomPathFunction 5
			customCDNIP 6
		fi
		nginxBlog 7
		updateRedirectNginxConf
		handleNginx start

		# 安装V2Ray
		installXray 8
		installXrayService 9
		initXrayConfig custom 10
		cleanUp v2rayDel
		if echo "${selectCustomInstallType}" | grep -q 4; then
			installTrojanGo 11
			installTrojanService 12
			initTrojanGoConfig 13
			handleTrojanGo stop
			handleTrojanGo start
		else
			# 这里需要删除trojan的服务
			handleTrojanGo stop
			rm -rf /etc/v2ray-agent/trojan/*
			rm -rf /etc/systemd/system/trojan-go.service
		fi
		installCronTLS 14
		handleXray stop
		handleXray start
		# 生成账号
		checkGFWStatue 15
		showAccounts 16
	else
		echoContent red " ---> 输入不合法"
		customXrayInstall
	fi
}

# 选择核心安装---xray-core
selectCoreInstall() {
	echoContent skyBlue "\n功能 1/${totalProgress} : 选择核心安装"
	echoContent red "\n=============================================================="
	echoContent yellow "1.Xray-core"
	echoContent red "=============================================================="
	read -r -p "请选择：" selectCoreType
	case ${selectCoreType} in
	"1")
		if [[ "${selectInstallType}" == "2" ]]; then
			customXrayInstall
		else
			xrayCoreInstall
		fi
		;;
	*)
		echoContent red ' ---> 选择错误，重新选择'
		selectCoreInstall
		;;
	esac
}

# xray-core 安装
xrayCoreInstall() {
	cleanUp v2rayClean
	selectCustomInstallType=

	totalProgress=17
	installTools 2
	# 申请tls
	initTLSNginxConfig 3
	installTLS 4
	handleNginx stop
	initNginxConfig 5
	randomPathFunction 6
	# 安装Xray
	handleV2Ray stop
	installXray 7
	installXrayService 8
	installTrojanGo 9
	installTrojanService 10
	customCDNIP 11
	initXrayConfig all 12
	cleanUp v2rayDel
	initTrojanGoConfig 13
	installCronTLS 14
	nginxBlog 15
	updateRedirectNginxConf
	handleXray stop
	sleep 2
	handleXray start

	handleNginx start
	handleTrojanGo stop
	sleep 1
	handleTrojanGo start
	# 生成账号
	checkGFWStatue 16
	showAccounts 17
}

# 核心管理
coreVersionManageMenu() {

	if [[ -z "${coreInstallType}" ]]; then
		echoContent red "\n ---> 没有检测到安装目录，请执行脚本安装内容"
		menu
		exit 0
	fi
	if [[ "${coreInstallType}" == "1" ]]; then
		xrayVersionManageMenu 1
	elif [[ "${coreInstallType}" == "2" ]]; then
		v2rayCoreVersion=
		v2rayVersionManageMenu 1

	elif [[ "${coreInstallType}" == "3" ]]; then
		v2rayCoreVersion=v4.32.1
		v2rayVersionManageMenu 1
	fi
}
# 定时任务检查证书
cronRenewTLS() {
	if [[ "${renewTLS}" == "RenewTLS" ]]; then
		renewalTLS
		exit 0
	fi
}

# 主菜单
menu() {
	cd "$HOME" || exit
	echoContent red "\n=============================================================="
	echoContent green "作者：mack-a"
	showInstallStatus
	echoContent red "\n=============================================================="
	if [[ -n "${coreInstallType}" ]]; then
		echoContent yellow "1.重新安装"
	else
		echoContent yellow "1.安装"
	fi

	echoContent yellow "2.任意组合安装"
	echoContent skyBlue "-------------------------工具管理-----------------------------"
	echoContent yellow "3.更换伪装站"
	echoContent yellow "4.更新证书"
	echoContent skyBlue "-------------------------版本管理-----------------------------"
	echoContent yellow "5.core管理"
	echoContent skyBlue "-------------------------脚本管理-----------------------------"
	echoContent yellow "6.查看日志"
	echoContent yellow "7.卸载脚本"
	echoContent red "=============================================================="
	mkdirTools
	aliasInstall
	read -r -p "请选择:" selectInstallType
	case ${selectInstallType} in
	1)
		selectCoreInstall
		;;
	2)
		selectCoreInstall
		;;
	3)
		updateNginxBlog 1
		;;
	4)
		renewalTLS 1
		;;
	5)
		coreVersionManageMenu 1
		;;
	6)
		checkLog 1
		;;
	7)
		unInstall 1
		;;
	esac
}
cronRenewTLS
menu
