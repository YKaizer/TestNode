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
    echo -e "${CLR_INFO}     Добро пожаловать в скрипт установки ноды Ritual      ${CLR_RESET}"
    curl -s https://raw.githubusercontent.com/profitnoders/Profit_Nodes/refs/heads/main/logo_new.sh | bash
}

# Функция установки необходимых пакетов
function install_dependencies() {
    echo -e "${CLR_INFO}Обновляем систему и устанавливаем пакеты...${CLR_RESET}"
    sudo apt update -y
    sudo apt install -y git curl jq build-essential docker.io docker-compose nano
    echo -e "${CLR_INFO}Клонируем репозиторий Ritual...${CLR_RESET}"
    git clone https://github.com/ritual-net/infernet-container-starter.git
    cd infernet-container-starter
}

# Функция установки ноды Ritual
function install_node() {
    install_dependencies

    echo -e "${CLR_INFO}Клонируем репозиторий Ritual...${CLR_RESET}"
    git clone https://github.com/ritual-net/infernet-container-starter.git
    cd infernet-container-starter

    echo -e "${CLR_INFO}Настраиваем конфигурацию ноды...${CLR_RESET}"
    cp deploy/config.example.json deploy/config.json
    nano deploy/config.json

    echo -e "${CLR_INFO}Запускаем контейнер Ritual...${CLR_RESET}"
    screen -S ritual -dm bash -c "project=hello-world make deploy-container"

    echo -e "${CLR_SUCCESS}✅ Установка завершена! Нода запущена.${CLR_RESET}"
}

# Функция проверки статуса контейнера Ritual
function check_status() {
    echo -e "${CLR_INFO}Проверяем статус контейнера Ritual...${CLR_RESET}"
    docker ps | grep ritual || echo -e "${CLR_ERROR}Нода не запущена!${CLR_RESET}"
}

# Функция просмотра логов ноды
function view_logs() {
    echo -e "${CLR_INFO}Просмотр логов ноды Ritual...${CLR_RESET}"
    docker logs -f $(docker ps -q --filter "name=ritual")
}

# Функция обновления ноды Ritual
function update_node() {
    echo -e "${CLR_INFO}Обновляем ноду Ritual...${CLR_RESET}"
    cd ~/infernet-container-starter
    nano deploy/docker-compose.yaml
    docker-compose -f deploy/docker-compose.yaml down
    docker-compose -f deploy/docker-compose.yaml up -d
    echo -e "${CLR_SUCCESS}✅ Обновление завершено!${CLR_RESET}"
}

# Функция удаления ноды
function remove_node() {
    echo -e "${CLR_WARNING}Вы уверены, что хотите удалить ноду? (y/n)${CLR_RESET}"
    read -r CONFIRMATION
    if [[ "$CONFIRMATION" == "y" ]]; then
        docker-compose -f ~/infernet-container-starter/deploy/docker-compose.yaml down
        rm -rf ~/infernet-container-starter
        echo -e "${CLR_SUCCESS}✅ Нода удалена!${CLR_RESET}"
    else
        echo -e "${CLR_SUCCESS}Операция отменена.${CLR_RESET}"
    fi
}

# Главное меню
function show_menu() {
    show_logo
    echo -e "${CLR_INFO}Выберите действие:${CLR_RESET}"
    echo -e "${CLR_GREEN}1) 🚀 Установить ноду Ritual${CLR_RESET}"
    echo -e "${CLR_GREEN}2) 📊 Проверить статус ноды${CLR_RESET}"
    echo -e "${CLR_GREEN}3) 📖 Просмотреть логи ноды${CLR_RESET}"
    echo -e "${CLR_GREEN}4) 🔄 Обновить ноду Ritual${CLR_RESET}"
    echo -e "${CLR_ERROR}5) 🗑️ Удалить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}6) ❌ Выйти${CLR_RESET}"

    read -p "Введите номер действия: " choice

    case $choice in
        1) install_node ;;
        2) check_status ;;
        3) view_logs ;;
        4) update_node ;;
        5) remove_node ;;
        6) echo -e "${CLR_SUCCESS}Выход...${CLR_RESET}" && exit 0 ;;
        *) echo -e "${CLR_ERROR}Ошибка: Неверный выбор! Попробуйте снова.${CLR_RESET}" && show_menu ;;
    esac
}

# Запуск меню
show_menu
