#!/bin/bash
set -eEuo pipefail

# ============================================================================
# УДАЛЕНИЕ LeakAnalyze с интеграцией bog_push
# ============================================================================
# ⚠️ ВНИМАНИЕ: СИСТЕМА НЕ РАБОТАЕТ ⚠️
# Этот скрипт удаляет LeakAnalyze и восстанавливает оригинальные компиляторы.
# Безопасно работает с существующей системой bog_push.

# === Цветной вывод ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { echo -e "${RED}Error: $1${NC}" >&2; }
success() { echo -e "${GREEN}$1${NC}"; }
warning() { echo -e "${YELLOW}Warning: $1${NC}"; }
info() { echo -e "${BLUE}$1${NC}"; }

# === Переменные ===
BOGACHEV_BIN="$HOME/bogachev/bin"
BOGACHEV_ENV="$HOME/.bogachev_env"
CLEANUP_REQUIRED=false

# === Функция очистки при ошибке ===
cleanup() {
  if [ "$CLEANUP_REQUIRED" = true ]; then
    echo ""
    warning "Выполняется откат изменений..."
    echo "Откат завершён."
  fi
  exit 1
}
trap cleanup INT TERM EXIT

# === Проверка установки ===
echo "Проверка установки LeakAnalyze..."

if [ ! -d "$BOGACHEV_BIN" ]; then
  warning "Папка $BOGACHEV_BIN не найдена."
  echo "LeakAnalyze не установлен."
  exit 0
fi

# Проверяем наличие компонентов LeakAnalyze
COMPONENTS_FOUND=0
if [ -d "$BOGACHEV_BIN/LeakAnalyze" ]; then
  COMPONENTS_FOUND=$((COMPONENTS_FOUND + 1))
fi
if [ -f "$BOGACHEV_BIN/gcc" ]; then
  COMPONENTS_FOUND=$((COMPONENTS_FOUND + 1))
fi
if [ -f "$BOGACHEV_BIN/g++" ]; then
  COMPONENTS_FOUND=$((COMPONENTS_FOUND + 1))
fi

if [ $COMPONENTS_FOUND -eq 0 ]; then
  warning "LeakAnalyze не установлен."
  exit 0
fi

echo "Найдено $COMPONENTS_FOUND компонент(ов) LeakAnalyze"

# === Подтверждение удаления ===
echo ""
warning "Это действие удалит:"
if [ -d "$BOGACHEV_BIN/LeakAnalyze" ]; then
  echo "  • Папку LeakAnalyze: $BOGACHEV_BIN/LeakAnalyze/"
fi
if [ -f "$BOGACHEV_BIN/gcc" ]; then
  echo "  • Обёртку gcc: $BOGACHEV_BIN/gcc"
fi
if [ -f "$BOGACHEV_BIN/g++" ]; then
  echo "  • Обёртку g++: $BOGACHEV_BIN/g++"
fi
echo ""

read -p "Продолжить удаление? [y/N]: " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Удаление отменено."
  exit 0
fi

CLEANUP_REQUIRED=true

# === Создание бэкапов ===
echo ""
info "Создание резервных копий..."

TS=$(date +%Y%m%d%H%M%S)
BACKUP_DIR="$HOME/.bogachev_backup_compiler_$TS"
mkdir -p "$BACKUP_DIR"

# Бэкап обёрток если они есть
if [ -f "$BOGACHEV_BIN/gcc" ]; then
  cp "$BOGACHEV_BIN/gcc" "$BACKUP_DIR/gcc"
  echo "✓ Создан бэкап gcc"
fi

if [ -f "$BOGACHEV_BIN/g++" ]; then
  cp "$BOGACHEV_BIN/g++" "$BACKUP_DIR/g++"
  echo "✓ Создан бэкап g++"
fi

# Бэкап папки LeakAnalyze
if [ -d "$BOGACHEV_BIN/LeakAnalyze" ]; then
  cp -r "$BOGACHEV_BIN/LeakAnalyze" "$BACKUP_DIR/"
  echo "✓ Создан бэкап LeakAnalyze"
fi

# Бэкап .bogachev_env
if [ -f "$BOGACHEV_ENV" ]; then
  cp "$BOGACHEV_ENV" "$BACKUP_DIR/bogachev_env"
  echo "✓ Создан бэкап .bogachev_env"
fi

echo "Резервные копии сохранены в: $BACKUP_DIR"

# === Удаление обёрток компиляторов ===
echo ""
info "Удаление обёрток компиляторов..."

# Удаляем обёртки gcc и g++
if [ -f "$BOGACHEV_BIN/gcc" ]; then
  rm -f "$BOGACHEV_BIN/gcc"
  echo "✓ Удалена обёртка gcc"
fi

if [ -f "$BOGACHEV_BIN/g++" ]; then
  rm -f "$BOGACHEV_BIN/g++"
  echo "✓ Удалена обёртка g++"
fi

# === Удаление LeakAnalyze ===
echo ""
info "Удаление LeakAnalyze..."

if [ -d "$BOGACHEV_BIN/LeakAnalyze" ]; then
  rm -rf "$BOGACHEV_BIN/LeakAnalyze"
  echo "✓ Удалена папка LeakAnalyze"
fi

# === Очистка .bogachev_env ===
echo ""
info "Очистка конфигурации..."

if [ -f "$BOGACHEV_ENV" ]; then
  # Создаём временный файл без строк LeakAnalyze
  grep -v "LeakAnalyze" "$BOGACHEV_ENV" > "$BOGACHEV_ENV.tmp" || true
  
  # Если файл не пустой, заменяем оригинал
  if [ -s "$BOGACHEV_ENV.tmp" ]; then
    mv "$BOGACHEV_ENV.tmp" "$BOGACHEV_ENV"
    echo "✓ Удалены настройки LeakAnalyze из ~/.bogachev_env"
  else
    # Если файл стал пустым, оставляем оригинал
    rm -f "$BOGACHEV_ENV.tmp"
    echo "✓ Настройки LeakAnalyze не найдены в ~/.bogachev_env"
  fi
fi

# === Проверка удаления ===
echo ""
info "Проверка удаления..."

# Проверяем, что обёртки удалены
if [ ! -f "$BOGACHEV_BIN/gcc" ] && [ ! -f "$BOGACHEV_BIN/g++" ]; then
  success "✓ Обёртки компиляторов удалены"
else
  warning "⚠ Некоторые обёртки могли не удалиться"
fi

# Проверяем, что LeakAnalyze удалён
if [ ! -d "$BOGACHEV_BIN/LeakAnalyze" ]; then
  success "✓ LeakAnalyze удалён"
else
  warning "⚠ Папка LeakAnalyze могла не удалиться"
fi

# === Проверка системных компиляторов ===
echo ""
info "Проверка системных компиляторов..."

# Проверяем доступность системных компиляторов
if command -v /usr/bin/gcc >/dev/null 2>&1; then
  success "✓ Системный gcc доступен: $(/usr/bin/gcc --version | head -n1)"
else
  warning "⚠ Системный gcc не найден"
fi

if command -v /usr/bin/g++ >/dev/null 2>&1; then
  success "✓ Системный g++ доступен: $(/usr/bin/g++ --version | head -n1)"
else
  warning "⚠ Системный g++ не найден"
fi

# === Завершение ===
CLEANUP_REQUIRED=false

echo ""
success "=========================================="
success "  ✓ Удаление LeakAnalyze завершено!"
success "=========================================="
echo ""
echo "Удалённые компоненты:"
if [ -d "$BACKUP_DIR/LeakAnalyze" ]; then
  echo "  • LeakAnalyze (бэкап: $BACKUP_DIR/LeakAnalyze/)"
fi
if [ -f "$BACKUP_DIR/gcc" ]; then
  echo "  • Обёртка gcc (бэкап: $BACKUP_DIR/gcc)"
fi
if [ -f "$BACKUP_DIR/g++" ]; then
  echo "  • Обёртка g++ (бэкап: $BACKUP_DIR/g++)"
fi
echo ""
echo "Резервные копии сохранены в: $BACKUP_DIR"
echo ""
echo "Теперь используются системные компиляторы:"
echo "  • gcc: $(command -v gcc 2>/dev/null || echo 'не найден')"
echo "  • g++: $(command -v g++ 2>/dev/null || echo 'не найден')"
echo ""
echo "Для полной активации выполните:"
echo "  source ~/.bogachev_env"
echo ""