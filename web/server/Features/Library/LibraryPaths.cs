namespace RomChecker.Web.Features.Library;

public sealed class LibraryPaths(WebOptions options)
{
    public void AssertPath(string path, bool directory = false)
        => AssertPath(options.Root, path, directory);

    public static void AssertPath(string root, string path, bool directory = false)
    {
        string full;
        try { full = Path.GetFullPath(path); }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException)
        { throw new RequestException("Invalid library path."); }
        var relative = Path.GetRelativePath(root, full);
        if (Path.IsPathRooted(relative) || relative == ".." || relative.StartsWith(".." + Path.DirectorySeparatorChar))
            throw new RequestException("Paths must remain inside the configured library.");
        for (var current = new DirectoryInfo(directory ? full : Path.GetDirectoryName(full)!);
             current is not null; current = current.Parent)
        {
            if (current.Exists && current.Attributes.HasFlag(FileAttributes.ReparsePoint))
                throw new RequestException("Symbolic links and junctions are not supported.");
            if (Path.GetRelativePath(root, current.FullName) == ".") break;
        }
        if (directory && !Directory.Exists(full)) throw new RequestException("Directory does not exist.");
    }
}
