#!/bin/bash

# 检查是否提供了端口号参数
if [ $# -ne 1 ]; then
    echo "错误: 请提供端口号作为参数"
    echo "用法: $0 <端口号>"
    exit 1
fi

# 验证端口号是否为数字
if ! [[ $1 =~ ^[0-9]+$ ]]; then
    echo "错误: 端口号必须是数字"
    exit 1
fi

PORT=$1

# 检测操作系统类型
if [ "$(uname)" = "Linux" ]; then
    # Linux系统：使用ss命令查找端口对应的进程
    PID=$(ss -lptn "sport = :$PORT" | grep LISTEN | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -n1)
else
    # Windows系统：使用netstat命令
    PID=$(netstat -ano | grep "LISTENING" | grep ":$PORT" | awk '{print $5}')
fi

# 检查是否找到进程
if [ -z "$PID" ]; then
    echo "未找到使用端口 $PORT 的进程"
    exit 1
fi

# 显示进程信息并请求确认
echo "找到使用端口 $PORT 的进程:"
echo "进程ID (PID): $PID"
echo "进程详情:"
if [ "$(uname)" = "Linux" ]; then
    # Linux系统：使用ps命令显示进程信息
    ps -p $PID -o pid,ppid,user,%cpu,%mem,cmd
else
    # Windows系统：使用tasklist命令
    tasklist | findstr "$PID"
fi

read -p "是否要终止该进程? (y/n): " confirm
if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    # 尝试终止进程
    if [ "$(uname)" = "Linux" ]; then
        # Linux系统：使用kill命令
        kill -9 $PID
    else
        # Windows系统：使用taskkill命令
        taskkill /F /PID $PID
    fi
    
    if [ $? -eq 0 ]; then
        echo "进程已成功终止"
    else
        echo "终止进程失败"
        exit 1
    fi
else
    echo "操作已取消"
    exit 0
fi