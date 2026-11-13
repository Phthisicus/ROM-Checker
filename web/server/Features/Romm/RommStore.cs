using Microsoft.AspNetCore.DataProtection;
using Microsoft.Data.Sqlite;
using System.Text.Json;

namespace RomChecker.Web.Features.Romm;

public sealed class RommStore
{
    private readonly string connectionString;
    private readonly IDataProtector protector;
    public RommStore(WebOptions options, IDataProtectionProvider protection)
    {
        connectionString = new SqliteConnectionStringBuilder { DataSource = Path.Combine(options.Data, "romchecker.db") }.ToString();
        protector = protection.CreateProtector("RomChecker.Romm.Connection.v1");
        using var db = Open();
        using var command = db.CreateCommand();
        command.CommandText = """
            CREATE TABLE IF NOT EXISTS romm_config (id INTEGER PRIMARY KEY CHECK(id=1), protected TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS romm_jobs (id TEXT PRIMARY KEY, created TEXT NOT NULL, status TEXT NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS romm_links (id TEXT PRIMARY KEY, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS romm_remote (connection_id TEXT NOT NULL, rom_id INTEGER NOT NULL, json TEXT NOT NULL,
                PRIMARY KEY(connection_id,rom_id));
            UPDATE romm_jobs SET status='queued',json=json_set(json,'$.status','queued') WHERE status='running';
            """;
        command.ExecuteNonQuery();
    }
    private SqliteConnection Open()
    {
        var db = new SqliteConnection(connectionString);
        db.Open();
        return db;
    }
    public RommConfig Config()
    {
        using var db = Open();
        using var command = db.CreateCommand();
        command.CommandText = "SELECT protected FROM romm_config WHERE id=1";
        return command.ExecuteScalar() is string value
            ? JsonSerializer.Deserialize<RommConfig>(protector.Unprotect(value), Json.Options)! : new();
    }
    public void Save(RommConfig config)
    {
        using var db = Open();
        using var command = db.CreateCommand();
        command.CommandText = "INSERT INTO romm_config VALUES(1,$value) ON CONFLICT(id) DO UPDATE SET protected=$value";
        command.Parameters.AddWithValue("$value", protector.Protect(Json.Serialize(config)));
        command.ExecuteNonQuery();
    }
    public void Save(RommJob job)
    {
        using var db = Open();
        using var command = db.CreateCommand();
        command.CommandText = """
            INSERT INTO romm_jobs VALUES($id,$created,$status,$json)
            ON CONFLICT(id) DO UPDATE SET status=$status,json=$json
            """;
        command.Parameters.AddWithValue("$id", job.Id);
        command.Parameters.AddWithValue("$created", job.Created.ToString("O"));
        command.Parameters.AddWithValue("$status", job.Status);
        command.Parameters.AddWithValue("$json", Json.Serialize(job));
        command.ExecuteNonQuery();
    }
    public RommJob Get(string id) => Jobs().FirstOrDefault(job => job.Id == id) ?? throw new RequestException("Synchronization job not found.", 404);
    public RommJob[] Jobs()
    {
        using var db = Open();
        using var command = db.CreateCommand();
        command.CommandText = "SELECT json FROM romm_jobs ORDER BY created DESC";
        using var reader = command.ExecuteReader();
        var result = new List<RommJob>();
        while (reader.Read()) result.Add(JsonSerializer.Deserialize<RommJob>(reader.GetString(0), Json.Options)!);
        return result.ToArray();
    }
    public void Save(RommLink link)
    {
        using var db = Open();
        using var command = db.CreateCommand();
        command.CommandText = "INSERT INTO romm_links VALUES($id,$json) ON CONFLICT(id) DO UPDATE SET json=$json";
        command.Parameters.AddWithValue("$id", link.EntryId);
        command.Parameters.AddWithValue("$json", Json.Serialize(link));
        command.ExecuteNonQuery();
    }
    public RommLink[] Links()
    {
        using var db = Open();
        using var command = db.CreateCommand();
        command.CommandText = "SELECT json FROM romm_links";
        using var reader = command.ExecuteReader();
        var result = new List<RommLink>();
        while (reader.Read()) result.Add(JsonSerializer.Deserialize<RommLink>(reader.GetString(0), Json.Options)!);
        return result.ToArray();
    }
    public RommRemoteState[] Remotes(string connectionId)
    {
        using var db = Open();
        using var command = db.CreateCommand();
        command.CommandText = "SELECT json FROM romm_remote WHERE connection_id=$connection ORDER BY rom_id";
        command.Parameters.AddWithValue("$connection", connectionId);
        using var reader = command.ExecuteReader();
        var result = new List<RommRemoteState>();
        while (reader.Read()) result.Add(JsonSerializer.Deserialize<RommRemoteState>(reader.GetString(0), Json.Options)!);
        return result.ToArray();
    }
    public void Save(RommRemoteState state)
    {
        using var db = Open();
        using var command = db.CreateCommand();
        command.CommandText = """
            INSERT INTO romm_remote VALUES($connection,$rom,$json)
            ON CONFLICT(connection_id,rom_id) DO UPDATE SET json=$json
            """;
        command.Parameters.AddWithValue("$connection", state.ConnectionId);
        command.Parameters.AddWithValue("$rom", state.RommId);
        command.Parameters.AddWithValue("$json", Json.Serialize(state));
        command.ExecuteNonQuery();
    }
}
