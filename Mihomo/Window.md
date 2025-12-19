### 1. 下载 mihomo 核心文件并解压

> 下载文件解压得到exe文件,创建核心目录并放入exe文件

> 需注意是否需要手动创建web控制面板的目录（D:\mihomo\ui）

```
https://github.com/MetaCubeX/mihomo/releases/download/v1.19.5/mihomo-windows-amd64-v1.19.5.zip
```

### 2. 裸核运行脚本

> 在核心同级目录下创建 mihomo.vbs 文件

```
set mihomo = CreateObject("WScript.Shell")
mihomo.Run "mihomo-windows-amd64.exe -d .", 0
```

### 3. 创建配置文件

> 在核心同级目录下创建 config.yaml 文件

### 4. 运行核心

> 运行 mihomo.vbs 文件

> 访问 http://127.0.0.1:9090/ui 进入控制面板

### 5. 开机启动

> 为 mihomo.vbs 文件创建快捷方式，置于以下目录

```
C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup
```

### 6.设置以管理员身份运行

> 右键点击mihomo-windows-amd64.exe文件，选择属性->兼容性->勾选"以管理员身份运行此程序"
