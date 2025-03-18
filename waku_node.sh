#!/bin/bash

# Оформление текста: цвета и фоны
CLR_INFO='\033[1;97;44m'  # Белый текст на синем фоне
CLR_SUCCESS='\033[1;30;42m'  # Зеленый текст на черном фоне
CLR_WARNING='\033[1;37;41m'  # Белый текст на красном фоне
CLR_ERROR='\033[1;31;40m'  # Красный текст на черном фоне
CLR_RESET='\033[0m'  # Сброс форматирования
CLR_GREEN='\033[0;32m' #Зеленый текст

# Функция отображения логотипа
function show_logo() {
    echo -e "${CLR_INFO}        Добро пожаловать в скрипт управления нодой Waku        ${CLR_RESET}"
    curl -s https://raw.githubusercontent.com/profitnoders/Profit_Nodes/refs/heads/main/logo_new.sh | bash
}

# Функция установки необходимых пакетов
function install_dependencies() {
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install -y curl iptables build-essential git wget jq make gcc nano tmux htop \
        nvme-cli pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip
    # Проверка и установка curl, если он отсутствует
    if ! command -v curl &> /dev/null; then
        sudo apt update
        sudo apt install curl -y
    fi
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sh
    fi

    if ! command -v docker-compose &> /dev/null; then
        sudo apt update && sudo apt install -y docker-compose
        command -v docker-compose &> /dev/null && echo -e "${CLR_INFO}Docker Compose успешно установлен!${CLR_RESET}" || { echo -e "\033[1;31;40mОшибка установки.${CLR_RESET}"; exit 1; }
    fi 
}

# Установка ноды Waku
function install_node() {
    install_dependencies
    install_docker

    cd $HOME
    git clone https://github.com/waku-org/nwaku-compose
    cd nwaku-compose
    cp .env.example .env

    echo -e "${CLR_INFO}Вставьте ваш RPC Sepolia ETH:${CLR_RESET}"
    read RPC
    
    echo -e "${CLR_INFO}\nВставьте ваш приватный ключ от EVM кошелька, на котором есть Sepolia ETH:${CLR_RESET}"
    read PRIVATE_KEY
    
    echo -e "${CLR_INFO}\nУстановите пароль:${CLR_RESET}"
    read PASSWORD


    sed -i "s|RLN_RELAY_ETH_CLIENT_ADDRESS=.*|RLN_RELAY_ETH_CLIENT_ADDRESS=$RPC|" .env
    sed -i "s|ETH_TESTNET_KEY=.*|ETH_TESTNET_KEY=$PRIVATE_KEY|" .env
    sed -i "s|RLN_RELAY_CRED_PASSWORD=.*|RLN_RELAY_CRED_PASSWORD=$PASSWORD|" .env

    ./register_rln.sh

    echo -e "${CLR_INFO}\nЗаменяем порты 5432 -> 5433; 80 -> 81; 8003 -> 8033...${CLR_RESET}"
    echo -e "${CLR_INFO}\nПроверяем наличие файла $HOME/nwaku-compose/docker-compose.yml...${CLR_RESET}"
    if [[ -s "$HOME/nwaku-compose/docker-compose.yml" ]]; then
        echo -e "${CLR_SUCCESS}Файл найден, продолжаем замену портов...${CLR_RESET}"
        sed -i 's/5432/5433/g' "$HOME/nwaku-compose/docker-compose.yml"
        sed -i 's/80:80/81:80/g' "$HOME/nwaku-compose/docker-compose.yml"
        sed -i 's/8003:8003/8033:8003/g' "$HOME/nwaku-compose/docker-compose.yml"
        echo -e "${CLR_SUCCESS}Замена портов выполнена успешно.${CLR_RESET}"
    else
        echo -e "${CLR_ERROR}Ошибка: Файл $HOME/nwaku-compose/docker-compose.yml отсутствует или пуст.${CLR_RESET}"
        exit 1
    fi
    
    docker-compose up -d
}

# Обновление ноды Waku
function update_node() {
    cd $HOME/nwaku-compose
    docker-compose down
    git pull origin master
    docker-compose up -d

    echo -e "${CLR_INFO}Обновление завершено!${CLR_RESET}"
}

# Просмотр логов ноды (последние 300 строк + live)
function view_logs() {
    echo -e "${CLR_INFO}Просмотр логов ноды Waku...${CLR_RESET}"
    cd $HOME/nwaku-compose && docker-compose logs --tail=300 -f
}

# Функция изменения NWAKU_IMAGE
function change_nwaku_image() {
    if [[ -s "$HOME/nwaku-compose/.env" ]]; then
        # Проверяем текущее значение NWAKU_IMAGE
        CURRENT_IMAGE=$(grep "^NWAKU_IMAGE=" "$HOME/nwaku-compose/.env" | cut -d'=' -f2)
        
        if [[ -n "$CURRENT_IMAGE" ]]; then
            echo -e "${CLR_WARNING}Внимание: NWAKU_IMAGE уже задан как '$CURRENT_IMAGE'.${CLR_RESET}"
            echo -e "${CLR_INFO}Вы уверены, что хотите изменить его? (y/n)${CLR_RESET}"
            read -r CONFIRM
            if [[ "$CONFIRM" != "y" ]]; then
                echo -e "${CLR_INFO}Отмена изменения NWAKU_IMAGE.${CLR_RESET}"
                return
            fi
        fi

        echo -e "${CLR_INFO}Введите новую версию NWAKU_IMAGE (пример: wakuorg/nwaku:v0.35.0):${CLR_RESET}"
        read -r NEW_IMAGE

        if [[ -z "$NEW_IMAGE" ]]; then
            echo -e "${CLR_ERROR}Ошибка: Вы не ввели значение. Попробуйте снова.${CLR_RESET}"
            return
        fi

        sed -i "/^NWAKU_IMAGE=/c\NWAKU_IMAGE=$NEW_IMAGE" "$HOME/nwaku-compose/.env"
        echo -e "${CLR_SUCCESS}NWAKU_IMAGE успешно изменен на $NEW_IMAGE${CLR_RESET}"
    else
        echo -e "${CLR_ERROR}Ошибка: Файл $HOME/nwaku-compose/.env отсутствует или пуст.${CLR_RESET}"
    fi
}

# Перезапуск docker-compose
function restart_docker_compose() {
    echo -e "${CLR_INFO}Перезапуск docker-compose...${CLR_RESET}"
    cd $HOME/nwaku-compose || { echo -e "${CLR_ERROR}Ошибка: Директория $HOME/nwaku-compose не найдена.${CLR_RESET}"; return; }
    docker-compose down
    docker-compose up -d
    echo -e "${CLR_SUCCESS}docker-compose успешно перезапущен.${CLR_RESET}"
}

# Проверка запущенных контейнеров
function check_docker_containers() {
    echo -e "${CLR_INFO}Список запущенных контейнеров:${CLR_RESET}"
    docker ps --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

}

# Проверка состояния ноды Waku
function check_node_health() {
    echo -e "${CLR_INFO}🔍 Запуск проверки состояния ноды...${CLR_RESET}"
    cd $HOME/nwaku-compose || { echo -e "${CLR_ERROR}❌ Ошибка: Директория $HOME/waku не найдена.${CLR_RESET}"; return; }
    ./chkhealth.sh
    echo -e "${CLR_INFO}🔍 Если вы видите "nodeHealth": "Ready" и "Rln Relay": "Ready", значит ваша нода работает стабильно${CLR_RESET}"
    echo -e "${CLR_INFO}🔍 Если вы видите "nodeHealth": "Initializing", значит необходимо еще подождать прежде чем вводить эту команду снова!${CLR_RESET}"
}

# Удаление ноды Waku с подтверждением
function remove_node() {
    echo -e "${CLR_WARNING}Внимание: Это действие удалит ноду Waku и все связанные файлы!${CLR_RESET}"
    echo -e "${CLR_INFO}Вы уверены, что хотите продолжить? (y/n)${CLR_RESET}"
    read -r CONFIRM

    if [[ "$CONFIRM" != "y" ]]; then
        echo -e "${CLR_INFO}Удаление отменено.${CLR_RESET}"
        return
    fi

    cd $HOME/nwaku-compose || { echo -e "${CLR_ERROR}Ошибка: Директория $HOME/nwaku-compose не найдена.${CLR_RESET}"; return; }
    docker-compose down
    cd $HOME
    rm -rf nwaku-compose
    rm -rf waku_node.sh

    echo -e "${CLR_SUCCESS}Нода успешно удалена!${CLR_RESET}"
}


# Главное меню
function show_menu() {
    show_logo
    echo -e "${CLR_GREEN} 1)🚀 Установить ноду ${CLR_RESET}"
    echo -e "${CLR_GREEN} 2)📜 Просмотр логов ${CLR_RESET}"
    echo -e "${CLR_GREEN} 3)🔄 Обновить ноду ${CLR_RESET}"
    echo -e "${CLR_GREEN} 4)🔄 Перезапустить ноду ${CLR_RESET}"
    echo -e "${CLR_GREEN} 5)🛠  Изменить NWAKU_IMAGE ${CLR_RESET}"
    echo -e "${CLR_GREEN} 6)🔍 Проверить запущенные контейнеры ${CLR_RESET}"
    echo -e "${CLR_GREEN} 7)🩺 Проверить ноду (chkhealth.sh) ${CLR_RESET}"
    echo -e "${CLR_ERROR} 8)🗑  Удалить ноду ${CLR_RESET}"
    echo -e "${CLR_GREEN} 9)❌ Выйти ${CLR_RESET}"

    echo -e "${CLR_INFO}Выберите действие:${CLR_RESET}"
    read choice

    case $choice in
        1) install_node ;;
        2) view_logs ;;
        3) update_node ;;
        4) restart_docker_compose ;;
        5) change_nwaku_image ;;
        6) check_docker_containers ;;
        7) check_node_health ;;
        8) remove_node ;;
        8) echo -e "${CLR_INFO}Выход...${CLR_RESET}" && exit 0 ;;
        *) echo -e "${CLR_INFO}Неверный выбор! Попробуйте снова.${CLR_RESET}" && show_menu ;;
    esac
}

# Запуск меню
show_menu
