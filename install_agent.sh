#!/bin/bash

# === Цвета ===
CLR_INFO='\033[1;97;44m'
CLR_SUCCESS='\033[1;30;42m'
CLR_WARNING='\033[1;37;41m'
CLR_ERROR='\033[1;31;40m'
CLR_GREEN='\033[1;32m'
CLR_RESET='\033[0m'

# === Логотип ===
function show_logo() {
    echo -e "${CLR_INFO}   Добро пожаловать в установщик Agent Monitor   ${CLR_RESET}"
    curl -s https://raw.githubusercontent.com/profitnoders/Profit_Nodes/refs/heads/main/logo_new.sh | bash
}

# === Установка Agent ===
function install_agent() {
    echo -e "${CLR_INFO}▶ Установка агента...${CLR_RESET}"
    mkdir -p /root/agent
    cd /root/agent || exit

    # Создание agent.py
    cat > agent.py << 'EOF'
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import psutil, docker, subprocess

app = FastAPI()
SERVICE_NAMES = ["initverse.service", "t3rn.service", "zgs.service", "cysic.service"]
PROCESS_KEYWORDS = ["./pop", "wasmedge", "dill-node"]

def get_token():
    try:
        with open("token.txt") as f:
            return f.read().strip()
    except:
        return ""

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
EOF

    # Python окружение и зависимости
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install fastapi uvicorn psutil docker

    echo -e "${CLR_SUCCESS}✅ Agent установлен!${CLR_RESET}"
}

# === Ввод токена ===
function set_token() {
    read -p "Введите токен для доступа: " TOKEN
    echo "$TOKEN" > /root/agent/token.txt
    echo -e "${CLR_SUCCESS}✅ Токен сохранён!${CLR_RESET}"
}

# === systemd ===
function create_service() {
    echo -e "${CLR_INFO}▶ Создание systemd-сервиса...${CLR_RESET}"
    cat > /etc/systemd/system/agent.service << EOF
[Unit]
Description=Agent Monitor
After=network.target

[Service]
User=root
WorkingDirectory=/root/agent
ExecStart=/root/agent/venv/bin/uvicorn agent:app --host 0.0.0.0 --port=8844
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
        rm -rf /root/agent
        rm -f /etc/systemd/system/agent.service
        systemctl daemon-reload
        echo -e "${CLR_SUCCESS}✅ Agent удалён!${CLR_RESET}"
    else
        echo -e "${CLR_INFO}❎ Отмена удаления.${CLR_RESET}"
    fi
}

# === Меню ===
function show_menu() {
    show_logo
    echo -e "${CLR_GREEN}1) 🧱 Установка Agent${CLR_RESET}"
    echo -e "${CLR_GREEN}2) 🔑 Внести токен доступа${CLR_RESET}"
    echo -e "${CLR_GREEN}3) ▶️ Запустить Agent как сервис${CLR_RESET}"
    echo -e "${CLR_GREEN}4) ♻️ Перезапустить сервис${CLR_RESET}"
    echo -e "${CLR_GREEN}5) 🗑 Удалить Agent${CLR_RESET}"
    echo -e "${CLR_GREEN}6) ❌ Выйти${CLR_RESET}"
    echo -e "${CLR_INFO}Введите номер действия:${CLR_RESET}"
    read -r choice
    case $choice in
        1) install_agent ;;
        2) set_token ;;
        3) create_service && start_agent ;;
        4) restart_agent ;;
        5) remove_agent ;;
        6) echo -e "${CLR_ERROR}Выход...${CLR_RESET}" ;;
        *) echo -e "${CLR_WARNING}Неверный выбор. Попробуйте снова.${CLR_RESET}" && show_menu ;;
    esac
}

# === Запуск меню ===
show_menu
