using RomChecker.Web.Features.Catalog;

namespace RomChecker.Web.Features.Romm;

public static class RommPublishPolicy
{
    public static readonly string[] Categories =
        ["Original", "Hacks_Mods", "Translations", "Beta_Proto_Sample", "PD_Homebrew_Unlicensed", "BS_ST",
         "Not_In_DAT", "Invalid_Corrupt", "Unknown_Check_Manually"];

    public static RommPublishRules Validate(RommPublishRules rules)
    {
        if (rules.ReferenceRequirement is not ("eligible" or "matched"))
            throw new RequestException("Choose eligible files or reference-matched files for automatic publication.");
        string[] Values(string[]? values, string label, Func<string, bool> valid)
        {
            if (values is null) return [];
            if (values.Length > 1000 || values.Any(value => string.IsNullOrWhiteSpace(value)
                || value.Length > 200 || !valid(value)))
                throw new RequestException($"Invalid automatic publication {label}.");
            return values.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray();
        }
        return rules with
        {
            Consoles = Values(rules.Consoles, "console keys", value => !value.Any(char.IsControl)),
            Regions = Values(rules.Regions, "regions", CatalogRegions.Names.Contains),
            Categories = Values(rules.Categories, "categories", Categories.Contains),
            BatchIds = Values(rules.BatchIds, "import IDs", value => Guid.TryParseExact(value, "N", out _))
        };
    }

    public static string? BlockReason(CatalogEntry[] group, RommConfig config)
    {
        var rules = config.PublishRules ?? new();
        foreach (var entry in group)
        {
            if (!entry.PublishEligible) return entry.PublishBlockReason ?? "Required publication checks have not passed.";
            if (string.IsNullOrEmpty(entry.BatchId)) return "Import into managed storage before publishing.";
            if (!(config.PlatformMappings ?? []).Any(mapping => mapping.Console == entry.Console))
                return "Configure the RomM platform mapping first.";
            if (rules.Consoles is { Length: > 0 } && !rules.Consoles.Contains(entry.Console))
                return "Console is not selected by the automatic publishing rules.";
            if (rules.BatchIds is { Length: > 0 } && !rules.BatchIds.Contains(entry.BatchId))
                return "Import is not selected by the automatic publishing rules.";
        }
        // Companions inherit game filters, but never bypass the required checks above.
        var games = group.Where(entry => entry.Category != "Companion").ToArray();
        if (games.Length == 0) return "No primary game is available for this companion group.";
        foreach (var entry in games)
        {
            if (rules.ReferenceRequirement == "matched" && entry.ReferenceStatus != "matched")
                return "A reference match is required; manual approval does not satisfy this rule.";
            if (rules.Categories is { Length: > 0 } && !rules.Categories.Contains(entry.Category))
                return "Game category is not selected by the automatic publishing rules.";
            if (rules.Regions is { Length: > 0 })
            {
                var region = CatalogRegions.For(entry);
                if (region.Values.Length == 0 || region.Source == "filename" && !rules.AllowFilenameRegions)
                {
                    if (!rules.IncludeUnknownRegions)
                        return "Region is unknown or filename-only; the current region rules hold it for review.";
                }
                else if (!region.Values.Intersect(rules.Regions, StringComparer.Ordinal).Any())
                    return "Game region does not match the automatic publishing rules.";
            }
        }
        return null;
    }
}
