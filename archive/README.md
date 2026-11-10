# Archive

Retired code kept for reference. Nothing here is stowed into `$HOME`, loaded by pi or run by `task test`.

- `pi-web/`: the pi extension that provided `web_search` and `web_fetch`. bb's Forage plugin provides those tools now. Its tests still pass outside bb: `cd archive/pi-web && node --import ./test/_pi-resolve.mjs --test 'test/*.test.ts'`.
