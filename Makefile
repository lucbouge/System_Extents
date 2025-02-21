OS := $(shell uname)

# export O_CFLAGS := $(CFLAGS)
CFLAGS := -I$(OS) -I. # -O
ADDITIONAL_CFLAGS := -Wall -pedantic -g -Wno-nullability-extension
COMPILE := gcc $(CFLAGS) $(ADDITIONAL_CFLAGS)

C_FILES := $(wildcard *.c $(OS)/*.c)
C_FILES_EXCLUDE := fiemap.c mkself.c $(wildcard *_original.c)
C_FILES := $(filter-out $(C_FILES_EXCLUDE), $(C_FILES))
H_FILES := $(wildcard *.h $(OS)/*.h)
O_FILES := $(C_FILES:%.c=%.o)

MAKEFILE_FILES := Makefile Makefile.d



################################################################################

TARGET := extents
.DEFAULT_GOAL:=$(TARGET)

.PHONY: all dependencies install test clean

clean:
	rm -rf $(O_FILES) $(TARGET) $(D_FILES)

all: $(TARGET)

Makefile.d: $(C_FILES) $(H_FILES) 
	$(COMPILE) -MM $^ > $@

################################################################################

include Makefile.d

$(TARGET): $(O_FILES) 
	$(COMPILE) -o $@ $^

$(O_FILES):%.o:%.c $(MAKEFILE_FILES)
	$(COMPILE) -c $< -o $@

################################################################################

test:
	TEST_DIR=. ./tests-ccmp



