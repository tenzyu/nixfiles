use rustix::fs::{openat2, Mode, OFlags, ResolveFlags};
use rustix::io::Errno;
use std::ffi::{CStr, CString};
use std::os::fd::{BorrowedFd, OwnedFd};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

#[derive(Debug, Eq, PartialEq)]
pub enum BoundaryError {
    InvalidPath,
    Denied(Errno),
    Unsupported(Errno),
    Lookup(Errno),
}

/// Open a directory below an already authorized directory descriptor.
/// Each component must be nonempty and different from `.` and `..`.
/// The caller establishes the root's authority before passing its descriptor.
pub fn open_descendant(root: BorrowedFd<'_>, path: &Path) -> Result<OwnedFd, BoundaryError> {
    open_with(root, path, |root, path, flags, mode, resolve| {
        openat2(root, path, flags, mode, resolve)
    })
}

fn open_with(
    root: BorrowedFd<'_>,
    path: &Path,
    open: impl FnOnce(BorrowedFd<'_>, &CStr, OFlags, Mode, ResolveFlags) -> rustix::io::Result<OwnedFd>,
) -> Result<OwnedFd, BoundaryError> {
    let bytes = path.as_os_str().as_bytes();
    if bytes
        .split(|&byte| byte == b'/')
        .any(|component| matches!(component, b"" | b"." | b".."))
    {
        return Err(BoundaryError::InvalidPath);
    }
    let path = CString::new(bytes).map_err(|_| BoundaryError::InvalidPath)?;

    open(
        root,
        &path,
        OFlags::PATH | OFlags::DIRECTORY | OFlags::CLOEXEC,
        Mode::empty(),
        ResolveFlags::BENEATH | ResolveFlags::NO_SYMLINKS | ResolveFlags::NO_XDEV,
    )
    .map_err(|errno| match errno {
        Errno::NOSYS => BoundaryError::Unsupported(errno),
        Errno::LOOP | Errno::NOTDIR | Errno::XDEV => BoundaryError::Denied(errno),
        _ => BoundaryError::Lookup(errno),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use rustix::io::{fcntl_getfd, FdFlags};
    use std::fs::{self, DirBuilder, File};
    use std::os::fd::AsFd;
    use std::os::unix::fs::{symlink, DirBuilderExt, MetadataExt};
    use std::path::PathBuf;

    fn fixture(case: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("adr02-{}-{case}", std::process::id()));
        DirBuilder::new().mode(0o700).create(&dir).unwrap();
        dir
    }

    #[test]
    fn boundary_01_pins_directory_across_rename() {
        let dir = fixture("rename");
        let original = dir.join("root");
        let moved = dir.join("moved");
        fs::create_dir_all(original.join("child/nested")).unwrap();
        let root = File::open(&original).unwrap();
        let expected = fs::metadata(original.join("child/nested")).unwrap();

        fs::rename(&original, &moved).unwrap();
        fs::create_dir_all(original.join("child/nested")).unwrap();
        let child = open_descendant(root.as_fd(), Path::new("child")).unwrap();
        drop(root);
        let nested = open_descendant(child.as_fd(), Path::new("nested")).unwrap();
        assert!(fcntl_getfd(&nested).unwrap().contains(FdFlags::CLOEXEC));
        let actual = File::from(nested).metadata().unwrap();
        assert_eq!(
            (actual.dev(), actual.ino()),
            (expected.dev(), expected.ino())
        );

        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn boundary_01_rejects_invalid_paths_and_entry_types() {
        let dir = fixture("paths");
        fs::create_dir(dir.join("child")).unwrap();
        fs::write(dir.join("file"), b"fixture").unwrap();
        symlink("child", dir.join("alias")).unwrap();
        let root = File::open(&dir).unwrap();

        for path in [
            "",
            "/child",
            "child/..",
            "child/../child",
            "./child",
            "child/",
            "child//nested",
            "child\0",
        ] {
            assert_eq!(
                open_descendant(root.as_fd(), Path::new(path)).unwrap_err(),
                BoundaryError::InvalidPath,
            );
        }
        for (path, errno) in [
            ("alias", Errno::LOOP),
            ("alias/subdir", Errno::LOOP),
            ("file", Errno::NOTDIR),
            ("file/subdir", Errno::NOTDIR),
        ] {
            assert_eq!(
                open_descendant(root.as_fd(), Path::new(path)).unwrap_err(),
                BoundaryError::Denied(errno),
            );
        }

        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn boundary_01_refuses_missing_kernel_feature_and_preserves_errno() {
        let dir = fixture("errno");
        fs::create_dir(dir.join("child")).unwrap();
        let root = File::open(&dir).unwrap();

        for (errno, expected) in [
            (Errno::NOSYS, BoundaryError::Unsupported(Errno::NOSYS)),
            (Errno::XDEV, BoundaryError::Denied(Errno::XDEV)),
            (Errno::PERM, BoundaryError::Lookup(Errno::PERM)),
        ] {
            let error = open_with(
                root.as_fd(),
                Path::new("child"),
                |_, path, flags, mode, resolve| {
                    assert_eq!(path.to_bytes(), b"child");
                    assert_eq!(flags, OFlags::PATH | OFlags::DIRECTORY | OFlags::CLOEXEC);
                    assert_eq!(mode, Mode::empty());
                    assert_eq!(
                        resolve,
                        ResolveFlags::BENEATH | ResolveFlags::NO_SYMLINKS | ResolveFlags::NO_XDEV
                    );
                    Err(errno)
                },
            )
            .unwrap_err();
            assert_eq!(error, expected);
        }
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 1);

        fs::remove_dir_all(dir).unwrap();
    }
}
