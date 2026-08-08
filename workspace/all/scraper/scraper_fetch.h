#ifndef SCRAPER_FETCH_H
#define SCRAPER_FETCH_H

// Headless single-ROM fetch. Parses --fetch/--out/--system/--status from argv,
// scrapes one ROM with no GFX, writes the status file, returns the process
// exit code (0 done, 1 error, 2 not-found/usage).
int run_headless_fetch(int argc, char* argv[]);

#endif // SCRAPER_FETCH_H
