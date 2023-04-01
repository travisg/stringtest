
TARGET := string_tests
BUILDDIR := build-$(TARGET)

# compiler flags, default libs to link against
COMPILEFLAGS := -g -O2 -Wall -W -I. -Wno-unused-parameter -fno-builtin
CFLAGS :=
CXXFLAGS := -std=c++11
ASMFLAGS :=
LDFLAGS :=
LDLIBS :=

UNAME := $(shell uname -s)
ARCH := $(shell uname -m)

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
endif
NOECHO ?= @

OBJS := \
	string_tests.o \
	asm.o

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
