# v2ray-agent

- [流量中转](https://github.com/mack-a/v2ray-agent/blob/master/documents/traffic_relay.md)
- [手动自建教程](https://github.com/mack-a/v2ray-agent/blob/master/documents/Cloudflare_install_manual.md)
- [ssh入门教程](https://www.v2ray-agent.com/2020-12-16-ssh%E5%85%A5%E9%97%A8%E6%95%99%E7%A8%8B)

* * *

## 特性

- 支持[Xray-core[XTLS]](https://github.com/XTLS/Xray-core)
- 支持Debian、Ubuntu、Centos，支持主流的cpu架构。**不建议使用Centos以及低版本的系统，2.3.x后不再支持Centos6**
- 支持个性化安装
- 无需卸载即可安装、重装任意组合
- 支持卸载时保留Nginx、tls证书。如果acme.sh申请的证书有效的情况下，不会重新签发。
- [支持自定义证书安装](https://github.com/mack-a/v2ray-agent/blob/master/documents/install_tls.md)

## 支持的安装类型

- VLESS+TCP+xtls-rprx-direct【**推荐**】


## 组合推荐

- 中专/gia ---> VLESS+TCP+TLS/XTLS、Trojan【推荐使用XTLS的xtls-rprx-direct】

## 注意事项

- **修改Cloudflare->SSL/TLS->Overview->Full**
- **Cloudflare ---> A记录解析的云朵必须为灰色**
- **使用纯净系统安装，如使用其他脚本安装过，请重新build系统再安装**
- wget: command not found [**这里需要自己手动安装下wget**]
  ，如未使用过Linux，[点击查看](https://github.com/mack-a/v2ray-agent/tree/master/documents/install_tools.md)安装教程
- **不建议使用Centos以及低版本的系统，2.3.x后不再支持Centos6**

## 脚本目录

- Xray-core 【**/etc/v2ray-agent/xray、/etc/v2ray-agent/xray/conf**】
- TLS证书 【**/etc/v2ray-agent/tls**】
- Nginx配置文件 【**/etc/nginx/conf.d/alone.conf**】、Nginx伪装站点目录 【**/usr/share/nginx/html**】

## [脚本功能详解、错误处理、常用命令](https://github.com/mack-a/v2ray-agent/blob/master/documents/how_to_use.md)

## 安装脚本

- 支持快捷方式启动，安装完毕后，shell输入[**vasma**]即可打开脚本，脚本执行路径[**/etc/v2ray-agent/install.sh**]

- Latest Version

```
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/DonaldOffical/v2ray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

# 许可证

[GPL-3.0](https://github.com/mack-a/v2ray-agent/blob/master/LICENSE)
