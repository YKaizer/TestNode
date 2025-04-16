#!/bin/bash

# === Цвета ===
CLR_INFO='\\033[1;97;44m'
CLR_SUCCESS='\\033[1;30;42m'
CLR_WARNING='\\033[1;37;41m'
CLR_ERROR='\\033[1;31;40m'
CLR_GREEN='\\033[1;32m'
CLR_RESET='\\033[0m'

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
<СЮДА ПОДСТАВИМ agent.py позже>
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
