# GCC 15 Compatibility Fixes for TheRock

This document lists patches required to build TheRock with GCC 15 (tested with GCC 15.2.1).

GCC 15 is stricter about:
- Missing `#include <cstdint>` for `uint32_t`, `int32_t`, etc.
- Missing `#include <algorithm>` for `std::any_of`, `std::find`, etc.
- K&R-style function declarations (empty parentheses)
- Implicit function pointer type conversions
- Unterminated string initializers in char arrays

## Fixes Applied

### 1. rocprofiler-sdk: elfio/elf_types.hpp

**File:** `rocm-systems/projects/rocprofiler-sdk/external/elfio/elfio/elf_types.hpp`

**Issue:** Missing `#include <cstdint>` and using unqualified type names.

**Fix:**
```cpp
// Add after include guards
#include <cstdint>

// Change types to use std:: prefix
using Elf_Half   = std::uint16_t;
using Elf_Word   = std::uint32_t;
using Elf_Sword  = std::int32_t;
using Elf_Xword  = std::uint64_t;
using Elf_Sxword = std::int64_t;
using Elf32_Addr = std::uint32_t;
using Elf32_Off  = std::uint32_t;
using Elf64_Addr = std::uint64_t;
using Elf64_Off  = std::uint64_t;
```

### 2. rocprofiler-sdk: yaml-cpp/emitterutils.cpp

**File:** `rocm-systems/projects/rocprofiler-sdk/external/yaml-cpp/src/emitterutils.cpp`

**Issue:** Missing `#include <cstdint>`.

**Fix:**
```cpp
#include <algorithm>
#include <cstdint>  // ADD THIS LINE
#include <iomanip>
```

### 3. rocprofiler-systems: PAPI papi_hl.c

**File:** `rocm-systems/projects/rocprofiler-systems/external/papi/src/high-level/papi_hl.c`

**Issue:** K&R-style function declaration without parameter types.

**Fix (line 170):**
```c
// Change from:
static int _internal_hl_read_user_events();
// To:
static int _internal_hl_read_user_events(const char *user_events);
```

### 4. rocprofiler-systems: PAPI papi_vector.c

**File:** `rocm-systems/projects/rocprofiler-systems/external/papi/src/papi_vector.c`

**Issue:** Function pointer cast mismatch.

**Fix (line 221):**
```c
// Change from:
v->get_system_info = ( int ( * )(  ) ) vec_int_dummy;
// To:
v->get_system_info = ( int ( * )( papi_mdi_t * ) ) vec_int_dummy;
```

### 5. rocprofiler-systems: elfutils build flags

**File:** `rocm-systems/projects/rocprofiler-systems/cmake/DyninstElfUtils.cmake`

**Issue:** Unterminated string warnings treated as errors in elfutils.

**Fix (line 187):**
```cmake
# Change CFLAGS from:
CFLAGS=-fPIC\ -O3
# To:
CFLAGS=-fPIC\ -O3\ -Wno-error=unterminated-string-initialization
```

### 6. rocprofiler-systems: logger.hpp

**File:** `rocm-systems/projects/rocprofiler-systems/source/lib/logger/logger.hpp`

**Issue:** Missing `#include <algorithm>` for `std::any_of`.

**Fix:**
```cpp
#include <spdlog/spdlog.h>

#include <algorithm>  // ADD THIS LINE
#include <atomic>
```

### 7. rocprofiler-systems: dyninst sha1.C

**File:** `rocm-systems/projects/rocprofiler-systems/external/dyninst/common/src/sha1.C`

**Issue:** Missing `#include <cstdint>` for `uint32_t`.

**Fix:**
```cpp
#include <cstdint>  // ADD THIS LINE
#include <stdio.h>
#include <string.h>
```

### 8. rocprofiler-systems: dyninst arch-x86.h

**File:** `rocm-systems/projects/rocprofiler-systems/external/dyninst/common/src/arch-x86.h`

**Issue:** Missing `#include <cstdint>` for `INT32_MAX`, `INT32_MIN`, `UINT32_MAX`.

**Fix (after line 46):**
```cpp
#include "dyn_register.h"
#include <cstdint>  // ADD THIS LINE
```

### 9. rocgdb: CMakeLists.txt (PDF docs)

**File:** `debug-tools/rocgdb/CMakeLists.txt`

**Issue:** PDF/HTML doc generation requires full TeX installation (texi2dvi).

**Fix (for bootc/immutable systems):** Comment out PDF/HTML install command (lines 274-277):
```cmake
# Skip gdb docs (PDF/HTML) - requires full TeX installation
# COMMAND
#   ${CMAKE_COMMAND} -E chdir "${ROCGDB_BUILD_DIR}"
#   ${MAKE_EXECUTABLE} -s -C gdb install-pdf install-html
```

**Fix (for regular systems):** Install TeX Live:
```bash
sudo dnf install texlive-scheme-basic texlive-collection-latexrecommended
```

### 10. libhipcxx: atomic_codegen symlink

**File:** `math-libs/libhipcxx/test/`

**Issue:** Missing `atomic_codegen` directory for tests when FileCheck is available (e.g., from linuxbrew).
Note: The `test/` directory is itself a symlink to `.upstream-tests/test/`, so the relative path must account for this.

**Fix:**
```bash
cd math-libs/libhipcxx/test
ln -s ../../._upstream/.upstream-tests/atomic_codegen atomic_codegen
```

### 11. libhipcxx: atomic_codegen cuobjdump check

**File:** `math-libs/libhipcxx/test/CMakeLists.txt`

**Issue:** When FileCheck is available (e.g., from linuxbrew) but CUDA is not installed, the atomic_codegen tests fail because they require `cuobjdump`.

**Fix (around line 283):**
```cmake
find_program(filecheck "FileCheck")
find_program(cuobjdump_check "cuobjdump")

if (filecheck AND cuobjdump_check)
  message("-- ${filecheck} and cuobjdump found... building atomic codegen tests")
  add_subdirectory(atomic_codegen)
elseif(filecheck)
  message("-- FileCheck found but cuobjdump not found - skipping atomic codegen tests (CUDA not available)")
endif()
```

## Notes

- These fixes are needed for Fedora 43+ and other distributions with GCC 15
- The upstream elfio library has already fixed the cstdint issue
- PAPI and elfutils bundled in rocprofiler-systems are older versions
- Consider submitting upstream patches for rocprofiler-systems dependencies

## Testing

After applying these fixes, build with:
```bash
ninja -C build -j4
```

Use `-j4` or lower for LLVM/Flang builds to avoid OOM on systems with 32GB RAM.
