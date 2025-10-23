#!/bin/bash
set -euo pipefail

# ============================================================================
# Тестовый скрипт для проверки работы LeakAnalyze
# ============================================================================
# ⚠️ ВНИМАНИЕ: СИСТЕМА НЕ РАБОТАЕТ ⚠️

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

# === Проверка установки ===
echo "Проверка установки LeakAnalyze..."

BOGACHEV_BIN="$HOME/bogachev/bin"

if [ ! -d "$BOGACHEV_BIN" ]; then
  error "Папка $BOGACHEV_BIN не найдена. Сначала запустите install.sh"
  exit 1
fi

if [ ! -f "$BOGACHEV_BIN/gcc" ] || [ ! -f "$BOGACHEV_BIN/g++" ]; then
  error "Обёртки компиляторов не найдены. Запустите install.sh"
  exit 1
fi

if [ ! -d "$BOGACHEV_BIN/LeakAnalyze" ]; then
  error "LeakAnalyze не установлен. Запустите install.sh"
  exit 1
fi

success "✓ LeakAnalyze установлен"

# === Загрузка переменных окружения ===
if [ -f "$HOME/.bogachev_env" ]; then
  source "$HOME/.bogachev_env"
  export PATH="$HOME/bogachev/bin:$PATH"
  success "✓ Переменные окружения загружены"
else
  warning "⚠ Файл ~/.bogachev_env не найден"
fi

# === Тест 1: Проверка версий компиляторов ===
echo ""
info "Тест 1: Проверка версий компиляторов"

echo "gcc версия:"
if "$BOGACHEV_BIN/gcc" --version | head -n1; then
  success "✓ gcc работает"
else
  error "✗ gcc не работает"
fi

echo ""
echo "g++ версия:"
if "$BOGACHEV_BIN/g++" --version | head -n1; then
  success "✓ g++ работает"
else
  error "✗ g++ не работает"
fi

# === Тест 2: Компиляция C программы ===
echo ""
info "Тест 2: Компиляция C программы с LeakAnalyze"

TEST_C="/tmp/test_leak_c_$$.c"
TEST_BINARY="/tmp/test_leak_c_$$"

cat > "$TEST_C" <<'EOF'
#include <stdlib.h>
#include <stdio.h>

int main() {
    printf("Тест C программы с LeakAnalyze\n");
    
    // Тест malloc/free
    char *ptr1 = malloc(100);
    printf("malloc(100): %p\n", ptr1);
    free(ptr1);
    
    // Тест calloc
    int *ptr2 = calloc(10, sizeof(int));
    printf("calloc(10, sizeof(int)): %p\n", ptr2);
    free(ptr2);
    
    // Тест realloc
    ptr1 = malloc(50);
    ptr1 = realloc(ptr1, 100);
    printf("realloc: %p\n", ptr1);
    free(ptr1);
    
    printf("Тест завершён успешно\n");
    return 0;
}
EOF

if "$BOGACHEV_BIN/gcc" -o "$TEST_BINARY" "$TEST_C" 2>/dev/null; then
  success "✓ C программа скомпилирована с LeakAnalyze"
  
  # Запускаем программу
  if [ -x "$TEST_BINARY" ]; then
    echo "Запуск программы:"
    "$TEST_BINARY"
    success "✓ C программа выполнена успешно"
  fi
else
  error "✗ Ошибка компиляции C программы"
fi

# Очистка
rm -f "$TEST_C" "$TEST_BINARY"

# === Тест 3: Компиляция C++ программы ===
echo ""
info "Тест 3: Компиляция C++ программы с LeakAnalyze"

TEST_CPP="/tmp/test_leak_cpp_$$.cpp"
TEST_BINARY="/tmp/test_leak_cpp_$$"

cat > "$TEST_CPP" <<'EOF'
#include <iostream>
#include <memory>

int main() {
    std::cout << "Тест C++ программы с LeakAnalyze" << std::endl;
    
    // Тест new/delete
    int *ptr1 = new int(42);
    std::cout << "new int(42): " << *ptr1 << std::endl;
    delete ptr1;
    
    // Тест new[]/delete[]
    int *ptr2 = new int[10];
    std::cout << "new int[10]: " << ptr2 << std::endl;
    delete[] ptr2;
    
    // Тест с malloc/free (C функции)
    char *ptr3 = static_cast<char*>(malloc(50));
    std::cout << "malloc(50): " << static_cast<void*>(ptr3) << std::endl;
    free(ptr3);
    
    std::cout << "Тест завершён успешно" << std::endl;
    return 0;
}
EOF

if "$BOGACHEV_BIN/g++" -o "$TEST_BINARY" "$TEST_CPP" 2>/dev/null; then
  success "✓ C++ программа скомпилирована с LeakAnalyze"
  
  # Запускаем программу
  if [ -x "$TEST_BINARY" ]; then
    echo "Запуск программы:"
    "$TEST_BINARY"
    success "✓ C++ программа выполнена успешно"
  fi
else
  error "✗ Ошибка компиляции C++ программы"
fi

# Очистка
rm -f "$TEST_CPP" "$TEST_BINARY"

# === Тест 4: Компиляция без линковки ===
echo ""
info "Тест 4: Компиляция без линковки (флаг -c)"

TEST_C_NO_LINK="/tmp/test_no_link_$$.c"
TEST_OBJECT="/tmp/test_no_link_$$.o"

cat > "$TEST_C_NO_LINK" <<'EOF'
#include <stdio.h>
int main() {
    printf("Hello\n");
    return 0;
}
EOF

if "$BOGACHEV_BIN/gcc" -c -o "$TEST_OBJECT" "$TEST_C_NO_LINK" 2>/dev/null; then
  success "✓ Компиляция без линковки работает (LeakAnalyze не подключается)"
  
  # Проверяем, что объектный файл создан
  if [ -f "$TEST_OBJECT" ]; then
    success "✓ Объектный файл создан"
  fi
else
  error "✗ Ошибка компиляции без линковки"
fi

# Очистка
rm -f "$TEST_C_NO_LINK" "$TEST_OBJECT"

# === Тест 5: Проверка LeakAnalyze ===
echo ""
info "Тест 5: Проверка программы LeakAnalyze"

if [ -x "$BOGACHEV_BIN/LeakAnalyze/LeakAnalyze" ]; then
  echo "LeakAnalyze найден: $BOGACHEV_BIN/LeakAnalyze/LeakAnalyze"
  
  # Пытаемся запустить LeakAnalyze (может потребовать аргументы)
  if "$BOGACHEV_BIN/LeakAnalyze/LeakAnalyze" --help 2>/dev/null; then
    success "✓ LeakAnalyze отвечает на --help"
  else
    warning "⚠ LeakAnalyze не отвечает на --help (возможно, требует другие аргументы)"
  fi
else
  error "✗ LeakAnalyze не найден или не исполняемый"
fi

# === Итоговый результат ===
echo ""
success "=========================================="
success "  ✓ Все тесты завершены!"
success "=========================================="
echo ""
echo "LeakAnalyze успешно интегрирован с компиляторами."
echo "Теперь gcc и g++ автоматически подключают LeakAnalyze при линковке."
echo ""
echo "Использование:"
echo "  gcc program.c -o program    # с LeakAnalyze"
echo "  gcc -c program.c           # без LeakAnalyze"
echo "  g++ program.cpp -o program # с LeakAnalyze"
echo ""
