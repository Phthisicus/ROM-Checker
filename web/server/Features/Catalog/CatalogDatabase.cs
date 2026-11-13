using Microsoft.Data.Sqlite;
using System.Text.Json;

namespace RomChecker.Web.Features.Catalog;

public sealed class CatalogDatabase
{
    private readonly string connectionString;
    public CatalogDatabase(WebOptions options)
    {
        Directory.CreateDirectory(options.Data);
        connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = Path.Combine(options.Data, "romchecker.db"),
            Mode = SqliteOpenMode.ReadWriteCreate,
            DefaultTimeout = 30
        }.ToString();
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS catalog_entries(id TEXT PRIMARY KEY, source TEXT NOT NULL, json TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS catalog_source ON catalog_entries(source);
            CREATE INDEX IF NOT EXISTS catalog_group ON catalog_entries(source,json_extract(json,'$.groupId'));
            CREATE TABLE IF NOT EXISTS catalog_history(
              id TEXT PRIMARY KEY, entry_id TEXT NOT NULL, created TEXT NOT NULL, json TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS catalog_history_entry ON catalog_history(entry_id,created);
            CREATE TABLE IF NOT EXISTS catalog_verifications(id TEXT PRIMARY KEY, created TEXT NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS catalog_metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
            INSERT OR IGNORE INTO catalog_metadata VALUES('schema','1');
            """;
        command.ExecuteNonQuery();
    }
    private SqliteConnection Open()
    {
        var connection = new SqliteConnection(connectionString);
        connection.Open();
        return connection;
    }
    public CatalogEntry[] Entries()
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT json FROM catalog_entries ORDER BY id";
        using var reader = command.ExecuteReader();
        var entries = new List<CatalogEntry>();
        while (reader.Read()) entries.Add(JsonSerializer.Deserialize<CatalogEntry>(reader.GetString(0), Json.Options)!);
        return entries.ToArray();
    }
    public CatalogEntry? Get(string id)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT json FROM catalog_entries WHERE id=$id";
        command.Parameters.AddWithValue("$id", id);
        return command.ExecuteScalar() is string json ? JsonSerializer.Deserialize<CatalogEntry>(json, Json.Options) : null;
    }
    public CatalogEntry[] Unit(CatalogEntry entry)
    {
        if (entry.GroupId.Length == 0) return [entry];
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT json FROM catalog_entries WHERE source=$source AND json_extract(json,'$.groupId')=$group";
        command.Parameters.AddWithValue("$source", entry.BatchId ?? "legacy");
        command.Parameters.AddWithValue("$group", entry.GroupId);
        using var reader = command.ExecuteReader();
        var entries = new List<CatalogEntry>();
        while (reader.Read()) entries.Add(JsonSerializer.Deserialize<CatalogEntry>(reader.GetString(0), Json.Options)!);
        return entries.ToArray();
    }
    public void Save(CatalogEntry entry, string? action = null, string detail = "", string actor = "System")
        => SaveMany([(entry, action, detail, actor)]);

    public void SaveMany(IEnumerable<(CatalogEntry Entry, string? Action, string Detail, string Actor)> changes)
    {
        using var connection = Open();
        using var transaction = connection.BeginTransaction();
        foreach (var (entry, action, detail, actor) in changes)
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = """
                INSERT INTO catalog_entries VALUES($id,$source,$json)
                ON CONFLICT(id) DO UPDATE SET source=$source,json=$json
                """;
            command.Parameters.AddWithValue("$id", entry.Id);
            command.Parameters.AddWithValue("$source", entry.BatchId ?? "legacy");
            command.Parameters.AddWithValue("$json", Json.Serialize(entry));
            command.ExecuteNonQuery();
            if (action is not null) InsertAudit(connection, transaction, entry, action, detail, actor);
        }
        transaction.Commit();
    }
    private static void InsertAudit(SqliteConnection connection, SqliteTransaction? transaction,
        CatalogEntry entry, string action, string detail, string actor)
    {
        var item = new CatalogHistory(Guid.NewGuid().ToString("N"), entry.Id, DateTimeOffset.UtcNow,
            actor, action, entry.SHA256, detail);
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "INSERT INTO catalog_history VALUES($id,$entry,$created,$json)";
        command.Parameters.AddWithValue("$id", item.Id);
        command.Parameters.AddWithValue("$entry", item.EntryId);
        command.Parameters.AddWithValue("$created", item.CreatedUtc.ToString("O"));
        command.Parameters.AddWithValue("$json", Json.Serialize(item));
        command.ExecuteNonQuery();
    }
    public void Audit(CatalogEntry entry, string action, string detail, string actor = "Administrator")
    {
        using var connection = Open();
        InsertAudit(connection, null, entry, action, detail, actor);
    }
    public CatalogHistory[] History(string id)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT json FROM catalog_history WHERE entry_id=$id ORDER BY created DESC,id DESC";
        command.Parameters.AddWithValue("$id", id);
        using var reader = command.ExecuteReader();
        var history = new List<CatalogHistory>();
        while (reader.Read()) history.Add(JsonSerializer.Deserialize<CatalogHistory>(reader.GetString(0), Json.Options)!);
        return history.ToArray();
    }
    public void SaveVerification(CatalogVerification run)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO catalog_verifications VALUES($id,$created,$json)
            ON CONFLICT(id) DO UPDATE SET json=$json
            """;
        command.Parameters.AddWithValue("$id", run.Id);
        command.Parameters.AddWithValue("$created", run.CreatedUtc.ToString("O"));
        command.Parameters.AddWithValue("$json", Json.Serialize(run));
        command.ExecuteNonQuery();
    }
    public CatalogVerification[] Verifications()
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT json FROM catalog_verifications ORDER BY created";
        using var reader = command.ExecuteReader();
        var runs = new List<CatalogVerification>();
        while (reader.Read()) runs.Add(JsonSerializer.Deserialize<CatalogVerification>(reader.GetString(0), Json.Options)!);
        return runs.ToArray();
    }
}
