namespace RomChecker.Web.Features.Storage;

public static class StoragePaths
{
    public static string Id(string id) => Guid.TryParseExact(id, "N", out _) ? id : throw new RequestException("Invalid storage ID.");

    public static string Relative(string value, bool root = false)
    {
        if (root && value is "" or ".") return "";
        if (string.IsNullOrWhiteSpace(value) || value.Length > 800 || value.StartsWith('/') || value.Contains('\\'))
            throw new RequestException("Invalid relative path.");
        var parts = value.Split('/');
        foreach (var part in parts)
        {
            var stem = part.Split('.')[0];
            if (part is "" or "." or ".." || part.Length > 200 || part.EndsWith('.') || part.EndsWith(' ')
                || part.Any(c => c < 32 || "<>:\"|?*".Contains(c))
                || stem.Equals("CON", StringComparison.OrdinalIgnoreCase) || stem.Equals("PRN", StringComparison.OrdinalIgnoreCase)
                || stem.Equals("AUX", StringComparison.OrdinalIgnoreCase) || stem.Equals("NUL", StringComparison.OrdinalIgnoreCase)
                || System.Text.RegularExpressions.Regex.IsMatch(stem, "^(COM|LPT)[0-9]$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                throw new RequestException("Unsupported file or folder name. Paths must be portable and cannot contain traversal.");
        }
        if (parts.Length > 32) throw new RequestException("Folder nesting exceeds 32 levels.");
        return value;
    }

    public static string Resolve(string root, string relative, bool allowRoot = false)
    {
        relative = Relative(relative, allowRoot);
        var full = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        AssertNoLinks(root, full);
        return full;
    }

    public static void AssertNoLinks(string root, string path)
    {
        var relative = Path.GetRelativePath(root, path);
        if (Path.IsPathRooted(relative) || relative == ".." || relative.StartsWith(".." + Path.DirectorySeparatorChar))
            throw new RequestException("Path is outside storage.");
        for (var current = path; current is not null; current = Path.GetDirectoryName(current))
        {
            if (Path.Exists(current) && File.GetAttributes(current).HasFlag(FileAttributes.ReparsePoint))
                throw new RequestException("Links are not supported in storage.");
            if (Path.GetRelativePath(root, current) == ".") break;
        }
    }

    public static IEnumerable<(string Full, string Relative)> Files(string root, string relative = "")
    {
        var start = Resolve(root, relative, true);
        if (File.Exists(start)) { yield return (start, relative); yield break; }
        if (!Directory.Exists(start)) throw new RequestException("Folder not found.", 404);
        var pending = new Stack<string>();
        pending.Push(start);
        while (pending.TryPop(out var directory))
            foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
            {
                AssertNoLinks(root, entry);
                if (Directory.Exists(entry)) pending.Push(entry);
                else yield return (entry, Path.GetRelativePath(root, entry).Replace(Path.DirectorySeparatorChar, '/'));
            }
    }
}
