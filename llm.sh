#!/bin/bash

# 模型管理脚本

# 检查是否安装了modelscope
check_modelscope() {
    if ! command -v modelscope &> /dev/null; then
        echo "正在安装modelscope..."
        pip install modelscope -i https://pypi.tuna.tsinghua.edu.cn/simple
    fi
}

# 检查是否安装了vllm
check_vllm() {
    if ! command -v vllm &> /dev/null; then
        echo "正在安装vllm..."
        pip install vllm -i https://pypi.tuna.tsinghua.edu.cn/simple
    fi
}

# 读取配置文件
CONFIG_FILE="./models_config.ini"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误：配置文件不存在！"
    exit 1
 fi

# 读取配置文件中的端口号和模型根目录
PORT=$(awk -F '=' '/^port=/{print $2}' "$CONFIG_FILE")
MODEL_BASE_PATH=$(awk -F '=' '/^model_base_path=/{print $2}' "$CONFIG_FILE")

# 显示菜单
show_menu() {
    echo "=========================="
    echo "    LLM 模型管理系统"
    echo "=========================="
    echo "1. 下载模型"
    echo "2. 运行模型"
    echo "3. 停止服务"
    echo "4. 退出"
    echo "=========================="
    echo "请选择操作 [1-4]: "
}

# 显示模型列表
show_models() {
    echo "可用的模型列表："
    echo "=========================="
    awk -F '=' '/^model_[0-9]+=/{models[++count]=$2} END{for(i=1;i<=count;i++) print i ". " models[i]}' "$CONFIG_FILE"
    echo "=========================="
}

# 获取模型总数
get_total_models() {
    awk -F '=' '/^model_[0-9]+=/{count++} END{print count}' "$CONFIG_FILE"
}

# 获取指定索引的模型名称
get_model_name() {
    local index=$1
    awk -F '=' '/^model_[0-9]+=/{models[++count]=$2} END{print models['$index']}' "$CONFIG_FILE"
}

# 下载模型
download_model() {
    show_models
    echo "请选择要下载的模型编号: "
    read choice
    
    # 获取选择的模型信息
    local total_models=$(get_total_models)
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$total_models" ]; then
        echo "无效的选择！"
        return 1
    fi
    
    local model_name=$(get_model_name $choice)
    local model_dir="$MODEL_BASE_PATH/${model_name//\//-}"
    
    echo "开始下载模型: $model_name"
    echo "存储路径: $model_dir"
    
    # 创建模型目录
    mkdir -p "$model_dir"
    
    # 使用modelscope下载模型
    modelscope download --model "$model_name" --local_dir "$model_dir"
    
    if [ $? -eq 0 ]; then
        echo "模型下载完成！"
    else
        echo "模型下载失败！"
        return 1
    fi
}

# 检查服务是否启动
check_service() {
    local port=$1
    curl -s "http://localhost:$port/health" >/dev/null 2>&1
    return $?
}

# 检查服务是否已运行
is_service_running() {
    local port=$1
    
    # 首先尝试使用 lsof
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i:$port >/dev/null 2>&1; then
            return 0  # 服务正在运行
        fi
    # 如果没有 lsof，尝试使用 netstat
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -an | grep "LISTEN" | grep ":$port " >/dev/null 2>&1; then
            return 0  # 服务正在运行
        fi
    # 如果都没有，尝试使用 ss
    elif command -v ss >/dev/null 2>&1; then
        if ss -ln | grep ":$port " >/dev/null 2>&1; then
            return 0  # 服务正在运行
        fi
    else
        echo "警告：未找到 lsof、netstat 或 ss 命令，无法检查端口状态" >&2
        return 2  # 返回特殊错误码表示无法检查
    fi
    
    return 1  # 服务未运行
}

# 停止模型服务
stop_model() {
    echo "检查服务状态..."
    if ! is_service_running $PORT; then
        echo "服务未运行！"
        return 1
    fi
    
    echo "正在停止服务..."
    # 查找并终止运行在指定端口的vllm进程
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        # Windows系统
        for pid in $(netstat -ano | grep "LISTENING" | grep ":$PORT " | awk '{print $5}'); do
            taskkill //F //PID $pid
        done
    else
        # Linux/Unix系统
        pkill -f "vllm serve.*--port $PORT"
    fi
    
    # 等待服务停止
    local timeout=30
    local interval=2
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if ! is_service_running $PORT; then
            echo "服务已停止！"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo "已等待 $elapsed 秒..."
    done
    
    echo "停止服务超时！请手动检查进程状态。"
    return 1
}

# 运行模型
run_model() {
    show_models
    echo "请选择要运行的模型编号: "
    read choice
    
    # 获取选择的模型信息
    local total_models=$(get_total_models)
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$total_models" ]; then
        echo "无效的选择！"
        return 1
    fi
    
    local model_name=$(get_model_name $choice)
    local model_dir="$MODEL_BASE_PATH/${model_name//\//-}"
    
    # 检查模型文件是否存在
    if [ ! -d "$model_dir" ]; then
        echo "错误：模型文件不存在，请先下载模型！"
        return 1
    fi
    
    echo "正在启动模型: $model_name"
    echo "服务将在端口 $PORT 上运行"

    # 检查服务是否已经运行
    if is_service_running $PORT; then
        echo "错误：端口 $PORT 已被占用，可能服务已经在运行！"
        return 1
    fi    
    
    # 构建vllm命令行参数
    local vllm_cmd="vllm serve \"$model_dir\" --port $PORT --host \"0.0.0.0\""
    
    # 获取模型编号
    local model_number="$choice"
    
    # 读取模型特定的参数配置
    local model_params_section="model_${model_number}_params"
    
    # 确保模型参数段存在
    if grep -q "^\[${model_params_section}\]" "$CONFIG_FILE"; then
        echo "正在加载模型 ${model_number} 的参数配置..."
        
        # 提取当前模型的参数部分
        local params_lines=$(sed -n "/^\[${model_params_section}\]/,/^\[/p" "$CONFIG_FILE" | sed '1d;/^\[/d')
        
        # 处理每个参数
        while IFS= read -r line; do
            # 跳过空行和注释行
            if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi
            
            # 分割参数名和值
            if [[ "$line" =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                local param_name="${BASH_REMATCH[1]}"
                local param_value="${BASH_REMATCH[2]}"
                
                # 去除参数名和值两端的空白
                param_name=$(echo "$param_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                param_value=$(echo "$param_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                
                # 如果参数为空则跳过
                if [ -z "$param_name" ]; then
                    continue
                fi
                
                # 将下划线转换为连字符
                local param_flag=${param_name//_/-}
                
                # 特殊处理布尔参数
                if [ "$param_value" = "true" ]; then
                    vllm_cmd="$vllm_cmd --$param_flag"
                elif [ -n "$param_value" ]; then
                    vllm_cmd="$vllm_cmd --$param_flag $param_value"
                fi
            fi
        done <<< "$params_lines"
    else
        echo "警告：未找到模型 ${model_number} 的参数配置，将使用默认参数运行"
    fi

    vllm_cmd="nohup $vllm_cmd > output_$(date +\%Y-\%m-\%d).log 2>&1 &"
    
    # 显示完整命令供用户确认
    echo "即将执行的命令："
    echo "$vllm_cmd"
    echo "按回车键继续执行，或按Ctrl+C取消..."
    read
    
    # 执行vllm命令
    eval $vllm_cmd

    # 设置超时时间（秒）
    local timeout=60
    local interval=5
    local elapsed=0
    
    echo "正在等待服务启动..."
    while [ $elapsed -lt $timeout ]; do
        if check_service $PORT; then
            echo "模型启动成功！服务运行在 http://localhost:$PORT"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo "已等待 $elapsed 秒..."
    done
    
    echo "模型启动超时！请检查日志文件 output_$(date +%Y-%m-%d).log"
    return 1
}

# 主程序
main() {
    # 检查依赖工具
    check_modelscope
    check_vllm
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                download_model
                ;;
            2)
                run_model
                ;;
            3)
                stop_model
                ;;
            4)
                echo "感谢使用！再见！"
                exit 0
                ;;
            *)
                echo "无效的选择，请重试！"
                ;;
        esac
        
        echo "\n按回车键继续..."
        read
        clear
    done
}

# 运行主程序
main