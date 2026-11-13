using System.Text.RegularExpressions;

namespace RomChecker.Web.Features.Catalog;

public sealed record CatalogRegionEvidence(string[] Values, string Source);

public static partial class CatalogRegions
{
    public static readonly string[] Names =
        ["USA", "Europe", "Japan", "World", "United Kingdom", "Korea", "Germany", "France", "Spain", "Italy",
         "Netherlands", "Sweden", "Asia", "China", "Taiwan", "Hong Kong", "Brazil", "Australia", "Canada",
         "Russia", "Scandinavia", "Denmark", "Finland", "Norway", "Portugal", "Greece"];

    private static readonly Dictionary<string, string> Aliases = BuildAliases();
    private static Dictionary<string, string> BuildAliases()
    {
        var aliases = Names.ToDictionary(name => name, StringComparer.OrdinalIgnoreCase);
        foreach (var (alias, name) in new[] { ("US", "USA"), ("United States", "USA"), ("EU", "Europe"),
            ("JP", "Japan"), ("UK", "United Kingdom") })
            aliases.Add(alias, name);
        return aliases;
    }

    public static CatalogRegionEvidence For(CatalogEntry entry)
    {
        if (entry.CheckStatus == "checked")
            foreach (var (field, source) in new[] { ("DatMatch", "dat-title"), ("HashMatch", "hash-title") })
            {
                var regions = Parse(CanonicalCatalog.Text(entry.Evidence, field));
                if (regions.Length > 0) return new(regions, source);
            }
        return new(Parse(entry.FileName), "filename");
    }

    public static string[] Parse(string title)
    {
        var regions = new HashSet<string>(StringComparer.Ordinal);
        foreach (Match match in Tags().Matches(title))
        {
            var parts = match.Groups[1].Value.Split(',', StringSplitOptions.TrimEntries);
            var tag = new List<string>();
            foreach (var part in parts)
            {
                if (Aliases.TryGetValue(part, out var name)) tag.Add(name);
                else if (part.Length is > 0 and <= 3 && part.All(c => c is 'U' or 'J' or 'E'))
                    tag.AddRange(part.Select(c => c switch { 'U' => "USA", 'J' => "Japan", _ => "Europe" }));
                else { tag.Clear(); break; }
            }
            regions.UnionWith(tag);
        }
        return regions.Order(StringComparer.Ordinal).ToArray();
    }

    [GeneratedRegex(@"\(([^()]*)\)", RegexOptions.CultureInvariant)]
    private static partial Regex Tags();
}
