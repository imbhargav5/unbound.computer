use parking_lot::Mutex;
use std::fs::{File, OpenOptions};
use std::io::{self, BufWriter};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tracing_subscriber::fmt::MakeWriter;

pub fn default_log_path() -> PathBuf {
    dirs::home_dir()
        .expect("home directory must exist")
        .join(".unbound")
        .join("logs")
        .join("dev.jsonl")
}

#[derive(Clone)]
pub struct CentralLogWriter {
    inner: Arc<Mutex<BufWriter<File>>>,
}

impl CentralLogWriter {
    pub fn new(path: &Path) -> io::Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let file = OpenOptions::new().create(true).append(true).open(path)?;

        Ok(Self {
            inner: Arc::new(Mutex::new(BufWriter::with_capacity(8192, file))),
        })
    }
}

impl io::Write for CentralLogWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let mut guard = self.inner.lock();
        let result = guard.write(buf);
        guard.flush()?;
        result
    }

    fn flush(&mut self) -> io::Result<()> {
        self.inner.lock().flush()
    }
}

#[derive(Clone)]
pub struct WriterFactory {
    writer: CentralLogWriter,
}

impl WriterFactory {
    pub fn new(path: &Path) -> io::Result<Self> {
        let writer = CentralLogWriter::new(path)?;
        Ok(Self { writer })
    }
}

impl<'a> MakeWriter<'a> for WriterFactory {
    type Writer = CentralLogWriter;

    fn make_writer(&'a self) -> Self::Writer {
        self.writer.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use tempfile::tempdir;

    #[test]
    fn central_writer_creates_file_and_parent_dirs() {
        let dir = tempdir().expect("temp dir");
        let path = dir.path().join("logs").join("test.jsonl");

        let mut writer = CentralLogWriter::new(&path).expect("writer");
        writer.write_all(b"line\n").expect("write");

        let mut content = String::new();
        File::open(&path)
            .expect("open")
            .read_to_string(&mut content)
            .expect("read");
        assert_eq!(content, "line\n");
    }
}
