#!/bin/bash

# Скрипт первоначальной настройки VPS Ubuntu Server 24.04.3
# Этот скрипт должен выполняться от имени root
# Создает нового пользователя с sudo правами

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для цветного вывода
print_info() {
    echo -e "${BLUE}[ИНФО]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[УСПЕХ]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1"
}

print_error() {
    echo -e "${RED}[ОШИБКА]${NC} $1"
}

# Проверка выполнения скрипта от root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен выполняться от имени root"
        echo "Использование: sudo $0"
        exit 1
    fi
}

# Получение данных для создания нового пользователя
get_user_info() {
    echo
    print_info "Создание нового пользователя с sudo правами"
    echo
    
    while true; do
        read -p "Введите имя пользователя: " NEW_USER
        if [[ -n "$NEW_USER" ]] && [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            break
        else
            print_error "Неверное имя пользователя. Используйте только строчные буквы, цифры, подчеркивания и дефисы."
        fi
    done
    
    # Проверка существования пользователя
    if id "$NEW_USER" &>/dev/null; then
        print_error "Пользователь '$NEW_USER' уже существует"
        exit 1
    fi
    
    echo
    read -p "Введите полное имя пользователя (необязательно): " FULL_NAME
    
    echo
    print_info "Выберите способ настройки пароля:"
    echo "1) Установить пароль сейчас"
    echo "2) Отключить пароль (только SSH ключ)"
    read -p "Введите выбор (1-2): " PASSWORD_CHOICE
    
    if [[ "$PASSWORD_CHOICE" == "1" ]]; then
        while true; do
            read -s -p "Введите пароль для $NEW_USER: " USER_PASSWORD
            echo
            read -s -p "Подтвердите пароль: " USER_PASSWORD_CONFIRM
            echo
            
            if [[ "$USER_PASSWORD" == "$USER_PASSWORD_CONFIRM" ]]; then
                break
            else
                print_error "Пароли не совпадают. Попробуйте еще раз."
            fi
        done
    fi
    
    echo
    read -p "Хотите добавить SSH публичный ключ? (y/n): " ADD_SSH_KEY
}

# Создание нового пользователя
create_user() {
    print_info "Создание пользователя '$NEW_USER'..."
    
    if [[ -n "$FULL_NAME" ]]; then
        useradd -m -s /bin/bash -c "$FULL_NAME" "$NEW_USER"
    else
        useradd -m -s /bin/bash "$NEW_USER"
    fi
    
    if [[ "$PASSWORD_CHOICE" == "1" ]]; then
        echo "$NEW_USER:$USER_PASSWORD" | chpasswd
        print_success "Пароль установлен для пользователя '$NEW_USER'"
    else
        passwd -d "$NEW_USER"
        passwd -l "$NEW_USER"
        print_success "Пароль отключен для пользователя '$NEW_USER'"
    fi
    
    print_success "Пользователь '$NEW_USER' успешно создан"
}

# Добавление пользователя в группу sudo
add_sudo_privileges() {
    print_info "Добавление пользователя '$NEW_USER' в группу sudo..."
    usermod -aG sudo "$NEW_USER"
    print_success "Пользователь '$NEW_USER' добавлен в группу sudo"
}

# Настройка SSH ключа
setup_ssh_key() {
    if [[ "$ADD_SSH_KEY" == "y" ]] || [[ "$ADD_SSH_KEY" == "Y" ]]; then
        print_info "Настройка SSH ключа для пользователя '$NEW_USER'..."
        
        # Создание директории .ssh
        USER_HOME="/home/$NEW_USER"
        SSH_DIR="$USER_HOME/.ssh"
        
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        
        echo
        echo "Вставьте ваш SSH публичный ключ (или нажмите Enter для пропуска):"
        read SSH_PUBLIC_KEY
        
        if [[ -n "$SSH_PUBLIC_KEY" ]]; then
            echo "$SSH_PUBLIC_KEY" > "$SSH_DIR/authorized_keys"
            chmod 600 "$SSH_DIR/authorized_keys"
            chown -R "$NEW_USER:$NEW_USER" "$SSH_DIR"
            print_success "SSH ключ добавлен для пользователя '$NEW_USER'"
        else
            print_warning "SSH ключ не предоставлен"
        fi
    fi
}

# Тестирование sudo доступа
test_sudo_access() {
    print_info "Тестирование sudo доступа для пользователя '$NEW_USER'..."
    
    if sudo -u "$NEW_USER" sudo -n true 2>/dev/null; then
        print_success "Sudo доступ подтвержден для пользователя '$NEW_USER'"
    else
        print_info "Пользователь '$NEW_USER' имеет sudo доступ (требуется пароль)"
    fi
}

# Отображение сводки
display_summary() {
    echo
    echo "======================================"
    print_success "Настройка пользователя успешно завершена!"
    echo "======================================"
    echo
    echo "Данные пользователя:"
    echo "  Имя пользователя: $NEW_USER"
    echo "  Домашняя директория: /home/$NEW_USER"
    echo "  Оболочка: /bin/bash"
    echo "  Sudo доступ: Да"
    
    if [[ "$PASSWORD_CHOICE" == "1" ]]; then
        echo "  Пароль: Установлен"
    else
        echo "  Пароль: Отключен (только SSH ключ)"
    fi
    
    if [[ "$ADD_SSH_KEY" == "y" ]] || [[ "$ADD_SSH_KEY" == "Y" ]]; then
        if [[ -f "/home/$NEW_USER/.ssh/authorized_keys" ]]; then
            echo "  SSH ключ: Настроен"
        else
            echo "  SSH ключ: Не настроен"
        fi
    fi
    
    echo
    echo "Следующие шаги:"
    echo "1. Тестирование SSH подключения: ssh $NEW_USER@ваш_ip_сервера"
    echo "2. Тестирование sudo доступа: sudo whoami"
    echo "3. Рассмотрите отключение SSH доступа для root в целях безопасности"
    echo
}

# Основная функция
main() {
    echo "======================================"
    echo "Скрипт настройки пользователя Ubuntu Server 24.04.3"
    echo "====================================="
    
    check_root
    get_user_info
    create_user
    add_sudo_privileges
    setup_ssh_key
    test_sudo_access
    display_summary
}

# Run main function
main "$@"