#!/bin/bash

# Оформление текста: цвета и фоны
CLR_INFO='\033[1;97;44m'  
CLR_SUCCESS='\033[1;30;42m'  
CLR_WARNING='\033[1;37;41m'  
CLR_ERROR='\033[1;31;40m'  
CLR_RESET='\033[0m'  
CLR_GREEN='\033[0;32m' 

# Функция отображения логотипа
function show_logo() {
    echo -e "${CLR_INFO}     Добро пожаловать в скрипт установки ноды ZeroGravity      ${CLR_RESET}"
    curl -s https://raw.githubusercontent.com/profitnoders/Profit_Nodes/refs/heads/main/logo_new.sh | bash
}

# Функция установки необходимых пакетов
function install_dependencies() {
    echo -e "${CLR_INFO}Обновляем систему и устанавливаем пакеты...${CLR_RESET}"
    sudo apt update -y
    sudo apt install -y git nano jq curl clang cmake build-essential openssl pkg-config libssl-dev
}

# Функция установки Rust
function install_rust() {
    echo -e "${CLR_INFO}Устанавливаем Rust...${CLR_RESET}"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    sudo systemctl daemon-reexec
    rustup install 1.78.0
    rustup default 1.78.0
}

# Функция установки ноды ZeroGravity
function install_node() {
    install_dependencies
    install_rust

    echo -e "${CLR_INFO}Удаляем старую версию ноды...${CLR_RESET}"
    sudo systemctl stop zgs 2>/dev/null
    rm -rf $HOME/0g-storage-node

    echo -e "${CLR_INFO}Клонируем репозиторий...${CLR_RESET}"
    git clone -b v0.8.4 https://github.com/0glabs/0g-storage-node.git
    cd $HOME/0g-storage-node

    echo -e "${CLR_INFO}Скачиваем теги и обновляем подмодули...${CLR_RESET}"
    git stash
    git fetch --all --tags
    git checkout 40d4355
    git submodule update --init

    echo -e "${CLR_INFO}Компилируем ноду...${CLR_RESET}"
    cargo build --release

    echo -e "${CLR_INFO}Обновляем конфигурационный файл...${CLR_RESET}"
    rm -rf $HOME/0g-storage-node/run/config.toml
    curl -o $HOME/0g-storage-node/run/config.toml https://raw.githubusercontent.com/zstake-xyz/test/refs/heads/main/0g_storage_config.toml

    echo -e "${CLR_INFO}Создаем systemd сервис...${CLR_RESET}"
    sudo tee /etc/systemd/system/zgs.service > /dev/null <<EOF
[Unit]
Description=ZGS Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/0g-storage-node/run
ExecStart=$HOME/0g-storage-node/target/release/zgs_node --config $HOME/0g-storage-node/run/config.toml
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${CLR_INFO}Запускаем ноду...${CLR_RESET}"
    sudo systemctl daemon-reload
    sudo systemctl enable zgs
    sudo systemctl start zgs

    echo -e "${CLR_SUCCESS}✅ Установка завершена! Нода запущена.${CLR_RESET}"
}

# Функция вставки приватного ключа
function insert_private_key() {
    echo -e "${CLR_INFO}Введите ваш приватный ключ:${CLR_RESET}"
    read -r MINER_KEY

    CONFIG_FILE="$HOME/0g-storage-node/run/config.toml"

    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${CLR_INFO}Записываем приватный ключ...${CLR_RESET}"
        
        sed -i 's/# miner_key = "your key"/miner_key = "'"$MINER_KEY"'"/' "$CONFIG_FILE"
        sed -i 's/# log_config_file = "log_config"/log_config_file = "log_config"/' "$CONFIG_FILE"
        sed -i 's/# log_directory = "log"/log_directory = "log"/' "$CONFIG_FILE"
        
        echo -e "${CLR_SUCCESS}✅ Приватный ключ успешно вставлен!${CLR_RESET}"

        echo -e "${CLR_INFO}Перезапускаем ноду...${CLR_RESET}"
        sudo systemctl daemon-reload
        sudo systemctl restart zgs
        echo -e "${CLR_INFO}Нода перезапущена! Можете проверить статус и рост блоков!${CLR_RESET}"
    else
        echo -e "${CLR_ERROR}Ошибка: Файл конфигурации не найден!${CLR_RESET}"
    fi
}

# Функция проверки пиров и высоты логов
function check_peers() {
    echo -e "${CLR_INFO}Запуск мониторинга пиров и высоты логов...${CLR_RESET}"
    while true; do 
        response=$(curl -s -X POST http://localhost:5678 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}')
        logSyncHeight=$(echo $response | jq '.result.logSyncHeight')
        connectedPeers=$(echo $response | jq '.result.connectedPeers')
        echo -e "Block: \033[32m$logSyncHeight\033[0m, Peers: \033[34m$connectedPeers\033[0m"
        sleep 5
    done
}

# Функция перезапуска сервиса
function restart_service() {
    echo -e "${CLR_INFO}Перезапускаем сервис ноды ZeroGravity...${CLR_RESET}"
    sudo systemctl daemon-reload  # Перезагружаем systemd, чтобы он учел изменения в сервисе
    sudo systemctl restart zgs
}


# Функция проверки статуса ноды
function check_status() {
    echo -e "${CLR_INFO}Проверяем статус ноды ZeroGravity...${CLR_RESET}"
    sudo systemctl status zgs --no-pager
}

# Просмотр полных логов
function view_full_logs() {
    LOG_FILE="$HOME/0g-storage-node/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)"
    
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "${CLR_INFO}Просмотр полных логов ноды ZeroGravity...${CLR_RESET}"
        tail -f "$LOG_FILE"
    else
        echo -e "${CLR_ERROR}Ошибка: Файл логов не найден!${CLR_RESET}"
    fi
}

# Функция смены RPC
function change_rpc() {
    echo -e "${CLR_INFO}Выберите RPC для ноды:${CLR_RESET}"
    echo -e "${CLR_GREEN}1) https://16600.rpc.thirdweb.com/${CLR_RESET}"
    echo -e "${CLR_GREEN}2) https://og-testnet-evm.itrocket.net/${CLR_RESET}"
    echo -e "${CLR_GREEN}3) https://rpc.ankr.com/0g_newton${CLR_RESET}"
    echo -e "${CLR_GREEN}4) https://evmrpc-testnet.0g.ai/${CLR_RESET}"
    
    read -p "Введите номер RPC: " rpc_choice
    
    case $rpc_choice in
        1) RPC_URL="https://16600.rpc.thirdweb.com/" ;;
        2) RPC_URL="https://og-testnet-evm.itrocket.net/" ;;
        3) RPC_URL="https://rpc.ankr.com/0g_newton" ;;
        4) RPC_URL="https://evmrpc-testnet.0g.ai/" ;;
        *) echo -e "${CLR_ERROR}Ошибка: Неверный выбор!${CLR_RESET}" && return ;;
    esac

    CONFIG_FILE="$HOME/0g-storage-node/run/config.toml"

    sed -i "s|^blockchain_rpc_endpoint = .*|blockchain_rpc_endpoint = \"$RPC_URL\"|g" "$CONFIG_FILE"
    restart_service
}

# Функция удаления ноды с подтверждением
function remove_node() {
    echo -e "${CLR_WARNING}Вы уверены, что хотите удалить ноду? (y/n)${CLR_RESET}"
    read -r CONFIRMATION
    if [[ "$CONFIRMATION" == "y" ]]; then
        sudo systemctl stop zgs
        sudo systemctl disable zgs
        rm -rf $HOME/0g-storage-node
        sudo rm -rf /etc/systemd/system/zgs.service
        sudo systemctl daemon-reload
        echo -e "${CLR_SUCCESS}✅ Нода удалена!${CLR_RESET}"
    else
        echo -e "${CLR_SUCCESS}Операция отменена.${CLR_RESET}"
    fi
}

function update_node() {
    echo "Updating 0g-storage-node..."
    sudo systemctl stop zgs
    cp $HOME/0g-storage-node/run/config.toml $HOME/0g-storage-node/run/config.toml.backup
    cd $HOME/0g-storage-node
    git stash
    git fetch --all --tags
    git checkout be14ba6
    git submodule update --init
    cargo build --release
    cp $HOME/0g-storage-node/run/config.toml.backup $HOME/0g-storage-node/run/config.toml
    sudo systemctl daemon-reload
    sudo systemctl enable zgs
    sudo systemctl start zgs
    echo -e "${CLR_INFO}Нода успешно обновлена${CLR_RESET}"
}

# Главное меню
function show_menu() {
    show_logo
    echo -e "${CLR_INFO}Выберите действие:${CLR_RESET}"
    echo -e "${CLR_GREEN}1) 🚀 Установить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}2) 🔍 Проверить высоту логов и пиров${CLR_RESET}"
    echo -e "${CLR_GREEN}3) 🔑 Вставить приватный ключ${CLR_RESET}"
    echo -e "${CLR_GREEN}4) 🔄 Перезапустить сервис${CLR_RESET}"
    echo -e "${CLR_GREEN}5) 📊 Проверить статус ноды${CLR_RESET}"
    echo -e "${CLR_GREEN}6) 📖 Просмотр полных логов${CLR_RESET}"
    echo -e "${CLR_GREEN}7) 🔄 Сменить RPC в конфиге${CLR_RESET}"
    echo -e "${CLR_ERROR}8) 🗑️ Удалить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}9) 💽 Обновить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}10) ❌ Выйти${CLR_RESET}"

    read -p "Введите номер действия: " choice

    case $choice in
        1) install_node ;;
        2) check_peers ;;
        3) insert_private_key ;;
        4) restart_service ;;
        5) check_status ;;
        6) view_full_logs ;;
        7) change_rpc ;;
        8) remove_node ;;
        9) update_node ;;
        10) echo -e "${CLR_SUCCESS}Выход...${CLR_RESET}" && exit 0 ;;
        *) echo -e "${CLR_ERROR}Ошибка: Неверный выбор! Попробуйте снова.${CLR_RESET}" && show_menu ;;
    esac
}

# Запуск меню
show_menu

