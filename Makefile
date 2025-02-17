OS := $(shell uname)

# export O_CFLAGS := $(CFLAGS)
CFLAGS := -I$(OS) -I. # -O
COMPILE := gcc $(CFLAGS)

C_FILES := $(wildcard *.c $(OS)/*.c)
C_FILES_EXCLUDE := fiemap.c mkself.c
C_FILES := $(filter-out $(C_FILES_EXCLUDE), $(C_FILES))
H_FILES := $(wildcard *.h $(OS)/*.h)
O_FILES := $(C_FILES:%.c=%.o)
D_FILES := $(wildcard *.d)

################################################################################

TARGET = extents

.DEFAULT: all
.PHONY: all dependencies install test clean

clean:
	rm -rf $(O_FILES) $(TARGET) $(D_FILES)

all: Makefile.d 
	$(MAKE) $(TARGET)

Makefile.d: $(C_FILES) $(H_FILES) 
	$(COMPILE) -MM $^ > $@

################################################################################

include Makefile.d

$(TARGET): $(O_FILES)
	$(COMPILE) -o $@ $^

$(O_FILES):%.o:%.c
	$(COMPILE) -c $< -o $@

################################################################################

test:
	TEST_DIR=. ./tests-ccmp



