<#
.SYNOPSIS
    ROM Sorter - checks, verifies and organises ROMs and disc images for many emulators, with menus.

.DESCRIPTION
    Scans the ROM folder and EVERY subfolder (any depth) and for every file checks:

      1. SECURITY   - programs disguised as ROMs (Windows/Linux executables, double extensions
                      like "Mario.sfc.exe", hidden right-to-left characters, archives renamed to
                      ROMs, embedded Windows programs, archives that contain programs), Windows
                      Defender / Linux ClamAV when enabled, and optional VirusTotal and
                      MalwareBazaar lookups (online, hash only).
      2. VALIDITY   - the internal header for its console (SNES checksum, iNES, GB/GBA logo and
                      checksums, N64 byte order, NDS CRC, SEGA header, ISO-9660 / GameCube / Wii /
                      PSP / Saturn / Sega CD / 3DS / Switch signatures, ...) and complete disc sets
                      (.cue/.gdi/.m3u/.ccd/.mds tracks present).
      3. ORIGINAL   - system-scoped SHA256/SHA1/MD5 when supplied by a DAT; otherwise
                      weaker, explicitly labelled CRC32/size matching (your own folder and/or
                      downloaded automatically from the libretro database), online lookup at
                      Hasheous (No-Intro, Redump, TOSEC, MAME, RetroAchievements, known hacks), and
                      GoodTools / No-Intro filename tags (Hack, [T+], [b], (Beta), (Unl), ...).
      4. REAL GAME  - "retail only" (default): a file only counts as OK when an online game
                      library confirms it is a released game. Libraries used: No-Intro/Redump,
                      libretro release info (year + publisher), Hasheous (incl. its demo flag) and
                      the IGDB / TheGamesDB / RetroAchievements / LaunchBox entries Hasheous links.
                      Demos, betas, prototypes, homebrew, unlicensed, pirate, hacks, tools, videos
                      and files no library knows are all flagged.
      5. DUPLICATES - identical SHA-1 hashes found in several places for the same system.

    ARCHIVES (.zip .7z .rar .gz .tar): "Unpack archives only" / "Full workflow" first checks every
    archive for malware (programs inside, fake extensions, zip-slip paths, zip bombs, Windows
    Defender / Linux ClamAV, MalwareBazaar/VirusTotal when a key is set), unpacks only the
    eligible ones into a private staging folder, scans the unpacked files again and places them
    next to the archive (names unchanged). Originals are kept in <Root>\_Unpacked archives\.
    Nested archives are unpacked too. Arcade (MAME) sets stay zipped. Undo removes the copies.
    ZIP/7z/RAR/gzip signatures also identify unknown extensions such as DOS-shortened .ZI.
    An archive signature identifies its format, not whether it is complete or malware-free.
    If an enabled antivirus scan fails or is unavailable, extraction is skipped; a check-only
    run records the incomplete protection as a warning instead of claiming a clean scan.
    Archive limits (Settings > Other options): 16 GiB extracted bytes and 10,000 entries
    across an unpack run, three nested levels, and 300 seconds per extraction/listing.
    Limits are enforced while streaming, not only from archive declarations. Limit failures
    keep the archive packed and are not malware verdicts. 7-Zip streams each entry to a
    validated path, rather than letting an external extractor write arbitrary paths.
    Undo verifies SHA-256; changed files and legacy extracts without hashes are kept.
    Authenticity, integrity, antivirus completion and malware indicators are independent
    report fields. "No detections" never means guaranteed safe.
    Local checks are checkpointed under _RomSorter/scan-cache. Run Check again to resume:
    unchanged content is revalidated with SHA-256; antivirus, DATs and relationships are
    refreshed. Disable reuse in Other options for a fresh check. Sort can restore the last
    completed check; its AV results are historical evidence. Apply revalidates content.
    Permanent offline regression suite:
      powershell -NoProfile -ExecutionPolicy Bypass -File .\RomSorter.Tests.ps1
      pwsh -NoProfile -File ./RomSorter.Tests.ps1
    ADDING MORE GAMES: run menu 6 (Full workflow) again, or use -DoEverything.
    Each run enumerates the current folder tree, including newly created subfolders,
    extracts eligible new ZIPs, checks new/changed ROMs, and rebuilds the sort plan.
    Unchanged local checks are reused only after SHA-256 revalidation. Original archives,
    including extracted inner archives, are moved to _Unpacked archives so later runs
    do not repeatedly extract them. Do not put new downloads in the recovery, quarantine,
    duplicates, application-work or protected emulator folders.
    Saved plans are rejected if files have been added or removed since the check.
    Directory traversal has no artificial depth cap; archive nesting/resource limits
    still apply, and arcade sets stay packed for emulator compatibility.
    Loose BIOS/firmware with an identifiable console sorts into <Root>/<Console>/BIOS,
    independently of the game layout. Recognition uses filenames/folder context, not
    proof of authenticity. Unknown firmware, keys, packed BIOS sets and protected emulator
    installations stay in place. This organises a collection; it does not install firmware
    into emulators. Existing emulator configurations may need their BIOS path updated.
    CLEANUP (menu C): previews processed archives in _Unpacked archives and their total
    disk space. Only successfully journaled archives with SHA-256-verified extracted
    copies are eligible; sorted copies are followed through move journals. Nested archives
    require verified surviving copies or their own verified extracted contents.
    Confirming cleanup PERMANENTLY deletes eligible archives (not to the recycle bin),
    disabling extraction undo for those archives. Untracked, changed, failed/blocked
    archives and packed arcade sets are kept. Cleanup is never run automatically.
    Older extraction journals without a completion marker are kept conservatively;
    cleanup requires complete evidence, not just an archive name or an existing ROM.

    UNKNOWN FILES: automatic Hasheous identification sends hashes only, never file
    contents, names or paths. Settings > Verification > 8 disables this separately
    from normal game verification. Unknown loose ROMs and firmware are mapped only
    when reference size and SHA256/SHA1 agree and the platform has an exact local
    profile. Weak/conflicting results are clues for manual review, not sorting rules.
    Keys, protected installations, programs, unsafe files and packed/dependent sets
    are not submitted by this fallback. Hash size limits still apply.
    Every check writes dated Identification-*.html and .csv under _RomSorter/reports,
    with online clues, unresolved/error reasons, hashes and suggested improvements.
    Regular reports also keep dated copies alongside the existing latest reports.
    Unavailable services/rate limits are reported and retried, not recorded as success.
    Unknown online hashes are retried each check; successful references are cached
    for 30 days and remapped against current console profiles after script updates.

    UPDATING: replace RomSorter.ps1/RomSorter.sh, but keep the collection's _RomSorter
    folder and your RomSorter user configuration/cache. Successful local checks use
    a versioned state format independent of script bytes and survive replacement.
    SHA256 still revalidates unchanged files; antivirus and reference checks refresh.
    Unidentified, invalid and failed local checks are retried on subsequent checks.
    Sorting transfers saved local evidence to the new path after a verified move.
    Legacy pre-versioned checkpoints are safely refreshed once; reports/journals stay.
    Future incompatible analysis/security changes must bump LocalAnalysisSchema and
    checkpoint Schema together to require a fresh local check. Completed move previews
    remain tied to the exact script version and must be regenerated after replacement.

    PROGRESS: interactive terminals show overall workflow steps, a current-stage bar,
    and measured byte progress for hashing and extraction. Counts, processed data,
    throughput, elapsed time and smoothed stage ETA update at most four times/second.
    ETA starts after enough measurements; discovery, dynamic archive queues, antivirus
    and network waits show unknown remaining time instead of invented percentages.
    ETA is for the current measurable stage, not a prediction for the whole workflow.
    Redirected/non-console output uses plain phase updates and ten-second snapshots.
    Each action ends with elapsed time and result counters; interrupted/failed actions
    say stopped/incomplete. PowerShell 7's Classic progress view is restored afterward.

    FULL WORKFLOW (menu 6 or -DoEverything): unpack -> check every file -> sort using the
    selected layout (including Validity). With the default ByConsole layout, the result is:
      <Root>\<Console>\           only verified, real released games
      <Root>\_Not valid\<Console>\<reason>\   demos, homebrew, hacks, bad dumps, unverified
      <Root>\_Quarantine\  <Root>\_Duplicates\  <Root>\_Unpacked archives\

    By default the script only CHECKS and reports; nothing is moved. Optionally it sorts the
    files. File names are NEVER changed, nothing is ever overwritten, multi-file games (cue/bin,
    gdi, m3u) stay together, saves/patches/cheats with the same name follow their ROM,
    emulator/program folders are left alone, and every move is journaled so it can be undone.

      Layout "ByConsole" (default when sorting) <Root>\SNES\...
      Layout "Validity" (sort by validity)      <Root>\SNES\Verified\Retail | Revisions | Demos | Other-Official-Releases
                                                <Root>\SNES\Modified\Hacks | Translations | Fixed | Trainers | Pirate
                                                <Root>\SNES\Non-Retail\Homebrew | Unlicensed | Prototypes
                                                <Root>\SNES\Unverified\Unknown | Needs-Verification
                                                <Root>\SNES\Invalid\Bad-Dumps | Corrupted | Incomplete
      Layout "Emulator"                         <Root>\Snes9x\SNES\Super Mario World (USA).sfc
                                                <Root>\Snes9x\SNES\Non-Original\Hacks_Mods\...
      Layout "Frontend" (ES-DE, RetroBat,      <Root>\snes\...      <Root>\psx\...
             Batocera, EmuDeck, Recalbox)
      Layout "RetroArch" (libretro names)       <Root>\Nintendo - Super Nintendo Entertainment System\...
      Layout "Classic" (like the old script)    originals stay where they are
      Always:                                   <Root>\_Quarantine\   <Root>\_Duplicates\

    Recognised system profiles: SNES, NES, FDS, GB, GBC, GBA, N64, NDS, 3DS, Virtual Boy, Pokemon Mini, Mega Drive,
    32X, Master System, Game Gear, SG-1000, Sega CD, Saturn, Dreamcast, PC Engine (+CD), Atari
    2600/5200/7800/Lynx/Jaguar, WonderSwan (Color), Neo Geo Pocket (Color), ColecoVision,
    Intellivision, Vectrex, MSX, PlayStation 1/2, PSP, GameCube, Wii, Wii U, Switch, Xbox, 3DO,
    MAME, FBNeo, Neo Geo AES/MVS/CD, Naomi/Naomi 2, Atomiswave, Commodore 64/128, VIC-20,
    Plus/4, Amiga/CD32/CDTV, Atari 8-bit/ST, Amstrad CPC/GX4000, ZX Spectrum, Sharp X68000,
    NEC PC-98 - with emulator suggestions (Snes9x, bsnes, Mesen, mGBA, melonDS,
    Azahar, Project64, DuckStation, PCSX2, PPSSPP, Dolphin, Flycast, Mednafen, MAME, RetroArch...).
    Emulator suggestions do not install emulators or guarantee a game is playable.
    Shared extensions (.dsk, .tap, .prg, .crt, .st, .ipf, .hdf, etc.) need a recognisable
    signature or a matching parent folder. Unidentified images stay in place, not guessed.
    Headerless computer media and WHDLoad .lha packages need matching DAT/hash evidence to
    be classed as verified. Some compressed/preservation formats need specialised external
    tools to verify the underlying media; lack of verification is not proof of corruption.
    Keep sets under MAME, FBNeo, NeoGeo, Naomi, Naomi2 or Atomiswave folders. With folder
    protection enabled (default), arcade folders are scanned but not internally reorganised;
    archives stay packed and parent/clone, BIOS and CHD paths are preserved. When the chosen
    scan root itself has that system name it is protected too. If protection is disabled,
    individual arcade files may move independently; do not disable it for dependent sets.
    Arcade recognition is NOT a version-specific set audit. Use the exact emulator's DAT
    and a specialised set auditor to validate completeness, BIOS, parents and CHDs.
    Generic chip-dump archives without a system hint are kept packed as possible arcade sets,
    never claimed verified. Use a named system folder to distinguish MAME/FBNeo/Naomi/Neo Geo.
    Amiga WHDLoad .lha packages stay packed; extracted games with .slave/.info/.uae files and
    configured computer-game folders stay together. Host .exe/.com/.cmd files remain subject
    to security handling even though some legacy systems can use those extensions.
    Format and set-layout references:
      https://docs.libretro.com/library/vice/
      https://docs.libretro.com/library/puae/
      https://docs.libretro.com/library/flycast/

    Start the script without parameters to get the menu (a setup wizard runs the first time).
    Checking never moves anything. Sorting is a preview first; nothing is moved until you confirm.
    MAIN MENU:
      1 Check files      - report only, no unpacking or moving.
      2 Sort by validity - select Validity and continue to sorting; not just a setting.
      3 Sort by console  - select ByConsole and continue to sorting.
      4 Other sorting    - choose emulator, frontend, RetroArch, Classic, or another layout,
                           then continue directly to sorting.
                           Sorting reuses the last check or builds a filename/extension inventory.
                           No antivirus, content validation, hashing, or online lookups run.
                           Without verification evidence, validity sorting uses Unverified.
                           Preview and Apply before moving files. Changed files need a new check.
      5 Check + sort     - a fresh check using the current layout, then preview and Apply.
      6 Full workflow    - confirm once, then unpack, check and sort using the current layout.
      7 Undo             - restore a previous run (newest first).
      8 Unpack only      - archive safety checks and extraction, without sorting.
      9 Results          - review reasons, file details, tables and HTML reports.
      S Settings         - folder, sort layout, verification, security and file handling.
      Q Quit
    Settings > Sort layout changes only the destination layout; it does not start an action.
    Changing the layout keeps the last check available; changing verification or file handling
    settings clears it so that the next check uses the new settings. Last checks are not
    reloaded from disk when the script is restarted.

.EXAMPLE
    .\RomSorter.ps1
    Opens the interactive menu.

.EXAMPLE
    .\RomSorter.ps1 -RootFolder D:\Roms -DoEverything
    Unpack (after a malware check), check every file and sort using the saved layout, no questions.

.EXAMPLE
    .\RomSorter.ps1 -RootFolder D:\Roms -Layout Validity -DoEverything
    Unpack, check and sort by validity, no questions.

.EXAMPLE
    .\RomSorter.ps1 -RootFolder D:\Roms -NoMenu
    Check only (no menu): shows the summary and writes _RomSorter\Preview-latest.csv + HTML report.

.EXAMPLE
    .\RomSorter.ps1 -RootFolder D:\Roms -NoMenu -RetailOnly:$false
    Check, but accept ROMs no online library knows when their header and name look fine.

.EXAMPLE
    .\RomSorter.ps1 -RootFolder D:\Roms -Layout Frontend -AutoDat -Hasheous Unverified -Apply
    Verify with downloaded DATs + Hasheous and sort into ES-DE/RetroBat style folders.

.EXAMPLE
    .\RomSorter.ps1 -RootFolder D:\Roms -NoMenu -OnlineCheck Risky -VirusTotalKey <your key>
    Preview with VirusTotal lookups (Windows saves the key encrypted; Linux uses it for this process only).

.EXAMPLE
    .\RomSorter.ps1 -Undo -Apply
    Undo the most recent run.

.NOTES
    Windows: Windows PowerShell 5.1 or PowerShell 7. Ubuntu/WSL: PowerShell 7 (pwsh).
    Automatic Ubuntu/WSL setup: keep RomSorter.sh beside this file and run:
      bash ./RomSorter.sh -RootFolder "/home/you/Roms"
    The launcher installs missing PowerShell 7 (.NET dependencies included), ClamAV,
    clamav-freshclam and 7zip (p7zip-full on older Ubuntu). It verifies the official PowerShell
    package checksum, checks the antivirus database, and starts this script as the current user.
    Only installation/updates use sudo; Ubuntu may ask for your password. Internet and working
    Ubuntu apt repositories are required. Automatic installation currently supports amd64 only.
    Setup errors stop the launcher before any ROM action. Use --install-only for setup alone.
    The initial signature download can take several minutes. Existing working tools are reused.
    To manage dependencies yourself instead: pwsh -NoProfile -File ./RomSorter.ps1 ...
    Keep ClamAV databases updated with freshclam / the clamav-freshclam service.
    ZIP extraction does not require 7-Zip.
    WSL Windows-drive example: -RootFolder /mnt/c/Users/you/Downloads/Roms
    Use Linux-style paths in Ubuntu; do not run Windows and Linux sorting on the same library
    concurrently. Undo journals must be used on the same OS/path namespace that created them.
    Linux respects filename case and skips symbolic links. Prefer a Linux filesystem for
    case-distinct names; Windows-mounted drives may be case-insensitive.
    Settings/cache: %APPDATA%\RomSorter on Windows; $XDG_CONFIG_HOME/RomSorter or
    ~/.config/RomSorter on Linux. Windows and Linux settings are independent.
    -AntivirusScan is an alias for the legacy -DefenderScan switch; on Linux it selects ClamAV.
    Linux API keys are never persisted by the script: supply ROMSORTER_VIRUSTOTAL_KEY and/or
    ROMSORTER_MALWAREBAZAAR_KEY in the process environment, CLI, or menu for each session.
    Optional report/browser opening needs xdg-open and a graphical session on Linux/WSL.
    Content heuristics and antivirus cannot guarantee a file is safe; game authenticity
    requires matching trusted verification data, not just a filename or a valid header.

    If scripts are blocked on your PC:
    powershell -ExecutionPolicy Bypass -File .\RomSorter.ps1
#>
[CmdletBinding()]
param(
    [string]$RootFolder,
    [string]$Console,
    [string]$DatFolder,
    [ValidateSet('Emulator', 'Frontend', 'RetroArch', 'ByConsole', 'Validity', 'Classic')][string]$Layout,
    [switch]$SortByCategory,
    [Alias('AntivirusScan')][switch]$DefenderScan,
    [switch]$Strict,
    [switch]$RetailOnly,
    [switch]$MoveBSandST,
    [switch]$AutoDat,
    [ValidateSet('Off', 'Unverified', 'All')][string]$Hasheous,
    [switch]$Apply,
    [switch]$Undo,
    [switch]$ListRemaining,
    [switch]$NoMenu,
    [switch]$DefinitionsOnly,
    [switch]$Unpack,
    [switch]$DoEverything,
    [ValidateSet('Off', 'Risky', 'Unverified', 'All')][string]$OnlineCheck,
    [string]$VirusTotalKey,
    [string]$MalwareBazaarKey
)

$ErrorActionPreference = 'Stop'
$script:ScriptPath = $PSCommandPath
$script:OnWindows = [IO.Path]::DirectorySeparatorChar -eq '\'
$script:PathComparison = if ($script:OnWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$script:PathComparer = if ($script:OnWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
$script:AntivirusName = if ($script:OnWindows) { 'Windows Defender' } else { 'ClamAV' }

# ===================================================================== NATIVE HELPERS
if (-not ('RomSorter.RomTools' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
namespace RomSorter {
public static class RomTools {
    static readonly uint[] T = MakeTable();
    static uint[] MakeTable() {
        uint[] t = new uint[256];
        for (uint i = 0; i < 256; i++) { uint c = i; for (int k = 0; k < 8; k++) c = ((c & 1) != 0) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1); t[i] = c; }
        return t;
    }
    public static string Crc32(byte[] d, int off, int len) {
        uint c = 0xFFFFFFFFu; int end = off + len;
        for (int i = off; i < end; i++) c = T[(c ^ d[i]) & 0xFF] ^ (c >> 8);
        return (c ^ 0xFFFFFFFFu).ToString("X8");
    }
    public static long Sum(byte[] d, int off, int len) {
        long s = 0; int end = off + len; for (int i = off; i < end; i++) s += d[i]; return s;
    }
    public static int SnesChecksum(byte[] d, int off, int len) {
        if (len <= 0) return 0;
        int b = 1; while (b <= len / 2) b *= 2;
        long s = Sum(d, off, b); int rest = len - b;
        if (rest > 0) { long rs = Sum(d, off + b, rest); if (b % rest == 0) s += rs * (b / rest); else s += rs; }
        return (int)(s & 0xFFFF);
    }
    public static int WordSumBE(byte[] d, int off, int len) {
        long s = 0; int end = off + len; for (int i = off; i + 1 < end; i += 2) s += (d[i] << 8) | d[i + 1];
        return (int)(s & 0xFFFF);
    }
    public static int Crc16(byte[] d, int off, int len) {
        int crc = 0xFFFF;
        for (int i = off; i < off + len; i++) { crc ^= d[i]; for (int k = 0; k < 8; k++) crc = ((crc & 1) != 0) ? ((crc >> 1) ^ 0xA001) : (crc >> 1); }
        return crc & 0xFFFF;
    }
    public static byte[] ToZ64(byte[] d) {
        byte[] o = new byte[d.Length];
        if (d[0] == 0x37 && d[1] == 0x80) { for (int i = 0; i + 1 < d.Length; i += 2) { o[i] = d[i + 1]; o[i + 1] = d[i]; } }
        else if (d[0] == 0x40 && d[1] == 0x12) { for (int i = 0; i + 3 < d.Length; i += 4) { o[i] = d[i + 3]; o[i + 1] = d[i + 2]; o[i + 2] = d[i + 1]; o[i + 3] = d[i]; } }
        else Array.Copy(d, o, d.Length);
        return o;
    }
    public static byte[] SmdToBin(byte[] d) {
        int n = (d.Length - 512) / 16384; byte[] o = new byte[n * 16384];
        for (int b = 0; b < n; b++) { int src = 512 + b * 16384, dst = b * 16384;
            for (int i = 0; i < 8192; i++) { o[dst + 2 * i + 1] = d[src + i]; o[dst + 2 * i] = d[src + 8192 + i]; } }
        return o;
    }
    public static int IndexOf(byte[] d, byte[] p) {
        int last = d.Length - p.Length;
        for (int i = 0; i <= last; i++) { if (d[i] != p[0]) continue; int k = 1; while (k < p.Length && d[i + k] == p[k]) k++; if (k == p.Length) return i; }
        return -1;
    }
    // Long-path safe form (\\?\C:\... or \\?\UNC\server\share\...)
    public static string LP(string p) {
        if (System.IO.Path.DirectorySeparatorChar != '\\') return p;
        if (string.IsNullOrEmpty(p) || p.StartsWith(@"\\?\")) return p;
        if (p.StartsWith(@"\\")) return @"\\?\UNC\" + p.Substring(2);
        return @"\\?\" + p;
    }
    public static string Plain(string p) {
        if (System.IO.Path.DirectorySeparatorChar != '\\') return p;
        if (string.IsNullOrEmpty(p)) return p;
        if (p.StartsWith(@"\\?\UNC\")) return @"\\" + p.Substring(8);
        if (p.StartsWith(@"\\?\")) return p.Substring(4);
        return p;
    }
    public static uint BE32(byte[] d, int o) { if (o < 0 || o + 4 > d.Length) return 0; return ((uint)d[o] << 24) | ((uint)d[o+1] << 16) | ((uint)d[o+2] << 8) | d[o+3]; }
    public static uint LE32(byte[] d, int o) { if (o < 0 || o + 4 > d.Length) return 0; return BitConverter.ToUInt32(d, o); }
    static string Hex(byte[] h) { return BitConverter.ToString(h).Replace("-", ""); }
    // CRC32 + MD5 + SHA1 + SHA256 in one pass over a byte range
    public static string[] HashBytes(byte[] d, int off, int len) {
        using (var md5 = System.Security.Cryptography.MD5.Create())
        using (var s1 = System.Security.Cryptography.SHA1.Create())
        using (var s256 = System.Security.Cryptography.SHA256.Create()) {
            return new string[] { Crc32(d, off, len), Hex(md5.ComputeHash(d, off, len)), Hex(s1.ComputeHash(d, off, len)), Hex(s256.ComputeHash(d, off, len)) };
        }
    }
    // Same, streamed from disk (works for multi-GB disc images); skip = bytes to skip at start
    public static string[] HashFile(string path, long skip) {
        return HashFile(path, skip, null);
    }
    public static string[] HashFile(string path, long skip, Action<long,long> progress) {
        using (var fs = new System.IO.FileStream(LP(path), System.IO.FileMode.Open, System.IO.FileAccess.Read, System.IO.FileShare.Read, 1 << 20))
        using (var md5 = System.Security.Cryptography.MD5.Create())
        using (var s1 = System.Security.Cryptography.SHA1.Create())
        using (var s256 = System.Security.Cryptography.SHA256.Create()) {
            if (skip > 0) fs.Seek(skip, System.IO.SeekOrigin.Begin);
            byte[] buf = new byte[1 << 20]; uint c = 0xFFFFFFFFu; int n;
            var watch = System.Diagnostics.Stopwatch.StartNew(); long last = -250;
            while ((n = fs.Read(buf, 0, buf.Length)) > 0) {
                for (int i = 0; i < n; i++) c = T[(c ^ buf[i]) & 0xFF] ^ (c >> 8);
                md5.TransformBlock(buf, 0, n, null, 0); s1.TransformBlock(buf, 0, n, null, 0); s256.TransformBlock(buf, 0, n, null, 0);
                if (progress != null && watch.ElapsedMilliseconds - last >= 250) {
                    progress(fs.Position - skip, fs.Length - skip); last = watch.ElapsedMilliseconds;
                }
            }
            md5.TransformFinalBlock(buf, 0, 0); s1.TransformFinalBlock(buf, 0, 0); s256.TransformFinalBlock(buf, 0, 0);
            if (progress != null) progress(fs.Length - skip, fs.Length - skip);
            return new string[] { (c ^ 0xFFFFFFFFu).ToString("X8"), Hex(md5.Hash), Hex(s1.Hash), Hex(s256.Hash) };
        }
    }
    public static string Sha256File(string path, Action<long,long> progress) {
        using (var fs = new System.IO.FileStream(LP(path), System.IO.FileMode.Open, System.IO.FileAccess.Read, System.IO.FileShare.Read, 1 << 20))
        using (var sha = System.Security.Cryptography.SHA256.Create()) {
            byte[] buffer = new byte[1 << 20]; int n;
            var watch = System.Diagnostics.Stopwatch.StartNew(); long last = -250;
            while ((n = fs.Read(buffer, 0, buffer.Length)) > 0) {
                sha.TransformBlock(buffer, 0, n, null, 0);
                if (progress != null && watch.ElapsedMilliseconds - last >= 250) {
                    progress(fs.Position, fs.Length); last = watch.ElapsedMilliseconds;
                }
            }
            sha.TransformFinalBlock(buffer, 0, 0);
            if (progress != null) progress(fs.Length, fs.Length);
            return Hex(sha.Hash);
        }
    }
    public static byte[] ReadAt(string path, long pos, int count) {
        using (var fs = new System.IO.FileStream(LP(path), System.IO.FileMode.Open, System.IO.FileAccess.Read, System.IO.FileShare.Read)) {
            if (pos >= fs.Length) return new byte[0];
            fs.Seek(pos, System.IO.SeekOrigin.Begin);
            int n = (int)Math.Min((long)count, fs.Length - pos); byte[] b = new byte[n]; int r = 0;
            while (r < n) { int k = fs.Read(b, r, n - r); if (k <= 0) break; r += k; }
            if (r < n) Array.Resize(ref b, r);
            return b;
        }
    }
    public static long CopyLimited(System.IO.Stream input, System.IO.Stream output, long limit, int milliseconds) {
        return CopyLimited(input, output, limit, milliseconds, null);
    }
    public static long CopyLimited(System.IO.Stream input, System.IO.Stream output, long limit, int milliseconds, Action<long,long> progress) {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        byte[] buffer = new byte[65536]; long total = 0; long last = -250;
        while (true) {
            int remaining = milliseconds - (int)Math.Min(watch.ElapsedMilliseconds, int.MaxValue);
            if (remaining <= 0) throw new System.IO.IOException("Archive resource limit: extraction timeout");
            var read = input.ReadAsync(buffer, 0, buffer.Length);
            if (!read.Wait(remaining)) throw new System.IO.IOException("Archive resource limit: extraction timeout");
            int n = read.Result;
            if (n == 0) break;
            if (n > limit - total) throw new System.IO.IOException("Archive resource limit: extracted byte limit exceeded");
            output.Write(buffer, 0, n); total += n;
            if (progress != null && watch.ElapsedMilliseconds - last >= 250) {
                progress(total, limit); last = watch.ElapsedMilliseconds;
            }
        }
        return total;
    }
    public static string QuoteArgument(string value) {
        if (value.IndexOf('\0') >= 0 || value.IndexOf('\n') >= 0 || value.IndexOf('\r') >= 0)
            throw new ArgumentException("Invalid process argument");
        var text = new System.Text.StringBuilder("\""); int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { text.Append('\\', slashes * 2 + 1).Append(c); slashes = 0; continue; }
            text.Append('\\', slashes).Append(c); slashes = 0;
        }
        return text.Append('\\', slashes * 2).Append('"').ToString();
    }
}}
'@
}

# ===================================================================== LIVE PROGRESS
function Format-ProgressTime([double]$Seconds) {
    $span = [TimeSpan]::FromSeconds([math]::Max(0,[math]::Min($Seconds,315360000)))
    '{0:00}:{1:00}:{2:00}' -f [int][math]::Floor($span.TotalHours),$span.Minutes,$span.Seconds
}
function Get-ProgressEstimate([double]$Done, [double]$Total, [double]$Elapsed, [double]$Rate, [bool]$Unknown = $false) {
    $percent = -1; $remaining = -1
    if (-not $Unknown -and $Total -gt 0) {
        $percent = [int][math]::Floor(100 * [math]::Min(1.0,[math]::Max(0.0,$Done / $Total)))
        if ($Done -ge $Total) { $remaining = 0 }
        elseif ($Elapsed -ge 3 -and $Done -gt 0 -and $Rate -gt 0) { $remaining = [int][math]::Min(2147483647,[math]::Ceiling(($Total - $Done) / $Rate)) }
    }
    [pscustomobject]@{ Percent = $percent; SecondsRemaining = $remaining }
}
function Test-LiveProgress {
    $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected -and $env:TERM -ne 'dumb'
}
function Invoke-ProgressTask([string]$Name, [scriptblock]$Body, [string[]]$Stages = @()) {
    $parent = $script:RomProgress
    $frame = @{
        Name = $Name; Watch = [Diagnostics.Stopwatch]::StartNew(); PhaseWatch = [Diagnostics.Stopwatch]::StartNew()
        Phase = ''; Done = 0.0; Total = -1.0; Unit = 'files'; Rate = 0.0; LastDone = 0.0; LastSample = 0.0
        Current = ''; Detail = ''; Unknown = $true; LastRender = -1.0; LastText = -30.0; LastPhase = ''
        Live = (Test-LiveProgress); Counters = [ordered]@{}; Stages = $Stages; StageIndex = 0
        StageStates = @($Stages | ForEach-Object { 'Waiting' }); File = $null; LastFileRender = -1.0
    }
    $previousView = $null
    if ($frame.Live -and $PSVersionTable.PSVersion -ge [version]'7.2') { $previousView = $PSStyle.Progress.View; $PSStyle.Progress.View = 'Classic' }
    $script:RomProgress = $frame
    $success = $false
    if ($parent -and $parent.Stages.Count) {
        $index = [array]::IndexOf($parent.Stages,$Name)
        if ($index -ge 0) { $parent.StageIndex = $index; $parent.StageStates[$index] = 'Running' }
    }
    try {
        Update-RomProgress -Phase 'Starting' -Indeterminate -Force
        & $Body
        $success = $true
    } finally {
        if ($frame.Live) {
            foreach ($id in 72,71,70) { Write-Progress -Id $id -Activity $Name -Completed }
        }
        $status = if ($success) { 'Finished' } else { 'Stopped / incomplete' }
        $color = if (-not $success) { 'Red' } elseif ($frame.Counters.Contains('Warnings') -and $frame.Counters['Warnings'] -gt 0) { 'Yellow' } else { 'Green' }
        $counts = @($frame.Counters.Keys | ForEach-Object { "$_=$($frame.Counters[$_])" }) -join ' | '
        Write-Host "  $Name - $status | elapsed $(Format-ProgressTime $frame.Watch.Elapsed.TotalSeconds)$(if ($counts) { ' | ' + $counts })" -ForegroundColor $color
        if ($frame.Stages.Count) {
            Write-Host ('  ' + (@(for ($i=0;$i -lt $frame.Stages.Count;$i++) { "$($frame.Stages[$i]): $($frame.StageStates[$i])" }) -join ' | ')) -ForegroundColor $color
        }
        $script:LastProgressSummary = [pscustomobject]@{ Name = $Name; Status = $status; Counters = $frame.Counters; Seconds = $frame.Watch.Elapsed.TotalSeconds }
        $script:RomProgress = $parent
        if ($parent -and $parent.Stages.Count) {
            $index = [array]::IndexOf($parent.Stages,$Name)
            if ($index -ge 0) {
                $parent.StageStates[$index] = $status
                if ($frame.Counters.Contains('Warnings') -and $frame.Counters['Warnings'] -gt 0) { $parent.StageStates[$index] += ' (warnings)' }
                foreach ($key in $frame.Counters.Keys) {
                    if ($key -eq 'Warnings') { $parent.Counters['Warnings'] = [int]$parent.Counters['Warnings'] + [int]$frame.Counters[$key] }
                    else { $parent.Counters["$Name $key"] = $frame.Counters[$key] }
                }
            }
        }
        if ($null -ne $previousView) { $PSStyle.Progress.View = $previousView }
    }
}
function Set-ProgressCounter([string]$Name, $Value) {
    if ($script:RomProgress) { $script:RomProgress.Counters[$Name] = $Value }
}
function Update-RomProgress {
    param([string]$Phase, [double]$Done, [double]$Total, [string]$Unit = 'files',
          [string]$Current = '', [string]$Detail = '', [switch]$Indeterminate, [switch]$Force)
    $p = $script:RomProgress
    if (-not $p) { return }
    $newPhase = $Phase -and $Phase -ne $p.Phase
    if ($newPhase) {
        if ($p.File -and $p.Live) { Write-Progress -Id 72 -Activity 'File operation' -Completed }
        $p.Phase = $Phase; $p.PhaseWatch.Restart(); $p.Rate = 0.0; $p.LastDone = 0.0; $p.LastSample = 0.0
        $p.Done = 0.0; $p.Total = -1.0; $p.File = $null
    }
    if ($PSBoundParameters.ContainsKey('Done')) { $p.Done = $Done }
    if ($PSBoundParameters.ContainsKey('Total')) { $p.Total = $Total }
    $p.Unit = $Unit; $p.Current = $Current; $p.Detail = $Detail; $p.Unknown = [bool]$Indeterminate -or $p.Total -le 0
    $now = $p.PhaseWatch.Elapsed.TotalSeconds
    if ($now - $p.LastSample -ge 0.25) {
        $sample = [math]::Max(0.0,($p.Done - $p.LastDone) / ($now - $p.LastSample))
        $p.Rate = if ($p.Rate -le 0) { $sample } else { 0.25 * $sample + 0.75 * $p.Rate }
        $p.LastDone = $p.Done; $p.LastSample = $now
    }
    if (-not $Force -and -not $newPhase -and $p.Watch.Elapsed.TotalSeconds - $p.LastRender -lt 0.25) { return }
    $p.LastRender = $p.Watch.Elapsed.TotalSeconds
    $estimate = Get-ProgressEstimate $p.Done $p.Total $now $p.Rate $p.Unknown
    if ($script:ProgressSink) {
        & $script:ProgressSink ([pscustomobject]@{
            Task = $p.Name; Phase = $p.Phase; Done = $p.Done; Total = $p.Total; Unit = $p.Unit
            Percent = $estimate.Percent; SecondsRemaining = $estimate.SecondsRemaining
            Current = $p.Current; Detail = $p.Detail; Elapsed = $p.Watch.Elapsed.TotalSeconds
        })
    }
    $eta = if ($estimate.SecondsRemaining -ge 0) { '~' + (Format-ProgressTime $estimate.SecondsRemaining) } elseif ($p.Unknown) { 'Unknown' } else { 'Calculating...' }
    $count = if ($p.Total -gt 0) { "$($p.Done) / $($p.Total) $($p.Unit)" } else { "$($p.Done) $($p.Unit)" }
    if ($p.Unit -eq 'bytes') { $count = '{0:N1} / {1:N1} MB' -f ($p.Done/1MB),($p.Total/1MB) }
    $speed = if ($p.Rate -gt 0 -and -not $p.Unknown) {
        if ($p.Unit -eq 'bytes') { '{0:N1} MB/s' -f ($p.Rate/1MB) } else { '{0:N1} {1}/s' -f $p.Rate,$p.Unit }
    } else { 'measuring' }
    $status = "$count | elapsed $(Format-ProgressTime $p.Watch.Elapsed.TotalSeconds) | stage ETA $eta | $speed"
    if ($p.Detail) { $status += " | $($p.Detail)" }
    $root = $p
    # Full workflow owns the stage tracker; individual operations supply the measurable bar.
    if ($script:RomWorkflow -and $script:RomWorkflow -ne $p) { $root = $script:RomWorkflow }
    $tracker = if ($root.Stages.Count) {
        'Step {0}/{1}: {2}' -f ($root.StageIndex+1),$root.Stages.Count,(@(for ($i=0;$i -lt $root.Stages.Count;$i++) { "$($root.Stages[$i]) [$($root.StageStates[$i])]" }) -join ' | ')
    } else { $p.Name }
    if ($p.Live) {
        Write-Progress -Id 70 -Activity $root.Name -Status "$tracker | elapsed $(Format-ProgressTime $root.Watch.Elapsed.TotalSeconds)" -PercentComplete -1
        Write-Progress -Id 71 -ParentId 70 -Activity $p.Phase -Status $status -CurrentOperation $(if ($p.Current) { $p.Current } else { $p.Phase }) -PercentComplete $estimate.Percent -SecondsRemaining $estimate.SecondsRemaining
    } elseif ($Force -or $newPhase -or $p.Watch.Elapsed.TotalSeconds - $p.LastText -ge 10) {
        Write-Host "  [$($p.Name) / $($p.Phase)] $(if ($root.Stages.Count) { $tracker + ' | ' })$status$(if ($p.Current) { ' | ' + $p.Current })" -ForegroundColor Cyan
        $p.LastText = $p.Watch.Elapsed.TotalSeconds
    }
}
function Update-FileProgress([string]$Task, [string]$Path, [long]$Done = 0, [long]$Total = -1, [string]$Detail = '') {
    $p = $script:RomProgress
    if (-not $p) { return }
    if (-not $p.File -or $p.File.Path -ne $Path -or $p.File.Task -ne $Task -or $Done -lt $p.File.Done) {
        $p.File = @{ Path = $Path; Task = $Task; Done = 0L; Watch = [Diagnostics.Stopwatch]::StartNew(); Last = -1.0 }
    }
    $f = $p.File; $f.Done = $Done
    if ($p.Watch.Elapsed.TotalSeconds - $p.LastFileRender -lt 0.25) { return }
    $p.LastFileRender = $p.Watch.Elapsed.TotalSeconds
    $f.Last = $f.Watch.Elapsed.TotalSeconds
    $rate = if ($f.Watch.Elapsed.TotalSeconds -gt 0) { $Done / $f.Watch.Elapsed.TotalSeconds } else { 0 }
    $estimate = Get-ProgressEstimate $Done $Total $f.Watch.Elapsed.TotalSeconds $rate ($Total -lt 0)
    $status = if ($Total -ge 0) { '{0:N1} / {1:N1} MB | {2:N1} MB/s' -f ($Done/1MB),($Total/1MB),($rate/1MB) } else { 'Waiting - progress/remaining time unknown' }
    $status += " | elapsed $(Format-ProgressTime $f.Watch.Elapsed.TotalSeconds)"
    if ($Detail) { $status += " | $Detail" }
    if ($p.Phase -eq 'Local checks' -and $p.ContainsKey('TrackedPath') -and $Total -ge 0 -and (Test-SamePath $Path $p.TrackedPath)) {
        $aggregate = [math]::Max([double]$p.Done,($p.ByteBase + [math]::Min([long]$Done,[long]$p.TrackedLength)))
        Update-RomProgress -Done $aggregate -Unit bytes -Current $Path -Detail $p.Detail
    }
    if ($p.Live) { Write-Progress -Id 72 -ParentId 71 -Activity $Task -Status $status -CurrentOperation $Path -PercentComplete $estimate.Percent -SecondsRemaining $estimate.SecondsRemaining }
    else {
        Update-RomProgress -Unit $p.Unit -Current "$Task - $Path" -Detail $status -Indeterminate:($p.Unknown)
    }
}
function Complete-FileProgress {
    if ($script:RomProgress) {
        if ($script:RomProgress.Live) { Write-Progress -Id 72 -Activity 'File operation' -Completed }
        $script:RomProgress.File = $null
    }
}
function Wait-RomProgress([double]$Seconds, [string]$Service) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt $Seconds) {
        Update-FileProgress "$Service rate limit" 'Waiting for next request' -Detail "Retry in $([math]::Ceiling($Seconds - $watch.Elapsed.TotalSeconds)) seconds"
        Start-Sleep -Milliseconds ([int][math]::Min(250,[math]::Max(1,($Seconds-$watch.Elapsed.TotalSeconds)*1000)))
    }
    Complete-FileProgress
}
function Get-RomHashes([string]$Path) {
    Update-FileProgress 'Calculating CRC32 / MD5 / SHA1 / SHA256' $Path 0 ([IO.FileInfo]::new((LongP $Path)).Length)
    $callback = [Action[long,long]]{ param($done,$total) Update-FileProgress 'Calculating CRC32 / MD5 / SHA1 / SHA256' $Path $done $total }
    try { [RomSorter.RomTools]::HashFile($Path,0,$callback) } finally { Complete-FileProgress }
}

# ===================================================================== CONSOLES / EMULATORS
# Key, display name, ByConsole folder, extensions, max size MB, DAT-header regex, frontend (ES-DE/RetroBat/Batocera) folder,
# libretro database DAT names, emulators (first = default), folder-name hint regex, kind (cart/disc)
function New-Console($Key, $Name, $Folder, $Ext, $MaxMB, $Dat, $Short, $Libretro, $Emus, $Hint, $Kind = 'cart') {
    [pscustomobject]@{ Key = $Key; Name = $Name; Folder = $Folder; Ext = @($Ext); MaxMB = $MaxMB; Dat = $Dat; Short = $Short
                       Libretro = @($Libretro); Emus = @($Emus); Hint = $Hint; Kind = $Kind }
}
$NI = 'no-intro/'; $RD = 'redump/'
$script:Consoles = @(
    New-Console 'SNES' 'Super Nintendo / Super Famicom' 'SNES' @('.sfc', '.smc', '.swc', '.fig', '.bs', '.st', '.bsz') 16 'Super Nintendo|Super Famicom|Satellaview|Sufami' 'snes' @("${NI}Nintendo - Super Nintendo Entertainment System", "${NI}Nintendo - Satellaview", "${NI}Nintendo - Sufami Turbo") @('Snes9x', 'bsnes', 'Mesen', 'ares', 'RetroArch') '^(snes|sfc|super ?nintendo|super ?famicom|super nes)$'
    New-Console 'NES' 'Nintendo NES / Famicom' 'NES' @('.nes', '.unf', '.unif') 16 '(?<!Super )Nintendo Entertainment System|(?<!Super )Famicom(?! Disk)' 'nes' @("${NI}Nintendo - Nintendo Entertainment System") @('Mesen', 'FCEUX', 'Nestopia', 'RetroArch') '^(nes|famicom|fc|nintendo)$'
    New-Console 'FDS' 'Famicom Disk System' 'FDS' @('.fds') 4 'Disk System' 'fds' @("${NI}Nintendo - Family Computer Disk System") @('Mesen', 'FCEUX', 'Nestopia', 'RetroArch') '^(fds|famicom ?disk.*)$'
    New-Console 'GB' 'Game Boy' 'GB' @('.gb', '.dmg') 16 'Game Boy(?! Color| Advance)' 'gb' @("${NI}Nintendo - Game Boy") @('mGBA', 'SameBoy', 'Gambatte', 'BGB', 'RetroArch') '^(gb|game ?boy|gameboy)$'
    New-Console 'GBC' 'Game Boy Color' 'GBC' @('.gbc', '.cgb') 16 'Game Boy Color' 'gbc' @("${NI}Nintendo - Game Boy Color") @('mGBA', 'SameBoy', 'Gambatte', 'BGB', 'RetroArch') '^(gbc|game ?boy ?colou?r)$'
    New-Console 'GBA' 'Game Boy Advance' 'GBA' @('.gba', '.agb') 64 'Game Boy Advance' 'gba' @("${NI}Nintendo - Game Boy Advance") @('mGBA', 'NanoBoyAdvance', 'VBA-M', 'RetroArch') '^(gba|game ?boy ?advance)$'
    New-Console 'N64' 'Nintendo 64' 'N64' @('.z64', '.n64', '.v64') 128 'Nintendo 64(?!DD)' 'n64' @("${NI}Nintendo - Nintendo 64") @('Project64', 'simple64', 'RMG', 'ares', 'RetroArch') '^(n64|nintendo ?64)$'
    New-Console 'NDS' 'Nintendo DS' 'NDS' @('.nds', '.dsi', '.srl') 1024 'Nintendo DS(?!i)' 'nds' @("${NI}Nintendo - Nintendo DS") @('melonDS', 'DeSmuME', 'RetroArch') '^(nds|ds|nintendo ?ds)$'
    New-Console '3DS' 'Nintendo 3DS' '3DS' @('.3ds', '.cci', '.cia', '.cxi', '.3dsx') 8192 'Nintendo 3DS' 'n3ds' @("${NI}Nintendo - Nintendo 3DS") @('Azahar', 'Lime3DS', 'Citra') '^(3ds|n3ds|nintendo ?3ds)$'
    New-Console 'VB' 'Virtual Boy' 'VirtualBoy' @('.vb', '.vboy') 4 'Virtual Boy' 'virtualboy' @("${NI}Nintendo - Virtual Boy") @('Mednafen', 'RetroArch') '^(vb|virtual ?boy)$'
    New-Console 'POKEMINI' 'Pokemon Mini' 'PokemonMini' @('.min') 1 'Pokemon Mini' 'pokemini' @("${NI}Nintendo - Pokemon Mini") @('PokeMini', 'RetroArch') '^(poke ?mon ?mini|pokemini)$'
    New-Console 'MD' 'Mega Drive / Genesis' 'MegaDrive' @('.md', '.gen', '.smd', '.bin', '.sg') 16 'Mega Drive|Genesis' 'megadrive' @("${NI}Sega - Mega Drive - Genesis") @('Kega Fusion', 'BlastEm', 'Genesis Plus GX', 'ares', 'RetroArch') '^(md|megadrive|mega ?drive|genesis|gen)$'
    New-Console '32X' 'Sega 32X' '32X' @('.32x') 8 '32X' 'sega32x' @("${NI}Sega - 32X") @('Kega Fusion', 'ares', 'RetroArch') '^(32x|sega ?32x)$'
    New-Console 'SMS' 'Master System' 'MasterSystem' @('.sms') 8 'Master System|Mark III' 'mastersystem' @("${NI}Sega - Master System - Mark III") @('Kega Fusion', 'Genesis Plus GX', 'ares', 'RetroArch') '^(sms|master ?system|mark ?iii)$'
    New-Console 'GG' 'Game Gear' 'GameGear' @('.gg') 4 'Game Gear' 'gamegear' @("${NI}Sega - Game Gear") @('Kega Fusion', 'Genesis Plus GX', 'ares', 'RetroArch') '^(gg|game ?gear)$'
    New-Console 'SG1000' 'Sega SG-1000' 'SG-1000' @('.sg1', '.sc') 1 'SG-1000' 'sg-1000' @("${NI}Sega - SG-1000") @('Kega Fusion', 'Genesis Plus GX', 'RetroArch') '^(sg-?1000)$'
    New-Console 'PCE' 'PC Engine / TurboGrafx-16' 'PCEngine' @('.pce', '.sgx') 8 'PC Engine(?! CD)|TurboGrafx(?!.*CD)' 'pcengine' @("${NI}NEC - PC Engine - TurboGrafx 16") @('Mednafen', 'ares', 'RetroArch') '^(pce|pc ?engine|turbografx(-?16)?|tg-?16)$'
    New-Console 'A2600' 'Atari 2600' 'Atari2600' @('.a26') 1 '2600' 'atari2600' @("${NI}Atari - 2600") @('Stella', 'RetroArch') '^(a?2600|atari ?2600)$'
    New-Console 'A5200' 'Atari 5200' 'Atari5200' @('.a52', '.car') 1 '5200' 'atari5200' @("${NI}Atari - 5200") @('Altirra', 'RetroArch') '^(a?5200|atari ?5200)$'
    New-Console 'A7800' 'Atari 7800' 'Atari7800' @('.a78') 2 '7800' 'atari7800' @("${NI}Atari - 7800") @('A7800', 'RetroArch') '^(a?7800|atari ?7800)$'
    New-Console 'LYNX' 'Atari Lynx' 'Lynx' @('.lnx', '.lyx') 2 'Lynx' 'atarilynx' @("${NI}Atari - Lynx") @('Mednafen', 'Handy', 'RetroArch') '^(lynx|atari ?lynx)$'
    New-Console 'JAGUAR' 'Atari Jaguar' 'Jaguar' @('.j64', '.jag') 8 'Jaguar' 'atarijaguar' @("${NI}Atari - Jaguar") @('BigPEmu', 'RetroArch') '^(jaguar|atari ?jaguar)$'
    New-Console 'WS' 'WonderSwan' 'WonderSwan' @('.ws') 16 'WonderSwan(?! Color)' 'wonderswan' @("${NI}Bandai - WonderSwan") @('Mednafen', 'ares', 'RetroArch') '^(ws|wonder ?swan)$'
    New-Console 'WSC' 'WonderSwan Color' 'WonderSwanColor' @('.wsc', '.pc2') 16 'WonderSwan Color' 'wonderswancolor' @("${NI}Bandai - WonderSwan Color") @('Mednafen', 'ares', 'RetroArch') '^(wsc|wonder ?swan ?colou?r)$'
    New-Console 'NGP' 'Neo Geo Pocket' 'NeoGeoPocket' @('.ngp') 4 'Neo Geo Pocket(?! Color)' 'ngp' @("${NI}SNK - Neo Geo Pocket") @('Mednafen', 'RetroArch') '^(ngp|neo ?geo ?pocket)$'
    New-Console 'NGPC' 'Neo Geo Pocket Color' 'NeoGeoPocketColor' @('.ngc', '.ngpc') 4 'Neo Geo Pocket Color' 'ngpc' @("${NI}SNK - Neo Geo Pocket Color") @('Mednafen', 'RetroArch') '^(ngpc|neo ?geo ?pocket ?colou?r)$'
    New-Console 'COLECO' 'ColecoVision' 'ColecoVision' @('.col', '.cv') 1 'ColecoVision' 'colecovision' @("${NI}Coleco - ColecoVision") @('ares', 'RetroArch') '^(coleco ?vision|coleco|cv)$'
    New-Console 'INTV' 'Intellivision' 'Intellivision' @('.int', '.itv') 1 'Intellivision' 'intellivision' @("${NI}Mattel - Intellivision") @('jzIntv', 'RetroArch') '^(intv|intellivision)$'
    New-Console 'VECTREX' 'Vectrex' 'Vectrex' @('.vec') 1 'Vectrex' 'vectrex' @("${NI}GCE - Vectrex") @('MAME', 'RetroArch') '^(vectrex)$'
    New-Console 'MSX' 'MSX / MSX2' 'MSX' @('.mx1', '.mx2', '.rom', '.dsk') 4 'MSX' 'msx' @("${NI}Microsoft - MSX", "${NI}Microsoft - MSX2") @('openMSX', 'RetroArch') '^(msx2?|msx ?2)$'
    New-Console 'MAME' 'Arcade - MAME' 'MAME' @() 65536 '\bMAME\b' 'mame' @() @('MAME', 'RetroArch') '^(mame|mame[0-9. -]*)$' 'arcade'
    New-Console 'FBNEO' 'Arcade - FinalBurn Neo' 'FBNeo' @() 4096 'FinalBurn|FBNeo' 'fbneo' @() @('FinalBurn Neo', 'RetroArch') '^(fbneo|fb ?neo|fba|finalburn.*)$' 'arcade'
    New-Console 'NEOGEO' 'SNK Neo Geo AES / MVS' 'NeoGeo' @('.neo') 1024 'Neo Geo(?! Pocket| CD)' 'neogeo' @() @('FinalBurn Neo', 'MAME', 'RetroArch') '^(neogeo|neo ?geo|aes|mvs)$' 'arcade'
    New-Console 'NAOMI' 'Sega Naomi' 'Naomi' @() 65536 'Naomi(?! 2)' 'naomi' @("${RD}Sega - Naomi") @('Flycast', 'RetroArch') '^(naomi|sega ?naomi)$' 'arcade'
    New-Console 'NAOMI2' 'Sega Naomi 2' 'Naomi2' @() 65536 'Naomi 2' 'naomi2' @("${RD}Sega - Naomi 2") @('Flycast', 'RetroArch') '^(naomi ?2|sega ?naomi ?2)$' 'arcade'
    New-Console 'ATOMISWAVE' 'Sammy Atomiswave' 'Atomiswave' @() 4096 'Atomiswave' 'atomiswave' @() @('Flycast', 'RetroArch') '^(atomiswave|sammy ?atomiswave)$' 'arcade'
    New-Console 'ARCADE' 'Arcade - unidentified platform' 'Arcade' @() 65536 'Arcade' 'arcade' @() @('MAME', 'FinalBurn Neo', 'RetroArch') '^(arcade|cps[123]?)$' 'arcade'
    New-Console 'C64' 'Commodore 64 / 128' 'Commodore64' @('.d64', '.d71', '.d81', '.g64', '.x64', '.t64', '.crt', '.prg', '.p00', '.tap', '.nib') 64 'Commodore.*(64|128)' 'c64' @("${NI}Commodore - 64") @('VICE', 'RetroArch') '^(c64|c128|commodore ?(64|128))$' 'computer'
    New-Console 'VIC20' 'Commodore VIC-20' 'VIC20' @('.20', '.40', '.60', '.a0', '.b0', '.prg', '.tap', '.crt') 16 'VIC-20' 'vic20' @("${NI}Commodore - VIC-20") @('VICE', 'RetroArch') '^(vic-?20|commodore ?vic-?20)$' 'computer'
    New-Console 'PLUS4' 'Commodore Plus/4 / C16' 'Plus4' @('.prg', '.tap', '.d64') 16 'Commodore.*(Plus-4|16)' 'plus4' @("${NI}Commodore - Plus-4") @('VICE', 'RetroArch') '^(plus-?4|c16|commodore ?(plus-?4|16))$' 'computer'
    New-Console 'AMIGA' 'Commodore Amiga' 'Amiga' @('.adf', '.adz', '.dms', '.ipf', '.hdf', '.hdz', '.lha', '.fdi') 32768 'Amiga(?! CD)' 'amiga' @("${NI}Commodore - Amiga") @('FS-UAE', 'WinUAE', 'PUAE', 'RetroArch') '^(amiga|commodore ?amiga|amiga ?(500|600|1200|4000))$' 'computer'
    New-Console 'CPC' 'Amstrad CPC' 'AmstradCPC' @('.dsk', '.cdt', '.sna') 32 'Amstrad.*CPC' 'amstradcpc' @('tosec/Amstrad - CPC') @('Caprice32', 'RetroArch') '^(cpc|amstrad ?cpc|amstrad)$' 'computer'
    New-Console 'GX4000' 'Amstrad GX4000' 'GX4000' @('.cpr') 16 'GX4000' 'gx4000' @('tosec/Amstrad - GX4000') @('Caprice32', 'RetroArch') '^(gx4000|amstrad ?gx4000)$'
    New-Console 'ATARI8' 'Atari 8-bit computers' 'Atari8bit' @('.atr', '.atx', '.xfd', '.xex', '.car', '.cas', '.rom') 64 'Atari.*8-bit' 'atari800' @("${NI}Atari - 8-bit Family") @('Altirra', 'Atari800', 'RetroArch') '^(atari ?(8-?bit|800|400|xl|xe)|a800|atari800)$' 'computer'
    New-Console 'ATARIST' 'Atari ST / STE / TT / Falcon' 'AtariST' @('.st', '.msa', '.stx', '.ipf') 32768 'Atari.*ST' 'atarist' @("${NI}Atari - ST") @('Hatari', 'RetroArch') '^(atari ?st|atarist|ste|falcon|hatari)$' 'computer'
    New-Console 'ZX' 'Sinclair ZX Spectrum' 'ZXSpectrum' @('.tzx', '.tap', '.z80', '.sna', '.szx', '.dsk', '.trd', '.scl') 64 'ZX Spectrum' 'zxspectrum' @("${NI}Sinclair - ZX Spectrum +3") @('Fuse', 'RetroArch') '^(zx|spectrum|zx ?spectrum|sinclair ?zx ?spectrum)$' 'computer'
    New-Console 'X68000' 'Sharp X68000' 'X68000' @('.dim', '.hdf', '.xdf', '.hdm', '.dup', '.2hd') 32768 'X68000' 'x68000' @("${NI}Sharp - X68000") @('PX68k', 'RetroArch') '^(x68000|sharp ?x68000|x68k)$' 'computer'
    New-Console 'PC98' 'NEC PC-98' 'PC98' @('.d88', '.d98', '.fdi', '.hdi', '.nhd', '.hdd') 32768 'PC-98' 'pc98' @("${RD}NEC - PC-98") @('Neko Project II', 'RetroArch') '^(pc-?98|nec ?pc-?98)$' 'computer'
    New-Console 'NEOGEOCD' 'SNK Neo Geo CD' 'NeoGeoCD' @() 1024 'Neo Geo CD' 'neogeocd' @("${RD}SNK - Neo Geo CD") @('NeoCD', 'RetroArch') '^(neogeocd|neo ?geo ?cd)$' 'disc'
    New-Console 'CD32' 'Commodore Amiga CD32' 'AmigaCD32' @() 1024 'Commodore.*CD32|Amiga CD32' 'amigacd32' @("${RD}Commodore - CD32") @('FS-UAE', 'PUAE', 'RetroArch') '^(cd32|amiga ?cd32|commodore ?cd32)$' 'disc'
    New-Console 'CDTV' 'Commodore CDTV' 'CDTV' @() 1024 'CDTV' 'amigacdtv' @("${RD}Commodore - CDTV") @('FS-UAE', 'PUAE', 'RetroArch') '^(cdtv|amiga ?cdtv|commodore ?cdtv)$' 'disc'
    New-Console 'SEGACD' 'Sega CD / Mega-CD' 'SegaCD' @() 1024 'Mega-CD|Sega CD' 'segacd' @("${RD}Sega - Mega-CD - Sega CD") @('Kega Fusion', 'Genesis Plus GX', 'ares', 'RetroArch') '^(segacd|sega ?cd|mega-?cd)$' 'disc'
    New-Console 'SATURN' 'Sega Saturn' 'Saturn' @() 1024 'Saturn' 'saturn' @("${RD}Sega - Saturn") @('Mednafen', 'Ymir', 'RetroArch') '^(saturn|sega ?saturn|ss)$' 'disc'
    New-Console 'DC' 'Sega Dreamcast' 'Dreamcast' @('.gdi', '.cdi') 1300 'Dreamcast' 'dreamcast' @("${RD}Sega - Dreamcast") @('Flycast', 'Redream', 'RetroArch') '^(dc|dreamcast|sega ?dreamcast)$' 'disc'
    New-Console 'PCECD' 'PC Engine CD / TurboGrafx-CD' 'PCEngineCD' @() 1024 'PC Engine CD|TurboGrafx-CD' 'pcenginecd' @("${RD}NEC - PC Engine CD - TurboGrafx-CD") @('Mednafen', 'ares', 'RetroArch') '^(pcecd|pc ?engine ?cd|turbografx ?cd|tg-?cd)$' 'disc'
    New-Console 'PS1' 'PlayStation' 'PS1' @() 1024 'Sony - PlayStation$|PlayStation(?! 2| Portable| 3)' 'psx' @("${RD}Sony - PlayStation") @('DuckStation', 'RetroArch') '^(ps1|psx|psone|playstation ?1?)$' 'disc'
    New-Console 'PS2' 'PlayStation 2' 'PS2' @() 9000 'PlayStation 2' 'ps2' @("${RD}Sony - PlayStation 2") @('PCSX2') '^(ps2|playstation ?2)$' 'disc'
    New-Console 'PSP' 'PlayStation Portable' 'PSP' @('.cso', '.zso') 2048 'PlayStation Portable' 'psp' @("${RD}Sony - PlayStation Portable", "${NI}Sony - PlayStation Portable") @('PPSSPP', 'RetroArch') '^(psp|playstation ?portable)$' 'disc'
    New-Console 'GC' 'Nintendo GameCube' 'GameCube' @('.gcm', '.gcz') 1500 'GameCube' 'gc' @("${RD}Nintendo - GameCube") @('Dolphin', 'RetroArch') '^(gc|gcn|ngc|gamecube)$' 'disc'
    New-Console 'WII' 'Nintendo Wii' 'Wii' @('.wbfs', '.wad') 9000 'Wii(?! U)' 'wii' @("${RD}Nintendo - Wii") @('Dolphin') '^(wii)$' 'disc'
    New-Console 'WIIU' 'Nintendo Wii U' 'WiiU' @('.wud', '.wux', '.wua', '.rpx') 26000 'Wii U' 'wiiu' @() @('Cemu') '^(wiiu|wii ?u)$' 'disc'
    New-Console 'SWITCH' 'Nintendo Switch' 'Switch' @('.nsp', '.xci', '.nsz', '.xcz') 33000 'Switch' 'switch' @() @('Ryujinx', 'Eden', 'Citron') '^(switch|nsw|nintendo ?switch)$' 'disc'
    New-Console 'XBOX' 'Microsoft Xbox' 'Xbox' @('.xiso') 9000 'Xbox(?! 360)' 'xbox' @("${RD}Microsoft - Xbox") @('xemu') '^(xbox|og ?xbox)$' 'disc'
    New-Console '3DO' '3DO Interactive Multiplayer' '3DO' @() 1024 '3DO' '3do' @("${RD}The 3DO Company - 3DO") @('RetroArch', 'Opera') '^(3do)$' 'disc'
)
Remove-Variable NI, RD
$script:ConByKey = @{}; foreach ($c in $script:Consoles) { $script:ConByKey[$c.Key] = $c }
function Get-Con([string]$Key) { if ($Key) { $script:ConByKey[$Key] } }

# extension -> list of possible consoles (first = most likely)
$script:ExtMap = @{}
foreach ($c in $script:Consoles) { foreach ($e in $c.Ext) { if (-not $script:ExtMap.ContainsKey($e)) { $script:ExtMap[$e] = New-Object Collections.ArrayList }; [void]$script:ExtMap[$e].Add($c) } }
# generic disc-image / container extensions: the console is found by reading the content (and folder names)
$script:DiscExt = '.iso', '.bin', '.img', '.cue', '.chd', '.ccd', '.mds', '.mdf', '.nrg', '.toc', '.m3u', '.pbp', '.ciso', '.rvz', '.wia', '.ecm', '.cdi', '.gdi'
$script:DiscCons = 'SEGACD', 'SATURN', 'DC', 'PCECD', 'PS1', 'PS2', 'PSP', 'GC', 'WII', 'XBOX', '3DO', 'NEOGEOCD', 'CD32', 'CDTV'
foreach ($e in $script:DiscExt) { if (-not $script:ExtMap.ContainsKey($e)) { $script:ExtMap[$e] = New-Object Collections.ArrayList } }
$script:SetDescExt = '.cue', '.gdi', '.ccd', '.mds', '.m3u', '.toc'
$script:CompressedDiscExt = '.chd', '.rvz', '.wia', '.gcz', '.wbfs', '.cso', '.zso', '.ciso', '.pbp', '.ecm', '.nsz', '.xcz', '.wux', '.cia', '.nsp', '.xci', '.wad', '.wua', '.rpx', '.3dsx'
$script:SharedExt = @('.bin', '.rom', '.dsk', '.sg', '.sc', '.img') + @($script:ExtMap.Keys | Where-Object { $script:ExtMap[$_].Count -gt 1 })

$script:DangerExt  = '.exe', '.com', '.scr', '.pif', '.bat', '.cmd', '.ps1', '.psm1', '.vbs', '.vbe', '.js', '.jse', '.wsf', '.wsh',
                     '.hta', '.msi', '.msp', '.lnk', '.dll', '.cpl', '.jar', '.reg', '.sh', '.apk', '.appx', '.msix', '.iso.exe'
$script:ArchiveExt = '.zip', '.7z', '.rar', '.gz', '.tar'
$script:DisguiseExt = '.zip', '.7z', '.rar', '.txt', '.pdf', '.jpg', '.png', '.mp4', '.iso', '.cue', '.bin', '.img', '.srm', '.sav', '.chd'
# files with the same name as a ROM that should travel with it (saves, patches, cheats, covers, manuals)
$script:CompanionExt = '.srm', '.sav', '.sv', '.state', '.ss0', '.ss1', '.ss2', '.ss3', '.ips', '.bps', '.ups', '.xdelta', '.ppf', '.aps',
                       '.cht', '.txt', '.nfo', '.png', '.jpg', '.jpeg', '.pdf', '.mcr', '.mcd', '.dsv', '.eep', '.fla', '.rtc', '.cfg', '.sbi'
# Loose identifiable BIOS can be organised; installed firmware and keys remain protected.
$script:BiosRx = '^(scph[-_ ]?\d+.*|ps[12]-?\d*.*bios.*|psxonpsp660|ps1_rom|gba_bios|gb_bios|gbc_bios|sgb_bios|sgb2_boot|dmg_boot|cgb_boot|bios[79](\.bin)?|firmware|dsi_(bios|firmware|nand)\w*|dc_(boot|flash|bios)|naomi2?|naomi2?_bios.*|hod2bios|f355dlx|f355bios|airlbios|awbios|segasp|syscard\d.*|disksys|sega_101|mpr-\d+|saturn_bios|sega_?cd.*bios.*|bios_cd_[eju]|us_scd\d.*|eu_mcd\d.*|jp_mcd\d.*|5200|7800 bios.*|lynxboot|neogeo|pgm|panafz\d.*|goldstar|sanyotry|3do_arcade_saot|exec|grom|ivoice|coleco|colecovision|bios\d?|cart|kick\d+.*|aes_bios|keys|prod\.keys|title\.keys|aes_keys|boot9|boot11|nand|secure_info_[ab])$'
# folders that belong to an installed program/emulator or an extracted console game (never pulled apart)
$script:AppMarkers = 'default.xbe', 'PARAM.SFO', 'EBOOT.BIN', 'eboot.bin', 'PS3_GAME', 'PS3_DISC.SFB', 'code', 'content', 'meta', 'sce_sys'
$script:SkipDirRx = '^(\$RECYCLE\.BIN|System Volume Information|_RomSorter|\.git|\.svn|node_modules)$'

$script:CatInfo = [ordered]@{
    'Original'               = @{ Color = 'Green';       Label = 'Original' }
    'Quarantine'             = @{ Color = 'Red';         Label = 'QUARANTINE (possibly malicious)' }
    'Invalid_Corrupt'        = @{ Color = 'DarkRed';     Label = 'Invalid / corrupt / incomplete' }
    'Hacks_Mods'             = @{ Color = 'Magenta';     Label = 'Hacks / mods' }
    'Translations'           = @{ Color = 'Cyan';        Label = 'Fan translations' }
    'Bad_or_Fixed_Dumps'     = @{ Color = 'Yellow';      Label = 'Bad or fixed dumps' }
    'Beta_Proto_Sample'      = @{ Color = 'DarkYellow';  Label = 'Demo / beta / prototype (not a released game)' }
    'PD_Homebrew_Unlicensed' = @{ Color = 'Blue';        Label = 'Homebrew / unlicensed / pirate (not official)' }
    'Other_NonGame'          = @{ Color = 'Gray';        Label = 'Not a game (tools, cheat devices, videos, tests)' }
    'BS_ST'                  = @{ Color = 'DarkCyan';    Label = 'Satellaview / Sufami Turbo' }
    'Checksum_Mismatch'      = @{ Color = 'DarkMagenta'; Label = 'Checksum mismatch (strict)' }
    'Not_In_DAT'             = @{ Color = 'DarkCyan';    Label = 'Unverified - not found in any game library' }
    'Unknown_Check_Manually' = @{ Color = 'DarkGray';    Label = 'Unknown - check manually' }
    'Duplicate'              = @{ Color = 'DarkYellow';  Label = 'Duplicates (identical copy found elsewhere)' }
    'Companion'              = @{ Color = 'DarkGray';    Label = 'Saves / patches / covers (follow their ROM)' }
    'BIOS'                   = @{ Color = 'DarkGray';    Label = 'BIOS / firmware / keys' }
    'Protected'              = @{ Color = 'DarkGray';    Label = 'Inside an emulator/program/game folder (left in place)' }
    'Kept'                   = @{ Color = 'DarkGray';    Label = 'Kept in place by you (manual review)' }
    'Executable'             = @{ Color = 'Red';         Label = 'Programs/scripts (reported, not moved)' }
    'Archive'                = @{ Color = 'DarkGray';    Label = 'Archives (not unpacked, not moved)' }
    'Other_Console'          = @{ Color = 'DarkGray';    Label = 'Other console (filtered out)' }
    'Not_A_ROM'              = @{ Color = 'DarkGray';    Label = 'Other files (ignored)' }
}
$script:StayCats = 'Executable', 'Archive', 'Other_Console', 'Not_A_ROM', 'BIOS', 'Protected', 'Kept'

$script:Advice = @{
    'Quarantine'             = 'Do NOT open or run these. Delete them, or check the VirusTotal link for a second opinion.'
    'Executable'             = 'Programs are never ROMs. Keep only if you installed it yourself (e.g. an emulator); otherwise delete.'
    'Invalid_Corrupt'        = 'Damaged, incomplete or not a ROM for this console. Not dangerous, but will likely not run. Re-download from a trusted source.'
    'Hacks_Mods'             = 'Not malicious - a modified version of a game (graphics/level/cheat hack).'
    'Translations'           = 'Not malicious - an unofficial fan translation patch was applied.'
    'Bad_or_Fixed_Dumps'     = 'Not malicious - the dump has errors or was patched to work around errors. Prefer the [!] / verified version.'
    'Beta_Proto_Sample'      = 'Not malicious - unreleased/pre-release or demo version.'
    'PD_Homebrew_Unlicensed' = 'Not malicious - homebrew, public domain or unlicensed game, not an official release.'
    'Other_NonGame'          = 'Not a game: cheat device or utility ROM.'
    'BS_ST'                  = 'Official Satellaview / Sufami Turbo release (moved because that option is on).'
    'Checksum_Mismatch'      = 'Header looks fine but the data does not match its own checksum: patched, trained or bad dump.'
    'Not_In_DAT'             = 'No game library (No-Intro/Redump, Hasheous) knows this exact file, so it cannot be confirmed as a real released game. Usually a hack, homebrew, bad dump, other revision or wrong format. Re-download a verified copy if you want it in your library.'
    'Unknown_Check_Manually' = 'Could not be confirmed: no status/region tag in the name, no recognisable header and no online match - check by hand.'
    'Duplicate'              = 'Byte-for-byte identical to another file that is kept. Safe to delete once you have checked.'
    'Companion'              = 'Save/patch/cover/manual with the same name as a ROM - moved together with that ROM.'
    'BIOS'                   = 'Identified loose BIOS goes to <console>/BIOS without renaming. This is not firmware installation or authenticity verification. Unknown firmware, keys, packed sets and protected emulator files stay in place; configure your emulator BIOS path if needed.'
    'Protected'              = 'Part of an installed emulator/program or an extracted game folder - moving it would break it.'
    'Archive'                = 'Use "Unpack archives only" or "Full workflow" in the main menu: the archive is checked for malware first and then unpacked. Full workflow also verifies and sorts each ROM. Arcade sets, password-protected and unreadable archives stay as they are.'
}

# ===================================================================== SETTINGS
$configRoot = if ($script:OnWindows) { $env:APPDATA } elseif ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
$script:AppDir = Join-Path $configRoot 'RomSorter'
$script:SettingsPath = Join-Path $script:AppDir 'settings.json'
$script:DatIndex = @{}
$script:DatConsoles = New-Object 'System.Collections.Generic.HashSet[string]'
$script:DatInfo = ''
$script:LastResults = $null

function Get-DefaultSettings {
    $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    [ordered]@{
        RootFolder = $root; Console = 'All'; DatFolder = ''; Layout = 'ByConsole'; SortByCategory = $true; CheckOnly = $true
        DefenderScan = $true; Strict = $false; RequireDatMatch = $true; MoveBSandST = $false
        NonOriginalFolder = 'Non-Original'; QuarantineFolder = '_Quarantine'; DuplicateFolder = '_Duplicates'
        RejectsOutside = $true; RejectFolder = '_Not valid'; UnpackedFolder = '_Unpacked archives'
        Emulators = @{}; ProtectAppFolders = $true; MoveCompanions = $true; KeepGameFolders = $true
        DuplicateMode = 'Move'; CleanEmptyFolders = $true; UseFolderHints = $true; HashLimitMB = 4096
        AutoDat = $true; Hasheous = 'All'; IdentifyUnknown = $true; RetailOnly = $true; OnlineCheck = 'Off'; VtKeyEnc = ''; VtDelay = 15; MbKeyEnc = ''
        SetupDone = $false
        ResumeScans = $true; ArchiveMaxMB = 16384; ArchiveMaxEntries = 10000; ArchiveMaxDepth = 3; ArchiveTimeoutSeconds = 300
    }
}
function ConvertTo-Hashtable($o) {
    $h = @{}; if ($o -is [hashtable]) { foreach ($k in $o.Keys) { $h[$k] = $o[$k] } } elseif ($o) { foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value } }; $h
}
function Read-Settings {
    $s = Get-DefaultSettings
    if (Test-Path -LiteralPath $script:SettingsPath) {
        try {
            $j = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
            foreach ($k in @($s.Keys)) {
                if ($k -ne 'RootFolder' -and $null -ne $j.PSObject.Properties[$k]) { $s[$k] = $j.$k }
            }
        } catch { Write-Host "  Settings file is damaged, using defaults ($($_.Exception.Message))" -ForegroundColor Yellow }
    }
    $s.Emulators = ConvertTo-Hashtable $s.Emulators
    if ($s.Layout -notin 'Emulator', 'Frontend', 'RetroArch', 'ByConsole', 'Validity', 'Classic') { $s.Layout = 'ByConsole' }
    $s
}
function Save-Settings {
    try {
        if (-not (Test-Path -LiteralPath $script:AppDir)) { New-Item -ItemType Directory -Path $script:AppDir | Out-Null }
        $copy = [ordered]@{}; foreach ($k in $S.Keys) { if ($k -ne 'RootFolder') { $copy[$k] = $S[$k] } }
        $tmp = "$($script:SettingsPath).tmp"
        $copy | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $script:SettingsPath -Force
    } catch { Write-Host "  Could not save settings: $($_.Exception.Message)" -ForegroundColor Yellow }
}
function Get-WorkDir { Join-Path $S.RootFolder '_RomSorter' }
function Get-Emulator($Con) {
    if (-not $Con) { return '' }
    $e = $S.Emulators[$Con.Key]; if ($e) { return $e }
    $Con.Emus[0]
}

# ===================================================================== SMALL HELPERS
function LongP([string]$p) { [RomSorter.RomTools]::LP($p) }
function New-PathMap([switch]$Ordered) {
    if ($Ordered) { return ,([Collections.Specialized.OrderedDictionary]::new($script:PathComparer)) }
    ,([Collections.Hashtable]::new($script:PathComparer))
}
function Get-DirectoryPath([string]$Path) {
    $p = [IO.Path]::GetFullPath([RomSorter.RomTools]::Plain($Path))
    if ($p -eq [IO.Path]::GetPathRoot($p)) { return $p }
    $p.TrimEnd([IO.Path]::DirectorySeparatorChar)
}
function Get-DirectoryPrefix([string]$Path) { (Get-DirectoryPath $Path).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar }
function Test-SamePath([string]$Left, [string]$Right) { [string]::Equals($Left, $Right, $script:PathComparison) }
function Test-ChildPath([string]$Path, [string]$Directory) {
    $prefix = Get-DirectoryPrefix $Directory
    $Path.Length -gt $prefix.Length -and $Path.StartsWith($prefix, $script:PathComparison)
}
function Convert-RelativePath([string]$Path) { $Path.Replace('\', [IO.Path]::DirectorySeparatorChar).Replace('/', [IO.Path]::DirectorySeparatorChar) }
function Open-LocalItem([string]$Path, [switch]$SelectFile) {
    try {
        if ($script:OnWindows -and $SelectFile) { Start-Process explorer.exe "/select,`"$Path`"" }
        elseif ($script:OnWindows) { Start-Process $Path }
        else {
            $opener = Get-Command xdg-open -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $opener) { throw 'xdg-open is unavailable; open the displayed path/URL manually' }
            $target = if ($SelectFile) { Split-Path $Path } else { $Path }
            Start-Process $opener.Source -ArgumentList "`"$target`""
        }
    } catch { Write-Warning "Could not open '$Path': $($_.Exception.Message)" }
}
function Get-Ascii([byte[]]$d, [int]$off, [int]$len) {
    if ($off -lt 0 -or ($off + $len) -gt $d.Length) { return '' }
    [Text.Encoding]::ASCII.GetString($d, $off, $len)
}
function Test-Bytes([byte[]]$d, [int]$off, [byte[]]$p) {
    if (($off + $p.Length) -gt $d.Length) { return $false }
    for ($i = 0; $i -lt $p.Length; $i++) { if ($d[$off + $i] -ne $p[$i]) { return $false } }
    $true
}
function Read-Head([string]$Path, [int]$Count) { , [RomSorter.RomTools]::ReadAt($Path, 0, $Count) }
function Read-At([string]$Path, [long]$Pos, [int]$Count) { , [RomSorter.RomTools]::ReadAt($Path, $Pos, $Count) }
function Test-PathLP([string]$p) { [IO.File]::Exists((LongP $p)) -or [IO.Directory]::Exists((LongP $p)) }
function Add-Note($r, [string]$n) { if ($n) { if ($r.Notes) { $r.Notes = "$($r.Notes); $n" } else { $r.Notes = $n } } }
$script:SecRank = @{ 'Clean' = 0; 'Warning' = 1; 'Executable' = 2; 'Suspicious' = 3; 'Malicious' = 4 }
function Set-Security($r, [string]$Level, [string]$Why) {
    if ($script:SecRank[$Level] -gt $script:SecRank[$r.Security]) { $r.Security = $Level }
    if ($Why) { if ($r.Threats) { $r.Threats = "$($r.Threats) | $Why" } else { $r.Threats = $Why } }
}
function New-Cand($b, [int]$o, [int]$l) { @{ B = $b; O = $o; L = $l } }
function New-HeaderResult { @{ Header = 'Unknown'; Integrity = 'N/A'; Notes = (New-Object Collections.ArrayList); Cands = (New-Object Collections.ArrayList) } }

# ===================================================================== HEADER CHECKS
$GbLogo  = [byte[]](0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D, 0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E)
$GbaLogo = [byte[]](0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21)

function Test-HdrSNES($h, [byte[]]$d, $ext) {
    $len = $d.Length; $off = 0
    if (($len % 1024) -eq 512) { $off = 512; [void]$h.Notes.Add('512-byte copier header') }
    [void]$h.Cands.Add((New-Cand $d $off ($len - $off))); if ($off) { [void]$h.Cands.Add((New-Cand $d 0 $len)) }
    if (($len - $off) -lt 0x8000) { $h.Header = 'Invalid'; [void]$h.Notes.Add('Too small for a SNES ROM'); return }
    $stored = @()
    foreach ($base in 0x7FC0, 0xFFC0, 0x40FFC0) {
        $p = $off + $base
        if (($p + 32) -gt $len) { continue }
        $cmp = $d[$p + 0x1C] + 256 * $d[$p + 0x1D]; $chk = $d[$p + 0x1E] + 256 * $d[$p + 0x1F]
        if (($cmp -bxor $chk) -eq 0xFFFF) { $stored += $chk }
    }
    if ($stored.Count) {
        $h.Header = 'Valid'
        $calc = [RomSorter.RomTools]::SnesChecksum($d, $off, $len - $off)
        if ($stored -contains $calc) { $h.Integrity = 'OK' } else { $h.Integrity = 'Mismatch'; [void]$h.Notes.Add('Internal checksum does not match (modified or bad dump?)') }
    } elseif ($ext -in '.bs', '.bsz', '.st') { $h.Header = 'Unknown' }
    else { $h.Header = 'Invalid'; [void]$h.Notes.Add('No valid SNES internal header') }
}
function Test-HdrNES($h, [byte[]]$d, $ext) {
    $len = $d.Length
    if ($len -ge 16 -and $d[0] -eq 0x4E -and $d[1] -eq 0x45 -and $d[2] -eq 0x53 -and $d[3] -eq 0x1A) {
        $h.Header = 'Valid'
        $trainer = 0; if ($d[6] -band 4) { $trainer = 512 }
        $prg = [int]$d[4]; $chr = [int]$d[5]
        if (($d[7] -band 0x0C) -eq 0x08) {
            $pm = $d[9] -band 0x0F; $cm = ($d[9] -shr 4) -band 0x0F
            if ($pm -eq 0xF -or $cm -eq 0xF) { $prg = -1 } else { $prg += $pm * 256; $chr += $cm * 256 }
        } elseif ((Get-Ascii $d 7 9) -match 'DiskDude|demiforce|NI\d') { [void]$h.Notes.Add('Dirty iNES header') }
        if ($prg -ge 0) {
            $exp = 16 + $trainer + $prg * 16384 + $chr * 8192
            if ($exp -eq $len) { $h.Integrity = 'OK' } else { $h.Integrity = 'Mismatch'; [void]$h.Notes.Add("Size does not match iNES header (expected $exp bytes)") }
        }
        [void]$h.Cands.Add((New-Cand $d 16 ($len - 16)))
        if ($trainer -and $len -gt 528) { [void]$h.Cands.Add((New-Cand $d 528 ($len - 528))) }
        [void]$h.Cands.Add((New-Cand $d 0 $len))
    } elseif ((Get-Ascii $d 0 4) -eq 'UNIF') { $h.Header = 'Valid'; [void]$h.Cands.Add((New-Cand $d 0 $len)) }
    else { $h.Header = 'Invalid'; [void]$h.Notes.Add('No iNES header'); [void]$h.Cands.Add((New-Cand $d 0 $len)) }
}
function Test-HdrFDS($h, [byte[]]$d, $ext) {
    $len = $d.Length; $off = 0
    if ((Get-Ascii $d 0 3) -eq 'FDS' -and $len -gt 16 -and $d[3] -eq 0x1A) { $h.Header = 'Valid'; $off = 16 }
    elseif ($len -gt 16 -and $d[0] -eq 1 -and (Get-Ascii $d 1 14) -eq '*NINTENDO-HVC*') { $h.Header = 'Valid' }
    else { $h.Header = 'Invalid'; [void]$h.Notes.Add('No FDS disk header') }
    if ($h.Header -eq 'Valid') { if ((($len - $off) % 65500) -eq 0) { $h.Integrity = 'OK' } else { $h.Integrity = 'Mismatch'; [void]$h.Notes.Add('Disk size is not a multiple of 65500') } }
    if ($off) { [void]$h.Cands.Add((New-Cand $d $off ($len - $off))) }
    [void]$h.Cands.Add((New-Cand $d 0 $len))
}
function Test-HdrGB($h, [byte[]]$d, $ext) {
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
    if ($d.Length -lt 0x150) { $h.Header = 'Invalid'; [void]$h.Notes.Add('Too small for a Game Boy ROM'); return }
    $logo = Test-Bytes $d 0x104 $GbLogo
    $x = 0; for ($i = 0x134; $i -le 0x14C; $i++) { $x = ($x - $d[$i] - 1) -band 0xFF }
    $hdr = ($x -eq $d[0x14D])
    if ($logo -and $hdr) { $h.Header = 'Valid' } else {
        $h.Header = 'Invalid'
        if (-not $logo) { [void]$h.Notes.Add('Nintendo logo missing/damaged') }
        if (-not $hdr) { [void]$h.Notes.Add('Header checksum wrong') }
    }
    $stored = $d[0x14E] * 256 + $d[0x14F]
    $calc = ([RomSorter.RomTools]::Sum($d, 0, $d.Length) - $d[0x14E] - $d[0x14F]) -band 0xFFFF
    if ($stored -eq $calc) { $h.Integrity = 'OK' } else { $h.Integrity = 'Mismatch'; [void]$h.Notes.Add('Global checksum does not match') }
    if ($ext -eq '.gb' -and $d[0x143] -eq 0xC0) { [void]$h.Notes.Add('Game Boy Color-only game') }
}
function Test-HdrGBA($h, [byte[]]$d, $ext) {
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
    if ($d.Length -lt 0xC0) { $h.Header = 'Invalid'; [void]$h.Notes.Add('Too small for a GBA ROM'); return }
    $c = 0; for ($i = 0xA0; $i -le 0xBC; $i++) { $c = $c - $d[$i] }; $c = ($c - 0x19) -band 0xFF
    $ok = ($d[0xB2] -eq 0x96) -and ($c -eq $d[0xBD]) -and (Test-Bytes $d 4 $GbaLogo)
    if ($ok) { $h.Header = 'Valid' } else { $h.Header = 'Invalid'; [void]$h.Notes.Add('GBA header (logo/complement) invalid') }
}
function Test-HdrN64($h, [byte[]]$d, $ext) {
    $len = $d.Length
    if ($len -lt 0x1000) { $h.Header = 'Invalid'; [void]$h.Notes.Add('Too small for an N64 ROM'); [void]$h.Cands.Add((New-Cand $d 0 $len)); return }
    if (Test-Bytes $d 0 ([byte[]](0x80, 0x37, 0x12, 0x40))) { $h.Header = 'Valid' }
    elseif (Test-Bytes $d 0 ([byte[]](0x37, 0x80, 0x40, 0x12))) { $h.Header = 'Valid'; [void]$h.Notes.Add('Byte-swapped (v64) format') }
    elseif (Test-Bytes $d 0 ([byte[]](0x40, 0x12, 0x37, 0x80))) { $h.Header = 'Valid'; [void]$h.Notes.Add('Little-endian (n64) format') }
    else { $h.Header = 'Invalid'; [void]$h.Notes.Add('Unknown N64 byte order / header') }
    if ($h.Header -eq 'Valid' -and $d[0] -ne 0x80) { $z = [RomSorter.RomTools]::ToZ64($d); [void]$h.Cands.Add((New-Cand $z 0 $len)) }
    [void]$h.Cands.Add((New-Cand $d 0 $len))
}
function Test-HdrNDS($h, [byte[]]$d, $ext) {
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
    if ($d.Length -lt 0x200) { $h.Header = 'Invalid'; [void]$h.Notes.Add('Too small for an NDS ROM'); return }
    $stored = $d[0x15E] + 256 * $d[0x15F]
    if ($stored -eq [RomSorter.RomTools]::Crc16($d, 0, 0x15E)) {
        $h.Header = 'Valid'
        if (($d[0x15C] + 256 * $d[0x15D]) -ne 0xCF56) { [void]$h.Notes.Add('Nintendo logo CRC differs (homebrew?)') }
    } else { $h.Header = 'Invalid'; [void]$h.Notes.Add('NDS header CRC wrong') }
}
function Test-HdrMD($h, [byte[]]$d, $ext) {
    $len = $d.Length; $md = $d
    if ((($len % 16384) -eq 512) -and $len -gt 512 -and $d[8] -eq 0xAA -and $d[9] -eq 0xBB) {
        $md = [RomSorter.RomTools]::SmdToBin($d); [void]$h.Notes.Add('Interleaved SMD format')
    }
    [void]$h.Cands.Add((New-Cand $md 0 $md.Length)); if ($md -ne $d) { [void]$h.Cands.Add((New-Cand $d 0 $len)) }
    if ($md.Length -lt 0x200) { $h.Header = 'Invalid'; [void]$h.Notes.Add('Too small'); return }
    if ((Get-Ascii $md 0x100 4) -eq 'SEGA' -or (Get-Ascii $md 0x101 4) -eq 'SEGA') { $h.Header = 'Valid' }
    else { $h.Header = 'Unknown'; [void]$h.Notes.Add('No SEGA header text') }
    $stored = $md[0x18E] * 256 + $md[0x18F]
    if ([RomSorter.RomTools]::WordSumBE($md, 0x200, $md.Length - 0x200) -eq $stored) { $h.Integrity = 'OK' }
    else { $h.Integrity = 'Mismatch'; [void]$h.Notes.Add('Header checksum does not match') }
}
function Test-HdrSMS($h, [byte[]]$d, $ext) {
    $len = $d.Length; $off = 0
    if (($len % 16384) -eq 512) { $off = 512; [void]$h.Notes.Add('512-byte copier header') }
    [void]$h.Cands.Add((New-Cand $d $off ($len - $off))); if ($off) { [void]$h.Cands.Add((New-Cand $d 0 $len)) }
    foreach ($p in 0x7FF0, 0x3FF0, 0x1FF0) { if ((Get-Ascii $d ($off + $p) 8) -eq 'TMR SEGA') { $h.Header = 'Valid'; return } }
}
function Test-HdrPCE($h, [byte[]]$d, $ext) {
    $len = $d.Length
    if (($len % 8192) -eq 512) { [void]$h.Notes.Add('512-byte copier header'); [void]$h.Cands.Add((New-Cand $d 512 ($len - 512))) }
    [void]$h.Cands.Add((New-Cand $d 0 $len))
}
function Test-HdrA2600($h, [byte[]]$d, $ext) {
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
    if ($d.Length -in 2048, 4096, 6144, 8192, 10240, 12288, 16384, 32768, 65536, 131072, 262144, 524288) { $h.Header = 'Valid' }
    else { [void]$h.Notes.Add('Unusual size for Atari 2600') }
}
function Test-HdrA7800($h, [byte[]]$d, $ext) {
    if ((Get-Ascii $d 1 9) -eq 'ATARI7800' -and $d.Length -gt 128) { $h.Header = 'Valid'; [void]$h.Cands.Add((New-Cand $d 128 ($d.Length - 128))) }
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
}
function Test-HdrLynx($h, [byte[]]$d, $ext) {
    if ((Get-Ascii $d 0 4) -eq 'LYNX' -and $d.Length -gt 64) { $h.Header = 'Valid'; [void]$h.Cands.Add((New-Cand $d 64 ($d.Length - 64))) }
    elseif ($ext -eq '.lnx') { $h.Header = 'Invalid'; [void]$h.Notes.Add('No LYNX header') }
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
}
function Test-HdrNGP($h, [byte[]]$d, $ext) {
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
    if ((Get-Ascii $d 0 28) -match 'COPYRIGHT BY SNK CORPORATION|LICENSED BY SNK CORPORATION') { $h.Header = 'Valid' }
}

function Test-HdrWS($h, [byte[]]$d, $ext) {
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
    if ($d.Length -ge 0x10000 -and $d[$d.Length - 16] -eq 0xEA) {
        $h.Header = 'Valid'
        $stored = [BitConverter]::ToUInt16($d, $d.Length - 2)
        $sum = [RomSorter.RomTools]::Sum($d, 0, $d.Length - 2) -band 0xFFFF
        $h.Integrity = if ($sum -eq $stored) { 'OK' } else { 'Mismatch' }
        if ($h.Integrity -eq 'Mismatch') { [void]$h.Notes.Add(('WonderSwan checksum {0:X4} <> stored {1:X4}' -f $sum, $stored)) }
    } elseif ($d.Length -lt 0x10000) { $h.Header = 'Invalid'; [void]$h.Notes.Add('Too small for a WonderSwan cartridge') }
}
function Test-HdrJaguar($h, [byte[]]$d, $ext) {
    if ($ext -eq '.j64' -and $d.Length -gt 0x2000 -and ($d.Length % 0x100000) -eq 0x2000) { [void]$h.Cands.Add((New-Cand $d 0x2000 ($d.Length - 0x2000))); [void]$h.Notes.Add('8KB header present') }
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
    if ($d.Length -in 1MB, 2MB, 4MB, 6MB, 0x102000, 0x202000, 0x402000, 0x602000) { $h.Header = 'Valid' }
}
function Test-HdrMSX($h, [byte[]]$d, $ext) {
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
    if ($ext -eq '.dsk') { if ($d.Length -in 368640, 737280) { $h.Header = 'Valid' } else { [void]$h.Notes.Add('Unusual size for an MSX disk image') }; return }
    if ((Get-Ascii $d 0 2) -eq 'AB' -or (Get-Ascii $d 0x4000 2) -eq 'AB') { $h.Header = 'Valid' }
}
function Test-HdrColeco($h, [byte[]]$d, $ext) {
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
    if ($d.Length -ge 2 -and (($d[0] -eq 0xAA -and $d[1] -eq 0x55) -or ($d[0] -eq 0x55 -and $d[1] -eq 0xAA))) { $h.Header = 'Valid' }
}
function Test-HdrVectrex($h, [byte[]]$d, $ext) {
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
    if ((Get-Ascii $d 0 5) -eq 'g GCE') { $h.Header = 'Valid' } else { $h.Header = 'Invalid'; [void]$h.Notes.Add("No 'g GCE' Vectrex header") }
}
function Test-Hdr3DS($h, [byte[]]$d, $ext) {
    if ($ext -in '.3ds', '.cci') {
        if ((Get-Ascii $d 0x100 4) -eq 'NCSD') { $h.Header = 'Valid' } else { $h.Header = 'Invalid'; [void]$h.Notes.Add('No NCSD signature (not a 3DS cartridge image, or encrypted/damaged)') }
    } elseif ($ext -eq '.cxi') { if ((Get-Ascii $d 0x100 4) -eq 'NCCH') { $h.Header = 'Valid' } }
    elseif ($ext -eq '.cia') { if ($d.Length -ge 4 -and [RomSorter.RomTools]::LE32($d, 0) -eq 0x2020) { $h.Header = 'Valid' } else { $h.Header = 'Invalid'; [void]$h.Notes.Add('Not a CIA installer file') } }
    elseif ($ext -eq '.3dsx') { if ((Get-Ascii $d 0 4) -eq '3DSX') { $h.Header = 'Valid' } }
    [void]$h.Cands.Add((New-Cand $d 0 $d.Length))
}

function Test-RomHeader($Con, [IO.FileInfo]$File, [byte[]]$d) {
    $h = New-HeaderResult; $ext = $File.Extension.ToLower()
    switch ($Con.Key) {
        'SNES'  { Test-HdrSNES  $h $d $ext }
        'NES'   { Test-HdrNES   $h $d $ext }
        'FDS'   { Test-HdrFDS   $h $d $ext }
        'GB'    { Test-HdrGB    $h $d $ext }
        'GBC'   { Test-HdrGB    $h $d $ext }
        'GBA'   { Test-HdrGBA   $h $d $ext }
        'N64'   { Test-HdrN64   $h $d $ext }
        'NDS'   { Test-HdrNDS   $h $d $ext }
        '3DS'   { Test-Hdr3DS   $h $d $ext }
        'MD'    { Test-HdrMD    $h $d $ext }
        '32X'   { Test-HdrMD    $h $d $ext }
        'SMS'   { Test-HdrSMS   $h $d $ext }
        'GG'    { Test-HdrSMS   $h $d $ext }
        'PCE'   { Test-HdrPCE   $h $d $ext }
        'A2600' { Test-HdrA2600 $h $d $ext }
        'A7800' { Test-HdrA7800 $h $d $ext }
        'LYNX'  { Test-HdrLynx  $h $d $ext }
        'JAGUAR' { Test-HdrJaguar $h $d $ext }
        'NGP'   { Test-HdrNGP   $h $d $ext }
        'NGPC'  { Test-HdrNGP   $h $d $ext }
        'WS'    { Test-HdrWS    $h $d $ext }
        'WSC'   { Test-HdrWS    $h $d $ext }
        'MSX'   { Test-HdrMSX   $h $d $ext }
        'COLECO' { Test-HdrColeco $h $d $ext }
        'VECTREX' { Test-HdrVectrex $h $d $ext }
        default { [void]$h.Cands.Add((New-Cand $d 0 $d.Length)) }
    }
    $h
}

# ===================================================================== CONSOLE DETECTION (content + folder names)
function New-Detect([string]$Key, [string]$Header, [string]$Why) { [pscustomobject]@{ Key = $Key; Header = $Header; Why = $Why; Alt = @() } }
function Get-ComputerSignature([byte[]]$Head) {
    if ((Get-Ascii $Head 0 16) -eq 'C64 CARTRIDGE   ') { return New-Detect 'C64' 'Unknown' 'Commodore 64 cartridge signature (not an authenticity check)' }
    if ((Get-Ascii $Head 0 16) -eq 'VIC20 CARTRIDGE ') { return New-Detect 'VIC20' 'Unknown' 'VIC-20 cartridge signature' }
    if ((Get-Ascii $Head 0 8) -eq 'GCR-1541' -or (Get-Ascii $Head 0 12) -eq 'C64-TAPE-RAW') { return New-Detect 'C64' 'Unknown' 'Commodore disk/tape signature' }
    if ((Get-Ascii $Head 0 8) -eq 'MV - CPC' -or (Get-Ascii $Head 0 8) -eq 'EXTENDED' -and (Get-Ascii $Head 0 34) -match 'CPC DSK File') { return New-Detect 'CPC' 'Unknown' 'Amstrad CPC disk signature' }
    if ((Get-Ascii $Head 0 8) -eq 'MV - SNA') { return New-Detect 'CPC' 'Unknown' 'Amstrad CPC snapshot signature' }
    if ((Get-Ascii $Head 0 4) -eq 'CART') { $x = New-Detect '' 'Unknown' 'Atari cartridge container (8-bit / 5200); a matching folder hint is needed'; $x.Alt = @('ATARI8', 'A5200'); return $x }
    if ((Get-Ascii $Head 0 4) -eq 'AT8X') { return New-Detect 'ATARI8' 'Unknown' 'Atari ATX disk signature' }
    if ((Get-Ascii $Head 0 4) -eq 'CAPS') { $x = New-Detect '' 'Unknown' 'IPF preservation disk image (shared format)'; $x.Alt = @('AMIGA', 'ATARIST'); return $x }
    if ((Get-Ascii $Head 0 4) -eq 'DMS!') { return New-Detect 'AMIGA' 'Unknown' 'Amiga DMS disk signature' }
    if ((Get-Ascii $Head 0 4) -eq 'ZXST') { return New-Detect 'ZX' 'Unknown' 'ZX Spectrum snapshot signature' }
    if ((Get-Ascii $Head 0 7) -eq 'ZXTape!') { $x = New-Detect '' 'Unknown' 'TZX/CDT tape container (shared format)'; $x.Alt = @('ZX', 'CPC'); return $x }
    $null
}

# ISO-9660: find a file in the root directory and return its first bytes
function Read-IsoFile([string]$Path, [int]$SecSize, [int]$DataOff, [byte[]]$Pvd, [string]$Name) {
    try {
        $lba = [BitConverter]::ToUInt32($Pvd, 156 + 2); $len = [BitConverter]::ToUInt32($Pvd, 156 + 10)
        $len = [math]::Min([long]$len, 8192); $dir = New-Object Collections.Generic.List[byte]
        for ($s = 0; $s * 2048 -lt $len; $s++) { $dir.AddRange([byte[]](Read-At $Path ([long]($lba + $s) * $SecSize + $DataOff) 2048)) }
        $b = $dir.ToArray(); $i = 0
        while ($i -lt $b.Length) {
            $rl = $b[$i]; if ($rl -eq 0) { $i = (([math]::Floor($i / 2048)) + 1) * 2048; continue }
            $nl = $b[$i + 32]; $n = Get-Ascii $b ($i + 33) $nl
            if ($n -split ';' | Select-Object -First 1 | Where-Object { $_ -eq $Name }) {
                $flba = [BitConverter]::ToUInt32($b, $i + 2)
                return , (Read-At $Path ([long]$flba * $SecSize + $DataOff) 512)
            }
            $i += $rl
        }
    } catch { }
    $null
}

function Get-ContentConsole([string]$Path, [string]$Ext, [long]$Len) {
    try { $d = Read-Head $Path 0x9A00 } catch { return $null }
    if ($d.Length -lt 16) { return $null }
    $m4 = Get-Ascii $d 0 4
    # containers / compressed formats
    if ((Get-Ascii $d 0 8) -eq 'MComprHD') {
        $tags = @()
        try {
            $ver = [RomSorter.RomTools]::BE32($d, 12)
            if ($ver -ge 5) {
                $mo = [long]0; for ($k = 0; $k -lt 8; $k++) { $mo = ($mo -shl 8) -bor $d[0x30 + $k] }
                $guard = 0
                while ($mo -gt 0 -and $guard++ -lt 64) {
                    $e = Read-At $Path $mo 16; if ($e.Length -lt 16) { break }
                    $tags += Get-Ascii $e 0 4
                    $mo = [long]0; for ($k = 0; $k -lt 8; $k++) { $mo = ($mo -shl 8) -bor $e[8 + $k] }
                }
            }
        } catch { }
        if ($tags -contains 'CHGD') {
            $x = New-Detect '' 'Unknown' 'CHD with GD-ROM track data (Dreamcast / Naomi); a system folder is needed'
            $x.Alt = @('DC', 'NAOMI', 'NAOMI2'); return $x
        }
        $x = New-Detect '' 'Valid' 'Valid CHD (compressed disc) - the console is taken from the folder name'
        $arcadeKeys = @($script:Consoles | Where-Object Kind -eq 'arcade' | ForEach-Object Key)
        $x.Alt = if ($tags -contains 'DVD ') { @('PS2', 'PSP', 'XBOX', 'GC', 'WII') + $arcadeKeys } else { @($script:DiscCons) + $arcadeKeys }
        return $x
    }
    if ($m4 -eq 'WBFS') { return New-Detect 'WII' 'Valid' 'WBFS container = Wii' }
    if ($m4 -in "RVZ$([char]1)", "WIA$([char]1)") {
        $t = [RomSorter.RomTools]::BE32($d, 0x48)
        if ($t -eq 1) { return New-Detect 'GC' 'Valid' "$($m4.Substring(0,3)) image of a GameCube disc" }
        if ($t -eq 2) { return New-Detect 'WII' 'Valid' "$($m4.Substring(0,3)) image of a Wii disc" }
        $x = New-Detect '' 'Valid' 'RVZ/WIA image'; $x.Alt = @('GC', 'WII'); return $x
    }
    if ([RomSorter.RomTools]::LE32($d, 0) -eq 0xB10BC001L) {
        if ([RomSorter.RomTools]::LE32($d, 4) -eq 1) { return New-Detect 'WII' 'Valid' 'GCZ image of a Wii disc' } else { return New-Detect 'GC' 'Valid' 'GCZ image of a GameCube disc' }
    }
    if ($m4 -eq 'CISO') { if ([RomSorter.RomTools]::LE32($d, 4) -eq 0x18) { return New-Detect 'PSP' 'Valid' 'CISO = compressed PSP UMD' } else { return New-Detect 'WII' 'Valid' 'CISO = compact Wii image' } }
    if ($m4 -eq 'ZISO') { return New-Detect 'PSP' 'Valid' 'ZSO = compressed PSP UMD' }
    if ($m4 -eq "$([char]0)PBP") {
        try { $po = [RomSorter.RomTools]::LE32($d, 0x24); $ps = Get-Ascii (Read-At $Path $po 16) 0 10 } catch { $ps = '' }
        if ($ps -match 'PSISOIMG|PSTITLEIM') { return New-Detect 'PS1' 'Valid' 'PBP (EBOOT) containing a PlayStation 1 game' }
        return New-Detect 'PSP' 'Valid' 'PBP (EBOOT) = PSP game'
    }
    if ($m4 -eq 'PFS0') { return New-Detect 'SWITCH' 'Valid' 'PFS0 container (NSP) = Switch' }
    if ((Get-Ascii $d 0x100 4) -eq 'HEAD' -and $Ext -in '.xci', '.xcz') { return New-Detect 'SWITCH' 'Valid' 'XCI cartridge image = Switch' }
    if ((Get-Ascii $d 0x100 4) -eq 'NCSD') { return New-Detect '3DS' 'Valid' 'NCSD cartridge image = 3DS' }
    if ($m4 -eq "ECM$([char]0)") { $x = New-Detect '' 'Valid' 'ECM-compressed disc image'; $x.Alt = @('PS1', 'SATURN', 'SEGACD', 'PCECD', 'DC'); return $x }
    # GameCube / Wii plain images
    if ([RomSorter.RomTools]::BE32($d, 0x1C) -eq 0xC2339F3DL) { return New-Detect 'GC' 'Valid' 'GameCube disc magic found' }
    if ([RomSorter.RomTools]::BE32($d, 0x18) -eq 0x5D1C9EA3) { return New-Detect 'WII' 'Valid' 'Wii disc magic found' }
    # 3DO Opera filesystem
    if ($d[0] -eq 1 -and (Get-Ascii $d 1 5) -eq 'ZZZZZ' -and $d[6] -eq 1) { return New-Detect '3DO' 'Valid' '3DO Opera filesystem' }
    if ((Get-Ascii $d 0x10 5) -eq 'ZZZZZ' -and $d[0x16] -eq 1) { return New-Detect '3DO' 'Valid' '3DO Opera filesystem (raw)' }

    # CD/DVD sectors: raw 2352 (sync pattern) or cooked 2048
    $raw = ($d[0] -eq 0 -and $d[11] -eq 0); for ($k = 1; $k -le 10 -and $raw; $k++) { if ($d[$k] -ne 0xFF) { $raw = $false } }
    $sec = 2048; $off = 0
    if ($raw) { $sec = 2352; $off = if ($d[15] -eq 2) { 24 } else { 16 } }
    $s0 = Get-Ascii $d $off 16
    if ($s0 -like 'SEGADISCSYSTEM*') { return New-Detect 'SEGACD' 'Valid' 'Sega CD boot sector (SEGADISCSYSTEM)' }
    if ($s0 -like 'SEGA SEGASATURN*') { return New-Detect 'SATURN' 'Valid' 'Saturn boot sector (SEGA SEGASATURN)' }
    if ($s0 -like 'SEGA SEGAKATANA*') { return New-Detect 'DC' 'Valid' 'Dreamcast boot sector (SEGA SEGAKATANA)' }
    if ([RomSorter.RomTools]::IndexOf($d, [Text.Encoding]::ASCII.GetBytes('PC Engine CD-ROM SYSTEM')) -ge 0) { return New-Detect 'PCECD' 'Valid' 'PC Engine CD-ROM signature' }
    $pvd = Read-At $Path ([long]16 * $sec + $off) 2048
    if ((Get-Ascii $pvd 1 5) -eq 'CD001') {
        $sys = (Get-Ascii $pvd 8 32).Trim(); $vol = (Get-Ascii $pvd 40 32).Trim()
        if ($sys -like 'PSP GAME*' -or $vol -like 'UMD*') { return New-Detect 'PSP' 'Valid' "ISO-9660 system id '$sys' = PSP UMD" }
        if ($sys -like 'PLAYSTATION*') {
            $cnf = Read-IsoFile $Path $sec $off $pvd 'SYSTEM.CNF'
            if ($cnf) { $t = Get-Ascii $cnf 0 ([math]::Min(200, $cnf.Length)); if ($t -match 'BOOT2') { return New-Detect 'PS2' 'Valid' 'SYSTEM.CNF has BOOT2 = PlayStation 2' } elseif ($t -match 'BOOT') { return New-Detect 'PS1' 'Valid' 'SYSTEM.CNF has BOOT = PlayStation 1' } }
            if ($Len -gt 800MB) { return New-Detect 'PS2' 'Valid' "System id 'PLAYSTATION' on a DVD-size image = PlayStation 2" }
            return New-Detect 'PS1' 'Valid' "System id 'PLAYSTATION' = PlayStation 1"
        }
        if ((Read-IsoFile $Path $sec $off $pvd 'PSP_GAME') -ne $null) { return New-Detect 'PSP' 'Valid' 'PSP_GAME folder found' }
        $x = New-Detect '' 'Valid' "ISO-9660 disc image (system '$sys', volume '$vol')"; $x.Alt = @('PS1', 'PS2', 'PSP', 'SEGACD', 'SATURN', 'PCECD', '3DO'); return $x
    }
    # Xbox XISO (plain or with the video partition in front)
    foreach ($xo in 0x10000, 0x18310000) {
        if ($Len -gt $xo + 20 -and (Get-Ascii (Read-At $Path $xo 20) 0 20) -eq 'MICROSOFT*XBOX*MEDIA') { return New-Detect 'XBOX' 'Valid' 'Xbox XDVDFS signature' }
    }
    $null
}

# nearest parent folder whose name says which console it is (also recognises the folders this script creates)
function Get-FolderHint([IO.FileInfo]$File) {
    if (-not $S.UseFolderHints) { return $null }
    $root = Get-DirectoryPath $S.RootFolder; $dir = $File.Directory
    while ($dir) {
        $n = $dir.Name.ToLower()
        foreach ($c in $script:Consoles) {
            if ($n -eq $c.Key.ToLower() -or $n -eq $c.Folder.ToLower() -or $n -eq $c.Short -or ($c.Libretro | Where-Object { ($_ -split '/')[-1].ToLower() -eq $n }) -or ($c.Hint -and $n -match $c.Hint)) { return $c }
        }
        if (Test-SamePath (Get-DirectoryPath $dir.FullName) $root) { break }
        $dir = $dir.Parent
    }
    $null
}

# returns @{ Con; Header; Why } - Header/Why come from content sniffing when that decided it
function Get-ConsoleForFile([IO.FileInfo]$File) {
    $ext = $File.Extension.ToLower(); $res = [pscustomobject]@{ Con = $null; Header = ''; Why = '' }
    $cands = @(); if ($script:ExtMap.ContainsKey($ext)) { $cands = @($script:ExtMap[$ext]) }
    $isDisc = $script:DiscExt -contains $ext -or $script:CompressedDiscExt -contains $ext
    $shared = $script:SharedExt -contains $ext
    $hint = Get-FolderHint $File
    if ($shared) {
        $computer = Get-ComputerSignature (Read-Head $File.FullName 64)
        if ($computer -and $computer.Key) {
            $res.Con = Get-Con $computer.Key
            $res.Header = $computer.Header; $res.Why = $computer.Why; return $res
        }
        if ($computer -and $computer.Alt.Count) {
            if ($hint -and $computer.Alt -contains $hint.Key) { $res.Con = $hint }
            $res.Header = $computer.Header; $res.Why = $computer.Why; return $res
        }
    }
    if ($cands.Count -eq 1 -and -not $isDisc -and -not $shared) {
        $res.Con = $cands[0]
        if ($res.Con.Kind -eq 'disc' -or $ext -in '.3ds', '.cci') { $det = Get-ContentConsole $File.FullName $ext $File.Length; if ($det -and $det.Key) { $res.Header = $det.Header; $res.Why = $det.Why } }
        return $res
    }
    if ($ext -eq '.gdi') { $res.Con = Get-Con 'DC'; $res.Why = '.gdi = Dreamcast GD-ROM track list'; return $res }
    if ($script:SetDescExt -contains $ext) { $res.Why = 'set descriptor'; $h = Get-FolderHint $File; if ($h) { $res.Con = $h }; return $res }
    $det = $null; if ($File.Length -gt 0) { $det = Get-ContentConsole $File.FullName $ext $File.Length }
    if ($det -and $det.Key) { $res.Con = Get-Con $det.Key; $res.Header = $det.Header; $res.Why = $det.Why; return $res }
    $hint = Get-FolderHint $File
    if ($det -and $det.Alt.Count) {
        if ($hint -and $det.Alt -contains $hint.Key) { $res.Con = $hint; $res.Header = $det.Header; $res.Why = "$($det.Why); console from folder name '$($File.Directory.Name)'" }
        else { $res.Why = "$($det.Why). Could not tell which console - put it in a folder named e.g. 'PS1' or 'Saturn' and scan again" }
        return $res
    }
    if ($ext -eq '.bin' -or $ext -eq '.sg') {
        try { $head = Read-Head $File.FullName 0x200 } catch { return $res }
        if ((Get-Ascii $head 0x100 8) -eq 'SEGA 32X') { $res.Con = Get-Con '32X'; return $res }
        if ((Get-Ascii $head 0x100 4) -eq 'SEGA' -or (Get-Ascii $head 0x101 4) -eq 'SEGA') { $res.Con = Get-Con 'MD'; return $res }
    }
    if ($ext -eq '.rom' -and (Test-Path -LiteralPath $File.FullName)) {
        try { $head = Read-Head $File.FullName 0x4002 } catch { return $res }
        if ((Get-Ascii $head 0 2) -eq 'AB' -or (Get-Ascii $head 0x4000 2) -eq 'AB') { $res.Con = Get-Con 'MSX'; return $res }
    }
    if ($hint -and ($cands -contains $hint -or $isDisc -or $shared)) {
        if ($hint.Kind -eq 'disc' -and -not $isDisc) { return $res }
        if ($hint.Kind -notin 'disc', 'arcade' -and $isDisc -and $ext -notin '.bin', '.img') { return $res }
        $res.Con = $hint; $res.Why = "console from folder name '$($File.Directory.Name)'"; return $res
    }
    if ($cands.Count -eq 1 -and -not $isDisc -and -not $shared) { $res.Con = $cands[0] }
    if ($shared -and -not $res.Con) { $res.Why = "Shared format ${ext}: no reliable signature or matching system folder; left unidentified rather than guessing" }
    $res
}

# ===================================================================== FILENAME TAGS
$RegionRx = '^(?:[UJEGFAKCSIBHDR]{1,4}|Sw|Nl|Unk|UK|USA|Japan|Europe|World|Korea|Germany|France|Spain|Italy|Netherlands|Sweden|Asia|China|Taiwan|Hong Kong|Brazil|Australia|Canada|Russia|Scandinavia|Denmark|Finland|Norway|Portugal|Greece|NTSC|PAL)$'
function Test-Region([string]$Tag) {
    foreach ($part in ($Tag -split ',')) { if ($part.Trim() -cnotmatch $RegionRx) { return $false } }
    $true
}
function New-Tag([string]$Category, [string]$Reason) { [pscustomobject]@{ Category = $Category; Reason = $Reason } }
function Get-TagCategory([string]$Stem, [string]$Ext) {
    $paren = @([regex]::Matches($Stem, '\(([^)]*)\)')  | ForEach-Object { $_.Groups[1].Value })
    $sq    = @([regex]::Matches($Stem, '\[([^\]]*)\]') | ForEach-Object { $_.Groups[1].Value })
    $m = $null
    function First($list, $rx, [switch]$Case) { $list | Where-Object { if ($Case) { $_ -cmatch $rx } else { $_ -match $rx } } | Select-Object -First 1 }

    if ($m = First $paren 'hack')                    { return New-Tag 'Hacks_Mods' "Name tag ($m) = hacked/modified game" }
    if ($m = First $sq '^h' -Case)                   { return New-Tag 'Hacks_Mods' "Name tag [$m] = hack (GoodTools code [h])" }
    if ($m = First $sq '^t\d' -Case)                 { return New-Tag 'Hacks_Mods' "Name tag [$m] = trainer (cheat menu added)" }
    if ($m = First $sq '^p\d' -Case)                 { return New-Tag 'Hacks_Mods' "Name tag [$m] = pirate version" }
    if ($m = First $sq '^c\d' -Case)                 { return New-Tag 'Hacks_Mods' "Name tag [$m] = cracked (copy protection removed)" }
    if ($m = First $sq '^BF' -Case)                  { return New-Tag 'Hacks_Mods' "Name tag [$m] = bung fix (patched for copier)" }
    if ($m = First $sq '^cr( |$)' -Case)             { return New-Tag 'Hacks_Mods' "Name tag [$m] = cracked (TOSEC)" }
    if ($m = First $sq '^t( |\d|$)' -Case)           { return New-Tag 'Hacks_Mods' "Name tag [$m] = trainer (TOSEC)" }
    if ($m = First $sq '^m( |\d|$)' -Case)           { return New-Tag 'Hacks_Mods' "Name tag [$m] = modified (TOSEC)" }
    if ($m = First $sq '^tr( |$)' -Case)             { return New-Tag 'Translations' "Name tag [$m] = fan translation (TOSEC)" }
    if ($m = First $sq '^o(\d|$)' -Case)             { return New-Tag 'Bad_or_Fixed_Dumps' "Name tag [$m] = overdump (TOSEC)" }
    if ($m = First $sq '^T[+-]' -Case)               { return New-Tag 'Translations' "Name tag [$m] = fan translation" }
    if ($m = First $paren 'Translat')                { return New-Tag 'Translations' "Name tag ($m) = fan translation" }
    if ($m = First $sq '^b(\d|$)' -Case)             { return New-Tag 'Bad_or_Fixed_Dumps' "Name tag [$m] = bad dump (known errors in the data)" }
    if ($m = First $sq '^f(\d|$)' -Case)             { return New-Tag 'Bad_or_Fixed_Dumps' "Name tag [$m] = fixed (patched to run on emulators/copiers)" }
    if ($m = First $sq '^x(\d|$)' -Case)             { return New-Tag 'Bad_or_Fixed_Dumps' "Name tag [$m] = bad checksum" }
    if ($m = First $paren '^(NG-Dump Known|Bad Dump)$') { return New-Tag 'Bad_or_Fixed_Dumps' "Name tag ($m) = no good dump exists" }
    if ($m = First $paren '\b(Beta|Proto|Prototype|Pre-Release|Sample|Demo|Kiosk|Shoshinkai|Debug|Promo|Preview|Trial|Taikenban|Location Test|Review Copy)\b') { return New-Tag 'Beta_Proto_Sample' "Name tag ($m) = demo / unreleased version, not the full released game" }
    if ($m = First $paren '^(PD|Public Domain|Unl|Unlicensed|Free Version|Freeware|Shareware|Homebrew|Aftermarket|Pirate|Multicart)$|\b(Homebrew|Aftermarket)\b') { return New-Tag 'PD_Homebrew_Unlicensed' "Name tag ($m) = homebrew / unlicensed / pirate, not an official licensed release" }
    if ($m = First $paren '^(Program|Video|Music|Utility|Application|SDK|Test|Tools?|Diagnostics?)$') { return New-Tag 'Other_NonGame' "Name tag ($m) = program / video / test, not a game" }
    if ($Stem -match '\[BIOS\]|\bBIOS\b|Enhancement Chip|Action Replay|Game Genie|GameShark|Copier|Test Program|Test Cartridge|Game Boy Advance Video|Diagnostic') { return New-Tag 'Other_NonGame' "Name contains '$($Matches[0])' = not a game" }

    if (($Ext -in '.bs', '.bsz') -or ($paren -contains 'BS')) { if ($S.MoveBSandST) { return New-Tag 'BS_ST' 'Satellaview (BS) release' } else { return New-Tag 'Original' 'Official Satellaview (BS) release' } }
    if (($Ext -eq '.st') -or ($paren -contains 'ST'))         { if ($S.MoveBSandST) { return New-Tag 'BS_ST' 'Sufami Turbo (ST) release' } else { return New-Tag 'Original' 'Official Sufami Turbo (ST) release' } }
    if ($paren -contains 'NSS') { return New-Tag 'Original' 'Official Nintendo Super System release' }
    if ($m = $paren | Where-Object { Test-Region $_ } | Select-Object -First 1) { return New-Tag 'Original' "Region tag ($m), no hack/bad-dump tags" }
    $null
}

# ===================================================================== SECURITY
$script:DosStub = [Text.Encoding]::ASCII.GetBytes('This program cannot be run in DOS mode')

function Test-ContentSecurity($r, [byte[]]$d) {
    if ($d.Length -ge 0x40 -and $d[0] -eq 0x4D -and $d[1] -eq 0x5A) {
        $pe = [BitConverter]::ToInt32($d, 0x3C)
        if ($pe -gt 0 -and ($pe + 4) -le $d.Length -and (Get-Ascii $d $pe 4) -eq "PE`0`0") {
            Set-Security $r 'Malicious' 'The file content is a Windows program (starts with the MZ/PE executable signature) but has a ROM extension. Real ROMs never look like this - classic disguised malware.'; return
        }
    }
    if ($d.Length -ge 4 -and $d[0] -eq 0x7F -and (Get-Ascii $d 1 3) -eq 'ELF') {
        Set-Security $r 'Malicious' 'The file content is a Linux/Android program (ELF signature) with a ROM extension. Real ROMs never look like this.'; return
    }
    $magic = Get-Ascii $d 0 4
    if ($d.Length -ge 4 -and $d[0] -eq 0x50 -and $d[1] -eq 0x4B -and $d[2] -eq 3 -and $d[3] -eq 4) { Set-Security $r 'Suspicious' 'This is really a ZIP archive renamed to a ROM extension. Emulators cannot play it like this and it may hide other files. Open it with 7-Zip and inspect the contents.' }
    elseif ($magic -eq 'Rar!') { Set-Security $r 'Suspicious' 'This is really a RAR archive renamed to a ROM extension; it may hide other files. Inspect it with 7-Zip.' }
    elseif ($d.Length -ge 6 -and (Get-Ascii $d 0 2) -eq '7z' -and $d[2] -eq 0xBC -and $d[3] -eq 0xAF) { Set-Security $r 'Suspicious' 'This is really a 7z archive renamed to a ROM extension; it may hide other files. Inspect it with 7-Zip.' }
    elseif ((Get-Ascii $d 0 2) -eq '#!' -or $magic -eq '@ech') { Set-Security $r 'Suspicious' 'The file content is a text script (batch/shell commands), not game data.' }
    $pos = [RomSorter.RomTools]::IndexOf($d, $script:DosStub)
    if ($pos -ge 0) { Set-Security $r 'Suspicious' ('A complete Windows program is hidden inside the ROM data (found "This program cannot be run in DOS mode" at offset 0x{0:X}). Game ROMs have no reason to contain one. Can rarely be a false alarm on DS/GBA ROMs that bundle PC software.' -f $pos) }
}

function Get-SevenZip {
    if ($null -ne $script:SevenZip) { return $script:SevenZip }
    $script:SevenZip = ''
    if ($script:OnWindows) {
        foreach ($p in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) { if ($p -and (Test-Path -LiteralPath $p)) { $script:SevenZip = $p; break } }
    }
    $names = if ($script:OnWindows) { '7z.exe', '7za.exe' } else { '7zz', '7z', '7za' }
    if (-not $script:SevenZip) { $c = Get-Command $names -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { $script:SevenZip = $c.Source } }
    $script:SevenZip
}
# real archive type ('.zip', '.7z', '.rar', '.gz', '.tar') or $null. Files with an unknown/odd extension
# (e.g. 'DRAGO~210.ZI', a DOS 8.3 short name of a .zip) are identified by their first bytes.
function Get-ArchiveType([IO.FileInfo]$File) {
    $ext = $File.Extension.ToLower()
    if ($script:ArchiveExt -contains $ext) { return $ext }
    if ($script:ExtMap.ContainsKey($ext) -or $script:DangerExt -contains $ext -or $File.Length -lt 22) { return $null }
    if (-not $script:ArcTypeCache) { $script:ArcTypeCache = New-PathMap }
    $key = "$($File.FullName)|$($File.Length)|$($File.LastWriteTimeUtc.Ticks)"
    if ($script:ArcTypeCache.ContainsKey($key)) { return $script:ArcTypeCache[$key] }
    $t = $null
    try {
        $h = Read-Head $File.FullName 8
        if ($h.Length -ge 4 -and $h[0] -eq 0x50 -and $h[1] -eq 0x4B -and (($h[2] -eq 3 -and $h[3] -eq 4) -or ($h[2] -eq 5 -and $h[3] -eq 6))) { $t = '.zip' }
        elseif ($h.Length -ge 6 -and $h[0] -eq 0x37 -and $h[1] -eq 0x7A -and $h[2] -eq 0xBC -and $h[3] -eq 0xAF -and $h[4] -eq 0x27 -and $h[5] -eq 0x1C) { $t = '.7z' }
        elseif ($h.Length -ge 4 -and $h[0] -eq 0x52 -and $h[1] -eq 0x61 -and $h[2] -eq 0x72 -and $h[3] -eq 0x21) { $t = '.rar' }
        elseif ($h.Length -ge 3 -and $h[0] -eq 0x1F -and $h[1] -eq 0x8B -and $h[2] -eq 8) { $t = '.gz' }
    } catch { }
    $script:ArcTypeCache[$key] = $t
    $t
}

# list archive entries (name, size, crc) without extracting anything
function Get-ArchiveEntries([IO.FileInfo]$File) {
    Assert-ArchiveSettings
    $listingWatch = [Diagnostics.Stopwatch]::StartNew()
    $list = New-Object Collections.ArrayList; $ext = Get-ArchiveType $File
    if ($ext -eq '.zip') {
        $len = $File.Length; $tailLen = [int][math]::Min($len, 65557); $tail = Read-At $File.FullName ($len - $tailLen) $tailLen
        $eocd = -1; for ($i = $tail.Length - 22; $i -ge 0; $i--) { if ([RomSorter.RomTools]::LE32($tail, $i) -eq 0x06054b50) { $eocd = $i; break } }
        if ($eocd -lt 0) { throw 'not a valid ZIP (end of central directory missing - damaged or incomplete download)' }
        $count = [BitConverter]::ToUInt16($tail, $eocd + 10); $cdSize = [RomSorter.RomTools]::LE32($tail, $eocd + 12); $cdOff = [RomSorter.RomTools]::LE32($tail, $eocd + 16)
        Assert-ArchiveSettings
        if ($count -gt $S.ArchiveMaxEntries) { throw 'Archive resource limit: entry count exceeded' }
        if ($cdOff -eq 0xFFFFFFFFL -or $cdSize -gt 64MB) { throw 'ZIP64 archive - listing not supported' }
        if ($cdOff + $cdSize -gt $len) { throw 'damaged ZIP central directory size' }
        $cd = Read-At $File.FullName $cdOff ([int]$cdSize); $p = 0
        for ($n = 0; $n -lt $count -and $p + 46 -le $cd.Length; $n++) {
            if ($listingWatch.Elapsed.TotalSeconds -ge $S.ArchiveTimeoutSeconds) { throw 'Archive resource limit: listing timeout' }
            if ([RomSorter.RomTools]::LE32($cd, $p) -ne 0x02014b50) { throw 'damaged ZIP central directory' }
            $nl = [BitConverter]::ToUInt16($cd, $p + 28); $xl = [BitConverter]::ToUInt16($cd, $p + 30); $cl = [BitConverter]::ToUInt16($cd, $p + 32)
            if ($p + 46 + $nl + $xl + $cl -gt $cd.Length) { throw 'damaged ZIP central directory entry' }
            $flags = [BitConverter]::ToUInt16($cd, $p + 8)
            $enc = if ($flags -band 0x800) { [Text.Encoding]::UTF8 } else { [Text.Encoding]::GetEncoding(437) }
            $name = $enc.GetString($cd, $p + 46, $nl)
            if (-not $name.EndsWith('/')) {
                $mode = [RomSorter.RomTools]::LE32($cd, $p + 38) -shr 16
                [void]$list.Add([pscustomobject]@{ Name = $name; Size = [long][RomSorter.RomTools]::LE32($cd, $p + 24); Crc = ('{0:X8}' -f [RomSorter.RomTools]::LE32($cd, $p + 16)); Encrypted = [bool]($flags -band 1); Link = (($mode -band 0xF000) -eq 0xA000) })
            }
            $p += 46 + $nl + $xl + $cl
        }
        if ($n -ne $count) { throw 'incomplete ZIP central directory' }
        return , $list
    }
    $7z = Get-SevenZip
    if (-not $7z) { return $null }
    $memory = New-Object IO.MemoryStream
    try {
        [void](Invoke-Bounded7z @('l','-slt','-ba','-p-','--',([RomSorter.RomTools]::Plain($File.FullName))) $memory 16MB ($S.ArchiveTimeoutSeconds * 1000))
        $out = [Text.Encoding]::UTF8.GetString($memory.ToArray()) -split '\r?\n'
    } finally { $memory.Dispose() }
    $cur = @{}; $count = 0
    foreach ($line in @($out) + '') {
        if ($listingWatch.Elapsed.TotalSeconds -ge $S.ArchiveTimeoutSeconds) { throw 'Archive resource limit: listing timeout' }
        if ($line -match '^(\w[\w ]*?) = (.*)$') { $cur[$Matches[1]] = $Matches[2] }
        elseif ($cur.Count) {
            $count++
            if ($count -gt $S.ArchiveMaxEntries) { throw 'Archive resource limit: entry count exceeded' }
            $link = [bool]($cur['Symbolic Link'] -or $cur['Hard Link'] -or $cur['Attributes'] -match '(^| )l')
            if ($cur['Path'] -and ($cur['Folder'] -ne '+' -or $link)) { [void]$list.Add([pscustomobject]@{ Name = $cur['Path']; Size = [long]("0$($cur['Size'])"); Crc = "$($cur['CRC'])".ToUpper(); Encrypted = ($cur['Encrypted'] -eq '+'); Link = $link }) }
            $cur = @{}
        }
    }
    , $list
}

# security + content check of an archive; returns the console when it holds ROMs of one console (emulators load zipped ROMs)
function Test-Archive($r, [IO.FileInfo]$File) {
    try { $entries = Get-ArchiveEntries $File }
    catch {
        if ($_.Exception.Message -notmatch 'Archive resource limit') { $r.Header = 'Invalid' }
        Add-Note $r "Archive contents not verified: $($_.Exception.Message)"; return $null
    }
    if ($null -eq $entries) { Add-Note $r 'Contents not checked (install 7-Zip to let the script look inside .7z/.rar)'; return $null }
    $r.Members = $entries.Count
    if ($entries.Count -eq 0) { $r.Header = 'Invalid'; Add-Note $r 'Archive is empty'; return $null }
    foreach ($e in $entries) {
        if ($e.Link -or $e.Name -match '(^[\\/]|^[A-Za-z]:|(^|[\\/])\.\.([\\/]|$))') {
            Set-Security $r 'Suspicious' "Archive contains an unsafe path or link ('$($e.Name)'); extraction is blocked."
            return $null
        }
        $leaf = ($e.Name -split '[\\/]')[-1]; $ee = [IO.Path]::GetExtension($leaf).ToLower()
        if ($leaf.IndexOf([char]0x202E) -ge 0) { Set-Security $r 'Malicious' "The archive contains '$($e.Name)' whose name uses a hidden right-to-left character to fake its extension - a malware trick."; return $null }
        if ($script:DangerExt -contains $ee) {
            $inner = [IO.Path]::GetExtension([IO.Path]::GetFileNameWithoutExtension($leaf)).ToLower()
            if ($inner -and ($script:ExtMap.ContainsKey($inner) -or $script:DisguiseExt -contains $inner)) { Set-Security $r 'Malicious' "The archive contains '$($e.Name)': a program disguised with a double extension. Almost always malware." }
            else { Set-Security $r 'Suspicious' "The archive contains a program ($($e.Name)). ROM downloads never need a program inside; it may be malware posing as an 'installer' or 'unlocker'." }
            return $null
        }
        if ($e.Encrypted) { Add-Note $r "Password-protected entry '$($e.Name)' (cannot be checked)" }
    }
    # which consoles do the entries belong to?
    $roms = @(); $keys = @{}; $unknown = 0
    $hint = Get-FolderHint $File
    if ($hint -and $hint.Kind -eq 'arcade') {
        $r.ArchiveSet = $true; $r.Header = 'Unknown'
        $r.Detected = "$($hint.Name) container; kept packed. Set completeness and emulator-version compatibility require the matching emulator DAT audit."
        return $hint
    }
    foreach ($e in $entries) {
        $ee = [IO.Path]::GetExtension($e.Name).ToLower()
        if ($script:CompanionExt -contains $ee -or $ee -in '.dat', '.xml', '.htm', '.html', '.url', '.diz') { continue }
        $cs = $null; if ($script:ExtMap.ContainsKey($ee)) { $cs = @($script:ExtMap[$ee]) }
        if ($cs -and $cs.Count -eq 1 -and $script:SharedExt -notcontains $ee) { $keys[$cs[0].Key] = $true; $roms += $e }
        elseif ($hint -and $cs -contains $hint) { $keys[$hint.Key] = $true; $roms += $e }
        else { $unknown++ }
    }
    $hint = Get-FolderHint $File
    if ($keys.Count -eq 1 -and $unknown -eq 0) {
        $con = Get-Con @($keys.Keys)[0]; $r.Header = 'Valid'; $r.Detected = "Archive with $($roms.Count) $($con.Key) ROM(s)"
        if ($roms.Count -gt 1) { $r.ArchiveSet = $true; $r.Header = 'Unknown'; Add-Note $r 'Multi-file container: a match for one member does not verify the entire collection' }
        else { foreach ($e in $roms) { [void]$r.Cands.Add("$($e.Size)|$($e.Crc)") } }
        if ($roms.Count -eq 1) { $r.CRC32 = $roms[0].Crc; $r.InnerName = $roms[0].Name }
        return $con
    }
    if ($hint -and ($keys.Count -eq 0 -or $keys.ContainsKey($hint.Key))) {
        $r.Header = 'Unknown'; $r.ArchiveSet = $true; $r.Detected = "Unverified archive in system folder '$($File.Directory.Name)'"; return $hint
    }
    $chips = @($entries | Where-Object { $_.Name -match '\.(bin|rom|\d[0-9a-z]*|[icmpsv]\d+)$' })
    if (-not $hint -and $entries.Count -ge 2 -and $chips.Count -eq $entries.Count) {
        $r.ArchiveSet = $true; $r.Header = 'Unknown'; $r.Detected = 'Possible arcade chip-dump set; platform unknown, archive kept packed'
        return (Get-Con 'ARCADE')
    }
    $null
}

function Invoke-ProgressProcess([string]$Executable, [string[]]$Arguments, [string]$Label) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable; $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.Arguments = ($Arguments | ForEach-Object { [RomSorter.RomTools]::QuoteArgument($_) }) -join ' '
    $process = New-Object Diagnostics.Process; $process.StartInfo = $start; $started = $false
    try {
        Update-FileProgress $Label 'Waiting for scanner; remaining time unknown'
        $started = $process.Start()
        if (-not $started) { throw "Could not start $Executable" }
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(250)) { Update-FileProgress $Label 'Waiting for scanner; remaining time unknown' }
        [pscustomobject]@{ Code = $process.ExitCode; Output = $stdout.Result + "`n" + $stderr.Result }
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose(); Complete-FileProgress
    }
}
function Invoke-DefenderScan([string]$Path) {
    $exe = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return @{ Available = $false; Hits = @{}; Message = 'Windows Defender not found' } }
    $scan = Invoke-ProgressProcess $exe @('-Scan','-ScanType','3','-File',$Path,'-DisableRemediation') 'Waiting for Windows Defender'
    $out = $scan.Output; $code = $scan.Code
    $hits = @{}; $threat = ''
    foreach ($line in ($out -split "`r?`n")) {
        if ($line -match '^\s*Threat\s*:\s*(.+?)\s*$') { $threat = $Matches[1] }
        elseif ($line -match '^\s*file\s*:\s*(.+?)\s*$') { $hits[($Matches[1] -split '->')[0]] = $threat }
    }
    $msg = switch ($code) { 0 { 'no threats found' } 2 { "$($hits.Count) threat(s) found" } default { "scan failed (exit code $code) - Defender may be disabled by another antivirus" } }
    @{ Available = ($code -in 0, 2); Hits = $hits; Message = $msg }
}
function Invoke-AntivirusScan([string]$Path) {
    if ($script:OnWindows) { return (Invoke-DefenderScan $Path) }
    $exe = Get-Command clamscan -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $hits = New-PathMap
    if (-not $exe) { return @{ Available = $false; Hits = $hits; Message = 'ClamAV unavailable: start with bash ./RomSorter.sh for automatic Ubuntu setup. Antivirus protection was NOT performed.' } }
    $scan = Invoke-ProgressProcess $exe.Source @('--recursive','--infected','--no-summary','--alert-exceeds-max=yes','--follow-dir-symlinks=0','--follow-file-symlinks=0','--',$Path) 'Waiting for ClamAV'
    $out = @($scan.Output -split '\r?\n'); $code = $scan.Code
    $limited = @()
    foreach ($line in $out) {
        if ($line -match '^(.*): (.+) FOUND$') {
            if ($Matches[2] -match '^Heuristics\.Limits\.Exceeded') { $limited += $line }
            else { $hits[$Matches[1]] = $Matches[2] }
        }
    }
    $msg = switch ($code) {
        0 { 'no threats found' }
        1 { "$($hits.Count) threat(s) found" }
        default { "scan failed (exit code $code): $($out -join '; '). Check ClamAV installation and signature databases. Protection is incomplete." }
    }
    if ($limited.Count) { $msg += "; incomplete scan: ClamAV inspection limits exceeded ($($limited -join '; '))" }
    @{ Available = (($code -in 0, 1) -and -not $limited.Count); Hits = $hits; Message = $msg }
}

# ===================================================================== DAT FILES (No-Intro / Redump / libretro)
function Import-DatFolder([string[]]$Folders) { Invoke-ProgressTask 'Loading DATs' { Import-DatFolderCore $Folders } }
function Import-DatFolderCore([string[]]$Folders) {
    $script:DatIndex = @{}; $script:DatConsoles.Clear(); $script:DatInfo = ''
    $files = @(foreach ($Folder in $Folders) { if ($Folder -and (Test-Path -LiteralPath $Folder)) { Get-ChildItem -LiteralPath $Folder -File -Recurse | Where-Object { $_.Extension -in '.dat', '.xml' } } })
    if (-not $files.Count) { return }
    $names = @()
    foreach ($f in $files) {
        Update-RomProgress -Phase 'Loading DAT files' -Current $f.Name -Indeterminate
        $sys = ''; $game = ''; $n = 0; $records = New-Object Collections.ArrayList
        try {
            $first = (Get-Content -LiteralPath $f.FullName -TotalCount 5) -join ' '
            if ($first.TrimStart().StartsWith('<')) {
                $xs = New-Object Xml.XmlReaderSettings; $xs.DtdProcessing = 'Ignore'; $xs.XmlResolver = $null
                $rd = [Xml.XmlReader]::Create($f.FullName, $xs)
                try {
                    $inHeader = $false
                    while ($rd.Read()) {
                        if ($rd.NodeType -eq 'Element') {
                            switch ($rd.Name) {
                                'header' { $inHeader = $true }
                                'name'   { if ($inHeader -and -not $sys) { $sys = $rd.ReadElementContentAsString() } }
                                { $_ -in 'game', 'machine' } { $game = $rd.GetAttribute('name') }
                                'rom' {
                                    $sz = $rd.GetAttribute('size'); $crc = [string]$rd.GetAttribute('crc')
                                    if ($sz -and ($crc -or $rd.GetAttribute('sha1') -or $rd.GetAttribute('sha256') -or $rd.GetAttribute('md5'))) {
                                        [void]$records.Add([pscustomobject]@{ Size = $sz; CRC = $crc.ToUpperInvariant(); Name = $game
                                            SHA1 = $rd.GetAttribute('sha1'); SHA256 = $rd.GetAttribute('sha256'); MD5 = $rd.GetAttribute('md5') })
                                        $n++
                                    }
                                }
                            }
                        } elseif ($rd.NodeType -eq 'EndElement' -and $rd.Name -eq 'header') { $inHeader = $false }
                    }
                } finally { $rd.Dispose() }
            } else {
                $inHeader = $false
                foreach ($line in [IO.File]::ReadLines($f.FullName)) {
                    if ($line -match '^\s*clrmamepro\s*\(') { $inHeader = $true; continue }
                    if ($line -match '^\s*(game|machine|resource)\s*\(') { $inHeader = $false; $game = ''; continue }
                    if ($line -match '^\s*name\s+(?:"([^"]+)"|([^\s()]+))') {
                        $value = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
                        if ($inHeader) { if (-not $sys) { $sys = $value } } elseif (-not $game) { $game = $value }
                        continue
                    }
                    if ($line -match '^\s*\)\s*$') { $inHeader = $false; continue }
                    if ($line -match '^\s*rom\s*\(.*\bsize\s+(\d+)') {
                        $sz = $Matches[1]; $crc = ''; $hashes = @{}
                        if ($line -match '\bcrc\s+"?([a-fA-F0-9]{8})\b') { $crc = $Matches[1].ToUpperInvariant() }
                        foreach ($algorithm in 'sha1', 'sha256', 'md5') {
                            if ($line -match "\b$algorithm\s+`"?([a-fA-F0-9]+)") { $hashes[$algorithm] = $Matches[1] }
                        }
                        if ($crc -or $hashes.Count) {
                            [void]$records.Add([pscustomobject]@{ Size = $sz; CRC = $crc; Name = $game; SHA1 = $hashes.sha1; SHA256 = $hashes.sha256; MD5 = $hashes.md5 }); $n++
                        }
                    }
                }
            }
        } catch { Write-Host "  Could not read $($f.Name): $($_.Exception.Message)" -ForegroundColor Red; continue }
        if (-not $sys) { $sys = $f.BaseName }
        $scopes = @($script:Consoles | Where-Object { $_.Key -eq $sys -or $_.Name -eq $sys -or ($_.Libretro | Where-Object { ($_ -split '/')[-1] -eq $sys -or ($_ -split '/')[-1] -eq $f.BaseName }) })
        if ($scopes.Count -eq 0) { $scopes = @($script:Consoles | Where-Object { $sys -match $_.Dat }) }
        if ($scopes.Count -ne 1) { Write-Warning "DAT '$($f.Name)' has no unambiguous system scope ('$sys'); entries were not imported."; continue }
        $scope = $scopes[0].Key
        [void]$script:DatConsoles.Add($scope)
        foreach ($record in $records) {
            $invalid = @()
            foreach ($spec in @(@('CRC',8),@('MD5',32),@('SHA1',40),@('SHA256',64))) {
                if ($record.($spec[0]) -and $record.($spec[0]) -notmatch ("^[a-fA-F0-9]{" + $spec[1] + "}$")) { $invalid += $spec[0] }
            }
            $length = 0L
            if (-not [long]::TryParse([string]$record.Size,[ref]$length) -or $length -lt 0 -or $invalid.Count) { Write-Warning "Invalid DAT size/hash in '$($f.Name)' for '$($record.Name)'; entry skipped."; continue }
            $record.Size = [string]$length
            $key = "$scope|$($record.Size)|$($record.CRC)"
            if (-not $script:DatIndex.ContainsKey($key)) { $script:DatIndex[$key] = New-Object Collections.ArrayList }
            [void]$script:DatIndex[$key].Add($record)
        }
        $names += "$sys ($n)"
    }
    Complete-FileProgress
    $script:DatInfo = "$($files.Count) DAT file(s), $($script:DatIndex.Count) ROM entries"
    if ($script:DatConsoles.Count) { $script:DatInfo += " - covers: $(@($script:DatConsoles) -join ', ')" }
    Set-ProgressCounter 'DAT files' $files.Count; Set-ProgressCounter 'Indexed entries' $script:DatIndex.Count
}
function Get-DatCacheDir { Join-Path $script:AppDir 'dats' }
function Get-DatFolders { @($S.DatFolder, $(if ($S.AutoDat) { Get-DatCacheDir })) | Where-Object { $_ } }

# download the libretro-database No-Intro / Redump DATs for the consoles that were found (refreshed every 30 days)
function Update-LibretroDats([string[]]$Keys, [switch]$Force) { Invoke-ProgressTask 'Updating DAT sources' { Update-LibretroDatsCore $Keys -Force:$Force } }
function Update-LibretroDatsCore([string[]]$Keys, [switch]$Force) {
    $dir = Get-DatCacheDir; $got = 0; $failed = @()
    Update-RomProgress -Phase 'Refreshing DAT downloads' -Indeterminate
    foreach ($k in $Keys) {
        $c = Get-Con $k; if (-not $c) { continue }
        foreach ($lr in $c.Libretro) {
            $src, $name = $lr -split '/', 2
            $dest = Join-Path (Join-Path $dir $src) "$name.dat"
            if (-not $Force -and (Test-Path -LiteralPath $dest) -and ((Get-Date) - (Get-Item -LiteralPath $dest).LastWriteTime).TotalDays -lt 30) { continue }
            $url = 'https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/' + $src + '/' + [Uri]::EscapeDataString($name) + '.dat'
            Write-Host "  Downloading DAT: $name ($src)" -ForegroundColor DarkCyan
            try {
                if (-not (Test-Path -LiteralPath (Split-Path $dest))) { New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null }
                $tmp = "$dest.part"
                Update-FileProgress 'Downloading DAT (network wait; timeout 120s)' $name
                Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 120 -Headers @{ 'User-Agent' = 'RomSorter-PowerShell' }
                Complete-FileProgress
                if ((Get-Item -LiteralPath $tmp).Length -lt 100) { throw 'empty download' }
                Move-Item -LiteralPath $tmp -Destination $dest -Force; $got++
            } catch {
                $failed += $name; Remove-Item -LiteralPath "$dest.part" -ErrorAction SilentlyContinue
                $msg = if (Test-Path -LiteralPath $dest) { 'keeping the older copy' } else { 'this console will not be DAT-verified' }
                Write-Host "    failed ($($_.Exception.Message)) - $msg" -ForegroundColor Yellow
            } finally { Complete-FileProgress }
        }
    }
    Set-ProgressCounter 'Downloaded' $got; Set-ProgressCounter 'Warnings' $failed.Count
    @{ Downloaded = $got; Failed = $failed }
}

# libretro release info: release year + publisher per checksum (proof that a game was really released)
function Get-MetaCacheDir { Join-Path $script:AppDir 'meta' }
function Update-LibretroMeta([string[]]$Keys, [switch]$Force) { Invoke-ProgressTask 'Updating release metadata' { Update-LibretroMetaCore $Keys -Force:$Force } }
function Update-LibretroMetaCore([string[]]$Keys, [switch]$Force) {
    $dir = Get-MetaCacheDir; $got = 0; $warned = $false
    Update-RomProgress -Phase 'Refreshing release-info downloads' -Indeterminate
    foreach ($k in $Keys) {
        $c = Get-Con $k; if (-not $c) { continue }
        foreach ($lr in $c.Libretro) {
            $name = ($lr -split '/', 2)[1]
            foreach ($type in 'releaseyear', 'publisher') {
                $dest = Join-Path (Join-Path $dir $type) "$name.dat"; $none = "$dest.none"
                $fresh = $false
                foreach ($x in $dest, $none) { if ((Test-Path -LiteralPath $x) -and ((Get-Date) - (Get-Item -LiteralPath $x).LastWriteTime).TotalDays -lt 30) { $fresh = $true } }
                if ($fresh -and -not $Force) { continue }
                $url = 'https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/' + $type + '/' + [Uri]::EscapeDataString($name) + '.dat'
                try {
                    if (-not (Test-Path -LiteralPath (Split-Path $dest))) { New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null }
                    Update-FileProgress 'Downloading release metadata (network wait; timeout 120s)' "$name / $type"
                    Invoke-WebRequest -Uri $url -OutFile "$dest.part" -UseBasicParsing -TimeoutSec 120 -Headers @{ 'User-Agent' = 'RomSorter-PowerShell' }
                    Complete-FileProgress
                    if ((Get-Item -LiteralPath "$dest.part").Length -lt 100) { throw 'empty download' }
                    Move-Item -LiteralPath "$dest.part" -Destination $dest -Force; $got++
                    Remove-Item -LiteralPath $none -ErrorAction SilentlyContinue
                } catch {
                    Remove-Item -LiteralPath "$dest.part" -ErrorAction SilentlyContinue
                    if ((Get-HttpStatus $_) -eq 404) { [IO.File]::WriteAllText($none, '') }
                    elseif (-not $warned) { $warned = $true; Write-Host "    Release info download failed ($($_.Exception.Message))" -ForegroundColor Yellow }
                } finally { Complete-FileProgress }
            }
        }
    }
    Set-ProgressCounter 'Downloaded' $got; Set-ProgressCounter 'Warnings' ([int]$warned)
    if ($got) { Write-Host "  Downloaded $got release-info list(s) (libretro)" -ForegroundColor DarkCyan }
}
function Import-LibretroMeta {
    $script:MetaIndex = @{}
    $dir = Get-MetaCacheDir; if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object Extension -eq '.dat')) {
        $field = if ($f.Directory.Name -eq 'publisher') { 'Publisher' } else { 'Year' }
        $val = ''
        try {
            foreach ($line in [IO.File]::ReadLines($f.FullName)) {
                if ($line -match '^\s*game\s*\(') { $val = ''; continue }
                if ($line -match '^\s*(releaseyear|publisher)\s+"(.*)"') { $val = $Matches[2]; continue }
                if ($val -and $line -match '\bcrc\s+([0-9A-Fa-f]{8})') {
                    $key = $Matches[1].ToUpper()
                    if (-not $script:MetaIndex.ContainsKey($key)) { $script:MetaIndex[$key] = @{ Year = ''; Publisher = '' } }
                    if (-not $script:MetaIndex[$key][$field]) { $script:MetaIndex[$key][$field] = $val }
                }
            }
        } catch { }
    }
}
function Resolve-ReleaseInfo($r) {
    if (-not $script:MetaIndex -or -not $script:MetaIndex.Count -or $r.Compressed) { return }
    $keys = @($r.CRC32) + @($r.Cands | ForEach-Object { ($_ -split '\|')[1] })
    foreach ($k in $keys) {
        if ($k -and $script:MetaIndex.ContainsKey($k)) {
            $m = $script:MetaIndex[$k]
            if (-not $r.Year) { $r.Year = $m.Year }; if (-not $r.Publisher) { $r.Publisher = $m.Publisher }
            Add-Source $r 'libretro release info'; return
        }
    }
}
function Get-ReleaseText($r) {
    $t = ''
    if ($r.Year -or $r.Publisher) { $t += '; released' + $(if ($r.Year) { " $($r.Year)" }) + $(if ($r.Publisher) { " by $($r.Publisher)" }) }
    if ($r.Libraries) { $t += "; also listed on $($r.Libraries)" }
    $t
}

# ===================================================================== ANALYSIS
function New-Result([IO.FileInfo]$File) {
    $full = [RomSorter.RomTools]::Plain($File.FullName)
    [pscustomobject]@{
        FileName = $File.Name; Folder = (Split-Path $full); Console = '-'; ConsoleFolder = ''; Emulator = ''; SizeKB = [math]::Round($File.Length / 1KB, 1)
        Header = '-'; Integrity = '-'; CRC32 = ''; DatMatch = ''; HashMatch = ''; HashSource = ''; Security = 'Clean'; Category = 'Not_A_ROM'
        Reason = ''; Threats = ''; Notes = ''; Online = ''; Sources = ''; Year = ''; Publisher = ''; Libraries = ''; HhDemo = ''; Detected = ''; Set = ''; MD5 = ''; SHA1 = ''; SHA256 = ''
        Target = ''; Action = ''; FullName = $full; Length = $File.Length; LastWriteUtc = $File.LastWriteTimeUtc
        Cands = (New-Object Collections.ArrayList); CandidateHashes = @{}; Members = 0; InnerName = ''; Compressed = $false; Protected = ''; SetId = ''; Lead = $null; DupOf = ''; ArcType = ''; ArchiveSet = $false
        DatStrength = ''; Authenticity = 'Unverified'; IntegrityStatus = 'Unknown'; AntivirusStatus = 'Not checked'; MalwareStatus = 'Not checked'
        ScanFingerprint = ''; CheckedUtc = ''; AntivirusCheckedUtc = ''; Resumed = $false
        IdentificationStatus = 'Not needed'; OnlinePlatform = ''; OnlineName = ''; IdentificationReason = ''
    }
}

function Test-Rom($r, [IO.FileInfo]$File, $Con) {
    $path = $File.FullName; $len = $File.Length; $small = $len -le 64MB
    try { if ($small) { $d = [IO.File]::ReadAllBytes((LongP $path)) } else { $d = Read-Head $path 0x40000 } }
    catch { $r.Header = 'Invalid'; Add-Note $r "Cannot read file: $($_.Exception.Message)"; return }
    if ($d.Length -eq 0) { $r.Header = 'Invalid'; Add-Note $r 'Empty file (0 bytes) - incomplete download or copy'; return }

    Test-ContentSecurity $r $d
    if ($r.Security -eq 'Malicious') { return }
    $ext = $File.Extension.ToLower()
    if ($ext -in '.cue', '.gdi', '.ccd', '.toc', '.m3u', '.mds') { if (-not $r.Header -or $r.Header -eq '-') { $r.Header = 'Unknown' }; return }

    if ($Con.Kind -eq 'disc' -or $script:CompressedDiscExt -contains $ext) {
        if ($r.Header -eq '-' -or -not $r.Header) { $r.Header = 'Unknown' }
        $r.Compressed = $script:CompressedDiscExt -contains $ext
        if ($Con.Kind -ne 'disc') { $h = Test-RomHeader $Con $File $d; if ($h.Header -ne 'Unknown') { $r.Header = $h.Header }; foreach ($n in $h.Notes) { Add-Note $r $n } }
        if ($r.Compressed) { Add-Note $r "Compressed format ($ext): checksums cannot be compared with Redump/No-Intro lists" }
        if ($ext -in '.iso', '.bin', '.img' -and $Con.Kind -eq 'disc' -and ($len % 2048) -ne 0 -and ($len % 2352) -ne 0) { $r.Header = 'Invalid'; Add-Note $r 'Size is not a whole number of CD/DVD sectors - incomplete or damaged image' }
    } else {
        $h = Test-RomHeader $Con $File $d
        if ($r.Header -eq '-' -or -not $r.Header -or $h.Header -ne 'Unknown') { $r.Header = $h.Header }
        $r.Integrity = $h.Integrity
        foreach ($n in $h.Notes) { Add-Note $r $n }
        if ($small) {
            foreach ($c in $h.Cands) {
                $hashes = [RomSorter.RomTools]::HashBytes($c.B, $c.O, $c.L)
                $key = "$($c.L)|$($hashes[0])"
                [void]$r.Cands.Add($key); $r.CandidateHashes[$key] = $hashes
            }
        }
    }
    if ($len -gt ([long]$Con.MaxMB * 1MB)) { $r.Header = 'Invalid'; Add-Note $r "Bigger than any real $($Con.Key) game ($([math]::Round($len/1MB)) MB)" }

    if ($small) { $hs = [RomSorter.RomTools]::HashBytes($d, 0, $d.Length) }
    elseif (($len / 1MB) -le [double]$S.HashLimitMB) {
        try { $hs = Get-RomHashes $path } catch { Add-Note $r "Hashing failed: $($_.Exception.Message)"; return }
    } else { Add-Note $r "Not hashed: bigger than the hash limit ($($S.HashLimitMB) MB, see Options)"; return }
    $r.MD5 = $hs[1]; $r.SHA1 = $hs[2]; $r.SHA256 = $hs[3]
    if (-not $r.Cands.Count) { [void]$r.Cands.Add("$len|$($hs[0])") }
    $r.CandidateHashes["$len|$($hs[0])"] = $hs
    $r.CRC32 = ($r.Cands[0] -split '\|')[1]
}

function Resolve-DatMatch($r) {
    $r.DatMatch = ''; $r.DatStrength = ''
    if (-not $script:DatIndex.Count -or $r.Compressed -or $r.ArchiveSet) { return }
    $matchesFound = @()
    foreach ($k in $r.Cands) {
        $lookup = @("$($r.Console)|$k", "$($r.Console)|$(($k -split '\|')[0])|")
        foreach ($indexKey in $lookup) {
          if (-not $script:DatIndex.ContainsKey($indexKey)) { continue }
          foreach ($entry in $script:DatIndex[$indexKey]) {
            $hashes = $r.CandidateHashes[$k]; $strength = 'CRC32 + size'; $rank = 1; $ok = $true
            foreach ($spec in @(@('MD5',1,2), @('SHA1',2,3), @('SHA256',3,4))) {
                if ($entry.($spec[0])) {
                    if (-not $hashes -or $hashes[$spec[1]] -ine $entry.($spec[0])) { $ok = $false; break }
                    $strength = [string]$spec[0]; $rank = [int]$spec[2]
                }
            }
            if ($ok) { $matchesFound += [pscustomobject]@{ Entry = $entry; Strength = $strength; Rank = $rank; Key = $k } }
          }
        }
    }
    if (-not $matchesFound.Count) { return }
    $best = $matchesFound | Sort-Object Rank -Descending | Select-Object -First 1
    $top = @($matchesFound | Where-Object Rank -eq $best.Rank)
    if (@($top.Entry.Name | Select-Object -Unique).Count -gt 1) { Add-Note $r 'Ambiguous DAT candidates share available hashes; no release was selected'; return }
    $r.DatMatch = $best.Entry.Name; $r.DatStrength = $best.Strength; $r.CRC32 = ($best.Key -split '\|')[1]
}

function Get-Verdict($r, $Con, [string]$Ext) {
    if ($r.Security -in 'Malicious', 'Suspicious') { $r.Reason = $r.Threats; return 'Quarantine' }
    if ($r.Category -in 'BIOS', 'Protected', 'Companion', 'Other_Console', 'Kept') { return $r.Category }
    if ($r.Security -eq 'Executable') { $r.Reason = $r.Threats; return 'Executable' }
    if (-not $Con) {
        if ($script:ArchiveExt -contains $Ext -or $r.ArcType) { $r.Reason = 'Archive - contents are mixed or unknown, so it is left in place' + $(if ($r.Notes) { " ($($r.Notes))" }); return 'Archive' }
        if ($script:DiscExt -contains $Ext -or $script:CompressedDiscExt -contains $Ext) { $r.Reason = if ($r.Detected) { $r.Detected } else { 'Disc image of an unknown console - put it in a folder named after the console (e.g. PS1, Saturn) and scan again' }; return 'Unknown_Check_Manually' }
        if ($script:ExtMap.ContainsKey($Ext)) { $r.Reason = "Recognised/shared image format $Ext, but its system could not be identified reliably. Use a matching system folder and check again."; return 'Unknown_Check_Manually' }
        $r.Reason = 'Not a ROM file type'; return 'Not_A_ROM'
    }
    if ($r.ArchiveSet -or $Con.Kind -eq 'arcade') {
        $r.Reason = "$($Con.Name) set/container: preserved intact, not verified as a complete working game. Audit arcade sets against the exact MAME/FBNeo/Flycast version and its parent/BIOS/CHD requirements."
        if ($Con.Kind -ne 'arcade') { $r.Reason = 'Multi-file archive: the complete contents have not been verified. Unpack and check its images separately when appropriate.' }
        return 'Unknown_Check_Manually'
    }
    $match = $r.DatMatch; $src = 'the No-Intro/Redump DAT'
    if (-not $match -and $r.HashMatch) { $match = $r.HashMatch; $src = 'the Hasheous online database' }
    if ($match) {
        if ($r.HashSource -eq 'HackHash' -and -not $r.DatMatch) { $r.Reason = "Hasheous identifies this exact file as a known hack: '$match'"; return 'Hacks_Mods' }
        $t = Get-TagCategory $match ''
        if ($t -and $t.Category -ne 'Original') { $r.Reason = "Checksum matches '$match' in ${src}: $($t.Reason)"; return $t.Category }
        if ($r.HhDemo) { $r.Reason = "Checksum matches '$match', but the Hasheous library marks it as a demo ($($r.HhDemo)) - not the full released game"; return 'Beta_Proto_Sample' }
        $evidence = if ($r.DatMatch) { $r.DatStrength } else { 'online hash match' }
        $r.Reason = "VERIFIED released game: $evidence matches '$match' in $src$(Get-ReleaseText $r)"; return 'Original'
    }
    if ($r.Header -eq 'Invalid') {
        $why = if ($r.Notes) { $r.Notes } else { 'header check failed' }
        $r.Reason = "Not a valid $($Con.Name) file: $why"; return 'Invalid_Corrupt'
    }
    $stem = [IO.Path]::GetFileNameWithoutExtension($r.FileName)
    $t = Get-TagCategory $stem $Ext
    if ($t -and $t.Category -ne 'Original') { $r.Reason = $t.Reason; return $t.Category }
    if (-not $r.Compressed -and (($S.RequireDatMatch -and $r.CRC32 -and $script:DatConsoles.Contains($Con.Key)) -or $S.RetailOnly)) {
        $checked = @(); if ($script:DatConsoles.Contains($Con.Key)) { $checked += "No-Intro/Redump list for $($Con.Key)" }; if ($r.Online -match 'Hasheous') { $checked += 'Hasheous (No-Intro, Redump, TOSEC, MAME)' }
        $r.Reason = if (-not $r.CRC32 -and -not $r.MD5) { 'Too big to hash (see Options), so no game library could confirm it is a real released game' }
            elseif ($checked.Count) { "Not found in any game library ($($checked -join ', ')): this exact file is not a known released game" }
            else { "Could not be checked against a game library (online verification off, offline, or no list for $($Con.Key)), so it cannot be confirmed as a real released game" }
        return 'Not_In_DAT'
    }
    if (-not $t -and $r.Header -ne 'Valid') { $r.Reason = "No region/status tag in the name and no recognisable $($Con.Key) header to confirm it"; return 'Unknown_Check_Manually' }
    if ($S.Strict -and $r.Integrity -eq 'Mismatch') { $r.Reason = 'The internal checksum stored in the ROM does not match its data: it was patched/trained or is a bad dump'; return 'Checksum_Mismatch' }
    $why = if ($t) { $t.Reason } else { 'No tags, but valid header/signature' }
    if ($r.Detected) { $why += "; $($r.Detected)" }
    elseif ($r.Header -eq 'Valid') { $why += '; valid header' }
    if ($r.Integrity -eq 'OK') { $why += '; internal checksum OK' }
    elseif ($r.Integrity -eq 'Mismatch') { $why += '; WARNING: internal checksum mismatch (may be modified - enable Strict to move these)' }
    if ($r.Compressed) { $why += '; compressed image (not verifiable against DAT)' }
    $r.Reason = $why
    'Original'
}

function Get-BiosIdentity([IO.FileInfo]$File, [string]$ConsoleKey = '', [string]$ReferenceName = '') {
    $stem = [IO.Path]::GetFileNameWithoutExtension($(if ($ReferenceName) { $ReferenceName } else { $File.Name }))
    $ext = $File.Extension.ToLowerInvariant()
    if ($script:DangerExt -contains $ext) { return $null }
    $keyFile = $ext -eq '.keys' -or $stem -match '^(keys|prod\.keys|title\.keys|aes_keys|aeskeydb|secure_info_[ab])$'
    $rules = @(
        @('PS1','^(scph[-_ ]?(100[0-2]|550[0-2]|700[0-3]|750[0-3]|900[0-3])|psxonpsp660|ps1_rom|ps1[_ -]?bios)$'),
        @('PS2','^(scph[-_ ]?\d{5}(?:[_ -]bios.*)?|ps2[_ -]?bios|ps2[-_ ]?\d+.*bios.*)$'),
        @('GBA','^gba[_ -]?bios$'),
        @('GBC','^(gbc[_ -]?bios|cgb_boot|cgb0_boot)$'),
        @('GB','^(gb[_ -]?bios|dmg_boot|dmg0_boot|sgb_bios|sgb2_boot)$'),
        @('NDS','^(bios7i?|bios9i?|dsi_bios7|dsi_bios9|dsi_firmware|ds[_ -]?firmware|nds[_ -]?bios)$'),
        @('3DS','^(boot9|boot11|3ds[_ -]?firmware|3ds[_ -]?bios)$'),
        @('DC','^dc_(boot|flash|bios)$'),
        @('SATURN','^(sega_101|mpr-17933|saturn[_ -]?bios|bios_saturn)$'),
        @('SEGACD','^(bios_cd_[eju]|us_scd\d.*|eu_mcd\d.*|jp_mcd\d.*|sega[_ -]?cd.*bios.*)$'),
        @('FDS','^disksys$'),
        @('PCECD','^syscard\d.*$'),
        @('A5200','^(5200|5200 bios.*)$'),
        @('A7800','^7800 bios.*$'),
        @('LYNX','^lynxboot$'),
        @('AMIGA','^(kick\d+.*|kickstart(?:[ _.-].*)?)$'),
        @('COLECO','^coleco(?:vision)?(?:[_ -]?bios)?$'),
        @('INTV','^(exec|grom|ivoice)$'),
        @('3DO','^(panafz\d.*|goldstar|sanyotry|3do_arcade_saot)$'),
        @('NEOGEO','^(neogeo|aes_bios)$'),
        @('NAOMI','^(naomi|naomi_bios.*|hod2bios|f355dlx|f355bios|airlbios)$'),
        @('NAOMI2','^(naomi2|naomi2_bios.*)$'),
        @('ATOMISWAVE','^awbios$')
    )
    $key = $ConsoleKey
    if (-not $key) { foreach ($rule in $rules) { if ($stem -match $rule[1]) { $key = $rule[0]; break } } }
    $named = $key -or $keyFile -or $stem -match $script:BiosRx -or $stem -match '\[BIOS\]|\(BIOS\)|(^|[ _.-])(bios|firmware|bootrom)([ _.-]|$)'
    $inBiosFolder = $File.DirectoryName -match '(^|[\\/])(bios|firmware)([\\/]|$)'
    if (-not $named -and -not $inBiosFolder) { return $null }
    $hint = Get-FolderHint $File
    if (-not $key -and $hint) { $key = $hint.Key }
    if (-not $key -and $named) {
        $nameMatches = @($script:Consoles | Where-Object { $stem -match $_.Dat })
        if ($nameMatches.Count -eq 1) { $key = $nameMatches[0].Key }
    }
    $con = Get-Con $key
    $loose = $ext -in '.bin','.rom','.bios','.img','.fd','.nds','.dsi','.dat','.jpn','.usa','.eur','.enc','.pce','.col','.int','.a52','.a78','.lnx','.gba','.gb','.gbc',''
    $movable = $con -and $con.Kind -ne 'arcade' -and $loose -and -not $keyFile -and $File.Length -gt 0
    $why = if ($keyFile) { 'Key/security material is kept in place.' } elseif (-not $con) { 'Console is ambiguous; kept in place rather than guessed.' } elseif (-not $loose -or $con.Kind -eq 'arcade') { 'Packed sets or dependent firmware remain in place.' } elseif (-not $File.Length) { 'Empty firmware file is kept for manual review.' } else { "Identified by filename/folder context; organise into $($con.Folder)/BIOS (not proof of authenticity)." }
    [pscustomobject]@{ Console = $key; Movable = [bool]$movable; Why = $why }
}
function Set-BiosIdentity($r, $Identity) {
    $r.Category = 'BIOS'; $r.Reason = "BIOS/firmware: $($Identity.Why)"
    if ($r.PSObject.Properties['SortOnly'] -and $r.SortOnly) { $r.Reason += ' Sort-only: no content, hash or malware checks performed.' }
    $r | Add-Member NoteProperty BiosMovable $Identity.Movable -Force
    $con = Get-Con $Identity.Console
    if ($con) {
        $r.Console = $con.Key; $r.ConsoleFolder = $con.Folder; $r.Emulator = Get-Emulator $con
        $r.Detected = 'BIOS filename/folder context (unverified)'
        if ($S.Console -ne 'All' -and $S.Console -ne $con.Key) { $r.Category = 'Other_Console'; $r.BiosMovable = $false }
    }
}
function Invoke-FileAnalysis([IO.FileInfo]$File, $DefHits) {
    $r = New-Result $File
    $ext = $File.Extension.ToLower(); $stem = [IO.Path]::GetFileNameWithoutExtension($File.Name)

    if ($File.Name.IndexOf([char]0x202E) -ge 0) { Set-Security $r 'Malicious' 'The file name contains an invisible right-to-left character, which makes the real extension look like something else (e.g. "Game[RLO]cfs.exe" shows as "Gameexe.sfc"). This is a well-known malware trick.' }
    if ($script:DangerExt -contains $ext) {
        $inner = [IO.Path]::GetExtension($stem).ToLower()
        if ($inner -and ($script:ExtMap.ContainsKey($inner) -or $script:DisguiseExt -contains $inner)) {
            Set-Security $r 'Malicious' "Double extension: the name ends in '$inner$ext'. Windows hides the last extension by default, so this program shows up as a '$inner' file. A program pretending to be a ROM is almost always malware."
        } else { Set-Security $r 'Executable' "This is a $ext program/script, not a ROM. It is reported but not moved." }
    }
    if ($DefHits -and $DefHits.ContainsKey($r.FullName)) { Set-Security $r 'Malicious' "$script:AntivirusName detected it as '$($DefHits[$r.FullName])'." }
    if ($File.Length -eq 0 -and $script:DangerExt -notcontains $ext) { $r.Header = 'Invalid'; Add-Note $r 'Empty file (0 bytes)' }

    $bios = Get-BiosIdentity $File
    if ($bios) {
        Set-BiosIdentity $r $bios
        try {
            if (Get-ArchiveType $File) { [void](Test-Archive $r $File) }
            elseif ($File.Length -gt 0) { Test-ContentSecurity $r (Read-Head $File.FullName ([int][math]::Min($File.Length,64MB))) }
        }
        catch { Set-Security $r 'Warning' "BIOS content check failed: $($_.Exception.Message); left in place." }
        return $r
    }
    $con = $null
    $arc = Get-ArchiveType $File
    if ($arc) {
        $r.ArcType = $arc
        if ($script:ArchiveExt -notcontains $ext) { Add-Note $r "Really a $($arc.TrimStart('.').ToUpper()) archive with the wrong extension '$($File.Extension)' (often a cut-off DOS short name like 'NAME~123.ZI'); Unpack handles it" }
    }
    if ($script:DangerExt -notcontains $ext -and $File.Length -gt 0) {
        if ($arc) {
            $con = Test-Archive $r $File
            if ($r.Security -in 'Clean', 'Warning') {
                try { $hs = if ($File.Length -le 64MB) { [RomSorter.RomTools]::HashBytes([IO.File]::ReadAllBytes((LongP $File.FullName)), 0, [int]$File.Length) } elseif (($File.Length / 1MB) -le $S.HashLimitMB) { Get-RomHashes $File.FullName } } catch { $hs = $null }
                if ($hs) { $r.MD5 = $hs[1]; $r.SHA1 = $hs[2]; $r.SHA256 = $hs[3]; if (-not $r.CRC32) { $r.CRC32 = $hs[0] } }
            }
        } else {
            $det = Get-ConsoleForFile $File; $con = $det.Con
            if ($det.Header) { $r.Header = $det.Header }
            if ($det.Why -and $det.Why -ne 'set descriptor') { $r.Detected = $det.Why }
        }
    }
    if ($con) {
        $r.Console = $con.Key; $r.ConsoleFolder = $con.Folder; $r.Emulator = Get-Emulator $con
        if ($S.Console -ne 'All' -and $con.Key -ne $S.Console) { $r.Category = 'Other_Console'; $r.Reason = "Skipped: console filter is set to $($S.Console)" }
        elseif (-not $arc) { Test-Rom $r $File $con }
    } elseif ($script:DangerExt -notcontains $ext -and $File.Length -gt 0 -and ($script:DiscExt -contains $ext -or $script:CompressedDiscExt -contains $ext) -and $script:SetDescExt -notcontains $ext) {
        try { $d = Read-Head $File.FullName 0x40000; Test-ContentSecurity $r $d } catch { }
    }
    if ($script:CompanionExt -contains $ext -and -not $con -and $r.Security -in 'Clean', 'Warning') { $r.Category = 'Not_A_ROM' }
    $r
}

# ===================================================================== ONLINE CHECKS (Hasheous, VirusTotal, MalwareBazaar)
# Only fingerprints (MD5 / SHA-256) are sent - never the files themselves.
$script:OnlineCachePath = Join-Path $script:AppDir 'online-cache.json'
$script:OldVtCachePath = Join-Path $script:AppDir 'virustotal-cache.json'
$script:OnlineCache = $null
$script:UA = @{ 'User-Agent' = 'RomSorter-PowerShell/3 (+local ROM organiser)' }

function Unprotect-Key([string]$Enc) {
    if (-not $Enc) { return $null }
    try {
        $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR((ConvertTo-SecureString $Enc))
        try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
    } catch { $null }
}
function Protect-Key([string]$Plain) { if ($Plain) { ConvertTo-SecureString $Plain -AsPlainText -Force | ConvertFrom-SecureString } else { '' } }
function Get-VtKey { if ($script:OnWindows) { Unprotect-Key $S.VtKeyEnc } else { $env:ROMSORTER_VIRUSTOTAL_KEY } }
function Set-VtKey([string]$Plain) {
    if ($script:OnWindows) { $S.VtKeyEnc = Protect-Key $Plain }
    else { $env:ROMSORTER_VIRUSTOTAL_KEY = $Plain; $S.VtKeyEnc = '' }
}
function Get-MbKey { if ($script:OnWindows) { Unprotect-Key $S.MbKeyEnc } else { $env:ROMSORTER_MALWAREBAZAAR_KEY } }
function Set-MbKey([string]$Plain) {
    if ($script:OnWindows) { $S.MbKeyEnc = Protect-Key $Plain }
    else { $env:ROMSORTER_MALWAREBAZAAR_KEY = $Plain; $S.MbKeyEnc = '' }
}

function Get-OnlineCache {
    if ($null -eq $script:OnlineCache) {
        $script:OnlineCache = @{}
        foreach ($f in @(@{ P = $script:OldVtCachePath; Pre = 'vt:' }, @{ P = $script:OnlineCachePath; Pre = '' })) {
            if (Test-Path -LiteralPath $f.P) {
                try { (Get-Content -LiteralPath $f.P -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:OnlineCache["$($f.Pre)$($_.Name)"] = $_.Value } }
                catch { Write-Warning "Cannot read online cache '$($f.P)': $($_.Exception.Message); lookups will be refreshed." }
            }
        }
    }
    $script:OnlineCache
}
function Save-OnlineCache {
    if ($null -eq $script:OnlineCache) { return }
    $tmp = "$($script:OnlineCachePath).$([guid]::NewGuid().ToString('N')).tmp"
    try {
        if (-not (Test-Path -LiteralPath $script:AppDir)) { New-Item -ItemType Directory -Path $script:AppDir | Out-Null }
        $script:OnlineCache | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $tmp -Encoding UTF8
        if ([IO.File]::Exists($script:OnlineCachePath)) { [IO.File]::Replace($tmp,$script:OnlineCachePath,[NullString]::Value) }
        else { [IO.File]::Move($tmp,$script:OnlineCachePath) }
        if (Test-Path -LiteralPath $script:OldVtCachePath) { Remove-Item -LiteralPath $script:OldVtCachePath -ErrorAction SilentlyContinue }
    } catch {
        if (-not $script:OnlineCacheSaveWarning) {
            $message = "Cannot save online lookup progress: $($_.Exception.Message). Lookups can continue, but may be repeated next time."
            Write-Warning $message
            if ($null -ne $script:ServiceIssues) { [void]$script:ServiceIssues.Add($message) }
            $script:OnlineCacheSaveWarning = $true
        }
    }
    finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp } }
}
function Get-Cached([string]$Key, [int]$Days = 30) {
    $c = (Get-OnlineCache)[$Key]
    if ($c -and $c.Date -and ((Get-Date) - [datetime]$c.Date).TotalDays -lt $Days) { return $c }
    $null
}
function Get-HttpStatus($Err) { $code = 0; try { $code = [int]$Err.Exception.Response.StatusCode } catch { }; $code }
function Enable-Tls { try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { } }
function Add-Online($r, [string]$Text) { if ($Text) { if ($r.Online) { $r.Online = "$($r.Online); $Text" } else { $r.Online = $Text } } }
function Add-Source($r, [string]$Text) { if ($Text -and ($r.Sources -split ', ') -notcontains $Text) { if ($r.Sources) { $r.Sources = "$($r.Sources), $Text" } else { $r.Sources = $Text } } }
function Get-VtLink([string]$Sha) { if ($Sha) { "https://www.virustotal.com/gui/file/$Sha" } else { '' } }
function Get-Sha256([string]$Path) {
    Update-FileProgress 'Verifying SHA256' $Path 0 ([IO.FileInfo]::new((LongP $Path)).Length)
    $callback = [Action[long,long]]{ param($done,$total) Update-FileProgress 'Verifying SHA256' $Path $done $total }
    try { [RomSorter.RomTools]::Sha256File($Path,$callback) }
    finally { Complete-FileProgress }
}

# ---- Hasheous (free, no key): identifies ROMs by hash using No-Intro, Redump, TOSEC, MAME, RetroAchievements, ...
function Invoke-HasheousLookup([string]$Md5) {
    Enable-Tls
    try {
        Update-FileProgress 'Waiting for Hasheous (network timeout 30s)' $Md5
        $j = Invoke-RestMethod -Uri "https://hasheous.org/api/v1/Lookup/ByHash/md5/$($Md5.ToLower())" -Headers $script:UA -Method Get -TimeoutSec 30 -UseBasicParsing
        Complete-FileProgress
        $rom = $j.signature.rom; $g = $j.signature.game
        $libs = @(@($j.metadata) | Where-Object { $_ -and $_.status -eq 'Mapped' -and $_.source -in 'IGDB', 'TheGamesDb', 'RetroAchievements', 'LaunchBox', 'MobyGames', 'GiantBomb', 'ScreenScraper', 'Wikipedia' } | ForEach-Object { [string]$_.source }) -join ', '
        $pub = if ($g.publisher) { [string]$g.publisher } else { [string]$j.publisher.name }
        [pscustomobject]@{ Status = 'Found'; Name = [string]$(if ($rom.name) { $rom.name } else { $j.name }); Game = [string]$j.name
            Source = [string]$rom.signatureSource; Platform = [string]$j.platform.name; Demo = [string]$g.demo; Year = [string]$g.year
            Publisher = $pub; Libraries = $libs; Date = (Get-Date).ToString('s')
            MD5 = [string]$rom.md5; SHA1 = [string]$rom.sha1; SHA256 = [string]$rom.sha256; Length = $rom.size
            System = [string]$g.system; GameCategory = [string]$g.category }
    } catch {
        switch (Get-HttpStatus $_) {
            404 { [pscustomobject]@{ Status = 'Unknown'; Date = (Get-Date).ToString('s') } }
            429 { [pscustomobject]@{ Status = 'Quota' } }
            default { [pscustomobject]@{ Status = 'Error'; Message = $_.Exception.Message } }
        }
    } finally { Complete-FileProgress }
}
function ConvertTo-PlatformKey([string]$Name) {
    (($Name.ToLowerInvariant() -replace '^(nintendo|sony|sega|snk|atari|commodore|bandai|nec|microsoft|sinclair|amstrad|sharp|sammy|coleco|mattel|gce)\s*[- ]+','') -replace '[^a-z0-9]','')
}
function Get-OnlineConsole([string]$Platform) {
    if (-not $Platform) { return $null }
    $key = ConvertTo-PlatformKey $Platform
    $aliases = @{ 'supernintendoentertainmentsystem'='SNES'; 'supernes'='SNES'; 'entertainmentsystem'='NES'; 'familycomputer'='NES'; 'familycomputerdisksystem'='FDS'; 'gameboycolour'='GBC'; 'megacd'='SEGACD'; 'playstation1'='PS1'; 'markiii'='SMS'; '8bitfamily'='ATARI8'; 'plus4'='PLUS4' }
    if ($aliases.ContainsKey($key)) { return Get-Con $aliases[$key] }
    $matches = @(
        foreach ($con in $script:Consoles) {
            $names = @($con.Key,$con.Name,$con.Folder,$con.Short) + @($con.Name -split '\s*/\s*') + @($con.Libretro | ForEach-Object { ($_ -split '/',2)[1] })
            if (@($names | Where-Object { $_ -and (ConvertTo-PlatformKey $_) -eq $key }).Count) { $con }
        }
    )
    if ($matches.Count -eq 1) { $matches[0] }
}
function Invoke-UnknownIdentification($Results) {
    $memo = @{}; $cache = Get-OnlineCache; $stop = ''; $script:IdentificationStop = ''
    $candidates = @($Results | Where-Object { $_.Console -eq '-' -or ($_.Category -eq 'BIOS' -and -not $_.SHA256) })
    $i = 0
    foreach ($r in $candidates) {
        $i++
        Update-RomProgress -Phase 'Identifying unknown files online' -Done ($i-1) -Total $candidates.Count -Indeterminate -Current $r.FileName
        $r.IdentificationStatus = 'Unresolved'
        $ext = [IO.Path]::GetExtension($r.FileName).ToLowerInvariant()
        if ($r.Category -in 'Protected','Other_Console','Companion' -or $r.Security -in 'Malicious','Suspicious','Executable' -or
            $script:DangerExt -contains $ext -or $script:CompanionExt -contains $ext -or $ext -eq '.keys' -or
            $r.Reason -match 'Key/security material' -or $r.Compressed -or $r.ArchiveSet -or $r.ArcType -or $script:SetDescExt -contains $ext -or $r.Length -eq 0) {
            $r.IdentificationStatus = 'Skipped'; $r.IdentificationReason = 'Protected, unsafe, auxiliary, empty or packed/dependent data; not submitted online.'
            continue
        }
        if (-not $S.IdentifyUnknown) { $r.IdentificationStatus = 'Disabled'; $r.IdentificationReason = 'Unknown-file online identification is disabled in Settings.'; continue }
        if ($stop -or $script:CancelOnline) {
            $r.IdentificationStatus = 'Deferred'; $r.IdentificationReason = $(if ($stop) { $stop } else { 'Online checks cancelled; retry next run.' }); continue
        }
        if ($r.Length -gt [double]$S.HashLimitMB * 1MB) { $r.IdentificationStatus = 'Hash limit'; $r.IdentificationReason = 'Exceeds configured hash limit; raise it in Settings if appropriate.'; continue }
        try {
            if (-not $r.SHA256 -or -not $r.MD5 -or -not $r.SHA1) {
                $hs = @(Get-RomHashes $r.FullName)
                if ($r.ScanFingerprint -and $hs[3] -ine $r.ScanFingerprint) { throw 'File changed since local checks' }
                $r.CRC32 = $hs[0]; $r.MD5 = $hs[1]; $r.SHA1 = $hs[2]; $r.SHA256 = $hs[3]
            }
            Test-ContentSecurity $r (Read-Head $r.FullName ([int][math]::Min($r.Length,0x40000)))
            if ($r.Security -in 'Malicious','Suspicious','Executable') {
                $r.IdentificationStatus = 'Skipped'; $r.IdentificationReason = 'Executable or suspicious content detected; not submitted online.'; continue
            }
            $key = "identify1:$($r.SHA256)"
            $v = if ($memo.ContainsKey($key)) { $memo[$key] } else { Get-Cached $key }
            if (-not $v) {
                $v = Invoke-HasheousLookup $r.MD5
                $memo[$key] = $v
                Start-Sleep -Milliseconds 400
            }
            Add-Source $r 'Hasheous'
            $r.IdentificationStatus = [string]$v.Status
            if ($v.Status -ne 'Found') {
                $r.IdentificationReason = switch ($v.Status) {
                    'Unknown' { 'No reference hash found; retry on the next check run.' }
                    'Quota' { 'Service rate limit; retry next run.' }
                    default { "Lookup incomplete: $($v.Message); retry next run." }
                }
                if ($v.Status -in 'Quota','Error') { $stop = $r.IdentificationReason; $script:IdentificationStop = $stop; Write-Warning $stop }
                continue
            }
            $r.OnlineName = $v.Name
            $r.OnlinePlatform = if ($v.Platform) { $v.Platform } else { $v.System }
            $con = Get-OnlineConsole $r.OnlinePlatform
            $systemCon = Get-OnlineConsole $v.System
            $mismatch = ($v.SHA256 -and $v.SHA256 -ine $r.SHA256) -or ($v.SHA1 -and $v.SHA1 -ine $r.SHA1) -or ($v.MD5 -and $v.MD5 -ine $r.MD5)
            $strong = ($v.SHA256 -and $v.SHA256 -ieq $r.SHA256) -or ($v.SHA1 -and $v.SHA1 -ieq $r.SHA1)
            if ($mismatch -or -not $strong -or $null -eq $v.Length -or [long]$v.Length -ne $r.Length -or ($con -and $systemCon -and $con.Key -ne $systemCon.Key)) {
                $r.IdentificationStatus = 'Needs review'; $r.IdentificationReason = 'Online clue only: missing strong hash/size evidence or conflicting reference data. Console not changed.'; continue
            }
            $cache[$key] = $v; Save-OnlineCache
            if (-not $con) { $r.IdentificationStatus = 'Unsupported platform'; $r.IdentificationReason = 'Hash identified, but platform has no unambiguous local profile. Add a profile/platform alias and check again.'; continue }
            if ($r.Console -ne '-' -and $r.Console -ne $con.Key) {
                $r.IdentificationStatus = 'Needs review'; $r.IdentificationReason = 'Online platform conflicts with local firmware identification; kept local identity for review.'; continue
            }
            $isBios = $r.Category -eq 'BIOS' -or "$($v.Name) $($v.Game) $($v.GameCategory)" -match '(?i)\b(bios|firmware|bootrom|kickstart)\b'
            if ($isBios) {
                Set-BiosIdentity $r (Get-BiosIdentity ([IO.FileInfo]::new((LongP $r.FullName))) $con.Key $v.Name)
            } else {
                $r.Console = $con.Key; $r.ConsoleFolder = $con.Folder; $r.Emulator = Get-Emulator $con
                Test-Rom $r ([IO.FileInfo]::new((LongP $r.FullName))) $con
                if ($S.Console -ne 'All' -and $S.Console -ne $con.Key) { $r.Category = 'Other_Console'; $r.Reason = "Skipped: console filter is set to $($S.Console)" }
            }
            Set-HasheousResult $r $v
            $r.Detected = 'Online reference hash (SHA256/SHA1); Hasheous platform mapping'
            $r.IdentificationStatus = 'Identified'; $r.IdentificationReason = "Strong hash reference identifies $($con.Name); filenames unchanged. Identification is not malware clearance."
        } catch {
            $r.IdentificationStatus = 'Error'; $r.IdentificationReason = "Identification failed: $($_.Exception.Message); retry next run."
            Write-Warning "$($r.FileName): $($r.IdentificationReason)"
        }
    }
    Set-ProgressCounter 'Previously unknown identified' @($candidates | Where-Object IdentificationStatus -eq 'Identified').Count
}
function Set-HasheousResult($r, $v) {
    Add-Source $r 'Hasheous'
    if ($v.Status -eq 'Found') {
        $r.HashMatch = [IO.Path]::GetFileNameWithoutExtension($v.Name); $r.HashSource = $v.Source
        if ($v.Year -and -not $r.Year) { $r.Year = $v.Year }
        if ($v.Publisher -and -not $r.Publisher) { $r.Publisher = $v.Publisher }
        if ($v.Libraries) { $r.Libraries = $v.Libraries; foreach ($l in ($v.Libraries -split ', ')) { if ($l -ne 'Wikipedia') { Add-Source $r $l } } }
        if ($v.Demo -and $v.Demo -ne 'NotDemo') { $r.HhDemo = $v.Demo }
        Add-Online $r "Hasheous: '$($v.Name)' [$($v.Source)]$(if ($v.Libraries) { " - on $($v.Libraries)" })"
    } elseif ($v.Status -eq 'Unknown') { Add-Online $r 'Hasheous: unknown hash' }
}
function Invoke-HasheousCheck($Results) {
    if ($S.Hasheous -eq 'Off' -and -not $S.IdentifyUnknown) { return }
    $cands = @($Results | Where-Object { $_.MD5 -and $_.Console -ne '-' -and $_.IdentificationStatus -eq 'Not needed' -and $_.Category -notin 'BIOS', 'Protected', 'Other_Console' -and $_.Security -notin 'Malicious', 'Suspicious' -and -not $_.Compressed -and -not $_.ArchiveSet -and ($S.Hasheous -eq 'All' -or -not $_.DatMatch) })
    if (-not $cands.Count) { return }
    $todo = @($cands | Where-Object { (Get-Cached "hh2:$($_.MD5)").Status -ne 'Found' } | Group-Object MD5 | ForEach-Object { $_.Group[0] })
    Write-Host "  Hasheous: $($cands.Count) file(s) to identify online, $($cands.Count - $todo.Count) from cache." -ForegroundColor DarkCyan
    $cache = Get-OnlineCache; $i = 0; $stop = ''
    foreach ($r in $todo) {
        $i++
        if ($script:CancelOnline -or $script:IdentificationStop) { $stop = $(if ($script:IdentificationStop) { $script:IdentificationStop } else { 'cancelled' }); break }
        Update-RomProgress -Phase 'Hasheous identification' -Done ($i-1) -Total $todo.Count -Unit lookups -Current $r.FileName -Indeterminate -Detail "$($cands.Count-$todo.Count) cached | request $i/$($todo.Count) | remote ETA unknown"
        $v = Invoke-HasheousLookup $r.MD5
        if ($v.Status -in 'Found', 'Unknown') { $cache["hh2:$($r.MD5)"] = $v; Save-OnlineCache }
        elseif ($v.Status -eq 'Quota') { $stop = 'Hasheous asked us to slow down - run again later'; break }
        elseif ($i -le 2 -and $v.Status -eq 'Error') { $stop = "Hasheous not reachable ($($v.Message))"; break }
        Start-Sleep -Milliseconds 400
    }
    Complete-FileProgress
    foreach ($r in $cands) {
        $v = Get-Cached "hh2:$($r.MD5)"
        if ($v) { Set-HasheousResult $r $v }
        if (-not $v -or $v.Status -ne 'Found') {
            $r.IdentificationStatus = if ($stop) { 'Deferred' } else { 'Unknown' }
            $r.IdentificationReason = if ($stop) { "$stop; retry next run." } else { 'Console recognized locally, but the reference database does not identify this dump; retry next run.' }
        }
    }
    Save-OnlineCache
    if ($stop) { Write-Host "  Hasheous stopped: $stop." -ForegroundColor Yellow }
    $n = @($cands | Where-Object HashMatch).Count
    Update-RomProgress -Phase 'Hasheous identification' -Done $i -Total $todo.Count -Unit lookups -Detail "$n reference matches; cached results included" -Force
    Write-Host "  Hasheous: $n identified." -ForegroundColor Green
}

# ---- VirusTotal (free key: 4 lookups/minute, 500/day)
function Invoke-VtLookup([string]$Sha, [string]$Key) {
    Enable-Tls
    try {
        Update-FileProgress 'Waiting for VirusTotal (network timeout 30s)' $Sha
        $resp = Invoke-RestMethod -Uri "https://www.virustotal.com/api/v3/files/$Sha" -Headers @{ 'x-apikey' = $Key } -Method Get -TimeoutSec 30 -UseBasicParsing
        Complete-FileProgress
        $a = $resp.data.attributes; $st = $a.last_analysis_stats
        $total = [int]$st.malicious + [int]$st.suspicious + [int]$st.harmless + [int]$st.undetected
        $names = @()
        if ($a.last_analysis_results) {
            $names = @($a.last_analysis_results.PSObject.Properties | Where-Object { $_.Value.category -eq 'malicious' } |
                    Select-Object -First 3 | ForEach-Object { "$($_.Name): $($_.Value.result)" })
        }
        [pscustomobject]@{ Status = 'Found'; Malicious = [int]$st.malicious; Suspicious = [int]$st.suspicious; Total = $total
            Label = [string]$a.popular_threat_classification.suggested_threat_label; Engines = ($names -join ', '); Date = (Get-Date).ToString('s') }
    } catch {
        switch (Get-HttpStatus $_) {
            404 { [pscustomobject]@{ Status = 'Unknown'; Date = (Get-Date).ToString('s') } }
            401 { [pscustomobject]@{ Status = 'BadKey' } }
            403 { [pscustomobject]@{ Status = 'BadKey' } }
            429 { [pscustomobject]@{ Status = 'Quota' } }
            default { [pscustomobject]@{ Status = 'Error'; Message = $_.Exception.Message } }
        }
    }
}
function Set-VtResult($r, $v) {
    Add-Source $r 'VirusTotal'
    switch ($v.Status) {
        'Found' {
            Add-Online $r "VT $($v.Malicious)/$($v.Total)"
            $lbl = if ($v.Label) { " ('$($v.Label)')" } else { '' }
            $eng = if ($v.Engines) { " e.g. $($v.Engines)" } else { '' }
            if ($v.Malicious -ge 3) { Set-Security $r 'Malicious' "VirusTotal: $($v.Malicious) of $($v.Total) antivirus engines detect this file as malicious$lbl.$eng" }
            elseif ($v.Malicious -eq 2 -or ($v.Malicious -eq 1 -and $v.Suspicious -ge 1)) { Set-Security $r 'Suspicious' "VirusTotal: $($v.Malicious) of $($v.Total) engines flag this file$lbl.$eng Few detections can be a false positive - check the link." }
            elseif ($v.Malicious -eq 1 -or $v.Suspicious -ge 1) { Set-Security $r 'Warning' "VirusTotal: only 1 of $($v.Total) engines flags this file$lbl.$eng Probably a false positive (common for ROMs, patchers and emulators); not moved." }
            else { Add-Note $r "VirusTotal: clean (0 of $($v.Total) engines)" }
        }
        'Unknown' { Add-Online $r 'VT not seen'; Add-Note $r 'VirusTotal has never seen this exact file (normal for ROMs, not a sign of danger)' }
    }
}

# ---- MalwareBazaar (abuse.ch, free key): database of confirmed malware samples
function Invoke-MbLookup([string]$Sha, [string]$Key) {
    Enable-Tls
    try {
        Update-FileProgress 'Waiting for MalwareBazaar (network timeout 30s)' $Sha
        $j = Invoke-RestMethod -Uri 'https://mb-api.abuse.ch/api/v1/' -Method Post -Body @{ query = 'get_info'; hash = $Sha } -Headers @{ 'Auth-Key' = $Key; 'User-Agent' = $script:UA['User-Agent'] } -TimeoutSec 30 -UseBasicParsing
        Complete-FileProgress
        switch ($j.query_status) {
            'ok' { $d0 = @($j.data)[0]; [pscustomobject]@{ Status = 'Found'; Signature = [string]$d0.signature; Tags = (@($d0.tags) -join ', '); FileName = [string]$d0.file_name; Date = (Get-Date).ToString('s') } }
            'hash_not_found' { [pscustomobject]@{ Status = 'Unknown'; Date = (Get-Date).ToString('s') } }
            default { [pscustomobject]@{ Status = 'Error'; Message = "MalwareBazaar answered '$($j.query_status)'" } }
        }
    } catch {
        switch (Get-HttpStatus $_) {
            401 { [pscustomobject]@{ Status = 'BadKey' } }
            403 { [pscustomobject]@{ Status = 'BadKey' } }
            429 { [pscustomobject]@{ Status = 'Quota' } }
            default { [pscustomobject]@{ Status = 'Error'; Message = $_.Exception.Message } }
        }
    }
}
function Set-MbResult($r, $v) {
    Add-Source $r 'MalwareBazaar'
    if ($v.Status -eq 'Found') {
        $sig = if ($v.Signature) { " as '$($v.Signature)'" } else { '' }
        Add-Online $r 'MalwareBazaar: KNOWN MALWARE'
        Set-Security $r 'Malicious' "MalwareBazaar (abuse.ch) lists this exact file as a confirmed malware sample$sig$(if ($v.Tags) { " (tags: $($v.Tags))" })."
    } elseif ($v.Status -eq 'Unknown') { Add-Online $r 'MalwareBazaar: not listed' }
}

function Get-OnlineCandidates($Results) {
    @(switch ($S.OnlineCheck) {
            'Risky'      { $Results | Where-Object { $_.Category -notin 'Other_Console', 'Protected' -and ($_.Security -ne 'Clean' -or $_.Category -in 'Archive', 'Unknown_Check_Manually', 'Invalid_Corrupt', 'Not_In_DAT') } }
            'Unverified' { $Results | Where-Object { $_.Category -notin 'Other_Console', 'Protected' -and -not $_.DatMatch -and -not $_.HashMatch -and ($_.Category -ne 'Not_A_ROM' -or $_.Security -ne 'Clean') } }
            'All'        { $Results | Where-Object { $_.Category -notin 'Other_Console' } }
        })
}

function Invoke-OnlineCheck($Results) {
    foreach ($r in $Results) { $r | Add-Member NoteProperty OnlineMalwareStatus $(if ($S.OnlineCheck -eq 'Off') { 'Skipped' } else { 'Not selected by policy' }) -Force }
    if ($S.OnlineCheck -eq 'Off') { return }
    $vtKey = Get-VtKey; $mbKey = Get-MbKey
    $cands = Get-OnlineCandidates $Results
    if (-not $vtKey -and -not $mbKey) {
        $message = 'Online malware checks are enabled but no VirusTotal or MalwareBazaar key is configured. These checks were unavailable.'
        Write-Warning $message
        if ($null -ne $script:ServiceIssues) { [void]$script:ServiceIssues.Add($message) }
        foreach ($r in $cands) { $r.OnlineMalwareStatus = 'Unavailable' }
        return
    }
    if (-not $cands.Count) { Write-Host '  Virus lookup: no files need checking.' -ForegroundColor Green; return }
    foreach ($r in $cands) { if (-not $r.SHA256 -and $r.Length -le ([long]$S.HashLimitMB * 1MB)) { try { $r.SHA256 = Get-Sha256 $r.FullName } catch { } } }
    $cache = Get-OnlineCache

    if ($mbKey) {
        $todo = @($cands | Where-Object { $_.SHA256 -and -not (Get-Cached "mb:$($_.SHA256)" 7) } | Group-Object SHA256 | ForEach-Object { $_.Group[0] })
        Write-Host "  MalwareBazaar: $($cands.Count) file(s), $($todo.Count) online." -ForegroundColor DarkCyan
        $i = 0; $stop = ''
        foreach ($r in $todo) {
            $i++; Update-RomProgress -Phase 'MalwareBazaar lookups' -Done ($i-1) -Total $todo.Count -Unit lookups -Current $r.FileName -Indeterminate -Detail "Request $i/$($todo.Count); remote ETA unknown"
            $v = Invoke-MbLookup $r.SHA256 $mbKey
            switch ($v.Status) {
                'BadKey' { $stop = 'the MalwareBazaar key was rejected' }
                'Quota'  { $stop = 'MalwareBazaar rate limit reached' }
                'Error'  { if ($i -le 2) { $stop = "MalwareBazaar not reachable ($($v.Message))" } }
                default  { $cache["mb:$($r.SHA256)"] = $v }
            }
            if ($stop) { break }
            Start-Sleep -Milliseconds 300
        }
        Complete-FileProgress
        foreach ($r in $cands) { if ($r.SHA256) { $v = Get-Cached "mb:$($r.SHA256)" 7; if ($v) { Set-MbResult $r $v } } }
        if ($stop) { Write-Host "  MalwareBazaar stopped: $stop." -ForegroundColor Yellow }
    }

    if ($vtKey) {
        $fresh = @($cands | Where-Object { $_.SHA256 -and -not (Get-Cached "vt:$($_.SHA256)") } | Group-Object SHA256 | ForEach-Object { $_.Group[0] })
        $eta = [math]::Ceiling($fresh.Count * $S.VtDelay / 60)
        Write-Host "  VirusTotal: $($cands.Count) file(s) to check, $($cands.Count - $fresh.Count) from cache, $($fresh.Count) online (~$eta min)." -ForegroundColor DarkCyan
        $i = 0; $stop = $null; $last = [datetime]::MinValue
        foreach ($r in $fresh) {
            $i++
            $wait = $S.VtDelay - ((Get-Date) - $last).TotalSeconds
            Update-RomProgress -Phase 'VirusTotal lookups' -Done ($i-1) -Total $fresh.Count -Unit lookups -Current $r.FileName -Indeterminate -Detail "Request $i/$($fresh.Count); rate limited, remote ETA unknown"
            if ($wait -gt 0) { Wait-RomProgress $wait 'VirusTotal' }
            $v = Invoke-VtLookup $r.SHA256 $vtKey; $last = Get-Date
            switch ($v.Status) {
                'BadKey' { $stop = 'the API key was rejected - check it in the Security & online menu' }
                'Quota'  { $stop = 'the VirusTotal quota is used up (free: 500 lookups/day) - run again later; checked files are cached' }
                'Error'  { Add-Note $r "VirusTotal lookup failed: $($v.Message)" }
                default  { $cache["vt:$($r.SHA256)"] = $v }
            }
            if ($stop) { break }
        }
        Complete-FileProgress
        foreach ($r in $cands) { if ($r.SHA256) { $v = Get-Cached "vt:$($r.SHA256)"; if ($v) { Set-VtResult $r $v } } }
        if ($stop) { Write-Host "  VirusTotal stopped early: $stop." -ForegroundColor Yellow }
    }
    Save-OnlineCache
    foreach ($r in $cands) {
        $vt = if ($vtKey -and $r.SHA256) { Get-Cached "vt:$($r.SHA256)" } else { $null }
        $mb = if ($mbKey -and $r.SHA256) { Get-Cached "mb:$($r.SHA256)" 7 } else { $null }
        $r.OnlineMalwareStatus = if ((-not $vtKey -or $vt.Status -in 'Found','Unknown') -and (-not $mbKey -or $mb.Status -in 'Found','Unknown')) { 'Completed' } else { 'Incomplete' }
    }
    if (@($cands | Where-Object OnlineMalwareStatus -eq 'Incomplete').Count -and $null -ne $script:ServiceIssues) {
        [void]$script:ServiceIssues.Add('Some enabled online malware lookups did not complete. Affected files are held for review.')
    }
    $bad = @($cands | Where-Object { $_.Threats -match 'VirusTotal|MalwareBazaar' }).Count
    Write-Host "  Virus lookup: done, $bad file(s) flagged." -ForegroundColor $(if ($bad) { 'Red' } else { 'Green' })
    foreach ($r in $cands) { if ($r.Security -in 'Malicious', 'Suspicious' -and $r.Category -ne 'Quarantine') { $r.Category = 'Quarantine'; $r.Reason = $r.Threats } }
}

# ===================================================================== SCANNING (every subfolder, any depth)
$script:EmuExeRx = '^(retroarch|snes9x.*|bsnes.*|mesen.*|fceux.*|nestopia.*|mgba.*|sameboy.*|bgb.*|visualboyadvance.*|vba.*|project64.*|simple64.*|rmg.*|ares.*|melonds.*|desmume.*|azahar.*|lime3ds.*|citra.*|mednafen.*|kega.*|fusion.*|blastem.*|stella.*|altirra.*|a7800.*|bigpemu.*|jzintv.*|openmsx.*|mame.*|fbneo.*|duckstation.*|pcsx2.*|ppsspp.*|dolphin.*|cemu.*|ryujinx.*|eden.*|citron.*|yuzu.*|xemu.*|flycast.*|redream.*|epsxe.*|xenia.*|rpcs3.*|handy.*|pokemini.*|ymir.*|nanoboyadvance.*|gambatte.*|emulationstation.*|es-de.*|launchbox.*|bigbox.*|retrobat.*|playnite.*)\.exe$'

function Test-AppFolder([IO.DirectoryInfo]$Dir, $Items) {
    $files = @($Items | Where-Object { $_ -is [IO.FileInfo] }); $dirs = @($Items | Where-Object { $_ -is [IO.DirectoryInfo] } | ForEach-Object { $_.Name.ToLower() })
    $exe = @($files | Where-Object { $_.Extension -ieq '.exe' }); $dll = @($files | Where-Object { $_.Extension -ieq '.dll' })
    if ($files.Count) {
        $hint = Get-FolderHint $files[0]
        if ($hint -and $hint.Kind -eq 'arcade') { return "$($hint.Name) collection: parent/clone ROMs, BIOS and CHD paths must stay together; files are checked but this folder is not reorganised internally" }
        if ($hint -and $hint.Kind -eq 'computer' -and ($files | Where-Object { $_.Extension -in '.slave', '.uae', '.vfl', '.info' })) {
            return 'extracted/configured computer game: keep WHDLoad, emulator configuration and relative media paths intact'
        }
    }
    if (-not $script:OnWindows) {
        # Only extensionless binaries and AppImages can be Linux programs; ROM names like "SNES9X Demo.smc" must not match.
        $app = $files | Where-Object {
            if ($_.Extension -ieq '.AppImage') { $name = $_.BaseName }
            elseif ([string]::IsNullOrEmpty($_.Extension)) { $name = $_.Name }
            else { return $false }
            if (($name + '.exe') -notmatch $script:EmuExeRx) { return $false }
            $mode = $_.PSObject.Properties['UnixFileMode']
            if ($mode -and $null -ne $mode.Value) { return (([int]$mode.Value) -band 73) -ne 0 }
            $true
        } | Select-Object -First 1
        if ($app) { return "Linux emulator/frontend program found ($($app.Name))" }
    }
    if ($exe | Where-Object { $_.Name -match $script:EmuExeRx }) { return "emulator/frontend program found ($(($exe | Where-Object { $_.Name -match $script:EmuExeRx } | Select-Object -First 1).Name))" }
    if ($exe.Count -and $dll.Count) { return "installed program found ($($exe[0].Name) + $($dll.Count) DLL file(s))" }
    if ($files | Where-Object { $_.Name -in 'default.xbe', 'PARAM.SFO', 'PS3_DISC.SFB' }) { return 'extracted console game (Xbox/PS3/PS Vita files)' }
    if ($dirs -contains 'ps3_game' -or $dirs -contains 'psp_game' -or $dirs -contains 'sce_sys') { return 'extracted PS3/PSP/Vita game folder' }
    if ($dirs -contains 'code' -and $dirs -contains 'content' -and $dirs -contains 'meta') { return 'extracted Wii U game (code/content/meta)' }
    if ($dirs -contains 'sys' -and $dirs -contains 'files' -and $Dir.Name -match '\[[0-9A-Z]{6}\]|^[0-9A-Z]{6}$') { return 'extracted GameCube/Wii game folder' }
    $null
}

function Get-ScanFiles {
    $root = Get-DirectoryPath $S.RootFolder
    $out = New-Object Collections.Generic.List[object]; $script:ScanErrors = New-Object Collections.ArrayList; $script:ProtectedDirs = New-PathMap
    $skipNames = @($S.QuarantineFolder, $S.DuplicateFolder, $S.UnpackedFolder) | Where-Object { $_ }
    $stack = New-Object Collections.Stack; $stack.Push(@{ Dir = ([IO.DirectoryInfo]::new((LongP $root))); Prot = $null; Depth = 0 })
    $n = 0
    while ($stack.Count) {
        $it = $stack.Pop(); $dir = $it.Dir
        try { $items = $dir.GetFileSystemInfos() } catch { [void]$script:ScanErrors.Add("$([RomSorter.RomTools]::Plain($dir.FullName)): $($_.Exception.Message)"); continue }
        $prot = $it.Prot
        if (-not $prot -and $S.ProtectAppFolders) {
            $why = Test-AppFolder $dir $items
            if ($why) { $prot = $why; $script:ProtectedDirs[[RomSorter.RomTools]::Plain($dir.FullName)] = $why }
        }
        foreach ($x in $items) {
            if ($x.Attributes -band [IO.FileAttributes]::ReparsePoint) { [void]$script:ScanErrors.Add("Skipped link/junction: $([RomSorter.RomTools]::Plain($x.FullName))"); continue }
            if ($x -is [IO.DirectoryInfo]) {
                if ($x.Name -match $script:SkipDirRx -or ($it.Depth -eq 0 -and $skipNames -contains $x.Name)) { continue }
                $stack.Push(@{ Dir = $x; Prot = $prot; Depth = $it.Depth + 1 })
            } else {
                if ($x.Name -in 'desktop.ini', 'Thumbs.db', '.DS_Store' -or $x.Name -like '._*') { continue }
                $plain = [RomSorter.RomTools]::Plain($x.FullName)
                if ((Test-SamePath $plain $script:ScriptPath) -or
                    (Test-SamePath $plain (Join-Path (Split-Path $script:ScriptPath) 'RomSorter.sh')) -or
                    (Test-SamePath $plain (Join-Path (Split-Path $script:ScriptPath) 'RomSorter.Tests.ps1'))) { continue }
                $out.Add([pscustomobject]@{ File = $x; Prot = $prot }); $n++
                if (($n % 200) -eq 0) { Update-RomProgress -Phase 'Finding files' -Done $n -Current ([RomSorter.RomTools]::Plain($dir.FullName)) -Indeterminate }
            }
        }
    }
    Update-RomProgress -Phase 'Finding files' -Done $n -Indeterminate -Detail 'Discovery finished'
    if ($script:CollectionSelection) { $out = @($out | Where-Object { $script:CollectionSelection.ContainsKey([RomSorter.RomTools]::Plain($_.File.FullName)) }) }
    $out | Sort-Object { $_.File.FullName }
}

# ---- multi-file games (cue/bin, gdi, ccd, mds, toc, m3u)
function Get-SetMembers([string]$Path) {
    $ext = [IO.Path]::GetExtension($Path).ToLower(); $dir = Split-Path $Path; $stem = [IO.Path]::GetFileNameWithoutExtension($Path)
    $names = New-Object Collections.ArrayList
    switch ($ext) {
        '.ccd' { foreach ($e in '.img', '.sub') { if (Test-PathLP (Join-Path $dir "$stem$e")) { [void]$names.Add("$stem$e") } }; if (-not $names.Count) { [void]$names.Add("$stem.img") } }
        '.mds' { [void]$names.Add("$stem.mdf") }
        default {
            if ((Get-Item -LiteralPath (LongP $Path)).Length -gt 1MB) { throw 'descriptor file is far too big - not a real cue/gdi/m3u' }
            $lines = [IO.File]::ReadAllLines((LongP $Path))
            foreach ($l in $lines) {
                $t = $l.Trim(); if (-not $t) { continue }
                if ($ext -eq '.m3u') { if (-not $t.StartsWith('#')) { [void]$names.Add($t) } }
                elseif ($ext -eq '.gdi') { if ($t -match '^\d+\s+\d+\s+\d+\s+\d+\s+(?:"(.+)"|(\S+))\s+-?\d+') { [void]$names.Add($(if ($Matches[1]) { $Matches[1] } else { $Matches[2] })) } }
                elseif ($t -match '^(?:FILE|DATAFILE)\s+(?:"(.+?)"|(\S+))') { [void]$names.Add($(if ($Matches[1]) { $Matches[1] } else { $Matches[2] })) }
            }
        }
    }
    @($names | Select-Object -Unique)
}

function Join-Sets($Results) {
    $byPath = New-PathMap; foreach ($r in $Results) { $byPath[$r.FullName] = $r }
    $desc = @($Results | Where-Object { $script:SetDescExt -contains [IO.Path]::GetExtension($_.FileName).ToLower() -and $_.Category -notin 'Protected', 'BIOS' -and $_.Security -notin 'Malicious', 'Suspicious', 'Executable' })
    # m3u last so it can adopt complete cue/gdi sets
    foreach ($d in @($desc | Where-Object { $_.FileName -notmatch '\.m3u$' }) + @($desc | Where-Object { $_.FileName -match '\.m3u$' })) {
        try { $names = Get-SetMembers $d.FullName } catch { $d.Header = 'Invalid'; Add-Note $d $_.Exception.Message; continue }
        $d.SetId = $d.FullName; $d.Set = $d.FileName; $missing = @(); $outside = @(); $mem = @()
        $base = Get-DirectoryPrefix (Split-Path $d.FullName)
        foreach ($n in $names) {
            try { $full = [IO.Path]::GetFullPath((Join-Path (Split-Path $d.FullName) (Convert-RelativePath $n))) } catch { $missing += $n; continue }
            if (-not $full.StartsWith($base, $script:PathComparison)) { $outside += $n; continue }
            $m = $byPath[$full]
            if (-not $m) { $missing += $n; continue }
            $mem += $m
        }
        if ($missing.Count) { $d.Header = 'Invalid'; Add-Note $d "Incomplete set - missing file(s): $(($missing | Select-Object -First 5) -join ', ')" }
        if ($outside.Count) { $d.Header = 'Invalid'; Add-Note $d "Refers to file(s) outside its own folder ($(($outside | Select-Object -First 3) -join ', ')) - left in place" ; $d.Category = 'Unknown_Check_Manually' }
        if (-not $names.Count) { $d.Header = 'Invalid'; Add-Note $d 'Descriptor lists no files' }
        $con = $null
        foreach ($m in $mem) { if (-not $con -and $m.Console -ne '-') { $con = Get-Con $m.Console } }
        if (-not $con -and $d.Console -ne '-') { $con = Get-Con $d.Console }
        if (-not $con) { $h = Get-FolderHint ([IO.FileInfo]::new((LongP $d.FullName))); if ($h -and $h.Kind -eq 'disc') { $con = $h; $d.Detected = "console from folder name" } }
        if ($con) { $d.Console = $con.Key; $d.ConsoleFolder = $con.Folder; $d.Emulator = Get-Emulator $con }
        foreach ($m in $mem) {
            if ($m.Security -in 'Malicious', 'Suspicious', 'Executable') { $d.Header = 'Invalid'; Add-Note $d "Member '$($m.FileName)' is flagged as dangerous and quarantined separately"; continue }
            if ($m.Lead -and $m.Lead -ne $d) { if ($m.Lead.FileName -match '\.m3u$') { continue } }
            $m.Lead = $d; $m.SetId = $d.FullName; $m.Set = $d.FileName
            if ($con -and $m.Console -eq '-') { $m.Console = $con.Key; $m.ConsoleFolder = $con.Folder; $m.Emulator = Get-Emulator $con }
            if ($m.Category -eq 'Not_A_ROM') { $m.Category = '' }
        }
        $d | Add-Member -NotePropertyName SetMembers -NotePropertyValue @($mem) -Force
        if ($d.Header -ne 'Invalid' -and $mem.Count) { $d.Header = ($mem | Where-Object { $_.Header -eq 'Valid' } | Select-Object -First 1) | ForEach-Object { 'Valid' }; if (-not $d.Header) { $d.Header = 'Unknown' } }
    }
}

# verdict for a whole set: every track must be OK / in the DAT
function Set-SetVerdict($d) {
    $con = Get-Con $d.Console; $mem = @($d.SetMembers | Where-Object { $_.Security -notin 'Malicious', 'Suspicious', 'Executable' })
    if ($d.FileName -match '\.m3u$' -and $con -and $d.Header -ne 'Invalid') {
        $worst = $mem | Where-Object { $_.Category -ne 'Original' } | Select-Object -First 1
        if ($worst) { $d.Category = $worst.Category; $d.Reason = "Multi-disc playlist; disc '$($worst.FileName)': $($worst.Reason)" }
        else { $d.Category = 'Original'; $d.Reason = "Multi-disc playlist with $($mem.Count) disc(s), all OK" }
        return
    }
    if (-not $con) { $d.Category = 'Unknown_Check_Manually'; $d.Reason = 'Disc set of an unknown console - put it in a folder named after the console and scan again' }
    elseif ($d.Category -eq 'Unknown_Check_Manually' -and $d.Notes -match 'outside its own folder') { $d.Reason = $d.Notes }
    elseif ($d.Header -eq 'Invalid') { $d.Category = 'Invalid_Corrupt'; $d.Reason = "Broken $($con.Name) disc set: $($d.Notes)" }
    elseif (($bad = @($mem | Where-Object { $_.Header -eq 'Invalid' })).Count) { $d.Category = 'Invalid_Corrupt'; $d.Reason = "Track '$($bad[0].FileName)' is damaged: $($bad[0].Notes)" }
    else {
        $hashed = @($mem | Where-Object { $_.CRC32 -and -not $_.Compressed })
        $matched = @($hashed | Where-Object { $_.DatMatch -or $_.HashMatch })
        $name = ($matched | Select-Object -First 1) | ForEach-Object { if ($_.DatMatch) { $_.DatMatch } else { $_.HashMatch } }
        $tag = Get-TagCategory ([IO.Path]::GetFileNameWithoutExtension($d.FileName)) ''
        if ($hashed.Count -and $hashed.Count -eq @($d.SetMembers).Count -and $matched.Count -eq $hashed.Count) {
            $t = Get-TagCategory $name ''
            $first = $matched | Select-Object -First 1; $demo = @($matched | Where-Object HhDemo | Select-Object -First 1)
            foreach ($f in 'Year', 'Publisher', 'Libraries') { if (-not $d.$f) { $d.$f = ($matched | Where-Object $f | Select-Object -First 1).$f } }
            if ($t -and $t.Category -ne 'Original') { $d.Category = $t.Category; $d.Reason = "Tracks match '$name': $($t.Reason)" }
            elseif ($demo.Count) { $d.Category = 'Beta_Proto_Sample'; $d.Reason = "Tracks match '$name', but the Hasheous library marks it as a demo ($($demo[0].HhDemo))" }
            else { $d.Category = 'Original'; $d.Reason = "VERIFIED released game: all $($hashed.Count) track(s) match '$name'$(Get-ReleaseText $d)" }
        } elseif ($tag -and $tag.Category -ne 'Original') { $d.Category = $tag.Category; $d.Reason = $tag.Reason }
        elseif ($hashed.Count -and (($S.RequireDatMatch -and $script:DatConsoles.Contains($con.Key)) -or $S.RetailOnly)) {
            $d.Category = 'Not_In_DAT'; $d.Reason = "$($hashed.Count - $matched.Count) of $($hashed.Count) track(s) are not found in any game library (Redump DAT / Hasheous), so this is not a confirmed released game"
        } else {
            $d.Category = 'Original'; $d.Reason = "Complete $($con.Name) disc set ($($mem.Count) file(s))" + $(if ($tag) { "; $($tag.Reason)" }) + $(if ($mem | Where-Object Detected) { "; $(($mem | Where-Object Detected | Select-Object -First 1).Detected)" })
        }
    }
    foreach ($m in $mem) { if ($m.Lead -eq $d) { $m.Category = $d.Category; $m.Reason = "Part of '$($d.FileName)': $($d.Reason)" } }
}

# ---- saves / patches / covers with the same name follow their ROM
function Join-Companions($Results) {
    $roms = New-PathMap
    foreach ($r in $Results) {
        if ($r.Console -ne '-' -and $r.Category -notin 'Quarantine', 'Executable', 'Protected', 'BIOS', 'Not_A_ROM' -and -not ($r.Lead)) {
            $roms["$($r.Folder)|$([IO.Path]::GetFileNameWithoutExtension($r.FileName))"] = $r
        }
    }
    foreach ($r in $Results) {
        if ($r.Category -ne 'Not_A_ROM' -or $r.Security -ne 'Clean') { continue }
        $ext = [IO.Path]::GetExtension($r.FileName).ToLower()
        if (-not ($script:CompanionExt -contains $ext -or $ext -match '^\.(state\d*|ss\d|st\d|sa\d|ep\d)$')) { continue }
        $stem = [IO.Path]::GetFileNameWithoutExtension($r.FileName)
        $rom = $roms["$($r.Folder)|$stem"]
        if (-not $rom) { $s2 = [IO.Path]::GetFileNameWithoutExtension($stem); if ($s2 -ne $stem) { $rom = $roms["$($r.Folder)|$s2"] } }
        if ($rom -and $S.MoveCompanions) { $r.Category = 'Companion'; $r.Lead = $rom; $r.Console = $rom.Console; $r.Reason = "Belongs to '$($rom.FileName)' (same name) - moves with it" }
    }
}

# ---- identical files: keep one, move the rest to _Duplicates
function Find-Duplicates($Results) {
    if ($S.DuplicateMode -eq 'Off') { return }
    $groups = $Results | Where-Object { $_.Console -ne '-' -and $_.SHA1 -and -not $_.SetId -and -not $_.Lead -and $_.Category -notin $script:StayCats -and $_.Category -notin 'Quarantine', 'Companion' } | Group-Object Console, SHA1 | Where-Object Count -gt 1
    foreach ($g in $groups) {
        $keep = $g.Group | Sort-Object @{ E = { if ($_.Category -eq 'Original') { 0 } else { 1 } } }, @{ E = { $x = $_; if (@($Results | Where-Object { $_.Lead -eq $x -and $_.Category -eq 'Companion' }).Count) { 0 } else { 1 } } }, @{ E = { if ($_.Folder -match '(?i)[\\/](backups?|old|copy|copies|dupes?|duplicates?|temp|tmp)([\\/]|$)') { 1 } else { 0 } } }, @{ E = { $_.FullName.Length } }, FullName | Select-Object -First 1
        foreach ($r in $g.Group) {
            if ($r -eq $keep) { continue }
            $r.DupOf = $keep.FullName
            if ($S.DuplicateMode -eq 'Move') { $r.Category = 'Duplicate'; $r.Reason = "Byte-for-byte identical to '$($keep.FullName)' (kept)" }
            else { Add-Note $r "Duplicate of '$($keep.FullName)'" }
        }
    }
}

# ---- where does each file go?
function Get-SafeName([string]$n) { foreach ($c in [IO.Path]::GetInvalidFileNameChars()) { $n = $n.Replace([string]$c, '_') }; $n.Trim().TrimEnd('.') }
function Get-ConsoleDir($r) {
    $con = Get-Con $r.Console; $root = $S.RootFolder
    if (-not $con) { return $null }
    switch ($S.Layout) {
        'Emulator'  { Join-Path (Join-Path $root (Get-SafeName (Get-Emulator $con))) $con.Folder }
        'Frontend'  { Join-Path $root $con.Short }
        'RetroArch' { $n = if ($con.Libretro.Count) { ($con.Libretro[0] -split '/', 2)[1] } elseif ($con.Key -eq 'ARCADE') { 'MAME' } else { $con.Name }; Join-Path $root (Get-SafeName $n) }
        'Classic'   { $root }
        default     { Join-Path $root $con.Folder }
    }
}
# Validity layout: integrity (verified against a DAT/online library) + release status + modification, as sub-folders
function Get-Validity($r) {
    if ($r.PSObject.Properties['SortOnly'] -and $r.SortOnly) { return 'Unverified\Needs-Verification' }
    $stem = [IO.Path]::GetFileNameWithoutExtension($r.FileName)
    $n = "$stem $($r.DatMatch) $($r.HashMatch)"
    $ver = [bool]($r.DatMatch -or $r.HashMatch -or $r.Reason -match '^VERIFIED')
    $unver = 'Unverified\Needs-Verification'
    $c = $r.Category
    if ($c -in 'Original', 'Beta_Proto_Sample', 'PD_Homebrew_Unlicensed', 'BS_ST', 'Bad_or_Fixed_Dumps', 'Hacks_Mods', 'Translations', 'Not_In_DAT', 'Unknown_Check_Manually' -and $n -cmatch '\[u\d*\]') { return 'Invalid\Incomplete' }
    switch ($c) {
        'Invalid_Corrupt' {
            if ($r.Reason -match 'Empty|truncat|too small|too short|incomplete|missing|Cannot read|smaller') { return 'Invalid\Incomplete' }
            return 'Invalid\Corrupted'
        }
        'Hacks_Mods' {
            if ($n -cmatch '\[t(\d|\s|\])|trainer') { return 'Modified\Trainers' }
            if ($n -cmatch '\[p\d|Pirate') { return 'Modified\Pirate' }
            if ($n -cmatch '\[f\d*\]|\[BF') { return 'Modified\Fixed' }
            return 'Modified\Hacks'
        }
        'Translations' { return 'Modified\Translations' }
        'Bad_or_Fixed_Dumps' {
            if ($n -cmatch '\[f\d*\]') { return 'Modified\Fixed' }
            if ($n -cmatch '\[o\d*\]') { return $unver }
            return 'Invalid\Bad-Dumps'
        }
        'Beta_Proto_Sample' {
            if (-not $ver) { return $unver }
            if ($r.HhDemo -or $n -match '\b(Demo|Kiosk|Sample|Trial|Taikenban|Promo|Preview|Shoshinkai)\b') { return 'Verified\Demos' }
            return 'Non-Retail\Prototypes'
        }
        'PD_Homebrew_Unlicensed' {
            if ($n -match 'Pirate|Multicart') { return 'Modified\Pirate' }
            if ($n -match '\b(Unl|Unlicensed)\b') { return 'Non-Retail\Unlicensed' }
            return 'Non-Retail\Homebrew'
        }
        'Other_NonGame' { return 'Non-Games' }
        'BS_ST' { if ($ver) { return 'Verified\Other-Official-Releases' } else { return $unver } }
        'Not_In_DAT' { return 'Unverified\Unknown' }
        'Original' {
            if (-not $ver) { return $unver }
            if ($n -cmatch '\((Rev [^)]*|v\d[^)]*)\)') { return 'Verified\Revisions' }
            if ($n -match "Player's Choice|Nintendo Selects|Greatest Hits|Platinum|The Best|Virtual Console|Classic|Collection|Reprint|Budget|Switch Online|Limited Run") { return 'Verified\Other-Official-Releases' }
            return 'Verified\Retail'
        }
        default { return $unver }
    }
}
function Get-BaseDir($r) {
    if ($r.Category -eq 'Quarantine') { return (Join-Path $S.RootFolder $S.QuarantineFolder) }
    if ($r.Category -eq 'Duplicate') { return (Join-Path (Join-Path $S.RootFolder $S.DuplicateFolder) $(if ($r.ConsoleFolder) { $r.ConsoleFolder } else { 'Other' })) }
    if ($r.Category -eq 'BIOS') {
        if (-not $r.BiosMovable -or $r.Protected -or $r.Security -notin 'Clean','Not checked') { return $null }
        $biosConsole = Get-Con $r.Console
        if (-not $biosConsole -or $biosConsole.Kind -eq 'arcade') { return $null }
        return (Join-Path (Join-Path $S.RootFolder $biosConsole.Folder) 'BIOS')
    }
    if ($script:StayCats -contains $r.Category -or $r.Category -eq 'Companion' -or -not $r.Category) { return $null }
    $cd = Get-ConsoleDir $r; if (-not $cd) { return $null }
    $con = Get-Con $r.Console
    if ($con.Kind -eq 'arcade') {
        if ($S.Layout -eq 'Classic') { return $null }
        return $cd
    }
    if ($S.Layout -eq 'Validity') { return (Join-Path $cd (Convert-RelativePath (Get-Validity $r))) }
    if ($r.PSObject.Properties['SortOnly'] -and $r.SortOnly) {
        if ($S.Layout -eq 'Classic') { return $null }
        return $cd
    }
    if ($r.Category -eq 'Original') { if ($S.Layout -eq 'Classic') { return $null }; return $cd }
    $dir = if ($S.RejectsOutside) { Join-Path (Join-Path $S.RootFolder $S.RejectFolder) (Get-Con $r.Console).Folder } else { Join-Path $cd $S.NonOriginalFolder }
    if ($S.SortByCategory) { $dir = Join-Path $dir $r.Category }
    $dir
}
function Get-Top($r) { $t = $r; $guard = 0; while ($t.Lead -and $guard++ -lt 5) { $t = $t.Lead }; $t }

function Set-Targets($Results) {
    if ($script:RomProgress) { Set-TargetsCore $Results }
    else { Invoke-ProgressTask 'Sort preview' { Set-TargetsCore $Results } }
}
function Set-TargetsCore($Results) {
    foreach ($r in $Results) { $r.Target = ''; $r.Action = 'Stays' }
    $units = New-PathMap
    foreach ($r in $Results) {
        if ($r.Category -in 'Quarantine', 'Executable', 'Protected', 'Kept') { if ($r.Category -eq 'Quarantine') { $units[$r.FullName] = @($r) }; continue }
        $top = Get-Top $r
        if ($top.Category -eq 'Quarantine') { continue }
        if (-not $units.ContainsKey($top.FullName)) { $units[$top.FullName] = New-Object Collections.ArrayList }
        if ($units[$top.FullName] -is [Collections.ArrayList]) { [void]$units[$top.FullName].Add($r) }
    }
    $claimed = New-PathMap; $byFolder = New-PathMap
    foreach ($r in $Results) { $k = $r.Folder; if (-not $byFolder.ContainsKey($k)) { $byFolder[$k] = New-Object Collections.ArrayList }; [void]$byFolder[$k].Add($r) }
    $planned = 0
    foreach ($key in ($units.Keys | Sort-Object)) {
        Update-RomProgress -Phase 'Planning destinations' -Done $planned -Total $units.Count -Unit groups -Current $key
        $planned++
        $files = @($units[$key]); $lead = $files | Where-Object { Test-SamePath $_.FullName $key } | Select-Object -First 1
        if (-not $lead) { continue }
        $base = Get-BaseDir $lead; if (-not $base) { continue }
        $srcDir = Split-Path $lead.FullName
        $sub = ''
        $isSet = $lead.SetId -or @($files | Where-Object { $_.SetId }).Count
        if ($S.KeepGameFolders -and $isSet -and $lead.Category -ne 'Quarantine') {
            $dirFiles = @($byFolder[$srcDir])
            $own = -not ($dirFiles | Where-Object { $files -notcontains $_ })
            $pn = Split-Path $srcDir -Leaf
            if ($own -and -not (Test-SamePath (Get-DirectoryPath $srcDir) (Get-DirectoryPath $S.RootFolder)) -and -not (Get-Con $pn) -and -not ($script:Consoles | Where-Object { $_.Folder -ieq $pn -or $_.Short -ieq $pn -or $pn -match $_.Hint }) -and $pn -notin $S.NonOriginalFolder, $S.RejectFolder, 'Original' -and -not $script:CatInfo.Contains($pn)) { $sub = $pn }
        }
        $dest = if ($sub) { Join-Path $base $sub } else { $base }
        if ((Test-SamePath (Split-Path $srcDir) $dest) -and (Split-Path $srcDir -Leaf) -like 'from *') { $dest = $srcDir }   # already in a name-clash subfolder from an earlier run
        for ($try = 0; $try -lt 25; $try++) {
            $plan = New-PathMap; $clash = $false
            foreach ($f in $files) {
                $rel = if (Test-ChildPath $f.FullName $srcDir) { $f.FullName.Substring((Get-DirectoryPrefix $srcDir).Length) } else { $f.FileName }
                $t = Join-Path $dest $rel
                if (Test-SamePath $t $f.FullName) { $plan[$f.FullName] = ''; continue }
                if ($claimed.ContainsKey($t) -or (Test-PathLP $t)) { $clash = $true; break }
                $plan[$f.FullName] = $t
            }
            if (-not $clash) { break }
            $pn = Get-SafeName (Split-Path $srcDir -Leaf); if (-not $pn -or (Test-SamePath (Get-DirectoryPath $srcDir) (Get-DirectoryPath $S.RootFolder))) { $pn = 'from root' }
            $dest = if ($try -eq 0) { Join-Path $dest "from $pn" } else { Join-Path (Split-Path $dest) "from $pn ($($try + 1))" }
        }
        if ($clash) { foreach ($f in $files) { Add-Note $f 'No free target name found - left in place' }; continue }
        foreach ($f in $files) {
            $t = $plan[$f.FullName]
            if ($t) { $f.Target = $t; $f.Action = 'Will move'; $claimed[$t] = $true }
            if ($t -and -not (Test-SamePath $dest $base) -and -not $sub) { Add-Note $f "A different file with this name already exists in the target folder, so it goes to subfolder '$(Split-Path $dest -Leaf)' (name unchanged)" }
        }
    }
}

function Invoke-Scan { Invoke-ProgressTask 'Checking' { Invoke-ScanCore } }
function Invoke-ScanCore {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $script:ScanRunStamp = Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'
    Update-RomProgress -Phase 'Finding files' -Indeterminate
    $entries = @(Get-ScanFiles)
    if (-not $entries.Count) { Write-Host "  No files found in $($S.RootFolder)" -ForegroundColor Yellow; Export-IdentificationReport @(); return @() }
    Write-Host "  Found $($entries.Count) file(s) in $(@($entries | ForEach-Object { $_.File.DirectoryName } | Select-Object -Unique).Count) folder(s)." -ForegroundColor DarkCyan
    if ($script:ScanErrors.Count) { Write-Host "  $($script:ScanErrors.Count) folder(s) could not be read or were skipped (see report)." -ForegroundColor Yellow }

    $defHits = New-PathMap; $def = $null
    if ($S.DefenderScan) {
        $antivirusWatch = [Diagnostics.Stopwatch]::StartNew()
        Update-RomProgress -Phase 'Antivirus scan' -Current $script:AntivirusName -Indeterminate
        Write-Host "  Running $script:AntivirusName scan (this can take a while)..." -ForegroundColor DarkCyan
        $def = Invoke-AntivirusScan $S.RootFolder
        $defHits = $def.Hits
        Write-Host "  ${script:AntivirusName}: $($def.Message)" -ForegroundColor $(if ($def.Hits.Count) { 'Red' } elseif ($def.Available) { 'Green' } else { 'Yellow' })
        Set-ProgressCounter 'Antivirus seconds' ([int]$antivirusWatch.Elapsed.TotalSeconds)
        if (-not $def.Available -and $null -ne $script:ServiceIssues) { [void]$script:ServiceIssues.Add("$script:AntivirusName did not complete: $($def.Message)") }
    }

    $results = New-Object Collections.Generic.List[object]; $i = 0; $resumed = 0; $fresh = 0; $rechecked = 0
    $bytesDone = 0L; $totalBytes = [double](($entries | ForEach-Object { $_.File.Length } | Measure-Object -Sum).Sum)
    $script:ScanContext = Get-ScanContext -Local
    foreach ($e in $entries) {
        $i++; $f = $e.File
        if ($script:RomProgress) {
            $script:RomProgress.TrackedPath = [RomSorter.RomTools]::Plain($f.FullName)
            $script:RomProgress.ByteBase = $bytesDone; $script:RomProgress.TrackedLength = $f.Length
        }
        Update-RomProgress -Phase 'Local checks' -Done $bytesDone -Total $totalBytes -Unit bytes -Current $f.FullName -Detail "$($i-1)/$($entries.Count) files | reused $resumed | fresh $fresh | rechecked $rechecked"
        try {
            $r = Read-ScanCheckpoint $f
            if ($r) { $resumed++ }
            else {
                if (Test-Path -LiteralPath (Get-CheckpointPath ([RomSorter.RomTools]::Plain($f.FullName)))) { $rechecked++ } else { $fresh++ }
                $r = Invoke-FileAnalysis $f $null
                if (-not $r.SHA256) { $r.ScanFingerprint = Get-Sha256 $f.FullName } else { $r.ScanFingerprint = $r.SHA256 }
                $r.CheckedUtc = [DateTime]::UtcNow.ToString('o')
                Write-ScanCheckpoint $r
            }
        }
        catch { $r = New-Result $f; $r.Category = 'Unknown_Check_Manually'; $r.Reason = "Error while checking: $($_.Exception.Message)" }
        if ($defHits.ContainsKey($r.FullName)) { Set-Security $r 'Malicious' "$script:AntivirusName detected '$($defHits[$r.FullName])'." }
        $r.AntivirusStatus = if (-not $S.DefenderScan) { 'Disabled' } elseif ($defHits.ContainsKey($r.FullName)) { 'Threat detected' } elseif ($def.Available) { 'Completed - no detections' } else { 'Incomplete' }
        $r.AntivirusCheckedUtc = if ($S.DefenderScan) { [DateTime]::UtcNow.ToString('o') } else { '' }
        if ($def -and $def.Available) { Add-Source $r $script:AntivirusName }
        elseif ($S.DefenderScan) {
            Add-Note $r "$script:AntivirusName did not complete: $($def.Message)"
            if ($r.Security -eq 'Clean') { $r.Security = 'Warning' }
        }
        if ($script:UnpackBlocked -and $script:UnpackBlocked.ContainsKey($r.FullName)) { $b = $script:UnpackBlocked[$r.FullName]; if ("$($r.Threats)".IndexOf($b.Why) -lt 0) { Set-Security $r $b.Level "Not unpacked: $($b.Why)" } }
        if ($e.Prot -and $r.Security -notin 'Malicious', 'Suspicious') { $r.Category = 'Protected'; $r.Protected = $e.Prot; $r.Reason = "Inside a folder that should not be pulled apart: $($e.Prot)" }
        $results.Add($r)
        $bytesDone += $f.Length
        Update-RomProgress -Phase 'Local checks' -Done $bytesDone -Total $totalBytes -Unit bytes -Current $f.FullName -Detail "$i/$($entries.Count) files | reused $resumed | fresh $fresh | rechecked $rechecked"
    }
    Update-RomProgress -Phase 'Local checks' -Done $totalBytes -Total $totalBytes -Unit bytes -Force
    Set-ProgressCounter 'Checked' $results.Count; Set-ProgressCounter 'New' $fresh; Set-ProgressCounter 'Reused' $resumed; Set-ProgressCounter 'Rechecked' $rechecked
    if ($resumed) { Write-Host "  Resumed $resumed unchanged file check(s); hashes revalidated, antivirus and DAT checks refreshed." -ForegroundColor DarkCyan }
    $script:ScanChanges = [pscustomobject]@{ New = $fresh; Rechecked = $rechecked; Reused = $resumed }
    Write-Host "  This run: $fresh newly encountered file(s), $rechecked rechecked, $resumed unchanged local checks reused." -ForegroundColor DarkCyan

    Invoke-UnknownIdentification $results
    Update-RomProgress -Phase 'Building disc sets' -Indeterminate
    Join-Sets $results

    # verification sources: own DATs + libretro DATs for the consoles that were found
    $found = @($results | Where-Object { $_.Console -ne '-' } | ForEach-Object { $_.Console } | Select-Object -Unique)
    Update-RomProgress -Phase 'Refreshing verification sources' -Indeterminate
    if ($S.AutoDat -and $found.Count) { [void](Update-LibretroDats $found); Update-LibretroMeta $found }
    $script:MetaIndex = @{}; if ($S.AutoDat) { Import-LibretroMeta; if ($script:MetaIndex.Count) { Write-Host "  Release info: $($script:MetaIndex.Count) released games known (libretro)" -ForegroundColor DarkCyan } }
    $folders = @(Get-DatFolders)
    Import-DatFolder $folders
    if ($script:DatInfo) { Write-Host "  DAT: $($script:DatInfo)" -ForegroundColor DarkCyan }
    $matchedCount = 0
    foreach ($r in $results) {
        Update-RomProgress -Phase 'Matching DAT references' -Done $matchedCount -Total $results.Count -Current $r.FileName
        Resolve-DatMatch $r; if ($script:DatConsoles.Contains($r.Console)) { Add-Source $r 'DAT' }; Resolve-ReleaseInfo $r
        $matchedCount++
    }
    Invoke-HasheousCheck $results
    Set-ProgressCounter 'DAT matches' @($results | Where-Object DatMatch).Count
    Set-ProgressCounter 'Hasheous matches' @($results | Where-Object HashMatch).Count

    Update-RomProgress -Phase 'Resolving verdicts and dependencies' -Indeterminate
    foreach ($r in $results) {
        if ($r.SetId -and -not (Test-SamePath $r.SetId $r.FullName)) { continue }
        if ($script:SetDescExt -contains [IO.Path]::GetExtension($r.FileName).ToLower() -and $r.PSObject.Properties['SetMembers']) { continue }
        $con = Get-Con $(if ($r.Console -ne '-') { $r.Console })
        if ($r.Category -eq 'Not_A_ROM' -or $r.Category -eq '' -or $r.Security -ne 'Clean' -or $con) { $r.Category = Get-Verdict $r $con ([IO.Path]::GetExtension($r.FileName).ToLower()) }
    }
    $sets = @($results | Where-Object { $_.PSObject.Properties['SetMembers'] }); $sets = @($sets | Where-Object { $_.FileName -notmatch '\.m3u$' }) + @($sets | Where-Object { $_.FileName -match '\.m3u$' })
    foreach ($d in $sets) { if ($d.Security -in 'Clean', 'Warning') { Set-SetVerdict $d } else { $d.Category = Get-Verdict $d $null '' } }
    # members that became orphans (lead quarantined) or never got a verdict
    foreach ($r in $results) { if (-not $r.Category) { $r.Category = Get-Verdict $r (Get-Con $(if ($r.Console -ne '-') { $r.Console })) ([IO.Path]::GetExtension($r.FileName).ToLower()) } }

    Join-Companions $results
    Find-Duplicates $results
    Invoke-OnlineCheck $results
    foreach ($r in $results) { if ($r.Security -in 'Malicious', 'Suspicious' -and $r.Category -ne 'Quarantine') { $r.Category = 'Quarantine'; $r.Reason = $r.Threats } }
    Update-EvidenceStatus $results
    Update-RomProgress -Phase 'Building sort plan and saving results' -Indeterminate
    Set-Targets $results
    $script:ScanSeconds = [int]$sw.Elapsed.TotalSeconds
    Save-CompletedScan $results
    Export-IdentificationReport $results
    Set-ProgressCounter 'Warnings' @($results | Where-Object { $_.Security -ne 'Clean' -or $_.Header -eq 'Invalid' }).Count
    $results.ToArray()
}

function Update-EvidenceStatus($Results) {
    foreach ($r in $Results) {
        $sortOnly = $r.PSObject.Properties['SortOnly'] -and $r.SortOnly
        $r.Authenticity = if ($sortOnly) { 'Unverified' } elseif ($r.DatMatch) { "Verified ($($r.DatStrength))" } elseif ($r.HashMatch) { 'Verified (online hash)' } else { 'Unverified' }
        $r.IntegrityStatus = if ($sortOnly) { 'Unknown' } elseif ($r.Header -eq 'Invalid' -or $r.Integrity -eq 'Mismatch') { 'Failed checks' } elseif ($r.DatMatch -or $r.HashMatch) { 'Matches reference dump' } elseif ($r.Integrity -eq 'OK') { 'Internal checks passed (not authenticity)' } else { 'Unknown' }
        $r.MalwareStatus = if ($sortOnly) { 'Not checked' } elseif ($r.Security -eq 'Malicious') { 'Threat/heuristic detection' } elseif ($r.Security -eq 'Suspicious') { 'Suspicious' } elseif ($r.Security -eq 'Warning') { 'Warning / incomplete protection (see findings)' } elseif ($r.Security -eq 'Executable') { 'Executable - not a ROM' } elseif ($r.AntivirusStatus -eq 'Completed - no detections') { 'No detections (not a safety guarantee)' } else { 'Not fully checked' }
        if (-not $sortOnly -and ($r.DatMatch -or $r.HashMatch)) {
            if ($r.Category -in 'Hacks_Mods','Translations','Bad_or_Fixed_Dumps') { $r.Authenticity = 'Known modified dump (see matching evidence)' }
            elseif ($r.Category -in 'Beta_Proto_Sample','PD_Homebrew_Unlicensed') { $r.Authenticity = 'Known non-retail dump (see matching evidence)' }
        }
    }
    foreach ($r in $Results) {
        if (-not $r.PSObject.Properties['SetMembers'] -or -not $r.SetMembers.Count) { continue }
        $media = @($r.SetMembers | Where-Object { $_.CRC32 -and -not $_.Compressed })
        if ($media.Count -and $media.Count -eq @($r.SetMembers).Count -and -not @($media | Where-Object { -not $_.DatMatch -and -not $_.HashMatch }).Count) {
            $r.Authenticity = 'Verified member dumps (not descriptor bytes)'
            $r.IntegrityStatus = if ($r.Header -eq 'Invalid' -or @($media | Where-Object IntegrityStatus -eq 'Failed checks').Count) { 'Failed checks' } else { 'Member dumps match references' }
        }
    }
}
function Get-TextHash([string]$Text) {
    $b = [Text.Encoding]::UTF8.GetBytes($Text)
    ([RomSorter.RomTools]::HashBytes($b,0,$b.Length))[3]
}
function Get-ScanContext([switch]$Local) {
    $settings = [ordered]@{}
    foreach ($key in ($S.Keys | Sort-Object)) {
        if ($key -notin 'Layout','CheckOnly','ResumeScans','SetupDone' -and (-not $Local -or $key -ne 'IdentifyUnknown')) {
            if ($S[$key] -is [Collections.IDictionary]) {
                $ordered = [ordered]@{}
                foreach ($child in ($S[$key].Keys | Sort-Object)) { $ordered[$child] = $S[$key][$child] }
                $settings[$key] = $ordered
            } else { $settings[$key] = $S[$key] }
        }
    }
    $version = if ($Local) { 'LocalAnalysisSchema-1' } else { Get-Sha256 $script:ScriptPath }
    Get-TextHash ($version + ($settings | ConvertTo-Json -Depth 6 -Compress))
}
function Get-CheckpointPath([string]$Path) { Join-Path (Join-Path (Get-WorkDir) 'scan-cache') ((Get-TextHash $Path) + '.clixml') }
function Write-AtomicClixml($Value, [string]$Path) {
    [void][IO.Directory]::CreateDirectory((LongP (Split-Path $Path)))
    $tmp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $Value | Export-Clixml -LiteralPath $tmp -Depth 12
        if ([IO.File]::Exists((LongP $Path))) { [IO.File]::Replace((LongP $tmp),(LongP $Path),[NullString]::Value) }
        else { [IO.File]::Move((LongP $tmp),(LongP $Path)) }
    }
    finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp } }
}
function Write-ScanCheckpoint($r) {
    if (-not $S.ResumeScans -or -not $r.ScanFingerprint) { return }
    $f = [IO.FileInfo]::new((LongP $r.FullName))
    if (-not $f.Exists -or $f.Length -ne $r.Length -or $f.LastWriteTimeUtc -ne $r.LastWriteUtc) { throw 'File changed during scan; checkpoint not saved' }
    try { Write-AtomicClixml ([pscustomobject]@{ Schema = 1; Context = (Get-ScanContext -Local); Result = $r }) (Get-CheckpointPath $r.FullName) }
    catch { Write-Warning "Cannot save scan progress for '$($r.FileName)': $($_.Exception.Message)" }
}
function Read-ScanCheckpoint([IO.FileInfo]$File) {
    if (-not $S.ResumeScans) { return $null }
    $path = Get-CheckpointPath ([RomSorter.RomTools]::Plain($File.FullName))
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { $saved = Import-Clixml -LiteralPath $path }
    catch { Write-Warning "Unreadable scan checkpoint '$path'; checking again: $($_.Exception.Message)"; return $null }
    $r = $saved.Result
    if ($saved.Schema -ne 1 -or $saved.Context -ne (Get-ScanContext -Local) -or -not $r.PSObject.Properties['IdentificationStatus'] -or
        -not (Test-SamePath $r.FullName ([RomSorter.RomTools]::Plain($File.FullName))) -or
        $r.Length -ne $File.Length -or $r.LastWriteUtc -ne $File.LastWriteTimeUtc -or -not $r.ScanFingerprint) { return $null }
    if ($r.Console -eq '-' -or $r.Header -eq 'Invalid' -or $r.Category -eq 'Unknown_Check_Manually' -or
        "$($r.Notes) $($r.Reason) $($r.Threats)" -match '(?i)failed|cannot read|error while checking|incomplete') { return $null }
    if ((Get-Sha256 $File.FullName) -ine $r.ScanFingerprint) { return $null }
    $r.Cands = [Collections.ArrayList]@($r.Cands); $r.Resumed = $true
    $r
}
function Copy-MovedCheckpoint($r) {
    if (-not $S.ResumeScans -or -not $r.ScanFingerprint) { return }
    $path = Get-CheckpointPath $r.FullName
    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $saved = Import-Clixml -LiteralPath $path
        if ($saved.Schema -ne 1 -or $saved.Result.ScanFingerprint -ine $r.ScanFingerprint) { return }
        $file = [IO.FileInfo]::new((LongP $r.Target))
        if (-not $file.Exists -or $file.Length -ne $saved.Result.Length) { throw 'Moved file does not match checkpoint size' }
        $saved.Result.FullName = $r.Target; $saved.Result.Folder = Split-Path $r.Target
        $saved.Result.LastWriteUtc = $file.LastWriteTimeUtc
        Write-AtomicClixml $saved (Get-CheckpointPath $r.Target)
    } catch { Write-Warning "Cannot transfer saved local check for '$($r.FileName)': $($_.Exception.Message); it will be checked again." }
}
function Save-CompletedScan($Results) {
    $flat = @(
        foreach ($r in $Results) {
            $copy = $r | Select-Object * -ExcludeProperty Lead,SetMembers
            $copy | Add-Member NoteProperty SavedLead $(if ($r.Lead) { $r.Lead.FullName } else { '' })
            $copy | Add-Member NoteProperty SavedMembers @($(if ($r.PSObject.Properties['SetMembers']) { $r.SetMembers | ForEach-Object FullName }))
            $copy
        }
    )
    try { Write-AtomicClixml ([pscustomobject]@{ Context = (Get-ScanContext); Results = $flat; CompletedUtc = [DateTime]::UtcNow }) (Join-Path (Get-WorkDir) 'last-check.clixml') }
    catch { Write-Warning "Cannot save completed check: $($_.Exception.Message)" }
}
function Restore-CompletedScan {
    $path = Join-Path (Get-WorkDir) 'last-check.clixml'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { $saved = Import-Clixml -LiteralPath $path }
    catch { Write-Warning "Cannot restore last check: $($_.Exception.Message)"; return $null }
    if ($saved.Context -ne (Get-ScanContext)) { return $null }
    if (-not (Test-CurrentInventory $saved.Results)) { return $null }
    $map = New-PathMap
    foreach ($r in $saved.Results) {
        $f = [IO.FileInfo]::new((LongP $r.FullName))
        if (-not $f.Exists -or $f.Length -ne $r.Length -or $f.LastWriteTimeUtc -ne $r.LastWriteUtc) { Write-Warning 'Saved check is stale; run Check files to refresh it.'; return $null }
        $r | Add-Member NoteProperty Lead $null -Force
        $map[$r.FullName] = $r
    }
    foreach ($r in $saved.Results) {
        if ($r.SavedLead) { $r.Lead = $map[$r.SavedLead] }
        if ($r.SavedMembers.Count) { $r | Add-Member NoteProperty SetMembers @($r.SavedMembers | ForEach-Object { $map[$_] }) -Force }
    }
    Write-Host "  Restored last check ($($saved.CompletedUtc)); antivirus statuses are historical, not a new scan." -ForegroundColor Yellow
    Set-Targets $saved.Results
    $saved.Results
}

# ===================================================================== UNPACKING ARCHIVES (malware check first, then extract)
function Remove-Tree([string]$Path) {
    $lp = LongP $Path
    if (-not [IO.Directory]::Exists($lp)) { return }
    try {
        foreach ($f in [IO.Directory]::EnumerateFiles($lp, '*', 'AllDirectories')) { [IO.File]::SetAttributes($f, 'Normal') }
        [IO.Directory]::Delete($lp, $true)
    } catch { }
}
function Get-TreeFiles([string]$Path) {
    $base = Get-DirectoryPrefix $Path
    @([IO.Directory]::EnumerateFiles((LongP $Path), '*', 'AllDirectories') | ForEach-Object {
            $p = [RomSorter.RomTools]::Plain($_); [pscustomobject]@{ Full = $p; Rel = $p.Substring($base.Length); Length = ([IO.FileInfo]::new($_)).Length } })
}

function Expand-ZipSafe([string]$Zip, [string]$Dest) {
    Initialize-ArchiveBudget
    $watch = [Diagnostics.Stopwatch]::StartNew()
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $destFull = Get-DirectoryPrefix $Dest
    $fs = [IO.File]::OpenRead((LongP $Zip))
    $za = $null
    try {
        $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Read)
        Reserve-ArchiveEntries $za.Entries.Count
        $seen = New-PathMap
        foreach ($e in $za.Entries) {
            if ($watch.Elapsed.TotalSeconds -ge $S.ArchiveTimeoutSeconds) { throw 'Archive resource limit: extraction timeout' }
            $rel = Convert-RelativePath $e.FullName
            if ([IO.Path]::IsPathRooted($rel) -or $rel.Contains(':')) { throw "unsafe path inside the archive ('$($e.FullName)') is absolute or contains a stream name (zip-slip)" }
            $t = [IO.Path]::GetFullPath((Join-Path $Dest $rel))
            if (-not $t.StartsWith($destFull, $script:PathComparison)) { throw "unsafe path inside the archive ('$($e.FullName)') points outside the folder - a known attack (zip-slip)" }
            if ($seen.ContainsKey($t)) { throw "Duplicate archive path: $rel" }; $seen[$t] = $true
            if (($e.ExternalAttributes -shr 16 -band 0xF000) -eq 0xA000) { throw "unsafe path (symbolic link): $rel" }
            if (-not $e.Name) { continue }
            [void][IO.Directory]::CreateDirectory((LongP (Split-Path $t)))
            $in = $e.Open(); $out = [IO.File]::Open((LongP $t), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
            try {
                $available = [math]::Min([long]$e.Length, ($script:ArchiveBudget.MaxBytes - $script:ArchiveBudget.Bytes))
                $ms = $S.ArchiveTimeoutSeconds * 1000 - [int]$watch.ElapsedMilliseconds
                if ($ms -le 0) { throw 'Archive resource limit: extraction timeout' }
                $callback = [Action[long,long]]{ param($done,$total) Update-FileProgress 'Extracting ZIP entry' $e.FullName $done $total }
                $written = [RomSorter.RomTools]::CopyLimited($in, $out, $available, $ms, $callback)
                $script:ArchiveBudget.Bytes += $written
            } finally { $out.Dispose(); $in.Dispose() }
            if (([IO.FileInfo]::new((LongP $t))).Length -ne $e.Length) { throw "'$rel' was not unpacked completely" }
        }
    } finally { if ($za) { $za.Dispose() }; $fs.Dispose() }
}
function Expand-With7z([string]$Arc, [string]$Dest) {
    $7z = Get-SevenZip
    if (-not $7z) { throw '7-Zip is needed for this archive type (free at 7-zip.org)' }
    $r = New-Result ([IO.FileInfo]::new((LongP $Arc)))
    [void](Test-Archive $r ([IO.FileInfo]::new((LongP $Arc))))
    if ($r.Security -in 'Malicious', 'Suspicious' -or $r.Header -eq 'Invalid') { throw "unsafe path or contents in archive: $($r.Threats) $($r.Notes)" }
    Initialize-ArchiveBudget
    $entries = Get-ArchiveEntries ([IO.FileInfo]::new((LongP $Arc)))
    Reserve-ArchiveEntries $entries.Count
    [void][IO.Directory]::CreateDirectory((LongP $Dest))
    $watch = [Diagnostics.Stopwatch]::StartNew(); $seen = New-PathMap
    foreach ($entry in $entries) {
        $rel = Convert-RelativePath $entry.Name
        $target = [IO.Path]::GetFullPath((Join-Path $Dest $rel))
        if (-not (Test-ChildPath $target $Dest) -or $entry.Link -or $entry.Encrypted -or $rel -match '(^[\\/]|:|(^|[\\/])\.\.([\\/]|$))') { throw "unsafe path or encrypted entry: $rel" }
        if ($seen.ContainsKey($target)) { throw "Duplicate archive path: $rel" }; $seen[$target] = $true
        $ms = $S.ArchiveTimeoutSeconds * 1000 - [int]$watch.ElapsedMilliseconds
        if ($ms -le 0) { throw 'Archive resource limit: extraction timeout' }
        [void][IO.Directory]::CreateDirectory((LongP (Split-Path $target)))
        $stream = [IO.File]::Open((LongP $target),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            $available = [math]::Min([long]$entry.Size, ($script:ArchiveBudget.MaxBytes - $script:ArchiveBudget.Bytes))
            $written = Invoke-Bounded7z @('x','-so','-spd','-p-','--',([RomSorter.RomTools]::Plain($Arc)),$entry.Name) $stream $available $ms
            $script:ArchiveBudget.Bytes += $written
            if ($written -ne $entry.Size) { throw "Archive entry length mismatch: $rel" }
        } finally { $stream.Dispose() }
    }
}

function Assert-ArchiveSettings {
    foreach ($item in @(@('ArchiveMaxMB',1,1048576), @('ArchiveMaxEntries',1,1000000), @('ArchiveMaxDepth',0,32), @('ArchiveTimeoutSeconds',1,86400))) {
        $value = 0L
        if (-not [long]::TryParse([string]$S[$item[0]],[ref]$value) -or $value -lt $item[1] -or $value -gt $item[2]) { throw "Invalid archive setting '$($item[0])'; expected $($item[1])..$($item[2])" }
    }
}
function Initialize-ArchiveBudget {
    Assert-ArchiveSettings
    if (-not $script:ArchiveBudget) { $script:ArchiveBudget = @{ Bytes = 0L; Entries = 0L; MaxBytes = [long]$S.ArchiveMaxMB * 1MB; MaxEntries = [long]$S.ArchiveMaxEntries } }
}
function Reserve-ArchiveEntries([long]$Count) {
    Initialize-ArchiveBudget
    if ($Count -lt 0 -or $Count -gt $script:ArchiveBudget.MaxEntries - $script:ArchiveBudget.Entries) { throw 'Archive resource limit: cumulative entry count exceeded' }
    $script:ArchiveBudget.Entries += $Count
}
function Invoke-Bounded7z([string[]]$Arguments, [IO.Stream]$Output, [long]$MaxBytes, [int]$Milliseconds) {
    Assert-ArchiveSettings
    if ($Milliseconds -le 0) { throw 'Archive resource limit: extraction timeout' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Get-SevenZip; $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.Arguments = ($Arguments | ForEach-Object { [RomSorter.RomTools]::QuoteArgument($_) }) -join ' '
    $process = New-Object Diagnostics.Process; $process.StartInfo = $start; $started = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $started = $process.Start()
        if (-not $started) { throw 'Could not start 7-Zip' }
        $stderr = $process.StandardError.ReadToEndAsync()
        $callback = [Action[long,long]]{ param($done,$total) Update-FileProgress '7-Zip stream (bounded output)' ($Arguments -join ' ') $done -1 }
        $written = [RomSorter.RomTools]::CopyLimited($process.StandardOutput.BaseStream,$Output,$MaxBytes,$Milliseconds,$callback)
        $remaining = [math]::Max(0,$Milliseconds - [int]$watch.ElapsedMilliseconds)
        if (-not $process.WaitForExit($remaining)) { throw 'Archive resource limit: extraction timeout' }
        if ($process.ExitCode -ne 0) { throw "7-Zip failed ($($process.ExitCode)): $($stderr.Result)" }
        $written
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}

# every check that must pass BEFORE an archive is unpacked; returns $null when it is safe
function Test-ArchiveSafety([IO.FileInfo]$File, [string]$MbKey, [string]$VtKey) {
    $r = New-Result $File
    if ($File.Name.IndexOf([char]0x202E) -ge 0) { return @{ Block = 'Malicious'; Why = 'the archive name hides its real extension with an invisible right-to-left character (malware trick)' } }
    $con = Test-Archive $r $File
    if ($r.Security -in 'Malicious', 'Suspicious') { return @{ Block = $r.Security; Why = $r.Threats } }
    if ($r.Header -eq 'Invalid') { return @{ Skip = "cannot be read ($($r.Notes))" } }
    if ($con -and $con.Kind -eq 'arcade') { return @{ Skip = "$($con.Name) set - the emulator needs it packed with its dependencies, so it is kept as it is" } }
    if ($r.Notes -match 'Password-protected') { return @{ Skip = 'password-protected, so it cannot be checked for malware' } }
    if ((Get-ArchiveType $File) -ne '.zip' -and -not (Get-SevenZip)) { return @{ Skip = "$($File.Extension) needs 7-Zip to unpack (free at 7-zip.org)" } }
    $size = 0L
    try {
        Initialize-ArchiveBudget
        $en = Get-ArchiveEntries $File
        if ($null -eq $en) { return @{ Skip = 'Archive contents could not be inspected' } }
        foreach ($e in $en) {
            if ($e.Size -lt 0 -or $e.Size -gt $script:ArchiveBudget.MaxBytes - $script:ArchiveBudget.Bytes - $size) { return @{ Skip = 'Archive resource limit: cumulative extracted byte limit exceeded' } }
            $size += $e.Size
        }
        if ($en.Count -gt $script:ArchiveBudget.MaxEntries - $script:ArchiveBudget.Entries) { return @{ Skip = 'Archive resource limit: cumulative entry count exceeded' } }
    } catch { return @{ Skip = "Archive preflight failed: $($_.Exception.Message)" } }
    $free = 0L; try { $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($S.RootFolder))).AvailableFreeSpace } catch { $free = [long]::MaxValue }
    if ($size + 200MB -gt $free) { return @{ Skip = "not enough free disk space (needs $([math]::Round($size / 1MB)) MB)" } }
    if ($S.DefenderScan) {
        $d = Invoke-AntivirusScan $File.FullName
        if ($d.Hits.Count) { return @{ Block = 'Malicious'; Why = "$script:AntivirusName detected '$(@($d.Hits.Values)[0])' in the archive" } }
        if (-not $d.Available) { return @{ Skip = "$script:AntivirusName did not complete: $($d.Message)" } }
    }
    if ($MbKey -or ($VtKey -and $S.OnlineCheck -ne 'Off')) {
        $sha = ''; try { $sha = Get-Sha256 $File.FullName } catch { }
        if ($sha -and $MbKey) {
            $v = Get-Cached "mb:$sha" 7; if (-not $v) { $v = Invoke-MbLookup $sha $MbKey; if ($v.Status -in 'Found', 'Unknown') { (Get-OnlineCache)["mb:$sha"] = $v } }
            if ($v.Status -eq 'Found') { return @{ Block = 'Malicious'; Why = "MalwareBazaar lists this archive as known malware$(if ($v.Signature) { " ('$($v.Signature)')" })" } }
        }
        if ($sha -and $VtKey -and $S.OnlineCheck -ne 'Off') {
            $v = Get-Cached "vt:$sha"
            if (-not $v) { $v = Invoke-VtLookup $sha $VtKey; if ($v.Status -in 'Found', 'Unknown') { (Get-OnlineCache)["vt:$sha"] = $v }; Wait-RomProgress $S.VtDelay 'VirusTotal' }
            if ($v.Status -eq 'Found' -and $v.Malicious -ge 2) { return @{ Block = 'Malicious'; Why = "VirusTotal: $($v.Malicious) of $($v.Total) antivirus engines flag this archive" } }
        }
    }
    $null
}

function Invoke-Unpack { Invoke-ProgressTask 'Unpacking' { Invoke-UnpackCore } }
function Invoke-UnpackCore {
    $script:ArchiveBudget = $null; Initialize-ArchiveBudget
    $root = Get-DirectoryPath $S.RootFolder
    $wd = Get-WorkDir; $stage = Join-Path $wd 'unpacking'; [void][IO.Directory]::CreateDirectory((LongP $stage))
    if (-not $script:UnpackBlocked) { $script:UnpackBlocked = New-PathMap }
    $queue = New-Object Collections.Queue
    foreach ($e in @(Get-ScanFiles)) { if (-not $e.Prot -and (Get-ArchiveType $e.File)) { $queue.Enqueue(@{ Path = [RomSorter.RomTools]::Plain($e.File.FullName); Depth = 0 }) } }
    if (-not $queue.Count) { Write-Host '  No archives (.zip .7z .rar .gz .tar) found - nothing to unpack.' -ForegroundColor Green; return }
    $total = $queue.Count
    Write-Host "  Found $total archive(s). Each one is checked for malware BEFORE it is unpacked." -ForegroundColor DarkCyan
    if (-not (Get-SevenZip)) { Write-Host '  7-Zip not found: .zip files are unpacked, .7z/.rar/.gz/.tar are skipped (install 7-Zip to unpack those too).' -ForegroundColor Yellow }
    $mbKey = Get-MbKey; $vtKey = Get-VtKey
    $logPath = Join-Path $wd ("Run-{0}-unpack.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'))
    $w = New-Object IO.StreamWriter((LongP $logPath), $false, (New-Object Text.UTF8Encoding $true)); $w.AutoFlush = $true
    $w.WriteLine('"Timestamp","FileName","Console","Category","Security","Action","OriginalPath","CurrentPath","SHA256","ArchiveSHA256"')
    $ok = 0; $nFiles = 0; $blocked = New-Object Collections.ArrayList; $skipped = New-Object Collections.ArrayList; $i = 0
    try {
        while ($queue.Count) {
            $it = $queue.Dequeue(); $i++
            $f = [IO.FileInfo]::new((LongP $it.Path)); $name = $f.Name
            Update-RomProgress -Phase 'Inspecting and extracting archives' -Done ($i-1) -Total $total -Unit archives -Current $it.Path -Indeterminate -Detail "Queue can grow: extracted $ok | blocked $($blocked.Count) | skipped $($skipped.Count) | $([math]::Round($script:ArchiveBudget.Bytes/1MB,1)) MB streamed"
            $row = [pscustomobject]@{ FileName = $name; Console = ''; Category = 'Archive'; Security = 'Clean'; ArchiveProofHash = '' }
            $chk = Test-ArchiveSafety $f $mbKey $vtKey
            if ($chk -and $chk.Block) { $script:UnpackBlocked[$it.Path] = @{ Level = $chk.Block; Why = $chk.Why }; [void]$blocked.Add("$name - $($chk.Why)"); continue }
            if ($chk -and $chk.Skip) { [void]$skipped.Add("$name - $($chk.Skip)"); continue }
            $row.ArchiveProofHash = Get-Sha256 $it.Path

            $tmp = Join-Path $stage ([string]$i); Remove-Tree $tmp
            try {
                if ((Get-ArchiveType $f) -eq '.zip') {
                    Expand-ZipSafe $it.Path $tmp
                } else { Expand-With7z $it.Path $tmp }
            } catch {
                Remove-Tree $tmp
                if ($_.Exception.Message -match 'zip-slip|unsafe path') { $script:UnpackBlocked[$it.Path] = @{ Level = 'Malicious'; Why = $_.Exception.Message }; [void]$blocked.Add("$name - $($_.Exception.Message)") }
                else { [void]$skipped.Add("$name - could not unpack: $($_.Exception.Message)") }
                continue
            }
            $files = @(Get-TreeFiles $tmp)
            if (-not $files.Count) { Remove-Tree $tmp; [void]$skipped.Add("$name - empty"); continue }
            if ((Get-Sha256 $it.Path) -ine $row.ArchiveProofHash) { Remove-Tree $tmp; [void]$skipped.Add("$name - original archive changed during extraction; copies discarded"); continue }
            # second check on the unpacked files, still in the private staging folder
            $bad = @($files | Where-Object { $script:DangerExt -contains [IO.Path]::GetExtension($_.Rel).ToLower() -or $_.Rel.IndexOf([char]0x202E) -ge 0 })
            if ($bad.Count) { Remove-Tree $tmp; $why = "contains a program ($($bad[0].Rel))"; $script:UnpackBlocked[$it.Path] = @{ Level = 'Suspicious'; Why = $why }; [void]$blocked.Add("$name - $why"); continue }
            if ($S.DefenderScan) {
                $d = Invoke-AntivirusScan $tmp
                $gone = @($files | Where-Object { -not [IO.File]::Exists((LongP $_.Full)) })
                if ($d.Hits.Count -or $gone.Count) {
                    Remove-Tree $tmp
                    $why = if ($d.Hits.Count) { "$script:AntivirusName detected '$(@($d.Hits.Values)[0])' in the unpacked files" } else { "$script:AntivirusName removed an unpacked file (threat found)" }
                    $script:UnpackBlocked[$it.Path] = @{ Level = 'Malicious'; Why = $why }; [void]$blocked.Add("$name - $why"); continue
                }
                if (-not $d.Available) { Remove-Tree $tmp; [void]$skipped.Add("$name - $script:AntivirusName did not complete: $($d.Message)"); continue }
            }
            # put the files next to the archive, names unchanged; a subfolder named after the archive when a name is taken
            $dest = $f.DirectoryName; $dest = [RomSorter.RomTools]::Plain($dest)
            if (@($files | Where-Object { Test-PathLP (Join-Path $dest $_.Rel) }).Count) {
                $base = Join-Path $dest (Get-SafeName ([IO.Path]::GetFileNameWithoutExtension($name))); $dest = $base; $n = 2
                while (Test-PathLP $dest) { $dest = "$base ($n)"; $n++ }
            }
            $placed = New-Object Collections.ArrayList; $placedHashes = New-PathMap; $err = $null
            foreach ($x in $files) {
                $t = Join-Path $dest $x.Rel
                try {
                    $hash = Get-Sha256 $x.Full
                    $row.FileName = Split-Path $t -Leaf
                    Write-JournalRow $w (New-JournalRow $row 'PlannedExtraction' $it.Path $t $hash)
                    Move-OneFile $x.Full $t $hash
                    [void]$placed.Add($t); $placedHashes[$t] = $hash
                    Write-JournalRow $w (New-JournalRow $row 'Extracted' $it.Path $t)
                }
                catch { $err = "$($x.Rel): $($_.Exception.Message)"; break }
            }
            if ($err) {
                foreach ($t in $placed) {
                    try {
                        if ((Get-Sha256 $t) -ine $placedHashes[$t]) { throw 'Placed copy changed; kept for manual recovery' }
                        [IO.File]::Delete((LongP $t)); Write-JournalRow $w (New-JournalRow $row 'RolledBack' $it.Path $t)
                    } catch { Write-Warning "Unpack rollback kept '$t': $($_.Exception.Message). Use the recovery journal." }
                }
                Remove-Tree $tmp; [void]$skipped.Add("$name - could not place the files ($err); rollback attempted; recovery journal retained"); continue
            }
            Remove-Tree $tmp
            $row.FileName = $name
            Write-JournalRow $w (New-JournalRow $row 'ExtractionCompleted' $it.Path $it.Path $row.ArchiveProofHash)
            # Keep every processed archive out of the active tree, including inner ZIPs.
            # This prevents extracting the same inner archive on subsequent runs.
            $fdir = Get-DirectoryPath $f.DirectoryName
            $rel = if (Test-ChildPath $fdir $root) { $fdir.Substring((Get-DirectoryPrefix $root).Length) } else { '' }
            $adir = Join-Path (Join-Path $root $S.UnpackedFolder) $rel; $abase = $adir; $n = 2
            while (Test-PathLP (Join-Path $adir $name)) { $adir = "$abase ($n)"; $n++ }
            try {
                $savedArchive = Join-Path $adir $name
                Write-JournalRow $w (New-JournalRow $row 'PlannedMove' $it.Path $savedArchive $row.ArchiveProofHash)
                Move-OneFile $it.Path $savedArchive $row.ArchiveProofHash
                Write-JournalRow $w (New-JournalRow $row 'Moved' $it.Path $savedArchive)
            }
            catch { [void]$skipped.Add("$name - unpacked, but the archive itself could not be moved away ($($_.Exception.Message))") }
            $ok++; $nFiles += $placed.Count
            foreach ($t in $placed) {
                if (Get-ArchiveType ([IO.FileInfo]::new((LongP $t)))) {
                    if ($it.Depth -lt $S.ArchiveMaxDepth) { $queue.Enqueue(@{ Path = $t; Depth = $it.Depth + 1 }); $total++ }
                    else { [void]$skipped.Add("$(Split-Path $t -Leaf) - nested archive depth limit reached; kept packed") }
                }
            }
        }
    } finally { $w.Dispose(); Complete-FileProgress; Remove-Tree $stage; Save-OnlineCache }
    Set-ProgressCounter 'Extracted' $ok; Set-ProgressCounter 'Files' $nFiles; Set-ProgressCounter 'Kept packed' ($blocked.Count+$skipped.Count); Set-ProgressCounter 'Warnings' ($blocked.Count+$skipped.Count)
    if (-not $ok -and @(Import-Csv -LiteralPath $logPath).Count -eq 0) { Remove-Item -LiteralPath $logPath }
    Write-Host ''
    Write-Host "  Unpacked $ok archive(s) -> $nFiles file(s). Originals kept in $($S.UnpackedFolder)\. Use menu C for verified archive cleanup." -ForegroundColor Green
    if ($blocked.Count) {
        Write-Host "  NOT unpacked - possibly malicious ($($blocked.Count)), will be quarantined:" -ForegroundColor Red
        $blocked | Select-Object -First 25 | ForEach-Object { Write-Wrapped $_ 6 'Red' '- ' }
    }
    if ($skipped.Count) {
        Write-Host "  Not unpacked - left as they are ($($skipped.Count)):" -ForegroundColor Yellow
        $skipped | Select-Object -First 25 | ForEach-Object { Write-Wrapped $_ 6 'Yellow' '- ' }
    }
}

function Show-Library($Results) {
    Write-Host ''
    Write-Host '  YOUR LIBRARY NOW' -ForegroundColor Cyan
    $good = @($Results | Where-Object { $_.Category -eq 'Original' -and $_.Console -ne '-' -and -not $_.Lead -and $_.Action -notlike 'Error*' })
    foreach ($g in ($good | Group-Object Console | Sort-Object Name)) {
        $c = Get-Con $g.Name
        Write-Host ('    {0,-36} {1,6} valid game(s)   {2}' -f $c.Name, $g.Count, (Get-ConsoleDir $g.Group[0])) -ForegroundColor Green
    }
    if (-not $good.Count) { Write-Host '    No verified games found.' -ForegroundColor Yellow }
    $rej = @($Results | Where-Object { $_.Category -notin 'Original', 'Quarantine', 'Duplicate', 'Companion', 'Not_A_ROM', 'Protected', 'BIOS', 'Kept', 'Other_Console', 'Archive', 'Executable' -and -not $_.Lead }).Count
    $q = @($Results | Where-Object Category -eq 'Quarantine').Count; $d = @($Results | Where-Object Category -eq 'Duplicate').Count
    $stay = @($Results | Where-Object { $_.Category -in 'Archive', 'Executable', 'BIOS', 'Protected', 'Not_A_ROM' -and -not $_.Target -and $_.Action -ne 'Moved' }).Count
    if ($rej -and $S.Layout -eq 'Validity') { Write-Host "    $rej other file(s) sorted into <console>\Modified, Non-Retail, Unverified, Invalid" -ForegroundColor Magenta }
    elseif ($rej) { Write-Host "    $rej not valid (demo, homebrew, hack, unverified...) -> $($S.RejectFolder)\<console>\<reason>" -ForegroundColor Magenta }
    if ($q) { Write-Host "    $q possibly malicious -> $($S.QuarantineFolder)\  (do not open these)" -ForegroundColor Red }
    if ($d) { Write-Host "    $d duplicate(s) -> $($S.DuplicateFolder)\" -ForegroundColor DarkYellow }
    if ($stay) { Write-Host "    $stay other file(s) left where they were (BIOS, programs, archives that could not be unpacked, non-ROM files)" -ForegroundColor DarkGray }
    Write-Host '    File names were not changed. Undo everything: main menu > 7 (newest run first).' -ForegroundColor DarkGray
}

function Invoke-DoEverything([switch]$NoConfirm) {
    if (-not $NoConfirm) {
        Show-Banner; Write-Host ''
        Write-Host '  FULL WORKFLOW - unpack, check, and sort automatically' -ForegroundColor Cyan
        Write-Host "  Folder: $($S.RootFolder)  (every subfolder)" -ForegroundColor Yellow
        Write-Host ''
        Write-Wrapped "1. UNPACK - every .zip/.7z/.rar is first checked for malware (content, $script:AntivirusName, MalwareBazaar/VirusTotal if you set a key) and only then unpacked. The original archives are kept in a separate folder." 2 'Gray'
        Write-Wrapped '2. CHECK - every file: malware, valid header, original dump (No-Intro/Redump), real released game (libretro, Hasheous, IGDB, TheGamesDB, RetroAchievements).' 2 'Gray'
        Write-Wrapped "3. SORT - use the selected layout: $(Get-LayoutText). Possibly malicious files go to $($S.QuarantineFolder)\ and duplicates to $($S.DuplicateFolder)\." 2 'Gray'
        Write-Wrapped "This workflow enables automatic DAT downloads, $script:AntivirusName, and Hasheous if it was off. Check and sort actions use your existing verification settings." 2 'DarkGray'
        Write-Wrapped 'File names are never changed, nothing is overwritten or deleted, and every step can be undone.' 2 'DarkGray'
        Write-Host ''
        if (-not (Confirm-Action 'Start?')) { return }
    }
    $S.CheckOnly = $false; $S.RejectsOutside = $true; $S.AutoDat = $true; $S.DefenderScan = $true
    if ($S.Hasheous -eq 'Off') { $S.Hasheous = 'All' }
    Save-Settings
    Invoke-ProgressTask 'Full workflow' {
        $previousWorkflow = $script:RomWorkflow
        $script:RomWorkflow = $script:RomProgress
        try {
            Write-Host ''; Write-Host '  STEP 1/3 - Unpacking archives' -ForegroundColor Cyan
            $script:LastResults = $null
            Invoke-Unpack
            Write-Host ''; Write-Host '  STEP 2/3 - Checking every file' -ForegroundColor Cyan
            $res = @(Invoke-Scan)
            if (-not $res.Count) { return }
            Show-Summary $res
            Write-Host ''; Write-Host '  STEP 3/3 - Sorting' -ForegroundColor Cyan
            Invoke-Organize $res
            $p = Export-Report $res 'Applied'
            Show-Library $res
            Write-Host "  Full report: $p" -ForegroundColor DarkGray
            $script:LastResults = $null
        } finally { $script:RomWorkflow = $previousWorkflow }
    } -Stages @('Unpacking','Checking','Sorting')
}

# ===================================================================== MOVING / UNDO (journaled, long-path safe, sets move together)
function Write-JournalRow($w, $Row) { $w.WriteLine((($Row | ConvertTo-Csv -NoTypeInformation) | Select-Object -Skip 1)) }
function New-JournalRow($r, [string]$Action, [string]$From, [string]$To, [string]$ExpectedHash = '') {
    $hash = if ($ExpectedHash) { $ExpectedHash } elseif ($To -and [IO.File]::Exists((LongP $To))) { Get-Sha256 $To } elseif ($Action -eq 'PlannedMove') { Get-Sha256 $From } else { '' }
    $archiveHash = if ($Action -in 'Extracted','PlannedExtraction') { if ($r.ArchiveProofHash) { $r.ArchiveProofHash } else { Get-Sha256 $From } } else { '' }
    [pscustomobject]@{ Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); FileName = $r.FileName; Console = $r.Console; Category = $r.Category
        Security = $r.Security; Action = $Action; OriginalPath = $From; CurrentPath = $To; SHA256 = $hash; ArchiveSHA256 = $archiveHash }
}
function Move-OneFile([string]$From, [string]$To, [string]$ExpectedHash = '') {
    $src = LongP $From; $dst = LongP $To
    if (-not [IO.File]::Exists($src)) { throw 'file no longer exists' }
    if ([IO.File]::Exists($dst) -or [IO.Directory]::Exists($dst)) { throw 'name already exists in destination' }
    $len = ([IO.FileInfo]::new($src)).Length
    $hash = Get-Sha256 $From
    if ($ExpectedHash -and $hash -ine $ExpectedHash) { throw 'Source content changed since verification; move cancelled' }
    [void][IO.Directory]::CreateDirectory((LongP (Split-Path $To)))
    [IO.File]::Move($src, $dst)
    $fi = [IO.FileInfo]::new($dst)
    if (-not $fi.Exists -or $fi.Length -ne $len -or (Get-Sha256 $To) -ine $hash) {
        if ([IO.File]::Exists($dst) -and -not [IO.File]::Exists($src)) { [IO.File]::Move($dst, $src) }
        throw 'SHA-256/size verification failed after move; destination restored to source when possible'
    }
}
function Remove-EmptyDirs([string[]]$Dirs) {
    $root = Get-DirectoryPath $S.RootFolder; $n = 0
    foreach ($d0 in ($Dirs | Select-Object -Unique | Sort-Object Length -Descending)) {
        $d = $d0
        while ($d -and (Test-ChildPath $d $root)) {
            if ($script:ProtectedDirs -and $script:ProtectedDirs.ContainsKey($d)) { break }
            $lp = LongP $d
            if (-not [IO.Directory]::Exists($lp)) { $d = Split-Path $d; continue }
            $left = @([IO.Directory]::EnumerateFileSystemEntries($lp) | Where-Object { (Split-Path $_ -Leaf) -notin 'desktop.ini', 'Thumbs.db' })
            if ($left.Count) { break }
            try { foreach ($j in [IO.Directory]::EnumerateFiles($lp)) { [IO.File]::SetAttributes($j, 'Normal'); [IO.File]::Delete($j) }; [IO.Directory]::Delete($lp); $n++ } catch { break }
            $d = Split-Path $d
        }
    }
    $n
}

function Invoke-Organize($Results) { Invoke-ProgressTask 'Sorting' { Invoke-OrganizeCore $Results } }
function Invoke-OrganizeCore($Results) {
    if (-not (Test-SortResults $Results)) { Set-ProgressCounter 'Warnings' 1; Set-ProgressCounter 'Moved' 0; return }
    $wd = Get-WorkDir; [void][IO.Directory]::CreateDirectory((LongP $wd))
    $logPath = Join-Path $wd ("Run-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'))
    $todo = @($Results | Where-Object { $_.Target })
    if (-not $todo.Count) { Write-Host '  Nothing to move.' -ForegroundColor Green; return }
    # units: a ROM with its companions, or a whole disc set - all or nothing
    $units = New-PathMap -Ordered
    foreach ($r in $todo) { $k = (Get-Top $r).FullName; if (-not $units.Contains($k)) { $units[$k] = New-Object Collections.ArrayList }; [void]$units[$k].Add($r) }
    $w = New-Object IO.StreamWriter((LongP $logPath), $false, (New-Object Text.UTF8Encoding $true)); $w.AutoFlush = $true
    $w.WriteLine('"Timestamp","FileName","Console","Category","Security","Action","OriginalPath","CurrentPath","SHA256","ArchiveSHA256"')
    $moved = 0; $failed = New-Object Collections.ArrayList; $srcDirs = New-Object Collections.ArrayList; $i = 0
    $processedBytes = 0L; $totalMoveBytes = [double](($todo | Measure-Object Length -Sum).Sum)
    try {
        foreach ($k in $units.Keys) {
            $unit = @($units[$k]); $done = New-Object Collections.ArrayList; $err = $null
            foreach ($r in $unit) {
                $i++; Update-RomProgress -Phase 'Moving and verifying files' -Done $processedBytes -Total $totalMoveBytes -Unit bytes -Current $r.FullName -Detail "$($i-1)/$($todo.Count) files; SHA256 before/after move"
                try {
                    $expected = if ($r.ScanFingerprint) { $r.ScanFingerprint } else { $r.SHA256 }
                    Write-JournalRow $w (New-JournalRow $r 'PlannedMove' $r.FullName $r.Target $expected)
                    Move-OneFile $r.FullName $r.Target $expected
                    [void]$done.Add($r); Write-JournalRow $w (New-JournalRow $r 'Moved' $r.FullName $r.Target)
                    $processedBytes += $r.Length
                    Update-RomProgress -Phase 'Moving and verifying files' -Done $processedBytes -Total $totalMoveBytes -Unit bytes -Current $r.Target -Detail "$i/$($todo.Count) files verified"
                }
                catch { $err = "$($r.FileName): $($_.Exception.Message)"; break }
            }
            if ($err) {
                foreach ($r in $done) {
                    try { Move-OneFile $r.Target $r.FullName; Write-JournalRow $w (New-JournalRow $r 'RolledBack' $r.FullName $r.Target) }
                    catch { Write-JournalRow $w (New-JournalRow $r 'Moved' $r.FullName $r.Target); [void]$failed.Add("ROLLBACK FAILED for $($r.FileName) - it is at $($r.Target) (undo will restore it)") }
                }
                foreach ($r in $unit) { if ($done -notcontains $r -or $r.Action -ne 'Moved') { $r.Action = "Error - $err" } }
                [void]$failed.Add($(if ($unit.Count -gt 1) { "$err (whole set of $($unit.Count) files left in place)" } else { $err }))
                continue
            }
            foreach ($r in $unit) { Copy-MovedCheckpoint $r; $r.Action = 'Moved'; [void]$srcDirs.Add($r.Folder); $moved++ }
        }
    } finally { $w.Dispose(); Complete-FileProgress }
    Set-ProgressCounter 'Moved' $moved; Set-ProgressCounter 'Warnings' $failed.Count
    $removed = 0; if ($S.CleanEmptyFolders -and $srcDirs.Count) { $removed = Remove-EmptyDirs @($srcDirs) }
    Write-Host ''
    Write-Host "  Moved $moved file(s)." -ForegroundColor Green
    if ($removed) { Write-Host "  Removed $removed empty folder(s)." -ForegroundColor DarkGray }
    if ($failed.Count) { Write-Host "  $($failed.Count) problem(s):" -ForegroundColor Yellow; $failed | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow } }
    Write-Host "  Journal (used for undo, written before and after every move): $logPath" -ForegroundColor DarkGray
}

function Get-UndoLogs {
    $list = @()
    $wd = Get-WorkDir
    if (Test-Path -LiteralPath $wd) { $list += @(Get-ChildItem -LiteralPath $wd -Filter 'Run-*.csv' -File | Where-Object { $_.Name -notlike '*.undone.csv' } | Sort-Object Name -Descending) }
    $legacy = Join-Path $S.RootFolder 'SNES-Move-Log.csv'
    if (Test-Path -LiteralPath $legacy) { $list += Get-Item -LiteralPath $legacy }
    $list
}

function Test-CleanupPath([string]$Path) {
    if (-not $Path -or -not (Test-ChildPath $Path $S.RootFolder)) { return $false }
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        }
        if (Test-SamePath $current (Get-DirectoryPath $S.RootFolder)) { return $true }
        $current = Split-Path $current
    }
    return $false
}
function Get-CleanupRecords {
    foreach ($log in @(Get-UndoLogs)) {
        try {
            $rows = @(Import-Csv -LiteralPath $log.FullName)
            $rolled = New-PathMap
            foreach ($row in $rows) { if ($row.Action -eq 'RolledBack') { $rolled["$($row.OriginalPath)`n$($row.CurrentPath)"] = $true } }
            foreach ($row in $rows) {
                if ($row.Action -notin 'Moved','Extracted','ExtractionCompleted' -or $row.SHA256 -notmatch '^[a-fA-F0-9]{64}$') { continue }
                if ($rolled.ContainsKey("$($row.OriginalPath)`n$($row.CurrentPath)")) { continue }
                if (-not (Test-CleanupPath $row.OriginalPath) -or -not (Test-CleanupPath $row.CurrentPath)) { continue }
                $row
            }
        } catch { Write-Warning "Cleanup cannot read journal '$($log.Name)': $($_.Exception.Message). Its archives will not be eligible without other complete evidence." }
    }
}
function Test-CleanupCopy([string]$Path, [string]$Hash, $Records) {
    $queue = New-Object Collections.Queue; $queue.Enqueue($Path); $visited = New-PathMap
    while ($queue.Count) {
        $candidate = [string]$queue.Dequeue()
        if ($visited.ContainsKey($candidate)) { continue }; $visited[$candidate] = $true
        if (-not (Test-CleanupPath $candidate)) { continue }
        # A recovery archive is not an independent surviving extracted copy.
        if (-not (Test-ChildPath $candidate (Join-Path $S.RootFolder $S.UnpackedFolder)) -and
            [IO.File]::Exists((LongP $candidate)) -and (Get-Sha256 $candidate) -ieq $Hash) { return $true }
        foreach ($move in $Records) {
            if ($move.Action -eq 'Moved' -and $move.SHA256 -ieq $Hash -and (Test-SamePath $move.OriginalPath $candidate)) { $queue.Enqueue($move.CurrentPath) }
        }
    }
    return $false
}
function Test-CleanupExtraction([string]$ArchivePath, [string]$Hash, $Records, $Visited = $null) {
    if ($null -eq $Visited) { $Visited = New-PathMap }
    $key = "$ArchivePath`n$Hash"
    if ($Visited.ContainsKey($key) -or $Visited.Count -ge 64) { return $false }
    $Visited[$key] = $true
    try {
        if (-not @($Records | Where-Object { $_.Action -eq 'ExtractionCompleted' -and $_.SHA256 -ieq $Hash -and (Test-SamePath $_.OriginalPath $ArchivePath) }).Count) { return $false }
        $members = @($Records | Where-Object { $_.Action -eq 'Extracted' -and $_.ArchiveSHA256 -ieq $Hash -and (Test-SamePath $_.OriginalPath $ArchivePath) })
        if (-not $members.Count) { return $false }
        foreach ($member in $members) {
            if (Test-CleanupCopy $member.CurrentPath $member.SHA256 $Records) { continue }
            if (-not (Test-CleanupExtraction $member.CurrentPath $member.SHA256 $Records $Visited)) { return $false }
        }
        return $true
    } finally { $Visited.Remove($key) }
}
function Get-ArchiveCleanupPlan($Records) { Invoke-ProgressTask 'Cleanup preview' { Get-ArchiveCleanupPlanCore $Records } }
function Get-ArchiveCleanupPlanCore($Records) {
    $recovery = Join-Path $S.RootFolder $S.UnpackedFolder
    $seen = New-PathMap
    $cleanupCandidates = 0; $cleanupEligible = 0; $cleanupBytes = 0L
    $examined = 0
    Update-RomProgress -Phase 'Verifying processed archives and surviving copies' -Total $Records.Count -Done 0 -Unit 'journal rows' -Indeterminate
    foreach ($move in $Records) {
        $examined++
        Update-RomProgress -Phase 'Verifying processed archives and surviving copies' -Total $Records.Count -Done $examined -Unit 'journal rows' -Current $move.CurrentPath -Indeterminate -Detail 'Hashing dependencies; ETA unknown'
        if ($move.Action -ne 'Moved' -or -not (Test-ChildPath $move.CurrentPath $recovery) -or $seen.ContainsKey($move.CurrentPath)) { continue }
        if (-not [IO.File]::Exists((LongP $move.CurrentPath))) { continue }
        $seen[$move.CurrentPath] = $true
        $reason = ''; $eligible = $false; $length = 0L
        try {
            $file = [IO.FileInfo]::new((LongP $move.CurrentPath)); $length = $file.Length
            if (-not (Test-CleanupPath $move.CurrentPath)) { $reason = 'Link or path outside the library' }
            elseif ((Get-Sha256 $move.CurrentPath) -ine $move.SHA256) { $reason = 'Archive changed since extraction' }
            elseif (-not (Get-ArchiveType $file)) { $reason = 'Not a recognized compressed archive' }
            elseif (-not (Test-CleanupExtraction $move.OriginalPath $move.SHA256 $Records)) { $reason = 'Missing/changed extracted copies or incomplete extraction evidence' }
            else { $eligible = $true; $reason = 'Extracted copies verified with SHA-256' }
        } catch { $reason = "Verification failed: $($_.Exception.Message)" }
        $cleanupCandidates++
        if ($eligible) { $cleanupEligible++; $cleanupBytes += $length }
        [pscustomobject]@{ Path = $move.CurrentPath; OriginalPath = $move.OriginalPath; SHA256 = $move.SHA256; Bytes = $length; Eligible = $eligible; Reason = $reason }
    }
    Set-ProgressCounter 'Examined archives' $cleanupCandidates; Set-ProgressCounter 'Eligible' $cleanupEligible; Set-ProgressCounter 'Reclaimable MB' ([math]::Round($cleanupBytes/1MB,2))
}
function Invoke-ArchiveCleanup($Plan) { Invoke-ProgressTask 'Cleanup' { Invoke-ArchiveCleanupCore $Plan } }
function Invoke-ArchiveCleanupCore($Plan) {
    $reportPath = Join-Path (Get-WorkDir) ("Cleanup-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'))
    [void][IO.Directory]::CreateDirectory((LongP (Get-WorkDir)))
    $writer = New-Object IO.StreamWriter($reportPath,$false,(New-Object Text.UTF8Encoding $true)); $writer.AutoFlush = $true
    $writer.WriteLine('"Timestamp","Path","SHA256","Bytes","Action","Reason"')
    $deleted = 0; $freed = 0L; $examined = 0; $kept = 0
    $eligiblePlan = @($Plan | Where-Object Eligible)
    try {
        $records = @(Get-CleanupRecords)
        foreach ($item in $eligiblePlan) {
            Update-RomProgress -Phase 'Rechecking and deleting confirmed archives' -Done $examined -Total $eligiblePlan.Count -Unit archives -Current $item.Path -Detail "$deleted deleted | $([math]::Round($freed/1MB,2)) MB freed"
            $action = 'Kept'; $reason = ''
            try {
                if (-not (Test-ChildPath $item.Path (Join-Path $S.RootFolder $S.UnpackedFolder)) -or -not (Test-CleanupPath $item.Path)) { throw 'Unsafe cleanup path' }
                $proof = @($records | Where-Object { $_.Action -eq 'Moved' -and $_.SHA256 -ieq $item.SHA256 -and (Test-SamePath $_.OriginalPath $item.OriginalPath) -and (Test-SamePath $_.CurrentPath $item.Path) })
                if (-not $proof.Count -or -not (Test-CleanupExtraction $item.OriginalPath $item.SHA256 $records)) { throw 'Extracted copies no longer verified; archive kept' }
                if ((Get-Sha256 $item.Path) -ine $item.SHA256) { throw 'Archive changed after preview; kept' }
                $bytes = ([IO.FileInfo]::new((LongP $item.Path))).Length
                $before = [pscustomobject]@{ Timestamp = [DateTime]::UtcNow.ToString('o'); Path = $item.Path; SHA256 = $item.SHA256; Bytes = $bytes; Action = 'DeletePlanned'; Reason = 'User confirmed permanent cleanup; extraction undo unavailable' }
                Write-JournalRow $writer $before
                [IO.File]::Delete((LongP $item.Path))
                $deleted++; $freed += $bytes; $action = 'Deleted'; $reason = 'Verified processed archive permanently removed'
            } catch { $reason = $_.Exception.Message; $kept++; Write-Warning "Cleanup kept '$($item.Path)': $reason" }
            $examined++
            Write-JournalRow $writer ([pscustomobject]@{ Timestamp = [DateTime]::UtcNow.ToString('o'); Path = $item.Path; SHA256 = $item.SHA256; Bytes = $item.Bytes; Action = $action; Reason = $reason })
        }
    } finally { $writer.Dispose() }
    Set-ProgressCounter 'Deleted' $deleted; Set-ProgressCounter 'Freed MB' ([math]::Round($freed/1MB,2)); Set-ProgressCounter 'Kept' $kept; Set-ProgressCounter 'Warnings' $kept
    Write-Host "  Permanently deleted $deleted processed archive(s); freed $([math]::Round($freed / 1MB,2)) MB. Extraction undo is unavailable for deleted archives." -ForegroundColor Yellow
    Write-Host "  Cleanup record: $reportPath" -ForegroundColor DarkGray
}
function Show-ArchiveCleanupMenu {
    Show-Banner
    Write-Host '  CLEANUP - permanently remove verified processed archives' -ForegroundColor Cyan
    $records = @(Get-CleanupRecords)
    $plan = @(Get-ArchiveCleanupPlan $records)
    foreach ($item in $plan) { Write-Host "  $(if ($item.Eligible) { 'DELETE' } else { 'KEEP' })  $($item.Path)  - $($item.Reason)" -ForegroundColor $(if ($item.Eligible) { 'Yellow' } else { 'DarkGray' }) }
    $eligible = @($plan | Where-Object Eligible)
    if (-not $eligible.Count) { Write-Host '  No verified processed archives are eligible. Untracked archives and active ROM/arcade ZIPs are never deleted.' -ForegroundColor Gray; Wait-Key; return }
    $bytes = ($eligible | Measure-Object Bytes -Sum).Sum
    Write-Host "  Preview: $($eligible.Count) archive(s), $([math]::Round($bytes / 1MB,2)) MB reclaimable." -ForegroundColor Yellow
    Write-Wrapped 'PERMANENT deletion, not the recycle bin. Deleted originals cannot be restored and extraction undo becomes unavailable. Only recovery archives with verified extracted copies are eligible; everything is rechecked before deletion.' 2 'Red'
    Write-Host '  Older journals without complete extraction evidence are kept; a filename alone is never enough.' -ForegroundColor DarkGray
    if (Confirm-Action 'Permanently delete the eligible archives listed above?') { Invoke-ArchiveCleanup $eligible }
    Wait-Key
}

function Invoke-UndoLog([IO.FileInfo]$Log, [bool]$DoIt) { Invoke-ProgressTask $(if ($DoIt) { 'Undo' } else { 'Undo preview' }) { Invoke-UndoLogCore $Log $DoIt } }
function Invoke-UndoLogCore([IO.FileInfo]$Log, [bool]$DoIt) {
    $all = @(Import-Csv -LiteralPath $Log.FullName)
    $innerGone = New-PathMap; foreach ($x in $all) { if ($x.Action -eq 'RemovedInnerArchive') { $innerGone[$x.OriginalPath] = $true } }
    $rows = @($all | Where-Object { $_.Action -in 'Moved', 'Extracted','PlannedMove','PlannedExtraction' }); [array]::Reverse($rows)
    $seen = New-PathMap; $rolled = New-PathMap
    foreach ($x in $all) { if ($x.Action -eq 'RolledBack') { $rolled["$($x.OriginalPath)`n$($x.CurrentPath)"] = $true } }
    $ok = 0; $problems = 0; $dirs = New-Object Collections.ArrayList
    $examined = 0
    foreach ($r in $rows) {
        Update-RomProgress -Phase 'Verifying recovery journal' -Done $examined -Total $rows.Count -Unit 'journal rows' -Current $r.CurrentPath -Detail "$ok restored/eligible | $problems problems"
        $examined++
        $key = "$($r.OriginalPath)`n$($r.CurrentPath)"
        if ($seen.ContainsKey($key) -or $rolled.ContainsKey($key)) { continue }; $seen[$key] = $true
        if ($r.Action -eq 'PlannedExtraction') { $r.Action = 'Extracted' }
        if ([IO.File]::Exists((LongP $r.CurrentPath))) {
            if ($r.SHA256 -and (Get-Sha256 $r.CurrentPath) -ine $r.SHA256) {
                Write-Warning "Kept changed file '$($r.CurrentPath)': SHA-256 differs from journal; undo will not move or delete it."; $problems++; continue
            }
            if ($r.Action -eq 'Extracted' -and -not $r.SHA256) {
                Write-Warning "Kept '$($r.CurrentPath)': legacy extraction journal has no content hash; removal is not safe."; $problems++; continue
            }
        }
        if ($r.Action -eq 'Extracted') {
            # unpacked copy: removed again once its archive is back in place (so nothing can be lost)
            if (-not [IO.File]::Exists((LongP $r.CurrentPath))) { continue }
            if ($DoIt) {
                if (-not [IO.File]::Exists((LongP $r.OriginalPath)) -and -not $innerGone.ContainsKey($r.OriginalPath)) { Write-Host "  Kept $($r.CurrentPath): its archive is not back at $($r.OriginalPath)" -ForegroundColor Yellow; $problems++; continue }
                if ($r.ArchiveSHA256 -and [IO.File]::Exists((LongP $r.OriginalPath)) -and (Get-Sha256 $r.OriginalPath) -ine $r.ArchiveSHA256) {
                    Write-Warning "Kept '$($r.CurrentPath)': original archive content changed."; $problems++; continue
                }
                try { [IO.File]::SetAttributes((LongP $r.CurrentPath), 'Normal'); [IO.File]::Delete((LongP $r.CurrentPath)); [void]$dirs.Add((Split-Path $r.CurrentPath)) }
                catch { Write-Host "  Could not remove unpacked file $($r.FileName): $($_.Exception.Message)" -ForegroundColor Red; $problems++; continue }
            }
            $ok++; continue
        }
        if (-not [IO.File]::Exists((LongP $r.CurrentPath))) { if ([IO.File]::Exists((LongP $r.OriginalPath))) { continue }; Write-Host "  Missing: $($r.CurrentPath)" -ForegroundColor Yellow; $problems++; continue }
        if ([IO.File]::Exists((LongP $r.OriginalPath))) { Write-Host "  Already exists, skipped: $($r.OriginalPath)" -ForegroundColor Yellow; $problems++; continue }
        if ($DoIt) {
            try { Move-OneFile $r.CurrentPath $r.OriginalPath $r.SHA256; [void]$dirs.Add((Split-Path $r.CurrentPath)) }
            catch { Write-Host "  Could not restore $($r.FileName): $($_.Exception.Message)" -ForegroundColor Red; $problems++; continue }
        }
        $ok++
    }
    Set-ProgressCounter 'Restored / eligible' $ok; Set-ProgressCounter 'Warnings' $problems
    Update-RomProgress -Phase 'Verifying recovery journal' -Done $rows.Count -Total $rows.Count -Unit 'journal rows' -Detail "$ok restored/eligible | $problems problems" -Force
    if ($DoIt) {
        if ($dirs.Count) { [void](Remove-EmptyDirs @($dirs)) }
        Write-Host "  Restored $ok file(s)." -ForegroundColor Green
        if ($problems -eq 0) {
            $name = $Log.BaseName + '.undone.csv'
            if (Test-Path -LiteralPath (Join-Path $Log.DirectoryName $name)) { $name = $Log.BaseName + '.' + [guid]::NewGuid().ToString('N') + '.undone.csv' }
            Rename-Item -LiteralPath $Log.FullName -NewName $name
        }
        else { Write-Host "  $problems problem(s) - the log is kept so you can try again." -ForegroundColor Yellow }
    } else { Write-Host "  $ok file(s) can be restored, $problems problem(s)." -ForegroundColor Cyan }
}

# ===================================================================== DISPLAY
function Write-Line([string]$Text = '', [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }

function Show-Banner {
    Clear-Host
    $w = 66; $h = [string][char]0x2550
    Write-Host ''
    Write-Host ("  " + [char]0x2554 + ($h * $w) + [char]0x2557) -ForegroundColor DarkCyan
    Write-Host ("  " + [char]0x2551 + "   ROM SORTER v3  -  verify, secure and sort ROMs per emulator".PadRight($w) + [char]0x2551) -ForegroundColor Cyan
    Write-Host ("  " + [char]0x255A + ($h * $w) + [char]0x255D) -ForegroundColor DarkCyan
}

function Get-LayoutText {
    $text = switch ($S.Layout) {
        'Emulator'  { 'Per emulator   <Root>\<Emulator>\<Console>\...' }
        'Frontend'  { 'Frontend       <Root>\snes, <Root>\psx ... (ES-DE / Batocera / RetroPie)' }
        'RetroArch' { 'RetroArch      <Root>\<libretro system name>\...' }
        'ByConsole' { 'Per console    <Root>\<Console>\...' }
        'Validity'  { 'By validity    <Root>\<Console>\Verified|Modified|Non-Retail|Unverified|Invalid\...' }
        default      { 'Classic        originals stay where they are, only bad files move' }
    }
    $text.Replace('\', [IO.Path]::DirectorySeparatorChar)
}

function Show-Status {
    $conName = if ($S.Console -eq 'All') { "All $($script:Consoles.Count) consoles (auto-detect)" } else { (Get-Con $S.Console).Name }
    $src = @('Headers', 'Filename tags')
    if ($S.AutoDat) { $src += 'libretro DATs (auto)' }
    if ($S.DatFolder) { $src += 'own DAT folder' }
    if ($S.AutoDat) { $src += 'libretro release info' }
    if ($S.Hasheous -ne 'Off') { $src += "Hasheous + IGDB/TheGamesDB/RetroAchievements ($($S.Hasheous))" }
    if ($S.RetailOnly) { $src += 'RETAIL ONLY' }
    $sec = @('Content scan')
    if ($S.DefenderScan) { $sec += "$script:AntivirusName (requested; availability reported during check)" }
    if ($S.OnlineCheck -ne 'Off') {
        if (Get-MbKey) { $sec += 'MalwareBazaar' }
        $sec += $(if (Get-VtKey) { "VirusTotal ($($S.OnlineCheck))" } else { 'VirusTotal (NO KEY!)' })
    }
    Write-Host ''
    Write-Host '   Folder      : ' -NoNewline; Write-Host "$($S.RootFolder)  (all subfolders)" -ForegroundColor Yellow
    Write-Host '   Consoles    : ' -NoNewline; Write-Host $conName -ForegroundColor Yellow
    Write-Host '   Sort layout : ' -NoNewline; Write-Host (Get-LayoutText) -ForegroundColor Yellow
    Write-Host '   Last check  : ' -NoNewline
    if ($script:LastResults) { Write-Host "$(@($script:LastResults).Count) file record(s) available (may be sort-only inventory)" -ForegroundColor Green }
    else { Write-Host 'None - sorting can continue without checks' -ForegroundColor DarkGray }
    Write-Host '   Check sources: ' -NoNewline; Write-Host ($src -join ', ') -ForegroundColor Green
    Write-Host '   Check security: ' -NoNewline; Write-Host ($sec -join ', ') -ForegroundColor $(if ($sec -match 'NO KEY') { 'Red' } else { 'Green' })
    Write-Host '   Sort actions: No antivirus or verification; unknown validity stays Unverified.' -ForegroundColor DarkGray
    if ($script:DatInfo) { Write-Host '   DATs loaded : ' -NoNewline; Write-Host $script:DatInfo -ForegroundColor DarkGray }
    Write-Host ''
}

function Write-MenuItem([string]$Key, [string]$Text, [string]$Color = 'White', [string]$Value = '') {
    Write-Host "    [" -NoNewline -ForegroundColor DarkGray; Write-Host $Key -NoNewline -ForegroundColor Cyan
    Write-Host "] " -NoNewline -ForegroundColor DarkGray
    if ($Value) { Write-Host $Text.PadRight(40) -NoNewline -ForegroundColor $Color; Write-Host $Value -ForegroundColor Yellow } else { Write-Host $Text -ForegroundColor $Color }
}

function Read-Choice([string]$Prompt, [string[]]$Valid) {
    while ($true) {
        $c = ([string](Read-Host "  $Prompt")).Trim().ToUpper()
        if ($Valid -contains $c) { return $c }
        Write-Host "  Invalid choice ($($Valid -join '/')), try again." -ForegroundColor Red
    }
}
function Read-Number([string]$Prompt, [int]$Min, [int]$Max, [int]$Default) {
    while ($true) {
        $v = ([string](Read-Host "  $Prompt [$Min-$Max, Enter = $Default]")).Trim()
        if (-not $v) { return $Default }
        $n = 0; if ([int]::TryParse($v, [ref]$n) -and $n -ge $Min -and $n -le $Max) { return $n }
        Write-Host '  Not a valid number.' -ForegroundColor Red
    }
}
function Confirm-Action([string]$Question) { (Read-Choice "$Question [Y/N]" @('Y', 'N')) -eq 'Y' }
function Wait-Key { [void](Read-Host '  Press Enter to continue') }
function Get-OnOff($v) { if ($v) { 'ON' } else { 'off' } }

function Show-Summary($Results) {
    Update-EvidenceStatus $Results
    Write-Host '  Authenticity, integrity and malware protection are independent; no detection is a guarantee of safety.' -ForegroundColor DarkGray
    foreach ($g in ($Results | Group-Object Authenticity,IntegrityStatus,AntivirusStatus)) { Write-Host "    $($g.Count) file(s): $($g.Name)" -ForegroundColor DarkGray }
    $Results = @($Results)
    Write-Host ''
    if (@($Results | Where-Object { $_.PSObject.Properties['SortOnly'] -and $_.SortOnly }).Count) {
        Write-Host "  Sort-only inventory: $($Results.Count) file(s). Integrity and malware status have NOT been checked." -ForegroundColor Yellow
        $Results | Group-Object Category | Sort-Object Name | ForEach-Object {
            Write-Host ('    {0,-30} {1,6} file(s)' -f $_.Name, $_.Count) -ForegroundColor Gray
        }
        Write-Host "  $(@($Results | Where-Object Target).Count) file(s) planned for sorting. Preview and Apply before moving." -ForegroundColor Cyan
        Write-Host '  Categories reflect file handling only, not proven validity or malware findings.' -ForegroundColor Gray
        return
    } else {
        Write-Host "  Checked $($Results.Count) file(s) in $($S.RootFolder) and all subfolders ($($script:ScanSeconds)s)" -ForegroundColor Cyan
    }

    $roms = @($Results | Where-Object { $_.Console -ne '-' -and $_.Category -notin 'Other_Console', 'Companion' -and -not $_.Lead })
    if ($roms.Count) {
        Write-Host ''
        Write-Host ('   {0,-9} {1,-16} {2,5} {3,8} {4,8} {5,7} {6,7} {7,6} {8,6}' -f 'Console', $(if ($S.CheckOnly) { '' } else { 'Emulator' }), 'Games', 'Original', 'Non-orig', 'Invalid', 'Verifd', 'Dupes', 'Danger') -ForegroundColor White
        Write-Host ('   ' + ('-' * 82)) -ForegroundColor DarkGray
        $roms | Group-Object Console | Sort-Object Name | ForEach-Object {
            $g = $_.Group
            $orig = @($g | Where-Object Category -eq 'Original').Count
            $inv = @($g | Where-Object Category -eq 'Invalid_Corrupt').Count
            $q = @($g | Where-Object Category -eq 'Quarantine').Count
            $dup = @($g | Where-Object Category -eq 'Duplicate').Count
            $ver = @($g | Where-Object { $_.DatMatch -or $_.HashMatch }).Count
            $emu = if ($S.CheckOnly) { '' } else { $g[0].Emulator }; if (-not $emu -and -not $S.CheckOnly) { $emu = '-' }; if ($emu.Length -gt 16) { $emu = $emu.Substring(0, 15) + '~' }
            Write-Host ('   {0,-9} {1,-16} {2,5} ' -f $_.Name, $emu, $g.Count) -NoNewline
            Write-Host ('{0,8} ' -f $orig) -NoNewline -ForegroundColor Green
            Write-Host ('{0,8} ' -f ($g.Count - $orig - $inv - $q - $dup)) -NoNewline -ForegroundColor Magenta
            Write-Host ('{0,7} ' -f $inv) -NoNewline -ForegroundColor DarkRed
            Write-Host ('{0,7} ' -f $ver) -NoNewline -ForegroundColor Cyan
            Write-Host ('{0,6} ' -f $dup) -NoNewline -ForegroundColor DarkYellow
            Write-Host ('{0,6}' -f $q) -ForegroundColor $(if ($q) { 'Red' } else { 'DarkGray' })
        }
        Write-Host '   (Verifd = hash confirmed by a DAT file or Hasheous; disc sets count once)' -ForegroundColor DarkGray
    }

    Write-Host ''
    $groups = @($Results | Group-Object Category)
    $max = ($groups | Measure-Object Count -Maximum).Maximum; if (-not $max) { $max = 1 }
    $block = [string][char]0x2588
    foreach ($cat in $script:CatInfo.Keys) {
        $g = $groups | Where-Object Name -eq $cat
        if (-not $g) { continue }
        $info = $script:CatInfo[$cat]
        $bar = $block * [math]::Max(1, [int](30 * $g.Count / $max))
        Write-Host ('   {0,-56} {1,5}  ' -f $info.Label, $g.Count) -NoNewline
        Write-Host $bar -ForegroundColor $info.Color
    }

    $danger = @($Results | Where-Object { $_.Security -ne 'Clean' -and $_.Category -ne 'Protected' })
    if ($danger.Count) {
        Write-Host ''
        Write-Host '  SECURITY WARNINGS - why these files look dangerous' -ForegroundColor Red
        Write-Host ('  ' + ('-' * 64)) -ForegroundColor DarkRed
        foreach ($d in ($danger | Select-Object -First 15)) { Show-SecurityItem $d }
        if ($danger.Count -gt 15) { Write-Host "   ... and $($danger.Count - 15) more (use [R] review or the report)" -ForegroundColor DarkGray }
    }

    Show-Reasons $Results

    if ($script:ScanErrors -and $script:ScanErrors.Count) {
        Write-Host ''
        Write-Host "  SKIPPED / UNREADABLE ($($script:ScanErrors.Count))" -ForegroundColor Yellow
        $script:ScanErrors | Select-Object -First 5 | ForEach-Object { Write-Wrapped $_ 4 'DarkYellow' '- ' }
        if ($script:ScanErrors.Count -gt 5) { Write-Host '    ... see the report' -ForegroundColor DarkGray }
    }
    $lib = @($Results | Where-Object { $_.Console -ne '-' -and $_.Category -notin 'Other_Console', 'Companion', 'BIOS', 'Protected', 'Not_A_ROM', 'Kept' -and -not $_.Lead })
    if ($lib.Count) {
        $ok = @($lib | Where-Object { $_.Category -eq 'Original' -and ($_.DatMatch -or $_.HashMatch) }).Count
        $okUnv = @($lib | Where-Object { $_.Category -eq 'Original' -and -not ($_.DatMatch -or $_.HashMatch) }).Count
        $nr = @($lib | Where-Object { $_.Category -in 'Beta_Proto_Sample', 'PD_Homebrew_Unlicensed', 'Other_NonGame', 'Hacks_Mods', 'Translations', 'BS_ST' }).Count
        $uv = @($lib | Where-Object { $_.Category -in 'Not_In_DAT', 'Unknown_Check_Manually' }).Count
        Write-Host ''
        Write-Host '  GAME LIBRARY CHECK' -ForegroundColor Cyan
        Write-Host "    Confirmed real released games : $ok of $($lib.Count)" -ForegroundColor Green
        if ($okUnv) { Write-Host "    Looks OK, but not verifiable  : $okUnv  (compressed images or retail-only check is off)" -ForegroundColor Yellow }
        if ($nr) { Write-Host "    Not a real released game      : $nr  (demos, betas, homebrew, unlicensed, hacks, tools...)" -ForegroundColor Magenta }
        if ($uv) { Write-Host "    Not found in any library      : $uv  (cannot be confirmed as a real game)" -ForegroundColor DarkCyan }
    }
    $prot = @($Results | Where-Object Category -eq 'Protected').Count
    if ($prot) { Write-Host ''; Write-Host "  $prot file(s) are inside emulator/program folders and are left alone." -ForegroundColor DarkGray }

    $moves = @($Results | Where-Object Target).Count
    Write-Host ''
    if ($S.CheckOnly) { Write-Host '  CHECK ONLY - nothing was moved. Use [W] to see why files were flagged, or [H] for the full report.' -ForegroundColor White }
    else { Write-Host "  $moves file(s) would be moved (file names unchanged). Use [T] to preview the new folder tree." -ForegroundColor White }
}

function Write-Wrapped([string]$Text, [int]$Indent, [string]$Color = 'Gray', [string]$Prefix = '') {
    $width = 100; try { $width = [math]::Max(60, $Host.UI.RawUI.WindowSize.Width - 2) } catch { }
    $pad = ' ' * $Indent; $line = $Prefix
    foreach ($w in ($Text -split ' ')) {
        if (($pad.Length + $line.Length + $w.Length + 1) -gt $width -and $line.Trim()) {
            Write-Host ($pad + $line.TrimEnd()) -ForegroundColor $Color; $line = ' ' * $Prefix.Length
        }
        $line += "$w "
    }
    if ($line.Trim()) { Write-Host ($pad + $line.TrimEnd()) -ForegroundColor $Color }
}

function Show-SecurityItem($d) {
    $col = switch ($d.Security) { 'Malicious' { 'Red' } 'Suspicious' { 'Red' } 'Executable' { 'Yellow' } default { 'DarkYellow' } }
    $what = switch ($d.Security) {
        'Malicious'  { 'MALICIOUS  -> quarantine' }
        'Suspicious' { 'SUSPICIOUS -> quarantine' }
        'Executable' { 'PROGRAM    -> not moved' }
        default      { 'WARNING    -> not moved' }
    }
    Write-Host ''
    Write-Host "   [$what] " -NoNewline -ForegroundColor $col; Write-Host $d.FileName -ForegroundColor White
    Write-Host "      in $($d.Folder)" -ForegroundColor DarkGray
    foreach ($t in ($d.Threats -split ' \| ')) { if ($t) { Write-Wrapped $t 6 'Gray' '- ' } }
    if ($d.Online) { Write-Wrapped "Online: $($d.Online)" 6 'Gray' '- ' }
    if ($d.SHA256) { Write-Host "      Check online: $(Get-VtLink $d.SHA256)" -ForegroundColor DarkCyan }
    $adv = if ($d.Security -in 'Malicious', 'Suspicious') { $script:Advice['Quarantine'] } elseif ($d.Security -eq 'Executable') { $script:Advice['Executable'] } else { '' }
    if ($adv) { Write-Wrapped "What to do: $adv" 6 'DarkGray' }
}

function Show-Reasons($Results, [int]$PerCategory = 8) {
    $flag = @($Results | Where-Object { $_.Category -notin 'Original', 'Quarantine', 'Executable', 'Not_A_ROM', 'Other_Console', 'Protected', 'Companion' -and -not $_.Lead })
    $warnOrig = @($Results | Where-Object { $_.Category -eq 'Original' -and $_.Integrity -eq 'Mismatch' -and -not $_.DatMatch -and -not $_.HashMatch })
    if (-not $flag.Count -and -not $warnOrig.Count) { return }
    Write-Host ''
    Write-Host '  WHY FILES ARE NOT ORIGINAL / WRONG' -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * 64)) -ForegroundColor DarkCyan
    foreach ($cat in $script:CatInfo.Keys) {
        $g = @($flag | Where-Object Category -eq $cat)
        if (-not $g.Count) { continue }
        $info = $script:CatInfo[$cat]
        Write-Host ''
        Write-Host "   $($info.Label) ($($g.Count))" -ForegroundColor $info.Color
        if ($script:Advice[$cat]) { Write-Wrapped $script:Advice[$cat] 5 'DarkGray' }
        foreach ($r in ($g | Select-Object -First $PerCategory)) {
            Write-Host "     - $($r.FileName)" -NoNewline -ForegroundColor White; Write-Host "  [$($r.Console)]" -ForegroundColor DarkGray
            Write-Wrapped $r.Reason 9 'Gray'
        }
        if ($g.Count -gt $PerCategory) { Write-Host "     ... and $($g.Count - $PerCategory) more (see [E] or the report)" -ForegroundColor DarkGray }
    }
    if ($warnOrig.Count) {
        Write-Host ''
        Write-Host "   Kept as original, but internal checksum does not match ($($warnOrig.Count))" -ForegroundColor DarkYellow
        Write-Wrapped 'The name looks original, but the data does not match the checksum stored inside the ROM. It may be patched or a bad dump. Enable auto DATs / Hasheous or Strict mode to be sure.' 5 'DarkGray'
        foreach ($r in ($warnOrig | Select-Object -First $PerCategory)) { Write-Host "     - $($r.FileName)" -ForegroundColor White }
        if ($warnOrig.Count -gt $PerCategory) { Write-Host "     ... and $($warnOrig.Count - $PerCategory) more" -ForegroundColor DarkGray }
    }
}

function Show-FileDetails($r) {
    Update-EvidenceStatus @($r)
    $info = $script:CatInfo[$r.Category]
    Write-Host ''
    Write-Host "  $($r.FileName)" -ForegroundColor White
    Write-Host ('  ' + ('-' * 64)) -ForegroundColor DarkGray
    $con = Get-Con $r.Console
    $members = if ($r.PSObject.Properties['SetMembers'] -and $r.SetMembers) { "$(@($r.SetMembers).Count) file(s): " + ((@($r.SetMembers) | ForEach-Object { $_.FileName }) -join ', ') } else { '' }
    $rows = [ordered]@{
        'Console'    = $(if ($con) { "$($con.Name) ($($r.Console))" } else { $r.Console })
        'Detected by'= $r.Detected; 'Emulator' = $r.Emulator; 'Verdict' = $info.Label; 'Security' = $r.Security
        'Header'     = $r.Header; 'Checksum' = $r.Integrity; 'DAT match' = $r.DatMatch; 'Hash match' = $r.HashMatch
        'Authenticity' = $r.Authenticity; 'Integrity result' = $r.IntegrityStatus; 'Antivirus' = $r.AntivirusStatus; 'Malware result' = $r.MalwareStatus
        'Local check UTC' = $r.CheckedUtc; 'AV attempt UTC' = $r.AntivirusCheckedUtc
        'Released'   = (@($r.Year, $r.Publisher) | Where-Object { $_ }) -join ', '; 'Libraries' = $r.Libraries
        'Verified by'= $r.Sources; 'Online'  = $r.Online; 'Part of set' = $(if ($r.Lead) { $r.Lead.FileName } else { '' })
        'Set files'  = $members; 'Duplicate of' = $r.DupOf; 'CRC32' = $r.CRC32; 'SHA1' = $r.SHA1
        'Size'       = "$($r.SizeKB) KB"; 'Action' = $r.Action; 'Move to' = $r.Target; 'Location' = $r.FullName
    }
    foreach ($k in $rows.Keys) {
        if (-not $rows[$k]) { continue }
        Write-Host ('   {0,-12}: ' -f $k) -NoNewline -ForegroundColor DarkGray
        $c = if ($k -eq 'Verdict') { $info.Color } elseif ($k -eq 'Security' -and $r.Security -ne 'Clean') { 'Red' } elseif ($k -in 'DAT match', 'Hash match', 'Verified by', 'Released', 'Libraries') { 'Green' } else { 'Gray' }
        Write-Host $rows[$k] -ForegroundColor $c
    }
    Write-Host ''
    Write-Host '   Why:' -ForegroundColor Cyan
    Write-Wrapped $r.Reason 6 'Gray'
    if ($r.Threats -and $r.Reason -ne $r.Threats) { foreach ($t in ($r.Threats -split ' \| ')) { Write-Wrapped $t 6 'Yellow' '! ' } }
    if ($r.Notes) {
        Write-Host '   Technical details:' -ForegroundColor Cyan
        foreach ($n in ($r.Notes -split '; ')) { Write-Wrapped $n 6 'DarkGray' '- ' }
    }
    $adv = $script:Advice[$r.Category]
    if ($adv) { Write-Host '   What to do:' -ForegroundColor Cyan; Write-Wrapped $adv 6 'Gray' }
    if ($r.SHA256) { Write-Host "   VirusTotal  : $(Get-VtLink $r.SHA256)" -ForegroundColor DarkCyan }
}

function Show-Tree($Results, [int]$MaxFilesPerDir = 4) {
    $moves = @($Results | Where-Object Target)
    if (-not $moves.Count) { Write-Host '  Nothing would be moved - everything is already in place.' -ForegroundColor Green; return }
    $root = Get-DirectoryPath $S.RootFolder
    Write-Host ''
    Write-Host "  New folder structure (only moved files shown) under $root" -ForegroundColor Cyan
    $byDir = $moves | Group-Object -CaseSensitive:(-not $script:OnWindows) { (Split-Path $_.Target).Substring([math]::Min($root.Length, (Split-Path $_.Target).Length)).TrimStart([IO.Path]::DirectorySeparatorChar) } | Sort-Object Name
    foreach ($g in $byDir) {
        $depth = if ($g.Name) { ($g.Name -split '[\\/]').Count } else { 0 }
        $label = if ($g.Name) { ($g.Name -split '[\\/]')[-1] } else { '(root)' }
        $col = if ($g.Name -match [regex]::Escape($S.QuarantineFolder)) { 'Red' } elseif ($g.Name -match [regex]::Escape($S.NonOriginalFolder) -or $g.Name -match [regex]::Escape($S.RejectFolder) -or $g.Name -match [regex]::Escape($S.DuplicateFolder)) { 'Magenta' } else { 'Yellow' }
        Write-Host ('   ' + ('  ' * [math]::Max(0, $depth - 1)) + [char]0x2514 + ' ' + $g.Name) -NoNewline -ForegroundColor $col
        Write-Host "  ($($g.Count))" -ForegroundColor DarkGray
        foreach ($r in ($g.Group | Select-Object -First $MaxFilesPerDir)) { Write-Host ('   ' + ('  ' * $depth) + '  ' + $r.FileName) -ForegroundColor Gray }
        if ($g.Count -gt $MaxFilesPerDir) { Write-Host ('   ' + ('  ' * $depth) + "  ... +$($g.Count - $MaxFilesPerDir) more") -ForegroundColor DarkGray }
    }
}

function Export-IdentificationReport($Results) {
    $dir = Join-Path (Get-WorkDir) 'reports'
    [void][IO.Directory]::CreateDirectory((LongP $dir))
    $stamp = if ($script:ScanRunStamp) { $script:ScanRunStamp } else { Get-Date -Format 'yyyyMMdd-HHmmss-fffffff' }
    $base = Join-Path $dir "Identification-$stamp"
    $runDate = (Get-Date).ToString('o'); $scriptHash = Get-Sha256 $script:ScriptPath
    $rows = @(
        foreach ($r in $Results) {
            $status = $r.IdentificationStatus
            if (-not $status -or $status -eq 'Not needed') {
                $status = if ($r.Console -eq '-') { 'Unresolved' } elseif ($r.Category -eq 'BIOS') { 'Firmware filename identification' } elseif (-not $r.DatMatch -and -not $r.HashMatch) { 'Console known; dump unverified' } else { 'Recognized' }
            }
            $advice = switch ($status) {
                'Unsupported platform' { 'Add an exact console profile/platform alias; do not guess from the extension.' }
                'Identified' { 'Review online name/platform and add a local signature or firmware rule if useful.' }
                'Firmware filename identification' { 'Compare with a trusted firmware DAT; filename recognition is not authenticity proof.' }
                'Recognized' { 'No identification change required.' }
                'Skipped' { 'Review locally; do not upload keys or run suspicious content. Packed sets need a set auditor.' }
                'Hash limit' { 'Review file size/format and optionally raise the hash limit in Settings.' }
                'Disabled' { 'Enable unknown-file hash identification in Settings > Verification if desired.' }
                'Console known; dump unverified' { 'Add a trusted system-specific DAT; check format, revision and firmware rules. Remote verification is refreshed on later checks.' }
                default { 'Review findings and online clues. Retry Check/Full workflow after fixes or a script update; unresolved/error checks are retried.' }
            }
            [pscustomobject][ordered]@{
                RunDate = $runDate; ScriptSHA256 = $scriptHash; FileName = $r.FileName; FullName = $r.FullName
                Extension = [IO.Path]::GetExtension($r.FileName); Bytes = $r.Length; Console = $r.Console; Category = $r.Category
                IdentificationStatus = $status; OnlinePlatform = $r.OnlinePlatform; OnlineName = $r.OnlineName
                IdentificationReason = $r.IdentificationReason; Reason = $r.Reason; Findings = "$($r.Notes) $($r.Threats)".Trim()
                Online = $r.Online; SuggestedImprovement = $advice; MD5 = $r.MD5; SHA1 = $r.SHA1; SHA256 = $r.SHA256
                CheckedUtc = $r.CheckedUtc; LocalCheckReused = $r.Resumed
            }
        }
        foreach ($errorText in $script:ScanErrors) {
            [pscustomobject]@{ RunDate=$runDate; ScriptSHA256=$scriptHash; IdentificationStatus='Unreadable/skipped path'; Findings=[string]$errorText; SuggestedImprovement='Review access permissions or skipped link; retry after resolving it.' }
        }
    )
    $columns = 'RunDate','ScriptSHA256','FileName','FullName','Extension','Bytes','Console','Category','IdentificationStatus','OnlinePlatform','OnlineName','IdentificationReason','Reason','Findings','Online','SuggestedImprovement','MD5','SHA1','SHA256','CheckedUtc','LocalCheckReused'
    if ($rows.Count) { $rows | Select-Object $columns | Export-Csv -LiteralPath "$base.csv" -NoTypeInformation -Encoding UTF8 }
    else { ('"' + ($columns -join '","') + '"') | Set-Content -LiteralPath "$base.csv" -Encoding UTF8 }
    $enc = { param($v) [Net.WebUtility]::HtmlEncode([string]$v) }
    $tableRows = foreach ($row in $rows) {
        '<tr>' + (@(foreach ($column in $columns) { "<td>$(& $enc $row.$column)</td>" }) -join '') + '</tr>'
    }
    $header = (@($columns | ForEach-Object { "<th>$_</th>" }) -join '')
    $counts = (@($rows | Group-Object IdentificationStatus | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ' | ')
    "<html><head><meta charset='utf-8'><title>Identification $stamp</title><style>body{font-family:Segoe UI,Arial}table{border-collapse:collapse}td,th{border:1px solid #aaa;padding:5px;vertical-align:top}</style></head><body><h1>ROM identification / improvement report</h1><p>$(& $enc $runDate) | $(& $enc $S.RootFolder)</p><p>$(& $enc $counts)</p><p>Only hashes are submitted online. A missing match is not proof of malware or an invalid ROM. Unresolved and failed work is retried on later checks. No rules are automatically downloaded or executed.</p><table><thead><tr>$header</tr></thead><tbody>$($tableRows -join "`n")</tbody></table></body></html>" |
        Set-Content -LiteralPath "$base.html" -Encoding UTF8
    $script:LastIdentificationReport = "$base.html"
    Write-Host "  Dated identification / improvement report: $base.html (CSV alongside)" -ForegroundColor Cyan
}
function Export-Report($Results, [string]$Kind = 'Preview') { Invoke-ProgressTask 'Exporting report' { Export-ReportCore $Results $Kind } }
function Export-ReportCore($Results, [string]$Kind = 'Preview') {
    Update-RomProgress -Phase 'Writing CSV report' -Indeterminate -Current $Kind
    Update-EvidenceStatus $Results
    $wd = Get-WorkDir; [void][IO.Directory]::CreateDirectory((LongP $wd))
    $csv = Join-Path $wd "$Kind-latest.csv"
    $Results | Select-Object FileName, Folder, Console, Emulator, Category, Reason, IdentificationStatus, OnlinePlatform, OnlineName, IdentificationReason, Authenticity, IntegrityStatus, AntivirusStatus, AntivirusCheckedUtc, CheckedUtc, MalwareStatus, DatStrength, Security, Threats, Detected, Header, Integrity, CRC32, DatMatch, HashMatch, Year, Publisher, Libraries, Sources, Online,
        @{ n = 'Set'; e = { if ($_.Lead) { $_.Lead.FileName } elseif ($_.PSObject.Properties['SetMembers']) { "$(@($_.SetMembers).Count) files" } else { '' } } }, DupOf, MD5, SHA1, SHA256,
        @{ n = 'VirusTotalLink'; e = { Get-VtLink $_.SHA256 } }, SizeKB, Action, Target, Notes, FullName |
        Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $html = Join-Path $wd 'Report-latest.html'
    $css = @"
<style>
body{font-family:Segoe UI,Arial;background:#1e1e1e;color:#ddd;margin:20px} h1{color:#4fc3f7} a{color:#4fc3f7} .small{color:#999;font-size:12px}
table{border-collapse:collapse;width:100%;font-size:13px} th{background:#333;position:sticky;top:0;text-align:left;padding:6px}
td{padding:4px 6px;border-bottom:1px solid #333;vertical-align:top} tr:hover{background:#2a2a2a} .why{color:#bbb;max-width:520px}
.threat{color:#ff8a80;display:block;margin-top:3px} .Original td:nth-child(4){color:#81c784}
.Quarantine{background:#4a1010} .Quarantine td:nth-child(4){color:#ff5252;font-weight:bold} .Invalid_Corrupt td:nth-child(4){color:#e57373}
.Hacks_Mods td:nth-child(4){color:#ce93d8} .Translations td:nth-child(4){color:#4dd0e1} .Bad_or_Fixed_Dumps td:nth-child(4){color:#fff176}
.Beta_Proto_Sample td:nth-child(4){color:#ffb74d} .PD_Homebrew_Unlicensed td:nth-child(4){color:#64b5f6} .Executable td:nth-child(4){color:#ff8a80}
.Not_In_DAT td:nth-child(4){color:#80cbc4} .Unknown_Check_Manually td:nth-child(4){color:#9e9e9e} .Duplicate td:nth-child(4){color:#ffcc80}
input{background:#333;color:#ddd;border:1px solid #555;padding:5px;width:300px;margin-bottom:10px}
</style>
<script>function f(v){v=v.toLowerCase();document.querySelectorAll('tbody tr').forEach(function(r){r.style.display=r.innerText.toLowerCase().indexOf(v)>=0?'':'none'})}</script>
"@
    $enc = { param($v) [Net.WebUtility]::HtmlEncode([string]$v) }
    $order = @{}; $i = 0; foreach ($k in $script:CatInfo.Keys) { $order[$k] = $i++ }
    $reportDone = 0
    $rows = foreach ($r in ($Results | Sort-Object { $order[$_.Category] }, Console, FileName)) {
        Update-RomProgress -Phase 'Building HTML report' -Done $reportDone -Total @($Results).Count -Current $r.FileName
        $reportDone++
        $why = & $enc $r.Reason
        if ($r.Threats -and $r.Threats -ne $r.Reason) { foreach ($t in ($r.Threats -split ' \| ')) { $why += "<span class='threat'>! $(& $enc $t)</span>" } }
        if ($script:Advice[$r.Category]) { $why += "<br><i>$(& $enc $script:Advice[$r.Category])</i>" }
        $vt = if ($r.SHA256) { "<a href='$(Get-VtLink $r.SHA256)'>$(if ($r.Online) { & $enc $r.Online } else { 'check' })</a>" } else { & $enc $r.Online }
        $label = if ($script:CatInfo[$r.Category]) { $script:CatInfo[$r.Category].Label } else { $r.Category }
        "<tr class='$($r.Category)'><td>$(& $enc $r.FileName)<div class='small'>$(& $enc $r.Folder)</div></td><td>$(& $enc $r.Console)</td><td>$(& $enc $r.Emulator)</td><td>$(& $enc $label)</td>" +
        "<td class='why'>$why</td><td>Authenticity: $(& $enc $r.Authenticity)<br>Integrity: $(& $enc $r.IntegrityStatus)<br>Antivirus: $(& $enc $r.AntivirusStatus)<div class='small'>$(& $enc $r.AntivirusCheckedUtc)</div>Malware: $(& $enc $r.MalwareStatus)<br>Heuristics: $(& $enc $r.Security)</td><td>$(& $enc $r.Sources)<div class='small'>$(& $enc $r.DatMatch) $(& $enc $r.HashMatch)</div></td>" +
        "<td>$vt</td><td class='small'>$(& $enc $r.Detected); $(& $enc $r.Header); $(& $enc $r.Integrity); $(& $enc $r.Notes)</td><td>$(& $enc $r.Action)<div class='small'>$(& $enc $r.Target)</div></td></tr>"
    }
    $errs = ''
    if ($script:ScanErrors -and $script:ScanErrors.Count) { $errs = "<h3>Skipped / unreadable</h3><ul>" + (($script:ScanErrors | ForEach-Object { "<li>$(& $enc $_)</li>" }) -join '') + '</ul>' }
    $body = "<h1>ROM Sorter report</h1><p>$(& $enc $S.RootFolder) (all subfolders) - $(Get-Date) - $(@($Results).Count) files - layout $(& $enc $S.Layout)</p>" +
            "<input placeholder='Filter...' onkeyup='f(this.value)'>" +
            '<table><thead><tr><th>File</th><th>Console</th><th>Emulator</th><th>Verdict</th><th>Why</th><th>Security</th><th>Verified by</th><th>Online</th><th>Technical</th><th>Action</th></tr></thead><tbody>' +
            ($rows -join "`n") + "</tbody></table>$errs"
    "<html><head><meta charset='utf-8'><title>ROM Sorter report</title>$css</head><body>$body</body></html>" | Set-Content -LiteralPath $html -Encoding UTF8
    $history = Join-Path $wd 'reports'; [void][IO.Directory]::CreateDirectory((LongP $history))
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'
    Copy-Item -LiteralPath $csv -Destination (Join-Path $history "$Kind-$stamp.csv")
    Copy-Item -LiteralPath $html -Destination (Join-Path $history "$Kind-$stamp.html")
    Write-Host "  Report: $html" -ForegroundColor DarkGray
    Set-ProgressCounter 'Reported files' @($Results).Count
    $html
}
# ===================================================================== MENUS
function Select-FromList([string]$Title, [object[]]$Items, [scriptblock]$Label, [switch]$AllowBack) {
    # paged picker: number = choose, N/P = next/prev page, text = filter
    $filter = ''; $page = 0; $size = 20
    while ($true) {
        $list = @($Items | Where-Object { -not $filter -or (& $Label $_) -like "*$filter*" })
        $pages = [math]::Max(1, [math]::Ceiling($list.Count / $size)); if ($page -ge $pages) { $page = $pages - 1 }
        Write-Host ''
        Write-Host "  $Title$(if ($filter) { "  (filter: $filter)" })  - page $($page + 1)/$pages" -ForegroundColor Cyan
        for ($i = $page * $size; $i -lt [math]::Min($list.Count, ($page + 1) * $size); $i++) { Write-MenuItem ([string]($i + 1)) (& $Label $list[$i]) }
        Write-Host '  Number = choose, N/P = next/previous page, text = filter, Enter = clear filter' -NoNewline -ForegroundColor DarkGray
        if ($AllowBack) { Write-Host ', B = back' -ForegroundColor DarkGray } else { Write-Host '' }
        $v = ([string](Read-Host '  Choice')).Trim()
        $n = 0
        if ([int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le $list.Count) { return $list[$n - 1] }
        switch ($v.ToUpper()) {
            'N' { if ($page -lt $pages - 1) { $page++ } }
            'P' { if ($page -gt 0) { $page-- } }
            'B' { if ($AllowBack) { return $null } }
            ''  { $filter = '' ; $page = 0 }
            default { $filter = $v; $page = 0 }
        }
    }
}

function Select-RootFolder {
    Show-Banner
    Write-Host ''
    Write-Host "  Current: $($S.RootFolder)" -ForegroundColor DarkGray
    Write-Host '  All subfolders (any depth) are scanned. Pick the top folder of your ROM collection.' -ForegroundColor DarkGray
    Write-Host ''
    if ($script:OnWindows) { Write-MenuItem '1' 'Browse for a folder...' }
    Write-MenuItem '2' 'Type / paste a path'
    Write-MenuItem 'B' 'Back'
    $choices = if ($script:OnWindows) { @('1', '2', 'B') } else { @('2', 'B') }
    $c = Read-Choice 'Choice' $choices
    $path = $null
    if ($c -eq '1') {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'Select the top folder of your ROM collection'; $dlg.SelectedPath = $S.RootFolder
            if ($dlg.ShowDialog() -eq 'OK') { $path = $dlg.SelectedPath }
        } catch { Write-Host '  Folder dialog not available, type the path instead.' -ForegroundColor Yellow; $c = '2' }
    }
    if ($c -eq '2') { $path = ([string](Read-Host '  Folder')).Trim('"', ' ') }
    if ($path) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { Write-Host '  Folder not found.' -ForegroundColor Red; Wait-Key; return }
        $full = (Resolve-Path -LiteralPath $path).Path
        if ($full -match '^[A-Za-z]:\\?$' -or $full -match '^[A-Za-z]:\\(Windows|Program Files( \(x86\))?|Users)\\?$' -or
            (-not $script:OnWindows -and ($full -in '/', '/home', '/usr', '/etc', '/var', '/bin', '/sbin', '/opt', '/mnt', '/media' -or
            $full -match '^/mnt/[a-z](/Users)?/?$' -or (Test-SamePath $full $HOME)))) {
            Write-Host "  '$full' is a drive root or system folder. Sorting it could move files you did not mean to." -ForegroundColor Red
            if (-not (Confirm-Action 'Use it anyway?')) { return }
        }
        $S.RootFolder = $full; $script:LastResults = $null; Save-Settings
    }
}

function Select-ConsoleMenu {
    Show-Banner
    Write-Host ''
    Write-Host '  Normally leave this on "All": every file is detected by extension, header, content and folder name.' -ForegroundColor DarkGray
    Write-Host '  Choose one console only to limit the scan (other ROMs are then left alone).' -ForegroundColor DarkGray
    $items = @([pscustomobject]@{ Key = 'All'; Name = 'All consoles (auto-detect)'; Ext = @() }) + @($script:Consoles)
    $pick = Select-FromList 'Console' $items { param($c) '{0,-36} {1}' -f $c.Name, (($c.Ext | Select-Object -First 8) -join ' ') } -AllowBack
    if ($pick) { $S.Console = $pick.Key; $script:LastResults = $null; Save-Settings }
}

function Show-LayoutMenu([switch]$RunSort) {
    while ($true) {
        Show-Banner
        Write-Host ''
        Write-Host '  How should the sorted ROMs be organised? (file names are never changed)' -ForegroundColor Cyan
        if ($RunSort) { Write-Host '  Choose a layout to continue directly to its sorting preview.' -ForegroundColor Gray }
        Write-Host ''
        $lay = [ordered]@{
            'Emulator'  = 'Per emulator   D:\Roms\Snes9x\Super Nintendo\Game.sfc'
            'ByConsole' = 'Per console    D:\Roms\Super Nintendo\Game.sfc'
            'Validity'  = 'By validity    D:\Roms\Super Nintendo\Verified\Retail\Game.sfc   (Verified / Modified / Non-Retail / Unverified / Invalid)'
            'Frontend'  = 'Frontend       D:\Roms\snes\Game.sfc   (EmulationStation, Batocera, RetroPie)'
            'RetroArch' = 'RetroArch      D:\Roms\Nintendo - Super Nintendo Entertainment System\Game.sfc'
            'Classic'   = 'Classic        good ROMs stay where they are; only bad/unsafe files move'
        }
        $keys = @($lay.Keys)
        for ($i = 0; $i -lt $keys.Count; $i++) { Write-MenuItem ([string]($i + 1)) $lay[$keys[$i]] $(if ($S.Layout -eq $keys[$i]) { 'Green' } else { 'White' }) }
        Write-Host ''
        Write-MenuItem 'E' 'Choose the emulator per console' 'White' "$(@($S.Emulators.Keys).Count) changed from default"
        Write-MenuItem 'S' 'Show the emulator list for all consoles'
        Write-MenuItem 'R' 'Reset all emulators to the recommended default'
        Write-MenuItem 'B' 'Back'
        $c = Read-Choice 'Choice' (@('E', 'S', 'R', 'B') + (1..$keys.Count | ForEach-Object { [string]$_ }))
        switch ($c) {
            'E' { Select-EmulatorMenu }
            'S' {
                Write-Host ''
                Write-Host ('   {0,-8} {1,-34} {2,-18} {3}' -f 'Key', 'Console', 'Emulator', 'Alternatives') -ForegroundColor White
                foreach ($con in $script:Consoles) {
                    $e = Get-Emulator $con
                    Write-Host ('   {0,-8} {1,-34} ' -f $con.Key, $con.Name) -NoNewline
                    Write-Host ('{0,-18} ' -f $e) -NoNewline -ForegroundColor $(if ($S.Emulators[$con.Key]) { 'Yellow' } else { 'Green' })
                    Write-Host ((@($con.Emus | Where-Object { $_ -ne $e })) -join ', ') -ForegroundColor DarkGray
                }
                Wait-Key
            }
            'R' { $S.Emulators = @{}; Save-Settings }
            'B' { Save-Settings; return }
            default {
                $S.Layout = $keys[[int]$c - 1]; Save-Settings
                if ($RunSort) { Show-SortMenu; return }
            }
        }
    }
}

function Select-EmulatorMenu {
    while ($true) {
        $con = Select-FromList 'Pick a console to change its emulator' @($script:Consoles) { param($c) '{0,-34} -> {1}' -f $c.Name, (Get-Emulator $c) } -AllowBack
        if (-not $con) { return }
        $opts = @($con.Emus) + @('(type your own name)')
        $e = Select-FromList "Emulator for $($con.Name)" $opts { param($x) $x } -AllowBack
        if (-not $e) { continue }
        if ($e -eq '(type your own name)') { $e = ([string](Read-Host '  Emulator / folder name')).Trim(); $e = Get-SafeName $e; if (-not $e) { continue } }
        if ($e -eq $con.Emus[0]) { $S.Emulators.Remove($con.Key) } else { $S.Emulators[$con.Key] = $e }
        Write-Host "  $($con.Name) -> $e" -ForegroundColor Green
        Save-Settings
    }
}

function Show-VerifyMenu {
    $hmodes = [ordered]@{ 'Off' = 'Off'; 'Unverified' = 'Only files not proven by a DAT (faster)'; 'All' = 'All ROM files (recommended: also IGDB etc.)' }
    while ($true) {
        Show-Banner
        Write-Host ''
        Write-Wrapped 'To PROVE a ROM is an unmodified original, its checksum is compared with databases of known good dumps. The script combines several sources:' 2 'Gray'
        Write-Wrapped '1) No-Intro / Redump DAT files from the libretro database (downloaded automatically per console, refreshed monthly). 2) libretro release info: release year + publisher of every released game. 3) Your own DAT folder (e.g. from datomatic.no-intro.org / redump.org). 4) Hasheous.org - combines No-Intro, Redump, TOSEC, MAME and known hacks, flags demos, and links the game to IGDB, TheGamesDB, RetroAchievements and LaunchBox; only the MD5 fingerprint is sent.' 2 'DarkGray'
        Write-Host ''
        Write-MenuItem '1' 'Download libretro DATs automatically' 'White' (Get-OnOff $S.AutoDat)
        Write-MenuItem '2' 'Own DAT folder' 'White' $(if ($S.DatFolder) { $S.DatFolder } else { '(none)' })
        Write-MenuItem '3' 'Hasheous online lookup' 'White' $hmodes[$S.Hasheous]
        Write-MenuItem '4' 'With DATs: ROMs not in the DAT count as non-original' 'White' (Get-OnOff $S.RequireDatMatch)
        Write-MenuItem '5' 'Download / refresh DATs for all consoles now'
        Write-MenuItem '6' 'Test Hasheous (look up Super Mario World)'
        Write-MenuItem '7' 'Retail only (only confirmed real games = OK)' 'White' (Get-OnOff $S.RetailOnly)
        Write-MenuItem '8' 'Identify unknown ROMs/firmware online (hashes only)' 'White' (Get-OnOff $S.IdentifyUnknown)
        Write-MenuItem 'B' 'Back'
        switch (Read-Choice 'Choice' @('1', '2', '3', '4', '5', '6', '7', '8', 'B')) {
            '8' { $S.IdentifyUnknown = -not $S.IdentifyUnknown }
            '7' { $S.RetailOnly = -not $S.RetailOnly }
            '1' { $S.AutoDat = -not $S.AutoDat }
            '2' {
                $p = ([string](Read-Host '  DAT folder (empty = stop using one)')).Trim('"', ' ')
                if (-not $p) { $S.DatFolder = '' }
                elseif (Test-Path -LiteralPath $p -PathType Container) {
                    $S.DatFolder = (Resolve-Path -LiteralPath $p).Path; Import-DatFolder (Get-DatFolders)
                    Write-Host "  Loaded: $script:DatInfo" -ForegroundColor Green; Wait-Key
                } else { Write-Host '  Folder not found.' -ForegroundColor Red; Wait-Key }
            }
            '3' { $k = @($hmodes.Keys); $S.Hasheous = $k[($k.IndexOf($S.Hasheous) + 1) % $k.Count] }
            '4' { $S.RequireDatMatch = -not $S.RequireDatMatch }
            '5' {
                $force = Confirm-Action 'Re-download even DATs that are still fresh?'
                Update-LibretroDats @($script:Consoles | ForEach-Object Key) -Force:$force
                Update-LibretroMeta @($script:Consoles | ForEach-Object Key) -Force:$force
                Import-DatFolder (Get-DatFolders); Write-Host "  $script:DatInfo" -ForegroundColor Green; Wait-Key
            }
            '6' {
                $h = Invoke-HasheousLookup 'CDD3C8C37322978CA8669B34BC89C804'
                if ($h -and $h.Status -eq 'Found') { Write-Host "  Hasheous works: $($h.Name) [$($h.Source)], $($h.Year) by $($h.Publisher), demo flag: $($h.Demo), on: $($h.Libraries)" -ForegroundColor Green } else { Write-Host "  Hasheous lookup failed: $(if ($h) { "$($h.Status) $($h.Message)" })" -ForegroundColor Red }
                Wait-Key
            }
            'B' { Save-Settings; $script:LastResults = $null; return }
        }
        Save-Settings
    }
}

function Show-OnlineMenu {
    $modes = [ordered]@{
        'Off'        = 'Off - no virus lookups'
        'Risky'      = 'Risky files only (warnings, archives, invalid/unknown, not verified)'
        'Unverified' = 'Everything not proven original by a DAT/Hasheous'
        'All'        = 'All files (slow on the free VirusTotal key)'
    }
    while ($true) {
        Show-Banner
        Write-Host ''
        Write-Wrapped "Check actions inspect files locally (hidden programs, scripts, disguised extensions). When enabled, $script:AntivirusName also scans them; failures are reported. Online you can add two malware databases - only the SHA-256 fingerprint is sent, never the file:" 2 'Gray'
        Write-Wrapped 'MalwareBazaar (abuse.ch): free key at https://auth.abuse.ch - no strict rate limit. VirusTotal: 70+ antivirus engines, free key at virustotal.com (profile > API key), 4 lookups/minute. A ROM that is unknown to them is normal, not a danger sign. Results are cached.' 2 'DarkGray'
        Write-Host ''
        if (-not $script:OnWindows) { Write-Wrapped 'Linux keys are used for this process only, never written to settings. Supply ROMSORTER_VIRUSTOTAL_KEY / ROMSORTER_MALWAREBAZAAR_KEY in the environment on later runs.' 2 'Yellow' }
        Write-MenuItem '1' "$script:AntivirusName scan" 'White' (Get-OnOff $S.DefenderScan)
        Write-MenuItem '2' 'What to check online' 'White' $modes[$S.OnlineCheck]
        $keyStatus = if ($script:OnWindows) { 'set (encrypted)' } else { 'set (process environment only)' }
        Write-MenuItem '3' 'MalwareBazaar API key' 'White' $(if (Get-MbKey) { $keyStatus } else { 'not set' })
        Write-MenuItem '4' 'VirusTotal API key' 'White' $(if (Get-VtKey) { $keyStatus } else { 'not set' })
        Write-MenuItem '5' 'VirusTotal delay between lookups' 'White' "$($S.VtDelay) s"
        Write-MenuItem '6' 'Test the keys'
        Write-MenuItem '7' 'Remove both keys'
        Write-MenuItem '8' 'Clear online cache' 'White' "$(@((Get-OnlineCache).Keys).Count) entries"
        Write-MenuItem 'B' 'Back'
        switch (Read-Choice 'Choice' @('1', '2', '3', '4', '5', '6', '7', '8', 'B')) {
            '1' { $S.DefenderScan = -not $S.DefenderScan }
            '2' {
                $keys = @($modes.Keys)
                for ($i = 0; $i -lt $keys.Count; $i++) { Write-MenuItem ([string]($i + 1)) $modes[$keys[$i]] }
                $S.OnlineCheck = $keys[[int](Read-Choice 'Mode' @('1', '2', '3', '4')) - 1]
                if ($S.OnlineCheck -ne 'Off' -and -not (Get-VtKey) -and -not (Get-MbKey)) { Write-Host '  Set at least one API key, otherwise nothing is checked online.' -ForegroundColor Yellow; Wait-Key }
            }
            '3' {
                $k = ([string](Read-Host '  Paste your MalwareBazaar / abuse.ch Auth-Key')).Trim()
                if ($k -match '^[\w\-]{20,100}$') { Set-MbKey $k; if ($S.OnlineCheck -eq 'Off') { $S.OnlineCheck = 'Risky' }; Write-Host $(if ($script:OnWindows) { '  Key saved (encrypted).' } else { '  Key set for this process only.' }) -ForegroundColor Green }
                elseif ($k) { Write-Host '  That does not look like an abuse.ch key.' -ForegroundColor Red }
                Wait-Key
            }
            '4' {
                $k = ([string](Read-Host '  Paste your VirusTotal API key')).Trim()
                if ($k -match '^[0-9a-fA-F]{64}$') { Set-VtKey $k; if ($S.OnlineCheck -eq 'Off') { $S.OnlineCheck = 'Risky' }; Write-Host $(if ($script:OnWindows) { '  Key saved (encrypted).' } else { '  Key set for this process only.' }) -ForegroundColor Green }
                elseif ($k) { Write-Host '  That does not look like a VirusTotal key (64 hex characters).' -ForegroundColor Red }
                Wait-Key
            }
            '5' { $S.VtDelay = Read-Number 'Seconds between VirusTotal lookups (free key: 15)' 0 120 $S.VtDelay }
            '6' {
                # EICAR test file: harmless, but flagged by every antivirus on purpose
                $eicar = '275A021BBFB6489E54D471899F7DB9D1663FC695EC2FE2A2C4538AABF651FD0F'
                if ($k = Get-MbKey) {
                    $v = Invoke-MbLookup $eicar $k
                    if ($v.Status -in 'Found', 'Unknown') { Write-Host "  MalwareBazaar key works ($($v.Status))." -ForegroundColor Green } else { Write-Host "  MalwareBazaar: $($v.Status) $($v.Message)" -ForegroundColor Red }
                } else { Write-Host '  MalwareBazaar: no key set.' -ForegroundColor DarkGray }
                if ($k = Get-VtKey) {
                    $v = Invoke-VtLookup $eicar $k
                    switch ($v.Status) {
                        'Found'  { Write-Host "  VirusTotal key works (test file flagged by $($v.Malicious) of $($v.Total) engines)." -ForegroundColor Green }
                        'BadKey' { Write-Host '  VirusTotal rejected the key.' -ForegroundColor Red }
                        'Quota'  { Write-Host '  VirusTotal key works, but the quota is used up for now.' -ForegroundColor Yellow }
                        default  { Write-Host "  VirusTotal lookup failed: $($v.Message)" -ForegroundColor Red }
                    }
                } else { Write-Host '  VirusTotal: no key set.' -ForegroundColor DarkGray }
                Wait-Key
            }
            '7' { if (Confirm-Action 'Remove both API keys?') { Set-VtKey ''; Set-MbKey ''; $S.OnlineCheck = 'Off' } }
            '8' { $script:OnlineCache = @{}; Remove-Item -LiteralPath $script:OnlineCachePath -ErrorAction SilentlyContinue; Write-Host '  Cache cleared.' -ForegroundColor Green; Wait-Key }
            'B' { Save-Settings; $script:LastResults = $null; return }
        }
        Save-Settings
    }
}

function Show-OptionsMenu {
    while ($true) {
        Show-Banner
        Write-Host ''
        $dm = @{ Move = "Move to $($S.DuplicateFolder)"; Report = 'Only report'; Off = 'Off' }
        Write-MenuItem '1'  'Sort non-originals into category folders' 'White' (Get-OnOff $S.SortByCategory)
        Write-MenuItem '2'  'Move save files / patches along with their ROM' 'White' (Get-OnOff $S.MoveCompanions)
        Write-MenuItem '3'  'Keep a disc game''s own folder name' 'White' (Get-OnOff $S.KeepGameFolders)
        Write-MenuItem '4'  'Duplicates (identical content)' 'White' $dm[$S.DuplicateMode]
        Write-MenuItem '5'  'Leave emulator/program folders alone' 'White' (Get-OnOff $S.ProtectAppFolders)
        Write-MenuItem '6'  'Remove folders that become empty' 'White' (Get-OnOff $S.CleanEmptyFolders)
        Write-MenuItem '7'  'Use folder names to detect the console' 'White' (Get-OnOff $S.UseFolderHints)
        Write-MenuItem '8'  'Strict: originals with bad internal checksum move' 'White' (Get-OnOff $S.Strict)
        Write-MenuItem '9'  'Move SNES Satellaview / Sufami Turbo releases' 'White' (Get-OnOff $S.MoveBSandST)
        Write-MenuItem '10' 'Max file size to hash (bigger = slower)' 'White' "$($S.HashLimitMB) MB"
        Write-MenuItem '11' 'Folder names (non-original / quarantine / duplicates)' 'White' "$($S.NonOriginalFolder) / $($S.QuarantineFolder) / $($S.DuplicateFolder)"
        Write-MenuItem '12' 'Limit scan to one console' 'White' $S.Console
        Write-MenuItem '13' 'Not-valid files go to a separate top folder' 'White' $(if ($S.RejectsOutside) { "ON - $($S.RejectFolder)\<console>" } else { "off - <console>\$($S.NonOriginalFolder)" })
        Write-MenuItem '14' 'Reuse unchanged local checks (SHA-256 revalidated)' 'White' (Get-OnOff $S.ResumeScans)
        Write-MenuItem '15' 'Archive resource limits' 'White' "$($S.ArchiveMaxMB) MB / $($S.ArchiveMaxEntries) entries / depth $($S.ArchiveMaxDepth) / $($S.ArchiveTimeoutSeconds)s"
        Write-MenuItem 'R'  'Reset all options to defaults (keeps folder and keys)'
        Write-MenuItem 'B'  'Back'
        $c = Read-Choice 'Toggle option' (@('B', 'R') + (1..15 | ForEach-Object { [string]$_ }))
        switch ($c) {
            '1'  { $S.SortByCategory = -not $S.SortByCategory }
            '2'  { $S.MoveCompanions = -not $S.MoveCompanions }
            '3'  { $S.KeepGameFolders = -not $S.KeepGameFolders }
            '4'  { $S.DuplicateMode = @{ Move = 'Report'; Report = 'Off'; Off = 'Move' }[$S.DuplicateMode] }
            '5'  {
                if ($S.ProtectAppFolders) { Write-Host '  Turning this off can break installed emulators and extracted PC games!' -ForegroundColor Red; if (Confirm-Action 'Turn off?') { $S.ProtectAppFolders = $false } }
                else { $S.ProtectAppFolders = $true }
            }
            '6'  { $S.CleanEmptyFolders = -not $S.CleanEmptyFolders }
            '7'  { $S.UseFolderHints = -not $S.UseFolderHints }
            '8'  { $S.Strict = -not $S.Strict }
            '9'  { $S.MoveBSandST = -not $S.MoveBSandST }
            '10' { $S.HashLimitMB = Read-Number 'Max MB to hash per file' 64 65536 $S.HashLimitMB }
            '11' {
                foreach ($n in 'NonOriginalFolder', 'QuarantineFolder', 'DuplicateFolder') {
                    $v = ([string](Read-Host "  $n [$($S.$n)]")).Trim()
                    if ($v -and $v -notmatch '[\\/:*?"<>|]') { $S.$n = $v } elseif ($v) { Write-Host '  Invalid characters, kept the old name.' -ForegroundColor Red }
                }
            }
            '12' { Select-ConsoleMenu }
            '13' { $S.RejectsOutside = -not $S.RejectsOutside }
            '14' { $S.ResumeScans = -not $S.ResumeScans }
            '15' {
                $S.ArchiveMaxMB = Read-Number 'Maximum extracted MB across this unpack run' 1 1048576 $S.ArchiveMaxMB
                $S.ArchiveMaxEntries = Read-Number 'Maximum cumulative archive entries' 1 1000000 $S.ArchiveMaxEntries
                $S.ArchiveMaxDepth = Read-Number 'Nested archive levels (0 = outer archives only)' 0 32 $S.ArchiveMaxDepth
                $S.ArchiveTimeoutSeconds = Read-Number 'Maximum seconds per archive extraction/listing' 1 86400 $S.ArchiveTimeoutSeconds
            }
            'R'  {
                if (Confirm-Action 'Reset options?') {
                    $d = Get-DefaultSettings
                    foreach ($k in @($d.Keys)) { if ($k -notin 'RootFolder', 'VtKeyEnc', 'MbKeyEnc', 'DatFolder', 'Emulators', 'SetupDone') { $S[$k] = $d[$k] } }
                }
            }
            'B'  { Save-Settings; $script:LastResults = $null; return }
        }
        Save-Settings
    }
}

function Update-Plan($Results) {
    foreach ($r in $Results) { $c = Get-Con $r.Console; if ($c) { $r.Emulator = Get-Emulator $c } }
    Set-Targets $Results
}

function Show-ReviewMenu($Results) {
    $list = @($Results | Where-Object { $_.Category -notin 'Original', 'Not_A_ROM', 'Protected', 'Companion', 'Other_Console', 'Kept' -and -not $_.Lead } |
        Sort-Object @{ E = { if ($_.Security -ne 'Clean') { 0 } else { 1 } } }, Category, FileName)
    if (-not $list.Count) { Write-Host '  Nothing to review - all files are original or left alone.' -ForegroundColor Green; return }
    $i = 0; $changed = $false
    while ($i -lt $list.Count) {
        $r = $list[$i]
        Show-Banner
        Write-Host "  Review $($i + 1) of $($list.Count)" -ForegroundColor Cyan
        Show-FileDetails $r
        Write-Host ''
        Write-MenuItem 'Enter' 'Accept the suggestion and go to the next file'
        Write-MenuItem 'K' 'Keep this file where it is'
        Write-MenuItem 'O' 'It is fine - treat as original (sorts with the good ROMs)'
        Write-MenuItem 'Q' 'Quarantine it'
        Write-MenuItem 'F' 'Open its folder'
        if ($r.SHA256) { Write-MenuItem 'V' 'Open VirusTotal page in browser' }
        Write-MenuItem 'P' 'Previous file'
        Write-MenuItem 'X' 'Stop reviewing'
        $c = ([string](Read-Host '  Choice')).Trim().ToUpper()
        switch ($c) {
            ''  { $i++ }
            'K' { $r.Category = 'Kept'; $r.Reason = "Kept in place by you (was: $($r.Reason))"; $changed = $true; $i++ }
            'O' {
                if ($r.Security -ne 'Clean' -and -not (Confirm-Action 'This file has a SECURITY WARNING. Really treat it as a normal ROM?')) { continue }
                $r.Category = 'Original'; $r.Security = 'Clean'; $r.Reason = "Marked as OK by you (was: $($r.Reason))"; $changed = $true; $i++
            }
            'Q' { $r.Category = 'Quarantine'; $r.Reason = "Quarantined by you (was: $($r.Reason))"; $changed = $true; $i++ }
            'F' { Open-LocalItem $r.FullName -SelectFile }
            'V' { if ($r.SHA256) { Open-LocalItem (Get-VtLink $r.SHA256) } }
            'P' { if ($i -gt 0) { $i-- } }
            'X' { break }
        }
        if ($c -eq 'X') { break }
    }
    if ($changed) { Update-Plan $Results; Write-Host '  Your choices are applied to the plan (nothing moved yet).' -ForegroundColor Green }
}

function Select-CategoriesToMove($Results) {
    $cats = @($Results | Where-Object Target | Group-Object Category | Sort-Object Name)
    if (-not $cats.Count) { Write-Host '  Nothing to move.' -ForegroundColor Yellow; return }
    Write-Host ''
    Write-Host '  Choose which groups to move now. The others stay where they are for this run.' -ForegroundColor Cyan
    for ($i = 0; $i -lt $cats.Count; $i++) {
        $lbl = if ($script:CatInfo[$cats[$i].Name]) { $script:CatInfo[$cats[$i].Name].Label } else { $cats[$i].Name }
        Write-MenuItem ([string]($i + 1)) ('{0,-50} {1,6} file(s)' -f $lbl, $cats[$i].Count)
    }
    $v = ([string](Read-Host '  Numbers to KEEP moving, e.g. 1,3 (Enter = all)')).Trim()
    if (-not $v) { return }
    $keep = @($v -split '[,; ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $cats.Count })
    for ($i = 0; $i -lt $cats.Count; $i++) {
        if ($keep -contains $i) { continue }
        foreach ($r in $cats[$i].Group) { $r.Target = ''; $r.Action = 'Stays (not selected)' }
    }
    # a set moves as a whole or not at all
    foreach ($r in @($Results | Where-Object Target)) {
        $top = Get-Top $r
        $unit = @($Results | Where-Object { (Get-Top $_) -eq $top })
        if (@($unit | Where-Object { -not $_.Target -and $_.Action -like 'Stays (not selected)' }).Count) { foreach ($u in $unit) { $u.Target = ''; $u.Action = 'Stays (not selected)' } }
    }
    Write-Host "  $(@($Results | Where-Object Target).Count) file(s) will be moved." -ForegroundColor Green
}

function Test-CurrentInventory($Results) {
    $known = New-PathMap
    foreach ($r in $Results) { $known[$r.FullName] = $true }
    $current = @(Get-ScanFiles)
    if ($script:ScanErrors.Count) {
        Write-Warning 'Cannot confirm the whole library inventory: some folders/files could not be read. Refresh the check after resolving the reported access/link errors.'
        return $false
    }
    $added = @($current | Where-Object { -not $known.ContainsKey([RomSorter.RomTools]::Plain($_.File.FullName)) })
    if ($added.Count -or $current.Count -ne $known.Count) {
        Write-Warning "Library contents changed since this check ($($added.Count) added file(s), or removed files). Run Full workflow to unpack, check and sort the current library."
        return $false
    }
    return $true
}
function Test-SortResults($Results) {
    if (-not (Test-CurrentInventory $Results)) { $script:LastResults = $null; return $false }
    $changed = @(
        foreach ($r in $Results) {
            if (-not $r.Target) { continue }
            $f = [IO.FileInfo]::new((LongP $r.FullName))
            if (-not $f.Exists -or $f.Length -ne $r.Length -or $f.LastWriteTimeUtc -ne $r.LastWriteUtc -or
                ($r.ScanFingerprint -and (Get-Sha256 $r.FullName) -ine $r.ScanFingerprint)) { $r.FileName }
        }
    )
    if ($changed.Count) {
        Write-Host "  Sorting stopped: $($changed.Count) file(s) changed or disappeared since the check." -ForegroundColor Red
        $changed | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        Write-Host '  Run Check files or Check + sort again before moving them.' -ForegroundColor Yellow
        $script:LastResults = $null
        return $false
    }
    return $true
}

function Show-ResultsMenu($Results) {
    while ($true) {
        Write-Host ''
        Write-Host '  RESULTS - review, report, or apply the move plan' -ForegroundColor Cyan
        $n = if ($S.CheckOnly) { 0 } else { @($Results | Where-Object Target).Count }
        $flag = @($Results | Where-Object { $_.Category -notin 'Original', 'Not_A_ROM', 'Protected', 'Companion', 'Other_Console', 'Kept' -and -not $_.Lead }).Count
        if ($S.CheckOnly) { Write-Host '  Check only: no files have been moved.' -ForegroundColor Gray }
        else {
            Write-Host "  Preview only: $n file(s) planned. Nothing moves until you choose Apply." -ForegroundColor Gray
            Write-Host "  Layout: $(Get-LayoutText)" -ForegroundColor Gray
        }
        Write-Host ''
        Write-Host '  MOVE PLAN' -ForegroundColor White
        if ($n) { Write-MenuItem 'A' "Apply: move $n file(s) now" 'Green' }
        if (-not $S.CheckOnly) { Write-MenuItem 'T' 'Preview the new folder tree' }
        if ($n) { Write-MenuItem 'C' 'Choose which groups to move' }
        if ($S.CheckOnly) { Write-MenuItem 'M' 'Sort these files (preview first; no new scan)' }
        Write-Host ''
        Write-Host '  INSPECT AND REPORT' -ForegroundColor White
        if ($flag) { Write-MenuItem 'R' "Review the $flag flagged file(s) one by one (keep / OK / quarantine)" }
        Write-MenuItem 'W' 'Why? Show the reason for every flagged file'
        Write-MenuItem 'E' 'Explain one file (search by name)'
        Write-MenuItem 'S' 'Summary again'
        Write-MenuItem 'D' 'Table of all files'
        if (Get-Command Out-GridView -ErrorAction SilentlyContinue) { Write-MenuItem 'G' 'Sortable / filterable window' }
        Write-MenuItem 'H' 'Open HTML report (reasons, sources, VirusTotal links)'
        Write-Host ''
        Write-MenuItem 'B' 'Back to main menu'
        $valid = @('W', 'E', 'S', 'D', 'H', 'B')
        if ($S.CheckOnly) { $valid += 'M' } else { $valid += 'T' }
        if (Get-Command Out-GridView -ErrorAction SilentlyContinue) { $valid += 'G' }
        if ($n) { $valid += 'A', 'C' }; if ($flag) { $valid += 'R' }
        switch (Read-Choice 'Choice' $valid) {
            'A' {
                $q = @($Results | Where-Object { $_.Category -eq 'Quarantine' -and $_.Target }).Count
                if ($q) { Write-Host "  $q possibly malicious file(s) will go to $($S.QuarantineFolder). Do NOT run them." -ForegroundColor Red }
                Write-Host '  Every move is logged right away, so you can always undo (main menu > 7), even after a crash.' -ForegroundColor DarkGray
                if (Confirm-Action "Move $n file(s)?") {
                    if (-not (Test-SortResults $Results)) { Wait-Key; return }
                    Invoke-Organize $Results; [void](Export-Report $Results 'Applied'); $script:LastResults = $null; Wait-Key; return
                }
            }
            'M' {
                if ($S.CheckOnly) {
                    Write-Wrapped "Sorting uses: $(Get-LayoutText). File names never change and every move can be undone. Change the layout in Settings > Sort layout." 2 'Gray'
                    if (Confirm-Action 'Turn on sorting?') { $S.CheckOnly = $false; Save-Settings; Update-Plan $Results; Show-Banner; Show-Summary $Results }
                }
            }
            'T' { if (-not $S.CheckOnly) { Show-Tree $Results } }
            'R' { Show-ReviewMenu $Results; Show-Banner; Show-Summary $Results }
            'C' { Select-CategoriesToMove $Results }
            'W' {
                $danger = @($Results | Where-Object { $_.Security -notin 'Clean', 'Not checked' -and $_.Category -ne 'Protected' })
                if ($danger.Count) { Write-Host ''; Write-Host '  SECURITY WARNINGS' -ForegroundColor Red; foreach ($d in $danger) { Show-SecurityItem $d } }
                Show-Reasons $Results 100000
            }
            'E' {
                $q = ([string](Read-Host '  Part of the file name')).Trim()
                $hits = @($Results | Where-Object { $q -and $_.FileName -like "*$q*" })
                if (-not $hits.Count) { Write-Host '  No file matches.' -ForegroundColor Yellow }
                elseif ($hits.Count -eq 1) { Show-FileDetails $hits[0] }
                else { $h = Select-FromList 'Which file' $hits { param($x) "$($x.FileName)  [$($x.Console)]  $($x.Folder)" } -AllowBack; if ($h) { Show-FileDetails $h } }
            }
            'S' { Show-Banner; Show-Summary $Results }
            'D' {
                $Results | Where-Object { $_.Category -ne 'Not_A_ROM' } |
                    Format-Table @{ n = 'File'; e = { $_.FileName } }, Console, Category, Authenticity, IntegrityStatus, AntivirusStatus, MalwareStatus, Action -AutoSize | Out-Host
            }
            'G' {
                $Results | Select-Object FileName, Folder, Console, Emulator, Category, Reason, Authenticity, IntegrityStatus, AntivirusStatus, AntivirusCheckedUtc, CheckedUtc, MalwareStatus, DatStrength, Security, Threats, Detected, Header, Integrity, DatMatch, HashMatch, Year, Publisher, Libraries, Sources, Online, DupOf,
                    @{ n = 'VirusTotalLink'; e = { Get-VtLink $_.SHA256 } }, Action, Target, Notes | Out-GridView -Title 'ROM Sorter results'
            }
            'H' { $p = Export-Report $Results; Open-LocalItem $p }
            'B' { return }
        }
    }
}

function Show-UndoMenu {
    Show-Banner
    $logs = @(Get-UndoLogs)
    Write-Host ''
    if (-not $logs.Count) { Write-Host "  No runs to undo in $(Get-WorkDir)." -ForegroundColor Yellow; Wait-Key; return }
    for ($i = 0; $i -lt $logs.Count; $i++) {
        $cnt = @(Import-Csv -LiteralPath $logs[$i].FullName | Where-Object { $_.Action -in 'Moved','Extracted','PlannedMove','PlannedExtraction' } | Select-Object OriginalPath,CurrentPath -Unique).Count
        Write-MenuItem ([string]($i + 1)) ('{0,-40} {1,6} {2}   {3}' -f $logs[$i].Name, $cnt, $(if ($logs[$i].Name -like '*unpack*') { 'unpacked file(s)' } else { 'moved file(s)   ' }), $logs[$i].LastWriteTime)
    }
    Write-Host '  Undo the newest run first if you made several.' -ForegroundColor DarkGray
    Write-MenuItem 'B' 'Back'
    $c = Read-Choice 'Undo which run' (@('B') + (1..$logs.Count | ForEach-Object { [string]$_ }))
    if ($c -eq 'B') { return }
    $log = $logs[[int]$c - 1]
    Invoke-UndoLog $log $false
    if (Confirm-Action 'Move these files back?') { Invoke-UndoLog $log $true }
    $script:LastResults = $null
    Wait-Key
}

function Start-SetupWizard {
    Show-Banner
    Write-Host ''
    Write-Host '  WELCOME - quick setup (you can change everything later)' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Step 1/5 - ROM folder' -ForegroundColor White
    Write-Host "  Current: $($S.RootFolder)" -ForegroundColor Yellow
    if (-not (Confirm-Action 'Is this the top folder of your ROMs?')) { Select-RootFolder }
    Show-Banner; Write-Host ''
    Write-Host '  Step 2/5 - Preferred sorting layout' -ForegroundColor White
    Write-Wrapped 'Choose a layout now, then choose an action from the main menu. Setup does not scan, unpack, or move files.' 2 'Gray'
    Write-MenuItem '1' 'Per console - good games together, other files separate'
    Write-MenuItem '2' 'By validity - Verified / Modified / Non-Retail / Unverified / Invalid'
    Write-MenuItem '3' 'Keep the current layout'
    switch (Read-Choice 'Choice' @('1', '2', '3')) {
        '1' { $S.Layout = 'ByConsole' }
        '2' { $S.Layout = 'Validity' }
    }
    $S.CheckOnly = $true; $script:LastResults = $null
    Show-Banner; Write-Host ''
    Write-Host '  Step 3/5 - Verification' -ForegroundColor White
    Write-Wrapped 'Check every ROM against online game libraries (No-Intro, Redump, libretro release info, Hasheous with IGDB / TheGamesDB / RetroAchievements)? This proves which files are real released games and finds demos, betas, homebrew and hacks. Only checksums are sent.' 2 'Gray'
    if (Confirm-Action 'Use online game libraries, including unknown-file hash identification (recommended)?') { $S.AutoDat = $true; $S.Hasheous = 'All'; $S.IdentifyUnknown = $true } else { $S.AutoDat = $false; $S.Hasheous = 'Off'; $S.IdentifyUnknown = $false }
    $S.RetailOnly = Confirm-Action 'Only count confirmed released games as OK (no demos, homebrew or unknown files)?'
    Write-Host ''
    Write-Host '  Step 4/5 - Malware check' -ForegroundColor White
    Write-Wrapped "Check actions use local checks and, when enabled and available, $script:AntivirusName. Optionally add free MalwareBazaar and/or VirusTotal keys." 2 'Gray'
    if (Confirm-Action 'Set up online malware keys now?') { Show-OnlineMenu }
    Show-Banner; Write-Host ''
    Write-Host '  Step 5/5 - Safety' -ForegroundColor White
    Write-Wrapped 'Check files only produces results and reports. Sort only and Check + sort require Apply after a preview. Full workflow and Unpack only ask for confirmation before changing files. File names are never changed, existing files are never overwritten, emulator/program folders are left alone, and every move can be undone.' 2 'Gray'
    $S.SetupDone = $true; Save-Settings
    Wait-Key
}

function Show-SettingsMenu {
    while ($true) {
        Show-Banner
        Show-Status
        Write-Host '  SETTINGS - configuration only; no files are moved' -ForegroundColor Cyan
        Write-MenuItem '1' 'ROM folder'
        Write-MenuItem '2' 'Sort layout (including validity)' 'White' $S.Layout
        Write-MenuItem '3' 'Verification sources and release policy'
        Write-MenuItem '4' 'Security and online malware services'
        Write-MenuItem '5' 'File handling, duplicates, and other options'
        Write-MenuItem '6' 'Console filter (All = automatic detection)' 'White' $S.Console
        Write-MenuItem 'W' 'Run setup wizard again'
        Write-MenuItem 'B' 'Back to main menu'
        switch (Read-Choice 'Choice' @('1', '2', '3', '4', '5', '6', 'W', 'B')) {
            '1' { Select-RootFolder }
            '2' { Show-LayoutMenu }
            '3' { Show-VerifyMenu }
            '4' { Show-OnlineMenu }
            '5' { Show-OptionsMenu }
            '6' { Select-ConsoleMenu }
            'W' { Start-SetupWizard }
            'B' { return }
        }
    }
}

function Get-SortInventory { Invoke-ProgressTask 'Sort inventory' { Get-SortInventoryCore } }
function Get-SortInventoryCore {
    $entries = @(Get-ScanFiles)
    $results = New-Object 'Collections.Generic.List[object]'
    # Descriptor folders are kept intact: inventory-only sorting must not split disc sets.
    $setFolders = New-PathMap
    $inventoryDone = 0
    foreach ($e in $entries) {
        if ($script:SetDescExt -contains $e.File.Extension.ToLower()) {
            $setFolders[[RomSorter.RomTools]::Plain($e.File.DirectoryName)] = $true
        }
    }
    foreach ($e in $entries) {
        Update-RomProgress -Phase 'Building sort-only inventory' -Done $inventoryDone -Total $entries.Count -Current $e.File.FullName -Detail 'No antivirus, hashes or content checks'
        $inventoryDone++
        $f = $e.File; $r = New-Result $f
        $r | Add-Member -NotePropertyName SortOnly -NotePropertyValue $true
        $r.Security = 'Not checked'
        $ext = $f.Extension.ToLower()
        $stem = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        $r.Reason = 'Sort-only inventory: no content, hash, library or malware checks were performed.'
        if ($e.Prot -or $setFolders.ContainsKey($r.Folder)) {
            $r.Category = 'Protected'; $r.Reason += ' Folder left intact to protect an application or disc set.'
        } elseif ($script:DangerExt -contains $ext) {
            $r.Category = 'Executable'; $r.Reason += ' Program/script left in place.'
        } elseif ($script:ArchiveExt -contains $ext -or $ext -eq '.zi') {
            $r.Category = 'Archive'; $r.Reason += ' Archive left packed and in place.'
        } elseif (($bios = Get-BiosIdentity $f)) {
            Set-BiosIdentity $r $bios
        } else {
            $candidates = @()
            if ($script:ExtMap.ContainsKey($ext)) { $candidates = @($script:ExtMap[$ext]) }
            $hint = Get-FolderHint $f
            $con = $null
            if ($candidates.Count -eq 1 -and $script:SharedExt -notcontains $ext) { $con = $candidates[0] }
            elseif ($hint -and @($candidates | Where-Object Key -eq $hint.Key).Count) { $con = $hint }
            if ($con) {
                $r.Console = $con.Key; $r.ConsoleFolder = $con.Folder; $r.Emulator = Get-Emulator $con
                $r.Category = 'Unknown_Check_Manually'
                $r.Reason += ' Console inferred from extension/folder only; validity is unknown.'
                if ($S.Console -ne 'All' -and $con.Key -ne $S.Console) { $r.Category = 'Other_Console' }
            } else { $r.Reason += ' Unknown or ambiguous file type left in place.' }
        }
        $results.Add($r)
    }
    # Reuse companion grouping without treating the inventory as a security scan.
    foreach ($r in $results) { $r.Security = 'Clean' }
    Join-Companions $results
    foreach ($r in $results) { $r.Security = 'Not checked' }
    Set-ProgressCounter 'Inventoried' $results.Count; Set-ProgressCounter 'Warnings' $script:ScanErrors.Count
    if ($script:ScanErrors.Count) {
        Write-Host '  Some folders could not be inventoried or were skipped:' -ForegroundColor Yellow
        $script:ScanErrors | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    }
    $results.ToArray()
}

function Show-SortMenu([string]$Layout) {
    if (-not $script:LastResults) { $script:LastResults = Restore-CompletedScan }
    if ($Layout) { $S.Layout = $Layout; Save-Settings }
    :sortMenu while ($true) {
        Show-Banner
        Write-Host ''
        $title = switch ($S.Layout) {
            'Validity' { 'SORT BY VALIDITY - Verified / Modified / Non-Retail / Unverified / Invalid' }
            'ByConsole' { 'SORT BY CONSOLE - one folder per console' }
            default { "SORT ROMS - $($S.Layout) layout" }
        }
        Write-Host "  $title" -ForegroundColor Cyan
        Write-Host "  Layout: $(Get-LayoutText)" -ForegroundColor Yellow
        if (-not $script:LastResults) {
            Write-Wrapped 'No previous check is available. Sort without checking uses extensions and folder names only: no antivirus, content validation, hashes, online lookups or extraction. Unknown validity goes to Unverified; ambiguous files, archives, programs and disc-set folders stay in place. Nothing moves before Apply.' 2 'Yellow'
            Write-MenuItem '1' 'Sort without checking - build a move preview' 'Green'
            Write-MenuItem 'L' 'Change sort layout first'
            Write-MenuItem 'B' 'Back - do not check or move anything'
            switch (Read-Choice 'Choice' @('1', 'L', 'B')) {
                '1' {
                    $S.CheckOnly = $false
                    $script:LastResults = @(Get-SortInventory)
                    if (-not $script:LastResults.Count) { $script:LastResults = $null; Write-Host '  No files to sort.' -ForegroundColor Yellow; Wait-Key; return }
                    Update-Plan $script:LastResults
                    Show-Tree $script:LastResults
                    Show-ResultsMenu $script:LastResults
                }
                'L' { Show-LayoutMenu; continue sortMenu }
                'B' { return }
            }
            return
        }
        Write-Host "  $(@($script:LastResults).Count) file record(s) available; no new checks will run." -ForegroundColor Gray
        Write-MenuItem '1' 'Preview and apply sorting' 'Green'
        Write-MenuItem 'L' 'Change sort layout (console / validity / emulator / frontend)'
        Write-MenuItem 'B' 'Back - do not move anything'
        switch (Read-Choice 'Choice' @('1', 'L', 'B')) {
            '1' {
                $S.CheckOnly = $false
                Update-Plan $script:LastResults
                if (-not (Test-SortResults $script:LastResults)) { Wait-Key; return }
                Show-Summary $script:LastResults
                Show-Tree $script:LastResults
                Show-ResultsMenu $script:LastResults
                return
            }
            'L' { Show-LayoutMenu }
            'B' { return }
        }
    }
}

function Invoke-CheckAction([switch]$PlanSort) {
    $S.CheckOnly = -not [bool]$PlanSort
    Show-Banner; Write-Host ''
    Write-Host '  Checking every file. No archives are unpacked and no files are moved.' -ForegroundColor Cyan
    Write-Host '  Press Ctrl+C to abort the check.' -ForegroundColor DarkGray
    $script:LastResults = $null
    $script:LastResults = @(Invoke-Scan)
    if (-not $script:LastResults.Count) { $script:LastResults = $null; Wait-Key; return }
    Show-Summary $script:LastResults
    [void](Export-Report $script:LastResults)
    if ($PlanSort) { Show-Tree $script:LastResults }
    Show-ResultsMenu $script:LastResults
}

function Start-Menu {
    if (-not $S.SetupDone) { Start-SetupWizard }
    while ($true) {
        Show-Banner
        Show-Status
        Write-Host '  CHECK' -ForegroundColor Cyan
        Write-MenuItem '1' 'Check files' 'Green' 'Verification + configured malware checks; no moves'
        Write-Host ''
        Write-Host '  SORT - direct actions; preview before moving' -ForegroundColor Cyan
        Write-MenuItem '2' 'SORT BY VALIDITY' 'Green' 'Verified / Modified / Non-Retail / Unverified / Invalid'
        Write-MenuItem '3' 'Sort by console' 'White' 'One folder per console'
        Write-MenuItem '4' 'Sort by another layout' 'White' 'Emulator / frontend / RetroArch / Classic'
        Write-Host '      Sort only: no antivirus, verification or online checks. Preview, then Apply.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  WORKFLOWS AND ARCHIVES' -ForegroundColor Cyan
        Write-MenuItem '5' 'Fresh check + sort' 'White' "Current layout: $($S.Layout); preview, then Apply"
        Write-MenuItem '6' 'Full workflow: unpack + check + sort' 'White' "Includes new files in all subfolders; layout: $($S.Layout)"
        Write-MenuItem '8' 'Unpack archives only' 'White' 'Safety checks + extraction; no sorting'
        Write-MenuItem 'C' 'Cleanup processed archives' 'Yellow' 'Verify extracted copies, preview space, confirm permanent deletion'
        Write-Host ''
        Write-Host '  RESULTS AND RECOVERY' -ForegroundColor Cyan
        Write-MenuItem '9' 'Review results / reasons / export reports' 'White' $(if ($script:LastResults) { 'Available' } else { 'Run a check first' })
        Write-MenuItem '7' 'Undo a previous run'
        Write-Host ''
        Write-Host '  CONFIGURATION' -ForegroundColor Cyan
        Write-MenuItem 'S' 'Settings (folder, layout, verification, security)'
        Write-MenuItem 'Q' 'Quit'
        Write-Host ''
        Write-Host '  Options 2, 3 and 4 start sorting workflows. File names stay unchanged.' -ForegroundColor DarkGray
        switch (Read-Choice 'Choice' @('1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', 'S', 'Q')) {
            '1' { Invoke-CheckAction }
            '2' { Show-SortMenu -Layout 'Validity' }
            '3' { Show-SortMenu -Layout 'ByConsole' }
            '4' { Show-LayoutMenu -RunSort }
            '5' { Invoke-CheckAction -PlanSort }
            '6' { Invoke-DoEverything; Wait-Key }
            '8' {
                Show-Banner; Write-Host ''
                Write-Wrapped "Every archive is checked for malware first; safe ones are unpacked next to the archive (names unchanged) and the original archive is kept in $($S.UnpackedFolder)\. Can be undone (menu 7)." 2 'Gray'
                if (Confirm-Action 'Unpack all archives now?') { $script:LastResults = $null; Invoke-Unpack }
                Wait-Key
            }
            '9' {
                if ($script:LastResults) {
                    Update-Plan $script:LastResults
                    Show-Summary $script:LastResults
                    Show-ResultsMenu $script:LastResults
                } else {
                    Write-Host '  No results in this session. Run Check files first.' -ForegroundColor Yellow
                    Wait-Key
                }
            }
            '7' { Show-UndoMenu }
            'C' { Show-ArchiveCleanupMenu }
            'S' { Show-SettingsMenu }
            'Q' { return }
        }
    }
}

# ===================================================================== START
if ($DefinitionsOnly) { return }
$S = Read-Settings
if ($RootFolder) { $S.RootFolder = $RootFolder }
if (-not (Test-Path -LiteralPath $S.RootFolder -PathType Container)) { throw "Folder not found: $($S.RootFolder)" }
$S.RootFolder = (Resolve-Path -LiteralPath $S.RootFolder).Path
if ($PSBoundParameters.ContainsKey('Console')) {
    $match = Get-Con $Console
    if ($Console -eq 'All') { $S.Console = 'All' } elseif ($match) { $S.Console = $match.Key }
    else { throw "Unknown console '$Console'. Use one of: All, $(($script:Consoles | ForEach-Object Key) -join ', ')" }
}
if ($PSBoundParameters.ContainsKey('DatFolder'))      { $S.DatFolder = $DatFolder }
if ($PSBoundParameters.ContainsKey('Layout'))         { $S.Layout = $Layout; $S.CheckOnly = $false }
if ($Apply -and -not $Undo)                          { $S.CheckOnly = $false }
if ($PSBoundParameters.ContainsKey('SortByCategory')) { $S.SortByCategory = [bool]$SortByCategory }
if ($PSBoundParameters.ContainsKey('DefenderScan'))   { $S.DefenderScan = [bool]$DefenderScan }
if ($PSBoundParameters.ContainsKey('Strict'))         { $S.Strict = [bool]$Strict }
if ($PSBoundParameters.ContainsKey('RetailOnly'))     { $S.RetailOnly = [bool]$RetailOnly }
if ($PSBoundParameters.ContainsKey('MoveBSandST'))    { $S.MoveBSandST = [bool]$MoveBSandST }
if ($PSBoundParameters.ContainsKey('AutoDat'))        { $S.AutoDat = [bool]$AutoDat }
if ($PSBoundParameters.ContainsKey('Hasheous'))       { $S.Hasheous = $Hasheous }
if ($VirusTotalKey)    { Set-VtKey $VirusTotalKey.Trim() }
if ($MalwareBazaarKey) { Set-MbKey $MalwareBazaarKey.Trim() }
if ($PSBoundParameters.ContainsKey('OnlineCheck'))    { $S.OnlineCheck = $OnlineCheck }
if ($VirusTotalKey -or $MalwareBazaarKey) { Save-Settings }

$interactive = -not ($NoMenu -or $Apply -or $Undo -or $ListRemaining -or $DoEverything -or $Unpack)
if ($interactive) { Start-Menu; return }
if ($DoEverything) { Invoke-DoEverything -NoConfirm; return }

if ($Undo) {
    $logs = @(Get-UndoLogs)
    if (-not $logs.Count) { Write-Host 'No runs to undo.' -ForegroundColor Yellow; return }
    Write-Host "Undo: $($logs[0].FullName)" -ForegroundColor Cyan
    Invoke-UndoLog $logs[0] ([bool]$Apply)
    if (-not $Apply) { Write-Host 'Dry run - add -Apply to restore.' -ForegroundColor Yellow }
    return
}

if ($Unpack) { Invoke-Unpack }
$results = @(Invoke-Scan)
if (-not $results.Count) { return }
Show-Summary $results
if ($Apply -and -not $ListRemaining) { Invoke-Organize $results; [void](Export-Report $results 'Applied') }
else {
    [void](Export-Report $results $(if ($ListRemaining) { 'Remaining' } else { 'Preview' }))
    Write-Host $(if ($S.CheckOnly) { '  CHECK ONLY - nothing was moved. To also sort the files, run with -Apply (per console), or use the menu.' } else { '  PREVIEW - nothing was moved. Run again with -Apply, or start without parameters for the menu.' }) -ForegroundColor Yellow
}
