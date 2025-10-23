#!/bin/bash
set -eEuo pipefail

# ============================================================================
# УСТАНОВКА LeakAnalyze с интеграцией bog_push
# ============================================================================
# Этот скрипт устанавливает LeakAnalyze и создаёт обёртки для gcc/g++
# с автоматической подстановкой библиотек только при линковке.
# Интегрируется с существующей системой bog_push.

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
TS=$(date +%Y%m%d%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOGACHEV_BIN="$HOME/bogachev/bin"
BOGACHEV_ENV="$HOME/.bogachev_env"
BACKUP_SUFFIX="compiler_$TS"
CLEANUP_REQUIRED=false

# === Функция очистки при ошибке ===
cleanup() {
  if [ "$CLEANUP_REQUIRED" = true ]; then
    echo ""
    warning "Выполняется откат изменений..."
    
    # Восстанавливаем оригинальные файлы если есть бэкапы
    if [ -f "$BOGACHEV_BIN/gcc.bak_$BACKUP_SUFFIX" ]; then
      mv "$BOGACHEV_BIN/gcc.bak_$BACKUP_SUFFIX" "$BOGACHEV_BIN/gcc" 2>/dev/null || true
    fi
    if [ -f "$BOGACHEV_BIN/g++.bak_$BACKUP_SUFFIX" ]; then
      mv "$BOGACHEV_BIN/g++.bak_$BACKUP_SUFFIX" "$BOGACHEV_BIN/g++" 2>/dev/null || true
    fi
    
    # Удаляем установленные файлы
    rm -rf "$BOGACHEV_BIN/LeakAnalyze" 2>/dev/null || true
    rm -f "$BOGACHEV_BIN/gcc" "$BOGACHEV_BIN/g++" 2>/dev/null || true
    
    # Восстанавливаем .bogachev_env если есть бэкап
    if [ -f "$BOGACHEV_ENV.bak_$BACKUP_SUFFIX" ]; then
      mv "$BOGACHEV_ENV.bak_$BACKUP_SUFFIX" "$BOGACHEV_ENV" 2>/dev/null || true
    fi
    
    echo "Откат завершён."
  fi
  exit 1
}
trap cleanup INT TERM EXIT

# === Проверка зависимостей ===
echo "Проверка зависимостей..."

# Проверяем наличие системных компиляторов
if ! command -v /usr/bin/gcc >/dev/null 2>&1; then
  error "Системный gcc не найден в /usr/bin/gcc"
  echo "Установите gcc: sudo apt install gcc (Ubuntu/Debian) или sudo yum install gcc (CentOS/RHEL)"
  exit 1
fi

if ! command -v /usr/bin/g++ >/dev/null 2>&1; then
  error "Системный g++ не найден в /usr/bin/g++"
  echo "Установите g++: sudo apt install g++ (Ubuntu/Debian) или sudo yum install g++ (CentOS/RHEL)"
  exit 1
fi

success "✓ Системные компиляторы найдены"

# Создаём папку bogachev/bin если её нет
if [ ! -d "$BOGACHEV_BIN" ]; then
  echo "Создаю папку $BOGACHEV_BIN"
  mkdir -p "$BOGACHEV_BIN"
fi

# Проверяем наличие библиотек
if [ ! -f "$SCRIPT_DIR/libs/libgcc_leaks_tracer.o" ]; then
  error "Библиотека libgcc_leaks_tracer.o не найдена в $SCRIPT_DIR/libs/"
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/libs/libgcc_leaks_rbtree.o" ]; then
  error "Библиотека libgcc_leaks_rbtree.o не найдена в $SCRIPT_DIR/libs/"
  exit 1
fi

# Проверяем наличие LeakAnalyze
if [ ! -f "$SCRIPT_DIR/libs/LeakAnalyze" ]; then
  error "Программа LeakAnalyze не найдена в $SCRIPT_DIR/libs/"
  exit 1
fi

success "✓ Все зависимости найдены"

# === Создание бэкапов ===
echo ""
info "Создание резервных копий..."

# Бэкап .bogachev_env
if [ -f "$BOGACHEV_ENV" ]; then
  cp "$BOGACHEV_ENV" "$BOGACHEV_ENV.bak_$BACKUP_SUFFIX"
  echo "✓ Создан бэкап $BOGACHEV_ENV"
fi

CLEANUP_REQUIRED=true

# === Копирование файлов ===
echo ""
info "Копирование файлов LeakAnalyze..."

# Создаём папку для LeakAnalyze
mkdir -p "$BOGACHEV_BIN/LeakAnalyze"

# Копируем библиотеки
cp "$SCRIPT_DIR/libs/libgcc_leaks_tracer.o" "$BOGACHEV_BIN/LeakAnalyze/"
cp "$SCRIPT_DIR/libs/libgcc_leaks_rbtree.o" "$BOGACHEV_BIN/LeakAnalyze/"
cp "$SCRIPT_DIR/libs/LeakAnalyze" "$BOGACHEV_BIN/LeakAnalyze/"
chmod +x "$BOGACHEV_BIN/LeakAnalyze/LeakAnalyze"

success "✓ Файлы скопированы"

# === Создание обёрток для gcc и g++ ===
echo ""
info "Создание обёрток для компиляторов..."

# Функция создания обёртки
create_wrapper() {
  local COMPILER="$1"
  local WRAPPER_PATH="$BOGACHEV_BIN/$COMPILER"
  
  # Создаём бэкап существующей обёртки если есть
  if [ -f "$WRAPPER_PATH" ]; then
    cp "$WRAPPER_PATH" "$WRAPPER_PATH.bak_$BACKUP_SUFFIX"
  fi
  
  cat > "$WRAPPER_PATH" <<EOF
#!/bin/bash
# --------------------------------------------
# $COMPILER wrapper with LeakAnalyze integration
# --------------------------------------------
REAL_COMPILER="/usr/bin/$COMPILER"
LIB_DIR="\$HOME/bogachev/bin/LeakAnalyze"
LIB=(
  "\$LIB_DIR/libgcc_leaks_rbtree.o"
  "\$LIB_DIR/libgcc_leaks_tracer.o"
)

# Автоматически добавляем wrap-флаги
WRAP_FLAGS=(
  -Wl,--wrap=malloc
  -Wl,--wrap=calloc
  -Wl,--wrap=realloc
  -Wl,--wrap=free
EOF

  # Добавляем специфичные для C++ флаги только для g++
  if [ "$COMPILER" = "g++" ]; then
    cat >> "$WRAPPER_PATH" <<EOF
  -Wl,--wrap=operator\ new
  -Wl,--wrap=operator\ delete
  -Wl,--wrap=operator\ new[]
  -Wl,--wrap=operator\ delete[]
EOF
  fi

  cat >> "$WRAPPER_PATH" <<EOF
)

# Проверяем, нужна ли линковка
# Линковка НЕ нужна только если:
# 1. Есть флаг -c И нет выходного файла (-o)
# 2. Или есть флаг -S (только ассемблер)
# 3. Или есть флаг -E (только препроцессор)
LINKING_STAGE=true
HAS_C_FLAG=false
HAS_OUTPUT_FILE=false

for arg in "\$@"; do
  if [[ "\$arg" == "-c" ]]; then
    HAS_C_FLAG=true
  elif [[ "\$arg" == "-o" ]]; then
    HAS_OUTPUT_FILE=true
  elif [[ "\$arg" == "-S" || "\$arg" == "-E" ]]; then
    LINKING_STAGE=false
    break
  fi
done

# Если есть -c но нет -o, то это только компиляция без линковки
if [ "\$HAS_C_FLAG" = true ] && [ "\$HAS_OUTPUT_FILE" = false ]; then
  LINKING_STAGE=false
fi

# Если вызывают справку/версию — передаём без изменений
for arg in "\$@"; do
  if [[ "\$arg" == "-h" || "\$arg" == "--help" || "\$arg" == "-v" || "\$arg" == "--version" ]]; then
    exec "\$REAL_COMPILER" "\$@"
  fi
done

# Если это финальная линковка → добавляем LeakAnalyze
if [ "\$LINKING_STAGE" = true ]; then
  exec "\$REAL_COMPILER" "\$@" "\${LIB[@]}" "\${WRAP_FLAGS[@]}"
else
  # Если это только компиляция .c/.cpp → .o, не добавляем ничего
  exec "\$REAL_COMPILER" "\$@"
fi
EOF

  chmod +x "$WRAPPER_PATH"
  echo "✓ Создана обёртка для $COMPILER"
}

# Создаём обёртки для gcc и g++
create_wrapper "gcc"
create_wrapper "g++"

# === Обновление .bogachev_env ===
echo ""
info "Обновление конфигурации..."

# Создаём .bogachev_env если его нет
if [ ! -f "$BOGACHEV_ENV" ]; then
  echo "Создаю файл ~/.bogachev_env"
  touch "$BOGACHEV_ENV"
fi

# Проверяем, есть ли уже настройки LeakAnalyze в .bogachev_env
if ! grep -q "LeakAnalyze" "$BOGACHEV_ENV"; then
  cat >> "$BOGACHEV_ENV" <<EOF

# LeakAnalyze compiler integration
export LEAKANALYZE_HOME="\$HOME/bogachev/bin/LeakAnalyze"
export PATH="\$HOME/bogachev/bin:\$PATH"
EOF
  echo "✓ Добавлены настройки LeakAnalyze в ~/.bogachev_env"
else
  echo "✓ Настройки LeakAnalyze уже присутствуют в ~/.bogachev_env"
fi

# === Добавление .bogachev_env в .bashrc ===
echo ""
info "Настройка автоматической загрузки..."

# Проверяем, есть ли уже загрузка .bogachev_env в .bashrc
if ! grep -q "bogachev_env" "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<'EOF'

# Source bogachev environment if it exists (interactive shells only)
if [ -f "$HOME/.bogachev_env" ]; then
  case "$-" in
    *i*) source "$HOME/.bogachev_env" ;;
  esac
fi
EOF
  echo "✓ Добавлена автоматическая загрузка ~/.bogachev_env в ~/.bashrc"
else
  echo "✓ Автоматическая загрузка ~/.bogachev_env уже настроена в ~/.bashrc"
fi

# Обновляем PATH в текущей сессии
export PATH="$HOME/bogachev/bin:$PATH"

# === Проверка установки ===
echo ""
info "Проверка установки..."

# Загружаем переменные из .bogachev_env если файл существует
if [ -f "$BOGACHEV_ENV" ]; then
  source "$BOGACHEV_ENV"
fi

# Убеждаемся, что PATH обновлён
export PATH="$HOME/bogachev/bin:$PATH"

# Проверяем доступность обёрток
if [ -x "$BOGACHEV_BIN/gcc" ] && [ -x "$BOGACHEV_BIN/g++" ]; then
  success "✓ Обёртки gcc и g++ созданы"
else
  error "Ошибка создания обёрток"
  exit 1
fi

# Проверяем наличие LeakAnalyze
if [ -x "$BOGACHEV_BIN/LeakAnalyze/LeakAnalyze" ]; then
  success "✓ LeakAnalyze установлен"
else
  error "Ошибка установки LeakAnalyze"
  exit 1
fi

# === Тестовая компиляция ===
echo ""
info "Тестовая компиляция..."

# Создаём временный тестовый файл
TEST_FILE="/tmp/test_leakanalyze_$$.c"
cat > "$TEST_FILE" <<'EOF'
#include <stdlib.h>
#include <stdio.h>

int main() {
    char *ptr = malloc(100);
    printf("Test: %p\n", ptr);
    free(ptr);
    return 0;
}
EOF

# Тестируем gcc
if "$BOGACHEV_BIN/gcc" -o "/tmp/test_leakanalyze_$$" "$TEST_FILE" 2>/dev/null; then
  success "✓ Тестовая компиляция с gcc прошла успешно"
  rm -f "/tmp/test_leakanalyze_$$"
else
  warning "⚠ Тестовая компиляция с gcc не удалась (возможно, системные библиотеки)"
fi

# Очищаем тестовый файл
rm -f "$TEST_FILE"

# === Завершение ===
CLEANUP_REQUIRED=false

echo ""
success "=========================================="
success "  ✓ Установка LeakAnalyze завершена!"
success "=========================================="
echo ""
echo "Установленные компоненты:"
echo "  • LeakAnalyze: $BOGACHEV_BIN/LeakAnalyze/"
echo "  • Обёртка gcc: $BOGACHEV_BIN/gcc"
echo "  • Обёртка g++: $BOGACHEV_BIN/g++"
echo ""
echo "Особенности:"
echo "  • Библиотеки подставляются ТОЛЬКО при линковке (флаг -c отключает)"
echo "  • Поддержка как gcc, так и g++"
echo "  • Интеграция с bog_push системой"
echo "  • Автоматический откат при ошибках"
echo ""
echo "Использование:"
echo "  • gcc program.c -o program    # с LeakAnalyze"
echo "  • gcc -c program.c           # без LeakAnalyze (только компиляция)"
echo "  • g++ program.cpp -o program # с LeakAnalyze"
echo ""
echo "Для активации окружения выберите вариант:"
echo "  1) Автоматически запустить новую оболочку с загруженным окружением (рекомендовано)"
echo "  2) Я загружу вручную (source ~/.bashrc)"
echo ""

read -p "Введите ваш выбор [1/2]: " -r RELOAD_CHOICE

case "$RELOAD_CHOICE" in
  1)
    echo ""
    echo "Запускаю новую оболочку с загруженным окружением..."
    echo "Наберите 'exit' для выхода и возврата в предыдущую оболочку."
    echo ""
    # Загружаем окружение и стартуем новый интерактивный bash
    exec bash --rcfile <(cat ~/.bashrc; echo "source $BOGACHEV_ENV"; echo "echo ''; echo '✓ Окружение загружено. Доступны gcc/g++ с LeakAnalyze'; echo ''")
    ;;
  2)
    echo ""
    echo "Чтобы активировать окружение вручную, выполните одну из команд:"
    echo ""
    echo "  source ~/.bashrc"
    echo ""
    echo "Или просто откройте новый терминал — настройки загрузятся автоматически."
    echo ""
    ;;
  *)
    echo ""
    echo "Неверный выбор. Пожалуйста, выполните вручную:"
    echo ""
    echo "  source ~/.bashrc"
    echo ""
    echo "Или откройте новый терминал."
    echo ""
    ;;
esac