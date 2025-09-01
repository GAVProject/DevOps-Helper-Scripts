#!/bin/bash

# Скрипт первоначальной настройки VPS Ubuntu Server 24.04.3
# Этот скрипт должен выполняться от имени пользователя с sudo правами
# Выполняет комплексную настройку системы безопасности и основных сервисов

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Переменные по умолчанию
DEFAULT_TIMEZONE="Europe/Moscow"
DEFAULT_SWAP_SIZE="2G"
SCRIPT_VERSION="1.0.0"

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

print_step() {
    echo -e "${PURPLE}[ШАГ]${NC} $1"
}

# Проверка sudo прав
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_error "Этот скрипт требует sudo права"
        echo "Убедитесь, что пользователь имеет sudo доступ и выполните:"
        echo "sudo $0"
        exit 1
    fi
}

# Проверка версии Ubuntu
check_ubuntu_version() {
    if ! grep -q "Ubuntu 24.04" /etc/os-release; then
        print_warning "Этот скрипт оптимизирован для Ubuntu 24.04"
        read -p "Продолжить? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Получение конфигурации от пользователя
get_configuration() {
    echo
    print_info "Настройка параметров системы"
    echo
    
    # Timezone
    print_info "Текущая временная зона: $(timedatectl | grep "Time zone" | awk '{print $3}')"
    read -p "Введите временную зону (по умолчанию: $DEFAULT_TIMEZONE): " TIMEZONE
    TIMEZONE=${TIMEZONE:-$DEFAULT_TIMEZONE}
    
    # Swap
    echo
    read -p "Создать swap файл? (y/n, по умолчанию: y): " CREATE_SWAP
    CREATE_SWAP=${CREATE_SWAP:-y}
    
    if [[ "$CREATE_SWAP" == "y" ]] || [[ "$CREATE_SWAP" == "Y" ]]; then
        read -p "Размер swap (по умолчанию: $DEFAULT_SWAP_SIZE): " SWAP_SIZE
        SWAP_SIZE=${SWAP_SIZE:-$DEFAULT_SWAP_SIZE}
    fi
    
    # SSH настройки
    echo
    read -p "Изменить стандартный SSH порт? (y/n, по умолчанию: n): " CHANGE_SSH_PORT
    if [[ "$CHANGE_SSH_PORT" == "y" ]] || [[ "$CHANGE_SSH_PORT" == "Y" ]]; then
        while true; do
            read -p "Введите новый SSH порт (1024-65535): " NEW_SSH_PORT
            if [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_SSH_PORT" -ge 1024 ] && [ "$NEW_SSH_PORT" -le 65535 ]; then
                break
            else
                print_error "Некорректный порт. Введите число от 1024 до 65535"
            fi
        done
    fi
    
    # Автообновления
    echo
    read -p "Включить автоматические обновления безопасности? (y/n, по умолчанию: y): " ENABLE_AUTO_UPDATES
    ENABLE_AUTO_UPDATES=${ENABLE_AUTO_UPDATES:-y}
    

}

# Обновление системы
update_system() {
    print_step "Обновление системы"
    
    print_info "Обновление списка пакетов..."
    sudo apt update
    
    print_info "Обновление установленных пакетов..."
    sudo apt upgrade -y
    
    print_info "Удаление ненужных пакетов..."
    sudo apt autoremove -y
    sudo apt autoclean
    
    print_success "Система успешно обновлена"
}

# Установка необходимых пакетов
install_packages() {
    print_step "Установка необходимых пакетов"
    
    local packages=(
        "curl"
        "wget"
        "git"
        "htop"
        "nano"
        "vim"
        "unzip"
        "tree"
        "fail2ban"
        "ufw"
#        "build-essential"
#        "software-properties-common"
#        "apt-transport-https"
#        "ca-certificates"
#        "gnupg"
#        "lsb-release"
#        "net-tools"
#        "build-essentialt"
    )
    
    print_info "Установка пакетов: ${packages[*]}"
    sudo apt install -y "${packages[@]}"
    
    print_success "Все пакеты успешно установлены"
}

# Настройка временной зоны
setup_timezone() {
    print_step "Настройка временной зоны"
    
    print_info "Установка временной зоны: $TIMEZONE"
    sudo timedatectl set-timezone "$TIMEZONE"
    
    print_info "Синхронизация времени..."
    sudo timedatectl set-ntp true
    
    print_success "Временная зона настроена: $(timedatectl | grep "Time zone" | awk '{print $3}')"
}

# Создание swap файла
setup_swap() {
    if [[ "$CREATE_SWAP" == "y" ]] || [[ "$CREATE_SWAP" == "Y" ]]; then
        print_step "Настройка swap файла"
        
        # Проверка существующего swap
        if swapon --show | grep -q "/swapfile"; then
            print_warning "Swap файл уже существует"
            return
        fi
        
        print_info "Создание swap файла размером $SWAP_SIZE"
        sudo fallocate -l "$SWAP_SIZE" /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        
        # Добавление в fstab для автоматического монтирования
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
        fi
        
        # Настройка swappiness
        echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
        
        print_success "Swap файл создан и настроен"
    fi
}

# Настройка брандмауэра UFW
setup_firewall() {
    print_step "Настройка брандмауэра UFW"
    
    print_info "Настройка правил UFW..."
    
    # Сброс к настройкам по умолчанию
    sudo ufw --force reset
    
    # Политики по умолчанию
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Разрешение SSH
    if [[ -n "$NEW_SSH_PORT" ]]; then
        sudo ufw allow "$NEW_SSH_PORT"/tcp comment 'SSH'
    else
        sudo ufw allow ssh comment 'SSH'
    fi
    
    # Включение UFW
    sudo ufw --force enable
    
    print_success "Брандмауэр UFW настроен и активирован"
}

# Настройка SSH
setup_ssh() {
    print_step "Настройка SSH"
    
    print_info "Создание резервной копии SSH конфигурации..."
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)
    
    # Создание временного файла конфигурации
    local ssh_config="/tmp/sshd_config_new"
    sudo cp /etc/ssh/sshd_config "$ssh_config"
    
    # Основные настройки безопасности
    sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' "$ssh_config"
    sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' "$ssh_config"
    sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' "$ssh_config"
    sudo sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' "$ssh_config"
    sudo sed -i 's/X11Forwarding yes/X11Forwarding no/' "$ssh_config"
    
    # Добавление дополнительных настроек безопасности
    if ! grep -q "Protocol 2" "$ssh_config"; then
        echo "Protocol 2" | sudo tee -a "$ssh_config"
    fi
    
    if ! grep -q "MaxAuthTries" "$ssh_config"; then
        echo "MaxAuthTries 3" | sudo tee -a "$ssh_config"
    fi
    
    if ! grep -q "ClientAliveInterval" "$ssh_config"; then
        echo "ClientAliveInterval 300" | sudo tee -a "$ssh_config"
        echo "ClientAliveCountMax 2" | sudo tee -a "$ssh_config"
    fi
    
    # Изменение порта SSH если требуется
    if [[ -n "$NEW_SSH_PORT" ]]; then
        sudo sed -i "s/#Port 22/Port $NEW_SSH_PORT/" "$ssh_config"
        print_info "SSH порт изменен на $NEW_SSH_PORT"
    fi
    
    # Применение конфигурации
    sudo mv "$ssh_config" /etc/ssh/sshd_config
    
    # Проверка конфигурации
    if sudo sshd -t; then
        sudo systemctl restart ssh
        print_success "SSH настроен и перезапущен"
        if [[ -n "$NEW_SSH_PORT" ]]; then
            print_warning "SSH порт изменен на $NEW_SSH_PORT. Используйте: ssh -p $NEW_SSH_PORT пользователь@сервер"
        fi
    else
        print_error "Ошибка в конфигурации SSH. Восстанавливаем резервную копию..."
        sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
        sudo systemctl restart ssh
    fi
}

# Настройка Fail2Ban
setup_fail2ban() {
    print_step "Настройка Fail2Ban"
    
    print_info "Создание конфигурации Fail2Ban..."
    
    # Создание локальной конфигурации
    sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ${NEW_SSH_PORT:-22}
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF
    
    # Запуск и включение Fail2Ban
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
    
    print_success "Fail2Ban настроен и запущен"
}

# Настройка автоматических обновлений
setup_auto_updates() {
    if [[ "$ENABLE_AUTO_UPDATES" == "y" ]] || [[ "$ENABLE_AUTO_UPDATES" == "Y" ]]; then
        print_step "Настройка автоматических обновлений"
        
        print_info "Установка unattended-upgrades..."
        sudo apt install -y unattended-upgrades
        
        print_info "Настройка автоматических обновлений безопасности..."
        sudo dpkg-reconfigure -plow unattended-upgrades
        
        # Настройка конфигурации
        sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
        
        print_success "Автоматические обновления настроены"
    fi
}



# Настройка системных лимитов
setup_system_limits() {
    print_step "Настройка системных лимитов"
    
    print_info "Настройка лимитов для файлов и процессов..."
    
    # Настройка limits.conf
    sudo tee -a /etc/security/limits.conf > /dev/null <<EOF

# Увеличение лимитов для всех пользователей
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
    
    # Настройка systemd лимитов
    sudo mkdir -p /etc/systemd/system.conf.d
    sudo tee /etc/systemd/system.conf.d/limits.conf > /dev/null <<EOF
[Manager]
DefaultLimitNOFILE=65536
DefaultLimitNPROC=32768
EOF
    
    print_success "Системные лимиты настроены"
}

# Очистка и оптимизация
cleanup_system() {
    print_step "Очистка и оптимизация системы"
    
    print_info "Очистка пакетов и кэша..."
    sudo apt autoremove -y
    sudo apt autoclean
    
    print_info "Очистка логов..."
    sudo journalctl --vacuum-time=7d
    
    print_success "Система очищена"
}

# Отображение сводки
display_summary() {
    echo
    echo "================================================="
    print_success "Настройка VPS Ubuntu Server 24.04.3 завершена!"
    echo "================================================="
    echo
    echo "🔧 Выполненные настройки:"
    echo "  ✅ Система обновлена"
    echo "  ✅ Необходимые пакеты установлены"
    echo "  ✅ Временная зона: $TIMEZONE"
    
    if [[ "$CREATE_SWAP" == "y" ]] || [[ "$CREATE_SWAP" == "Y" ]]; then
        echo "  ✅ Swap файл: $SWAP_SIZE"
    fi
    
    echo "  ✅ SSH настроен и защищен"
    
    if [[ -n "$NEW_SSH_PORT" ]]; then
        echo "  ✅ SSH порт изменен на: $NEW_SSH_PORT"
    fi
    
    echo "  ✅ UFW брандмауэр активирован"
    echo "  ✅ Fail2Ban настроен"
    
    if [[ "$ENABLE_AUTO_UPDATES" == "y" ]] || [[ "$ENABLE_AUTO_UPDATES" == "Y" ]]; then
        echo "  ✅ Автоматические обновления включены"
    fi
    
    echo "  ✅ Системные лимиты оптимизированы"
    
    echo
    echo "🔒 Рекомендации по безопасности:"
    echo "  • Регулярно обновляйте систему: sudo apt update && sudo apt upgrade"
    echo "  • Проверяйте логи: sudo fail2ban-client status sshd"
    echo "  • Мониторьте подключения: sudo ss -tuln"
    
    if [[ -n "$NEW_SSH_PORT" ]]; then
        echo "  • Подключение SSH: ssh -p $NEW_SSH_PORT пользователь@ip_сервера"
    fi
    
    echo
    echo "📊 Статус сервисов:"
    echo "  • SSH: $(systemctl is-active ssh)"
    echo "  • UFW: $(systemctl is-active ufw)"
    echo "  • Fail2Ban: $(systemctl is-active fail2ban)"
    
    echo
    print_success "VPS готов к использованию!"
}

# Основная функция
main() {
    echo "================================================="
    echo "🚀 Скрипт настройки VPS Ubuntu Server 24.04.3"
    echo "📋 Версия: $SCRIPT_VERSION"
    echo "================================================="
    
    check_sudo
    check_ubuntu_version
    get_configuration
    
    echo
    print_info "Начинаем настройку VPS..."
    echo
    
    update_system
    install_packages
    setup_timezone
    setup_swap
    setup_firewall
    setup_ssh
    setup_fail2ban
    setup_auto_updates
#    setup_system_limits
#    cleanup_system
    
    display_summary
}

# Обработка сигналов
trap 'print_error "Скрипт прерван пользователем"; exit 1' INT TERM

# Запуск основной функции
main "$@"