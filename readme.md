## 目标实现 handshake 穿透

### handshake server

1. 在阿里云上使用docker部署handshake server；
2. 要求安装docker到启动handshake的完整步骤+检查，如：已经安装docker则不用再安装
3. 要求提供一个注册 ssh public key的server

### handshake source

handshake server => source; 如 通过handshake server 访问 gitlab主机

### handshake client

client => handleshake server => handshake source

### gitlab

docker 部署gitlab

最终要求，可以将代码拉下来，在对应的机器上执行，即可完成对应的安装