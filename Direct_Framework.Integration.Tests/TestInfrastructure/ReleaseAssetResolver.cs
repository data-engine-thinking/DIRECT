using System.Collections.Concurrent;
using System.IO.Compression;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace IntegrationTests.Infrastructure;

public sealed record ResolvedRelease(
  string Tag,
  string RootDir,
  bool HasDeploymentScripts);

/// <summary>
/// Resolves a tagged GitHub release of Direct_Framework to a local folder containing
/// Direct_Framework.dacpac, master.dacpac, and (optionally) an unzipped DeploymentScripts/ tree.
/// Downloads + caches on first request; cache hits return immediately.
/// </summary>
public static class ReleaseAssetResolver
{
  private const string DefaultRepo = "data-solution-automation-engine/DIRECT";
  private const string DacpacAsset = "Direct_Framework.dacpac";
  private const string MasterAsset = "master.dacpac";
  private const string DeploymentScriptsAsset = "DeploymentScripts.zip";
  private const string CompleteMarker = ".complete";

  private static readonly ConcurrentDictionary<string, SemaphoreSlim> _tagLocks = new();
  private static readonly Lazy<HttpClient> _http = new(CreateHttpClient);

  /// <summary>
  /// Resolve a release tag to a local cache folder. Pass "latest" to resolve via the GitHub API.
  /// </summary>
  public static async Task<ResolvedRelease> EnsureReleaseAsync(
    string tag = "latest",
    CancellationToken ct = default)
  {
    var explicitOverride = Environment.GetEnvironmentVariable("DIRECT_IT_BASELINE_TAG");
    if (!string.IsNullOrWhiteSpace(explicitOverride))
    {
      Console.WriteLine($"[ReleaseAssetResolver] DIRECT_IT_BASELINE_TAG override -> {explicitOverride}");
      tag = explicitOverride;
    }

    var resolvedTag = tag.Equals("latest", StringComparison.OrdinalIgnoreCase)
      ? await ResolveLatestTagAsync(ct).ConfigureAwait(false)
      : tag;

    var sem = _tagLocks.GetOrAdd(resolvedTag, _ => new SemaphoreSlim(1, 1));
    await sem.WaitAsync(ct).ConfigureAwait(false);
    try
    {
      var cacheDir = Path.Combine(GetCacheRoot(), resolvedTag);
      var marker = Path.Combine(cacheDir, CompleteMarker);
      if (File.Exists(marker))
      {
        Console.WriteLine($"[ReleaseAssetResolver] cache hit for {resolvedTag} -> {cacheDir}");
        return BuildResult(resolvedTag, cacheDir);
      }

      Console.WriteLine($"[ReleaseAssetResolver] downloading release {resolvedTag}");
      await DownloadReleaseAsync(resolvedTag, cacheDir, ct).ConfigureAwait(false);
      File.WriteAllText(marker, DateTime.UtcNow.ToString("O"));
      return BuildResult(resolvedTag, cacheDir);
    }
    finally
    {
      sem.Release();
    }
  }

  private static ResolvedRelease BuildResult(string tag, string cacheDir)
  {
    var hasScripts = Directory.Exists(Path.Combine(cacheDir, "DeploymentScripts"));
    return new ResolvedRelease(tag, cacheDir, hasScripts);
  }

  private static async Task<string> ResolveLatestTagAsync(CancellationToken ct)
  {
    var repo = GetRepo();
    var buildTag = Environment.GetEnvironmentVariable("GITHUB_REF_NAME")
                   ?? Environment.GetEnvironmentVariable("GIT_TAG");

    // Always fetch the top 2 so we can fall back if `latest` happens to be the
    // tag CI is currently building (would make the test compare a release to itself).
    var releases = await _http.Value
      .GetFromJsonAsync<List<GhRelease>>($"https://api.github.com/repos/{repo}/releases?per_page=5", ct)
      .ConfigureAwait(false)
      ?? throw new InvalidOperationException($"No releases returned for {repo}");

    var nonDraft = releases.Where(r => !r.Draft && !r.Prerelease).ToList();
    if (nonDraft.Count == 0)
      throw new InvalidOperationException($"No published releases found for {repo}");

    var top = nonDraft[0].TagName;
    if (!string.IsNullOrWhiteSpace(buildTag) && string.Equals(top, buildTag, StringComparison.Ordinal))
    {
      if (nonDraft.Count < 2)
        throw new InvalidOperationException(
          $"Build is on tag {buildTag} which matches the only published release; no previous baseline available.");
      var previous = nonDraft[1].TagName;
      Console.WriteLine($"[ReleaseAssetResolver] latest tag {top} matches build tag, falling back to previous release {previous}");
      return previous;
    }

    Console.WriteLine($"[ReleaseAssetResolver] latest release resolved to {top}");
    return top;
  }

  private static async Task DownloadReleaseAsync(string tag, string cacheDir, CancellationToken ct)
  {
    var repo = GetRepo();
    var release = await _http.Value
      .GetFromJsonAsync<GhRelease>($"https://api.github.com/repos/{repo}/releases/tags/{tag}", ct)
      .ConfigureAwait(false)
      ?? throw new InvalidOperationException($"Release {tag} not found in {repo}");

    var staging = cacheDir + ".staging-" + Guid.NewGuid().ToString("N");
    Directory.CreateDirectory(staging);
    try
    {
      var dacpacAsset = FindAsset(release, DacpacAsset)
        ?? throw new InvalidOperationException($"Release {tag} has no {DacpacAsset} asset");
      await DownloadAssetAsync(dacpacAsset, Path.Combine(staging, DacpacAsset), ct).ConfigureAwait(false);

      // master.dacpac MUST sit next to Direct_Framework.dacpac so DacServices can resolve the ref
      var masterAsset = FindAsset(release, MasterAsset);
      if (masterAsset is not null)
      {
        await DownloadAssetAsync(masterAsset, Path.Combine(staging, MasterAsset), ct).ConfigureAwait(false);
      }
      else
      {
        Console.WriteLine($"[ReleaseAssetResolver] WARNING: release {tag} has no {MasterAsset} asset; DacServices may fail to resolve referenced server-scoped objects");
      }

      var scriptsAsset = FindAsset(release, DeploymentScriptsAsset);
      if (scriptsAsset is not null)
      {
        var zipPath = Path.Combine(staging, DeploymentScriptsAsset);
        await DownloadAssetAsync(scriptsAsset, zipPath, ct).ConfigureAwait(false);
        var extractDir = Path.Combine(staging, "DeploymentScripts");
        ZipFile.ExtractToDirectory(zipPath, extractDir);
        File.Delete(zipPath);
        Console.WriteLine($"[ReleaseAssetResolver] extracted DeploymentScripts/ for {tag}");
      }
      else
      {
        Console.WriteLine($"[ReleaseAssetResolver] release {tag} has no {DeploymentScriptsAsset}; postdeploy step will be skipped");
      }

      // Atomic-rename staging -> final cache slot
      if (Directory.Exists(cacheDir))
        Directory.Delete(cacheDir, recursive: true);
      Directory.Move(staging, cacheDir);
    }
    catch
    {
      try { if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true); }
      catch { /* best-effort cleanup */ }
      throw;
    }
  }

  private static GhAsset? FindAsset(GhRelease release, string name) =>
    release.Assets?.FirstOrDefault(a => string.Equals(a.Name, name, StringComparison.Ordinal));

  private static async Task DownloadAssetAsync(GhAsset asset, string destPath, CancellationToken ct)
  {
    using var resp = await _http.Value.GetAsync(asset.BrowserDownloadUrl, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
    resp.EnsureSuccessStatusCode();
    await using var src = await resp.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
    await using var dst = File.Create(destPath);
    await src.CopyToAsync(dst, ct).ConfigureAwait(false);
    Console.WriteLine($"[ReleaseAssetResolver]   downloaded {asset.Name} ({asset.Size:N0} bytes)");
  }

  private static string GetRepo() =>
    Environment.GetEnvironmentVariable("DIRECT_RELEASE_REPO") is { Length: > 0 } r ? r : DefaultRepo;

  private static string GetCacheRoot()
  {
    var overrideDir = Environment.GetEnvironmentVariable("DIRECT_IT_CACHE_DIR");
    if (!string.IsNullOrWhiteSpace(overrideDir))
      return overrideDir;

    var runnerTemp = Environment.GetEnvironmentVariable("RUNNER_TEMP");
    if (!string.IsNullOrWhiteSpace(runnerTemp))
      return Path.Combine(runnerTemp, "DirectFwIT", "releases");

    var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
    if (string.IsNullOrWhiteSpace(localAppData))
      localAppData = Path.GetTempPath();
    return Path.Combine(localAppData, "DirectFwIT", "releases");
  }

  private static HttpClient CreateHttpClient()
  {
    var c = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
    c.DefaultRequestHeaders.UserAgent.ParseAdd("DirectFramework.IntegrationTests/1.0");
    c.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
    var token = Environment.GetEnvironmentVariable("GITHUB_TOKEN");
    if (!string.IsNullOrWhiteSpace(token))
      c.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
    return c;
  }

  private sealed class GhRelease
  {
    [JsonPropertyName("tag_name")] public string TagName { get; set; } = "";
    [JsonPropertyName("draft")] public bool Draft { get; set; }
    [JsonPropertyName("prerelease")] public bool Prerelease { get; set; }
    [JsonPropertyName("assets")] public List<GhAsset>? Assets { get; set; }
  }

  private sealed class GhAsset
  {
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("size")] public long Size { get; set; }
    [JsonPropertyName("browser_download_url")] public string BrowserDownloadUrl { get; set; } = "";
  }
}
