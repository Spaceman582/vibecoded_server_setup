#!/bin/bash

# --- 1. ЗАЩИТА ОТ ПОВТОРНОГО ЗАПУСКА ---
MARKER="/var/lib/server_setup_done"
if [ -f "$MARKER" ] && [ "$1" != "--ignore" ]; then
    echo "-------------------------------------------------------"
    echo "⚠️  Система уже настроена! Чтобы запустить принудительно:"
    echo "bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) --ignore"
    echo "-------------------------------------------------------"
    exit 0
fi

# --- 2. ПРОВЕРКА SSH-КЛЮЧА (Termius) ---
if [ ! -s /root/.ssh/authorized_keys ]; then
    echo "❌ ОШИБКА: SSH-ключ не найден. Сначала деплой ключ через Termius."
    exit 1
fi

echo "🚀 Начинаем установку..."

# Запрос данных
read -p "Имя пользователя: " USERNAME
read -s -p "Пароль: " USERPASS
echo
read -p "Порт SSH (напр. 2222): " SSHPORT

# --- 3. ОБНОВЛЕНИЕ И ПАКЕТЫ ---
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y nano ufw btop python3 python3-pip curl git vim wget fail2ban neofetch landscape-common

# Алиас python
echo "alias python='python3'" >> /etc/bash.bashrc
alias python='python3'

# --- 4. КРАСИВЫЙ ВХОД И ОПТИМИЗАЦИЯ ---
chmod -x /etc/update-motd.d/* 2>/dev/null
chmod +x /etc/update-motd.d/50-landscape-sysinfo 2>/dev/null

# SWAP 2GB
if ! grep -q "swapfile" /etc/fstab; then
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Лимит логов 200MB
sed -i 's/#SystemMaxUse=/SystemMaxUse=200M/' /etc/systemd/journald.conf
systemctl restart systemd-journald

# --- 5. ПОЛЬЗОВАТЕЛЬ И SSH ---
useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$USERPASS" | chpasswd
usermod -aG sudo "$USERNAME"
echo "neofetch" >> "/home/$USERNAME/.bashrc"

mkdir -p "/home/$USERNAME/.ssh"
cp /root/.ssh/authorized_keys "/home/$USERNAME/.ssh/"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
chmod 700 "/home/$USERNAME/.ssh"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"

# ---  КОНФИГУРАЦИЯ SSH (Только ключи, новый порт, без Root) ---
echo "--- Настройка SSH (Запрет паролей и Root-доступа) ---"

# Меняем порт
sed -i "s/^#Port 22/Port $SSHPORT/" /etc/ssh/sshd_config
sed -i "s/^Port 22/Port $SSHPORT/" /etc/ssh/sshd_config

# Запрещаем вход под root
sed -i "s/^#PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config

# ОТКЛЮЧАЕМ ВХОД ПО ПАРОЛЮ (Разрешаем только ключи)
sed -i "s/^#PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
sed -i "s/^PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config

# Дополнительная защита: отключаем пустые пароли
sed -i "s/^#PermitEmptyPasswords.*/PermitEmptyPasswords no/" /etc/ssh/sshd_config


# Проверка конфига перед перезагрузкой (чтобы не вылететь с ошибкой)
sshd -t && systemctl restart ssh

# --- 6. UFW (ФАЕРВОЛ) ---
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSHPORT"/tcp
ufw allow 80/tcp
ufw allow 443/tcp
#ufw allow 2053/tcp 
ufw --force enable

# --- 7. ПАНЕЛЬ 3X-UI ---
#echo "--- Запуск инсталлятора 3x-ui ---"
#bash <(curl -Ls https://raw.githubusercontent.com)

# --- 8. ФИНАЛ ---
touch "$MARKER"
IP_ADDR=$(hostname -I | awk '{print $1}')
echo "-----------------------------------------------"
echo " ✅ НАСТРОЙКА ЗАВЕРШЕНА!"
echo " Пользователь: $USERNAME | Порт: $SSHPORT"
echo " Вход: ssh -p $SSHPORT $USERNAME@$IP_ADDR"
echo "-----------------------------------------------"
neofetch
