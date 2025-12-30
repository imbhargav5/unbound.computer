//
//  FileSystemService.swift
//  rocketry-macos
//
//  Scans directories and builds FileItem trees for the file browser
//

import Foundation

@Observable
class FileSystemService {

    /// Scan directory and build FileItem tree
    func scanDirectory(at path: String, maxDepth: Int = 10) -> [FileItem] {
        let url = URL(fileURLWithPath: path)
        return scanDirectory(url: url, currentDepth: 0, maxDepth: maxDepth)
    }

    private func scanDirectory(url: URL, currentDepth: Int, maxDepth: Int) -> [FileItem] {
        guard currentDepth < maxDepth else { return [] }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Sort: folders first, then alphabetically
        let sorted = contents.sorted { url1, url2 in
            let isDir1 = (try? url1.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let isDir2 = (try? url2.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDir1 != isDir2 {
                return isDir1 // folders first
            }
            return url1.lastPathComponent.localizedCaseInsensitiveCompare(url2.lastPathComponent) == .orderedAscending
        }

        return sorted.compactMap { itemURL -> FileItem? in
            let name = itemURL.lastPathComponent
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDirectory {
                let children = scanDirectory(url: itemURL, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                return FileItem(name: name, type: .folder, children: children)
            } else {
                let type = FileItemType.fromExtension(itemURL.pathExtension)
                return FileItem(name: name, type: type)
            }
        }
    }

    /// Build file tree from git status (changed files only)
    func buildChangesTree(from status: GitStatus) -> [FileItem] {
        var items: [FileItem] = []

        for file in status.staged {
            let ext = (file as NSString).pathExtension
            items.append(FileItem(name: file, type: .fromExtension(ext), gitStatus: .staged))
        }
        for file in status.modified {
            let ext = (file as NSString).pathExtension
            items.append(FileItem(name: file, type: .fromExtension(ext), gitStatus: .modified))
        }
        for file in status.untracked {
            let ext = (file as NSString).pathExtension
            items.append(FileItem(name: file, type: .fromExtension(ext), gitStatus: .untracked))
        }

        return items.sorted { $0.name < $1.name }
    }
}
