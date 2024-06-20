UNAME := $(shell uname -s)
ARCH := $(shell uname -m)

#$(info UNAME = $(UNAME))
#$(info ARCH = $(ARCH))

TARGET := string_tests
BUILDDIR := build-$(TARGET)-$(ARCH)

# compiler flags, default libs to link against
COMPILEFLAGS := -g -O2 -Wall -W -I. -Wno-unused-parameter -Wno-unused-function -fno-builtin
CFLAGS :=
CXXFLAGS :=
ASMFLAGS :=
LDFLAGS := -static
LDLIBS :=

# switch any platform specific stuff here
# ifeq ($(findstring CYGWIN,$(UNAME)),CYGWIN)
# ...
# endif
ifeq ($(UNAME),Darwin)
CC := clang
CPLUSPLUS := clang++
COMPILEFLAGS += -I/opt/local/include
LDFLAGS += -L/opt/local/lib
LDLIBS +=
OTOOL := otool
endif
ifeq ($(UNAME),Linux)
CC := cc
CPLUSPLUS := c++
OBJDUMP := objdump
LDLIBS +=

ifeq ($(ARCH),riscv64)
# try to tweak for a sifive u74 (visionfive 2)
COMPILEFLAGS += -mtune=sifive-u74 -march=rv64gc_zba_zbb
# try to tweak for a spacemit-k60 (banana pi f3)
#COMPILEFLAGS += -mtune=sifive-u74 -march=rv64gcv_zba_zbb_zbc_zbs
endif

endif
NOECHO ?= @

OBJS := \
	string_tests.o \
	myroutines.o \
	asm-$(ARCH).o

OBJS := $(addprefix $(BUILDDIR)/,$(OBJS))
DEPS := $(OBJS:.o=.d)

.PHONY: all
all: $(BUILDDIR)/$(TARGET) $(BUILDDIR)/$(TARGET).lst

$(BUILDDIR)/$(TARGET): $(OBJS)
	@$(MKDIR)
	@echo linking $<
	$(NOECHO)$(CPLUSPLUS) $(LDFLAGS) $(OBJS) -o $@ $(LDLIBS)

$(BUILDDIR)/$(TARGET).lst: $(BUILDDIR)/$(TARGET)
ifeq ($(UNAME),Darwin)
	$(OTOOL) -Vt $< | c++filt > $@
else
	$(OBJDUMP) -Cd $< > $@
endif

clean:
	rm -f $(OBJS) $(DEPS) $(TARGET)

spotless:
	rm -rf build-*

# makes sure the target dir exists
MKDIR = if [ ! -d $(dir $@) ]; then mkdir -p $(dir $@); fi

$(BUILDDIR)/%.o: %.c
	@$(MKDIR)
	@echo compiling $<
	$(NOECHO)$(CC) $(COMPILEFLAGS) $(CFLAGS) -c $< -MD -MT $@ -MF $(@:%o=%d) -o $@

$(BUILDDIR)/%.o: %.cpp
	@$(MKDIR)
	@echo compiling $<
	$(NOECHO)$(CPLUSPLUS) $(COMPILEFLAGS) $(CXXFLAGS) -c $< -MD -MT $@ -MF $(@:%o=%d) -o $@

$(BUILDDIR)/%.o: %.S
	@$(MKDIR)
	@echo compiling $<
	$(NOECHO)$(CC) $(COMPILEFLAGS) $(ASMFLAGS) -c $< -MD -MT $@ -MF $(@:%o=%d) -o $@

ifeq ($(filter $(MAKECMDGOALS), clean), )
-include $(DEPS)
endif
