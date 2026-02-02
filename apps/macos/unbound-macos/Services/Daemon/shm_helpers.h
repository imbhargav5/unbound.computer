#ifndef shm_helpers_h
#define shm_helpers_h

#include <sys/mman.h>

/// Opens or creates a POSIX shared memory object.
/// This wrapper exists because shm_open is variadic and cannot be called from Swift.
int shm_open_wrapper(const char *name, int oflag, mode_t mode);

/// Removes a shared memory object.
int shm_unlink_wrapper(const char *name);

#endif /* shm_helpers_h */
