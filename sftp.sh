#!/bin/bash
# 1. 建 tap 网卡（WSL 重启后需重跑一次）                                                                                                      
sudo ./scripts/net_tap.sh setup                                                                                                               
																																			
# 2. tap 模式启动 QEMU（当前已在运行，无需重复启动）                                                                                          
QEMU_NET=tap ./scripts/run_qemu.sh                                                                                                            
																																			
# 3. 连接（密码 root）                                                                                                                        
sftp root@192.168.76.2  