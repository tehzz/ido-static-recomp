BUILD_DIR := build

SUPPORTED_IDO := 5.3 7.1
IDO71_PROGS := bin/cc lib/as1 lib/cfe lib/ugen lib/uopt
IDO53_PROGS := bin/cc lib/acpp lib/as lib/as0 lib/as1 lib/cfe lib/copt lib/ugen lib/ujoin \
               lib/uld lib/umerge lib/uopt lib/usplit
IRIX_BIN_DIR ?= NOT_SUPPLIED

# Host Detection
ifeq ($(OSTYPE),cygwin)
  HOST_OS := cygwin
else
  ifeq ($(shell which uname),"")
    $(error can't find uname)
  else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Linux)
      HOST_OS := linux
    else
    ifeq ($(UNAME_S),Darwin)
      HOST_OS := macos
	  HOST_MACOS := 1
    else
      $(error Unsupported host $(UNAME_S))
	endif
	endif
  endif
endif

# Check IDO Version to build
ifeq (,$(findstring $(MAKECMDGOALS),clean))
ifeq ($(IRIX_BIN_DIR),NOT_SUPPLIED)
  $(error Please supply the location of native irix binaries)
endif
endif

# TODO: User can override version through CLI
ifneq ($(findstring 5.3,$(IRIX_BIN_DIR)),)
  IDO_VERSION ?= 5.3
  TARGETS := $(IDO53_PROGS)
  IDO_DEF := -DIDO53
else
ifneq ($(findstring 7.1,$(IRIX_BIN_DIR)),)
  IDO_VERSION ?= 7.1
  TARGETS := $(IDO71_PROGS)
  IDO_DEF := -DIDO71
else
  $(info IDO Version could not be determined by IDO binary path)
endif
endif

IDO_OUT_DIR := $(BUILD_DIR)/$(IDO_VERSION)
OUTPUTS := $(addprefix $(IDO_OUT_DIR)/,$(notdir $(TARGETS)))
IDO_BIN_RAW := $(addprefix $(IRIX_BIN_DIR)/usr/,$(TARGETS))

# IDO libc shim
LIBC_SRC := libc_impl.c
LIBC_O := $(addprefix $(IDO_OUT_DIR)/,$(patsubst %.c,%.o,$(LIBC_SRC)))

# for build `recomp`
CXX := g++
CXXFLAGS := -O2 -std=c++11 -Wno-switch -lcapstone
# building the translated irix binaries
CC := gcc
CFLAGS := -g -fno-strict-aliasing -lm $(if $(HOST_MACOS),-fno-pie,-no-pie)


# Translate and Recompile Binaries
# param $(1): program irix /usr/ path [bin/cc, lib/as1, etc.]
define TRANSLATE_AND_COMPILE
$(IDO_OUT_DIR)/src/$(1).c: $(IRIX_BIN_DIR)/usr/$(1) $(BUILD_DIR)/recomp | $$$$(@D)/.
	$(BUILD_DIR)/recomp $$(CONSERVATIVE) $$< > $$@

$(IDO_OUT_DIR)/$(notdir $(1)): $(IDO_OUT_DIR)/src/$(1).c $(LIBC_O) | $$$$(@D)/.
	$$(CC) $$^ -o $$@ $$(CFLAGS) -I.
endef

# Need the conservative flag
ifeq ($(IDO_VERSION),5.3)
$(IDO_OUT_DIR)/ugen: CONSERVATIVE := --conservative
endif

# Error strings
ERRSTR_SRC := $(IRIX_BIN_DIR)/usr/lib/err.english.cc
ERRSTR_CPY := $(IDO_OUT_DIR)/$(notdir $(ERRSTR_SRC))


.PHONY: default test clean build
.PRECIOUS: $(BUILD_DIR)/. $(BUILD_DIR)%/.

default: test

test: 
	@echo $(HOST_OS) $(IRIX_BIN_DIR) $(IDO_VERSION)
	@echo $(OUTPUTS)
	@echo $(IDO_BIN_RAW)

# http://ismail.badawi.io/blog/2017/03/28/automatic-directory-creation-in-make/
$(BUILD_DIR)/.:
	mkdir -p $@

$(BUILD_DIR)%/.:
	mkdir -p $@

.SECONDEXPANSION:

$(BUILD_DIR)/recomp: recomp.cpp elf.h | $$(@D)/.
	$(CXX) $< -o $@ $(CXXFLAGS)

$(LIBC_O): $(LIBC_SRC) libc_impl.h helpers.h | $$(@D)/.
	$(CC) -c $< -o $@ $(CFLAGS) $(IDO_DEF)

$(ERRSTR_CPY): $(ERRSTR_SRC)
	cp $< $@

#delete only for testing
build: $(OUTPUTS) $(ERRSTR_CPY)

clean:
	$(RM) -rf $(BUILD_DIR)

$(foreach p,$(TARGETS),$(eval $(call TRANSLATE_AND_COMPILE,$(p))))
