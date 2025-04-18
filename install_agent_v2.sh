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
from fastapi.responses import JSONResponse
import psutil, docker, subprocess, threading, time, requests, os, socket
from fastapi.responses import PlainTextResponse

app = FastAPI()

# === Настройки ===
SERVICE_NAMES = [
    "initverse.service", "t3rn.service", "zgs.service", "cysic.service"
]
PROCESS_KEYWORDS = [
    "./pop", "wasmedge", "dill-node",
    "python -m hivemind_exp.gsm8k.train_single_gpu",
    "./multiple-node"
]
COMPOSE_PATH = os.path.expanduser("~/infernet-container-starter/deploy/docker-compose.yaml")
BOT_ALERT_URL = "http://91.108.246.138:8080/alert"  # ЗАМЕНИ на IP бота
ALERT_SENT = False
CHECK_INTERVAL = 60  # в секундах

# === Функции ===

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

def restart_in_screen():
    screen_name = "ritual"
    try:
        print("📦 Останавливаю docker-compose...")
        subprocess.call(["docker-compose", "-f", COMPOSE_PATH, "down"])
        print("🧼 Завершаю все screen-сессии 'ritual'...")
        subprocess.call("for s in $(screen -ls | grep ritual | awk '{print $1}'); do screen -S $s -X quit; done", shell=True)
        print("🚀 Запускаю в новом screen...")
        subprocess.call(["screen", "-dmS", screen_name, "bash", "-c", f"docker-compose -f {COMPOSE_PATH} up"])
    except Exception as e:
        print(f"❌ Ошибка при перезапуске в screen: {e}")

# === Фоновый мониторинг диска ===

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
                restart_in_screen()
                ALERT_SENT = True
            except Exception as e:
                print("Ошибка отправки алерта:", e)

        elif percent < 88 and ALERT_SENT:
            ALERT_SENT = False

        time.sleep(CHECK_INTERVAL)

# === Эндпоинты ===

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

@app.post("/ping")
async def ping(request: Request):
    data = await request.json()
    if data.get("token") != get_token():
        return JSONResponse(content={"error": "unauthorized"}, status_code=403)

    return {
        "system": get_system_stats(),
        "docker": get_docker_status(),
        "systemd": get_systemd_services(),
        "background": get_background_processes()
    }

@app.post("/update_token")
async def update_token(request: Request):
    data = await request.json()
    new_token = data.get("new_token")
    if not new_token:
        return {"status": "missing new_token"}
    with open("token.txt", "w") as f:
        f.write(new_token.strip())
    return {"status": "updated"}

# === Запуск ===

if __name__ == "__main__":
    threading.Thread(target=monitor_disk, daemon=True).start()
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
