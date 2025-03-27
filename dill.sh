#!/bin/bash

# Оформление текста
CLR_INFO='\033[1;97;44m'
CLR_SUCCESS='\033[1;30;42m'
CLR_WARNING='\033[1;37;41m'
CLR_ERROR='\033[1;31;40m'
CLR_RESET='\033[0m'
CLR_GREEN='\033[0;32m'

# Переменные
DILL_VERSION="v1.0.4"
DILL_DIR="$HOME/dill"
DILL_LINUX_AMD64_URL="https://dill-release.s3.ap-southeast-1.amazonaws.com/$DILL_VERSION/dill-$DILL_VERSION-linux-amd64.tar.gz"

# Логотип
function show_logo() {
    echo -e "${CLR_INFO}      Добро пожаловать в скрипт управления нодами Dill      ${CLR_RESET}"
    curl -s https://raw.githubusercontent.com/profitnoders/Profit_Nodes/refs/heads/main/logo_new.sh | bash
}

# Зависимости
function install_dependencies() {
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl tar lsof
}


function install_node() {
    install_dependencies

    echo -e "${CLR_INFO}Скачиваем и устанавливаем Dill Node...${CLR_RESET}"
    mkdir -p "$DILL_DIR"
    cd "$DILL_DIR" || exit 1

    curl -O "$DILL_LINUX_AMD64_URL"
    tar -zxvf "dill-$DILL_VERSION-linux-amd64.tar.gz"

    # Если файлы внутри папки dill — переместим
    if [ -d "$DILL_DIR/dill" ]; then
        mv dill/* .
        rm -rf dill
    fi

    echo -e "${CLR_SUCCESS}Установка завершена!${CLR_RESET}"

    # Заменим дефолтные порты
    sed -i 's/8545/8546/g' default_ports.txt
    sed -i 's/4000/4050/g' default_ports.txt

    echo -e "${CLR_SUCCESS}Кастомные порты применены${CLR_RESET}"

    echo -e "${CLR_INFO}Запускаем ноду через 1_launch_dill_node.sh...${CLR_RESET}"
    bash "$DILL_DIR/1_launch_dill_node.sh"
}





# Добавить валидатора
function add_validator() {
    echo -e "${CLR_INFO}Добавляем валидатора...${CLR_RESET}"
    bash "$DILL_DIR/2_add_validator.sh"
}

# Перезапуск
function restart_node() {
    echo -e "${CLR_INFO}Перезапускаем Dill ноду...${CLR_RESET}"
    
    # Завершаем работающий процесс dill-node, если он есть
    if pgrep -f dill-node > /dev/null; then
        echo -e "${CLR_INFO}Останавливаем текущий процесс dill-node...${CLR_RESET}"
        pkill -f dill-node
        sleep 2
    fi

    # Запуск
    echo -e "${CLR_INFO}Запускаем ноду заново...${CLR_RESET}"
    bash "$DILL_DIR/start_dill_node.sh"

    echo -e "${CLR_SUCCESS}Нода успешно перезапущена!${CLR_RESET}"
}


# Функция отображения всех аккаунтов через accounts list
function show_pubkeys() {
    echo -e "${CLR_INFO}Список валидаторов через accounts list:${CLR_RESET}"
    if [ -f "$DILL_DIR/dill-node" ]; then
        "$DILL_DIR/dill-node" accounts list \
            --wallet-dir "$DILL_DIR/keystore" \
            --wallet-password-file "$DILL_DIR/validator_keys/keystore_password.txt"
    else
        echo -e "${CLR_WARNING}dill-node не найден. Возможно, нода не установлена.${CLR_RESET}"
    fi
}


# Проверка состояния ноды (health check)
function check_node_status() {
    if [ -f "$DILL_DIR/health_check.sh" ]; then
        echo -e "${CLR_INFO}Запуск проверки состояния ноды...${CLR_RESET}"
        bash "$DILL_DIR/health_check.sh" -v
    else
        echo -e "${CLR_WARNING}Скрипт health_check.sh не найден.${CLR_RESET}"
    fi
}


function remove_node() {
    echo -e "${CLR_WARNING}Вы уверены, что хотите удалить ноду? (y/n)${CLR_RESET}"
    read -r confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo -e "${CLR_INFO}Останавливаем процессы и удаляем папку...${CLR_RESET}"

        if pgrep -f dill-node > /dev/null; then
            pkill -f dill-node
            echo -e "${CLR_SUCCESS}Процесс dill-node остановлен.${CLR_RESET}"
        else
            echo -e "${CLR_WARNING}Процесс dill-node не найден.${CLR_RESET}"
        fi

        if [ -d "$DILL_DIR" ]; then
            rm -rf "$DILL_DIR"
            echo -e "${CLR_SUCCESS}Папка $DILL_DIR удалена.${CLR_RESET}"
        else
            echo -e "${CLR_WARNING}Папка $DILL_DIR не найдена.${CLR_RESET}"
        fi
    else
        echo -e "${CLR_WARNING}Операция отменена.${CLR_RESET}"
    fi
}


function show_menu() {
    show_logo
    echo -e "${CLR_GREEN}1) 🚀 Установить light node${CLR_RESET}"
    echo -e "${CLR_GREEN}2) ➕ Добавить валидатора${CLR_RESET}"
    echo -e "${CLR_GREEN}3) 🔑 Показать все pubkey валидаторов${CLR_RESET}"
    echo -e "${CLR_GREEN}4) 📊 Проверить статус ноды${CLR_RESET}"
    echo -e "${CLR_GREEN}5) 🔄 Перезапустить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}6) 🗑  Удалить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}7) ❌ Выйти${CLR_RESET}"
    echo -ne "${CLR_INFO}Введите номер действия: ${CLR_RESET}"
    read -r choice
    case $choice in
        1) install_node ;;
        2) add_validator ;;
        3) show_pubkeys ;;
        4) check_node_status ;;
        5) restart_node ;;
        6) remove_node ;;
        7) exit 0 ;;
        *) echo -e "${CLR_ERROR}Неверный выбор!${CLR_RESET}"; sleep 1; show_menu ;;
    esac
}

show_menu
