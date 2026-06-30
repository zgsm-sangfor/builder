# efficiency-dashboard

efficiency-dashboard package component

本目录的内容会被 build-components.sh 以 zip 方式整体打包为 `efficiency-dashboard.zip`。

如需针对不同平台提供不同内容，可在 `./configures/<os>/<arch>/efficiency-dashboard/` 下放置
平台特定版本；未提供平台目录时，回退到本 common 目录。

kbcli:
    deploy:
      resources:
        limits:
          cpus: "3"
          memory: 6144M
        reservations:
          cpus: "0.25"
          memory: 256M
portal:
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
        reservations:
          cpus: "0.25"
          memory: 128M
server:
    deploy:
      resources:
        limits:
          cpus: "3"
          memory: 6144M
        reservations:
          cpus: "0.25"
          memory: 256M
