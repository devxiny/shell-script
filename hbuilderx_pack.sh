#!/bin/bash

# HBuilderX自动化打包脚本

# 配置路径变量
HBUILDERX_CLI_PATH="/home/yanxin/HBuilderX"  # HBuilderX-CLI目录路径
UNIAPP_PROJECT_PATH="/home/yanxin/sw.uni-app.front"  # uniapp项目路径
ANDROID_PACK_PATH="/home/yanxin/sw.uni-app.android"     # android打包载体路径
APK_OUTPUT_PATH="/home/yanxin/apk-output"  # APK输出目录路径

# 配置用户信息
USERNAME=""  # HBuilderX账号用户名
PASSWORD=""  # HBuilderX账号密码

# 配置项目信息
PROJECT_NAME="sw.uni-app.front"  # 项目名称

# 错误处理函数
handle_error() {
    echo "错误: $1"
    exit 1
}

# 检查必要路径和权限
check_paths() {
    if [ ! -d "$HBUILDERX_CLI_PATH" ]; then
        handle_error "HBuilderX-CLI目录不存在"
    fi
    if [ ! -d "$UNIAPP_PROJECT_PATH" ]; then
        handle_error "uniapp项目路径不存在"
    fi
    if [ ! -d "$ANDROID_PACK_PATH" ]; then
        handle_error "android打包载体路径不存在"
    fi

    # 检查gradlew文件权限
    local gradlew_path="$ANDROID_PACK_PATH/gradlew"
    if [ -f "$gradlew_path" ]; then
        if [ ! -x "$gradlew_path" ]; then
            echo "正在设置gradlew文件执行权限..."
            chmod +x "$gradlew_path" || handle_error "设置gradlew执行权限失败"
        fi
    else
        handle_error "gradlew文件不存在: $gradlew_path"
    fi
}

# 启动HBuilderX
start_hbuilderx() {
    cd "$HBUILDERX_CLI_PATH" || handle_error "无法进入HBuilderX-CLI目录"
    ./cli open || handle_error "启动HBuilderX失败"
}

# 登录HBuilderX
login_hbuilderx() {
    cd "$HBUILDERX_CLI_PATH" || handle_error "无法进入HBuilderX-CLI目录"
    ./cli user login --username "$USERNAME" --password "$PASSWORD" || handle_error "登录失败"
}

# 导入项目
import_project() {
    cd "$HBUILDERX_CLI_PATH" || handle_error "无法进入HBuilderX-CLI目录"
    ./cli project open --path "$UNIAPP_PROJECT_PATH" || handle_error "导入项目失败"
}

# 生成本地打包App资源
generate_app_resource() {
    cd "$HBUILDERX_CLI_PATH" || handle_error "无法进入HBuilderX-CLI目录"
    ./cli publish --platform APP --type appResource --project "$PROJECT_NAME" || handle_error "生成App资源失败"
}

# 清理资源文件
clean_resources() {
    # 清理uniapp项目资源目录
    local uniapp_resource_dir="$UNIAPP_PROJECT_PATH/unpackage/resources"
    if [ -d "$uniapp_resource_dir" ]; then
        rm -rf "$uniapp_resource_dir"/* || handle_error "清理uniapp资源目录失败"
        echo "已清理uniapp资源目录: $uniapp_resource_dir"
    fi

    # 清理android打包载体资源目录
    local android_resource_dir="$ANDROID_PACK_PATH/app/src/main/assets/apps"
    if [ -d "$android_resource_dir" ]; then
        rm -rf "$android_resource_dir"/* || handle_error "清理android资源目录失败"
        echo "已清理android资源目录: $android_resource_dir"
    fi
}

# 复制资源文件到Android打包载体目录
copy_resources() {
    # 检查资源目录是否存在
    local resource_dir="$UNIAPP_PROJECT_PATH/unpackage/resources"
    if [ ! -d "$resource_dir" ]; then
        handle_error "资源目录不存在: $resource_dir"
    fi

    # 查找以__开头的目录
    local source_dir=$(find "$resource_dir" -maxdepth 1 -type d -name "__*" -print -quit)
    if [ -z "$source_dir" ]; then
        handle_error "未找到以__开头的资源目录"
    fi

    # 获取源目录名称
    local dir_name=$(basename "$source_dir")

    # 检查目标目录
    local target_base_dir="$ANDROID_PACK_PATH/app/src/main/assets/apps"
    local target_dir="$target_base_dir/$dir_name"

    # 确保目标基础目录存在
    mkdir -p "$target_base_dir"

    # 检查目标目录是否已存在
    if [ -d "$target_dir" ]; then
        handle_error "目标目录已存在同名文件夹: $target_dir"
    fi

    # 执行复制操作
    cp -r "$source_dir" "$target_base_dir/" || handle_error "复制资源文件失败"
    echo "资源文件已成功复制到: $target_dir"
}

# 执行Android Release打包
build_android_release() {
    cd "$ANDROID_PACK_PATH" || handle_error "无法进入Android打包载体目录"
    echo "开始执行Android Release打包..."
    
    # 确保gradlew有执行权限
    if [ ! -x "./gradlew" ]; then
        echo "正在设置gradlew文件执行权限..."
        chmod +x ./gradlew || handle_error "设置gradlew执行权限失败"
    fi
    
    # 确保输出目录存在
    mkdir -p "$APK_OUTPUT_PATH" || handle_error "创建APK输出目录失败"
    
    ./gradlew assembleRelease -PoutputDir="$APK_OUTPUT_PATH" || handle_error "Android Release打包失败"
    echo "Android Release打包完成，APK已输出到: $APK_OUTPUT_PATH"
}

# 制作wgt包
generate_wgt() {
    local confuse=$1
    local custom_path=$2
    local custom_name=$3

    cd "$HBUILDERX_CLI_PATH" || handle_error "无法进入HBuilderX-CLI目录"
    
    if [ "$confuse" = "true" ]; then
        # 混淆打包
        ./cli publish --platform APP --type wgt --project "$PROJECT_NAME" --confuse true || handle_error "生成混淆wgt包失败"
    elif [ -n "$custom_path" ] && [ -n "$custom_name" ]; then
        # 自定义路径和名称
        ./cli publish --platform APP --type wgt --project "$PROJECT_NAME" --path "$custom_path" --name "$custom_name" || handle_error "生成自定义wgt包失败"
    else
        # 默认打包
        ./cli publish --platform APP --type wgt --project "$PROJECT_NAME" || handle_error "生成wgt包失败"
    fi
}

# 主函数
main() {
    # 检查参数
    local action=$1
    shift

    # 检查路径
    check_paths

    case "$action" in
        "start")
            start_hbuilderx
            ;;
        "login")
            login_hbuilderx
            ;;
        "import")
            import_project
            ;;
        "app-resource")
            generate_app_resource
            ;;

        "all")
            start_hbuilderx
            login_hbuilderx
            import_project
            clean_resources
            generate_app_resource
            copy_resources
            build_android_release
            ;;
        *)
            echo "用法: $0 [start|login|import|app-resource|all]"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"