#include "shm_helpers.h"
#include <fcntl.h>

int shm_open_wrapper(const char *name, int oflag, mode_t mode) {
    return shm_open(name, oflag, mode);
}

int shm_unlink_wrapper(const char *name) {
    return shm_unlink(name);
}
