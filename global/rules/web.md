# Web research

- Search with `kagi_search_fetch`.
- Read a page with `http-fetch` (under `mcp__anvil-emacs-eval__`) and `selector="p"`. A `selector` that matches nothing returns the whole page body, so check `extract-miss` in the result.
- For a page in Chinese or another non-ASCII language, start with `kagi_extract`: it returns clean markdown in one call, and `http-fetch` returns such text as octal-escaped bytes.
- For a page that needs JavaScript or gives an empty result, use `kagi_extract` or `browser-fetch`.
- Screenshot or live-UI bugs: use `$browser-use`.
