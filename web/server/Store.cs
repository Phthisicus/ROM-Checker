using Microsoft.Data.Sqlite;
using System.Text.Json;

namespace RomChecker.Web;

public sealed class Store
{
    private readonly string connectionString;
    public Store(WebOptions options)
    {
        Directory.CreateDirectory(options.Data);
        connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = Path.Combine(options.Data, "romchecker.db"),
            Mode = SqliteOpenMode.ReadWriteCreate
        }.ToString();
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY CHECK(id=1), json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS jobs (
              id TEXT PRIMARY KEY, created TEXT NOT NULL, status TEXT NOT NULL, json TEXT NOT NULL);
            """;
        command.ExecuteNonQuery();
        foreach (var job in All().Where(j => j.Status is "queued" or "running" or "cancelling"))
            Save(job with { Status = "interrupted", Finished = DateTimeOffset.UtcNow,
                Error = "The server restarted during this job. Review recovery journals before retrying file operations." });
    }
    private SqliteConnection Open()
    {
        var connection = new SqliteConnection(connectionString);
        connection.Open();
        return connection;
    }
    public EngineSettings Settings()
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT json FROM settings WHERE id=1";
        var json = command.ExecuteScalar() as string;
        return json is null ? new() : JsonSerializer.Deserialize<EngineSettings>(json, Json.Options)!;
    }
    public void SaveSettings(EngineSettings settings)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "INSERT INTO settings VALUES(1,$json) ON CONFLICT(id) DO UPDATE SET json=$json";
        command.Parameters.AddWithValue("$json", Json.Serialize(settings));
        command.ExecuteNonQuery();
    }
    public void Save(Job job)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO jobs VALUES($id,$created,$status,$json)
            ON CONFLICT(id) DO UPDATE SET status=$status,json=$json
            """;
        command.Parameters.AddWithValue("$id", job.Id);
        command.Parameters.AddWithValue("$created", job.Created.ToString("O"));
        command.Parameters.AddWithValue("$status", job.Status);
        command.Parameters.AddWithValue("$json", Json.Serialize(job));
        command.ExecuteNonQuery();
    }
    public Job Get(string id)
    {
        if (!Guid.TryParseExact(id, "N", out _)) throw new RequestException("Invalid job ID.");
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT json FROM jobs WHERE id=$id";
        command.Parameters.AddWithValue("$id", id);
        return command.ExecuteScalar() is string json
            ? JsonSerializer.Deserialize<Job>(json, Json.Options)!
            : throw new RequestException("Job not found.", 404);
    }
    public bool HasApplyAttempt(string sourceId)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT EXISTS(SELECT 1 FROM jobs
            WHERE json_extract(json,'$.action')='apply' AND json_extract(json,'$.request.sourceId')=$source)
            """;
        command.Parameters.AddWithValue("$source", sourceId);
        return Convert.ToInt64(command.ExecuteScalar()) == 1;
    }
    public List<Job> All()
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT json FROM jobs ORDER BY created DESC LIMIT 200";
        using var reader = command.ExecuteReader();
        var jobs = new List<Job>();
        while (reader.Read()) jobs.Add(JsonSerializer.Deserialize<Job>(reader.GetString(0), Json.Options)!);
        return jobs;
    }
}
