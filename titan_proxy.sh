#!/bin/bash

# Оформление текста: цвета и фоны
CLR_INFO='\033[1;97;44m'  # Белый текст на синем фоне
CLR_SUCCESS='\033[1;30;42m'  # Зеленый текст на черном фоне
CLR_WARNING='\033[1;37;41m'  # Белый текст на красном фоне
CLR_ERROR='\033[1;31;40m'  # Красный текст на черном фоне
CLR_RESET='\033[0m'  # Сброс форматирования
CLR_GREEN='\033[0;32m' # Зеленый текст

# Функция отображения логотипа
function show_logo() {
    echo -e "${CLR_INFO}     Добро пожаловать в скрипт установки ноды Titan      ${CLR_RESET}"
    curl -s https://raw.githubusercontent.com/profitnoders/Profit_Nodes/refs/heads/main/logo_new.sh | bash
}

# Функция установки необходимых пакетов
function install_dependencies() {
    sudo apt update -y && sudo apt upgrade -y
    sudo apt install -y curl wget git docker.io
}

# Функция установки Docker
function install_docker() {
    echo -e "${CLR_INFO}Проверяем Docker...${CLR_RESET}"
    if ! command -v docker &> /dev/null; then
        echo -e "${CLR_WARNING}Docker не установлен. Устанавливаем Docker...${CLR_RESET}"
        sudo apt install docker.io -y
    else
        echo -e "${CLR_SUCCESS}Docker уже установлен!${CLR_RESET}"
    fi
}

# Функция настройки прокси
# function configure_proxy() {
#     echo -e "${CLR_INFO}Настройка HTTP-прокси для Docker...${CLR_RESET}"

#     read -p "Введите IP (оставьте пустым для пропуска): " PROXY_IP
#     read -p "Введите порт (оставьте пустым для пропуска): " PROXY_PORT
#     read -p "Введите логин (если нет, оставьте пустым): " PROXY_LOGIN
#     read -p "Введите пароль (если нет, оставьте пустым): " PROXY_PASS

#     # Проверяем, введены ли IP и порт
#     if [[ -z "$PROXY_IP" || -z "$PROXY_PORT" ]]; then
#         echo -e "${CLR_WARNING}⚠️ Прокси не настроен, так как не введены IP и порт.${CLR_RESET}"
#         return
#     fi

#     # Формируем прокси-URL (с логином/паролем, если они есть)
#     if [[ -n "$PROXY_LOGIN" && -n "$PROXY_PASS" ]]; then
#         PROXY_URL="http://${PROXY_LOGIN}:${PROXY_PASS}@${PROXY_IP}:${PROXY_PORT}"
#     else
#         PROXY_URL="http://${PROXY_IP}:${PROXY_PORT}"
#     fi

#     # Создаём конфигурацию прокси для Docker
#     sudo mkdir -p /etc/systemd/system/docker.service.d
#     echo "[Service]
# Environment=\"HTTP_PROXY=$PROXY_URL\"
# Environment=\"HTTPS_PROXY=$PROXY_URL\"
# Environment=\"FTP_PROXY=$PROXY_URL\"
# Environment=\"ALL_PROXY=$PROXY_URL\"
# Environment=\"NO_PROXY=localhost,127.0.0.1\"" | sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null

#     # Применяем изменения
#     sudo systemctl daemon-reload
#     sudo systemctl restart docker

#     echo -e "${CLR_SUCCESS}✅ Прокси успешно настроен!${CLR_RESET}"
# }

# Функция установки ноды Titan
function install_node() {
    install_dependencies
    install_docker

    # echo -e "${CLR_INFO}Хотите настроить прокси для Docker? (y/n)${CLR_RESET}"
    # read -r USE_PROXY
    # if [[ "$USE_PROXY" == "y" ]]; then
    #     configure_proxy
    # fi

    echo -e "${CLR_INFO}Удаляем старые данные ноды...${CLR_RESET}"
    rm -rf ~/.titanedge

    echo -e "${CLR_INFO}Скачиваем Docker-образ ноды Titan...${CLR_RESET}"
    docker pull nezha123/titan-edge

    echo -e "${CLR_INFO}Создаем хранилище для ноды...${CLR_RESET}"
    mkdir -p ~/.titanedge

    echo -e "${CLR_INFO}Запускаем контейнер Titan для генерации конфигурации...${CLR_RESET}"
    docker run --rm -it -v ~/.titanedge:/root/.titanedge nezha123/titan-edge daemon start || true

    if [[ -f ~/.titanedge/config.toml ]]; then
        echo -e "${CLR_INFO}Меняем порт ноды с 1234 на 1235...${CLR_RESET}"
        sed -i 's/#ListenAddress = "0.0.0.0:1234"/ListenAddress = "0.0.0.0:1235"/' ~/.titanedge/config.toml
    else
        echo -e "${CLR_WARNING}⚠️ Файл config.toml не найден! Возможно, контейнер не запустился корректно.${CLR_RESET}"
    fi

    echo -e "${CLR_INFO}Запускаем контейнер Titan...${CLR_RESET}"
    docker run -d --network=host -v ~/.titanedge:/root/.titanedge nezha123/titan-edge

    echo -e "${CLR_SUCCESS}✅ Установка завершена! Нода запущена.${CLR_RESET}"
}

# Функция привязки идентификатора
function bind_identity() {
    echo -e "${CLR_WARNING}Введите ваш Identity Code:${CLR_RESET}"
    read -r IDENTITY_CODE

    echo -e "${CLR_INFO}Привязываем ваш код...${CLR_RESET}"
    docker run --rm -it -v ~/.titanedge:/root/.titanedge nezha123/titan-edge bind --hash="$IDENTITY_CODE" https://api-test1.container1.titannet.io/api/v2/device/binding

    echo -e "${CLR_SUCCESS}✅ Нода успешно привязана!${CLR_RESET}"
}

# Функция удаления ноды
function remove_node() {
    echo -e "${CLR_ERROR}Останавливаем и удаляем ноду Titan...${CLR_RESET}"
    docker stop $(docker ps -q --filter ancestor=nezha123/titan-edge) 2>/dev/null
    docker rm $(docker ps -aq --filter ancestor=nezha123/titan-edge) 2>/dev/null
    rm -rf ~/.titanedge
    echo -e "${CLR_SUCCESS}✅ Нода успешно удалена!${CLR_RESET}"
}

# Функция просмотра логов
function check_logs() {
    echo -e "${CLR_INFO}Просмотр логов ноды Titan...${CLR_RESET}"
    docker logs --tail 100 -f $(docker ps -q --filter ancestor=nezha123/titan-edge)
}

# Главное меню
function show_menu() {
    show_logo
    echo -e "${CLR_INFO}Выберите действие:${CLR_RESET}"
    echo -e "${CLR_GREEN}1) 🚀 Установить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}2) 🔗 Привязать Identity Code${CLR_RESET}"
    echo -e "${CLR_GREEN}3) 📜 Просмотр логов${CLR_RESET}"
    echo -e "${CLR_ERROR}4) 🗑️ Удалить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}5) ❌ Выйти${CLR_RESET}"
    
    read -p "Введите номер действия: " choice

    case $choice in
        1) install_node ;;
        2) bind_identity ;;
        3) check_logs ;;
        4) remove_node ;;
        5) echo -e "${CLR_SUCCESS}Выход...${CLR_RESET}" && exit 0 ;;
        *) echo -e "${CLR_ERROR}Ошибка: Неверный выбор! Попробуйте снова.${CLR_RESET}" && show_menu ;;
    esac
}

# Запуск меню
show_menu

