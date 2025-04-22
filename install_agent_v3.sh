#!/bin/bash

# === Цвета ===
CLR_INFO='\033[1;97;44m'
CLR_SUCCESS='\033[1;30;42m'
CLR_WARNING='\033[1;37;41m'
CLR_ERROR='\033[1;31;40m'
CLR_GREEN='\033[1;32m'
CLR_RESET='\033[0m'

AGENT_DIR="/root/agent"
TOKEN_FILE="$AGENT_DIR/token.txt"
SERVICE_FILE="/etc/systemd/system/agent.service"

# === Логотип ===
function show_logo() {
    echo -e "${CLR_INFO}   Добро пожаловать в установщик Agent Monitor   ${CLR_RESET}"
    curl -s https://raw.githubusercontent.com/profitnoders/Profit_Nodes/refs/heads/main/logo_new.sh | bash
}

# === Установка зависимостей ===
function install_dependencies() {
    apt update && apt install -y python3 python3-venv python3-pip docker.io curl
}

# === Ввод токена ===
function set_token() {
    read -p "Введите токен для доступа: " TOKEN
    mkdir -p "$AGENT_DIR"
    echo "$TOKEN" > "$TOKEN_FILE"
    echo -e "${CLR_SUCCESS}✅ Токен сохранён в $TOKEN_FILE${CLR_RESET}"
}

# === Установка агента ===
function install_agent() {
    mkdir -p "$AGENT_DIR"
    cd "$AGENT_DIR" || exit

    cat > agent.py << 'EOF'
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse
import psutil, docker, subprocess, threading, time, requests, os, socket

app = FastAPI()
ALERT_STATUS = {}  # {"NodeName": True/False}

# === Конфигурация всех нод ===

NODE_SYSTEMD = {
    "Cysic": "cysic.service",
    "Initverse": "initverse.service",
    "t3rn": "t3rn.service",
    "Pipe": "pipe-node.service",
    "0G": "zgs.service"
}

NODE_PROCESSES = {
    "Multiple": "multiple-node",
    "Dill Light Validator": "--light",
    "Dill Full Validator": "/root/dill/dill-node",
    "Gaia": "wasmedge",
    "Gensyn": "python -m hivemind_exp.gsm8k"
}

NODE_SCREENS = {
    "Gaia": "gaia_bot",
    "Dria": "dria_node"
}

NODE_DOCKER_CONTAINERS = {
    "Ritual": {"hello-world", "infernet-anvil", "infernet-fluentbit", "infernet-redis", "infernet-node"},
    "Biconomy": {"mee-node-deployment-node-1", "mee-node-deployment-redis-1"},
    "Unichain": {"unichain-node-op-node-1", "unichain-node-execution-client-1"},
    "Spheron": {"fizz-node"}
}

NODE_DOCKER_IMAGES = {
    "Titan": "nezha123/titan-edge"
}

COMPOSE_PATH = os.path.expanduser("~/infernet-container-starter/deploy/docker-compose.yaml")
BOT_ALERT_URL = "http://91.108.246.138:8080/alert"
ALERT_SENT = False
CHECK_INTERVAL = 60

def get_token():
    try:
        with open("token.txt") as f:
            return f.read().strip()
    except:
        return ""

def get_ip_address():
    return socket.gethostbyname(socket.gethostname())

def get_system_stats():
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    return {
        "cpu_percent": psutil.cpu_percent(interval=1),
        "cpu_cores": psutil.cpu_count(),
        "memory": {
            "percent": mem.percent,
            "used": mem.used,
            "total": mem.total
        },
        "disk": {
            "percent": disk.percent,
            "used": disk.used,
            "total": disk.total
        }
    }

def get_docker_status():
    try:
        client = docker.from_env()
        return {
            c.name: {
                "status": c.status,
                "started_at": c.attrs["State"]["StartedAt"]
            }
            for c in client.containers.list()
            if c.status == "running"
        }
    except Exception as e:
        return {"error": str(e)}

def get_systemd_services():
    statuses = {}
    for name in NODE_SYSTEMD.values():
        try:
            result = subprocess.check_output(["systemctl", "is-active", name], text=True).strip()
        except subprocess.CalledProcessError:
            result = "not found"
        statuses[name] = result
    return statuses

def get_background_processes():
    found = set()
    for proc in psutil.process_iter(['cmdline']):
        try:
            cmd = " ".join(proc.info['cmdline'])
            for name, match in NODE_PROCESSES.items():
                if match in cmd:
                    found.add(name)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return sorted(found)

def get_installed_nodes():
    result = []

    # 1. systemd
    for name, service in NODE_SYSTEMD.items():
        try:
            subprocess.check_output(["systemctl", "is-active", service], stderr=subprocess.DEVNULL)
            result.append(name)
        except subprocess.CalledProcessError:
            pass

    # 2. processes
    for proc in psutil.process_iter(['cmdline']):
        try:
            cmd = " ".join(proc.info['cmdline'])
            for name, keyword in NODE_PROCESSES.items():
                if keyword in cmd:
                    result.append(name)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    # 3. screen
    try:
        screens = subprocess.check_output(["screen", "-ls"], text=True)
        for name, session in NODE_SCREENS.items():
            if session in screens:
                result.append(name)
    except:
        pass

    # 4. docker
    try:
        client = docker.from_env()
        containers = client.containers.list()
        names = {c.name for c in containers}
        images = [img for c in containers for img in c.image.tags if c.image.tags]

        for name, expected in NODE_DOCKER_CONTAINERS.items():
            if expected.issubset(names):
                result.append(name)

        for name, img_pattern in NODE_DOCKER_IMAGES.items():
            if any(img_pattern in img for img in images):
                result.append(name)
    except Exception as e:
        print("⚠️ Docker check failed:", e)

    return sorted(set(result))

def monitor_disk():
    global ALERT_SENT
    while True:
        disk = psutil.disk_usage("/")
        percent = disk.percent

        if percent >= 90 and not ALERT_SENT:
            try:
                requests.post(BOT_ALERT_URL, json={
                    "token": get_token(),
                    "ip": get_ip_address(),
                    "percent": percent,
                    "alert_id": f"{get_ip_address()}-{int(time.time())}"
                })
                ALERT_SENT = True
            except Exception as e:
                print("Ошибка отправки алерта:", e)

        elif percent < 88 and ALERT_SENT:
            ALERT_SENT = False

        time.sleep(CHECK_INTERVAL)

def monitor_nodes():
    while True:
        failed = []

        # 1. Systemd
        for name, service in NODE_SYSTEMD.items():
            try:
                status = subprocess.check_output(["systemctl", "is-active", service], text=True).strip()
                if status != "active":
                    failed.append(name)
            except subprocess.CalledProcessError:
                failed.append(name)

        # 2. Docker
        try:
            client = docker.from_env()
            running = {c.name for c in client.containers.list()}
            for node, expected in NODE_DOCKER_CONTAINERS.items():
                if not expected.issubset(running):
                    failed.append(node)
            for node, image_part in NODE_DOCKER_IMAGES.items():
                if not any(image_part in (tag or "") for c in client.containers.list() for tag in c.image.tags):
                    failed.append(node)
        except Exception as e:
            print("⚠️ Docker error:", e)

        # 3. Процессы
        active = set()
        for proc in psutil.process_iter(['cmdline']):
            try:
                cmd = " ".join(proc.info['cmdline'])
                for name, pattern in NODE_PROCESSES.items():
                    if pattern in cmd:
                        active.add(name)
            except:
                continue
        for name in NODE_PROCESSES:
            if name not in active:
                failed.append(name)

        # 4. Screen
        try:
            screens = subprocess.check_output(["screen", "-ls"], text=True)
            for name, session in NODE_SCREENS.items():
                if session not in screens:
                    failed.append(name)
        except:
            failed += list(NODE_SCREENS.keys())

        # === Алерты ===
        for name in set(failed):
            if not ALERT_STATUS.get(name):
                send_alert(name)
                ALERT_STATUS[name] = True

        for name in list(ALERT_STATUS):
            if name not in failed:
                ALERT_STATUS.pop(name)

        time.sleep(CHECK_INTERVAL)


def send_alert(nodename: str):
    try:
        requests.post(BOT_ALERT_URL, json={
            "token": get_token(),
            "ip": get_ip_address(),
            "message": f"❌ Упала нода: {nodename}",
            "alert_id": f"{nodename}-{int(time.time())}"
        })
        print(f"🔔 Алерт по {nodename} отправлен")
    except Exception as e:
        print("Ошибка отправки алерта:", e)

@app.post("/ping")
async def ping(request: Request):
    data = await request.json()
    if data.get("token") != get_token():
        return JSONResponse(content={"error": "unauthorized"}, status_code=403)

    return {
        "system": get_system_stats(),
        "docker": get_docker_status(),
        "systemd": get_systemd_services(),
        "background": get_background_processes(),
        "nodes": get_installed_nodes()
    }

@app.post("/logs_services")
async def get_service_logs(request: Request):
    data = await request.json()
    if data.get("token") != get_token():
        return JSONResponse(content={"error": "unauthorized"}, status_code=403)

    service = data.get("service")
    if not service:
        return JSONResponse(content={"error": "missing service name"}, status_code=400)

    try:
        logs = subprocess.check_output(
            ["journalctl", "-u", service, "-n", "50", "--no-pager"],
            text=True
        )
        return PlainTextResponse(logs)
    except subprocess.CalledProcessError:
        return PlainTextResponse("⚠️ Не удалось получить логи", status_code=500)

@app.post("/update_token")
async def update_token(request: Request):
    data = await request.json()
    new_token = data.get("new_token")
    if not new_token:
        return {"status": "missing new_token"}
    with open("token.txt", "w") as f:
        f.write(new_token.strip())
    return {"status": "updated"}

@app.post("/nodes")
async def nodes_info(request: Request):
    data = await request.json()
    if data.get("token") != get_token():
        return JSONResponse(status_code=403, content={"error": "unauthorized"})

    nodes = get_installed_nodes()
    return {"nodes": nodes}

if __name__ == "__main__":
    threading.Thread(target=monitor_disk, daemon=True).start()
    threading.Thread(target=monitor_nodes, daemon=True).start()
    import uvicorn
    uvicorn.run("agent:app", host="0.0.0.0", port=8844)
EOF

    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install fastapi uvicorn psutil docker

    echo -e "${CLR_SUCCESS}✅ Agent установлен!${CLR_RESET}"
}

# === Сервис ===
function create_service() {
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Agent Monitor
After=network.target

[Service]
User=root
WorkingDirectory=$AGENT_DIR
ExecStart=$AGENT_DIR/venv/bin/uvicorn agent:app --host 0.0.0.0 --port=8844
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reexec
    systemctl daemon-reload
    echo -e "${CLR_SUCCESS}✅ Сервис создан!${CLR_RESET}"
}

function start_agent() {
    systemctl enable agent.service
    systemctl start agent.service
    echo -e "${CLR_SUCCESS}✅ Agent запущен!${CLR_RESET}"
}

function restart_agent() {
    systemctl restart agent.service
    echo -e "${CLR_SUCCESS}✅ Agent перезапущен!${CLR_RESET}"
}

function remove_agent() {
    read -p "⚠ Удалить агент полностью? (y/n): " CONFIRM
    if [[ "$CONFIRM" == "y" ]]; then
        systemctl stop agent.service
        systemctl disable agent.service
        rm -rf "$AGENT_DIR"
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        echo -e "${CLR_SUCCESS}✅ Агент удалён!${CLR_RESET}"
    else
        echo -e "${CLR_INFO}❎ Отмена удаления.${CLR_RESET}"
    fi
}

# === Меню ===
function show_menu() {
    show_logo
    echo -e "${CLR_GREEN}1) 📦 Установить зависимости${CLR_RESET}"
    echo -e "${CLR_GREEN}2) 🔑 Ввести токен доступа${CLR_RESET}"
    echo -e "${CLR_GREEN}3) ⚙️ Установить Agent и создать сервис${CLR_RESET}"
    echo -e "${CLR_GREEN}4) ▶️ Перезапустить Agent${CLR_RESET}"
    echo -e "${CLR_GREEN}5) 🗑 Удалить Agent${CLR_RESET}"
    echo -e "${CLR_GREEN}6) ❌ Выйти${CLR_RESET}"
    echo -en "${CLR_INFO}Введите номер действия:${CLR_RESET} "
    read -r choice
    case $choice in
        1) install_dependencies ;;
        2) set_token ;;
        3) install_agent && create_service && start_agent ;;
        4) restart_agent ;;
        5) remove_agent ;;
        6) echo -e "${CLR_ERROR}Выход...${CLR_RESET}" ;;
        *) echo -e "${CLR_WARNING}Неверный выбор. Попробуйте снова.${CLR_RESET}" && show_menu ;;
    esac
}

# === Запуск ===
show_menu
