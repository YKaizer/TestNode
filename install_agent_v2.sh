#!/bin/bash

AGENT_DIR="/root/agent"
TOKEN_FILE="$AGENT_DIR/token.txt"

CLR_INFO='\033[1;97;44m'
CLR_SUCCESS='\033[1;30;42m'
CLR_WARNING='\033[1;37;41m'
CLR_ERROR='\033[1;31;40m'
CLR_GREEN='\033[1;32m'
CLR_RESET='\033[0m'

function install_dependencies() {
    echo -e "${CLR_INFO}▶ Установка зависимостей...${CLR_RESET}"
    apt update && apt install -y python3 python3-venv python3-pip docker.io curl
}

function set_token() {
    read -p "🔑 Введите токен, полученный в боте: " TOKEN
    mkdir -p "$AGENT_DIR"
    echo "$TOKEN" > "$TOKEN_FILE"
    echo -e "${CLR_SUCCESS}✅ Токен сохранён в $TOKEN_FILE${CLR_RESET}"
}

function install_agent() {
    mkdir -p "$AGENT_DIR"
    cd "$AGENT_DIR" || exit

    echo "📄 Пишу agent.py..."

    cat > agent.py << 'EOF'
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import psutil, docker, subprocess, threading, time, requests, os, socket

def get_token():
    try:
        with open("token.txt") as f:
            return f.read().strip()
    except:
        return ""

AGENT_TOKEN = get_token()
app = FastAPI()

SERVICE_NAMES = ["initverse.service", "t3rn.service", "zgs.service", "cysic.service"]
PROCESS_KEYWORDS = ["./pop", "wasmedge", "dill-node", "./multiple-node"]

def get_ip_address():
    return socket.gethostbyname(socket.gethostname())

def get_system_stats():
    return {
        "cpu_percent": psutil.cpu_percent(interval=1),
        "memory": psutil.virtual_memory()._asdict(),
        "disk": psutil.disk_usage("/")._asdict()
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
    for name in SERVICE_NAMES:
        try:
            result = subprocess.check_output(["systemctl", "is-active", name], text=True).strip()
        except subprocess.CalledProcessError:
            result = "not found"
        statuses[name] = result
    return statuses

def get_background_processes():
    matched = {}
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            cmdline = " ".join(proc.info['cmdline'])
            for keyword in PROCESS_KEYWORDS:
                if keyword in cmdline:
                    matched[proc.info['pid']] = {
                        "name": proc.info['name'],
                        "cmd": cmdline
                    }
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return matched

ALERT_SENT = False
CHECK_INTERVAL = 60
BOT_ALERT_URL = "http://91.108.246.138:8080/alert"
COMPOSE_PATH = os.path.expanduser("~/infernet-container-starter/deploy/docker-compose.yaml")

def monitor_disk():
    global ALERT_SENT
    while True:
        disk = psutil.disk_usage("/")
        percent = disk.percent

        if percent >= 90 and not ALERT_SENT:
            try:
                requests.post(BOT_ALERT_URL, json={
                    "token": AGENT_TOKEN,
                    "ip": get_ip_address(),
                    "percent": percent,
                    "alert_id": f"{get_ip_address()}-{int(time.time())}"
                })
                os.system(f"docker-compose -f {COMPOSE_PATH} restart")
                ALERT_SENT = True
            except Exception as e:
                print("Ошибка отправки алерта:", e)
        elif percent < 88 and ALERT_SENT:
            ALERT_SENT = False

        time.sleep(CHECK_INTERVAL)

@app.post("/ping")
async def ping(request: Request):
    data = await request.json()
    if data.get("token") != AGENT_TOKEN:
        return JSONResponse(content={"error": "unauthorized"}, status_code=403)

    return {
        "system": get_system_stats(),
        "docker": get_docker_status(),
        "systemd": get_systemd_services(),
        "background": get_background_processes()
    }

if __name__ == "__main__":
    threading.Thread(target=monitor_disk, daemon=True).start()
    import uvicorn
    uvicorn.run("agent:app", host="0.0.0.0", port=8844)
EOF

    echo "📦 Установка зависимостей Python..."
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install fastapi uvicorn psutil docker

    echo "⚙️ Создаю systemd-сервис..."
    cat > /etc/systemd/system/agent.service << EOF
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
    echo -e "${CLR_SUCCESS}✅ Agent установлен!${CLR_RESET}"
}

function start_agent() {
    systemctl enable agent.service
    systemctl restart agent.service
    echo -e "${CLR_SUCCESS}✅ Agent запущен!${CLR_RESET}"
}

function remove_agent() {
    read -p "❗ Удалить агент полностью? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        systemctl stop agent.service
        systemctl disable agent.service
        rm -f /etc/systemd/system/agent.service
        rm -rf "$AGENT_DIR"
        systemctl daemon-reload
        echo -e "${CLR_SUCCESS}✅ Агент удалён.${CLR_RESET}"
    else
        echo -e "${CLR_INFO}❎ Отмена удаления.${CLR_RESET}"
    fi
}

function show_menu() {
    echo -e "${CLR_INFO}   Меню управления Agent Monitor   ${CLR_RESET}"
    echo -e "${CLR_GREEN}1) Установить зависимости${CLR_RESET}"
    echo -e "${CLR_GREEN}2) Ввести/обновить токен доступа${CLR_RESET}"
    echo -e "${CLR_GREEN}3) Установить и запустить агент${CLR_RESET}"
    echo -e "${CLR_GREEN}4) Удалить агент${CLR_RESET}"
    echo -e "${CLR_GREEN}5) Выйти${CLR_RESET}"
    read -p "Выберите действие: " choice
    case $choice in
        1) install_dependencies ;;
        2) set_token ;;
        3) install_agent && start_agent ;;
        4) remove_agent ;;
        5) echo -e "${CLR_ERROR}Выход...${CLR_RESET}" ;;
        *) echo -e "${CLR_WARNING}Неверный выбор.${CLR_RESET}" && show_menu ;;
    esac
}

show_menu
