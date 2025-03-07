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

# Функция вставки приватного ключа
function insert_private_key() {
    echo -e "${CLR_INFO}Введите ваш приватный ключ:${CLR_RESET}"
    read -r MINER_KEY

    CONFIG_FILE="$HOME/0g-storage-node/run/config.toml"

    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${CLR_INFO}Записываем приватный ключ...${CLR_RESET}"
        sed -i 's/# miner_key = "your key"/miner_key = "'"$MINER_KEY"'"/' "$CONFIG_FILE"

        echo -e "${CLR_SUCCESS}✅ Приватный ключ успешно вставлен!${CLR_RESET}"

        echo -e "${CLR_INFO}Перезапускаем ноду...${CLR_RESET}"
        sudo systemctl restart zgs
    else
        echo -e "${CLR_ERROR}Ошибка: Файл конфигурации не найден!${CLR_RESET}"
    fi
}

# Функция удаления ноды с подтверждением
function remove_node() {
    echo -e "${CLR_WARNING}Вы уверены, что хотите удалить ноду? (y/n)${CLR_RESET}"
    read -r CONFIRMATION
    if [[ "$CONFIRMATION" == "y" ]]; then
        echo -e "${CLR_ERROR}Останавливаем и удаляем ноду ZeroGravity...${CLR_RESET}"
        sudo systemctl stop zgs 2>/dev/null
        sudo systemctl disable zgs 2>/dev/null
        rm -rf $HOME/0g-storage-node
        sudo rm -rf /etc/systemd/system/zgs.service
        sudo systemctl daemon-reload
        echo -e "${CLR_SUCCESS}✅ Нода успешно удалена!${CLR_RESET}"
    else
        echo -e "${CLR_SUCCESS}Операция отменена.${CLR_RESET}"
    fi
}

# Главное меню
function show_menu() {
    show_logo
    echo -e "${CLR_INFO}Выберите действие:${CLR_RESET}"
    echo -e "${CLR_GREEN}1) 🚀 Установить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}2) 🔍 Проверить высоту логов и пиров${CLR_RESET}"
    echo -e "${CLR_GREEN}3) 🔑 Вставить приватный ключ${CLR_RESET}"
    echo -e "${CLR_GREEN}4) 📜 Просмотр логов${CLR_RESET}"
    echo -e "${CLR_GREEN}5) 🔄 Перезапустить сервис и проверить статус${CLR_RESET}"
    echo -e "${CLR_GREEN}6) 📖 Просмотр полных логов${CLR_RESET}"
    echo -e "${CLR_GREEN}7) 🔄 Сменить RPC в конфиге${CLR_RESET}"
    echo -e "${CLR_ERROR}8) 🗑️ Удалить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}9) ❌ Выйти${CLR_RESET}"

    read -p "Введите номер действия: " choice

    case $choice in
        1) install_node ;;
        2) check_peers ;;
        3) insert_private_key ;;
        4) check_logs ;;
        5) restart_service ;;
        6) view_full_logs ;;
        7) change_rpc ;;
        8) remove_node ;;
        9) echo -e "${CLR_SUCCESS}Выход...${CLR_RESET}" && exit 0 ;;
        *) echo -e "${CLR_ERROR}Ошибка: Неверный выбор! Попробуйте снова.${CLR_RESET}" && show_menu ;;
    esac
}

# Запуск меню
show_menu
