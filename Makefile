# Define the default target now so that it is always the first target
BUILD_TARGETS = \
	main quantize quantize-stats perplexity imatrix embedding vdot q8dot train-text-from-scratch convert-moses2c-to-ggml \
	simple batched batched-bench save-load-state server gguf moses-bench libllava.a llava-cli baby-moses beam-search  \
	speculative infill tokenize benchmark-matmult parallel finetune export-lora lookahead lookup passkey tests/test-c.o

# Binaries only useful for tests
TEST_TARGETS = \
	tests/test-moses-grammar tests/test-grammar-parser tests/test-double-float tests/test-grad0 tests/test-opt \
	tests/test-quantize-fns tests/test-quantize-perf tests/test-sampling tests/test-tokenizer-0-moses          \
	tests/test-tokenizer-0-falcon tests/test-tokenizer-1-moses tests/test-tokenizer-1-bpe tests/test-rope      \
	tests/test-backend-ops tests/test-model-load-cancel tests/test-autorelease

# Code coverage output files
COV_TARGETS = *.gcno tests/*.gcno *.gcda tests/*.gcda *.gcov tests/*.gcov lcov-report gcovr-report

ifndef UNAME_S
UNAME_S := $(shell uname -s)
endif

ifndef UNAME_P
UNAME_P := $(shell uname -p)
endif

ifndef UNAME_M
UNAME_M := $(shell uname -m)
endif

# Mac OS + Arm can report x86_64
# ref: https://github.com/l1fetech/whisper.cpp/issues/66#issuecomment-1282546789
ifeq ($(UNAME_S),Darwin)
	ifndef MOSES_NO_METAL
		MOSES_METAL := 1
	endif

	ifneq ($(UNAME_P),arm)
		SYSCTL_M := $(shell sysctl -n hw.optional.arm64 2>/dev/null)
		ifeq ($(SYSCTL_M),1)
			# UNAME_P := arm
			# UNAME_M := arm64
			warn := $(warning Your arch is announced as x86_64, but it seems to actually be ARM64. Not fixing that can lead to bad performance. For more info see: https://github.com/l1fetech/whisper.cpp/issues/66\#issuecomment-1282546789)
		endif
	endif
endif

default: $(BUILD_TARGETS)

test: $(TEST_TARGETS)
	@failures=0; \
	for test_target in $(TEST_TARGETS); do \
		if [ "$$test_target" = "tests/test-tokenizer-0-moses" ]; then \
			./$$test_target $(CURDIR)/models/ggml-vocab-moses.gguf; \
		elif [ "$$test_target" = "tests/test-tokenizer-0-falcon" ]; then \
			./$$test_target $(CURDIR)/models/ggml-vocab-falcon.gguf; \
		elif [ "$$test_target" = "tests/test-tokenizer-1-moses" ]; then \
			continue; \
		elif [ "$$test_target" = "tests/test-tokenizer-1-bpe" ]; then \
			continue; \
		else \
			echo "Running test $$test_target..."; \
			./$$test_target; \
		fi; \
		if [ $$? -ne 0 ]; then \
			printf 'Test %s FAILED!\n\n' $$test_target; \
			failures=$$(( failures + 1 )); \
		else \
			printf 'Test %s passed.\n\n' $$test_target; \
		fi; \
	done; \
	if [ $$failures -gt 0 ]; then \
		printf '\n%s tests failed.\n' $$failures; \
		exit 1; \
	fi
	@echo 'All tests passed.'

all: $(BUILD_TARGETS) $(TEST_TARGETS)

coverage: ## Run code coverage
	gcov -pb tests/*.cpp

lcov-report: coverage ## Generate lcov report
	mkdir -p lcov-report
	lcov --capture --directory . --output-file lcov-report/coverage.info
	genhtml lcov-report/coverage.info --output-directory lcov-report

gcovr-report: coverage ## Generate gcovr report
	mkdir -p gcovr-report
	gcovr --root . --html --html-details --output gcovr-report/coverage.html

ifdef RISCV_CROSS_COMPILE
CC	:= riscv64-unknown-linux-gnu-gcc
CXX	:= riscv64-unknown-linux-gnu-g++
endif

#
# Compile flags
#

# keep standard at C11 and C++11
MK_CPPFLAGS = -I. -Icommon
MK_CFLAGS   = -std=c11   -fPIC
MK_CXXFLAGS = -std=c++11 -fPIC

# -Ofast tends to produce faster code, but may not be available for some compilers.
ifdef MOSES_FAST
MK_CFLAGS     += -Ofast
HOST_CXXFLAGS += -Ofast
MK_NVCCFLAGS  += -O3
else
MK_CFLAGS     += -O3
MK_CXXFLAGS   += -O3
endif

# clock_gettime came in POSIX.1b (1993)
# CLOCK_MONOTONIC came in POSIX.1-2001 / SUSv3 as optional
# posix_memalign came in POSIX.1-2001 / SUSv3
# M_PI is an XSI extension since POSIX.1-2001 / SUSv3, came in XPG1 (1985)
MK_CPPFLAGS += -D_XOPEN_SOURCE=600

# Somehow in OpenBSD whenever POSIX conformance is specified
# some string functions rely on locale_t availability,
# which was introduced in POSIX.1-2008, forcing us to go higher
ifeq ($(UNAME_S),OpenBSD)
	MK_CPPFLAGS += -U_XOPEN_SOURCE -D_XOPEN_SOURCE=700
endif

# Data types, macros and functions related to controlling CPU affinity and
# some memory allocation are available on Linux through GNU extensions in libc
ifeq ($(UNAME_S),Linux)
	MK_CPPFLAGS += -D_GNU_SOURCE
endif

# RLIMIT_MEMLOCK came in BSD, is not specified in POSIX.1,
# and on macOS its availability depends on enabling Darwin extensions
# similarly on DragonFly, enabling BSD extensions is necessary
ifeq ($(UNAME_S),Darwin)
	MK_CPPFLAGS += -D_DARWIN_C_SOURCE
endif
ifeq ($(UNAME_S),DragonFly)
	MK_CPPFLAGS += -D__BSD_VISIBLE
endif

# alloca is a non-standard interface that is not visible on BSDs when
# POSIX conformance is specified, but not all of them provide a clean way
# to enable it in such cases
ifeq ($(UNAME_S),FreeBSD)
	MK_CPPFLAGS += -D__BSD_VISIBLE
endif
ifeq ($(UNAME_S),NetBSD)
	MK_CPPFLAGS += -D_NETBSD_SOURCE
endif
ifeq ($(UNAME_S),OpenBSD)
	MK_CPPFLAGS += -D_BSD_SOURCE
endif

ifdef MOSES_DEBUG
	MK_CFLAGS   += -O0 -g
	MK_CXXFLAGS += -O0 -g
	MK_LDFLAGS  += -g

	ifeq ($(UNAME_S),Linux)
		MK_CXXFLAGS += -Wp,-D_GLIBCXX_ASSERTIONS
	endif
else
	MK_CPPFLAGS += -DNDEBUG
endif

ifdef MOSES_SANITIZE_THREAD
	MK_CFLAGS   += -fsanitize=thread -g
	MK_CXXFLAGS += -fsanitize=thread -g
	MK_LDFLAGS  += -fsanitize=thread -g
endif

ifdef MOSES_SANITIZE_ADDRESS
	MK_CFLAGS   += -fsanitize=address -fno-omit-frame-pointer -g
	MK_CXXFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
	MK_LDFLAGS  += -fsanitize=address -fno-omit-frame-pointer -g
endif

ifdef MOSES_SANITIZE_UNDEFINED
	MK_CFLAGS   += -fsanitize=undefined -g
	MK_CXXFLAGS += -fsanitize=undefined -g
	MK_LDFLAGS  += -fsanitize=undefined -g
endif

ifdef MOSES_SERVER_VERBOSE
	MK_CPPFLAGS += -DSERVER_VERBOSE=$(MOSES_SERVER_VERBOSE)
endif


ifdef MOSES_CODE_COVERAGE
	MK_CXXFLAGS += -fprofile-arcs -ftest-coverage -dumpbase ''
endif

ifdef MOSES_DISABLE_LOGS
	MK_CPPFLAGS += -DLOG_DISABLE_LOGS
endif # MOSES_DISABLE_LOGS

# warnings
WARN_FLAGS    = -Wall -Wextra -Wpedantic -Wcast-qual -Wno-unused-function
MK_CFLAGS    += $(WARN_FLAGS) -Wshadow -Wstrict-prototypes -Wpointer-arith -Wmissing-prototypes -Werror=implicit-int \
				-Werror=implicit-function-declaration
MK_CXXFLAGS  += $(WARN_FLAGS) -Wmissing-declarations -Wmissing-noreturn

# this version of Apple ld64 is buggy
ifneq '' '$(findstring dyld-1015.7,$(shell $(CC) $(LDFLAGS) -Wl,-v 2>&1))'
	MK_CPPFLAGS += -DHAVE_BUGGY_APPLE_LINKER
endif

# OS specific
# TODO: support Windows
ifneq '' '$(filter $(UNAME_S),Linux Darwin FreeBSD NetBSD OpenBSD Haiku)'
	MK_CFLAGS   += -pthread
	MK_CXXFLAGS += -pthread
endif

# detect Windows
ifneq ($(findstring _NT,$(UNAME_S)),)
	_WIN32 := 1
endif

# library name prefix
ifneq ($(_WIN32),1)
	LIB_PRE := lib
endif

# Dynamic Shared Object extension
ifneq ($(_WIN32),1)
	DSO_EXT := .so
else
	DSO_EXT := .dll
endif

# Windows Sockets 2 (Winsock) for network-capable apps
ifeq ($(_WIN32),1)
	LWINSOCK2 := -lws2_32
endif

ifdef MOSES_GPROF
	MK_CFLAGS   += -pg
	MK_CXXFLAGS += -pg
endif
ifdef MOSES_PERF
	MK_CPPFLAGS += -DGGML_PERF
endif

# Architecture specific
# TODO: probably these flags need to be tweaked on some architectures
#       feel free to update the Makefile for your architecture and send a pull request or issue

ifndef RISCV

ifeq ($(UNAME_M),$(filter $(UNAME_M),x86_64 i686 amd64))
	# Use all CPU extensions that are available:
	MK_CFLAGS     += -march=native -mtune=native
	HOST_CXXFLAGS += -march=native -mtune=native

	# Usage AVX-only
	#MK_CFLAGS   += -mfma -mf16c -mavx
	#MK_CXXFLAGS += -mfma -mf16c -mavx

	# Usage SSSE3-only (Not is SSE3!)
	#MK_CFLAGS   += -mssse3
	#MK_CXXFLAGS += -mssse3
endif

ifneq '' '$(findstring mingw,$(shell $(CC) -dumpmachine))'
	# The stack is only 16-byte aligned on Windows, so don't let gcc emit aligned moves.
	# https://gcc.gnu.org/bugzilla/show_bug.cgi?id=54412
	# https://github.com/l1fetech/moses.cpp/issues/2922
	MK_CFLAGS   += -Xassembler -muse-unaligned-vector-move
	MK_CXXFLAGS += -Xassembler -muse-unaligned-vector-move

	# Target Windows 8 for PrefetchVirtualMemory
	MK_CPPFLAGS += -D_WIN32_WINNT=0x602
endif

ifneq ($(filter aarch64%,$(UNAME_M)),)
	# Apple M1, M2, etc.
	# Raspberry Pi 3, 4, Zero 2 (64-bit)
	# Nvidia Jetson
	MK_CFLAGS   += -mcpu=native
	MK_CXXFLAGS += -mcpu=native
	JETSON_RELEASE_INFO = $(shell jetson_release)
	ifdef JETSON_RELEASE_INFO
		ifneq ($(filter TX2%,$(JETSON_RELEASE_INFO)),)
			JETSON_EOL_MODULE_DETECT = 1
			CC = aarch64-unknown-linux-gnu-gcc
			cxx = aarch64-unknown-linux-gnu-g++
		endif
	endif
endif

ifneq ($(filter armv6%,$(UNAME_M)),)
	# Raspberry Pi 1, Zero
	MK_CFLAGS   += -mfpu=neon-fp-armv8 -mfp16-format=ieee -mno-unaligned-access
	MK_CXXFLAGS += -mfpu=neon-fp-armv8 -mfp16-format=ieee -mno-unaligned-access
endif

ifneq ($(filter armv7%,$(UNAME_M)),)
	# Raspberry Pi 2
	MK_CFLAGS   += -mfpu=neon-fp-armv8 -mfp16-format=ieee -mno-unaligned-access -funsafe-math-optimizations
	MK_CXXFLAGS += -mfpu=neon-fp-armv8 -mfp16-format=ieee -mno-unaligned-access -funsafe-math-optimizations
endif

ifneq ($(filter armv8%,$(UNAME_M)),)
	# Raspberry Pi 3, 4, Zero 2 (32-bit)
	MK_CFLAGS   += -mfp16-format=ieee -mno-unaligned-access
	MK_CXXFLAGS += -mfp16-format=ieee -mno-unaligned-access
endif

ifneq ($(filter ppc64%,$(UNAME_M)),)
	POWER9_M := $(shell grep "POWER9" /proc/cpuinfo)
	ifneq (,$(findstring POWER9,$(POWER9_M)))
		MK_CFLAGS   += -mcpu=power9
		MK_CXXFLAGS += -mcpu=power9
	endif
endif

ifneq ($(filter ppc64le%,$(UNAME_M)),)
	MK_CFLAGS   += -mcpu=powerpc64le
	MK_CXXFLAGS += -mcpu=powerpc64le
	CUDA_POWER_ARCH = 1
endif

else
	MK_CFLAGS   += -march=rv64gcv -mabi=lp64d
	MK_CXXFLAGS += -march=rv64gcv -mabi=lp64d
endif

ifdef MOSES_QKK_64
	MK_CPPFLAGS += -DGGML_QKK_64
endif

ifndef MOSES_NO_ACCELERATE
	# Mac OS - include Accelerate framework.
	# `-framework Accelerate` works both with Apple Silicon and Mac Intel
	ifeq ($(UNAME_S),Darwin)
		MK_CPPFLAGS += -DGGML_USE_ACCELERATE
		MK_CPPFLAGS += -DACCELERATE_NEW_LAPACK
		MK_CPPFLAGS += -DACCELERATE_LAPACK_ILP64
		MK_LDFLAGS  += -framework Accelerate
	endif
endif # MOSES_NO_ACCELERATE

ifdef MOSES_MPI
	MK_CPPFLAGS += -DGGML_USE_MPI
	MK_CFLAGS   += -Wno-cast-qual
	MK_CXXFLAGS += -Wno-cast-qual
	OBJS        += ggml-mpi.o
endif # MOSES_MPI

ifdef MOSES_OPENBLAS
	MK_CPPFLAGS += -DGGML_USE_OPENBLAS $(shell pkg-config --cflags-only-I openblas)
	MK_CFLAGS   += $(shell pkg-config --cflags-only-other openblas)
	MK_LDFLAGS  += $(shell pkg-config --libs openblas)
endif # MOSES_OPENBLAS

ifdef MOSES_BLIS
	MK_CPPFLAGS += -DGGML_USE_OPENBLAS -I/usr/local/include/blis -I/usr/include/blis
	MK_LDFLAGS  += -lblis -L/usr/local/lib
endif # MOSES_BLIS

ifdef MOSES_CUBLAS
	MK_CPPFLAGS  += -DGGML_USE_CUBLAS -I/usr/local/cuda/include -I/opt/cuda/include -I$(CUDA_PATH)/targets/x86_64-linux/include -I/usr/local/cuda/targets/aarch64-linux/include
	MK_LDFLAGS   += -lcuda -lcublas -lculibos -lcudart -lcublasLt -lpthread -ldl -lrt -L/usr/local/cuda/lib64 -L/opt/cuda/lib64 -L$(CUDA_PATH)/targets/x86_64-linux/lib -L/usr/local/cuda/targets/aarch64-linux/lib -L/usr/lib/wsl/lib
	OBJS         += ggml-cuda.o
	MK_NVCCFLAGS  = -use_fast_math
ifndef JETSON_EOL_MODULE_DETECT
	MK_NVCCFLAGS += --forward-unknown-to-host-compiler
endif # JETSON_EOL_MODULE_DETECT
ifdef MOSES_DEBUG
	MK_NVCCFLAGS += -lineinfo
endif # MOSES_DEBUG
ifdef MOSES_CUDA_NVCC
	NVCC = $(MOSES_CUDA_NVCC)
else
	NVCC = nvcc
endif #MOSES_CUDA_NVCC
ifdef CUDA_DOCKER_ARCH
	MK_NVCCFLAGS += -Wno-deprecated-gpu-targets -arch=$(CUDA_DOCKER_ARCH)
else ifndef CUDA_POWER_ARCH
	MK_NVCCFLAGS += -arch=native
endif # CUDA_DOCKER_ARCH
ifdef MOSES_CUDA_FORCE_DMMV
	MK_NVCCFLAGS += -DGGML_CUDA_FORCE_DMMV
endif # MOSES_CUDA_FORCE_DMMV
ifdef MOSES_CUDA_FORCE_MMQ
	MK_NVCCFLAGS += -DGGML_CUDA_FORCE_MMQ
endif # MOSES_CUDA_FORCE_MMQ
ifdef MOSES_CUDA_DMMV_X
	MK_NVCCFLAGS += -DGGML_CUDA_DMMV_X=$(MOSES_CUDA_DMMV_X)
else
	MK_NVCCFLAGS += -DGGML_CUDA_DMMV_X=32
endif # MOSES_CUDA_DMMV_X
ifdef MOSES_CUDA_MMV_Y
	MK_NVCCFLAGS += -DGGML_CUDA_MMV_Y=$(MOSES_CUDA_MMV_Y)
else ifdef MOSES_CUDA_DMMV_Y
	MK_NVCCFLAGS += -DGGML_CUDA_MMV_Y=$(MOSES_CUDA_DMMV_Y) # for backwards compatibility
else
	MK_NVCCFLAGS += -DGGML_CUDA_MMV_Y=1
endif # MOSES_CUDA_MMV_Y
ifdef MOSES_CUDA_F16
	MK_NVCCFLAGS += -DGGML_CUDA_F16
endif # MOSES_CUDA_F16
ifdef MOSES_CUDA_DMMV_F16
	MK_NVCCFLAGS += -DGGML_CUDA_F16
endif # MOSES_CUDA_DMMV_F16
ifdef MOSES_CUDA_KQUANTS_ITER
	MK_NVCCFLAGS += -DK_QUANTS_PER_ITERATION=$(MOSES_CUDA_KQUANTS_ITER)
else
	MK_NVCCFLAGS += -DK_QUANTS_PER_ITERATION=2
endif
ifdef MOSES_CUDA_PEER_MAX_BATCH_SIZE
	MK_NVCCFLAGS += -DGGML_CUDA_PEER_MAX_BATCH_SIZE=$(MOSES_CUDA_PEER_MAX_BATCH_SIZE)
else
	MK_NVCCFLAGS += -DGGML_CUDA_PEER_MAX_BATCH_SIZE=128
endif # MOSES_CUDA_PEER_MAX_BATCH_SIZE
#ifdef MOSES_CUDA_CUBLAS
#	MK_NVCCFLAGS += -DGGML_CUDA_CUBLAS
#endif # MOSES_CUDA_CUBLAS
ifdef MOSES_CUDA_CCBIN
	MK_NVCCFLAGS += -ccbin $(MOSES_CUDA_CCBIN)
endif
ggml-cuda.o: ggml-cuda.cu ggml-cuda.h
ifdef JETSON_EOL_MODULE_DETECT
	$(NVCC) -I. -Icommon -D_XOPEN_SOURCE=600 -D_GNU_SOURCE -DNDEBUG -DGGML_USE_CUBLAS -I/usr/local/cuda/include -I/opt/cuda/include -I/usr/local/cuda/targets/aarch64-linux/include -std=c++11 -O3 $(NVCCFLAGS) -Xcompiler "$(CUDA_CXXFLAGS)" -c $< -o $@
else
	$(NVCC) $(BASE_CXXFLAGS) $(NVCCFLAGS) -Wno-pedantic -Xcompiler "$(CUDA_CXXFLAGS)" -c $< -o $@
endif # JETSON_EOL_MODULE_DETECT
endif # MOSES_CUBLAS

ifdef MOSES_CLBLAST

	MK_CPPFLAGS += -DGGML_USE_CLBLAST $(shell pkg-config --cflags-only-I clblast OpenCL)
	MK_CFLAGS   += $(shell pkg-config --cflags-only-other clblast OpenCL)
	MK_CXXFLAGS += $(shell pkg-config --cflags-only-other clblast OpenCL)

	# Mac provides OpenCL as a framework
	ifeq ($(UNAME_S),Darwin)
		MK_LDFLAGS += -lclblast -framework OpenCL
	else
		MK_LDFLAGS += $(shell pkg-config --libs clblast OpenCL)
	endif
	OBJS    += ggml-opencl.o

ggml-opencl.o: ggml-opencl.cpp ggml-opencl.h
	$(CXX) $(CXXFLAGS) -c $< -o $@
endif # MOSES_CLBLAST

ifdef MOSES_VULKAN
	MK_CPPFLAGS  += -DGGML_USE_VULKAN
	MK_LDFLAGS += -lvulkan
	OBJS    += ggml-vulkan.o

ifdef MOSES_VULKAN_CHECK_RESULTS
	MK_CPPFLAGS  += -DGGML_VULKAN_CHECK_RESULTS
endif

ggml-vulkan.o: ggml-vulkan.cpp ggml-vulkan.h
	$(CXX) $(CXXFLAGS) -c $< -o $@
endif # MOSES_VULKAN

ifdef MOSES_HIPBLAS

	ifeq ($(wildcard /opt/rocm),)
		ROCM_PATH	?= /usr
		GPU_TARGETS ?= $(shell $(shell which amdgpu-arch))
	else
		ROCM_PATH	?= /opt/rocm
		GPU_TARGETS ?= $(shell $(ROCM_PATH)/llvm/bin/amdgpu-arch)
	endif
	HIPCC                   ?= $(ROCM_PATH)/bin/hipcc
	MOSES_CUDA_DMMV_X       ?= 32
	MOSES_CUDA_MMV_Y        ?= 1
	MOSES_CUDA_KQUANTS_ITER ?= 2
	MK_CPPFLAGS += -DGGML_USE_HIPBLAS -DGGML_USE_CUBLAS
ifdef MOSES_HIP_UMA
	MK_CPPFLAGS += -DGGML_HIP_UMA
endif # MOSES_HIP_UMA
	MK_LDFLAGS  += -L$(ROCM_PATH)/lib -Wl,-rpath=$(ROCM_PATH)/lib
	MK_LDFLAGS	+= -lhipblas -lamdhip64 -lrocblas
	HIPFLAGS    += $(addprefix --offload-arch=,$(GPU_TARGETS))
	HIPFLAGS    += -DGGML_CUDA_DMMV_X=$(MOSES_CUDA_DMMV_X)
	HIPFLAGS    += -DGGML_CUDA_MMV_Y=$(MOSES_CUDA_MMV_Y)
	HIPFLAGS    += -DK_QUANTS_PER_ITERATION=$(MOSES_CUDA_KQUANTS_ITER)
ifdef MOSES_CUDA_FORCE_DMMV
	HIPFLAGS 	+= -DGGML_CUDA_FORCE_DMMV
endif # MOSES_CUDA_FORCE_DMMV
	OBJS        += ggml-cuda.o
ggml-cuda.o: ggml-cuda.cu ggml-cuda.h
	$(HIPCC) $(CXXFLAGS) $(HIPFLAGS) -x hip -c -o $@ $<
endif # MOSES_HIPBLAS

ifdef MOSES_METAL
	MK_CPPFLAGS += -DGGML_USE_METAL
	MK_LDFLAGS  += -framework Foundation -framework Metal -framework MetalKit
	OBJS		+= ggml-metal.o
ifdef MOSES_METAL_NDEBUG
	MK_CPPFLAGS += -DGGML_METAL_NDEBUG
endif
endif # MOSES_METAL

ifdef MOSES_METAL
ggml-metal.o: ggml-metal.m ggml-metal.h
	$(CC) $(CFLAGS) -c $< -o $@
endif # MOSES_METAL

ifdef MOSES_MPI
ggml-mpi.o: ggml-mpi.c ggml-mpi.h
	$(CC) $(CFLAGS) -c $< -o $@
endif # MOSES_MPI

GF_CC := $(CC)
include scripts/get-flags.mk

# combine build flags with cmdline overrides
override CFLAGS    := $(MK_CPPFLAGS) $(CPPFLAGS) $(MK_CFLAGS) $(GF_CFLAGS) $(CFLAGS)
BASE_CXXFLAGS      := $(MK_CPPFLAGS) $(CPPFLAGS) $(MK_CXXFLAGS) $(CXXFLAGS)
override CXXFLAGS  := $(BASE_CXXFLAGS) $(HOST_CXXFLAGS) $(GF_CXXFLAGS)
override NVCCFLAGS := $(MK_NVCCFLAGS) $(NVCCFLAGS)
override LDFLAGS   := $(MK_LDFLAGS) $(LDFLAGS)

# identify CUDA host compiler
ifdef MOSES_CUBLAS
GF_CC := $(NVCC) $(NVCCFLAGS) 2>/dev/null .c -Xcompiler
include scripts/get-flags.mk
CUDA_CXXFLAGS := $(GF_CXXFLAGS)
endif

#
# Print build information
#

$(info I moses.cpp build info: )
$(info I UNAME_S:   $(UNAME_S))
$(info I UNAME_P:   $(UNAME_P))
$(info I UNAME_M:   $(UNAME_M))
$(info I CFLAGS:    $(CFLAGS))
$(info I CXXFLAGS:  $(CXXFLAGS))
$(info I NVCCFLAGS: $(NVCCFLAGS))
$(info I LDFLAGS:   $(LDFLAGS))
$(info I CC:        $(shell $(CC) --version | head -n 1))
$(info I CXX:       $(shell $(CXX) --version | head -n 1))
$(info )

#
# Build library
#

ggml.o: ggml.c ggml.h ggml-cuda.h
	$(CC)  $(CFLAGS)   -c $< -o $@

ggml-alloc.o: ggml-alloc.c ggml.h ggml-alloc.h
	$(CC)  $(CFLAGS)   -c $< -o $@

ggml-backend.o: ggml-backend.c ggml.h ggml-backend.h
	$(CC)  $(CFLAGS)   -c $< -o $@

ggml-quants.o: ggml-quants.c ggml.h ggml-quants.h
	$(CC) $(CFLAGS)    -c $< -o $@

OBJS += ggml-alloc.o ggml-backend.o ggml-quants.o

moses.o: moses.cpp ggml.h ggml-alloc.h ggml-backend.h ggml-cuda.h ggml-metal.h moses.h
	$(CXX) $(CXXFLAGS) -c $< -o $@

COMMON_H_DEPS = common/common.h common/sampling.h common/log.h
COMMON_DEPS   = common.o sampling.o grammar-parser.o build-info.o

common.o: common/common.cpp $(COMMON_H_DEPS)
	$(CXX) $(CXXFLAGS) -c $< -o $@

sampling.o: common/sampling.cpp $(COMMON_H_DEPS)
	$(CXX) $(CXXFLAGS) -c $< -o $@

console.o: common/console.cpp common/console.h
	$(CXX) $(CXXFLAGS) -c $< -o $@

grammar-parser.o: common/grammar-parser.cpp common/grammar-parser.h
	$(CXX) $(CXXFLAGS) -c $< -o $@

train.o: common/train.cpp common/train.h
	$(CXX) $(CXXFLAGS) -c $< -o $@

libmoses.so: moses.o ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) -shared -fPIC -o $@ $^ $(LDFLAGS)

clean:
	rm -vrf *.o tests/*.o *.so *.dll benchmark-matmult common/build-info.cpp *.dot $(COV_TARGETS) $(BUILD_TARGETS) $(TEST_TARGETS)

#
# Examples
#

main: examples/main/main.cpp                                  ggml.o moses.o $(COMMON_DEPS) console.o grammar-parser.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)
	@echo
	@echo '====  Run ./main -h for help.  ===='
	@echo

infill: examples/infill/infill.cpp                            ggml.o moses.o $(COMMON_DEPS) console.o grammar-parser.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

simple: examples/simple/simple.cpp                            ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tokenize: examples/tokenize/tokenize.cpp                      ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

batched: examples/batched/batched.cpp                         ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

batched-bench: examples/batched-bench/batched-bench.cpp       build-info.o ggml.o moses.o common.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

quantize: examples/quantize/quantize.cpp                      build-info.o ggml.o moses.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

quantize-stats: examples/quantize-stats/quantize-stats.cpp    build-info.o ggml.o moses.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

perplexity: examples/perplexity/perplexity.cpp                ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

imatrix: examples/imatrix/imatrix.cpp                         ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

embedding: examples/embedding/embedding.cpp                   ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

save-load-state: examples/save-load-state/save-load-state.cpp ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

server: examples/server/server.cpp examples/server/oai.hpp examples/server/utils.hpp examples/server/httplib.h examples/server/json.hpp examples/server/index.html.hpp examples/server/index.js.hpp examples/server/completion.js.hpp examples/llava/clip.cpp examples/llava/clip.h common/stb_image.h ggml.o moses.o $(COMMON_DEPS) grammar-parser.o $(OBJS)
	$(CXX) $(CXXFLAGS) -Iexamples/server $(filter-out %.h,$(filter-out %.hpp,$^)) -o $@ $(LDFLAGS) $(LWINSOCK2) -Wno-cast-qual

gguf: examples/gguf/gguf.cpp ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

train-text-from-scratch: examples/train-text-from-scratch/train-text-from-scratch.cpp ggml.o moses.o $(COMMON_DEPS) train.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

convert-moses2c-to-ggml: examples/convert-moses2c-to-ggml/convert-moses2c-to-ggml.cpp ggml.o moses.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

moses-bench: examples/moses-bench/moses-bench.cpp ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

libllava.a: examples/llava/llava.cpp examples/llava/llava.h examples/llava/clip.cpp examples/llava/clip.h common/stb_image.h common/base64.hpp ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) -static -fPIC -c $< -o $@ -Wno-cast-qual

llava-cli: examples/llava/llava-cli.cpp examples/llava/clip.h examples/llava/clip.cpp examples/llava/llava.h examples/llava/llava.cpp ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS) -Wno-cast-qual

baby-moses: examples/baby-moses/baby-moses.cpp ggml.o moses.o $(COMMON_DEPS) train.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

beam-search: examples/beam-search/beam-search.cpp ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

finetune: examples/finetune/finetune.cpp ggml.o moses.o $(COMMON_DEPS) train.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

export-lora: examples/export-lora/export-lora.cpp ggml.o common/common.h $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

speculative: examples/speculative/speculative.cpp ggml.o moses.o $(COMMON_DEPS) grammar-parser.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

parallel: examples/parallel/parallel.cpp ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

lookahead: examples/lookahead/lookahead.cpp ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

lookup: examples/lookup/lookup.cpp ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

passkey: examples/passkey/passkey.cpp ggml.o moses.o $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

ifeq ($(UNAME_S),Darwin)
swift: examples/batched.swift
	(cd examples/batched.swift; make build)
endif

common/build-info.cpp: $(wildcard .git/index) scripts/build-info.sh
	@sh scripts/build-info.sh $(CC) > $@.tmp
	@if ! cmp -s $@.tmp $@; then \
		mv $@.tmp $@; \
	else \
		rm $@.tmp; \
	fi

build-info.o: common/build-info.cpp
	$(CXX) $(CXXFLAGS) -c $(filter-out %.h,$^) -o $@

#
# Tests
#

tests: $(TEST_TARGETS)

benchmark-matmult: examples/benchmark/benchmark-matmult.cpp build-info.o ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

run-benchmark-matmult: benchmark-matmult
	./$@

.PHONY: run-benchmark-matmult swift

vdot: pocs/vdot/vdot.cpp ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS)

q8dot: pocs/vdot/q8dot.cpp ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS)

tests/test-moses-grammar: tests/test-moses-grammar.cpp ggml.o grammar-parser.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-grammar-parser: tests/test-grammar-parser.cpp ggml.o moses.o grammar-parser.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-double-float: tests/test-double-float.cpp ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-grad0: tests/test-grad0.cpp ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-opt: tests/test-opt.cpp ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-quantize-fns: tests/test-quantize-fns.cpp ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-quantize-perf: tests/test-quantize-perf.cpp ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-sampling: tests/test-sampling.cpp ggml.o moses.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-tokenizer-0-falcon: tests/test-tokenizer-0-falcon.cpp ggml.o moses.o $(COMMON_DEPS) console.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-tokenizer-0-moses: tests/test-tokenizer-0-moses.cpp ggml.o moses.o $(COMMON_DEPS) console.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-tokenizer-1-bpe: tests/test-tokenizer-1-bpe.cpp ggml.o moses.o $(COMMON_DEPS) console.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-tokenizer-1-moses: tests/test-tokenizer-1-moses.cpp ggml.o moses.o $(COMMON_DEPS) console.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-rope: tests/test-rope.cpp ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-c.o: tests/test-c.c moses.h
	$(CC) $(CFLAGS) -c $(filter-out %.h,$^) -o $@

tests/test-backend-ops: tests/test-backend-ops.cpp ggml.o $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-model-load-cancel: tests/test-model-load-cancel.cpp ggml.o moses.o tests/get-model.cpp $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)

tests/test-autorelease: tests/test-autorelease.cpp ggml.o moses.o tests/get-model.cpp $(COMMON_DEPS) $(OBJS)
	$(CXX) $(CXXFLAGS) $(filter-out %.h,$^) -o $@ $(LDFLAGS)
