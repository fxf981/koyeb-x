FROM debian

# 设置工作目录
WORKDIR /app

# 设置全局环境变量
ENV NZ_SERVER=
ENV NZ_SERVER_PORT=
ENV NZ_KEY=
ENV NZ_isTLS=
ENV UUID=

# 安装依赖
RUN apt-get update &&\
    apt-get -y install wget unzip supervisor curl net-tools htop btop screen nano cron &&\
    apt-get clean &&\
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
