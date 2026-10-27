using Microsoft.Data.Sqlite;

namespace RomChecker.Web.Features.Settings;

public sealed record DatabaseCompatibility(int Version, int MinimumSupported, int MaximumSupported)
{
    public const int Current = 1;

    public static DatabaseCompatibility Initialize(string data)
    {
        Directory.CreateDirectory(data);
        using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = Path.Combine(data, "romchecker.db")
        }.ToString());
        connection.Open();
        using var transaction = connection.BeginTransaction();
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "PRAGMA user_version";
        var version = Convert.ToInt32(command.ExecuteScalar());
        if (version > Current || version < 0)
            throw new InvalidOperationException($"Database schema {version} is incompatible with this container (supports 1-{Current}). Do not downgrade against newer data; restore a matching backup or use a compatible image.");
        // Version zero is the existing unversioned schema; adoption changes no tables or ROM data.
        if (version == 0)
        {
            command.CommandText = $"PRAGMA user_version={Current}";
            command.ExecuteNonQuery();
        }
        transaction.Commit();
        return new(Current, 1, Current);
    }
}
