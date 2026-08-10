#ifndef SEARCH_H
#define SEARCH_H

#include "sdl.h"
#include <stdbool.h>

typedef struct {
	bool dirty;
	bool startgame;
	bool folderbgchanged;
	int screen;
} SearchResult;

void Search_init(void);
void Search_quit(void);

// Opens keyboard, performs search, returns true if user entered a query
bool Search_open(void);

SearchResult Search_handleInput(unsigned long now);
void Search_render(SDL_Surface* screen, int lastScreen);

// True while the results-list selection pill is mid-glide (dirty-loop hook).
bool Search_pillAnimating(void);

// Marquee driving for the results list (see GameList_scrollBusy twin).
bool Search_scrollBusy(void);
void Search_scrollTickIdle(void);

#endif // SEARCH_H
