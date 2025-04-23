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
import psutil, docker, subprocess, threading, time, requests, os, socket, sqlite3
from fastapi.responses import PlainTextResponse

app = FastAPI()
CHECK_INTERVAL = 60
ALERTS_ENABLED = True
BOT_ALERT_URL = "http://91.108.246.138:8080/alert"
ALERT_DB_PATH = os.path.join(os.path.dirname(__file__), "alerts.db")
COMPOSE_PATH = os.path.expanduser("~/infernet-container-starter/deploy/docker-compose.yaml")

# === Ноды ===
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

# === Вспомогательные ===
def get_token():
    try:
        with open("token.txt") as f:
            return f.read().strip()
    except:
        return ""

def get_ip_address():
    return socket.gethostbyname(socket.gethostname())

# === SQLite ===
def init_alert_db():
    with sqlite3.connect(ALERT_DB_PATH) as conn:
        # Таблица алертов по нодам
        conn.execute("""
            CREATE TABLE IF NOT EXISTS alerts (
                name TEXT PRIMARY KEY,
                active INTEGER DEFAULT 0,
                last_alert INTEGER DEFAULT 0
            )
        """)
        # Новая таблица настроек
        conn.execute("""
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """)
        # Вставка по умолчанию (если нет)
        conn.execute("""
            INSERT OR IGNORE INTO settings (key, value) VALUES ('alerts_enabled', '1')
        """)

def load_alerts_enabled():
    global ALERTS_ENABLED
    try:
        with sqlite3.connect(ALERT_DB_PATH) as conn:
            cursor = conn.execute("SELECT value FROM settings WHERE key = 'alerts_enabled'")
            row = cursor.fetchone()
            ALERTS_ENABLED = row and row[0] == '1'
    except:
        ALERTS_ENABLED = True

def save_alerts_enabled(flag: bool):
    with sqlite3.connect(ALERT_DB_PATH) as conn:
        conn.execute("""
            INSERT INTO settings (key, value)
            VALUES ('alerts_enabled', ?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value
        """, ('1' if flag else '0',))

def was_already_reported(name: str) -> bool:
    with sqlite3.connect(ALERT_DB_PATH) as conn:
        cur = conn.execute("SELECT active FROM alerts WHERE name = ?", (name,))
        row = cur.fetchone()
        return row and row[0] == 1

def mark_alert(name: str, status: bool):
    now = int(time.time())
    with sqlite3.connect(ALERT_DB_PATH) as conn:
        conn.execute("""
            INSERT INTO alerts (name, active, last_alert)
            VALUES (?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET active=excluded.active, last_alert=excluded.last_alert
        """, (name, int(status), now if status else 0))

# === Stats ===

def get_system_stats():
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")  # Только root

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

# === Мониторинг ===
def send_alert(name: str, custom_message: str = None):
    try:
        payload = {
            "token": get_token(),
            "ip": get_ip_address(),
            "alert_id": f"{name}-{int(time.time())}",
            "message": custom_message or f"❌ Упала нода: {name}"
        }
        requests.post(BOT_ALERT_URL, json=payload)
        print(f"🔔 Алерт отправлен: {name}")
    except Exception as e:
        print("Ошибка отправки алерта:", e)

def monitor_nodes():
    while True:
        failed = []

        for name, service in NODE_SYSTEMD.items():
            try:
                if subprocess.check_output(["systemctl", "is-active", service], text=True).strip() != "active":
                    failed.append(name)
            except:
                failed.append(name)

        try:
            client = docker.from_env()
            running = {c.name for c in client.containers.list()}
            for name, expected in NODE_DOCKER_CONTAINERS.items():
                if not expected.issubset(running):
                    failed.append(name)
            for name, img in NODE_DOCKER_IMAGES.items():
                if not any(img in (tag or "") for c in client.containers.list() for tag in c.image.tags):
                    failed.append(name)
        except:
            pass

        active = set()
        for p in psutil.process_iter(['cmdline']):
            try:
                cmd = " ".join(p.info['cmdline'])
                for name, pattern in NODE_PROCESSES.items():
                    if pattern in cmd:
                        active.add(name)
            except:
                continue
        for name in NODE_PROCESSES:
            if name not in active:
                failed.append(name)

        try:
            out = subprocess.check_output(["screen", "-ls"], text=True)
            for name, session in NODE_SCREENS.items():
                if session not in out:
                    failed.append(name)
        except:
            failed += list(NODE_SCREENS)

        all_nodes = set(NODE_SYSTEMD) | set(NODE_PROCESSES) | set(NODE_SCREENS) | set(NODE_DOCKER_CONTAINERS) | set(NODE_DOCKER_IMAGES)

        for name in failed:
            if not was_already_reported(name):
                send_alert(name)
                mark_alert(name, True)

        for name in all_nodes:
            if name not in failed:
                mark_alert(name, False)

        time.sleep(CHECK_INTERVAL)

def monitor_disk():
    global ALERT_SENT
    while True:
        disk = psutil.disk_usage("/")
        percent = disk.percent

        # ⚠️ Проверка наличия ноды Ritual
        ritual_detected = False
        try:
            client = docker.from_env()
            containers = {c.name for c in client.containers.list()}
            ritual_containers = {"hello-world", "infernet-node", "infernet-anvil", "infernet-fluentbit", "infernet-redis"}
            ritual_detected = len(ritual_containers & containers) >= 3
        except Exception as e:
            print("Ошибка проверки Docker:", e)

        # 🔁 Перезапуск Ritual если диск > 80%
        if ritual_detected and percent > 80:
            try:
                print("📦 Диск > 80% и Ritual найден — перезапуск...")

                # Остановка docker-compose
                down_result = subprocess.call(["docker-compose", "-f", COMPOSE_PATH, "down"])

                # Завершение всех screen-сессий с именем 'ritual'
                subprocess.call("for s in $(screen -ls | grep ritual | awk '{print $1}'); do screen -S $s -X quit; done", shell=True)

                # Запуск docker-compose в новой screen-сессии
                up_result = subprocess.call(
                    ["screen", "-dmS", "ritual", "bash", "-c", f"docker-compose -f {COMPOSE_PATH} up"]
                )

                if down_result == 0 and up_result == 0:
                    print("✅ Ritual перезапущен успешно.")
                else:
                    print("⚠️ Перезапуск Ritual завершился с ошибками.")

            except Exception as e:
                print("❌ Ошибка перезапуска Ritual:", e)

        # 🔔 Алерт по диску
        if percent >= 80 and not ALERT_SENT:
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

        elif percent < 78 and ALERT_SENT:
            ALERT_SENT = False

        time.sleep(CHECK_INTERVAL)


# === Эндпоинты ===
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

from fastapi.responses import PlainTextResponse

@app.post("/logs_docker")
async def get_docker_logs(request: Request):
    data = await request.json()
    if data.get("token") != get_token():
        return JSONResponse(content={"error": "unauthorized"}, status_code=403)

    container = data.get("container")
    if not container:
        return JSONResponse(content={"error": "missing container name"}, status_code=400)

    try:
        logs = subprocess.check_output(
            ["docker", "logs", "--tail", "50", container],
            text=True,
            stderr=subprocess.STDOUT
        )
        return PlainTextResponse(logs)
    except subprocess.CalledProcessError:
        return PlainTextResponse(f"⚠️ Не удалось получить логи контейнера `{container}`", status_code=500)

@app.post("/set_alert_mode")
async def set_alert_mode(request: Request):
    global ALERTS_ENABLED
    data = await request.json()
    enabled = data.get("enabled", True)
    ALERTS_ENABLED = bool(enabled)
    save_alerts_enabled(ALERTS_ENABLED)
    print(f"Уведомления об упавших нодах [FALL ALERTS MODE] updated: {'ENABLED ✅' if ALERTS_ENABLED else 'DISABLED ❌'}")
    return {"status": "ok", "alerts_enabled": ALERTS_ENABLED}

@app.post("/restart_ritual")
async def restart_ritual_endpoint(request: Request):
    data = await request.json()
    if data.get("token") != get_token():
        return JSONResponse(status_code=403, content={"error": "unauthorized"})

    try:
        down_result = subprocess.call(["docker-compose", "-f", COMPOSE_PATH, "down"])
        subprocess.call("for s in $(screen -ls | grep ritual | awk '{print $1}'); do screen -S $s -X quit; done", shell=True)
        up_result = subprocess.call(["screen", "-dmS", "ritual", "bash", "-c", f"docker-compose -f {COMPOSE_PATH} up"])

        if down_result == 0 and up_result == 0:
            return {"status": "ok", "message": "Ritual успешно перезапущен"}
        else:
            return {"status": "fail", "message": "Ошибка при перезапуске docker-compose"}

    except Exception as e:
        return {"status": "fail", "message": f"❌ Исключение: {e}"}


# === Запуск ===
if __name__ == "__main__":
    init_alert_db()
    load_alerts_enabled()
    threading.Thread(target=monitor_nodes, daemon=True).start()
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
