#ifndef UI_KEYBOARD_H
#define UI_KEYBOARD_H

// Kept for backward compatibility (scraper/musicplayer call it); no-op.
void UIKeyboard_init(void);

// Show the modal in-process on-screen keyboard, blocking until the user
// confirms or cancels. Returns a malloc'd string with the input, or NULL
// if cancelled or empty. Caller must free() the result.
// `prompt` is rendered as the title above the input line.
char* UIKeyboard_open(const char* prompt);

#endif // UI_KEYBOARD_H
