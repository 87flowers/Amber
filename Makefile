.RECIPEPREFIX = >
SUFFIX :=

EXE ?= amber

BUILD_DIR := ./build

all: $(EXE)

$(EXE):
> @mkdir -p $(BUILD_DIR)
> nasm -f elf64 src/main.s -o $(BUILD_DIR)/amber.o
> ld -s -no-pie -z noseparate-code --strip-all $(BUILD_DIR)/amber.o -o $(EXE)
> strip --strip-section-headers --discard-all amber

bench: $(EXE)
> ./$(EXE) bench

.PHONY: all $(EXE)
