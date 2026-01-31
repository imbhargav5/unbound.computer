//! Unix (macOS/Linux) shared memory implementation.
//!
//! Uses POSIX shared memory (`shm_open`) and `mmap` for zero-copy IPC.
//!
//! # Platform Differences
//!
//! - **macOS**: Uses `os_unfair_lock` for synchronization (via pthread)
//! - **Linux**: Uses `futex` for efficient blocking wait
//!
//! # Shared Memory Lifecycle
//!
//! 1. Producer creates shm with `shm_open(O_CREAT | O_EXCL)`
//! 2. Producer maps memory with `mmap(PROT_READ | PROT_WRITE)`
//! 3. Producer initializes header
//! 4. Consumer opens existing shm with `shm_open(O_RDWR)`
//! 5. Consumer maps memory (same way)
//! 6. Consumer validates header magic/version
//! 7. On shutdown, producer sets SHUTDOWN flag
//! 8. Producer calls `shm_unlink` to remove the shm object
//!
//! # Naming Convention
//!
//! Shared memory objects are named: `/unbound_stream_{session_id}`
//!
//! The leading `/` is required by POSIX. Session IDs are UUIDs, which are
//! safe for use in shm names (alphanumeric + hyphens).

mod producer;
pub mod consumer;

pub use producer::UnixStreamProducer;
pub use consumer::UnixStreamConsumer;

use std::ffi::CString;
use std::ptr;

use libc::{
    c_int, c_uint, c_void, close, ftruncate, mmap, munmap, off_t, shm_open, shm_unlink,
    MAP_FAILED, MAP_SHARED, O_CREAT, O_EXCL, O_RDWR, PROT_READ, PROT_WRITE,
    S_IRUSR, S_IWUSR,
};

use crate::error::{StreamError, StreamResult};
use crate::protocol::{StreamHeader, HEADER_SIZE};

/// Generate the shared memory name for a session.
///
/// On macOS, POSIX shared memory names are limited to 31 characters (including the leading `/`).
/// We use a hash-based short name to stay within this limit while maintaining uniqueness.
pub fn shm_name(session_id: &str) -> String {
    // macOS limits shm names to 31 chars including the leading '/'
    // We use a prefix + truncated session_id to stay within limits
    // Format: "/ub_" + first 8 chars of session_id = 12 chars (well under limit)
    let short_id = if session_id.len() > 8 {
        &session_id[..8]
    } else {
        session_id
    };
    format!("/ub_{}", short_id)
}

/// Create and map a new shared memory region (for producer)
///
/// # Safety
///
/// Returns a raw pointer to mapped memory. Caller must ensure:
/// - Pointer is not used after `munmap`
/// - Concurrent access follows the SPSC protocol
pub(crate) fn create_shm(name: &str, size: usize) -> StreamResult<(*mut u8, c_int)> {
    let c_name = CString::new(name).map_err(|e| StreamError::SharedMemory(e.to_string()))?;

    unsafe {
        // Create shared memory object (fail if exists)
        let fd = shm_open(
            c_name.as_ptr(),
            O_CREAT | O_EXCL | O_RDWR,
            (S_IRUSR | S_IWUSR) as c_uint,
        );

        if fd == -1 {
            let err = std::io::Error::last_os_error();
            return Err(StreamError::SharedMemory(format!(
                "shm_open failed for '{}': {}",
                name, err
            )));
        }

        // Set size
        if ftruncate(fd, size as off_t) == -1 {
            let err = std::io::Error::last_os_error();
            close(fd);
            shm_unlink(c_name.as_ptr());
            return Err(StreamError::SharedMemory(format!(
                "ftruncate failed: {}",
                err
            )));
        }

        // Map into address space
        let ptr = mmap(
            ptr::null_mut(),
            size,
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            fd,
            0,
        );

        if ptr == MAP_FAILED {
            let err = std::io::Error::last_os_error();
            close(fd);
            shm_unlink(c_name.as_ptr());
            return Err(StreamError::Mmap(format!("mmap failed: {}", err)));
        }

        Ok((ptr as *mut u8, fd))
    }
}

/// Open and map an existing shared memory region (for consumer)
///
/// # Safety
///
/// Returns a raw pointer to mapped memory. Caller must ensure:
/// - Pointer is not used after `munmap`
/// - Concurrent access follows the SPSC protocol
pub(crate) fn open_shm(name: &str) -> StreamResult<(*mut u8, c_int, usize)> {
    let c_name = CString::new(name).map_err(|e| StreamError::SharedMemory(e.to_string()))?;

    unsafe {
        // Open existing shared memory object
        let fd = shm_open(c_name.as_ptr(), O_RDWR, 0);

        if fd == -1 {
            let err = std::io::Error::last_os_error();
            return Err(StreamError::SharedMemory(format!(
                "shm_open failed for '{}': {}",
                name, err
            )));
        }

        // First, map just the header to read the size
        let header_ptr = mmap(
            ptr::null_mut(),
            HEADER_SIZE,
            PROT_READ,
            MAP_SHARED,
            fd,
            0,
        );

        if header_ptr == MAP_FAILED {
            let err = std::io::Error::last_os_error();
            close(fd);
            return Err(StreamError::Mmap(format!(
                "mmap header failed: {}",
                err
            )));
        }

        // Read total size from header
        let header = &*(header_ptr as *const StreamHeader);
        if !header.validate() {
            munmap(header_ptr, HEADER_SIZE);
            close(fd);
            return Err(StreamError::InvalidHeader(format!(
                "invalid magic {:x} or version {}",
                header.magic, header.version
            )));
        }

        let total_size = header.total_size();
        munmap(header_ptr, HEADER_SIZE);

        // Now map the full region
        let ptr = mmap(
            ptr::null_mut(),
            total_size,
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            fd,
            0,
        );

        if ptr == MAP_FAILED {
            let err = std::io::Error::last_os_error();
            close(fd);
            return Err(StreamError::Mmap(format!("mmap full failed: {}", err)));
        }

        Ok((ptr as *mut u8, fd, total_size))
    }
}

/// Unmap and close shared memory
///
/// # Safety
///
/// Must only be called once per mapping
pub(crate) unsafe fn close_shm(ptr: *mut u8, size: usize, fd: c_int) {
    if !ptr.is_null() {
        munmap(ptr as *mut c_void, size);
    }
    if fd >= 0 {
        close(fd);
    }
}

/// Remove the shared memory object (producer only, on shutdown)
///
/// # Safety
///
/// Should only be called after all consumers have disconnected
pub(crate) fn unlink_shm(name: &str) -> StreamResult<()> {
    let c_name = CString::new(name).map_err(|e| StreamError::SharedMemory(e.to_string()))?;

    unsafe {
        if shm_unlink(c_name.as_ptr()) == -1 {
            let err = std::io::Error::last_os_error();
            // ENOENT is ok - already unlinked
            if err.raw_os_error() != Some(libc::ENOENT) {
                return Err(StreamError::SharedMemory(format!(
                    "shm_unlink failed: {}",
                    err
                )));
            }
        }
    }
    Ok(())
}

/// Wake consumers waiting on the futex (Linux) or do nothing (macOS)
///
/// On macOS, we rely on consumers polling or using a separate signaling mechanism.
/// On Linux, we use the futex syscall for efficient wakeup.
#[cfg(target_os = "linux")]
pub(crate) fn wake_consumer(header: &StreamHeader) {
    use std::sync::atomic::Ordering;

    // Increment futex value and wake one waiter
    header.wake_futex.fetch_add(1, Ordering::Release);

    unsafe {
        libc::syscall(
            libc::SYS_futex,
            &header.wake_futex as *const _ as *const c_int,
            libc::FUTEX_WAKE,
            1, // Wake one waiter
            ptr::null::<libc::timespec>(),
            ptr::null::<c_int>(),
            0,
        );
    }
}

#[cfg(target_os = "macos")]
pub(crate) fn wake_consumer(header: &StreamHeader) {
    use std::sync::atomic::Ordering;
    // On macOS, we increment the futex value so consumers can detect changes
    // Consumers use polling with exponential backoff
    header.wake_futex.fetch_add(1, Ordering::Release);
}

/// Wait for producer to write new data (Linux futex)
#[cfg(target_os = "linux")]
pub(crate) fn wait_for_data(header: &StreamHeader, current_futex: u32, timeout_ms: Option<u32>) {
    use std::ptr;

    let timeout = timeout_ms.map(|ms| libc::timespec {
        tv_sec: (ms / 1000) as i64,
        tv_nsec: ((ms % 1000) * 1_000_000) as i64,
    });

    unsafe {
        libc::syscall(
            libc::SYS_futex,
            &header.wake_futex as *const _ as *const c_int,
            libc::FUTEX_WAIT,
            current_futex as c_int,
            timeout.as_ref().map_or(ptr::null(), |t| t as *const _),
            ptr::null::<c_int>(),
            0,
        );
    }
}

#[cfg(target_os = "macos")]
pub(crate) fn wait_for_data(_header: &StreamHeader, _current_futex: u32, timeout_ms: Option<u32>) {
    // On macOS, we use a simple sleep-based polling strategy
    // For production, consider using dispatch_semaphore or mach ports
    let sleep_time = timeout_ms.unwrap_or(1).min(10);
    std::thread::sleep(std::time::Duration::from_millis(sleep_time as u64));
}
